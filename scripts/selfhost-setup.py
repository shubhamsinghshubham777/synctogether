#!/usr/bin/env python3
"""
SyncTogether self-hosting setup wizard
======================================

Walks you through everything docs/self-hosting.md asks for, in one sitting:

  1. who you are (the Terms, Privacy and DMCA pages name the operator - that is you),
  2. where your backend, website and (optionally) LiveKit server and file storage live,
  3. how people sign in,

then writes the config files for you, generates your auth config and the one-off SQL,
and prints the exact commands left to run, in order, for YOUR answers. Finally it can
run scripts/selfhost-verify.py, which is the only thing that can tell you it all works.

  python3 scripts/selfhost-setup.py                   # interactive
  python3 scripts/selfhost-setup.py --answers a.json  # repeatable / scripted (see the keys below)
  python3 scripts/selfhost-setup.py --out-dir /tmp/x --no-config   # write somewhere else, skip the CLI-facing step

It is safe to run again: your earlier answers are read back as the defaults, and an
existing file is only replaced after it has been backed up (<file>.bak.<timestamp>).
Files that hold secrets are written with mode 600 and are all git-ignored. Standard
library only. Secrets are typed hidden and are never printed.

This is not legal advice: the wizard fills in the operator's details, but the Terms
and Privacy texts are templates for the project's own deployment. Have a lawyer read
them before you publish a site that collects other people's data.
"""
from __future__ import annotations

import argparse
import getpass
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
COLOR = sys.stdout.isatty()


def c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if COLOR else text


# ------------------------------------------------------------------ validation


def v_url(value: str) -> str | None:
    return None if re.fullmatch(r"https?://[^\s/]+(:\d+)?", value) else "an origin like https://watch.example.com (no path, no trailing slash)"


def v_https(value: str) -> str | None:
    return None if re.fullmatch(r"https://[^\s/]+(:\d+)?", value) else "an https origin like https://watch.example.com"


def v_email(value: str) -> str | None:
    return None if re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value) else "an email address like help@example.com"


def v_wss(value: str) -> str | None:
    return None if re.fullmatch(r"wss?://[^\s/]+(:\d+)?", value) else "a LiveKit URL like wss://av.example.com"


def v_nonempty(value: str) -> str | None:
    return None if value.strip() else "a value"


def v_reg(value: str) -> str | None:
    return None if re.fullmatch(r"DMCA-\d+", value) else "a registration number like DMCA-1234567, or leave it empty"


# --------------------------------------------------------------------- the questions


@dataclass
class Q:
    key: str
    prompt: str
    help: str = ""
    required: bool = True
    secret: bool = False
    validate: object = None
    default: str = ""
    multiline: bool = False
    when: object = None  # callable(answers) -> bool


@dataclass
class Step:
    title: str
    intro: str
    questions: list = field(default_factory=list)


def has(key):
    return lambda a: a.get(key) in ("y", "yes", "true", True)


def is_(key, *values):
    return lambda a: a.get(key) in values


STEPS: list[Step] = [
    Step("1. You", "The legal pages of your website name whoever runs the service. That is you.", [
        Q("operator_name", "Your name or company", "Shown on the Terms, Privacy, DMCA pages and the footer.", validate=v_nonempty),
        Q("operator_address", "Your postal address", "A copyright notice has to be sendable to a real address. One line per prompt; an empty line ends it.", multiline=True, validate=v_nonempty),
        Q("governing_law", "Country whose law governs your Terms", "A legal choice - confirm it with a lawyer.", validate=v_nonempty),
        Q("support_email", "Support email", "Where reports, appeals and user questions go.", validate=v_email),
        Q("copyright_email", "Copyright (DMCA) email", "Where takedown notices go. Defaults to your support email.", validate=v_email),
        Q("dmca_registration", "U.S. Copyright Office DMCA agent registration number", "Leave EMPTY unless you registered an agent: the DMCA page only claims a registered agent when this is set.", required=False, validate=v_reg),
        Q("operator_url", "A page about you (shown as a link in the footer)", "Optional - a homepage or profile.", required=False, validate=v_url),
        Q("operator_twitter", "Your X/Twitter handle", "Optional, with the @ - used on link-preview cards.", required=False, validate=lambda v: None if re.fullmatch(r"@\w{1,15}", v) else "a handle like @yourname"),
    ]),
    Step("2. Where it lives", "Three addresses. You can put placeholders now and re-run the wizard later; it remembers.", [
        Q("site_url", "Your web portal's address", "Invite links, the Terms/Privacy pages and the Google sign-in bridge live here. Deploy website/ at this origin.", validate=v_https),
        Q("supabase_url", "Your Supabase API address", "Supabase Cloud: https://<project-ref>.supabase.co. Self-hosted: https://api.yourdomain.com (the Kong gateway behind TLS).", validate=v_https),
        Q("supabase_hosting", "Is that Supabase Cloud or your own Docker stack? (cloud/docker)", "Decides which commands you are given for the database and the auth settings.", default="cloud", validate=lambda v: None if v in ("cloud", "docker") else "cloud or docker"),
        Q("supabase_publishable_key", "Supabase publishable (anon) key", "Project Settings -> API. Safe to ship in the app.", validate=v_nonempty),
        Q("supabase_service_role_key", "Supabase service-role key", "Project Settings -> API. SECRET. Only written to website/.env.local (git-ignored) - the website's server needs it. Never goes in the app.", secret=True, validate=v_nonempty),
        Q("has_stores", "Do you publish the client app in the App Store / Microsoft Store? (y/n)", "If not, the site's download buttons lead to your own /download page.", default="n"),
        Q("app_store_url", "Your Mac App Store listing URL", "", required=False, validate=v_url, when=has("has_stores")),
        Q("microsoft_store_url", "Your Microsoft Store listing URL", "", required=False, validate=v_url, when=has("has_stores")),
    ]),
    Step("3. Sign-in", "Guests and email codes always work. These are the extras.", [
        Q("captcha", "Protect guest sign-in with Cloudflare Turnstile? (y/n)", "Recommended on a public server: without it a bot can create unlimited guests. Needs a free Turnstile widget (add localhost to its hostnames).", default="y"),
        Q("turnstile_site_key", "Turnstile SITE key", "Public key, goes in the app and the website.", validate=v_nonempty, when=has("captcha")),
        Q("turnstile_secret", "Turnstile SECRET key", "Goes only to supabase/.env.", secret=True, validate=v_nonempty, when=has("captcha")),
        Q("google", "Offer Google sign-in? (y/n)", "Needs a Google Cloud OAuth web client with the redirect <supabase-url>/auth/v1/callback.", default="n"),
        Q("google_client_id", "Google OAuth client ID", "", validate=v_nonempty, when=has("google")),
        Q("google_client_secret", "Google OAuth client secret", "", secret=True, validate=v_nonempty, when=has("google")),
    ]),
    Step("4. Voice and video", "Facecams use a LiveKit server. Skip it and the app simply hides them.", [
        Q("av", "Voice/video: (cloud / own / none)", "cloud = LiveKit Cloud's free tier; own = a server you run (scripts/setup-livekit-server.sh does it on a fresh Ubuntu VPS); none = no facecams.", default="none", validate=lambda v: None if v in ("cloud", "own", "none") else "cloud, own or none"),
        Q("livekit_url", "LiveKit address", "wss://... - from LiveKit Cloud's settings, or your server's domain. If your own server is not up yet, leave it empty: the wizard tells you how to build it and you re-run this after.", required=False, validate=v_wss, when=is_("av", "cloud", "own")),
        Q("livekit_key", "LiveKit API key", "", required=False, validate=v_nonempty, when=is_("av", "cloud", "own")),
        Q("livekit_secret", "LiveKit API secret", "SECRET - goes only to supabase/functions/.env.", secret=True, required=False, validate=v_nonempty, when=is_("av", "cloud", "own")),
    ]),
    Step("5. Shared files", "Lets a host upload a video so members without a copy can stream it. Any S3-compatible bucket (Cloudflare R2 is cheap).", [
        Q("r2", "Enable shared files? (y/n)", "", default="n"),
        Q("r2_endpoint", "Bucket endpoint", "e.g. https://<account-id>.r2.cloudflarestorage.com", validate=v_https, when=has("r2")),
        Q("r2_bucket", "Bucket name", "", validate=v_nonempty, when=has("r2")),
        Q("r2_access_key", "Access key ID", "", validate=v_nonempty, when=has("r2")),
        Q("r2_secret_key", "Secret access key", "SECRET - goes only to supabase/functions/.env.", secret=True, validate=v_nonempty, when=has("r2")),
    ]),
]

ALL_KEYS = [q.key for s in STEPS for q in s.questions]


# --------------------------------------------------------------------------- IO


def parse_env_file(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        v = v.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            quote, v = v[0], v[1:-1]
            if quote == '"':
                v = v.replace('\\"', '"').replace("\\\\", "\\")
        out[k.strip()] = v
    return out


def remembered(out_dir: Path) -> dict[str, str]:
    """Earlier answers, recovered from the files this wizard wrote, as defaults."""
    cl = parse_env_file(out_dir / ".env")
    sb = parse_env_file(out_dir / "supabase" / ".env")
    fn = parse_env_file(out_dir / "supabase" / "functions" / ".env")
    web = parse_env_file(out_dir / "website" / ".env.local")
    get = lambda *ds_k: next((d[k] for d, k in ds_k if d.get(k)), "")  # noqa: E731
    a = {
        "operator_name": web.get("NEXT_PUBLIC_OPERATOR_NAME", ""),
        "operator_address": web.get("NEXT_PUBLIC_OPERATOR_ADDRESS", "").replace("|", "\n"),
        "governing_law": web.get("NEXT_PUBLIC_GOVERNING_LAW", ""),
        "support_email": get((cl, "SUPPORT_EMAIL"), (web, "NEXT_PUBLIC_SUPPORT_EMAIL")),
        "copyright_email": web.get("NEXT_PUBLIC_COPYRIGHT_EMAIL", ""),
        "dmca_registration": web.get("NEXT_PUBLIC_DMCA_REGISTRATION", ""),
        "operator_url": web.get("NEXT_PUBLIC_OPERATOR_URL", ""),
        "operator_twitter": web.get("NEXT_PUBLIC_OPERATOR_TWITTER", ""),
        "site_url": get((cl, "SITE_URL"), (web, "NEXT_PUBLIC_SITE_URL")),
        "supabase_url": get((cl, "SUPABASE_URL"), (web, "NEXT_PUBLIC_SUPABASE_URL")),
        "supabase_publishable_key": get((cl, "SUPABASE_PUBLISHABLE_KEY"), (web, "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY")),
        "app_store_url": web.get("NEXT_PUBLIC_APP_STORE_URL", ""),
        "microsoft_store_url": web.get("NEXT_PUBLIC_MICROSOFT_STORE_URL", ""),
        "turnstile_site_key": cl.get("TURNSTILE_SITE_KEY", ""),
        "livekit_url": cl.get("LIVEKIT_URL", ""),
        "livekit_key": fn.get("LIVEKIT_API_KEY", ""),
        "r2_endpoint": fn.get("CF_R2_ENDPOINT", ""),
        "r2_bucket": fn.get("CF_R2_BUCKET_NAME", ""),
        "r2_access_key": fn.get("CF_R2_ACCESS_KEY_ID", ""),
    }
    if a["app_store_url"] or a["microsoft_store_url"]:
        a["has_stores"] = "y"
    if a["turnstile_site_key"]:
        a["captcha"] = "y"
    if sb.get("SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID"):
        a["google"], a["google_client_id"] = "y", sb["SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID"]
    if a["livekit_url"]:
        a["av"] = "own" if "livekit.cloud" not in a["livekit_url"] else "cloud"
    if a["r2_endpoint"]:
        a["r2"] = "y"
    return {k: v for k, v in a.items() if v}


def ask(q: Q, answers: dict, scripted: dict | None):
    """Return the answer for one question (scripted, or typed)."""
    default = answers.get(q.key, q.default)
    if q.key == "copyright_email" and not default:
        default = answers.get("support_email", "")
    if scripted is not None:
        value = scripted.get(q.key, default)
        if isinstance(value, list):
            value = "\n".join(value)
        value = str(value).strip() if value is not None else ""
        if not value and q.required:
            raise SystemExit(f"--answers: '{q.key}' is required ({q.prompt})")
        err = q.validate(value) if (value and q.validate) else None
        if err:
            raise SystemExit(f"--answers: '{q.key}' must be {err}")
        return value
    print(f"\n  {c('1', q.prompt)}" + ("" if q.required else c("90", "  (optional)")))
    if q.help:
        print(c("90", f"  {q.help}"))
    while True:
        if q.multiline:
            existing = default.split("\n") if default else []
            if existing:
                print(c("90", "  current: " + " | ".join(existing) + "  (press Enter on the first line to keep it)"))
            lines: list[str] = []
            while True:
                line = input("  > ").strip()
                if not line:
                    break
                lines.append(line)
            value = "\n".join(lines) if lines else default
        else:
            shown = "" if q.secret else (f" [{default}]" if default else "")
            if q.secret and default:
                shown = " [keep current]"
            prompt = f"  > {shown} " if shown else "  > "
            try:
                value = (getpass.getpass(prompt) if q.secret else input(prompt)).strip()
            except EOFError:
                raise SystemExit("\ninput closed - run it in a terminal, or pass --answers")
            value = value or default
        if not value and not q.required:
            return ""
        if not value:
            print(c("31", "  required."))
            continue
        err = q.validate(value) if q.validate else None
        if err:
            print(c("31", f"  needs {err}."))
            continue
        return value


# --------------------------------------------------------------------- rendering


def yes(a: dict, key: str) -> bool:
    return str(a.get(key, "")).lower() in ("y", "yes", "true")


def project_ref(a: dict) -> str:
    m = re.match(r"https://([a-z0-9]{20})\.supabase\.co", a.get("supabase_url", ""))
    return m.group(1) if m else "<your-project-ref>"


def env_value(value: str) -> str:
    """Quote only when an .env parser would otherwise misread it (spaces, '#', quotes)."""
    if re.search(r"[\s#\"'\\$]", value):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return value


def env_text(title: str, lines: list[tuple[str, str] | str]) -> str:
    body = [f"# {title}", "# Written by scripts/selfhost-setup.py - re-run it to change values.", ""]
    for item in lines:
        body.append(item if isinstance(item, str) else f"{item[0]}={env_value(item[1])}")
    return "\n".join(body) + "\n"


def render(a: dict) -> dict[str, str]:
    """relative path -> file content."""
    client = [("SUPABASE_URL", a["supabase_url"]), ("SUPABASE_PUBLISHABLE_KEY", a["supabase_publishable_key"]),
              ("SITE_URL", a["site_url"]), ("SUPPORT_EMAIL", a["support_email"]),
              ("LIVEKIT_URL", a.get("livekit_url", "") if a.get("av", "none") != "none" else ""),
              ("TURNSTILE_SITE_KEY", a.get("turnstile_site_key", "") if yes(a, "captcha") else ""),
              ("SENTRY_DSN", ""), ("POSTHOG_API_KEY", ""), ("POSTHOG_HOST", "")]
    auth = []
    if yes(a, "captcha"):
        auth.append(("SUPABASE_AUTH_CAPTCHA_SECRET", a["turnstile_secret"]))
    if yes(a, "google"):
        auth += [("SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID", a["google_client_id"]),
                 ("SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET", a["google_client_secret"])]
    fn: list = []
    if a.get("av", "none") != "none" and a.get("livekit_key"):
        fn += [("LIVEKIT_API_KEY", a["livekit_key"]), ("LIVEKIT_API_SECRET", a.get("livekit_secret", "")),
               ("LIVEKIT_URL", a.get("livekit_url", ""))]
    if yes(a, "r2"):
        fn += [("CF_R2_ENDPOINT", a["r2_endpoint"]), ("CF_R2_ACCESS_KEY_ID", a["r2_access_key"]),
               ("CF_R2_SECRET_ACCESS_KEY", a["r2_secret_key"]), ("CF_R2_BUCKET_NAME", a["r2_bucket"])]
    web = [("NEXT_PUBLIC_SUPABASE_URL", a["supabase_url"]), ("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", a["supabase_publishable_key"]),
           ("SUPABASE_SERVICE_ROLE_KEY", a["supabase_service_role_key"]),
           ("NEXT_PUBLIC_SITE_URL", a["site_url"]), ("NEXT_PUBLIC_SUPPORT_EMAIL", a["support_email"]),
           ("NEXT_PUBLIC_COPYRIGHT_EMAIL", a.get("copyright_email") or a["support_email"]),
           ("NEXT_PUBLIC_OPERATOR_NAME", a["operator_name"]),
           ("NEXT_PUBLIC_OPERATOR_ADDRESS", "|".join(l.strip() for l in a["operator_address"].splitlines() if l.strip())),
           ("NEXT_PUBLIC_GOVERNING_LAW", a["governing_law"]),
           ("NEXT_PUBLIC_OPERATOR_URL", a.get("operator_url", "")),
           ("NEXT_PUBLIC_OPERATOR_TWITTER", a.get("operator_twitter", "")),
           ("NEXT_PUBLIC_DMCA_REGISTRATION", a.get("dmca_registration", "")),
           ("NEXT_PUBLIC_APP_STORE_URL", a.get("app_store_url", "") if yes(a, "has_stores") else ""),
           ("NEXT_PUBLIC_MICROSOFT_STORE_URL", a.get("microsoft_store_url", "") if yes(a, "has_stores") else ""),
           ("NEXT_PUBLIC_TURNSTILE_SITE_KEY", a.get("turnstile_site_key", "") if yes(a, "captcha") else "")]
    files = {
        ".env": env_text("SyncTogether client defines - pass with --dart-define-from-file=.env (client-safe values only)", client),
        "supabase/.env": env_text("Secrets read by supabase/config.toml (auth) - never commit", auth or ["# (no OAuth or captcha secrets needed for your choices)"]),
        "supabase/functions/.env": env_text("Edge function secrets - upload with `supabase secrets set --env-file supabase/functions/.env`", fn or ["# (voice/video and shared files are off)"]),
        "website/.env.local": env_text("Website configuration - never commit", web),
    }
    return files


def post_deploy_sql(a: dict) -> str:
    base = a["supabase_url"].rstrip("/")
    out = ["-- Run once, after the database migrations and the edge functions are deployed.",
           "-- Contains your service-role key: keep this file private (it is git-ignored).", ""]
    if a.get("av", "none") != "none":
        out += [f"update public.app_settings set value = jsonb_build_object('enabled', true,",
                f"  'endpoint_url', '{base}/functions/v1/av-cleanup',",
                f"  'service_role_key', '{a['supabase_service_role_key']}') where key = 'av_cleanup';", ""]
    if yes(a, "r2"):
        out += [f"update public.app_settings set value = jsonb_build_object('enabled', true,",
                f"  'endpoint_url', '{base}/functions/v1/cleanup-r2',",
                f"  'service_role_key', '{a['supabase_service_role_key']}') where key = 'r2_cleanup';", ""]
    if len(out) == 3:
        out.append("-- Nothing to do: voice/video and shared files are off.")
    return "\n".join(out) + "\n"


# --------------------------------------------------------------------- writing


def write_file(path: Path, text: str, mode: int, on_exists: str) -> str:
    """on_exists: 'ask' | 'overwrite' | 'skip'. Returns what happened."""
    if path.exists():
        if path.read_text() == text:
            return "unchanged"
        choice = on_exists
        if choice == "ask":
            ans = input(f"  {path} exists and differs. [o]verwrite (a backup is kept) / [s]kip / write as [n]ew file? [o] ").strip().lower() or "o"
            choice = {"o": "overwrite", "s": "skip", "n": "new"}.get(ans[0], "overwrite")
        if choice == "skip":
            return "skipped"
        if choice == "new":
            path = path.with_name(path.name + ".new")
        else:
            backup = path.with_name(f"{path.name}.bak.{time.strftime('%Y%m%d%H%M%S')}")
            shutil.copy2(path, backup)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    os.chmod(path, mode)
    return "written" + (" (as .new)" if path.name.endswith(".new") else "")


# -------------------------------------------------------------------- next steps


def tools_report() -> list[tuple[str, bool, str]]:
    return [("supabase", bool(shutil.which("supabase")), "brew install supabase/tap/supabase  (or scoop on Windows)"),
            ("docker", bool(shutil.which("docker")), "https://docs.docker.com/get-docker/  (only needed to run Supabase or LiveKit yourself)"),
            ("node", bool(shutil.which("node")), "Node 22+ for the website: https://nodejs.org"),
            ("fvm", bool(shutil.which("fvm")), "dart pub global activate fvm  (to build the client app)")]


def next_steps(a: dict) -> list[tuple[str, list[str]]]:
    ref = project_ref(a)
    cloud = a.get("supabase_hosting", "cloud") == "cloud"
    steps: list[tuple[str, list[str]]] = []
    steps.append(("Database: apply the schema and background jobs", [
        f"supabase link --project-ref {ref}   # Supabase Cloud (you will be asked for the database password)" if cloud
        else 'supabase db push --db-url "postgresql://postgres:<db-password>@<db-host>:5432/postgres"   # your Docker stack',
        *(["supabase db push"] if cloud else []),
        "# pg_cron and pg_net must be enabled (they are on Supabase Cloud and the official Docker images)."]))
    gen = f"./scripts/selfhost-config.sh {a['site_url']}" + ("" if yes(a, "captcha") else " --no-captcha") + (" --google" if yes(a, "google") else "")
    if cloud:
        steps.append(("Sign-in settings (auth config for your own domain)", [
            gen, f"(cd .selfhost && supabase config push --project-ref {ref})   # run from INSIDE .selfhost"]))
    else:
        steps.append(("Sign-in settings (Docker stack: paste into its .env)", [gen + " --gotrue"]))
    if a.get("av", "none") != "none":
        if not a.get("livekit_url") or not a.get("livekit_key"):
            steps.append(("Your LiveKit server (not set up yet)", [
                "# On a fresh Ubuntu VPS with a DNS A record pointing at it (DNS-only if on Cloudflare):",
                "sudo ./scripts/setup-livekit-server.sh av.yourdomain.com",
                "# It prints an endpoint line: put its key/secret/url in supabase/functions/.env",
                "# (or re-run this wizard and answer the LiveKit questions), then continue below."]))
    fdeploy = ["livekit-token", "av-cleanup"] if a.get("av", "none") != "none" else []
    if yes(a, "r2"):
        fdeploy += ["media-share", "cleanup-r2"]
    cmds = ["supabase secrets set --env-file supabase/functions/.env"] + [f"supabase functions deploy {f}" for f in fdeploy]
    steps.append(("Edge functions", cmds if fdeploy else ["# Nothing to deploy: voice/video and shared files are off."]))
    if fdeploy:
        steps.append(("Switch the cleanup jobs on (they ship off)", [
            "# Run .selfhost/post-deploy.sql in the SQL editor (it holds your service key - keep it private), or:",
            'psql "<your database connection string>" -f .selfhost/post-deploy.sql']))
    steps.append(("Website (deploy at " + a["site_url"] + ")", [
        "cd website && npm ci && npm run build && npm run start",
        "# On Vercel or similar: copy the values from website/.env.local into the host's environment variables.",
        "# A production build refuses to start if the site URL, support/copyright email, operator name,",
        "# address or governing law is missing - that is the point.",
        f"# Point {a['site_url']} at it with TLS."]))
    steps.append(("Read the legal pages before you publish", [
        "# The wizard filled in your name, address, contacts and governing law. The TEXT around them is written",
        "# for the project's own deployment. Review it with a lawyer, in particular:",
        "#   website/app/privacy/page.tsx   - the list of service providers (yours will differ),",
        "#                                    the India (DPDP Act) section, retention periods",
        "#   website/app/terms/page.tsx     - everything",
        "#   website/app/refund/page.tsx    - only if you sell anything",
        "#   website/app/dmca/page.tsx      - only claims a registered agent if you set a registration number"]))
    steps.append(("Build the app with your values", [
        "fvm flutter pub get",
        "fvm flutter build macos --release --dart-define-from-file=.env     # or: windows"]))
    req = ",".join(x for x, on in (("av", a.get("av", "none") != "none"), ("media", yes(a, "r2")), ("google", yes(a, "google"))) if on)
    steps.append(("Verify everything (the only way to know it works)", [
        "export SUPABASE_SERVICE_ROLE_KEY=<your service-role key>",
        "python3 scripts/selfhost-verify.py" + (f" --require {req}" if req else ""),
        "# READY means every automated check passed. It also prints the few things only a person can confirm."]))
    return steps


# ------------------------------------------------------------------------- main


def main() -> int:
    ap = argparse.ArgumentParser(description="Guided setup for a self-hosted SyncTogether.")
    ap.add_argument("--answers", help="JSON file with the answers (non-interactive)")
    ap.add_argument("--out-dir", default=str(REPO), help="where to write the config files (default: this repo)")
    ap.add_argument("--yes", action="store_true", help="overwrite existing files (after backing them up) without asking")
    ap.add_argument("--no-config", action="store_true", help="skip generating the auth config and the post-deploy SQL")
    ap.add_argument("--print-keys", action="store_true", help="list the answer keys and exit")
    args = ap.parse_args()
    if args.print_keys:
        print("\n".join(ALL_KEYS))
        return 0

    out = Path(args.out_dir).resolve()
    scripted = json.loads(Path(args.answers).read_text()) if args.answers else None
    answers: dict = remembered(out)
    if scripted is not None:
        unknown = sorted(set(scripted) - set(ALL_KEYS))
        if unknown:
            raise SystemExit(f"--answers: unknown keys {unknown} (run --print-keys)")
    else:
        print(c("1", "\nSyncTogether self-hosting setup"))
        print("Answer a few questions; press Enter to accept a [default]. Nothing is sent anywhere,")
        print("and secrets are typed hidden. You can stop with Ctrl-C and run it again later.\n")
        missing = [(n, hint) for n, ok, hint in tools_report() if not ok]
        if missing:
            print(c("33", "Tools not found on this machine (install what each step needs):"))
            for n, hint in missing:
                print(f"  - {n}: {hint}")
    for step in STEPS:
        if scripted is None:
            print(f"\n{c('1;36', step.title)}  {step.intro}")
        for q in step.questions:
            if q.when and not q.when(answers):
                continue
            answers[q.key] = ask(q, answers, scripted)

    files = render(answers)
    on_exists = "overwrite" if (args.yes or scripted is not None) else "ask"
    print(f"\n{c('1', 'Writing files')}  ({out})")
    for rel, text in files.items():
        res = write_file(out / rel, text, 0o600, on_exists)
        print(f"  {rel:28} {res}")
    if not args.no_config:
        # The generator recreates .selfhost/ from scratch, so it runs before anything else goes in there.
        gen = [str(REPO / "scripts" / "selfhost-config.sh"), answers["site_url"]]
        if not yes(answers, "captcha"):
            gen.append("--no-captcha")
        if yes(answers, "google"):
            gen.append("--google")
        r = subprocess.run(gen, capture_output=True, text=True)
        print(f"  {'.selfhost/supabase/config.toml':28} {'generated' if r.returncode == 0 else 'FAILED: ' + r.stderr.strip()[:120]}")
        sql = write_file(REPO / ".selfhost" / "post-deploy.sql", post_deploy_sql(answers), 0o600, "overwrite")
        print(f"  {'.selfhost/post-deploy.sql':28} {sql}")

    print(f"\n{c('1', 'What is left, in order')}")
    for i, (title, cmds) in enumerate(next_steps(answers), 1):
        print(f"\n  {c('1;36', f'{i}.')} {c('1', title)}")
        for line in cmds:
            print(f"     {c('90', line) if line.startswith('#') else line}")
    if scripted is None:
        print(f"\n{c('1', 'Done writing.')} Everything above is a command for you to run when you are ready;")
        print("the wizard changed only the files listed and touched no server.")
        try:
            run_now = input("\nRun the verifier now (needs your servers to be up)? [y/N] ").strip().lower().startswith("y")
        except EOFError:
            run_now = False
        if run_now:
            env = {**os.environ, "SUPABASE_SERVICE_ROLE_KEY": answers["supabase_service_role_key"]}
            req = [x for x, on in (("av", answers.get("av", "none") != "none"), ("media", yes(answers, "r2")), ("google", yes(answers, "google"))) if on]
            cmd = [sys.executable, str(REPO / "scripts" / "selfhost-verify.py"), "--client-env", str(out / ".env"),
                   "--functions-env", str(out / "supabase" / "functions" / ".env")] + (["--require", ",".join(req)] if req else [])
            return subprocess.run(cmd, env=env).returncode
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nstopped - nothing half-written: files are only written after the last question.")
        sys.exit(130)
