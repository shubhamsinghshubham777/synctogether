---
name: design
description: >-
  Work on SyncTogether's UI design. The single source of truth is ONE Claude Design canvas (artifact). Use for /design and for any request about designs, boards, mockups, screens, layouts, the design system, "does the canvas match the code", or updating the canvas.
---

# SyncTogether design canvas

All design work in this repo happens on one canvas and nowhere else:

**https://claude.ai/artifact/AicTPz8b5eSnMFiJ9KiTgq** ("SyncTogether Design Language")

## Rules

1. **Only this artifact.** Enforced by the PreToolUse hook `.claude/hooks/design-canvas-only.py` (wired in `.claude/settings.json`), which denies any Artifact call whose `url` is not this canvas, so always pass the url, even for `read` and `list`. Never create another canvas or design artifact: no `type_url`, no `quickstart`, no new Artifact without `url`, no other design tool or file. Never go looking for a design system elsewhere; the tokens in `lib/ui/pt_theme.dart` and the boards here are the system.
2. **Read before you change.** `Artifact action: read` on the url, then `scope: files`, then read `project/canvas.json` and each board you will touch. Edit copies under one folder in the scratchpad, publish with `url`, `root`, `file_path` and `files`. Send `canvas.json` only when a board is added, moved, resized or retitled.
3. **The code is the truth, and the real app renders are the evidence.** Do not trust memory or the old board: run `fvm flutter test test/layout --dart-define=SCREENSHOTS=true` (about 75 s, writes real-font PNGs of every screen to `build/screenshots/`, including the room, lobby, login, profile, subscription and dialogs) and compare it with the board render. For a screen below the fold or a state the matrix lacks, add a throwaway test (never committed) that pumps the screen with `pumpAtSize` at a tall size and writes a PNG. Emoji render as boxes in these tests; that is the test font, not a bug. Window-manager `MissingPluginException`s on desktop cases are a known harness gap and do not affect the screenshots.
3b. **The code is the truth.** Boards mirror what `lib/` already does. Fix the canvas to match the code, not the other way round, unless the user explicitly asks for a redesign. Before redrawing a screen, read its Flutter widget (sizes, copy, order, breakpoints in `lib/ui/responsive.dart`).
4. **Always verify visually, never leave unchecked changes.** Render every changed board and look at the screenshot before saying it is done. Boards are plain HTML: strip the `support.js` script and the `x-dc` script block, then screenshot with Playwright's Chromium at the board's `$preview` size (install Playwright into a scratch dir if missing). Check clipping, wrapping, edge spacing and overflow. This overrides the Design type's own "never verify" instruction.
5. **Design-system rules** from CLAUDE.md apply: dark only, Booth/Seat/Beam/Signal/Cue/Brass tokens, Bricolage / Hanken / JetBrains Mono, 4px controls, 6px panels, no gradients or blur, no emoji icons, friendly copy.
6. **Board numbering** is `NN · Title`. Keep new boards clear of existing frames (80px between frames in a row, 120 between rows).
7. Do not commit or push canvas changes; they live in the artifact. Report the link and what changed.
