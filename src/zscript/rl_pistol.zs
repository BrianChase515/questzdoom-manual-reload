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

class RL_Pistol : RL_PhysWeapon
{
	const MAGSIZE = 15;

	bool   magSeated;
	bool   slideLocked;
	int    heldRounds;
	double grabF;          // off-hand forward position when the slide was grabbed
	bool   cycled;         // slide pulled far enough to cycle
	double slideShown;     // 0 = forward, 1 = locked back (drives the model)
	bool   nearWell, nearSlide;

	Default
	{
		Weapon.SelectionOrder 1900;
		Weapon.AmmoType1 "Clip";
		Weapon.AmmoUse1 0;          // rounds come out of the magazine, not the reserve
		Weapon.AmmoGive1 20;
		Weapon.AmmoType2 "RL_PistolMag";
		Weapon.AmmoUse2 0;
		Weapon.AmmoGive2 0;
		Weapon.SlotNumber 2;
		Obituary "$OB_MPPISTOL";
		Inventory.Pickupmessage "$PICKUP_PISTOL_DROPPED";
		Tag "$TAG_PISTOL";
		+WEAPON.WIMPY_WEAPON
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

	// ---- framework hooks ------------------------------------------------------

	override int CalZoneCount() { return 2; }
	override Name CalZone(int i) { return i == 0 ? 'rl_well' : 'rl_slide'; }
	override String CalPrompt(int i)
	{
		return i == 0
			? "CALIBRATING PISTOL 1/2: put your off hand where you'd SEAT A MAG (bottom of the grip) and squeeze"
			: "CALIBRATING PISTOL 2/2: now put your off hand on the BACK OF THE SLIDE and squeeze";
	}
	// A pistol's support hand sits beside/under the gun, so QuestZDoom's
	// "aim at the off hand" steadying always bends the aim sideways/down.
	override bool SteadyIsWrong() { return steadied; }

	override String StatusLine()
	{
		return String.Format("PISTOL  mag %s   slide %s   chamber %d   mag %d   slide pos %.2f",
			magSeated ? "IN" : "OUT", slideLocked ? "LOCKED" : "fwd",
			Owner.CountInv("RL_PistolChamber"), Owner.CountInv("RL_PistolMag"), slideShown);
	}
	override String ZoneLine()
	{
		return String.Format("zones: %s %s %s", inHip ? "[HIP]" : "hip",
			nearWell ? "[MAGWELL]" : "magwell", nearSlide ? "[SLIDE]" : "slide");
	}

	override void PhysOff(PlayerPawn pm) { slideShown = 0; }

	override void OnHolster(PlayerPawn pm)
	{
		if (hand == HAND_HELD) StowHeldMag(pm);
	}

	override void PhysTick(PlayerPawn pm, bool gripNow, bool gripWas, bool magRelease)
	{
		nearWell  = InZone('rl_well', -1, 0, -7, 4);
		nearSlide = InZone('rl_slide', -4, 0, 3, 4);
		nearGun   = nearGun || nearWell;

		// QuestZDoom two-handed hold: the grip (not the trigger) is holding the gun
		if (steadied && gripNow && hand != HAND_HELD) { hand = HAND_SUPPORT; cycled = false; }

		// ---- mag release (B) -------------------------------------------
		if (magRelease && magSeated) EjectMag(pm);

		// ---- grab -----------------------------------------------------------
		if (gripNow && !gripWas && hand == HAND_EMPTY)
		{
			if (nearSlide)
			{
				hand = HAND_ACTION;
				grabF = lf;
				cycled = false;
			}
			else if (nearGun) hand = HAND_SUPPORT;          // on the gun beats the hip pouch
			else if (inHip && pm.CountInv("Clip") > 0)
			{
				heldRounds = min(MAGSIZE, pm.CountInv("Clip"));
				pm.TakeInventory("Clip", heldRounds);
				hand = HAND_HELD;
				pm.A_StartSound("rl/pistol/pouch", CHAN_AUTO);
			}
			else hand = HAND_GRIP;
		}

		// ---- holding ------------------------------------------------------
		if (gripNow)
		{
			if (hand == HAND_HELD && nearWell && !magSeated) SeatMag(pm);

			if (hand == HAND_ACTION)
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
							Eject(pm, "RL_EjectedRound", RL_CVarF('rl_port_f', 4), RL_CVarF('rl_port_u', 1.5));
						}
						pm.A_StartSound("rl/pistol/slideback", CHAN_AUTO);
					}
				}
			}
		}
		// ---- let go ---------------------------------------------------------
		else if (gripWas)
		{
			if (hand == HAND_ACTION && cycled) SlideForward(pm);
			if (hand == HAND_HELD) StowHeldMag(pm);
			hand = HAND_EMPTY;
		}

		if (hand != HAND_ACTION) slideShown = slideLocked ? 1 : 0;
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
		let m = Actor.Spawn("RL_DroppedMag", GunPoint(RL_CVarF('rl_well_f', -1), RL_CVarF('rl_well_s', 0), RL_CVarF('rl_well_u', -7) + 1.5));
		if (m)
		{
			m.angle = pm.angle;
			m.vel = pm.vel + gu * -1.5;
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

	// ======================================================================
	//  BUTTON RELOAD (non-VR)
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
		invoker.Eject(PlayerPawn(self), "RL_Casing", RL_CVarF('rl_port_f', 4), RL_CVarF('rl_port_u', 1.5));

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

	action void RL_Tracer() { RL_Tracers(1); }

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

	// In physical mode the model frame comes from the gun's real state
	// (mag in/out, slide position, support hand) instead of the animation.
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
	
	Spawn:
		PIST A -1;
		Stop;
	}
}
