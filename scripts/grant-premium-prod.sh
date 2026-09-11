#!/usr/bin/env bash
# ==============================================================================
# SyncTogether: Grant Premium Access (Production Environment)
# ------------------------------------------------------------------------------
# Grants premium tier subscription benefits to any user in the live production
# Supabase environment by their email address.
#
# Safety Guaranteed:
#   - Strictly refuses to run against localhost / loopback addresses.
#   - Strictly refuses to run with the local demo service key.
#   - Displays target user details and requests explicit confirmation (y/N)
#     before modifying production records (bypassable via --yes / -y for CI/automation).
#
# Usage:
#   ./scripts/grant-premium-prod.sh user@example.com           # Grant lifetime premium
#   ./scripts/grant-premium-prod.sh user@example.com 12        # Grant 12 months premium
#   ./scripts/grant-premium-prod.sh user@example.com --revoke  # Revert back to free tier
#   ./scripts/grant-premium-prod.sh                            # Interactive prompt
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ANSI Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info() { echo -e "${CYAN}ℹ ${NC}$1"; }
success() { echo -e "${GREEN}✔ ${NC}$1"; }
warn() { echo -e "${YELLOW}⚠ ${NC}$1"; }
error() { echo -e "${RED}✖ ${NC}$1"; }

show_help() {
  cat << 'EOF'
SyncTogether Production Premium Grant Tool

Grants premium tier subscription access to a user on the live production Supabase instance.

USAGE:
  ./scripts/grant-premium-prod.sh <USER_EMAIL> [OPTIONS]

ARGUMENTS:
  USER_EMAIL          Email of the user account (case-insensitive)

OPTIONS:
  [MONTHS]            Duration in months (e.g., 6 or 12). Default is lifetime.
  --months <N>        Explicit duration in months.
  --revoke            Revoke premium subscription and restore user to free tier.
  --yes, -y           Bypass interactive confirmation prompt.
  --help, -h          Show this help message.

EXAMPLES:
  ./scripts/grant-premium-prod.sh user@gmail.com
  ./scripts/grant-premium-prod.sh user@gmail.com 12
  ./scripts/grant-premium-prod.sh user@gmail.com --revoke
EOF
}

# 1. Dependency checks
if ! command -v node &>/dev/null; then
  error "Node.js (version 18+) is required to run this script. Please install Node.js."
  exit 1
fi

# 2. Discover Production Credentials
PROD_URL="${PROD_SUPABASE_URL:-}"
PROD_KEY="${PROD_SUPABASE_SERVICE_ROLE_KEY:-}"

# Candidate locations for environment files
CANDIDATE_FILES=(
  "$REPO_ROOT/website/.env.local"
  "$REPO_ROOT/website/.env.production.local"
  "$REPO_ROOT/website/.env"
  "$REPO_ROOT/.env"
)

for file in "${CANDIDATE_FILES[@]}"; do
  if [ -f "$file" ]; then
    if [ -z "$PROD_URL" ]; then
      PROD_URL=$(grep -E '^PROD_SUPABASE_URL=' "$file" 2>/dev/null | cut -d '=' -f2- | tr -d ' "' || true)
    fi
    if [ -z "$PROD_KEY" ]; then
      PROD_KEY=$(grep -E '^PROD_SUPABASE_SERVICE_ROLE_KEY=' "$file" 2>/dev/null | cut -d '=' -f2- | tr -d ' "' || true)
    fi
    # Fallback to SUPABASE_URL in root .env if it is a remote https domain
    if [ -z "$PROD_URL" ]; then
      CANDIDATE=$(grep -E '^SUPABASE_URL=' "$file" 2>/dev/null | cut -d '=' -f2- | tr -d ' "' || true)
      if [[ -n "$CANDIDATE" && "$CANDIDATE" =~ ^https:// ]]; then
        PROD_URL="$CANDIDATE"
      fi
    fi
    # Fallback to SUPABASE_SERVICE_ROLE_KEY if non-demo
    if [ -z "$PROD_KEY" ]; then
      CANDIDATE=$(grep -E '^SUPABASE_SERVICE_ROLE_KEY=' "$file" 2>/dev/null | cut -d '=' -f2- | tr -d ' "' || true)
      if [[ -n "$CANDIDATE" && ! "$CANDIDATE" =~ "supabase-demo" && ! "$CANDIDATE" == "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vI"* ]]; then
        PROD_KEY="$CANDIDATE"
      fi
    fi
  fi
done

# 3. Validate Credentials Presence
if [ -z "$PROD_URL" ] || [ -z "$PROD_KEY" ]; then
  error "Missing production Supabase credentials."
  echo ""
  echo -e "Please ensure ${BOLD}PROD_SUPABASE_URL${NC} and ${BOLD}PROD_SUPABASE_SERVICE_ROLE_KEY${NC} are configured in:"
  echo -e "  ${CYAN}website/.env.local${NC}"
  echo "Or export them in your shell environment:"
  echo -e "  export PROD_SUPABASE_URL=\"https://<your-project-ref>.supabase.co\""
  echo -e "  export PROD_SUPABASE_SERVICE_ROLE_KEY=\"sb_production_service_role_...\""
  exit 1
fi

# 4. Safety Guardrails: Refuse Loopback and Demo Keys
PROD_URL_CLEAN=$(echo "$PROD_URL" | tr -d '[:space:]')
PROD_KEY_CLEAN=$(echo "$PROD_KEY" | tr -d '[:space:]')

if [[ "$PROD_URL_CLEAN" =~ localhost|127\.0\.0\.1|0\.0\.0\.0|::1|\.local$|\.localhost$ ]]; then
  error "ABORT: Target URL ($PROD_URL_CLEAN) is a local loopback address!"
  echo "The production grant script strictly forbids running against local development environments."
  echo -e "To grant premium access on local, use: ${BOLD}./scripts/grant-premium-local.sh${NC}"
  exit 1
fi

if [[ "$PROD_KEY_CLEAN" =~ "supabase-demo" ]] || [[ "$PROD_KEY_CLEAN" == "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vI"* ]]; then
  error "ABORT: Local demo service_role key was detected!"
  echo "A genuine live production service_role key is required to modify production users."
  exit 1
fi

# 5. Check Remote Connectivity
if ! curl -s --connect-timeout 5 "$PROD_URL_CLEAN/rest/v1/" &>/dev/null; then
  warn "Unable to reach $PROD_URL_CLEAN (connectivity or firewall issue). Attempting to proceed..."
fi

# 6. Parse Arguments
USER_EMAIL=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      show_help
      exit 0
      ;;
    --revoke)
      EXTRA_ARGS+=("--revoke")
      shift
      ;;
    --yes|-y)
      EXTRA_ARGS+=("--yes")
      shift
      ;;
    --months)
      if [[ $# -ge 2 ]]; then
        EXTRA_ARGS+=("--months" "$2")
        shift 2
      else
        error "--months requires an integer argument."
        exit 1
      fi
      ;;
    --email)
      if [[ $# -ge 2 ]]; then
        USER_EMAIL="$2"
        shift 2
      else
        error "--email requires an argument."
        exit 1
      fi
      ;;
    *)
      if [ -z "$USER_EMAIL" ] && [[ ! "$1" =~ ^[0-9]+$ ]]; then
        USER_EMAIL="$1"
      elif [[ "$1" =~ ^[0-9]+$ ]]; then
        EXTRA_ARGS+=("--months" "$1")
      else
        EXTRA_ARGS+=("$1")
      fi
      shift
      ;;
  esac
done

# 7. Interactive prompt if email is not passed
if [ -z "$USER_EMAIL" ]; then
  echo -e "${BOLD}${RED}SyncTogether Production Premium Grant${NC}"
  read -rp "Enter user email: " USER_EMAIL
  USER_EMAIL=$(echo "$USER_EMAIL" | tr -d '[:space:]')
fi

if [ -z "$USER_EMAIL" ]; then
  error "User email cannot be empty."
  show_help
  exit 1
fi

# 8. Execute Core Engine against Production
if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
  exec node "$REPO_ROOT/scripts/lib/grant-premium-core.mjs" \
    --url "$PROD_URL_CLEAN" \
    --key "$PROD_KEY_CLEAN" \
    --env-name "Production" \
    --email "$USER_EMAIL" \
    "${EXTRA_ARGS[@]}"
else
  exec node "$REPO_ROOT/scripts/lib/grant-premium-core.mjs" \
    --url "$PROD_URL_CLEAN" \
    --key "$PROD_KEY_CLEAN" \
    --env-name "Production" \
    --email "$USER_EMAIL"
fi
