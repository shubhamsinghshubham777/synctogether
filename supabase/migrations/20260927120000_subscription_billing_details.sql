-- What a Paddle subscription actually charges, so revenue can be summed rather
-- than guessed.
--
-- The internal dashboard computed MRR as `premium_count * $5`. Nobody pays $5:
-- the prices are $3.99/mo and $29.99/yr, with localised overrides (INR 199 and
-- 999), and the count included manual grants, debug grants and past_due rows.
-- Nothing recorded the price, the interval or the Paddle status, so no honest
-- figure was possible. The webhook now writes these from `items[0].price` and
-- the subscription's own `currency_code`.
--
-- All nullable: rows written before this migration, and manual or debug grants,
-- have no Paddle price behind them. The dashboard reports those as "unpriced"
-- rather than filling in a number. A Paddle row gets its price on its next
-- webhook (every renewal sends `subscription.updated`).

alter table public.subscriptions
  add column if not exists price_id text,
  add column if not exists unit_amount bigint check (unit_amount is null or unit_amount >= 0),
  add column if not exists currency text check (currency is null or currency ~ '^[A-Z]{3}$'),
  add column if not exists billing_interval text check (billing_interval is null or billing_interval in ('day', 'week', 'month', 'year')),
  add column if not exists billing_frequency int check (billing_frequency is null or billing_frequency > 0),
  add column if not exists paddle_status text,
  add column if not exists scheduled_cancel_at timestamptz;

comment on column public.subscriptions.unit_amount is
  'Recurring charge per billing cycle in the currency''s lowest denomination (Paddle''s unit), resolved against the subscription currency so a localised override is what gets recorded, not the base USD price. Times quantity.';
comment on column public.subscriptions.currency is
  'ISO 4217 code the subscription bills in (Paddle currency_code).';
comment on column public.subscriptions.billing_interval is
  'Paddle billing_cycle.interval. With billing_frequency, what one charge covers.';
comment on column public.subscriptions.paddle_status is
  'Paddle subscription status as of the last applied event (active, trialing, past_due, paused, canceled).';
comment on column public.subscriptions.scheduled_cancel_at is
  'Set while a cancellation is scheduled (scheduled_change.action = cancel): the row is still premium but will not renew.';
