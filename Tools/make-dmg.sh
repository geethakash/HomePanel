#!/bin/bash
# Builds an ad-hoc signed Release of HomePanel and packs it into a DMG.
#
#   Tools/make-dmg.sh
#
# Output: build.noindex/release/HomePanel-<version>.dmg and its .sha256.
#
# No Apple Developer account is needed. The app is signed ad hoc (not with a Developer ID)
# and isn't notarized, so the first launch on another Mac needs System Settings → Privacy &
# Security → Open Anyway. Without a provisioning profile it has no App Group or Keychain
# group; it keeps its settings in its own container and the token in the login keychain.
#
# BUNDLE_ID_PREFIX sets the bundle ID prefix (default: io.github.<GitHub owner>).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"?.*/\1/p' project.yml)
OWNER=$( (git config --get remote.origin.url 2>/dev/null || true) | sed -nE 's#.*github\.com[:/]([^/]+)/.*#\1#p' | tr 'A-Z' 'a-z')
PREFIX="${BUNDLE_ID_PREFIX:-io.github.${OWNER:-homepanel}}"
DERIVED=build.noindex/adhoc
OUT=build.noindex/release

echo "HomePanel $VERSION ($PREFIX.HomePanel)"

# project.yml reads Config/Signing.xcconfig; its values are overridden below.
[ -f Config/Signing.xcconfig ] || cp Config/Signing.xcconfig.template Config/Signing.xcconfig
xcodegen generate --quiet

xcodebuild -project HomePanel.xcodeproj -scheme HomePanel -configuration Release \
  -derivedDataPath "$DERIVED" -destination "generic/platform=macOS" \
  BUNDLE_ID_PREFIX="$PREFIX" \
  DEVELOPMENT_TEAM="" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" PROVISIONING_PROFILE_SPECIFIER="" \
  CODE_SIGN_ENTITLEMENTS=Config/AdHoc.entitlements HP_APP_GROUP="" HP_KEYCHAIN_GROUP="" \
  build | grep -E "error:|warning:|BUILD" || true

APP="$DERIVED/Build/Products/Release/HomePanel.app"
[ -d "$APP" ] || { echo "Build failed" >&2; exit 1; }
codesign --verify --deep --strict "$APP"

rm -rf "$OUT"
mkdir -p "$OUT/stage"
ditto "$APP" "$OUT/stage/HomePanel.app"
ln -s /Applications "$OUT/stage/Applications"

DMG="$OUT/HomePanel-$VERSION.dmg"
hdiutil create -quiet -volname "HomePanel $VERSION" -srcfolder "$OUT/stage" -format UDZO -ov "$DMG"
rm -rf "$OUT/stage"
(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

echo "Created $DMG"
cat "$DMG.sha256"
