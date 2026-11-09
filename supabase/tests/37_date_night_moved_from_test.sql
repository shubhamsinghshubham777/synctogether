begin;
select plan(8);

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
select pg_temp.act_as((select v from t where k = 'maya'));
select public.register_push_token('ios', 'maya-ios-token-0001', 'sandbox');
insert into c select 'code', (public.create_pair_invite()).code;
select pg_temp.act_as((select v from t where k = 'sam'));
select public.register_push_token('ios', 'sam-ios-token-00001', 'sandbox');
select public.accept_pair_invite((select v from c where k = 'code'));
insert into public.subscriptions (user_id, tier, current_period_end)
values ((select v from t where k = 'maya'), 'premium', now() + interval '30 days');

select pg_temp.act_as((select v from t where k = 'maya'));
insert into t select 'night', (public.create_date_night('Spirited Away', now() + interval '2 days')).id;

select is((select moved_from from public.date_nights where id = (select v from t where k = 'night')), null,
  'a new night has not been moved');

insert into c select 'orig', (select starts_at::text from public.date_nights where id = (select v from t where k = 'night'));

-- Sam moves it: the card remembers where it was.
select pg_temp.act_as((select v from t where k = 'sam'));
select public.reschedule_date_night((select v from t where k = 'night'), now() + interval '4 days');
select is((select moved_from::text from public.date_nights where id = (select v from t where k = 'night')),
  (select v from c where k = 'orig'), 'moving a night records the time it moved from');
select is((select proposed_by from public.date_nights where id = (select v from t where k = 'night')),
  (select v from t where k = 'sam'), 'and hands the answer to the other person');

-- Moving it again before it is answered keeps the original time, not the interim one.
select pg_temp.act_as((select v from t where k = 'maya'));
select public.reschedule_date_night((select v from t where k = 'night'), now() + interval '6 days');
select is((select moved_from::text from public.date_nights where id = (select v from t where k = 'night')),
  (select v from c where k = 'orig'), 'a second move before an answer still shows the first time');

-- Accepting the new time clears it.
select pg_temp.act_as((select v from t where k = 'sam'));
select public.respond_date_night((select v from t where k = 'night'), true);
select is((select moved_from from public.date_nights where id = (select v from t where k = 'night')), null,
  'accepting the new time clears the old one');
select is((select status from public.date_nights where id = (select v from t where k = 'night')),
  'accepted', 'and the night is accepted');

-- Moving an accepted night records it afresh.
select public.reschedule_date_night((select v from t where k = 'night'), now() + interval '8 days');
select isnt((select moved_from from public.date_nights where id = (select v from t where k = 'night')), null,
  'moving an accepted night records where it was');

-- A decline keeps it, since the card still describes that move.
select pg_temp.act_as((select v from t where k = 'maya'));
select public.respond_date_night((select v from t where k = 'night'), false);
select isnt((select moved_from from public.date_nights where id = (select v from t where k = 'night')), null,
  'declining the new time keeps the record of the move');

select * from finish();
rollback;
