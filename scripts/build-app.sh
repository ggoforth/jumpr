#!/bin/bash
# Builds a release binary and assembles a signed build/Jumpr.app.
#
# Environment (defaults make a development build):
#   CODESIGN_IDENTITY         signing identity            (default "Apple Development")
#   CODESIGN_OPTIONS          extra codesign arguments, e.g. "--options runtime --timestamp"
#                             for a Developer ID release   (default none)
#   JUMPR_FEED_URL            Sparkle appcast address      (default file:///dev/null: updates off)
#   JUMPR_SPARKLE_PUBLIC_KEY  Sparkle EdDSA public key     (default a placeholder: updates off)
set -euo pipefail
cd "$(dirname "$0")/.."

# A stable identity keeps the Accessibility grant across rebuilds.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Apple Development}"
CODESIGN_OPTIONS="${CODESIGN_OPTIONS:-}"
# Switched off as in Watchflows' Debug build, so a development build never updates itself.
JUMPR_FEED_URL="${JUMPR_FEED_URL:-file:///dev/null}"
# Must match UpdatePolicy.placeholderPublicKey; the app never starts Sparkle with it.
JUMPR_SPARKLE_PUBLIC_KEY="${JUMPR_SPARKLE_PUBLIC_KEY:-PLACEHOLDER-NOT-A-REAL-SPARKLE-KEY}"

read -r -a EXTRA_OPTIONS <<< "$CODESIGN_OPTIONS"
sign() {
    # The ${a[@]+...} form keeps bash 3.2 (macOS) happy with an empty array under `set -u`.
    codesign --force --sign "$CODESIGN_IDENTITY" ${EXTRA_OPTIONS[@]+"${EXTRA_OPTIONS[@]}"} "$@"
}

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP=build/Jumpr.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Jumpr" "$APP/Contents/MacOS/Jumpr"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
plutil -replace SUFeedURL -string "$JUMPR_FEED_URL" "$APP/Contents/Info.plist"
plutil -replace SUPublicEDKey -string "$JUMPR_SPARKLE_PUBLIC_KEY" "$APP/Contents/Info.plist"

# ditto keeps the framework's symlinks and permissions.
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

# Inside out, in the order Sparkle documents (sparkle-project.org/documentation/sandboxing),
# never --deep. Jumpr is not sandboxed and does not use the XPC services, but they ship in
# the framework and must carry the same signature as everything else.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP"

codesign --verify --deep --strict "$APP"
echo "Built $APP"
