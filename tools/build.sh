#!/usr/bin/env bash
# Build ManualReload_VR.pk3 from this repo + assets taken from YOUR OWN copies of
#   HDVRweapons_Plus_v1.0.pk3  (pistol model)   and   brutalv21.pk3  (reload sounds)
# Those third-party assets are not stored in the repo.  The hand model
# (assets/webxr-hand, MIT) is.
# Needs: python3 + numpy + pygltflib, ffmpeg, unzip, zip
#
# usage: tools/build.sh [--desktop-test] path/to/HDVRweapons_Plus_v1.0.pk3 path/to/brutalv21.pk3 [out.pk3]
#   --desktop-test  swaps in tests/shim (fake VR hands driven by cvars) for the desktop test harness
set -euo pipefail
TEST=0; if [ "${1:-}" = "--desktop-test" ]; then TEST=1; shift; fi
HDVR=$(realpath "$1"); BD=$(realpath "$2"); OUT=$(realpath -m "${3:-ManualReload_VR.pk3}")
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

cp -r "$ROOT/src/." "$W/pk3"
if [ $TEST = 1 ]; then cp -r "$ROOT/tests/shim/." "$W/pk3/"; fi
P="$W/pk3/Models/Weapons/Hud/Pistol"; mkdir -p "$P" "$W/pk3/sounds/rlreload" "$W/x"

# models: pistol (+ tactical / physical frames), standalone magazine, posed hand
unzip -q -j -o "$HDVR" 'Models/Weapons/Hud/Pistol/Pistol.md3' -d "$W/x"
python3 -I "$ROOT/tools/make_tactical_md3.py" "$W/x/Pistol.md3" "$P/RL_Pistol.md3" "$P/RL_Mag.md3" "$P/RL_Round.md3" "$P/RL_Casing.md3"
python3 -I "$ROOT/tools/make_hand_md3.py" "$ROOT/assets/webxr-hand/right.glb" "$P/RL_Hand.md3" "$P/RL_Mag.md3"

# sounds
for n in RELOAD PRel.ogg DRYFIRE; do unzip -q -j -o "$BD" "SOUNDS/COMBAT/WEAPONS/$n" -d "$W/x"; done
unzip -q -j -o "$BD" "SOUNDS/ITEMS/CLIPICK" -d "$W/x"
for n in DSBOUNC1 DSBOUNC2; do unzip -q -j -o "$BD" "$(unzip -Z1 "$BD" | grep -i "/$n" | head -1)" -d "$W/x"; done
S="$W/pk3/sounds/rlreload"
cut() { ffmpeg -v error -y -i "$1" "${@:3}" -ar 22050 -ac 1 -c:a pcm_s16le "$S/$2.wav"; }
cut "$W/x/RELOAD"   RLMAGOUT -t 0.36 -af "afade=t=out:st=0.30:d=0.06"
cut "$W/x/RELOAD"   RLMAGIN  -ss 0.50 -af "afade=t=in:st=0:d=0.01"
cut "$W/x/PRel.ogg" RLSLIDE  -ss 0.58 -af "afade=t=in:st=0:d=0.01"
cut "$W/x/PRel.ogg" RLSLBACK -t 0.45 -af "afade=t=out:st=0.38:d=0.07"
cut "$W/x/DRYFIRE"  RLDRY
cut "$W/x/CLIPICK"  RLPOUCH
cp "$W/x/"DSBOUNC1* "$S/RLBNC1.lmp"; cp "$W/x/"DSBOUNC2* "$S/RLBNC2.lmp"

rm -f "$OUT"; (cd "$W/pk3" && zip -q -r -X "$OUT" .)
echo "built $OUT"
