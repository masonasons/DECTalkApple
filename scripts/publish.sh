#!/usr/bin/env bash
#
# publish.sh — build the iOS ad-hoc OTA bundle and copy it to the web directory
# it's served from, then verify it's live. (macOS builds ship via GitHub
# Releases; this is iOS ad-hoc only.)
#
# Bump CURRENT_PROJECT_VERSION in project.yml (+ re-run xcodegen) first if you
# want already-installed apps to see a newer build number.
#
# Override the destination via env:
#   IOS_BASE_URL   public HTTPS URL of the folder (default win.masonasons.me/dectalk)
#   IOS_WEB_DIR    local path that folder maps to  (default /Volumes/winserver2/Web/dectalk)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"
IOS_BASE_URL="${IOS_BASE_URL:-https://win.masonasons.me/dectalk}"
IOS_WEB_DIR="${IOS_WEB_DIR:-/Volumes/winserver2/Web/dectalk}"

# Create the web dir only when the share itself is mounted.
if [[ ! -d "$IOS_WEB_DIR" ]]; then
  parent="$(dirname "$IOS_WEB_DIR")"
  if [[ -d "$parent" ]]; then mkdir -p "$IOS_WEB_DIR"
  else echo "error: web share not mounted: $parent" >&2; exit 1; fi
fi

bash scripts/adhoc.sh "$IOS_BASE_URL"

echo "==> Publishing to $IOS_WEB_DIR"
cp dist/ota/DECtalk.ipa dist/ota/manifest.plist dist/ota/index.html \
   dist/ota/ios_version.txt "$IOS_WEB_DIR/"

echo "==> Verifying"
for f in DECtalk.ipa index.html ios_version.txt; do
  code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 25 "$IOS_BASE_URL/$f" || echo ERR)"
  printf "  %-40s HTTP %s\n" "$IOS_BASE_URL/$f" "$code"
done
echo "Published ad-hoc build $(cat dist/ota/ios_version.txt) to ${IOS_BASE_URL}"
echo "Install page: ${IOS_BASE_URL}/index.html  (open on a registered device)"
