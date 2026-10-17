// ===========================================================================
//  Manual Reload  -  Pump shotgun (Remington 870 style, 6 in the tube + 1)
//
//  PHYSICAL (VR):
//   * Grab the pump with your off hand (grip or trigger) and work it:
//     pulling it fully back ejects whatever is in the chamber (a fired hull, or a
//     live shell that goes back to your reserve); pushing it home chambers the
//     next shell from the tube.  With QuestZDoom's "Two Handed Weapons" on, the
//     grip on the pump also steadies your aim along the line between your hands.
//   * Load: off-hand trigger at your hip takes ONE shell; push it into the
//     loading port under the receiver.  Repeat.
//   * The gun only fires with a live shell chambered and the pump home.
//  BUTTON (flat screen): fire pumps automatically, Reload loads shells one at a
//  time until the tube is full (fire to stop early).
// ===========================================================================

class RL_ShotgunTube : Ammo
{
	Default
	{
		Inventory.MaxAmount 6;
		Ammo.BackpackMaxAmount 6;
		Ammo.BackpackAmount 0;
		Inventory.Icon "SHELA0";
		Tag "Shotgun tube";
		+INVENTORY.IGNORESKILL
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
	}
}

class RL_Shotgun : RL_PhysWeapon
{
	const TUBESIZE = 6;
	enum EChamber { CH_EMPTY, CH_LIVE, CH_SPENT };

	int    chamber;
	double pumpShown;      // 0 = home (forward), 1 = fully back
	double grabF;
	bool   opened;         // pump has been pulled back this stroke
	bool   nearPump, nearPort;

	Default
	{
		Weapon.SelectionOrder 1300;
		Weapon.AmmoType1 "Shell";
		Weapon.AmmoUse1 0;
		Weapon.AmmoGive1 8;
		Weapon.AmmoType2 "RL_ShotgunTube";
		Weapon.AmmoUse2 0;
		Weapon.AmmoGive2 0;
		Weapon.SlotNumber 3;
		Inventory.PickupMessage "$GOTSHOTGUN";
		Obituary "$OB_MPSHOTGUN";
		Tag "$TAG_SHOTGUN";
	}

	// Comes loaded from the shells it was picked up with: chamber first, then the tube.
	override void AttachToOwner(Actor other)
	{
		Super.AttachToOwner(other);
		if (!other) return;
		chamber = CH_EMPTY;
		if (other.CountInv("Shell") > 0) { other.TakeInventory("Shell", 1); chamber = CH_LIVE; }
		int load = min(TUBESIZE, other.CountInv("Shell"));
		if (load > 0) { other.TakeInventory("Shell", load); other.GiveInventory("RL_ShotgunTube", load); }
		pumpShown = 0;
	}

	action int RL_Tube() { return CountInv("RL_ShotgunTube"); }

	// ---- mechanism ------------------------------------------------------------

	// Pump fully back: whatever is in the chamber flies out of the port.
	void EjectChamber(PlayerPawn pm)
	{
		double f = RL_CVarF('rl_sg_eject_f', 7), u = RL_CVarF('rl_sg_eject_u', 2);
		if (chamber == CH_LIVE)
		{
			pm.GiveInventory("Shell", 1);              // a live shell is picked back up
			Eject(pm, "RL_LiveShell", f, u, 3);
		}
		else if (chamber == CH_SPENT) Eject(pm, "RL_Hull", f, u, 3.5);
		chamber = CH_EMPTY;
	}

	// Pump home: the next shell comes off the tube into the chamber.
	void Feed(PlayerPawn pm)
	{
		if (chamber == CH_EMPTY && pm.CountInv("RL_ShotgunTube") > 0)
		{
			pm.TakeInventory("RL_ShotgunTube", 1);
			chamber = CH_LIVE;
		}
	}

	// ---- framework hooks --------------------------------------------------------

	override int CalZoneCount() { return 2; }
	override Name CalZone(int i) { return i == 0 ? 'rl_sg_pump' : 'rl_sg_port'; }
	override String CalPrompt(int i)
	{
		return i == 0
			? "CALIBRATING SHOTGUN 1/2: put your off hand ON THE PUMP (pump pushed forward) and squeeze"
			: "CALIBRATING SHOTGUN 2/2: now put your off hand at the LOADING PORT (under the receiver) and squeeze";
	}
	override String StatusLine()
	{
		static const String ch[] = { "empty", "LIVE", "spent" };
		return String.Format("SHOTGUN  chamber %s   tube %d   pump %.2f", ch[clamp(chamber, 0, 2)], Owner.CountInv("RL_ShotgunTube"), pumpShown);
	}
	override String ZoneLine()
	{
		return String.Format("zones: %s %s %s", inHip ? "[HIP]" : "hip",
			nearPump ? "[PUMP]" : "pump", nearPort ? "[LOADING PORT]" : "loading port");
	}

	override int OffhandPose()
	{
		switch (hand)
		{
			case HAND_HELD:   return POSE_SHELL;
			case HAND_ACTION: return POSE_HIDDEN;      // drawn on the pump
			case HAND_GRIP:   return POSE_GRIP;
		}
		return POSE_OPEN;
	}

	override void OnHolster(PlayerPawn pm)
	{
		if (hand == HAND_HELD) pm.GiveInventory("Shell", 1);
	}

	override void PhysTick(PlayerPawn pm, bool gripNow, bool gripWas, bool release)
	{
		nearPump = InZone('rl_sg_pump', 14, 0, -1, 8);
		nearPort = InZone('rl_sg_port', 4, 0, -4, 5);
		double len = RL_CVarF('rl_sg_pump_len', 3);

		// QuestZDoom two-handed hold: the grip is on the pump
		if (steadied && gripNow && hand != HAND_HELD && hand != HAND_ACTION)
		{
			hand = HAND_ACTION;
			grabF = lf + pumpShown * len;
		}

		// ---- grab -----------------------------------------------------------
		if (gripNow && !gripWas && hand == HAND_EMPTY)
		{
			if (nearPump)
			{
				hand = HAND_ACTION;
				grabF = lf + pumpShown * len;      // where "pump home" is for this hand
			}
			else if (inHip && !nearGun && pm.CountInv("Shell") > 0)
			{
				pm.TakeInventory("Shell", 1);
				hand = HAND_HELD;
				pm.A_StartSound("rl/pistol/pouch", CHAN_AUTO, 0, 0.7);
			}
			else hand = HAND_GRIP;
		}

		// ---- holding ------------------------------------------------------
		if (gripNow)
		{
			if (hand == HAND_HELD && nearPort && pm.CountInv("RL_ShotgunTube") < TUBESIZE)
			{
				pm.GiveInventory("RL_ShotgunTube", 1);
				pm.A_StartSound("weapons/shotgun/in", CHAN_WEAPON);
				hand = HAND_GRIP;                    // shell's in; go back for another
			}

			if (hand == HAND_ACTION)
			{
				double pull = clamp((grabF - lf) / len, 0, 1);
				pumpShown = pull;
				if (pull >= 0.85 && !opened)
				{
					opened = true;
					EjectChamber(pm);
					pm.A_StartSound("rl/shotgun/pumpback", CHAN_WEAPON);
				}
				else if (pull <= 0.15 && opened)
				{
					opened = false;
					Feed(pm);
					pm.A_StartSound("rl/shotgun/pumpfwd", CHAN_WEAPON);
				}
			}
		}
		// ---- let go: the pump stays wherever you left it --------------------
		else if (gripWas)
		{
			if (hand == HAND_HELD) pm.GiveInventory("Shell", 1);   // shell back in the pouch
			hand = HAND_EMPTY;
		}
	}

	override void PhysOff(PlayerPawn pm) { if (!opened) pumpShown = 0; }

	// ---- firing -------------------------------------------------------------------

	action bool RL_CanFire()
	{
		if (invoker.chamber != CH_LIVE) return false;
		if (RL_Physical() && invoker.pumpShown > 0.1) return false;   // action open
		return true;
	}

	action void RL_SGShoot()
	{
		bool enhanced = RL_CVarInt('evw_weapons') == 1;
		class<Actor> puff = enhanced ? RL_FindActor('EnShotPuff', "BulletPuff") : (class<Actor>)("BulletPuff");
		A_FireBullets(5.6, 0, 7, 5, puff, 0);
		A_StartSound(enhanced ? "weapons/shotgun/fire" : "weapons/shotgf", CHAN_WEAPON);
		invoker.chamber = CH_SPENT;
		RL_BarrelSmoke('ShotgunBarrelSmoke');
	}

	// button mode: the automatic pump stroke
	action void RL_AutoEject() { invoker.EjectChamber(PlayerPawn(self)); }
	action void RL_AutoFeed()  { invoker.Feed(PlayerPawn(self)); }

	// button mode: one shell into the tube
	action void RL_LoadOne()
	{
		if (CountInv("Shell") > 0 && RL_Tube() < TUBESIZE)
		{
			A_TakeInventory("Shell", 1);
			A_GiveInventory("RL_ShotgunTube", 1);
			A_StartSound("weapons/shotgun/in", CHAN_WEAPON);
		}
	}

	action state RL_LoadMore()
	{
		if ((player.cmd.buttons & BT_ATTACK) || CountInv("Shell") <= 0 || RL_Tube() >= TUBESIZE)
			return invoker.chamber == CH_LIVE ? ResolveState("Ready") : ResolveState("Pump");
		return ResolveState("Reload.Loop");
	}

	action state RL_GotoReload()
	{
		if (RL_Physical() || CountInv("Shell") <= 0 || RL_Tube() >= TUBESIZE) return ResolveState("Ready");
		return ResolveState("Reload.Start");
	}

	// Physical mode model: pump position, shell in the chamber, hand on the pump.
	action void RL_SGVisual()
	{
		if (!RL_Physical() || !player) return;
		let psp = player.GetPSprite(PSP_WEAPON);
		if (!psp) return;
		bool shell = invoker.chamber != CH_EMPTY;
		bool onPump = invoker.hand == HAND_ACTION;
		bool sideB = RL_CVarInt('rl_support_side', 0) != 0;
		State s;
		if (!onPump)     s = shell ? invoker.FindState("Spr.Shell")      : invoker.FindState("Spr.Empty");
		else if (!sideB) s = shell ? invoker.FindState("Spr.ShellHandA") : invoker.FindState("Spr.EmptyHandA");
		else             s = shell ? invoker.FindState("Spr.ShellHandB") : invoker.FindState("Spr.EmptyHandB");
		psp.Sprite = s.sprite;
		psp.Frame = clamp(int(invoker.pumpShown * 8 + 0.5), 0, 8);
	}

	//  RSGO = original model frames: A idle, B fire, C/D pump back, E idle (level)
	//  RSGL = shell-loading animation (button mode)
	//  RSGA/RSGB = physical: shell / no shell, pump step A (home) .. I (back)
	//  RSGC..RSGF = the same with the off hand on the pump (versions A / B)
	States
	{
	Spr.Shell:      RSGA A -1; Stop;
	Spr.Empty:      RSGB A -1; Stop;
	Spr.ShellHandA: RSGC A -1; Stop;
	Spr.EmptyHandA: RSGD A -1; Stop;
	Spr.ShellHandB: RSGE A -1; Stop;
	Spr.EmptyHandB: RSGF A -1; Stop;

	Ready:
		RSGO A 0 A_JumpIf(RL_Physical(), "Ready.Physical");
		RSGO A 1 A_WeaponReady(WRF_ALLOWRELOAD);
		Loop;
	Ready.Physical:
		RSGA A 1 { RL_SGVisual(); A_WeaponReady(); }
		RSGA A 0 A_JumpIf(!RL_Physical(), "Ready");
		Loop;

	Deselect:
		RSGO A 0 A_JumpIf(RL_FastSwitch(), "Deselect.Fast");
		RSGO A 1 { RL_SGVisual(); A_Lower(); }
		Wait;
	Deselect.Fast:
		RSGO A 1 { RL_SGVisual(); A_Lower(60); }
		Wait;
	Select:
		RSGO A 0 A_JumpIf(RL_FastSwitch(), "Select.Fast");
		RSGO A 1 { RL_SGVisual(); A_Raise(); }
		Wait;
	Select.Fast:
		RSGO A 1 { RL_SGVisual(); A_Raise(60); }
		Wait;

	Fire:
		RSGO A 0 A_JumpIf(!RL_CanFire(), "NotReady");
		RSGO A 3 RL_SGVisual;
		RSGO A 0 A_GunFlash;
		RSGO A 7 { RL_SGShoot(); RL_SGVisual(); }
		RSGO A 0 A_JumpIf(RL_Physical(), "Fire.Physical");
	Pump:                                    // button mode: automatic pump stroke
		RSGO BC 5;
		RSGO D 4 RL_AutoEject;
		RSGO C 5 A_StartSound("weapons/shotgun/pump", CHAN_AUTO);
		RSGO B 5 RL_AutoFeed;
		RSGO A 3;
		RSGO A 7 A_ReFire;
		Goto Ready;
	Fire.Physical:                           // you work the pump yourself
		RSGA A 6 RL_SGVisual;
		Goto Ready;

	NotReady:
		RSGO A 0 A_JumpIf(RL_Physical(), "DryFire");
		RSGO A 0 A_JumpIf(RL_Tube() > 0 || invoker.chamber == CH_SPENT, "Pump");
	DryFire:
		RSGO A 0 A_StartSound("rl/pistol/dry", CHAN_WEAPON);
		RSGO A 12 RL_SGVisual;
		Goto Ready;

	Flash:
		SHTF A 4 Bright { A_Light1(); RL_Tracers(6, 3); }
		SHTF B 3 Bright A_Light2;
		Goto LightDone;

	Reload:
		TNT1 A 0 RL_GotoReload;
		Goto Ready;
	Reload.Start:
		RSGO E 4;
	Reload.Loop:
		RSGL ABCDE 2;
		RSGL F 2 RL_LoadOne;
		RSGL GHIJ 2;
		RSGL J 0 RL_LoadMore;
		Goto Ready;

	Spawn:
		SHOT A -1;
		Stop;
	}
}
