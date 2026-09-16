# Gamification & word-of-mouth plan

Status: **implemented**. This document is kept as the design argument - why each
mechanic is shaped the way it is, and what would break if it were changed. The
operational notes live in `CLAUDE.md` under *Gamification*; where the two
disagree, `CLAUDE.md` describes the code and this describes the reasoning.

Names that moved between plan and build: `user_streaks` became **`user_rewards`**
(it holds every lifetime aggregate, not only the streak), and
`profiles.leaderboard_opt_in` became **`profiles.public_profile`** (one consent
governs the board, the profile page and shared recaps, so the flag is named for
what it does). Three tables the plan did not anticipate carry the anti-abuse
arithmetic: `watch_day_rooms`, `co_watch_daily` and `watch_heartbeats`.

Goal, in the owner's words: entice users to share SyncTogether on social media for free
word of mouth, keep them entertained, and give them leaderboards to climb by being
consistent users.

This document is the design *and* the argument for it. Where a mechanic is a bad idea
for this particular product, that is said plainly rather than left to be discovered
during implementation.

---

## 0. The thing that has to be true first

**SyncTogether currently has nothing shareable.** The invite link is
`synctogether://join/<code>` - a custom URI scheme. Pasted into X, Instagram, WhatsApp or
Discord it does not linkify, shows no preview card, and is a dead end for the ~100% of
recipients who do not already have the app installed. The website has no room page, no
user page and no Open Graph images beyond the marketing pages.

So the honest sequencing is: **a leaderboard nobody can link to is not a growth feature,
it is a retention feature.** Both are worth building, but only one of them answers the
brief, and the shareable-surface work is a prerequisite for it rather than a phase of it.

The same logic that already governs `website/lib/public-metrics.ts` applies with force
here: that file refuses to publish a stat below a floor, because "publishing a small
number is worse than publishing none". A global leaderboard with 14 names on it is
exactly that failure, screenshot-ready. Leaderboards must therefore ship *behind* a
participation floor and *after* the sharing surface that fills them.

**Order built, highest return first. All five shipped:**

| Phase | What | Drives | Built as |
|---|---|---|---|
| 0 | Web join landing + OG cards | Every share becomes clickable | `website/app/join/[code]`, `Room.inviteLink` |
| 1 | Session recap + superlatives | The artifact people actually post | `showRecapDialog`, `create_recap`, `website/app/r/[id]` |
| 2 | Server watch ledger, streaks, achievements | Consistency, retention | `record_watch_progress`, `user_rewards`, `achievements` |
| 3 | Leaderboards (3 boards) + public profiles | The climb, and its shareable proof | `leaderboard()`, `LeaderboardScreen`, `website/app/u/[handle]` |
| 4 | Wrapped, seasons, cosmetics, combos | Seasonal spike, delight | `website/app/wrapped`, `close_seasons`, `AvatarFrame`, `ComboTracker` |

Coverage: 82 new Dart tests (585 -> 667) and 145 new pgTAP assertions
(277 -> 422) - 60 in `15_rewards_test.sql`, 43 in `16_leaderboard_test.sql`,
15 in `17_seasons_test.sql` and 27 added to `07_grants_test.sql` - plus the
website suite.

---

## 1. Design principles (derived from this codebase, not from generic growth advice)

These are constraints the implementation must respect. Each one already has a precedent
in the repo.

1. **Server truth, never analytics.** PostHog is client-reported, opt-out-able and
   fire-and-forget (`lib/analytics.dart` swallows every failure by design). A leaderboard
   computed from it would be wrong and gameable. Scores come from a `security definer`
   RPC over real tables, exactly as `effective_tier` is "the single arbiter" for crowns.

2. **Thresholds are config rows, not constants.** `tier_limits` made tuning a tier an
   `update` rather than a deploy. Streak minimums, point weights and achievement
   thresholds get the same treatment (`reward_config`, `achievements`). You will tune
   these weekly for the first month; do not make that a release.

3. **Client checks are affordance only.** Every cap is re-enforced server-side, so a
   stale client costs a worse message, never a bypass. Same doctrine as the tier caps.

4. **Guests are structurally excluded, and that is the conversion lever.** Anonymous
   users are purged after 3 days (`..._purge_stale_guests.sql`) and `effective_tier`
   short-circuits to `guest` before it looks at anything else. A guest cannot hold a
   streak because their account will not exist next week. Surface this as the offer it
   is: *"Sign in to start a streak"* - one Google tap, keeps the user id and session, and
   it is the same in-place `linkGoogleIdentity` upgrade the profile screen already runs.
   This mirrors the existing doctrine that a guest's upsell is sign-in, never a waitlist.

5. **A badge render is not an analytics event.** "A crown is not an analytics event. It
   renders; nobody caused it." The same rule holds for streak flames, frames and rank
   chips. Only the human's tap gets tracked. See section 11 for the one nuanced case.

6. **Do not touch presence.** Realtime allows 5 presence calls per 30 seconds and drops
   the *whole channel* past it - sync, chat and the readiness gate with it. The
   `_presenceThrottle` survives only because `presencePayloadsMatch` dedupes no-op flips.
   **Putting a live-updating score or streak counter in the presence payload would defeat
   that dedupe on every tick and take the room down.** Cosmetic state for other members
   comes from an RPC, cached, refetched only on unresolved ids - the exact shape of
   `room_member_tiers` and `_premiumMembers`. Extend that RPC rather than adding a second
   round trip.

7. **Rewards must not cannibalize Premium.** Do not hand out extended reactions, larger
   rooms, longer sessions or video facecams as streak prizes - those are the things
   people pay for, and giving them away for logging in makes the subscription look
   optional. Rewards are cosmetics and grace, which cost nothing and devalue nothing.

8. **Privacy is a stated product position.** The FAQ says "100% free with no ads or
   tracking", "never recorded", and the analytics doctrine forbids ever sending chat
   content, file names, file paths or YouTube ids. A public leaderboard that shows
   display names is a *change to that posture*. It must be explicit opt-in, stored
   server-side (so the server can refuse to publish a non-consenting row), and the
   privacy policy and FAQ must be updated in the same release. This is not optional
   polish; it is the difference between a feature and a complaint.

---

## 2. Phase 0 - make a share clickable (website only, no schema)

Nothing in this phase is gamification. It is the pipe everything else flows through.

### 0.1 `https://synctogether.app/join/<CODE>`

A Next.js route that:
- Immediately attempts `synctogether://join/<CODE>` (the scheme the app already handles
  via `app_links`, and which `main.dart` already replays from `getInitialLink()` on cold
  start).
- After ~1200 ms with no blur/visibility change, falls back to the download page with the
  code preserved in the URL and a cookie.
- Renders an OG card: room name if the code resolves to a live room, a generic
  "You're invited to watch together" card if not. Never leak room contents - name and
  member count at most, and only for live rooms.

Caveat to be honest about: **desktop has no install-referrer.** A cookie set in the
browser cannot survive an `.exe`/`.dmg` install into the app. So do not build install
attribution. Attribute at the *join* instead: the app's first-run screen asks "Have an
invite code?", and credit is computed server-side as "this brand-new account's first room
join was a room X created". That needs no attribution plumbing at all and is unfakeable.

The app already tracks `room_joined {via: code|deeplink}`. Add `via: 'web_landing'` by
having the landing page hand the code over in the deep link query, so the funnel can
actually be measured.

### 0.2 Copy-invite becomes a real link

`RoomScreen._copyInvite` (currently `room_screen.dart:3130`) should copy the **https**
link, not the scheme link. The scheme link stays as a secondary "Copy app link" for
people already in the ecosystem.

### 0.3 OG image infrastructure

Stand up `next/og` `ImageResponse` once, with the violet-glass look, Space Grotesk and
Outfit loaded from the same font files the app bundles. Every later phase - recap cards,
public profiles, leaderboard rows, Wrapped - reuses this renderer. Doing it once here is
what keeps phases 1-4 cheap.

---

## 3. Phase 1 - the session recap (the artifact people post)

This is the highest-leverage feature in the whole plan and it needs **no schema at all**
for v1, because `RoomScreen` already counts everything it needs:

```dart
DateTime? _sessionStart;   int _peakMembers = 0;
int _messagesSent = 0;     int _reactionsSent = 0;
bool _facecamUsed = false; final _modesUsed = <String>{};
```

...and `_trackWatchSessionEnded()` already fires from exactly two places, deduped by
`_sessionReported`: `_leaveRoom()` (room_screen.dart:3056) and `_evictSelf()`
(room_screen.dart:2872). Those are the insertion points.

### 3.1 What the recap shows

A glass card, shown after the existing "That's a wrap!" eviction popup and on deliberate
leave:

- **Time synced** - session wall-clock, and the "together" figure (see section 6).
- **Who was there** - `PTAvatarStack`, already built.
- **Reactions flown** - the number, plus the top emoji of the session.
- **Messages** - count only. Never content.
- **Superlatives** - three silly per-person awards, computed from what the room already
  counted. These are the shareable part. Examples:
  - *Reaction Machine* - most reactions sent
  - *Chatterbox* - most messages
  - *Rock Solid* - never held the readiness gate shut
  - *The Pauser* - most play/pause events (affectionate, not a callout)
  - *Night Owl* - session crossed 02:00 local
  - *Ride or Die* - present from first frame to last

  Superlatives are per-session and disposable. They are the thing that makes someone
  screenshot a recap, and they cost one counter each.

- **One button: "Share this".**

### 3.2 How sharing actually works on desktop

Do not add `share_plus`. Desktop share sheets are unreliable, `Clipboard.setData` is
text-only so a PNG cannot go to the clipboard, and pubspec uses exact pins with a
deliberately small dependency set.

**The web page is the share surface; the app's job is to produce the link.** On "Share
this" the app posts a small recap payload to a `create_recap` RPC and receives
`https://synctogether.app/r/<unguessable-id>`. The link is copied and `url_launcher`
(already a dependency) opens it. The browser's own share affordances do the rest, and the
OG image renderer from Phase 0 makes the card.

This also solves the image-generation problem for free: the card is rendered server-side
by the same code that renders every other OG image, so it looks identical everywhere and
never depends on a `RepaintBoundary` capture at whatever DPI the user's monitor happens
to be.

### 3.3 Privacy rules for recaps (non-negotiable)

- Never include the media name, file path, YouTube URL or video id. **Media is reported
  as `kind` only** - this is the existing analytics privacy boundary and it applies
  verbatim.
- Never include chat content.
- Other people's display names and avatars appear **only** for members who have opted
  into public sharing (section 9). Everyone else appears as their gradient avatar with no
  name. A recap is a public URL; it must not out a co-watcher.
- Recaps expire. 90 days, swept by the existing per-minute cron infrastructure.

---

## 4. Phase 2 - the ledger, streaks and achievements

This is where server truth gets built. Everything downstream reads from it.

### 4.1 Schema

```sql
-- Tuning surface. Config rows, never constants - the tier_limits doctrine.
create table public.reward_config (
  key   text primary key,
  value jsonb not null
);
-- seeds: streak_min_minutes=20, daily_credit_cap_min=480, daily_points_cap_min=240,
--        pair_daily_cap_min=120, heartbeat_clamp_sec=90, freezes_per_week=1,
--        freezes_per_week_premium=2, leaderboard_min_participants=200

-- Per-user, per-local-day roll-up. Append-and-increment; never one row per heartbeat.
create table public.watch_ledger (
  user_id          uuid not null references public.profiles (id) on delete cascade,
  day              date not null,               -- the user's LOCAL day
  credited_seconds int  not null default 0,
  rooms_touched    int  not null default 0,
  co_watchers      int  not null default 0,
  points           int  not null default 0,
  primary key (user_id, day)
);
create index watch_ledger_day_points_idx on public.watch_ledger (day, points desc);

-- Shipped as `user_rewards`: one row per user carrying the streak plus every
-- lifetime aggregate an achievement can be evaluated against.
create table public.user_rewards (
  user_id            uuid primary key references public.profiles (id) on delete cascade,
  current_streak     int  not null default 0,
  longest_streak     int  not null default 0,
  last_credited_day  date,
  freezes_available  int  not null default 1,
  freezes_refreshed  date,
  total_seconds      bigint not null default 0,
  total_sessions     int  not null default 0
  -- ... plus total_hosted, longest_session_seconds, max_room_members,
  -- distinct_co_watchers, days_active, double_feature_days, night_owl_sessions,
  -- clean_gate_sessions, reactions_sent, messages_sent, lifetime_points
);

-- Not in the original plan, and all three are load-bearing:
--   watch_heartbeats  - the anchor `now() - last_at` is measured from, which is
--                       what makes the RPC unspammable
--   watch_day_rooms   - the per-room slice of a day, carrying longest-sitting
--                       and biggest-room for achievements
--   co_watch_daily    - per-pair daily accrual, so two accounts farming each
--                       other hit diminishing returns

-- Catalogue lives in the database so a new badge is an insert, not a release.
create table public.achievements (
  id          text primary key,
  title       text not null,
  description text not null,
  icon        text not null,          -- material_symbols name
  grade       text not null check (grade in ('bronze','silver','gold','secret')),
  metric      text not null,          -- 'total_seconds' | 'streak' | 'co_watchers' | ...
  threshold   bigint not null,
  reward      jsonb not null default '{}'::jsonb,   -- e.g. {"frame":"aurora"}
  sort        int  not null default 0
);

create table public.user_achievements (
  user_id        uuid not null references public.profiles (id) on delete cascade,
  achievement_id text not null references public.achievements (id) on delete cascade,
  unlocked_at    timestamptz not null default now(),
  seen           boolean not null default false,
  primary key (user_id, achievement_id)
);

-- The co-watch graph. Powers the friends leaderboard AND the per-pair farming cap.
create table public.co_watchers (
  user_id   uuid not null references public.profiles (id) on delete cascade,
  other_id  uuid not null references public.profiles (id) on delete cascade,
  sessions  int  not null default 0,
  seconds   bigint not null default 0,
  first_at  timestamptz not null default now(),
  last_at   timestamptz not null default now(),
  primary key (user_id, other_id)
);

alter table public.profiles
  add column leaderboard_opt_in boolean not null default false,
  add column handle             text unique,        -- for /u/<handle>
  add column equipped_frame     text,               -- cosmetic, validated against unlocks
  add column referred_by        uuid references public.profiles (id);
```

All four new tables get RLS. Reads of *own* rows go direct; everything cross-user goes
through `security definer` RPCs. **Note the trap the repo already documented:** changing a
`returns table` signature means `drop function` first, and a drop takes the grants with
it - so every migration touching an RPC must re-`grant execute ... to authenticated`.
`supabase/tests/07_grants_test.sql` exists precisely to catch that; extend it.

### 4.2 The heartbeat RPC

```
record_watch_progress(p_room_id uuid, p_local_day date, p_local_hour int)
  returns  jsonb  -- { credited, reason, granted_seconds, seconds_today,
                  --   points_today, streak, freezes, streak_frozen,
                  --   day_qualified, unlocked: [...] }
```

`p_local_hour` was added for the Night Owl award, and is range-checked the same
way `p_local_day` is - the client is trusted with which calendar day it is, never
with how much time passed.

`security definer`. Called from the client on the **same 60 s cadence as
`update_media_position`**, so no new timer is introduced - piggyback on the existing one
in `RoomScreen`. It must:

1. Reject guests outright: `effective_tier(auth.uid()) = 'guest'` returns a payload with
   an `upgrade: true` flag and credits nothing. The client renders the sign-in offer.
2. Require membership and `room_state(room) = 'live'`.
3. Require `member_count >= 2`. Watching alone is fine, it just is not "together" and
   earns nothing. Say so in the UI, once, kindly.
4. Require the room's media to be set (`media_kind <> 'none'`).
5. Require evidence of actual playback: `rooms.media_position_ms` written within the last
   3 minutes. This is free liveness - `update_media_position` is authority-only on a 60 s
   timer plus play/pause/seek/mode-switch/leave, so a paused-and-abandoned room stops
   producing it. **A room left open overnight earns nothing.**
6. Compute elapsed since the caller's last heartbeat and **clamp it to 90 s**. This is
   the single most important line in the function: it makes call frequency irrelevant, so
   a client that spams the RPC gains nothing.
7. Validate `p_local_day` is within one day of UTC today, so nobody claims 2030-01-01.
8. Increment `watch_ledger`, `co_watchers` (both directions), `user_streaks.total_*`.
9. Roll the streak *lazily* - compare `last_credited_day` to `p_local_day`; no cron
   needed, which also sidesteps the "which timezone does the cron run in" problem
   entirely.
10. Evaluate `achievements` against the updated aggregates and insert any newly crossed
    thresholds, returning their ids.

One RPC, one round trip, returns everything the client needs to render - the same shape
as `room_member_tiers` "answers the whole room in one round trip".

### 4.3 Streaks

A day counts when `credited_seconds >= reward_config.streak_min_minutes x 60` (seed: 20
minutes). Twenty minutes is deliberately low - a streak you can lose by having a busy
Tuesday is a streak you quit.

**Streak freeze.** One free rest day per rolling 7 days (two for Premium). Consumed
automatically, silently, and *reported afterwards*: "Your streak survived Tuesday." This
is the single mechanic that separates a streak people keep from one they abandon at day 9,
and giving Premium a second one is the model reward - it is grace, not capability, so it
cannot cannibalize the subscription.

`freezes_refreshed` is the anchor date; refill lazily at heartbeat time.

### 4.4 Achievement catalogue (starter set)

Seeded as rows, tuned as `update`s. Design rule: every achievement must be reachable by
doing what the user came here to do. Nothing should make someone use the app *weirdly*.

| id | Title | Condition | Grade |
|---|---|---|---|
| `first_sync` | First Sync | Finish one session with someone | bronze |
| `week_one` | Regular | 3-day streak | bronze |
| `seven_up` | Seven Up | 7-day streak | silver |
| `unbroken` | Unbroken | 30-day streak | gold |
| `full_house` | Full House | Session with 8+ people present | silver |
| `marathon` | Marathon | Single session over 4 hours | silver |
| `double_feature` | Double Feature | Two sessions in one day | bronze |
| `night_owl` | Night Owl | A session crossing 02:00 local | bronze |
| `circle` | Wide Circle | Watched with 10 distinct people | silver |
| `century` | Century | 100 hours watched together | gold |
| `hype_man` | Hype Man | 500 reactions sent | bronze |
| `host_with_most` | Host With The Most | Hosted 25 sessions | silver |
| `perfect_sync` | Perfect Sync | 10 sessions never holding the gate shut | secret |

Secret achievements are not listed until unlocked. They are cheap and they are the ones
people screenshot.

### 4.5 Rewards: cosmetics only

Unlocks grant **avatar frames** and **profile badges**. Nothing functional.

`PTAvatar` gains a `frame` parameter alongside the existing `premium` bool, following the
documented doctrine verbatim: *"`PTAvatar.premium` is an opt-in bool, and must stay one...
letting the widget reach for `EntitlementService` itself would make it untestable and
rebuild it on every unrelated notify. Whoever builds the avatar owns the lookup."* The
frame is passed in, never looked up inside the widget. Doing it on the avatar covers the
lobby pill, chat bubbles, the readiness roster, the overflow member list and facecam tiles
in one change - the same argument that justified `premium`.

Frames are drawn from `PTColors`, not new hex values. A gradient ring, a gold ring for
gold-grade unlocks (distinct from the Premium crown by *shape*, per the existing "a crown
glyph and a Host pill are told apart by shape, not hue" reasoning).

`profiles.equipped_frame` is validated server-side against `user_achievements` on write.
Client-side selection is affordance only.

---

## 5. Phase 3 - leaderboards

### 5.1 Three boards, not one

A single global board is demoralizing by construction: the top is unreachable and the
middle is invisible. Ship three, default to the first.

1. **Circle** (default) - ranked among people you have actually shared a room with, from
   `co_watchers`. This is the board that drives sharing, because it is winnable, the
   rivals are real, and beating your friend is a thing you tell your friend.
2. **This Week** - global, resets Monday 00:00 UTC, top 100 plus "your rank". A weekly
   reset means a user who installs on Wednesday can still place, which a lifetime board
   never allows.
3. **Hall of Fame** - all-time top 50. Small, aspirational, rarely changes, exists to be
   aimed at.

### 5.2 The score

Legibility matters more than cleverness - people must be able to see why they are where
they are, or the board reads as rigged. Published formula, five terms:

```
base   = min(credited_minutes_today, 240)
       + 15 x min(distinct_co_watchers_today, 5)
       + 25 if any session today had 4 or more people present

points = round(base x streak_multiplier)

streak_multiplier:  1.00 below 3 days
                    1.10 at 3+
                    1.25 at 7+
                    1.50 at 30+
```

Consistency is rewarded through the multiplier rather than through raw time, which is the
brief: *climb by being consistent*. A person who watches 40 minutes every day for a month
outranks a person who watches 12 hours on one Saturday. That is the intended message and
it should be stated on the board itself.

**Premium buys no points.** Pay-to-win on a social board destroys the board's credibility
and invites exactly the wrong kind of post. Premium gets the second streak freeze, gold
frames, and higher-fidelity Wrapped exports - visible, not advantageous.

### 5.3 Query shape

```
leaderboard(p_scope text, p_period text, p_limit int default 100)
  returns table (rank int, user_id uuid, display_name text, avatar_url text,
                 handle text, frame text, is_premium boolean,
                 points bigint, streak int, is_me boolean)
```

`security definer`, respects `public_profile` (a non-consenting user is absent from
every row *except their own*, where they see their private rank). Index
`watch_ledger (day, points desc)` carries this to five figures of users; past that,
promote to a materialized view refreshed by pg_cron every 5 minutes. Do not build the
matview first - it is premature, and refresh scheduling is a new failure mode.

### 5.4 The participation floor

Reuse the `public-metrics.ts` doctrine literally. `reward_config.leaderboard_min_participants`
(seed 200) gates the *global* boards; below it, the app shows only the Circle board and
your own stats. A leaderboard that looks empty is worse than one that is not there yet.

### 5.5 Public profile pages

`https://synctogether.app/u/<handle>` - opt-in, server-rendered, revalidated hourly:
streak, rank, badge shelf, total hours. OG image via the Phase 0 renderer.

This is what converts a leaderboard into distribution. A rank chip in the app is a private
pleasure; a rank chip with a URL under it is a post. Handles are claimed in the profile
screen, unique, 3-20 chars, and rejected against a reserved list (`admin`, `premium`,
`join`, `auth`, `r`, `api`, ...) so they cannot shadow a route.

---

## 6. Phase 4 - Wrapped, seasons, cosmetics

- **Yearly Wrapped** (ship in the first week of December). The single most reliably shared
  artifact in consumer software. It is a `/wrapped/<id>` page built from `watch_ledger`,
  `co_watchers` and `user_achievements` - by this phase all the data already exists, so it
  is a rendering job, not a data job. "You watched 312 hours with 14 people. Your most
  loyal co-watcher was @ana - 61 nights."
- **Monthly seasons** - the weekly board's slower sibling, with a season badge minted to
  the top 3 and frozen into their badge shelf forever. A permanent trophy for a temporary
  achievement is what makes people care about a temporary achievement.
- **Reaction combos** - pure entertainment, zero persistence, very cheap: when 3+ members
  send the same emoji within 3 seconds, the overlay renders one large combo burst instead
  of three small ones. It rides the existing ephemeral reaction channel and touches
  nothing else. Constraint: it must stay inside the existing `TrailingThrottle` budget and
  must **not** go through `_shouldApply` - reactions deliberately do not advance
  `_lastAppliedTimestamp`, and breaking that would silently eat the next real play/pause.

---

## 7. Anti-abuse

This system is trivially farmable if built naively - two accounts in a room overnight.
Every one of the following is load-bearing; dropping any one re-opens the hole.

| Vector | Mitigation |
|---|---|
| Spamming the heartbeat RPC | Elapsed is computed **server-side** and clamped to 90 s. Call frequency is irrelevant. |
| Idle room left open | Requires `media_position_ms` written in the last 3 min - authority-only, stops when playback stops. |
| Solo farming | Requires `member_count >= 2`. |
| Two accounts farming each other | Per-pair daily cap (`pair_daily_cap_min`, seed 120). The 11th hour with the same person is worth zero. |
| Guest army | Guests earn nothing at all, and are purged in 3 days regardless. |
| Timezone hopping for extra days | `p_local_day` validated within +/-1 day of UTC today. |
| Absurd daily totals | `daily_credit_cap_min` 480, `daily_points_cap_min` 240. |
| Co-watcher count inflation | `min(distinct_co_watchers_today, 5)` in the formula. |

Plus one operational control: a `reward_config` kill switch (`ledger_enabled: false`) that
makes `record_watch_progress` a no-op returning an empty payload, so the whole system can
be switched off from a SQL console without a release. Given this is the first
adversarially-interesting surface in the product, that switch will earn its keep.

---

## 8. Client architecture

```
lib/rewards/
  rewards_service.dart      ChangeNotifier singleton, EntitlementService shape:
                            loads my_rewards(), listens to realtime on user_achievements,
                            debounced reload, falls back to a zeroed state (understate,
                            never overstate - same doctrine as the tier fallback).
  rewards_models.dart       Streak, LedgerDay, Achievement, LeaderboardRow, plain data.
  rewards_logic.dart        PURE free functions over plain values:
                            streakAfter(), pointsFor(), multiplierFor(), nextThreshold(),
                            superlativesFor(). Unit-tested with no network and no Supabase.
  leaderboard_screen.dart   /lobby/leaderboard
  achievements_sheet.dart   badge shelf
  widgets/
    streak_chip.dart        lobby header, next to _premiumChip()
    recap_card.dart         the session recap
    unlock_toast.dart       the achievement pop
```

The `rewards_logic.dart` split is the same seam `lib/sync/sync_logic.dart` established and
it exists for the same reason - the scoring rules are exactly the kind of thing that must
be testable without a room, a network or a clock. Keep it pure delegation.

### Insertion points (all already exist)

| Surface | Where |
|---|---|
| Streak chip | `lobby_screen.dart` header row, beside `_premiumChip()` / `_mediaQuotaChip()` |
| Leaderboard route | `/lobby/leaderboard`, nested under `/lobby` so `context.go('/lobby')` still pops |
| Heartbeat | alongside the existing 60 s `updateMediaPosition` timer in `RoomScreen` |
| Recap | `_leaveRoom()` and `_evictSelf()`, beside `_trackWatchSessionEnded()` (already deduped by `_sessionReported`) |
| Badges in-room | `PTAvatar`, via the `room_member_tiers` cache pattern (`_premiumMembers`) |
| Stats + opt-in + handle | `profile_screen.dart`, new section beside `_privacySection()` |

### Route nesting

`/lobby/leaderboard` must be nested under `/lobby`, not a sibling. The repo documents why:
nesting keeps the lobby page underneath so `context.go('/lobby')` shrinks the stack and
plays the *pop* transition; as siblings, `go` swaps the whole stack and Flutter animates a
forward push instead.

---

## 9. Privacy, consent and legal

1. `profiles.public_profile` defaults to **false**. Server-side, because the server is
   what publishes; a shared_preferences flag (the `AnalyticsConsent` pattern) is the wrong
   home for this one.
2. Consent is asked once, in context - the first time the leaderboard is opened - with
   plain copy about what becomes public: display name, avatar, streak, rank. Not hours
   watched with whom, not room names, not media.
3. Opting out removes the row from every published board immediately and hides the public
   profile. Historical ledger data is retained for the user's own stats.
4. Guests can never appear. Structurally impossible - they earn nothing.
5. `delete_account` must cascade the four new tables. It already fails loudly on missing
   cascades (that is what `..._purge_stale_guests.sql` had to fix for `rooms.created_by`);
   add pgTAP coverage rather than assuming.
6. **Privacy policy and FAQ updates ship in the same release.** The FAQ currently says
   "no ads or tracking" and describes the data collected; a public leaderboard and public
   profiles are new categories and must be listed. Shipping the feature without the policy
   update is the failure mode worth naming.

---

## 10. Instrumentation

Per the standing instruction, in the same diff as the code.

`trace` gets a new category: **`rewards`**. Transitions and corrections only, never ticks:

- streak incremented / broken / frozen (with `{from, to, day}`)
- achievement unlocked (`{id}`)
- heartbeat rejected by the server and why (`{reason}`) - this is the one that will
  actually be needed at 2am
- leaderboard load failure

**No `trace` on the 60 s heartbeat itself.** It is a tick, it is exactly the kind of thing
the doctrine forbids, and it would evict the trail that matters from the ring buffer.

`reportNonFatal` in any `catch` that would otherwise swallow a consequential failure -
particularly the recap upload and the handle claim, both of which show friendly copy and
would otherwise fail invisibly.

---

## 11. Analytics (product events)

User-initiated only. The invariant: nothing fires from a server push, a realtime callback,
or a render.

```
leaderboard_viewed    {scope}
leaderboard_opt_in    {on}
achievements_opened
recap_shown                        -- a screen the user's leave produced; borderline, see below
recap_shared          {surface}
profile_handle_claimed
streak_shared
frame_equipped        {frame}
```

**The nuanced case: `achievement_unlocked`.** By the letter of the doctrine it is a render,
like a crown - nobody caused it at that moment. But it is genuinely the most valuable
product event in this feature, and unlike a crown it is a discrete, server-authoritative,
once-ever fact. Resolution: emit it **once, from the account owner's client, at the moment
the unlock toast is first shown**, deduped by achievement id in `shared_preferences` so a
reconnect, a reinstall or a second device cannot double-count. It is never emitted by an
observer, never from a realtime callback on someone else's unlock, and never re-emitted.
Write that reasoning into the code comment, because the next reader will otherwise
reasonably try to delete it.

`recap_shown` is similarly borderline - the user's leave caused it, one per session,
already deduped by `_sessionReported`. Acceptable. `recap_shared` is the one that matters.

Funnels to build in PostHog on day one:
- `recap_shown` -> `recap_shared` -> (web) `/r/` pageview -> `/download` -> `app_opened`
  **This is the word-of-mouth loop. If it does not convert, nothing else in this plan
  matters, and it is measurable within a week of Phase 1.**
- `app_opened` -> `room_joined` -> day-2 / day-7 return, split by streak length
- `leaderboard_viewed` -> `upgrade_cta_shown` -> `checkout_opened`

---

## 12. Testing

| Layer | What |
|---|---|
| pgTAP `15_rewards_test.sql` (60 assertions) | heartbeat clamp; guest earns nothing; solo earns nothing; stale media position earns nothing; per-pair cap; daily cap; local-day validation; streak increment / break / freeze; achievement idempotency |
| pgTAP `16_leaderboard_test.sql` (43 assertions) | opt-out excluded from others' views but present in own; rank correctness; participation floor |
| pgTAP `07_grants_test.sql` | extend - every new RPC granted to `authenticated` after its drop/recreate |
| Dart `test/rewards/rewards_logic_test.dart` | pure scoring, multipliers, superlative selection, next-threshold copy |
| Dart `test/rewards/rewards_service_test.dart` | fallback state on load failure; realtime debounce |
| Widget | streak chip states (none / active / frozen / broken); leaderboard empty + below-floor states; recap card |
| Website `tests/` | `/join/<code>` fallback; OG renderer; leaderboard floor; handle reserved-word rejection |

Note the pgTAP constraint the repo already documents: each file is one transaction that
rolls back, and `now()` is transaction-time, so a test **cannot observe a timestamp
advance across statements**. Every streak and heartbeat test must assert against a value
back-dated by the test itself, not against elapsed time.

---

## 13. Risks, and two things worth arguing about

**1. Leaderboards may not fit this product as well as they fit a fitness app.**
Watching films with friends is intrinsically motivated. Wrapping it in a points economy
risks making a cosy thing feel like a job, and the people most likely to be alienated are
the couples and small friend groups who are the core use case. Mitigation is already in
the design - Circle board as the default, weekly reset, cosmetics-only rewards, and the
whole system opt-in for anything public - but it is worth an explicit A/B or a staged
rollout rather than a confident ship.

**2. Streaks create pressure to open the app when you do not want to.**
That is the mechanic working as designed, and it is also how streak features earn their
bad reputation. The streak freeze is the mitigation; a second one is to **never send a
"your streak is about to break" notification** (the app has no notification infrastructure
today - keep it that way for this). Let the streak be a thing users discover when they
open the app, not a thing that summons them.

| Risk | Mitigation |
|---|---|
| Empty leaderboard at launch | Participation floor; Circle board first |
| Farming | Section 7; kill switch |
| Premium cannibalization | Cosmetics and grace only; no point multipliers for money |
| Privacy backlash | Opt-in, policy updated in the same release |
| Scope creep into a whole economy | Phases 0-1 are independently valuable; stop after either if the funnel does not convert |
| Recap URLs indexed by search engines | `noindex` on `/r/<id>`; opt-in only for `/u/<handle>` |

---

## 14. What I would build first if only one thing shipped

**Phase 0 + Phase 1.** A clickable invite link and a shareable session recap with silly
superlatives. Together they are roughly one to two weeks of work, need no schema, no
leaderboard, no streak, no consent flow and no policy change - and they are the only part
of this plan that directly answers "free word of mouth". The retention machinery in Phases
2-4 is worth building, but it is worth building *after* there is a measured share-to-install
conversion to feed it.

---

## Appendix: badge artwork

`assets/badges/*.png` (18 files, 256px, ~1.2 MB total) is **build output**. Change
`tool/process_badge_art.py` and re-run it; never hand-edit a PNG.

```bash
python3 -m venv /tmp/badges && /tmp/badges/bin/pip install Pillow numpy scipy
/tmp/badges/bin/python tool/process_badge_art.py <renders-dir> assets/badges 256
```

The source renders are **not in the repo** - eighteen 2048px PNGs is ~90 MB, and
they are regenerable from the prompts below.

### Why the renders are black, not transparent

The image model cannot emit an alpha channel. Asked for a transparent PNG it
paints a *picture of a checkerboard* - the UI symbol for transparency - as opaque
pixels. The first attempt came back that way and was unusable.

Asking for **flat pure black** instead is both achievable and better for glowing
artwork: luminance then *is* the alpha, so a glow fades out naturally instead of
being hard-keyed into a fringe. Two wrinkles the script handles:

- A glyph can contain genuinely dark pixels - `devoted` has a near-black
  checkmark on a gold calendar - so the silhouette is flood-filled from the
  border first and everything enclosed is forced opaque. Keying on luminance
  alone punches a hole straight through it.
- Every render carries a decorative corner sparkle. It is dropped by connected
  components: anything unattached to the glyph and under a twentieth of its area
  is a speck, and a speck that survives is a stray dot in a 40px tile.

### What the prompts must say

Learned the hard way, and all four matter:

1. **Flat pure black background**, never "transparent".
2. **Bare glyph - no tile, frame, badge, container or border.** `BadgeTile`
   already draws a glass tile; art that carries its own nests glass on glass,
   which the design system forbids and which looks muddy.
3. **One bold silhouette, no scenes.** These render at **40px**. The first
   attempt asked for a laurel wreath *plus* a film reel, a ring of ten figures, a
   calendar with grid lines - all mush at that size.
4. **Generate one reference, then attach it to every other prompt.** The model is
   an image *editor* at heart; "same style, change only the symbol" gives
   consistency that 18 independent prompts never will.

The reference prompt:

> A single glowing icon symbol floating on a solid pure black background. The
> symbol is two hands clasped in a handshake, drawn as bold thick simplified
> shapes with no fine detail. Glossy 3D glass material with a violet-to-magenta
> gradient (#8B5CF6 to #C084FC), bright inner glow, crisp rim light, and a soft
> violet glow spilling onto the black around it. The symbol is centred and fills
> about 80% of the frame. Square 1:1 image. Background is flat pure black
> #000000 with nothing else in it - no tile, no rounded square, no frame, no
> border, no container, no card, no checkerboard, no text, no letters, no
> numbers. Just the glowing symbol on black.

Every other badge is that image plus: *"Using the attached image as the exact
style reference - same glossy violet glass material, same lighting, same glow,
same size in frame, same flat pure black background - replace the symbol with
SUBJECT. Keep everything else identical. No tile, no frame, no text."*

Subjects: handshake · flame · upward arrow with flame trail · lightning bolt
through an unbroken ring *(gold)* · two overlapping clapperboards · cluster of
three person silhouettes · hourglass with a light trail · crescent moon and
stars · three interlocking rings · laurel wreath *(gold)* · party popper · game
controller · bullseye with an arrow *(magenta)* · three speech bubbles ·
calendar with a checkmark *(gold)* · trophy cup in gold / silver / bronze.

### Locked badges

Rendered dimmed and desaturated rather than behind a padlock: the shape stays
recognisable, which is the point of showing somebody what they have not earned.
The progress ring already says "not yet", so a padlock would say it twice. A
badge with **no** art still falls back to its Material Symbol, and to a padlock
when locked - `achievements` is a database table, so the catalogue is allowed to
run ahead of the client.
