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
		int cas = 0; let it = ThinkerIterator.Create("RL_Casing"); Actor a; while (a = Actor(it.Next())) cas++;
		let psp = players[0].GetPSprite(PSP_WEAPON);
		String st = "?";
		if (psp && psp.CurState) { if (psp.CurState.InStateSequence(g.FindState("Ready.Physical"))) st = "ReadyPhys"; else if (psp.CurState.InStateSequence(g.FindState("Ready.Loop"))) st = "ReadyButton"; else st = "other"; }
		String s = String.Format("hand=%d steadied=%d slide=%.2f | chamber=%d mag=%d | casings=%d | state=%s",
			g.hand, g.steadied, g.slideShown, p.CountInv("RL_PistolChamber"), p.CountInv("RL_PistolMag"), cas, st);
		if (s != last) Console.Printf("T%d %s", level.maptime, s);
		last = s;
	}
}
