# Manual Reload for QuestZDoom 3D weapons

Adds magazine-based manual reloading to the vanilla Doom weapons when played with the
HDVR 3D weapon packs in QuestZDoom (Meta Quest). No Brutal Doom required.

**Status:** Pistol done (Beretta 92FS style). Other weapons next.

## Physical reloading (VR, default)
Your off hand is visible (rigged WebXR hand model) and does the work:
- **B** (gun hand) = magazine release. The mag drops out of the gun.
- **Grip at your hip** = draw a fresh magazine (filled from your reserve).
- **Push it into the bottom of the grip** = it seats. With a round still chambered you're done (15+1).
- **Grip the back of the slide and pull** = rack. From slide-lock a short tug slingshots it;
  a full rack with a round chambered ejects that round.
- The slide locks back on an empty mag, stays locked when you swap mags, and the gun won't fire
  with the slide out of battery.
- Let go of a mag away from the gun and it goes back in your pouch.
- **Two-handed grip:** squeeze the off-hand grip on the pistol and your hand wraps the grip (it
  stays there after you seat a mag). If it looks like the wrong hand, switch *Two-handed grip hand*.
- **Grip vs trigger:** with QuestZDoom's *Two Handed Weapons* on, the off-hand **grip** near a gun makes
  QuestZDoom steady the aim along the line between your hands (best on long guns); the mod detects this
  and treats the hand as holding the gun. Use the off-hand **trigger** to grab things (mags, slide) — it
  never engages QuestZDoom's steadying.
- Dropped mags fall and lie on the floor; racking with a round chambered ejects a live round; every
  shot ejects a spent case.

Settings live in *Options → Manual Reload Settings*: physical on/off, off-hand orientation,
grab-zone sliders, and a **calibration readout** that shows your hand's position relative to the
gun so the zones can be tuned. Jumping is disabled (B is the mag release).

QuestZDoom's own *Two Handed Weapons* option hides the off-hand model while it's steadying the gun.

## Button reloading (non-VR, or physical off)
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
`assets/webxr-hand/right.glb` is the WebXR generic hand (MIT, see its LICENSE). `tools/make_hand_md3.py`
poses it (relaxed / grip / holding mag / pinch) and writes the game model.

Third-party assets are not in this repo. `tools/build.sh` pulls them from your own copies:
- the 3D pistol model from the HDVR weapons pack (and generates extra tactical-reload frames
  with `tools/make_tactical_md3.py`, keeping the slide forward during the mag swap),
- reload sounds from `brutalv21.pk3`.

```
tools/build.sh path/to/HDVRweapons_Plus_v1.0.pk3 path/to/brutalv21.pk3 ManualReload_VR.pk3
```
Needs python3 + numpy + pygltflib, ffmpeg, unzip, zip.

`tools/build.sh --desktop-test ...` builds a variant whose `RL_VR` layer fakes both controllers
from console variables (`tests/shim`), so the whole physical reload can be scripted and checked
on desktop LZDoom with `tests/probe_physical.zs` logging the gun's state.

## Files
- `src/zscript/rl_pistol.zs` – weapon logic (magazine, chamber, reload states)
- `src/DECORATE.RLReload` – player class + map pistol replacement
- `src/MODELDEF.RLReload` – maps animation states to model frames
- `src/KEYCONF.RLReload`, `src/ZMAPINFO.RLReload` – player class + reload command aliases
- `src/SNDINFO.RLReload`, `src/MENUDEF.RLReload`, `src/CVARINFO.RLReload`, `src/TEXTURES.RLReload`

## Credits
Pistol model: HDVR weapons pack (Models/Weapons/Hud/Pistol). Sounds: Brutal Doom v21.
Hand model: WebXR Input Profiles generic hand, © 2019 Amazon, MIT License.
Engine: QuestZDoom (LZDoom/GZDoom).
