#!/usr/bin/env bash
# scripts/package-macos-direct.sh
#
# Signs, packages, notarizes, and staples the SyncTogether macOS app bundle and DMG.
# Usable both locally and in CI/CD (GitHub Actions).
#
# Environment variables:
#   SIGN_IDENTITY                - Code signing identity (e.g. "Developer ID Application: Shubham Singh (6NKFZTB3JJ)")
#                                  Defaults to the first Developer ID Application found in the keychain.
#   APPLE_ID                     - Apple account email for notarization
#   APPLE_TEAM_ID                - 10-char Team ID (defaults to 6NKFZTB3JJ)
#   APPLE_APP_SPECIFIC_PASSWORD  - App-specific password generated from appleid.apple.com
#   APP_PATH                     - Path to SyncTogether.app (default: build/macos/Build/Products/Release/SyncTogether.app)
#   SKIP_NOTARIZATION            - Set to "true" to skip notarization/stapling (useful for local offline testing)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_PATH="${APP_PATH:-build/macos/Build/Products/Release/SyncTogether.app}"
ENTITLEMENTS="${ROOT_DIR}/macos/Runner/Release.entitlements"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-false}"

# Helper to read secrets from .env if unset in environment
get_env_val() {
  local key="$1"
  if [ -f "${ROOT_DIR}/.env" ]; then
    python3 -c "
import sys
target = sys.argv[1]
with open('${ROOT_DIR}/.env', 'r', encoding='utf-8', errors='ignore') as f:
    for line in f:
        line = line.strip()
        if line.startswith(target + '='):
            val = line.split('=', 1)[1].strip()
            if (val.startswith('\"') and val.endswith('\"')) or (val.startswith(\"'\") and val.endswith(\"'\")):
                val = val[1:-1]
            print(val)
            break
" "$key" 2>/dev/null || true
  fi
}

APPLE_ID="${APPLE_ID:-$(get_env_val APPLE_ID)}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-$(get_env_val APPLE_TEAM_ID)}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-6NKFZTB3JJ}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-$(get_env_val APPLE_APP_SPECIFIC_PASSWORD)}"

if [ ! -d "$APP_PATH" ]; then
  echo "::error::App bundle not found at '$APP_PATH'. Run 'fvm flutter build macos --release' first."
  exit 1
fi

# Detect signing identity if not explicitly passed
if [ -z "${SIGN_IDENTITY:-}" ]; then
  echo "==> Probing keychain for Developer ID Application identity..."
  # Match: "Developer ID Application: Shubham Singh (6NKFZTB3JJ)"
  SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -n 1 | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' || true)
  if [ -z "$SIGN_IDENTITY" ]; then
    CERT_B64="${MACOS_CERTIFICATE_BASE64:-$(get_env_val MACOS_CERTIFICATE_BASE64)}"
    CERT_PWD="${MACOS_CERTIFICATE_PASSWORD:-$(get_env_val MACOS_CERTIFICATE_PASSWORD)}"
    if [ -n "$CERT_B64" ]; then
      echo "==> Certificate not found in keychain; importing from environment into login keychain..."
      CERT_TMP="$(mktemp -t cert.XXXXXX.p12)"
      echo "$CERT_B64" | base64 --decode > "$CERT_TMP"
      security import "$CERT_TMP" -k ~/Library/Keychains/login.keychain-db -P "$CERT_PWD" -T /usr/bin/codesign -T /usr/bin/security || true
      rm -f "$CERT_TMP"
      SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -n 1 | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' || true)
    fi
  fi
  if [ -z "$SIGN_IDENTITY" ]; then
    echo "::error::No 'Developer ID Application' certificate found in the keychain."
    echo "Please import your .p12 certificate or specify SIGN_IDENTITY."
    exit 1
  fi
fi

echo "==> Using Code Signing Identity: $SIGN_IDENTITY"
echo "==> App Bundle: $APP_PATH"
echo "==> Entitlements: $ENTITLEMENTS"

# Extract version from pubspec.yaml
VERSION=$(grep '^version:' pubspec.yaml | cut -d ' ' -f 2 | cut -d '+' -f 1)
DMG_PATH="SyncTogether-${VERSION}-macOS.dmg"

# 1. Deep code-sign all nested dylibs, XPC services, helper apps, and frameworks from inside out
echo "==> Deep-signing nested libraries, XPC services, helper apps, and frameworks..."

# 1a. Sign individual dylibs and shared objects inside Frameworks
find "$APP_PATH/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "*.so" \) 2>/dev/null | while read -r lib; do
  echo "    Signing dylib: $(basename "$lib")"
  codesign --force --verbose --timestamp --options runtime --sign "$SIGN_IDENTITY" "$lib"
done

# 1b. Sign nested XPC services inside frameworks (e.g. Sparkle Downloader.xpc, Installer.xpc)
find "$APP_PATH/Contents/Frameworks" -type d -name "*.xpc" 2>/dev/null | while read -r xpc; do
  echo "    Signing XPC service: $(basename "$xpc")"
  codesign --force --verbose --timestamp --options runtime --sign "$SIGN_IDENTITY" "$xpc"
done

# 1c. Sign nested helper .app bundles inside frameworks (e.g. Sparkle Updater.app)
find "$APP_PATH/Contents/Frameworks" -type d -name "*.app" 2>/dev/null | while read -r helper_app; do
  echo "    Signing helper app: $(basename "$helper_app")"
  codesign --force --verbose --timestamp --options runtime --sign "$SIGN_IDENTITY" "$helper_app"
done

# 1d. Sign standalone executable binaries inside frameworks (e.g. Sparkle Autoupdate)
find "$APP_PATH/Contents/Frameworks" -type f -perm +111 ! -name "*.dylib" ! -name "*.so" 2>/dev/null | while read -r bin; do
  echo "    Signing framework binary: $(basename "$bin")"
  codesign --force --verbose --timestamp --options runtime --sign "$SIGN_IDENTITY" "$bin"
done

# 1e. Sign nested frameworks from deep to shallow
find "$APP_PATH/Contents/Frameworks" -depth -type d -name "*.framework" 2>/dev/null | while read -r framework; do
  echo "    Signing framework: $(basename "$framework")"
  codesign --force --verbose --timestamp --options runtime --sign "$SIGN_IDENTITY" "$framework"
done

# 1f. Sign any helper executables in Contents/MacOS (excluding main binary)
find "$APP_PATH/Contents/MacOS" -type f ! -name "SyncTogether" 2>/dev/null | while read -r bin; do
  echo "    Signing helper binary: $(basename "$bin")"
  codesign --force --verbose --timestamp --options runtime --sign "$SIGN_IDENTITY" "$bin"
done

# 2. Sign main application bundle with Release entitlements and hardened runtime
echo "==> Signing main application bundle..."
codesign --force --verbose --timestamp --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP_PATH"

echo "==> Verifying application code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "Application signature verified successfully."

# 3. Create DMG
echo "==> Packaging DMG: $DMG_PATH"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP_PATH" "$STAGE/SyncTogether.app"
ln -s /Applications "$STAGE/Applications"
if [ -f "macos/dmg/dmg_ds_store" ]; then
  cp macos/dmg/dmg_ds_store "$STAGE/.DS_Store"
fi

rm -f "$DMG_PATH"
hdiutil create \
  -volname "SyncTogether" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG_PATH"

# 4. Sign the DMG itself
echo "==> Signing DMG..."
codesign --force --verbose --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

# 5. Notarize and Staple (if credentials present and not skipped)
if [ "$SKIP_NOTARIZATION" = "true" ]; then
  echo "==> SKIP_NOTARIZATION is true. Skipping Apple Notary submission and stapling."
elif [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ] && [ -n "${APPLE_ID:-}" ]; then
  echo "==> Submitting DMG to Apple Notary Service..."
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait

  echo "==> Stapling notarization ticket to DMG..."
  xcrun stapler staple "$DMG_PATH"

  echo "==> Verifying Gatekeeper acceptance..."
  spctl --assess --type open --context context:primary-signature -v "$DMG_PATH"
  echo "DMG successfully notarized and stapled!"
else
  echo "::warning::Apple notarization credentials not provided (APPLE_ID or APPLE_APP_SPECIFIC_PASSWORD unset). Skipping notarization."
fi

echo "==> Completed packaging: $DMG_PATH"
