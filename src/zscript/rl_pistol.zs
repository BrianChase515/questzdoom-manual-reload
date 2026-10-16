// ===========================================================================
//  Manual Reload for VR 3D weapons  -  Pistol (Beretta 92FS style, 15+1)
//
//  * Magazine (15) + chambered round (1) are tracked separately.
//  * Reserve ammo is the normal Doom "Clip" pool, so pickups, backpacks,
//    the chaingun and cheats all keep working as usual.
//  * Firing the last round locks the slide back.
//  * Reload with a round chambered  = tactical: drop mag, insert mag (15+1).
//  * Reload from slide-lock         = drop mag, insert mag, release slide (15).
//  * Uses the HDVR 3D pistol model; the reload animation frames live in
//    Models/Weapons/Hud/Pistol/RL_Pistol.md3 (see MODELDEF.RLReload).
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
	}

	action bool RL_Chambered() { return CountInv("RL_PistolChamber") > 0; }
	action int  RL_MagCount()  { return CountInv("RL_PistolMag"); }

	// What should the reload button do right now?
	//   0 = nothing, 1 = tactical (round chambered), 2 = empty (slide locked),
	//   3 = slide release only (chamber empty but mag has rounds)
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

		if (RL_MagCount() > 0)
		{
			A_TakeInventory("RL_PistolMag", 1);
			A_GiveInventory("RL_PistolChamber", 1);
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

	// Mag comes out.  Its rounds go back to the reserve unless the
	// "rl_droppedmag_loses_rounds" option is on.
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

	// Fresh mag goes in, filled from the reserve.
	action void RL_InsertMag()
	{
		int n = min(MAGSIZE, CountInv("Clip"));
		if (n > 0)
		{
			A_TakeInventory("Clip", n);
			A_GiveInventory("RL_PistolMag", n);
		}
	}

	// Slide goes forward, stripping a round off the top of the mag.
	action void RL_ChamberRound()
	{
		if (!RL_Chambered() && RL_MagCount() > 0)
		{
			A_TakeInventory("RL_PistolMag", 1);
			A_GiveInventory("RL_PistolChamber", 1);
		}
	}

	action bool RL_FastSwitch() { return RL_CVarInt('evw_fastswitch') != 0; }

	// ---- states ----------------------------------------------------------
	//  RLPI = frames of the original model (A idle, B/C firing, F slide locked,
	//         G..X the empty reload).  RLPT = generated tactical reload frames.

	States
	{
	Ready:
		RLPI A 0 A_JumpIf(!RL_Chambered(), "Ready.Locked");
	Ready.Loop:
		RLPI A 1 A_WeaponReady(WRF_ALLOWRELOAD);
		Loop;
	Ready.Locked:
		RLPI F 1 A_WeaponReady(WRF_ALLOWRELOAD);
		Loop;

	Deselect:
		RLPI A 0 A_JumpIf(!RL_Chambered(), "Deselect.Locked");
		RLPI A 0 A_JumpIf(RL_FastSwitch(), "Deselect.Fast");
		RLPI A 1 A_Lower;
		Wait;
	Deselect.Fast:
		RLPI A 1 A_Lower(60);
		Wait;
	Deselect.Locked:
		RLPI F 0 A_JumpIf(RL_FastSwitch(), "Deselect.LockedFast");
		RLPI F 1 A_Lower;
		Wait;
	Deselect.LockedFast:
		RLPI F 1 A_Lower(60);
		Wait;

	Select:
		RLPI A 0 A_JumpIf(!RL_Chambered(), "Select.Locked");
		RLPI A 0 A_JumpIf(RL_FastSwitch(), "Select.Fast");
		RLPI A 1 A_Raise;
		Wait;
	Select.Fast:
		RLPI A 1 A_Raise(60);
		Wait;
	Select.Locked:
		RLPI F 0 A_JumpIf(RL_FastSwitch(), "Select.LockedFast");
		RLPI F 1 A_Raise;
		Wait;
	Select.LockedFast:
		RLPI F 1 A_Raise(60);
		Wait;

	Fire:
		RLPI A 0 A_JumpIf(!RL_Chambered(), "DryFire");
		RLPI A 4;
		RLPI B 0 A_JumpIf(RL_CVarInt('evw_weapons') == 1, "Fire.Enhanced");
		RLPI B 0 A_StartSound("weapons/pistol", CHAN_WEAPON);
		Goto Fire.Shot;
	Fire.Enhanced:
		RLPI B 0 A_StartSound("weapons/pistol/fire", CHAN_WEAPON);
	Fire.Shot:
		RLPI B 0 A_GunFlash;
		RLPI B 6 RL_Shoot;
		RLPI B 0 A_JumpIf(!RL_Chambered(), "Fire.LastRound");
		RLPI C 4;
		RLPI B 5 A_ReFire;
		RLPI A 0 RL_BarrelSmoke;
		Goto Ready;
	Fire.LastRound:            // slide locks back on the empty mag
		RLPI C 4;
		RLPI F 5;
		RLPI F 0 RL_BarrelSmoke;
		Goto Ready;

	DryFire:
		RLPI F 0 A_StartSound("rl/pistol/dry", CHAN_WEAPON);
		RLPI F 12;
		Goto Ready;

	Flash:
		PISF A 7 Bright { A_Light1(); RL_Tracer(); }
		Goto LightDone;

	Reload:
		TNT1 A 0 RL_GotoReload;
		Goto Ready;

	// ----- round chambered: drop mag, insert mag (slide stays forward) -----
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

	// ----- slide locked: drop mag, insert mag, release slide -----
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

	// ----- chamber empty but mag loaded (e.g. after a cheat): just release slide -----
	Reload.SlideOnly:
		RLPI F 4;
		Goto Reload.Release;
	}
}
