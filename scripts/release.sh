#!/usr/bin/env bash
#
# release.sh vX.Y.Z — cut a signed GitHub Release and publish the macOS build.
#
#   1. builds the signed + notarized macOS DMG   (scripts/package.sh)
#   2. builds the unsigned iOS .ipa               (Sideloadly/AltStore re-sign it)
#   3. tags the commit and pushes it
#   4. creates a GitHub Release with both files
#   5. copies the DMG to the web server (brynify.me/dectalk)
#
# The signed DMG requires the "Developer ID Application" identity in the keychain
# and Signing/asc.env (for notarization); without them package.sh makes an
# unsigned DMG. iOS ad-hoc OTA is a separate flow — see scripts/publish.sh.
set -euo pipefail

VER="${1:?usage: scripts/release.sh vX.Y.Z}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"
SSH_HOST="${SSH_HOST:-brynify}"
REMOTE_DIR="${REMOTE_DIR:-/web/web/dectalk}"

echo "==> [1/5] Signed macOS DMG"
./scripts/package.sh

echo "==> [2/5] Unsigned iOS .ipa"
xcodebuild -project DECtalk.xcodeproj -scheme DECtalkApp-iOS -configuration Release \
  -sdk iphoneos -derivedDataPath build/rel-ios \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" build >/dev/null
rm -rf build/rel-payload && mkdir -p build/rel-payload/Payload
cp -R build/rel-ios/Build/Products/Release-iphoneos/DECtalk.app build/rel-payload/Payload/
( cd build/rel-payload && zip -qry "$HERE/dist/DECtalk-iOS-unsigned.ipa" Payload )

echo "==> [3/5] Tagging $VER"
git tag "$VER"
git push origin "$VER"

echo "==> [4/5] GitHub Release $VER"
gh release create "$VER" --title "DECtalk $VER" --notes \
"**macOS** — \`DECtalk.dmg\`: signed with Developer ID + notarized, opens cleanly (drag to Applications).
**iOS** — \`DECtalk-iOS-unsigned.ipa\`: install with Sideloadly or AltStore (they re-sign with your Apple ID)." \
  dist/DECtalk.dmg dist/DECtalk-iOS-unsigned.ipa

echo "==> [5/5] Publishing DMG to ${SSH_HOST}:${REMOTE_DIR}"
ssh "$SSH_HOST" "mkdir -p '$REMOTE_DIR'"
scp dist/DECtalk.dmg "${SSH_HOST}:${REMOTE_DIR}/"

echo
echo "Released $VER:"
echo "  https://github.com/masonasons/DECTalkApple/releases/tag/$VER"
echo "  https://brynify.me/dectalk/DECtalk.dmg"
