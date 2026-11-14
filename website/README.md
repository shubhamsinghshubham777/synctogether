# SyncTogether Web Portal

The official web application for [SyncTogether](https://synctogether.app) - featuring the marketing landing page, store links (App Store, Microsoft Store), release changelogs, FAQ and legal policies, Supabase authentication, and a read-only account page. There is no web checkout: Premium is sold only inside the store apps.

## Tech Stack

- **Framework**: [Next.js 16](https://nextjs.org/) (App Router) + React 19
- **Styling**: [Tailwind CSS v4](https://tailwindcss.com/) with dark projection booth cinema tokens matching the Flutter app design system
- **Auth & Database**: [Supabase](https://supabase.com/) (`@supabase/ssr`) with PostgreSQL row-level security and Realtime subscriptions
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
- `SUPABASE_SERVICE_ROLE_KEY`: Supabase service role secret (server-only admin and metrics reads)
- `NEXT_PUBLIC_SITE_URL`: Web portal origin URL (e.g. `http://localhost:3000` or `https://synctogether.app`) for OAuth redirects and invite bridges
- `NEXT_PUBLIC_TURNSTILE_SITE_KEY`: Cloudflare Turnstile site key for captcha verification
- `NEXT_PUBLIC_SUPPORT_EMAIL` / `NEXT_PUBLIC_COPYRIGHT_EMAIL`: contact addresses shown on the site and legal pages (required for a production build)
- `NEXT_PUBLIC_OPERATOR_NAME`, `NEXT_PUBLIC_OPERATOR_ADDRESS`, `NEXT_PUBLIC_GOVERNING_LAW`: who runs the site, named on the legal pages (required for a production build)
- `NEXT_PUBLIC_OPERATOR_URL`, `NEXT_PUBLIC_OPERATOR_TWITTER`, `NEXT_PUBLIC_DMCA_REGISTRATION`: footer credit link, link-preview handle, DMCA agent registration (optional)
- `NEXT_PUBLIC_APP_STORE_URL` / `NEXT_PUBLIC_MICROSOFT_STORE_URL`: store links; unset, the buttons lead to `/download` (optional)
- `NEXT_PUBLIC_SHOW_USAGE_STATS`: show the numeric usage-stats strip (optional)
- `PROD_SUPABASE_URL` / `PROD_SUPABASE_SERVICE_ROLE_KEY`: production project for the `/admin` and `/internal/*` dashboards (optional)
- `POSTHOG_PROJECT_URL`, `METRICS_INR_PER_USD`, `SUPABASE_DB_CAP_BYTES`, `CLOUDFLARE_ACCOUNT_ID` / `CLOUDFLARE_API_TOKEN`: metrics-dashboard tuning (optional); see `.env.example`
- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, `APPLE_APP_APPLE_ID`: live App Store prices on `/pricing` (optional; unset falls back to the built-in USD price)
- `GITHUB_TOKEN`: raises the GitHub API rate limit for `/changelog` (optional)

Web analytics are first-party (`/api/analytics/collect` writes to Supabase), so the site needs no PostHog key.

### 3. Run Development Server

```bash
npm run dev
```

Visit [http://localhost:3000](http://localhost:3000).

### 4. Run Tests

```bash
npm test
```

Runs the test suite in `tests/` (admin metrics, bug board, hero scrub, public stats, release-note sanitization, rewards, site config, store prices, tier resolution and web events).

## Key Routes & Architecture

### User-Facing Pages
- `/` - Homepage featuring interactive hero playback synchronizer and feature breakdown
- `/pricing` - Plan comparison; subscribing happens in the store apps (`/premium` redirects here)
- `/account` - Authenticated, read-only account overview and subscription status
- `/auth`, `/auth/callback`, `/auth/desktop-callback` - Supabase Google OAuth, Apple Sign-In, and Turnstile-protected email OTP authentication flows and desktop PKCE bridge
- `/download` - Store hub: iPhone & iPad (App Store), Mac App Store and Microsoft Store, with `?code=` invite carry-through
- `/changelog` - Release history fetched directly from GitHub releases
- `/join/<code>` - Invite landing: tries the `synctogether://` scheme, falls back to `/download?code=`
- `/r/<id>` (shared session recaps), `/u/<handle>` (Premium profile pages), `/leaderboard`, `/wrapped/<handle>` - Gamification pages
- `/pair/<code>` - Pair-invite landing, same scheme-then-download fallback as `/join`
- `/vs/discord`, `/vs/syncplay`, `/vs/teleparty` - Comparison pages
- `/guides`, `/guides/<slug>` - Long-form guides; `/facts` and `/llms.txt` - plain facts for search and AI crawlers
- `/faq`, `/privacy`, `/terms`, `/refund`, `/dmca` - Help center and compliance documentation
- `/admin` - Operator hub linking the internal dashboards
- `/internal/metrics` - Metrics dashboard (users, rooms, revenue, storage, sync health)
- `/internal/moderation` - Content-report and copyright-complaint queue
- `/internal/bugs` - Bug board for in-app bug reports

`/admin` and `/internal/*` only open from a local `next dev` on a loopback host; a production build returns 404 (`lib/admin-guard.ts`).

### API Route Handlers
- `GET /api/internal/metrics` - Aggregated system and room metrics endpoint.
- `POST /api/analytics/collect` - First-party, privacy-preserving pageview and conversion-event collector.
- `GET /api/public/stats` - Public usage figures for the homepage strip (suppressed below their floors).

## Deploying

Vercel builds the **last commit of a push** and cancels it when that commit changes nothing under `website/`. If a push ends with an app-only commit (a version bump, a docs tweak), website changes from earlier commits in the same push are never built, and redeploying from the dashboard is canceled the same way. End the push with a commit that touches `website/`, or push the website change on its own.

The hero and social images are baked from the demo build: recapture with `CAPTURE_WEBSITE=true` (see `docs/feature-toggles.md`), then re-run `node tool/compose-og-image.mjs` for `public/og-image.png`.
