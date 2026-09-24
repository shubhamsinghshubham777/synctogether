#!/usr/bin/env python3

import hashlib
import json
import pathlib
import re
import ssl
import sys
import urllib.request

# Pinned sources. Unicode's emoji list decides *what* the picker offers; CLDR's
# English annotations decide what a search for it matches. CLDR 45 is the
# release that pairs with Emoji 15.1.
SOURCES = {
    "emoji-test": (
        "https://www.unicode.org/Public/emoji/15.1/emoji-test.txt",
        "d876ee249aa28eaa76cfa6dfaa702847a8d13b062aa488d465d0395ee8137ed9",
    ),
    "annotations": (
        "https://cdn.jsdelivr.net/npm/cldr-annotations-full@45.0.0/annotations/en/annotations.json",
        "a9554de7f8fe295aeb4b4ca615ec787e0cf74c017e8027f96a45e9ed2ff87366",
    ),
    "derived": (
        "https://cdn.jsdelivr.net/npm/cldr-annotations-derived-full@45.0.0/annotationsDerived/en/annotations.json",
        "c0dec40a8e903c74fab96d7509d55b7e0e368473858d771b93e5622388393c48",
    ),
}

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEST = ROOT / "lib" / "rooms" / "emoji" / "emoji_data.g.dart"

USAGE = """\
Regenerates lib/rooms/emoji/emoji_data.g.dart - the chat emoji picker's list,
names, search keywords and skin-tone variants. The .dart file is build output:
edit this script, never it.

    python3 tool/generate_emoji_data.py
    python3 tool/generate_emoji_data.py --print-digests

Sources are Unicode's emoji-test.txt (the fully-qualified set, in Unicode's own
order) and CLDR's English annotations, each checked against the SHA-256 pinned in
SOURCES. A mismatch aborts without writing. Bumping the Emoji version means new
URLs *and* new pins: run --print-digests, then paste them in. The per-platform
version caps in emoji_logic.dart decide which of the new emoji a given OS font
can actually draw - raise those separately, once the fonts ship them.

Skin-tone variants are folded into their base: the picker shows one cell and
offers the tones on long-press. Only *uniform* variants are kept (one tone for
the whole sequence), which is what a single remembered tone can express.
"""

TONES = ["light", "medium-light", "medium", "medium-dark", "dark"]
TONE_SUFFIX = re.compile(r"^(.*): (" + "|".join(TONES) + r") skin tone$")

GROUP_IDS = {
    "Smileys & Emotion": "smileys",
    "People & Body": "people",
    "Animals & Nature": "nature",
    "Food & Drink": "food",
    "Travel & Places": "travel",
    "Activities": "activities",
    "Objects": "objects",
    "Symbols": "symbols",
    "Flags": "flags",
}

LINE = re.compile(r"^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*(\S+)\s+E(\d+\.\d+)\s+(.+)$")


def fetch(url: str) -> bytes:
    # The repo's own Mozilla bundle, so a python.org install with no system
    # roots wired up (the macOS framework build) still verifies TLS.
    context = ssl.create_default_context(cafile=ROOT / "assets" / "ca" / "cacert.pem")
    with urllib.request.urlopen(url, timeout=60, context=context) as response:
        return response.read()


def dart_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")
    return f"'{escaped}'"


def strip_vs(value: str) -> str:
    return value.replace("️", "")


def main() -> int:
    if "-h" in sys.argv or "--help" in sys.argv:
        print(USAGE)
        return 0

    blobs = {}
    failed = False
    for key, (url, pin) in SOURCES.items():
        data = fetch(url)
        digest = hashlib.sha256(data).hexdigest()
        blobs[key] = data
        if "--print-digests" in sys.argv:
            print(f"{key}: {digest}  ({len(data)} bytes)")
        elif digest != pin:
            print(f"{key}: digest mismatch\n  pinned  {pin}\n  fetched {digest}", file=sys.stderr)
            failed = True
    if "--print-digests" in sys.argv:
        return 0
    if failed:
        print("Refusing to write. Re-pin deliberately (see --help).", file=sys.stderr)
        return 1

    keywords = {}
    for key in ("annotations", "derived"):
        tree = json.loads(blobs[key])
        root = tree.get("annotations") or tree.get("annotationsDerived")
        for char, entry in root["annotations"].items():
            words = entry.get("default", []) + entry.get("tts", [])
            keywords.setdefault(strip_vs(char), [])
            for word in words:
                word = word.lower().strip()
                if word and word not in keywords[strip_vs(char)]:
                    keywords[strip_vs(char)].append(word)

    groups = {}
    order = []
    group = None
    bases = {}
    for raw in blobs["emoji-test"].decode("utf-8").splitlines():
        if raw.startswith("# group:"):
            name = raw.split(":", 1)[1].strip()
            group = GROUP_IDS.get(name)
            if group and group not in groups:
                groups[group] = (name, [])
                order.append(group)
            continue
        if group is None:
            continue
        match = LINE.match(raw)
        if not match:
            continue
        char, version, name = match.group(2), match.group(3), match.group(4)
        # emoji-test.txt carries the literal characters in the comment, but a
        # few fonts print them oddly - rebuild from the codepoints instead.
        char = "".join(chr(int(cp, 16)) for cp in match.group(1).split())
        tone = TONE_SUFFIX.match(name)
        if tone:
            base = bases.get(tone.group(1))
            if base is not None:
                base["tones"][TONES.index(tone.group(2))] = char
            continue
        if "skin tone" in name:
            # Mixed-tone sequences (two people, two tones) cannot be reached
            # from one remembered tone.
            continue
        entry = {"char": char, "name": name, "version": version, "tones": [None] * 5}
        bases[name] = entry
        groups[group][1].append(entry)

    total = 0
    lines = [
        "// GENERATED by tool/generate_emoji_data.py - do not edit by hand.",
        "// Source: Unicode Emoji 15.1 emoji-test.txt + CLDR 45 English annotations.",
        "",
        "import 'emoji_models.dart';",
        "",
        "const kEmojiGroups = <EmojiGroup>[",
    ]
    for group in order:
        label, entries = groups[group]
        lines.append(f"  EmojiGroup({dart_string(group)}, {dart_string(label)}, [")
        for entry in entries:
            words = [w for w in keywords.get(strip_vs(entry["char"]), []) if w != entry["name"]]
            tones = entry["tones"]
            toned = ""
            if all(tones):
                toned = ", tones: [" + ", ".join(dart_string(t) for t in tones) + "]"
            lines.append(
                f"    EmojiEntry({dart_string(entry['char'])}, {dart_string(entry['name'])}, "
                f"{dart_string(' '.join(words))}, {entry['version']}{toned}),"
            )
            total += 1
        lines.append("  ]),")
    lines.append("];")
    lines.append("")

    DEST.parent.mkdir(parents=True, exist_ok=True)
    DEST.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {total} emoji in {len(order)} groups to {DEST.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
