begin;
select plan(14);

create function pg_temp.mk_user(p_guest boolean default false) returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_id, p_guest,
    case when p_guest then null else 'u' || replace(v_id::text, '-', '') || '@example.test' end, '{}'::jsonb);
  return v_id;
end $$;

create function pg_temp.act_as(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid)::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

create temp table t (k text primary key, v uuid);
grant all on t to public;
insert into t values ('a', pg_temp.mk_user()), ('g', pg_temp.mk_user(true)), ('b', pg_temp.mk_user());

select pg_temp.act_as((select v from t where k = 'a'));
create temp table c (k text primary key, v text);
grant all on c to public;
insert into c select 'code', code from public.submit_bug_report('video', 'went black', '{"app":"1.4.1"}', 'evt1');

select matches((select v from c where k = 'code'), '^BUG-[A-HJ-NP-Z2-9]{4}$',
  'a report returns a BUG-XXXX code from the unambiguous alphabet');

select throws_ok($$select * from public.submit_bug_report('video', 'again', '{}', null)$$,
  '54000', 'rate_limited', 'a second report inside 30 s is refused');

select is((select count(*)::int from public.my_bug_reports()), 1, 'the owner lists their report');
select is((select status from public.my_bug_reports() limit 1), 'received', 'new reports start as received');
select is((select title from public.my_bug_reports() limit 1), 'went black', 'the title is the note');

select throws_ok($$update public.bug_reports set status = 'fixed'$$,
  '42501', null, 'clients cannot write status');
select throws_ok($$insert into public.bug_reports (code, user_id) values ('BUG-ZZZZ', gen_random_uuid())$$,
  '42501', null, 'clients cannot insert directly');

select throws_ok($$select * from public.submit_bug_report('nonsense', null, '{}', null)$$,
  '22023', 'invalid_category', 'unknown categories are refused');

select pg_temp.act_as((select v from t where k = 'b'));
select is((select count(*)::int from public.bug_reports), 0, 'another user sees none of it');
select is((select count(*)::int from public.my_bug_reports()), 0, 'my_bug_reports is scoped to the caller');

select throws_ok(format($$select * from public.submit_bug_report(null, %L, '{}', null)$$, repeat('x', 2001)),
  '22023', 'note_too_long', 'notes over 2000 chars are refused');
select throws_ok(format($$select * from public.submit_bug_report(null, null, jsonb_build_object('k', %L), null)$$, repeat('x', 20000)),
  '22023', 'context_too_large', 'oversized context is refused');

select pg_temp.act_as((select v from t where k = 'g'));
select lives_ok($$select * from public.submit_bug_report(null, null, '{}', null)$$, 'guests can report');

reset role;
select ok(not has_function_privilege('anon', 'public.submit_bug_report(text,text,jsonb,text)', 'execute'),
  'anon cannot call the RPC');

select * from finish();
rollback;
