begin;
select plan(49);

select ok(
  has_table_privilege('authenticated', 'public.profiles', 'SELECT'),
  'signed-in clients can read profiles, which every screen needs');

select ok(
  has_table_privilege('authenticated', 'public.rooms', 'SELECT'),
  'signed-in clients can read rooms');

select ok(
  has_table_privilege('authenticated', 'public.room_members', 'SELECT'),
  'signed-in clients can read the member list');

select ok(
  has_table_privilege('authenticated', 'public.messages', 'SELECT'),
  'signed-in clients can read chat history');

select ok(
  has_table_privilege('authenticated', 'public.messages', 'INSERT'),
  'signed-in clients can post chat');

select ok(
  has_table_privilege('authenticated', 'public.tier_limits', 'SELECT'),
  'signed-in clients can read the tier table their entitlement resolves against');

select ok(
  has_table_privilege('authenticated', 'public.subscriptions', 'SELECT'),
  'signed-in clients can read their own subscription row');

select ok(
  has_column_privilege('authenticated', 'public.profiles', 'display_name', 'UPDATE'),
  'the profile fields a user owns stay writable');

select ok(
  has_column_privilege('authenticated', 'public.profiles', 'avatar_url', 'UPDATE'),
  'the avatar stays writable');

select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'email', 'UPDATE'),
  'the email mirror is not user-editable, whatever RLS says');

select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'is_guest', 'UPDATE'),
  'nobody can promote themselves out of being a guest');

select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'free_extension_used', 'UPDATE'),
  'the one free extension cannot be handed back by the client that spent it');

select ok(
  not has_table_privilege('authenticated', 'public.room_bans', 'SELECT'),
  'the ban list stays unreadable by clients, grant as well as policy');

select ok(
  not has_table_privilege('authenticated', 'public.rooms', 'UPDATE'),
  'rooms are written only by the security-definer RPCs');

select ok(
  not has_table_privilege('authenticated', 'public.tier_limits', 'UPDATE'),
  'nobody can raise their own limits');

select ok(
  not has_table_privilege('authenticated', 'public.subscriptions', 'INSERT'),
  'nobody can grant themselves premium');

create function pg_temp.abandoned_room() returns uuid
language plpgsql as $$
declare v_u uuid := gen_random_uuid(); v_room public.rooms;
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_u, true, null, '{}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', v_u)::text, true);
  v_room := public.create_room('Abandoned', 60);
  perform public.leave_room(v_room.id);
  return v_room.id;
end $$;

create function pg_temp.rows_visible_as_authenticated(p_room_id uuid) returns int
language plpgsql as $$
declare v_cnt int;
begin
  set local role authenticated;
  select count(*) into v_cnt from public.rooms where id = p_room_id;
  reset role;
  return v_cnt;
end $$;

select is(
  pg_temp.rows_visible_as_authenticated(pg_temp.abandoned_room()),
  1,
  'RLS lets a creator read a room they have left - a plain table read is how the lobby finds the room blocking their cap');

create function pg_temp.visible_to_a_stranger(p_room_id uuid) returns int
language plpgsql as $$
declare v_other uuid := gen_random_uuid(); v_cnt int;
begin
  insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
  values (v_other, true, null, '{}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', v_other)::text, true);
  set local role authenticated;
  select count(*) into v_cnt from public.rooms where id = p_room_id;
  reset role;
  return v_cnt;
end $$;

select is(
  pg_temp.visible_to_a_stranger(pg_temp.abandoned_room()),
  0,
  'and that visibility is scoped to the creator - a stranger still sees nothing');


-- ---------------------------------------------------------------------------
-- Gamification. Every one of these RPCs was created fresh, and a `drop` takes
-- the grants with it - which is the failure this file exists to catch.
-- ---------------------------------------------------------------------------

select ok(
  has_table_privilege('authenticated', 'public.reward_config', 'SELECT'),
  'clients can read the tuning values the UI has to explain');

select ok(
  has_table_privilege('authenticated', 'public.achievements', 'SELECT'),
  'clients can read the achievement catalogue they render');

select ok(
  has_table_privilege('authenticated', 'public.watch_ledger', 'SELECT'),
  'clients can read their own ledger');

select ok(
  has_table_privilege('authenticated', 'public.user_rewards', 'SELECT'),
  'clients can read their own streak row');

select ok(
  not has_table_privilege('authenticated', 'public.co_watch_daily', 'SELECT'),
  'the per-pair accrual stays unreadable - it is how much farming headroom is left');

select ok(
  not has_table_privilege('authenticated', 'public.watch_heartbeats', 'SELECT'),
  'the heartbeat anchor stays unreadable, grant as well as policy');

select ok(
  not has_table_privilege('authenticated', 'public.co_watchers', 'SELECT'),
  'the co-watch graph is served through RPCs, never read raw');

select ok(
  not has_table_privilege('authenticated', 'public.watch_ledger', 'UPDATE'),
  'nobody can write their own score');

select ok(
  not has_table_privilege('authenticated', 'public.user_rewards', 'UPDATE'),
  'nor their own streak');

select ok(
  not has_table_privilege('authenticated', 'public.user_achievements', 'INSERT'),
  'nor award themselves a badge');

select ok(
  not has_table_privilege('authenticated', 'public.reward_config', 'UPDATE'),
  'nor retune the thresholds they are scored against');

select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'public_profile', 'UPDATE'),
  'consent to be published is set through an RPC, never by a direct column write');

select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'handle', 'UPDATE'),
  'handles go through claim_handle, which is what enforces the reserved list');

select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'equipped_frame', 'UPDATE'),
  'a frame is worn only if it was unlocked, and that is checked in the RPC');

select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'referred_by', 'UPDATE'),
  'nobody can name their own referrer after the fact');

select ok(
  has_function_privilege('authenticated', 'public.record_watch_progress(uuid, date, int)', 'EXECUTE'),
  'the heartbeat is callable by the client that beats');

select ok(
  has_function_privilege('authenticated', 'public.my_rewards()', 'EXECUTE'),
  'the one-round-trip payload the lobby loads is callable');

select ok(
  has_function_privilege('authenticated', 'public.leaderboard(text, text, int)', 'EXECUTE'),
  'the board is callable');

select ok(
  has_function_privilege('authenticated', 'public.create_recap(uuid, int, int, int, int, text, text[], boolean, boolean, uuid[], jsonb)', 'EXECUTE'),
  'sharing a recap is callable');

select ok(
  has_function_privilege('authenticated', 'public.claim_handle(text)', 'EXECUTE'),
  'claiming a handle is callable');

select ok(
  has_function_privilege('authenticated', 'public.set_public_profile(boolean)', 'EXECUTE'),
  'consent is callable - a consent nobody can give is a feature nobody can use');

select ok(
  not has_function_privilege('authenticated', 'public.public_leaderboard(text, int)', 'EXECUTE'),
  'the website read path is not reachable from a client JWT');

select ok(
  not has_function_privilege('authenticated', 'public.public_profile_card(text)', 'EXECUTE'),
  'nor is the public profile card, which bypasses the caller entirely');

select ok(
  not has_function_privilege('authenticated', 'public.grant_achievements(uuid, jsonb)', 'EXECUTE'),
  'the badge-granting internals are not a client API');

select ok(
  not has_function_privilege('authenticated', 'public.sweep_rewards()', 'EXECUTE'),
  'housekeeping belongs to cron, not to clients');

select ok(
  has_function_privilege('authenticated', 'public.my_recaps(int)', 'EXECUTE'),
  'an owner can list what they have published');

select ok(
  has_function_privilege('authenticated', 'public.delete_recap(text)', 'EXECUTE'),
  'and take any of it back - a public link nobody can revoke is not a share, it is a leak');

select ok(
  has_function_privilege('authenticated', 'public.my_season_awards()', 'EXECUTE'),
  'reading your own season placings is a client call');

select ok(
  not has_function_privilege('authenticated', 'public.close_seasons()', 'EXECUTE'),
  'but closing a season early to lock in a lead is not');

select ok(
  has_function_privilege('service_role', 'public.public_recap(text)', 'EXECUTE'),
  'the website, which talks to Supabase as the service role, can read a recap');

select ok(
  has_function_privilege('service_role', 'public.public_wrapped(text, int)', 'EXECUTE'),
  'and can render Wrapped');

select * from finish();
rollback;
