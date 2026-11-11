// The King's garrison: the one owner of "a royal company stands at this town" (Total War's
// reinforcements; docs/review/decisions-in-the-world.md). When the King's men march from his seat to
// another town (backing a house, the banners, sellswords), the company is kept with the reign
// (meta.garrisons, so it survives a restart), its men join the town's defence in Freeciv, and it goes
// home after its seasons. The view only draws it (cities[].garrison in /world; decisions_world.gd).
// Numbers: data/garrison.json.
import fs from "node:fs";
import * as chron from "./chronicles.js";

export const GARRISON = JSON.parse(fs.readFileSync(new URL("./data/garrison.json", import.meta.url), "utf8"));

const live = (meta, turn) => (meta.garrisons ?? []).filter((g) => g.until > turn);

// A decree sent the King's men to this town (server.js decreeScenes): the company stands there from now.
// send: Freeciv's console; the men are raised in the town for its holder, as the court's own gifts of men are.
export function post(meta, action, city, turn, send) {
  if (!meta || !city || !GARRISON.on.includes(action)) return null;
  const until = turn + GARRISON.seasons;
  const list = live(meta, turn).filter((g) => g.city !== city.id);  // sent again: the stay starts over
  const g = { city: city.id, since: turn, until, by: action };
  meta.garrisons = [...list, g];
  chron.saveMeta(meta);
  if (GARRISON.units > 0 && send) {
    const type = GARRISON.types.map((t) => `find.unit_type("${t}")`).join(" or ");
    send(`lua cmd local c = find.city(nil, ${Number(city.id)}); if c then for i = 1, ${Number(GARRISON.units)} do edit.create_unit(c.owner, c.tile, ${type}, 0, c, -1) end end`);
  }
  return g;
}

// For /world (view.js townStates): the company at this town, or null. left: its seasons still to stand.
export function view(meta, city, turn) {
  const g = live(meta ?? {}, turn).find((x) => x.city === city.id);
  return g ? { since: g.since, until: g.until, left: g.until - turn } : null;
}
