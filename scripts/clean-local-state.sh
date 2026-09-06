#!/usr/bin/env bash
# ==============================================================================
# SyncTogether: Clean Slate Local State & Test Users Reset
# ------------------------------------------------------------------------------
# Deletes all local test users and sessions from:
#   1. Local desktop macOS clients (Instance A & B session tokens & preferences)
#   2. Local Supabase Postgres stack (auth.users, profiles, subscriptions, rooms)
#   3. Paddle Sandbox (cancels all active/trialing subscriptions & archives customers)
#   4. Local log files and temporary build artifacts
#
# SAFETY GUARANTEE:
#   Strictly restricted to local stack and Paddle Sandbox.
#   NEVER touches production Supabase or production users.
# ==============================================================================

set -eo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${CYAN}ℹ ${NC}$1"; }
success() { echo -e "${GREEN}✔ ${NC}$1"; }
warn() { echo -e "${YELLOW}⚠ ${NC}$1"; }
error() { echo -e "${RED}✖ ${NC}$1"; }
banner() { echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}\n"; }

banner "SyncTogether Local Clean Slate Reset"

# ------------------------------------------------------------------------------
# 1. Safety Checks (Guarantee we NEVER touch production)
# ------------------------------------------------------------------------------
info "Running safety guard checks..."

if [ -f "$REPO_ROOT/website/.env.local" ]; then
  PADDLE_ENV=$(grep -E '^NEXT_PUBLIC_PADDLE_ENVIRONMENT=' "$REPO_ROOT/website/.env.local" | cut -d '=' -f2- | tr -d ' "')
  if [ "$PADDLE_ENV" = "production" ]; then
    error "ABORT: website/.env.local has NEXT_PUBLIC_PADDLE_ENVIRONMENT=production! Will not proceed."
    exit 1
  fi
fi

if [ -f "$REPO_ROOT/website/.env.local" ]; then
  PADDLE_KEY=$(grep -E '^PADDLE_API_KEY=' "$REPO_ROOT/website/.env.local" | cut -d '=' -f2- | tr -d ' "')
  if [[ -n "$PADDLE_KEY" && ! "$PADDLE_KEY" =~ ^pdl_sdbx_ ]]; then
    error "ABORT: PADDLE_API_KEY does not start with 'pdl_sdbx_'! Refusing to run against non-sandbox environment."
    exit 1
  fi
fi

success "Safety guards passed: targeting local stack and sandbox only."

# ------------------------------------------------------------------------------
# 2. Local Desktop Apps & Preferences Domain Reset
# ------------------------------------------------------------------------------
info "Cleaning local macOS client authentication sessions & preferences..."

# Kill any running app instances
pkill -f "SyncTogether B.app" 2>/dev/null || true
pkill -f "SyncTogether.app/Contents/MacOS/SyncTogether" 2>/dev/null || true

# Clear NSUserDefaults domains
defaults delete app.synctogether 2>/dev/null || true
defaults delete app.synctogether.b 2>/dev/null || true

# Remove preference plist files
rm -f "$HOME/Library/Preferences/app.synctogether.plist" 2>/dev/null || true
rm -f "$HOME/Library/Preferences/app.synctogether.b.plist" 2>/dev/null || true

# Remove container caches if present
rm -rf "$HOME/Library/Containers/app.synctogether" 2>/dev/null || true
rm -rf "$HOME/Library/Containers/app.synctogether.b" 2>/dev/null || true

# Remove secondary test instance bundle
rm -rf "$REPO_ROOT/build/st-instance-b" 2>/dev/null || true

success "Local desktop sessions and preferences completely cleared."

# ------------------------------------------------------------------------------
# 3. Local Supabase Database Reset
# ------------------------------------------------------------------------------
info "Checking local Supabase container..."

if docker ps --filter "name=supabase_db" --format "{{.Names}}" | grep -q "supabase_db"; then
  info "Resetting local Supabase database to pristine state..."
  supabase db reset
  success "Local database re-migrated with 0 users."
else
  warn "Local Supabase stack is not currently running. Skipping DB reset (start with ./scripts/dev.sh)."
fi

# ------------------------------------------------------------------------------
# 4. Paddle Sandbox Cleanup
# ------------------------------------------------------------------------------
if [ -n "${PADDLE_KEY:-}" ] && [[ "$PADDLE_KEY" =~ ^pdl_sdbx_ ]]; then
  info "Checking for active subscriptions in Paddle Sandbox..."

  ACTIVE_SUBS=$(curl -s "https://sandbox-api.paddle.com/subscriptions?status=active,trialing,paused" \
    -H "Authorization: Bearer $PADDLE_KEY" | grep -o '"id":"sub_[^"]*"' | cut -d '"' -f4 | sort -u || true)

  if [ -n "$ACTIVE_SUBS" ]; then
    for SUB_ID in $ACTIVE_SUBS; do
      info "Canceling sandbox subscription $SUB_ID..."
      curl -s -X POST "https://sandbox-api.paddle.com/subscriptions/$SUB_ID/cancel" \
        -H "Authorization: Bearer $PADDLE_KEY" \
        -H "Content-Type: application/json" \
        -d '{"effective_from":"immediately"}' > /dev/null || true
    done
    success "Canceled all active Paddle Sandbox subscriptions."
  else
    success "Paddle Sandbox has 0 active subscriptions."
  fi

  info "Checking for active customers in Paddle Sandbox..."
  ACTIVE_CUSTOMERS=$(curl -s "https://sandbox-api.paddle.com/customers?status=active" \
    -H "Authorization: Bearer $PADDLE_KEY" | grep -o '"id":"ctm_[^"]*"' | cut -d '"' -f4 | sort -u || true)

  if [ -n "$ACTIVE_CUSTOMERS" ]; then
    for CUST_ID in $ACTIVE_CUSTOMERS; do
      info "Archiving sandbox customer $CUST_ID..."
      curl -s -X PATCH "https://sandbox-api.paddle.com/customers/$CUST_ID" \
        -H "Authorization: Bearer $PADDLE_KEY" \
        -H "Content-Type: application/json" \
        -d '{"status":"archived"}' > /dev/null || true
    done
    success "Archived all active Paddle Sandbox customers."
  else
    success "Paddle Sandbox has 0 active customers."
  fi
else
  info "No Paddle sandbox API key found in website/.env.local. Skipping Paddle sandbox cleanup."
fi

# ------------------------------------------------------------------------------
# 5. Temporary Logs & Files Cleanup
# ------------------------------------------------------------------------------
info "Cleaning local temporary files and logs..."
rm -f /tmp/st-b.log /tmp/pt-b.log 2>/dev/null || true
rm -rf /tmp/synctogether-logs/*.log 2>/dev/null || true
success "Local logs and temporary artifacts cleaned."

banner "Clean Slate Ready"
echo -e "${GREEN}All local users, sessions, database state, and sandbox subscriptions have been reset.${NC}"
echo -e "You can now launch the app or website with a completely clean slate!\n"
