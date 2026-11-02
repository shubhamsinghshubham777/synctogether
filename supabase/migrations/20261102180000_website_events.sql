-- Website events: the two moments a pageview cannot see.
--
-- website_pageviews already says who landed on /join/<code> and /download. It
-- cannot say whether the invite handed off to an installed app, or whether the
-- visitor went on to a store - and that pair is the install rate the growth
-- plan steers by. Events are an allow-list, not free text: the collector
-- rejects any name that is not listed in website/lib/web-events.ts, and the
-- check below is the same list, so a typo cannot create a new bucket.
--
-- No details beyond the name and a path with the invite code already stripped.
-- The visitor id is the same first-party cookie the pageviews use.

create table if not exists public.website_events (
  id bigint generated always as identity primary key,
  visitor_id text not null references public.website_visitors (visitor_id) on delete cascade,
  name text not null check (
    name in ('join_handed_off', 'join_fallback', 'store_click_mac', 'store_click_windows')
  ),
  path text not null,
  created_at timestamptz not null default now()
);

create index if not exists website_events_created_idx on public.website_events (created_at desc);
create index if not exists website_events_name_idx on public.website_events (name, created_at desc);
create index if not exists website_events_visitor_idx on public.website_events (visitor_id);

alter table public.website_events enable row level security;
revoke all on public.website_events from public, anon, authenticated;
grant all on public.website_events to service_role;
