#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: ./Scripts/release.sh <version>   (e.g. 1.0.0)" >&2
  exit 1
fi

APP_NAME="RemoteMac"
DIST="dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/RemoteMac-$VERSION.zip"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-remotemac-notary}"
SPARKLE_BIN="${SPARKLE_BIN:-$HOME/.local/sparkle/bin}"
APPCAST_DIR="$DIST/appcast"

echo "==> Build + Developer ID signature"
./Scripts/build-app.sh "$APP"

echo "==> Packaging $ZIP"
mkdir -p "$DIST"
rm -f "$ZIP"
# ditto, not zip — preserves the bundle's metadata and signature
ditto -c -k --keepParent "$APP" "$ZIP"

# Read back from the signature rather than hardcoded, so this works for
# whoever built the app. Only used in the help text below.
TEAM_ID="$(codesign -dvv "$APP" 2>&1 | awk -F= '/^TeamIdentifier/{print $2}')"

echo "==> Checking notarization credentials"
# Do NOT run notarization without a real profile — there are no credentials
# in this environment, and submitting would upload the owner's binary to
# Apple under an unconfigured identity. Fail loudly and tell the owner what
# to run instead of silently skipping or guessing.
if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
  cat >&2 <<EOF

ERROR: notarytool keychain profile "$KEYCHAIN_PROFILE" is not configured.

This script will not attempt notarization without it. Set it up once with:

  xcrun notarytool store-credentials $KEYCHAIN_PROFILE \\
    --apple-id "<your Apple ID email>" \\
    --team-id "$TEAM_ID" \\
    --password "<app-specific password>"

(Generate the app-specific password at https://appleid.apple.com under
Sign-In and Security > App-Specific Passwords.)

To use a different profile name, set KEYCHAIN_PROFILE when running this
script.
EOF
  exit 1
fi

echo "==> Notarization (this may take a few minutes)"
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

echo "==> Stapling"
xcrun stapler staple "$APP"

echo "==> Repackaging after stapling"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Gatekeeper verification"
spctl -a -vvv -t install "$APP"

echo "==> Appcast for Sparkle"
# generate_appcast reads the whole directory and signs with the EdDSA key from
# the keychain. It must run after stapling, so it covers the ZIP with the
# notarization ticket.
if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
  echo "generate_appcast not found in $SPARKLE_BIN" >&2
  echo "Download it from https://github.com/sparkle-project/Sparkle/releases and set SPARKLE_BIN" >&2
  exit 1
fi
mkdir -p "$APPCAST_DIR"
cp "$ZIP" "$APPCAST_DIR/"
URL_PREFIX="https://github.com/radnok/remote-mac/releases/download/v$VERSION/"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  # CI: key from the secret via stdin, the runner's keychain doesn't have it
  echo "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN/generate_appcast" \
    --ed-key-file - --download-url-prefix "$URL_PREFIX" "$APPCAST_DIR"
else
  # Locally: the private key lives in the login keychain under the account
  # io.eightlines.remotemac. --account is mandatory here: without it
  # generate_appcast falls back to the default "ed25519" account, which on a
  # machine with more than one Sparkle app is somebody else's key — updates
  # would be signed with a key this app does not trust, and the failure would
  # only surface on users' machines.
  "$SPARKLE_BIN/generate_appcast" \
    --account io.eightlines.remotemac \
    --download-url-prefix "$URL_PREFIX" "$APPCAST_DIR"
fi

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo
echo "==> Done"
echo "    file:    $ZIP"
echo "    sha256:  $SHA"
echo "    appcast: $APPCAST_DIR/appcast.xml"
echo
echo "Next:"
echo "  1. gh release create v$VERSION \"$ZIP\" --title \"RemoteMac $VERSION\" --generate-notes"
echo "  2. publish $APPCAST_DIR/appcast.xml at the URL in SUFeedURL (Resources/Info.plist)"
echo "     — e.g. commit it to the gh-pages branch if that's how it's served"
