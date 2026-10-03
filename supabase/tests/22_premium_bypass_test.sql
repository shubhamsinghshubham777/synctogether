begin;
select plan(9);

-- A free account must not be able to reach a premium-only outcome by writing
-- tables directly. Every write here is attempted as `authenticated`.

insert into auth.users (id, is_anonymous, email, raw_user_meta_data)
values ('00000000-0000-0000-0000-0000000000f1', false, 'free@example.test', '{}'::jsonb);

insert into public.staged_media_uploads (id, user_id, file_name, file_size, r2_key, upload_id, upload_state)
values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000f1',
        'film.mkv', 10485760, 'users/x/staged/film.mkv', 'up-1', 'uploading');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f1"}', true);

select throws_ok(
  $$ update public.staged_media_uploads set upload_state = 'ready', r2_key = 'rooms/other/film.mkv' $$,
  '42501', null, 'a client cannot mark its own staged upload ready or repoint its key');
select throws_ok(
  $$ insert into public.staged_media_uploads (user_id, file_name, file_size, r2_key, upload_state)
     values ('00000000-0000-0000-0000-0000000000f1', 'f', 1, 'k', 'ready') $$,
  '42501', null, 'nor insert a ready one');
select throws_ok(
  $$ delete from public.staged_media_uploads $$,
  '42501', null, 'nor delete one to dodge the abort ladder');
select throws_ok(
  $$ insert into public.subscriptions (user_id, tier, current_period_end)
     values ('00000000-0000-0000-0000-0000000000f1', 'premium', now() + interval '1 year') $$,
  '42501', null, 'a client cannot grant itself a subscription');
select throws_ok(
  $$ insert into public.apple_subscriptions (original_transaction_id, user_id)
     values ('fake', '00000000-0000-0000-0000-0000000000f1') $$,
  '42501', null, 'nor an App Store one');
select throws_ok(
  $$ update public.tier_limits set max_members = 99 $$,
  '42501', null, 'nor retune a tier');
select throws_ok(
  $$ update public.profiles set free_extension_used = false $$,
  '42501', null, 'nor reset its spent free extension');
select throws_ok(
  $$ select public.debug_grant_premium(12) $$,
  'P0001', 'debug_grant_premium is only available on the local stack',
  'debug_grant_premium refuses outside a stack flagged local');

reset role;
select is(public.effective_tier('00000000-0000-0000-0000-0000000000f1'), 'free',
  'and after all of that the account is still free');

select * from finish();
rollback;
