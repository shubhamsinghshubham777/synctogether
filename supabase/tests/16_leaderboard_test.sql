begin;
select plan(51);

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

create function pg_temp.score(p_uid uuid, p_points int, p_seconds int default 3600) returns void
language plpgsql as $$
begin
  insert into public.watch_ledger (user_id, day, credited_seconds, points)
  values (p_uid, current_date, p_seconds, p_points)
  on conflict (user_id, day) do update
    set points = excluded.points, credited_seconds = excluded.credited_seconds;
end $$;

create temp table t (k text primary key, v uuid);

do $$
declare v_me uuid; v_friend uuid; v_quiet uuid; v_stranger uuid; v_guest uuid;
begin
  v_me := pg_temp.mk_user(); v_friend := pg_temp.mk_user();
  v_quiet := pg_temp.mk_user(); v_stranger := pg_temp.mk_user();
  v_guest := pg_temp.mk_user(true);
  insert into t values ('me', v_me), ('friend', v_friend), ('quiet', v_quiet),
                       ('stranger', v_stranger), ('guest', v_guest);

  update public.profiles set public_profile = true, handle = 'me_'      where id = v_me;
  update public.profiles set public_profile = true, handle = 'friend_'  where id = v_friend;
  update public.profiles set public_profile = false                     where id = v_quiet;
  update public.profiles set public_profile = true, handle = 'stranger' where id = v_stranger;

  -- me and friend and quiet have watched together; stranger has not.
  insert into public.co_watchers (user_id, other_id, sessions, seconds) values
    (v_me, v_friend, 3, 9000), (v_friend, v_me, 3, 9000),
    (v_me, v_quiet, 1, 600),   (v_quiet, v_me, 1, 600);

  perform pg_temp.score(v_me, 100);
  perform pg_temp.score(v_friend, 300);
  perform pg_temp.score(v_quiet, 999);
  perform pg_temp.score(v_stranger, 200);

  insert into public.user_rewards (user_id, current_streak, last_credited_day, freezes_available)
  values (v_me, 4, current_date, 1), (v_friend, 12, current_date, 1)
  on conflict (user_id) do nothing;
end $$;

-- ---------------------------------------------------------------------------
-- The participation floor
-- ---------------------------------------------------------------------------

select is(public.leaderboard_open(), false,
  'with three opted-in players the global board stays shut - a board of three is worse than no board');

do $$ begin perform pg_temp.act_as((select v from t where k = 'me')); end $$;

select is(
  (select count(*)::int from public.leaderboard('global', 'week', 100)),
  0,
  'and it returns nothing at all rather than a sad little list');

select is(
  (public.public_leaderboard('week', 100) ->> 'open'),
  'false',
  'the website is told the same thing, so it can render the empty state on purpose');

do $$ begin
  update public.reward_config set value = '2'::jsonb where key = 'leaderboard_min_participants';
end $$;

select is(public.leaderboard_open(), true,
  'lowering the floor opens the board - the threshold is config, not a constant');

-- ---------------------------------------------------------------------------
-- Consent decides who is published
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from public.leaderboard('global', 'week', 100)
    where user_id = (select v from t where k = 'quiet')),
  0,
  'the highest scorer in the database is absent, because they never opted in');

select is(
  (select rank from public.leaderboard('global', 'week', 100)
    where user_id = (select v from t where k = 'friend')),
  1,
  'the top opted-in score ranks first');

select is(
  (select rank from public.leaderboard('global', 'week', 100)
    where user_id = (select v from t where k = 'stranger')),
  2,
  'and the rest fall in points order');

select is(
  (select is_me from public.leaderboard('global', 'week', 100)
    where user_id = (select v from t where k = 'me')),
  true,
  'the caller is flagged so the row can be highlighted without a second lookup');

select is(
  (select streak from public.leaderboard('global', 'week', 100)
    where user_id = (select v from t where k = 'friend')),
  12,
  'the published streak is the effective one, not the raw stored number');

-- ---------------------------------------------------------------------------
-- Circle: people you have actually watched with
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from public.leaderboard('circle', 'week', 100)
    where user_id = (select v from t where k = 'stranger')),
  0,
  'a stranger is not in your circle however many points they have');

select is(
  (select count(*)::int from public.leaderboard('circle', 'week', 100)
    where user_id = (select v from t where k = 'friend')),
  1,
  'someone you have shared a room with is');

select is(
  (select count(*)::int from public.leaderboard('circle', 'week', 100)
    where user_id = (select v from t where k = 'me')),
  1,
  'and so are you - a board you are not on is not a board you can climb');

-- ---------------------------------------------------------------------------
-- Private rank: knowing where you would stand is what makes the opt-in a choice
-- ---------------------------------------------------------------------------

do $$ begin perform pg_temp.act_as((select v from t where k = 'quiet')); end $$;

select is(public.my_rank('global', 'week'), 1,
  'an opted-out user still learns their own rank, privately');

do $$ begin perform pg_temp.act_as((select v from t where k = 'me')); end $$;

select is(public.my_rank('global', 'week'), 3,
  'and everyone else counts only the published scores above them');

-- ---------------------------------------------------------------------------
-- The website's read path
-- ---------------------------------------------------------------------------

select is(
  jsonb_array_length(public.public_leaderboard('week', 100) -> 'rows'),
  3,
  'the public board carries exactly the opted-in rows');

select is(
  (public.public_leaderboard('week', 100) -> 'rows' -> 0 ->> 'name'),
  (select display_name from public.profiles where id = (select v from t where k = 'friend')),
  'ordered highest first');

select is(
  public.public_profile_card('nobody_at_all'),
  null,
  'a handle nobody has claimed has no public card');

select is(
  public.public_profile_card((select handle from public.profiles
                               where id = (select v from t where k = 'quiet'))),
  null,
  'nor does an account that never opted in');

select is(
  (public.public_profile_card('friend_') ->> 'streak'),
  '12',
  'an opted-in card carries the streak the badge shows');

select is(
  (public.public_wrapped('friend_', extract(year from current_date)::int) ->> 'points'),
  '300',
  'wrapped reads the same ledger the board does');

-- ---------------------------------------------------------------------------
-- Recaps
-- ---------------------------------------------------------------------------

do $$
declare v_room public.rooms;
begin
  perform pg_temp.act_as((select v from t where k = 'me'));
  v_room := public.create_room('Friday film', 240);
  perform pg_temp.act_as((select v from t where k = 'friend'));
  perform public.join_room(v_room.code);
  perform pg_temp.act_as((select v from t where k = 'quiet'));
  perform public.join_room(v_room.code);
  insert into t values ('room', v_room.id);
end $$;

do $$ begin perform pg_temp.act_as((select v from t where k = 'guest')); end $$;

select throws_ok(
  format($$ select public.create_recap(%L::uuid, 3600) $$, (select v from t where k = 'room')),
  'P0001', 'guest_not_eligible',
  'a guest cannot mint a public URL from an account that will be purged');

do $$ begin perform pg_temp.act_as((select v from t where k = 'stranger')); end $$;

select throws_ok(
  format($$ select public.create_recap(%L::uuid, 3600) $$, (select v from t where k = 'room')),
  'P0001', 'not_a_member',
  'nor can somebody who was never in the room');

do $$
declare v_res jsonb; v_again jsonb;
begin
  perform pg_temp.act_as((select v from t where k = 'me'));
  v_res := public.create_recap(
    (select v from t where k = 'room'), 5400, 3, 42, 9000, '🎉',
    array['local', 'sneaky_mode'], true, true,
    array[(select v from t where k = 'friend'), (select v from t where k = 'quiet')],
    jsonb_build_array(
      jsonb_build_object('key', 'chat',    'user_id', (select v from t where k = 'friend')),
      jsonb_build_object('key', 'nonsense','user_id', (select v from t where k = 'quiet'))));
  -- Deliberately thinner than the first call: a re-share must not be able to
  -- replace a rich recap with a poor one.
  v_again := public.create_recap((select v from t where k = 'room'), 5400, 3, 5, 5);
  create temp table recap_result as select v_res as res, v_again as again;
end $$;

select is(
  (select jsonb_typeof(res -> 'id') from recap_result), 'string',
  'a share mints an id');

select is(
  (select (again ->> 'id') = (res ->> 'id') from recap_result), true,
  'sharing the same session twice returns the same URL rather than a second one');

select is(
  (select reactions_sent from public.user_rewards where user_id = (select v from t where k = 'me')),
  500,
  'client-reported reaction counts are capped before they are banked');

select is(
  (select messages_sent from public.user_rewards where user_id = (select v from t where k = 'me')),
  42,
  'and the second share does not bank the counters a second time');

select is(
  (select clean_gate_sessions from public.user_rewards
    where user_id = (select v from t where k = 'me')),
  1,
  'nor the session counters');

do $$
declare v_payload jsonb;
begin
  v_payload := public.public_recap((select res ->> 'id' from recap_result));
  create temp table recap_payload as select v_payload as p;
end $$;

select is(
  (select p -> 'people' -> 0 ->> 'name' from recap_payload),
  (select display_name from public.profiles where id = (select v from t where k = 'friend')),
  'a co-watcher who opted in is named on the public page');

select is(
  (select p -> 'people' -> 1 ->> 'name' from recap_payload),
  null,
  'a co-watcher who did not is a gradient and nothing else - a recap must not out anybody');

select is(
  (select p -> 'people' -> 1 ->> 'public' from recap_payload),
  'false',
  'and the page is told why, so it renders an anonymous avatar rather than a blank');

select ok(
  (select p -> 'people' -> 1 ->> 'seed' from recap_payload) is not null,
  'an anonymous co-watcher still gets a stable gradient seed');

select ok(
  (select (p -> 'people' -> 1 ->> 'seed') <> (select v::text from t where k = 'quiet')
     from recap_payload),
  'and the seed is a hash, never the account id - public pages carry no identifiers');

select is(
  (select p ->> 'room_name' from recap_payload),
  'Friday film',
  'the host named the room, so the host may publish the name');

select is(
  (select jsonb_array_length(p -> 'superlatives') from recap_payload),
  1,
  'superlatives are an allow-list: the client picks the winner, not the award');

select is(
  (select p -> 'superlatives' -> 0 ->> 'key' from recap_payload),
  'chat',
  'and the one that survives is the real one');

select is(
  (select p -> 'modes' ->> 0 from recap_payload),
  'local',
  'playback modes are filtered to the ones that exist');

select is(
  (select jsonb_array_length(p -> 'modes') from recap_payload),
  1,
  'an invented mode is dropped rather than published');

select is(
  (select p ->> 'reactions' from recap_payload),
  '500',
  'the published reaction figure is the capped one');

select is(
  (select views from public.recaps where id = (select res ->> 'id' from recap_result)),
  1,
  'reading a public recap counts the view');

-- A member who is not the host may share, but may not publish the room's name.
do $$
declare v_res jsonb;
begin
  perform pg_temp.act_as((select v from t where k = 'friend'));
  v_res := public.create_recap((select v from t where k = 'room'), 900);
  create temp table guest_recap as select public.public_recap(v_res ->> 'id') as p;
end $$;

select is(
  (select p ->> 'room_name' from guest_recap),
  null,
  'a member who did not name the room does not get to publish its name');

-- ---------------------------------------------------------------------------
-- Housekeeping
-- ---------------------------------------------------------------------------

do $$ begin
  update public.recaps set expires_at = now() - interval '1 day';
  perform public.sweep_rewards();
end $$;

select is(
  (select count(*)::int from public.recaps),
  0,
  'expired recaps are swept, so a shared URL really does stop working');

select is(
  public.public_recap('does_not_exist'),
  null,
  'and an unknown id is a null, never an error page');

do $$ begin perform pg_temp.act_as((select v from t where k = 'friend')); end $$;

select is(
  (public.my_referrals() ->> 'total'),
  '0',
  'referral counts start at zero rather than null');

-- ---------------------------------------------------------------------------
-- Taking a recap back
-- ---------------------------------------------------------------------------

do $$
declare v_res jsonb;
begin
  perform pg_temp.act_as((select v from t where k = 'me'));
  v_res := public.create_recap((select v from t where k = 'room'), 4200);
  create temp table owned_recap as select v_res ->> 'id' as id;
end $$;

select is(
  jsonb_array_length(public.my_recaps()),
  1,
  'the owner can see what they have published');

select is(
  (public.my_recaps() -> 0 ->> 'id'),
  (select id from owned_recap),
  'listed by id, so a single one can be taken down');

select ok(
  (public.my_recaps() -> 0 -> 'payload') is null,
  'the management list carries no payload - it is not a second copy of the page');

do $$ begin perform pg_temp.act_as((select v from t where k = 'stranger')); end $$;

select is(
  public.delete_recap((select id from owned_recap)),
  false,
  'somebody else deleting it is a no-op, not a deletion');

select ok(
  public.public_recap((select id from owned_recap)) is not null,
  'and the page is still there');

do $$ begin perform pg_temp.act_as((select v from t where k = 'me')); end $$;

select is(
  public.delete_recap((select id from owned_recap)),
  true,
  'the owner can take it back');

select is(
  public.public_recap((select id from owned_recap)),
  null,
  'and the link stops working immediately, not in ninety days');

select is(
  public.delete_recap((select id from owned_recap)),
  false,
  'deleting it twice reports honestly rather than pretending');

select * from finish();
rollback;
