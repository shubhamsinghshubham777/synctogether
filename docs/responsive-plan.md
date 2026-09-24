# Responsive readiness plan

Goal: every screen works correctly, and feels designed rather than stretched, on
desktop windows, phones (portrait and landscape), tablets (portrait and
landscape, including split view and Stage Manager), foldables (folded, unfolded
and tabletop), and at large accessibility text sizes. An automated size matrix
proves it and keeps it true.

Status: **planned, not started.** Implementation begins once the in-flight
website work (`website/**`, currently uncommitted) lands. None of this plan
touches `website/`.

---

## 0. Decisions already made

| # | Decision | Source |
|---|---|---|
| D1 | Remove `onDoubleTap: _toggleFullscreen` from the desktop video (`room_screen.dart` `_desktop()`, ~L4878). A single click toggles controls instantly. Fullscreen stays on F / Esc / the control-bar button / the native green button. | User, 2026-09-24 |
| D2 | Layout is decided by **two questions**: how much room is there (size class) and what drives input (pointer vs touch). Width alone no longer decides. | This plan |
| D3 | Tablets get their own layout: roomy like desktop, with touch affordances (tap to toggle, double-tap skip zones, no hover or cursor logic). | This plan |
| D4 | Foldables are handled through `MediaQuery.displayFeaturesOf` (hinge/fold). There is no special-casing by device model. | This plan |
| D5 | A widget-test size matrix is the definition of done. A layout counts as supported only when the matrix renders it without overflow. | This plan |

---

## 1. Foundation (serial, lands first, owned by the lead agent)

Everything in phase 2 depends on these APIs, so they land in one small commit
before any agent fans out.

### 1.1 `lib/ui/responsive.dart`: a new classification

Replace the width-only `layoutOf` with:

```dart
enum PTLayout { desktop, tablet, portrait, landscape }

/// Pointer-first (mouse/trackpad) vs touch-first.
enum PTInput { pointer, touch }

PTInput inputOf(BuildContext context);   // isDesktop platform → pointer, else touch
PTLayout layoutOf(BuildContext context);
```

Rules for `layoutOf`, evaluated in order:

1. `inputOf == pointer` and width >= 840 → `desktop` (desktop windows can't go below 900x600 anyway).
2. `inputOf == touch` and `size.shortestSide >= 600` → `tablet`. This covers
   iPad in both orientations, unfolded foldables, and Android tablets.
3. Otherwise width > height → `landscape`, else `portrait`.
4. **Split-view / multi-window:** the rules run on the *window* size
   (`MediaQuery.sizeOf`), so an iPad in 1/3 split view (about 320 wide) correctly
   becomes `portrait`. Crossing a class boundary rebuilds the layout builder but
   must never recreate `RoomScreen` state (see 2A.5).

`PTResponsive` gains an optional `tablet:` builder, with fallback
`tablet → desktop → landscape → portrait`. Screens that only need a
wider-content tweak can keep falling back to `desktop`. The room screen gets a
real tablet builder.

Add helpers used across the codebase:

- `PTFold foldOf(BuildContext)` → `{none, vertical(hingeRect), horizontal(hingeRect)}`,
  read from `MediaQuery.displayFeaturesOf` (`DisplayFeatureType.hinge` or `.fold`
  with `state == postureHalfOpened`, or a hinge with non-zero area).
- `bool isCompactHeight(BuildContext)` → height < 480 (phone landscape, and
  tabletop half-panes).
- Breakpoint constants documented in one place. `responsive_framework`
  stays only if something else needs it; otherwise drop the dependency (exact
  pin removal in `pubspec.yaml`).

Update `test/ui/responsive_test.dart` with a table of (size, platform,
displayFeatures) → expected `PTLayout`, including 744x1133 iPad mini → tablet,
820x1180 → tablet, 1180x820 → tablet, 882x1104 Fold unfolded → tablet,
390x844 → portrait, 844x390 → landscape, 1440x900 macOS → desktop, 320x1024
iPad split view → portrait.

### 1.2 D1: remove `onDoubleTap`

One-line removal in `_desktop()`. Fix the CLAUDE.md paragraph under "Room
viewing UX" so it reads correctly again. It already says "no `onDoubleTap`";
confirm nothing else re-adds it. Add a widget test in the room test suite (or
a focused one) asserting the desktop video `GestureDetector` has
`onDoubleTap == null`, so this regression can't come back silently.

### 1.3 Test harness: `test/support/screen_matrix.dart`

```dart
class ScreenCase { String name; Size size; TargetPlatform platform;
                   double textScale; List<DisplayFeature> features; EdgeInsets padding; }

const kScreenMatrix = [ ...see §3... ];

Future<void> pumpAtSize(WidgetTester t, Widget child, ScreenCase c);
void expectNoOverflow(WidgetTester t);  // fails on any RenderFlex overflow / FlutterError
```

`pumpAtSize` sets `tester.view.physicalSize`/`devicePixelRatio`, wraps in
`MediaQuery` (textScaler, padding for notches, viewInsets for keyboard cases,
displayFeatures), sets `debugDefaultTargetPlatformOverride`, and installs the
PT theme and responsive wrapper exactly like `MainApp.builder`. It reuses the
existing `lib/mock/mock_dependencies.dart` fakes and the `SyncBackend` seam so a
room can be pumped with no network.

**Exit criterion for phase 1:** `fvm flutter analyze` and `fvm flutter test` are
green, and the foundation commit is on `main`.

---

## 2. Parallel implementation (5 agents, disjoint file ownership)

Agents share one working tree. **Each agent owns its files exclusively** and
must not edit files owned by another. If an agent needs a change in someone
else's file, it reports it in its final message instead of making it. That is
what lets them run concurrently without a merge step.

| Agent | Owns | Must not touch |
|---|---|---|
| A: Room | `lib/rooms/room_screen.dart` | everything else |
| B: Dialogs | `lib/ui/glass.dart`, every dialog file (list in 2B) | `room_screen.dart`, `lobby_screen.dart` |
| C: Screens | `lobby_screen.dart`, `widgets/my_rooms_section.dart`, `auth/login_screen.dart`, `profile/profile_screen.dart`, `profile/subscription_screen.dart`, `rewards/leaderboard_screen.dart` | room, dialogs, `ui/` |
| D: Components & text scale | `lib/ui/*` except `glass.dart`/`responsive.dart`, `rooms/widgets/room_control_bar.dart`, `room_overflow_menu.dart`, `facecam_rail.dart`, `reaction_strip.dart`, `room_chat_panel.dart`, `readiness_overlay.dart`, `rewards/widgets/unlock_toast.dart` | screens, dialogs |
| E: Matrix tests | `test/layout/**` (new) | all of `lib/` |

### 2A. Room screen (Agent A): the biggest risk, one owner

1. **Tablet layout `_tablet()`**, wired through `PTResponsive(tablet: ...)`.
   - Landscape tablet: the desktop composition (docked chat 320, facecam rail,
     banner stack top-left) **with touch input**: no `MouseRegion`/cursor
     hiding, a tap toggles controls, double-tap ±10 s skip zones like the phone
     layouts, and larger hit targets (>= 44 pt). Fullscreen button hidden
     (`isDesktop` false). The control bar uses its non-compact variant.
   - Portrait tablet: video 16:9 pinned top, with chat, facecams and readiness
     roster *below* the video as real layout (not overlay). There is height to
     spare, so use it instead of covering the video.
2. **Phone landscape (`_landscape()`)**
   - Chat panel and banner widths become fractions with caps:
     `min(300, width * 0.38)` and `min(340, width * 0.42)`. The facecam rail
     drops to 2 tiles when `width < 740`.
   - Chat minimum height: if the space between `top` and `bottom` would drop
     below 160, or the keyboard is up (`MediaQuery.viewInsetsOf(context).bottom > 0`),
     chat switches to a **keyboard mode**. The panel spans from the top inset down to
     the keyboard, the control bar and reaction strip hide, and the video stays
     behind. Leaving the text field restores the normal layout.
   - Handle a 667x375 (iPhone SE) landscape case explicitly in the matrix.
3. **Phone portrait**: audit fixed widths (`maxWidth: 260` at ~L4763, facecam
   widths) against 320 and 360 widths. Anything fixed becomes
   `min(fixed, available)`.
4. **Foldables**
   - `vertical` fold (book posture): video in the left pane, chat and roster in the
     right. Nothing interactive straddles `hingeRect`.
   - `horizontal` fold (tabletop / Flex mode): video in the top pane, and the
     control bar, reactions and chat in the bottom pane. This is the headline
     foldable experience: the phone on a table playing a film.
   - Implemented as a small `_foldSplit(first, second, fold)` helper inside
     `room_screen.dart`. It stays in this file because it is used nowhere else.
5. **Layout switches must preserve state.** Everything that matters lives in
   `_RoomScreenState` fields already. Verify that crossing phone→tablet (split
   view drag, fold/unfold) keeps the sync channel, player, chat scroll, open
   reaction strip and focus. The only per-layout widgets are positional
   wrappers. The YouTube embed must keep `ObjectKey(controller)` and must not be
   remounted by a layout change. If the tree shape differs between builders,
   hoist the embed with a `GlobalKey` so the platform view isn't recreated
   (recreating it restarts playback).
6. **Instrumentation** (standing rule): `trace('layout class changed',
   category: 'room', data: {from, to, size, fold})` on *transitions only*, from a
   post-frame check comparing to the last recorded class. Never from `build`.
7. Esc/focus ordering and `PopScope` behaviour stay unchanged.

### 2B. Dialogs (Agent B)

1. `showGlassDialog` (`glass.dart`):
   - Horizontal gutter: `insetPadding` 16 each side, so width becomes
     `min(width, screenWidth - 32)`.
   - Height: `maxHeight = size.height - viewInsets.bottom - viewPadding.vertical - 32`,
     animated with the keyboard (`AnimatedPadding` on `viewInsets`).
   - Scrolling: the shell wraps the builder in a `SingleChildScrollView` by
     default. Add a `scrollable: false` escape hatch for dialogs that manage
     their own list (AV settings device list, shared recaps list). Use the
     existing `scroll_fade` treatment so clipped content reads as scrollable.
   - Compact padding: horizontal padding drops 32 → 20 below 400 width.
   - Phone portrait option `sheetOnCompact: true` presents the dialog as a
     bottom sheet under 480 width, for the long forms (report, extend room, AV
     settings). Opt-in per call site, default off.
2. Audit every dialog for internal fixed sizes and replace them with
   constrained/flexible equivalents:
   `analytics_disclosure_dialog.dart`, `av/av_settings_dialog.dart` (also its
   220 fixed-height loader), `auth/turnstile_dialog.dart` (the 300x65 webview is
   Cloudflare's widget size and must stay. Wrap it in a `FittedBox` scaled down
   under 332 available width, never below Turnstile's 300 CSS minimum, so switch the
   page to `data-size="flexible"`), `profile/media_quota_dialog.dart`,
   `profile/camera_capture_dialog.dart` (250 preview → `min(250, avail)`,
   aspect preserved), `rewards/widgets/shared_recaps_dialog.dart`,
   `rewards/widgets/recap_card.dart` (470 → scale-to-fit, the card is
   screenshot art so scale it rather than reflowing), `rooms/widgets/report_dialog.dart`,
   `rooms/widgets/extend_room_dialog.dart`, `premium_tease_dialog`, ended-room
   dialog.
3. Dialog *call sites* inside `room_screen.dart` / `lobby_screen.dart` /
   `profile_screen.dart` only pass `width:`. The central fix covers them, so
   agent B does not edit those files. If a specific call site needs
   `sheetOnCompact`, B lists it for A and C.

### 2C. Screens (Agent C)

For each screen, add a `tablet:` builder only where the fallback is wrong:

- **Lobby**: tablet portrait gets the desktop header row with the two-column
  create/join cards and the rooms list below. Tablet landscape uses the desktop
  layout. The header `Row` (wordmark + streak/quota/premium chips + profile +
  logout) overflows near 840 with every chip showing: make chips collapse into
  the profile pill's menu below 1000 width (or wrap). Phone portrait at 320:
  verify the code input and cards.
- **Login**: already capped at 440, so check phone landscape (390 tall) scrolls
  and the Apple/Google buttons don't clip.
- **Profile**: the desktop two-pane uses a fixed 240 identity column. On tablet
  portrait use the stacked layout. The 104 avatar stays.
- **Subscription**: check the plan cards stack under 600, and that the IAP legal
  copy (Terms/Privacy/auto-renew, required by App Store 3.1.2) is never
  clipped or pushed off-screen. This is a review blocker, not polish.
- **Leaderboard**: capped 620. Tabs and rows at 320, podium at 1.5x text.
- All: `SafeArea` checked for landscape side insets (notch on the left or
  right in landscape iPhone).

### 2D. Components and text scale (Agent D)

1. Replace fixed widths that hold text with intrinsic sizing plus caps:
   control bar 110 box (time readout: use `FittedBox` or `IntrinsicWidth`
   with tabular figures), overflow menu `maxWidth: 116` pill,
   `maxWidth: 300` menu (→ `min(300, screen - 32)`), facecam rail 200,
   unlock toast 420 → `min(420, screen - 32)`.
2. Text scale policy: support system scaling up to **2.0x**, clamped with
   `MediaQuery.withClampedTextScaling(maxScaleFactor: 2.0)` at the app root
   (Agent D proposes it; the lead applies it in `main.dart`, which nobody owns in
   phase 2). Icon-only controls don't scale. Labels scale and wrap or ellipsize,
   never overflow.
3. Touch targets: `PTIconButton`/`PTButton` enforce a 44 pt minimum hit area
   when `inputOf == touch` (visual size unchanged). They read `inputOf`, a pure
   `MediaQuery`/platform read, which keeps them testable.
4. The reaction strip already sits in a `FittedBox`. Verify it at 320 and at 2.0x.
5. Chat panel: bubbles wrap at 2.0x, the composer grows to 4 lines max, and
   typing and presence rows ellipsize.

### 2E. Matrix tests (Agent E)

Writes `test/layout/*_matrix_test.dart`, one per screen: login, lobby (empty,
full rooms list, all chips), profile, subscription (store and non-store),
leaderboard, room (local idle, playing with chat open, readiness overlay,
facecams, banners stacked, chat keyboard mode), and each dialog.

Each test loops `kScreenMatrix` and calls `expectNoOverflow`. Agent E starts in
parallel with A–D against the foundation APIs. Early failures are *expected*
and are the to-do list. E does not fix `lib/`, only reports failing cases
grouped by owning agent.

---

## 3. The screen matrix

| Case | Size (logical) | Platform | Notes |
|---|---|---|---|
| phone-small | 320x568 | iOS | iPhone SE 1st gen / split-view floor |
| phone-android | 360x800 | Android | most common Android width |
| phone | 390x844 | iOS | notch padding 47 top / 34 bottom |
| phone-land | 844x390 | iOS | side insets 47 |
| phone-se-land | 667x375 | iOS | tightest landscape |
| phone-keyboard | 390x844 + 336 viewInsets | iOS | chat composer focused |
| phone-land-keyboard | 844x390 + 200 viewInsets | Android | the worst case |
| ipad-mini | 744x1133 | iOS | tablet portrait floor |
| ipad | 820x1180 | iOS | |
| ipad-land | 1180x820 | iOS | |
| ipad-pro-13 | 1032x1376 | iOS | |
| ipad-split-third | 320x1024 | iOS | must be phone portrait |
| fold-unfolded | 882x1104 | Android | Galaxy Z Fold inner |
| fold-book | 1080x960 + vertical hinge | Android | Pixel Fold-ish |
| fold-tabletop | 882x1104 + horizontal fold, half-opened | Android | |
| fold-cover | 344x882 | Android | narrow cover screen |
| desktop-min | 900x600 | macOS | the enforced minimum |
| desktop | 1440x900 | macOS | |
| desktop-wide | 2560x1080 | Windows | ultrawide |

Every case also runs at textScale **1.0, 1.5 and 2.0**. That makes 57 cases
per screen. They run in about a second each without network, which is well
inside CI budget.

---

## 4. Integration and verification (serial, lead)

1. Collect every agent's "needs a change in someone else's file" notes and
   apply them.
2. Apply root text-scale clamp in `main.dart`.
3. Run the whole matrix and fix the remaining failures, routed back to the
   owning agent via `SendMessage` if it's substantial.
4. Manual smoke on real devices where available: macOS window resized to the
   minimum, iPad Split View drag across the boundary while a video plays
   (playback must not restart), Android split screen, and a foldable emulator
   (Android Studio "7.6 Fold-in with outer display" + tabletop posture).
5. CLAUDE.md updates: replace the responsive description (the `PTLayout`
   classes, `inputOf`, fold handling), keep the "no `onDoubleTap`" rule, and add
   "a new screen or dialog must pass `test/layout/`" to Conventions.
6. Pre-commit checklist: `fvm dart format --output=none --set-exit-if-changed .`,
   `fvm flutter analyze`, `fvm flutter test`. Commits split by concern
   (foundation / room / dialogs / screens / components / tests / docs).

---

## 5. Risks

| Risk | Mitigation |
|---|---|
| `room_screen.dart` (5.3k lines) is a merge hotspot | Single owner (A); nobody else edits it in phase 2 |
| A layout switch remounts the YouTube platform view and restarts playback | `GlobalKey` hoist + an explicit test that switches class mid-play and asserts the controller/embed identity is unchanged |
| Tablet touch skip zones reintroduce double-tap lag on tablets | Accepted: it matches phone behaviour (touch users expect double-tap skip). Desktop, where snappiness matters, has no double-tap after D1 |
| Chat keyboard mode fights the Esc/focus order | Keyboard mode is derived from focus and viewInsets, not a new Esc consumer. Existing order untouched |
| Turnstile widget can't shrink below 300 CSS px | `flexible` size + FittedBox; the 320 case keeps 10 px margins |
| Matrix is slow or flaky | Pure widget tests, fake backend, no `pumpAndSettle` on infinite animations (loader, splash): use bounded `pump(duration)` |
| Premium/store-build branches untested at sizes | Subscription matrix runs both `isAppleStoreBuild` shapes |

## 6. Out of scope

- Web target, Linux-specific polish, TV / 10-foot UI.
- Redesigning desktop, which is already fine. Desktop changes are D1 plus the
  lobby chip overflow only.
- `website/`.
