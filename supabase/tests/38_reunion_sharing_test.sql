begin;
select plan(11);

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

-- Shared by default: either of them can set and change it.
select pg_temp.act_as((select v from t where k = 'maya'));
select public.set_reunion('2026-12-26', 'Heathrow');
select is((public.my_pair())->>'reunion_shared_edit', 'true', 'a new date is editable by both');
select pg_temp.act_as((select v from t where k = 'sam'));
select lives_ok($$ select public.set_reunion('2026-12-27', 'Heathrow, Sunday') $$,
  'the other partner can change a shared date');
select is((public.my_pair())->>'reunion_set_by', (select v::text from t where k = 'sam'),
  'and is now the one who set it');

-- Locking it to yourself.
select public.set_reunion('2026-12-27', 'Heathrow, Sunday', false);
select is((public.my_pair())->>'reunion_shared_edit', 'false', 'the person who set it can lock it');
select pg_temp.act_as((select v from t where k = 'maya'));
select throws_ok($$ select public.set_reunion('2026-12-30', 'Changed') $$, 'reunion_locked',
  'the other person is refused while it is locked');
select throws_ok($$ select public.set_reunion(null, null) $$, 'reunion_locked',
  'and cannot clear it either');
select is((public.my_pair())->>'reunion_label', 'Heathrow, Sunday', 'the date is untouched');

-- The lobby switch is personal and always allowed.
select public.set_reunion('2026-12-27', 'Heathrow, Sunday', null, false);
select is((public.my_pair())->>'show_reunion', 'false', 'each person hides the countdown on their own lobby');
select pg_temp.act_as((select v from t where k = 'sam'));
select is((public.my_pair())->>'show_reunion', 'true', 'without hiding it for the other');

-- Clearing hands the date back to both.
select public.set_reunion(null, null);
select is((public.my_pair())->>'reunion_shared_edit', 'true', 'clearing makes the next date shared again');
select pg_temp.act_as((select v from t where k = 'maya'));
select lives_ok($$ select public.set_reunion('2027-01-02', 'New date') $$, 'so either can set a new one');

select * from finish();
rollback;
