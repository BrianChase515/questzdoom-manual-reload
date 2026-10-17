// Makes sure the pistol and shotgun you hold are always the Manual Reload ones,
// however you got them (cheat menus, "give", old saves, other mods' spawners).
class RL_WeaponSwap : EventHandler
{
	static const Name fromNames[] = { 'Pistol', 'Vanilla_Pistol', 'Shotgun', 'Vanilla_Shotgun' };
	static const Name toNames[]   = { 'RL_Pistol', 'RL_Pistol', 'RL_Shotgun', 'RL_Shotgun' };

	// Map-spawned originals (if anything spawns them by their HDVR name).
	override void CheckReplacement(ReplaceEvent e)
	{
		Name n = e.Replacee.GetClassName();
		if (n == 'Vanilla_Pistol') e.Replacement = 'RL_Pistol';
		else if (n == 'Vanilla_Shotgun') e.Replacement = 'RL_Shotgun';
	}

	override void WorldTick()
	{
		for (int pn = 0; pn < MAXPLAYERS; pn++)
		{
			if (!playeringame[pn]) continue;
			let p = players[pn].mo;
			if (!p) continue;
			for (int i = 0; i < fromNames.Size(); i++)
			{
				class<Inventory> fromCls = (class<Inventory>)(fromNames[i]);
				if (!fromCls) continue;
				let old = p.FindInventory(fromCls);
				if (!old || old.GetClass() != fromCls) continue;   // exact class only
				Swap(players[pn], old, toNames[i]);
			}
		}
	}

	void Swap(PlayerInfo pl, Inventory old, Name toName)
	{
		let p = pl.mo;
		bool wasReady = pl.ReadyWeapon == old || pl.PendingWeapon == old;
		class<Inventory> toCls = (class<Inventory>)(toName);
		Weapon w = Weapon(p.FindInventory(toCls));
		if (!w)
		{
			w = Weapon(Actor.Spawn(toCls, p.pos));
			if (w)
			{
				w.AmmoGive1 = 0;          // the original already brought its ammo
				w.AmmoGive2 = 0;
				bool ok; Actor dummy;
				[ok, dummy] = w.CallTryPickup(p);
				if (!ok) { w.Destroy(); w = null; }
			}
		}
		if (pl.ReadyWeapon == old)
		{
			pl.ReadyWeapon = null;
			pl.SetPsprite(PSP_WEAPON, null);
		}
		old.Destroy();
		if (w && wasReady)
		{
			pl.PendingWeapon = w;
			p.BringUpWeapon();
		}
	}
}
