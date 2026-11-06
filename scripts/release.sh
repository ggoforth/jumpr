#!/bin/bash
# Builds build/release/Jumpr.zip: universal, Developer ID signed, notarized, stapled.
#
#   scripts/release.sh <version> [--skip-notarize]
#
# Env:
#   JUMPR_NOTARY_PROFILE  notarytool keychain profile (required unless --skip-notarize)
#   JUMPR_SIGN_IDENTITY   codesign identity; default: SHA-1 of the first valid
#                         "Developer ID Application ... (WUGFD7332A)" identity
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID=WUGFD7332A
OUT=build/release
APP="$OUT/Jumpr.app"
ZIP="$OUT/Jumpr.zip"

die() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

# --- arguments ---------------------------------------------------------------
VERSION=""
NOTARIZE=1
for arg in "$@"; do
    case "$arg" in
        --skip-notarize) NOTARIZE=0 ;;
        -*) die "unknown option: $arg" ;;
        *) [ -z "$VERSION" ] || die "more than one version given"; VERSION="$arg" ;;
    esac
done
[ -n "$VERSION" ] || die "usage: scripts/release.sh <version> [--skip-notarize]"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || die "version must look like 1.0.0, got '$VERSION'"

if [ "$NOTARIZE" = 1 ] && [ -z "${JUMPR_NOTARY_PROFILE:-}" ]; then
    die "JUMPR_NOTARY_PROFILE is not set. Set it to your notarytool keychain profile, or pass --skip-notarize."
fi

BUILD_NUMBER="$(git rev-list --count HEAD)"

# --- signing identity --------------------------------------------------------
# Two certificates share the same name here, so sign by SHA-1 hash, not by name.
IDENTITY="${JUMPR_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning \
        | awk -v team="($TEAM_ID)\"" '/"Developer ID Application:/ && index($0, team) && !found { print $2; found = 1 }')"
    [ -n "$IDENTITY" ] || die "no valid Developer ID Application identity for team $TEAM_ID in the keychain"
fi
echo "Version $VERSION (build $BUILD_NUMBER), signing identity $IDENTITY"

# Signs everything that ships. Sparkle goes here later, signed inside-out
# (its nested helpers and framework first, the app last).
sign_app() {
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
}

report() {
    echo
    echo "$1: $ZIP"
    echo "Size:    $(du -h "$ZIP" | cut -f1) ($(stat -f %z "$ZIP") bytes)"
    echo "SHA-256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
}

zip_app() {
    rm -f "$ZIP"
    ditto -c -k --norsrc --keepParent "$APP" "$ZIP"
}

# --- build -------------------------------------------------------------------
step "Building universal app"
rm -rf "$OUT"
mkdir -p "$OUT"
JUMPR_BUILD_DIR="$OUT" JUMPR_ARCHS="arm64 x86_64" JUMPR_NO_SIGN=1 scripts/build-app.sh

ARCHS="$(lipo -archs "$APP/Contents/MacOS/Jumpr")"
echo "Architectures: $ARCHS"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || die "binary is not universal (got: $ARCHS)"

# --- version -----------------------------------------------------------------
step "Stamping version"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"

# --- sign + verify -----------------------------------------------------------
step "Signing"
sign_app
codesign --verify --deep --strict --verbose=2 "$APP"
SIG="$(codesign -dvv "$APP" 2>&1)"
grep -q '^CodeDirectory .*flags=0x10000(runtime)' <<<"$SIG" || die "signature lacks the hardened runtime flag"
grep -q '^Authority=Developer ID Application:' <<<"$SIG" || die "signature is not from a Developer ID Application certificate"
grep -q '^Timestamp=' <<<"$SIG" || die "signature has no secure timestamp"
grep -E '^(Authority=Developer ID Application|TeamIdentifier|Timestamp|CodeDirectory)' <<<"$SIG"

step "Zipping"
zip_app

# --- notarize ----------------------------------------------------------------
if [ "$NOTARIZE" = 0 ]; then
    echo
    echo "*** --skip-notarize: $ZIP is signed but NOT notarized. Do not ship it. ***"
    report "NOT notarized"
    exit 0
fi

step "Notarizing (this waits for Apple)"
NOTARY_JSON="$OUT/notarytool.json"
xcrun notarytool submit "$ZIP" --keychain-profile "$JUMPR_NOTARY_PROFILE" \
    --wait --timeout 1h --output-format json >"$NOTARY_JSON" || true
SUB_ID="$(plutil -extract id raw -o - "$NOTARY_JSON" 2>/dev/null || true)"
STATUS="$(plutil -extract status raw -o - "$NOTARY_JSON" 2>/dev/null || true)"
echo "Submission ${SUB_ID:-<none>}: ${STATUS:-<no status>}"
if [ "$STATUS" != Accepted ]; then
    cat "$NOTARY_JSON" >&2
    if [ -n "$SUB_ID" ]; then
        echo "See why: xcrun notarytool log $SUB_ID --keychain-profile \"$JUMPR_NOTARY_PROFILE\"" >&2
    fi
    die "notarization did not succeed"
fi

step "Stapling"
xcrun stapler staple "$APP"
zip_app
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

report "Notarized and stapled"
