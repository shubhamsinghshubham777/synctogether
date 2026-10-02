begin;
select plan(17);

create function pg_temp.mk_user() returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_id, false, 'u' || replace(v_id::text, '-', '') || '@example.test', '{}'::jsonb);
  return v_id;
end $$;

create temp table t (k text primary key, v uuid);

do $$
declare v_host uuid; v_room public.rooms;
begin
  v_host := pg_temp.mk_user();
  perform set_config('request.jwt.claims', json_build_object('sub', v_host)::text, true);
  v_room := public.create_room('AV room', 60);
  insert into t values ('host', v_host), ('room', v_room.id),
    ('a', pg_temp.mk_user()), ('b', pg_temp.mk_user());
  v_room := public.create_room('Other room', 60);
  insert into t values ('room2', v_room.id);
end $$;

select is(public.pick_av_endpoint((select v from t where k = 'room'), array['self', 'cloud']),
  'self', 'a fresh room takes the first endpoint');
select is((select av_endpoint from public.rooms where id = (select v from t where k = 'room')),
  'self', 'and is pinned to it');

select is(public.pick_av_endpoint((select v from t where k = 'room'), array['cloud', 'self']),
  'self', 'a pinned room stays put even when priorities change');

select is(public.pick_av_endpoint((select v from t where k = 'room'), array['self', 'cloud'],
  'self', (select v from t where k = 'a')),
  'cloud', 'one failure report moves that room');
select is((select count(*)::int from public.av_endpoint_state), 0,
  'but one reporter cannot mark the endpoint down for everyone');
select is(public.pick_av_endpoint((select v from t where k = 'room2'), array['self', 'cloud']),
  'self', 'so other rooms still get it');

select is(public.pick_av_endpoint((select v from t where k = 'room2'), array['self', 'cloud'],
  'self', (select v from t where k = 'a')), 'cloud', 'a repeat report from the same account');
select is((select count(*)::int from public.av_endpoint_state), 0,
  'still counts once');

select is(public.pick_av_endpoint((select v from t where k = 'room2'), array['self', 'cloud'],
  'self', (select v from t where k = 'b')), 'cloud', 'a second distinct reporter');
select ok((select exhausted_until > now() from public.av_endpoint_state where endpoint = 'self'),
  'reaches quorum and cools the endpoint down');

select is(public.pick_av_endpoint((select v from t where k = 'room'), array['self', 'cloud'],
  'cloud', (select v from t where k = 'host')),
  null, 'with every endpoint out, the answer is null');

select is(public.pick_av_endpoint((select v from t where k = 'room2'), array['self', 'cloud'],
  null, null, 'self'), 'self', 'a debug force pins even a cooling-down endpoint');

-- SFU cleanup queue.
delete from public.pending_av_cleanups;

do $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', (select v from t where k = 'a'))::text, true);
  perform public.join_room((select code from public.rooms where id = (select v from t where k = 'room')));
  perform public.leave_room((select v from t where k = 'room'));
end $$;
select is((select count(*)::int from public.pending_av_cleanups
           where room_id = (select v from t where k = 'room') and user_id = (select v from t where k = 'a')),
  1, 'a member leaving queues their removal from the call');

do $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', (select v from t where k = 'host'))::text, true);
  perform public.end_room((select v from t where k = 'room'));
end $$;
select is((select count(*)::int from public.pending_av_cleanups
           where room_id = (select v from t where k = 'room') and user_id is null),
  1, 'ending a room queues the SFU room delete');

update public.rooms set expires_at = expires_at where id = (select v from t where k = 'room');
select is((select count(*)::int from public.pending_av_cleanups
           where room_id = (select v from t where k = 'room') and user_id is null),
  1, 'touching an already-ended room queues nothing more');

delete from public.rooms where id = (select v from t where k = 'room2');
select is((select count(*)::int from public.pending_av_cleanups
           where room_id = (select v from t where k = 'room2') and user_id is null),
  1, 'deleting a live room queues its SFU delete');
select is((select count(*)::int from public.pending_av_cleanups
           where room_id = (select v from t where k = 'room2') and user_id is not null),
  0, 'without a participant row per cascaded member');

select * from finish();
rollback;
