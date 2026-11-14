-- Android early access: the waitlist behind /android.
--
-- Google Play will not list a new app until a closed group has tested it for 14
-- days, and the developer account that can run that test costs money. This table
-- is the proof people are waiting before that is spent, and the list the testers
-- are invited from afterwards.
--
-- Written only by the website's /api/android route (service role). Nobody reads
-- it from a client: the count the page shows and a seat number come back through
-- that same route, so there is no policy to get wrong.
create table if not exists public.android_testers (
  id bigint generated always as identity primary key,
  -- Stored lower-cased and trimmed, so one address is one seat however it was typed.
  email text not null check (
    email = lower(btrim(email))
    and length(email) between 5 and 254
    and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
  ),
  -- Where the sign-up came from: an allow-list, not free text, like website_events.
  source text not null default 'android' check (
    source in ('android', 'download', 'join', 'pair', 'app')
  ),
  -- The tick box: they said they would keep the app installed for the test.
  consented_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint android_testers_email_key unique (email)
);

alter table public.android_testers enable row level security;
revoke all on public.android_testers from public, anon, authenticated;
grant all on public.android_testers to service_role;
