-- Simplify room host handling logic:
-- 1. leave_room: The host leaving does not make someone else the host automatically.
-- 2. join_room: Entering an empty/hostless room does not promote non-creators to host.
--    Only the original host (created_by) reclaims host when the room has no host.
-- 3. assign_host: Allows the original host (or current host) to explicitly assign
--    the host role to another member.

-- ---------------------------------------------------------------------------
-- 1. leave_room
-- ---------------------------------------------------------------------------
create or replace function public.leave_room(p_room_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  delete from public.room_members
    where room_id = p_room_id and user_id = v_uid;
end $$;

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
  if v_uid is null then
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

  if public.room_state(v_room) = 'dormant' then
    raise exception 'room_dormant';
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
-- 3. assign_host
-- ---------------------------------------------------------------------------
create or replace function public.assign_host(
  p_room_id uuid,
  p_target_user_id uuid
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  if p_target_user_id is null then
    raise exception 'invalid_target';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    raise exception 'room_not_found';
  end if;

  if not public.is_room_live(p_room_id) then
    raise exception 'room_ended';
  end if;

  -- Caller must be in the room and be either the original creator or current host
  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = v_uid and (role = 'host' or v_uid = v_room.created_by)
  ) then
    raise exception 'not_host';
  end if;

  -- Target must be an existing member in the room
  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = p_target_user_id
  ) then
    raise exception 'target_not_in_room';
  end if;

  -- Demote current host(s) to 'member'
  update public.room_members
    set role = 'member'
    where room_id = p_room_id and role = 'host';

  -- Promote target user to 'host'
  update public.room_members
    set role = 'host'
    where room_id = p_room_id and user_id = p_target_user_id;
end $$;

revoke execute on function public.assign_host(uuid, uuid) from public, anon;
grant execute on function public.assign_host(uuid, uuid) to authenticated;
