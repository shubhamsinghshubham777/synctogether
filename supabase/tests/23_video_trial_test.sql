begin;
select plan(18);

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

create temp table t (k text primary key, v uuid);

create function pg_temp.id(p_k text) returns uuid
language sql as $$ select v from t where k = p_k $$;


do $$
declare v_free uuid; v_member uuid; v_premium uuid; v_guest uuid; v_outsider uuid;
begin
  v_free := pg_temp.mk_user();
  v_member := pg_temp.mk_user();
  v_premium := pg_temp.mk_user();
  v_guest := pg_temp.mk_user(true);
  v_outsider := pg_temp.mk_user();
  insert into public.subscriptions (user_id, tier, current_period_end)
  values (v_premium, 'premium', null);
  insert into t values ('free', v_free), ('member', v_member), ('premium', v_premium),
    ('guest', v_guest), ('outsider', v_outsider);

  perform pg_temp.act_as(v_free);
  insert into t values
    ('room1', (public.create_room('One', 60)).id),
    ('room2', (public.create_room('Two', 60)).id),
    ('room3', (public.create_room('Three', 60)).id);

  perform pg_temp.act_as(v_member);
  perform public.join_room((select code from public.rooms where id = pg_temp.id('room1')));

  perform pg_temp.act_as(v_premium);
  insert into t values ('premium_room', (public.create_room('Patron', 60)).id);

  perform pg_temp.act_as(v_guest);
  insert into t values ('guest_room', (public.create_room('Guest', 60)).id);
end $$;

select is((select video_trial_minutes || '/' || video_trials_per_day from public.tier_limits where tier = 'free'),
  '10/2', 'free rooms get one 10-minute trial, twice a day');
select is((select sum(video_trial_minutes)::int from public.tier_limits where tier <> 'free'),
  0, 'guests and premium have no trial');

-- A member who is not the creator starts it; it still belongs to the room.
do $$ begin perform pg_temp.act_as(pg_temp.id('member')); end $$;
select is(public.start_video_trial(pg_temp.id('room1'))->>'status', 'started',
  'any member of a free room can start the trial');
select ok((select video_trial_ends_at between now() + interval '9 minutes 59 seconds'
                                         and now() + interval '10 minutes 1 second'
           from public.rooms where id = pg_temp.id('room1')),
  'and it runs ten minutes from now');
select is((select host_id from public.video_trial_grants where room_id = pg_temp.id('room1')),
  pg_temp.id('free'), 'it counts against the creator, not whoever pressed');

do $$ begin perform pg_temp.act_as(pg_temp.id('free')); end $$;
select is(public.start_video_trial(pg_temp.id('room1'))->>'status', 'active',
  'a second press reports the running trial');
select is((select count(*)::int from public.video_trial_grants where room_id = pg_temp.id('room1')),
  1, 'without spending another');

select is(public.start_video_trial(pg_temp.id('room2'))->>'status', 'started',
  'the second room of the day gets one');
select is(public.start_video_trial(pg_temp.id('room3'))->>'status', 'daily_cap',
  'the third does not');

do $$ begin perform pg_temp.act_as(pg_temp.id('premium')); end $$;
select is(public.start_video_trial(pg_temp.id('premium_room'))->>'status', 'not_eligible',
  'a video room has nothing to try');
do $$ begin perform pg_temp.act_as(pg_temp.id('guest')); end $$;
select is(public.start_video_trial(pg_temp.id('guest_room'))->>'status', 'not_eligible',
  'a guest room gets no trial');

do $$ begin perform pg_temp.act_as(pg_temp.id('outsider')); end $$;
select throws_ok($$ select public.start_video_trial(pg_temp.id('room1')) $$,
  'not_a_member', 'a non-member cannot start it');

-- Running out. Back-dated, since now() cannot move inside the transaction.
update public.rooms set video_trial_ends_at = now() - interval '1 second'
where id = pg_temp.id('room1');
delete from public.pending_av_cleanups;

do $$ begin perform pg_temp.act_as(pg_temp.id('free')); end $$;
select is(public.start_video_trial(pg_temp.id('room1'))->>'status', 'trial_spent',
  'a finished trial is spent');

select is(public.close_video_trials(), 1, 'the sweep closes the finished trial');
select is((select kind from public.pending_av_cleanups where room_id = pg_temp.id('room1')),
  'revoke_camera', 'and queues the camera revocation on the SFU');
select is(public.close_video_trials(), 0, 'exactly once');

-- Ending and resuming is not a second trial.
do $$
begin
  perform public.end_room(pg_temp.id('room1'));
  perform public.resume_room(pg_temp.id('room1'), 60);
end $$;
select is(public.start_video_trial(pg_temp.id('room1'))->>'status', 'trial_spent',
  'resuming a room does not hand its trial back');

select ok(has_function_privilege('authenticated', 'public.start_video_trial(uuid)', 'execute')
          and not has_function_privilege('authenticated', 'public.close_video_trials()', 'execute'),
  'members may start a trial; only the server closes them');

select * from finish();
rollback;
