begin;
select plan(18);

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

-- The RLS assertions below have to run as `authenticated`: as the owning
-- superuser, row security is bypassed and a policy test would pass whatever
-- the policy said. Reading the fixture ids back under that role needs this.
grant select on t to authenticated;

do $$
declare v_host uuid; v_a uuid; v_b uuid; v_room public.rooms;
begin
  v_host := pg_temp.mk_user();
  v_a := pg_temp.mk_user();
  v_b := pg_temp.mk_user();
  insert into t values ('host', v_host), ('a', v_a), ('b', v_b);

  perform pg_temp.act_as(v_host);
  v_room := public.create_room('Moderation room', 60);
  insert into t values ('room', v_room.id);

  perform pg_temp.act_as(v_a);
  perform public.join_room(v_room.code);
  perform pg_temp.act_as(v_b);
  perform public.join_room(v_room.code);

  -- b says something; a blocks them.
  insert into public.messages (room_id, sender_id, content)
  values (v_room.id, v_b, 'something unpleasant');

  perform pg_temp.act_as(v_a);
  perform public.block_user(v_b, v_room.id, 'harassment', 'something unpleasant');
end $$;

-- --- the block itself ------------------------------------------------------

select is(
  (select count(*)::int from public.user_blocks
     where blocker_id = (select v from t where k = 'a')
       and blocked_id = (select v from t where k = 'b')),
  1,
  'blocking records a durable row rather than a per-room, in-memory set');

-- Apple 1.2 asks that blocking notify the developer of the content. The block
-- files its own report so the common case - block and close the app - still
-- reaches the queue.
select is(
  (select count(*)::int from public.content_reports
     where reported_user_id = (select v from t where k = 'b') and source = 'blocked'),
  1,
  'blocking files an accompanying report');

select is(
  (select reason from public.content_reports
     where reported_user_id = (select v from t where k = 'b') and source = 'blocked'),
  'harassment',
  'the report carries the category the blocker picked');

select is(
  (select message_excerpt from public.content_reports
     where reported_user_id = (select v from t where k = 'b') and source = 'blocked'),
  'something unpleasant',
  'the excerpt is retained so the report is actionable');

-- --- the feed --------------------------------------------------------------

-- "Remove it from the user's feed instantly" has to survive the reload too,
-- so the block lives in the select policy rather than only in the client.
select pg_temp.act_as((select v from t where k = 'a'));
set local role authenticated;

select is(
  (select count(*)::int from public.messages where room_id = (select v from t where k = 'room')),
  0,
  'a blocked sender vanishes from chat history for the blocker');

reset role;
select pg_temp.act_as((select v from t where k = 'host'));
set local role authenticated;

select is(
  (select count(*)::int from public.messages where room_id = (select v from t where k = 'room')),
  1,
  'and stays visible to everybody else - a block is one-way');

reset role;

-- --- listing and undoing ---------------------------------------------------

select pg_temp.act_as((select v from t where k = 'a'));

select is(
  (select count(*)::int from public.my_blocked_users()),
  1,
  'the blocker can list who they blocked, so they can undo it');

select is(
  (select user_id from public.my_blocked_users()),
  (select v from t where k = 'b'),
  'the list names the right person');

select pg_temp.act_as((select v from t where k = 'host'));
select is(
  (select count(*)::int from public.my_blocked_users()),
  0,
  'and nobody else sees that list');

select pg_temp.act_as((select v from t where k = 'a'));
select lives_ok(
  $$ select public.unblock_user((select v from t where k = 'b')) $$,
  'unblocking works');

set local role authenticated;
select is(
  (select count(*)::int from public.messages where room_id = (select v from t where k = 'room')),
  1,
  'and the messages come back');
reset role;

-- Re-blocking does not bank a second report: the queue must not be paddable
-- by toggling a block on and off.
do $$
begin
  perform pg_temp.act_as((select v from t where k = 'a'));
  perform public.block_user((select v from t where k = 'b'), null, 'spam', null);
  perform public.block_user((select v from t where k = 'b'), null, 'spam', null);
end $$;

select is(
  (select count(*)::int from public.content_reports
     where reported_user_id = (select v from t where k = 'b') and source = 'blocked'),
  2,
  'a repeat block on an existing row files nothing further');

-- --- guards ----------------------------------------------------------------

select throws_ok(
  $$ select public.block_user((select v from t where k = 'a')) $$,
  'cannot_block_self',
  'you cannot block yourself');

select throws_ok(
  $$ select public.report_content((select v from t where k = 'b'), 'not_a_reason') $$,
  'invalid_reason',
  'the reason is an allow-list the server re-checks');

select throws_ok(
  $$ select public.report_content((select v from t where k = 'a'), 'spam') $$,
  'invalid_target',
  'you cannot report yourself');

-- --- privacy ---------------------------------------------------------------

-- A report is never read back by any client: not by the reporter, and
-- certainly not by the person reported. Triage happens under service_role.
select ok(
  not has_table_privilege('authenticated', 'public.content_reports', 'SELECT'),
  'reports are not readable by signed-in clients');

select ok(
  not has_table_privilege('authenticated', 'public.user_blocks', 'INSERT'),
  'blocks are written only through the RPC, so one can never land without its report');

select ok(
  has_function_privilege('authenticated', 'public.my_blocked_users()', 'EXECUTE'),
  'the block list survives the drop-and-recreate grant trap');

select * from finish();
rollback;
