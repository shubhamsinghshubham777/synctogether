begin;
select plan(9);

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
    'public.apply_microsoft_subscription(uuid, text, text, text, timestamptz, timestamptz, boolean, timestamptz)', 'EXECUTE'),
  'clients cannot apply microsoft subscriptions themselves');

select ok(not has_table_privilege('authenticated', 'public.microsoft_subscriptions', 'INSERT'),
  'clients cannot write microsoft_subscriptions');

select is(
  public.apply_microsoft_subscription(null, 'p1', 'prod', 'sku', now() + interval '30 days', null, true, now() - interval '10 minutes'),
  'unbound', 'a purchase with no account cannot create a row');

select is(
  public.apply_microsoft_subscription((select v from t where k = 'a'), 'p1', 'prod', 'sku',
    now() + interval '30 days', null, true, now() - interval '10 minutes'),
  'applied', 'first verified purchase binds to the buyer');

select is(public.effective_tier((select v from t where k = 'a')), 'premium',
  'an unexpired microsoft subscription is premium');

select is(
  public.apply_microsoft_subscription((select v from t where k = 'b'), 'p1', 'prod', 'sku',
    now() + interval '60 days', null, true, now() - interval '5 minutes'),
  'owned_elsewhere', 'a second account cannot take over the purchase');

select is(
  public.apply_microsoft_subscription((select v from t where k = 'a'), 'p1', 'prod', 'sku',
    now() - interval '1 day', null, false, now() - interval '20 minutes'),
  'stale', 'an older observation never overwrites a newer one');

select is(
  public.apply_microsoft_subscription((select v from t where k = 'a'), 'p1', 'prod', 'sku',
    now() + interval '30 days', now() - interval '1 minute', false, now() - interval '1 minute'),
  'applied', 'a newer observation can revoke');

select is(public.effective_tier((select v from t where k = 'a')), 'free',
  'a revoked subscription is not premium');

select * from finish();
rollback;
