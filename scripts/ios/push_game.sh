#!/bin/bash
# scripts/ios/push_game.sh: the game into the app's Documents/game on a
# jailbroken device over USB (OpenSSH as `mobile` with this Mac's key, through
# pymobiledevice3's usbmux forward). Kept across app updates. Not jailbroken:
# copy build/ios/game in with Finder or the Files app instead.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
[ -f "$ROOT/scripts/ios/local.env" ] && . "$ROOT/scripts/ios/local.env"
BUNDLE_ID=${IOS_BUNDLE_ID:-io.github.sims2pets-ios}
PORT=2222
SSH=(ssh -o BatchMode=yes -p "$PORT" mobile@127.0.0.1)
export PATH="$HOME/.local/bin:$PATH"
if ! nc -z 127.0.0.1 "$PORT" 2>/dev/null; then
    pymobiledevice3 usbmux forward ${IOS_UDID:+--serial "$IOS_UDID"} "$PORT" 22 >/dev/null 2>&1 &
    FORWARD=$!
    trap 'kill $FORWARD 2>/dev/null || true' EXIT
    sleep 2
fi
# shellcheck disable=SC2016
DATA=$("${SSH[@]}" 'for d in /var/mobile/Containers/Data/Application/*; do
    grep -q -a "'"$BUNDLE_ID"'" "$d/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null && echo "$d" && break; done')
[ -n "$DATA" ] || { echo "push_game.sh: $BUNDLE_ID has no data folder yet (launch the app once)" >&2; exit 1; }
"${SSH[@]}" "df -h /var | tail -1; rm -rf '$DATA/Documents/game' && mkdir -p '$DATA/Documents/game'"
# build/ios/game (scripts/build_ios.sh): sys/, files/ (empty), disc.rvz.
COPYFILE_DISABLE=1 tar -C "$ROOT/build/ios/game" -cf - --no-xattrs . | "${SSH[@]}" "tar -C '$DATA/Documents/game' -xf -"
"${SSH[@]}" "du -sh '$DATA/Documents/game'; df -h /var | tail -1"
echo "$DATA"
