<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

## SyncTogether Web Portal Architecture & Guidelines

### Overview
This Next.js 16 application serves as the marketing site, downloads portal, legal documentation, authentication bridge, and read-only account portal for SyncTogether. Premium is sold only inside the store apps (Apple StoreKit and the Microsoft Store): there is no web checkout, billing code or payment webhook.

### Supabase SSR Patterns
- **Client Components**: Use `createClient()` from `lib/supabase/client.ts` (`createBrowserClient`).
- **Server Components & Route Handlers**: Use `createClient()` from `lib/supabase/server.ts` (`createServerClient` with `cookies()`).
- **Admin / Webhooks**: Use `createAdminClient()` from `lib/supabase/admin.ts` (`SUPABASE_SERVICE_ROLE_KEY`) only in secure server route handlers that require elevated database privileges (e.g. metrics and moderation).

### Design System & Styling
- Styled with Tailwind CSS v4 in the Projection Booth language shared with the Flutter app (dark only, warm matte neutrals, Beam amber for the one live action, no gradients or blur). `app/globals.css` `@theme` remaps the legacy `purple`/`indigo`/`gray`/`white` scales onto it - prefer `beam-*`, `booth`, `seat`, `rail`, `screen`, `signal`, `cue`, `brass` in new code.
- Shared components in `components/`: `PTButton`, `GlassPanel`, `PlanCard`, `PricingTable`, `Header`, `Footer`, and `Ticket` (the notched invite/room-code object). Link-preview images use `lib/og-ticket.tsx`. The homepage hero lives in `components/hero/` and drives the room mockups in `components/room-sim/`.

### Testing & Verification
- Unit test suite in `tests/` covers metrics, moderation heuristics, rewards and tier resolution.
- Run tests with `npm test`.
