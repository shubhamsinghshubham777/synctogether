# SyncTogether Web Portal

The official web application for [SyncTogether](https://synctogether.app) - featuring the marketing landing page, app downloads, release changelogs, FAQ and legal policies, Supabase authentication, and Merchant of Record (MoR) billing checkout (Creem) & account management.

## Tech Stack

- **Framework**: [Next.js 16](https://nextjs.org/) (App Router) + React 19
- **Styling**: [Tailwind CSS v4](https://tailwindcss.com/) with dark projection booth cinema tokens matching the Flutter app design system
- **Auth & Database**: [Supabase](https://supabase.com/) (`@supabase/ssr`) with PostgreSQL row-level security and Realtime subscriptions
- **Billing**: [Creem](https://docs.creem.io) Merchant of Record behind a thin provider seam (`lib/billing/`), Node native `crypto.createHmac`
- **Testing**: Node.js built-in test runner (`node --test`) with TypeScript

## Getting Started

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Environment Variables

Copy `.env.example` to `.env.local`:

```bash
cp .env.example .env.local
```

Required and optional environment variables:
- `NEXT_PUBLIC_SUPABASE_URL`: Supabase URL (e.g. `http://127.0.0.1:54321` for local dev or production project URL)
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`: Supabase anon/publishable key
- `SUPABASE_SERVICE_ROLE_KEY`: Supabase service role secret (used securely by webhook handlers to update `subscriptions`)
- `NEXT_PUBLIC_SITE_URL`: Web portal origin URL (e.g. `http://localhost:3000` or `https://synctogether.app`) for OAuth redirects and invite bridges
- `CREEM_ENVIRONMENT` (`test` for sandbox), `CREEM_API_KEY`, `CREEM_WEBHOOK_SECRET`, `CREEM_PRODUCT_MONTHLY`, `CREEM_PRODUCT_ANNUAL`: Creem billing (one USD price for everyone)
- `NEXT_PUBLIC_TURNSTILE_SITE_KEY`: Cloudflare Turnstile site key for captcha verification
- `NEXT_PUBLIC_POSTHOG_KEY`: PostHog public project key for web telemetry (optional)
- `NEXT_PUBLIC_POSTHOG_HOST`: PostHog host endpoint (defaults to `https://us.i.posthog.com`)

### 3. Run Development Server

```bash
npm run dev
```

Visit [http://localhost:3000](http://localhost:3000).

### 4. Run Tests

```bash
npm test
```

Runs the test suite in `tests/` (billing core decisions, each provider's signature verification and event mapping, the database writer against a fake client, and the fulfil fallback).

## Local Webhook Testing

The webhook is `/api/billing/webhook/creem`. The Creem CLI forwards test-mode webhooks to your dev server with no tunnel:

```bash
CREEM_API_KEY=creem_test_... npx @creem_io/cli listen --webhook "$CREEM_CLI_WEBHOOK_ID" \
  --forward-to http://localhost:3000/api/billing/webhook/creem
# or: ./scripts/dev.sh -w
```

Create the persistent endpoint once with `creem webhooks create --name "local dev" --delivery-mode cli --event subscription.paid ...` and put its signing secret in `CREEM_WEBHOOK_SECRET` (without `--webhook`, `listen` makes a throwaway endpoint with a new secret each run).

## Key Routes & Architecture

### User-Facing Pages
- `/` - Homepage featuring interactive hero playback synchronizer and feature breakdown
- `/pricing` & `/premium` - Interactive plan selector, FAQ, and checkout (redirects to Creem's hosted checkout)
- `/account` - Authenticated account overview, subscription status, renewal date, and cancellation action
- `/auth`, `/auth/callback`, `/auth/desktop-callback` - Supabase Google OAuth, Apple Sign-In, and Turnstile-protected email OTP authentication flows and desktop PKCE bridge
- `/download` - Desktop installers for macOS (signed & notarized DMG) and Windows (Inno Setup executable)
- `/changelog` - Release history fetched directly from GitHub releases
- `/faq`, `/privacy`, `/terms`, `/refund` - Help center and compliance documentation
- `/admin` - Protected administration console for inspecting subscriber entitlements
- `/internal/metrics` - Real-time system performance and sync health telemetry dashboard

### API Route Handlers
- `POST /api/billing/webhook/[provider]` - Receives and verifies a provider's subscription webhooks (`creem`), normalises them, and applies them through the single database writer with replay protection and write-deduplication.
- `POST /api/billing/checkout` - Authenticated; creates a checkout with the active provider (`BILLING_PROVIDER`) and returns its URL. The user id comes from the session, never the body.
- `POST /api/billing/cancel` - Authenticated; cancels at period end through the provider named by the row's `source`.
- `POST /api/billing/fulfill` - Fallback verification for the gap before a webhook lands; never invents a billing period.
- `GET /api/billing/prices` - The single USD price (no local pricing).
- `GET /api/download` - Direct download route redirecting to the latest platform-specific client installer.
- `GET /api/releases/latest` - Proxies GitHub release assets and metadata for downloads.
- `GET /api/internal/metrics` - Aggregated system and room metrics endpoint.
- `POST /api/analytics/collect` - Proxied privacy-preserving web analytics event collector.
