#!/usr/bin/env bash
# ==============================================================================
# SyncTogether: Grant Premium Access (Local Development Stack)
# ------------------------------------------------------------------------------
# Grants premium tier subscription benefits to any user in the local Supabase
# environment by their email address.
#
# Usage:
#   ./scripts/grant-premium-local.sh user@example.com           # Grant lifetime premium
#   ./scripts/grant-premium-local.sh user@example.com 6         # Grant 6 months premium
#   ./scripts/grant-premium-local.sh user@example.com --revoke  # Revert back to free tier
#   ./scripts/grant-premium-local.sh                            # Interactive prompt
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
SyncTogether Local Premium Grant Tool

Grants premium tier subscription access to a user on the local Supabase stack.

USAGE:
  ./scripts/grant-premium-local.sh <USER_EMAIL> [OPTIONS]

ARGUMENTS:
  USER_EMAIL          Email of the user account (case-insensitive)

OPTIONS:
  [MONTHS]            Duration in months (e.g., 6 or 12). Default is lifetime.
  --months <N>        Explicit duration in months.
  --revoke            Revoke premium subscription and restore user to free tier.
  --yes, -y           Bypass any interactive confirmation prompts.
  --help, -h          Show this help message.

EXAMPLES:
  ./scripts/grant-premium-local.sh dev@example.com
  ./scripts/grant-premium-local.sh dev@example.com 3
  ./scripts/grant-premium-local.sh dev@example.com --revoke
EOF
}

# 1. Dependency checks
if ! command -v node &>/dev/null; then
  error "Node.js (version 18+) is required to run this script. Please install Node.js."
  exit 1
fi

# 2. Local Supabase defaults
LOCAL_URL="http://127.0.0.1:54321"
LOCAL_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"

# Optional overrides from .env or website/.env.local if custom local port configured
if [ -f "$REPO_ROOT/.env" ]; then
  CANDIDATE_URL=$(grep -E '^SUPABASE_URL_LOCAL=' "$REPO_ROOT/.env" | cut -d '=' -f2- | tr -d ' "' || true)
  if [ -n "$CANDIDATE_URL" ]; then
    LOCAL_URL="$CANDIDATE_URL"
  fi
fi

# 3. Check connectivity to local Supabase
if ! curl -s --connect-timeout 2 "$LOCAL_URL/rest/v1/" &>/dev/null; then
  error "Local Supabase stack is not responding at $LOCAL_URL."
  echo ""
  warn "Please ensure your local environment is running:"
  echo -e "  Run: ${BOLD}./scripts/dev.sh${NC} (or ${BOLD}supabase start${NC})"
  exit 1
fi

# 4. Parse Arguments
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

# 5. Interactive prompt if email is not passed
if [ -z "$USER_EMAIL" ]; then
  echo -e "${BOLD}${CYAN}SyncTogether Local Premium Grant${NC}"
  read -rp "Enter user email: " USER_EMAIL
  USER_EMAIL=$(echo "$USER_EMAIL" | tr -d '[:space:]')
fi

if [ -z "$USER_EMAIL" ]; then
  error "User email cannot be empty."
  show_help
  exit 1
fi

# On local development, default to auto-confirming unless revoke
HAS_YES=false
HAS_REVOKE=false
if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
  for arg in "${EXTRA_ARGS[@]}"; do
    if [ "$arg" = "--yes" ] || [ "$arg" = "-y" ]; then
      HAS_YES=true
    elif [ "$arg" = "--revoke" ]; then
      HAS_REVOKE=true
    fi
  done
fi

if [ "$HAS_YES" = false ] && [ "$HAS_REVOKE" = false ]; then
  EXTRA_ARGS+=("--yes")
fi

# 6. Execute Core Engine
if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
  exec node "$REPO_ROOT/scripts/lib/grant-premium-core.mjs" \
    --url "$LOCAL_URL" \
    --key "$LOCAL_KEY" \
    --env-name "Local" \
    --email "$USER_EMAIL" \
    "${EXTRA_ARGS[@]}"
else
  exec node "$REPO_ROOT/scripts/lib/grant-premium-core.mjs" \
    --url "$LOCAL_URL" \
    --key "$LOCAL_KEY" \
    --env-name "Local" \
    --email "$USER_EMAIL"
fi
