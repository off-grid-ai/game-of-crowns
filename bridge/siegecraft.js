// Besiegers that adapt (casebook, War: Break the favourite trick; Dwarf Fortress's attackers, Stronghold's and Total
// War's siege choices). A great house's siege of a town (campaigns.js besiegers: three of its companies at the walls;
// the King's own sieges are his to call) that loses a company storming the walls changes its approach: it mines
// under walls, bribes a man inside if its purse allows, else starves the town (data/siegecraft.json). One owner,
// meta.siegecraft {town id: {by, since, storms, approach, dug}}; Freeciv's hit points, walls and units carry it out.
// /world `sieges` [{town, by, since, storms, approach, dug}] for the view to show the approach.
import fs from "node:fs";
import * as Lua from "./lua.js";
import { besiegers, CIVILIAN } from "./campaigns.js";
import { HITPOINTS } from "./rules.js";
import { crownOf } from "./realm.js";
import { houseFor, cityName } from "./narrator.js";

const S = JSON.parse(fs.readFileSync(new URL("./data/siegecraft.json", import.meta.url), "utf8"));
const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
const WORDS = {
  mine: "they set miners to dig under its walls",
  bribe: "they look for a man inside who can be bought",
  starve: "they settle in to starve it",
};

// A company killed (server.js unit_killed): one of a besieger's, at the walls, is a storm that failed.
export function killed(meta, ev) {
  for (const s of Object.values(meta.siegecraft ?? {})) {
    if (s.by === Number(ev.owner) && cheb(s, { x: Number(ev.x), y: Number(ev.y) }) <= 1) s.storms++;
  }
}

const defenders = (world, c) => (world.units ?? []).filter((u) => u.owner === c.owner && u.x === c.x && u.y === c.y && !CIVILIAN.has(u.type));

// Each season: the sieges seen, a failed storm's new approach chosen, and each approach worked.
export function season(ctx, turn) {
  const { meta, world, send, record } = ctx;
  if (!world?.cities) return;
  const crownId = crownOf(world)?.id;
  const all = (meta.siegecraft ??= {});
  const seen = new Set();
  for (const c of world.cities) {
    const near = besiegers(ctx, c);
    if (near.length < 3) continue;
    const counts = {};
    for (const u of near) counts[u.owner] = (counts[u.owner] ?? 0) + 1;
    const by = Number(Object.entries(counts).sort((a, b) => b[1] - a[1])[0][0]);
    if (by === crownId) continue;
    seen.add(String(c.id));
    const s = all[c.id]?.by === by ? all[c.id] : (all[c.id] = { by, x: c.x, y: c.y, since: turn, storms: 0, approach: null, dug: 0 });
    const them = houseFor(world.players.find((p) => p.id === by) ?? {}).name;
    if (s.storms && !s.approach) {
      const walls = (c.buildings ?? []).includes("City Walls");
      const gold = world.players.find((p) => p.id === by)?.gold ?? 0;
      s.approach = walls ? "mine" : gold >= S.bribe.gold ? "bribe" : "starve";
      record({ turn, kind: "battle", text: `${them} failed to storm ${cityName(c.id)}. Now ${WORDS[s.approach]}.`, city: c.id });
      continue;
    }
    if (s.approach === "mine" && ++s.dug >= S.mine.seasons) {
      if ((c.buildings ?? []).includes("City Walls")) {
        send(`lua cmd ${Lua.building(c.id, "City Walls", false)}`);
        record({ turn, kind: "battle", text: `The walls of ${cityName(c.id)} come down over ${them}'s mines. The breach is open.`, city: c.id });
      }
      s.approach = "starve";
    } else if (s.approach === "bribe") {
      const gate = defenders(world, c)[0];
      send(`lua cmd ${Lua.gold(by, -S.bribe.gold)}`);
      if (gate) {
        send(`lua cmd ${Lua.desert(gate.id)}`);
        record({ turn, kind: "battle", text: `Gold changes hands in the dark. A company of ${cityName(c.id)}'s garrison is gone by morning, and ${them} is the richer for it.`, city: c.id });
      }
      s.approach = "starve";
    } else if (s.approach === "starve") {
      for (const u of defenders(world, c)) {
        const full = HITPOINTS[u.type] ?? 10;
        const loss = Math.min(Math.max(1, Math.round(full * S.starve)), Number(u.hp ?? full) - 1);
        if (loss > 0) send(`lua cmd ${Lua.hurt(u.id, -loss)}`);
      }
    }
  }
  for (const id of Object.keys(all)) if (!seen.has(id)) delete all[id];
}

// For /world: the great houses' sieges and how they press them.
export function list(meta) {
  return Object.entries(meta?.siegecraft ?? {}).map(([town, s]) => ({ town: Number(town), by: s.by, since: s.since, storms: s.storms, approach: s.approach, dug: s.dug }));
}
