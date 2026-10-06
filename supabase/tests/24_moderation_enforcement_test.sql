begin;
select plan(19);

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
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
end $$;

create temp table t (k text primary key, v uuid);
grant select on t to authenticated;

do $$
declare
  v_host uuid;
  v_pirate uuid;
  v_reporter uuid;
  v_room public.rooms;
  v_report_id uuid;
begin
  v_host := pg_temp.mk_user();
  v_pirate := pg_temp.mk_user();
  v_reporter := pg_temp.mk_user();
  insert into t values ('host', v_host), ('pirate', v_pirate), ('reporter', v_reporter);

  perform pg_temp.act_as(v_host);
  v_room := public.create_room('Cinema Room', 60);
  insert into t values ('room', v_room.id);

  perform pg_temp.act_as(v_pirate);
  perform public.join_room(v_room.code);

  perform pg_temp.act_as(v_reporter);
  perform public.join_room(v_room.code);

  -- Reporter files a copyright complaint with full media context
  v_report_id := public.report_content(
    p_reported_user_id => v_pirate,
    p_reason => 'copyright',
    p_room_id => v_room.id,
    p_details => 'Streaming pirated movie',
    p_media_kind => 'r2',
    p_media_title => 'Movie.2026.1080p.WEBRip.mp4',
    p_media_source_url => 'https://r2.example.com/media/xyz',
    p_room_code => v_room.code
  );
  insert into t values ('report', v_report_id);
end $$;

-- 1. Report captured media snapshot
select is(
  (select media_title from public.content_reports where id = (select v from t where k = 'report')),
  'Movie.2026.1080p.WEBRip.mp4',
  'report snapshots the media title');

select is(
  (select media_kind from public.content_reports where id = (select v from t where k = 'report')),
  'r2',
  'report snapshots the media kind');

-- 2. Initial pirate state is clean
select is(
  (select moderation_status from public.profiles where id = (select v from t where k = 'pirate')),
  'clean',
  'user starts in clean moderation status');

select is(
  (select strikes_count from public.profiles where id = (select v from t where k = 'pirate')),
  0,
  'user starts with 0 strikes');

-- 3. AI Triage recording
do $$
begin
  perform public.admin_record_ai_triage(
    (select v from t where k = 'report'),
    92,
    'ban_room_and_warn_user',
    'Media title matches scene pirated release'
  );
end $$;

select is(
  (select ai_risk_score from public.content_reports where id = (select v from t where k = 'report')),
  92,
  'admin_record_ai_triage stores the risk score');

-- 4. Strike 1 Warning
do $$
begin
  perform public.admin_warn_user(
    p_user_id => (select v from t where k = 'pirate'),
    p_reason => 'First copyright strike: pirated video stream',
    p_report_id => (select v from t where k = 'report'),
    p_ai_assisted => true
  );
end $$;

select is(
  (select strikes_count from public.profiles where id = (select v from t where k = 'pirate')),
  1,
  'Strike 1 increments strike count to 1');

select is(
  (select moderation_status from public.profiles where id = (select v from t where k = 'pirate')),
  'warned',
  'moderation_status becomes warned');

select is(
  (select warning_acknowledged from public.profiles where id = (select v from t where k = 'pirate')),
  false,
  'warning_acknowledged is false on warning');

-- 5. User acknowledges warning
select pg_temp.act_as((select v from t where k = 'pirate'));
select lives_ok(
  $$ select public.acknowledge_warning() $$,
  'warned user can acknowledge warning');

select is(
  (select warning_acknowledged from public.profiles where id = (select v from t where k = 'pirate')),
  true,
  'warning_acknowledged is set to true');

-- 6. User cannot tamper with strikes or status
select pg_temp.act_as((select v from t where k = 'pirate'));
set local role authenticated;

select throws_ok(
  $$ update public.profiles set strikes_count = 0 where id = (select v from t where k = 'pirate') $$,
  '42501',
  null,
  'user cannot clear strikes');

select throws_ok(
  $$ update public.profiles set moderation_status = 'clean' where id = (select v from t where k = 'pirate') $$,
  '42501',
  null,
  'user cannot reset moderation status');

reset role;

-- 7. Strike 2: Indefinite Ban
do $$
begin
  perform public.admin_warn_user(
    p_user_id => (select v from t where k = 'pirate'),
    p_reason => 'Second copyright strike: repeated pirated media'
  );
end $$;

select is(
  (select strikes_count from public.profiles where id = (select v from t where k = 'pirate')),
  2,
  'Strike 2 results in 2 strikes');

select is(
  (select moderation_status from public.profiles where id = (select v from t where k = 'pirate')),
  'banned',
  'Strike 2 sets moderation_status to banned');

-- Banned user cannot create or join rooms
select pg_temp.act_as((select v from t where k = 'pirate'));
select throws_ok(
  $$ select public.create_room('Pirate party', 60) $$,
  'account_banned',
  'banned user cannot create rooms');

select throws_ok(
  $$ select public.join_room((select code from public.rooms where id = (select v from t where k = 'room'))) $$,
  'account_banned',
  'banned user cannot join rooms');

-- 8. Room Ban by Admin
do $$
begin
  perform public.admin_ban_room(
    p_room_id => (select v from t where k = 'room'),
    p_reason => 'Infringing copyright content'
  );
end $$;

select is(
  (select is_banned from public.rooms where id = (select v from t where k = 'room')),
  true,
  'admin_ban_room marks room as banned');

-- Non-banned user trying to join a banned room
select pg_temp.act_as((select v from t where k = 'reporter'));
select throws_ok(
  $$ select public.join_room((select code from public.rooms where id = (select v from t where k = 'room'))) $$,
  'room_closed_by_admin',
  'joining a banned room raises room_closed_by_admin');

-- 9. Moderation Actions table is protected
select ok(
  not has_table_privilege('authenticated', 'public.moderation_actions', 'SELECT'),
  'moderation_actions is not readable by authenticated users');

rollback;
