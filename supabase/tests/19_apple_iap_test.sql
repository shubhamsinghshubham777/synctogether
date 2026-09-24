begin;
select plan(13);

create function pg_temp.mk_user(p_anon boolean default false) returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_id, p_anon, case when p_anon then null else 'u' || replace(v_id::text, '-', '') || '@example.test' end, '{}'::jsonb);
  return v_id;
end $$;

create function pg_temp.act_as(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid)::text, true);
end $$;

create temp table t (k text primary key, v uuid);
insert into t values ('a', pg_temp.mk_user()), ('b', pg_temp.mk_user()), ('g', pg_temp.mk_user(true));

select ok(
  not has_function_privilege('authenticated',
    'public.apply_apple_transaction(uuid, text, text, text, text, timestamptz, timestamptz, boolean, timestamptz)', 'EXECUTE'),
  'clients cannot apply apple transactions themselves');

select ok(
  not has_table_privilege('authenticated', 'public.apple_subscriptions', 'INSERT'),
  'clients cannot write apple_subscriptions');

select is(
  public.apply_apple_transaction(null, 'otx1', 'tx1', 'monthly', 'Sandbox',
    now() + interval '30 days', null, true, now() - interval '10 minutes'),
  'unbound', 'a transaction with no account token cannot create a row');

select is(
  public.apply_apple_transaction((select v from t where k = 'a'), 'otx1', 'tx1', 'monthly', 'Sandbox',
    now() + interval '30 days', null, true, now() - interval '10 minutes'),
  'applied', 'first verified purchase binds to the buyer');

select is(public.effective_tier((select v from t where k = 'a')), 'premium',
  'an unexpired apple subscription is premium');

select is(
  public.apply_apple_transaction((select v from t where k = 'b'), 'otx1', 'tx2', 'monthly', 'Sandbox',
    now() + interval '60 days', null, true, now() - interval '5 minutes'),
  'owned_elsewhere', 'a second account cannot take over the purchase');

select is(public.effective_tier((select v from t where k = 'b')), 'free',
  'the refused account stays free');

select is(
  public.apply_apple_transaction(null, 'otx1', 'tx0', 'monthly', 'Sandbox',
    now() - interval '1 day', null, false, now() - interval '20 minutes'),
  'stale', 'an older payload never overwrites a newer one');

select is(
  public.apply_apple_transaction(null, 'otx1', 'tx1', 'monthly', 'Sandbox',
    now() + interval '30 days', now() - interval '1 minute', false, now() - interval '1 minute'),
  'applied', 'a bound row accepts a newer notification without a token');

select is(public.effective_tier((select v from t where k = 'a')), 'free',
  'a refunded (revoked) subscription is not premium');

insert into public.apple_subscriptions (original_transaction_id, user_id, product_id, environment,
  latest_transaction_id, expires_at, signed_at)
values ('otx-guest', (select v from t where k = 'g'), 'monthly', 'Sandbox', 'txg',
  now() + interval '30 days', now());

select is(public.effective_tier((select v from t where k = 'g')), 'guest',
  'guests stay guests whatever rows they have');

insert into public.subscriptions (user_id, tier, source, current_period_end)
values ((select v from t where k = 'b'), 'premium', 'paddle', now() + interval '30 days');
insert into public.apple_subscriptions (original_transaction_id, user_id, product_id, environment,
  latest_transaction_id, expires_at, signed_at)
values ('otx-b', (select v from t where k = 'b'), 'annual', 'Sandbox', 'txb',
  now() + interval '1 year', now());

select pg_temp.act_as((select v from t where k = 'b'));
select is(public.my_premium_sources(), array['paddle', 'apple'],
  'both rails are reported when both entitle the caller');

select pg_temp.act_as((select v from t where k = 'a'));
select is(public.my_premium_sources(), array[]::text[],
  'a revoked apple row entitles nothing');

select * from finish();
rollback;
