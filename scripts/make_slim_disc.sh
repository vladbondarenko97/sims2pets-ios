#!/bin/bash
# scripts/make_slim_disc.sh <your disc (.iso/.rvz/.gcm)> [out.rvz]: a smaller
# copy of your own disc for the device. The intro-only movies (EA/Maxis
# logos in 14 languages, the intro) are zeroed inside movies.arc (66 MB, no
# offsets change), then the disc is recompressed (RVZ, zstd 22, 512 KiB
# blocks): about 603 MB for the USA disc. The app's skip-intro mod (default)
# never plays them; with "Intro movies: Play" a slim disc hangs on a black screen.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IN=${1:?usage: make_slim_disc.sh <disc> [out.rvz]}
OUT=${2:-$ROOT/build/slim/sims2pets-slim.rvz}
TOOL=$ROOT/lib/ModernGekko/build/Binaries/dolphin-tool
[ -x "$TOOL" ] || { echo "dolphin-tool missing: make tools (MODERNGEKKO_ENABLE_DISC_TOOL=ON)" >&2; exit 1; }
WORK=$(dirname "$OUT")/slim-work
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT
"$TOOL" convert -u "$WORK/user" -i "$IN" -o "$WORK/full.iso" -f iso
"$TOOL" extract -i "$WORK/full.iso" -o "$WORK/x" -s DATA/movies.arc -q
ARC=$(find "$WORK/x" -name movies.arc | head -1)
python3 - "$WORK/full.iso" "$ARC" <<'PY'
import mmap, re, struct, sys
with open(sys.argv[1], 'r+b') as iso, open(sys.argv[2], 'rb') as f:
    arc = f.read(); m = mmap.mmap(iso.fileno(), 0)
    base = m.find(arc[:0x800])
    assert base > 0 and m[base:base + len(arc)] == arc, 'movies.arc not found in the disc'
    freed = 0
    for e in re.finditer(rb'([a-z0-9_]{4,})\x00', arc[:0x800]):
        name = e.group(1).decode()
        if name.startswith(('ea_games', 's2c_intro')):
            off, size = struct.unpack('>II', arc[e.start() - 8:e.start()])
            m[base + off:base + off + size] = bytes(size); freed += size
    m.flush(); print(f'zeroed {freed / 1e6:.0f} MB of intro movies')
PY
mkdir -p "$(dirname "$OUT")"
"$TOOL" convert -u "$WORK/user" -i "$WORK/full.iso" -o "$OUT" -f rvz -b 524288 -c zstd -l 22
echo "$OUT ($(du -h "$OUT" | cut -f1))"
