#!/usr/bin/env python3
"""
SyncTogether self-host verifier
===============================

Run it after setting up your own instance. It does not just check that values are
present: it signs in a throwaway test user and drives the real flow against YOUR
servers - create a room, join its private Realtime channel, mint a LiveKit token
and have LiveKit accept it, upload a small file through the media function to your
bucket and read it back, and wait for the minute cron to end an expired room.

  export SUPABASE_SERVICE_ROLE_KEY=...        # needed; never put it in a client file
  python3 scripts/selfhost-verify.py          # reads ./.env and supabase/functions/.env
  python3 scripts/selfhost-verify.py --require av,media     # missing = FAIL, not "off"

Exit code: 0 = READY (every automated check passed), 1 = NOT READY (something
failed), 2 = INCOMPLETE (a check could not run, so nothing can be promised).

What READY means: every check that can be made from outside passed. It does not
cover what only a person can see; those items are printed at the end every time.
Everything the script creates (test user, room, uploaded file) is removed at the
end. Standard library only; no installs.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import secrets
import socket
import ssl
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
USE_COLOR = sys.stdout.isatty()


def c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if USE_COLOR else text


PASS, FAIL, WARN, SKIP, OFF = "PASS", "FAIL", "WARN", "SKIP", "OFF"
ICON = {PASS: c("32", "✔"), FAIL: c("31", "✖"), WARN: c("33", "!"), SKIP: c("33", "?"), OFF: c("90", "-")}
results: list[tuple[str, str, str, str]] = []  # status, section, name, detail
section = ""


def head(name: str) -> None:
    global section
    section = name
    print(f"\n{c('1', name)}")


def report(status: str, name: str, detail: str = "", fix: str = "") -> bool:
    results.append((status, section, name, detail))
    line = f"  {ICON[status]} {name}"
    if detail:
        line += c("90", f"  {detail}")
    print(line)
    if fix and status in (FAIL, WARN, SKIP):
        print(f"      {c('36', 'fix:')} {fix}")
    return status == PASS


# --------------------------------------------------------------------------- io


def parse_env_file(path: Path) -> dict[str, str]:
    """KEY=VALUE lines (quotes allowed) or a flat JSON object. Never sourced."""
    if not path.is_file():
        return {}
    text = path.read_text()
    try:
        data = json.loads(text)
        if isinstance(data, dict):
            return {k: str(v) for k, v in data.items()}
    except ValueError:
        pass
    out: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip().removeprefix("export ").strip()
        val = val.strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        out[key] = val
    return out


class Resp:
    def __init__(self, status: int, body: bytes, headers):
        self.status, self.body, self.headers = status, body, headers

    def json(self):
        try:
            return json.loads(self.body or b"null")
        except ValueError:
            return None

    @property
    def text(self) -> str:
        return self.body.decode("utf-8", "replace")


def http(method: str, url: str, *, headers=None, body=None, raw: bytes | None = None, timeout=25) -> Resp:
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    h = {"User-Agent": "synctogether-selfhost-verify"}
    if body is not None:
        h["Content-Type"] = "application/json"
    h.update(headers or {})
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return Resp(r.status, r.read(), r.headers)
    except urllib.error.HTTPError as e:
        return Resp(e.code, e.read(), e.headers)
    except (urllib.error.URLError, socket.timeout, ssl.SSLError, ConnectionError, OSError) as e:
        return Resp(0, str(getattr(e, "reason", e)).encode(), {})


def pg_denied(r: "Resp") -> bool:
    """PostgREST 'permission denied' (42501): the key was accepted and the object
    exists, but this role is deliberately not allowed to read it."""
    j = r.json()
    return isinstance(j, dict) and j.get("code") == "42501"


def jwt_claims(token: str) -> dict:
    try:
        p = token.split(".")[1]
        return json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))
    except Exception:
        return {}


# ------------------------------------------------------------------- websocket


def ws_session(url: str, send: list[dict], want_event: str, timeout=12):
    """Minimal RFC 6455 client: send Phoenix messages, return replies until
    `want_event` has been seen for every sent topic or the timeout passes."""
    u = urllib.parse.urlparse(url)
    port = u.port or (443 if u.scheme == "wss" else 80)
    sock = socket.create_connection((u.hostname, port), timeout=timeout)
    if u.scheme == "wss":
        sock = ssl.create_default_context().wrap_socket(sock, server_hostname=u.hostname)
    key = base64.b64encode(os.urandom(16)).decode()
    path = u.path + ("?" + u.query if u.query else "")
    sock.sendall(
        (f"GET {path} HTTP/1.1\r\nHost: {u.netloc}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
         f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("closed during handshake")
        buf += chunk
    head_, _, rest = buf.partition(b"\r\n\r\n")
    if b" 101 " not in head_.split(b"\r\n")[0]:
        raise ConnectionError(head_.split(b"\r\n")[0].decode())

    def frame(payload: bytes, opcode=1) -> bytes:
        mask = os.urandom(4)
        n = len(payload)
        hdr = bytes([0x80 | opcode])
        hdr += bytes([0x80 | n]) if n < 126 else bytes([0x80 | 126]) + struct.pack(">H", n)
        return hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload))

    def read_exact(n: int) -> bytes:
        nonlocal rest
        while len(rest) < n:
            chunk = sock.recv(65536)
            if not chunk:
                raise ConnectionError("closed")
            rest += chunk
        out, rest = rest[:n], rest[n:]
        return out

    for m in send:
        sock.sendall(frame(json.dumps(m).encode()))
    got: list[dict] = []
    end = time.time() + timeout
    sock.settimeout(2)
    try:
        while time.time() < end:
            try:
                b1, b2 = read_exact(2)
                op, ln = b1 & 0x0F, b2 & 0x7F
                if ln == 126:
                    ln = struct.unpack(">H", read_exact(2))[0]
                elif ln == 127:
                    ln = struct.unpack(">Q", read_exact(8))[0]
                payload = read_exact(ln)
            except socket.timeout:
                continue
            if op == 9:
                sock.sendall(frame(payload, 10))
            elif op == 8:
                break
            elif op == 1:
                try:
                    got.append(json.loads(payload))
                except ValueError:
                    pass
                if sum(1 for g in got if g.get("event") == want_event) >= len(send):
                    break
    finally:
        sock.close()
    return got


# --------------------------------------------------------------------- context


class Ctx:
    def __init__(self, a: argparse.Namespace):
        client = parse_env_file(Path(a.client_env))
        server = parse_env_file(Path(a.functions_env))
        self.client, self.server = client, server
        self.base = client.get("SUPABASE_URL", "").rstrip("/")
        self.anon = client.get("SUPABASE_PUBLISHABLE_KEY", "")
        self.service = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
        self.site = client.get("SITE_URL", "").rstrip("/")
        self.support = client.get("SUPPORT_EMAIL", "")
        self.livekit_client = client.get("LIVEKIT_URL", "")
        self.turnstile = client.get("TURNSTILE_SITE_KEY", "")
        self.require = {x.strip() for x in a.require.split(",") if x.strip()}
        self.skip_cron = a.skip_cron_wait
        self.endpoints = self._endpoints()
        self.r2_keys = ["CF_R2_ENDPOINT", "CF_R2_ACCESS_KEY_ID", "CF_R2_SECRET_ACCESS_KEY", "CF_R2_BUCKET_NAME"]
        self.r2_set = [k for k in self.r2_keys if server.get(k)]
        self.user_id = ""
        self.user_jwt = ""
        self.room_id = ""
        self.email = f"selfhost-verify-{secrets.token_hex(4)}@example.com"
        self.cleanup_media_room = ""

    def _endpoints(self) -> list[dict]:
        raw = self.server.get("LIVEKIT_ENDPOINTS", "").strip()
        if raw:
            try:
                return [e for e in json.loads(raw) if isinstance(e, dict)]
            except ValueError:
                return []
        if self.server.get("LIVEKIT_URL"):
            return [{"id": "default", "url": self.server["LIVEKIT_URL"],
                     "key": self.server.get("LIVEKIT_API_KEY", ""), "secret": self.server.get("LIVEKIT_API_SECRET", "")}]
        return []

    @property
    def av_on(self) -> bool:
        return bool(self.endpoints or self.livekit_client)

    @property
    def r2_on(self) -> bool:
        return bool(self.r2_set)

    def rest(self, method, path, *, key=None, jwt=None, body=None, headers=None):
        h = {"apikey": key or self.anon, "Authorization": f"Bearer {jwt or key or self.anon}"}
        h.update(headers or {})
        return http(method, f"{self.base}{path}", headers=h, body=body)

    def admin(self, method, path, body=None, headers=None):
        return self.rest(method, path, key=self.service, body=body, headers=headers)

    def rpc(self, name, args, jwt):
        return self.rest("POST", f"/rest/v1/rpc/{name}", jwt=jwt, body=args)


# ---------------------------------------------------------------------- checks


def check_config(x: Ctx) -> bool:
    head("1. Configuration")
    ok = True
    if not x.base:
        ok = report(FAIL, "SUPABASE_URL", "not set in the client env file", "set it in .env (client defines) or pass --client-env") and ok
    elif not x.base.startswith("https://"):
        local = re.match(r"https?://(localhost|127\.0\.0\.1)", x.base)
        report(WARN if local else FAIL, "SUPABASE_URL is https", x.base, "release builds need an https URL")
        ok = ok and bool(local)
    else:
        report(PASS, "SUPABASE_URL", x.base)
    ok = (report(PASS, "SUPABASE_PUBLISHABLE_KEY set") if x.anon else
          report(FAIL, "SUPABASE_PUBLISHABLE_KEY", "not set", "copy the publishable/anon key from your Supabase API settings")) and ok
    ok = (report(PASS, "SUPABASE_SERVICE_ROLE_KEY (environment)", "used only by this script, never sent anywhere else") if x.service else
          report(FAIL, "SUPABASE_SERVICE_ROLE_KEY", "not in the environment", "export SUPABASE_SERVICE_ROLE_KEY=... then re-run")) and ok
    if x.site.startswith("https://"):
        report(PASS, "SITE_URL", x.site)
    elif x.site:
        report(WARN, "SITE_URL is https", x.site, "invite links and Google sign-in expect https")
    else:
        ok = report(FAIL, "SITE_URL", "not set", "pass --dart-define=SITE_URL=https://your-portal (client builds have no built-in site)") and ok
    if x.support:
        report(PASS, "SUPPORT_EMAIL", x.support)
    else:
        ok = report(FAIL, "SUPPORT_EMAIL", "not set", "set SUPPORT_EMAIL - reports and appeals need somewhere to go") and ok

    # AV: client and server must agree.
    if x.av_on:
        if not x.livekit_client:
            ok = report(FAIL, "LIVEKIT_URL (client)", "server has LiveKit configured but the client define is missing", "set LIVEKIT_URL=wss://... in the client env") and ok
        if not x.endpoints:
            ok = report(FAIL, "LiveKit on the server", "client has LIVEKIT_URL but supabase/functions/.env has no LiveKit settings",
                        "set LIVEKIT_API_KEY/_SECRET/_URL (or LIVEKIT_ENDPOINTS) and run `supabase secrets set --env-file supabase/functions/.env`") and ok
        else:
            bad = [e.get("id", "?") for e in x.endpoints if not (e.get("url") and e.get("key") and e.get("secret"))]
            if bad:
                ok = report(FAIL, "LiveKit endpoint fields", f"missing url/key/secret on: {', '.join(bad)}") and ok
            if x.livekit_client:
                hosts = {urllib.parse.urlparse(e.get("url", "")).hostname for e in x.endpoints}
                if urllib.parse.urlparse(x.livekit_client).hostname not in hosts:
                    ok = report(WARN, "client LIVEKIT_URL matches a server endpoint", x.livekit_client,
                                "the client fallback host should be one of your endpoints") and ok
                else:
                    report(PASS, "client LIVEKIT_URL matches a server endpoint")
            if any(e.get("secret") in ("secret_dev_key_for_synctogether_change_in_production",) or e.get("key") == "devkey" for e in x.endpoints):
                ok = report(FAIL, "LiveKit keys are not the shipped dev pair", "devkey is public", "generate real keys") and ok
    elif "av" in x.require:
        ok = report(FAIL, "AV (voice/video)", "required, but no LiveKit settings found") and ok
    else:
        report(OFF, "AV (voice/video)", "no LiveKit configured - facecams stay hidden")

    if x.r2_on and len(x.r2_set) != 4:
        missing = [k for k in x.r2_keys if k not in x.r2_set]
        ok = report(FAIL, "R2 / S3 settings", f"incomplete, missing {', '.join(missing)}") and ok
    elif x.r2_on:
        report(PASS, "R2 / S3 settings", "all four set")
    elif "media" in x.require:
        ok = report(FAIL, "Shared media (R2)", "required, but CF_R2_* are not set") and ok
    else:
        report(OFF, "Shared media (R2)", "no CF_R2_* set - hosts cannot upload files for members")
    return ok


def check_backend(x: Ctx) -> bool:
    head("2. Backend reachable and keys valid")
    ok = True
    r = http("GET", f"{x.base}/auth/v1/health", headers={"apikey": x.anon})
    ok = (report(PASS, "Auth service", "/auth/v1/health ok") if r.status == 200 else
          report(FAIL, "Auth service", f"HTTP {r.status or 'no connection'}: {r.text[:80]}", "is the URL right and the stack up? self-hosted: check Kong on :8000 and TLS")) and ok
    r = x.rest("GET", "/rest/v1/tier_limits?select=tier")
    if r.status == 200 or pg_denied(r):
        report(PASS, "Publishable key accepted by the API")
    else:
        ok = report(FAIL, "Publishable key accepted by the API", f"HTTP {r.status}: {r.text[:80]}", "wrong key, or PostgREST cannot see the schema (did `supabase db push` run?)") and ok
    r = x.admin("GET", "/rest/v1/tier_limits?select=tier")
    if r.status == 200:
        tiers = {row.get("tier") for row in (r.json() or [])}
        missing = {"guest", "free", "premium"} - tiers
        ok = (report(PASS, "Service key works, tier_limits seeded", ", ".join(sorted(t for t in tiers if t))) if not missing else
              report(FAIL, "tier_limits rows", f"missing {', '.join(sorted(missing))}", "re-run `supabase db push`; the migrations seed these")) and ok
    else:
        ok = report(FAIL, "Service key", f"HTTP {r.status}: {r.text[:80]}", "check SUPABASE_SERVICE_ROLE_KEY belongs to this project") and ok
    return ok


def migration_tables() -> list[str]:
    created: set[str] = set()
    for f in sorted((REPO / "supabase" / "migrations").glob("*.sql")):
        text = re.sub(r"--[^\n]*", "", f.read_text())
        for m in re.finditer(r"create\s+table\s+(?:if\s+not\s+exists\s+)?public\.(\w+)", text, re.I):
            created.add(m.group(1))
        for m in re.finditer(r"drop\s+table\s+(?:if\s+exists\s+)?public\.(\w+)", text, re.I):
            created.discard(m.group(1))
    return sorted(created)


def migration_settings() -> list[str]:
    keys: set[str] = set()
    for f in sorted((REPO / "supabase" / "migrations").glob("*.sql")):
        text = f.read_text()
        for m in re.finditer(r"insert\s+into\s+public\.app_settings[^;]*?values\s*\(\s*'(\w+)'", text, re.I | re.S):
            keys.add(m.group(1))
    return sorted(keys)


def check_schema(x: Ctx) -> bool:
    head("3. Database schema and seed data")
    tables = migration_tables()
    if not tables:
        return report(SKIP, "tables from supabase/migrations", "run this from a full repo checkout")
    missing = []
    for t in tables:
        r = x.admin("GET", f"/rest/v1/{t}?select=*&limit=0")
        if r.status != 200 and not pg_denied(r):
            missing.append(f"{t}({r.status})")
    ok = (report(PASS, f"all {len(tables)} tables from the migrations exist") if not missing else
          report(FAIL, "tables from the migrations", "missing: " + ", ".join(missing[:8]) + (" ..." if len(missing) > 8 else ""),
                 "run `supabase db push` against THIS database (self-hosted: pass --db-url)"))
    r = x.admin("GET", "/rest/v1/app_settings?select=key,value")
    rows = {row["key"]: row["value"] for row in (r.json() or [])} if r.status == 200 else {}
    x.settings = rows  # type: ignore[attr-defined]
    miss = [k for k in migration_settings() if k not in rows]
    ok = (report(PASS, "app_settings seeded", ", ".join(sorted(rows))) if not miss else
          report(FAIL, "app_settings keys", "missing: " + ", ".join(miss), "re-run `supabase db push`")) and ok
    return ok


def check_auth(x: Ctx) -> bool:
    head("4. Authentication")
    ok = True
    r = http("GET", f"{x.base}/auth/v1/settings", headers={"apikey": x.anon})
    s = r.json() or {}
    ext = s.get("external", {})
    if r.status != 200:
        return report(FAIL, "Auth settings", f"HTTP {r.status}")
    ok = (report(PASS, "Anonymous (guest) sign-in enabled") if ext.get("anonymous_users") else
          report(FAIL, "Anonymous (guest) sign-in", "disabled", "enable_anonymous_sign_ins = true (see scripts/selfhost-config.sh)")) and ok
    ok = (report(PASS, "Email sign-in enabled") if ext.get("email") else
          report(FAIL, "Email sign-in", "disabled", "enable the email provider")) and ok
    x.google = bool(ext.get("google"))  # type: ignore[attr-defined]
    if x.google:
        report(PASS, "Google OAuth provider on", "log in once by hand to confirm the Google console side")
    elif "google" in x.require:
        ok = report(FAIL, "Google OAuth", "required, but not enabled") and ok
    else:
        report(OFF, "Google OAuth", "not enabled - email codes and guests only")

    # Captcha: an anonymous sign-up with no token tells us whether the server enforces it.
    r = http("POST", f"{x.base}/auth/v1/signup", headers={"apikey": x.anon}, body={})
    body = r.json() or {}
    msg = json.dumps(body).lower()
    if r.status == 200 and body.get("access_token"):
        uid = (body.get("user") or {}).get("id")
        if uid and x.service:
            x.admin("DELETE", f"/auth/v1/admin/users/{uid}")
        if x.turnstile:
            report(WARN, "Captcha", "server does NOT enforce it but the client has TURNSTILE_SITE_KEY", "harmless; enable [auth.captcha] if you want bot protection")
        else:
            report(PASS, "Captcha off on the server", "guests can sign in with no token (the client sends none)")
    elif "captcha" in msg:
        if x.turnstile:
            report(PASS, "Captcha enforced and the client has a Turnstile site key", "solving the widget itself needs a person")
        else:
            ok = report(FAIL, "Captcha enforced, but the client has no TURNSTILE_SITE_KEY",
                        "every guest sign-in would be rejected",
                        "build with --dart-define=TURNSTILE_SITE_KEY=... or disable [auth.captcha]") and ok
    else:
        ok = report(FAIL, "Guest sign-in probe", f"HTTP {r.status}: {msg[:100]}") and ok

    # Test user, signed in through the admin API (no email, no captcha involved).
    r = x.admin("POST", "/auth/v1/admin/users", {"email": x.email, "email_confirm": True})
    if r.status not in (200, 201):
        return report(FAIL, "Create the throwaway test user", f"HTTP {r.status}: {r.text[:100]}", "check the service key and auth config") and False
    x.user_id = (r.json() or {}).get("id", "")
    redirects = [f"{x.site}/auth/desktop-callback" if x.site else "", "synctogether://auth-callback", "synctogether://join/ABC234"]
    jwt = ""
    for target in [t for t in redirects if t]:
        r = x.admin("POST", "/auth/v1/admin/generate_link", {"type": "magiclink", "email": x.email, "redirect_to": target})
        j = r.json() or {}
        link = j.get("action_link", "")
        accepted = urllib.parse.parse_qs(urllib.parse.urlparse(link).query).get("redirect_to", [""])[0]
        if r.status != 200:
            ok = report(FAIL, f"Redirect allow-list: {target}", f"generate_link HTTP {r.status}") and ok
            continue
        if accepted == target:
            report(PASS, f"Redirect allowed: {target}")
        else:
            ok = report(FAIL, f"Redirect NOT allowed: {target}", f"auth fell back to {accepted or 'nothing'}",
                        "add it to additional_redirect_urls (./scripts/selfhost-config.sh) and push the config") and ok
        if not jwt and j.get("hashed_token"):
            v = http("POST", f"{x.base}/auth/v1/verify", headers={"apikey": x.anon},
                     body={"type": "magiclink", "token_hash": j["hashed_token"]})
            jwt = (v.json() or {}).get("access_token", "")
    if jwt:
        x.user_jwt = jwt
        report(PASS, "Test user signed in", "session minted through the auth server")
    else:
        ok = report(FAIL, "Test user sign-in", "could not obtain a session; the checks below need one") and False
    return ok


def check_room_flow(x: Ctx) -> bool:
    head("5. Rooms, privacy and Realtime")
    if not x.user_jwt:
        return report(SKIP, "room flow", "no test session (see section 4)")
    ok = True
    r = x.rpc("create_room", {"p_name": "selfhost-verify", "p_duration_minutes": 30}, x.user_jwt)
    room = r.json() if r.status in (200, 201) else None
    if isinstance(room, list):
        room = room[0] if room else None
    if not room or not room.get("id"):
        return report(FAIL, "create_room RPC", f"HTTP {r.status}: {r.text[:120]}", "migrations not fully applied, or a grant/RLS problem") and False
    x.room_id = room["id"]
    report(PASS, "create_room RPC", f"code {room.get('code')}")

    r = x.rest("GET", f"/rest/v1/rooms?id=eq.{x.room_id}&select=id", jwt=x.user_jwt)
    ok = (report(PASS, "Host can read their room") if r.status == 200 and r.json() else
          report(FAIL, "Host can read their room", f"HTTP {r.status}", "RLS policy on rooms is missing or wrong")) and ok
    r = x.rest("GET", f"/rest/v1/rooms?id=eq.{x.room_id}&select=id")  # anon key only
    ok = (report(PASS, "Anonymous visitors cannot read rooms", "RLS is enforcing") if r.status in (401, 403) or r.json() == [] else
          report(FAIL, "Anonymous visitors CAN read rooms", f"HTTP {r.status}: {r.text[:60]}", "RLS is not enabled - data is exposed; re-apply the migrations")) and ok

    # Realtime: a private channel, authorised through RLS on realtime.messages.
    ws = f"{x.base.replace('https://', 'wss://').replace('http://', 'ws://')}/realtime/v1/websocket?apikey={urllib.parse.quote(x.anon)}&vsn=1.0.0"
    topic = f"realtime:room:{x.room_id}"
    cfg = {"config": {"broadcast": {"self": True}, "presence": {"key": ""}, "private": True}, "access_token": x.user_jwt}
    try:
        msgs = ws_session(ws, [{"topic": topic, "event": "phx_join", "payload": cfg, "ref": "1", "join_ref": "1"}], "phx_reply")
        reply = next((m for m in msgs if m.get("event") == "phx_reply" and m.get("topic") == topic), None)
        status = ((reply or {}).get("payload") or {}).get("status")
        if status == "ok":
            ok = report(PASS, "Realtime: member joins the private room channel") and ok
        elif reply:
            ok = report(FAIL, "Realtime: private channel join refused", json.dumps(reply.get("payload"))[:120],
                        "the realtime.messages RLS policies, or the Realtime JWT secret, do not match this database") and ok
        else:
            ok = report(FAIL, "Realtime: no reply", "websocket opened but nothing answered", "Realtime service not running / not routed") and ok
    except Exception as e:  # noqa: BLE001
        if "401" in str(e) or "403" in str(e):
            ok = report(FAIL, "Realtime refused the publishable key", str(e)[:100],
                        "SUPABASE_PUBLISHABLE_KEY is not this project's key (REST can look fine while Realtime rejects it)") and ok
        else:
            ok = report(FAIL, "Realtime websocket", str(e)[:120], "self-hosted: Kong must proxy /realtime/v1 with websocket upgrade; TLS in front must allow it") and ok
    return ok


def check_functions(x: Ctx) -> bool:
    head("6. Edge functions, LiveKit and media")
    if not x.user_jwt:
        return report(SKIP, "edge functions", "no test session")
    ok = True
    names = ["livekit-token", "av-cleanup", "media-share", "cleanup-r2"]
    for n in names:
        r = http("POST", f"{x.base}/functions/v1/{n}", headers={"apikey": x.anon}, body={})
        deployed = not (r.status == 404 and "NOT_FOUND" in r.text.upper())
        want = (n in ("livekit-token", "av-cleanup") and x.av_on) or (n in ("media-share", "cleanup-r2") and x.r2_on)
        if deployed:
            report(PASS, f"function {n} deployed")
        elif want:
            ok = report(FAIL, f"function {n} NOT deployed", "", f"supabase functions deploy {n}") and ok
        else:
            report(OFF, f"function {n} not deployed", "not needed with this configuration")

    # --- AV
    if x.av_on and x.room_id:
        r = http("POST", f"{x.base}/functions/v1/livekit-token", headers={"apikey": x.anon, "Authorization": f"Bearer {x.user_jwt}"},
                 body={"room_id": x.room_id})
        j = r.json() or {}
        if r.status == 200 and j.get("token"):
            claims = jwt_claims(j["token"])
            report(PASS, "livekit-token mints a token", f"endpoint {j.get('endpoint')}, key {claims.get('iss', '?')}")
            lk = (j.get("url") or "").replace("wss://", "https://").replace("ws://", "http://").rstrip("/")
            v = http("GET", f"{lk}/rtc/validate?access_token={urllib.parse.quote(j['token'])}", timeout=15)
            if v.status == 200:
                report(PASS, "LiveKit server accepts that token", f"{lk}  (secret in Supabase matches the server)")
            elif v.status == 0:
                ok = report(FAIL, "LiveKit server reachable", v.text[:100], "DNS, TLS certificate or the cloud firewall (80/443, 7881/tcp, 7882/udp, 3478/udp)") and ok
            else:
                ok = report(FAIL, "LiveKit rejected the token", f"HTTP {v.status}: {v.text[:100]}",
                            "the key/secret in `supabase secrets` differ from the LiveKit server's; re-set and redeploy livekit-token") and ok
        else:
            ok = report(FAIL, "livekit-token", f"HTTP {r.status}: {r.text[:120]}", "check LIVEKIT_* secrets were uploaded: supabase secrets set --env-file supabase/functions/.env") and ok
        av = (getattr(x, "settings", {}) or {}).get("av_cleanup") or {}
        if av.get("endpoint_url"):
            report(PASS, "av_cleanup is switched on", av["endpoint_url"])
        else:
            ok = report(FAIL, "av_cleanup is switched OFF", "ended and kicked members would stay in calls",
                        "update public.app_settings set value = jsonb_build_object('enabled', true, 'endpoint_url', '<your-url>/functions/v1/av-cleanup', 'service_role_key', '<key>') where key='av_cleanup'") and ok

    # --- Media
    if x.r2_on and len(x.r2_set) == 4 and x.room_id:
        ok = media_roundtrip(x) and ok
    return ok


def media_roundtrip(x: Ctx) -> bool:
    ok = True
    hdr = {"apikey": x.anon, "Authorization": f"Bearer {x.user_jwt}"}
    fn = f"{x.base}/functions/v1/media-share"
    data = os.urandom(4096)

    def call(body):
        return http("POST", fn, headers=hdr, body=body, timeout=40)

    r = call({"action": "initiate", "roomId": x.room_id, "fileName": "verify.mp4", "fileSize": len(data), "contentType": "video/mp4"})
    j = r.json() or {}
    if r.status != 200 or not j.get("uploadId"):
        err = j.get("error", "") or r.text[:100]
        if "s3" in err.lower() or r.status == 502:
            return report(FAIL, "Upload: storage rejected the request", f"{err} {j.get('details', '')}"[:140],
                          "wrong CF_R2_ENDPOINT / keys / bucket name, or the key lacks write access") and False
        return report(FAIL, "Upload: initiate", f"HTTP {r.status}: {err}"[:140],
                      "media_sharing may be disabled in app_settings, or a tier limit blocks the test user") and False
    ident = {"roomId": x.room_id, "uploadId": j["uploadId"], "r2Key": j["r2Key"]}
    r = call({"action": "part-urls", **ident, "partNumbers": [1]})
    parts = (r.json() or {}).get("parts") or []
    if not parts:
        return report(FAIL, "Upload: part URLs", f"HTTP {r.status}: {r.text[:100]}") and False
    put = http("PUT", parts[0]["url"], raw=data, headers={"Content-Type": "video/mp4"}, timeout=60)
    if put.status not in (200, 201):
        return report(FAIL, "Upload: PUT to the bucket", f"HTTP {put.status}: {put.text[:100]}",
                      "presigned URLs must be reachable from here: check the endpoint is public and (R2) the account id in CF_R2_ENDPOINT") and False
    etag = put.headers.get("ETag", "") if put.headers else ""
    r = call({"action": "complete", **ident, "parts": [{"partNumber": 1, "etag": etag}]})
    if r.status != 200:
        return report(FAIL, "Upload: complete", f"HTTP {r.status}: {r.text[:100]}") and False
    report(PASS, "Shared media: upload through your bucket works")
    x.cleanup_media_room = x.room_id
    r = call({"action": "download-url", "roomId": x.room_id})
    j = r.json() or {}
    url = j.get("streamUrl", "")
    if not url:
        return report(FAIL, "Shared media: download URL", f"HTTP {r.status}: {r.text[:100]}") and False
    g = http("GET", url, headers={"Range": "bytes=0-1023"}, timeout=40)
    host = urllib.parse.urlparse(url).hostname
    if g.status in (200, 206) and len(g.body) >= 1024 and g.body[:1024] == data[:1024]:
        report(PASS, "Shared media: members can stream it back, bytes identical", f"via {host}")
    else:
        ok = report(FAIL, "Shared media: stream read-back", f"HTTP {g.status} from {host}, {len(g.body)} bytes",
                    "bucket not readable via the URL given out (edge worker/route, CORS or endpoint)") and ok
    edge = (getattr(x, "settings", {}) or {}).get("media_edge") or {}
    if edge.get("enabled") and not x.server.get("MEDIA_EDGE_SECRET"):
        ok = report(WARN, "media_edge is enabled but MEDIA_EDGE_SECRET is unset", "the function ignores the edge", "set the secret or disable media_edge") and ok
    elif edge.get("enabled"):
        report(PASS if "workers" in (host or "") or host == urllib.parse.urlparse(edge.get("base_url") or "").hostname else WARN,
               "media_edge in use", f"stream served from {host}")
    # R2 cleanup wiring
    c = (getattr(x, "settings", {}) or {}).get("r2_cleanup") or {}
    if c.get("endpoint_url"):
        res = http("POST", c["endpoint_url"], headers={"Authorization": f"Bearer {x.service}", "apikey": x.anon}, body={})
        ok = (report(PASS, "r2_cleanup is switched on and the function answers") if res.status == 200 else
              report(FAIL, "cleanup-r2 call", f"HTTP {res.status}: {res.text[:100]}", "redeploy cleanup-r2 / check its secrets")) and ok
    else:
        ok = report(FAIL, "r2_cleanup is switched OFF", "deleted and expired videos stay in your bucket forever",
                    "update public.app_settings set value = jsonb_build_object('enabled', true, 'endpoint_url', '<your-url>/functions/v1/cleanup-r2', 'service_role_key', '<key>') where key='r2_cleanup'") and ok
    return ok


def check_cron(x: Ctx) -> bool:
    head("7. Scheduled jobs (pg_cron)")
    if not x.room_id:
        return report(SKIP, "cron", "no test room")
    if x.skip_cron:
        return report(SKIP, "minute cron ends an expired room", "skipped by --skip-cron-wait - this is the only check that proves pg_cron is running")
    past = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 120))
    r = x.admin("PATCH", f"/rest/v1/rooms?id=eq.{x.room_id}", body={"expires_at": past}, headers={"Prefer": "return=minimal"})
    if r.status not in (200, 204):
        return report(FAIL, "Back-date the test room", f"HTTP {r.status}: {r.text[:100]}")
    print(c("90", "      waiting up to 150 s for the every-minute sweep ..."), flush=True)
    end = time.time() + 150
    while time.time() < end:
        time.sleep(8)
        r = x.admin("GET", f"/rest/v1/rooms?id=eq.{x.room_id}&select=ended_at")
        rows = r.json() if r.status == 200 else None
        if rows == [] or (rows and rows[0].get("ended_at")):
            x.room_id_swept = True  # type: ignore[attr-defined]
            return report(PASS, "pg_cron is running: the expired room was ended by the sweep")
    return report(FAIL, "pg_cron did not end an expired room in 150 s",
                  "", "enable the pg_cron and pg_net extensions and check cron.job has 'minutely-maintenance' (run `supabase db push` again; self-hosted Postgres needs them in shared_preload_libraries)")


def check_website(x: Ctx) -> bool:
    head("8. Web portal")
    if not x.site:
        return report(SKIP, "website", "SITE_URL not set")
    ok = True
    for path, label in (("/", "home"), ("/terms", "terms"), ("/privacy", "privacy"), ("/join/ABC234", "invite page")):
        r = http("GET", x.site + path, headers={"Accept": "text/html"})
        if r.status == 200:
            report(PASS, f"{label}: {path}")
        else:
            ok = report(FAIL, f"{label}: {path}", f"HTTP {r.status or 'no connection'}", "deploy website/ at SITE_URL (npm run build && npm run start, or your host)") and ok
    r = http("GET", x.site + "/auth/desktop-callback", headers={"Accept": "text/html"})
    if r.status in (200, 301, 302, 307, 308, 400):
        report(PASS, "Google sign-in bridge route exists", f"HTTP {r.status}")
    else:
        ok = report(FAIL, "Google sign-in bridge /auth/desktop-callback", f"HTTP {r.status}") and ok
    return ok


def cleanup(x: Ctx) -> None:
    head("Cleanup")
    try:
        if x.room_id and x.user_jwt and not getattr(x, "room_id_swept", False):
            x.rpc("end_room", {"p_room_id": x.room_id}, x.user_jwt)
        if x.user_id:
            r = x.admin("DELETE", f"/auth/v1/admin/users/{x.user_id}")
            report(PASS if r.status in (200, 204) else WARN, "throwaway test user removed",
                   "" if r.status in (200, 204) else f"HTTP {r.status} - delete {x.email} by hand")
    except Exception as e:  # noqa: BLE001
        report(WARN, "cleanup", str(e)[:100], f"delete the user {x.email} and room {x.room_id} by hand")


MANUAL = [
    "Email sign-in codes actually arrive in an inbox (SMTP): sign in once with a real address.",
    "Google sign-in end to end (Google console redirect URI, consent screen) - once, by hand.",
    "Two real machines in one room: sync, voice and video media over UDP (firewall / NAT / TURN). "
    "The script proves signalling and tokens, not that UDP gets through.",
    "A store/release build, run once, with the SAME defines you passed here (SUPABASE_URL, key, SITE_URL, ...).",
    "Backups and certificate renewal on your own servers.",
]


def main() -> int:
    ap = argparse.ArgumentParser(description="Verify a SyncTogether self-hosted deployment.")
    ap.add_argument("--client-env", default=str(REPO / ".env"), help="client defines (KEY=VALUE or JSON)")
    ap.add_argument("--functions-env", default=str(REPO / "supabase" / "functions" / ".env"))
    ap.add_argument("--require", default="", help="comma list of features that must work: av, media, google")
    ap.add_argument("--skip-cron-wait", action="store_true", help="skip the 2-minute pg_cron test (verdict becomes INCOMPLETE)")
    x = Ctx(ap.parse_args())
    print(c("1", "SyncTogether self-host verification"))
    if not check_config(x) and (not x.base or not x.anon or not x.service):
        print(c("31", "\nStopped: fix the configuration above first."))
        return 1
    try:
        check_backend(x)
        check_schema(x)
        check_auth(x)
        check_room_flow(x)
        check_functions(x)
        check_cron(x)
        check_website(x)
    finally:
        cleanup(x)

    fails = [r for r in results if r[0] == FAIL]
    skips = [r for r in results if r[0] == SKIP]
    offs = [r for r in results if r[0] == OFF]
    warns = [r for r in results if r[0] == WARN]
    print("\n" + "=" * 70)
    print(f"  {c('32', str(sum(1 for r in results if r[0] == PASS)))} passed   {c('31', str(len(fails)))} failed   "
          f"{c('33', str(len(warns)))} warnings   {c('33', str(len(skips)))} not run   {c('90', str(len(offs)))} off")
    if offs:
        print(c("90", "  Off by configuration: " + "; ".join(r[2] for r in offs)))
    if fails:
        print("\n" + c("31;1", "  NOT READY") + " - fix these and run again:")
        for _, sec, name, detail in fails:
            print(f"    ✖ [{sec.split('.')[0]}] {name}  {detail}")
        code = 1
    elif skips:
        print("\n" + c("33;1", "  INCOMPLETE") + " - these could not run, so nothing is promised:")
        for _, sec, name, detail in skips:
            print(f"    ? {name}  {detail}")
        code = 2
    else:
        print("\n" + c("32;1", "  READY") + " - every automated check passed against your servers.")
        code = 0
    print("\n  Only a person can confirm these (not covered by any script):")
    for m in MANUAL:
        print(f"    • {m}")
    print()
    return code


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\ninterrupted - if a test user was created, remove selfhost-verify-*@example.com from Auth > Users.")
        sys.exit(130)
