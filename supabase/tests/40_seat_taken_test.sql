begin;
select plan(16);

create function pg_temp.mk_user(p_name text) returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_id, false, 'u' || replace(v_id::text, '-', '') || '@example.test',
          jsonb_build_object('full_name', p_name));
  update public.profiles set display_name = p_name where id = v_id;
  -- A device to reach: enqueue_push queues nothing for a person with no token.
  insert into public.push_tokens (user_id, platform, token) values (v_id, 'ios', 'tok-' || v_id::text);
  return v_id;
end $$;

create function pg_temp.act_as(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid)::text, true);
end $$;

-- A room by a fresh host, who then steps out (leaves), as in "shared the link and put the phone down".
create function pg_temp.mk_room(p_host uuid, p_name text) returns public.rooms
language plpgsql as $$
declare v_room public.rooms;
begin
  perform pg_temp.act_as(p_host);
  v_room := public.create_room(p_name, 60);
  return v_room;
end $$;

create function pg_temp.queued(p_host uuid) returns bigint
language sql as $$
  select count(*) from public.push_outbox where user_id = p_host and kind = 'seat_taken';
$$;

create temp table t (k text primary key, v uuid);
create temp table c (k text primary key, v text);

do $$
declare v_host uuid; v_priya uuid; v_jo uuid; v_room public.rooms;
begin
  v_host := pg_temp.mk_user('Maya');
  v_priya := pg_temp.mk_user('Priya');
  v_jo := pg_temp.mk_user('Jo');
  insert into t values ('host', v_host), ('priya', v_priya), ('jo', v_jo);
  v_room := pg_temp.mk_room(v_host, 'Friday Horror Club');
  insert into t values ('room', v_room.id);
  insert into c values ('code', v_room.code);
  perform pg_temp.act_as(v_host);
  perform public.leave_room(v_room.id); -- the host steps away
end $$;

-- 1. The first person to sit down in an empty-hosted room rings the host once.
do $$ begin
  perform pg_temp.act_as((select v from t where k = 'priya'));
  perform public.join_room((select v from c where k = 'code'));
end $$;

select is(pg_temp.queued((select v from t where k = 'host')), 1::bigint,
  'the first joiner queues exactly one seat_taken for the host');

select is(
  (select title from public.push_outbox where kind = 'seat_taken' limit 1),
  'Priya took a seat', 'it names who sat down');

select is(
  (select body from public.push_outbox where kind = 'seat_taken' limit 1),
  'Friday Horror Club has someone waiting. Tap to join them.', 'and says where');

select is(
  (select data ->> 'route' from public.push_outbox where kind = 'seat_taken' limit 1),
  '/lobby/room/' || (select v from t where k = 'room')::text,
  'the tap opens the room');

-- 2. A second joiner in the same session does not ring again.
do $$ begin
  perform pg_temp.act_as((select v from t where k = 'jo'));
  perform public.join_room((select v from c where k = 'code'));
end $$;

select is(pg_temp.queued((select v from t where k = 'host')), 1::bigint,
  'a second joiner does not queue another');

-- 3. Rejoining as an existing member does not either.
do $$ begin
  perform pg_temp.act_as((select v from t where k = 'priya'));
  perform public.join_room((select v from c where k = 'code'));
end $$;

select is(pg_temp.queued((select v from t where k = 'host')), 1::bigint,
  'an existing member rejoining is not news');

-- 4. The host walking into their own room is not someone waiting for them.
do $$
declare v_host2 uuid; v_room public.rooms;
begin
  v_host2 := pg_temp.mk_user('Sam');
  insert into t values ('host2', v_host2);
  v_room := pg_temp.mk_room(v_host2, 'Sam''s room');
  insert into t values ('room2', v_room.id);
  insert into c values ('code2', v_room.code);
  perform pg_temp.act_as(v_host2);
  perform public.leave_room(v_room.id);
  perform public.join_room(v_room.code);
end $$;

select is(pg_temp.queued((select v from t where k = 'host2')), 0::bigint,
  'the host joining their own room queues nothing');

select isnt(
  (select host_seen_at from public.rooms where id = (select v from t where k = 'room2')), null,
  'and counts as the host being present');

-- 5. A host who is present (pinging) is not rung.
do $$ begin
  perform pg_temp.act_as((select v from t where k = 'host2'));
  perform public.room_host_ping((select v from t where k = 'room2'));
  perform pg_temp.act_as((select v from t where k = 'jo'));
  perform public.join_room((select v from c where k = 'code2'));
end $$;

select is(pg_temp.queued((select v from t where k = 'host2')), 0::bigint,
  'a host who is present is not rung');

-- 6. Only the owner can move the heartbeat.
do $$ begin
  update public.rooms set host_seen_at = now() - interval '1 hour'
    where id = (select v from t where k = 'room2');
  perform pg_temp.act_as((select v from t where k = 'jo'));
  perform public.room_host_ping((select v from t where k = 'room2'));
end $$;

select ok(
  (select host_seen_at < now() - interval '30 minutes' from public.rooms
    where id = (select v from t where k = 'room2')),
  'a member cannot fake the host being there');

-- 7. Leaving clears the heartbeat.
do $$ begin
  perform pg_temp.act_as((select v from t where k = 'host2'));
  perform public.room_host_ping((select v from t where k = 'room2'));
  perform public.leave_room((select v from t where k = 'room2'));
end $$;

select is(
  (select host_seen_at from public.rooms where id = (select v from t where k = 'room2')), null,
  'the host leaving clears their heartbeat');

-- 8. A stale heartbeat counts as away: a new room, host pinged long ago.
do $$
declare v_host3 uuid; v_room public.rooms;
begin
  v_host3 := pg_temp.mk_user('Lee');
  insert into t values ('host3', v_host3);
  v_room := pg_temp.mk_room(v_host3, 'Lee''s room');
  insert into t values ('room3', v_room.id);
  insert into c values ('code3', v_room.code);
  update public.rooms set host_seen_at = now() - interval '5 minutes' where id = v_room.id;
  perform pg_temp.act_as((select v from t where k = 'priya'));
  perform public.join_room(v_room.code);
end $$;

select is(pg_temp.queued((select v from t where k = 'host3')), 1::bigint,
  'no heartbeat for 90 s counts as away, even without leaving');

-- 9. The switch: off means nothing is queued.
do $$
declare v_host4 uuid; v_room public.rooms;
begin
  v_host4 := pg_temp.mk_user('Kit');
  insert into t values ('host4', v_host4);
  perform pg_temp.act_as(v_host4);
  perform public.set_push_pref('seat_taken', false);
  v_room := pg_temp.mk_room(v_host4, 'Kit''s room');
  perform public.leave_room(v_room.id);
  perform pg_temp.act_as((select v from t where k = 'priya'));
  perform public.join_room(v_room.code);
end $$;

select is(pg_temp.queued((select v from t where k = 'host4')), 0::bigint,
  'a host who turned it off is not rung');

select is(
  (select (public.my_push_prefs() ->> 'seat_taken')), 'true',
  'the preference defaults on (read as someone who never set one)');

-- 10. A restarted session can ring again.
do $$ begin
  update public.rooms set seat_taken_sent_at = now(), expires_at = now() - interval '1 minute'
    where id = (select v from t where k = 'room3');
  update public.rooms set expires_at = now() + interval '1 hour'
    where id = (select v from t where k = 'room3');
end $$;

select is(
  (select seat_taken_sent_at from public.rooms where id = (select v from t where k = 'room3')), null,
  'starting a dead session again clears the once-per-session mark');

-- 11. Extending a running session does not.
do $$ begin
  update public.rooms set seat_taken_sent_at = now()
    where id = (select v from t where k = 'room3');
  update public.rooms set expires_at = expires_at + interval '30 minutes'
    where id = (select v from t where k = 'room3');
end $$;

select isnt(
  (select seat_taken_sent_at from public.rooms where id = (select v from t where k = 'room3')), null,
  'extending a running session keeps it');

select * from finish();
rollback;
