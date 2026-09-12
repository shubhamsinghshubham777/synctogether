-- Migration: Remove dormant/napping room state
-- Simplifies room lifecycle: rooms are either 'live' or 'expired'.
-- Active rooms remain live until expiry. No intermediate dormant/napping state.

-- ---------------------------------------------------------------------------
-- 1. room_state
-- ---------------------------------------------------------------------------
create or replace function public.room_state(p_room public.rooms)
returns text
language sql stable set search_path = ''
as $$
  select case
    when p_room.ended_at is not null and not p_room.persistent then 'expired'
    when p_room.persistent and public.effective_tier(p_room.created_by) = 'premium' then 'live'
    when p_room.ended_at is not null then 'expired'
    when p_room.expires_at > now() then 'live'
    else 'expired'
  end;
$$;

-- ---------------------------------------------------------------------------
-- 2. join_room
-- ---------------------------------------------------------------------------
create or replace function public.join_room(p_code text)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms;
  v_count int;
  v_has_host boolean;
begin
  if v_uid is null or not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'not_authenticated';
  end if;

  select * into v_room from public.rooms where code = upper(trim(p_code));
  if not found then
    raise exception 'room_not_found';
  end if;

  if exists (select 1 from public.room_bans
             where room_id = v_room.id and user_id = v_uid) then
    raise exception 'room_banned';
  end if;

  if public.room_state(v_room) <> 'live' then
    raise exception 'room_ended';
  end if;

  select exists (select 1 from public.room_members
                 where room_id = v_room.id and role = 'host') into v_has_host;

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

  return v_room;
end $$;

-- ---------------------------------------------------------------------------
-- 3. list_my_rooms
-- ---------------------------------------------------------------------------
drop function if exists public.list_my_rooms();

create function public.list_my_rooms()
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
      public.room_state(r) = 'live'
      or (
        r.created_by = (select auth.uid())
        and r.ended_at is not null
        and r.ended_at > now() - interval '24 hours'
      )
    )
  order by (public.room_state(r) = 'live') desc, r.created_at desc;
$$;

revoke execute on function public.list_my_rooms() from public, anon;
grant execute on function public.list_my_rooms() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. retire_room
-- ---------------------------------------------------------------------------
create or replace function public.retire_room(p_room_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
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

  delete from public.messages where room_id = p_room_id;

  if not v_room.persistent and v_room.resumable_until is null then
    delete from public.rooms where id = p_room_id;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 5. sweep_rooms
-- ---------------------------------------------------------------------------
create or replace function public.sweep_rooms()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
begin
  for v_id in
    select id from public.rooms where ended_at is null and expires_at <= now()
  loop
    perform public.retire_room(v_id);
  end loop;

  -- Drop persistence for users who lapsed from premium
  update public.rooms r set
    persistent = false,
    resumable_until = now() + interval '7 days'
  where r.persistent
    and r.ended_at is not null
    and public.effective_tier(r.created_by) <> 'premium';

  delete from public.rooms r
  where r.ended_at is not null
    and not r.persistent
    and (r.resumable_until is null or r.resumable_until <= now());
end $$;

-- ---------------------------------------------------------------------------
-- 6. resume_room (compatibility wrapper)
-- ---------------------------------------------------------------------------
create or replace function public.resume_room(p_room_id uuid, p_minutes int)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_limits public.tier_limits;
  v_room public.rooms;
  v_min int;
begin
  if v_uid is null or not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'not_authenticated';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    raise exception 'room_not_found';
  end if;

  if v_room.created_by <> v_uid and not exists (
    select 1 from public.room_members where room_id = p_room_id and user_id = v_uid and role = 'host'
  ) then
    raise exception 'not_host';
  end if;

  select * into v_limits from public.tier_limits
    where tier = public.effective_tier(v_uid);

  v_min := coalesce(p_minutes, v_room.duration_minutes);
  if v_min is null or v_min < 5 or v_min > v_limits.max_session_minutes then
    raise exception 'invalid_duration';
  end if;

  update public.rooms set
    ended_at = null,
    resumable_until = null,
    duration_minutes = v_min,
    expires_at = now() + make_interval(mins => v_min),
    max_members = v_limits.max_members,
    av_level = v_limits.av_level,
    persistent = v_limits.persistent_room_cap > 0
  where id = p_room_id
  returning * into v_room;

  insert into public.room_members (room_id, user_id, role)
  values (p_room_id, v_uid, 'host')
  on conflict (room_id, user_id) do update set role = 'host';

  return v_room;
end $$;

-- ---------------------------------------------------------------------------
-- 7. create_room (updated to drop dormant references and ensure profile exists)
-- ---------------------------------------------------------------------------
create or replace function public.create_room(
  p_name text,
  p_duration_minutes int,
  p_staged_id uuid default null
)
returns public.rooms
language plpgsql security definer set search_path = ''
as $$
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
    where r.created_by = v_uid and public.room_state(r) = 'live';
  if v_held >= v_limits.max_live_rooms then
    if v_tier = 'guest' then
      raise exception 'guest_room_limit';
    end if;
    raise exception 'room_limit_reached';
  end if;

  if v_limits.persistent_room_cap > 0 then
    select count(*) into v_held from public.rooms r
      where r.created_by = v_uid and r.persistent;
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
end $$;

grant execute on function public.create_room(text, int, uuid) to authenticated;

