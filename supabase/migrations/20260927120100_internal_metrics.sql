-- One aggregation RPC for the internal dashboard (/internal/metrics).
--
-- The dashboard used to fetch rows through PostgREST and count them in JS.
-- `max_rows = 1000` silently truncated every one of those reads, so past a
-- thousand profiles, rooms or member rows the numbers simply stopped growing.
-- Every figure here is a single SQL aggregate instead, and each is defined in
-- the comment beside it - the page quotes these definitions.
--
-- Replaces `get_system_storage_stats`, whose only caller was the dashboard.

drop function if exists public.get_system_storage_stats();

create or replace function public.internal_metrics()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v jsonb := '{}'::jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service_role required' using errcode = '42501';
  end if;

  -- Accounts. `premium` is `effective_tier`, the single arbiter: it covers both
  -- rails (Paddle `subscriptions` and `apple_subscriptions`), expiry, and
  -- short-circuits guests, so a guest with a stray subscription row is a guest.
  -- `free` = registered minus premium.
  with t as (
    select p.is_guest, public.effective_tier(p.id) as tier from public.profiles p
  )
  select v || jsonb_build_object('accounts', jsonb_build_object(
    'total_profiles', count(*),
    'guests', count(*) filter (where is_guest),
    'registered', count(*) filter (where not is_guest),
    'premium', count(*) filter (where tier = 'premium'),
    'free', count(*) filter (where not is_guest and tier <> 'premium')
  )) into v from t;

  -- Signups: profiles created in each rolling window. Kept apart from activity.
  select v || jsonb_build_object('signups', jsonb_build_object(
    'last_24h', count(*) filter (where created_at >= now() - interval '1 day'),
    'last_7d',  count(*) filter (where created_at >= now() - interval '7 days'),
    'last_30d', count(*) filter (where created_at >= now() - interval '30 days')
  )) into v from public.profiles;

  -- DAU / WAU / MAU: distinct users credited watch time (watch_ledger,
  -- credited_seconds > 0) inside the rolling window. `updated_at` is the time
  -- of a row's latest credit, so "credited within W" is exactly "some row has
  -- updated_at >= now() - W". The ledger survives leaving, kicks and room
  -- deletion, unlike room_members. It inherits the ledger's rules: it counts
  -- co-watching (>= 2 members, live playback), excludes guests (they earn
  -- nothing) and users who switched off "Share usage data".
  with a as (
    select l.user_id, max(l.updated_at) as last_at
    from public.watch_ledger l
    where l.credited_seconds > 0 and l.updated_at >= now() - interval '30 days'
    group by l.user_id
  ), d as (
    select public.effective_tier(user_id) as tier from a where last_at >= now() - interval '1 day'
  )
  select v || jsonb_build_object('activity', jsonb_build_object(
    'dau', (select count(*) from a where last_at >= now() - interval '1 day'),
    'wau', (select count(*) from a where last_at >= now() - interval '7 days'),
    'mau', (select count(*) from a),
    'dau_by_tier', jsonb_build_object(
      'premium', (select count(*) from d where tier = 'premium'),
      'free',    (select count(*) from d where tier = 'free'),
      'guest',   (select count(*) from d where tier = 'guest'))
  )) into v;

  -- Subscriptions by rail. Paddle "active" = source paddle, tier premium,
  -- current_period_end in the future. Manual/debug = premium rows not from
  -- Paddle. Apple = distinct users with an unrevoked, unexpired App Store row,
  -- Production and Sandbox (App Review, testers) reported apart.
  select v || jsonb_build_object('subscriptions', jsonb_build_object(
    'paddle_active', count(*) filter (where source = 'paddle' and tier = 'premium' and current_period_end > now()),
    'paddle_past_due', count(*) filter (where source = 'paddle' and tier = 'premium' and current_period_end > now() and paddle_status = 'past_due'),
    'paddle_canceling', count(*) filter (where source = 'paddle' and tier = 'premium' and current_period_end > now() and scheduled_cancel_at is not null),
    'manual_or_debug', count(*) filter (where source <> 'paddle' and tier = 'premium' and (current_period_end is null or current_period_end > now())),
    'apple_production', (select count(distinct user_id) from public.apple_subscriptions
                         where revoked_at is null and expires_at > now() and environment = 'Production'),
    'apple_sandbox', (select count(distinct user_id) from public.apple_subscriptions
                      where revoked_at is null and expires_at > now() and environment <> 'Production'),
    -- MRR inputs: active, not past_due Paddle rows grouped by what they charge.
    -- Rows with no recorded price are counted in `unpriced`, never summed.
    'paddle_revenue', coalesce((
      select jsonb_agg(jsonb_build_object(
        'currency', currency, 'interval', billing_interval, 'frequency', billing_frequency,
        'subscribers', n, 'unit_amount_sum', amount))
      from (
        select currency, billing_interval, billing_frequency, count(*) as n, sum(unit_amount) as amount
        from public.subscriptions
        where source = 'paddle' and tier = 'premium' and current_period_end > now()
          and coalesce(paddle_status, '') <> 'past_due'
          and unit_amount is not null and currency is not null and billing_interval is not null
        group by 1, 2, 3
      ) g), '[]'::jsonb),
    'paddle_unpriced', count(*) filter (where source = 'paddle' and tier = 'premium' and current_period_end > now()
      and coalesce(paddle_status, '') <> 'past_due'
      and (unit_amount is null or currency is null or billing_interval is null))
  )) into v from public.subscriptions;

  -- Rooms. `live_now` is `room_state(r) = 'live'`, which knows about persistent
  -- premium rooms. `member_rows_in_live_rooms` counts room_members rows, i.e.
  -- memberships - not people online (presence lives in Realtime, not here).
  select v || jsonb_build_object('rooms', jsonb_build_object(
    'total', (select count(*) from public.rooms),
    'last_7d', (select count(*) from public.rooms where created_at >= now() - interval '7 days'),
    'last_30d', (select count(*) from public.rooms where created_at >= now() - interval '30 days'),
    'live_now', (select count(*) from public.rooms r where public.room_state(r) = 'live'),
    'media_kind', coalesce((select jsonb_object_agg(k, n) from (
        select coalesce(media_kind, 'none') as k, count(*) as n from public.rooms group by 1) m), '{}'::jsonb),
    'messages_total', (select count(*) from public.messages),
    'member_rows_in_live_rooms', (select count(*) from public.room_members m
        join public.rooms r on r.id = m.room_id where public.room_state(r) = 'live')
  )) into v;

  -- Website. Visitors are first-party cookies (website_visitors), windowed by
  -- last_seen_at. `visitors_who_downloaded` is distinct non-null visitor_id in
  -- website_downloads - the same cookie population, so the rate is <= 100%.
  -- `single_page_visitors` is lifetime per cookie; there are no sessions.
  -- Top paths: pageviews in the last 30 days. Top referrers: first-referrer
  -- host (www. stripped) of visitors first seen in the last 30 days.
  select v || jsonb_build_object('website', jsonb_build_object(
    'visitors_total', (select count(*) from public.website_visitors),
    'visitors_24h', (select count(*) from public.website_visitors where last_seen_at >= now() - interval '1 day'),
    'visitors_7d', (select count(*) from public.website_visitors where last_seen_at >= now() - interval '7 days'),
    'visitors_30d', (select count(*) from public.website_visitors where last_seen_at >= now() - interval '30 days'),
    'single_page_visitors', (select count(*) from public.website_visitors where pageviews_count = 1),
    'pageviews_total', (select count(*) from public.website_pageviews),
    'visitors_who_downloaded', (select count(distinct visitor_id) from public.website_downloads where visitor_id is not null),
    'downloads_total', (select count(*) from public.website_downloads),
    'downloads_24h', (select count(*) from public.website_downloads where created_at >= now() - interval '1 day'),
    'downloads_7d', (select count(*) from public.website_downloads where created_at >= now() - interval '7 days'),
    'downloads_30d', (select count(*) from public.website_downloads where created_at >= now() - interval '30 days'),
    'downloads_by_platform', coalesce((select jsonb_object_agg(platform, n) from (
        select platform, count(*) as n from public.website_downloads group by 1) p), '{}'::jsonb),
    'top_paths_30d', coalesce((select jsonb_agg(jsonb_build_object('path', pathname, 'count', n) order by n desc) from (
        select pathname, count(*) as n from public.website_pageviews
        where created_at >= now() - interval '30 days'
        group by 1 order by 2 desc limit 5) tp), '[]'::jsonb),
    'top_referrers_30d', coalesce((select jsonb_agg(jsonb_build_object('source', host, 'count', n) order by n desc) from (
        select host, count(*) as n from (
          select regexp_replace(lower(substring(first_referrer from '^[A-Za-z][A-Za-z0-9+.-]*://([^/:?#]+)')), '^www\.', '') as host
          from public.website_visitors
          where first_referrer is not null and first_seen_at >= now() - interval '30 days') h
        where host is not null and host <> ''
        group by 1 order by 2 desc limit 5) tr), '[]'::jsonb)
  )) into v;

  -- Storage. R2 figures are what the database references, not a bucket
  -- listing: `active_room_media_bytes` = rooms whose shared upload is 'ready'
  -- (retire_room clears these, so every one is a live object);
  -- `staged_ready_bytes` = unclaimed ready staged uploads (a claimed one is
  -- the same object as its room's, and counting it would double it);
  -- `pending_r2_deletions` = objects queued for deletion, count only (the
  -- queue records no sizes).
  select v || jsonb_build_object('storage', jsonb_build_object(
    'db_bytes', pg_database_size(current_database()),
    'active_room_media_bytes', (select coalesce(sum(media_file_size), 0) from public.rooms where media_upload_state = 'ready'),
    'staged_ready_bytes', (select coalesce(sum(file_size), 0) from public.staged_media_uploads
                           where upload_state = 'ready' and claimed_room_id is null),
    'pending_r2_deletions', (select count(*) from public.pending_r2_deletions)
  )) into v;

  return v;
end;
$$;

revoke all on function public.internal_metrics() from public, anon, authenticated;
grant execute on function public.internal_metrics() to service_role;
