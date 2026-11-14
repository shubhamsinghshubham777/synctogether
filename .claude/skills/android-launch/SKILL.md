---
name: android-launch
description: >-
  Retire the Android early-access (tester waitlist) surfaces and turn SyncTogether's Android build into a normal, advertised platform once it is live on Google Play production. Use when the user says "android is live", "android is in production", "clear up the android waitlist", "remove the android tester page", "launch android on the site", or "/android-launch". Also use at the earlier milestone "the closed test is open" to flip the card to its opt-in steps (Phase 1 only).
---

# Android launch: from "save a seat" to "get it on Google Play"

The early-access feature (commits `0bb8924`, `881d207`) exists only to collect the 12+ testers Google's closed test needs. It has three lives, and this skill covers the last two:

1. **Collecting** (now): `/android` waitlist, card on `/download` and `/join`, the pair-invite link in the app.
2. **Closed test open**: testers opt in through a Google Play link. Phase 1 below.
3. **Production live**: the waitlist is dead weight and "Android is next" is a false statement. Phase 2 onward.

Do the phases in order. Never push the website before the store link exists and works, and never delete the `android_testers` data before the testers have been told (Phase 3).

## Phase 1 - closed test is open (small, reversible)

1. In Vercel set `ANDROID_TEST_URL` to the Play opt-in link (https only; `androidTestUrl()` in `website/lib/android-testers-server.ts` ignores anything else). The card in `website/components/AndroidSeat.tsx` then switches from the sign-up form to the opt-in steps. No code change.
2. Paste the emails from `/internal/android` (the "Paste into Play Console" box lists only people not added yet; run `npm run dev` in `website/` and open `/admin`) into the closed track's tester list in Play Console, then press **Mark all as added** there. That stamps `added_at`, which is what flips a person's card to "Opt in on Google Play" (the card asks the server through `/api/android/check`, so it works on any device). Repeat for later sign-ups.
3. Optionally raise or lower `ANDROID_SEAT_TARGET`.

## Phase 2 - production is live: make Android a real platform

Get the real store URL first. Ask the user for it if it is not in the conversation: it is `https://play.google.com/store/apps/details?id=<applicationId>` (read the id from `android/app/build.gradle.kts`). Then:

### 2a. Add Android as a store, the way the other three are
- `website/lib/constants.ts`: add `playStoreUrl` to `SITE_CONFIG` beside `appStoreUrl` / `microsoftStoreUrl` (env `NEXT_PUBLIC_PLAY_STORE_URL`, falling back like the others - read how `microsoftStoreUrl` does it, and follow the "no operator-specific value in code" rule in the root CLAUDE.md). Add the env to `website/.env.example` and the Vercel project.
- `website/components/DownloadDoors.tsx`: add an Android door (door D) with a Google Play button. Update `useDesktopOS` (`website/components/hero/useDesktopOS.ts`): `"android"` stops meaning "a phone we cannot serve yet", so an Android visitor gets the Play door lit, like iOS gets the App Store. Update its doc comment.
- `website/components/hero/DownloadCTA.tsx`: the Android phone branch ("Copy the download link") becomes "Get a free seat - Google Play"; delete the "On Android? Save a test seat" line; fix `secondaryLabel` ("Also on ...") for the new platform set.
- Footer (`website/components/Footer.tsx`): replace "Android early access" with "Google Play" next to the other stores, and update `COMPACT_LINKS` if needed.

### 2b. Remove the waitlist surfaces
Delete, then follow the compiler and `grep -rn "android" website` until nothing stale is left:
- `website/app/android/` (the page), `website/app/api/android/check/` (the "Check my seat" lookup). Replace it with a redirect to `/download` in `website/next.config.*` (`redirects()`, permanent) so shared links and the app's old `/android?from=app` keep working. Remove it from `website/app/sitemap.ts`.
- `website/components/AndroidSeat.tsx`, `website/components/SendToComputer.tsx` (it exists only for Android visitors with no app), `website/lib/android-testers.ts`, `website/lib/android-testers-server.ts`, `website/app/api/android/`, `website/tests/android_testers.test.ts`.
- `website/app/download/page.tsx`: the `android` user-agent branch, `getSeatCounts`, the `AndroidSeat` card, `SendToComputer`, and the "Door D - Android / Save a seat" row (now a real door from 2a).
- `website/app/join/[code]/JoinLauncher.tsx`: the `phone` (Android) branch and the "Friend on Android? Save them a test seat" line. Android phones now take the same install path as iPhone: the Play door, with the invite code written down for after the install (no store hands an install-referrer back to the app - read the comment on `/download`).
- `website/app/internal/android/` (page, `actions.ts`, `AddedButtons.tsx`) and the "Android Testers" card in `website/app/admin/page.tsx` (restore the grid so the remaining four cards still balance).
- Anything added later around the test (for example a reward or incentive line in the card, the page or the FAQ): `grep -rni "tester\|early access\|test seat\|android" website/app website/components website/lib` until nothing about the test is left.
- `website/.env.example`: drop `ANDROID_SEAT_TARGET` and `ANDROID_TEST_URL`. Keep `TURNSTILE_SECRET_KEY` only if another route still uses it (`grep -rn TURNSTILE_SECRET_KEY website`).

### 2c. The Flutter app
- `lib/pairing/pair_widgets.dart` (`PairAndroidNudge`, `showsAndroidNudge`) and its use in `lib/pairing/pair_screen.dart`, plus `test/pairing/pair_android_nudge_test.dart`. Replace the nudge with nothing: pairing invites already carry a link that opens the right store through `/join` and `/download`. Remove now-unused imports.
- Check `Env.sitePage` still has callers; do not delete it if so.
- The Android build is consumption-only (no steering to another way to pay): read `docs/agent/backend-and-entitlements.md` before adding any copy to the Android listing or in-app.

### 2d. Copy that names the platforms
Every place that lists "iPhone, iPad, Mac and Windows" is now incomplete. Find them with:

```bash
grep -rn "iPhone, iPad, Mac\|iPhone, iPad and Mac\|iPhone · iPad\|Mac and Windows\|Windows and iPhone" website/app website/components website/lib
```

Known spots: `website/app/layout.tsx` (metadata), `website/app/llms.txt/route.ts`, `website/lib/constants.ts` (FAQ and `SITE_CONFIG`), `website/components/hero/` (the "IPHONE · IPAD · MAC · WINDOWS" eyebrow), `website/app/vs/teleparty/page.tsx` and `vs/syncplay/page.tsx` and `website/components/ComparisonPage.tsx` (the "Platforms" rows), the two guides under `website/app/guides/`, `website/app/download/page.tsx` (title, description and the "Every screen you own" blurb).

FAQ (`FAQ_ITEMS` in `website/lib/constants.ts`): delete "Is there an Android version?" and add Android to "What platforms does SyncTogether support?" (state the minimum Android version from `android/app/build.gradle.kts` `minSdk`).

### 2e. Docs, tests, canvas
- `docs/agent/auth-and-platform.md` (Google Play release section) and the root `CLAUDE.md` project overview: Android ships, remove any "unverified" or "not uploaded" wording. Run the `document-cleanup` skill afterwards.
- Add a changelog entry for the release (the `release` skill writes the store notes; keep the "TITLE: text" bullet format).
- Design canvas (https://claude.ai/artifact/AicTPz8b5eSnMFiJ9KiTgq), follow `.claude/skills/design/SKILL.md`: boards 89 `AndroidSeatWeb` and 90 `AndroidSeatPhone` are obsolete. Remove them from `project/canvas.json`, and update any board that shows a download surface, so the canvas keeps mirroring the code. Render and look at every changed board.
- Analytics: check `website/lib/web-events.ts` for any Android-seat event names and remove them in the same change (the allow-list test must still pass).

## Phase 2.5 - the reward (before anything is deleted)

Testers are promised 14 days of Patron for keeping it installed 14 days. At day 14, check Play Console's tester list for who stayed opted in, then press **Grant 14 days** in `/internal/android` (per person, or "to all added"). It calls `grant_android_tester_reward`, matches the tester to a SyncTogether account by email and writes a 14-day manual Premium row. Anyone with no account yet is skipped, not lost: tell them to sign in with the same Google account and press again later. Do not drop the table until every tester who earned it has it. Remove the reward copy in the same cleanup (the gift line in `AndroidSeat.tsx`, step 3 on `/android`, the opt-in card's step 3).

## Phase 3 - the people who signed up

They gave an address for one purpose ("only used to invite you on Google Play"). Honour that and then let it go:

1. Draft one short thank-you message for the user to send (Gmail or their mail tool): Android is live, link, thanks for testing. **Do not send it yourself**: it goes to real people, so get the user's explicit go-ahead on the text and the recipient list first. Send it as BCC, never a visible list.
2. After it has gone out (and after any promised reward has been granted), add a migration that drops the table, which takes `added_at`, `reward_granted_at` with it, and also drop the function: `drop function if exists public.grant_android_tester_reward(bigint);` plus `drop table if exists public.android_testers;` (timestamped in the `YYYYMMDDHHMMSS` style of `supabase/migrations/`), and delete `supabase/tests/android_testers_test.sql`. Run `supabase test db`, then run `supabase db push` only with the user's go-ahead. The addresses are personal data we no longer have a purpose for.
3. Run `python3 scripts/selfhost-verify.py` as the root `CLAUDE.md` asks after a change to the deployment surface (migrations).

## Order of operations

1. Phase 2 website changes, locally: `npm --prefix website run dev`, screenshot `/`, `/download`, `/join/ABCDEF`, `/faq`, the footer, `/admin` at desktop and phone width, with an Android user agent too (Playwright `user_agent` with `Android`). Look at each, per the standing UI verification rule.
2. `npm --prefix website test`, `npx tsc --noEmit -p website`, then `fvm dart format --output=none --set-exit-if-changed .`, `fvm flutter analyze`, `fvm flutter test`.
3. Commit (no co-author trailers) and push to `main`. The website deploys itself.
4. The app side (2c) only reaches users with the next store builds, so mention that and do not start a build (batch builds; see the release skill).
5. Phase 3 last, and only after the user confirms the Play listing is public.

## Do not

- Remove the waitlist before the production listing is public and the link has been opened by a real person.
- Keep any "Android is next" or "coming soon" text after launch.
- Leave `/android` returning a 404: redirect it.
- Add copy to the Android listing or app that links to a way to pay.
