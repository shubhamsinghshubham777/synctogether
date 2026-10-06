---
name: moderation
description: >-
  Review, triage, and take action on user content reports and copyright/piracy complaints in SyncTogether. Use when the user asks to "review complaints", "check reported rooms", "moderate reports", "ban pirated room", or inspect open moderation queues.
---

# Anti-Piracy & Content Moderation

SyncTogether provides an end-to-end moderation system allowing human reviewers and AI agents (Antigravity & Claude Code) to review user-reported copyright infringements and malicious behavior, and execute administrative enforcement.

## Enforcement Doctrine

1. **Room Enforcement**:
   - Pirated or infringing rooms can be terminated immediately by calling `admin_ban_room`.
   - Banning a room evicts all members via Realtime broadcast `room_banned`, enqueues Cloudflare R2 media files for permanent deletion, and marks the room `is_banned = true`.

2. **User Enforcement (2-Strike Policy)**:
   - **Strike 1 (Warning)**: Issued via `admin_warn_user`. Increments user strike count to 1, sets `moderation_status = 'warned'`, and triggers a blocking in-app acknowledgment dialog.
   - **Strike 2 (Indefinite Ban)**: Calling `admin_warn_user` on a user with 1 strike automatically escalates to `admin_ban_user`. Alternatively, direct bans can be issued for severe violations.
   - Banned accounts are permanently blocked from creating rooms, joining rooms, or uploading media, and are routed to `/banned`.

## Moderation CLI

Agents can run the moderation tool directly:

```bash
# List open reports
node scripts/moderate.ts list open

# Inspect a specific report dossier
node scripts/moderate.ts inspect <report-id>

# Issue Strike 1 warning
node scripts/moderate.ts warn <user-id> --reason="Copyright infringement: streaming unauthorized commercial release" --report-id="<report-id>"

# Ban and terminate a room immediately
node scripts/moderate.ts ban-room <room-id> --reason="Pirated media stream" --report-id="<report-id>"

# Ban account indefinitely
node scripts/moderate.ts ban-user <user-id> --reason="Repeat copyright infringement" --report-id="<report-id>"

# Dismiss report
node scripts/moderate.ts dismiss <report-id> --notes="No infringement found"

# Record AI evaluation
node scripts/moderate.ts triage <report-id> --score=95 --action=ban_room_and_warn_user --reason="Scene pirated release filename"
```
