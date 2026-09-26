begin;
select plan(12);

create function pg_temp.as_role(p_role text) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_role)::text, true);
end $$;

create function pg_temp.m() returns jsonb
language plpgsql as $$
begin
  perform pg_temp.as_role('service_role');
  return public.internal_metrics();
end $$;

create function pg_temp.mk_user(p_anon boolean default false) returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_id, p_anon, case when p_anon then null else 'm' || replace(v_id::text, '-', '') || '@example.test' end, '{}'::jsonb);
  return v_id;
end $$;

-- Grants: the service role only, revoke before grant.
select ok(not has_function_privilege('anon', 'public.internal_metrics()', 'EXECUTE'),
  'anon cannot read internal metrics');
select ok(not has_function_privilege('authenticated', 'public.internal_metrics()', 'EXECUTE'),
  'signed-in clients cannot read internal metrics');
select ok(has_function_privilege('service_role', 'public.internal_metrics()', 'EXECUTE'),
  'the service role can');

-- Even with EXECUTE (security definer owner), a non-service caller is refused.
select pg_temp.as_role('authenticated');
select throws_ok('select public.internal_metrics()', '42501', null,
  'a caller without the service_role claim is refused');

create temp table base as select pg_temp.m() as j;

-- 1100 registered profiles: past PostgREST's max_rows of 1000.
select pg_temp.mk_user() from generate_series(1, 1100);
select is((pg_temp.m() #>> '{accounts,registered}')::int - (select (j #>> '{accounts,registered}')::int from base),
  1100, 'more than 1000 profiles are all counted');

-- A guest with a stray premium subscription row is still a guest.
create temp table t (k text primary key, v uuid);
insert into t values ('g', pg_temp.mk_user(true)), ('p', pg_temp.mk_user()), ('w', pg_temp.mk_user());
insert into public.subscriptions (user_id, tier, current_period_end, source)
values ((select v from t where k = 'g'), 'premium', now() + interval '30 days', 'manual');
select is((pg_temp.m() #>> '{accounts,premium}')::int - (select (j #>> '{accounts,premium}')::int from base),
  0, 'a guest with a subscription row is not premium');

-- Paddle MRR inputs: a priced row is summed, a past_due one is not, and an
-- unpriced one is counted apart rather than guessed.
insert into public.subscriptions (user_id, tier, current_period_end, source, unit_amount, currency, billing_interval, billing_frequency, paddle_status)
values ((select v from t where k = 'p'), 'premium', now() + interval '30 days', 'paddle', 399, 'USD', 'month', 1, 'active');
select ok(
  (pg_temp.m() -> 'subscriptions' -> 'paddle_revenue') @> '[{"currency":"USD","interval":"month","subscribers":1,"unit_amount_sum":399}]'::jsonb,
  'an active priced Paddle row feeds MRR');
update public.subscriptions set paddle_status = 'past_due' where user_id = (select v from t where k = 'p');
select is((pg_temp.m() #>> '{subscriptions,paddle_past_due}')::int - (select (j #>> '{subscriptions,paddle_past_due}')::int from base),
  1, 'past_due is counted separately');
select is(pg_temp.m() -> 'subscriptions' -> 'paddle_revenue',
  (select j -> 'subscriptions' -> 'paddle_revenue' from base),
  'past_due is excluded from MRR');

-- DAU comes from the ledger: a user with no room membership at all (left,
-- kicked, room deleted) who was credited today is still active.
insert into public.watch_ledger (user_id, day, credited_seconds, updated_at)
values ((select v from t where k = 'w'), current_date, 600, now());
select is((pg_temp.m() #>> '{activity,dau}')::int - (select (j #>> '{activity,dau}')::int from base),
  1, 'a credited user who has left every room still counts toward DAU');

-- A new signup who watched nothing is not active.
select is((pg_temp.m() #>> '{activity,mau}')::int - (select (j #>> '{activity,mau}')::int from base),
  1, 'signups are not added to MAU');

-- An expired room is not live; a fresh one is.
insert into public.rooms (code, created_by, duration_minutes, expires_at, created_at)
values ('ZZEXP1', (select v from t where k = 'w'), 60, now() - interval '1 minute', now() - interval '61 minutes'),
       ('ZZLIV1', (select v from t where k = 'w'), 60, now() + interval '59 minutes', now());
select is((pg_temp.m() #>> '{rooms,live_now}')::int - (select (j #>> '{rooms,live_now}')::int from base),
  1, 'an expired room is not counted as live');

select * from finish();
rollback;
