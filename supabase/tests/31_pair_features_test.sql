begin;
select plan(49);

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
insert into t values ('maya', pg_temp.mk_user()), ('sam', pg_temp.mk_user()), ('lee', pg_temp.mk_user());

-- Pair Maya and Sam.
do $$
declare v_code text;
begin
  perform pg_temp.act_as((select v from t where k = 'maya'));
  v_code := (public.create_pair_invite()).code;
  perform pg_temp.act_as((select v from t where k = 'sam'));
  perform public.accept_pair_invite(v_code);
end $$;

-- ---------------------------------------------------------------------------
-- Push tokens and preferences
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'maya'));
select lives_ok($$ select public.register_push_token('ios', 'maya-ios-token-0001', 'sandbox') $$, 'a token registers');
select pg_temp.act_as((select v from t where k = 'sam'));
select lives_ok($$ select public.register_push_token('windows', 'https://wns.example/sam-channel-0001') $$, 'a Windows channel registers');
select throws_ok($$ select public.register_push_token('plan9', 'sam-token-00000001') $$, '23514', null, 'an unknown platform is refused');
select is((public.my_push_prefs())->>'reunion', 'true', 'the reunion countdown is on by default');
select is((public.my_push_prefs())->>'calls', 'true', 'calls are on by default');
select lives_ok($$ select public.set_push_pref('reunion', false) $$, 'a switch can be flipped');
select is((public.my_push_prefs())->>'reunion', 'false', 'and reads back');
select throws_ok($$ select public.set_push_pref('everything', true) $$, 'invalid_pref', 'an unknown switch is refused');

-- Lee has no token: nothing is queued for them.
select pg_temp.act_as((select v from t where k = 'lee'));
select is((select count(*)::int from public.push_outbox where user_id = (select v from t where k = 'lee')), 0, 'no outbox rows for a person with no device');

-- ---------------------------------------------------------------------------
-- Calling
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'maya'));
select is((public.call_partner())->>'sent', 'true', 'Maya rings Sam');
select is((select count(*)::int from public.push_outbox where kind = 'call' and user_id = (select v from t where k = 'sam')), 1, 'one call is queued for Sam');
select is((select title from public.push_outbox where kind = 'call'), (select display_name from public.profiles where id = (select v from t where k = 'maya')) || ' is calling', 'the push names the caller');
select is((public.call_partner())->>'reason', 'throttled', 'a second ring within a minute is throttled');
select ok((select expires_at <= now() + interval '95 seconds' from public.push_outbox where kind = 'call'), 'a call expires quickly');

-- ---------------------------------------------------------------------------
-- Claiming: quiet hours hold everything but a call
-- ---------------------------------------------------------------------------
update public.profiles set timezone = 'UTC' where id = (select v from t where k = 'sam');
insert into public.push_outbox (user_id, kind, title, body)
values ((select v from t where k = 'sam'), 'reunion', 'x', 'y');

-- Pin the clock by choosing the time zone whose local hour is 3 right now.
do $$
declare v_tz text;
begin
  select name into v_tz from pg_catalog.pg_timezone_names
   where extract(hour from now() at time zone name) = 3 and name !~ '^(posix|Etc|SystemV)' limit 1;
  update public.profiles set timezone = v_tz where id = (select v from t where k = 'sam');
end $$;
select is((select count(*)::int from public.claim_push_batch(50) where kind = 'reunion'), 0, 'a reunion push waits through quiet hours');
update public.push_outbox set locked_until = null, attempts = 0;
select is((select count(*)::int from public.claim_push_batch(50) where kind = 'call'), 1, 'but a call goes through');
update public.push_prefs set quiet_hours = false where user_id = (select v from t where k = 'sam');
update public.push_outbox set locked_until = null where kind = 'reunion';
select is((select count(*)::int from public.claim_push_batch(50) where kind = 'reunion'), 1, 'with quiet hours off it is claimed');
select is((select count(*)::int from public.claim_push_batch(50)), 0, 'claimed rows are locked, not handed out twice');

select lives_ok($$ select public.complete_push((select id from public.push_outbox where kind = 'call'), true) $$, 'a delivered push is completed');
select isnt((select sent_at from public.push_outbox where kind = 'call'), null::timestamptz, 'and stamped sent');

-- ---------------------------------------------------------------------------
-- An outsider
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'lee'));
set local role authenticated;
select is((select count(*)::int from public.date_nights) + (select count(*)::int from public.pairs), 0,
  'an outsider sees no pairs or nights');
select throws_ok($$ select count(*) from public.push_outbox $$, '42501', null, 'the outbox is not readable by clients at all');
select throws_ok($$ select count(*) from public.push_tokens $$, '42501', null, 'nor are device tokens');
reset role;
select throws_ok($$ select public.call_partner() $$, 'not_paired', 'and cannot ring anyone');

-- ---------------------------------------------------------------------------
-- Date nights: creating is Patron, answering never is
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'maya'));
select throws_ok($$ select public.create_date_night('Spirited Away', now() + interval '2 days') $$,
  'patron_required', 'a free pair cannot schedule');

insert into public.subscriptions (user_id, tier, current_period_end)
values ((select v from t where k = 'maya'), 'premium', now() + interval '30 days');
select throws_ok($$ select public.create_date_night('Soon', now() + interval '1 minute') $$, 'invalid_time', 'a night must be a few minutes away');
insert into t select 'night', (public.create_date_night('Spirited Away', now() + interval '2 days')).id;
select is((select count(*)::int from public.push_outbox where kind = 'date_night_invite'), 1, 'Sam is told');

select pg_temp.act_as((select v from t where k = 'sam'));
select is((public.respond_date_night((select v from t where k = 'night'), true)).status, 'accepted', 'a free partner can accept');
select is((select count(*)::int from public.push_outbox where kind = 'date_night_reminder'), 2, 'both people get a reminder');
select ok((select bool_and(send_after < now() + interval '2 days' and send_after > now() + interval '47 hours')
           from public.push_outbox where kind = 'date_night_reminder'), 'queued 15 minutes before the start');
select throws_ok($$ select public.respond_date_night((select v from t where k = 'night'), true) $$, 'night_not_open', 'it cannot be answered twice');

select is((public.reschedule_date_night((select v from t where k = 'night'), now() + interval '3 days')).status, 'proposed',
  'a free partner can suggest another time');
select is((select count(*)::int from public.push_outbox where kind = 'date_night_reminder' and sent_at is null), 0, 'which drops the old reminders');

select pg_temp.act_as((select v from t where k = 'maya'));
select lives_ok($$ select public.respond_date_night((select v from t where k = 'night'), true) $$, 'the proposer of the first time can accept the new one');
select lives_ok($$ select public.cancel_date_night((select v from t where k = 'night')) $$, 'either person can cancel');
select is((select count(*)::int from public.push_outbox where kind = 'date_night_reminder' and sent_at is null), 0, 'which removes the reminders');

-- Patron lapses: nothing is deleted, only creating needs it.
delete from public.subscriptions;
select is((select count(*)::int from public.date_nights), 1, 'the night is still there after Patron ends');

-- ---------------------------------------------------------------------------
-- History, streak, export
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'maya'));
select lives_ok($$ select public.log_pair_session('Spirited Away', now() - interval '1 hour', 7200) $$, 'a session is logged');
select lives_ok($$ select public.log_pair_session('Spirited Away', now() - interval '1 hour', 7500) $$, 'the same sitting reported again');
select is((select count(*)::int from public.pair_sessions), 1, 'is one row');
select is((select seconds from public.pair_sessions), 7500, 'keeping the longer report');
select lives_ok($$ select public.log_pair_session('Blip', now(), 30) $$, 'under a minute is ignored');
select is((select count(*)::int from public.pair_sessions), 1, 'and not stored');

-- Older sittings: backfill directly, then check the free window and the lock.
insert into public.pair_sessions (pair_id, title, started_at, seconds) values
  ((select public.my_pair_id()), 'Old film', now() - interval '20 days', 5400),
  ((select public.my_pair_id()), 'Older film', now() - interval '27 days', 5400);
select is(jsonb_array_length((public.pair_history())->'items'), 1, 'a free pair sees the last 7 days');
select is(((public.pair_history())->>'locked_count')::int, 2, 'and how many are kept behind the lock');
select is(jsonb_array_length(public.pair_history_export()), 3, 'export returns everything, free or not');

insert into public.subscriptions (user_id, tier, current_period_end)
values ((select v from t where k = 'sam'), 'premium', now() + interval '30 days');
select is(jsonb_array_length((public.pair_history())->'items'), 3, 'either partner being Patron unlocks the archive');
select is(((public.pair_stats())->>'nights')::int, 3, 'stats count the nights');
select is(((public.pair_stats())->>'films')::int, 3, 'and the films');

select * from finish();
rollback;
