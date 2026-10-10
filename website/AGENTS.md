<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

## SyncTogether Web Portal Architecture & Guidelines

### Overview
This Next.js 16 application serves as the marketing site, downloads portal, legal documentation, authentication bridge, and Merchant of Record (MoR, Creem) subscription & account management portal for SyncTogether.

### Supabase SSR Patterns
- **Client Components**: Use `createClient()` from `lib/supabase/client.ts` (`createBrowserClient`).
- **Server Components & Route Handlers**: Use `createClient()` from `lib/supabase/server.ts` (`createServerClient` with `cookies()`).
- **Admin / Webhooks**: Use `createAdminClient()` from `lib/supabase/admin.ts` (`SUPABASE_SERVICE_ROLE_KEY`) only in secure server route handlers that require elevated database privileges (e.g. updating `subscriptions`).

### Billing Invariants (`lib/billing/`)
1. **Thin provider seam**: one `BillingProvider` interface, one `NormalizedEvent`, one adapter (Creem), one writer (`apply.ts`). `subscriptions.source` owns a row; cancel, fulfil and webhooks dispatch on it. No plugin registry.
2. **Webhook verification fails closed**: `/api/billing/webhook/[provider]` verifies the raw body before parsing (Creem: `creem-signature` hex HMAC of the raw body, no timestamp, so replay protection is the event cursor). A missing secret answers 500 so the provider retries; anything else 401.
3. **Strict ordering and dedup**: `shouldApplyEvent` applies only strictly newer events (the cursor advances even for ignored ones); `isRedundantGrant` skips no-op writes that would wake every Flutter client over Realtime. `eventTargetsRow` stops one provider's event changing a row another provider currently holds.
4. **`past_due` is grace, never revocation**; only `canceled` and `paused` revoke, and revoking sets `tier = 'free'` and dates the row rather than deleting it.
5. **Never invent a billing period**: no period end means 422 from the webhook and 202 from fulfil.
6. **Cancel at the period end**, addressed by stored subscription id; a failed remote call never touches the local row.
7. **Checkouts are created server-side** (`/api/billing/checkout`) so the user id comes from the session cookie.
Tests live in `tests/billing_*.test.ts`; a test that re-implements its subject inline is worse than none.

### Design System & Styling
- Styled with Tailwind CSS v4 in the Projection Booth language shared with the Flutter app (dark only, warm matte neutrals, Beam amber for the one live action, no gradients or blur). `app/globals.css` `@theme` remaps the legacy `purple`/`indigo`/`gray`/`white` scales onto it - prefer `beam-*`, `booth`, `seat`, `rail`, `screen`, `signal`, `cue`, `brass` in new code.
- Shared components in `components/`: `PTButton`, `GlassPanel`, `PlanCard`, `PricingTable`, `Header`, `Footer`, and `Ticket` (the notched invite/room-code object). Link-preview images use `lib/og-ticket.tsx`. The homepage hero lives in `components/hero/` and drives the room mockups in `components/room-sim/`.

### Testing & Verification
- Unit test suite in `tests/` tests billing decisions, each provider's signature verification and event mapping, and the database writer.
- Run tests with `npm test`.
