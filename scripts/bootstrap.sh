#!/usr/bin/env bash
#
# bootstrap.sh — set up a fresh checkout so it can build.
#
# Fetches the proprietary DECtalk engine sources (not committed to this repo),
# builds the engine xcframework, installs the dictionary resource, and generates
# the Xcode project. Safe to re-run.
#
#   ./scripts/bootstrap.sh            # everything
#   ./scripts/bootstrap.sh --no-xcodeproj   # skip xcodegen (e.g. SwiftPM-only/CI)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

UPSTREAM_REPO="https://github.com/dectalk/dectalk.git"
GEN_XCODEPROJ=1
[ "${1:-}" = "--no-xcodeproj" ] && GEN_XCODEPROJ=0

say() { printf '\n\033[1;36m>>> %s\033[0m\n' "$*"; }

# 1. Toolchain checks --------------------------------------------------------
say "Checking toolchain"
command -v git >/dev/null        || { echo "git is required"; exit 1; }
command -v xcodebuild >/dev/null || { echo "Xcode command-line tools are required"; exit 1; }
# `| head -1` closes the pipe early; some xcodebuild builds then abort on the
# broken pipe (SIGPIPE), which pipefail turns into a failure. awk consumes all
# output, so xcodebuild finishes cleanly.
xcodebuild -version 2>/dev/null | awk 'NR==1'

# 2. Fetch the DECtalk engine (proprietary — not committed) ------------------
if [ ! -d upstream/src ]; then
  say "Cloning DECtalk engine into upstream/ (shallow)"
  git clone --depth 1 "$UPSTREAM_REPO" upstream
else
  say "upstream/ already present — skipping clone"
fi

# 3. Install the dictionary resource ----------------------------------------
say "Installing dictionary resource"
mkdir -p Sources/DECtalkKit/Resources
cp -f upstream/ports/emscripten/fs/dtalk_us.dic Sources/DECtalkKit/Resources/dtalk_us.dic
echo "  dtalk_us.dic -> Sources/DECtalkKit/Resources/"

# 4. Build the engine xcframework -------------------------------------------
say "Building DECtalkEngine.xcframework (macOS + iOS + simulator)"
./engine/build-xcframework.sh

# 5. Generate the Xcode project ---------------------------------------------
if [ "$GEN_XCODEPROJ" = 1 ]; then
  if ! command -v xcodegen >/dev/null; then
    if command -v brew >/dev/null; then
      say "Installing xcodegen via Homebrew"
      brew install xcodegen
    else
      echo "xcodegen not found and Homebrew unavailable — install xcodegen or run with --no-xcodeproj"; exit 1
    fi
  fi
  say "Generating DECtalk.xcodeproj"
  xcodegen generate
fi

say "Done. Next:"
echo "  swift test                                             # run the engine/kit tests"
echo "  open DECtalk.xcodeproj                                 # build the apps in Xcode"
echo "  (set DEVELOPMENT_TEAM in project.yml to your team ID)"
