-- Migration: persistent (premium) rooms rest as 'idle' between sessions.
--
-- Before this, room_state() called a persistent premium room 'live' forever,
-- even after sweep_rooms had retired its session (chat wiped, media cleared,
-- ended_at stamped). The lobby showed it live, join_room let people in, and the
-- room screen then bounced them with the "ended" dialog because ended_at was
-- set. Nothing could start a new session: resume_room only ran for 'dormant',
-- a state that no longer exists.
--
-- A persistent room now has two honest states: 'live' (a session is running)
-- and 'idle' (the room is kept, nobody is watching, the host can start a new
-- session). Idle rooms do not count against max_live_rooms, only against
-- persistent_room_cap.

-- ---------------------------------------------------------------------------
-- 1. room_state
-- ---------------------------------------------------------------------------
create or replace function public.room_state(p_room public.rooms)
returns text
language sql stable set search_path = ''
as $$
  select case
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

-- ---------------------------------------------------------------------------
-- 2. join_room: an idle room has no session to join. Built on the latest
--    definition (profile_moderation migration): account ban, admin room ban,
--    referral stamp all stay.
-- ---------------------------------------------------------------------------
create or replace function public.join_room(p_code text)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
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

  if not v_was_member and v_room.created_by <> v_uid then
    update public.profiles
       set referred_by = v_room.created_by, updated_at = now()
     where id = v_uid and referred_by is null;
  end if;

  return v_room;
end $$;

-- ---------------------------------------------------------------------------
-- 3. list_my_rooms: idle rooms are listed (same return type, no drop needed)
-- ---------------------------------------------------------------------------
create or replace function public.list_my_rooms()
returns table (
  id uuid,
  code text,
  name text,
  created_by uuid,
  created_at timestamptz,
  duration_minutes int,
  expires_at timestamptz,
  ended_at timestamptz,
  resumable_until timestamptz,
  persistent boolean,
  dormant_hours int,
  av_level text,
  max_members int,
  transport_lock boolean,
  media_kind text,
  media_name text,
  media_duration_ms bigint,
  media_url text,
  media_updated_at timestamptz,
  media_position_ms bigint,
  media_position_at timestamptz,
  media_file_size bigint,
  media_r2_key text,
  media_upload_state text,
  media_sharing_level text,
  state text,
  role text,
  member_count int,
  is_owner boolean,
  is_member boolean
)
language sql stable security definer set search_path = ''
as $$
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
$$;

revoke execute on function public.list_my_rooms() from public, anon;
grant execute on function public.list_my_rooms() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. resume_room: start a new session on an idle or still-resumable room
--
-- The previous body had no state check at all, so the host of a *live* room
-- could call it to reset expires_at to now + max_session_minutes as often as
-- they liked - an unlimited extension that bypassed max_total_session_minutes
-- and a guest's one-hour limit. It also skipped the live-room and persistent
-- caps that create_room enforces.
-- ---------------------------------------------------------------------------
create or replace function public.resume_room(p_room_id uuid, p_minutes int)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
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
    where r.created_by = v_uid and r.id <> p_room_id and public.room_state(r) = 'live';
  if v_held >= v_limits.max_live_rooms then
    if v_tier = 'guest' then
      raise exception 'guest_room_limit';
    end if;
    raise exception 'room_limit_reached';
  end if;

  v_persist := v_limits.persistent_room_cap > 0;
  if v_persist and not v_room.persistent then
    select count(*) into v_held from public.rooms r
      where r.created_by = v_uid and r.persistent and r.id <> p_room_id;
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
end $$;

revoke execute on function public.resume_room(uuid, int) from public, anon;
grant execute on function public.resume_room(uuid, int) to authenticated;
