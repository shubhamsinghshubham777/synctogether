You are working on a Windows 11 machine with the SyncTogether repo checked out. Goal: regenerate the Microsoft Store screenshots natively on Windows, so no macOS UI (traffic-light inset, Mac-only shortcut hints, Mac fonts or window chrome) appears in them. Do the work yourself; ask me only for things you truly cannot do.

Context
- Flutter via fvm: prefix every flutter/dart command with `fvm`. Pubspec pins are exact; do not change dependencies.
- The capture flow is `runStoreCaptureFlow` in lib/mock/store_capture.dart. It is enabled by `--dart-define=CAPTURE_STORE=true --dart-define=DEMO_MODE=true`, `STORE_TARGET` defaults to `windows`, lays the content out at 1280x720 and renders at 1.5x, so output is 1920x1080. It writes PNGs to `store/`, then exits. Shots: 1_lobby, 2_theater_room, 3_room_chat, 4_media_chooser, then the pairing set 6_our_room, 7_pair_hub, 8_date_nights, 9_streak, 10_year_card (5_subscription_purchase is Apple-only and is skipped on Windows).
- The committed store/*.jpg files were captured on a Mac. The capture only grabs the Flutter RepaintBoundary, so check whether the Mac look comes from the app UI itself (platform checks such as isMacOS/isApple, window controls inset, keyboard hints) rather than assuming the OS chrome is the cause.
- Read CLAUDE.md first. Follow it: dark mode only, design tokens from lib/ui/pt_theme.dart, no hardcoded colours, LF line endings (core.autocrlf=false), no Co-Authored-By trailers or "Generated with" lines in commits, hooks via `git config core.hooksPath .githooks`.

Steps
1. `fvm flutter pub get`, then `fvm flutter run -d windows --dart-define=CAPTURE_STORE=true --dart-define=DEMO_MODE=true` (debug is fine; the demo data needs no backend). If the build needs the vendored libmpv/ANGLE/libwebrtc, they are in the repo (see the `build(windows)` commit); do not download them from elsewhere.
2. Let the flow run to the end. Confirm the log prints `[STORE CAPTURE] Complete!` and that store/ has fresh PNGs with timestamps from this run.
3. Open every PNG and look at it. Check: size is exactly 1920x1080; no window title bar or Mac chrome; Windows-appropriate hints (Ctrl, not Cmd; Esc to go back); the video frame, avatars and chat are populated, not empty or loading; no debug banner, no "local" wordmark in amber (that means it ran against the local stack: DEMO_MODE should avoid that, so fix it if it appears); text is not clipped; pairing screens show the demo pair and a finished film in Our Room.
4. If anything looks Mac-specific or broken, fix it in the app code (not in the images), keep the Mac and iOS behaviour unchanged, add or update a test, and re-run. If the capture window cannot reach 1280x720 content because of Windows DPI scaling, fix `_sizeContentTo` rather than resizing the output.
5. Convert to the committed format: `magick store/<name>.png -quality 86 -strip store/<name>.jpg` for each shot (install ImageMagick with winget if missing), delete the PNGs, and confirm each JPG is 1920x1080. Keep the same file names so nothing else changes.
6. Run `fvm dart format --output=none --set-exit-if-changed .`, `fvm flutter analyze` and `fvm flutter test`; all must pass before committing.
7. Commit to main directly (no branch) with a plain message such as `feat(store): native Windows screenshots`, then push. Do not publish to the Microsoft Store and do not touch the listing JSON; I will do that.

Report back
- The list of files changed, the output of `file` or `magick identify` for each JPG, and the three shots you are least sure about, with why.
- Whether you changed any app code and what for.
- Anything you could not verify.
