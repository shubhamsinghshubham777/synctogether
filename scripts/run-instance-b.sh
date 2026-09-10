#!/bin/zsh
# Instance B launcher for dual-instance room synchronization testing.
# Clones the debug SyncTogether.app under a different bundle ID so it gets its
# own preferences domain (= its own Supabase session / guest identity), then
# launches it via macOS LaunchServices (`open -n`).
#
# Usage:
#   ./scripts/run-instance-b.sh                                      # Launch Instance B (reuses existing debug build)
#   ./scripts/run-instance-b.sh --build                              # Force rebuild debug app before launching
#   ./scripts/run-instance-b.sh --dart-define-from-file=.env         # Rebuild with environment defines and launch
#   ./scripts/run-instance-b.sh --dart-define-from-file              # Rebuild with .env (if present) and launch
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/build/macos/Build/Products/Debug/SyncTogether.app"
DEST_DIR="$REPO/build/st-instance-b"
DEST="$DEST_DIR/SyncTogether B.app"

FORCE_BUILD=false
DEFINE_FILES=()
EXTRA_BUILD_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      FORCE_BUILD=true
      shift
      ;;
    --dart-define-from-file=*)
      path="${1#*=}"
      if [[ "$path" != /* ]]; then
        path="$(pwd)/$path"
      fi
      if [[ ! -f "$path" ]]; then
        echo "Error: Define file not found at '$path'" >&2
        exit 1
      fi
      DEFINE_FILES+=("$path")
      FORCE_BUILD=true
      shift
      ;;
    --dart-define-from-file)
      if [[ $# -ge 2 ]] && [[ ! "$2" =~ ^-- ]]; then
        path="$2"
        if [[ "$path" != /* ]]; then
          path="$(pwd)/$path"
        fi
        if [[ ! -f "$path" ]]; then
          echo "Error: Define file not found at '$path'" >&2
          exit 1
        fi
        DEFINE_FILES+=("$path")
        shift 2
      else
        if [[ -f "$REPO/.env" ]]; then
          DEFINE_FILES+=("$REPO/.env")
        else
          echo "Error: --dart-define-from-file requires a file path (or a .env file in the repository root)." >&2
          exit 1
        fi
        shift
      fi
      FORCE_BUILD=true
      ;;
    --dart-define=*)
      EXTRA_BUILD_ARGS+=("$1")
      FORCE_BUILD=true
      shift
      ;;
    --dart-define)
      if [[ $# -ge 2 ]] && [[ ! "$2" =~ ^-- ]]; then
        EXTRA_BUILD_ARGS+=("--dart-define" "$2")
        shift 2
      else
        echo "Error: --dart-define requires key=value" >&2
        exit 1
      fi
      FORCE_BUILD=true
      ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --build                             Force rebuild debug app before launching"
      echo "  --dart-define-from-file[=<path>]    Pass compile-time environment definitions file to flutter build (forces rebuild)"
      echo "  --dart-define=<key=value>           Pass compile-time environment key-value to flutter build (forces rebuild)"
      echo "  -h, --help                          Show this help message"
      exit 0
      ;;
    *)
      echo "Warning: Unknown argument '$1' ignored" >&2
      shift
      ;;
  esac
done

# Check DART_DEFINE_FROM_FILE environment variable fallback if not passed explicitly on CLI
if [[ ${#DEFINE_FILES[@]} -eq 0 ]] && [[ -n "${DART_DEFINE_FROM_FILE:-}" ]]; then
  path="$DART_DEFINE_FROM_FILE"
  if [[ "$path" != /* ]]; then
    path="$(pwd)/$path"
  fi
  if [[ ! -f "$path" ]]; then
    echo "Error: Define file from DART_DEFINE_FROM_FILE not found at '$path'" >&2
    exit 1
  fi
  DEFINE_FILES+=("$path")
  FORCE_BUILD=true
fi

BUILD_ARGS=(build macos --debug)
for df in "${DEFINE_FILES[@]}"; do
  BUILD_ARGS+=(--dart-define-from-file="$df")
done
if [[ ${#EXTRA_BUILD_ARGS[@]} -gt 0 ]]; then
  BUILD_ARGS+=("${EXTRA_BUILD_ARGS[@]}")
fi

if [[ "$FORCE_BUILD" == true ]] || [[ ! -d "$SRC" ]]; then
  echo "Building fresh macOS debug client (fvm flutter ${BUILD_ARGS[*]})..."
  (cd "$REPO" && fvm flutter "${BUILD_ARGS[@]}")
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
