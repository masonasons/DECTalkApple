#!/usr/bin/env bash
#
# Build the DECtalk engine as a static library for Apple platforms and package
# it into DECtalkEngine.xcframework.
#
# The source list (sources.txt) and preprocessor defines are the self-contained,
# statically-linked configuration used by the emscripten/WASM port — no dlopen of
# per-language modules, audio device disabled, in-memory synthesis only.
#
# Usage:
#   ./build-xcframework.sh            # build all slices + xcframework
#   ./build-xcframework.sh macos      # build a single slice (macos|ios|ios-sim)
#
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$ENGINE_DIR/.." && pwd)"
DAPI="$ROOT_DIR/upstream/src/dapi/src"
SHIM_DIR="$ROOT_DIR/Sources/CDECtalk"
BUILD="$ENGINE_DIR/build"
OUT="$ENGINE_DIR/DECtalkEngine.xcframework"

# Language selection. US English only for now (matches emscripten reference).
# Multi-language selection at runtime is added once the US path is proven.
LANG_DEFINES="-DENGLISH -DENGLISH_US"

DEFINES=(
  -D_REENTRANT -DNOMME -DLTSSIM -DTTSSIM -DANSI -DBLD_DECTALK_DLL
  -DACCESS32 -DTYPING_MODE -DOS_SIXTY_FOUR_BIT -DACNA -DDISABLE_AUDIO
  $LANG_DEFINES
)

INCLUDES=(
  -I"$ROOT_DIR/upstream/src"
  -I"$DAPI"
  -I"$DAPI/api" -I"$DAPI/cmd" -I"$DAPI/dic" -I"$DAPI/include"
  -I"$DAPI/kernel" -I"$DAPI/lts" -I"$DAPI/osf" -I"$DAPI/ph"
  -I"$DAPI/protos" -I"$DAPI/vtm" -I"$DAPI/nt"
)

# This is 1990s C. Compile in its native dialect (gnu89) so implicit ints and
# implicit function declarations are warnings, not the hard errors modern clang
# defaults to. -fcommon restores pre-C99 tentative-definition merging. Remaining
# genuine type bugs are handled by engine/patches/*.patch (see apply_patches).
STD=-std=gnu89
WARNINGS=(
  -w
  -Wno-error=implicit-function-declaration
  -Wno-error=implicit-int
  -Wno-error=int-conversion
  -Wno-error=incompatible-function-pointer-types
  -fcommon
)

SOURCES=()
while IFS= read -r line; do
  case "$line" in ''|\#*) continue ;; esac
  SOURCES+=("$line")
done < "$ENGINE_DIR/sources.txt"

# Apply the source patches (genuine type bugs modern clang rejects) to the
# pristine upstream checkout. Idempotent: --forward -N skips already-applied hunks.
apply_patches() {
  local p
  for p in "$ENGINE_DIR"/patches/*.patch; do
    [ -e "$p" ] || continue
    patch -p1 -N --forward -d "$ROOT_DIR/upstream" -i "$p" >/dev/null 2>&1 || true
  done
}

# build_slice <label> <sdk> <min-version-flag> <arch...>
build_slice() {
  local label="$1"; local sdk="$2"; local minflag="$3"; shift 3
  local archs=("$@")
  local sysroot; sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  local clang; clang="$(xcrun --sdk "$sdk" -f clang)"
  local objdir="$BUILD/$label/obj"
  local lib="$BUILD/$label/libDECtalkEngine.a"
  rm -rf "$BUILD/$label"; mkdir -p "$objdir"

  local archflags=()
  for a in "${archs[@]}"; do archflags+=(-arch "$a"); done

  echo ">>> Compiling slice: $label (sdk=$sdk archs=${archs[*]})"
  local objs=()
  for src in "${SOURCES[@]}"; do
    local o="$objdir/$(echo "$src" | tr '/' '_').o"
    "$clang" -c $STD -O2 -g -fPIC "$minflag" -isysroot "$sysroot" \
      "${archflags[@]}" "${DEFINES[@]}" "${INCLUDES[@]}" "${WARNINGS[@]}" \
      "$DAPI/$src" -o "$o"
    objs+=("$o")
  done

  # Compile the clean C shim into the same library so its symbols ship in the
  # xcframework. It uses modern C, so no gnu89/legacy warning suppression.
  local shim_o="$objdir/dtk_shim.o"
  "$clang" -c -O2 -g -fPIC "$minflag" -isysroot "$sysroot" "${archflags[@]}" \
    "${DEFINES[@]}" "${INCLUDES[@]}" -I"$SHIM_DIR/include" \
    "$SHIM_DIR/dtk_shim.c" -o "$shim_o"
  objs+=("$shim_o")
  echo ">>> Archiving $lib"
  xcrun --sdk "$sdk" libtool -static -o "$lib" "${objs[@]}"
  echo ">>> Done: $lib ($(lipo -archs "$lib" 2>/dev/null))"
}

slice_macos()  { build_slice macos    macosx          -mmacosx-version-min=12.0     arm64 x86_64; }
slice_ios()    { build_slice ios      iphoneos        -miphoneos-version-min=15.0   arm64; }
slice_iossim() { build_slice ios-sim  iphonesimulator -mios-simulator-version-min=15.0 arm64 x86_64; }

# The xcframework exposes ONLY the clean shim header (dtk_shim.h) plus a module
# map so Swift can `import DECtalkEngine`. The messy ttsapi.h tree stays internal.
make_headers() {
  local hdr="$BUILD/include"
  rm -rf "$hdr"; mkdir -p "$hdr"
  cp "$SHIM_DIR/include/dtk_shim.h" "$hdr/"
  cat > "$hdr/module.modulemap" <<'EOF'
module DECtalkEngine {
    header "dtk_shim.h"
    export *
}
EOF
  echo "$hdr"
}

make_xcframework() {
  local hdr; hdr="$(make_headers)"
  rm -rf "$OUT"
  xcodebuild -create-xcframework \
    -library "$BUILD/macos/libDECtalkEngine.a"   -headers "$hdr" \
    -library "$BUILD/ios/libDECtalkEngine.a"      -headers "$hdr" \
    -library "$BUILD/ios-sim/libDECtalkEngine.a"  -headers "$hdr" \
    -output "$OUT"
  echo ">>> Created $OUT"
}

apply_patches

case "${1:-all}" in
  macos)   slice_macos ;;
  ios)     slice_ios ;;
  ios-sim) slice_iossim ;;
  all)     slice_macos; slice_ios; slice_iossim; make_xcframework ;;
  *) echo "unknown slice: $1" >&2; exit 1 ;;
esac
