#!/usr/bin/env bash
# scripts/package-macos-store.sh
#
# Signs and packages the SyncTogether macOS app bundle into a Mac App Store
# installer package (.pkg) using Apple Distribution certificates and productbuild.
# Usable both locally and in CI/CD (GitHub Actions).
#
# Environment variables:
#   APP_SIGN_IDENTITY       - Code signing identity for .app (e.g. "Apple Distribution: Shubham Singh (6NKFZTB3JJ)"
#                             or "3rd Party Mac Developer Application: Shubham Singh (6NKFZTB3JJ)")
#   INSTALLER_SIGN_IDENTITY - Installer signing identity for .pkg (e.g. "3rd Party Mac Developer Installer: ...")
#   PROVISIONING_PROFILE    - Path to .provisionprofile file
#   APP_PATH                - Path to SyncTogether.app (default: build/macos/Build/Products/Release/SyncTogether.app)
#   OUTPUT_PKG              - Path to output .pkg package

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_PATH="${APP_PATH:-build/macos/Build/Products/Release/SyncTogether.app}"
ENTITLEMENTS="${ROOT_DIR}/macos/Runner/Release-Store.entitlements"

if [ ! -d "$APP_PATH" ]; then
  echo "::error::App bundle not found at '$APP_PATH'. Run 'fvm flutter build macos --release' first."
  exit 1
fi

VERSION=$(grep '^version:' pubspec.yaml | cut -d ' ' -f 2 | cut -d '+' -f 1)
OUTPUT_PKG="${OUTPUT_PKG:-SyncTogether-${VERSION}-MacAppStore.pkg}"

# 1. Strip external updater frameworks (Sparkle / auto_updater) to comply with App Store rules
if [ -d "$APP_PATH/Contents/Frameworks/Sparkle.framework" ]; then
  echo "==> Removing Sparkle.framework from Mac App Store bundle to comply with App Store sandbox..."
  rm -rf "$APP_PATH/Contents/Frameworks/Sparkle.framework"
fi

# Remove any sparkle / update helper executables if present
find "$APP_PATH/Contents" -type f \( -name "Autoupdate" -o -name "sign_update" \) -exec rm -f {} + 2>/dev/null || true

# Strip Sparkle keys from Info.plist so Apple's static validator detects no updater configuration
if [ -f "$APP_PATH/Contents/Info.plist" ]; then
  /usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Delete :SUEnableAutomaticChecks" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
fi

# 2. Embed Provisioning Profile if present
if [ -n "${PROVISIONING_PROFILE:-}" ] && [ -f "$PROVISIONING_PROFILE" ]; then
  echo "==> Embedding provisioning profile: $PROVISIONING_PROFILE"
  cp "$PROVISIONING_PROFILE" "$APP_PATH/Contents/embedded.provisionprofile"
elif [ -f "${ROOT_DIR}/embedded.provisionprofile" ]; then
  echo "==> Embedding root provisioning profile..."
  cp "${ROOT_DIR}/embedded.provisionprofile" "$APP_PATH/Contents/embedded.provisionprofile"
fi

# 3. Detect signing identity if not explicitly passed
if [ -z "${APP_SIGN_IDENTITY:-}" ]; then
  echo "==> Probing keychain for Apple Distribution / 3rd Party Mac Developer Application identity..."
  APP_SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep -E "Apple Distribution|3rd Party Mac Developer Application" | head -n 1 | sed -n 's/.*"\(.*\)".*/\1/p' || true)
fi

if [ -z "${INSTALLER_SIGN_IDENTITY:-}" ]; then
  echo "==> Probing keychain for Mac Installer identity..."
  INSTALLER_SIGN_IDENTITY=$(security find-identity -v | grep -E "3rd Party Mac Developer Installer|Apple Distribution" | head -n 1 | sed -n 's/.*"\(.*\)".*/\1/p' || true)
fi

echo "==> App Bundle: $APP_PATH"
echo "==> Entitlements: $ENTITLEMENTS"
echo "==> App Signing Identity: ${APP_SIGN_IDENTITY:-[Unsigned/Ad-Hoc]}"
echo "==> Installer Signing Identity: ${INSTALLER_SIGN_IDENTITY:-[Unsigned]}"
echo "==> Output Package: $OUTPUT_PKG"

# 4. Code sign nested libraries and frameworks if signing identity exists
if [ -n "${APP_SIGN_IDENTITY:-}" ]; then
  echo "==> Deep-signing nested libraries and frameworks with $APP_SIGN_IDENTITY..."

  find "$APP_PATH/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "*.so" \) 2>/dev/null | while read -r lib; do
    echo "    Signing dylib: $(basename "$lib")"
    codesign --force --verbose --timestamp --options runtime --sign "$APP_SIGN_IDENTITY" "$lib"
  done

  find "$APP_PATH/Contents/Frameworks" -depth -type d -name "*.framework" 2>/dev/null | while read -r framework; do
    echo "    Signing framework: $(basename "$framework")"
    codesign --force --verbose --timestamp --options runtime --sign "$APP_SIGN_IDENTITY" "$framework"
  done

  find "$APP_PATH/Contents/MacOS" -type f ! -name "SyncTogether" 2>/dev/null | while read -r bin; do
    echo "    Signing helper binary: $(basename "$bin")"
    codesign --force --verbose --timestamp --options runtime --sign "$APP_SIGN_IDENTITY" "$bin"
  done

  echo "==> Signing main application bundle with Release-Store entitlements..."
  codesign --force --verbose --timestamp --options runtime --entitlements "$ENTITLEMENTS" --sign "$APP_SIGN_IDENTITY" "$APP_PATH"

  echo "==> Verifying application code signature..."
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
else
  echo "::warning::No Apple Distribution identity found. Skipping deep codesigning (bundle remains unsigned)."
fi

# 5. Build .pkg installer package via productbuild
rm -f "$OUTPUT_PKG"
if [ -n "${INSTALLER_SIGN_IDENTITY:-}" ]; then
  echo "==> Building signed installer package: $OUTPUT_PKG..."
  productbuild --component "$APP_PATH" /Applications --sign "$INSTALLER_SIGN_IDENTITY" "$OUTPUT_PKG"
else
  echo "::warning::No Mac Installer signing identity found. Packaging unsigned .pkg..."
  productbuild --component "$APP_PATH" /Applications "$OUTPUT_PKG"
fi

echo "==> Successfully generated Mac App Store package: $OUTPUT_PKG"
ls -lh "$OUTPUT_PKG"
