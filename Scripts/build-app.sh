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

# Signing identity: taken from $SIGN_IDENTITY when set (CI exports the one it
# imported into its temporary keychain), otherwise discovered in the login
# keychain. Identities are selected by SHA-1 rather than by name because a
# keychain can hold several Developer ID certificates with byte-identical
# common names, and `codesign --sign <name>` then fails as ambiguous.
# .signing-identity is gitignored: it keeps a machine-specific choice out of
# the repo while sparing you from typing SIGN_IDENTITY on every build.
if [ -z "${SIGN_IDENTITY:-}" ] && [ -f "$ROOT/.signing-identity" ]; then
  SIGN_IDENTITY="$(tr -d '[:space:]' < "$ROOT/.signing-identity")"
fi

CERT_SHA="${SIGN_IDENTITY:-}"

if [ -z "$CERT_SHA" ]; then
  MATCHES="$(security find-identity -v -p codesigning \
    | awk '/Developer ID Application/{print $2}')"
  COUNT="$(printf '%s\n' "$MATCHES" | grep -c . || true)"

  if [ "$COUNT" -eq 0 ]; then
    echo "ERROR: no Developer ID Application identity in the keychain." >&2
    echo "       Install one, or set SIGN_IDENTITY to its SHA-1." >&2
    exit 1
  elif [ "$COUNT" -gt 1 ]; then
    echo "ERROR: $COUNT Developer ID identities found — pick one explicitly:" >&2
    security find-identity -v -p codesigning | grep "Developer ID Application" >&2
    echo "       SIGN_IDENTITY=<sha1> ./Scripts/build-app.sh" >&2
    echo "       or save the one you want: echo <sha1> > .signing-identity" >&2
    exit 1
  fi

  CERT_SHA="$MATCHES"
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
