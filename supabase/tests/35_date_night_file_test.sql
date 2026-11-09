begin;
select plan(42);

create function pg_temp.mk_user(p_name text) returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_id, false, 'u' || replace(v_id::text, '-', '') || '@example.test',
          jsonb_build_object('full_name', p_name));
  return v_id;
end $$;

create function pg_temp.act_as(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid)::text, true);
end $$;

-- A staged upload slot, as the Edge Function's staged-initiate would leave it.
create function pg_temp.mk_staged(p_uid uuid, p_state text default 'uploading') returns uuid
language plpgsql as $$
declare v_id uuid;
begin
  insert into public.staged_media_uploads (user_id, file_name, file_size, r2_key, upload_id, upload_state)
  values (p_uid, 'film.mkv', 1000000000,
          'users/' || p_uid::text || '/staged/' || gen_random_uuid()::text,
          case when p_state = 'uploading' then 'mp-' || gen_random_uuid()::text end, p_state)
  returning id into v_id;
  return v_id;
end $$;

create temp table t (k text primary key, v uuid);
create temp table c (k text primary key, v text);
insert into t values ('maya', pg_temp.mk_user('Maya Lin')), ('sam', pg_temp.mk_user('Sam Rivera'));

select pg_temp.act_as((select v from t where k = 'maya'));
select public.register_push_token('ios', 'maya-ios-token-0001', 'sandbox');
insert into c select 'code', (public.create_pair_invite()).code;
select pg_temp.act_as((select v from t where k = 'sam'));
select public.register_push_token('ios', 'sam-ios-token-00001', 'sandbox');
select public.accept_pair_invite((select v from c where k = 'code'));
insert into public.subscriptions (user_id, tier, current_period_end)
values ((select v from t where k = 'maya'), 'premium', now() + interval '30 days');

-- ---------------------------------------------------------------------------
-- Adopting the upload slot
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'maya'));
insert into t select 'slot_a', pg_temp.mk_staged((select v from t where k = 'maya'));
insert into t select 'night_a',
  (public.create_date_night('Spirited Away', now() + interval '3 days', null,
                            (select v from t where k = 'slot_a'))).id;

select is((select attach_kind from public.date_nights where id = (select v from t where k = 'night_a')),
  'file', 'a night that adopts a slot is a file night');
select is((select upload_state from public.date_nights where id = (select v from t where k = 'night_a')),
  'uploading', 'and starts as uploading');
select is((select file_name from public.date_nights where id = (select v from t where k = 'night_a')),
  'film.mkv', 'with the file''s name');
select is((select date_night_id from public.staged_media_uploads where id = (select v from t where k = 'slot_a')),
  (select v from t where k = 'night_a'), 'and the slot knows which night it is for');
select ok((select expires_at > now() + interval '3 days' from public.staged_media_uploads where id = (select v from t where k = 'slot_a')),
  'the slot is held until a day after the night, not an hour');

insert into t select 'slot_b', pg_temp.mk_staged((select v from t where k = 'maya'));
select throws_ok(format($$ select public.create_date_night('Two', now() + interval '4 days', null, %L) $$,
  (select v from t where k = 'slot_b')), 'upload_in_progress',
  'one upload at a time, so nobody queues up bandwidth');
select throws_ok(format($$ select public.create_date_night('Both', now() + interval '4 days', 'https://youtu.be/ByXuk9QqQkk', %L) $$,
  (select v from t where k = 'slot_b')), 'invalid_attachment', 'a link and a file together is refused');

insert into t select 'slot_sam', pg_temp.mk_staged((select v from t where k = 'sam'));
select throws_ok(format($$ select public.create_date_night('Not mine', now() + interval '4 days', null, %L) $$,
  (select v from t where k = 'slot_sam')), 'staged_media_invalid', 'a slot that is not yours cannot be adopted');
select is((select count(*)::int from public.date_nights), 1, 'and none of those refusals left a night behind');

-- ---------------------------------------------------------------------------
-- Progress, and the connection dropping
-- ---------------------------------------------------------------------------
select public.set_date_night_upload_progress((select v from t where k = 'night_a'), 400000000);
select is((select upload_bytes from public.date_nights where id = (select v from t where k = 'night_a')),
  400000000::bigint, 'the planner''s progress is recorded');
select public.set_date_night_upload_progress((select v from t where k = 'night_a'), 100000000);
select is((select upload_bytes from public.date_nights where id = (select v from t where k = 'night_a')),
  400000000::bigint, 'and never goes backwards');

select pg_temp.act_as((select v from t where k = 'sam'));
select throws_ok(format($$ select public.set_date_night_upload_progress(%L, 1) $$,
  (select v from t where k = 'night_a')), 'not_planner', 'only the planner reports progress');

select pg_temp.act_as((select v from t where k = 'maya'));
select public.set_date_night_upload_progress((select v from t where k = 'night_a'), 400000000, 'stopped');
select is((select upload_state from public.date_nights where id = (select v from t where k = 'night_a')),
  'stopped', 'a dropped connection is a stopped upload');
select is((select count(*)::int from public.push_outbox where kind = 'date_night_upload'
           and user_id = (select v from t where k = 'maya')), 1, 'the planner is told, once');
select is((select title || ' / ' || body from public.push_outbox where kind = 'date_night_upload'),
  'Your upload paused / Spirited Away stopped at 40%. Open SyncTogether to carry on.',
  'in the words on the board');
select public.set_date_night_upload_progress((select v from t where k = 'night_a'), 400000000, 'stopped');
select is((select count(*)::int from public.push_outbox where kind = 'date_night_upload'), 1,
  'reporting it again does not nag');
select public.set_date_night_upload_progress((select v from t where k = 'night_a'), 450000000, 'uploading');
select is((select upload_state from public.date_nights where id = (select v from t where k = 'night_a')),
  'uploading', 'it picks up again');
select is((select count(*)::int from public.push_outbox where kind = 'date_night_upload'), 0,
  'and the pause notice is withdrawn if it had not gone out');

-- ---------------------------------------------------------------------------
-- Sam says yes; the reminder tells the truth about the film
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'sam'));
select public.respond_date_night((select v from t where k = 'night_a'), true);
select is((select public.date_night_reminder_body(n) from public.date_nights n where n.id = (select v from t where k = 'night_a')),
  'Spirited Away is still arriving (45%). The room opens on time.', 'while it uploads the reminder says how far it is');
select is((select count(*)::int from public.push_outbox where kind = 'date_night_ready'), 0,
  'and there is no "ready" yet');

-- The upload finishes.
select public.set_staged_upload_state((select v from t where k = 'slot_a'),
  (select v from t where k = 'maya'), 'ready', 1000000000, null, 0);
select is((select upload_state from public.date_nights where id = (select v from t where k = 'night_a')),
  'ready', 'finishing the upload makes the night ready');
select is((select title from public.push_outbox where kind = 'date_night_ready'), 'Your movie is ready',
  'Sam is told');
select is((select user_id from public.push_outbox where kind = 'date_night_ready'), (select v from t where k = 'sam'),
  'and only Sam');
select is((select public.date_night_reminder_body(n) from public.date_nights n where n.id = (select v from t where k = 'night_a')),
  'Spirited Away is ready. Open Our Room and press play.', 'and the reminder now says it is ready');

-- ---------------------------------------------------------------------------
-- The night starts: Our Room claims the file
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'maya'));
insert into t select 'slot_j', pg_temp.mk_staged((select v from t where k = 'maya'), 'ready');
insert into t select 'night_j',
  (public.create_date_night('Perfect Days', now() + interval '10 minutes', null,
                            (select v from t where k = 'slot_j'))).id;
select is((select upload_state from public.date_nights where id = (select v from t where k = 'night_j')),
  'ready', 'a slot that had already finished makes a ready night');
select pg_temp.act_as((select v from t where k = 'sam'));
select public.respond_date_night((select v from t where k = 'night_j'), true);
select pg_temp.act_as((select v from t where k = 'maya'));
select is((public.open_our_room()).media_kind, 'local', 'opening Our Room on the night loads the file');
select is((select media_upload_state from public.rooms where pair_id = public.my_pair_id()), 'ready',
  'as streamable media, which is what the members need');
select is((select media_r2_key from public.rooms where pair_id = public.my_pair_id()),
  (select r2_key from public.staged_media_uploads where id = (select v from t where k = 'slot_j')),
  'the room holds the very object that was uploaded');
select is((select claimed_room_id from public.staged_media_uploads where id = (select v from t where k = 'slot_j')),
  (select id from public.rooms where pair_id = public.my_pair_id()), 'and the slot is claimed by it');
select is((select count(*)::int from public.pending_r2_deletions
           where r2_key = (select r2_key from public.staged_media_uploads where id = (select v from t where k = 'slot_j'))),
  0, 'so nothing is queued to delete the file the room now owns');

-- ---------------------------------------------------------------------------
-- Still uploading when the night starts, then it lands
-- ---------------------------------------------------------------------------
update public.rooms set media_kind = 'none', media_name = null, media_url = null,
  media_r2_key = null, media_file_size = null, media_upload_state = 'none', media_duration_ms = null
  where pair_id = public.my_pair_id();
insert into t select 'slot_k', pg_temp.mk_staged((select v from t where k = 'maya'));
insert into t select 'night_k',
  (public.create_date_night('Past Lives', now() + interval '12 minutes', null,
                            (select v from t where k = 'slot_k'))).id;
select pg_temp.act_as((select v from t where k = 'sam'));
select public.respond_date_night((select v from t where k = 'night_k'), true);
select pg_temp.act_as((select v from t where k = 'maya'));
select is((public.open_our_room()).media_kind, 'none', 'an upload that is not done is not loaded, and does not block the room');
select public.set_staged_upload_state((select v from t where k = 'slot_k'),
  (select v from t where k = 'maya'), 'ready', 1000000000, null, 0);
select is((select media_kind from public.rooms where pair_id = public.my_pair_id()), 'local',
  'when it lands, with the room live and empty, it is handed over');

-- ---------------------------------------------------------------------------
-- Letting the file go
-- ---------------------------------------------------------------------------
insert into t select 'slot_l', pg_temp.mk_staged((select v from t where k = 'maya'), 'ready');
insert into t select 'night_l',
  (public.create_date_night('Cancelled', now() + interval '2 days', null, (select v from t where k = 'slot_l'))).id;
select public.cancel_date_night((select v from t where k = 'night_l'));
select is((select count(*)::int from public.staged_media_uploads where id = (select v from t where k = 'slot_l')), 0,
  'cancelling a night frees its file at once');
select is((select attach_kind from public.date_nights where id = (select v from t where k = 'night_l')), 'none',
  'and the night no longer promises one');
select ok(exists (select 1 from public.pending_r2_deletions
                  where r2_key like 'users/' || (select v::text from t where k = 'maya') || '/staged/%'), 'the object is queued for deletion');

insert into t select 'slot_m', pg_temp.mk_staged((select v from t where k = 'maya'), 'ready');
insert into t select 'night_m',
  (public.create_date_night('Swapped', now() + interval '2 days', null, (select v from t where k = 'slot_m'))).id;
select is((public.set_date_night_attachment((select v from t where k = 'night_m'), 'https://youtu.be/ByXuk9QqQkk')).attach_kind,
  'youtube', 'swapping the file for a link works');
select is((select count(*)::int from public.staged_media_uploads where id = (select v from t where k = 'slot_m')), 0,
  'and lets the file go');

insert into t select 'slot_n', pg_temp.mk_staged((select v from t where k = 'maya'), 'ready');
insert into t select 'night_n',
  (public.create_date_night('Long ago', now() + interval '2 days', null, (select v from t where k = 'slot_n'))).id;
update public.date_nights set starts_at = now() - interval '2 days' where id = (select v from t where k = 'night_n');
select is(public.sweep_date_night_files(), 1, 'a day after the night an unused file is swept');
select is((select count(*)::int from public.staged_media_uploads where id = (select v from t where k = 'slot_n')), 0,
  'and is gone');

-- A finished upload that simply expired is not an abandoned one.
insert into t select 'slot_o', pg_temp.mk_staged((select v from t where k = 'maya'), 'ready');
insert into t select 'night_o',
  (public.create_date_night('Kept too long', now() + interval '2 days', null, (select v from t where k = 'slot_o'))).id;
select public.clear_staged_upload((select v from t where k = 'slot_o'), 0);
select is((select r2_consecutive_aborts from public.profiles where id = (select v from t where k = 'maya')), 0,
  'clearing it afterwards does not count as an abort against the person');

-- An aborted upload takes the file off the night.
insert into t select 'slot_q', pg_temp.mk_staged((select v from t where k = 'maya'));
insert into t select 'night_q',
  (public.create_date_night('Abandoned', now() + interval '2 days', null, (select v from t where k = 'slot_q'))).id;
select public.clear_staged_upload((select v from t where k = 'slot_q'), 0);
select is((select attach_kind from public.date_nights where id = (select v from t where k = 'night_q')), 'none',
  'aborting an upload leaves a night that no longer promises a file');
select is((select r2_consecutive_aborts from public.profiles where id = (select v from t where k = 'maya')), 1,
  'and an actual abort still counts');

select * from finish();
rollback;
