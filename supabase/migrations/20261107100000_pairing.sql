-- Migration: pairing ("your person") and Our Room.
--
-- Two signed-in accounts can pair. A pair owns one persistent private room
-- (Our Room) that is free for everyone, does not count against any room cap,
-- keeps its chat between sessions, and can only be entered by the two people
-- paired on it. Pairing is account-scoped: guests cannot pair.
--
-- One pair per person (pair_members.user_id is the primary key). Either member
-- ending the pair, or deleting their account, deletes the pair and its room.
--
-- Patron status is read from effective_tier, the single arbiter: the pair is
-- "patron" when either partner is premium (used by later migrations for the
-- full history archive and date-night scheduling).

-- ---------------------------------------------------------------------------
-- 1. Profile time zone (IANA name, set by the client)
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists timezone text
  check (timezone is null or char_length(timezone) <= 64);

create or replace function public.set_my_timezone(p_timezone text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if p_timezone is null
     or not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    raise exception 'invalid_timezone';
  end if;
  update public.profiles set timezone = p_timezone
    where id = auth.uid() and timezone is distinct from p_timezone;
end $$;

revoke execute on function public.set_my_timezone(text) from public, anon;
grant execute on function public.set_my_timezone(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------
create table public.pairs (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  reunion_on date,
  reunion_label text check (reunion_label is null or char_length(reunion_label) <= 60)
);

create table public.pair_members (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  pair_id uuid not null references public.pairs (id) on delete cascade,
  joined_at timestamptz not null default now()
);
create index idx_pair_members_pair on public.pair_members (pair_id);

create table public.pair_invites (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  inviter_id uuid not null references public.profiles (id) on delete cascade,
  -- The last signed-in person who opened the link. Not a claim: anyone can
  -- still accept while the invite is pending. It is only who the lobby banner
  -- reminds, so "Not now" followed by a cold start does not lose the invite.
  seen_by uuid references public.profiles (id) on delete set null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'cancelled')),
  pair_id uuid references public.pairs (id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '48 hours'
);
create unique index pair_invites_one_pending
  on public.pair_invites (inviter_id) where status = 'pending';

alter table public.rooms
  add column if not exists pair_id uuid references public.pairs (id) on delete cascade;
create unique index rooms_one_per_pair on public.rooms (pair_id) where pair_id is not null;

-- A pair is two people. When either membership goes (unpair, account deletion)
-- the whole pair goes, which cascades to the other membership and to Our Room.
create or replace function public.pair_member_removed()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.pairs where id = old.pair_id;
  return old;
end $$;

create trigger pair_member_removed
  after delete on public.pair_members
  for each row execute function public.pair_member_removed();

-- ---------------------------------------------------------------------------
-- 3. Row level security: read-only to clients, every write is an RPC
-- ---------------------------------------------------------------------------
create or replace function public.my_pair_id()
returns uuid
language sql stable security definer set search_path = ''
as $$
  select pair_id from public.pair_members where user_id = (select auth.uid());
$$;

alter table public.pairs enable row level security;
alter table public.pair_members enable row level security;
alter table public.pair_invites enable row level security;

create policy pairs_select on public.pairs for select to authenticated
  using (id = (select public.my_pair_id()));
create policy pair_members_select on public.pair_members for select to authenticated
  using (pair_id = (select public.my_pair_id()));
create policy pair_invites_select on public.pair_invites for select to authenticated
  using (inviter_id = (select auth.uid()) or seen_by = (select auth.uid()));

revoke all on public.pairs, public.pair_members, public.pair_invites from public, anon, authenticated;
grant select on public.pairs, public.pair_members, public.pair_invites to authenticated;
revoke execute on function public.my_pair_id() from public, anon;
grant execute on function public.my_pair_id() to authenticated;

alter publication supabase_realtime add table public.pair_members, public.pair_invites;
alter table public.pair_members replica identity full;
alter table public.pair_invites replica identity full;

-- Our Room is a persistent room whatever its owner's tier, so room_state must
-- not hand it to the premium-only branch. It is live while a session runs and
-- idle between sessions; it never reads 'expired'.
create or replace function public.room_state(p_room public.rooms)
returns text
language sql stable set search_path = ''
as $$
  select case
    when p_room.pair_id is not null then
      case
        when p_room.ended_at is null and p_room.expires_at > now() then 'live'
        else 'idle'
      end
    when p_room.persistent and public.effective_tier(p_room.created_by) = 'premium' then
      case
        when p_room.ended_at is null and p_room.expires_at > now() then 'live'
        else 'idle'
      end
    when p_room.ended_at is not null then 'expired'
    when p_room.expires_at > now() then 'live'
    else 'expired'
  end;
$$;

-- The sweep must not strip persistence from, or age out, Our Room.
create or replace function public.sweep_rooms()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
  v_idle jsonb;
begin
  for v_id in
    select id from public.rooms where ended_at is null and expires_at <= now()
  loop
    perform public.retire_room(v_id);
  end loop;

  update public.rooms r set
    persistent = false,
    resumable_until = now() + interval '7 days'
  where r.persistent
    and r.pair_id is null
    and r.ended_at is not null
    and public.effective_tier(r.created_by) <> 'premium';

  delete from public.rooms r
  where r.ended_at is not null
    and not r.persistent
    and (r.resumable_until is null or r.resumable_until <= now());

  select value into v_idle from public.app_settings where key = 'idle_rooms';
  if coalesce((v_idle ->> 'enabled')::boolean, true) then
    delete from public.rooms r
    where r.persistent
      and r.pair_id is null
      and r.ended_at is not null
      and r.ended_at < now() - make_interval(days => coalesce((v_idle ->> 'ttl_days')::int, 90))
      and public.room_state(r) = 'idle';
  end if;

  -- Our Room chat is kept between sessions, but not forever.
  delete from public.messages m
  using public.rooms r
  where m.room_id = r.id
    and r.pair_id is not null
    and m.created_at < now() - interval '90 days';
end $$;

-- ---------------------------------------------------------------------------
-- 4. Existing room functions, patched from their live definitions
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_room(p_name text, p_duration_minutes integer, p_staged_id uuid DEFAULT NULL::uuid)
 RETURNS rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_tier text;
  v_limits public.tier_limits;
  v_held int;
  v_code text;
  v_room public.rooms;
  v_staged public.staged_media_uploads%rowtype;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  if v_uid is null or not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'not_authenticated';
  end if;

  if exists (select 1 from public.profile_moderation where user_id = v_uid and moderation_status = 'banned') then
    raise exception 'account_banned';
  end if;

  v_tier := public.effective_tier(v_uid);
  select * into v_limits from public.tier_limits where tier = v_tier;

  if p_duration_minutes is null
     or p_duration_minutes < 5
     or p_duration_minutes > v_limits.max_session_minutes then
    raise exception 'invalid_duration';
  end if;

  -- If staged media provided, validate ownership and ready status
  if p_staged_id is not null then
    select * into v_staged from public.staged_media_uploads
    where id = p_staged_id
      and user_id = v_uid
      and upload_state = 'ready'
      and claimed_room_id is null
      and expires_at > now();

    if v_staged.id is null then
      raise exception 'staged_media_invalid';
    end if;
  end if;

  select count(*) into v_held from public.rooms r
    where r.created_by = v_uid and r.pair_id is null and public.room_state(r) = 'live';
  if v_held >= v_limits.max_live_rooms then
    if v_tier = 'guest' then
      raise exception 'guest_room_limit';
    end if;
    raise exception 'room_limit_reached';
  end if;

  if v_limits.persistent_room_cap > 0 then
    select count(*) into v_held from public.rooms r
      where r.created_by = v_uid and r.pair_id is null and r.persistent;
    if v_held >= v_limits.persistent_room_cap then
      raise exception 'room_limit_reached';
    end if;
  end if;

  loop
    select string_agg(substr(v_alphabet, 1 + floor(random() * 32)::int, 1), '')
      into v_code from generate_series(1, 6);
    exit when not exists (select 1 from public.rooms where code = v_code);
  end loop;

  insert into public.rooms (
    code,
    name,
    created_by,
    duration_minutes,
    expires_at,
    persistent,
    dormant_hours,
    av_level,
    max_members,
    media_kind,
    media_name,
    media_duration_ms,
    media_file_size,
    media_r2_key,
    media_upload_state,
    media_sharing_level,
    media_updated_at
  )
  values (
    v_code,
    coalesce(nullif(left(trim(p_name), 60), ''), 'Watch party'),
    v_uid,
    p_duration_minutes,
    now() + make_interval(mins => p_duration_minutes),
    v_limits.persistent_room_cap > 0,
    v_limits.dormant_hours,
    v_limits.av_level,
    v_limits.max_members,
    case when p_staged_id is not null then 'local' else 'none' end,
    case when p_staged_id is not null then v_staged.file_name else null end,
    case when p_staged_id is not null then v_staged.duration_ms else null end,
    case when p_staged_id is not null then v_staged.file_size else null end,
    case when p_staged_id is not null then v_staged.r2_key else null end,
    case when p_staged_id is not null then 'ready' else 'none' end,
    v_limits.media_sharing,
    case when p_staged_id is not null then now() else null end
  )
  returning * into v_room;

  insert into public.room_members (room_id, user_id, role)
  values (v_room.id, v_uid, 'host');

  -- Mark staged upload as claimed
  if p_staged_id is not null then
    update public.staged_media_uploads
    set claimed_room_id = v_room.id
    where id = p_staged_id;
  end if;

  return v_room;
end $function$;

CREATE OR REPLACE FUNCTION public.resume_room(p_room_id uuid, p_minutes integer)
 RETURNS rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_limits public.tier_limits;
  v_tier text;
  v_room public.rooms;
  v_state text;
  v_min int;
  v_held int;
  v_persist boolean;
begin
  if v_uid is null or not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'not_authenticated';
  end if;

  if exists (select 1 from public.profile_moderation where user_id = v_uid and moderation_status = 'banned') then
    raise exception 'account_banned';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    raise exception 'room_not_found';
  end if;

  -- A room a moderator closed stays closed; resuming it would undo the ban.
  if v_room.is_banned then
    raise exception 'room_closed_by_admin';
  end if;

  if v_room.created_by <> v_uid and not exists (
    select 1 from public.room_members where room_id = p_room_id and user_id = v_uid and role = 'host'
  ) then
    raise exception 'not_host';
  end if;

  v_state := public.room_state(v_room);

  -- A running session is left exactly as it is. Extending is extend_room's job.
  if v_state = 'live' then
    return v_room;
  end if;

  if v_state = 'expired'
     and (v_room.resumable_until is null or v_room.resumable_until <= now()) then
    raise exception 'room_ended';
  end if;

  v_tier := public.effective_tier(v_uid);
  select * into v_limits from public.tier_limits where tier = v_tier;

  v_min := coalesce(p_minutes, v_room.duration_minutes);
  if v_min is null or v_min < 5 or v_min > v_limits.max_session_minutes then
    raise exception 'invalid_duration';
  end if;

  select count(*) into v_held from public.rooms r
    where r.created_by = v_uid and r.pair_id is null and r.id <> p_room_id and public.room_state(r) = 'live';
  if v_held >= v_limits.max_live_rooms then
    if v_tier = 'guest' then
      raise exception 'guest_room_limit';
    end if;
    raise exception 'room_limit_reached';
  end if;

  v_persist := v_limits.persistent_room_cap > 0;
  if v_persist and not v_room.persistent then
    select count(*) into v_held from public.rooms r
      where r.created_by = v_uid and r.pair_id is null and r.persistent and r.id <> p_room_id;
    if v_held >= v_limits.persistent_room_cap then
      -- Out of saved-room slots: resume it as an ordinary room rather than refuse.
      v_persist := false;
    end if;
  end if;

  update public.rooms set
    ended_at = null,
    resumable_until = null,
    duration_minutes = v_min,
    expires_at = now() + make_interval(mins => v_min),
    max_members = v_limits.max_members,
    av_level = v_limits.av_level,
    dormant_hours = v_limits.dormant_hours,
    persistent = v_persist
  where id = p_room_id
  returning * into v_room;

  insert into public.room_members (room_id, user_id, role)
  values (p_room_id, v_uid, 'host')
  on conflict (room_id, user_id) do update set role = 'host';

  return v_room;
end $function$;

CREATE OR REPLACE FUNCTION public.join_room(p_code text)
 RETURNS rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms;
  v_state text;
  v_count int;
  v_has_host boolean;
  v_was_member boolean;
begin
  if v_uid is null or not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'not_authenticated';
  end if;

  if exists (select 1 from public.profile_moderation where user_id = v_uid and moderation_status = 'banned') then
    raise exception 'account_banned';
  end if;

  select * into v_room from public.rooms where code = upper(trim(p_code));
  if not found then
    raise exception 'room_not_found';
  end if;

  if v_room.is_banned then
    raise exception 'room_closed_by_admin';
  end if;

  if exists (select 1 from public.room_bans
             where room_id = v_room.id and user_id = v_uid) then
    raise exception 'room_banned';
  end if;

  -- Our Room belongs to the two people paired on it. Anyone else holding the
  -- code gets the same answer as for a code that does not exist.
  if v_room.pair_id is not null and not exists (
    select 1 from public.pair_members pm
    where pm.pair_id = v_room.pair_id and pm.user_id = v_uid
  ) then
    raise exception 'room_not_found';
  end if;

  v_state := public.room_state(v_room);
  if v_state = 'idle' then
    raise exception 'room_idle';
  elsif v_state <> 'live' then
    raise exception 'room_ended';
  end if;

  select exists (select 1 from public.room_members
                 where room_id = v_room.id and role = 'host') into v_has_host;

  select exists (select 1 from public.room_members where user_id = v_uid)
    into v_was_member;

  if exists (select 1 from public.room_members
             where room_id = v_room.id and user_id = v_uid) then
    if not v_has_host and v_uid = v_room.created_by then
      update public.room_members set role = 'host'
        where room_id = v_room.id and user_id = v_uid;
    end if;
    return v_room;
  end if;

  select count(*) into v_count from public.room_members where room_id = v_room.id;
  if v_count >= v_room.max_members then
    raise exception 'room_full';
  end if;

  insert into public.room_members (room_id, user_id, role)
  values (
    v_room.id,
    v_uid,
    case when not v_has_host and v_uid = v_room.created_by then 'host' else 'member' end
  );

  if not v_was_member
     and v_room.created_by <> v_uid
     and exists (select 1 from public.profiles
                  where id = v_uid and created_at > now() - interval '1 day') then
    update public.profiles
       set referred_by = v_room.created_by, updated_at = now()
     where id = v_uid and referred_by is null;
  end if;

  return v_room;
end $function$;

CREATE OR REPLACE FUNCTION public.list_my_rooms()
 RETURNS TABLE(id uuid, code text, name text, created_by uuid, created_at timestamp with time zone, duration_minutes integer, expires_at timestamp with time zone, ended_at timestamp with time zone, resumable_until timestamp with time zone, persistent boolean, dormant_hours integer, av_level text, max_members integer, transport_lock boolean, media_kind text, media_name text, media_duration_ms bigint, media_url text, media_updated_at timestamp with time zone, media_position_ms bigint, media_position_at timestamp with time zone, media_file_size bigint, media_r2_key text, media_upload_state text, media_sharing_level text, state text, role text, member_count integer, is_owner boolean, is_member boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    r.id, r.code, r.name, r.created_by, r.created_at, r.duration_minutes,
    r.expires_at, r.ended_at, r.resumable_until, r.persistent, r.dormant_hours,
    r.av_level, r.max_members, r.transport_lock,
    r.media_kind, r.media_name, r.media_duration_ms, r.media_url, r.media_updated_at,
    r.media_position_ms, r.media_position_at,
    r.media_file_size, r.media_r2_key, r.media_upload_state, r.media_sharing_level,
    public.room_state(r),
    coalesce(m.role, case when r.created_by = (select auth.uid()) then 'host' else 'member' end),
    (select count(*)::int from public.room_members x where x.room_id = r.id),
    r.created_by = (select auth.uid()),
    m.user_id is not null
  from public.rooms r
  left join public.room_members m
    on m.room_id = r.id and m.user_id = (select auth.uid())
  where (select auth.uid()) is not null
    and r.pair_id is null
    and (m.user_id is not null or r.created_by = (select auth.uid()))
    and (
      public.room_state(r) in ('live', 'idle')
      or (
        r.created_by = (select auth.uid())
        and r.ended_at is not null
        and r.ended_at > now() - interval '24 hours'
      )
    )
  order by (public.room_state(r) = 'live') desc,
           (public.room_state(r) = 'idle') desc,
           r.created_at desc;
$function$;

CREATE OR REPLACE FUNCTION public.retire_room(p_room_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_room public.rooms;
begin
  update public.rooms r set
    ended_at = coalesce(r.ended_at, now()),
    resumable_until = case
      when r.persistent then null
      when r.dormant_hours > 0
        then greatest(r.expires_at, now()) + make_interval(hours => r.dormant_hours)
      else null
    end
  where r.id = p_room_id
  returning * into v_room;

  if v_room.id is null then
    return;
  end if;

  -- Clean up active R2 objects or incomplete multipart uploads
  if v_room.media_r2_key is not null or v_room.media_upload_id is not null then
    insert into public.pending_r2_deletions (r2_key, upload_id)
    values (v_room.media_r2_key, v_room.media_upload_id);

    update public.rooms set
      media_r2_key = null,
      media_upload_id = null,
      media_file_size = null,
      media_upload_state = 'none'
    where id = p_room_id;
  end if;

  -- Clear upload locks
  update public.profiles set
    active_upload_room_id = null,
    active_upload_started_at = null
  where active_upload_room_id = p_room_id;

  -- Our Room keeps its chat between sessions; the sweep prunes it by age.
  if v_room.pair_id is null then
    delete from public.messages where room_id = p_room_id;
  end if;

  if not v_room.persistent and v_room.resumable_until is null then
    delete from public.rooms where id = p_room_id;
  end if;
end $function$;

-- ---------------------------------------------------------------------------
-- 5. RPCs
-- ---------------------------------------------------------------------------
create or replace function public.pair_is_patron(p_pair_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.pair_members pm
    where pm.pair_id = p_pair_id and public.effective_tier(pm.user_id) = 'premium'
  );
$$;
revoke execute on function public.pair_is_patron(uuid) from public, anon, authenticated;
grant execute on function public.pair_is_patron(uuid) to service_role;

-- Signed-in, non-guest, not banned. Shared by every pairing write.
create or replace function public.assert_can_pair(p_uid uuid)
returns void
language plpgsql stable security definer set search_path = ''
as $$
begin
  if p_uid is null or not exists (select 1 from public.profiles where id = p_uid) then
    raise exception 'not_authenticated';
  end if;
  if public.effective_tier(p_uid) = 'guest' then
    raise exception 'sign_in_required';
  end if;
  if exists (select 1 from public.profile_moderation
             where user_id = p_uid and moderation_status = 'banned') then
    raise exception 'account_banned';
  end if;
end $$;
revoke execute on function public.assert_can_pair(uuid) from public, anon, authenticated;

create or replace function public.create_pair_invite()
returns public.pair_invites
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_inv public.pair_invites;
  v_code text;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  perform public.assert_can_pair(v_uid);

  if exists (select 1 from public.pair_members where user_id = v_uid) then
    raise exception 'already_paired';
  end if;

  -- An unexpired invite is reused, so "Share again" never mints a second code.
  select * into v_inv from public.pair_invites
    where inviter_id = v_uid and status = 'pending';
  if found then
    if v_inv.expires_at > now() then
      return v_inv;
    end if;
    update public.pair_invites set status = 'cancelled' where id = v_inv.id;
  end if;

  loop
    select string_agg(substr(v_alphabet, 1 + floor(random() * 32)::int, 1), '')
      into v_code from generate_series(1, 6);
    exit when not exists (select 1 from public.pair_invites where code = v_code);
  end loop;

  insert into public.pair_invites (code, inviter_id)
  values (v_code, v_uid)
  returning * into v_inv;
  return v_inv;
end $$;

create or replace function public.cancel_pair_invite()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  update public.pair_invites set status = 'cancelled'
    where inviter_id = auth.uid() and status = 'pending';
end $$;

-- What the accept screen shows. Opening a link as a signed-in person other than
-- the inviter also remembers them as the invite's most recent viewer.
create or replace function public.get_pair_invite(p_code text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_inv public.pair_invites;
  v_status text;
  v_inviter public.profiles;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_inv from public.pair_invites where code = upper(trim(p_code));
  if not found then
    raise exception 'invite_not_found';
  end if;

  v_status := case
    when v_inv.status = 'pending' and v_inv.expires_at <= now() then 'expired'
    else v_inv.status
  end;

  if v_status = 'pending'
     and v_inv.inviter_id <> v_uid
     and public.effective_tier(v_uid) <> 'guest'
     and v_inv.seen_by is distinct from v_uid then
    update public.pair_invites set seen_by = v_uid where id = v_inv.id;
  end if;

  select * into v_inviter from public.profiles where id = v_inv.inviter_id;
  return jsonb_build_object(
    'code', v_inv.code,
    'status', v_status,
    'is_mine', v_inv.inviter_id = v_uid,
    -- Someone who has since paired cannot be paired with, whatever the invite
    -- itself says: the accept screen reads this to say so up front.
    'inviter_paired', exists (select 1 from public.pair_members where user_id = v_inv.inviter_id),
    'created_at', v_inv.created_at,
    'expires_at', v_inv.expires_at,
    'inviter', jsonb_build_object(
      'id', v_inviter.id,
      'display_name', v_inviter.display_name,
      'avatar_url', v_inviter.avatar_url));
end $$;

-- The lobby banner: an invite this person opened but has not answered.
create or replace function public.my_pending_pair_invite()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'code', i.code,
    'created_at', i.created_at,
    'expires_at', i.expires_at,
    'inviter', jsonb_build_object(
      'id', p.id, 'display_name', p.display_name, 'avatar_url', p.avatar_url))
  from public.pair_invites i
  join public.profiles p on p.id = i.inviter_id
  where i.seen_by = (select auth.uid())
    and i.status = 'pending'
    and i.expires_at > now()
    and not exists (select 1 from public.pair_members where user_id = (select auth.uid()))
    and not exists (select 1 from public.pair_members where user_id = i.inviter_id)
  order by i.created_at desc
  limit 1;
$$;

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
  return v_pair;
end $$;

create or replace function public.my_pair()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_pair public.pairs;
  v_partner public.profiles;
  v_me public.profiles;
  v_room public.rooms;
begin
  if v_uid is null then
    return null;
  end if;

  select p.* into v_pair from public.pairs p
    join public.pair_members m on m.pair_id = p.id and m.user_id = v_uid;
  if not found then
    return null;
  end if;

  select pr.* into v_partner from public.profiles pr
    join public.pair_members m on m.user_id = pr.id
    where m.pair_id = v_pair.id and m.user_id <> v_uid;
  select * into v_me from public.profiles where id = v_uid;
  select * into v_room from public.rooms where pair_id = v_pair.id;

  return jsonb_build_object(
    'pair_id', v_pair.id,
    'since', v_pair.created_at,
    'reunion_on', v_pair.reunion_on,
    'reunion_label', v_pair.reunion_label,
    'patron', public.pair_is_patron(v_pair.id),
    'my_timezone', v_me.timezone,
    'room_id', v_room.id,
    'room_code', v_room.code,
    'partner', jsonb_build_object(
      'id', v_partner.id,
      'display_name', v_partner.display_name,
      'avatar_url', v_partner.avatar_url,
      'timezone', v_partner.timezone));
end $$;

create or replace function public.unpair()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_pair uuid;
  v_room uuid;
begin
  select pair_id into v_pair from public.pair_members where user_id = auth.uid();
  if v_pair is null then
    return;
  end if;
  select id into v_room from public.rooms where pair_id = v_pair;
  if v_room is not null then
    perform public.announce_room_ended(v_room, 'deleted');
  end if;
  delete from public.pairs where id = v_pair;
end $$;

create or replace function public.set_reunion(p_on date, p_label text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_pair uuid := public.my_pair_id();
begin
  if v_pair is null then
    raise exception 'not_paired';
  end if;
  update public.pairs set
    reunion_on = p_on,
    reunion_label = nullif(left(trim(coalesce(p_label, '')), 60), '')
  where id = v_pair;
end $$;

-- Create the pair's room on first use, start a new session when it is resting,
-- and make the caller a member. Both partners call this; it is idempotent.
create or replace function public.open_our_room()
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_pair uuid;
  v_room public.rooms;
  v_limits public.tier_limits;
  v_av text;
  v_code text;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_minutes constant int := 240;
begin
  perform public.assert_can_pair(v_uid);

  select pair_id into v_pair from public.pair_members where user_id = v_uid;
  if v_pair is null then
    raise exception 'not_paired';
  end if;

  select * into v_limits from public.tier_limits
    where tier = public.effective_tier(v_uid);

  -- Whichever partner has the better AV level sets it for the room.
  select l.av_level into v_av
  from public.pair_members pm
  join public.tier_limits l on l.tier = public.effective_tier(pm.user_id)
  where pm.pair_id = v_pair
  order by case l.av_level when 'video' then 2 when 'voice' then 1 else 0 end desc
  limit 1;

  select * into v_room from public.rooms where pair_id = v_pair for update;
  if not found then
    loop
      select string_agg(substr(v_alphabet, 1 + floor(random() * 32)::int, 1), '')
        into v_code from generate_series(1, 6);
      exit when not exists (select 1 from public.rooms where code = v_code);
    end loop;

    insert into public.rooms (
      code, name, created_by, pair_id, duration_minutes, expires_at, persistent,
      dormant_hours, av_level, max_members, media_kind, media_upload_state,
      media_sharing_level)
    values (
      v_code, 'Our Room', v_uid, v_pair, v_minutes,
      now() + make_interval(mins => v_minutes), true,
      0, coalesce(v_av, 'none'), 2, 'none', 'none', v_limits.media_sharing)
    returning * into v_room;
  elsif public.room_state(v_room) <> 'live' then
    update public.rooms set
      ended_at = null,
      resumable_until = null,
      duration_minutes = v_minutes,
      expires_at = now() + make_interval(mins => v_minutes),
      av_level = coalesce(v_av, 'none'),
      max_members = 2,
      media_sharing_level = v_limits.media_sharing
    where id = v_room.id
    returning * into v_room;
  end if;

  -- Partners are equals here: both are hosts, so either can choose what plays.
  -- Hosts cannot kick one another (kick_member refuses), so neither can remove
  -- the other, and succession on leave still has a host to fall back on.
  insert into public.room_members (room_id, user_id, role)
  values (v_room.id, v_uid, 'host')
  on conflict (room_id, user_id) do update set role = 'host';

  return v_room;
end $$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'create_pair_invite()', 'cancel_pair_invite()', 'get_pair_invite(text)',
    'my_pending_pair_invite()', 'accept_pair_invite(text)', 'my_pair()',
    'unpair()', 'set_reunion(date, text)', 'open_our_room()']
  loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
