// The King's garrison: the one owner of "a royal company stands at this town" (Total War's
// reinforcements; docs/review/decisions-in-the-world.md). When the King's men march from his seat to
// another town (backing a house, sellswords), the company is kept with the reign
// (meta.garrisons, so it survives a restart), its men join the town's defence in Freeciv, and it goes
// home after its seasons. The view only draws it (cities[].garrison in /world; decisions_world.gd).
// Numbers: data/garrison.json.
import * as Lua from "./lua.js";
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
    send(`lua cmd ${Lua.levy(city.id, Array(Number(GARRISON.units)).fill(GARRISON.types.join("|")), 0)}`);
  }
  return g;
}

// For /world (view.js townStates): the company at this town, or null. left: its seasons still to stand.
export function view(meta, city, turn) {
  const g = live(meta ?? {}, turn).find((x) => x.city === city.id);
  return g ? { since: g.since, until: g.until, left: g.until - turn } : null;
}
