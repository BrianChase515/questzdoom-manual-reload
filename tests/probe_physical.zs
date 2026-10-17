version "3.6"
class RLProbe2 : EventHandler
{
	String last;
	override void WorldTick()
	{
		let p = players[0].mo;
		if (!p) return;
		String s = "";
		let w = players[0].ReadyWeapon;
		let g = RL_Pistol(p.FindInventory("RL_Pistol"));
		let sg = RL_Shotgun(p.FindInventory("RL_Shotgun"));
		if (w) s = s .. w.GetClassName();
		if (g) s = s .. String.Format(" | PISTOL hand=%d seated=%d locked=%d slide=%.2f ch=%d mag=%d clip=%d", g.hand, g.magSeated, g.slideLocked, g.slideShown, p.CountInv("RL_PistolChamber"), p.CountInv("RL_PistolMag"), p.CountInv("Clip"));
		if (sg) s = s .. String.Format(" | SHOTGUN hand=%d chamber=%d tube=%d shells=%d pump=%.2f steadied=%d", sg.hand, sg.chamber, p.CountInv("RL_ShotgunTube"), p.CountInv("Shell"), sg.pumpShown, sg.steadied);
		int hulls = 0, live = 0; Actor a;
		let it = ThinkerIterator.Create("RL_Hull"); while (a = Actor(it.Next())) hulls++;
		it = ThinkerIterator.Create("RL_LiveShell"); while (a = Actor(it.Next())) live++;
		s = s .. String.Format(" | hulls=%d live=%d", hulls, live);
		if (s != last) Console.Printf("T%d %s", level.maptime, s);
		last = s;
	}
}
