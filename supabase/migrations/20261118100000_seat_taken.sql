-- Someone took a seat: one push to a host who is not in their room.
--
--   * rooms.host_seen_at is the host's heartbeat. Presence lives in Realtime,
--     which Postgres cannot ask, so the host's client pings room_host_ping
--     every 45 s while it is in the room and in front. "Away" is no ping for
--     90 s (a phone put down with the app still open counts as away once the
--     OS suspends it) or having left.
--   * rooms.seat_taken_sent_at makes it once per session: claimed inside
--     join_room, cleared when a dead session is started again.
--   * push_prefs.seat_taken (default on) gates the kind. Quiet hours apply:
--     claim_push_batch exempts only calls.
--   * Everything else in join_room is unchanged from 20261107100000_pairing.sql.
--     Our Room (pair_id set) never sends this: it has its own call.

alter table public.rooms
  add column if not exists host_seen_at timestamptz,
  add column if not exists seat_taken_sent_at timestamptz;

alter table public.push_prefs
  add column if not exists seat_taken boolean not null default true;

create or replace function public.push_kind_enabled(p_user uuid, p_kind text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select case
    when p_kind = 'call' then coalesce(p.calls, true)
    when p_kind like 'date_night%' then coalesce(p.date_nights, true)
    when p_kind = 'reunion' then coalesce(p.reunion, true)
    when p_kind = 'seat_taken' then coalesce(p.seat_taken, true)
    else true
  end
  from (select 1) x
  left join public.push_prefs p on p.user_id = p_user;
$$;
revoke execute on function public.push_kind_enabled(uuid, text) from public, anon, authenticated;

create or replace function public.my_push_prefs()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'calls', coalesce(p.calls, true),
    'date_nights', coalesce(p.date_nights, true),
    'reunion', coalesce(p.reunion, true),
    'quiet_hours', coalesce(p.quiet_hours, true),
    'seat_taken', coalesce(p.seat_taken, true))
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
  if p_key not in ('calls', 'date_nights', 'reunion', 'quiet_hours', 'seat_taken') then
    raise exception 'invalid_pref';
  end if;
  insert into public.push_prefs (user_id) values (auth.uid()) on conflict do nothing;
  execute format('update public.push_prefs set %I = $1 where user_id = $2', p_key)
    using p_value, auth.uid();
end $$;

-- The host's heartbeat. Only the owner can move it.
create or replace function public.room_host_ping(p_room_id uuid)
returns void
language sql security definer set search_path = ''
as $$
  update public.rooms set host_seen_at = now()
   where id = p_room_id and created_by = (select auth.uid());
$$;
revoke execute on function public.room_host_ping(uuid) from public, anon;
grant execute on function public.room_host_ping(uuid) to authenticated;

-- Leaving is the clearest way to be away.
create or replace function public.leave_room(p_room_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  delete from public.room_members
    where room_id = p_room_id and user_id = v_uid;
  update public.rooms set host_seen_at = null
    where id = p_room_id and created_by = v_uid;
end $$;

-- A session starting again (resume_room, a saved room waking up) is a new
-- chance to tell its host. Extending a running session is not.
create or replace function public.rooms_reset_seat_taken()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if old.expires_at <= now() and new.expires_at > now() then
    new.seat_taken_sent_at := null;
  end if;
  return new;
end $$;

drop trigger if exists rooms_reset_seat_taken on public.rooms;
create trigger rooms_reset_seat_taken
  before update of expires_at on public.rooms
  for each row execute function public.rooms_reset_seat_taken();

create or replace function public.join_room(p_code text)
returns public.rooms
language plpgsql security definer set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms;
  v_state text;
  v_count int;
  v_has_host boolean;
  v_was_member boolean;
  v_joiner text;
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
    if v_uid = v_room.created_by then
      update public.rooms set host_seen_at = now() where id = v_room.id;
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

  -- The owner walking in is the host being present, not someone waiting for them.
  -- Our Room has its own call; it never sends this.
  if v_uid = v_room.created_by then
    update public.rooms set host_seen_at = now() where id = v_room.id;
  elsif v_room.pair_id is null
        and v_room.seat_taken_sent_at is null
        and (v_room.host_seen_at is null or v_room.host_seen_at < now() - interval '90 seconds') then
    -- The first person to sit down in a room whose host is not there, once per
    -- session. Claimed before queueing so two joins at once cannot both ring.
    update public.rooms set seat_taken_sent_at = now()
      where id = v_room.id and seat_taken_sent_at is null;
    if found then
      select coalesce(nullif(trim(display_name), ''), 'Someone') into v_joiner
        from public.profiles where id = v_uid;
      perform public.enqueue_push(
        v_room.created_by, 'seat_taken',
        coalesce(v_joiner, 'Someone') || ' took a seat',
        v_room.name || ' has someone waiting. Tap to join them.',
        jsonb_build_object('route', '/lobby/room/' || v_room.id::text, 'room_id', v_room.id),
        now(), now() + interval '2 hours', 'seat:' || v_room.id::text);
    end if;
  end if;

  return v_room;
end $function$;
