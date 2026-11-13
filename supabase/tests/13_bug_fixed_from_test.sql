begin;
select plan(30);

-- ---- semver_gte -------------------------------------------------------------
select is(public.semver_gte('1.4.10', '1.4.9'), true, '1.4.10 is newer than 1.4.9, numerically');
select is(public.semver_gte('1.4.9', '1.4.10'), false, '1.4.9 is older than 1.4.10');
select is(public.semver_gte('1.4.2', '1.4.2'), true, 'equal versions are gte');
select is(public.semver_gte('2.0.0', '1.99.99'), true, 'the major part wins');
select is(public.semver_gte('1.4.2+88', '1.4.2'), true, 'build metadata is ignored');
select is(public.semver_gte('abc', '1.0.0'), null, 'malformed input is null, not an error');
select is(public.semver_gte('1.0', '1.0.0'), null, 'two parts are not a version');
select is(public.semver_gte(null, '1.0.0'), null, 'null in, null out');
select is(public.semver_gte('1.0.0', '99999999999.0.0'), null, 'absurdly long parts are unparsable, not an overflow');

-- ---- the table guards -------------------------------------------------------
create function pg_temp.mk_user() returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_id, false, 'u' || replace(v_id::text, '-', '') || '@example.test', '{}'::jsonb);
  return v_id;
end $$;

create temp table t (k text primary key, v uuid);
grant all on t to public;
insert into t values ('a', pg_temp.mk_user());

insert into public.bug_reports (code, user_id, category, note, context) values
  ('BUG-FFF1', (select v from t where k = 'a'), 'video', 'on 1.4.3', '{"app":{"version":"1.4.3"}}'),
  ('BUG-FFF2', (select v from t where k = 'a'), 'video', 'flat key', '{"app_version":"2.0.0"}'),
  ('BUG-FFF3', (select v from t where k = 'a'), 'video', 'unparsable', '{"app":{"version":"dev"}}'),
  ('BUG-FFF4', (select v from t where k = 'a'), 'video', 'no version', '{}'),
  ('BUG-FFF5', (select v from t where k = 'a'), 'chat', 'root', '{"app":{"version":"1.4.0"}}'),
  ('BUG-FFF6', (select v from t where k = 'a'), 'chat', 'follower on a newer build', '{"app":{"version":"1.9.0"}}');

select throws_ok($$update public.bug_reports set status = 'fixed', fixed_in = '1.4' where code = 'BUG-FFF4'$$,
  '23514', null, 'fixed_in must be X.Y.Z');
select throws_ok($$update public.bug_reports set status = 'fixed', fixed_in = 'v1.4.2' where code = 'BUG-FFF4'$$,
  '23514', null, 'a leading v is not a version');
select throws_ok($$update public.bug_reports set status = 'fixed', fixed_in = '1.4.2' where code = 'BUG-FFF1'$$,
  '23514', null, 'the fix cannot predate the build the report came from');
select lives_ok($$update public.bug_reports set status = 'fixed', fixed_in = '1.4.3' where code = 'BUG-FFF1'$$,
  'the same version as the report is fine');
select lives_ok($$update public.bug_reports set fixed_in = '1.4.4' where code = 'BUG-FFF1'$$,
  'a later version is fine');
select throws_ok($$update public.bug_reports set status = 'fixed', fixed_in = '1.9.0' where code = 'BUG-FFF2'$$,
  '23514', null, 'the flat app_version key is honoured too');
select lives_ok($$update public.bug_reports set status = 'fixed', fixed_in = '1.0.0' where code = 'BUG-FFF3'$$,
  'an unparsable reported version skips the guard');
select lives_ok($$update public.bug_reports set status = 'fixed', fixed_in = '1.0.0' where code = 'BUG-FFF4'$$,
  'a missing reported version skips the guard');

-- ---- the team RPC, as the service role ------------------------------------
set local role service_role;
select throws_ok($$select public.admin_set_bug_status('BUG-FFF5', 'fixed', 'v1')$$,
  '22023', 'fixed_in_invalid', 'the RPC refuses a version that is not X.Y.Z');
select throws_ok($$select public.admin_set_bug_status('BUG-FFF5', 'fixed', '1.3.9')$$,
  '22023', 'fixed_before_report', 'the RPC refuses a fix older than the report');
select lives_ok($$select public.admin_set_bug_status('BUG-FFF5', 'fixed', '1.4.2+88')$$,
  'the RPC accepts a build suffix');
select is((select fixed_in from public.bug_reports where code = 'BUG-FFF5'), '1.4.2',
  'and stores only X.Y.Z');

-- A follower reported on a newer build than the root's fix still mirrors it.
reset role;
update public.bug_reports set status = 'duplicate',
  duplicate_of = (select id from public.bug_reports where code = 'BUG-FFF5') where code = 'BUG-FFF6';
select is((select (status, fixed_in)::text from public.bug_reports where code = 'BUG-FFF6'), '(fixed,1.4.2)',
  'a follower inherits the root''s version even from a newer build');

-- Skipped release: re-setting fixed_in on a fixed row is allowed, up or down, and cascades.
set local role service_role;
select lives_ok($$select public.admin_set_bug_status('BUG-FFF5', 'fixed', '1.4.3')$$,
  'a fixed row can be re-fixed in a later version');
select is((select fixed_in from public.bug_reports where code = 'BUG-FFF6'), '1.4.3',
  'the new version cascades to its followers');
select lives_ok($$select public.admin_set_bug_status('BUG-FFF5', 'fixed', '1.4.1')$$,
  'and lowered again when the earlier build did ship');
select is((select fixed_in from public.bug_reports where code = 'BUG-FFF6'), '1.4.1',
  'which cascades too');
select throws_ok($$select public.admin_set_bug_status('BUG-FFF5', 'fixed', '1.3.0')$$,
  '22023', 'fixed_before_report', 'but never below the version the original came from');

reset role;

-- ---- deleting an account must not trip over its own followers ---------------
insert into t values ('x', pg_temp.mk_user()), ('y', pg_temp.mk_user());
insert into public.bug_reports (code, user_id, category, note) values
  ('BUG-GGG1', (select v from t where k = 'x'), 'chat', 'x owns the original'),
  ('BUG-GGG2', (select v from t where k = 'x'), 'chat', 'x also owns a follower'),
  ('BUG-GGG3', (select v from t where k = 'y'), 'chat', 'y follows x''s original');
update public.bug_reports set status = 'duplicate',
  duplicate_of = (select id from public.bug_reports where code = 'BUG-GGG1') where code in ('BUG-GGG2', 'BUG-GGG3');
select lives_ok($$delete from auth.users where id = (select v from t where k = 'x')$$,
  'deleting a user who owns both an original and its follower works');
select is((select count(*)::int from public.bug_reports where code in ('BUG-GGG1', 'BUG-GGG2')), 0,
  'their reports go with them');
select is((select (status, duplicate_of is null)::text from public.bug_reports where code = 'BUG-GGG3'), '(received,t)',
  'another user''s follower goes back to the queue as an ordinary report');

select * from finish();
rollback;
