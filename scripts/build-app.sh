#!/bin/bash
# Builds a release binary and assembles a signed build/Jumpr.app.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Jumpr"

APP=build/Jumpr.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Jumpr"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# A stable identity keeps the Accessibility grant across rebuilds.
codesign --force --sign "Apple Development" "$APP"
echo "Built $APP"
