#!/bin/bash
# scripts/build_module.sh ios|mac: compiles the recompiled game (the C that
# `make recompile` generated under build/modules/G4OE69/) for a device.
#   ios: build/ios-module/gG4OE69_recomp.a (static: no dlopen on iOS)
#   mac: build/mac-module/gG4OE69_recomp.dylib (arm64 + x86_64)
# The output is the game's code: keep it to yourself.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TARGET=${1:?usage: build_module.sh ios|mac}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
GEN=${GEN:-$(ls -td "$ROOT"/build/modules/G4OE69/*/dolrecomp-output/generated 2>/dev/null | head -1)}
[ -n "$GEN" ] || { echo "no recompiled game yet: run make recompile GAME=sims2pets first" >&2; exit 1; }
SRC=$ROOT/lib/ModernGekko/vendor/dolphin
OUT=$ROOT/build/$TARGET-module
COMMON=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DGAME_ID=G4OE69 -DGENERATED_DIR="$GEN"
        -DGXRUNTIME_DIR="$SRC/GXRuntime" -DCHASSIS_ABI_DIR="$SRC/Source/Core/Core/PowerPC/StaticRecomp")
# The flags of the 60 fps iPad build: no FP inline aliases (smaller code), no
# lwarx reservation (the game has none), no FPRF (Dolphin's JITs skip it too).
FAST_CFLAGS="-DGXRUNTIME_NO_FP_INLINE_ALIASES -DGXRUNTIME_NO_RESERVATION -DGXRUNTIME_NO_FPRF"
case $TARGET in
ios)
    cmake -S "$SRC/module-template" -B "$OUT" "${COMMON[@]}" \
        -DCMAKE_TOOLCHAIN_FILE="$ROOT/lib/ModernGekko/ios.cmake" \
        -DRECOMPCORE_MODULE_LIBRARY_TYPE=STATIC -DRECOMPCORE_MODULE_ENABLE_IPO=OFF \
        -DCMAKE_C_FLAGS="${MODULE_CFLAGS-$FAST_CFLAGS}" -DRECOMPCORE_MODULE_OPT_LEVEL="${MODULE_OPT:-2}" >/dev/null
    ninja -C "$OUT"
    # Apple's ar drops CMake's response file (an empty archive): archive again.
    # Only the objects of this build graph: those of an older recompile (or
    # source path) stay in CMakeFiles, and the linker takes whichever copy of
    # func_* comes first.
    (cd "$OUT" && ninja -t targets all | sed -n 's/\.o: .*/.o/p' > objs.txt && rm -f gG4OE69_recomp.a &&
        xcrun libtool -static -o gG4OE69_recomp.a -filelist objs.txt)
    echo "$OUT/gG4OE69_recomp.a" ;;
mac)
    cmake -S "$SRC/module-template" -B "$OUT" "${COMMON[@]}" -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 -DRECOMPCORE_MODULE_LIBRARY_TYPE=SHARED \
        -DCMAKE_C_FLAGS="${MODULE_CFLAGS-$FAST_CFLAGS}" >/dev/null
    ninja -C "$OUT"
    echo "$OUT/gG4OE69_recomp.dylib ($(lipo -archs "$OUT/gG4OE69_recomp.dylib"))" ;;
*) echo "usage: build_module.sh ios|mac" >&2; exit 1 ;;
esac
