begin;
select plan(61);

-- ---------------------------------------------------------------------------
-- Fixtures
--
-- `now()` is transaction time in Postgres, so a test cannot watch a timestamp
-- advance. Every elapsed-time assertion therefore back-dates the heartbeat
-- anchor itself rather than waiting - see pg_temp.beat.
-- ---------------------------------------------------------------------------

create function pg_temp.mk_user(p_guest boolean default false) returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (
    v_id,
    p_guest,
    case when p_guest then null else 'u' || replace(v_id::text, '-', '') || '@example.test' end,
    '{}'::jsonb);
  return v_id;
end $$;

create function pg_temp.act_as(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid)::text, true);
end $$;

create function pg_temp.grant_premium(p_uid uuid) returns void
language plpgsql as $$
begin
  insert into public.subscriptions (user_id, tier, current_period_end)
  values (p_uid, 'premium', null)
  on conflict (user_id) do update set tier = 'premium', current_period_end = null;
end $$;

-- A live room with canonical media and a fresh authority position write, which
-- is the shape record_watch_progress requires before it credits anything.
create function pg_temp.mk_room(p_host uuid, p_others uuid[] default '{}') returns uuid
language plpgsql as $$
declare v_room public.rooms; v_other uuid;
begin
  perform pg_temp.act_as(p_host);
  v_room := public.create_room('Fixture', 240);
  foreach v_other in array p_others loop
    perform pg_temp.act_as(v_other);
    perform public.join_room(v_room.code);
  end loop;
  update public.rooms set media_kind = 'local', media_name = 'fixture.mkv',
         media_duration_ms = 7200000, media_updated_at = now()
   where id = v_room.id;
  update public.rooms set media_position_ms = 1000, media_position_at = now()
   where id = v_room.id;
  return v_room.id;
end $$;

create function pg_temp.beat(
  p_uid uuid, p_room uuid, p_back int default null,
  p_day date default null, p_hour int default null) returns jsonb
language plpgsql as $$
begin
  perform pg_temp.act_as(p_uid);
  if p_back is not null then
    update public.watch_heartbeats set last_at = now() - make_interval(secs => p_back)
     where user_id = p_uid and room_id = p_room;
    if not found then
      insert into public.watch_heartbeats (user_id, room_id, last_at)
      values (p_uid, p_room, now() - make_interval(secs => p_back));
    end if;
  end if;
  return public.record_watch_progress(p_room, coalesce(p_day, current_date), p_hour);
end $$;

create temp table t (k text primary key, v uuid);

do $$
declare v_a uuid; v_b uuid; v_c uuid; v_g uuid; v_p uuid; v_x uuid;
begin
  v_a := pg_temp.mk_user(); v_b := pg_temp.mk_user(); v_c := pg_temp.mk_user();
  v_g := pg_temp.mk_user(true); v_p := pg_temp.mk_user(); v_x := pg_temp.mk_user();
  perform pg_temp.grant_premium(v_p);
  insert into t values ('a', v_a), ('b', v_b), ('c', v_c),
                       ('guest', v_g), ('premium', v_p), ('outsider', v_x);
  insert into t values ('room', pg_temp.mk_room(v_a, array[v_b]));
end $$;

-- ---------------------------------------------------------------------------
-- Pure scoring primitives
-- ---------------------------------------------------------------------------

select is(public.streak_multiplier(0),  1.00, 'no streak, no multiplier');
select is(public.streak_multiplier(2),  1.00, 'two days is not yet a streak');
select is(public.streak_multiplier(3),  1.10, 'three days starts paying');
select is(public.streak_multiplier(7),  1.25, 'a week pays more');
select is(public.streak_multiplier(30), 1.50, 'a month is the top band');

select is(public.reward_points(3600, 2, 2, 0), 90,
  'an hour with two people scores 60 minutes plus two co-watcher bonuses');
select is(public.reward_points(3600, 2, 4, 0), 115,
  'a room of four adds the full-house bonus');
select is(public.reward_points(3600, 2, 2, 7), 113,
  'a seven-day streak multiplies the whole base');
select is(public.reward_points(36000, 0, 0, 0), 240,
  'credited minutes are capped, so one enormous Saturday cannot run away with it');
select is(public.reward_points(0, 99, 0, 0), 75,
  'co-watcher bonuses are capped at five, so a crowd cannot be farmed');

select is(public.effective_streak(9, current_date, 0, current_date), 9,
  'a streak credited today stands');
select is(public.effective_streak(9, current_date - 1, 0, current_date), 9,
  'a streak credited yesterday is still alive today');
select is(public.effective_streak(9, current_date - 2, 1, current_date), 9,
  'one missed day costs one freeze, and survives');
select is(public.effective_streak(9, current_date - 2, 0, current_date), 0,
  'the same gap with no freeze left is over');
select is(public.effective_streak(9, current_date - 4, 3, current_date), 9,
  'three missed days survive on three freezes - almost nobody watches together seven days a week');
select is(public.effective_streak(9, current_date - 4, 2, current_date), 0,
  'but not on two: a freeze is spent per missed day, so the budget still means something');
select is(public.effective_streak(9, null, 1, current_date), 0,
  'a user who has never qualified has no streak');

-- ---------------------------------------------------------------------------
-- Who earns, and who does not
-- ---------------------------------------------------------------------------

select is(
  pg_temp.beat((select v from t where k = 'guest'), (select v from t where k = 'room')) ->> 'reason',
  'guest',
  'guests earn nothing - an account purged in three days cannot hold a streak');

select is(
  pg_temp.beat((select v from t where k = 'guest'), (select v from t where k = 'room')) ->> 'upgrade',
  'true',
  'and the refusal carries the sign-in offer rather than just a no');

select is(
  pg_temp.beat((select v from t where k = 'outsider'), (select v from t where k = 'room')) ->> 'reason',
  'not_a_member',
  'someone who is not in the room earns nothing from it');

select is(
  pg_temp.beat((select v from t where k = 'a'), (select v from t where k = 'room')) ->> 'reason',
  'anchored',
  'the first call of a session only starts the clock');

select is(
  (pg_temp.beat((select v from t where k = 'a'), (select v from t where k = 'room'), 60)
    ->> 'granted_seconds')::int,
  60,
  'a minute of elapsed time credits a minute');

select is(
  (pg_temp.beat((select v from t where k = 'a'), (select v from t where k = 'room'), 200)
    ->> 'granted_seconds')::int,
  90,
  'elapsed time is clamped, so calling the RPC more often earns nothing more');

select is(
  (pg_temp.beat((select v from t where k = 'a'), (select v from t where k = 'room'), 4000)
    ->> 'granted_seconds')::int,
  0,
  'a gap longer than the stale window means they were away, not watching');

-- ---------------------------------------------------------------------------
-- Room shape gates
-- ---------------------------------------------------------------------------

do $$
declare v_solo uuid;
begin
  v_solo := pg_temp.mk_room((select v from t where k = 'c'));
  insert into t values ('solo', v_solo);
end $$;

select is(
  pg_temp.beat((select v from t where k = 'c'), (select v from t where k = 'solo'), 60) ->> 'reason',
  'solo',
  'watching alone is fine, it just is not watching together');

do $$
declare v_room uuid;
begin
  v_room := pg_temp.mk_room((select v from t where k = 'c'), array[(select v from t where k = 'b')]);
  update public.rooms set media_kind = 'none', media_name = null, media_duration_ms = null
   where id = v_room;
  insert into t values ('nomedia', v_room);
end $$;

select is(
  pg_temp.beat((select v from t where k = 'c'), (select v from t where k = 'nomedia'), 60) ->> 'reason',
  'no_media',
  'a room with nothing playing earns nothing');

do $$
declare v_room uuid;
begin
  v_room := pg_temp.mk_room((select v from t where k = 'c'), array[(select v from t where k = 'b')]);
  update public.rooms set media_position_at = now() - interval '1 hour',
                          media_updated_at = now() - interval '1 hour'
   where id = v_room;
  insert into t values ('idle', v_room);
end $$;

select is(
  pg_temp.beat((select v from t where k = 'c'), (select v from t where k = 'idle'), 60) ->> 'reason',
  'idle',
  'a room left open overnight stops producing position writes, and stops earning');

do $$
declare v_room uuid;
begin
  v_room := pg_temp.mk_room((select v from t where k = 'c'), array[(select v from t where k = 'b')]);
  update public.rooms set ended_at = now() where id = v_room;
  insert into t values ('ended', v_room);
end $$;

select is(
  pg_temp.beat((select v from t where k = 'c'), (select v from t where k = 'ended'), 60) ->> 'reason',
  'room_ended',
  'an ended room earns nothing');

-- ---------------------------------------------------------------------------
-- Caps
-- ---------------------------------------------------------------------------

do $$
declare v_room uuid; v_first jsonb; v_second jsonb;
begin
  update public.reward_config set value = '2'::jsonb where key = 'daily_credit_cap_min';
  v_room := pg_temp.mk_room((select v from t where k = 'premium'),
                            array[(select v from t where k = 'b')]);
  insert into t values ('capped', v_room);
  v_first  := pg_temp.beat((select v from t where k = 'premium'), v_room, 90);
  v_second := pg_temp.beat((select v from t where k = 'premium'), v_room, 90);
  create temp table cap_result as select v_first as first, v_second as second;
end $$;

select is((select (first ->> 'granted_seconds')::int from cap_result), 90,
  'the first minute and a half lands under a two-minute daily cap');
select is((select (second ->> 'granted_seconds')::int from cap_result), 30,
  'the next call is trimmed to whatever the daily cap has left');
select is((select second ->> 'reason' from cap_result), null,
  'a partially credited call is still a credited call');

select is(
  pg_temp.beat((select v from t where k = 'premium'), (select v from t where k = 'capped'), 90)
    ->> 'reason',
  'daily_cap',
  'past the daily cap the RPC says so rather than silently crediting zero');

do $$ begin
  update public.reward_config set value = '480'::jsonb where key = 'daily_credit_cap_min';
end $$;

-- The per-pair cap: two accounts farming each other hit diminishing returns.
do $$
declare v_room uuid; v_res jsonb;
begin
  update public.reward_config set value = '1'::jsonb where key = 'pair_daily_cap_min';
  v_room := pg_temp.mk_room((select v from t where k = 'a'), array[(select v from t where k = 'c')]);
  perform pg_temp.beat((select v from t where k = 'c'), v_room, 90);
  v_res := pg_temp.beat((select v from t where k = 'c'), v_room, 90);
  create temp table pair_result as select v_res as res;
  update public.reward_config set value = '120'::jsonb where key = 'pair_daily_cap_min';
end $$;

select is((select (res ->> 'points_today')::int from pair_result), 16,
  'with a one-minute pair cap, three minutes with the same person scores one minute plus the co-watcher bonus');

-- ---------------------------------------------------------------------------
-- The client is trusted with the calendar, never with the clock
-- ---------------------------------------------------------------------------

do $$
declare v_room uuid;
begin
  v_room := pg_temp.mk_room((select v from t where k = 'b'), array[(select v from t where k = 'c')]);
  insert into t values ('dayroom', v_room);
  perform pg_temp.beat((select v from t where k = 'b'), v_room, 90, '2999-01-01'::date);
end $$;

select is(
  (select count(*)::int from public.watch_ledger
    where user_id = (select v from t where k = 'b') and day = '2999-01-01'),
  0,
  'a client claiming a day in the next century is ignored');

select ok(
  exists (select 1 from public.watch_ledger
           where user_id = (select v from t where k = 'b') and day = current_date),
  'and the credit lands on the server day instead');

-- ---------------------------------------------------------------------------
-- Streaks
-- ---------------------------------------------------------------------------

do $$
declare v_room uuid; v_uid uuid := (select v from t where k = 'c');
begin
  update public.reward_config set value = '1'::jsonb where key = 'streak_min_minutes';
  v_room := pg_temp.mk_room((select v from t where k = 'a'), array[v_uid]);
  insert into t values ('streakroom', v_room);
  delete from public.watch_ledger where user_id = v_uid;
  delete from public.user_rewards where user_id = v_uid;
  create temp table streak_steps (step text primary key, res jsonb);

  insert into streak_steps values ('day1', pg_temp.beat(v_uid, v_room, 90));

  update public.user_rewards
     set last_credited_day = current_date - 1, current_streak = 1
   where user_id = v_uid;
  insert into streak_steps values ('day2', pg_temp.beat(v_uid, v_room, 90));

  update public.user_rewards
     set last_credited_day = current_date - 2, current_streak = 5,
         freezes_available = 1, freezes_refreshed = current_date
   where user_id = v_uid;
  insert into streak_steps values ('frozen', pg_temp.beat(v_uid, v_room, 90));

  update public.user_rewards
     set last_credited_day = current_date - 2, current_streak = 5,
         freezes_available = 0, freezes_refreshed = current_date
   where user_id = v_uid;
  insert into streak_steps values ('nofreeze', pg_temp.beat(v_uid, v_room, 90));

  update public.user_rewards
     set last_credited_day = current_date - 4, current_streak = 9,
         freezes_available = 1, freezes_refreshed = current_date
   where user_id = v_uid;
  insert into streak_steps values ('broken', pg_temp.beat(v_uid, v_room, 90));
end $$;

select is((select (res ->> 'streak')::int from streak_steps where step = 'day1'), 1,
  'a first qualifying day is a streak of one');
select is((select (res ->> 'day_qualified')::text from streak_steps where step = 'day1'), 'true',
  'and the day reports itself as qualified');
select is((select (res ->> 'streak')::int from streak_steps where step = 'day2'), 2,
  'a consecutive day extends the streak');
select is((select (res ->> 'streak')::int from streak_steps where step = 'frozen'), 6,
  'a missed day is absorbed by a freeze rather than resetting the streak');
select is((select (res ->> 'streak_frozen')::text from streak_steps where step = 'frozen'), 'true',
  'and the client is told, so it can say the streak survived Tuesday');
select is((select (res ->> 'freezes')::int from streak_steps where step = 'frozen'), 0,
  'the freeze is spent, not merely consulted');
select is((select (res ->> 'streak')::int from streak_steps where step = 'nofreeze'), 1,
  'a missed day with no freeze in hand starts again at one');
select is((select (res ->> 'streak')::int from streak_steps where step = 'broken'), 1,
  'a four-day gap is beyond the freezes in hand');

do $$
declare v_uid uuid := (select v from t where k = 'c');
begin
  -- Refill is lazy, so it only happens once the week has actually turned.
  update public.user_rewards
     set freezes_refreshed = current_date - 8, freezes_available = 0,
         last_credited_day = current_date - 1
   where user_id = v_uid;
  perform pg_temp.beat(v_uid, (select v from t where k = 'streakroom'), 90);
end $$;

select is(
  (select freezes_available from public.user_rewards where user_id = (select v from t where k = 'c')),
  2,
  'a free account refills to two freezes a week');

do $$
declare v_room uuid; v_uid uuid := (select v from t where k = 'premium');
begin
  v_room := pg_temp.mk_room((select v from t where k = 'a'), array[v_uid]);
  update public.user_rewards set freezes_refreshed = current_date - 8 where user_id = v_uid;
  perform pg_temp.beat(v_uid, v_room, 90);
end $$;

select is(
  (select freezes_available from public.user_rewards
    where user_id = (select v from t where k = 'premium')),
  3,
  'premium refills to three - grace, not capability, so it cannot cannibalise the subscription');

do $$ begin
  update public.reward_config set value = '20'::jsonb where key = 'streak_min_minutes';
end $$;

-- ---------------------------------------------------------------------------
-- Achievements
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from public.user_achievements
    where user_id = (select v from t where k = 'a') and achievement_id = 'first_sync'),
  1,
  'an achievement crossed is recorded exactly once');

select ok(
  not exists (
    select 1 from public.user_achievements
     where user_id = (select v from t where k = 'a') and achievement_id = 'century'),
  'and one that has not been crossed is not');

select lives_ok(
  $$ select public.grant_achievements(
       (select v from t where k = 'a'),
       '{"total_sessions": 99, "total_seconds": 99999999}'::jsonb) $$,
  're-granting is idempotent rather than an error');

-- ---------------------------------------------------------------------------
-- Consent, handles, cosmetics
-- ---------------------------------------------------------------------------

do $$ begin perform pg_temp.act_as((select v from t where k = 'guest')); end $$;

select throws_ok(
  $$ select public.set_public_profile(true) $$, 'P0001', 'guest_not_eligible',
  'a guest cannot publish a profile that will be purged in three days');

do $$ begin perform pg_temp.act_as((select v from t where k = 'a')); end $$;

select lives_ok(
  $$ select public.set_public_profile(true) $$,
  'any account holder can join the board - appearing on it is not a paid thing');

select throws_ok(
  $$ select public.claim_handle('reel_fan') $$, 'P0001', 'premium_required',
  'but a handle is: a permanent globally unique name is the one thing here worth squatting');

do $$ begin perform pg_temp.act_as((select v from t where k = 'premium')); end $$;

select throws_ok($$ select public.claim_handle('ab') $$, 'P0001', 'invalid_handle',
  'a two-character handle is refused');
select throws_ok($$ select public.claim_handle('Not A Handle') $$, 'P0001', 'invalid_handle',
  'spaces and capitals are refused');
select throws_ok($$ select public.claim_handle('leaderboard') $$, 'P0001', 'handle_reserved',
  'a handle can never shadow a website route');
select is(public.claim_handle('  Reel_Fan  '), 'reel_fan',
  'a good handle is trimmed and lowercased');

select lives_ok(
  $$ select public.equip_frame('aurum') $$,
  'premium wears its own frame by right');

do $$ begin perform pg_temp.act_as((select v from t where k = 'b')); end $$;

select throws_ok(
  $$ select public.equip_frame('aurora') $$, 'P0001', 'frame_locked',
  'a frame nobody has unlocked cannot be worn');

select throws_ok(
  $$ select public.equip_frame('aurum') $$, 'P0001', 'frame_locked',
  'and a free account cannot borrow it');

-- ---------------------------------------------------------------------------
-- Referral: credited at the join, once
-- ---------------------------------------------------------------------------

select is(
  (select referred_by from public.profiles where id = (select v from t where k = 'b')),
  (select v from t where k = 'a'),
  'the room a brand-new account first walked into names who brought them');

do $$
declare v_room uuid;
begin
  v_room := pg_temp.mk_room((select v from t where k = 'c'), array[(select v from t where k = 'b')]);
end $$;

select is(
  (select referred_by from public.profiles where id = (select v from t where k = 'b')),
  (select v from t where k = 'a'),
  'and a later host does not steal the credit');

select is(
  (select referred_by from public.profiles where id = (select v from t where k = 'a')),
  null,
  'the person who made the room is nobody''s referral');

select * from finish();
rollback;
