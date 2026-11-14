begin;
select plan(9);

create function pg_temp.mk_user(p_name text, p_anon boolean default false) returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_id, p_anon,
          case when p_anon then null else 'u' || replace(v_id::text, '-', '') || '@example.test' end,
          jsonb_build_object('full_name', p_name));
  return v_id;
end $$;

create function pg_temp.act_as(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid)::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

create temp table t (k text primary key, v uuid);
grant all on t to authenticated;
insert into t values ('maya', pg_temp.mk_user('Maya Lin')), ('guest', pg_temp.mk_user(null, true));

select is((select onboarded_at from public.profiles where id = (select v from t where k = 'maya')),
  null, 'a brand-new account has not been onboarded');

select pg_temp.act_as((select v from t where k = 'maya'));
select throws_ok($$ update public.profiles set onboarded_at = now() where id = auth.uid() $$,
  '42501', null, 'the flag is not directly writable by the client');

select isnt(public.complete_onboarding('  Maya  '), null, 'finishing returns the timestamp');
select is((select display_name from public.profiles where id = auth.uid()), 'Maya',
  'the chosen name is saved, trimmed');

-- Back-date it, then finish again: the first timestamp is kept and a null name changes nothing.
reset role;
update public.profiles set onboarded_at = '2026-01-01' where id = (select v from t where k = 'maya');
select pg_temp.act_as((select v from t where k = 'maya'));
select is(public.complete_onboarding(null), '2026-01-01'::timestamptz, 'finishing twice keeps the first time');
select is((select display_name from public.profiles where id = auth.uid()), 'Maya',
  'skipping the name keeps the current one');

select throws_ok($$ select public.complete_onboarding(repeat('x', 41)) $$, '22001', null,
  'names over 40 characters are refused');

select pg_temp.act_as((select v from t where k = 'guest'));
select lives_ok($$ select public.complete_onboarding(null) $$, 'guests can finish too');

reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;
select throws_ok($$ select public.complete_onboarding(null) $$, '42501', null,
  'anon cannot call it');

select * from finish();
rollback;
