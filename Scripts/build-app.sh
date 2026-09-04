#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$HOME/Applications/RemoteMac.app}"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/RemoteMac" "$APP/Contents/MacOS/RemoteMac"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Localizations (en, pl)"
for LPROJ in Resources/*.lproj; do
  cp -R "$LPROJ" "$APP/Contents/Resources/"
done

echo "==> App icon"
"$ROOT/Scripts/make-icon.sh" >/dev/null
cp "$ROOT/dist/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> Sparkle.framework"
BUILD_DIR="$(swift build -c release --show-bin-path)"
SPARKLE_FW="$BUILD_DIR/Sparkle.framework"
if [[ ! -d "$SPARKLE_FW" ]]; then
  echo "Sparkle.framework not found in $BUILD_DIR" >&2
  exit 1
fi
mkdir -p "$APP/Contents/Frameworks"
# -R preserves the symlinks of the versioned framework layout
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"

# The binary links against @rpath — point it at Frameworks inside the bundle
install_name_tool -add_rpath "@executable_path/../Frameworks" \
  "$APP/Contents/MacOS/RemoteMac" 2>/dev/null || true

# Pinned by SHA-1, not by name: this keychain holds two Developer ID
# certificates with byte-identical common names, so selecting by name picks
# whichever `security` happens to list first. That is a silent coin flip over
# which certificate signs a release. CI overrides this with the identity it
# imported into its own temporary keychain.
CERT_SHA="${SIGN_IDENTITY:-425A48BCECBD18E1281D14C9A0E6D6937547B090}"

if ! security find-identity -v -p codesigning | grep -q "$CERT_SHA"; then
  echo "ERROR: signing identity $CERT_SHA not found in the keychain." >&2
  echo "       Set SIGN_IDENTITY to a different SHA-1 to override." >&2
  exit 1
fi

# Sign inside out — nested code must be signed before its parent, or
# codesign --verify --deep (and notarization) rejects the package.
FW="$APP/Contents/Frameworks/Sparkle.framework"
SIGN=(codesign --force --options runtime --timestamp --sign "$CERT_SHA")

"${SIGN[@]}" "$FW/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$FW/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" "$FW/Versions/B/Updater.app"
"${SIGN[@]}" "$FW/Versions/B/Autoupdate"
"${SIGN[@]}" "$FW/Versions/B"
"${SIGN[@]}" "$FW"

codesign --force --options runtime \
  --sign "$CERT_SHA" \
  --identifier io.eightlines.remotemac \
  --entitlements "Resources/entitlements.plist" \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built and signed: $APP"
