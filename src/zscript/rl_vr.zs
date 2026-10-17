// ===========================================================================
//  VR compatibility layer  -  REAL QuestZDoom version.
//  Everything that touches QuestZDoom-only engine features lives here, so the
//  rest of the mod also compiles on desktop LZDoom/GZDoom for testing
//  (tests/shim/rl_vr.zs is the desktop stand-in).
// ===========================================================================

class RL_VR play
{
	// True when hand tracking is driving the weapon (VR, not "purist" mode).
	static bool Active(PlayerPawn p)
	{
		return p && p.player && p.OverrideAttackPosDir;
	}

	// Controller pose: position + forward / side / up axes (world space, unit vectors).
	// AttackDir maps a yaw/pitch relative to the player into the controller's frame,
	// so offsets of +90 yaw / -90 pitch give the controller's side and up axes.
	static Vector3, Vector3, Vector3, Vector3 GunPose(PlayerPawn p)
	{
		Vector3 fwd  = p.AttackDir(p, p.angle, p.pitch);
		Vector3 side = p.AttackDir(p, p.angle + 90, p.pitch);
		Vector3 up   = p.AttackDir(p, p.angle, p.pitch - 90);
		return p.AttackPos, fwd, side, up;
	}

	static Vector3, Vector3, Vector3, Vector3 OffhandPose(PlayerPawn p)
	{
		Vector3 fwd  = p.OffhandDir(p, p.angle, p.pitch);
		Vector3 side = p.OffhandDir(p, p.angle + 90, p.pitch);
		Vector3 up   = p.OffhandDir(p, p.angle, p.pitch - 90);
		return p.OffhandPos, fwd, side, up;
	}

	static Weapon GetOffhand(PlayerPawn p)
	{
		return p.player.OffhandWeapon;
	}

	// Put a weapon in the off hand and start its ready animation.
	static void SetOffhand(PlayerPawn p, Weapon w)
	{
		w.bOffhandWeapon = true;
		w.bNoHandSwitch = true;
		p.player.OffhandWeapon = w;
		p.player.SetPsprite(PSP_OFFHANDWEAPON, w.GetReadyState());
	}

	static PSprite OffhandPSprite(PlayerPawn p)
	{
		return p.player.FindPSprite(PSP_OFFHANDWEAPON);
	}

	// Everything the engine reports, for calibration logs.
	static String RawDump(PlayerPawn p)
	{
		Vector3 af = p.AttackDir(p, p.angle, p.pitch);
		Vector3 of = p.OffhandDir(p, p.angle, p.pitch);
		Vector3 au = p.AttackDir(p, p.angle, p.pitch - 90);
		return String.Format(
			"player=(%.1f %.1f %.1f) ang=%.1f pitch=%.1f viewz=%.1f | AttackPos=(%.1f %.1f %.1f) AttackAng=%.1f Pitch=%.1f Roll=%.1f | OffhandPos=(%.1f %.1f %.1f) OffAng=%.1f Pitch=%.1f Roll=%.1f | AttackDir=(%.3f %.3f %.3f) len %.3f  AttackUp=(%.3f %.3f %.3f) | OffhandDir=(%.3f %.3f %.3f) len %.3f",
			p.pos.x, p.pos.y, p.pos.z, p.angle, p.pitch, p.player.viewz,
			p.AttackPos.x, p.AttackPos.y, p.AttackPos.z, p.AttackAngle, p.AttackPitch, p.AttackRoll,
			p.OffhandPos.x, p.OffhandPos.y, p.OffhandPos.z, p.OffhandAngle, p.OffhandPitch, p.OffhandRoll,
			af.x, af.y, af.z, af.Length(), au.x, au.y, au.z, of.x, of.y, of.z, of.Length());
	}
}
