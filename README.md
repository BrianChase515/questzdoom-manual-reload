# Manual Reload for QuestZDoom 3D weapons

Adds magazine-based manual reloading to the vanilla Doom weapons when played with the
HDVR 3D weapon packs in QuestZDoom (Meta Quest). No Brutal Doom required.

**Status:** Pistol done (Beretta 92FS style). Other weapons next.

## Pistol behaviour
- 15-round magazine + 1 in the chamber (15+1).
- Reserve ammo is the normal Doom bullet pool, so pickups, backpacks and the chaingun work as usual.
- Firing the last round locks the slide back; pulling the trigger after that just clicks.
- **Reload with a round chambered** (tactical): drop mag, insert mag → 15+1. Slide stays forward.
- **Reload from slide-lock**: drop mag, insert mag, slide release → 14+1.
- Reload does nothing if the gun is full or you have no reserve ammo.
- Leftover rounds in a dropped mag go back to your reserve (toggle in
  *Options → Manual Reload Settings* to lose them instead).
- The HUD's second ammo counter shows rounds in the magazine.

## Controls
Reload responds to the engine's **Reload** binding (`+reload`, right-stick click in the default
QuestZDoom config) and also to Brutal Doom's `reload` / `reloader` commands, so a button you set up
for Brutal Doom's reload works too.

## Install
1. Copy `ManualReload_VR.pk3` into `QuestZDoom/mods/` on the headset.
2. In the QuestZDoom launcher, load it **after** `HDVRweapons_Plus_v1.0.pk3`
   (or `HDVRweapons_Quest_Plus_v1.0.pk3`).
3. Start a **new game**. Saves from before the mod keep the old pistol.

## Building
Third-party assets are not in this repo. `tools/build.sh` pulls them from your own copies:
- the 3D pistol model from the HDVR weapons pack (and generates extra tactical-reload frames
  with `tools/make_tactical_md3.py`, keeping the slide forward during the mag swap),
- reload sounds from `brutalv21.pk3`.

```
tools/build.sh path/to/HDVRweapons_Plus_v1.0.pk3 path/to/brutalv21.pk3 ManualReload_VR.pk3
```
Needs python3 + numpy, ffmpeg, unzip, zip.

## Files
- `src/zscript/rl_pistol.zs` – weapon logic (magazine, chamber, reload states)
- `src/DECORATE.RLReload` – player class + map pistol replacement
- `src/MODELDEF.RLReload` – maps animation states to model frames
- `src/KEYCONF.RLReload`, `src/ZMAPINFO.RLReload` – player class + reload command aliases
- `src/SNDINFO.RLReload`, `src/MENUDEF.RLReload`, `src/CVARINFO.RLReload`, `src/TEXTURES.RLReload`

## Credits
Pistol model: HDVR weapons pack (Models/Weapons/Hud/Pistol). Sounds: Brutal Doom v21.
Engine: QuestZDoom (LZDoom/GZDoom).
