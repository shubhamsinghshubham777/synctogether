#!/usr/bin/env python3
"""PreToolUse hook for the Artifact tool: design work may only touch the one canvas.

Blocks any Artifact call that does not target the SyncTogether Design Language
canvas (new artifacts, other urls, quickstart, type listings, deletes of other
artifacts). See .claude/skills/design/SKILL.md.
"""
import json
import sys

CANVAS_ID = "AicTPz8b5eSnMFiJ9KiTgq"
CANVAS_URL = f"https://claude.ai/artifact/{CANVAS_ID}"

data = json.load(sys.stdin)
url = str((data.get("tool_input") or {}).get("url") or "")

if CANVAS_ID in url:
    sys.exit(0)

print(
    json.dumps(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": (
                    "This repo's design work happens only on the single canvas "
                    f"{CANVAS_URL}. Pass that url on every Artifact call; do not create or "
                    "touch any other artifact (see .claude/skills/design/SKILL.md)."
                ),
            }
        }
    )
)
