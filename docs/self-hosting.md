# Self-Hosting SyncTogether

This guide provides complete instructions for self-hosting your own SyncTogether infrastructure - from running on a local home server to deploying a high-availability production instance on a VPS or cloud provider.

---

## 1. System Architecture

SyncTogether consists of four modular layers designed for low latency, secure room state synchronization, and SFU-routed AV facecams (LiveKit relays media; clients never connect peer-to-peer):

```mermaid
flowchart TD
    Client["SyncTogether Client<br/>(Desktop macOS/Windows, Mobile iOS/Android)"]
    
    subgraph Backend ["Backend Infrastructure"]
        DB[("PostgreSQL Database<br/>(Rooms, Members, Chat, RLS)")]
        Realtime["Supabase Realtime<br/>(Low-Latency Room Lockstep Sync)"]
        Auth["Supabase Auth<br/>(Guest Anonymous & Google OAuth)"]
        Functions["Supabase Edge Functions<br/>(livekit-token, media-share, cleanup-r2, apple-iap)"]
    end

    subgraph AV ["Audio / Video Mesh"]
        LiveKit["LiveKit SFU Server<br/>(Voice & 360p Video Facecams)"]
    end

    subgraph Optional ["Optional Services"]
        R2["Cloudflare R2 / S3<br/>(Shared Media Streaming)"]
        Web["Next.js Web Portal<br/>(App Downloads & Invite Redirects)"]
    end

    Client -->|"WebSocket (Realtime Channel)"| Realtime
    Client -->|"PostgreSQL RPCs & Auth"| DB
    Client -->|"HTTPS REST"| Functions
    Client -->|"WebRTC (UDP/TCP)"| LiveKit
    Client -.->|"HTTP Upload/Stream"| R2
    Client -.->|"Deep Link Invite Bridge"| Web
    Functions -->|"Mint Room Token"| LiveKit
    Functions -->|"Generate Presigned URLs"| R2
```

---

## 2. Choosing Your Deployment Path

| Method | Complexity | Infrastructure Requirements | Best For |
|---|---|---|---|
| **Path A: Managed Hybrid** *(Recommended)* | 🟢 Easy (~5 mins) | Free accounts on [Supabase](https://supabase.com) and [LiveKit Cloud](https://livekit.io) | Personal use, small friend groups, fast onboarding with zero server maintenance |
| **Path B: Fully Self-Hosted (Docker)** | 🟡 Intermediate | VPS or home server with Docker, Docker Compose, public IP or domain with TLS | Complete data ownership, private networks, offline LAN parties |

---

## 3. Prerequisites

Before starting, ensure you have the following installed on your machine:

1. **[FVM](https://fvm.app)** (Flutter Version Management) or **Flutter SDK 3.44.8** (pinned in `.fvmrc`):
   ```bash
   dart pub global activate fvm
   fvm install
   ```
2. **[Supabase CLI](https://supabase.com/docs/guides/cli)** (v2.x+):
   ```bash
   # macOS / Linux (Homebrew)
   brew install supabase/tap/supabase
   
   # Windows (Scoop)
   scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
   scoop install supabase
   ```
3. **[Docker & Docker Compose](https://docs.docker.com/get-docker/)** (Required for local development and self-hosted LiveKit/Supabase).
4. **[Node.js 20+]** (Required if building/running the Next.js web portal).

---

## 4. Step-by-Step Setup Guide

### Step 1: Database & Backend (Supabase)

#### Option 1: Managed Supabase Cloud (Easiest)
1. Create a free project at [database.new](https://database.new).
2. Note your **Project URL** (`https://<project-ref>.supabase.co`) and **Publishable (anon) Key** from **Project Settings → API**.
3. Link your local repository to the project:
   ```bash
   supabase login
   supabase link --project-ref <project-ref>
   ```
4. Push all database migrations, RLS policies, stored procedures, and cron sweep jobs:
   ```bash
   supabase db push
   ```

#### Option 2: Self-Hosted Supabase Docker Stack
If self-hosting the full Supabase container stack on your own server:
1. Follow the official [Supabase Self-Hosting Guide with Docker](https://supabase.com/docs/guides/self-hosting/docker).
2. Once the container stack is active (the self-hosted Kong gateway listens on `http://<host>:8000` by default - put TLS in front of it, e.g. `https://api.yourdomain.com`; `54321` is only the Supabase CLI's local dev port), apply the SyncTogether schema:
   ```bash
   supabase db push --db-url "postgresql://postgres:<your-db-password>@<db-host>:5432/postgres"
   ```
3. The migrations schedule jobs with `pg_cron` and call Edge Functions with `pg_net`; both extensions ship in the official Supabase images, but confirm they are enabled if you run a custom Postgres.

---

### Step 2: Audio & Video Facecam Server (LiveKit)

SyncTogether uses LiveKit for ultra-low-latency voice and video facecam rails.

#### Option 1: LiveKit Cloud (Easiest)
1. Sign up for a free project at [cloud.livekit.io](https://cloud.livekit.io).
2. Retrieve your **WebSocket URL** (`wss://<your-subdomain>.livekit.cloud`), **API Key**, and **API Secret** from **Settings → Keys**.

#### Option 2: Self-Hosted LiveKit Server (Docker)
1. A ready-to-use Docker Compose setup is included in the repo (`docker-compose.selfhost.yml` + `docker/livekit.yaml`). **Replace the shipped `devkey` pair** in `docker/livekit.yaml` with your own, and set `use_external_ip: true` on a public VPS (it ships `false`, which only works on a LAN):
   ```yaml
   port: 7880
   rtc:
     tcp_port: 7881
     port_range_start: 50000
     port_range_end: 50100
     use_external_ip: true
   keys:
     <your_api_key>: <your_api_secret>   # must match LIVEKIT_API_KEY / LIVEKIT_API_SECRET
   ```
2. Start the LiveKit server:
   ```bash
   docker compose -f docker-compose.selfhost.yml up -d
   ```
3. Ensure the following firewall ports are open on your server:
   - `7880/TCP`: HTTP / WebSocket signaling
   - `7881/TCP`: WebRTC TCP fallback
   - `50000-50100/UDP`: WebRTC media streams
4. Clients connect over `wss://`, so terminate TLS for port 7880 behind a reverse proxy (Caddy, nginx, Traefik) on a domain such as `livekit.yourdomain.com`.

---

### Step 3: Deploy Backend Edge Functions

SyncTogether uses Supabase Edge Functions to mint short-lived LiveKit JWT access tokens and manage media sharing.

1. Copy `supabase/functions/.env.example` to `supabase/functions/.env` and fill in at least:
   ```bash
   LIVEKIT_API_KEY=<your-livekit-api-key>
   LIVEKIT_API_SECRET=<your-livekit-api-secret>
   LIVEKIT_URL=<your-livekit-websocket-url>
   ```
2. Upload the secrets, then deploy:
   ```bash
   supabase secrets set --env-file supabase/functions/.env

   # LiveKit token minter (required for voice/video facecams)
   supabase functions deploy livekit-token
   ```

*(Optional)* Media file sharing via Cloudflare R2 (or any S3-compatible store) - set the four `CF_R2_*` secrets first:
```bash
supabase functions deploy media-share
supabase functions deploy cleanup-r2
```

> [!IMPORTANT]
> **R2 cleanup ships switched off.** The 5-minute cron calls `invoke_r2_cleanup()`, which does nothing until you tell it where `cleanup-r2` lives. Without this, deleted and expired shared videos are never removed from your bucket:
> ```sql
> update public.app_settings
>    set value = jsonb_build_object(
>      'enabled', true,
>      'endpoint_url', 'https://<your-supabase-host>/functions/v1/cleanup-r2',
>      'service_role_key', '<your-service-role-key>')
>  where key = 'r2_cleanup';
> ```

`apple-iap` is only needed if you sell Premium through the Mac App Store (secrets `APPLE_BUNDLE_ID`, `APPLE_APP_APPLE_ID`); a self-hosted instance can skip it.

---

### Step 4: Authentication Configuration

All auth settings live in `supabase/config.toml`, with secrets read from `supabase/.env` (copy `supabase/.env.example`). Push them with:
```bash
supabase config push
```
Auth config is **not** part of `supabase db push` - a migrated database with un-pushed auth config will fail in confusing ways. On a self-hosted Docker stack, set the equivalent `GOTRUE_*` variables in its `.env` instead.

1. **Anonymous Guest Sign-in**: Enabled (`enable_anonymous_sign_ins = true`). Guests receive a temporary username (`Guest-xxxx`) and are purged after 3 days.
   - **Cloudflare Turnstile is required as shipped**: `[auth.captcha]` is `enabled = true`, so the server rejects any guest sign-in without a token. Either create a Turnstile widget (add `localhost` to its hostname allow-list - the client serves the challenge from a loopback page), set `SUPABASE_AUTH_CAPTCHA_SECRET` in `supabase/.env` and build the client with `TURNSTILE_SITE_KEY`, **or** set `[auth.captcha] enabled = false` before pushing.
2. **Google OAuth (Optional)**:
   - In Google Cloud Console, create a **Web Application OAuth Client** with the Authorized Redirect URI `https://<your-supabase-host>/auth/v1/callback`.
   - Put the ID and secret in `supabase/.env` as `SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID` / `SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET`.
   - Keep `enable_manual_linking = true` - it is what lets a guest upgrade to Google in place; with it off every upgrade fails with `manual_linking_disabled`.
   - Set `site_url` and `additional_redirect_urls` to your own web portal's domain.
3. **Apple Sign-In (Optional)**: `[auth.external.apple]` lists the Services ID and bundle id (`app.synctogether.web,app.synctogether`) - change them to your own identifiers and set `SUPABASE_AUTH_EXTERNAL_APPLE_SECRET` (a 6-month ES256 JWT from your `.p8` key).
4. **Email OTP (Optional)**: Email sign-in sends a 6-digit code using the template in `supabase/templates/magic_link.html`. Configure an SMTP provider (`[auth.email.smtp]`) for production - Supabase's built-in sender is heavily rate-limited.

---

### Step 5: Configure and Build Client Applications

> [!NOTE]
> **Platform Support**: Desktop builds officially target **macOS** and **Windows**. Linux desktop is currently unsupported due to upstream WebView and self-update limitations.

SyncTogether uses Flutter compile-time defines (`--dart-define`) to bake configuration directly into the compiled client binary. This ensures no plaintext credentials or `.env` files are bundled into distributed release packages.

#### Option A: Local Offline Development (Zero-Config)
If testing locally with the local Supabase stack (`./scripts/dev.sh`), no flags are needed. In debug mode, the client automatically defaults to `http://127.0.0.1:54321` and local development keys:
```bash
# Fetch dependencies
fvm flutter pub get

# Run on macOS, Windows, Android, or iOS
fvm flutter run -d macos
```

#### Option B: Connecting to Your Self-Hosted Cloud or VPS Instance
Provide your self-hosted endpoints via `--dart-define`:

```bash
# Fetch Flutter packages
fvm flutter pub get

# Run in debug mode pointing to your self-hosted backend:
fvm flutter run -d macos \
  --dart-define=SUPABASE_URL="https://<your-supabase-url>" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="<your-supabase-publishable-key>" \
  --dart-define=LIVEKIT_URL="wss://<your-livekit-url>"

# Build release binaries:
fvm flutter build macos --release \
  --dart-define=SUPABASE_URL="https://<your-supabase-url>" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="<your-supabase-publishable-key>" \
  --dart-define=LIVEKIT_URL="wss://<your-livekit-url>"

fvm flutter build windows --release \
  --dart-define=SUPABASE_URL="https://<your-supabase-url>" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="<your-supabase-publishable-key>" \
  --dart-define=LIVEKIT_URL="wss://<your-livekit-url>"

fvm flutter build apk --release \
  --dart-define=SUPABASE_URL="https://<your-supabase-url>" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="<your-supabase-publishable-key>" \
  --dart-define=LIVEKIT_URL="wss://<your-livekit-url>"
```

> [!WARNING]
> **Hardcoded `synctogether.app` URLs.** The client builds shareable invite links (`/join/<code>`), recap and profile links, and the Google OAuth desktop bridge (`/auth/desktop-callback`) against `https://synctogether.app` in release builds (`lib/rewards/rewards_service.dart`, `lib/auth/auth_service.dart`). A self-hosted build should change those to your own web portal's origin, otherwise invites point at the official site and Google sign-in redirects through it. Guests, in-app room codes and `synctogether://join/<code>` links work without any web portal.

> [!TIP]
> **VS Code & Define Files**: Instead of passing command-line arguments manually, you can configure these defines under `args` in `.vscode/launch.json` or maintain a local JSON file passed with `--dart-define-from-file=my_config.json`.

---

### Step 6: (Optional) Deploy Web Portal (`website/`)

The web portal (`website/`) provides marketing pages, app download links, and web invite redirection (`synctogether.app/join/<code>` to `synctogether://join/<code>` deep link).

1. Navigate to the website directory:
   ```bash
   cd website
   cp .env.example .env.local
   npm install
   ```
2. Set `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SERVICE_ROLE_KEY` and `NEXT_PUBLIC_SITE_URL` in `website/.env.local`. Paddle, PostHog and the `PROD_*` admin-dashboard variables are optional for self-hosted instances; see `website/.env.example` for the full list.
3. Run or deploy:
   ```bash
   # Development
   npm run dev

   # Production build
   npm run build
   npm run start
   ```

---

## 5. Environment Variables Reference

### Client Configuration (`--dart-define`)

Pass these variables at compile-time via `--dart-define=KEY=VALUE` or `--dart-define-from-file`:

| Variable | Required? | Description |
|---|---|---|
| `SUPABASE_URL` | **Yes** (Release) | Public HTTPS endpoint of your Supabase API gateway (defaults to `http://127.0.0.1:54321` in debug mode) |
| `SUPABASE_PUBLISHABLE_KEY` | **Yes** (Release) | Supabase publishable API key (defaults to local development key in debug mode) |
| `LIVEKIT_URL` | *No* | LiveKit WebSocket endpoint (`wss://...`). Facecam rails are hidden if unset |
| `TURNSTILE_SITE_KEY` | *No* | Cloudflare Turnstile site key for captcha verification |
| `SENTRY_DSN` | *No* | Sentry project DSN for client-side crash telemetry |
| `POSTHOG_API_KEY` | *No* | PostHog public project key for product analytics |
| `POSTHOG_HOST` | *No* | PostHog ingest host (defaults to `https://us.i.posthog.com`) |
| `SUPABASE_URL_LOCAL` / `SUPABASE_PUBLISHABLE_KEY_LOCAL` | *No* | Debug builds only: preferred over `SUPABASE_URL` so a debug run never touches production. Ignored in release |

In debug builds with no local values set, the client falls back to `http://127.0.0.1:54321` and Turnstile's always-pass test key. **A release build with no `SUPABASE_URL` has no backend at all** - always pass it.

### Edge Functions Secrets (`supabase/functions/.env`)

| Variable | Required? | Description |
|---|---|---|
| `LIVEKIT_API_KEY` | **Yes** *(for AV)* | LiveKit API Key (matches key in `livekit.yaml` or LiveKit Cloud) |
| `LIVEKIT_API_SECRET` | **Yes** *(for AV)* | LiveKit API Secret (used by edge function to sign JWT tokens) |
| `LIVEKIT_URL` | **Yes** *(for AV)* | LiveKit WebSocket URL |
| `CF_R2_ENDPOINT` | *No* | Cloudflare R2 / S3 S3-compatible endpoint for media sharing |
| `CF_R2_ACCESS_KEY_ID` | *No* | Cloudflare R2 / S3 access key |
| `CF_R2_SECRET_ACCESS_KEY` | *No* | Cloudflare R2 / S3 secret key |
| `CF_R2_BUCKET_NAME` | *No* | Cloudflare R2 bucket name |
| `APPLE_BUNDLE_ID` / `APPLE_APP_APPLE_ID` | *No* | Only for the `apple-iap` function (Mac App Store purchases) |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are injected into Edge Functions by Supabase automatically; don't set them yourself.

### Auth Secrets (`supabase/.env`, used by `supabase config push`)

| Variable | Required? | Description |
|---|---|---|
| `SUPABASE_AUTH_CAPTCHA_SECRET` | **Yes**, unless captcha is disabled | Cloudflare Turnstile secret key |
| `SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID` / `_SECRET` | *No* | Google OAuth client |
| `SUPABASE_AUTH_EXTERNAL_APPLE_SECRET` | *No* | Apple Sign-In client secret JWT |

### Tuning Limits

Room sizes, session lengths, AV level, media-sharing quotas and reward thresholds are database rows (`tier_limits`, `app_settings`, `reward_config`), not code - change them with an `update`. See [feature-toggles.md](feature-toggles.md) for every key.

---

## 6. Maintenance & Troubleshooting

### Database Resets & Migration Updates
When pulling updates from the upstream repository:
```bash
# Check status and apply any new migrations
supabase db push
```

### Checking Edge Functions Logs
The Supabase CLI has no log-tailing command for deployed functions. On Supabase Cloud use **Dashboard → Edge Functions → <function> → Logs**; on a self-hosted stack read the functions container (`docker logs -f supabase-edge-functions`). Locally, `supabase functions serve` prints logs to the terminal.

### Secrets Backup and Recovery (`scripts/secrets.sh`)
Packs every local secret file (`.env` files, certificates, keys) into one encrypted bundle and restores them to their original paths:
```bash
# Encrypt and package all repository secrets into a safe backup bundle
./scripts/secrets.sh pack

# List files included in a secrets bundle
./scripts/secrets.sh list

# Restore secret files into their exact paths with appropriate permissions
./scripts/secrets.sh unpack synctogether-secrets-bundle.txt
```

### Testing Connectivity Locally
To test the complete stack locally with automated hot reloading:
```bash
./scripts/dev.sh
```

---

## 7. License & Commercial Notice
 
SyncTogether is licensed under the **PolyForm Noncommercial License 1.0.0 (PolyForm-Noncommercial-1.0.0)**.
 
- **Permitted**: You are 100% free to self-host, run, inspect, and modify SyncTogether for yourself, your family, your community, or non-commercial/educational purposes.
- **Prohibited**: You may not sell SyncTogether, offer it as a commercial hosted service (SaaS), or use it for commercial organizational purposes without an explicit commercial license.
- See the [LICENSE](../LICENSE) file for complete legal terms.
