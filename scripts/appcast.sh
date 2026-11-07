#!/bin/bash
# Signs a release zip with Sparkle's EdDSA key and writes a one-item appcast for it.
#
#   scripts/appcast.sh <Jumpr.app> <Jumpr.zip> <appcast.xml>
#
# Version, build number and minimum macOS come from the app's Info.plist; the zip must be
# that app, final (notarized and stapled). Nothing is uploaded.
#
# The private key is read by Sparkle's sign_update from the login keychain, account
# "jumpr" (created with generate_keys --account jumpr). It is never printed.
# Env:
#   JUMPR_SPARKLE_KEY_FILE  sign with this private key file instead of the keychain
#                           (test keys only; never a file holding the real key in the repo)
set -euo pipefail
cd "$(dirname "$0")/.."

KEY_ACCOUNT=jumpr
DOWNLOAD_BASE=https://github.com/ggoforth/jumpr/releases/download
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin

die() { echo "appcast.sh: $*" >&2; exit 1; }

[ "$#" = 3 ] || die "usage: scripts/appcast.sh <Jumpr.app> <Jumpr.zip> <appcast.xml>"
APP="$1" ZIP="$2" XML="$3"
[ -d "$APP" ] || die "no app at $APP"
[ -f "$ZIP" ] || die "no zip at $ZIP"
[ -x "$SPARKLE_BIN/sign_update" ] || die "no $SPARKLE_BIN/sign_update; run swift build first"

plist() { plutil -extract "$1" raw -o - "$APP/Contents/Info.plist" 2>/dev/null || die "Info.plist has no $1"; }
VERSION="$(plist CFBundleShortVersionString)"
BUILD="$(plist CFBundleVersion)"
MIN_OS="$(plist LSMinimumSystemVersion)"
PUBLIC_KEY="$(plist SUPublicEDKey)"
URL="$DOWNLOAD_BASE/v$VERSION/Jumpr.zip"

# The zip must hold this exact app; a stale zip would ship a different build under this item.
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
ditto -x -k "$ZIP" "$CHECK"
[ "$(plutil -extract CFBundleVersion raw -o - "$CHECK/Jumpr.app/Contents/Info.plist")" = "$BUILD" ] \
    || die "$ZIP does not hold build $BUILD of $APP"

if [ -n "${JUMPR_SPARKLE_KEY_FILE:-}" ]; then
    echo "appcast.sh: signing with key file $JUMPR_SPARKLE_KEY_FILE (not the keychain)" >&2
    SIGNATURE="$("$SPARKLE_BIN/sign_update" -p --ed-key-file "$JUMPR_SPARKLE_KEY_FILE" "$ZIP")"
else
    SIGNATURE="$("$SPARKLE_BIN/sign_update" -p --account "$KEY_ACCOUNT" "$ZIP")"
fi
[[ "$SIGNATURE" =~ ^[A-Za-z0-9+/]{86}==$ ]] || die "sign_update did not return an EdDSA signature"
LENGTH="$(stat -f %z "$ZIP")"

# The signature must verify with the key the app carries, or no install could ever update.
if [ "$PUBLIC_KEY" = PLACEHOLDER-NOT-A-REAL-SPARKLE-KEY ]; then
    echo "appcast.sh: WARNING: $APP carries the placeholder key; signature NOT checked, appcast NOT shippable" >&2
else
    swift scripts/verify-ed-signature.swift "$PUBLIC_KEY" "$SIGNATURE" "$ZIP" \
        || die "the signature does not verify with the app's SUPublicEDKey: the signing key and the app's key differ"
    echo "Signature verified with the app's SUPublicEDKey"
fi

# Inline rather than a link: showing the notes must not add a request to the app's network use.
NOTES="$(swift scripts/release-notes.swift html "$VERSION")" || die "no release notes for $VERSION"

PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
cat >"$XML" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Jumpr</title>
    <link>https://getjumpr.app/</link>
    <description>Jumpr updates</description>
    <language>en</language>
    <item>
      <title>Jumpr $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <description><![CDATA[$NOTES]]></description>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <enclosure url="$URL" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIGNATURE"/>
    </item>
  </channel>
</rss>
EOF
xmllint --noout "$XML" || die "wrote invalid XML to $XML"
echo "Wrote $XML: Jumpr $VERSION (build $BUILD), $LENGTH bytes, $URL"
