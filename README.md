# Manual Reload for QuestZDoom 3D weapons

Adds magazine-based manual reloading to the vanilla Doom weapons when played with the
HDVR 3D weapon packs in QuestZDoom (Meta Quest). No Brutal Doom required.

**Status:** Pistol (Beretta 92FS style) and pump shotgun (870 style, 6+1) done. More weapons next.

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
- **Grip vs trigger:** with QuestZDoom's *Two Handed Weapons* on, squeezing the off-hand **grip** anywhere
  within ~50 cm of your gun hand (your hip included) makes QuestZDoom aim the gun *at your off hand*. That's
  right for a shotgun pump, but on the pistol the support hand sits beside/under the gun, so it bends the
  aim down. Grab with the off-hand **trigger**, and turn *QuestZDoom Two Handed Weapons* off (it's in the
  Manual Reload menu) if you play pistol-heavy. A red warning shows while it's bending your aim.
- Dropped mags fall and lie on the floor; racking with a round chambered ejects a live round; every
  shot ejects a spent case.

**Weapon switching:** *Manual Reload Settings → Right stick up/down = switch weapons* binds the right
stick (which QuestZDoom sends as mouse-wheel up/down) to previous/next weapon.

Whatever way you get a pistol or shotgun (cheat menu, `give`, an old save), the mod swaps it for its own
version automatically.

Settings live in *Options → Manual Reload Settings*: physical on/off, off-hand orientation,
grab-zone sliders, and a **calibration readout** that shows your hand's position relative to the
gun so the zones can be tuned. Jumping is disabled (B is the mag release).

QuestZDoom's own *Two Handed Weapons* option hides the off-hand model while it's steadying the gun.

## Shotgun (physical)
- **Work the pump with your off hand** (grip or trigger on the pump). Pulling it fully back ejects
  what's in the chamber: a fired hull, or a live shell (which goes back to your reserve). Pushing it
  home chambers the next shell from the tube. It only fires with a live shell chambered and the pump home.
- With QuestZDoom's *Two Handed Weapons* on, the **grip** on the pump also steadies your aim along the
  line between your hands — the hand that steadies is the hand that pumps.
- **Load:** off-hand **trigger** at your hip takes one shell; push it into the loading port under the
  receiver. Repeat, up to 6 in the tube.
- Flat screen: fire pumps automatically, Reload loads shells one at a time (fire to stop).

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
