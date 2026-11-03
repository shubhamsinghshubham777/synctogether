begin;
select plan(8);

select is(
  (select count(*)::int from cron.job where jobname = 'minutely-maintenance' and schedule = '* * * * *'),
  1,
  'one per-minute job runs the housekeeping');

select is(
  (select count(*)::int from cron.job
    where jobname in ('sweep-rooms', 'invoke-av-cleanup', 'close-video-trials')),
  0,
  'the three jobs it replaced are gone, or each minute would log them twice');

select is(
  (select count(*)::int from cron.job where jobname = 'invoke-r2-cleanup'),
  1,
  'the five-minute R2 job is untouched');

select ok(
  not has_function_privilege('authenticated', 'public.minutely_maintenance()', 'EXECUTE')
    and not has_function_privilege('anon', 'public.minutely_maintenance()', 'EXECUTE'),
  'housekeeping belongs to cron, not to clients');

select ok(
  has_function_privilege('service_role', 'public.minutely_maintenance()', 'EXECUTE'),
  'service_role can still run it by hand');

select lives_ok(
  $$ select public.minutely_maintenance() $$,
  'a run completes');

-- The wrapper must still do sweep_rooms' work: an expired room gets retired.
insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
values ('00000000-0000-0000-0000-0000000000a1', false, 'maint@example.test', '{}'::jsonb);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1"}', true);
create temp table made on commit drop as select id from public.create_room('Sweep me', 60);
grant select on made to authenticated;
reset role;

update public.rooms set expires_at = now() - interval '1 minute' where id = (select id from made);
select public.minutely_maintenance();
select ok(
  (select ended_at is not null from public.rooms where id = (select id from made)),
  'an expired room is retired through the wrapper');

select is(
  (select count(*)::int from cron.job where jobname = 'prune-cron-history' and command ilike '%job_run_details%'),
  1,
  'cron history is pruned, or its own run log outgrows the data it serves');

select * from finish();
rollback;
