"""Guards for everything a self-hoster relies on: the verifier, the config generator,
the LiveKit compose file and the .env.example files. Standard library only.

    python3 -m unittest discover -s scripts/tests -v
"""
from __future__ import annotations

import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def load_verifier():
    spec = importlib.util.spec_from_file_location("selfhost_verify", REPO / "scripts" / "selfhost-verify.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["selfhost_verify"] = mod
    spec.loader.exec_module(mod)
    return mod


V = load_verifier()


def run(cmd, **kw):
    kw.setdefault("capture_output", True)
    kw.setdefault("text", True)
    return subprocess.run(cmd, **kw)


class VerifierUnits(unittest.TestCase):
    def test_env_file_parsing(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "e"
            p.write_text("# c\nA=1\nexport B=\"two words\"\nC='x'\n\nD=\nBAD LINE\nE=a=b\n")
            self.assertEqual(V.parse_env_file(p), {"A": "1", "B": "two words", "C": "x", "D": "", "E": "a=b"})
            p.write_text('{"SUPABASE_URL": "https://x", "N": 3}')
            self.assertEqual(V.parse_env_file(p), {"SUPABASE_URL": "https://x", "N": "3"})
            self.assertEqual(V.parse_env_file(Path(d) / "missing"), {})

    def test_jwt_claims(self):
        import base64
        p = base64.urlsafe_b64encode(json.dumps({"iss": "APIkey"}).encode()).rstrip(b"=").decode()
        self.assertEqual(V.jwt_claims(f"h.{p}.s")["iss"], "APIkey")
        self.assertEqual(V.jwt_claims("garbage"), {})

    def test_migrations_are_understood(self):
        tables = V.migration_tables()
        self.assertGreater(len(tables), 20)
        for t in ("rooms", "room_members", "tier_limits", "app_settings"):
            self.assertIn(t, tables)
        keys = V.migration_settings()
        for k in ("r2_cleanup", "av_cleanup", "media_edge", "media_sharing"):
            self.assertIn(k, keys)

    def test_pg_denied_means_the_object_exists(self):
        denied = V.Resp(403, b'{"code":"42501","message":"permission denied for table x"}', {})
        missing = V.Resp(404, b'{"code":"PGRST205","message":"not found"}', {})
        self.assertTrue(V.pg_denied(denied))
        self.assertFalse(V.pg_denied(missing))

    def test_ws_client_reports_a_refused_handshake(self):
        with self.assertRaises(Exception):
            V.ws_session("ws://127.0.0.1:1/x", [], "phx_reply", timeout=1)


class VerifierCli(unittest.TestCase):
    def verify(self, client_env: str, functions_env: str = "", service_key: str | None = "x", *extra):
        with tempfile.TemporaryDirectory() as d:
            c, f = Path(d) / "client.env", Path(d) / "functions.env"
            c.write_text(client_env)
            f.write_text(functions_env)
            env = {k: v for k, v in os.environ.items() if k != "SUPABASE_SERVICE_ROLE_KEY"}
            if service_key is not None:
                env["SUPABASE_SERVICE_ROLE_KEY"] = service_key
            return run([sys.executable, str(REPO / "scripts" / "selfhost-verify.py"), "--client-env", str(c),
                        "--functions-env", str(f), "--skip-cron-wait", *extra], env=env)

    def test_unedited_examples_are_rejected_before_any_network_call(self):
        r = run([sys.executable, str(REPO / "scripts" / "selfhost-verify.py"), "--client-env", str(REPO / ".env.example"),
                 "--functions-env", str(REPO / "supabase/functions/.env.example"), "--skip-cron-wait"],
                env={**os.environ, "SUPABASE_SERVICE_ROLE_KEY": "x"})
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("still a placeholder", r.stdout)
        self.assertIn("Stopped", r.stdout)
        self.assertNotIn("Auth service", r.stdout)  # never probed the fake hosts

    def test_missing_service_key_stops(self):
        r = self.verify("SUPABASE_URL=http://127.0.0.1:1\nSUPABASE_PUBLISHABLE_KEY=k\nSITE_URL=https://a.example\nSUPPORT_EMAIL=a@a.example\n",
                        service_key=None)
        self.assertEqual(r.returncode, 1)
        self.assertIn("SUPABASE_SERVICE_ROLE_KEY", r.stdout)

    def test_a_dead_backend_is_not_ready_and_leaves_nothing_behind(self):
        r = self.verify("SUPABASE_URL=http://127.0.0.1:1\nSUPABASE_PUBLISHABLE_KEY=k\nSITE_URL=https://a.example\nSUPPORT_EMAIL=a@a.example\n")
        self.assertEqual(r.returncode, 1)
        self.assertIn("NOT READY", r.stdout)
        self.assertIn("Only a person can confirm", r.stdout)

    def test_client_and_server_must_agree_about_livekit(self):
        r = self.verify("SUPABASE_URL=http://127.0.0.1:1\nSUPABASE_PUBLISHABLE_KEY=k\nSITE_URL=https://a.example\n"
                        "SUPPORT_EMAIL=a@a.example\nLIVEKIT_URL=wss://lk.example\n")
        self.assertIn("LiveKit on the server", r.stdout)

    def test_missing_site_and_support_are_failures(self):
        r = self.verify("SUPABASE_URL=http://127.0.0.1:1\nSUPABASE_PUBLISHABLE_KEY=k\n")
        self.assertIn("SITE_URL", r.stdout)
        self.assertIn("SUPPORT_EMAIL", r.stdout)
        self.assertEqual(r.returncode, 1)


class ConfigGenerator(unittest.TestCase):
    """Runs the real script against a scratch copy of the repo layout, so it never touches .selfhost/."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        (self.tmp / "scripts").mkdir()
        shutil.copy(REPO / "scripts" / "selfhost-config.sh", self.tmp / "scripts")
        (self.tmp / "supabase").mkdir()
        shutil.copy(REPO / "supabase" / "config.toml", self.tmp / "supabase")
        shutil.copytree(REPO / "supabase" / "templates", self.tmp / "supabase" / "templates")
        self.script = self.tmp / "scripts" / "selfhost-config.sh"

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def gen(self, *args):
        return run(["bash", str(self.script), *args])

    def out(self) -> str:
        return (self.tmp / ".selfhost" / "supabase" / "config.toml").read_text()

    def test_site_only_changes_exactly_one_line(self):
        r = self.gen("https://watch.example.com/", "--site-only")
        self.assertEqual(r.returncode, 0, r.stderr)
        a = (self.tmp / "supabase" / "config.toml").read_text().splitlines()
        b = self.out().splitlines()
        self.assertEqual(len(a), len(b))
        diff = [(x, y) for x, y in zip(a, b) if x != y]
        self.assertEqual(len(diff), 1, diff)
        self.assertEqual(diff[0][1], 'site_url = "https://watch.example.com"')

    def test_default_mode_drops_other_peoples_redirects_and_providers(self):
        self.assertEqual(self.gen("https://watch.example.com", "--no-captcha").returncode, 0)
        text = self.out()
        self.assertIn('"https://watch.example.com/**"', text)
        self.assertIn('"synctogether://auth-callback"', text)
        self.assertNotIn("vercel.app", text)
        self.assertNotIn("synctogether.app", text)
        for section in ("auth.captcha", "auth.external.google", "auth.external.apple"):
            body = re.search(r"^\[%s\]\n(.*?)(?=^\[|\Z)" % re.escape(section), text, re.S | re.M).group(1)
            self.assertRegex(body, r"(?m)^enabled = false$", section)

    def test_flags_keep_providers_and_captcha(self):
        self.gen("https://watch.example.com", "--google", "--apple")
        text = self.out()
        for section in ("auth.captcha", "auth.external.google", "auth.external.apple"):
            body = re.search(r"^\[%s\]\n(.*?)(?=^\[|\Z)" % re.escape(section), text, re.S | re.M).group(1)
            self.assertRegex(body, r"(?m)^enabled = true$", section)

    def test_secrets_file_is_linked_when_present_and_a_missing_one_is_loud(self):
        r = self.gen("https://watch.example.com")
        self.assertIn("pushed EMPTY", r.stderr)
        self.assertFalse((self.tmp / ".selfhost" / "supabase" / ".env").exists())
        (self.tmp / "supabase" / ".env").write_text("X=1\n")
        r = self.gen("https://watch.example.com")
        self.assertNotIn("EMPTY", r.stderr)
        self.assertTrue((self.tmp / ".selfhost" / "supabase" / ".env").is_symlink())
        self.assertEqual((self.tmp / ".selfhost" / "supabase" / ".env").read_text(), "X=1\n")

    def test_email_template_is_reachable_from_the_output(self):
        self.gen("https://watch.example.com")
        self.assertTrue((self.tmp / ".selfhost" / "supabase" / "templates" / "magic_link.html").exists())

    def test_gotrue_mode_prints_variables_and_writes_nothing(self):
        r = self.gen("https://watch.example.com", "--gotrue", "--no-captcha")
        self.assertEqual(r.returncode, 0)
        self.assertIn("GOTRUE_SITE_URL=https://watch.example.com", r.stdout)
        self.assertIn("GOTRUE_SECURITY_CAPTCHA_ENABLED=false", r.stdout)
        self.assertFalse((self.tmp / ".selfhost").exists())

    def test_bad_input_is_refused(self):
        for bad in ("bad", "ftp://x", "https://x/path", ""):
            self.assertEqual(self.gen(bad).returncode, 1, bad)


def load_wizard():
    spec = importlib.util.spec_from_file_location("selfhost_setup", REPO / "scripts" / "selfhost-setup.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["selfhost_setup"] = mod
    spec.loader.exec_module(mod)
    return mod


W = load_wizard()

FULL = {
    "operator_name": "Alex Example", "operator_address": ["1 Example Street", "Springfield 00000", "Freedonia"],
    "governing_law": "Freedonia", "support_email": "help@watch.example.com", "site_url": "https://watch.example.com",
    "supabase_url": "https://abcdefghijklmnopqrst.supabase.co", "supabase_hosting": "cloud",
    "supabase_publishable_key": "sb_publishable_realvalue", "supabase_service_role_key": "sb_secret_realvalue",
    "has_stores": "n", "captcha": "y", "turnstile_site_key": "0x4AAAAAAAsite", "turnstile_secret": "0x4AAAAAAAsecret",
    "google": "y", "google_client_id": "123.apps.googleusercontent.com", "google_client_secret": "GOCSPX-real",
    "av": "cloud", "livekit_url": "wss://x.livekit.cloud", "livekit_key": "APIreal", "livekit_secret": "livesecret",
    "r2": "y", "r2_endpoint": "https://acc.r2.cloudflarestorage.com", "r2_bucket": "media",
    "r2_access_key": "AK", "r2_secret_key": "SK",
}
MINIMAL = {k: FULL[k] for k in ("operator_name", "operator_address", "governing_law", "support_email", "site_url",
                                 "supabase_url", "supabase_hosting", "supabase_publishable_key", "supabase_service_role_key")}
MINIMAL.update({"captcha": "n", "google": "n", "av": "none", "r2": "n", "has_stores": "n"})


class Wizard(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_wizard(self, answers, *extra, out=None):
        f = self.tmp / "answers.json"
        f.write_text(json.dumps(answers))
        return run([sys.executable, str(REPO / "scripts" / "selfhost-setup.py"), "--answers", str(f),
                    "--out-dir", str(out or self.tmp / "out"), "--no-config", *extra])

    def env(self, rel):
        return W.parse_env_file(self.tmp / "out" / rel)

    def test_full_run_writes_four_private_files(self):
        r = self.run_wizard(FULL)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        for rel in (".env", "supabase/.env", "supabase/functions/.env", "website/.env.local"):
            p = self.tmp / "out" / rel
            self.assertTrue(p.is_file(), rel)
            self.assertEqual(p.stat().st_mode & 0o777, 0o600, rel)

    def test_every_secret_lands_only_where_it_belongs(self):
        self.run_wizard(FULL)
        client, auth = self.env(".env"), self.env("supabase/.env")
        fn, web = self.env("supabase/functions/.env"), self.env("website/.env.local")
        self.assertNotIn("sb_secret_realvalue", json.dumps({"client": client, "auth": auth, "fn": fn}))
        self.assertEqual(web["SUPABASE_SERVICE_ROLE_KEY"], "sb_secret_realvalue")
        self.assertEqual(auth["SUPABASE_AUTH_CAPTCHA_SECRET"], "0x4AAAAAAAsecret")
        self.assertNotIn("0x4AAAAAAAsecret", json.dumps({"client": client, "fn": fn, "web": web}))
        self.assertEqual(fn["LIVEKIT_API_SECRET"], "livesecret")
        self.assertNotIn("livesecret", json.dumps({"client": client, "auth": auth, "web": web}))
        self.assertEqual(fn["CF_R2_SECRET_ACCESS_KEY"], "SK")
        self.assertNotIn("SK", json.dumps(client))

    def test_the_client_file_covers_every_define_in_env_example(self):
        self.run_wizard(FULL)
        wanted = {k for k in W.parse_env_file(REPO / ".env.example") if not k.endswith("_LOCAL")}
        self.assertEqual(sorted(wanted - set(self.env(".env"))), [])

    def test_the_website_file_covers_every_variable_the_site_reads(self):
        self.run_wizard(FULL)
        used = set()
        for f in (REPO / "website").rglob("*.ts*"):
            if "node_modules" in f.parts or ".next" in f.parts:
                continue
            used |= set(re.findall(r"process\.env\.(NEXT_PUBLIC_[A-Z0-9_]+)", f.read_text()))
        # NEXT_PUBLIC_SUPABASE_ANON_KEY is only the older name the code falls back to for the publishable key.
        optional_for_this_product = {"NEXT_PUBLIC_SUPABASE_ANON_KEY", "NEXT_PUBLIC_POSTHOG_KEY", "NEXT_PUBLIC_POSTHOG_HOST", "NEXT_PUBLIC_SHOW_USAGE_STATS",
                                     "NEXT_PUBLIC_PADDLE_ENVIRONMENT", "NEXT_PUBLIC_PADDLE_CLIENT_TOKEN",
                                     "NEXT_PUBLIC_PADDLE_MONTHLY_PRICE_ID", "NEXT_PUBLIC_PADDLE_ANNUAL_PRICE_ID"}
        self.assertEqual(sorted((used - optional_for_this_product) - set(self.env("website/.env.local"))), [])
        example = set(W.parse_env_file(REPO / "website" / ".env.example"))
        self.assertEqual(sorted(k for k in (used - optional_for_this_product) if k not in example), [],
                         "a variable the site requires is missing from website/.env.example")

    def test_operator_values_reach_the_website_file_intact(self):
        self.run_wizard(FULL)
        web = self.env("website/.env.local")
        self.assertEqual(web["NEXT_PUBLIC_OPERATOR_NAME"], "Alex Example")
        self.assertEqual(web["NEXT_PUBLIC_OPERATOR_ADDRESS"], "1 Example Street|Springfield 00000|Freedonia")
        self.assertEqual(web["NEXT_PUBLIC_GOVERNING_LAW"], "Freedonia")
        self.assertEqual(web["NEXT_PUBLIC_COPYRIGHT_EMAIL"], "help@watch.example.com")  # defaults to support
        self.assertEqual(web["NEXT_PUBLIC_DMCA_REGISTRATION"], "")  # never claimed unless given

    def test_awkward_characters_survive_a_round_trip(self):
        weird = dict(FULL, operator_name='Acme "Films" #1 & Co', operator_address=["Unit 5 #2, Main St"])
        self.run_wizard(weird)
        raw = (self.tmp / "out" / "website" / ".env.local").read_text().splitlines()
        # Quoted in the file itself: Next's (dotenv) parser would otherwise cut the value at " #".
        self.assertIn('NEXT_PUBLIC_OPERATOR_NAME="Acme \\"Films\\" #1 & Co"', raw)
        self.assertIn('NEXT_PUBLIC_OPERATOR_ADDRESS="Unit 5 #2, Main St"', raw)
        self.assertIn("NEXT_PUBLIC_GOVERNING_LAW=Freedonia", raw)  # plain values stay plain
        self.assertEqual(self.env("website/.env.local")["NEXT_PUBLIC_OPERATOR_NAME"], 'Acme "Films" #1 & Co')
        self.assertEqual(W.remembered(self.tmp / "out")["operator_name"], 'Acme "Films" #1 & Co')

    def test_nothing_written_is_a_placeholder_the_verifier_would_reject(self):
        self.run_wizard(FULL)
        for rel in (".env", "supabase/functions/.env"):
            for k, v in self.env(rel).items():
                self.assertNotRegex(v, r"xxxxx|<[^>]*>|\.\.\.$", f"{rel} {k}")

    def test_a_minimal_setup_turns_the_optional_features_off(self):
        self.assertEqual(self.run_wizard(MINIMAL).returncode, 0)
        self.assertEqual(self.env(".env")["LIVEKIT_URL"], "")
        self.assertEqual(self.env(".env")["TURNSTILE_SITE_KEY"], "")
        self.assertNotIn("SUPABASE_AUTH_CAPTCHA_SECRET", self.env("supabase/.env"))
        self.assertNotIn("LIVEKIT_API_KEY", self.env("supabase/functions/.env"))
        self.assertNotIn("CF_R2_ENDPOINT", self.env("supabase/functions/.env"))
        steps = " ".join(t for t, _ in W.next_steps(MINIMAL))
        self.assertNotIn("cleanup jobs", steps)
        cmds = " ".join(" ".join(c) for _, c in W.next_steps(MINIMAL))
        self.assertIn("--no-captcha", cmds)
        self.assertNotIn("functions deploy", cmds)

    def test_next_steps_follow_the_answers(self):
        cloud = " ".join(" ".join(c) for _, c in W.next_steps(FULL))
        self.assertIn("supabase link --project-ref abcdefghijklmnopqrst", cloud)
        self.assertIn("functions deploy media-share", cloud)
        self.assertIn("--require av,media,google", cloud)
        docker = " ".join(" ".join(c) for _, c in W.next_steps(dict(FULL, supabase_hosting="docker")))
        self.assertIn("--gotrue", docker)
        self.assertIn("--db-url", docker)
        own = [t for t, _ in W.next_steps(dict(FULL, av="own", livekit_url="", livekit_key=""))]
        self.assertIn("Your LiveKit server (not set up yet)", own)

    def test_bad_answers_are_refused_with_a_reason(self):
        for bad, key in (({"site_url": "http://watch.example.com"}, "site_url"), ({"support_email": "nope"}, "support_email"),
                         ({"operator_name": ""}, "operator_name"), ({"dmca_registration": "12345"}, "dmca_registration")):
            r = self.run_wizard(dict(FULL, **bad))
            self.assertNotEqual(r.returncode, 0, key)
            self.assertIn(key, r.stderr + r.stdout)
        r = self.run_wizard(dict(FULL, surprise="x"))
        self.assertIn("unknown keys", r.stderr + r.stdout)

    def test_rerun_keeps_old_answers_as_defaults_and_backs_up_changes(self):
        self.run_wizard(FULL)
        remembered = W.remembered(self.tmp / "out")
        self.assertEqual(remembered["site_url"], "https://watch.example.com")
        self.assertEqual(remembered["av"], "cloud")
        self.assertEqual(remembered["google_client_id"], "123.apps.googleusercontent.com")
        before = (self.tmp / "out" / ".env").read_text()
        self.run_wizard(dict(FULL, support_email="other@watch.example.com"))
        self.assertEqual(len(list((self.tmp / "out").glob(".env.bak.*"))), 1)  # changed -> backed up
        self.assertEqual((next((self.tmp / "out").glob(".env.bak.*"))).read_text(), before)
        self.run_wizard(dict(FULL, support_email="other@watch.example.com"))
        self.assertEqual(len(list((self.tmp / "out").glob(".env.bak.*"))), 1)  # unchanged -> no churn

    def test_the_post_deploy_sql_only_touches_what_is_enabled(self):
        full, minimal = W.post_deploy_sql(FULL), W.post_deploy_sql(MINIMAL)
        self.assertIn("'av_cleanup'", full)
        self.assertIn("/functions/v1/cleanup-r2", full)
        self.assertIn("Nothing to do", minimal)
        self.assertNotIn("update public", minimal)

    def test_interactive_prompts_use_defaults_and_collect_the_address(self):
        import builtins
        import contextlib
        import io
        q_addr = next(q for s in W.STEPS for q in s.questions if q.key == "operator_address")
        q_name = next(q for s in W.STEPS for q in s.questions if q.key == "operator_name")
        feed = iter(["1 Main St", "Town", ""])
        real = builtins.input
        builtins.input = lambda *a, **k: next(feed)
        try:
            with contextlib.redirect_stdout(io.StringIO()):  # the prompts themselves
                self.assertEqual(W.ask(q_addr, {}, None), "1 Main St\nTown")
                builtins.input = lambda *a, **k: ""  # Enter keeps the remembered value
                self.assertEqual(W.ask(q_name, {"operator_name": "Kept Name"}, None), "Kept Name")
                answers = iter(["", "Typed Name"])  # empty is refused for a required question, then accepted
                builtins.input = lambda *a, **k: next(answers)
                self.assertEqual(W.ask(q_name, {}, None), "Typed Name")
        finally:
            builtins.input = real

    def test_every_answer_key_is_documented_by_a_question(self):
        self.assertEqual(len(W.ALL_KEYS), len(set(W.ALL_KEYS)))
        self.assertTrue(set(FULL) <= set(W.ALL_KEYS))


class ShippedFiles(unittest.TestCase):
    def test_livekit_config_ships_no_keys(self):
        text = (REPO / "docker" / "livekit.yaml").read_text()
        self.assertNotRegex(text, r"(?m)^keys:")
        self.assertNotIn("devkey", text)

    def test_compose_pins_the_image_and_requires_keys(self):
        text = (REPO / "docker-compose.selfhost.yml").read_text()
        self.assertNotIn(":latest", text)
        self.assertIn("LIVEKIT_API_KEY:?", text)
        self.assertIn("LIVEKIT_API_SECRET:?", text)

    @unittest.skipUnless(shutil.which("docker"), "docker not available")
    def test_compose_refuses_to_start_without_keys_and_renders_with_them(self):
        base = ["docker", "compose", "-f", str(REPO / "docker-compose.selfhost.yml"), "config"]
        env = {k: v for k, v in os.environ.items() if not k.startswith("LIVEKIT_")}
        self.assertNotEqual(run(base, env=env).returncode, 0)
        ok = run(base, env={**env, "LIVEKIT_API_KEY": "APIabc", "LIVEKIT_API_SECRET": "s3cret"})
        self.assertEqual(ok.returncode, 0, ok.stderr)
        self.assertIn("APIabc", ok.stdout)

    def test_client_env_example_lists_every_define_the_client_reads(self):
        example = set(re.findall(r"(?m)^#?\s*([A-Z][A-Z0-9_]+)=", (REPO / ".env.example").read_text()))
        used = set()
        for f in (REPO / "lib").rglob("*.dart"):
            used |= set(re.findall(r"fromEnvironment\(\s*'([A-Z0-9_]+)'", f.read_text()))
        # Debug / screenshot / store-build switches, not deployment configuration.
        internal = {"CAPTURE_REVIEW", "CAPTURE_STORE", "CAPTURE_WEBSITE", "DEMO_MODE", "DEMO_ROOM", "DEMO_TIER",
                    "MPV_HWDEC", "REVIEW_HEIGHT", "REVIEW_WIDTH", "STORE_BUILD", "STORE_TARGET", "STREAM_PROXY"}
        self.assertEqual(sorted((used - internal) - example), [], "client define missing from .env.example")

    def test_functions_env_example_lists_every_secret_the_functions_read(self):
        example = set(re.findall(r"(?m)^#?\s*([A-Z][A-Z0-9_]+)=", (REPO / "supabase/functions/.env.example").read_text()))
        used = set()
        for f in (REPO / "supabase" / "functions").rglob("*.ts"):
            if f.name.endswith("_test.ts"):
                continue
            used |= set(re.findall(r'Deno\.env\.get\(\s*"([A-Z0-9_]+)"', f.read_text()))
        injected = {"SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY"}  # Supabase sets these itself
        self.assertEqual(sorted((used - injected) - example), [])

    def test_examples_carry_no_working_or_official_values(self):
        for rel in (".env.example", "supabase/.env.example", "supabase/functions/.env.example", "website/.env.example"):
            text = (REPO / rel).read_text()
            self.assertNotRegex(text, r"synctogether\.app", rel)
            self.assertNotIn("devkey", text, rel)
            self.assertNotRegex(text, r"eyJ[A-Za-z0-9_-]{30,}", rel)

    def test_the_client_has_no_built_in_official_hostname(self):
        hits = []
        for f in (REPO / "lib").rglob("*.dart"):
            for n, line in enumerate(f.read_text().splitlines(), 1):
                if "synctogether.app" in line:
                    hits.append(f"{f.relative_to(REPO)}:{n}")
        self.assertEqual(hits, [])

    def test_every_store_workflow_passes_the_operator_defines(self):
        for wf in ("ios_app_store", "mac_app_store", "microsoft_store", "play_store"):
            text = (REPO / ".github" / "workflows" / f"publish_{wf}.yaml").read_text()
            for name in ("SITE_URL", "SUPPORT_EMAIL"):
                self.assertIn(f'--dart-define={name}="${name}"', text, f"{wf} {name}")
                self.assertIn(f"{name}: ${{{{ secrets.{name} }}}}", text, f"{wf} {name}")


if __name__ == "__main__":
    unittest.main()
