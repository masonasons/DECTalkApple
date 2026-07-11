#!/usr/bin/env bash
#
# publish.sh — build the iOS ad-hoc OTA bundle and upload it (over SSH/scp) to
# the web server it's served from, then verify it's live. (macOS builds ship via
# GitHub Releases; this is iOS ad-hoc only.)
#
# Bump CURRENT_PROJECT_VERSION in project.yml (+ re-run xcodegen) first if you
# want already-installed apps to see a newer build number.
#
# Override the destination via env:
#   IOS_BASE_URL   public HTTPS URL of the folder (default https://brynify.me/dectalk)
#   SSH_HOST       ssh host/alias to upload to     (default brynify)
#   REMOTE_DIR     remote path that URL maps to    (default /web/web/dectalk)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"
IOS_BASE_URL="${IOS_BASE_URL:-https://brynify.me/dectalk}"
SSH_HOST="${SSH_HOST:-brynify}"
REMOTE_DIR="${REMOTE_DIR:-/web/web/dectalk}"

bash scripts/adhoc.sh "$IOS_BASE_URL"

echo "==> Uploading to ${SSH_HOST}:${REMOTE_DIR}"
ssh "$SSH_HOST" "mkdir -p '$REMOTE_DIR'"
scp dist/ota/DECtalk.ipa dist/ota/manifest.plist dist/ota/index.html \
    dist/ota/ios_version.txt "${SSH_HOST}:${REMOTE_DIR}/"

echo "==> Verifying"
for f in DECtalk.ipa manifest.plist index.html ios_version.txt; do
  code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 25 "$IOS_BASE_URL/$f" || echo ERR)"
  printf "  %-42s HTTP %s\n" "$IOS_BASE_URL/$f" "$code"
done
echo "Published ad-hoc build $(cat dist/ota/ios_version.txt) to ${IOS_BASE_URL}"
echo "Install page: ${IOS_BASE_URL}/index.html  (open on a registered device)"
