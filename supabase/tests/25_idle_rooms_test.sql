begin;
select plan(12);

-- Persistent premium rooms rest as 'idle' between sessions; a running session
-- is never resettable through resume_room.

insert into auth.users (id, is_anonymous, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000c1', false, 'prem@example.test', '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000000c2', false, 'mate@example.test', '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000000c3', true,  null,                '{}'::jsonb);
insert into public.subscriptions (user_id, tier, current_period_end)
values ('00000000-0000-0000-0000-0000000000c1', 'premium', now() + interval '30 days');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1"}', true);

create temp table made on commit drop as
  select id, code from public.create_room('Standing room', 60);
grant select on made to authenticated;

select ok((select persistent from public.rooms where id = (select id from made)),
  'a premium host gets a persistent room');
select is(public.room_state((select r from public.rooms r where id = (select id from made))), 'live',
  'which is live while its session runs');

-- The session timer runs out and the sweep retires it.
reset role;
update public.rooms set expires_at = now() - interval '1 minute' where id = (select id from made);
select public.sweep_rooms();

select is(public.room_state((select r from public.rooms r where id = (select id from made))), 'idle',
  'after the sweep it is idle, not live');
select ok(exists (select 1 from public.rooms where id = (select id from made)),
  'and the sweep keeps it');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c2"}', true);
select throws_ok(
  format($$ select public.join_room(%L) $$, (select code from made)),
  'P0001', 'room_idle', 'nobody can join an idle room');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1"}', true);
select is((select state from public.list_my_rooms() where id = (select id from made)), 'idle',
  'the owner still lists it, as idle');
select throws_ok(
  format($$ select public.resume_room(%L, 600) $$, (select id from made)),
  'P0001', 'invalid_duration', 'a session longer than the tier allows is refused');

select is((select (public.resume_room((select id from made), 90)).duration_minutes), 90,
  'the owner starts a new session from idle');
select is(public.room_state((select r from public.rooms r where id = (select id from made))), 'live',
  'and the room is live again');

-- resume_room must leave a running session alone.
select is((select (public.resume_room((select id from made), 240)).duration_minutes), 90,
  'resume_room on a live room does not reset its timer');

-- A non-host cannot start one.
reset role;
update public.rooms set expires_at = now() - interval '1 minute' where id = (select id from made);
select public.sweep_rooms();
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c2"}', true);
select throws_ok(
  format($$ select public.resume_room(%L, 60) $$, (select id from made)),
  'P0001', 'not_host', 'only a host or the creator can start a session');

-- A lapsed subscription turns the idle room into an ordinary ended one.
reset role;
delete from public.subscriptions where user_id = '00000000-0000-0000-0000-0000000000c1';
select is(public.room_state((select r from public.rooms r where id = (select id from made))), 'expired',
  'when premium lapses an idle room is just an ended room');

select * from finish();
rollback;
