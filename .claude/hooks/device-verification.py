#!/usr/bin/env python3
"""PreToolUse(Bash) guard for the device-verification rule in CLAUDE.md.

Two things are refused before a command runs:
  * a real `git commit` while staged app code has no matching device-verification
    record (the same check .githooks/pre-commit makes, surfaced early and with
    the instructions in front of the agent);
  * any way around the git hooks: `--no-verify` or `-n` on a real `git commit`,
    or pointing core.hooksPath somewhere other than .githooks.

Only shell segments that actually *start* with `git ... commit` / `git config`
are inspected, so prose that merely mentions those words (a commit message, a
document being written) is never mistaken for the command.
"""

import json
import re
import shlex
import subprocess
import sys

data = json.load(sys.stdin)
cmd = (data.get("tool_input") or {}).get("command", "")


def deny(reason: str) -> None:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            }
        )
    )
    sys.exit(0)


def git_invocations(command: str):
    """Yield (subcommand, argv, global options) for every shell segment that starts with git."""
    for segment in re.split(r"(?:&&|\|\||[;&|\n])", command):
        segment = segment.strip()
        # Drop leading VAR=value assignments and an `env` prefix.
        try:
            words = shlex.split(segment, posix=True)
        except ValueError:
            continue
        while words and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]) or words[0] == "env"):
            words.pop(0)
        if not words or words[0] != "git":
            continue
        rest = words[1:]
        # Skip git's own global options (-C <dir>, -c k=v, --no-pager ...).
        i = 0
        while i < len(rest) and rest[i].startswith("-"):
            i += 2 if rest[i] in ("-C", "-c") else 1
        if i < len(rest):
            yield rest[i], rest[i + 1 :], rest[:i]


is_commit = False
for sub, argv, opts in git_invocations(cmd):
    if any("core.hookspath" in o.lower() for o in opts):
        deny("core.hooksPath must stay .githooks: it carries the device-verification gate.")
    if sub == "commit":
        is_commit = True
        flags = [a for a in argv if a.startswith("-")]
        if "--no-verify" in flags or "-n" in flags:
            deny(
                "Bypassing the commit hooks is not allowed in this repository: they "
                "enforce format, analyze, tests and the device-verification rule in CLAUDE.md."
            )
    if sub == "config" and "core.hooksPath" in argv:
        if ".githooks" not in argv:
            deny("core.hooksPath must stay .githooks: it carries the device-verification gate.")

if is_commit:
    r = subprocess.run(
        ["python3", "scripts/device-verify.py", "check"], capture_output=True, text=True
    )
    if r.returncode != 0:
        deny(r.stdout.strip() or "Device verification is required before committing app code.")
