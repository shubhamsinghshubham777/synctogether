-- First-night onboarding: shown once per account, not per device.
--
-- onboarded_at is null only for accounts that have never finished (or skipped)
-- the first-run flow. Every profile that exists when this lands is backfilled,
-- so nobody who already uses the app ever sees it.

alter table public.profiles add column if not exists onboarded_at timestamptz;

update public.profiles set onboarded_at = created_at where onboarded_at is null;

-- The column is not client-writable (profiles only grants display_name and
-- avatar_url), so finishing goes through this. Optionally sets the display name
-- in the same statement, so the name step and the flag can never disagree.
-- Idempotent: a second call keeps the first timestamp.
create or replace function public.complete_onboarding(p_display_name text default null)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := nullif(trim(coalesce(p_display_name, '')), '');
  v_at timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_name is not null and char_length(v_name) > 40 then
    raise exception 'name_too_long' using errcode = '22001';
  end if;
  update public.profiles
     set onboarded_at = coalesce(onboarded_at, now()),
         display_name = coalesce(v_name, display_name),
         updated_at = now()
   where id = v_uid
  returning onboarded_at into v_at;
  return v_at;
end $$;

revoke all on function public.complete_onboarding(text) from public, anon;
grant execute on function public.complete_onboarding(text) to authenticated;
