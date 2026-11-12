// Gold seams: who owns the realm's gold and how long it lasts. Freeciv owns the fact (the Gold on a
// tile, the trade it yields and the tax that carries it to the owning house's purse); the ruleset's
// own Lua (realmrules/script.lua realm_mines, run each turn and saved with the game) wears each seam
// down and takes the Gold away when a seam is worked out, reporting it as a "seam_spent" event
// (narrator.js). Widelands and Settlers do the same: a mine's ore runs out, and the land's wealth
// with it. Tunables: realmrules/luadata.txt [mines].

// A seam worked out (Freeciv's "seam_spent" event): where the old workings stand, kept in the realm's
// meta (meta.spentSeams: [x, y, turn]) so the view shows the abandoned mine there (/world spentSeams).
export function spent(meta, ev) {
  const x = Number(ev.x), y = Number(ev.y);
  const list = (meta.spentSeams ??= []);
  if (!list.some((s) => s[0] === x && s[1] === y)) list.push([x, y, Number(ev.turn)]);
}
