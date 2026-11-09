begin;
select plan(21);

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

create temp table t (k text primary key, v uuid);
create temp table c (k text primary key, v text);
insert into t values ('maya', pg_temp.mk_user('Maya Lin')), ('sam', pg_temp.mk_user('Sam Rivera'));

-- Devices, or the server would queue nothing; a pair; and Patron on Maya's side.
select pg_temp.act_as((select v from t where k = 'maya'));
select public.register_push_token('ios', 'maya-ios-token-0001', 'sandbox');
insert into c select 'code', (public.create_pair_invite()).code;
select pg_temp.act_as((select v from t where k = 'sam'));
select public.register_push_token('ios', 'sam-ios-token-00001', 'sandbox');
select public.accept_pair_invite((select v from c where k = 'code'));
insert into public.subscriptions (user_id, tier, current_period_end)
values ((select v from t where k = 'maya'), 'premium', now() + interval '30 days');

-- ---------------------------------------------------------------------------
-- What a night carries
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'maya'));
insert into t select 'with_link',
  (public.create_date_night('Spirited Away', now() + interval '3 days',
                            'https://www.youtube.com/watch?v=ByXuk9QqQkk')).id;
select is((select attach_kind from public.date_nights where id = (select v from t where k = 'with_link')),
  'youtube', 'a night with a link is a YouTube night');
select is((select youtube_url from public.date_nights where id = (select v from t where k = 'with_link')),
  'https://www.youtube.com/watch?v=ByXuk9QqQkk', 'and keeps the link');

select throws_ok($$ select public.create_date_night('Bad', now() + interval '3 days', 'https://example.com/watch?v=abc') $$,
  'invalid_link', 'a link that is not YouTube is refused');
select throws_ok($$ select public.create_date_night('Bad', now() + interval '3 days', 'javascript:alert(1)') $$,
  'invalid_link', 'and so is anything that is not a web address');

insert into t select 'plain', (public.create_date_night('Past Lives', now() + interval '4 days')).id;
select is((select attach_kind from public.date_nights where id = (select v from t where k = 'plain')),
  'none', 'no link means "we will choose together", the old flow');
select is((select youtube_url from public.date_nights where id = (select v from t where k = 'plain')),
  null, 'with nothing stored');

-- ---------------------------------------------------------------------------
-- Reminders say what is waiting
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'sam'));
select public.respond_date_night((select v from t where k = 'with_link'), true);
select public.respond_date_night((select v from t where k = 'plain'), true);

select is((select count(*)::int from public.push_outbox where kind = 'date_night_reminder'
           and data->>'night' = (select v::text from t where k = 'with_link')), 2,
  'both people get a reminder');
select ok((select bool_and(body = 'Spirited Away is ready. Open Our Room and press play.')
           from public.push_outbox where kind = 'date_night_reminder'
           and data->>'night' = (select v::text from t where k = 'with_link')),
  'which says the film is ready when one is attached');
select ok((select bool_and(body = 'Pick something together in Our Room.')
           from public.push_outbox where kind = 'date_night_reminder'
           and data->>'night' = (select v::text from t where k = 'plain')),
  'and says to choose together when none is');

-- ---------------------------------------------------------------------------
-- Changing what we are watching
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.set_date_night_attachment((select v from t where k = 'with_link'), null) $$,
  'not_planner', 'only the planner can change it');

select pg_temp.act_as((select v from t where k = 'maya'));
select is((public.set_date_night_attachment((select v from t where k = 'with_link'), null)).attach_kind,
  'none', 'the planner can take the link off');
select ok((select bool_and(body = 'Pick something together in Our Room.')
           from public.push_outbox where kind = 'date_night_reminder'
           and data->>'night' = (select v::text from t where k = 'with_link')),
  'and the reminder is rewritten to match');
select is((select count(*)::int from public.push_outbox where kind = 'date_night_reminder'
           and data->>'night' = (select v::text from t where k = 'with_link')), 2,
  'replacing, not adding, a second reminder');
select throws_ok($$ select public.set_date_night_attachment((select v from t where k = 'with_link'), 'https://example.com/x') $$,
  'invalid_link', 'a new link is checked too');
select is((public.set_date_night_attachment((select v from t where k = 'with_link'),
           'https://youtu.be/ByXuk9QqQkk')).attach_kind, 'youtube', 'and a good one goes on');

-- ---------------------------------------------------------------------------
-- The night starts: the film is already in Our Room
-- ---------------------------------------------------------------------------
select public.cancel_date_night((select v from t where k = 'with_link'));
select public.cancel_date_night((select v from t where k = 'plain'));

-- A night ten minutes away is "on" (the window opens 15 minutes before).
insert into t select 'tonight',
  (public.create_date_night('Perfect Days', now() + interval '10 minutes',
                            'https://youtu.be/ByXuk9QqQkk')).id;
select pg_temp.act_as((select v from t where k = 'sam'));
select public.respond_date_night((select v from t where k = 'tonight'), true);

select pg_temp.act_as((select v from t where k = 'maya'));
select is((public.open_our_room()).media_kind, 'youtube', 'opening Our Room on the night loads the film');
select is((select media_name from public.rooms where pair_id = public.my_pair_id()), 'Perfect Days',
  'under the night''s title');
select ok((select media_applied_at is not null from public.date_nights where id = (select v from t where k = 'tonight')),
  'and notes that it has been loaded');

-- Cleared by the couple: it must not come back on the next opening.
update public.rooms set media_kind = 'none', media_url = null, media_name = null
  where pair_id = public.my_pair_id();
select is((public.open_our_room()).media_kind, 'none', 'once loaded it is never forced back in');

-- A session that already has something chosen is never overridden.
update public.rooms set media_kind = 'youtube', media_url = 'https://youtu.be/AAAAAAAAAAA', media_name = 'Chosen'
  where pair_id = public.my_pair_id();
insert into t select 'second',
  (public.create_date_night('Another', now() + interval '12 minutes', 'https://youtu.be/BBBBBBBBBBB')).id;
select pg_temp.act_as((select v from t where k = 'sam'));
select public.respond_date_night((select v from t where k = 'second'), true);
select pg_temp.act_as((select v from t where k = 'maya'));
select is((public.open_our_room()).media_url, 'https://youtu.be/AAAAAAAAAAA',
  'what the two of them chose is not replaced by the plan');

-- A night days away is not "on".
select public.cancel_date_night((select v from t where k = 'second'));
update public.rooms set media_kind = 'none', media_url = null, media_name = null
  where pair_id = public.my_pair_id();
insert into t select 'later',
  (public.create_date_night('Next week', now() + interval '2 days', 'https://youtu.be/CCCCCCCCCCC')).id;
select pg_temp.act_as((select v from t where k = 'sam'));
select public.respond_date_night((select v from t where k = 'later'), true);
select pg_temp.act_as((select v from t where k = 'maya'));
select is((public.open_our_room()).media_kind, 'none', 'a night two days away loads nothing yet');

select * from finish();
rollback;
