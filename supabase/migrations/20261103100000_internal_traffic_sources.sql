-- Where first-time visitors came from, for the weekly check in the organic
-- reach playbook (/internal/metrics, "Traffic sources"). Unlike
-- internal_metrics().top_referrers_30d this is not capped at five and keeps
-- "(direct)": in-app browsers (Instagram, TikTok) often hide the referrer, so
-- direct is where part of them lands and the playbook reads other channels as
-- a floor. Also returns an 8 bucket weekly trend. Host is the first-referrer host with www. stripped; windowed by
-- first_seen_at, i.e. new visitors only.

create or replace function public.traffic_source_host(p_referrer text)
returns text
language sql
immutable
set search_path = ''
as $$
  select coalesce(nullif(regexp_replace(lower(substring(p_referrer from '^[A-Za-z][A-Za-z0-9+.-]*://([^/:?#]+)')), '^www\.', ''), ''), '(direct)')
$$;

revoke all on function public.traffic_source_host(text) from public, anon, authenticated;
grant execute on function public.traffic_source_host(text) to service_role;

create or replace function public.internal_traffic_sources()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service_role required' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'sources', coalesce((
      select jsonb_agg(jsonb_build_object('source', source, 'visitors_7d', v7, 'visitors_30d', v30)
                       order by v30 desc, source)
      from (
        select source,
               count(*) filter (where first_seen_at >= now() - interval '7 days') as v7,
               count(*) as v30
        from (select first_seen_at, public.traffic_source_host(first_referrer) as source
              from public.website_visitors
              where first_seen_at >= now() - interval '30 days') s
        group by source
        order by v30 desc, source
        limit 50
      ) g
    ), '[]'::jsonb),
    -- Trend: new visitors per source in rolling 7-day buckets, age 0 = the
    -- last 7 days, age 7 = 49-56 days ago. Rolling rather than calendar weeks
    -- so the newest bucket is never a partial week.
    'weekly', coalesce((
      select jsonb_agg(jsonb_build_object('source', source, 'age', age, 'visitors', n) order by source, age)
      from (
        select public.traffic_source_host(first_referrer) as source,
               floor(extract(epoch from now() - first_seen_at) / 604800)::int as age,
               count(*) as n
        from public.website_visitors
        where first_seen_at >= now() - interval '56 days'
        group by 1, 2
      ) w
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.internal_traffic_sources() from public, anon, authenticated;
grant execute on function public.internal_traffic_sources() to service_role;
