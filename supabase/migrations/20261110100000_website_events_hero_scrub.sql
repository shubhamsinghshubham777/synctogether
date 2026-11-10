-- Website events: the hero scrub's two human moments.
--
-- hero_scrub_start  - the first press (or key) on the hero playhead in a page view.
-- hero_scrub_synced - the first committed release: the visitor let go (or a key
--                     burst ended) and the demo seats jumped. A tap counts, as in the app.
--
-- Same allow-list rule as before: website/lib/web-events.ts carries the same
-- names, so a typo cannot open a new bucket.

alter table public.website_events drop constraint if exists website_events_name_check;
alter table public.website_events add constraint website_events_name_check check (
  name in (
    'join_handed_off',
    'join_fallback',
    'store_click_mac',
    'store_click_windows',
    'hero_scrub_start',
    'hero_scrub_synced'
  )
);
