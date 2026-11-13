-- In-app bug reports: a user taps the bug button, the client sends a note plus
-- a jsonb context, and gets a BUG-XXXX code back. The team triages in SQL or
-- the dashboard and flips status / fixed_in; the owner sees it in "Your reports".

create table public.bug_reports (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  user_id uuid not null references auth.users(id) on delete cascade,
  category text,
  note text,
  context jsonb not null default '{}'::jsonb,
  sentry_event_id text,
  status text not null default 'received'
    check (status in ('received', 'looking', 'fixed')),
  fixed_in text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bug_reports_category_check
    check (category is null or category in ('video', 'sound', 'sync', 'chat', 'camera', 'other')),
  constraint bug_reports_note_len check (note is null or char_length(note) <= 2000),
  constraint bug_reports_context_size check (pg_column_size(context) <= 16384)
);

create index bug_reports_user_created_idx on public.bug_reports (user_id, created_at desc);
create index bug_reports_status_idx on public.bug_reports (status) where status <> 'fixed';

alter table public.bug_reports enable row level security;

create policy bug_reports_owner_select on public.bug_reports
  for select to authenticated using (user_id = (select auth.uid()));

-- Clients never write rows directly; the RPC below is the only way in, and
-- status / fixed_in change only through the service role (the team).
revoke all on public.bug_reports from anon, authenticated;
grant select on public.bug_reports to authenticated;
grant all on public.bug_reports to service_role;

create or replace function public.submit_bug_report(
  p_category text,
  p_note text,
  p_context jsonb,
  p_sentry_event_id text
) returns table (code text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
  v_ctx jsonb := coalesce(p_context, '{}'::jsonb);
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_cat text := nullif(btrim(coalesce(p_category, '')), '');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_cat is not null and v_cat not in ('video', 'sound', 'sync', 'chat', 'camera', 'other') then
    raise exception 'invalid_category' using errcode = '22023';
  end if;
  if v_note is not null and char_length(v_note) > 2000 then
    raise exception 'note_too_long' using errcode = '22023';
  end if;
  if pg_column_size(v_ctx) > 16384 then
    raise exception 'context_too_large' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.bug_reports
    where user_id = v_uid and created_at > now() - interval '30 seconds'
  ) then
    raise exception 'rate_limited' using errcode = '54000';
  end if;

  loop
    v_code := 'BUG-' || (
      select string_agg(substr(v_alphabet, 1 + floor(random() * 32)::int, 1), '')
      from generate_series(1, 4));
    exit when not exists (select 1 from public.bug_reports b where b.code = v_code);
  end loop;

  insert into public.bug_reports (code, user_id, category, note, context, sentry_event_id)
  values (v_code, v_uid, v_cat, v_note, v_ctx, nullif(btrim(coalesce(p_sentry_event_id, '')), ''));

  return query select v_code;
end $$;

create or replace function public.my_bug_reports()
returns table (
  code text,
  category text,
  title text,
  status text,
  fixed_in text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select b.code, b.category,
         coalesce(nullif(left(b.note, 80), ''), initcap(coalesce(b.category, 'bug report'))),
         b.status, b.fixed_in, b.created_at
  from public.bug_reports b
  where b.user_id = auth.uid()
  order by b.created_at desc
  limit 100;
$$;

revoke all on function public.submit_bug_report(text, text, jsonb, text) from public, anon;
grant execute on function public.submit_bug_report(text, text, jsonb, text) to authenticated;
revoke all on function public.my_bug_reports() from public, anon;
grant execute on function public.my_bug_reports() to authenticated;
