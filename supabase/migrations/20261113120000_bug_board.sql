-- The internal bug board: two closed states beyond "fixed" so no report is left
-- ambiguous. A won't-fix must carry the reason the user will read, a duplicate
-- must point at the original so the user can follow it. Duplicates are
-- "followers": they mirror the original's outcome (fixed in X, or closed with
-- the same reason) and fall back to plain "duplicate" while it is open.

alter table public.bug_reports drop constraint if exists bug_reports_status_check;

-- Rows flipped to fixed by hand before this migration may lack a version; the
-- new constraint requires one.
update public.bug_reports set fixed_in = 'an earlier version'
where status = 'fixed' and nullif(btrim(coalesce(fixed_in, '')), '') is null;

alter table public.bug_reports
  add column reason text,
  add column duplicate_of uuid references public.bug_reports(id) on delete set null,
  add column public_title text,
  add column closed_at timestamptz,
  add column notify_when_fixed boolean not null default false,
  add column note_appendix text;

alter table public.bug_reports
  add constraint bug_reports_status_check
    check (status in ('received', 'looking', 'fixed', 'wontfix', 'duplicate')),
  add constraint bug_reports_public_title_len
    check (public_title is null or char_length(public_title) <= 120),
  add constraint bug_reports_appendix_len
    check (note_appendix is null or char_length(note_appendix) <= 2000),
  -- A link to an original only exists on the closed-ish states a follower can be in.
  add constraint bug_reports_duplicate_of_status
    check (duplicate_of is null or status in ('duplicate', 'fixed', 'wontfix')),
  add constraint bug_reports_status_fields check (
    case status
      when 'received' then reason is null and duplicate_of is null and fixed_in is null
      when 'looking' then reason is null and duplicate_of is null and fixed_in is null
      when 'duplicate' then duplicate_of is not null and reason is null and fixed_in is null
      when 'fixed' then nullif(btrim(coalesce(fixed_in, '')), '') is not null and reason is null
      when 'wontfix' then fixed_in is null
        and char_length(regexp_replace(coalesce(reason, ''), '\s', '', 'g')) >= 20
    end
  );

create index bug_reports_duplicate_of_idx on public.bug_reports (duplicate_of)
  where duplicate_of is not null;

-- The BEFORE side: reopening clears everything a closed state carried, a link
-- always points at the root original (never at another duplicate), and a report
-- can never be a duplicate of itself, directly or through a cycle.
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

-- Followers mirror their root: fixed in the same version, or closed with the
-- same reason; plain "duplicate" while the root is open.
create or replace function public.bug_sync_followers(p_root uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.bug_reports f
  set status = case r.status when 'fixed' then 'fixed' when 'wontfix' then 'wontfix' else 'duplicate' end,
      fixed_in = case when r.status = 'fixed' then r.fixed_in end,
      reason = case when r.status = 'wontfix' then r.reason end
  from public.bug_reports r
  where r.id = p_root
    and f.duplicate_of = p_root
    and (f.status, f.fixed_in, f.reason) is distinct from (
      case r.status when 'fixed' then 'fixed' when 'wontfix' then 'wontfix' else 'duplicate' end,
      case when r.status = 'fixed' then r.fixed_in end,
      case when r.status = 'wontfix' then r.reason end
    );
end $$;

create or replace function public.bug_reports_after_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- A report that had followers of its own just became a duplicate: its
  -- followers follow the new root, so the chain stays one level deep.
  if new.duplicate_of is not null and old.duplicate_of is distinct from new.duplicate_of then
    update public.bug_reports set duplicate_of = new.duplicate_of where duplicate_of = new.id;
    perform public.bug_sync_followers(new.duplicate_of);
  end if;
  if new.duplicate_of is null
     and (old.status, old.fixed_in, old.reason) is distinct from (new.status, new.fixed_in, new.reason) then
    perform public.bug_sync_followers(new.id);
  end if;
  return new;
end $$;

-- Deleting an original (or its author's account) must not strand followers on
-- a link that points nowhere: they go back to the queue as ordinary reports.
create or replace function public.bug_reports_before_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.bug_reports set status = 'received', duplicate_of = null
  where duplicate_of = old.id;
  return old;
end $$;

create trigger bug_reports_before_write
  before insert or update on public.bug_reports
  for each row execute function public.bug_reports_before_write();
create trigger bug_reports_after_write
  after update on public.bug_reports
  for each row execute function public.bug_reports_after_write();
create trigger bug_reports_before_delete
  before delete on public.bug_reports
  for each row execute function public.bug_reports_before_delete();

revoke all on function public.bug_reports_before_write() from public, anon, authenticated;
revoke all on function public.bug_sync_followers(uuid) from public, anon, authenticated;
revoke all on function public.bug_reports_after_write() from public, anon, authenticated;
revoke all on function public.bug_reports_before_delete() from public, anon, authenticated;

-- How many other reports describe the same issue: the root's followers. The
-- same number for the original and for each follower (a follower counts the
-- root plus its siblings, minus itself).
create or replace function public.bug_same_count(p_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int from public.bug_reports f
  where f.duplicate_of = (select coalesce(b.duplicate_of, b.id) from public.bug_reports b where b.id = p_id);
$$;
revoke all on function public.bug_same_count(uuid) from public, anon, authenticated;
grant execute on function public.bug_same_count(uuid) to service_role;

create or replace function public.bug_category_label(p_category text)
returns text
language sql
immutable
as $$
  select case p_category
    when 'video' then 'Video issue' when 'sound' then 'Sound issue'
    when 'sync' then 'Sync issue' when 'chat' then 'Chat issue'
    when 'camera' then 'Camera issue' else 'Bug report' end;
$$;
revoke all on function public.bug_category_label(text) from public, anon;
grant execute on function public.bug_category_label(text) to authenticated, service_role;

-- The reports list now also carries what a closed state needs. The original's
-- title is the team's neutral public_title (or the category label), never the
-- other reporter's note.
drop function public.my_bug_reports();
create function public.my_bug_reports()
returns table (
  code text,
  category text,
  title text,
  status text,
  fixed_in text,
  created_at timestamptz,
  reason text,
  duplicate_of_code text,
  duplicate_of_title text,
  duplicate_of_status text,
  same_count integer,
  notify_when_fixed boolean,
  closed_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select b.code, b.category,
         coalesce(nullif(left(b.note, 80), ''), initcap(coalesce(b.category, 'bug report'))),
         b.status, b.fixed_in, b.created_at,
         b.reason,
         o.code,
         case when o.id is null then null
              else coalesce(nullif(btrim(o.public_title), ''), public.bug_category_label(o.category)) end,
         o.status,
         public.bug_same_count(b.id),
         b.notify_when_fixed,
         b.closed_at
  from public.bug_reports b
  left join public.bug_reports o on o.id = b.duplicate_of
  where b.user_id = auth.uid()
  order by b.created_at desc
  limit 100;
$$;
revoke all on function public.my_bug_reports() from public, anon;
grant execute on function public.my_bug_reports() to authenticated;

create or replace function public.set_bug_notify_when_fixed(p_code text, p_on boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  update public.bug_reports set notify_when_fixed = coalesce(p_on, false)
  where code = p_code and user_id = auth.uid();
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
end $$;

create or replace function public.append_bug_note(p_code text, p_text text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_text text := nullif(btrim(coalesce(p_text, '')), '');
  v_current text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_text is null then
    raise exception 'empty_note' using errcode = '22023';
  end if;
  select note_appendix into v_current from public.bug_reports
  where code = p_code and user_id = auth.uid() for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  v_current := case when v_current is null then v_text else v_current || E'\n\n' || v_text end;
  if char_length(v_current) > 2000 then
    raise exception 'note_too_long' using errcode = '22023';
  end if;
  update public.bug_reports set note_appendix = v_current
  where code = p_code and user_id = auth.uid();
end $$;

revoke all on function public.set_bug_notify_when_fixed(text, boolean) from public, anon;
grant execute on function public.set_bug_notify_when_fixed(text, boolean) to authenticated;
revoke all on function public.append_bug_note(text, text) from public, anon;
grant execute on function public.append_bug_note(text, text) to authenticated;

-- Team mutations: service role only (the internal board), never a client. Every
-- required field is checked here with a friendly code; the table constraints
-- are the backstop.
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
begin
  select id into v_id from public.bug_reports where code = p_code;
  if v_id is null then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  if p_status not in ('received', 'looking', 'fixed', 'wontfix', 'duplicate') then
    raise exception 'invalid_status' using errcode = '22023';
  end if;
  if p_status = 'fixed' and nullif(btrim(coalesce(p_fixed_in, '')), '') is null then
    raise exception 'fixed_in_required' using errcode = '22023';
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
    fixed_in = case when p_status = 'fixed' then btrim(p_fixed_in) end,
    reason = case when p_status = 'wontfix' then btrim(p_reason) end,
    duplicate_of = case when p_status = 'duplicate' then v_original end,
    public_title = coalesce(nullif(btrim(coalesce(p_public_title, '')), ''), public_title)
  where id = v_id;
end $$;

revoke all on function public.admin_set_bug_status(text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.admin_set_bug_status(text, text, text, text, text, text) to service_role;
