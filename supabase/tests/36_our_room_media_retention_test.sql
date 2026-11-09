begin;
select plan(22);

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

-- A finished shared film in a room, as `set_media_upload_state('ready')` leaves it.
create function pg_temp.give_film(p_room uuid, p_key text) returns void
language sql as $$
  update public.rooms set
    media_kind = 'local', media_name = 'film.mkv', media_r2_key = p_key,
    media_file_size = 1000000, media_upload_state = 'ready', media_upload_id = null
  where id = p_room;
$$;

create temp table t (k text primary key, v uuid);
create temp table c (k text primary key, v text);

-- Two pairs: Maya & Sam (free), Ana & Raj (Ana has Patron).
insert into t values ('maya', pg_temp.mk_user('Maya Lin')), ('sam', pg_temp.mk_user('Sam Rivera')),
                     ('ana', pg_temp.mk_user('Ana Cruz')), ('raj', pg_temp.mk_user('Raj Patel'));

select pg_temp.act_as((select v from t where k = 'maya'));
select public.register_push_token('ios', 'maya-ios-token-0001', 'sandbox');
insert into c select 'code1', (public.create_pair_invite()).code;
select pg_temp.act_as((select v from t where k = 'sam'));
select public.register_push_token('ios', 'sam-ios-token-00001', 'sandbox');
select public.accept_pair_invite((select v from c where k = 'code1'));

select pg_temp.act_as((select v from t where k = 'ana'));
select public.register_push_token('ios', 'ana-ios-token-00001', 'sandbox');
insert into c select 'code2', (public.create_pair_invite()).code;
select pg_temp.act_as((select v from t where k = 'raj'));
select public.register_push_token('ios', 'raj-ios-token-00001', 'sandbox');
select public.accept_pair_invite((select v from c where k = 'code2'));
insert into public.subscriptions (user_id, tier, current_period_end)
values ((select v from t where k = 'ana'), 'premium', now() + interval '30 days');

select pg_temp.act_as((select v from t where k = 'maya'));
insert into t select 'free_room', (public.open_our_room()).id;
select pg_temp.act_as((select v from t where k = 'ana'));
insert into t select 'patron_room', (public.open_our_room()).id;

-- ---------------------------------------------------------------------------
-- The retention follows the better of the two tiers
-- ---------------------------------------------------------------------------
select is(public.our_room_media_retention((select pair_id from public.rooms where id = (select v from t where k = 'free_room'))),
  interval '36 hours', 'a free pair keeps its film 36 hours');
select is(public.our_room_media_retention((select pair_id from public.rooms where id = (select v from t where k = 'patron_room'))),
  interval '168 hours', 'a pair with one Patron keeps it 7 days, for both of them');

-- ---------------------------------------------------------------------------
-- Ending a session keeps a finished film, with a deadline
-- ---------------------------------------------------------------------------
select pg_temp.give_film((select v from t where k = 'free_room'), 'rooms/free/film.mkv');
select pg_temp.give_film((select v from t where k = 'patron_room'), 'rooms/patron/film.mkv');
select public.retire_room((select v from t where k = 'free_room'));
select public.retire_room((select v from t where k = 'patron_room'));

select is((select media_r2_key from public.rooms where id = (select v from t where k = 'free_room')),
  'rooms/free/film.mkv', 'the free pair''s film is still there after the session');
select is((select media_upload_state from public.rooms where id = (select v from t where k = 'free_room')),
  'ready', 'and still ready');
select is((select count(*)::int from public.pending_r2_deletions where r2_key like 'rooms/free/%'), 0,
  'it is not queued for deletion');
select ok((select media_expires_at between now() + interval '35 hours 59 minutes' and now() + interval '36 hours 1 minute'
           from public.rooms where id = (select v from t where k = 'free_room')),
  'its deadline is 36 hours out');
select ok((select media_expires_at between now() + interval '167 hours 59 minutes' and now() + interval '168 hours 1 minute'
           from public.rooms where id = (select v from t where k = 'patron_room')),
  'the Patron pair''s is 7 days out');

-- Retiring again must not push the deadline out.
update public.rooms set media_expires_at = now() + interval '5 hours'
where id = (select v from t where k = 'free_room');
select public.retire_room((select v from t where k = 'free_room'));
select ok((select media_expires_at < now() + interval '6 hours' from public.rooms where id = (select v from t where k = 'free_room')),
  'ending an already-ended room again does not extend the deadline');

-- ---------------------------------------------------------------------------
-- Restarting before the deadline takes the clock off the file
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'maya'));
select public.open_our_room();
select is((select media_expires_at from public.rooms where id = (select v from t where k = 'free_room')), null,
  'a restart removes the deadline');
select is((select media_r2_key from public.rooms where id = (select v from t where k = 'free_room')),
  'rooms/free/film.mkv', 'and the film is still there, ready to stream, nothing to upload');
select is((select media_upload_state from public.rooms where id = (select v from t where k = 'free_room')),
  'ready', 'in the ready state');

-- ---------------------------------------------------------------------------
-- After the deadline the sweep releases it and says so
-- ---------------------------------------------------------------------------
select public.retire_room((select v from t where k = 'free_room'));
update public.rooms set media_expires_at = now() - interval '1 minute'
where id = (select v from t where k = 'free_room');
select public.sweep_rooms();

select is((select media_r2_key from public.rooms where id = (select v from t where k = 'free_room')), null,
  'past its deadline the object is released');
select is((select media_upload_state from public.rooms where id = (select v from t where k = 'free_room')),
  'none', 'the room no longer claims a shared copy');
select is((select count(*)::int from public.pending_r2_deletions where r2_key = 'rooms/free/film.mkv'), 1,
  'and the object is queued for deletion exactly once');
select isnt((select media_share_expired_at from public.rooms where id = (select v from t where k = 'free_room')), null,
  'the room records that its shared copy expired');
select is((select media_expires_at from public.rooms where id = (select v from t where k = 'free_room')), null,
  'with no deadline left');
select is((select media_name from public.rooms where id = (select v from t where k = 'free_room')),
  'film.mkv', 'the film''s name is kept, so the app can say which one');

-- The Patron pair's film is not due yet, and a sweep leaves it alone.
select is((select media_r2_key from public.rooms where id = (select v from t where k = 'patron_room')),
  'rooms/patron/film.mkv', 'a film still inside its window survives the sweep');

-- The notice goes when the media or its sharing changes.
update public.rooms set media_name = 'other.mkv' where id = (select v from t where k = 'free_room');
select is((select media_share_expired_at from public.rooms where id = (select v from t where k = 'free_room')), null,
  'choosing different media clears the expired notice');

-- ---------------------------------------------------------------------------
-- What must not change
-- ---------------------------------------------------------------------------
-- An unfinished upload is aborted when the session ends, as before.
select pg_temp.act_as((select v from t where k = 'ana'));
select public.open_our_room();
update public.rooms set media_kind = 'local', media_name = 'half.mkv',
  media_r2_key = 'rooms/partial/half.mkv', media_upload_id = 'mp-partial-1', media_upload_state = 'uploading'
where id = (select v from t where k = 'patron_room');
select public.retire_room((select v from t where k = 'patron_room'));
select is((select count(*)::int from public.pending_r2_deletions where upload_id = 'mp-partial-1'), 1,
  'an unfinished upload is still aborted at once when the session ends');

-- An ordinary room's finished film is still queued at once.
insert into t select 'plain', gen_random_uuid();
insert into public.rooms (id, code, name, created_by, duration_minutes, expires_at)
values ((select v from t where k = 'plain'), 'PLAIN1', 'Plain', (select v from t where k = 'sam'), 60, now() + interval '1 hour');
select pg_temp.give_film((select v from t where k = 'plain'), 'rooms/plain/film.mkv');
select public.retire_room((select v from t where k = 'plain'));
select is((select count(*)::int from public.pending_r2_deletions where r2_key = 'rooms/plain/film.mkv'), 1,
  'a friends'' room still queues its film for deletion when it ends');
select is((select media_expires_at from public.rooms where id = (select v from t where k = 'plain')), null,
  'and gets no retention deadline');

select * from finish();
rollback;
