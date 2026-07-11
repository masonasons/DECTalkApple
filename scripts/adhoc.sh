#!/usr/bin/env bash
#
# adhoc.sh — build a signed ad-hoc iOS build + OTA install bundle in dist/ota/:
#   DECtalk.ipa     the app, re-signed with the ad-hoc distribution profile
#   manifest.plist  itms-services manifest pointing at the IPA
#   index.html      a page with an "Install" link
#
# Host all three at the same HTTPS URL and open index.html on a registered
# device to install. Pass the public base URL (the folder they'll live in):
#   scripts/adhoc.sh https://example.com/dectalk
# or set BASE_URL. Both the IPA and manifest MUST be served over HTTPS.
#
# Requires local signing material in Signing/ (gitignored): the ASC API key and
# the ad-hoc provisioning profiles (regenerated here from all registered devices)
# plus an "iPhone/Apple Distribution" identity in the keychain.
#
# A device can only install if its UDID is registered. Add one with:
#   source Signing/asc.env
#   swift scripts/asc_tool.swift register <UDID> "<name>"   # then re-run this
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"
PROJ="DECtalk.xcodeproj"
SCHEME="DECtalkApp-iOS"
BASE_URL="${1:-${BASE_URL:-https://YOUR-HOST.example.com/dectalk}}"
OUT="$HERE/dist/ota"
APP_PROFILE="$HERE/Signing/DECtalk_App_AdHoc.mobileprovision"
EXT_PROFILE="$HERE/Signing/DECtalk_Ext_AdHoc.mobileprovision"

[ -f "$PROJ/project.pbxproj" ] || { echo "No $PROJ — run ./scripts/bootstrap.sh first"; exit 1; }
[ -f Signing/asc.env ] || { echo "Missing Signing/asc.env (signing material)"; exit 1; }
# shellcheck disable=SC1091
source Signing/asc.env

DIST_ID="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -E 'iPhone Distribution|Apple Distribution' | head -1 | sed -E 's/.*"(.*)".*/\1/')"
[ -n "$DIST_ID" ] || { echo "No distribution identity in keychain"; exit 1; }

# Device resource ids to include, pinned in Signing/.devices (first column).
# If that file is absent, the ASC tool falls back to ALL registered devices.
DEVICE_IDS=""
if [ -f Signing/.devices ]; then
  DEVICE_IDS="$(awk 'NF && $1 !~ /^#/ {print $1}' Signing/.devices | tr '\n' ' ')"
fi
echo "==> Refreshing ad-hoc profiles (devices: ${DEVICE_IDS:-ALL registered})"
# shellcheck disable=SC2086
ADHOC_PROFILE_NAME="DECtalk App Ad Hoc" \
  swift scripts/asc_tool.swift adhoc "$APP_BUNDLE_RESID" "$DIST_CERT_RESID" "$APP_PROFILE" $DEVICE_IDS
# shellcheck disable=SC2086
ADHOC_PROFILE_NAME="DECtalk Voice Ad Hoc" \
  swift scripts/asc_tool.swift adhoc "$EXT_BUNDLE_RESID" "$DIST_CERT_RESID" "$EXT_PROFILE" $DEVICE_IDS

echo "==> Building iOS app (Release, device)"
xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/adhoc \
  -allowProvisioningUpdates build >/dev/null
APP="build/adhoc/Build/Products/Release-iphoneos/DECtalk.app"
APPEX="$APP/PlugIns/DECtalkVoice.appex"

echo "==> Re-signing for ad-hoc ($DIST_ID)"
ent() { security cms -D -i "$1" > /tmp/dtk_prof.plist
        /usr/libexec/PlistBuddy -x -c 'Print :Entitlements' /tmp/dtk_prof.plist > "$2"; }
ent "$APP_PROFILE" /tmp/dtk_app_ent.plist
ent "$EXT_PROFILE" /tmp/dtk_ext_ent.plist
cp "$APP_PROFILE" "$APP/embedded.mobileprovision"
cp "$EXT_PROFILE" "$APPEX/embedded.mobileprovision"

# Sign inside-out: nested frameworks/bundles, then the extension, then the app.
sign_nested() { # <container> — sign frameworks + resource bundles it contains
  local dir="$1"
  [ -d "$dir/Frameworks" ] && find "$dir/Frameworks" -maxdepth 1 -name '*.dylib' -o -name '*.framework' \
    | while read -r f; do codesign --force --sign "$DIST_ID" --timestamp=none "$f"; done
  find "$dir" -maxdepth 1 -name '*.bundle' \
    | while read -r b; do codesign --force --sign "$DIST_ID" --timestamp=none "$b"; done
}
sign_nested "$APPEX"
codesign --force --sign "$DIST_ID" --timestamp=none --entitlements /tmp/dtk_ext_ent.plist "$APPEX"
sign_nested "$APP"
codesign --force --sign "$DIST_ID" --timestamp=none --entitlements /tmp/dtk_app_ent.plist "$APP"
codesign --verify --deep --strict --verbose=1 "$APP" 2>&1 | tail -1

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")"

rm -rf "$OUT"; mkdir -p "$OUT"
printf '%s' "$BUILD" > "$OUT/ios_version.txt"

echo "==> Packaging IPA"
PTMP="$(mktemp -d)"; mkdir -p "$PTMP/Payload"
cp -R "$APP" "$PTMP/Payload/"
( cd "$PTMP" && zip -qry "$OUT/DECtalk.ipa" Payload )
rm -rf "$PTMP"

echo "==> Writing manifest + install page (base URL: $BASE_URL)"
cat > "$OUT/manifest.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key><string>software-package</string>
          <key>url</key><string>${BASE_URL}/DECtalk.ipa</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key><string>${BUNDLE_ID}</string>
        <key>bundle-version</key><string>${VERSION}</string>
        <key>kind</key><string>software</string>
        <key>title</key><string>DECtalk</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

cat > "$OUT/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Install DECtalk</title>
</head>
<body>
  <h1>DECtalk for iOS</h1>
  <p><a href="itms-services://?action=download-manifest&amp;url=${BASE_URL}/manifest.plist">Install DECtalk</a></p>
  <p>Your device must be registered. After installing, open Settings &rsaquo;
     General &rsaquo; VPN &amp; Device Management and trust the developer if
     prompted. Enable the voice under Settings &rsaquo; Accessibility &rsaquo;
     Spoken Content &rsaquo; Voices.</p>
</body>
</html>
HTML

echo
echo "Done — ad-hoc build for the ${BASE_URL##*/} devices. Upload to ${BASE_URL}/ (HTTPS):"
ls -lh "$OUT"
