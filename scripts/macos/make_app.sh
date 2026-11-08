#!/bin/bash
# scripts/macos/make_app.sh: the Mac app, universal (Apple silicon + Intel):
#   $OUT/Sims 2 Pets.app   runner + recompiled game module + Dolphin's Sys
#   $OUT/Game/             sys/ (DOL etc.), files/ (empty), disc.rvz
# The app runs Game/ next to it. Saves and settings stay in
# ~/.local/share/moderngekko. Needs build/mac-module (build_module.sh mac),
# build/ios/game (build_ios.sh) and the runner for both CPUs:
#   lib/ModernGekko/build-mac-arm64 and build-mac-x86_64 (see BUILD below).
# Never share the app: it holds the game's code.
set -euo pipefail
T=$(cd "$(dirname "$0")/../.." && pwd)
[ -f "$T/scripts/ios/local.env" ] && . "$T/scripts/ios/local.env"
OUT=${OUT:-$T/build/mac}
MG=$T/lib/ModernGekko
# BUILD: the runner without Homebrew's libraries, once per CPU.
for A in arm64 x86_64; do
    if [ ! -x "$MG/build-mac-$A/moderngekko-run" ]; then
        TOOLCHAIN=()
        [ "$A" = x86_64 ] && [ "$(uname -m)" = arm64 ] && TOOLCHAIN=(-DCMAKE_TOOLCHAIN_FILE="$MG/macos-x86_64.cmake")
        cmake -S "$MG" -B "$MG/build-mac-$A" -G Ninja ${TOOLCHAIN[@]+"${TOOLCHAIN[@]}"} -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_OSX_ARCHITECTURES=$A -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 -DUSE_SYSTEM_LIBS=OFF -DBUNDLE_SPEEX=ON \
            -DENABLE_VULKAN=OFF -DENABLE_QT=OFF -DMACOS_CODE_SIGNING=OFF -DUSE_SANITIZERS=OFF \
            -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew -DHAVE_PIPE2=OFF >/dev/null
        ninja -C "$MG/build-mac-$A" moderngekko-run
    fi
done
MODULE=$T/build/mac-module/gG4OE69_recomp.dylib
GAME=$T/build/ios/game
APP=$OUT/Sims\ 2\ Pets.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OUT/Game/files"
lipo -create "$MG/build-mac-arm64/moderngekko-run" "$MG/build-mac-x86_64/moderngekko-run" \
    -output "$APP/Contents/MacOS/moderngekko-run"
cp "$MODULE" "$APP/Contents/Resources/gG4OE69_recomp.dylib"
rsync -a "$MG/vendor/dolphin/Data/Sys/" "$APP/Contents/Resources/Sys/"
rsync -a "$GAME/" "$OUT/Game/"
cat > "$APP/Contents/MacOS/Sims 2 Pets" <<'SH'
#!/bin/bash
here=$(cd "$(dirname "$0")" && pwd)
exec "$here/moderngekko-run" --game "$here/../../../Game" \
  --module "$here/../Resources/gG4OE69_recomp.dylib" --graphics Metal --allow-interpreter \
  --title "The Sims 2: Pets" > "$HOME/Library/Logs/Sims2Pets.log" 2>&1
SH
chmod +x "$APP/Contents/MacOS/Sims 2 Pets"
cat > "$APP/Contents/Info.plist.in" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Sims 2 Pets</string>
<key>CFBundleIdentifier</key><string>BUNDLE_ID</string>
<key>CFBundleName</key><string>Sims 2 Pets</string>
<key>CFBundleDisplayName</key><string>The Sims 2: Pets</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>11.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
sed "s/BUNDLE_ID/${MAC_BUNDLE_ID:-io.github.sims2pets-mac}/" "$APP/Contents/Info.plist.in" > "$APP/Contents/Info.plist"
rm "$APP/Contents/Info.plist.in"
SRC_ICON=$T/scripts/ios/icon.png
[ -f "$T/scripts/ios/icon.local.png" ] && SRC_ICON=$T/scripts/ios/icon.local.png
ICON=$(mktemp -d)/AppIcon.iconset; mkdir -p "$ICON"
for s in 16 32 128 256 512; do
  sips -z $s $s "$SRC_ICON" --out "$ICON/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$SRC_ICON" --out "$ICON/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICON" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep -s - "$APP" 2>/dev/null
echo "$APP"; du -sh "$APP" "$OUT/Game"
