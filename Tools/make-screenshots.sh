#!/bin/bash
# Renders the README screenshots (docs/screenshots/*.png) from a made-up demo home.
#
#   Tools/make-screenshots.sh
#
# Builds a Debug copy (unsandboxed, ad-hoc signed, separate bundle ID so it never touches
# an installed HomePanel) and runs it with --render-screenshots. No Home Assistant needed.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$PWD/docs/screenshots"
DERIVED=build.noindex/screenshots

[ -f Config/Signing.xcconfig ] || cp Config/Signing.xcconfig.template Config/Signing.xcconfig
xcodegen generate --quiet

xcodebuild -project HomePanel.xcodeproj -scheme HomePanel -configuration Debug \
  -derivedDataPath "$DERIVED" -destination "generic/platform=macOS" \
  BUNDLE_ID_PREFIX=dev.homepanel.screenshots ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES \
  DEVELOPMENT_TEAM="" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" PROVISIONING_PROFILE_SPECIFIER="" \
  CODE_SIGN_ENTITLEMENTS="" HP_APP_GROUP="" HP_KEYCHAIN_GROUP="" \
  build | grep -E "error:|BUILD" || true

APP="$DERIVED/Build/Products/Debug/HomePanel.app"
[ -d "$APP" ] || { echo "Build failed" >&2; exit 1; }

mkdir -p "$OUT"
"$APP/Contents/MacOS/HomePanel" --render-screenshots "$OUT"
echo "Screenshots in $OUT"
