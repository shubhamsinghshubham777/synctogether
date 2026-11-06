# Foldables and dual screens

The app classifies the *window* and reads folds from `MediaQuery.displayFeatures` (`foldOf`); it never looks at a device model. The rules live in `docs/agent/ui-and-av.md` ("A pane is its own small window", "iPhone Duo is a first-class device"); boards 52-57 on the design canvas draw them.

| Posture | What the OS reports | What we render |
|---|---|---|
| Cover display (Flip 360x374, iPhone Duo closed 466x678) | a small window | phone room; under 420 tall, picture and transport only |
| Unfolded, flat (Fold 882x1104, Pixel Fold, iPhone Duo inner 951x669 / 669x951) | one window, a flat or inactive fold | continuous display: roomy landscape, stacked portrait, or picture over a deck when near-square |
| Book / dual screen | Android: `hinge` or half-opened `fold`, vertical. iPhone Duo: an *active division* region | video left, chat right, nothing on the fold; the lobby spans both halves |
| Tabletop / laptop | half-opened `fold`, horizontal (iPhone Duo: the inner display held portrait, division active) | picture in the upper pane, a two-column deck below; one-column screens use the lower pane |

Anything that is not the room or the lobby takes one pane (`PTHingeSafe`); dialogs and popovers land in the pane they opened from, or the one the keyboard has not covered.

## Testing

- Software: `fvm flutter test test/layout` renders every screen and dialog over `kScreenMatrix` (Fold, Surface Duo-like, Pixel Fold, Flip, **iPhone Duo outer / inner / book / tabletop**, keyboards in folded postures, landscape tabletop, portrait book). `--dart-define=SCREENSHOTS=true` writes PNGs to `build/screenshots/` (the harness fails on a few desktop cases with it set; a normal run is the truth). Room fold tests: "room on a fold", "posture sequence" (video surface identity and draft survive the Fold's and the Duo's whole sequence) and "resizing inside the deck" in `room_screen_matrix_test.dart`; `hinge_check_test.dart` proves the hinge assertion can fail.
- **iPhone Duo simulator (Xcode 27.1, iOS 27.1):** `xcrun simctl create 'iPhone Duo' com.apple.CoreSimulator.SimDeviceType.iPhone-Duo com.apple.CoreSimulator.SimRuntime.iOS-27-1`, then `fvm flutter run -d <udid> --dart-define=DEMO_MODE=true --dart-define=DEMO_ROOM=true` (a mock room, no backend). `simctl` has **no fold command**: the open / closed / book / rotate buttons are in `DeviceHub.app` (Controls menu and the bar under the device). Screenshot each display with `xcrun simctl io <udid> screenshot --display=<uuid>` (`simctl io <udid> enumerate` lists them; the inner is 2007x2853, the outer 1398x2034). Driving Device Hub from a script works with posted mouse events (no accessibility permission); AppleScript sees nothing.
- **Android emulator (verified: opened, half-opened/book, rotated/tabletop).** Install `cmdline-tools` into the SDK (`cmdline-tools/latest`), then `avdmanager create avd -n Fold_Test -k "system-images;android-37.2;google_apis_playstore_ps16k;arm64-v8a" -d 62` (device 62 is "7.6in Foldable"; 1768x2208 at 420 dpi, a vertical hinge at x=884). **On this Mac a freshly created AVD does not boot** (`hvf is not enabled`, `qemu_mprotect__osdep: Permission denied`, adb stays `offline`) whatever the flags or the sandbox; the AVD that works is one cloned from a working one: `cp -R Fast_Phone.avd FoldClone.avd`, drop its `snapshots/`, locks and `hardware-qemu.ini*`, point `FoldClone.ini` at it, and overlay the foldable keys (`hw.sensor.hinge*`, `hw.sensor.posture*`, `hw.sensor.roll*`, `hw.lcd.width/height/density`, `hw.device.*`) onto its `config.ini`. Run `emulator -avd FoldClone -memory 3072 -cores 4 -no-audio -gpu host -no-snapshot-load -no-snapshot-save` (`-memory` must be explicit), `fvm flutter run -d emulator-5554 --dart-define=DEMO_MODE=true --dart-define=DEMO_ROOM=true`, and drive it from the console: `adb emu posture 3` (opened) / `2` (half-opened) / `1` (closed), `adb emu rotate`; screenshots with `adb exec-out screencap -p`. Quit with `adb emu kill`.
- iPad Split View and Stage Manager exercise the same window-size path.

## What only real hardware confirms

Hinge feel and the real fold width (the simulator reports 40 pt); how many frames pass between the fold angle changing and the regions updating; whether the keyboard covers one half or both on a folded device; multi-window quirks; the Flip cover launcher's app allow-list; the room under a real unfold with video playing (no stutter, no restart); the iOS 27.1 SDK's behaviour when an app is built with an older SDK (this app builds with 27.1).
