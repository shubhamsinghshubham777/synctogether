begin;
select plan(38);

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
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid)::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

create temp table t (k text primary key, v uuid);
grant all on t to public;
insert into t values ('a', pg_temp.mk_user()), ('b', pg_temp.mk_user()), ('c', pg_temp.mk_user());

-- Original, two reporters of the same thing, and an unrelated report.
insert into public.bug_reports (code, user_id, category, note) values
  ('BUG-AAAA', (select v from t where k = 'a'), 'chat', 'secret note A from the original reporter'),
  ('BUG-BBBB', (select v from t where k = 'b'), 'chat', 'secret note B'),
  ('BUG-CCCC', (select v from t where k = 'c'), 'chat', 'secret note C'),
  ('BUG-DDDD', (select v from t where k = 'a'), 'video', 'something else');

-- ---- constraints ---------------------------------------------------------
select throws_ok($$update public.bug_reports set status = 'wontfix' where code = 'BUG-AAAA'$$,
  '23514', null, 'won''t fix without a reason is refused');
select throws_ok($$update public.bug_reports set status = 'wontfix', reason = ' too   short ' where code = 'BUG-AAAA'$$,
  '23514', null, 'a reason under 20 non-space characters is refused');
select throws_ok($$update public.bug_reports set status = 'duplicate' where code = 'BUG-BBBB'$$,
  '23514', null, 'duplicate without an original is refused');
select throws_ok($$update public.bug_reports set status = 'fixed' where code = 'BUG-AAAA'$$,
  '23514', null, 'fixed without a version is refused');
select throws_ok($$update public.bug_reports set status = 'duplicate', duplicate_of = id where code = 'BUG-AAAA'$$,
  '22023', 'cannot_duplicate_self', 'a report cannot be a duplicate of itself');
select lives_ok($$update public.bug_reports set status = 'wontfix', reason = 'This is how the fold works on purpose.' where code = 'BUG-DDDD'$$,
  'a won''t fix with a real reason is accepted');
select is((select closed_at is not null from public.bug_reports where code = 'BUG-DDDD'), true,
  'closing stamps closed_at');
select lives_ok($$update public.bug_reports set status = 'received' where code = 'BUG-DDDD'$$, 'reopening works');
select is((select (reason is null and closed_at is null and fixed_in is null and duplicate_of is null)
  from public.bug_reports where code = 'BUG-DDDD'), true, 'reopening clears reason, version, link and closed_at');

-- ---- following an original -------------------------------------------------
update public.bug_reports set status = 'looking' where code = 'BUG-AAAA';
update public.bug_reports set status = 'duplicate',
  duplicate_of = (select id from public.bug_reports where code = 'BUG-AAAA') where code = 'BUG-BBBB';
-- CCCC points at BBBB (a follower): it must resolve to the root, AAAA.
update public.bug_reports set status = 'duplicate',
  duplicate_of = (select id from public.bug_reports where code = 'BUG-BBBB') where code = 'BUG-CCCC';
select is((select duplicate_of from public.bug_reports where code = 'BUG-CCCC'),
  (select id from public.bug_reports where code = 'BUG-AAAA'),
  'a duplicate of a duplicate resolves to the root original');
select throws_ok($$update public.bug_reports set status = 'duplicate',
  duplicate_of = (select id from public.bug_reports where code = 'BUG-BBBB') where code = 'BUG-AAAA'$$,
  '22023', 'cannot_duplicate_self', 'a cycle back to the root is refused');
select throws_ok($$update public.bug_reports set status = 'duplicate', duplicate_of = gen_random_uuid() where code = 'BUG-DDDD'$$,
  'P0002', 'unknown_original', 'an unknown original is refused');

-- ---- cascades ----------------------------------------------------------
update public.bug_reports set status = 'fixed', fixed_in = '1.4.2' where code = 'BUG-AAAA';
select results_eq($$select status, fixed_in from public.bug_reports where code in ('BUG-BBBB', 'BUG-CCCC') order by code$$,
  $$values ('fixed'::text, '1.4.2'::text), ('fixed'::text, '1.4.2'::text)$$,
  'fixing the original fixes every follower in the same version');
select is((select count(*)::int from public.bug_reports where duplicate_of is not null), 2,
  'followers keep their link while mirrored');

update public.bug_reports set status = 'wontfix', fixed_in = null,
  reason = 'Works as designed, the bar steps aside from the hinge.' where code = 'BUG-AAAA';
select results_eq($$select status, reason from public.bug_reports where code in ('BUG-BBBB', 'BUG-CCCC') order by code$$,
  $$values ('wontfix'::text, 'Works as designed, the bar steps aside from the hinge.'::text),
           ('wontfix'::text, 'Works as designed, the bar steps aside from the hinge.'::text)$$,
  'closing the original closes followers with the same reason');

update public.bug_reports set status = 'looking' where code = 'BUG-AAAA';
select results_eq($$select status, reason, fixed_in from public.bug_reports where code in ('BUG-BBBB', 'BUG-CCCC') order by code$$,
  $$values ('duplicate'::text, null::text, null::text), ('duplicate'::text, null::text, null::text)$$,
  'reopening the original puts followers back to plain duplicate');

-- ---- what an owner sees, and what they must not ---------------------------
select pg_temp.act_as((select v from t where k = 'b'));
select is((select duplicate_of_code from public.my_bug_reports()), 'BUG-AAAA',
  'a follower sees the original''s code');
select is((select duplicate_of_status from public.my_bug_reports()), 'looking',
  'a follower sees the original''s live status');
select is((select same_count from public.my_bug_reports()), 2,
  'same_count is the other reports of the same issue');
select is((select duplicate_of_title from public.my_bug_reports()), 'Chat issue',
  'the original''s title falls back to a neutral category label');
select is(position('secret note A' in (select string_agg(to_jsonb(r)::text, ' ') from public.my_bug_reports() r)), 0,
  'the original''s note never reaches another user');
select is((select count(*)::int from public.bug_reports where code = 'BUG-AAAA'), 0,
  'RLS still hides the original row from a follower');

-- ---- owner-only RPCs ------------------------------------------------------
select lives_ok($$select public.set_bug_notify_when_fixed('BUG-BBBB', true)$$, 'owners can ask to be told');
select is((select notify_when_fixed from public.my_bug_reports()), true, 'the choice is stored');
select throws_ok($$select public.set_bug_notify_when_fixed('BUG-AAAA', true)$$,
  'P0002', 'not_found', 'nobody can change someone else''s report');
select lives_ok($$select public.append_bug_note('BUG-BBBB', 'It also happens on Wi-Fi.')$$, 'owners can add details');
select throws_ok($$select public.append_bug_note('BUG-AAAA', 'hello')$$,
  'P0002', 'not_found', 'nobody can append to someone else''s report');
select throws_ok(format($$select public.append_bug_note('BUG-BBBB', %L)$$, repeat('x', 2001)),
  '22023', 'note_too_long', 'appended details are capped at 2000 characters');
select throws_ok($$update public.bug_reports set status = 'fixed'$$, '42501', null,
  'a client still cannot write status');
select throws_ok($$select public.admin_set_bug_status('BUG-BBBB', 'looking')$$, '42501', null,
  'a client cannot call the team RPC');

-- ---- the team RPC, as the service role -----------------------------------
reset role;
set local role service_role;
select throws_ok($$select public.admin_set_bug_status('BUG-DDDD', 'wontfix', null, 'too short')$$,
  '22023', 'reason_required', 'the RPC asks for a real reason');
select throws_ok($$select public.admin_set_bug_status('BUG-DDDD', 'duplicate')$$,
  '22023', 'original_required', 'the RPC asks for the original');
select throws_ok($$select public.admin_set_bug_status('BUG-DDDD', 'duplicate', null, null, 'BUG-ZZZZ')$$,
  'P0002', 'unknown_original', 'the RPC refuses an unknown original');
select throws_ok($$select public.admin_set_bug_status('BUG-DDDD', 'fixed')$$,
  '22023', 'fixed_in_required', 'the RPC asks for the version');
select lives_ok($$select public.admin_set_bug_status('BUG-AAAA', 'looking', null, null, null, 'Chat will not send on cellular')$$,
  'the team can set a neutral public title');
select is((select public_title from public.bug_reports where code = 'BUG-AAAA'), 'Chat will not send on cellular',
  'the public title is stored');

-- ---- deleting an original reopens its followers -----------------------------
select lives_ok($$delete from public.bug_reports where code = 'BUG-AAAA'$$, 'an original can be deleted');
select results_eq($$select status, duplicate_of from public.bug_reports where code in ('BUG-BBBB', 'BUG-CCCC') order by code$$,
  $$values ('received'::text, null::uuid), ('received'::text, null::uuid)$$,
  'its followers go back to the queue as ordinary reports');

reset role;
select * from finish();
rollback;
