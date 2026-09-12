begin;
select plan(12);

create function pg_temp.mk_user() returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_id, false, 'u' || replace(v_id::text, '-', '') || '@example.test', '{}'::jsonb);
  return v_id;
end $$;

create function pg_temp.act_as(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid)::text, true);
end $$;

create temp table t (k text primary key, v uuid);

do $$
declare
  v_host uuid;
  v_mem1 uuid;
  v_mem2 uuid;
  v_room public.rooms;
begin
  v_host := pg_temp.mk_user();
  v_mem1 := pg_temp.mk_user();
  v_mem2 := pg_temp.mk_user();
  insert into t values ('host', v_host), ('mem1', v_mem1), ('mem2', v_mem2);

  perform pg_temp.act_as(v_host);
  v_room := public.create_room('Assign host test', 60);
  insert into t values ('room', v_room.id);

  perform pg_temp.act_as(v_mem1);
  perform public.join_room(v_room.code);

  perform pg_temp.act_as(v_mem2);
  perform public.join_room(v_room.code);
end $$;

-- 1. Unauthenticated cannot assign host
do $$ begin perform set_config('request.jwt.claims', '', true); end $$;
select throws_ok(
  $$ select public.assign_host((select v from t where k = 'room'), (select v from t where k = 'mem1')) $$,
  'not_authenticated',
  'unauthenticated caller cannot assign host');

-- 2. Non-host cannot assign host
do $$ begin perform pg_temp.act_as((select v from t where k = 'mem1')); end $$;
select throws_ok(
  $$ select public.assign_host((select v from t where k = 'room'), (select v from t where k = 'mem2')) $$,
  'not_host',
  'a regular member cannot assign host');

-- 3. Host assigning to non-member fails
do $$
declare v_stranger uuid;
begin
  v_stranger := pg_temp.mk_user();
  insert into t values ('stranger', v_stranger);
  perform pg_temp.act_as((select v from t where k = 'host'));
end $$;
select throws_ok(
  $$ select public.assign_host((select v from t where k = 'room'), (select v from t where k = 'stranger')) $$,
  'target_not_in_room',
  'cannot assign host to a user not in the room');

-- 4. Host assigning null target fails
select throws_ok(
  $$ select public.assign_host((select v from t where k = 'room'), null) $$,
  'invalid_target',
  'cannot assign host to null target');

-- 5. Host assigns mem1 as host successfully
select lives_ok(
  $$ select public.assign_host((select v from t where k = 'room'), (select v from t where k = 'mem1')) $$,
  'host can explicitly assign another member as host');

-- 6. Verify mem1 is now host
select is(
  (select role from public.room_members
   where room_id = (select v from t where k = 'room')
     and user_id = (select v from t where k = 'mem1')),
  'host',
  'target member is now host');

-- 7. Verify former host is now member
select is(
  (select role from public.room_members
   where room_id = (select v from t where k = 'room')
     and user_id = (select v from t where k = 'host')),
  'member',
  'former host is demoted to member');

-- 8. Exactly one host in the room
select is(
  (select count(*) from public.room_members
   where room_id = (select v from t where k = 'room') and role = 'host'),
  1::bigint,
  'there is still exactly one host');

-- 9. Original creator (now member) can reclaim host
do $$ begin perform pg_temp.act_as((select v from t where k = 'host')); end $$;
select lives_ok(
  $$ select public.assign_host((select v from t where k = 'room'), (select v from t where k = 'host')) $$,
  'original creator can reclaim host even if currently a member');

select is(
  (select role from public.room_members
   where room_id = (select v from t where k = 'room')
     and user_id = (select v from t where k = 'host')),
  'host',
  'original creator is restored to host');

select is(
  (select role from public.room_members
   where room_id = (select v from t where k = 'room')
     and user_id = (select v from t where k = 'mem1')),
  'member',
  'previous host is demoted to member when creator reclaims');

-- 10. Assigned host leaves: no automatic succession
do $$
begin
  perform pg_temp.act_as((select v from t where k = 'host'));
  perform public.assign_host((select v from t where k = 'room'), (select v from t where k = 'mem1'));
  perform pg_temp.act_as((select v from t where k = 'mem1'));
  perform public.leave_room((select v from t where k = 'room'));
end $$;

select is(
  (select count(*) from public.room_members
   where room_id = (select v from t where k = 'room') and role = 'host'),
  0::bigint,
  'when assigned host leaves, no automatic succession occurs');

select * from finish();
rollback;
