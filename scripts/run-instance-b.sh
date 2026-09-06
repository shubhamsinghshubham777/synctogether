#!/bin/zsh
# Instance B launcher for dual-instance room synchronization testing.
# Clones the debug SyncTogether.app under a different bundle ID so it gets its
# own preferences domain (= its own Supabase session / guest identity), then
# launches it via macOS LaunchServices (`open -n`).
#
# Usage:
#   ./scripts/run-instance-b.sh                 # Launch Instance B
#   ./scripts/run-instance-b.sh --build         # Force rebuild debug app before launching
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/build/macos/Build/Products/Debug/SyncTogether.app"
DEST_DIR="$REPO/build/st-instance-b"
DEST="$DEST_DIR/SyncTogether B.app"

FORCE_BUILD=false

for arg in "$@"; do
  case "$arg" in
    --build) FORCE_BUILD=true ;;
  esac
done

if [[ "$FORCE_BUILD" == true ]] || [[ ! -d "$SRC" ]]; then
  echo "Building fresh macOS debug client (fvm flutter build macos --debug)..."
  (cd "$REPO" && fvm flutter build macos --debug)
fi

echo "Cloning $SRC -> $DEST"
rm -rf "$DEST_DIR" && mkdir -p "$DEST_DIR"
cp -R "$SRC" "$DEST"

PLIST="$DEST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.synctogether.b" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName SyncTogether B" "$PLIST"

# Create clean ad-hoc entitlements by stripping restricted Apple entitlements
# (like com.apple.developer.applesignin) which cause AMFI launchd spawn failures on ad-hoc signatures.
ADHOC_ENTITLEMENTS="/tmp/st-b-entitlements-$$.plist"
python3 -c "
import plistlib
ent_path = '$REPO/macos/Runner/DebugProfile.entitlements'
with open(ent_path, 'rb') as f:
    plist = plistlib.load(f)
plist.pop('com.apple.developer.applesignin', None)
with open('$ADHOC_ENTITLEMENTS', 'wb') as f:
    plistlib.dump(plist, f)
"
trap 'rm -f "$ADHOC_ENTITLEMENTS"' EXIT

echo "Re-signing Instance B (ad-hoc)..."
codesign --force --deep --sign - \
  --entitlements "$ADHOC_ENTITLEMENTS" \
  "$DEST" 2>/dev/null

echo "Launching Instance B..."
open -n "$DEST"
