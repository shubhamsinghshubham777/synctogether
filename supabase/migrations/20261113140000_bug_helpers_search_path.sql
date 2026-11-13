-- The two pure helpers behind the fixed-from check use only built-ins; pin their
-- search_path so the security advisor's "role mutable search_path" warning clears.
alter function public.semver_gte(text, text) set search_path = pg_catalog;
alter function public.bug_reported_version(jsonb) set search_path = pg_catalog;
