-- Video trial: a free host's room can switch facecams to video for a few
-- minutes, once in the room's life, so free users get to feel the thing
-- Premium sells instead of reading about it.
--
-- Config, not constants (the tier_limits doctrine): `video_trial_minutes` is
-- how long a trial lasts and `video_trials_per_day` how many a host may start
-- in any rolling 24 hours. Zero turns either off. The code below never reads
-- the tier name.
--
-- The trial belongs to the room, like av_level: anyone in a free host's room
-- may start it, it counts against the *creator's* daily allowance, and
-- everyone in the room shares it. `resume_room` never clears
-- `video_trial_ends_at`, so ending and resuming a room is not a second trial.
--
-- Enforcement is the livekit-token function (it grants the camera only while
-- `video_trial_ends_at` is in the future, and only on an endpoint marked for
-- trials) plus `close_video_trials`, which queues a `revoke_camera` job for
-- av-cleanup so a client that ignores the clock still loses its camera.

alter table public.tier_limits
  add column video_trial_minutes int not null default 0 check (video_trial_minutes between 0 and 120),
  add column video_trials_per_day int not null default 0 check (video_trials_per_day >= 0);

update public.tier_limits set video_trial_minutes = 10, video_trials_per_day = 2 where tier = 'free';

alter table public.rooms
  add column video_trial_ends_at timestamptz,
  -- Set once close_video_trials has queued the camera revocation, so the
  -- per-minute job does each room exactly once.
  add column video_trial_closed boolean not null default false;

-- The ledger behind the daily cap. No foreign key to rooms on purpose:
-- deleting a room must not hand its trial back.
create table public.video_trial_grants (
  id bigint generated always as identity primary key,
  host_id uuid not null references auth.users (id) on delete cascade,
  room_id uuid not null,
  started_at timestamptz not null default now()
);
create index video_trial_grants_host_started_idx
  on public.video_trial_grants (host_id, started_at desc);

alter table public.video_trial_grants enable row level security;
revoke all on public.video_trial_grants from public, anon, authenticated;
grant all on public.video_trial_grants to service_role;

-- av-cleanup learns a second kind of job. Existing rows are removals.
alter table public.pending_av_cleanups
  add column kind text not null default 'remove' check (kind in ('remove', 'revoke_camera'));

-- Starts (or reports) the room's video trial. Refusals are normal answers in
-- `status`, never exceptions, so the client can map them to copy:
--   started | active   -> `ends_at` is set
--   not_eligible       -> the room already has video, or its creator's tier has no trial
--   trial_spent        -> this room used its trial
--   daily_cap          -> the creator has started their allowance in the last 24 h
--   room_ended         -> the room is over
create or replace function public.start_video_trial(p_room_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms;
  v_limits public.tier_limits;
  v_used int;
  v_ends timestamptz;
begin
  if v_uid is null or not public.is_room_member(p_room_id) then
    raise exception 'not_a_member';
  end if;

  -- Serialises two members pressing the camera at once.
  select * into v_room from public.rooms where id = p_room_id for update;
  if v_room.ended_at is not null or v_room.expires_at <= now() then
    return jsonb_build_object('status', 'room_ended');
  end if;
  if v_room.video_trial_ends_at is not null then
    if v_room.video_trial_ends_at > now() then
      return jsonb_build_object('status', 'active', 'ends_at', v_room.video_trial_ends_at);
    end if;
    return jsonb_build_object('status', 'trial_spent');
  end if;

  select * into v_limits from public.tier_limits
  where tier = public.effective_tier(v_room.created_by);
  if v_room.av_level <> 'voice' or coalesce(v_limits.video_trial_minutes, 0) = 0 then
    return jsonb_build_object('status', 'not_eligible');
  end if;

  select count(*) into v_used from public.video_trial_grants
  where host_id = v_room.created_by and started_at > now() - interval '24 hours';
  if v_used >= v_limits.video_trials_per_day then
    return jsonb_build_object('status', 'daily_cap');
  end if;

  v_ends := now() + make_interval(mins => v_limits.video_trial_minutes);
  update public.rooms set video_trial_ends_at = v_ends where id = p_room_id;
  insert into public.video_trial_grants (host_id, room_id) values (v_room.created_by, p_room_id);

  -- Fan-out only: the row is the truth, and clients refetch it on entry and
  -- on every resubscribe.
  begin
    perform realtime.send(
      jsonb_build_object(
        'senderId', v_uid::text,
        'timestamp', (extract(epoch from clock_timestamp()) * 1000)::bigint,
        'endsAt', v_ends),
      'video_trial_started',
      'room:' || p_room_id::text,
      true);
  exception when others then
    raise warning 'video_trial_started broadcast failed for %: %', p_room_id, sqlerrm;
  end;

  return jsonb_build_object('status', 'started', 'ends_at', v_ends);
end $$;

revoke all on function public.start_video_trial(uuid) from public, anon;
grant execute on function public.start_video_trial(uuid) to authenticated;

-- Per-minute: every trial that has run out gets its camera revocation queued
-- on the SFU, once.
create or replace function public.close_video_trials()
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  v_count int;
begin
  with closed as (
    update public.rooms
    set video_trial_closed = true
    where video_trial_ends_at is not null
      and video_trial_ends_at <= now()
      and not video_trial_closed
    returning id, ended_at
  )
  insert into public.pending_av_cleanups (room_id, kind)
  select id, 'revoke_camera' from closed where ended_at is null;
  get diagnostics v_count = row_count;
  -- The cap only looks back 24 hours; anything older is dead weight.
  delete from public.video_trial_grants where started_at < now() - interval '7 days';
  return v_count;
end $$;

revoke all on function public.close_video_trials() from public, anon, authenticated;
grant execute on function public.close_video_trials() to service_role;

do $$
begin
  perform cron.unschedule('close-video-trials');
exception when others then
  null;
end $$;

select cron.schedule('close-video-trials', '* * * * *', $$ select public.close_video_trials(); $$);
