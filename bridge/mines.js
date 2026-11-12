// Gold seams: who owns the realm's gold and how long it lasts. Freeciv owns the fact (the Gold on a
// tile, the trade it yields and the tax that carries it to the owning house's purse); the ruleset's
// own Lua (realmrules/script.lua realm_mines, run each turn and saved with the game) wears each seam
// down and takes the Gold away when a seam is worked out, reporting it as a "seam_spent" event
// (narrator.js). Widelands and Settlers do the same: a mine's ore runs out, and the land's wealth
// with it. Tunables: realmrules/luadata.txt [mines].

// Which town works each seam (Freeciv's "seams_worked" each season: realm_seam_town, the one rule the seam
// wears down by), kept in the realm's meta (meta.seamTowns: "x,y" -> town id) and put on /world's gold rows
// as their fourth field (worked), -1 for a seam no town works.
export function worked(meta, ev) {
  meta.seamTowns = Object.fromEntries(String(ev.at ?? "").split(";").filter(Boolean).map((s) => { const [x, y, c] = s.split(",").map(Number); return [`${x},${y}`, c]; }));
}
export function withTowns(gold, meta) {
  return (gold ?? []).map(([x, y, owner]) => [x, y, owner, meta?.seamTowns?.[`${x},${y}`] ?? -1]);
}

// A seam worked out (Freeciv's "seam_spent" event): where the old workings stand, kept in the realm's
// meta (meta.spentSeams: [x, y, turn]) so the view shows the abandoned mine there (/world spentSeams).
export function spent(meta, ev) {
  const x = Number(ev.x), y = Number(ev.y);
  const list = (meta.spentSeams ??= []);
  if (!list.some((s) => s[0] === x && s[1] === y)) list.push([x, y, Number(ev.turn)]);
}
