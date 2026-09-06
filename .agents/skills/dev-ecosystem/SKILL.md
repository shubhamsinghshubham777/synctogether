---
name: dev-ecosystem
description: >-
  Manage the full local development environment for SyncTogether - spin up or down the local Supabase stack, Edge functions, and Next.js web application, or check ecosystem status. Use when the user asks to "start dev environment", "spin up local stack", "stop dev servers", "check dev status", or run `./scripts/dev.sh`.
---

# Local Development Ecosystem

SyncTogether uses `./scripts/dev.sh` to orchestrate all local dependencies (Supabase containers, Supabase Edge Functions, and the Next.js marketing/billing website).

## Usage Commands

### 1. Spin up everything
```bash
./scripts/dev.sh
```
This spins down previous lingering instances, starts the local Supabase stack (PostgreSQL, Realtime, Auth, Storage), serves Edge Functions (`livekit-token`, `media-share`, `cleanup-r2`), and launches the Next.js development server at `http://localhost:3000`.

### 2. Inspect Running Status
```bash
./scripts/dev.sh status
```
Shows process IDs, ports (e.g. Supabase API at `54321`, Web at `3000`), and container health.

### 3. Cleanly Spin Down
```bash
./scripts/dev.sh down
```
Stops background processes, tears down Supabase containers, and frees occupied network ports.

### 4. Clean-Slate Reset
```bash
./scripts/dev.sh clean
```
Completely wipes local database state, auth users, room sessions, and local storage buckets.

## Local Client Connection Notes
- Flutter debug builds automatically default to `http://127.0.0.1:54321` and local development keys without requiring command-line flags. Custom configurations are passed at compile time via `--dart-define` or `--dart-define-from-file=.env`.
- The lobby wordmark renders `1.x.x · local` in warning amber when connected to the local stack.
- To test Paddle billing locally with Next.js, run:
  ```bash
  hookdeck listen 3000 synctogether-webhooks --path /api/paddle/webhook
  ```
