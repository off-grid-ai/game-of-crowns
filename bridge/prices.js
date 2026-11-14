// The realm's market prices (casebook, Every coin is a thing; Anno's and Manor Lords' prices that follow supply,
// Victoria's goods made dear by war). Each season (season.js) every good's price is its base moved by what the realm
// lives through (data/prices.json): a wet harvest, winter, famine and sickness make grain dear; wars make iron dear;
// sieges, timber; stopped trade, cloth. One owner, meta.prices {turn, now, was, why}; the treasury's decrees cost their
// price times their good's rise (treasury.js priceOf). /world `prices` {good: {price, was, why}}.
import fs from "node:fs";
import { calendar } from "./calendar.js";
import * as Harvest from "./harvest.js";
import * as Contagion from "./contagion.js";
import { crownOf, greatHouses } from "./realm.js";

const P = JSON.parse(fs.readFileSync(new URL("./data/prices.json", import.meta.url), "utf8"));

export function season(ctx, turn) {
  const { meta, world } = ctx;
  if (!world?.cities?.length) return;
  const towns = world.cities.length;
  const share = (f) => world.cities.filter(f).length / towns;
  const d = ctx.detail?.();
  const houses = [...greatHouses(world), crownOf(world)].filter(Boolean);
  let wars = 0;
  for (const a of houses) for (const b of houses) if (a.id < b.id && (d?.players?.[a.id]?.atWarWith ?? []).includes(b.id)) wars++;
  wars += (meta.campaigns ?? []).length;
  const sieges = world.cities.filter((c) => c.besieged).length;
  const why = { grain: [], iron: [], timber: [], cloth: [] };
  let grain = 1;
  if (Harvest.view(meta, turn)?.kind === "poor") { grain *= P.grain.poorHarvest; why.grain.push("a wet harvest"); }
  if (calendar(turn).season === "winter") { grain *= P.grain.winter; why.grain.push("winter"); }
  const starving = share((c) => c.famine);
  if (starving) { grain *= 1 + P.grain.famine * starving; why.grain.push("hungry towns"); }
  if (Contagion.abroad(meta)) { grain *= P.grain.sickness; why.grain.push("the sickness"); }
  const iron = Math.min(P.iron.warMost, 1 + P.iron.war * wars);
  if (wars) why.iron.push(wars > 1 ? `${wars} wars` : "a war");
  const timber = 1 + P.timber.siege * sieges;
  if (sieges) why.timber.push(sieges > 1 ? `${sieges} sieges` : "a siege");
  const blocked = share((c) => c.besieged || c.closed);
  const cloth = 1 + P.cloth.blocked * blocked;
  if (blocked) why.cloth.push("roads stopped");
  const rise = { grain, iron, timber, cloth };
  const now = Object.fromEntries(Object.entries(P.base).map(([g, b]) => [g, Math.round(b * (rise[g] ?? 1))]));
  meta.prices = { turn, was: meta.prices?.now ?? now, now, why: Object.fromEntries(Object.entries(why).map(([g, w]) => [g, w.join(", ")])) };
}

// How much dearer a decree is for its good now (treasury.js priceOf): the good's price over its base; 1 without one.
export function rise(meta, action) {
  const g = P.decrees[action];
  return g && meta?.prices?.now?.[g] ? meta.prices.now[g] / P.base[g] : 1;
}

export function view(meta) {
  const p = meta?.prices;
  return p ? Object.fromEntries(Object.keys(P.base).map((g) => [g, { price: p.now[g], was: p.was[g], why: p.why[g] || null }])) : null;
}
