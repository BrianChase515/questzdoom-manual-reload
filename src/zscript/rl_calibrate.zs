// Calibration prompts (always) and the calibration readout
// (Options -> Manual Reload -> "Show calibration readout") for whichever
// physical weapon is in your hand.
class RL_Calibrate : EventHandler
{
	override void RenderOverlay(RenderEvent e)
	{
		let pm = players[consoleplayer].mo;
		if (!pm) return;
		let p = RL_PhysWeapon(players[consoleplayer].ReadyWeapon);
		if (!p) return;

		if (p.calStep > 0)
			Screen.DrawText(SmallFont, Font.CR_YELLOW, 10, 40, p.CalPrompt(p.calStep - 1),
				DTA_VirtualWidth, 480, DTA_VirtualHeight, 300, DTA_KeepRatio, true);

		CVar cv = CVar.FindCVar('rl_calibrate');
		if (!cv || !cv.GetBool()) return;

		static const String handNames[] = { "empty", "HOLDING", "ON ACTION", "grip", "ON GUN" };
		Array<String> lines;
		lines.Push(String.Format("physical %s   hand: %s   two-handed steady (QuestZDoom): %s",
			p.physActive ? "ON" : "off", handNames[clamp(p.hand, 0, 4)], p.steadied ? "YES" : "no"));
		lines.Push(p.StatusLine());
		lines.Push(String.Format("hand vs gun:  fwd %.1f  side %.1f  up %.1f", p.lf, p.ls, p.lu));
		lines.Push(String.Format("hand vs body: height %.1f (eye %.1f)  dist %.1f", p.bh, p.eyeH, p.bd));
		lines.Push(p.ZoneLine());
		lines.Push(String.Format("gun pos - player: %.1f %.1f %.1f   offhand - player: %.1f %.1f %.1f",
			p.rawGun.x, p.rawGun.y, p.rawGun.z, p.rawOff.x, p.rawOff.y, p.rawOff.z));
		lines.Push(String.Format("gun fwd %.2f %.2f %.2f (len %.2f)   up %.2f %.2f %.2f",
			p.rawFwd.x, p.rawFwd.y, p.rawFwd.z, p.rawFwdLen, p.rawUp.x, p.rawUp.y, p.rawUp.z));

		int y = 60;
		for (int i = 0; i < lines.Size(); i++)
		{
			Screen.DrawText(SmallFont, Font.CR_GREEN, 10, y, lines[i],
				DTA_VirtualWidth, 320, DTA_VirtualHeight, 200, DTA_KeepRatio, true);
			y += 9;
		}
	}
}
