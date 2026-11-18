begin;
select plan(7);

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
insert into t values ('maya', pg_temp.mk_user('Maya')), ('sam', pg_temp.mk_user('Sam')), ('lee', pg_temp.mk_user('Lee'));

do $$
declare v_code text; v_pair uuid; v_id uuid; v_maya uuid := (select v from t where k = 'maya');
begin
  perform pg_temp.act_as(v_maya);
  v_code := (public.create_pair_invite()).code;
  perform pg_temp.act_as((select v from t where k = 'sam'));
  perform public.accept_pair_invite(v_code);
  select pair_id into v_pair from public.pair_members where user_id = v_maya;
  insert into public.date_nights (pair_id, title, starts_at, proposed_by, status, attach_kind,
      file_name, file_size, upload_state, upload_bytes, media_r2_key)
    values (v_pair, 'Film night', now() + interval '1 hour', v_maya, 'accepted', 'file',
      'Film.mkv', 1000, 'ready', 1000, 'rooms/x/Film.mkv') returning id into v_id;
  insert into t values ('night', v_id);
end $$;

select ok(not has_function_privilege('authenticated', 'public.night_stream_source(uuid, uuid)', 'execute'),
  'a signed-in person cannot call it directly');
select ok(not has_function_privilege('anon', 'public.night_stream_source(uuid, uuid)', 'execute'),
  'nor can anyone anonymous');
select ok(has_function_privilege('service_role', 'public.night_stream_source(uuid, uuid)', 'execute'),
  'the function (service role) can');

select is((select media_r2_key from public.night_stream_source(
    (select v from t where k = 'maya'), (select v from t where k = 'night'))),
  'rooms/x/Film.mkv', 'the uploader gets the object');
select is((select file_size from public.night_stream_source(
    (select v from t where k = 'sam'), (select v from t where k = 'night'))),
  1000::bigint, 'so does the other person');
select is((select count(*)::int from public.night_stream_source(
    (select v from t where k = 'lee'), (select v from t where k = 'night'))),
  0, 'someone outside the pair gets nothing');
select is((select count(*)::int from public.night_stream_source(
    (select v from t where k = 'maya'), gen_random_uuid())),
  0, 'an unknown night gets nothing');

select * from finish();
rollback;
