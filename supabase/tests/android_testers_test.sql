begin;
select plan(9);

select has_table('public', 'android_testers', 'the waitlist table exists');

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

select * from finish();
rollback;
