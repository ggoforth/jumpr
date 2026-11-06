#!/bin/bash
# Builds a release binary and assembles build/Jumpr.app with Sparkle.framework embedded.
#
# Environment (defaults make a development build: host arch, Apple Development, updates off):
#   JUMPR_BUILD_DIR           where Jumpr.app goes                     (default build)
#   JUMPR_ARCHS               space-separated archs, e.g. "arm64 x86_64" (default host only)
#   JUMPR_NO_SIGN=1           leave the app unsigned; scripts/release.sh signs it itself
#   CODESIGN_IDENTITY         signing identity            (default "Apple Development")
#   CODESIGN_OPTIONS          extra codesign arguments, split on spaces, so no single
#                             argument may contain one; e.g. "--options runtime --timestamp"
#                                                          (default none)
#   JUMPR_FEED_URL            Sparkle appcast address      (default file:///dev/null: updates off)
#   JUMPR_SPARKLE_PUBLIC_KEY  Sparkle EdDSA public key     (default a placeholder: updates off)
#   JUMPR_VERSION             CFBundleShortVersionString   (default the one in Resources/Info.plist)
#   JUMPR_BUILD_NUMBER        CFBundleVersion, a positive integer Sparkle compares with the
#                             appcast's; it must rise with every release
#                                                          (default the one in Resources/Info.plist)
#   JUMPR_RELEASE=1           a release build (scripts/release.sh sets it)
#   JUMPR_ALLOW_PLACEHOLDER_KEY=1  release test builds only (release.sh --skip-notarize):
#                             accept the placeholder key, so updates stay off in that build
#
# A release build (JUMPR_RELEASE=1, or an identity starting with "Developer ID") fails
# unless the feed is an https URL, the key is base64 of exactly 32 bytes (UpdatePolicy's
# rule), and JUMPR_VERSION and JUMPR_BUILD_NUMBER are both given.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "build-app.sh: $*" >&2; exit 1; }
# Strips leading and trailing whitespace.
trim() { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; printf '%s' "$v"; }

# A stable identity keeps the Accessibility grant across rebuilds.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Apple Development}"
CODESIGN_OPTIONS="${CODESIGN_OPTIONS:-}"
# Switched off by default, so a development build never updates itself.
JUMPR_FEED_URL="${JUMPR_FEED_URL:-file:///dev/null}"
# Must match UpdatePolicy.placeholderPublicKey; the app never starts Sparkle with it.
JUMPR_SPARKLE_PUBLIC_KEY="$(trim "${JUMPR_SPARKLE_PUBLIC_KEY:-PLACEHOLDER-NOT-A-REAL-SPARKLE-KEY}")"
JUMPR_FEED_URL="$(trim "$JUMPR_FEED_URL")"
JUMPR_VERSION="$(trim "${JUMPR_VERSION:-}")"
JUMPR_BUILD_NUMBER="$(trim "${JUMPR_BUILD_NUMBER:-}")"
RELEASE="${JUMPR_RELEASE:-0}"
[[ "$CODESIGN_IDENTITY" == "Developer ID"* ]] && RELEASE=1

if [ -n "$JUMPR_BUILD_NUMBER" ] && ! [[ "$JUMPR_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    fail "JUMPR_BUILD_NUMBER must be a positive integer, got '$JUMPR_BUILD_NUMBER'"
fi
if [[ "$JUMPR_VERSION" =~ [[:space:]] ]]; then
    fail "JUMPR_VERSION must not contain whitespace, got '$JUMPR_VERSION'"
fi
if [ "$RELEASE" = 1 ]; then
    # Release: never ship with updates silently off or a build number Sparkle cannot compare.
    # UpdatePolicy.feedPattern, character for character: dotted host, optional port, plain path.
    FEED_RE='^https://[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:[0-9]+)?(/[A-Za-z0-9._~%!$&'"'"'()*+,;=:/-]*)?$'
    [[ "$JUMPR_FEED_URL" =~ $FEED_RE ]] \
        || fail "release build: JUMPR_FEED_URL must be an https URL, got '$JUMPR_FEED_URL'"
    # Exactly the base64 strings that decode to 32 bytes: 43 characters, then one '='.
    if ! [[ "$JUMPR_SPARKLE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
        if [ "${JUMPR_ALLOW_PLACEHOLDER_KEY:-0}" = 1 ] \
            && [ "$JUMPR_SPARKLE_PUBLIC_KEY" = PLACEHOLDER-NOT-A-REAL-SPARKLE-KEY ]; then
            echo "build-app.sh: WARNING: placeholder Sparkle key allowed; this build's updates are OFF" >&2
        else
            fail "release build: JUMPR_SPARKLE_PUBLIC_KEY must be a Sparkle EdDSA public key (base64 of 32 bytes)"
        fi
    fi
    [ -n "$JUMPR_VERSION" ] || fail "release build: JUMPR_VERSION is required"
    [ -n "$JUMPR_BUILD_NUMBER" ] || fail "release build: JUMPR_BUILD_NUMBER is required"
fi

read -r -a EXTRA_OPTIONS <<< "$CODESIGN_OPTIONS"
sign() {
    # The ${a[@]+...} form keeps bash 3.2 (macOS) happy with an empty array under `set -u`.
    codesign --force --sign "$CODESIGN_IDENTITY" ${EXTRA_OPTIONS[@]+"${EXTRA_OPTIONS[@]}"} "$@"
}

BUILD_FLAGS=(-c release)
for arch in ${JUMPR_ARCHS:-}; do
    BUILD_FLAGS+=(--arch "$arch")
done

swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

APP="${JUMPR_BUILD_DIR:-build}/Jumpr.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Jumpr" "$APP/Contents/MacOS/Jumpr"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
plutil -replace SUFeedURL -string "$JUMPR_FEED_URL" "$APP/Contents/Info.plist"
plutil -replace SUPublicEDKey -string "$JUMPR_SPARKLE_PUBLIC_KEY" "$APP/Contents/Info.plist"
if [ -n "$JUMPR_VERSION" ]; then
    plutil -replace CFBundleShortVersionString -string "$JUMPR_VERSION" "$APP/Contents/Info.plist"
fi
if [ -n "$JUMPR_BUILD_NUMBER" ]; then
    plutil -replace CFBundleVersion -string "$JUMPR_BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

# ditto keeps the framework's symlinks and permissions.
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

if [ "${JUMPR_NO_SIGN:-0}" = 1 ]; then
    echo "Built $APP (unsigned)"
    exit 0
fi

# Inside out, in the order Sparkle documents (sparkle-project.org/documentation/sandboxing),
# never --deep. Jumpr is not sandboxed and does not use the XPC services, but they ship in
# the framework and must carry the same signature as everything else. scripts/release.sh
# repeats this order in its sign_app with the Developer ID identity.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP"

codesign --verify --deep --strict "$APP"
echo "Built $APP"
