-- Paddle subscription identifiers, plus the fields that make webhook delivery
-- idempotent and ordered.
--
-- Three separate bugs share one root cause, which is that nothing here recorded
-- *which* Paddle subscription a row came from:
--
--   * `/api/paddle/cancel` and `/api/paddle/fulfill` both fetched an unfiltered
--     page of the seller's subscriptions (per_page 20 and 50 respectively) and
--     scanned it for a matching `custom_data.user_id`. Paddle returns newest
--     first, so past those counts older customers simply are not in the
--     response. Cancellation then failed at Paddle while the local row was
--     deleted anyway - the customer loses access and keeps being billed.
--
--   * Webhooks are delivered at least once and are not ordered. With no
--     event id and no `occurred_at` recorded, a replayed `subscription.activated`
--     re-grants premium after a cancellation, and an `updated` overtaking a
--     `canceled` resurrects it.
--
-- `paddle_subscription_id` is uniquely indexed where present so two profiles
-- can never claim the same Paddle subscription. It is nullable because rows
-- predating this migration, and rows created by `debug_grant_premium` or a
-- manual grant, legitimately have no Paddle subscription behind them.

alter table public.subscriptions
  add column if not exists paddle_subscription_id text,
  add column if not exists paddle_customer_id text,
  add column if not exists last_event_id text,
  add column if not exists last_event_at timestamptz;

create unique index if not exists subscriptions_paddle_subscription_id_key
  on public.subscriptions (paddle_subscription_id)
  where paddle_subscription_id is not null;

comment on column public.subscriptions.paddle_subscription_id is
  'Paddle subscription id (sub_...). Null for manual and debug grants. Addressed directly by the cancel route rather than scanning the seller''s subscription list.';
comment on column public.subscriptions.paddle_customer_id is
  'Paddle customer id (ctm_...), used to scope API lookups to this user.';
comment on column public.subscriptions.last_event_id is
  'Paddle event id (evt_...) of the last webhook applied, for replay rejection.';
comment on column public.subscriptions.last_event_at is
  'Paddle occurred_at of the last webhook applied. Events not strictly newer are ignored, which is what makes out-of-order delivery safe.';
