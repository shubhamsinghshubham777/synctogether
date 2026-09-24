#!/bin/zsh
# ==============================================================================
# SyncTogether iOS Device Runner
# ------------------------------------------------------------------------------
# Automatically determines the host Mac's LAN IP address, verifies the local
# Supabase Docker stack is reachable, and launches the app on a connected physical
# iPhone or iPad with the LAN backend dynamically injected via --dart-define.
#
# Usage:
#   ./scripts/run-ios.sh                    # Launch on connected iOS device (default)
#   ./scripts/run-ios.sh -d <device_id>     # Target a specific device ID
#   ./scripts/run-ios.sh --profile          # Run in profile mode
#   ./scripts/run-ios.sh --release          # Run in release mode
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# ANSI Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "\n${BOLD}${CYAN}=== SyncTogether iOS Device Runner ===${NC}"

# 1. Resolve host Mac's Wi-Fi / Ethernet LAN IP
HOST_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || ipconfig getifaddr bridge0 2>/dev/null || true)"

if [[ -z "$HOST_IP" ]]; then
  LOCAL_NAME="$(scutil --get LocalHostName 2>/dev/null || true)"
  if [[ -n "$LOCAL_NAME" ]]; then
    HOST_IP="${LOCAL_NAME}.local"
    echo -e "  ℹ️  LAN IP not detected on en0/en1. Using mDNS hostname: ${BOLD}${HOST_IP}${NC}"
  else
    echo -e "  ${RED}Error: Unable to determine Mac LAN IP or local hostname.${NC}" >&2
    echo -e "  Ensure your Mac is connected to Wi-Fi or Ethernet." >&2
    exit 1
  fi
else
  echo -e "  📡 Detected Mac LAN IP: ${BOLD}${GREEN}${HOST_IP}${NC}"
fi

LOCAL_BACKEND_URL="http://${HOST_IP}:54321"

# 2. Check if local Supabase stack is running
if ! curl -s -m 2 "http://127.0.0.1:54321/" >/dev/null 2>&1; then
  echo -e "  ${YELLOW}⚠️  Warning: Local Supabase does not seem to be running on port 54321.${NC}"
  echo -e "     If you haven't started the backend yet, run: ${BOLD}./scripts/dev.sh${NC}"
  echo -e "     Continuing anyway in case it is starting up...\n"
else
  echo -e "  ✅ Local Supabase Docker backend is responding on port 54321"
fi

# 3. Build argument list
ARGS=()

# Include .env defines if present
if [[ -f "$REPO_ROOT/.env" ]]; then
  ARGS+=("--dart-define-from-file=$REPO_ROOT/.env")
fi

# Inject the dynamic LAN backend URL (CLI --dart-define overrides values from .env file)
ARGS+=("--dart-define=SUPABASE_URL_LOCAL=${LOCAL_BACKEND_URL}")

# Check if a device was explicitly passed in arguments
HAS_DEVICE_FLAG=false
for arg in "$@"; do
  if [[ "$arg" == "-d" || "$arg" == "--device-id" || "$arg" == -d=* || "$arg" == --device-id=* ]]; then
    HAS_DEVICE_FLAG=true
    break
  fi
done

if [[ "$HAS_DEVICE_FLAG" == false ]]; then
  ARGS+=("-d" "ios")
fi

# Append any remaining user-supplied flags
ARGS+=("$@")

echo -e "  📱 Backend URL passed to iPhone: ${BOLD}${CYAN}${LOCAL_BACKEND_URL}${NC}"
echo -e "  🚀 Executing: ${YELLOW}fvm flutter run ${ARGS[*]}${NC}\n"

exec fvm flutter run "${ARGS[@]}"
