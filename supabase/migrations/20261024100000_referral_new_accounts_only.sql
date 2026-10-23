-- Migration: only a genuinely new account is credited as somebody's referral.
--
-- join_room stamped profiles.referred_by for any account that was not
-- currently in a room and had no referrer yet. Leaving a room deletes the
-- membership row, so "not in a room" is true of almost every established user:
-- an old account joining a friend's room was credited to that friend, and the
-- referral counts the marketing team reads ran high.
--
-- The stamp now also requires the profile to be under a day old. Everything
-- else in join_room is unchanged from 20261012120000_idle_persistent_rooms.sql.

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

  if not v_was_member
     and v_room.created_by <> v_uid
     and exists (select 1 from public.profiles
                  where id = v_uid and created_at > now() - interval '1 day') then
    update public.profiles
       set referred_by = v_room.created_by, updated_at = now()
     where id = v_uid and referred_by is null;
  end if;

  return v_room;
end $$;
