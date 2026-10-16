#!/usr/bin/env bash
# Build ManualReload_VR.pk3 from this repo + assets taken from YOUR OWN copies of
#   HDVRweapons_Plus_v1.0.pk3  (pistol model)   and   brutalv21.pk3  (reload sounds)
# Those third-party assets are not stored in the repo.
# Needs: python3 + numpy, ffmpeg, unzip, zip
#
# usage: tools/build.sh path/to/HDVRweapons_Plus_v1.0.pk3 path/to/brutalv21.pk3 [out.pk3]
set -euo pipefail
HDVR=$(realpath "$1"); BD=$(realpath "$2"); OUT=$(realpath -m "${3:-ManualReload_VR.pk3}")
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

cp -r "$ROOT/src/." "$W/pk3"
mkdir -p "$W/pk3/Models/Weapons/Hud/Pistol" "$W/pk3/sounds/rlreload" "$W/x"

# model: original frames + generated tactical-reload frames
unzip -q -j -o "$HDVR" 'Models/Weapons/Hud/Pistol/Pistol.md3' -d "$W/x"
python3 -I "$ROOT/tools/make_tactical_md3.py" "$W/x/Pistol.md3" "$W/pk3/Models/Weapons/Hud/Pistol/RL_Pistol.md3"

# sounds
for n in RELOAD PRel.ogg DRYFIRE; do unzip -q -j -o "$BD" "SOUNDS/COMBAT/WEAPONS/$n" -d "$W/x"; done
for n in DSBOUNC1 DSBOUNC2; do unzip -q -j -o "$BD" "$(unzip -Z1 "$BD" | grep -i "/$n" | head -1)" -d "$W/x"; done
S="$W/pk3/sounds/rlreload"
ffmpeg -v error -y -i "$W/x/RELOAD"   -t 0.36 -af "afade=t=out:st=0.30:d=0.06" -ar 22050 -ac 1 -c:a pcm_s16le "$S/RLMAGOUT.wav"
ffmpeg -v error -y -i "$W/x/RELOAD"   -ss 0.50 -af "afade=t=in:st=0:d=0.01"  -ar 22050 -ac 1 -c:a pcm_s16le "$S/RLMAGIN.wav"
ffmpeg -v error -y -i "$W/x/PRel.ogg" -ss 0.58 -af "afade=t=in:st=0:d=0.01"  -ar 22050 -ac 1 -c:a pcm_s16le "$S/RLSLIDE.wav"
ffmpeg -v error -y -i "$W/x/DRYFIRE"  -ar 22050 -ac 1 -c:a pcm_s16le "$S/RLDRY.wav"
cp "$W/x/"DSBOUNC1* "$S/RLBNC1.lmp"; cp "$W/x/"DSBOUNC2* "$S/RLBNC2.lmp"

rm -f "$OUT"; (cd "$W/pk3" && zip -q -r -X "$OUT" .)
echo "built $OUT"
