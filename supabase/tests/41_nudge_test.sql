begin;
select plan(18);

create function pg_temp.mk_user(p_name text) returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_id, false, 'u' || replace(v_id::text, '-', '') || '@example.test',
          jsonb_build_object('full_name', p_name));
  update public.profiles set display_name = p_name where id = v_id;
  insert into public.push_tokens (user_id, platform, token) values (v_id, 'ios', 'tok-' || v_id::text);
  return v_id;
end $$;

create function pg_temp.act_as(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid)::text, true);
end $$;

create temp table t (k text primary key, v uuid);
insert into t values ('maya', pg_temp.mk_user('Maya')), ('sam', pg_temp.mk_user('Sam')), ('lee', pg_temp.mk_user('Lee'));

-- Pair Maya and Sam, then give them three nights: one tonight, one a week out,
-- one that has not been accepted.
do $$
declare v_code text; v_pair uuid; v_id uuid; v_maya uuid := (select v from t where k = 'maya');
begin
  perform pg_temp.act_as(v_maya);
  v_code := (public.create_pair_invite()).code;
  perform pg_temp.act_as((select v from t where k = 'sam'));
  perform public.accept_pair_invite(v_code);
  select pair_id into v_pair from public.pair_members where user_id = v_maya;
  insert into t values ('pair', v_pair);
  insert into public.date_nights (pair_id, title, starts_at, proposed_by, status)
    values (v_pair, 'Tonight', now() + interval '12 minutes', v_maya, 'accepted') returning id into v_id;
  insert into t values ('tonight', v_id);
  insert into public.date_nights (pair_id, title, starts_at, proposed_by, status)
    values (v_pair, 'Later', now() + interval '7 days', v_maya, 'accepted') returning id into v_id;
  insert into t values ('later', v_id);
  insert into public.date_nights (pair_id, title, starts_at, proposed_by, status)
    values (v_pair, 'Proposed', now() + interval '2 hours', v_maya, 'proposed') returning id into v_id;
  insert into t values ('proposed', v_id);
end $$;

-- 1. Not callable anonymously, callable by a signed-in person.
select ok(not has_function_privilege('anon', 'public.nudge_partner(uuid)', 'execute'),
  'nobody anonymous can nudge');
select ok(has_function_privilege('authenticated', 'public.nudge_partner(uuid)', 'execute'),
  'a signed-in person can');

-- 2. Someone who is not paired gets the same refusal as for call_partner.
select pg_temp.act_as((select v from t where k = 'lee'));
select throws_ok(format($$ select public.nudge_partner(%L) $$, (select v from t where k = 'tonight')),
  'not_paired', 'a person with no pair cannot nudge');

-- 3. Maya nudges Sam about tonight.
select pg_temp.act_as((select v from t where k = 'maya'));
select is((public.nudge_partner((select v from t where k = 'tonight')))->>'sent', 'true',
  'Maya nudges Sam about tonight');
select is((select count(*)::int from public.push_outbox
           where kind = 'date_night_nudge' and user_id = (select v from t where k = 'sam')),
  1, 'one nudge is queued for Sam');
select is((select title from public.push_outbox where kind = 'date_night_nudge'),
  'Maya is ready for Tonight', 'the push names who is ready and for what');
select is((select data->>'route' from public.push_outbox where kind = 'date_night_nudge'),
  'lobby', 'tapping it opens the lobby, where the Pre-show check lives');
select is((select count(*)::int from public.push_outbox
           where kind = 'date_night_nudge' and user_id = (select v from t where k = 'maya')),
  0, 'Maya is not nudged about her own nudge');

-- 4. A second tap inside ten minutes is throttled and queues nothing more.
select is((public.nudge_partner((select v from t where k = 'tonight')))->>'reason', 'throttled',
  'a second nudge within ten minutes is throttled');
select is((select count(*)::int from public.push_outbox where kind = 'date_night_nudge'),
  1, 'and still only one is queued');

-- 5. After ten minutes (back-dated, since now() is transaction time) it can go again.
update public.push_outbox set created_at = now() - interval '11 minutes' where kind = 'date_night_nudge';
select is((public.nudge_partner((select v from t where k = 'tonight')))->>'sent', 'true',
  'ten minutes later a nudge can go again');

-- A nudge that was still waiting (quiet hours) is replaced by the new one, so
-- the throttle counts from the new one and a tap right after is throttled.
select is((select count(*)::int from public.push_outbox where kind = 'date_night_nudge'), 1,
  'the old waiting nudge was replaced, not doubled');
select is((public.nudge_partner((select v from t where k = 'tonight')))->>'reason', 'throttled',
  'and the new one starts a fresh ten minutes');

-- 6. Only for an accepted night that is around now.
select is((public.nudge_partner((select v from t where k = 'later')))->>'reason', 'not_now',
  'a night a week away is not a nudge');
select is((public.nudge_partner((select v from t where k = 'proposed')))->>'reason', 'no_night',
  'a night that has not been accepted is not a nudge');
select is((public.nudge_partner(gen_random_uuid()))->>'reason', 'no_night',
  'a night that does not exist is not a nudge');

-- 7. The date_nights switch silences it, like every date-night push.
select pg_temp.act_as((select v from t where k = 'sam'));
select lives_ok($$ select public.set_push_pref('date_nights', false) $$, 'Sam turns date-night pushes off');
delete from public.push_outbox where kind = 'date_night_nudge';
select pg_temp.act_as((select v from t where k = 'maya'));
do $$ begin
  perform public.nudge_partner((select v from t where k = 'tonight'));
end $$;
select is((select count(*)::int from public.push_outbox where kind = 'date_night_nudge'),
  0, 'with the switch off nothing is queued for Sam');

select * from finish();
rollback;
