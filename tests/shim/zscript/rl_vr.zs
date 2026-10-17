// ===========================================================================
//  VR compatibility layer  -  DESKTOP TEST STAND-IN.
//  Fakes the two controllers so the physical-reload logic can be driven by
//  console variables from a test script:
//    rl_fake_vr 1                    enable
//    rl_fake_mode 0                  off-hand position given in GUN space   (f, s, u)
//    rl_fake_mode 1                  off-hand position given in BODY space  (f, s, height above feet)
//    rl_fake_f / rl_fake_s / rl_fake_u
//  The gun is held 14 units in front of the eyes, 8 below, pointing where you look.
// ===========================================================================

class RL_VR play
{
	static double F(Name n) { CVar c = CVar.FindCVar(n); return c ? c.GetFloat() : 0; }

	static bool Active(PlayerPawn p)
	{
		return p && p.player && F('rl_fake_vr') != 0;
	}

	static Vector3, Vector3, Vector3, Vector3 GunPose(PlayerPawn p)
	{
		Vector3 fwd  = (Actor.AngleToVector(p.angle, cos(p.pitch)), -sin(p.pitch));
		Vector3 side = (Actor.AngleToVector(p.angle + 90, 1), 0);
		Vector3 up   = (Actor.AngleToVector(p.angle, sin(p.pitch)), cos(p.pitch));
		Vector3 pos  = p.pos + (0, 0, p.player.viewheight - 8) + fwd * 14;
		if (F('rl_fake_anglefmt') != 0)
		{
			// mimic QuestZDoom 1.5.x: directions come back as (yaw, pitch, 0) and go through ToDir
			Vector3 fa = (p.angle, p.pitch, 0);
			Vector3 sa = (p.angle + 90, 0, 0);
			fwd = RL_Math.ToDir(fa);
			side = RL_Math.ToDir(sa);
			[fwd, side, up] = RL_Math.Frame(fwd, side);
		}
		return pos, fwd, side, up;
	}

	static Vector3, Vector3, Vector3, Vector3 OffhandPose(PlayerPawn p)
	{
		Vector3 gp, gf, gs, gu;
		[gp, gf, gs, gu] = GunPose(p);
		Vector3 pos;
		if (F('rl_fake_mode') == 0)
			pos = gp + gf * F('rl_fake_f') + gs * F('rl_fake_s') + gu * F('rl_fake_u');
		else
		{
			Vector3 bf = (Actor.AngleToVector(p.angle, 1), 0);
			Vector3 bs = (Actor.AngleToVector(p.angle + 90, 1), 0);
			pos = p.pos + bf * F('rl_fake_f') + bs * F('rl_fake_s') + (0, 0, F('rl_fake_u'));
		}
		return pos, gf, gs, gu;
	}

	static Weapon GetOffhand(PlayerPawn p)
	{
		return Weapon(p.FindInventory("RL_OffHand"));
	}

	// Desktop has no off-hand layer; the hand isn't drawn, logic still runs.
	static void SetOffhand(PlayerPawn p, Weapon w) {}

	static PSprite OffhandPSprite(PlayerPawn p) { return null; }

	static String RawDump(PlayerPawn p) { return "desktop shim"; }
}
