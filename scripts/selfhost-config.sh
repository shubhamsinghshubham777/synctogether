#!/usr/bin/env bash
# ==============================================================================
# SyncTogether self-host auth config generator
# ------------------------------------------------------------------------------
# supabase/config.toml is the OFFICIAL deployment's auth config (synctogether.app
# redirects, Turnstile on, Google + Apple on with the official bundle ids). This
# derives a copy for your own domain into .selfhost/ (gitignored) and leaves the
# tracked file alone, then you push that copy:
#
#   ./scripts/selfhost-config.sh https://watch.example.com [--no-captcha] [--google] [--apple]
#   (cd .selfhost && supabase config push --project-ref <your-ref>)
#
# Flags:
#   --no-captcha  turn Cloudflare Turnstile off (guest sign-in needs no token)
#   --google      keep Google OAuth on (needs SUPABASE_AUTH_EXTERNAL_GOOGLE_* in supabase/.env)
#   --apple       keep Apple Sign-In on (edit client_id in the output to YOUR ids first)
#   --site-only   change ONLY site_url and leave every other setting as in config.toml
#                 (what the official project uses: its redirects and providers stay as they are)
#
# Running the full Supabase Docker stack instead? `config push` does not apply
# there - add --gotrue to print the equivalent GOTRUE_* variables for its .env.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO_ROOT/.selfhost"

SITE_URL=""
CAPTCHA=true
GOOGLE=false
APPLE=false
GOTRUE=false
SITE_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --no-captcha) CAPTCHA=false ;;
    --google) GOOGLE=true ;;
    --apple) APPLE=true ;;
    --gotrue) GOTRUE=true ;;
    --site-only) SITE_ONLY=true ;;
    -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
    *) SITE_URL="${arg%/}" ;;
  esac
done

if [[ ! "$SITE_URL" =~ ^https?://[^/]+$ ]]; then
  echo "Usage: $0 https://your-web-portal.example.com [--no-captcha] [--google] [--apple] [--gotrue]" >&2
  exit 1
fi

if [ "$GOTRUE" = true ]; then
  cat <<EOF
# Add to the Supabase Docker stack's .env (names follow GoTrue's config; check
# them against the release you deploy).
GOTRUE_SITE_URL=$SITE_URL
GOTRUE_URI_ALLOW_LIST=synctogether://auth-callback,synctogether://join/*,$SITE_URL/**
GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED=true
GOTRUE_SECURITY_MANUAL_LINKING_ENABLED=true
GOTRUE_SECURITY_CAPTCHA_ENABLED=$CAPTCHA
GOTRUE_SECURITY_CAPTCHA_PROVIDER=turnstile
GOTRUE_SECURITY_CAPTCHA_SECRET=<your-turnstile-secret>
EOF
  exit 0
fi

rm -rf "$OUT"
mkdir -p "$OUT/supabase"
cp "$REPO_ROOT/supabase/config.toml" "$OUT/supabase/config.toml"
# content_path entries are resolved against the workdir.
ln -s "$REPO_ROOT/supabase/templates" "$OUT/supabase/templates"
# config.toml reads its secrets as env(...) from <project>/supabase/.env. Without this
# the CLI resolves them to EMPTY and pushes empty OAuth/captcha secrets to the project.
if [ -f "$REPO_ROOT/supabase/.env" ]; then
  ln -s "$REPO_ROOT/supabase/.env" "$OUT/supabase/.env"
else
  echo "WARNING: supabase/.env not found - Google, Apple and captcha secrets will be pushed EMPTY." >&2
  echo "         Create it from supabase/.env.example first, or turn those providers off." >&2
fi

python3 -I - "$OUT/supabase/config.toml" "$SITE_URL" "$CAPTCHA" "$GOOGLE" "$APPLE" "$SITE_ONLY" <<'PY'
import re, sys
path, site, captcha, google, apple, site_only = sys.argv[1:]
s = open(path).read()

def set_in_section(text, section, key, value):
    """Replace `key = ...` inside [section] only."""
    m = re.search(r'^\[%s\]\n(.*?)(?=^\[|\Z)' % re.escape(section), text, re.S | re.M)
    if not m:
        raise SystemExit('section [%s] not found in config.toml' % section)
    body, n = re.subn(r'^%s\s*=.*$' % key, '%s = %s' % (key, value), m.group(1), count=1, flags=re.M)
    if n != 1:
        raise SystemExit('%s not found in [%s]' % (key, section))
    return text[:m.start(1)] + body + text[m.end(1):]

s, n = re.subn(r'^site_url\s*=.*$', 'site_url = "%s"' % site, s, count=1, flags=re.M)
assert n == 1, 'site_url not found'
if site_only == 'true':
    open(path, 'w').write(s)
    sys.exit(0)
s, n = re.subn(
    r'^additional_redirect_urls\s*=\s*\[.*?\]',
    'additional_redirect_urls = [\n  "synctogether://auth-callback",\n  "synctogether://join/*",\n  "%s/**",\n]' % site,
    s, count=1, flags=re.M | re.S)
assert n == 1, 'additional_redirect_urls not found'
s = set_in_section(s, 'auth.captcha', 'enabled', captcha)
s = set_in_section(s, 'auth.external.google', 'enabled', google)
s = set_in_section(s, 'auth.external.apple', 'enabled', apple)
open(path, 'w').write(s)
PY

cat <<EOF
Wrote $OUT/supabase/config.toml
  site_url            : $SITE_URL
$( [ "$SITE_ONLY" = true ] && echo "  everything else     : unchanged from supabase/config.toml" || printf "  redirects           : scheme links + %s/**\n  Turnstile captcha   : %s\n  Google / Apple      : %s / %s\n" "$SITE_URL" "$CAPTCHA" "$GOOGLE" "$APPLE" )

Next:
  (cd .selfhost && supabase config push --project-ref <your-ref>)
EOF
