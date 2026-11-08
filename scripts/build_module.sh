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
GEN=$(ls -td "$ROOT"/build/modules/G4OE69/*/dolrecomp-output/generated 2>/dev/null | head -1)
[ -n "$GEN" ] || { echo "no recompiled game yet: run make recompile GAME=sims2pets first" >&2; exit 1; }
SRC=$ROOT/lib/ModernGekko/vendor/dolphin
OUT=$ROOT/build/$TARGET-module
COMMON=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DGAME_ID=G4OE69 -DGENERATED_DIR="$GEN"
        -DGXRUNTIME_DIR="$SRC/GXRuntime" -DCHASSIS_ABI_DIR="$SRC/Source/Core/Core/PowerPC/StaticRecomp")
case $TARGET in
ios)
    cmake -S "$SRC/module-template" -B "$OUT" "${COMMON[@]}" \
        -DCMAKE_TOOLCHAIN_FILE="$ROOT/lib/ModernGekko/ios.cmake" \
        -DRECOMPCORE_MODULE_LIBRARY_TYPE=STATIC -DRECOMPCORE_MODULE_ENABLE_IPO=OFF >/dev/null
    ninja -C "$OUT"
    # Apple's ar drops CMake's response file (an empty archive): archive again.
    (cd "$OUT" && find CMakeFiles -name '*.o' > objs.txt && rm -f gG4OE69_recomp.a &&
        xcrun libtool -static -o gG4OE69_recomp.a -filelist objs.txt)
    echo "$OUT/gG4OE69_recomp.a" ;;
mac)
    cmake -S "$SRC/module-template" -B "$OUT" "${COMMON[@]}" -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 -DRECOMPCORE_MODULE_LIBRARY_TYPE=SHARED >/dev/null
    ninja -C "$OUT"
    echo "$OUT/gG4OE69_recomp.dylib ($(lipo -archs "$OUT/gG4OE69_recomp.dylib"))" ;;
*) echo "usage: build_module.sh ios|mac" >&2; exit 1 ;;
esac
