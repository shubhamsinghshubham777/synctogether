-- Microsoft Store in-app purchase, the third payment rail beside Apple
-- (`apple_subscriptions`) and hand-granted seats (`subscriptions`).
--
-- Web checkout is gone (no merchant of record would take the business), so the
-- Microsoft Store is how a Windows user pays. Like Apple, the rows live in a
-- table of their own: `subscriptions` is one row per user and the rails would
-- overwrite each other.
--
-- A row is keyed on the Store's collection item id (stable across renewals)
-- and bound to one account once; rebinding is refused, as with Apple. Unlike
-- Apple there are no server notifications, so the app re-verifies on launch
-- and the row's `expires_at` simply runs out if it stops doing so.

create table public.microsoft_subscriptions (
  purchase_id text primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  product_id text not null,
  sku_id text not null,
  expires_at timestamptz,
  revoked_at timestamptz,
  auto_renew boolean,
  observed_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index microsoft_subscriptions_user_id_idx on public.microsoft_subscriptions (user_id);

comment on table public.microsoft_subscriptions is
  'Microsoft Store subscriptions, one row per collection item id. Written only by the ms-iap Edge Function through apply_microsoft_subscription.';
comment on column public.microsoft_subscriptions.observed_at is
  'When the Store was queried for this state. Only strictly newer observations are applied.';

alter table public.microsoft_subscriptions enable row level security;

create policy "users read their own microsoft subscriptions"
  on public.microsoft_subscriptions for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.microsoft_subscriptions from public, anon, authenticated;
grant select on public.microsoft_subscriptions to authenticated;
grant all on public.microsoft_subscriptions to service_role;

alter publication supabase_realtime add table public.microsoft_subscriptions;
alter table public.microsoft_subscriptions replica identity full;

create or replace function public.effective_tier(p_user_id uuid default auth.uid())
returns text
language sql stable security definer set search_path = ''
as $$
  select case
    when p_user_id is null then 'guest'
    when coalesce((select is_guest from public.profiles where id = p_user_id), false) then 'guest'
    when exists (
      select 1 from public.subscriptions s
      where s.user_id = p_user_id
        and s.tier = 'premium'
        and (s.current_period_end is null or s.current_period_end > now())
    ) then 'premium'
    when exists (
      select 1 from public.apple_subscriptions a
      where a.user_id = p_user_id
        and a.revoked_at is null
        and a.expires_at > now()
    ) then 'premium'
    when exists (
      select 1 from public.microsoft_subscriptions m
      where m.user_id = p_user_id
        and m.revoked_at is null
        and m.expires_at > now()
    ) then 'premium'
    else 'free'
  end;
$$;

create or replace function public.apply_microsoft_subscription(
  p_user_id uuid,
  p_purchase_id text,
  p_product_id text,
  p_sku_id text,
  p_expires_at timestamptz,
  p_revoked_at timestamptz,
  p_auto_renew boolean,
  p_observed_at timestamptz
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_row public.microsoft_subscriptions;
begin
  if p_user_id is null then
    return 'unbound';
  end if;

  select * into v_row from public.microsoft_subscriptions
  where purchase_id = p_purchase_id
  for update;

  if not found then
    insert into public.microsoft_subscriptions (
      purchase_id, user_id, product_id, sku_id, expires_at, revoked_at, auto_renew, observed_at
    ) values (
      p_purchase_id, p_user_id, p_product_id, p_sku_id, p_expires_at, p_revoked_at, p_auto_renew, p_observed_at
    );
    return 'applied';
  end if;

  if v_row.user_id <> p_user_id then
    return 'owned_elsewhere';
  end if;

  if p_observed_at <= v_row.observed_at then
    return 'stale';
  end if;

  update public.microsoft_subscriptions set
    product_id = p_product_id,
    sku_id = p_sku_id,
    expires_at = p_expires_at,
    revoked_at = p_revoked_at,
    auto_renew = coalesce(p_auto_renew, auto_renew),
    observed_at = p_observed_at,
    updated_at = now()
  where purchase_id = p_purchase_id;
  return 'applied';
end;
$$;

revoke all on function public.apply_microsoft_subscription(uuid, text, text, text, timestamptz, timestamptz, boolean, timestamptz)
  from public, anon, authenticated;
grant execute on function public.apply_microsoft_subscription(uuid, text, text, text, timestamptz, timestamptz, boolean, timestamptz)
  to service_role;

-- Same signature and return type as before, so the grants survive.
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
        and a.expires_at > now())),
    (select 'microsoft' where exists (
      select 1 from public.microsoft_subscriptions m
      where m.user_id = auth.uid()
        and m.revoked_at is null
        and m.expires_at > now()))
  ], null);
$$;
