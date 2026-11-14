begin;
select plan(20);

select has_table('public', 'android_testers', 'the waitlist table exists');

select has_column('public', 'android_testers', 'added_at', 'added_at records when a tester was added to Play');


select ok(
  (select relrowsecurity from pg_class where oid = 'public.android_testers'::regclass),
  'row level security is on'
);

select ok(
  not has_table_privilege('anon', 'public.android_testers', 'select')
  and not has_table_privilege('authenticated', 'public.android_testers', 'select')
  and not has_table_privilege('authenticated', 'public.android_testers', 'insert'),
  'no client role can read or write it'
);

select lives_ok(
  $$insert into public.android_testers (email, source) values ('sam@gmail.com', 'download')$$,
  'a plain sign-up is accepted'
);

select throws_ok(
  $$insert into public.android_testers (email) values ('sam@gmail.com')$$,
  '23505', null, 'the same address cannot take two seats'
);

select throws_ok(
  $$insert into public.android_testers (email) values ('Sam@Gmail.com')$$,
  '23514', null, 'a mixed-case address is refused, so duplicates cannot hide in the casing'
);

select throws_ok(
  $$insert into public.android_testers (email) values ('sam@gmial')$$,
  '23514', null, 'an address with no dotted domain is refused'
);

select throws_ok(
  $$insert into public.android_testers (email, source) values ('a@b.co', 'twitter')$$,
  '23514', null, 'an unlisted source is refused'
);

select is(
  (select source from public.android_testers where email = 'sam@gmail.com'),
  'download', 'the source is kept'
);

select is(
  (select added_at from public.android_testers where email = 'sam@gmail.com'),
  null,
  'a new sign-up is not added yet'
);

-- Reward: two weeks of Premium once the tester is added and has an account.
select lives_ok(
  $$insert into public.android_testers (email) values ('reward@gmail.com'), ('noacct@gmail.com')$$,
  'two testers for the reward checks'
);
select is(
  public.grant_android_tester_reward((select id from public.android_testers where email = 'reward@gmail.com')),
  'not_added', 'no reward before the tester is added to Play'
);
update public.android_testers set added_at = now();
select is(
  public.grant_android_tester_reward((select id from public.android_testers where email = 'noacct@gmail.com')),
  'no_account', 'no account yet: nothing granted, nothing stamped'
);
insert into auth.users (id, email, raw_user_meta_data)
values ('00000000-0000-0000-0000-00000000a1a1', 'Reward@Gmail.com', '{}'::jsonb);
select is(
  public.grant_android_tester_reward((select id from public.android_testers where email = 'reward@gmail.com')),
  'granted', 'an added tester with an account (matched case-blind) gets the reward'
);
select ok(
  (select current_period_end between now() + interval '13 days' and now() + interval '15 days'
   from public.subscriptions where user_id = '00000000-0000-0000-0000-00000000a1a1' and tier = 'premium'),
  'the grant is a 14-day premium period'
);
select is(
  public.grant_android_tester_reward((select id from public.android_testers where email = 'reward@gmail.com')),
  'already', 'a second press never grants twice'
);
update public.subscriptions set source = 'apple' where user_id = '00000000-0000-0000-0000-00000000a1a1';
update public.android_testers set reward_granted_at = null where email = 'reward@gmail.com';
select is(
  public.grant_android_tester_reward((select id from public.android_testers where email = 'reward@gmail.com')),
  'has_plan', 'a plan bought elsewhere is left alone'
);
select ok(
  not has_function_privilege('authenticated', 'public.grant_android_tester_reward(bigint)', 'execute')
  and not has_function_privilege('anon', 'public.grant_android_tester_reward(bigint)', 'execute'),
  'only the service role can grant'
);
select has_column('public', 'android_testers', 'reward_granted_at', 'the reward is recorded per tester');

select * from finish();
rollback;
