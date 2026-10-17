// Calibration readout: Options -> Manual Reload -> "Show calibration readout".
// Shows where the off hand is relative to the gun and to your body, and which
// zones it is in, so the grab distances can be tuned on the headset.
class RL_Calibrate : EventHandler
{
	override void RenderOverlay(RenderEvent e)
	{
		CVar cv = CVar.FindCVar('rl_calibrate');
		if (!cv || !cv.GetBool()) return;
		let pm = players[consoleplayer].mo;
		if (!pm) return;
		let p = RL_Pistol(pm.FindInventory("RL_Pistol"));
		if (!p) return;

		static const String handNames[] = { "empty", "HOLDING MAG", "ON SLIDE", "grip" };
		Array<String> lines;
		lines.Push(String.Format("physical %s   mag %s   slide %s   chamber %d   mag %d",
			p.physActive ? "ON" : "off", p.magSeated ? "IN" : "OUT",
			p.slideLocked ? "LOCKED" : "fwd", pm.CountInv("RL_PistolChamber"), pm.CountInv("RL_PistolMag")));
		lines.Push(String.Format("hand vs gun:  fwd %.1f  side %.1f  up %.1f", p.lf, p.ls, p.lu));
		lines.Push(String.Format("hand vs body: height %.1f (eye %.1f)  dist %.1f", p.bh, p.eyeH, p.bd));
		lines.Push(String.Format("zones: %s %s %s   hand: %s   slide %.2f",
			p.inHip ? "[HIP]" : "hip", p.nearWell ? "[MAGWELL]" : "magwell",
			p.nearSlide ? "[SLIDE]" : "slide", handNames[clamp(p.hand, 0, 3)], p.slideShown));

		int y = 60;
		for (int i = 0; i < lines.Size(); i++)
		{
			Screen.DrawText(SmallFont, Font.CR_GREEN, 10, y, lines[i],
				DTA_VirtualWidth, 320, DTA_VirtualHeight, 200, DTA_KeepRatio, true);
			y += 9;
		}
	}
}
