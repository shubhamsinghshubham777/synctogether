begin;
select plan(52);

create function pg_temp.mk_user(p_guest boolean default false) returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (
    v_id, p_guest,
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
create temp table c (k text primary key, v text);

insert into t values
  ('maya', pg_temp.mk_user()),
  ('sam', pg_temp.mk_user()),
  ('lee', pg_temp.mk_user()),
  ('guest', pg_temp.mk_user(true));

-- ---------------------------------------------------------------------------
-- Time zone
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'maya'));
select lives_ok($$ select public.set_my_timezone('Europe/London') $$, 'a real IANA zone is accepted');
select throws_ok($$ select public.set_my_timezone('Mars/Olympus') $$, 'invalid_timezone', 'an unknown zone is refused');
select is((select timezone from public.profiles where id = (select v from t where k = 'maya')),
  'Europe/London', 'and stored');

-- ---------------------------------------------------------------------------
-- Guests cannot pair
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'guest'));
select throws_ok($$ select public.create_pair_invite() $$, 'sign_in_required', 'a guest cannot invite');

-- ---------------------------------------------------------------------------
-- Invite
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'maya'));
insert into c select 'code', (public.create_pair_invite()).code;
select is(char_length((select v from c where k = 'code')), 6, 'an invite has a 6 character code');
select is((public.create_pair_invite()).code, (select v from c where k = 'code'),
  'asking again reuses the pending invite');
select is((select count(*)::int from public.pair_invites where inviter_id = (select v from t where k = 'maya') and status = 'pending'),
  1, 'there is only ever one pending invite per person');

select throws_ok(format($$ select public.accept_pair_invite(%L) $$, (select v from c where k = 'code')),
  'cannot_pair_self', 'nobody can accept their own invite');

-- Sam opens the link: it is previewed, and remembered for the lobby banner.
select pg_temp.act_as((select v from t where k = 'sam'));
select is((public.get_pair_invite((select v from c where k = 'code')))->>'status', 'pending', 'the link previews as pending');
select is((public.get_pair_invite((select v from c where k = 'code')))->'inviter'->>'id',
  (select v::text from t where k = 'maya'), 'and names the inviter');
select is((public.my_pending_pair_invite())->>'code', (select v from c where k = 'code'),
  'the lobby banner finds an invite the person opened');

-- A guest opening the link is not remembered.
select pg_temp.act_as((select v from t where k = 'guest'));
select lives_ok(format($$ select public.get_pair_invite(%L) $$, (select v from c where k = 'code')), 'a guest can preview');
select is((select seen_by from public.pair_invites where code = (select v from c where k = 'code')),
  (select v from t where k = 'sam'), 'but does not replace the viewer');
select throws_ok(format($$ select public.accept_pair_invite(%L) $$, (select v from c where k = 'code')),
  'sign_in_required', 'and cannot accept');
select is((public.get_pair_invite('ZZZZZZ')) ->> 'status', 'not_found', 'an unknown code is not found');

-- ---------------------------------------------------------------------------
-- Accept
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'sam'));
select lives_ok(format($$ select public.accept_pair_invite(%L) $$, (select v from c where k = 'code')), 'Sam accepts');
select is((select count(*)::int from public.pair_members), 2, 'both people are members');
select is((public.my_pair())->'partner'->>'id', (select v::text from t where k = 'maya'), 'Sam sees Maya as the partner');
select is((public.my_pair())->'partner'->>'timezone', 'Europe/London', 'with her time zone');
select is((public.my_pending_pair_invite()), null::jsonb, 'the banner clears once answered');
select throws_ok(format($$ select public.accept_pair_invite(%L) $$, (select v from c where k = 'code')),
  'invite_used', 'an invite works once');
select throws_ok($$ select public.create_pair_invite() $$, 'already_paired', 'a paired person cannot invite');

-- Lee cannot pair with someone who is already paired.
select pg_temp.act_as((select v from t where k = 'maya'));
select throws_ok($$ select public.create_pair_invite() $$, 'already_paired', 'Maya is paired too');

-- ---------------------------------------------------------------------------
-- Expiry and cancel
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'lee'));
insert into c select 'lee', (public.create_pair_invite()).code;
update public.pair_invites set expires_at = now() - interval '1 minute' where code = (select v from c where k = 'lee');
select pg_temp.act_as((select v from t where k = 'guest'));
select is((public.get_pair_invite((select v from c where k = 'lee')))->>'status', 'expired', 'an old invite reads expired');
select pg_temp.act_as((select v from t where k = 'lee'));
select isnt((public.create_pair_invite()).code, (select v from c where k = 'lee'), 'an expired invite is replaced, not reused');
select lives_ok($$ select public.cancel_pair_invite() $$, 'the inviter can cancel');
select is((select count(*)::int from public.pair_invites where inviter_id = (select v from t where k = 'lee') and status = 'pending'),
  0, 'leaving nothing pending');

-- ---------------------------------------------------------------------------
-- Our Room
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select v from t where k = 'maya'));
insert into t select 'room', (public.open_our_room()).id;
select is((select count(*)::int from public.rooms where pair_id is not null), 1, 'opening creates the pair room once');
select is((select v from t where k = 'room'), (public.open_our_room()).id, 'and is idempotent');
select is((select persistent from public.rooms where id = (select v from t where k = 'room')), true, 'Our Room is persistent on a free account');
select is((select count(*)::int from public.list_my_rooms()), 0, 'it stays out of the lobby ticket list');

-- It never counts against the caps: Maya can still create a normal room.
select lives_ok($$ select public.create_room('Friday', 60) $$, 'a live Our Room does not use a room slot');

-- A stranger holding the code is told the room does not exist.
select pg_temp.act_as((select v from t where k = 'lee'));
select throws_ok(format($$ select public.join_room(%L) $$, (select code from public.rooms where id = (select v from t where k = 'room'))),
  'room_not_found', 'only the pair can enter by code');

-- Sam opens it too, as a member; chat survives retirement.
select pg_temp.act_as((select v from t where k = 'sam'));
select is((public.open_our_room()).id, (select v from t where k = 'room'), 'Sam opens the same room');
select is((select count(*)::int from public.room_members where room_id = (select v from t where k = 'room') and role = 'host'), 2,
  'and both partners are hosts, so either can choose what plays');
select throws_ok(format($$ select public.kick_member(%L, %L, true) $$, (select v from t where k = 'room'), (select v from t where k = 'maya')),
  'cannot_kick_host', 'yet neither can remove the other');

insert into public.messages (room_id, sender_id, content)
  select (select v from t where k = 'room'), (select v from t where k = 'sam'), 'hello';
select public.retire_room((select v from t where k = 'room'));
select is((select count(*)::int from public.messages where room_id = (select v from t where k = 'room')), 1, 'Our Room keeps its chat between sessions');
select is(public.room_state((select r from public.rooms r where r.id = (select v from t where k = 'room'))), 'idle', 'and rests as idle');
select is((public.open_our_room()).ended_at, null::timestamptz, 'opening again starts a new session');

-- ---------------------------------------------------------------------------
-- Reunion, unpair
-- ---------------------------------------------------------------------------
select lives_ok($$ select public.set_reunion('2026-12-26', 'Heathrow') $$, 'either partner can set the reunion');
select pg_temp.act_as((select v from t where k = 'maya'));
select is((public.my_pair())->>'reunion_label', 'Heathrow', 'and the other sees it');

select lives_ok($$ select public.unpair() $$, 'either partner can unpair');
select is((select count(*)::int from public.pairs) + (select count(*)::int from public.pair_members)
  + (select count(*)::int from public.rooms where pair_id is not null), 0, 'which removes the pair, both memberships and Our Room');

-- ---------------------------------------------------------------------------
-- One partner each: the edges
-- ---------------------------------------------------------------------------
insert into t values ('kai', pg_temp.mk_user()), ('noor', pg_temp.mk_user());

select pg_temp.act_as((select v from t where k = 'lee'));
insert into c select 'L', (public.create_pair_invite()).code;
select pg_temp.act_as((select v from t where k = 'kai'));
insert into c select 'K', (public.create_pair_invite()).code;
select pg_temp.act_as((select v from t where k = 'lee'));
select lives_ok(format($$ select public.accept_pair_invite(%L) $$, (select v from c where k = 'K')), 'Lee accepts Kai, so both are paired');

select is((select status from public.pair_invites where code = (select v from c where k = 'L')), 'cancelled',
  'and the invite Lee had open is tidied away, not left pending');

-- Noor opens Lee's older invite: Lee has a partner now.
select pg_temp.act_as((select v from t where k = 'noor'));
select throws_ok(format($$ select public.accept_pair_invite(%L) $$, (select v from c where k = 'L')),
  'partner_already_paired', 'an invite from someone who has since paired is refused');

-- A paired person accepting anyone's invite is refused too.
select pg_temp.act_as((select v from t where k = 'noor'));
insert into c select 'N', (public.create_pair_invite()).code;
select pg_temp.act_as((select v from t where k = 'kai'));
select throws_ok(format($$ select public.accept_pair_invite(%L) $$, (select v from c where k = 'N')),
  'already_paired', 'someone with a partner cannot accept a second');

-- ---------------------------------------------------------------------------
-- Nothing reachable by anonymous callers, and no stray grants on the helpers
-- ---------------------------------------------------------------------------
select ok(not has_function_privilege('anon', 'public.pair_member_removed()', 'execute'),
  'a trigger function is not callable by anon');
select ok(not has_function_privilege('authenticated', 'public.pair_member_removed()', 'execute'),
  'nor by signed-in users');
select ok(not has_function_privilege('anon', 'public.pair_id_from_topic(text)', 'execute'),
  'the realtime topic helper is not callable by anon');
select ok(has_function_privilege('authenticated', 'public.pair_id_from_topic(text)', 'execute'),
  'but the realtime policies can still use it');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prosecdef
             and (p.proname like 'pair%' or p.proname in ('open_our_room', 'invite_pair_by_email', 'call_partner',
                  'register_push_token', 'claim_push_batch', 'enqueue_push', 'my_pair'))
             and has_function_privilege('anon', p.oid, 'execute')),
  0, 'no security definer pairing function can be called anonymously');

select * from finish();
rollback;
