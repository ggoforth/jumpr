#!/bin/bash
# Builds a release binary and assembles a signed build/Jumpr.app.
#
# Defaults are the dev build. scripts/release.sh overrides them:
#   JUMPR_BUILD_DIR  where Jumpr.app goes          (default: build)
#   JUMPR_ARCHS      space-separated archs, e.g. "arm64 x86_64" (default: host only)
#   JUMPR_NO_SIGN=1  leave the app unsigned        (default: sign with Apple Development)
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_FLAGS=(-c release)
for arch in ${JUMPR_ARCHS:-}; do
    BUILD_FLAGS+=(--arch "$arch")
done

swift build "${BUILD_FLAGS[@]}"
BIN="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/Jumpr"

APP="${JUMPR_BUILD_DIR:-build}/Jumpr.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Jumpr"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

if [ "${JUMPR_NO_SIGN:-0}" != 1 ]; then
    # A stable identity keeps the Accessibility grant across rebuilds.
    codesign --force --sign "Apple Development" "$APP"
fi
echo "Built $APP"
