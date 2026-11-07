-- Migration: everything a pair does together, plus the push outbox.
--
--   * push_tokens / push_prefs / push_outbox: provider-neutral push queue. The
--     database decides WHAT to tell WHOM and WHEN; the push-dispatch Edge
--     Function only delivers (APNs, FCM, WNS). Quiet hours are enforced when a
--     row is claimed, in the recipient's own time zone, so a reminder queued
--     at noon still respects 11 PM.
--   * pair_watchlist, date_nights, pair_sessions: the shared list, scheduled
--     nights, and what you watched together (history, streak, recap stats).
--
-- Patron rules (pair_is_patron = either partner is premium):
--   creating a date night and reading history older than 7 days need it;
--   receiving, accepting, rescheduling and cancelling a night never do, and
--   nothing is deleted when Patron ends. Exporting history is always allowed.

-- ---------------------------------------------------------------------------
-- 1. Pair broadcast channel: private "pair:<pair id>" (Pick tonight, presence)
-- ---------------------------------------------------------------------------
create or replace function public.pair_id_from_topic(p_topic text)
returns uuid
language plpgsql immutable
as $$
begin
  if p_topic is null or p_topic not like 'pair:%' then
    return null;
  end if;
  return substr(p_topic, 6)::uuid;
exception when others then
  return null;
end $$;

create policy "pair members can receive pair broadcasts"
  on realtime.messages for select to authenticated
  using (
    public.pair_id_from_topic(realtime.topic()) is not null
    and public.pair_id_from_topic(realtime.topic()) = (select public.my_pair_id())
  );

create policy "pair members can send pair broadcasts"
  on realtime.messages for insert to authenticated
  with check (
    public.pair_id_from_topic(realtime.topic()) is not null
    and public.pair_id_from_topic(realtime.topic()) = (select public.my_pair_id())
  );

-- ---------------------------------------------------------------------------
-- 2. Push: tokens, preferences, outbox
-- ---------------------------------------------------------------------------
create table public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  platform text not null check (platform in ('ios', 'macos', 'android', 'windows')),
  token text not null check (char_length(token) between 8 and 4096),
  -- APNs has separate sandbox and production gateways; a debug build's token is
  -- only valid on the sandbox one.
  environment text not null default 'production' check (environment in ('production', 'sandbox')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (platform, token)
);
create index idx_push_tokens_user on public.push_tokens (user_id);

create table public.push_prefs (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  calls boolean not null default true,
  date_nights boolean not null default true,
  watchlist boolean not null default false,
  reunion boolean not null default true,
  quiet_hours boolean not null default true
);

create table public.push_outbox (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  collapse_key text,
  send_after timestamptz not null default now(),
  expires_at timestamptz,
  attempts int not null default 0,
  locked_until timestamptz,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);
create index idx_push_outbox_due on public.push_outbox (send_after) where sent_at is null;
-- One unsent row per (user, collapse key): a newer reminder replaces an older one.
create unique index push_outbox_collapse
  on public.push_outbox (user_id, collapse_key)
  where sent_at is null and collapse_key is not null;

alter table public.push_tokens enable row level security;
alter table public.push_prefs enable row level security;
alter table public.push_outbox enable row level security;
revoke all on public.push_tokens, public.push_prefs, public.push_outbox from public, anon, authenticated;
-- No policies and no grants: clients reach these only through the RPCs below.

insert into public.app_settings (key, value)
values ('push', '{"enabled": true, "endpoint_url": null, "service_role_key": null}'::jsonb)
on conflict (key) do nothing;

create or replace function public.register_push_token(
  p_platform text, p_token text, p_environment text default 'production')
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'not_authenticated';
  end if;

  -- A token belongs to one device, and a device to whoever is signed in now.
  insert into public.push_tokens (user_id, platform, token, environment)
  values (v_uid, p_platform, p_token, p_environment)
  on conflict (platform, token) do update
    set user_id = v_uid, environment = excluded.environment, updated_at = now();

  -- Keep the newest ten per person; older ones are stale installs.
  delete from public.push_tokens t
  where t.user_id = v_uid
    and t.id in (
      select id from public.push_tokens
      where user_id = v_uid
      order by updated_at desc
      offset 10);
end $$;

create or replace function public.unregister_push_token(p_token text)
returns void
language sql security definer set search_path = ''
as $$
  delete from public.push_tokens where token = p_token and user_id = (select auth.uid());
$$;

create or replace function public.my_push_prefs()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'calls', coalesce(p.calls, true),
    'date_nights', coalesce(p.date_nights, true),
    'watchlist', coalesce(p.watchlist, false),
    'reunion', coalesce(p.reunion, true),
    'quiet_hours', coalesce(p.quiet_hours, true))
  from (select 1) x
  left join public.push_prefs p on p.user_id = (select auth.uid());
$$;

create or replace function public.set_push_pref(p_key text, p_value boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if p_key not in ('calls', 'date_nights', 'watchlist', 'reunion', 'quiet_hours') then
    raise exception 'invalid_pref';
  end if;
  insert into public.push_prefs (user_id) values (auth.uid()) on conflict do nothing;
  execute format('update public.push_prefs set %I = $1 where user_id = $2', p_key)
    using p_value, auth.uid();
end $$;

-- Which switch governs a kind. Pairing messages are not optional.
create or replace function public.push_kind_enabled(p_user uuid, p_kind text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select case
    when p_kind = 'call' then coalesce(p.calls, true)
    when p_kind like 'date_night%' then coalesce(p.date_nights, true)
    when p_kind = 'watchlist_add' then coalesce(p.watchlist, false)
    when p_kind = 'reunion' then coalesce(p.reunion, true)
    else true
  end
  from (select 1) x
  left join public.push_prefs p on p.user_id = p_user;
$$;
revoke execute on function public.push_kind_enabled(uuid, text) from public, anon, authenticated;

-- Send pending pushes now. The Edge Function endpoint is operator configuration
-- (app_settings 'push'); with none set this is a no-op, like invoke_r2_cleanup.
create or replace function public.invoke_push_dispatch()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_settings jsonb;
  v_endpoint text;
  v_key text;
begin
  select value into v_settings from public.app_settings where key = 'push';
  if not coalesce((v_settings ->> 'enabled')::boolean, true) then
    return;
  end if;
  v_endpoint := nullif(trim(v_settings ->> 'endpoint_url'), '');
  v_key := nullif(trim(v_settings ->> 'service_role_key'), '');
  if v_endpoint is null then
    return;
  end if;
  perform net.http_post(
    url := v_endpoint,
    headers := case when v_key is not null
      then jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key)
      else jsonb_build_object('Content-Type', 'application/json') end,
    body := '{}'::jsonb);
exception when others then
  raise warning 'invoke_push_dispatch failed: %', sqlerrm;
end $$;
revoke execute on function public.invoke_push_dispatch() from public, anon, authenticated;
grant execute on function public.invoke_push_dispatch() to service_role;

create or replace function public.enqueue_push(
  p_user uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb,
  p_send_after timestamptz default now(),
  p_expires_at timestamptz default null,
  p_collapse text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_user is null or not public.push_kind_enabled(p_user, p_kind) then
    return;
  end if;
  -- Nothing to deliver to: do not queue what no device can receive.
  if not exists (select 1 from public.push_tokens where user_id = p_user) then
    return;
  end if;

  insert into public.push_outbox (user_id, kind, title, body, data, send_after, expires_at, collapse_key)
  values (p_user, p_kind, p_title, p_body, p_data, p_send_after, p_expires_at, p_collapse)
  on conflict (user_id, collapse_key) where sent_at is null and collapse_key is not null
  do update set
    title = excluded.title, body = excluded.body, data = excluded.data,
    send_after = excluded.send_after, expires_at = excluded.expires_at,
    attempts = 0, locked_until = null;

  if p_send_after <= now() then
    perform public.invoke_push_dispatch();
  end if;
end $$;
revoke execute on function public.enqueue_push(uuid, text, text, text, jsonb, timestamptz, timestamptz, text)
  from public, anon, authenticated;

-- Remove what has not gone out yet (a cancelled or moved date night).
create or replace function public.cancel_push(p_collapse text)
returns void
language sql security definer set search_path = ''
as $$
  delete from public.push_outbox where collapse_key = p_collapse and sent_at is null;
$$;
revoke execute on function public.cancel_push(text) from public, anon, authenticated;

-- Next rows for the dispatcher, with each recipient's tokens. Quiet hours (11 PM
-- to 8 AM in the recipient's zone) hold everything except a call.
create or replace function public.claim_push_batch(p_limit int default 50)
returns table (id bigint, user_id uuid, kind text, title text, body text, data jsonb,
               expires_at timestamptz, tokens jsonb)
language sql security definer set search_path = ''
as $$
  with due as (
    select o.id
    from public.push_outbox o
    left join public.profiles pr on pr.id = o.user_id
    left join public.push_prefs pp on pp.user_id = o.user_id
    where o.sent_at is null
      and o.send_after <= now()
      and (o.expires_at is null or o.expires_at > now())
      and o.attempts < 5
      and (o.locked_until is null or o.locked_until < now())
      and (
        o.kind = 'call'
        or not coalesce(pp.quiet_hours, true)
        or extract(hour from now() at time zone coalesce(pr.timezone, 'UTC')) between 8 and 22
      )
    order by o.send_after
    limit p_limit
    for update of o skip locked
  ), claimed as (
    update public.push_outbox o
       set attempts = o.attempts + 1, locked_until = now() + interval '2 minutes'
      from due where o.id = due.id
    returning o.*
  )
  select c.id, c.user_id, c.kind, c.title, c.body, c.data, c.expires_at,
         coalesce((select jsonb_agg(jsonb_build_object(
                     'platform', t.platform, 'token', t.token, 'environment', t.environment))
                   from public.push_tokens t where t.user_id = c.user_id), '[]'::jsonb)
  from claimed c;
$$;

-- Outcome of one row: delivered (or nothing left to deliver to), or retry later.
create or replace function public.complete_push(p_id bigint, p_done boolean)
returns void
language sql security definer set search_path = ''
as $$
  update public.push_outbox
     set sent_at = case when p_done then now() else sent_at end,
         locked_until = case when p_done then null else now() + (attempts * interval '30 seconds') end
   where id = p_id;
$$;

create or replace function public.drop_push_token(p_platform text, p_token text)
returns void
language sql security definer set search_path = ''
as $$
  delete from public.push_tokens where platform = p_platform and token = p_token;
$$;

do $$
declare f text;
begin
  foreach f in array array['claim_push_batch(int)', 'complete_push(bigint, boolean)', 'drop_push_token(text, text)'] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
  foreach f in array array['register_push_token(text, text, text)', 'unregister_push_token(text)',
                           'my_push_prefs()', 'set_push_pref(text, boolean)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Display helpers
-- ---------------------------------------------------------------------------
create or replace function public.local_stamp(p_at timestamptz, p_user uuid)
returns text
language sql stable security definer set search_path = ''
as $$
  select to_char(p_at at time zone coalesce((select timezone from public.profiles where id = p_user), 'UTC'),
                 'Dy, FMDD Mon "at" FMHH12:MI AM');
$$;
revoke execute on function public.local_stamp(timestamptz, uuid) from public, anon, authenticated;

create or replace function public.partner_of(p_user uuid)
returns uuid
language sql stable security definer set search_path = ''
as $$
  select o.user_id from public.pair_members m
  join public.pair_members o on o.pair_id = m.pair_id and o.user_id <> m.user_id
  where m.user_id = p_user;
$$;
revoke execute on function public.partner_of(uuid) from public, anon, authenticated;

create or replace function public.display_name_of(p_user uuid)
returns text
language sql stable security definer set search_path = ''
as $$
  select display_name from public.profiles where id = p_user;
$$;
revoke execute on function public.display_name_of(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Pairing now tells the inviter
-- ---------------------------------------------------------------------------
create or replace function public.accept_pair_invite(p_code text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_inv public.pair_invites;
  v_pair uuid;
begin
  perform public.assert_can_pair(v_uid);

  select * into v_inv from public.pair_invites
    where code = upper(trim(p_code)) for update;
  if not found then
    raise exception 'invite_not_found';
  end if;
  if v_inv.status = 'accepted' then
    raise exception 'invite_used';
  end if;
  if v_inv.status = 'cancelled' then
    raise exception 'invite_cancelled';
  end if;
  if v_inv.expires_at <= now() then
    raise exception 'invite_expired';
  end if;
  if v_inv.inviter_id = v_uid then
    raise exception 'cannot_pair_self';
  end if;
  if exists (select 1 from public.pair_members where user_id = v_uid) then
    raise exception 'already_paired';
  end if;
  if exists (select 1 from public.pair_members where user_id = v_inv.inviter_id) then
    raise exception 'partner_already_paired';
  end if;

  insert into public.pairs default values returning id into v_pair;
  insert into public.pair_members (user_id, pair_id)
    values (v_inv.inviter_id, v_pair), (v_uid, v_pair);
  update public.pair_invites set status = 'accepted', pair_id = v_pair where id = v_inv.id;

  perform public.enqueue_push(
    v_inv.inviter_id, 'pair_accepted',
    public.display_name_of(v_uid) || ' paired with you',
    'Your private room is ready.',
    jsonb_build_object('route', 'our-room'),
    now(), now() + interval '2 days', 'pair:' || v_pair::text);
  return v_pair;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Calling your person
-- ---------------------------------------------------------------------------
create or replace function public.call_partner()
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_pair uuid := public.my_pair_id();
  v_partner uuid;
begin
  if v_uid is null or v_pair is null then
    raise exception 'not_paired';
  end if;
  v_partner := public.partner_of(v_uid);

  -- One ring a minute: a held-down button must not become a barrage.
  if exists (select 1 from public.push_outbox
             where user_id = v_partner and kind = 'call'
               and created_at > now() - interval '1 minute') then
    return jsonb_build_object('sent', false, 'reason', 'throttled');
  end if;

  perform public.enqueue_push(
    v_partner, 'call',
    public.display_name_of(v_uid) || ' is calling',
    'Our Room is open. Tap to join.',
    jsonb_build_object('route', 'our-room', 'urgent', true),
    now(), now() + interval '90 seconds', null);
  return jsonb_build_object('sent', true);
end $$;

-- ---------------------------------------------------------------------------
-- 6. Watchlist
-- ---------------------------------------------------------------------------
create table public.pair_watchlist (
  id uuid primary key default gen_random_uuid(),
  pair_id uuid not null references public.pairs (id) on delete cascade,
  added_by uuid not null references public.profiles (id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  source_kind text not null check (source_kind in ('youtube', 'local')),
  source_url text check (source_url is null or char_length(source_url) <= 300),
  status text not null default 'to_watch' check (status in ('to_watch', 'watched')),
  created_at timestamptz not null default now(),
  watched_at timestamptz,
  constraint pair_watchlist_shape check ((source_kind = 'youtube') = (source_url is not null))
);
create index idx_pair_watchlist_pair on public.pair_watchlist (pair_id, created_at desc);

alter table public.pair_watchlist enable row level security;
create policy pair_watchlist_select on public.pair_watchlist for select to authenticated
  using (pair_id = (select public.my_pair_id()));
revoke all on public.pair_watchlist from public, anon, authenticated;
grant select on public.pair_watchlist to authenticated;
alter publication supabase_realtime add table public.pair_watchlist;
alter table public.pair_watchlist replica identity full;

create or replace function public.add_watchlist_item(p_title text, p_source_kind text, p_source_url text default null)
returns public.pair_watchlist
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_pair uuid := public.my_pair_id();
  v_item public.pair_watchlist;
  v_title text := left(trim(coalesce(p_title, '')), 120);
begin
  if v_uid is null or v_pair is null then
    raise exception 'not_paired';
  end if;
  if v_title = '' then
    raise exception 'invalid_title';
  end if;
  if p_source_kind = 'youtube' and (p_source_url is null or p_source_url !~* '^https?://') then
    raise exception 'invalid_source';
  end if;
  if (select count(*) from public.pair_watchlist where pair_id = v_pair) >= 200 then
    raise exception 'watchlist_full';
  end if;

  insert into public.pair_watchlist (pair_id, added_by, title, source_kind, source_url)
  values (v_pair, v_uid, v_title, p_source_kind,
          case when p_source_kind = 'youtube' then left(p_source_url, 300) else null end)
  returning * into v_item;

  perform public.enqueue_push(
    public.partner_of(v_uid), 'watchlist_add',
    public.display_name_of(v_uid) || ' added ' || v_title,
    'It is on your watchlist now.',
    jsonb_build_object('route', 'watchlist'),
    now(), now() + interval '1 day', 'wl:' || v_pair::text);
  return v_item;
end $$;

create or replace function public.set_watchlist_status(p_id uuid, p_watched boolean)
returns void
language sql security definer set search_path = ''
as $$
  update public.pair_watchlist set
    status = case when p_watched then 'watched' else 'to_watch' end,
    watched_at = case when p_watched then now() else null end
  where id = p_id and pair_id = (select public.my_pair_id());
$$;

create or replace function public.remove_watchlist_item(p_id uuid)
returns void
language sql security definer set search_path = ''
as $$
  delete from public.pair_watchlist where id = p_id and pair_id = (select public.my_pair_id());
$$;

-- ---------------------------------------------------------------------------
-- 7. Date nights
-- ---------------------------------------------------------------------------
create table public.date_nights (
  id uuid primary key default gen_random_uuid(),
  pair_id uuid not null references public.pairs (id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  starts_at timestamptz not null,
  -- Whoever made the latest proposal; the other person answers it.
  proposed_by uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'proposed' check (status in ('proposed', 'accepted', 'declined', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_date_nights_pair on public.date_nights (pair_id, starts_at);

alter table public.date_nights enable row level security;
create policy date_nights_select on public.date_nights for select to authenticated
  using (pair_id = (select public.my_pair_id()));
revoke all on public.date_nights from public, anon, authenticated;
grant select on public.date_nights to authenticated;
alter publication supabase_realtime add table public.date_nights;
alter table public.date_nights replica identity full;

-- Reminders go to both people, 15 minutes before, collapsed per night so moving
-- or cancelling it replaces or removes them.
create or replace function public.schedule_date_night_reminders(p_night public.date_nights)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_member uuid;
begin
  for v_member in select user_id from public.pair_members where pair_id = p_night.pair_id loop
    perform public.enqueue_push(
      v_member, 'date_night_reminder',
      'Date night in 15 minutes',
      p_night.title || ' with ' || public.display_name_of(public.partner_of(v_member))
        || ', ' || to_char(p_night.starts_at at time zone
            coalesce((select timezone from public.profiles where id = v_member), 'UTC'), 'FMHH12:MI AM')
        || ' your time',
      jsonb_build_object('route', 'our-room', 'night', p_night.id),
      greatest(p_night.starts_at - interval '15 minutes', now()),
      p_night.starts_at + interval '30 minutes',
      'dn:' || p_night.id::text);
  end loop;
end $$;
revoke execute on function public.schedule_date_night_reminders(public.date_nights) from public, anon, authenticated;

create or replace function public.create_date_night(p_title text, p_starts_at timestamptz)
returns public.date_nights
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_pair uuid := public.my_pair_id();
  v_night public.date_nights;
  v_title text := left(trim(coalesce(p_title, '')), 120);
begin
  if v_uid is null or v_pair is null then
    raise exception 'not_paired';
  end if;
  if not public.pair_is_patron(v_pair) then
    raise exception 'patron_required';
  end if;
  if v_title = '' then
    raise exception 'invalid_title';
  end if;
  if p_starts_at is null or p_starts_at < now() + interval '5 minutes'
     or p_starts_at > now() + interval '1 year' then
    raise exception 'invalid_time';
  end if;

  insert into public.date_nights (pair_id, title, starts_at, proposed_by)
  values (v_pair, v_title, p_starts_at, v_uid)
  returning * into v_night;

  perform public.enqueue_push(
    public.partner_of(v_uid), 'date_night_invite',
    public.display_name_of(v_uid) || ' proposed a date night',
    v_title || ', ' || public.local_stamp(p_starts_at, public.partner_of(v_uid)),
    jsonb_build_object('route', 'date-night', 'night', v_night.id),
    now(), now() + interval '2 days', 'dnp:' || v_night.id::text);
  return v_night;
end $$;

create or replace function public.respond_date_night(p_id uuid, p_accept boolean)
returns public.date_nights
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_night public.date_nights;
begin
  select * into v_night from public.date_nights
    where id = p_id and pair_id = public.my_pair_id() for update;
  if not found then
    raise exception 'night_not_found';
  end if;
  if v_night.proposed_by = v_uid then
    raise exception 'own_proposal';
  end if;
  if v_night.status <> 'proposed' then
    raise exception 'night_not_open';
  end if;

  update public.date_nights set
    status = case when p_accept then 'accepted' else 'declined' end,
    updated_at = now()
  where id = p_id returning * into v_night;

  perform public.cancel_push('dnp:' || p_id::text);
  if p_accept then
    perform public.schedule_date_night_reminders(v_night);
  end if;
  perform public.enqueue_push(
    v_night.proposed_by, 'date_night_response',
    case when p_accept then public.display_name_of(v_uid) || ' is in'
         else public.display_name_of(v_uid) || ' cannot make it' end,
    v_night.title || ', ' || public.local_stamp(v_night.starts_at, v_night.proposed_by),
    jsonb_build_object('route', 'date-night', 'night', v_night.id),
    now(), now() + interval '2 days', 'dnr:' || p_id::text);
  return v_night;
end $$;

-- Suggesting another time is a new proposal from the person who moved it.
create or replace function public.reschedule_date_night(p_id uuid, p_starts_at timestamptz)
returns public.date_nights
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_night public.date_nights;
begin
  select * into v_night from public.date_nights
    where id = p_id and pair_id = public.my_pair_id() for update;
  if not found then
    raise exception 'night_not_found';
  end if;
  if v_night.status = 'cancelled' then
    raise exception 'night_not_open';
  end if;
  if p_starts_at is null or p_starts_at < now() + interval '5 minutes'
     or p_starts_at > now() + interval '1 year' then
    raise exception 'invalid_time';
  end if;

  update public.date_nights set
    starts_at = p_starts_at, proposed_by = v_uid, status = 'proposed', updated_at = now()
  where id = p_id returning * into v_night;

  perform public.cancel_push('dn:' || p_id::text);
  perform public.enqueue_push(
    public.partner_of(v_uid), 'date_night_invite',
    public.display_name_of(v_uid) || ' suggested another time',
    v_night.title || ', ' || public.local_stamp(p_starts_at, public.partner_of(v_uid)),
    jsonb_build_object('route', 'date-night', 'night', v_night.id),
    now(), now() + interval '2 days', 'dnp:' || p_id::text);
  return v_night;
end $$;

create or replace function public.cancel_date_night(p_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_night public.date_nights;
begin
  select * into v_night from public.date_nights
    where id = p_id and pair_id = public.my_pair_id() for update;
  if not found or v_night.status = 'cancelled' then
    return;
  end if;
  update public.date_nights set status = 'cancelled', updated_at = now() where id = p_id;
  perform public.cancel_push('dn:' || p_id::text);
  perform public.cancel_push('dnp:' || p_id::text);
  perform public.enqueue_push(
    public.partner_of(v_uid), 'date_night_response',
    public.display_name_of(v_uid) || ' cancelled ' || v_night.title,
    'Plan another when you are both free.',
    jsonb_build_object('route', 'date-night'),
    now(), now() + interval '2 days', 'dnr:' || p_id::text);
end $$;

-- ---------------------------------------------------------------------------
-- 8. What you watched together
-- ---------------------------------------------------------------------------
create table public.pair_sessions (
  id uuid primary key default gen_random_uuid(),
  pair_id uuid not null references public.pairs (id) on delete cascade,
  title text check (title is null or char_length(title) <= 120),
  started_at timestamptz not null,
  seconds int not null check (seconds between 0 and 86400),
  logged_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
-- Both partners may report the same sitting; the longer report wins.
create unique index pair_sessions_sitting
  on public.pair_sessions (pair_id, (date_trunc('minute', started_at at time zone 'UTC')));
create index idx_pair_sessions_pair on public.pair_sessions (pair_id, started_at desc);

alter table public.pair_sessions enable row level security;
revoke all on public.pair_sessions from public, anon, authenticated;

create or replace function public.log_pair_session(p_title text, p_started_at timestamptz, p_seconds int)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_pair uuid := public.my_pair_id();
  v_title text := nullif(left(trim(coalesce(p_title, '')), 120), '');
begin
  if auth.uid() is null or v_pair is null then
    raise exception 'not_paired';
  end if;
  -- A minute is the least that counts as having watched anything together.
  if p_seconds is null or p_seconds < 60 or p_started_at is null
     or p_started_at > now() + interval '5 minutes'
     or p_started_at < now() - interval '2 days' then
    return;
  end if;

  insert into public.pair_sessions (pair_id, title, started_at, seconds, logged_by)
  values (v_pair, v_title, p_started_at, least(p_seconds, 86400), auth.uid())
  on conflict (pair_id, (date_trunc('minute', started_at at time zone 'UTC')))
  do update set
    seconds = greatest(public.pair_sessions.seconds, excluded.seconds),
    title = coalesce(public.pair_sessions.title, excluded.title);

  if v_title is not null then
    update public.pair_watchlist set status = 'watched', watched_at = now()
    where pair_id = v_pair and status = 'to_watch' and lower(title) = lower(v_title);
  end if;
end $$;

-- The last 7 days are free; the rest is Patron on either side, and is kept
-- (hidden, never deleted) when Patron lapses.
create or replace function public.pair_history()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_pair uuid := public.my_pair_id();
  v_patron boolean;
  v_cut timestamptz;
begin
  if auth.uid() is null or v_pair is null then
    raise exception 'not_paired';
  end if;
  v_patron := public.pair_is_patron(v_pair);
  v_cut := case when v_patron then '-infinity'::timestamptz else now() - interval '7 days' end;

  return jsonb_build_object(
    'patron', v_patron,
    'locked_count', (select count(*) from public.pair_sessions
                     where pair_id = v_pair and started_at < v_cut),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id, 'title', s.title, 'started_at', s.started_at, 'seconds', s.seconds)
             order by s.started_at desc)
      from (select * from public.pair_sessions
            where pair_id = v_pair and started_at >= v_cut
            order by started_at desc limit 500) s), '[]'::jsonb));
end $$;

-- Everything, for anyone, whatever the plan. Memories are not a paywall.
create or replace function public.pair_history_export()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_pair uuid := public.my_pair_id();
begin
  if auth.uid() is null or v_pair is null then
    raise exception 'not_paired';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'title', title, 'started_at', started_at, 'seconds', seconds)
           order by started_at)
    from public.pair_sessions where pair_id = v_pair), '[]'::jsonb);
end $$;

-- Weekly streak: a week counts when you spent 20+ minutes together in it. The
-- current streak survives a week that has not finished yet.
create or replace function public.pair_stats(p_year int default null)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_pair uuid := public.my_pair_id();
  v_this_week date := date_trunc('week', now() at time zone 'UTC')::date;
  v_current int;
  v_best int;
  v_done_this_week boolean;
begin
  if auth.uid() is null or v_pair is null then
    raise exception 'not_paired';
  end if;

  with w as (
    select distinct date_trunc('week', started_at at time zone 'UTC')::date as wk
    from public.pair_sessions where pair_id = v_pair and seconds >= 1200
  ), g as (
    select wk, wk - (row_number() over (order by wk) * 7)::int as grp from w
  ), islands as (
    select count(*)::int as len, max(wk) as last_wk from g group by grp
  )
  select coalesce(max(len) filter (where last_wk >= v_this_week - 7), 0),
         coalesce(max(len), 0)
    into v_current, v_best from islands;

  select exists (select 1 from public.pair_sessions
                 where pair_id = v_pair and seconds >= 1200
                   and date_trunc('week', started_at at time zone 'UTC')::date = v_this_week)
    into v_done_this_week;

  return jsonb_build_object(
    'streak_weeks', v_current,
    'best_streak_weeks', v_best,
    'done_this_week', v_done_this_week,
    'nights', (select count(*) from public.pair_sessions
               where pair_id = v_pair and seconds >= 1200
                 and (p_year is null or extract(year from started_at at time zone 'UTC') = p_year)),
    'hours', (select round(coalesce(sum(seconds), 0) / 3600.0, 1) from public.pair_sessions
              where pair_id = v_pair
                and (p_year is null or extract(year from started_at at time zone 'UTC') = p_year)),
    'films', (select count(distinct lower(title)) from public.pair_sessions
              where pair_id = v_pair and title is not null
                and (p_year is null or extract(year from started_at at time zone 'UTC') = p_year)));
end $$;

-- ---------------------------------------------------------------------------
-- 9. Reunion reminders and housekeeping, on the existing minutely job
-- ---------------------------------------------------------------------------
-- Run on the hour. A member hears about the countdown at 9 AM their time, the
-- day before and every Sunday in between.
create or replace function public.enqueue_reunion_pushes()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  r record;
  v_days int;
  v_local timestamp;
begin
  for r in
    select m.user_id, p.id as pair_id, p.reunion_on, p.reunion_label,
           coalesce(pr.timezone, 'UTC') as tz
    from public.pairs p
    join public.pair_members m on m.pair_id = p.id
    join public.profiles pr on pr.id = m.user_id
    where p.reunion_on is not null and p.reunion_on >= current_date - 1
  loop
    v_local := now() at time zone r.tz;
    continue when extract(hour from v_local) <> 9;
    v_days := r.reunion_on - v_local::date;
    continue when v_days < 0;
    if v_days = 1 then
      perform public.enqueue_push(
        r.user_id, 'reunion', 'Tomorrow',
        coalesce(r.reunion_label, 'You and ' || coalesce(public.display_name_of(public.partner_of(r.user_id)), 'your person') || ' are in the same room.'),
        jsonb_build_object('route', 'lobby'), now(), now() + interval '12 hours',
        'reunion:' || r.pair_id::text || ':' || r.user_id::text);
    elsif v_days = 0 then
      perform public.enqueue_push(
        r.user_id, 'reunion', 'Today',
        'Enjoy every minute of it.',
        jsonb_build_object('route', 'lobby'), now(), now() + interval '12 hours',
        'reunion:' || r.pair_id::text || ':' || r.user_id::text);
    elsif extract(dow from v_local) = 0 then
      perform public.enqueue_push(
        r.user_id, 'reunion', v_days || ' days to go',
        'Until you and ' || coalesce(public.display_name_of(public.partner_of(r.user_id)), 'your person') || ' are in the same room.',
        jsonb_build_object('route', 'lobby'), now(), now() + interval '12 hours',
        'reunion:' || r.pair_id::text || ':' || r.user_id::text);
    end if;
  end loop;
end $$;
revoke execute on function public.enqueue_reunion_pushes() from public, anon, authenticated;
grant execute on function public.enqueue_reunion_pushes() to service_role;

create or replace function public.minutely_maintenance()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  begin
    perform public.sweep_rooms();
  exception when others then
    raise warning 'minutely_maintenance: sweep_rooms failed: %', sqlerrm;
  end;
  begin
    perform public.invoke_av_cleanup();
  exception when others then
    raise warning 'minutely_maintenance: invoke_av_cleanup failed: %', sqlerrm;
  end;
  begin
    perform public.close_video_trials();
  exception when others then
    raise warning 'minutely_maintenance: close_video_trials failed: %', sqlerrm;
  end;
  begin
    if extract(minute from now()) = 0 then
      perform public.enqueue_reunion_pushes();
    end if;
    -- Due reminders and held rows go out on the next tick.
    if exists (select 1 from public.push_outbox
               where sent_at is null and send_after <= now()
                 and (expires_at is null or expires_at > now()) and attempts < 5) then
      perform public.invoke_push_dispatch();
    end if;
    delete from public.push_outbox where created_at < now() - interval '2 days';
  exception when others then
    raise warning 'minutely_maintenance: push failed: %', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 10. Grants for the client-facing RPCs
-- ---------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'call_partner()', 'add_watchlist_item(text, text, text)', 'set_watchlist_status(uuid, boolean)',
    'remove_watchlist_item(uuid)', 'create_date_night(text, timestamptz)',
    'respond_date_night(uuid, boolean)', 'reschedule_date_night(uuid, timestamptz)',
    'cancel_date_night(uuid)', 'log_pair_session(text, timestamptz, int)', 'pair_history()',
    'pair_history_export()', 'pair_stats(int)', 'accept_pair_invite(text)']
  loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
