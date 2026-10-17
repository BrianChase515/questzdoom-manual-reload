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
		String s = String.Format("phys=%d hand=%d seated=%d locked=%d slide=%.2f | chamber=%d mag=%d reserve=%d held=%d | hip=%d well=%d slidezone=%d offhandItem=%d",
			g.physActive, g.hand, g.magSeated, g.slideLocked, g.slideShown,
			p.CountInv("RL_PistolChamber"), p.CountInv("RL_PistolMag"), p.CountInv("Clip"), g.heldRounds,
			g.inHip, g.nearWell, g.nearSlide, p.CountInv("RL_OffHand"));
		if (s != last) Console.Printf("T%d %s", level.maptime, s);
		last = s;
	}
}
