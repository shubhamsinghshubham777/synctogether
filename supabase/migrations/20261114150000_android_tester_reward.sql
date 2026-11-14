-- Thank-you for finishing the Android closed test: two weeks of Premium.
-- Granted by the operator from /internal/android once the 14 days are up.
alter table public.android_testers add column if not exists reward_granted_at timestamptz;

-- One tester -> a hand-granted ('manual') Premium period of 14 days, extending an existing manual one.
-- The tester is matched to a SyncTogether account by email; no account yet = 'no_account', nothing
-- stamped, so pressing again later works. A plan bought elsewhere is never touched ('has_plan').
create or replace function public.grant_android_tester_reward(p_tester_id bigint)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  t public.android_testers;
  v_uid uuid;
  s public.subscriptions;
begin
  select * into t from public.android_testers where id = p_tester_id for update;
  if not found then return 'not_found'; end if;
  if t.reward_granted_at is not null then return 'already'; end if;
  if t.added_at is null then return 'not_added'; end if;

  select u.id into v_uid from auth.users u where lower(u.email) = t.email limit 1;
  if v_uid is null then return 'no_account'; end if;

  select * into s from public.subscriptions where user_id = v_uid;
  if found and s.source not in ('manual', 'debug') then return 'has_plan'; end if;

  insert into public.subscriptions (user_id, tier, source, current_period_end)
  values (v_uid, 'premium', 'manual', now() + interval '14 days')
  on conflict (user_id) do update
    set tier = 'premium',
        current_period_end = greatest(coalesce(public.subscriptions.current_period_end, now()), now()) + interval '14 days',
        updated_at = now();

  update public.android_testers set reward_granted_at = now() where id = p_tester_id;
  return 'granted';
end $$;

revoke all on function public.grant_android_tester_reward(bigint) from public, anon, authenticated;
grant execute on function public.grant_android_tester_reward(bigint) to service_role;
