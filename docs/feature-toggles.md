# What you can turn on and off, and how

Every switch in SyncTogether lives in one of four places. This lists all of them,
what they do, and the exact command to change one.

| Where | Changes take effect | Needs |
|---|---|---|
| **`reward_config`** table | Immediately, no deploy | SQL |
| **`tier_limits`** table | Immediately, no deploy | SQL |
| **`app_settings`** table | Immediately, no deploy | SQL |
| **Dart defines** (`--dart-define`) | Next build | A release |

Run SQL from the Supabase dashboard (SQL editor), or locally with:

```bash
docker exec -it supabase_db_synctogether psql -U postgres -d postgres
```

---

## 1. `reward_config` — streaks, points, leaderboards, seasons

The gamification tuning surface. **Nothing here requires a deploy.** Clients read
these through the RPCs, so a change is live on the next heartbeat.

```sql
-- See everything
select key, value from public.reward_config order by key;

-- Change one
update public.reward_config set value = '30'::jsonb where key = 'streak_min_minutes';
```

| Key | Ships as | What it does |
|---|---|---|
| `ledger_enabled` | `true` | **Master kill switch.** `false` makes the heartbeat a no-op - no streaks, no points, no badges accrue. Existing data is untouched. |
| `seasons_enabled` | `false` | Monthly podiums. **Off, because a trophy cannot be un-awarded** and there is nobody to crown yet. Turn on once the board is healthy. |
| `streak_min_minutes` | `10` | Minutes of watching *with someone* before a day counts toward a streak. |
| `daily_credit_cap_min` | `480` | Most minutes credited in one day (8h). Anti-farming. |
| `daily_points_cap_min` | `240` | Most minutes that convert to points in a day (4h). |
| `pair_daily_cap_min` | `120` | Most minutes with **the same person** that earn points in a day. Stops two accounts farming each other. |
| `heartbeat_clamp_sec` | `90` | Hard ceiling on seconds credited per heartbeat. **This is what makes the RPC unspammable** - do not raise it above the client's 60s interval by much. |
| `heartbeat_stale_sec` | `300` | A gap longer than this means they were away; credits nothing. |
| `playback_grace_sec` | `180` | How stale the room's playback position can be before it stops earning. Raise if rooms stop earning during long pauses. |
| `min_members` | `2` | People required in the room. `1` would make solo watching earn - don't. |
| `freezes_per_week` | `2` | Missed days a free account can absorb per week without losing its streak. |
| `freezes_per_week_premium` | `3` | Same, for Premium. Grace, not capability. |
| `co_watcher_points` | `15` | Points per distinct person watched with, per day. |
| `co_watcher_points_cap` | `5` | Most people that bonus counts for. |
| `full_house_members` | `4` | Room size that earns the bonus. |
| `full_house_bonus` | `25` | Size of that bonus. |
| `leaderboard_min_participants` | `30` | Opted-in players needed before the **global** board and season podiums appear at all. Below it, only the Circle board exists. |
| `recap_ttl_days` | `90` | How long a shared recap link works. |
| `recap_max_reactions` | `500` | Cap on the client-reported reaction count banked per session. |
| `recap_max_messages` | `1000` | Same, for messages. |
| `ledger_retention_days` | `400` | How long per-room daily rows are kept (Wrapped needs a year). |

**Turning the whole feature off:**

```sql
update public.reward_config set value = 'false'::jsonb where key = 'ledger_enabled';
```

**Turning seasons on** (do this only once the board has real traffic):

```sql
update public.reward_config set value = 'true'::jsonb where key = 'seasons_enabled';
```

---

## 2. `tier_limits` — what each plan gets

One row per tier. Tuning a plan is an `update`, never a deploy.

```sql
select * from public.tier_limits;

-- e.g. let free rooms hold ten people
update public.tier_limits set max_members = 10 where tier = 'free';
```

| Column | guest | free | premium |
|---|---|---|---|
| `max_live_rooms` | 1 | 4 | 20 |
| `max_members` | 4 | 8 | 16 |
| `max_session_minutes` | 60 | 240 | 240 |
| `max_total_session_minutes` | 60 | 240 | 1440 |
| `av_level` | none | voice | video |
| `persistent_room_cap` | 0 | 0 | 20 |
| `media_sharing` | none | limited | full |
| `media_sharing_weekly_bytes` | 0 | 2.5 GB | unlimited |

Two of these are read as *behaviour*, not just numbers:

- `av_level = 'none'` hides the facecam UI entirely, exactly as if LiveKit were unconfigured.
- `max_total_session_minutes > max_session_minutes` is what makes a tier able to choose its own extension length.

---

## 3. `app_settings` — media sharing

```sql
select value from public.app_settings where key = 'media_sharing';

-- Kill switch for all cloud uploads
update public.app_settings
   set value = jsonb_set(value, '{enabled}', 'false')
 where key = 'media_sharing';
```

| Field | Ships as | What it does |
|---|---|---|
| `enabled` | `true` | Master switch for cloud media sharing. `false` makes every upload fail with friendly copy; local-file sync is unaffected. |
| `free_tier_max_file_bytes` | 2 GB | Largest single file a free account may upload. |
| `premium_max_file_bytes` | 10 GB | Same, for Premium. |

Changing either cap here is only half the job - `EntitlementService.mediaSharingMaxSizeBytes`
inlines the same two numbers as a client-side pre-check, so an edit that is not
mirrored there leaves the app refusing a file the server would have taken (or
offering one it will reject). The weekly allowance lives in `tier_limits` above,
not here.

---

## 3b. `app_settings` — R2 cleanup

```sql
select value from public.app_settings where key = 'r2_cleanup';
```

| Field | Ships as | What it does |
|---|---|---|
| `enabled` | `true` | Master switch for the deletion sweeper. |
| `endpoint_url` | **`null`** | Full URL of the `cleanup-r2` Edge Function. |
| `service_role_key` | **`null`** | Bearer token the cron calls it with. |

**Two of these ship NULL, so nothing is collected until an operator fills them
in.** The `invoke-r2-cleanup` cron runs every 5 minutes, finds no endpoint, and
returns quietly; `invoke_r2_cleanup` only ever `raise warning`s, so a
misconfiguration is silent by design. Everything still *enqueues* correctly to
`pending_r2_deletions` in the meantime - the rows simply accumulate, and the
objects stay in the bucket and keep costing money. Check the queue depth rather
than assuming, and note that `cleanup-r2` permanently drops a row once
`attempts >= 5`, so a key that keeps failing is leaked deliberately:

```sql
select count(*), max(attempts) from public.pending_r2_deletions;
```

---

## 4. Dart defines — whole subsystems

These are compile-time. **Omitting one disables its subsystem cleanly** - no
timers, no sockets, no UI - which is why local development works with none of
them set. Changing any of these needs a rebuild and a release.

| Define | Absent means |
|---|---|
| `SENTRY_DSN` | No crash or error reporting at all. `reportNonFatal` and `trace` become no-ops. |
| `POSTHOG_API_KEY` | No product analytics: no queue, no timer, no socket. |
| `POSTHOG_HOST` | Defaults to `https://us.i.posthog.com`. |
| `LIVEKIT_URL` | Facecams disappear entirely - no service, no token fetch, no UI. |
| `TURNSTILE_SITE_KEY` | The client skips the captcha dialog, **but the server still demands a token**, so guest sign-in fails. Set it or disable captcha server-side too. |
| `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` | Required. Debug builds fall back to the local stack. |
| `DEMO_MODE` / `DEMO_ROOM` | Mock data for screenshots. Off in real builds. |
| `DEMO_TIER` | With `DEMO_MODE`: `free` (default) or `premium`, so Patron-side states can be shot. |
| `CAPTURE_STORE` | Store-screenshot capture flow: 1920x1080 into `assets/store/` (Microsoft Store and README). Add `STORE_TARGET=mac` and `STORE_BUILD=true` for the Mac App Store set, 2880x1800 into `assets/store/mac/`. Off in real builds. |
| `CAPTURE_WEBSITE` | Writes the homepage product shot. Off in real builds. |
| `CAPTURE_REVIEW` | With `DEMO_MODE`: renders every screen and state that has a design board to `build/review/<tier>/` at 1280x720 @ 1.5x, for comparing the build against the canvas. Run the built binary from the repo root. Off in real builds. |

Server-side captcha is separate, in `supabase/config.toml` under `[auth.captcha]`,
and ships with `supabase config push` (**not** `db push`).

---

## 5. Per-user switches (the user's own, not yours)

These belong to the person using the app. Listed so you know they exist.

| Switch | Where | Effect |
|---|---|---|
| **Share usage data** | Profile screen | Off stops *all* collection - product analytics **and** the watch ledger, so streaks, badges and leaderboards pause. Deliberately coupled: a switch that leaves half of it running is not a switch. Stored on-device in `shared_preferences`. |
| **Show me on leaderboards** | Profile screen | Off removes the account from every board and hides its public page. Stored server-side in `profiles.public_profile`, because the server is what publishes and therefore what must refuse. |
| **Auto-share local videos** | Profile screen | Remembers the upload-or-not choice instead of asking each time. |

---

## 6. Things that are *not* toggles

Worth knowing, so nobody goes looking:

- **Guests never earn streaks, badges or leaderboard places.** Not configurable. Anonymous accounts are purged after three days, so a streak on one is a promise that would break.
- **Premium buys no leaderboard points.** Not configurable, deliberately. It gets an extra streak freeze, the `aurum` avatar frame, and a public handle.
- **Handles are Premium.** Enforced in `claim_handle`. Being *on* a board is free.
- **Recaps never contain what you watched.** No file names, paths, links or chat - enforced in `create_recap`, which builds the payload server-side rather than accepting one.

---

## Verifying a change landed

```sql
-- gamification
select key, value from public.reward_config order by key;

-- is the global board open yet?
select public.leaderboard_open();

-- what a given account is entitled to
select public.effective_tier('<user-uuid>');
select * from public.tier_limits where tier = public.effective_tier('<user-uuid>');
```
