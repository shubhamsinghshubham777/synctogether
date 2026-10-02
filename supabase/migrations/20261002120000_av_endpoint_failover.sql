-- AV endpoint failover. Every endpoint speaks the LiveKit protocol (LiveKit
-- Cloud, or a LiveKit server we run ourselves), so the client SDK never
-- changes - only which URL and signing key the token function hands out.
--
-- A room is pinned to exactly one endpoint, because members on two different
-- SFUs cannot see or hear each other. Moving a room re-pins it and broadcasts
-- `av_endpoint_changed` so members already connected follow it.
--
-- The endpoint list itself (urls, keys, secrets, priority order) lives in the
-- livekit-token function's secrets, never in the database. The function
-- passes the ids it knows to `pick_av_endpoint` in priority order.

alter table public.rooms add column av_endpoint text;

-- Cooldown per endpoint. Empty means healthy.
create table public.av_endpoint_state (
  endpoint text primary key,
  exhausted_until timestamptz not null,
  updated_at timestamptz not null default now()
);

-- One row per (endpoint, reporter). A single client with a bad network can
-- move its own room, but marking an endpoint down for *everyone* needs
-- `kAvStrikeQuorum` distinct accounts inside the strike window.
create table public.av_endpoint_strikes (
  endpoint text not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  at timestamptz not null default now(),
  primary key (endpoint, user_id)
);

alter table public.av_endpoint_state enable row level security;
alter table public.av_endpoint_strikes enable row level security;
revoke all on public.av_endpoint_state from public, anon, authenticated;
revoke all on public.av_endpoint_strikes from public, anon, authenticated;
grant all on public.av_endpoint_state to service_role;
grant all on public.av_endpoint_strikes to service_role;

-- Returns the endpoint the room should use, re-pinning it if its current one
-- is down or was just reported failing by p_user. Null means every endpoint
-- is exhausted - the client shows its "facecams are resting" state.
create or replace function public.pick_av_endpoint(
  p_room_id uuid,
  p_candidates text[],
  p_failed text default null,
  p_user uuid default null,
  p_force text default null
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_quorum constant int := 2;
  v_window constant interval := interval '10 minutes';
  v_cooldown constant interval := interval '30 minutes';
  v_current text;
  v_next text;
begin
  -- Serialises members of one room racing to re-pin it.
  select av_endpoint into v_current from public.rooms where id = p_room_id for update;
  if not found then
    return null;
  end if;

  if p_failed is not null and p_user is not null then
    insert into public.av_endpoint_strikes (endpoint, user_id)
    values (p_failed, p_user)
    on conflict (endpoint, user_id) do update set at = now();

    if (select count(*) from public.av_endpoint_strikes
        where endpoint = p_failed and at > now() - v_window) >= v_quorum then
      insert into public.av_endpoint_state (endpoint, exhausted_until)
      values (p_failed, now() + v_cooldown)
      on conflict (endpoint) do update
        set exhausted_until = excluded.exhausted_until, updated_at = now();
      delete from public.av_endpoint_strikes where endpoint = p_failed;
    end if;
  end if;

  -- Debug switching (the function only passes p_force when the deployment
  -- allows it): pin exactly where asked, healthy or not.
  if p_force is not null and p_force = any(p_candidates) then
    v_next := p_force;
  else
  -- First candidate, in the caller's priority order, that is neither cooling
  -- down nor the one this caller just failed on.
  select c.endpoint into v_next
  from unnest(p_candidates) with ordinality as c(endpoint, ord)
  where c.endpoint is distinct from p_failed
    and not exists (
      select 1 from public.av_endpoint_state s
      where s.endpoint = c.endpoint and s.exhausted_until > now())
  order by
    -- Stay put when the current pin is still usable: another member may
    -- already have moved the room, and hopping again would split it.
    (c.endpoint is distinct from v_current), c.ord
  limit 1;
  end if;

  if v_next is distinct from v_current and v_next is not null then
    update public.rooms set av_endpoint = v_next where id = p_room_id;
    if v_current is not null then
      begin
        perform realtime.send(
          jsonb_build_object(
            'senderId', 'server',
            'timestamp', (extract(epoch from clock_timestamp()) * 1000)::bigint,
            'endpoint', v_next),
          'av_endpoint_changed',
          'room:' || p_room_id::text,
          true);
      exception when others then
        raise warning 'av_endpoint_changed broadcast failed for %: %', p_room_id, sqlerrm;
      end;
    end if;
  end if;

  return v_next;
end $$;

revoke all on function public.pick_av_endpoint(uuid, text[], text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.pick_av_endpoint(uuid, text[], text, uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- SFU cleanup. Ending, retiring or deleting one of our rooms - and removing a
-- member from it - must happen on the LiveKit side too, on *every* endpoint,
-- since a room may have lived on several over its life. Same shape as
-- pending_r2_deletions: Postgres enqueues, the av-cleanup function drains,
-- a row is dropped for good at attempts >= 5.
--
-- Without the participant half, a kicked or banned member stayed in the call
-- on their already-minted token: deleting the membership row ejects nobody
-- from an SFU, the same reason `member_kicked` exists for Realtime.

create table public.pending_av_cleanups (
  id bigint generated always as identity primary key,
  room_id uuid not null,
  user_id uuid,              -- null = delete the whole SFU room
  attempts int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.pending_av_cleanups enable row level security;
revoke all on public.pending_av_cleanups from public, anon, authenticated;
grant all on public.pending_av_cleanups to service_role;

create or replace function public.enqueue_av_room_cleanup()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.ended_at is null then
      insert into public.pending_av_cleanups (room_id) values (old.id);
    end if;
    return old;
  end if;
  if old.ended_at is null and new.ended_at is not null then
    insert into public.pending_av_cleanups (room_id) values (new.id);
  end if;
  return new;
end $$;

create trigger rooms_av_cleanup_on_end
after update of ended_at on public.rooms
for each row execute function public.enqueue_av_room_cleanup();

create trigger rooms_av_cleanup_on_delete
after delete on public.rooms
for each row execute function public.enqueue_av_room_cleanup();

-- Covers kick, ban and leave alike: whoever is no longer a member is no
-- longer in the call. Skipped while the room itself is going, which already
-- queues the whole-room delete.
create or replace function public.enqueue_av_member_cleanup()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (select 1 from public.rooms r where r.id = old.room_id and r.ended_at is null) then
    insert into public.pending_av_cleanups (room_id, user_id) values (old.room_id, old.user_id);
  end if;
  return old;
end $$;

create trigger room_members_av_cleanup
after delete on public.room_members
for each row execute function public.enqueue_av_member_cleanup();

-- Kicks the av-cleanup function when there is work, exactly like
-- invoke_r2_cleanup, and inert in the same way until an operator sets
-- app_settings.av_cleanup.endpoint_url.
insert into public.app_settings (key, value)
values ('av_cleanup', '{"enabled": true, "endpoint_url": null, "service_role_key": null}'::jsonb)
on conflict (key) do nothing;

create or replace function public.invoke_av_cleanup()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_settings jsonb;
  v_endpoint text;
  v_auth text;
begin
  if not exists (select 1 from public.pending_av_cleanups) then
    return;
  end if;
  select value into v_settings from public.app_settings where key = 'av_cleanup';
  if not coalesce((v_settings->>'enabled')::boolean, true) then
    return;
  end if;
  v_endpoint := nullif(trim(v_settings->>'endpoint_url'), '');
  v_auth := nullif(trim(v_settings->>'service_role_key'), '');
  if v_endpoint is not null then
    perform net.http_post(
      url := v_endpoint,
      headers := jsonb_build_object('Content-Type', 'application/json')
        || case when v_auth is not null
             then jsonb_build_object('Authorization', 'Bearer ' || v_auth)
             else '{}'::jsonb end,
      body := '{}'::jsonb);
  end if;
exception when others then
  raise warning 'invoke_av_cleanup failed: %', sqlerrm;
end $$;

revoke all on function public.invoke_av_cleanup() from public, anon, authenticated;
grant execute on function public.invoke_av_cleanup() to service_role;

do $$
begin
  perform cron.unschedule('invoke-av-cleanup');
exception when others then
  null;
end $$;

select cron.schedule('invoke-av-cleanup', '* * * * *', $$ select public.invoke_av_cleanup(); $$);
