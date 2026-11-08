#!/bin/bash
# scripts/build_ios.sh <your disc> [--slim] [--with-game]: The Sims 2: Pets
# (USA, G4OE69) for iPhone/iPad, from your own disc, on a Mac with Xcode.
#   1. tools: DolRecomp, ModernGekko (host), dolphin-tool
#   2. extract the disc's sys/ (main.dol ...) to extracted/sims2pets
#   3. make recompile: the game's PowerPC code to C (~30 min the first time)
#   4. the C for iOS (static), the iOS runtime, the app: build/ios/Sims2Pets.ipa
# --slim       make the device copy of the disc without the intro movies (-54 MB)
# --with-game  put the game inside the IPA (no Finder copy needed; ~600 MB IPA)
# Without --with-game, copy build/ios/game/ into the app's folder with Finder
# (iPhone > Files > Sims 2 Pets) or the Files app, as "game".
# Everything built from your disc is your game's code and data: don't share it.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DISC=${1:?usage: build_ios.sh <disc.iso|.rvz|.gcm> [--slim] [--with-game]}
DISC=$(cd "$(dirname "$DISC")" && pwd)/$(basename "$DISC")
shift
SLIM= WITH_GAME=
for a in "$@"; do case $a in --slim) SLIM=1 ;; --with-game) WITH_GAME=1 ;; *) echo "unknown option $a" >&2; exit 1 ;; esac; done
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
JOBS=$(sysctl -n hw.ncpu)
MG=$ROOT/lib/ModernGekko
cd "$ROOT"

echo "== 1/4 tools"
git submodule update --init --recursive
make dolrecomp JOBS="$JOBS"
cmake -S "$MG" -B "$MG/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DMODERNGEKKO_ENABLE_DISC_TOOL=ON >/dev/null
ninja -C "$MG/build" moderngekko-port dolphin-tool

echo "== 2/4 extract"
G=$ROOT/extracted/sims2pets
if [ ! -f "$G/sys/main.dol" ]; then
    rm -rf "$G.tmp"
    "$MG/build/Binaries/dolphin-tool" extract -i "$DISC" -o "$G.tmp" -q
    SYS=$(dirname "$(find "$G.tmp" -name main.dol | head -1)")
    mkdir -p "$G" && mv "$SYS" "$G/sys" && mkdir -p "$G/files" && rm -rf "$G.tmp"
fi
id=$(head -c 6 "$G/sys/boot.bin")
[ "$id" = G4OE69 ] || { echo "this is $id, not The Sims 2: Pets (USA, G4OE69)" >&2; exit 1; }

echo "== 3/4 recompile"
make recompile GAME=sims2pets JOBS="$JOBS"

echo "== 4/4 iOS"
scripts/build_module.sh ios
cmake -S "$MG" -B "$MG/build-ios" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$MG/ios.cmake" -DCMAKE_BUILD_TYPE=Release \
    -DMODERNGEKKO_ENABLE_DYNAMIC_MODULES=OFF -DENABLE_VULKAN=OFF -DENABLE_SDL=OFF -DUSE_SYSTEM_LIBS=OFF \
    -DUSE_SANITIZERS=OFF -DMACOS_CODE_SIGNING=OFF -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew -DHAVE_PIPE2=OFF >/dev/null
ninja -C "$MG/build-ios"
# The device's copy of the game: sys/ + the disc image (the app reads the disc directly).
OUT=$ROOT/build/ios/game
rm -rf "$OUT" && mkdir -p "$OUT/files"
cp -R "$G/sys" "$OUT/sys"
if [ -n "$SLIM" ]; then scripts/make_slim_disc.sh "$DISC" "$OUT/disc.rvz"
else
    case $DISC in
    *.rvz) cp "$DISC" "$OUT/disc.rvz" ;;
    *) "$MG/build/Binaries/dolphin-tool" convert -i "$DISC" -o "$OUT/disc.rvz" -f rvz -b 524288 -c zstd -l 19 ;;
    esac
fi
GAME_DIR=${WITH_GAME:+$OUT} scripts/ios/build_ipa.sh
