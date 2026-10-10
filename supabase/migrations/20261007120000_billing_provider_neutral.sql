-- Provider-neutral web billing.
--
-- Paddle was the only web seller of record, so the subscription columns, the
-- source label and the dashboard figures all carried its name. A second
-- provider (Creem) is now an adapter away, which makes every one of those a
-- lie waiting to happen. Safe to rename now: there are no live rows.
--
-- `source` already records which provider owns a row ('paddle', 'creem',
-- 'manual', 'debug'); cancel and webhook handling dispatch on it.

alter table public.subscriptions rename column paddle_subscription_id to provider_subscription_id;
alter table public.subscriptions rename column paddle_customer_id to provider_customer_id;
alter table public.subscriptions rename column paddle_status to provider_status;

-- Two providers can mint the same id string, so uniqueness is per provider.
drop index if exists public.subscriptions_paddle_subscription_id_key;
create unique index if not exists subscriptions_provider_subscription_id_key
  on public.subscriptions (source, provider_subscription_id)
  where provider_subscription_id is not null;

comment on column public.subscriptions.provider_subscription_id is
  'The seller of record''s subscription id (Paddle sub_..., Creem sub_...). Null for manual and debug grants. Addressed directly by the cancel route, scoped by `source`.';
comment on column public.subscriptions.provider_customer_id is
  'The seller of record''s customer id, used to scope API lookups to this user.';
comment on column public.subscriptions.provider_status is
  'The provider''s subscription status as of the last applied event (active, trialing, past_due, paused, canceled).';

-- Which rails entitle the caller. 'web' is any seller-of-record subscription,
-- whichever provider it came through. Released clients that only look for
-- 'paddle' degrade cosmetically, nothing more. The return type is unchanged,
-- so `create or replace` keeps the grants.
create or replace function public.my_premium_sources()
returns text[]
language sql stable security definer set search_path = ''
as $$
  select array_remove(array[
    (select case when s.source in ('manual', 'debug') then 'manual' else 'web' end
     from public.subscriptions s
     where s.user_id = auth.uid()
       and s.tier = 'premium'
       and (s.current_period_end is null or s.current_period_end > now())),
    (select 'apple' where exists (
      select 1 from public.apple_subscriptions a
      where a.user_id = auth.uid()
        and a.revoked_at is null
        and a.expires_at > now()))
  ], null);
$$;

-- Same signature and return type (jsonb), so grants survive; restated anyway
-- because a bare `create or replace` is the cheapest thing to get wrong.
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
  -- rails (web `subscriptions` and `apple_subscriptions`), expiry, and
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

  -- Subscriptions by rail. Web "active" = a provider source (not manual/debug), tier premium,
  -- current_period_end in the future. Manual/debug = premium rows not from
  -- a web provider. Apple = distinct users with an unrevoked, unexpired App Store row,
  -- Production and Sandbox (App Review, testers) reported apart.
  select v || jsonb_build_object('subscriptions', jsonb_build_object(
    'web_active', count(*) filter (where source not in ('manual', 'debug') and tier = 'premium' and current_period_end > now()),
    'web_past_due', count(*) filter (where source not in ('manual', 'debug') and tier = 'premium' and current_period_end > now() and provider_status = 'past_due'),
    'web_canceling', count(*) filter (where source not in ('manual', 'debug') and tier = 'premium' and current_period_end > now() and scheduled_cancel_at is not null),
    'web_by_provider', coalesce((
      select jsonb_object_agg(source, n) from (
        select source, count(*) as n from public.subscriptions
        where source not in ('manual', 'debug') and tier = 'premium' and current_period_end > now()
        group by 1) bp), '{}'::jsonb),
    'manual_or_debug', count(*) filter (where source in ('manual', 'debug') and tier = 'premium' and (current_period_end is null or current_period_end > now())),
    'apple_production', (select count(distinct user_id) from public.apple_subscriptions
                         where revoked_at is null and expires_at > now() and environment = 'Production'),
    'apple_sandbox', (select count(distinct user_id) from public.apple_subscriptions
                      where revoked_at is null and expires_at > now() and environment <> 'Production'),
    -- MRR inputs: active, not past_due web rows grouped by what they charge.
    -- Rows with no recorded price are counted in `unpriced`, never summed.
    'web_revenue', coalesce((
      select jsonb_agg(jsonb_build_object(
        'currency', currency, 'interval', billing_interval, 'frequency', billing_frequency,
        'subscribers', n, 'unit_amount_sum', amount))
      from (
        select currency, billing_interval, billing_frequency, count(*) as n, sum(unit_amount) as amount
        from public.subscriptions
        where source not in ('manual', 'debug') and tier = 'premium' and current_period_end > now()
          and coalesce(provider_status, '') <> 'past_due'
          and unit_amount is not null and currency is not null and billing_interval is not null
        group by 1, 2, 3
      ) g), '[]'::jsonb),
    'web_unpriced', count(*) filter (where source not in ('manual', 'debug') and tier = 'premium' and current_period_end > now()
      and coalesce(provider_status, '') <> 'past_due'
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
