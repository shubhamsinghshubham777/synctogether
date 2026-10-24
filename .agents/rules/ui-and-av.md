---
description: Projection booth cinema design system tokens, PTLoader, LiveKit AV rails, diagnostics vs. analytics doctrines, and generated asset tools.
trigger: model_decision
---


# UI Design System, AV & Telemetry

Guidance for UI components (`lib/ui/`), audio/video facecams (`lib/av/`), diagnostics (`lib/diagnostics.dart`), analytics (`lib/analytics.dart`), and generated assets.

## 1. Design System & UI Components (`lib/ui/`)

- **Dark Mode Only**: Aesthetic is warm cinema projection booth (dark mode only, no blur, warm neutrals). All colors and typography must use tokens from `lib/ui/pt_theme.dart` (`PTColors`, `PTText`). **Never hardcode hex color values.**
- **Bundled Fonts**: Bricolage Grotesque, Hanken Grotesk, and JetBrains Mono (in `assets/fonts/`). Icons are `BoothIcons` (`lib/ui/booth_icons.g.dart`); reach for one before a Material symbol, which stays only where no board draws a counterpart.
- **Loading Indicators**: Always use **`PTLoader`** (`lib/ui/loader.dart`), which is a tinted `CupertinoActivityIndicator`. Never use `CircularProgressIndicator` (except the determinate countdown ring in `PTBanner`).
- **Panel motion**: `GlassPanel` keeps its name but no longer blurs (an opaque Seat surface with a Rail hairline), so fading one is safe. The existing slide/clip animations (`Align(heightFactor:)`, slide transforms) stay because they read as mechanical, which is the booth motion language.
  - **Collapsed Overlays**: In a `Positioned`, zero-height/collapsed states still receive touch events. Always wrap inactive or collapsed overlays in `IgnorePointer`.
- **Keyboard Navigation & Focus**:
  - Shortcuts are ignored while `EditableText` has focus.
  - Esc hierarchy is strictly ordered: Emoji picker close -> Text field unfocus -> Reaction strip close -> Chat panel close -> Fullscreen exit.

---

## 2. Audio / Video Facecams (`lib/av/`)

- **LiveKit Service**: Managed per room via `LiveKitService`.
- **Token Minting**: Fetches credentials from `supabase/functions/livekit-token`.
- **Availability**: Gated strictly on `LiveKitService.isAvailableFor(room.avLevel)` (`none`, `voice`, `video`).
- **Video Publishing Cap**: Video publishes capped at 360p / 24fps to conserve room bandwidth for media playback.

---

## 3. Diagnostics vs. Analytics Doctrines

### Diagnostics (`lib/diagnostics.dart`) - *"Why did this break?"*
- **`reportNonFatal(error, stackTrace)`**: Routes to Sentry for unhandled or unexpected failure branches.
- **`trace(msg, category:, data:)`**: Records breadcrumbs on key state transitions (`billing`, `sync`, `gate`, `media`, `room`, `av`, `deeplink`, `auth`, `turnstile`, `youtube`, `tls`, `webview`, `analytics`, `rewards`, `moderation`, `network`).
- **Do NOT log per-frame or per-heartbeat ticks**: Avoid logging on the 10 s position heartbeat, presence updates, or scrub preview dragging to prevent evicting useful breadcrumbs.
- **Privacy**: Never log chat messages or full local file paths.

### Analytics (`lib/analytics.dart`) - *"Is anyone doing this?"*
- **Strictly User-Initiated**: Fire analytics events **only when a human explicitly triggered the action**. Never track inside remote action callbacks, gate pauses, drift corrections, or reconnect handlers.
- **Implementation**: Custom lightweight `dart:io` HTTP client to PostHog Cloud (no third-party Flutter plugin dependencies).
- **Privacy Boundaries**: Never track media file names, file paths, chat text, or YouTube video IDs.
- **Opt-Out**: User consent (`AnalyticsConsent`) is checked before initialization.

---

## 4. Generated Assets & Build Scripts (`tool/`)

The following files are generated build outputs. **Never edit them manually**:

| Asset | Generated Output | Generator Command |
| :--- | :--- | :--- |
| **Splash Sound** | `assets/sfx/splash.wav` | `python3 tool/generate_splash_sound.py` |
| **Reaction Emoji** | `assets/emoji/*.json` | `python3 tool/fetch_reaction_emoji.py` |
| **CA Root Bundle** | `assets/ca/cacert.pem` | `python3 tool/update_ca_bundle.py` |
| **App Icons** | `assets/icon/`, `windows/.../app_icon.ico` | `python3 tool/generate_app_icon.py && fvm dart run flutter_launcher_icons` |
| **Chat Emoji Data** | `lib/rooms/emoji/emoji_data.g.dart` | `python3 tool/generate_emoji_data.py` |
| **Booth Icons** | `assets/fonts/BoothIcons.otf`, `lib/ui/booth_icons.g.dart` | `python3 tool/generate_booth_icons.py` |
| **Badge Art** | `assets/badges/*.png` | `python3 tool/process_badge_art.py <renders-dir> assets/badges 256` |
