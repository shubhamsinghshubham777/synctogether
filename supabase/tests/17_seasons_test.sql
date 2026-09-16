begin;
select plan(15);

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

-- The month `close_seasons` will look at is always the one that just ended.
create function pg_temp.last_month_day() returns date
language sql as $$
  select (date_trunc('month', (now() at time zone 'utc')) - interval '1 day')::date;
$$;

create function pg_temp.last_month_id() returns text
language sql as $$
  select to_char(date_trunc('month', (now() at time zone 'utc')) - interval '1 month', 'YYYY-MM');
$$;

create temp table t (k text primary key, v uuid);

do $$
declare v_gold uuid; v_silver uuid; v_bronze uuid; v_fourth uuid; v_quiet uuid;
begin
  v_gold := pg_temp.mk_user(); v_silver := pg_temp.mk_user();
  v_bronze := pg_temp.mk_user(); v_fourth := pg_temp.mk_user();
  v_quiet := pg_temp.mk_user();
  insert into t values ('gold', v_gold), ('silver', v_silver), ('bronze', v_bronze),
                       ('fourth', v_fourth), ('quiet', v_quiet);

  update public.profiles set public_profile = true
   where id in (v_gold, v_silver, v_bronze, v_fourth);
  update public.profiles set public_profile = false, handle = 'quiet_one' where id = v_quiet;

  -- The quiet one outscores everybody and must still never place.
  insert into public.watch_ledger (user_id, day, credited_seconds, points) values
    (v_gold,   pg_temp.last_month_day(), 7200, 900),
    (v_silver, pg_temp.last_month_day(), 7200, 600),
    (v_bronze, pg_temp.last_month_day(), 7200, 300),
    (v_fourth, pg_temp.last_month_day(), 7200, 100),
    (v_quiet,  pg_temp.last_month_day(), 7200, 5000);

  -- Seasons ship switched off (nothing to crown with no users yet), so the
  -- suite turns them on before testing what they do.
  update public.reward_config set value = 'true'::jsonb where key = 'seasons_enabled';

  -- Four participants, well under the floor: nobody should be crowned.
  perform public.close_seasons();
end $$;

select is(
  (select count(*)::int from public.season_awards),
  0,
  'a podium picked from four people is not a podium - the floor gates the trophies too');

select ok(
  exists (select 1 from public.seasons
           where id = pg_temp.last_month_id() and closed_at is not null),
  'but the season still closes, so the cron does not retry it every day forever');

do $$ begin
  delete from public.seasons where id = pg_temp.last_month_id();
  update public.reward_config set value = '2'::jsonb where key = 'leaderboard_min_participants';
  perform public.close_seasons();
end $$;

select is(
  (select count(*)::int from public.season_awards where season_id = pg_temp.last_month_id()),
  3,
  'exactly three people take a season, however many played');

select is(
  (select user_id from public.season_awards
    where season_id = pg_temp.last_month_id() and rank = 1),
  (select v from t where k = 'gold'),
  'the highest opted-in score takes first');

select is(
  (select user_id from public.season_awards
    where season_id = pg_temp.last_month_id() and rank = 3),
  (select v from t where k = 'bronze'),
  'and the podium is in points order');

select ok(
  not exists (
    select 1 from public.season_awards
     where user_id = (select v from t where k = 'quiet')),
  'the top scorer in the database never places, because they never opted in');

select ok(
  not exists (
    select 1 from public.season_awards
     where user_id = (select v from t where k = 'fourth')),
  'fourth place gets nothing, which is what makes third worth having');

-- Idempotency. The cron runs daily; a closed season must not be re-minted, and
-- a trophy handed out must never be handed out twice.
do $$ begin
  perform public.close_seasons();
  perform public.close_seasons();
end $$;

select is(
  (select count(*)::int from public.season_awards where season_id = pg_temp.last_month_id()),
  3,
  'running the sweep again mints nothing new');

select is(
  (select count(*)::int from public.seasons where id = pg_temp.last_month_id()),
  1,
  'and does not duplicate the season row');

-- A season that has already been closed is never revisited, even if the board
-- changed afterwards - a placing is a record of a month, not a live query.
do $$ begin
  update public.watch_ledger set points = 99999
   where user_id = (select v from t where k = 'fourth');
  perform public.close_seasons();
end $$;

select is(
  (select user_id from public.season_awards
    where season_id = pg_temp.last_month_id() and rank = 1),
  (select v from t where k = 'gold'),
  'a closed season is a record, not a live query - later points do not rewrite it');

-- The kill switch.
do $$ begin
  delete from public.season_awards;
  delete from public.seasons;
  update public.reward_config set value = 'false'::jsonb where key = 'seasons_enabled';
  perform public.close_seasons();
end $$;

select is(
  (select count(*)::int from public.seasons),
  0,
  'with seasons off the sweep does nothing at all, not even open a season');

select ok(
  has_table_privilege('authenticated', 'public.season_awards', 'SELECT'),
  'placings are readable, so a profile can render somebody else''s trophies');

select ok(
  not has_table_privilege('authenticated', 'public.season_awards', 'INSERT'),
  'but nobody can award themselves one');

select ok(
  not has_function_privilege('authenticated', 'public.close_seasons()', 'EXECUTE'),
  'and nobody can close a season early to lock in a lead');

select ok(
  has_function_privilege('authenticated', 'public.my_season_awards()', 'EXECUTE'),
  'reading your own placings is a client call');

select * from finish();
rollback;
