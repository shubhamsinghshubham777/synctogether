# Pairing, Our Room, date nights and push

Read before touching `lib/pairing/`, `supabase/migrations/20261107*`, `supabase/functions/push-dispatch`, the three native `push` channels, or anything that changes how a room is counted, retired or entered.

Two signed-in accounts can **pair**. A pair owns one persistent private room (**Our Room**), date nights, and a history that feeds a weekly streak and a shareable year card. It exists for long-distance couples, but nothing in it says "couple" to the server: it is two accounts and the rules below. Rooms with friends and family are untouched.

## Data model (`20261107100000_pairing.sql`, `20261107110000_pair_features.sql`)

- `pairs`, `pair_members` (**`user_id` is the primary key: one pair per person**), `pair_invites`. All client reads are RLS-gated to the caller's own pair (`my_pair_id()`); **every write is a `security definer` RPC**. Tables grant `select` only.
- Deleting *any* membership deletes the whole pair (trigger `pair_member_removed`), which cascades to the other membership, Our Room, nights and sittings. Account deletion therefore ends the pair for both; `unpair()` announces `room_ended {reason: deleted}` first so a partner standing in the room is ejected.
- **Pairing is account-scoped. Guests cannot pair** (`assert_can_pair` raises `sign_in_required`). `effective_tier` stays the single arbiter, so "guest" is never re-derived client-side.
- `profiles.timezone` is an IANA name written by `set_my_timezone` (validated against `pg_timezone_names`). The partner's clock row is shown **only when it differs from the device's own offset** at that instant (`shouldShowPartnerTime`); DST is read at the moment in question, not today.

## Invites

- 48 h, six characters from the room alphabet, **one pending invite per inviter** (partial unique index); `create_pair_invite` reuses an unexpired one, so "Share again" never mints a second.
- `pair_invites.seen_by` is **not a claim**. It records the last signed-in person who opened the link, and exists only so the lobby banner can remind them after "Not now" or a cold start. Anyone can still accept while it is pending, so a forwarded link cannot lock out the real partner.
- **There is no push for a pairing request, and there cannot be one**: the invitee is unknown until they open the link, and by then the app is open. The "partner finds out" surface is the lobby banner (`PairRequestBanner`) plus the avatar dot. The inviter *is* pushed when it is accepted (`pair_accepted`).
- A typed pair code works in the lobby's "Enter a code" box: `join_room` says `room_not_found`, and `_openPairInvite` then tries it as an invite. A pair link to a signed-out person is parked in `PairService.pendingPairCode` and consumed after login, like `pendingJoinCode`.
- `synctogether://pair/<code>` is parsed by `pairCodeFromLink` (server alphabet only, so a stray path never reaches an RPC). The web page `/pair/<code>` (`website/app/pair`) reuses `JoinLauncher` with `kind="pair"`; its copy differs because pairing is the one thing that needs an account. It says nothing about the sender: a code is a capability.

## Our Room - the invariants that are easy to break

Our Room is an ordinary `rooms` row with `pair_id` set (unique per pair), created by `open_our_room()` and restarted by it when resting. What makes it different is in five places, and **adding a sixth place that counts or ages rooms means adding the `pair_id is null` / `pair_id is not null` branch there too**:

1. `create_room` and `resume_room` count live and persistent rooms with `r.pair_id is null`, so Our Room **never uses a room slot** (a free account is `max_live_rooms` 4). These were patched from their *live* definitions (`pg_get_functiondef`), not from the migration files: the latest body of `create_room` lives in `20261006130000`, not where the name is first defined.
2. `room_state` returns `live`/`idle` for a pair room whatever the owner's tier, never `expired`. Without this a free owner's Our Room read `expired` and was swept.
3. `sweep_rooms` skips pair rooms in the "drop persistence for lapsed premium" step and in the idle-TTL delete, and prunes their chat at 90 days.
4. `retire_room` **keeps the chat** of a pair room (the lobby promises "chat history carries over").
5. `join_room` answers `room_not_found` to anyone not in the pair, so a stranger holding the code cannot occupy a live room. `list_my_rooms` excludes pair rooms: Our Room is reached through the pair card, never as a ticket.

**Both partners are hosts.** `set_room_media` is host-only and either partner must be able to choose what plays. Hosts cannot kick one another (`kick_member` refuses), so neither can remove the other, and succession on leave still has a host to fall back on. Presence is read from the room's own channel; "is my person on" comes from private presence on `pair:<pair id>`, authorised by the same `my_pair_id()` rule (`pair_id_from_topic` policies on `realtime.messages`).

## Patron rules

`pair_is_patron(pair)` = **either** partner is premium (via `effective_tier`). It decides two things, enforced in SQL:

- **Creating a date night** raises `patron_required`. Answering, accepting, moving and cancelling one never do - a free partner can always take part in what they were sent.
- **History older than 7 days** is hidden (counted in `locked_count`), never deleted. `pair_history_export()` returns everything on any plan, so a lapse never feels like losing memories.

Booked nights keep their reminders if Patron ends; nothing is removed. The client mirrors these as affordances only (`PairInfo.patron`).

## Date nights, history and the streak

`date_nights.proposed_by` is whoever made the *latest* proposal; the other person answers it, so moving a night hands the answer across (`nightStanding`). Reminders are queued for both people 15 minutes ahead under a per-night collapse key (`dn:<id>`), so a move replaces them and a cancel deletes them.

`pair_sessions` is written by `log_pair_session` and is **idempotent per minute of start**: both partners report the same sitting and the longer report wins. The room feeds a `TogetherClock` that runs only while both are present (`_trackTogether`), writes when the partner drops out (so a killed app costs minutes, not the night) and once more on exit. A week counts toward the streak at 20+ minutes together; the current streak survives an unfinished week. The year card is stats only (no titles, no chat) and is drawn at one fixed size with text scaling off, so it looks the same for whoever shares it.

## Push

The database decides **what to tell whom and when**; `supabase/functions/push-dispatch` only delivers.

- `push_tokens` (per platform, with APNs `environment`), `push_prefs`, `push_outbox`. Clients reach them only through RPCs; the outbox and tokens are unreadable even to their owner.
- `enqueue_push` queues nothing for a person with no device and respects their switches; a **collapse key** replaces an unsent row (`dn:<id>`, `wl:<pair>`, `reunion:…`).
- **Quiet hours are enforced at claim time, in the recipient's own zone** (`claim_push_batch`: 23:00-08:00 holds everything except `kind = 'call'`), so a reminder queued at noon still respects 11 PM. A call expires in 90 s and is throttled to one a minute.
- `invoke_push_dispatch` is `invoke_r2_cleanup`'s twin: inert until `app_settings.push.endpoint_url` is set, then `pg_net` from `minutely_maintenance` and straight after an enqueue.
- Providers are independent and optional (`_shared/push.ts`, 12 Deno tests): APNs over HTTP/2 with an ES256 provider token, FCM HTTP v1 with a service-account OAuth token, WNS with client credentials. An unconfigured platform is **skipped, never failed**, so a fork shipping on one platform needs only that platform's secrets. Dead tokens (APNs 410, FCM `UNREGISTERED`, WNS 404/410) are dropped. **WNS channel URIs come from clients, so only `*.notify.windows.com` is ever called** (`isWnsChannel`).
- Reliability: an alert push is shown by iOS/macOS/Android even after a swipe-away; **force-stop** on Android and silent pushes after a force-quit on Apple are not delivered by any server design, which is why nothing here relies on silent pushes.

Client: one `MethodChannel` (`app.synctogether/push`) answered by every runner, so `PushService` is a single Dart implementation tested against a fake `PushBridge`.

- **Nothing prompts by itself.** `start()` only reads the permission; `enable()` is the one call that shows the OS prompt, and it runs because a person just turned a switch on (notification settings, or the hub's "Hear it when Sam calls").
- iOS/macOS: APNs directly, no SDK. A debug build's token is `sandbox`, a release build's `production`. The macOS `aps-environment` entitlement is **only in `Release-Store.entitlements`**: a restricted entitlement on a build without a provisioning profile makes AMFI kill the app at launch, so local debug builds simply have no push.
- Android: FCM with **no `google-services` file**. Firebase options arrive as `--dart-define`s (`Env.firebaseOptions`, all four or none), are stored by `Push.configure`, and `App.onCreate` re-initialises Firebase from them so a message can start a cold process. Unset, the build reports `unsupported` and offers no switches.
- Windows: WNS needs package identity, so only the packaged MSIX build has push. A toast is written with **protocol activation**, so a tap launches `synctogether://push?route=…` and the existing `app_links` handler does the rest - there is no native tap code. **`push_channel.cpp` was written without a Windows toolchain and has not been built or run**: build it, then test a real toast on a packaged, Store-associated install before relying on it (the same caveat `store_purchase.cpp` carried until it was exercised).
- Sign-out calls `PushService.forgetDevice()` *before* the session goes, because afterwards the server can no longer be told to stop pushing that account to this device.

## Testing seams

`FakePairService` (`test/support`) hands a screen its state with no backend; `test/layout/pair_matrix_test.dart` and `pair_screens_matrix_test.dart` run every pair screen across the whole screen matrix (folds, iPhone Duo, 2x text) and write real-font PNGs with `--dart-define=SCREENSHOTS=true`. Decisions are free functions in `pair_logic.dart`, `pair_links.dart`, all unit tested. `supabase/tests/30_pairing_test.sql` and `31_pair_features_test.sql` cover the RPCs; the second runs row-visibility assertions **as the `authenticated` role** (a superuser bypasses RLS and would pass for the wrong reason).

## Analytics

Product events fire only where a human caused them: `pair_invite_created`, `pair_invite_shared {via}`, `pair_accepted`, `pair_ended`, `our_room_opened`, `partner_called`, `date_night_planned`, `date_night_answered {accepted}`, `pair_year_shared`, `push_enabled {platform}`, plus the existing `upgrade_cta_shown/clicked` with surfaces `date_night` and `pair_history`. Never a film title, a link, a name or chat. All are listed in `lib/analytics_catalog.dart`, which a test keeps in step with the code.

## Not built (decided, not forgotten)

A shared watchlist and "Pick tonight" were built and then removed. This app plays the pair's own files and YouTube links, so there is no catalogue to recommend from, and a bare list of typed titles did not earn its place. If it comes back it should start from a real need (a title that reaches the room's source picker), not from a list.

A QR code for the invite; EventKit's native "Add to Calendar" (the share sheet carries the `.ics`, which iOS Calendar opens); "ping me when Sam is on"; a per-week breakdown behind the streak dots; hours-and-days granularity on the reunion card (the reunion is a calendar date with no time).
