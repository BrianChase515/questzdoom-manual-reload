# Manual Reload — Master Spec

Single source of truth for how every weapon reloads, and for what we learned getting the
pistol working. Update the weapon table when a decision changes; update "Engine lessons"
whenever something bites us.

## 1. Global rules (all weapons)

| Rule | Decision |
|---|---|
| Reserve ammo | Stays in Doom's normal pools (Clip / Shell / RocketAmmo / Cell). Pickups, backpacks, cheats untouched. |
| Loaded ammo | Separate per-weapon items: `RL_<Weapon>Mag` (Ammo subclass → shows as HUD ammo2) and, where the gun has one, `RL_<Weapon>Chamber`. |
| Engine auto-ammo | Disabled per weapon with `AmmoUse 0` + `+AMMO_OPTIONAL` + `A_FireBullets(..., flags 0)`. Firing only consumes loaded rounds. Weapon never auto-switches when its mag is empty. |
| Empty gun | Trigger gives a dry click. No auto-reload, ever. |
| Reload input (VR) | Physical: B = mag release, off-hand grip (`+reload`, "RThumb") = grab. Hip zone = draw mag; magwell zone = seat; slide zone = rack. |
| Reload input (non-VR) | `+reload`, plus aliases `reload` / `reloader` (Brutal Doom's commands). |
| Off hand | `RL_OffHand` weapon in QuestZDoom's off-hand slot; pose frame set every tic from the active gun's hand state. 3 orientation variants selectable in menu until we know which is right. |
| Reload no-op | Gun full, or no reserve ammo (unless a chamber-only action is possible). |
| Dropped mag rounds | Return to reserve by default; `rl_droppedmag_loses_rounds` makes them lost. Applies to every detachable-mag weapon. |
| First pickup | Weapon arrives fully loaded (`AttachToOwner` override). |
| Cancel mid-reload | Weapon switch is allowed; rounds are never destroyed by it (drop returns to reserve before insert). |
| Visuals | Reuse unused frames in the HDVR model when they exist. Otherwise generate frames with the md3 tool (rigid tilt / part offsets). Never ship hand-edited third-party assets in the repo — build from user's copies. |
| Sounds | Cut from the user's `brutalv21.pk3` at build time. |
| Compatibility | Load order: IWAD → HDVRweapons_Plus (or Quest_Plus) → ManualReload_VR.pk3. New game required. |

## 2. Weapon table

Status: ✅ done · 🧪 needs headset test · 📝 proposed (needs Brian's OK)

| Weapon | Real-world model | Capacity | Reload style | Animation source | Status |
|---|---|---|---|---|---|
| Pistol | Beretta 92FS | 15+1 | Physical: B release, hip draw, tap to seat, grab-and-rack; slide lock on empty mag. Button mode: tactical / empty auto sequences. | HDVR frames 8–26 (empty); generated 38–55 (tactical), 56–73 (slide steps, mag in/out) | ✅ desktop sim · 🧪 headset |
| Shotgun | Pump (Rem 870 style) | 6+1 tube | Physical: pump by hand (eject on back, feed on forward), shells one at a time from hip into loading port; QuestZDoom two-handed steadying on the pump. Button: auto-pump, shell-by-shell reload | HDVR surfaces: 2 shell, 4 pump, 5 bolt; frames 33–35 pump, 22–31 load; generated 36–53 pump steps ± shell; pump hand md3 | ✅ desktop sim · 🧪 headset |
| Super Shotgun | Double-barrel | 2 | 📝 Manual break-open: only reloads when you press reload (vanilla auto-reloads after every shot) | HDVR ssg.md3 already has open/load/close (frames 26–45) | 📝 |
| Chaingun | — | 📝 100-round belt box (vanilla uses Clip) | 📝 Box swap | 📝 No reload frames; generate a tilt-down/up | 📝 |
| Rocket Launcher | — | 📝 1 in tube? or 4-round mag | 📝 Single load | 📝 RPG.md3 frames 17–33 move sub-parts — likely a load; verify | 📝 |
| Plasma Rifle | — | 📝 50-cell pack | 📝 Pack swap | 📝 Check PlasmaRifle model | 📝 |
| BFG | — | 📝 1 shot (40 cells) per charge | 📝 Recharge/cell swap | 📝 No reload frames; generate | 📝 |
| Fist / Chainsaw | — | — | No reload | — | n/a |

### Per-weapon checklist (copy for each new weapon)
1. Inspect the HDVR md3: frame count, per-surface motion, identify parts (bounding boxes).
2. Decide capacity / chamber / reload style → fill the table above.
3. Write `src/zscript/rl_<weapon>.zs` from the pistol template.
4. Add `RL_<Weapon>` to `RL_Marine` slots and a `RandomSpawner replaces <Vanilla>` in DECORATE.
5. MODELDEF block for the new class (copy HDVR scale/offset/flash blocks).
6. TEXTURES placeholder sprites for every new sprite frame used.
7. Sounds into SNDINFO + build.sh.
8. Run the engine test harness (section 4) — counts must match expected for: start, fire N, tactical, empty, full no-op, zero reserve.
9. Headset test, then tick the table.

## 2b. Framework
`RL_PhysWeapon` (src/zscript/rl_base.zs) owns hand tracking, off-hand model, zones (`InZone(prefix,...)` reads
`<prefix>_f/_s/_u/_r` cvars), calibration wizard (per-weapon `CalZone/CalPrompt`), logging and ejecta.
A weapon overrides `PhysTick`, `OffhandPose`, `StatusLine/ZoneLine` and draws its own model frames.

## 3. Engine lessons (the trial-and-error, written down)

- **Engine** is QuestZDoom 1.5.0 = LZDoom 3.88b + VR changes. ZScript `version "3.6"` works. Use `A_StartSound`.
- **A weapon is silently NOT given** if its Ready state's sprite frame has no image (`ValidateSpriteFrame`). Model-only frames still need sprite entries → `TEXTURES.RLReload` defines them as aliases of the vanilla sprite.
- **MODELDEF is keyed by class name**, not inherited. Every new weapon class needs its own model blocks (incl. muzzle flash).
- **ZScript compiles before DECORATE.** HDVR's effects (`EnBulletPuff`, `GunBarrelSmoke`, `BulletTracer`) are DECORATE, so reference them by name at run time (`class<Actor> c = name;`), never as compile-time constants.
- **Player class:** DECORATE child of HDVR's `DoomMarineGuy` (first `StartItem` in a child clears the parent list — re-list everything), plus `KEYCONF` (`clearplayerclasses`/`addplayerclass`) and `ZMAPINFO GameInfo { PlayerClasses }`.
- Map-placed weapons: a later `RandomSpawner replaces X` wins over HDVR's.
- md3 frame surgery works: rigid-fit the body between frames (Kabsch) and move other parts with it. Fit error on the pistol was ~0.03 units.
- KEYCONF aliases print a harmless "Unknown command" at startup; they still work.
- Saves made before the mod keep old weapon classes → new game.

- **VR engine API** (QuestZDoom only, all wrapped in `src/zscript/rl_vr.zs`): `AttackPos/OffhandPos`,
  `AttackDir/OffhandDir(actor, yaw, pitch)` — feeding player angle/pitch +90 yaw / -90 pitch gives the
  controller's forward/side/up axes including roll. `player.OffhandWeapon` + `PSP_OFFHANDWEAPON` layer
  draws a weapon model at the off-hand controller. Off-hand grip sends `KEY_PAD_RTHUMB`; off-hand trigger
  `KEY_LSHIFT`. When QuestZDoom's own two-handed stabilisation engages it hides the off-hand layer.
- Positions are world map units (~3 cm each). Grab zones are cvars so they can be tuned in the menu.
- Model frames chosen per tic (psprite Sprite/Frame) need `NOINTERPOLATION` model blocks, or the renderer
  blends toward the state's own frame.

- **QuestZDoom 1.5.x quirk:** the *script* versions of `AttackDir`/`OffhandDir` return `(yaw, pitch, 0)` in
  degrees, not a vector (engine-side firing uses the real vector). `RL_Math.ToDir` converts (z == 0 exactly
  means angle form). Newer QuestZDoom returns a real unit vector; both are handled.
- Mod cvars are saved in the player's config, so changing a default does nothing for existing players —
  rename the cvar when a default must change.
- Every model in a MODELDEF block is drawn on every frame of that block; give optional parts their own block.
- Mods can't change engine cvars (e.g. `vr_two_handed_weapons`) outside menus — detect the engine's
  two-handed steadying instead (gun forward == gun→off-hand line).
- Overrides of `clearscope` virtuals must not repeat `clearscope`; `cross`/`dot` are operators, not names.
- Calibration wizard (`rl_calib_request`) records magwell / slide spots from the player's own hands.
- QuestZDoom two-handed steadying (VrInputDefault.cpp): engages on an off-hand **grip** press while the hands
  are < 0.5 m apart and replaces gun pitch/yaw with the dominant→off-hand line until the grip is released.
  Wrong for pistols (support hand isn't in front) and for grabbing at the hip. Engine cvars *can* be set
  from a MENUDEF `Option` (not from console/alias in mod context), so the menu exposes `vr_two_handed_weapons`.
- KEYCONF aliases run "unsafe", but `bind` is a safe command, so a menu `Command` can call an alias that binds
  keys. QuestZDoom sends right stick up/down as MWheelUp/MWheelDown.
- Weapons that arrive by `give`/cheat menus/old saves bypass `replaces`; `RL_WeaponSwap` converts them in
  inventory each tic (exact-class match on Pistol/Shotgun and HDVR's Vanilla_* subclasses).
- A Name compared with a `class<Actor>` is compiled as a class constant — compare `GetClassName()` for
  DECORATE classes.
- **Model units → gun space (QuestZDoom HUD models, from `RenderHUDModel`):** with MODELDEF `Scale -1 1 1`
  and no offsets, an md3 point (x fwd, y, z up) sits at roughly
  `forward = (1.02x − 30)·0.34`, `up = (1.02z + 5)·0.34`, `side = −1.02y·0.34` (side + = left) map units from
  `AttackPos` (the engine applies hand transform · 0.01 m · translate(0,5,30) · vr_weaponScale 1.02, and
  34 units per metre). Model −y is the gun's right. Checked against the pistol zones the player calibrated.
  Use this to place grab zones from the model instead of guessing.
- The hand model's fingertip joints carry no skin weight; pick fingertip vertices from the distal phalanges.
- The pump hand is posed by closing each finger joint until it touches a cylinder the size of the pump
  (and stays out of the barrel), with the pump angled across the palm so the wrist trails back.
- Deliveries to the laptop are verified by pulling the file back and comparing hashes.

## 4. Test harness

Desktop LZDoom 3.88b built from source (headers fix: `-include cstdint -include stdexcept ...`, stub
`I_BuildALDeviceList`/`I_BuildALResamplersList` when built without OpenAL), run under Xvfb with
`-iwad PLUTONIA.WAD -file HDVRweapons_Plus ManualReload_VR.pk3 probe -warp 1`.
A probe event handler logs `mag / chamber / reserve / sprite frame` every change.
`--desktop-test` builds swap in `tests/shim/zscript/rl_vr.zs`, which fakes both controllers from cvars
(`rl_fake_vr`, `rl_fake_mode` gun/body space, `rl_fake_f/s/u`), so hand gestures can be scripted.
**Gotcha:** startup `+commands` all run immediately — `wait` only delays commands in the same
string, so put the whole input script in ONE `+"cmd; wait N; cmd; ..."` argument.
