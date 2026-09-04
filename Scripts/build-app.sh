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

CERT_SHA=$(security find-identity -v -p codesigning \
  | awk '/Developer ID Application.*7S3F9767BM/{print $2; exit}')

if [ -z "$CERT_SHA" ]; then
  echo "BŁĄD: nie znaleziono certyfikatu Developer ID (Team 7S3F9767BM)." >&2
  exit 1
fi

codesign --force --options runtime \
  --sign "$CERT_SHA" \
  --identifier io.eightlines.remotemac \
  "$APP"

codesign --verify --strict "$APP"
echo "Zbudowano i podpisano: $APP"
