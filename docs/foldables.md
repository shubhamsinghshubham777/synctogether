# Foldables and dual screens

The app classifies the *window* and reads folds from `MediaQuery.displayFeatures` (`foldOf`); it never looks at a device model. The rules live in `docs/agent/ui-and-av.md` ("A pane is its own small window"); boards 52 and 53 on the design canvas draw them.

| Posture | What the OS reports | What we render |
|---|---|---|
| Cover display | a small window, no features | phone layout (Flip cover 360x374 is a known gap) |
| Unfolded, flat | one window, no feature (or a flat fold with no gap) | continuous display: tablet class, picture over chat |
| Book / dual screen | `hinge` (any state), vertical | video left, chat right, hinge empty; each pane is its own window |
| Tabletop / laptop | `fold` + `postureHalfOpened`, horizontal | picture in the upper pane, transport + chat in the lower |
| Half-opened, vertical | `fold` + `postureHalfOpened`, vertical | as book posture |
| Dual screen turned | `hinge`, horizontal | as tabletop |

Anything that is not the room takes one pane (`PTHingeSafe`); dialogs and popovers land in the pane they opened from.

## Testing

- Software: `fvm flutter test test/layout` renders every screen and dialog over `kScreenMatrix`, which has Fold book/tabletop/unfolded/cover, a Surface Duo-like dual screen in both orientations, Pixel Fold, a half-opened vertical fold and Flip unfolded/cover. `--dart-define=SCREENSHOTS=true` writes PNGs to `build/screenshots/`. Room fold tests: "room on a fold" and "fold -> unfold -> fold" in `room_screen_matrix_test.dart` (video surface identity, draft survives, transport hittable on every frame of a resize).
- Android emulator: create a *Pixel Fold* or *Resizable* AVD (needs `cmdline-tools`), run it with `-memory 3072`, and use the extended controls' Posture tab. `adb shell wm size 1080x960` resizes a plain AVD (no hinge), `adb shell cmd window` has no posture command - hinge geometry only comes from a foldable AVD.
- iOS: iPad Split View and Stage Manager exercise the same window-size path; there is no folding-iPhone simulator, so nothing here is specific to one.

## What only real hardware confirms

Hinge feel and the real hinge width; posture-sensor timing (how many frames between the fold angle changing and `displayFeatures` updating); whether the keyboard covers one screen or both on a dual screen; multi-window and drag-to-resize quirks; the Flip cover launcher's app allow-list; the room under a real unfold with video playing (no stutter, no restart).
