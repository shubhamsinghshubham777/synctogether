#!/usr/bin/env python3
"""Device-verification gate: no app code is committed untested on iOS, macOS and Android.

CLAUDE.md makes this a standing rule for every AI agent (and human) working here:
code that changes the app must be run on every platform this OS can run (the iOS
simulator, the macOS app, an Android emulator) before it is committed. This script
is how that is recorded and enforced.

    stage your change, run it on each platform, then:
    scripts/device-verify.py record \
        --ios "what you ran on the simulator and what you saw" \
        --macos "..." --android "..."
    # a platform that genuinely cannot be tested here (and the owner was told):
    scripts/device-verify.py record --ios "..." --macos "..." \
        --blocked android="emulator will not boot: <the real reason>"
    scripts/device-verify.py check      # what .githooks/pre-commit runs

The record is bound to a hash of the staged app-code diff, so editing the code
afterwards invalidates it and the testing has to be repeated. It lives in the
git dir (per clone, never committed). It is a forcing function, not proof: the
evidence text is read by whoever reviews the commit, so it must say what was
actually driven and observed, never "tested" alone.
"""

import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
from pathlib import Path

PLATFORMS = ("ios", "macos", "android")
# What counts as app code. Tests, docs, website and supabase have their own suites.
SCOPE = ["lib", "ios", "macos", "android", "pubspec.yaml"]
MIN_EVIDENCE = 25


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def is_version_bump_only(diff: str) -> bool:
    """A release bump: the only change in scope is pubspec.yaml's `version:` line.

    It changes no behaviour a device run could check, and the release skill makes
    one every release, so it needs no record.
    """
    changed = [
        line
        for line in diff.splitlines()
        if line[:1] in "+-" and not line.startswith(("+++", "---"))
    ]
    files = {
        line[len("diff --git a/") :].split(" ")[0]
        for line in diff.splitlines()
        if line.startswith("diff --git a/")
    }
    return (
        files == {"pubspec.yaml"}
        and len(changed) == 2
        and all(re.fullmatch(r"[+-]version: \d+\.\d+\.\d+", line) for line in changed)
    )


def staged_hash() -> str | None:
    diff = git("diff", "--cached", "--", *SCOPE)
    if not diff.strip() or is_version_bump_only(diff):
        return None
    return hashlib.sha256(diff.encode()).hexdigest()


def stamp_path() -> Path:
    return Path(git("rev-parse", "--git-dir").strip()) / "device-verified.json"


def record(args: argparse.Namespace) -> int:
    digest = staged_hash()
    if digest is None:
        print("Nothing staged under lib/, ios/, macos/, android/ or pubspec.yaml: nothing to record.")
        return 0
    entries: dict[str, dict[str, str]] = {}
    for p in PLATFORMS:
        text = getattr(args, p)
        if text:
            entries[p] = {"status": "ran", "evidence": text.strip()}
    for item in args.blocked or []:
        name, _, reason = item.partition("=")
        if name not in PLATFORMS or not reason.strip():
            print(f"--blocked needs platform=reason with platform in {PLATFORMS}: {item!r}")
            return 2
        entries[name] = {"status": "blocked", "evidence": reason.strip()}
    problems = validate(entries)
    if problems:
        print("Not recorded:\n  " + "\n  ".join(problems))
        return 2
    stamp_path().write_text(
        json.dumps({"hash": digest, "at": int(time.time()), "platforms": entries}, indent=2)
    )
    print(f"Recorded device verification for the staged change ({digest[:10]}).")
    for p, e in entries.items():
        print(f"  {p}: {e['status']} - {e['evidence'][:100]}")
    return 0


def validate(entries: dict[str, dict[str, str]]) -> list[str]:
    out = []
    for p in PLATFORMS:
        e = entries.get(p)
        if e is None:
            out.append(f"{p}: not recorded. Run it there, or pass --blocked {p}=<real reason>.")
        elif len(e["evidence"]) < MIN_EVIDENCE:
            out.append(f"{p}: say what you actually drove and saw (>= {MIN_EVIDENCE} characters).")
    return out


def check(_: argparse.Namespace) -> int:
    digest = staged_hash()
    if digest is None:
        return 0
    path = stamp_path()
    fail = (
        "\nDEVICE VERIFICATION REQUIRED (CLAUDE.md, standing rule)\n"
        "App code is staged but has not been run on iOS, macOS and Android.\n"
        "Run the change on each platform this machine can run (iOS simulator, the\n"
        "macOS app, an Android emulator), look at the result, then record it:\n\n"
        '  scripts/device-verify.py record --ios "<what you drove and saw>" \\\n'
        '      --macos "<...>" --android "<...>"\n\n'
        "Only a platform that truly cannot be tested here may use\n"
        "  --blocked <platform>=<the real reason>\n"
        "and the owner must have been told. Editing the staged code afterwards\n"
        "invalidates the record. Do not bypass this hook.\n"
    )
    if not path.exists():
        print(fail + "\nNo record exists for this clone yet.")
        return 1
    data = json.loads(path.read_text())
    if data.get("hash") != digest:
        print(fail + "\nThe record is for different code than what is staged now.")
        return 1
    problems = validate(data.get("platforms", {}))
    if problems:
        print(fail + "\n" + "\n".join(problems))
        return 1
    for p, e in data["platforms"].items():
        print(f"    device check {p}: {e['status']}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    rec = sub.add_parser("record")
    for p in PLATFORMS:
        rec.add_argument(f"--{p}", help=f"what you ran on {p} and what you saw")
    rec.add_argument("--blocked", action="append", help="platform=reason (cannot be tested here)")
    rec.set_defaults(fn=record)
    chk = sub.add_parser("check")
    chk.set_defaults(fn=check)
    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
