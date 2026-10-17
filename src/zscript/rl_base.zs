// ===========================================================================
//  Shared physical-weapon framework.
//
//  RL_PhysWeapon does everything that isn't specific to one gun:
//    * reads both controllers every tic (RL_VR) and works out where the off hand
//      is relative to the gun and to your body (hip pouch)
//    * keeps the visible off hand (RL_OffHand) in QuestZDoom's off-hand slot
//    * detects QuestZDoom's own two-handed steadying
//    * runs the grab-zone calibration wizard and the calibration log
//    * ejects brass / shells / magazines with a bit of physics
//  Each weapon overrides PhysTick() with its own mechanism.
//
//  Off hand: the GRIP button and the TRIGGER both send +reload (BT_RELOAD).
//  With QuestZDoom's "Two Handed Weapons" on, only the grip makes QuestZDoom
//  steady the gun, which is how the two are told apart (see `steadied`).
// ===========================================================================

class RL_PhysWeapon : DoomWeapon
{
	enum EHand
	{
		HAND_EMPTY,
		HAND_HELD,      // holding something (magazine, shell)
		HAND_ACTION,    // working the action (slide, pump)
		HAND_GRIP,      // squeezing nothing in particular
		HAND_SUPPORT    // holding the gun two-handed
	};

	enum EPose          // what the visible off hand looks like
	{
		POSE_HIDDEN = -1,   // drawn on the gun instead
		POSE_OPEN = 0,
		POSE_GRIP = 1,
		POSE_MAG = 2,
		POSE_PINCH = 3,
		POSE_SHELL = 4
	};

	bool   physActive;
	int    hand;
	int    prevButtons;
	// this tic's poses
	Vector3 gp, gf, gs, gu, op;
	// off hand relative to the gun (forward, side, up) and to the body
	double lf, ls, lu, bh, bd, eyeH;
	bool   inHip, nearGun, steadied;
	int    steadyTics;
	int    calStep;
	Vector3 rawGun, rawOff, rawFwd, rawUp;
	double rawFwdLen;

	Default
	{
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

	static void SetF(Name n, double v)
	{
		CVar c = CVar.FindCVar(n);
		if (c) c.SetFloat(v);
	}

	// Run-time class lookup, so the mod still loads without the HDVR pack's effects.
	static class<Actor> RL_FindActor(Name n, class<Actor> fallback = null)
	{
		class<Actor> c = n;
		return c ? c : fallback;
	}

	static Name ZoneVar(Name prefix, String suffix)
	{
		String s = String.Format("%s_%s", prefix, suffix);
		Name n = s;
		return n;
	}

	// Is the off hand inside the grab zone stored in cvars <prefix>_f/_s/_u/_r?
	bool InZone(Name prefix, double df, double ds, double du, double dr)
	{
		Vector3 c = (RL_CVarF(ZoneVar(prefix, "f"), df), RL_CVarF(ZoneVar(prefix, "s"), ds), RL_CVarF(ZoneVar(prefix, "u"), du));
		return ((lf, ls, lu) - c).Length() < RL_CVarF(ZoneVar(prefix, "r"), dr);
	}

	// A point on the gun, in gun space (forward, side, up), as a world position.
	Vector3 GunPoint(double f, double s, double u)
	{
		return gp + gf * f + gs * s + gu * u;
	}

	// ---- hooks for each weapon ---------------------------------------------

	virtual void PhysTick(PlayerPawn pm, bool gripNow, bool gripWas, bool releasePressed) {}
	virtual void PhysOff(PlayerPawn pm) {}                 // physical mode not active
	virtual void OnHolster(PlayerPawn pm) {}               // gun put away
	virtual int  CalZoneCount() { return 0; }
	virtual Name CalZone(int i) { return 'none'; }
	virtual clearscope String CalPrompt(int i) { return ""; }
	// True when QuestZDoom's two-handed steadying is pointing this gun somewhere
	// the player can't mean (e.g. at the off hand down at the hip).
	virtual clearscope bool SteadyIsWrong() { return steadied && inHip; }
	virtual clearscope String StatusLine() { return ""; }
	virtual clearscope String ZoneLine() { return ""; }

	virtual int OffhandPose()
	{
		switch (hand)
		{
			case HAND_HELD:    return POSE_MAG;
			case HAND_ACTION:  return POSE_PINCH;
			case HAND_GRIP:    return POSE_GRIP;
			case HAND_SUPPORT: return POSE_HIDDEN;
		}
		return POSE_OPEN;
	}

	// ---- every tic -----------------------------------------------------------

	override void DoEffect()
	{
		Super.DoEffect();
		let pm = PlayerPawn(Owner);
		if (!pm || !pm.player || pm.player.mo != pm) return;

		physActive = RL_VR.Active(pm) && RL_CVarInt('rl_physical', 1) != 0;
		if (!physActive) { hand = HAND_EMPTY; PhysOff(pm); return; }

		EnsureOffhand(pm);

		int buttons = pm.player.cmd.buttons;
		bool gripNow = (buttons & BT_RELOAD) != 0;
		bool gripWas = (prevButtons & BT_RELOAD) != 0;
		bool release = (buttons & BT_JUMP) && !(prevButtons & BT_JUMP);
		prevButtons = buttons;

		if (pm.player.ReadyWeapon != self)
		{
			OnHolster(pm);
			hand = HAND_EMPTY;
			return;
		}

		Measure(pm);

		// ---- grab-zone calibration wizard ---------------------------------
		CVar req = CVar.FindCVar('rl_calib_request');
		if (req && req.GetInt() != 0 && CalZoneCount() > 0) { req.SetInt(0); calStep = 1; hand = HAND_EMPTY; }
		if (calStep > 0)
		{
			if (gripNow && !gripWas)
			{
				Name z = CalZone(calStep - 1);
				SetF(ZoneVar(z, "f"), lf); SetF(ZoneVar(z, "s"), ls); SetF(ZoneVar(z, "u"), lu);
				pm.A_StartSound("rl/pistol/magin", CHAN_AUTO);
				if (RL_CVarInt('rl_log') != 0) RL_Log(pm, "CALIBRATE");
				calStep++;
				if (calStep > CalZoneCount()) calStep = 0;
			}
			return;                       // no gun actions while calibrating
		}

		if (RL_CVarInt('rl_log') != 0)
		{
			if (gripNow && !gripWas) RL_Log(pm, "GRIP");
			if (release) RL_Log(pm, "RELEASE");
			if (level.maptime % 70 == 0) RL_Log(pm, "TICK");
		}

		PhysTick(pm, gripNow, gripWas, release);
	}

	void Measure(PlayerPawn pm)
	{
		Vector3 of, os, ou;
		[gp, gf, gs, gu] = RL_VR.GunPose(pm);
		[op, of, os, ou] = RL_VR.OffhandPose(pm);
		rawGun = gp - pm.pos; rawOff = op - pm.pos; rawFwd = gf; rawUp = gu; rawFwdLen = gf.Length();
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
		inHip = bh < eyeH * RL_CVarF('rl_hip_height', 0.78) && bd < RL_CVarF('rl_hip_r', 20);
		nearGun = rel.Length() < RL_CVarF('rl_support_r', 8);

		// QuestZDoom's two-handed mode aims the gun along the gun->off-hand line
		// (heights in world units are squashed by the 1.2 pixel stretch).
		Vector3 hl = (rel.x, rel.y, rel.z * 1.2);
		bool aligned = hl.Length() > 2 && (gf dot hl.Unit()) > cos(RL_CVarF('rl_steady_deg', 3));
		steadyTics = aligned ? min(steadyTics + 1, 10) : 0;
		steadied = steadyTics >= 2;
	}

	void RL_Log(PlayerPawn pm, String tag)
	{
		Console.Printf("RLLOG %s %s t=%d hand=%d | rel gun f=%.1f s=%.1f u=%.1f | body h=%.1f d=%.1f | %s",
			tag, GetClassName(), level.maptime, hand, lf, ls, lu, bh, bd, RL_VR.RawDump(pm));
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

	// Throw something out of the gun: from a point in gun space, mostly to the right
	// and up.  Works on a flat screen too (approximate gun pose).
	Actor Eject(PlayerPawn pm, class<Actor> what, double f, double u, double speed = 3)
	{
		if (!pm) return null;
		if (!RL_VR.Active(pm))
		{
			gf = (Actor.AngleToVector(pm.angle, cos(pm.pitch)), -sin(pm.pitch));
			gs = (Actor.AngleToVector(pm.angle + 90, 1), 0);
			gu = (0, 0, 1);
			gp = pm.pos + (0, 0, pm.player.viewheight - 10) + gf * 10;
		}
		else if (gf.Length() < 0.5) [gp, gf, gs, gu] = RL_VR.GunPose(pm);
		let r = Actor.Spawn(what, GunPoint(f, -1, u));
		if (r)
		{
			r.angle = pm.angle + frandom(-60, 60);
			r.vel = pm.vel - gs * frandom(0.8, 1.2) * speed + gu * frandom(0.8, 1.2) * speed + gf * frandom(-0.5, 0.5);
		}
		return r;
	}

	action bool RL_Physical() { return invoker.physActive; }
	action bool RL_FastSwitch() { return RL_CVarInt('evw_fastswitch') != 0; }

	action void RL_BarrelSmoke(Name cls = 'GunBarrelSmoke')
	{
		if (RL_CVarInt('evw_weapons') != 1) return;
		class<Actor> smoke = RL_FindActor(cls);
		if (smoke) A_FireProjectile(smoke, 0, false, 0, 0, FPF_NOAUTOAIM, 0);
	}

	action void RL_Tracers(int n = 1, double spread = 0)
	{
		if (RL_CVarInt('evw_tracers') == 0) return;
		class<Actor> tracer = RL_FindActor('BulletTracer');
		if (!tracer) return;
		for (int i = 0; i < n; i++)
			A_FireProjectile(tracer, frandom(-spread, spread), false, 0, 0, FPF_NOAUTOAIM, frandom(-spread, spread) / 3);
	}
}

// ---------------------------------------------------------------------------
//  The off hand.  Lives in QuestZDoom's off-hand weapon slot; its pose comes
//  from the physical weapon in your main hand.
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

	// frame letter = pose + 4 * orientation; the shell pose uses letters M..O
	action void RL_HandPose()
	{
		if (!player) return;
		int pose = RL_PhysWeapon.POSE_OPEN;
		let pw = RL_PhysWeapon(player.ReadyWeapon);
		if (pw && pw.physActive) pose = pw.OffhandPose();
		else if (player.cmd.buttons & BT_RELOAD) pose = RL_PhysWeapon.POSE_GRIP;

		let me = RL_VR.OffhandPSprite(PlayerPawn(self));
		if (!me) return;
		if (pose < 0)
		{
			me.Sprite = invoker.FindState("Spr.Hidden").sprite;
			me.Frame = 0;
			return;
		}
		int orient = clamp(RL_PhysWeapon.RL_CVarInt('rl_hand_orient', 1), 0, 2);
		me.Sprite = invoker.FindState("Ready").sprite;
		me.Frame = pose == RL_PhysWeapon.POSE_SHELL ? 12 + orient : pose + 4 * orient;
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

// ---------------------------------------------------------------------------
//  Things that fall out of guns: fall, land with a sound, lie there, fade.
// ---------------------------------------------------------------------------
class RL_Ejecta : Actor
{
	int falling;
	Sound landSound;
	int lieTics;
	double spin;

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

	virtual void Setup() { landSound = "weapons/casing"; lieTics = 350; spin = 25; }

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		Setup();
	}

	States
	{
	Spawn:
		#### A 1
		{
			invoker.falling++;
			angle += invoker.spin;
			if (pos.z <= floorz || invoker.falling > 105)
			{
				A_StartSound(invoker.landSound, CHAN_BODY, 0, 0.5);
				return ResolveState("Landed");
			}
			return ResolveState(null);
		}
		Loop;
	Landed:
		#### B 1 { if (--invoker.lieTics <= 0) return ResolveState("Fade"); return ResolveState(null); }
		Loop;
	Fade:
		#### B 1 A_FadeOut(0.05);
		Loop;
	}
}

// A magazine dropped from the pistol: falls upright, lies flat once it lands.
class RL_DroppedMag : RL_Ejecta
{
	override void Setup() { landSound = "rl/pistol/magdrop"; lieTics = 350; spin = 0; }
	States { Spawn: RLMG A 0; Goto Super::Spawn; }
}

// A live round ejected by racking the slide.
class RL_EjectedRound : RL_Ejecta
{
	States { Spawn: RLRD A 0; Goto Super::Spawn; }
}

// A spent case ejected on every pistol shot.
class RL_Casing : RL_Ejecta
{
	override void Setup() { landSound = "weapons/casing"; lieTics = 210; spin = 31; }
	States { Spawn: RLCS A 0; Goto Super::Spawn; }
}

// Shotgun: a fired hull, and a live shell ejected by pumping a loaded gun.
class RL_Hull : RL_Ejecta
{
	override void Setup() { landSound = "weapons/shotgunshells"; lieTics = 280; spin = 20; }
	States { Spawn: RLHL A 0; Goto Super::Spawn; }
}

class RL_LiveShell : RL_Ejecta
{
	override void Setup() { landSound = "weapons/shotgunshells"; lieTics = 350; spin = 18; }
	States { Spawn: RLLS A 0; Goto Super::Spawn; }
}
