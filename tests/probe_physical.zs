version "3.6"
class RLProbe2 : EventHandler
{
	String last;
	override void WorldTick()
	{
		let p = players[0].mo;
		if (!p) return;
		let g = RL_Pistol(p.FindInventory("RL_Pistol"));
		if (!g) return;
		int rounds = 0, mags = 0;
		let it = ThinkerIterator.Create("RL_EjectedRound"); Actor a;
		while (a = Actor(it.Next())) { rounds++; if (level.maptime % 15 == 0) Console.Printf("  round z=%.1f floor=%.1f state=%s", a.pos.z, a.floorz, a.InStateSequence(a.CurState, a.FindState("Landed")) ? "landed" : "flying"); }
		it = ThinkerIterator.Create("RL_DroppedMag");
		while (a = Actor(it.Next())) mags++;
		let psp = players[0].GetPSprite(PSP_WEAPON);
		String s = String.Format("hand=%d seated=%d locked=%d | chamber=%d mag=%d reserve=%d | rounds=%d droppedmags=%d gunframe=%d",
			g.hand, g.magSeated, g.slideLocked, p.CountInv("RL_PistolChamber"), p.CountInv("RL_PistolMag"), p.CountInv("Clip"), rounds, mags, psp ? psp.Frame : -1);
		if (s != last) Console.Printf("T%d %s", level.maptime, s);
		last = s;
	}
}
