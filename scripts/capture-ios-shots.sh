#!/bin/zsh
# Shoots the App Store set on a simulator: runs the demo capture flow and takes
# a `simctl` screenshot at every `[SHOT] <name>` marker it prints.
#   scripts/capture-ios-shots.sh <udid> <out-dir> [display-uuid]
# display-uuid targets one display of an iPhone Duo (see docs/foldables.md).
set -euo pipefail
cd "$(dirname "$0")/.."
UDID=$1; OUT=$2; DISPLAY_ID=${3:-}
mkdir -p "$OUT"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null || true
fvm flutter run -d "$UDID" --dart-define=DEMO_MODE=true --dart-define=CAPTURE_STORE=true \
  --dart-define=STORE_TARGET=ios 2>&1 | while read -r line; do
  case "$line" in
    *"[SHOT] done"*) pkill -f "flutter_tools.*run -d $UDID" || true; break ;;
    *"[SHOT] "*)
      name=${line##*\[SHOT\] }
      if [[ -n "$DISPLAY_ID" ]]; then xcrun simctl io "$UDID" screenshot --display="$DISPLAY_ID" "$OUT/$name.png"
      else xcrun simctl io "$UDID" screenshot "$OUT/$name.png"; fi
      echo "shot $name" ;;
  esac
done
