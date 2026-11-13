-- fixed_in means the FIRST app version that contains the fix, shown to users as
-- "Fixed from X.Y.Z onward". It is never an exact-match version: a store may
-- reject X.Y.Z and a later build may ship instead, so it must always be a plain
-- semver the app can compare, and never older than the build the report came from.

-- Pure semver comparison. Build metadata ("+88") is ignored; anything that is
-- not plain X.Y.Z (or has more than 9 digits in a part) is unparsable and the
-- answer is null, never an error, so a constraint can skip what it cannot read.
create or replace function public.semver_gte(a text, b text)
returns boolean
language plpgsql
immutable
parallel safe
as $$
declare
  pa text := nullif(btrim(regexp_replace(coalesce(a, ''), '\+.*$', '')), '');
  pb text := nullif(btrim(regexp_replace(coalesce(b, ''), '\+.*$', '')), '');
  ra int[];
  rb int[];
begin
  if pa is null or pb is null
     or pa !~ '^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}$'
     or pb !~ '^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}$' then
    return null;
  end if;
  ra := string_to_array(pa, '.')::int[];
  rb := string_to_array(pb, '.')::int[];
  return ra >= rb;
end $$;
revoke all on function public.semver_gte(text, text) from public;
grant execute on function public.semver_gte(text, text) to public;

-- The version a report came from: the app's own context key, with the flat key
-- some older clients used as a fallback.
create or replace function public.bug_reported_version(p_context jsonb)
returns text
language sql
immutable
parallel safe
as $$
  select coalesce(p_context #>> '{app,version}', p_context ->> 'app_version');
$$;
revoke all on function public.bug_reported_version(jsonb) from public;
grant execute on function public.bug_reported_version(jsonb) to public;

-- A "fixed" row written before this must not keep a value the new format
-- refuses. There is no honest version to invent, so those go back to the queue
-- for the team to mark again (reopening clears the rest and re-syncs followers).
update public.bug_reports set status = 'looking'
where status = 'fixed' and fixed_in !~ '^[0-9]+\.[0-9]+\.[0-9]+$' and duplicate_of is null;
update public.bug_reports set fixed_in = null, status = 'duplicate'
where status = 'fixed' and fixed_in !~ '^[0-9]+\.[0-9]+\.[0-9]+$' and duplicate_of is not null;

alter table public.bug_reports
  add constraint bug_reports_fixed_in_format
    check (fixed_in is null or fixed_in ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  -- Never older than the build the report came from. Followers inherit the
  -- root's version (their reporters may be on newer builds than the fix), and a
  -- missing or unparsable reported version skips the guard.
  add constraint bug_reports_fixed_not_before_report
    check (
      status <> 'fixed'
      or duplicate_of is not null
      or public.semver_gte(fixed_in, public.bug_reported_version(context)) is distinct from false
    );

-- Same function as before with the new rules: the version is normalised
-- (build metadata stripped), must be plain X.Y.Z, and may not predate the
-- report. Setting fixed_in again on a row that is already fixed is allowed (a
-- release gets skipped), and the existing trigger cascades it to its followers.
create or replace function public.admin_set_bug_status(
  p_code text,
  p_status text,
  p_fixed_in text default null,
  p_reason text default null,
  p_duplicate_of_code text default null,
  p_public_title text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_original uuid;
  v_context jsonb;
  v_version text := nullif(btrim(regexp_replace(coalesce(p_fixed_in, ''), '\+.*$', '')), '');
begin
  select id, context into v_id, v_context from public.bug_reports where code = p_code;
  if v_id is null then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  if p_status not in ('received', 'looking', 'fixed', 'wontfix', 'duplicate') then
    raise exception 'invalid_status' using errcode = '22023';
  end if;
  if p_status = 'fixed' then
    if v_version is null then
      raise exception 'fixed_in_required' using errcode = '22023';
    end if;
    if v_version !~ '^[0-9]+\.[0-9]+\.[0-9]+$' then
      raise exception 'fixed_in_invalid' using errcode = '22023';
    end if;
    if public.semver_gte(v_version, public.bug_reported_version(v_context)) is false then
      raise exception 'fixed_before_report' using errcode = '22023';
    end if;
  end if;
  if p_status = 'wontfix'
     and char_length(regexp_replace(coalesce(p_reason, ''), '\s', '', 'g')) < 20 then
    raise exception 'reason_required' using errcode = '22023';
  end if;
  if p_status = 'duplicate' then
    if nullif(btrim(coalesce(p_duplicate_of_code, '')), '') is null then
      raise exception 'original_required' using errcode = '22023';
    end if;
    select id into v_original from public.bug_reports where code = btrim(p_duplicate_of_code);
    if v_original is null then
      raise exception 'unknown_original' using errcode = 'P0002';
    end if;
  end if;

  update public.bug_reports set
    status = p_status,
    fixed_in = case when p_status = 'fixed' then v_version end,
    reason = case when p_status = 'wontfix' then btrim(p_reason) end,
    duplicate_of = case when p_status = 'duplicate' then v_original end,
    public_title = coalesce(nullif(btrim(coalesce(p_public_title, '')), ''), public_title)
  where id = v_id;
end $$;

revoke all on function public.admin_set_bug_status(text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.admin_set_bug_status(text, text, text, text, text, text) to service_role;

-- Deleting reports (or the account behind them) must never trip over its own
-- followers. The BEFORE DELETE trigger from the first bug-board migration
-- updated rows that could be part of the same delete (a user who owns both an
-- original and its follower), which Postgres refuses. The foreign key already
-- nulls the link when an original goes; this rule turns the follower that was
-- still just "duplicate" back into an ordinary received report. A follower that
-- had been mirrored as fixed or won't fix keeps that outcome on its own.
drop trigger if exists bug_reports_before_delete on public.bug_reports;
drop function if exists public.bug_reports_before_delete();

create or replace function public.bug_reports_before_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_root uuid;
begin
  if tg_op = 'UPDATE' then
    new.updated_at := now();
    if new.status = 'duplicate' and new.duplicate_of is null and old.duplicate_of is not null then
      new.status := 'received';
    end if;
  end if;

  if new.status in ('received', 'looking') then
    new.reason := null;
    new.duplicate_of := null;
    new.fixed_in := null;
    new.closed_at := null;
  end if;

  if new.duplicate_of is not null then
    if tg_op = 'UPDATE' and new.duplicate_of = new.id then
      raise exception 'cannot_duplicate_self' using errcode = '22023';
    end if;
    select coalesce(r.duplicate_of, r.id) into v_root
    from public.bug_reports r where r.id = new.duplicate_of;
    if not found then
      raise exception 'unknown_original' using errcode = 'P0002';
    end if;
    if tg_op = 'UPDATE' and v_root = new.id then
      raise exception 'cannot_duplicate_self' using errcode = '22023';
    end if;
    new.duplicate_of := v_root;
  end if;

  if new.status in ('fixed', 'wontfix', 'duplicate') then
    if tg_op = 'INSERT'
       or (old.status is distinct from new.status and new.closed_at is not distinct from old.closed_at) then
      new.closed_at := now();
    end if;
  end if;

  return new;
end $$;
revoke all on function public.bug_reports_before_write() from public, anon, authenticated;
