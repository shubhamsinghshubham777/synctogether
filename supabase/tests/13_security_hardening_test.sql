begin;
select plan(22);

-- 1. Table privilege tests on public.rooms (must only be written by security definer RPCs)
select ok(
  not has_table_privilege('anon', 'public.rooms', 'INSERT'),
  'anon cannot insert rooms');
select ok(
  not has_table_privilege('anon', 'public.rooms', 'UPDATE'),
  'anon cannot update rooms');
select ok(
  not has_table_privilege('anon', 'public.rooms', 'DELETE'),
  'anon cannot delete rooms');

select ok(
  not has_table_privilege('authenticated', 'public.rooms', 'INSERT'),
  'authenticated cannot insert rooms');
select ok(
  not has_table_privilege('authenticated', 'public.rooms', 'UPDATE'),
  'authenticated cannot update rooms');
select ok(
  not has_table_privilege('authenticated', 'public.rooms', 'DELETE'),
  'authenticated cannot delete rooms');

-- 2. Routine execution privilege tests for staged upload RPCs (service_role only)
select ok(
  not has_function_privilege('anon', 'public.request_staged_upload_slot(uuid, bigint, text, bigint, text, text)', 'EXECUTE'),
  'anon cannot execute request_staged_upload_slot');
select ok(
  not has_function_privilege('authenticated', 'public.request_staged_upload_slot(uuid, bigint, text, bigint, text, text)', 'EXECUTE'),
  'authenticated cannot execute request_staged_upload_slot');
select ok(
  has_function_privilege('service_role', 'public.request_staged_upload_slot(uuid, bigint, text, bigint, text, text)', 'EXECUTE'),
  'service_role can execute request_staged_upload_slot');

select ok(
  not has_function_privilege('anon', 'public.set_staged_upload_state(uuid, uuid, text, bigint, text, bigint)', 'EXECUTE'),
  'anon cannot execute set_staged_upload_state');
select ok(
  not has_function_privilege('authenticated', 'public.set_staged_upload_state(uuid, uuid, text, bigint, text, bigint)', 'EXECUTE'),
  'authenticated cannot execute set_staged_upload_state');
select ok(
  has_function_privilege('service_role', 'public.set_staged_upload_state(uuid, uuid, text, bigint, text, bigint)', 'EXECUTE'),
  'service_role can execute set_staged_upload_state');

select ok(
  not has_function_privilege('anon', 'public.clear_staged_upload(uuid, bigint)', 'EXECUTE'),
  'anon cannot execute clear_staged_upload');
select ok(
  not has_function_privilege('authenticated', 'public.clear_staged_upload(uuid, bigint)', 'EXECUTE'),
  'authenticated cannot execute clear_staged_upload');
select ok(
  has_function_privilege('service_role', 'public.clear_staged_upload(uuid, bigint)', 'EXECUTE'),
  'service_role can execute clear_staged_upload');

-- 3. Website analytics tables existence and privilege isolation
select has_table('public', 'website_visitors', 'website_visitors table exists');
select has_table('public', 'website_pageviews', 'website_pageviews table exists');
select has_table('public', 'website_downloads', 'website_downloads table exists');

select ok(
  not has_table_privilege('anon', 'public.website_visitors', 'SELECT'),
  'anon cannot select website_visitors');
select ok(
  not has_table_privilege('authenticated', 'public.website_visitors', 'SELECT'),
  'authenticated cannot select website_visitors');
select ok(
  has_table_privilege('service_role', 'public.website_visitors', 'SELECT'),
  'service_role can select website_visitors');

-- 4. debug_grant_premium gate test when is_local is not set or empty
select throws_ok(
  'select public.debug_grant_premium(1)',
  'debug_grant_premium is only available on the local stack',
  'debug_grant_premium fails when is_local is not set');

select * from finish();
rollback;
