begin;
select plan(8);

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
insert into t values ('guesser', pg_temp.mk_user()), ('other', pg_temp.mk_user());

-- A pair code is a bearer credential, so guessing at them is budgeted.
select pg_temp.act_as((select v from t where k = 'guesser'));
do $$
begin
  for i in 1..30 loop
    begin
      perform public.get_pair_invite('ZZZZZ' || (i % 10));
    exception when others then
      raise;
    end;
  end loop;
end $$;

select is((select count(*)::int from public.pair_code_lookups
           where user_id = (select v from t where k = 'guesser')),
  30, 'every look-up is counted, hit or miss');

select throws_ok($$ select public.get_pair_invite('ZZZZZZ') $$, 'too_many_attempts',
  'the 31st look-up in an hour is refused');
select throws_ok($$ select public.accept_pair_invite('ZZZZZZ') $$, 'too_many_attempts',
  'and so is accepting blind, which would otherwise skip the look-up');

-- The budget is the account's own.
select pg_temp.act_as((select v from t where k = 'other'));
select is((public.get_pair_invite('ZZZZZZ')) ->> 'status', 'not_found',
  'another account is unaffected, and a miss is an answer, not an error');
select is(public.accept_pair_invite('ZZZZZZ'), null::uuid,
  'a blind accept of a code that does not exist is an answer too');

-- It refills: look-ups older than an hour stop counting.
update public.pair_code_lookups set looked_up_at = now() - interval '61 minutes'
  where user_id = (select v from t where k = 'guesser');
select pg_temp.act_as((select v from t where k = 'guesser'));
select is((public.get_pair_invite('ZZZZZZ')) ->> 'status', 'not_found',
  'after the hour the budget is back');

-- Nobody can read or edit the ledger directly.
select is(has_table_privilege('authenticated', 'public.pair_code_lookups', 'select'), false,
  'the ledger is not readable by clients');
select is(has_function_privilege('authenticated', 'public.pair_code_throttle()', 'execute'), false,
  'nor can clients call the throttle themselves');

select * from finish();
rollback;
