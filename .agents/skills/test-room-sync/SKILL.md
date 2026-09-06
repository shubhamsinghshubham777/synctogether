---
name: test-room-sync
description: >-
  Run dual macOS client instances to test synchronized media playback, room chat, reactions, and readiness gating on a single machine. Use when the user asks to "test sync locally", "run two instances", "test multi-client playback", or execute `./scripts/st-instance-b.sh`.
---

# Dual-Instance Room Sync Testing

Testing real-time synchronization between two participants on a single Mac requires two distinct app identities with separated preference domains (`NSUserDefaults` and `flutter_secure_storage`).

## Steps to Test

1. **Build & Run Instance A (Host)**:
   ```bash
   fvm flutter run -d macos
   ```
   Sign in (or join as Guest) and create a room.

2. **Launch Instance B (Participant)**:
   In a separate terminal:
   ```bash
   ./scripts/st-instance-b.sh
   ```
   This script clones the debug `.app` bundle under a secondary bundle ID (`app.synctogether.b`) to ensure an isolated Supabase session, strips restricted entitlements that would cause ad-hoc AMFI spawn failures, and launches Instance B. Pass `--build` to force a debug rebuild first if needed.

3. **Verify Sync Interactions**:
   - Copy the 6-character room code or invite URL from Instance A and join from Instance B.
   - Test Play, Pause, Scrubbing, Readiness Gate overlays, and Quick Reactions.

> [!NOTE]
> Whenever you recompile the Flutter app, re-run `./scripts/st-instance-b.sh` so Instance B receives the new binary.
