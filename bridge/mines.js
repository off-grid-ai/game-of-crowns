// Gold seams: who owns the realm's gold and how long it lasts. Freeciv owns the fact (the Gold on a
// tile, the trade it yields and the tax that carries it to the owning house's purse); its Lua keeps
// each seam's seasons left (lua/events.lua realm_mines, saved with the game) and takes the Gold away
// when a seam is worked out, reporting it as a "seam_spent" event (narrator.js). Widelands and
// Settlers do the same: a mine's ore runs out, and the land's wealth with it. This file only passes
// the tunables on each season. Tunables: data/mines.json.
import fs from "node:fs";

export const MINES = JSON.parse(fs.readFileSync(new URL("./data/mines.json", import.meta.url), "utf8"));

// Each season (season.js turn): the seams worked this season wear down; the first time, they're laid.
export function season(ctx) {
  if (!MINES.on) return;
  ctx.send(`lua cmd realm_mines(${Number(MINES.seamSeasons)}, "${String(MINES.goldHouse).replace(/[^A-Za-z ]/g, "")}", ${Number(MINES.goldSeams)})`);
}

// A seam worked out (Freeciv's "seam_spent" event): where the old workings stand, kept in the realm's
// meta (meta.spentSeams: [x, y, turn]) so the view shows the abandoned mine there (/world spentSeams).
export function spent(meta, ev) {
  const x = Number(ev.x), y = Number(ev.y);
  const list = (meta.spentSeams ??= []);
  if (!list.some((s) => s[0] === x && s[1] === y)) list.push([x, y, Number(ev.turn)]);
}
