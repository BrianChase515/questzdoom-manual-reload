// ===========================================================================
//  Manual Reload for VR 3D weapons  -  Pistol (Beretta 92FS style, 15+1)
//
//  Two ways to reload:
//   * PHYSICAL (VR, default): B drops the mag, grip at your hip draws a fresh
//     one, push it into the bottom of the grip to seat it, grab the back of the
//     slide and pull to rack.  Tactical reloads just need the mag tapped in.
//   * BUTTON (non-VR, or rl_physical off): the Reload button does the whole
//     sequence automatically (tactical / empty).
//
//  Reserve ammo is Doom's normal "Clip" pool.
// ===========================================================================

class RL_PistolMag : Ammo
{
	Default
	{
		Inventory.MaxAmount 15;
		Ammo.BackpackMaxAmount 15;
		Ammo.BackpackAmount 0;
		Inventory.Icon "CLIPA0";
		Tag "Pistol magazine";
		+INVENTORY.IGNORESKILL
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
	}
}

class RL_PistolChamber : Inventory
{
	Default
	{
		Inventory.MaxAmount 1;
		+INVENTORY.KEEPDEPLETED
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
		+INVENTORY.IGNORESKILL
	}
}

class RL_Pistol : Pistol
{
	const MAGSIZE = 15;

	// hand states for the physical reload
	enum EHand
	{
		HAND_EMPTY,
		HAND_MAG,       // holding a fresh magazine
		HAND_SLIDE,     // pinching the slide
		HAND_GRIP,      // gripping nothing in particular
		HAND_SUPPORT    // two-handed grip on the pistol
	};

	// ---- physical-reload state (public so the calibration overlay can read it)
	bool   physActive;
	bool   magSeated;
	bool   slideLocked;
	int    hand;
	int    heldRounds;
	double grabF;          // off-hand forward position when the slide was grabbed
	bool   cycled;         // slide pulled far enough to cycle
	double slideShown;     // 0 = forward, 1 = locked back (drives the model)
	int    prevButtons;
	// last measured positions, for calibration
	double lf, ls, lu;     // off hand relative to gun (forward, side, up)
	double bh, bd, eyeH;   // off hand height above feet, distance from body, eye height
	bool   nearWell, nearSlide, inHip, nearGun;
	bool   steadied;       // QuestZDoom's two-handed mode is aiming the gun at the off hand
	int    steadyTics;
	int    calStep;      // 0 = off, 1 = waiting for magwell squeeze, 2 = waiting for slide squeeze
	Vector3 rawGun, rawOff, rawFwd, rawUp;   // raw engine values relative to the player, for the readout
	double rawFwdLen;

	Default
	{
		Weapon.AmmoType1 "Clip";
		Weapon.AmmoUse1 0;          // rounds come out of the magazine, not the reserve
		Weapon.AmmoGive1 20;
		Weapon.AmmoType2 "RL_PistolMag";
		Weapon.AmmoUse2 0;
		Weapon.AmmoGive2 0;
		Weapon.SlotNumber 2;
		+WEAPON.AMMO_OPTIONAL
		+WEAPON.ALT_AMMO_OPTIONAL
	}

	// ---- helpers ---------------------------------------------------------

	static int RL_CVarInt(Name n, int def = 0)
	{
		CVar cv = CVar.FindCVar(n);
		return cv ? cv.GetInt() : def;
	}

	static double RL_CVarF(Name n, double def = 0)
	{
		CVar cv = CVar.FindCVar(n);
		return cv ? cv.GetFloat() : def;
	}

	// Look a class up at run time, so this mod still loads if the
	// HDVR pack (which defines the "enhanced" effects) is missing.
	static class<Actor> RL_FindActor(Name n, class<Actor> fallback = null)
	{
		class<Actor> c = n;
		return c ? c : fallback;
	}

	// The gun comes loaded the first time you get it (15+1).
	override void AttachToOwner(Actor other)
	{
		Super.AttachToOwner(other);
		if (other)
		{
			other.GiveInventory("RL_PistolMag", MAGSIZE);
			other.GiveInventory("RL_PistolChamber", 1);
		}
		magSeated = true;
		slideLocked = false;
		hand = HAND_EMPTY;
	}

	action bool RL_Chambered() { return CountInv("RL_PistolChamber") > 0; }
	action int  RL_MagCount()  { return CountInv("RL_PistolMag"); }
	action bool RL_Physical()  { return invoker.physActive; }

	// ======================================================================
	//  PHYSICAL RELOAD  -  runs every tic while the pistol is owned
	// ======================================================================

	override void DoEffect()
	{
		Super.DoEffect();
		let pm = PlayerPawn(Owner);
		if (!pm || !pm.player || pm.player.mo != pm) return;

		physActive = RL_VR.Active(pm) && RL_CVarInt('rl_physical', 1) != 0;
		if (!physActive) { hand = HAND_EMPTY; slideShown = 0; return; }

		EnsureOffhand(pm);

		int buttons = pm.player.cmd.buttons;
		bool gripNow  = (buttons & BT_RELOAD) != 0;
		bool gripWas  = (prevButtons & BT_RELOAD) != 0;
		bool magRelease = (buttons & BT_JUMP) && !(prevButtons & BT_JUMP);
		prevButtons = buttons;

		if (pm.player.ReadyWeapon != self)
		{
			// Gun put away: stow anything in the off hand.
			if (hand == HAND_MAG) StowHeldMag(pm);
			hand = HAND_EMPTY;
			return;
		}

		Measure(pm);

		// ---- grab-zone calibration wizard ---------------------------------
		CVar req = CVar.FindCVar('rl_calib_request');
		if (req && req.GetInt() != 0) { req.SetInt(0); calStep = 1; hand = HAND_EMPTY; }
		if (calStep > 0)
		{
			if (gripNow && !gripWas)
			{
				if (calStep == 1)
				{
					SetF('rl_well_f', lf); SetF('rl_well_s', ls); SetF('rl_well_u', lu);
					pm.A_StartSound("rl/pistol/magin", CHAN_AUTO);
					calStep = 2;
				}
				else
				{
					SetF('rl_slide_f', lf); SetF('rl_slide_s', ls); SetF('rl_slide_u', lu);
					pm.A_StartSound("rl/pistol/slide", CHAN_AUTO);
					calStep = 0;
				}
				if (RL_CVarInt('rl_log') != 0) RL_Log(pm, "CALIBRATE");
			}
			slideShown = slideLocked ? 1 : 0;
			return;                       // no reload actions while calibrating
		}

		// calibration log: every grip squeeze / mag release writes a tagged line
		if (RL_CVarInt('rl_log') != 0)
		{
			if (gripNow && !gripWas) RL_Log(pm, "GRIP");
			if (magRelease) RL_Log(pm, "MAGRELEASE");
			if (level.maptime % 70 == 0) RL_Log(pm, "TICK");
		}

		// ---- QuestZDoom two-handed hold: the grip (not the trigger) is holding the gun
		if (steadied && gripNow && hand != HAND_MAG) { hand = HAND_SUPPORT; cycled = false; }

		// ---- mag release (B) -------------------------------------------
		if (magRelease && magSeated) EjectMag(pm);

		// ---- grip pressed -----------------------------------------------
		if (gripNow && !gripWas && hand == HAND_EMPTY)
		{
			if (nearSlide)
			{
				hand = HAND_SLIDE;
				grabF = lf;
				cycled = false;
			}
			else if (nearGun) hand = HAND_SUPPORT;          // on the gun beats the hip pouch
			else if (inHip && pm.CountInv("Clip") > 0)
			{
				heldRounds = min(MAGSIZE, pm.CountInv("Clip"));
				pm.TakeInventory("Clip", heldRounds);
				hand = HAND_MAG;
				pm.A_StartSound("rl/pistol/pouch", CHAN_AUTO);
			}
			else hand = HAND_GRIP;
		}

		// ---- grip held ---------------------------------------------------
		if (gripNow)
		{
			if (hand == HAND_MAG && nearWell && !magSeated) SeatMag(pm);

			if (hand == HAND_SLIDE)
			{
				double rackLen = RL_CVarF('rl_rack_len', 2.5);
				double pull = clamp((grabF - lf) / rackLen, 0, 1);
				if (slideLocked)
				{
					slideShown = 1;
					if (pull > 0.15) cycled = true;      // slingshot from slide-lock
				}
				else
				{
					slideShown = pull;
					if (pull >= 0.9 && !cycled)
					{
						cycled = true;
						// Racking with a round chambered ejects it.
						if (pm.CountInv("RL_PistolChamber") > 0)
						{
							pm.TakeInventory("RL_PistolChamber", 1);
							pm.GiveInventory("Clip", 1);      // ejected round is picked back up
							EjectRound(pm);
						}
						pm.A_StartSound("rl/pistol/slideback", CHAN_AUTO);
					}
				}
			}
		}
		// ---- grip released -----------------------------------------------
		else if (gripWas)
		{
			if (hand == HAND_SLIDE && cycled) SlideForward(pm);
			if (hand == HAND_MAG) StowHeldMag(pm);
			hand = HAND_EMPTY;
		}

		if (hand != HAND_SLIDE) slideShown = slideLocked ? 1 : 0;
	}

	void Measure(PlayerPawn pm)
	{
		Vector3 gp, gf, gs, gu, op, of, os, ou;
		[gp, gf, gs, gu] = RL_VR.GunPose(pm);
		[op, of, os, ou] = RL_VR.OffhandPose(pm);
		rawGun = gp - pm.pos; rawOff = op - pm.pos; rawFwd = gf; rawUp = gu; rawFwdLen = gf.Length();
		// guard against non-unit direction vectors
		if (gf.Length() > 0.001) gf = gf.Unit();
		if (gs.Length() > 0.001) gs = gs.Unit();
		if (gu.Length() > 0.001) gu = gu.Unit();
		Vector3 rel = op - gp;
		lf = rel dot gf;
		ls = rel dot gs;
		lu = rel dot gu;

		Vector3 brel = op - pm.pos;
		bh = brel.z;
		bd = brel.xy.Length();
		eyeH = pm.player.viewz - pm.pos.z;

		Vector3 well  = (RL_CVarF('rl_well_f', -1), RL_CVarF('rl_well_s', 0), RL_CVarF('rl_well_u', -7));
		Vector3 slide = (RL_CVarF('rl_slide_f', -4), RL_CVarF('rl_slide_s', 0), RL_CVarF('rl_slide_u', 3));
		Vector3 here  = (lf, ls, lu);
		nearWell  = (here - well).Length()  < RL_CVarF('rl_well_r', 4);
		nearSlide = (here - slide).Length() < RL_CVarF('rl_slide_r', 4);
		nearGun   = nearWell || here.Length() < RL_CVarF('rl_support_r', 8);

		// Engine two-handed mode: the gun's forward axis lines up with the gun->off-hand
		// line (heights are squashed by the 1.2 pixel stretch in world units).
		Vector3 hl = (rel.x, rel.y, rel.z * 1.2);
		bool aligned = hl.Length() > 2 && (gf dot hl.Unit()) > cos(RL_CVarF('rl_steady_deg', 3));
		steadyTics = aligned ? min(steadyTics + 1, 10) : 0;
		steadied = steadyTics >= 2;
		inHip     = bh < eyeH * RL_CVarF('rl_hip_height', 0.65) && bd < RL_CVarF('rl_hip_r', 20);
	}

	static void SetF(Name n, double v)
	{
		CVar c = CVar.FindCVar(n);
		if (c) c.SetFloat(v);
	}

	void RL_Log(PlayerPawn pm, String tag)
	{
		Console.Printf("RLLOG %s t=%d hand=%d | rel gun f=%.1f s=%.1f u=%.1f | body h=%.1f d=%.1f | %s",
			tag, level.maptime, hand, lf, ls, lu, bh, bd, RL_VR.RawDump(pm));
	}

	void EjectMag(PlayerPawn pm)
	{
		int left = pm.CountInv("RL_PistolMag");
		if (left > 0)
		{
			pm.TakeInventory("RL_PistolMag", left);
			if (RL_CVarInt('rl_droppedmag_loses_rounds') == 0) pm.GiveInventory("Clip", left);
		}
		magSeated = false;
		pm.A_StartSound("rl/pistol/magout", CHAN_WEAPON);

		// drop a magazine you can see fall
		Vector3 gp, gf, gs, gu;
		[gp, gf, gs, gu] = RL_VR.GunPose(pm);
		Vector3 at = gp + gf * RL_CVarF('rl_well_f', -1) + gs * RL_CVarF('rl_well_s', 0) + gu * (RL_CVarF('rl_well_u', -7) + 1.5);
		let m = Actor.Spawn("RL_DroppedMag", at);
		if (m)
		{
			m.angle = pm.angle;
			m.vel = pm.vel + gu * -1.5;
		}
	}

	// A live round flies out of the ejection port (right side, top of the slide).
	void EjectRound(PlayerPawn pm) { EjectFromPort(pm, "RL_EjectedRound"); }
	void EjectCasing(PlayerPawn pm) { if (pm) EjectFromPort(pm, "RL_Casing"); }

	void EjectFromPort(PlayerPawn pm, class<Actor> what)
	{
		Vector3 gp, gf, gs, gu;
		if (RL_VR.Active(pm)) [gp, gf, gs, gu] = RL_VR.GunPose(pm);
		else
		{
			// flat screen: approximate the gun just below and in front of the eyes
			gf = (Actor.AngleToVector(pm.angle, cos(pm.pitch)), -sin(pm.pitch));
			gs = (Actor.AngleToVector(pm.angle + 90, 1), 0);
			gu = (0, 0, 1);
			gp = pm.pos + (0, 0, pm.player.viewheight - 10) + gf * 10;
		}
		Vector3 at = gp + gf * RL_CVarF('rl_port_f', 4) + gu * RL_CVarF('rl_port_u', 1.5) - gs * 1;
		let r = Actor.Spawn(what, at);
		if (r)
		{
			r.angle = pm.angle + frandom(-60, 60);
			r.vel = pm.vel - gs * frandom(2.5, 3.5) + gu * frandom(2.5, 3.5) + gf * frandom(-0.5, 0.5);
		}
	}

	void SeatMag(PlayerPawn pm)
	{
		pm.GiveInventory("RL_PistolMag", heldRounds);
		heldRounds = 0;
		magSeated = true;
		hand = HAND_SUPPORT;       // hand empties onto the gun; grip still held
		pm.A_StartSound("rl/pistol/magin", CHAN_WEAPON);
	}

	void StowHeldMag(PlayerPawn pm)
	{
		if (heldRounds > 0) pm.GiveInventory("Clip", heldRounds);
		heldRounds = 0;
	}

	// Slide runs forward: strips a round if the mag has one.  An empty
	// mag's follower catches the slide stop and the slide stays locked.
	void SlideForward(PlayerPawn pm)
	{
		pm.A_StartSound("rl/pistol/slide", CHAN_WEAPON);
		if (magSeated && pm.CountInv("RL_PistolMag") > 0)
		{
			slideLocked = false;
			if (pm.CountInv("RL_PistolChamber") == 0)
			{
				pm.TakeInventory("RL_PistolMag", 1);
				pm.GiveInventory("RL_PistolChamber", 1);
			}
		}
		else slideLocked = magSeated;    // empty mag in: locks; no mag: goes home empty
		slideShown = slideLocked ? 1 : 0;
	}

	// Keep a hand in the off-hand slot while playing in VR.
	void EnsureOffhand(PlayerPawn pm)
	{
		let cur = RL_VR.GetOffhand(pm);
		if (cur is "RL_OffHand") return;
		if (cur != null) return;                    // player chose a real off-hand weapon
		let h = Weapon(pm.FindInventory("RL_OffHand"));
		if (!h)
		{
			pm.GiveInventory("RL_OffHand", 1);
			h = Weapon(pm.FindInventory("RL_OffHand"));
		}
		if (h) RL_VR.SetOffhand(pm, h);
	}

	// ======================================================================
	//  BUTTON RELOAD (non-VR)  -  unchanged from v1
	// ======================================================================

	//   0 = nothing, 1 = tactical, 2 = empty (slide locked), 3 = slide release only
	action int RL_ReloadKind()
	{
		bool chambered = RL_Chambered();
		int mag = RL_MagCount();
		int reserve = CountInv("Clip");

		if (!chambered && mag > 0) return 3;
		if (reserve <= 0) return 0;
		if (chambered && mag >= MAGSIZE) return 0;
		return chambered ? 1 : 2;
	}

	action state RL_GotoReload()
	{
		if (RL_Physical()) return ResolveState("Ready");
		switch (RL_ReloadKind())
		{
			case 1: return ResolveState("Reload.Tactical");
			case 2: return ResolveState("Reload.Empty");
			case 3: return ResolveState("Reload.SlideOnly");
		}
		return ResolveState("Ready");
	}

	// Fire the chambered round, then cycle the next one in from the mag.
	action void RL_Shoot()
	{
		A_TakeInventory("RL_PistolChamber", 1);

		bool enhanced = RL_CVarInt('evw_weapons') == 1;
		class<Actor> puff = enhanced ? RL_FindActor('EnBulletPuff', "BulletPuff") : (class<Actor>)("BulletPuff");
		A_FireBullets(5.6, 0, 1, 5, puff, 0);   // flags 0 = don't touch the reserve
		invoker.EjectCasing(PlayerPawn(self));

		if (RL_MagCount() > 0)
		{
			A_TakeInventory("RL_PistolMag", 1);
			A_GiveInventory("RL_PistolChamber", 1);
		}
		else if (RL_Physical())
		{
			// last round: slide locks only if an (empty) mag is in the gun
			invoker.slideLocked = invoker.magSeated;
		}
	}

	action void RL_BarrelSmoke()
	{
		if (RL_CVarInt('evw_weapons') != 1) return;
		class<Actor> smoke = RL_FindActor('GunBarrelSmoke');
		if (smoke) A_FireProjectile(smoke, 0, false, 0, 0, FPF_NOAUTOAIM, 0);
	}

	action void RL_Tracer()
	{
		if (RL_CVarInt('evw_tracers') == 0) return;
		class<Actor> tracer = RL_FindActor('BulletTracer');
		if (tracer) A_FireProjectile(tracer, 0, false, 0, 0, FPF_NOAUTOAIM, 0);
	}

	action void RL_DropMag()
	{
		int left = RL_MagCount();
		if (left > 0)
		{
			A_TakeInventory("RL_PistolMag", left);
			if (RL_CVarInt('rl_droppedmag_loses_rounds') == 0)
				A_GiveInventory("Clip", left);
		}
	}

	action void RL_InsertMag()
	{
		int n = min(MAGSIZE, CountInv("Clip"));
		if (n > 0)
		{
			A_TakeInventory("Clip", n);
			A_GiveInventory("RL_PistolMag", n);
		}
	}

	action void RL_ChamberRound()
	{
		if (!RL_Chambered() && RL_MagCount() > 0)
		{
			A_TakeInventory("RL_PistolMag", 1);
			A_GiveInventory("RL_PistolChamber", 1);
		}
	}

	action bool RL_FastSwitch() { return RL_CVarInt('evw_fastswitch') != 0; }

	// In physical mode the model frame comes from the gun's real state
	// (mag in/out, slide position) instead of the animation.
	// slide < 0 means "use the live slide position".
	action void RL_PhysVisual(double slide = -1)
	{
		if (!RL_Physical() || !player) return;
		let psp = player.GetPSprite(PSP_WEAPON);
		if (!psp) return;
		if (slide < 0) slide = invoker.slideShown;
		State s;
		bool sup = invoker.hand == HAND_SUPPORT;
		bool sideB = RL_CVarInt('rl_support_side', 0) != 0;
		if (!sup)        s = invoker.magSeated ? invoker.FindState("Spr.MagIn")    : invoker.FindState("Spr.MagOut");
		else if (!sideB) s = invoker.magSeated ? invoker.FindState("Spr.MagInSupA") : invoker.FindState("Spr.MagOutSupA");
		else             s = invoker.magSeated ? invoker.FindState("Spr.MagInSupB") : invoker.FindState("Spr.MagOutSupB");
		psp.Sprite = s.sprite;
		psp.Frame = clamp(int(slide * 8 + 0.5), 0, 8);
	}

	// Physical mode: the gun can't fire with the slide out of battery.
	action bool RL_OutOfBattery() { return RL_Physical() && invoker.slideShown > 0.05; }

	// ---- states ----------------------------------------------------------
	//  RLPI = original model frames (A idle, B/C firing, F locked, G..X empty reload)
	//  RLPT = generated tactical reload frames
	//  RLSM / RLSN = physical mode, mag in / mag out, slide position A (home) .. I (locked)

	States
	{
	Spr.MagIn:
		RLSM A -1;
		Stop;
	Spr.MagOut:
		RLSN A -1;
		Stop;
	Spr.MagInSupA:
		RLSU A -1;
		Stop;
	Spr.MagOutSupA:
		RLSV A -1;
		Stop;
	Spr.MagInSupB:
		RLSW A -1;
		Stop;
	Spr.MagOutSupB:
		RLSX A -1;
		Stop;

	Ready:
		RLPI A 0 A_JumpIf(RL_Physical(), "Ready.Physical");
		RLPI A 0 A_JumpIf(!RL_Chambered(), "Ready.Locked");
	Ready.Loop:
		RLPI A 0 A_JumpIf(RL_Physical(), "Ready.Physical");   // re-checked every tic
		RLPI A 1 A_WeaponReady(WRF_ALLOWRELOAD);
		Loop;
	Ready.Locked:
		RLPI F 0 A_JumpIf(RL_Physical(), "Ready.Physical");
		RLPI F 1 A_WeaponReady(WRF_ALLOWRELOAD);
		Loop;
	Ready.Physical:
		RLSM A 1 { RL_PhysVisual(); A_WeaponReady(); }
		RLSM A 0 A_JumpIf(!RL_Physical(), "Ready");
		Loop;

	Deselect:
		RLPI A 0 A_JumpIf(!RL_Chambered(), "Deselect.Locked");
		RLPI A 0 A_JumpIf(RL_FastSwitch(), "Deselect.Fast");
		RLPI A 1 { RL_PhysVisual(); A_Lower(); }
		Wait;
	Deselect.Fast:
		RLPI A 1 { RL_PhysVisual(); A_Lower(60); }
		Wait;
	Deselect.Locked:
		RLPI F 0 A_JumpIf(RL_FastSwitch(), "Deselect.LockedFast");
		RLPI F 1 { RL_PhysVisual(); A_Lower(); }
		Wait;
	Deselect.LockedFast:
		RLPI F 1 { RL_PhysVisual(); A_Lower(60); }
		Wait;

	Select:
		RLPI A 0 A_JumpIf(!RL_Chambered(), "Select.Locked");
		RLPI A 0 A_JumpIf(RL_FastSwitch(), "Select.Fast");
		RLPI A 1 { RL_PhysVisual(); A_Raise(); }
		Wait;
	Select.Fast:
		RLPI A 1 { RL_PhysVisual(); A_Raise(60); }
		Wait;
	Select.Locked:
		RLPI F 0 A_JumpIf(RL_FastSwitch(), "Select.LockedFast");
		RLPI F 1 { RL_PhysVisual(); A_Raise(); }
		Wait;
	Select.LockedFast:
		RLPI F 1 { RL_PhysVisual(); A_Raise(60); }
		Wait;

	Fire:
		RLPI A 0 A_JumpIf(RL_OutOfBattery(), "Ready");
		RLPI A 0 A_JumpIf(!RL_Chambered(), "DryFire");
		RLPI A 4 RL_PhysVisual(0);
		RLPI B 0 A_JumpIf(RL_CVarInt('evw_weapons') == 1, "Fire.Enhanced");
		RLPI B 0 A_StartSound("weapons/pistol", CHAN_WEAPON);
		Goto Fire.Shot;
	Fire.Enhanced:
		RLPI B 0 A_StartSound("weapons/pistol/fire", CHAN_WEAPON);
	Fire.Shot:
		RLPI B 0 A_GunFlash;
		RLPI B 6 { RL_PhysVisual(0); RL_Shoot(); }
		RLPI B 0 A_JumpIf(!RL_Chambered(), "Fire.LastRound");
		RLPI C 4 RL_PhysVisual(1);
		RLPI B 5 { RL_PhysVisual(0); A_ReFire(); }
		RLPI A 0 RL_BarrelSmoke;
		Goto Ready;
	Fire.LastRound:            // slide locks back on the empty mag
		RLPI C 4 RL_PhysVisual(1);
		RLPI F 5 RL_PhysVisual();
		RLPI F 0 RL_BarrelSmoke;
		Goto Ready;

	DryFire:
		RLPI F 0 A_StartSound("rl/pistol/dry", CHAN_WEAPON);
		RLPI F 12 RL_PhysVisual();
		Goto Ready;

	Flash:
		PISF A 7 Bright { A_Light1(); RL_Tracer(); }
		Goto LightDone;

	Reload:
		TNT1 A 0 RL_GotoReload;
		Goto Ready;

	Reload.Tactical:
		RLPI A 0 A_StartSound("rl/pistol/magout", CHAN_WEAPON);
		RLPI A 4;
		RLPT A 0 RL_DropMag;
		RLPT A 6 A_StartSound("rl/pistol/magdrop", CHAN_AUTO, 0, 0.6);
		RLPT BCDEFG 2;
		RLPT H 2 A_StartSound("rl/pistol/magin", CHAN_WEAPON);
		RLPT IJ 2;
		RLPT K 2 RL_InsertMag;
		RLPT LMNOPQ 1;
		RLPT R 2;
		Goto Ready;

	Reload.Empty:
		RLPI F 0 A_StartSound("rl/pistol/magout", CHAN_WEAPON);
		RLPI F 4;
		RLPI G 0 RL_DropMag;
		RLPI G 6 A_StartSound("rl/pistol/magdrop", CHAN_AUTO, 0, 0.6);
		RLPI HIJKLM 2;
		RLPI N 2 A_StartSound("rl/pistol/magin", CHAN_WEAPON);
		RLPI OP 2;
		RLPI Q 3 RL_InsertMag;
	Reload.Release:
		RLPI R 2 A_StartSound("rl/pistol/slide", CHAN_WEAPON);
		RLPI S 2 RL_ChamberRound;
		RLPI TUVW 2;
		RLPI X 2;
		Goto Ready;

	Reload.SlideOnly:
		RLPI F 4;
		Goto Reload.Release;
	}
}

// ---------------------------------------------------------------------------
//  The off hand.  Lives in QuestZDoom's off-hand weapon slot; its pose follows
//  what the pistol's physical reload is doing.
// ---------------------------------------------------------------------------
class RL_OffHand : Weapon
{
	Default
	{
		Weapon.SelectionOrder 99999;
		Tag "Off hand";
		+WEAPON.CHEATNOTWEAPON
		+WEAPON.NOAUTOFIRE
		+WEAPON.WIMPY_WEAPON
		+WEAPON.AMMO_OPTIONAL
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
	}

	// pose: 0 open, 1 grip, 2 holding mag, 3 pinching slide (+4 per orientation)
	action void RL_HandPose()
	{
		if (!player) return;
		let pistol = RL_Pistol(FindInventory("RL_Pistol"));
		int f = 0;
		if (pistol && player.ReadyWeapon == pistol && pistol.physActive)
		{
			switch (pistol.hand)
			{
				case RL_Pistol.HAND_MAG:   f = 2; break;
				case RL_Pistol.HAND_SLIDE: f = 3; break;
				case RL_Pistol.HAND_GRIP:  f = 1; break;
				case RL_Pistol.HAND_SUPPORT: f = -1; break;   // drawn on the gun instead
			}
		}
		else if (player.cmd.buttons & BT_RELOAD) f = 1;
		let me = RL_VR.OffhandPSprite(PlayerPawn(self));
		if (!me) return;
		if (f < 0)
		{
			me.Sprite = invoker.FindState("Spr.Hidden").sprite;
			me.Frame = 0;
			return;
		}
		me.Sprite = invoker.FindState("Ready").sprite;
		me.Frame = f + 4 * clamp(RL_Pistol.RL_CVarInt('rl_hand_orient', 1), 0, 2);
	}

	States
	{
	Ready:
		RLHD A 1 RL_HandPose;
		Loop;
	Select:
		RLHD A 1 A_Raise(60);
		Wait;
	Deselect:
		RLHD A 1 A_Lower(60);
		Wait;
	Fire:
		RLHD A 1;
		Goto Ready;
	Spr.Hidden:
		TNT1 A -1;
		Stop;
	Spawn:
		TNT1 A -1;
		Stop;
	}
}

// A magazine dropped from the gun: falls, clatters, fades after a while.
class RL_DroppedMag : Actor
{
	Default
	{
		Radius 2;
		Height 3;
		Gravity 0.8;
		+NOBLOCKMAP
		+DROPOFF
		+NOTELEPORT
		+THRUACTORS
		+CANNOTPUSH
		+MOVEWITHSECTOR
	}

	int falling;

	States
	{
	Spawn:
		RLMG A 1
		{
			invoker.falling++;
			if (pos.z <= floorz || invoker.falling > 105) return ResolveState("Landed");
			return ResolveState(null);
		}
		Loop;
	Landed:
		RLMG B 350 A_StartSound("rl/pistol/magdrop", CHAN_BODY, 0, 0.6);
	Fade:
		RLMG B 1 A_FadeOut(0.05);
		Loop;
	}
}

// A live round ejected by racking the slide.
class RL_EjectedRound : Actor
{
	int falling;

	Default
	{
		Radius 1;
		Height 1;
		Gravity 0.8;
		+NOBLOCKMAP
		+DROPOFF
		+NOTELEPORT
		+THRUACTORS
		+CANNOTPUSH
		+MOVEWITHSECTOR
	}

	States
	{
	Spawn:
		RLRD A 1
		{
			invoker.falling++;
			angle += 25;                       // tumble
			if (pos.z <= floorz || invoker.falling > 105) return ResolveState("Landed");
			return ResolveState(null);
		}
		Loop;
	Landed:
		RLRD A 350 A_StartSound("weapons/casing", CHAN_BODY, 0, 0.5);
	Fade:
		RLRD A 1 A_FadeOut(0.05);
		Loop;
	}
}

// A spent case ejected on every shot.
class RL_Casing : RL_EjectedRound
{
	States
	{
	Spawn:
		RLCS A 1
		{
			invoker.falling++;
			angle += 31;
			if (pos.z <= floorz || invoker.falling > 105) return ResolveState("Landed");
			return ResolveState(null);
		}
		Loop;
	Landed:
		RLCS A 210 A_StartSound("weapons/casing", CHAN_BODY, 0, 0.4);
	Fade:
		RLCS A 1 A_FadeOut(0.05);
		Loop;
	}
}
