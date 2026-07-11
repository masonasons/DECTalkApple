#!/usr/bin/env bash
#
# package.sh — build the macOS app and package it into dist/DECtalk.dmg.
#
# If a "Developer ID Application" identity is in the keychain, the app + its
# extension are signed with the hardened runtime, the DMG is signed, and — when
# Signing/asc.env is present — the DMG is notarized (via the ASC API key) and
# stapled, so it opens cleanly on any Mac. Otherwise it falls back to an unsigned
# DMG (Gatekeeper note printed).
#
# Optional overrides:
#   DEVID_IDENTITY   "Developer ID Application: … (TEAMID)"  (auto-detected if unset)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"
PROJ="DECtalk.xcodeproj"
DIST="$HERE/dist"
APP_ENT="Apps/DECtalkApp/DECtalkApp.entitlements"
EXT_ENT="Apps/DECtalkVoiceExtension/DECtalkVoiceExtension.entitlements"

[ -f "$PROJ/project.pbxproj" ] || { echo "No $PROJ — run ./scripts/bootstrap.sh first"; exit 1; }
mkdir -p "$DIST"

DEVID="${DEVID_IDENTITY:-}"
if [ -z "$DEVID" ]; then
  DEVID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)"
fi

echo "==> Building macOS app (Release)"
xcodebuild -project "$PROJ" -scheme DECtalkApp-macOS -configuration Release \
  -derivedDataPath build/pkg-mac \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build >/dev/null
MACAPP="build/pkg-mac/Build/Products/Release/DECtalk.app"
APPEX="$MACAPP/Contents/PlugIns/DECtalkVoice.appex"

if [ -n "$DEVID" ]; then
  echo "==> Signing with Developer ID + hardened runtime ($DEVID)"
  cs() { codesign --force --options runtime --timestamp --sign "$DEVID" "$@"; }
  # Inside-out: nested bundles/frameworks, the extension, then the app.
  find "$APPEX/Contents" -name '*.bundle' -print0 2>/dev/null | while IFS= read -r -d '' b; do cs "$b"; done
  cs --entitlements "$EXT_ENT" "$APPEX"
  [ -d "$MACAPP/Contents/Frameworks" ] && find "$MACAPP/Contents/Frameworks" -depth \
    \( -name '*.dylib' -o -name '*.framework' \) -print0 | while IFS= read -r -d '' f; do cs "$f"; done
  find "$MACAPP/Contents/Resources" -name '*.bundle' -print0 2>/dev/null | while IFS= read -r -d '' b; do cs "$b"; done
  cs --entitlements "$APP_ENT" "$MACAPP"
  codesign --verify --deep --strict --verbose=1 "$MACAPP" 2>&1 | tail -1
else
  echo "==> No Developer ID identity found — building an UNSIGNED DMG"
fi

echo "==> Creating DMG"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$MACAPP/Contents/Info.plist" \
  | tr -d '\n' > "$DIST/mac_version.txt"
STAGE="$(mktemp -d)"
cp -R "$MACAPP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DIST/DECtalk.dmg"
hdiutil create -volname "DECtalk" -srcfolder "$STAGE" -ov -format UDZO "$DIST/DECtalk.dmg" >/dev/null
rm -rf "$STAGE"

if [ -n "$DEVID" ]; then
  codesign --force --timestamp --sign "$DEVID" "$DIST/DECtalk.dmg"
  if [ -f Signing/asc.env ]; then
    # shellcheck disable=SC1091
    source Signing/asc.env
    echo "==> Notarizing DMG (via ASC key; can take a minute)…"
    xcrun notarytool submit "$DIST/DECtalk.dmg" \
      --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER" --wait
    xcrun stapler staple "$DIST/DECtalk.dmg"
    echo "==> Notarized + stapled — opens cleanly on any Mac."
  else
    echo "==> Signed with Developer ID but NOT notarized (no Signing/asc.env)."
  fi
fi

echo
echo "Done:"; ls -lh "$DIST/DECtalk.dmg"
if [ -z "$DEVID" ]; then
  echo
  echo "Unsigned DMG. On another Mac, right-click the app → Open, or run:"
  echo "  xattr -dr com.apple.quarantine /Applications/DECtalk.app"
fi
