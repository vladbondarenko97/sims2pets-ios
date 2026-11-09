#!/bin/bash
# scripts/ios/build_ipa.sh: The Sims 2: Pets for iOS (build/ios/Sims2Pets.ipa).
# Needs lib/ModernGekko/build-ios and build/ios-module (scripts/build_ios.sh
# makes both). GAME_DIR=<sys/ + disc.rvz> puts the game inside the app.
# Ad hoc signed: TrollStore installs it as is; SideStore/AltStore re-sign it.
# scripts/ios/local.env (not in git) can set IOS_BUNDLE_ID and the like.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
[ -f "$ROOT/scripts/ios/local.env" ] && . "$ROOT/scripts/ios/local.env"
BUNDLE_ID=${IOS_BUNDLE_ID:-io.github.sims2pets-ios}
MG=$ROOT/lib/ModernGekko
B=$MG/build-ios
OUT=$ROOT/build/ios
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CXX=(xcrun --sdk iphoneos clang++ -target arm64-apple-ios15.0 -isysroot "$SDK")
ninja -C "$B" moderngekko
mkdir -p "$OUT"
P=$OUT/stage/Payload/Sims2Pets.app
rm -rf "$OUT/stage"; mkdir -p "$P"
"${CXX[@]}" -c "$ROOT/scripts/ios/main.mm" -o "$OUT/main.o"
LIBS=()
while IFS= read -r a; do LIBS+=("$a"); done < <(find "$B" -name '*.a' ! -name 'libmoderngekko.a' ! -name 'libmoderngekko_legacy.a' ! -name 'libgtest*' | sort)
FRAMEWORKS=()
for fw in AVFoundation AudioToolbox CoreAudio CoreFoundation CoreGraphics CoreMotion CoreVideo Foundation \
          GameController IOSurface Metal MetalKit QuartzCore Security SystemConfiguration UIKit; do
    FRAMEWORKS+=(-framework "$fw")
done
"${CXX[@]}" -o "$P/Sims2Pets" "$OUT/main.o" -Wl,-force_load,"$B/libmoderngekko.a" \
    "$ROOT/build/ios-module/gG4OE69_recomp.a" "${LIBS[@]}" "${FRAMEWORKS[@]}" -lz -liconv -lbz2 -lresolv \
    -Wl,-dead_strip -Wl,-U,___llvm_profile_write_file -Wl,-U,___llvm_profile_set_filename \
    -Wl,-U,___llvm_profile_reset_counters ${IPA_LDFLAGS:-}
sed "s/BUNDLE_ID/$BUNDLE_ID/" "$ROOT/scripts/ios/Info.plist" > "$P/Info.plist"
# Build stamp, shown at launch (PlatformIOS.mm) so the installed build is easy to tell apart.
STAMP="$(date '+%b %-d %H:%M') · $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo local)"
plutil -replace CFBundleVersion -string "$(date +%Y%m%d.%H%M)" "$P/Info.plist"
plutil -insert MGBuildStamp -string "$STAMP" "$P/Info.plist"
cp -R "$MG/vendor/dolphin/Data/Sys" "$P/Sys"
[ -n "${GAME_DIR:-}" ] && cp -R "$GAME_DIR" "$P/game"
# The icon (scripts/ios/icon.png; icon.local.png, not in git, wins), in the sizes iOS looks for.
ICON=$ROOT/scripts/ios/icon.png
[ -f "$ROOT/scripts/ios/icon.local.png" ] && ICON=$ROOT/scripts/ios/icon.local.png
for spec in AppIcon60x60@2x:120 AppIcon60x60@3x:180 AppIcon76x76@2x~ipad:152 AppIcon83.5x83.5@2x~ipad:167; do
    sips -s format png -z "${spec#*:}" "${spec#*:}" "$ICON" --out "$P/${spec%%:*}.png" >/dev/null
done
codesign --force --sign - --timestamp=none --generate-entitlement-der \
    --entitlements "$ROOT/scripts/ios/app.entitlements" "$P"
IPA=$OUT/Sims2Pets.ipa
rm -f "$IPA"
(cd "$OUT/stage" && zip -q -r -y -1 "$IPA" Payload)
echo "$IPA ($(du -h "$IPA" | cut -f1))"
