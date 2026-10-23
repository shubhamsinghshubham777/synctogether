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

Runs the test suite in `tests/` (metrics, moderation heuristics, rewards and tier resolution).

## Key Routes & Architecture

### User-Facing Pages
- `/` - Homepage featuring interactive hero playback synchronizer and feature breakdown
- `/pricing` - Plan comparison; subscribing happens in the store apps (`/premium` redirects here)
- `/account` - Authenticated, read-only account overview and subscription status
- `/auth`, `/auth/callback`, `/auth/desktop-callback` - Supabase Google OAuth, Apple Sign-In, and Turnstile-protected email OTP authentication flows and desktop PKCE bridge
- `/download` - Store hub: Mac App Store and Microsoft Store badges, with `?code=` invite carry-through
- `/changelog` - Release history fetched directly from GitHub releases
- `/faq`, `/privacy`, `/terms`, `/refund` - Help center and compliance documentation
- `/admin` - Protected administration console for inspecting subscriber entitlements
- `/internal/metrics` - Real-time system performance and sync health telemetry dashboard

### API Route Handlers
- `GET /api/internal/metrics` - Aggregated system and room metrics endpoint.
- `POST /api/analytics/collect` - Proxied privacy-preserving web analytics event collector.
