#!/usr/bin/env python3
"""Render per-store listing copy from store/copy/en-US.json.

  python3 scripts/store-copy.py            # drafts into store/copy/out/
  python3 scripts/store-copy.py --check    # fail if limits are broken or live files drifted
  python3 scripts/store-copy.py --apply    # overwrite metadata/ and store/ios/ (never pushes)

What's New stays in metadata/version/X.Y.Z (per release); this script leaves it alone.
"""
import json, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = json.loads((ROOT / "store/copy/en-US.json").read_text(encoding="utf-8"))
LIMITS = {"name": 30, "subtitle": 30, "promotionalText": 170, "description": 4000}


def body(platform, store):
    s = SRC
    fill = {"own_video": s["own_video"][platform], "sign_in": s["sign_in"][platform]}
    parts = [s["hook"], s["platform_line"][platform], "KEY FEATURES"]
    for p in s["pillars"]:
        parts.append("• %s\n%s" % (p["title"], p["body"].format(**fill)))
    parts.append(s["free_to_start"])
    patron = s["patron"] + " " + s["billing"]["microsoft" if store == "microsoft" else "apple"]
    parts.append(patron)
    if store == "microsoft":
        parts.insert(-2, s["windows_tiers"])
    parts.append(s["legal"])
    return "\n\n".join(parts)


def render():
    out = {}
    for plat in ("mac", "ios"):
        out[plat] = {
            "description": body(plat, "apple"),
            "keywords": SRC["keywords"][plat],
            "promotionalText": SRC["promo"][plat],
        }
    out["windows"] = {
        "Description": body("windows", "microsoft"),
        "Keywords": SRC["keywords"]["windows"],
        "Features": SRC["windows_features"],
        "ShortDescription": SRC["windows_short_description"],
    }
    return out


def problems(out):
    bad = []
    for plat in ("mac", "ios"):
        o = out[plat]
        if len(o["description"]) > LIMITS["description"]:
            bad.append(f"{plat} description {len(o['description'])}>4000")
        if len(o["promotionalText"]) > LIMITS["promotionalText"]:
            bad.append(f"{plat} promo {len(o['promotionalText'])}>170")
        if len(o["keywords"].encode()) > 100:
            bad.append(f"{plat} keywords {len(o['keywords'].encode())}B>100")
    if len(SRC["name"]) > 30 or len(SRC["subtitle"]) > 30:
        bad.append("name/subtitle over 30")
    w = out["windows"]
    if len(w["Keywords"]) > 7:
        bad.append("windows keywords >7")
    if len(w["Description"]) > 10000:
        bad.append("windows description >10000")
    if len(w["Features"]) > 20:
        bad.append("windows features >20")
    for t in ("Premium", "frame-perfect", "frame-accurate", "60-minute extension"):
        for k, o in out.items():
            if t.lower() in json.dumps(o).lower():
                bad.append(f"{k} contains banned term '{t}'")
    return bad


NOTE_RE = __import__("re").compile(r"^\u2022 [A-Z0-9&' -]{2,24}: [^\n]{8,100}$")


def check_notes():
    """What's New: 2-4 one-line '• TITLE: text' bullets, no headings, <= 400 chars,
    and the Mac and Microsoft texts identical (platform-specific releases may
    differ; edit this check deliberately if so)."""
    bad = []
    files = live_files()
    mac = json.loads(files["mac"].read_text(encoding="utf-8"))["whatsNew"]
    win = json.loads(files["windows"].read_text(encoding="utf-8"))["ReleaseNotes"]
    for name, t in (("Mac whatsNew", mac), ("Microsoft ReleaseNotes", win)):
        lines = t.split("\n")
        if not 2 <= len(lines) <= 4:
            bad.append(f"{name}: {len(lines)} lines, want 2-4 bullets")
        if len(t) > 400:
            bad.append(f"{name}: {len(t)} chars, want <= 400")
        for ln in lines:
            if not NOTE_RE.match(ln):
                bad.append(f"{name}: bad bullet {ln!r} (want '\u2022 TITLE: one short sentence')")
    if mac != win:
        bad.append("Mac whatsNew and Microsoft ReleaseNotes differ")
    return bad


def live_files():
    ver = sorted((ROOT / "metadata/version").iterdir(), key=lambda p: [int(x) for x in p.name.split(".")])[-1]
    return {
        "mac": ver / "en-US.json",
        "ios": ROOT / "store/ios/listing_en-US.json",
        "windows": ROOT / "metadata/msstore_listing_en-US.json",
    }


def drift(out):
    bad = []
    for k, f in live_files().items():
        live = json.loads(f.read_text(encoding="utf-8"))
        for key, want in out[k].items():
            if live.get(key) != want:
                bad.append(f"{f.relative_to(ROOT)}: '{key}' differs from store/copy/en-US.json (run --apply)")
    return bad


def apply(out):
    ver = sorted((ROOT / "metadata/version").iterdir(), key=lambda p: [int(x) for x in p.name.split(".")])[-1]
    f = ver / "en-US.json"
    m = json.loads(f.read_text(encoding="utf-8"))
    m.update(out["mac"])
    f.write_text(json.dumps(m, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (ROOT / "metadata/app-info/en-US.json").write_text(json.dumps({
        "name": SRC["name"], "subtitle": SRC["subtitle"],
        "privacyPolicyUrl": "https://synctogether.app/privacy"}, ensure_ascii=False) + "\n", encoding="utf-8")
    f = ROOT / "store/ios/listing_en-US.json"
    i = json.loads(f.read_text(encoding="utf-8"))
    i.update(out["ios"]); i["name"] = SRC["name"]; i["subtitle"] = SRC["subtitle"]
    f.write_text(json.dumps(i, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    f = ROOT / "metadata/msstore_listing_en-US.json"
    w = json.loads(f.read_text(encoding="utf-8"))
    w.update(out["windows"])
    f.write_text(json.dumps(w, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main():
    out = render()
    bad = problems(out)
    for b in bad:
        print("PROBLEM:", b)
    if "--check" in sys.argv:
        bad += drift(out) + check_notes()
        for b in bad:
            print("CHECK:", b)
        sys.exit(1 if bad else 0)
    if bad:
        sys.exit(1)
    if "--apply" in sys.argv:
        apply(out)
        print("applied to live files (not pushed)")
        return
    d = ROOT / "store/copy/out"
    d.mkdir(exist_ok=True)
    for k, v in out.items():
        (d / f"{k}.json").write_text(json.dumps(v, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("drafts in store/copy/out/")


if __name__ == "__main__":
    main()
