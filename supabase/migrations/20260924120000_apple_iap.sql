-- Apple In-App Purchase, as a second payment rail beside Paddle.
--
-- The Mac App Store edition used to ship with no premium at all, and Apple
-- rejected it anyway: guideline 3.1.1 objects to the app *reaching* premium
-- bought elsewhere (a free member in a premium host's room is exactly that),
-- and 3.1.3(b) only permits honouring a web purchase when the same thing is
-- also for sale in the app. So premium is now sold through StoreKit too, and
-- a subscription from either rail unlocks the same account everywhere.
--
-- Apple subscriptions live in their own table rather than in `subscriptions`,
-- because that table is one row per user and the two rails would otherwise
-- overwrite each other: a Paddle `canceled` would revoke a live App Store
-- subscription, and an App Store expiry would revoke a paid Paddle one.
-- `effective_tier` reads both, and is still the single arbiter.
--
-- A row is keyed on Apple's `originalTransactionId`, which is stable across
-- renewals, and bound to a user once. Rebinding is refused: one Apple ID
-- restoring on a second SyncTogether account must not move premium off the
-- first (or hand one purchase to any number of accounts).

create table public.apple_subscriptions (
  original_transaction_id text primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  product_id text not null,
  environment text not null check (environment in ('Production', 'Sandbox', 'Xcode', 'LocalTesting')),
  latest_transaction_id text not null,
  expires_at timestamptz,
  revoked_at timestamptz,
  auto_renew boolean,
  signed_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index apple_subscriptions_user_id_idx on public.apple_subscriptions (user_id);

comment on table public.apple_subscriptions is
  'App Store subscriptions, one row per originalTransactionId. Written only by the apple-iap Edge Function through apply_apple_transaction.';
comment on column public.apple_subscriptions.expires_at is
  'Entitled-until: the transaction expiresDate, or the billing grace period end when Apple grants one. A failed renewal is a grace state, never a revocation - the Paddle past_due rule.';
comment on column public.apple_subscriptions.signed_at is
  'signedDate of the payload last applied. Notifications arrive unordered and at least once; only strictly newer payloads are applied.';

alter table public.apple_subscriptions enable row level security;

create policy "users read their own apple subscriptions"
  on public.apple_subscriptions for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.apple_subscriptions from public, anon, authenticated;
grant select on public.apple_subscriptions to authenticated;
grant all on public.apple_subscriptions to service_role;

alter publication supabase_realtime add table public.apple_subscriptions;
alter table public.apple_subscriptions replica identity full;

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
    else 'free'
  end;
$$;

-- The binding and ordering decisions, in SQL so pgTAP can cover them. The
-- Edge Function has already verified Apple's signature; this decides whether
-- the verified payload is allowed to change anything.
--
-- `p_user_id` is null for a server notification whose transaction carries no
-- appAccountToken: it can update a row that is already bound, but can never
-- create one, because nothing in it says whose purchase it is.
create or replace function public.apply_apple_transaction(
  p_user_id uuid,
  p_original_transaction_id text,
  p_transaction_id text,
  p_product_id text,
  p_environment text,
  p_expires_at timestamptz,
  p_revoked_at timestamptz,
  p_auto_renew boolean,
  p_signed_at timestamptz
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_row public.apple_subscriptions;
begin
  select * into v_row from public.apple_subscriptions
  where original_transaction_id = p_original_transaction_id
  for update;

  if not found then
    if p_user_id is null then
      return 'unbound';
    end if;
    insert into public.apple_subscriptions (
      original_transaction_id, user_id, product_id, environment,
      latest_transaction_id, expires_at, revoked_at, auto_renew, signed_at
    ) values (
      p_original_transaction_id, p_user_id, p_product_id, p_environment,
      p_transaction_id, p_expires_at, p_revoked_at, p_auto_renew, p_signed_at
    );
    return 'applied';
  end if;

  if p_user_id is not null and v_row.user_id <> p_user_id then
    return 'owned_elsewhere';
  end if;

  if p_signed_at <= v_row.signed_at then
    return 'stale';
  end if;

  update public.apple_subscriptions set
    product_id = p_product_id,
    environment = p_environment,
    latest_transaction_id = p_transaction_id,
    expires_at = p_expires_at,
    revoked_at = p_revoked_at,
    auto_renew = coalesce(p_auto_renew, auto_renew),
    signed_at = p_signed_at,
    updated_at = now()
  where original_transaction_id = p_original_transaction_id;
  return 'applied';
end;
$$;

revoke all on function public.apply_apple_transaction(uuid, text, text, text, text, timestamptz, timestamptz, boolean, timestamptz)
  from public, anon, authenticated;
grant execute on function public.apply_apple_transaction(uuid, text, text, text, text, timestamptz, timestamptz, boolean, timestamptz)
  to service_role;

-- Which rails currently entitle the caller. The subscription screen needs it
-- to say where a subscription is managed, and to stop someone who already pays
-- through one rail from buying premium again through the other.
create or replace function public.my_premium_sources()
returns text[]
language sql stable security definer set search_path = ''
as $$
  select array_remove(array[
    (select case when s.source = 'paddle' then 'paddle' else 'manual' end
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

revoke all on function public.my_premium_sources() from public, anon;
grant execute on function public.my_premium_sources() to authenticated;
