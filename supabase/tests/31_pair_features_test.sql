begin;
select plan(66);

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

-- ---------------------------------------------------------------------------
-- Invite by email: the same answer whether or not an account matched
-- ---------------------------------------------------------------------------
insert into t values ('zed', pg_temp.mk_user()), ('amy', pg_temp.mk_user()), ('yan', pg_temp.mk_user()),
  ('xia', pg_temp.mk_user()), ('blk', pg_temp.mk_user()), ('rate', pg_temp.mk_user());
insert into t values ('guest', (select pg_temp.mk_user()));
update auth.users set is_anonymous = true, email = null where id = (select v from t where k = 'guest');
update public.profiles set is_guest = true, email = null where id = (select v from t where k = 'guest');

select pg_temp.act_as((select v from t where k = 'amy'));
select lives_ok($$ select public.register_push_token('ios', 'amy-ios-token-0001', 'sandbox') $$, 'Amy has a device');

select pg_temp.act_as((select v from t where k = 'zed'));
select throws_ok($$ select public.invite_pair_by_email('not an email') $$, 'invalid_email', 'a malformed address is refused');
select is((public.invite_pair_by_email((select email from public.profiles where id = (select v from t where k = 'amy')))).status,
  'pending', 'inviting a real account returns the invite');
select is((select seen_by from public.pair_invites where inviter_id = (select v from t where k = 'zed') and status = 'pending'),
  (select v from t where k = 'amy'), 'which is put in front of that account');
select is((select count(*)::int from public.push_outbox where kind = 'pair_request' and user_id = (select v from t where k = 'amy')),
  1, 'with a push queued');
select pg_temp.act_as((select v from t where k = 'amy'));
select is((public.my_pending_pair_invite())->'inviter'->>'id', (select v::text from t where k = 'zed'),
  'and it shows in their lobby banner');

-- An address with no account looks exactly the same to the sender.
select pg_temp.act_as((select v from t where k = 'yan'));
select is((public.invite_pair_by_email('nobody-at-all@example.test')).status, 'pending',
  'an unknown address returns the same kind of answer');
select is((select seen_by from public.pair_invites where inviter_id = (select v from t where k = 'yan') and status = 'pending'),
  null::uuid, 'but reaches no one');
select is((select count(*)::int from public.push_outbox where kind = 'pair_request' and user_id = (select v from t where k = 'yan')),
  0, 'and no push goes anywhere');

-- Never matched: yourself, someone already paired, a guest, someone who blocked you.
select pg_temp.act_as((select v from t where k = 'xia'));
select lives_ok(format($$ select public.invite_pair_by_email(%L) $$, (select email from public.profiles where id = (select v from t where k = 'xia'))),
  'your own address is accepted quietly');
select is((select seen_by from public.pair_invites where inviter_id = (select v from t where k = 'xia') and status = 'pending'),
  null::uuid, 'and matches no one');

select pg_temp.act_as((select v from t where k = 'yan'));
select lives_ok(format($$ select public.invite_pair_by_email(%L) $$, (select email from public.profiles where id = (select v from t where k = 'sam'))),
  'inviting someone who is already paired is accepted quietly');
select is((select seen_by from public.pair_invites where inviter_id = (select v from t where k = 'yan') and status = 'pending'),
  null::uuid, 'and they are not told');

insert into public.user_blocks (blocker_id, blocked_id)
  values ((select v from t where k = 'blk'), (select v from t where k = 'yan'));
select lives_ok(format($$ select public.invite_pair_by_email(%L) $$, (select email from public.profiles where id = (select v from t where k = 'blk'))),
  'inviting someone who blocked you is accepted quietly');
select is((select count(*)::int from public.push_outbox where kind = 'pair_request' and user_id = (select v from t where k = 'blk')),
  0, 'and they hear nothing');

select pg_temp.act_as((select v from t where k = 'guest'));
select throws_ok($$ select public.invite_pair_by_email('someone@example.test') $$, 'sign_in_required', 'a guest cannot invite by email');

-- Attempts are rate-limited per sender, matched or not.
select pg_temp.act_as((select v from t where k = 'rate'));
do $$
declare i int;
begin
  for i in 1..5 loop
    perform public.invite_pair_by_email('nobody' || i || '@example.test');
  end loop;
end $$;
select throws_ok($$ select public.invite_pair_by_email('nobody6@example.test') $$, 'too_many_invites',
  'the sixth address in a day is refused');

select * from finish();
rollback;
