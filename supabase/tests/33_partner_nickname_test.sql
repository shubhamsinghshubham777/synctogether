begin;
select plan(14);

create function pg_temp.mk_user(p_name text) returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_id, false, 'u' || replace(v_id::text, '-', '') || '@example.test',
          jsonb_build_object('full_name', p_name));
  return v_id;
end $$;

create function pg_temp.act_as(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid)::text, true);
end $$;

create temp table t (k text primary key, v uuid);
create temp table c (k text primary key, v text);
insert into t values
  ('maya', pg_temp.mk_user('Maya Lin')),
  ('sam', pg_temp.mk_user('Sam Rivera')),
  ('lee', pg_temp.mk_user('Lee Park'));

-- Both have a device, or the server would not queue anything for them.
select pg_temp.act_as((select v from t where k = 'maya'));
select public.register_push_token('ios', 'maya-ios-token-0001', 'sandbox');
select pg_temp.act_as((select v from t where k = 'sam'));
select public.register_push_token('ios', 'sam-ios-token-00001', 'sandbox');

-- Maya and Sam pair; Lee is on his own.
select pg_temp.act_as((select v from t where k = 'maya'));
insert into c select 'code', (public.create_pair_invite()).code;
select pg_temp.act_as((select v from t where k = 'sam'));
select public.accept_pair_invite((select v from c where k = 'code'));

-- ---------------------------------------------------------------------------
-- Setting and reading it back
-- ---------------------------------------------------------------------------
select is((public.my_pair()) -> 'partner' ->> 'nickname', null, 'no nickname until one is set');

select public.set_partner_nickname('  Mayu  ');
select is((public.my_pair()) -> 'partner' ->> 'nickname', 'Mayu', 'it is stored trimmed and read back');
select is((public.my_pair()) -> 'partner' ->> 'display_name', 'Maya Lin', 'their own name is untouched');

-- ---------------------------------------------------------------------------
-- It is Sam's alone
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'maya'));
select is((public.my_pair()) -> 'partner' ->> 'nickname', null, 'Maya is not shown what Sam calls her');
select is((public.my_pair()) -> 'partner' ->> 'display_name', 'Sam Rivera', 'and sees his own name as ever');

set local role authenticated;
select throws_ok($$ select * from public.pair_nicknames $$, '42501', null,
  'the table is closed to clients, so it cannot be selected by the person it names');
reset role;

-- ---------------------------------------------------------------------------
-- It reaches the notifications Sam receives from Maya
-- ---------------------------------------------------------------------------
select public.call_partner();
select is((select title from public.push_outbox where kind = 'call'), 'Mayu is calling',
  'Sam is told "Mayu is calling", in his own words for her');

select pg_temp.act_as((select v from t where k = 'sam'));
select public.call_partner();
select is((select title from public.push_outbox where kind = 'call'
           and user_id = (select v from t where k = 'maya')), 'Sam Rivera is calling',
  'while Maya, who named nobody, is told his real name');

-- ---------------------------------------------------------------------------
-- Clearing, limits, and who may set one
-- ---------------------------------------------------------------------------
select public.set_partner_nickname('   ');
select is((public.my_pair()) -> 'partner' ->> 'nickname', null, 'a blank clears it');
select is((select count(*)::int from public.pair_nicknames), 0, 'and removes the row');

select throws_ok($$ select public.set_partner_nickname(repeat('x', 41)) $$, 'invalid_nickname',
  'over 40 characters is refused');
select lives_ok($$ select public.set_partner_nickname(repeat('x', 40)) $$, 'exactly 40 is fine');

select pg_temp.act_as((select v from t where k = 'lee'));
select throws_ok($$ select public.set_partner_nickname('Anyone') $$, 'not_paired',
  'someone with no partner has nobody to name');

-- ---------------------------------------------------------------------------
-- It goes with the pair
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'sam'));
select public.unpair();
select is((select count(*)::int from public.pair_nicknames), 0,
  'unpairing takes the nickname with it');

select * from finish();
rollback;
