#!/bin/bash
# Builds build/release/Jumpr.zip: universal, Developer ID signed, notarized, stapled, with
# Sparkle embedded; then build/release/appcast.xml for it. Uploads nothing.
#
#   scripts/release.sh <version> [--skip-notarize]
#
# --skip-notarize makes a test build: signed, not notarized, no appcast. It is the only
# way to build while SPARKLE_PUBLIC_KEY below is still the placeholder.
#
# Env:
#   JUMPR_NOTARY_PROFILE    notarytool keychain profile (required unless --skip-notarize)
#   JUMPR_SIGN_IDENTITY     codesign identity; default: SHA-1 of the first valid
#                           "Developer ID Application ... (WUGFD7332A)" identity
#   JUMPR_SPARKLE_KEY_FILE  passed to scripts/appcast.sh (test keys only); default: the
#                           private key in the login keychain, account "jumpr"
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID=WUGFD7332A
OUT=build/release
APP="$OUT/Jumpr.app"
ZIP="$OUT/Jumpr.zip"
APPCAST="$OUT/appcast.xml"

# --- updates -----------------------------------------------------------------
FEED_URL=https://getjumpr.app/appcast.xml
# THE Sparkle public key; this line is the one place it lives. Paste what
# `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account jumpr -p` prints.
# Every Jumpr shipped trusts only this key: never change it after the first release.
SPARKLE_PUBLIC_KEY='UybtTCaO+m2OQcQHPooMTy+2sGlbH/sEvcxFNrGq+Mc='

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

ALLOW_PLACEHOLDER_KEY=0
if [ "$SPARKLE_PUBLIC_KEY" = PLACEHOLDER-NOT-A-REAL-SPARKLE-KEY ]; then
    [ "$NOTARIZE" = 0 ] || die "SPARKLE_PUBLIC_KEY in scripts/release.sh is still the placeholder; paste the key from: .build/artifacts/sparkle/Sparkle/bin/generate_keys --account jumpr -p"
    ALLOW_PLACEHOLDER_KEY=1
    echo
    echo "*****************************************************************************"
    echo "*** SPARKLE_PUBLIC_KEY is the PLACEHOLDER: this test build cannot update. ***"
    echo "*** Allowed only with --skip-notarize. Do not ship it.                     ***"
    echo "*****************************************************************************"
fi

# --- what is being released --------------------------------------------------
# A release must be exactly a commit: uncommitted or untracked source would ship code that
# no tag describes, and the public source would no longer match the binary.
if [ -n "$(git status --porcelain)" ]; then
    [ "$NOTARIZE" = 0 ] || die "the working tree has uncommitted changes; commit them first (a test build with --skip-notarize is allowed)"
    echo "warning: this test build includes uncommitted changes" >&2
fi

# Every release goes out with notes. Asked now, not after an hour of notarizing.
if [ "$NOTARIZE" = 1 ]; then
    NOTES_BODY="$(swift scripts/release-notes.swift body "$VERSION")" || exit 1
fi

# The build number is the commit count, which a shallow clone gets wrong.
[ "$(git rev-parse --is-shallow-repository)" = false ] \
    || die "this is a shallow clone; the build number would be wrong. Run: git fetch --unshallow"
BUILD_NUMBER="$(git rev-list --count HEAD)"

# Sparkle offers an update only when its build number is higher than the installed one.
# The build number is the commit count, so a release built from a shorter history (another
# branch, a squashed main) would be published and then never offered to anyone.
if [ "$NOTARIZE" = 1 ]; then
    PUBLISHED="$({ curl -fsS --max-time 10 "$FEED_URL" 2>/dev/null || true; } \
        | sed -n 's/.*<sparkle:version>\([0-9][0-9]*\)<.*/\1/p' | sort -n | tail -1)"
    if [ -z "$PUBLISHED" ]; then
        echo "warning: could not read the published build number from $FEED_URL; not compared" >&2
    elif [ "$BUILD_NUMBER" -le "$PUBLISHED" ]; then
        die "build $BUILD_NUMBER is not higher than the published build $PUBLISHED ($FEED_URL); installed copies would never be offered it. Build from main with new commits."
    fi
fi

# --- signing identity --------------------------------------------------------
# Two certificates share the same name here, so sign by SHA-1 hash, not by name.
IDENTITY="${JUMPR_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning \
        | awk -v team="($TEAM_ID)\"" '/"Developer ID Application:/ && index($0, team) && !found { print $2; found = 1 }')"
    [ -n "$IDENTITY" ] || die "no valid Developer ID Application identity for team $TEAM_ID in the keychain"
fi
echo "Version $VERSION (build $BUILD_NUMBER), signing identity $IDENTITY"

SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_B="$SPARKLE_FW/Versions/B"
# Everything that carries its own signature, innermost first, the app last.
SIGNED_PIECES=(
    "$SPARKLE_B/XPCServices/Installer.xpc"
    "$SPARKLE_B/XPCServices/Downloader.xpc"
    "$SPARKLE_B/Autoupdate"
    "$SPARKLE_B/Updater.app"
    "$SPARKLE_FW"
    "$APP"
)

sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }

# Signs everything that ships, inside out and never --deep: Sparkle's XPC services,
# Autoupdate, Updater.app, the framework, then the app. This is Sparkle's documented order
# for apps not built by Xcode (sparkle-project.org/documentation/sandboxing); Downloader.xpc
# keeps the entitlements Sparkle gave it.
sign_app() {
    sign "$SPARKLE_B/XPCServices/Installer.xpc"
    sign --preserve-metadata=entitlements "$SPARKLE_B/XPCServices/Downloader.xpc"
    sign "$SPARKLE_B/Autoupdate"
    sign "$SPARKLE_B/Updater.app"
    sign "$SPARKLE_FW"
    sign "$APP"
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
[ "$NOTARIZE" = 0 ] || printf '%s\n' "$NOTES_BODY" >"$OUT/notes.md"
# build-app.sh stamps version, build number, feed and key, and refuses a release without
# real ones (the placeholder key passes only under --skip-notarize, above).
JUMPR_BUILD_DIR="$OUT" JUMPR_ARCHS="arm64 x86_64" JUMPR_NO_SIGN=1 JUMPR_RELEASE=1 \
    JUMPR_VERSION="$VERSION" JUMPR_BUILD_NUMBER="$BUILD_NUMBER" \
    JUMPR_FEED_URL="$FEED_URL" JUMPR_SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY" \
    JUMPR_ALLOW_PLACEHOLDER_KEY="$ALLOW_PLACEHOLDER_KEY" \
    scripts/build-app.sh

for bin in "$APP/Contents/MacOS/Jumpr" "$SPARKLE_B/Sparkle"; do
    ARCHS="$(lipo -archs "$bin")"
    echo "Architectures of ${bin#"$OUT/"}: $ARCHS"
    [[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || die "$bin is not universal (got: $ARCHS)"
done
# The app finds Sparkle.framework through this rpath, or it does not launch.
# (Captured first: grep -q quitting early would fail the pipe under pipefail.)
LOAD_COMMANDS="$(otool -l "$APP/Contents/MacOS/Jumpr")"
grep -q 'path @executable_path/../Frameworks ' <<<"$LOAD_COMMANDS" \
    || die "the binary has no @executable_path/../Frameworks rpath"
echo "rpath: @executable_path/../Frameworks"

# --- version -----------------------------------------------------------------
step "Checking version, build number, feed and key"
info() { plutil -extract "$1" raw -o - "$APP/Contents/Info.plist"; }
[ "$(info CFBundleShortVersionString)" = "$VERSION" ] || die "CFBundleShortVersionString is not $VERSION"
[ "$(info CFBundleVersion)" = "$BUILD_NUMBER" ] || die "CFBundleVersion is not $BUILD_NUMBER"
[ "$(info SUFeedURL)" = "$FEED_URL" ] || die "SUFeedURL is not $FEED_URL"
[ "$(info SUPublicEDKey)" = "$SPARKLE_PUBLIC_KEY" ] || die "SUPublicEDKey is not the key in this script"
echo "CFBundleShortVersionString $VERSION, CFBundleVersion $BUILD_NUMBER"
echo "SUFeedURL     $FEED_URL"
echo "SUPublicEDKey $SPARKLE_PUBLIC_KEY"

# --- sign + verify -----------------------------------------------------------
step "Signing"
sign_app
codesign --verify --deep --strict --verbose=2 "$APP"
for piece in "${SIGNED_PIECES[@]}"; do
    SIG="$(codesign -dvv "$piece" 2>&1)"
    grep -q '^CodeDirectory .*flags=0x10000(runtime)' <<<"$SIG" || die "$piece lacks the hardened runtime flag"
    grep -q '^Authority=Developer ID Application:' <<<"$SIG" || die "$piece is not signed with a Developer ID Application certificate"
    grep -q "^TeamIdentifier=$TEAM_ID\$" <<<"$SIG" || die "$piece is not signed by team $TEAM_ID"
    grep -q '^Timestamp=' <<<"$SIG" || die "$piece has no secure timestamp"
    echo "Signed: ${piece#"$OUT/"}"
done
grep -E '^(Authority=Developer ID Application|TeamIdentifier|Timestamp|CodeDirectory)' <<<"$SIG"

step "Zipping"
zip_app

# --- notarize ----------------------------------------------------------------
if [ "$NOTARIZE" = 0 ]; then
    echo
    echo "*** --skip-notarize: $ZIP is signed but NOT notarized. Do not ship it. ***"
    echo "*** No appcast written: the appcast is only for a notarized zip. ***"
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

# --- appcast -----------------------------------------------------------------
step "Signing the zip for Sparkle and writing the appcast"
scripts/appcast.sh "$APP" "$ZIP" "$APPCAST"

report "Notarized and stapled"
echo
echo "Nothing was uploaded. Upload in this order: the appcast points at the zip, and the changelog names the release."
echo "  1. $ZIP     -> GitHub Release v$VERSION, asset named Jumpr.zip, text from $OUT/notes.md"
echo "       (it must download from https://github.com/ggoforth/jumpr/releases/download/v$VERSION/Jumpr.zip)"
echo "  2. $APPCAST -> $FEED_URL"
echo "  3. site/ -> getjumpr.app, for the changelog. A sync with --delete must exclude appcast.xml and download/:"
echo "       those exist only in the bucket, and losing the appcast stops every installed copy updating."
