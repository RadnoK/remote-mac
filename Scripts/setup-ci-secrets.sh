#!/usr/bin/env bash
# One-time secrets setup for the Release workflow.
#
# WARNING: this exports cryptographic material from the keychain into GitHub
# secrets. After this step, GitHub Actions can sign code as you. Only run it
# on a repo whose list of collaborators you fully trust.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Secrets will be saved to repo: $REPO"
read -r -p "Continue? [y/N] " ans
[[ "$ans" == "y" ]] || { echo "Aborted."; exit 1; }

# --- 1. Developer ID certificate --------------------------------------------
echo
echo "==> Exporting the Developer ID certificate"
echo "    Enter the password the .p12 file will be encrypted with."
echo "    Remember it — it goes into the DEVELOPER_ID_P12_PASSWORD secret."
read -r -s -p "Password for .p12: " P12_PASS; echo
[[ -n "$P12_PASS" ]] || { echo "Password cannot be empty." >&2; exit 1; }

# The keychain will prompt for permission to export the private key.
security export -t identities -f pkcs12 -P "$P12_PASS" \
  -o "$WORK/cert.p12" -k login.keychain-db 2>/dev/null || {
    echo "Export failed. Alternative: Keychain Access > My Certificates >" >&2
    echo "right-click 'Developer ID Application' > Export." >&2
    exit 1
  }

base64 -i "$WORK/cert.p12" | gh secret set DEVELOPER_ID_P12 --repo "$REPO"
printf '%s' "$P12_PASS" | gh secret set DEVELOPER_ID_P12_PASSWORD --repo "$REPO"

# Password for the temporary keychain on the runner — random, not used anywhere else
openssl rand -base64 24 | tr -d '\n' | gh secret set KEYCHAIN_PASSWORD --repo "$REPO"

# --- 2. Sparkle private key ---------------------------------------------
echo
echo "==> Exporting the EdDSA key (Sparkle)"
SPARKLE_BIN="${SPARKLE_BIN:-$HOME/.local/sparkle/bin}"
"$SPARKLE_BIN/generate_keys" --account io.eightlines.remotemac -x "$WORK/sparkle_key" > /dev/null

# The key from the keychain must match SUPublicEDKey in the bundle — otherwise
# updates signed in CI will be rejected by installed copies.
PLIST_PUB="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)"
KEYCHAIN_PUB="$("$SPARKLE_BIN/generate_keys" --account io.eightlines.remotemac -p)"
if [[ "$PLIST_PUB" != "$KEYCHAIN_PUB" ]]; then
  echo "ERROR: the public key from the keychain does not match Info.plist." >&2
  echo "  Info.plist: $PLIST_PUB" >&2
  echo "  keychain:   $KEYCHAIN_PUB" >&2
  exit 1
fi

# The file contains comments; the key is the last non-empty line.
grep -v '^#' "$WORK/sparkle_key" | grep -v '^$' | tail -1 \
  | gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO"

echo
echo "    BACK UP this key in a password manager."
echo "    Without it you cannot ship updates for installed copies:"
echo
grep -v '^#' "$WORK/sparkle_key" | grep -v '^$' | tail -1
echo

# --- 3. Notarization credentials -------------------------------------------
echo "==> Notarization credentials"
read -r -p "Apple ID: " APPLE_ID
read -r -s -p "App-specific password: " APP_PASS; echo

printf '%s' "$APPLE_ID"   | gh secret set NOTARY_APPLE_ID --repo "$REPO"
printf '%s' "$APP_PASS"   | gh secret set NOTARY_PASSWORD --repo "$REPO"
read -r -p "Team ID: " TEAM_ID
[[ -n "$TEAM_ID" ]] || { echo "Team ID cannot be empty." >&2; exit 1; }
printf '%s' "$TEAM_ID"    | gh secret set NOTARY_TEAM_ID  --repo "$REPO"

# --- 4. Tap token -------------------------------------------------------
echo
echo "==> Tap repository token"
echo "    Requires a fine-grained PAT with Contents: write permission"
echo "    for RadnoK/homebrew-tap (github.com/settings/tokens)."
read -r -s -p "Token: " TAP_TOKEN; echo
printf '%s' "$TAP_TOKEN" | gh secret set TAP_TOKEN --repo "$REPO"

echo
echo "==> Done. Secrets in the repo:"
gh secret list --repo "$REPO"
