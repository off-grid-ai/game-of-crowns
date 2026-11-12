// The crown's money: what a decree costs (priceOf, a share of a full treasury),
// the once-a-year occasions and how long until each comes again (yearlyKey,
// seasonsLeft), the King's own works rising and paying (royalWorks), and the
// season's tithe (tithe) with its ten-season reckoning (reckoning). Nothing here
// reads server.js: the realm's state and the bridge's own helpers come in as
// one context argument, built fresh by server.js on each call (server.js keeps
// wrappers of the same names, and the tally and lastSeason objects).

import { crownOf } from "./realm.js";
import { SEASONS_PER_YEAR, isYearEnd } from "./calendar.js";
import { houseFor, cityName } from "./narrator.js";
import { DECREES, titheLua, TITHE_HIGH, ECONOMY } from "./crown.js";
import * as Lua from "./lua.js";
import * as chron from "./chronicles.js";
import * as kingDeeds from "./ledger.js";
export { ECONOMY };

// The same thing bought again within the year costs more: each purchase of a key
// (decree:gift, court:<kind>:<option>) in the last wear.seasons raises its price
// by wear.step of the base. A King who answers everything with gold runs short.
export function usesOf(meta, key, turn) {
  return (meta?.spent ?? []).filter((x) => x.key === key && turn - x.turn < ECONOMY.wear.seasons).length;
}
export function worn(meta, key, base, turn) {
  return Math.round(base * (1 + ECONOMY.wear.step * usesOf(meta, key, turn)));
}
// A purchase made: counted for wear, and for the season's true income (the top bar).
export function spend(meta, key, cost, turn) {
  meta.spent = (meta.spent ?? []).filter((x) => turn - x.turn < ECONOMY.wear.seasons);
  meta.spent.push({ key, turn });
  (meta.econ ??= {}).spentSince = (meta.econ.spentSince ?? 0) + (cost ?? 0);
}
// One line of why the King can't pay, said at the moment of choice; null when he
// can. In crowns, as the King reads money (a hundred to each gold).
const inCr = (g) => `${(g * 100).toLocaleString("en-GB")} crowns`;
export function shortOf(purse, cost) {
  return cost > 0 && purse < cost ? `The treasury holds ${inCr(purse)}; this needs ${inCr(cost)}` : null;
}

// A decree's price grows with the treasury: a rich King's gift must be a real
// share of what he holds, or it means nothing to the house that gets it.
export const SHARE = { gift: 0.04, feast: 0.03, relief: 0.03, marriage: 0.08, alliance: 0.06, march: 0.08, buyoff: 0.1, build: 0.04 };

// The crown's great occasions come once a year: a levy drains the countryside of
// men, a feast at court is an event, the banners answer once. The turn each was
// last given is kept with the reign; seat feasts are keyed apart from a lord's.
// Seasons before the King may change the tithe again (data/economy.json tithe.changeEvery).
export const titheWait = (meta, turn) => Math.max(0, (meta?.titheSetAt ?? -99) + (ECONOMY.tithe.changeEvery ?? 0) - turn);
export const FAVOUR = new Set(["gift", "feast", "relief"]);
export function yearlyKey(ctx, cmd) {
  const { world } = ctx;
  if (cmd.action === "levy" || cmd.action === "banners") return cmd.action;
  if (cmd.action === "feast") {
    const c = world?.cities?.find((x) => x.id === Number(cmd.city));
    const owner = c ? world.players.find((p) => p.id === c.owner) : null;
    if (owner && houseFor(owner).crown) return "feast:court";
  }
  // One royal favour to a house a year: grain, crowns or a feast in their honour.
  if (FAVOUR.has(cmd.action)) {
    const c = world?.cities?.find((x) => x.id === Number(cmd.city));
    // Grain to the crown's own towns is counted town by town.
    const own = world.players.find((p) => p.id === c?.owner);
    if (c) return own && houseFor(own).crown ? `relief:${c.id}` : `favour:${c.owner}`;
  }
  return null;
}
export function seasonsLeft(ctx, key) {
  const { world, meta } = ctx;
  const at = meta?.decreeAt?.[key];
  return at == null ? 0 : Math.max(0, SEASONS_PER_YEAR - ((world?.turn ?? 0) - at));
}

export function priceOf(ctx, action) {
  const { world, meta } = ctx;
  const base = DECREES[action]?.cost ?? 0;
  const purse = crownOf(world)?.gold ?? 0;
  return worn(meta, `decree:${action}`, Math.max(base, Math.round(purse * (SHARE[action] ?? 0))), world?.turn ?? 0);
}

// The King's own works: what he funds in a royal town rises over two seasons
// (shown as a building site), then stands and works for him: a market brings
// coin each season, a barracks a company each year, a granary feeds the town.
export const WORK_SEASONS = 2;
export function royalWorks(ctx, turn) {
  const { world, meta, send, record, scene, crownOf } = ctx;
  const crown = crownOf();
  if (!crown) return;
  for (const [cid, w] of Object.entries(meta.works ?? {})) {
    w.left -= 1;
    w.since = Date.now();
    if (w.left > 0) continue;
    const c = world.cities.find((x) => x.id === Number(cid));
    delete meta.works[cid];
    if (!c || c.owner !== crown.id) {
      if (w.paid) send(`lua cmd ${Lua.gold(crown.id, w.paid)}`);
      record({ turn, kind: "works", text: `The King's masons leave their half-built ${w.building.toLowerCase()} in ${cityName(Number(cid))}: the town is no longer the Crown's. The coin comes home.` });
      continue;
    }
    send(`lua cmd ${Lua.building(c.id, w.building)}`);
    record({ turn, kind: "works", text: `The King's ${w.building.toLowerCase()} stands finished in ${cityName(c.id)}.`, city: c.id });
    scene("feast", { x: c.x, y: c.y, city: c.id, owner: c.owner });
  }
  // What his finished works bring in.
  const mine = world.cities.filter((x) => x.owner === crown.id);
  const markets = mine.filter((x) => (x.buildings ?? []).includes("Marketplace")).length;
  // A market's gold beyond Freeciv's own tax (data/economy.json marketGold; 0: the crown earns only what its towns yield).
  const marketGold = ECONOMY.marketGold ?? 0;
  if (markets && marketGold) send(`lua cmd ${Lua.gold(crown.id, markets * marketGold)}`);
  if (isYearEnd(turn)) for (const x of mine.filter((y) => (y.buildings ?? []).includes("Barracks"))) {
    send(`lua cmd ${Lua.levy(x.id, ["Pikemen"])}`);
  }
  chron.saveMeta(meta);
}

// The season's tithe: the wagons at the year's turn, the tithe's deed, and
// what reaches Kingsmere less the crown's upkeep (tally since the last
// reckoning, lastSeason for the top bar; both are server.js's, mutated here).
export function tithe(ctx, turn) {
  const { world, meta, history, tally, lastSeason, scene, deed, send } = ctx;
  // War between the houses chokes the roads: the less peace, the less tithe reaches Kingsmere.
  const peaceNow = history[history.length - 1]?.peace ?? 1;
  // The tithe, seen: at the year's turn wagons roll to Kingsmere from the realm's
  // biggest towns, more of them the higher the tithe.
  if (isYearEnd(turn) && meta.tithe > 0) {
    const crownId = crownOf(world)?.id;
    const king = world.cities.find((c) => c.owner === crownId && c.capital);
    const from = world.cities.filter((c) => c.owner !== crownId && !houseFor(world.players.find((p) => p.id === c.owner) ?? {}).wild).sort((x, y) => y.size - x.size).slice(0, Math.max(1, Math.round(meta.tithe * 20)));
    if (king) for (const c of from) scene("tribute", { x: c.x, y: c.y, tx: king.x, ty: king.y, city: king.id, tithe: true });
  }
  if (isYearEnd(turn) && (meta.tithe >= TITHE_HIGH || meta.tithe <= ECONOMY.tithe.low)) deed(kingDeeds.tagsFor("realm", meta.tithe >= TITHE_HIGH ? "tithe_high" : "tithe_low"), { act: false });
  // A heavy tithe is felt in Freeciv: every great house bears a Heavy Tithe (one townsman fewer content in each of its towns).
  const bearing = meta.tithe >= TITHE_HIGH ? world.players.filter((p) => !houseFor(p).crown && !houseFor(p).wild).map((p) => p.id) : [];
  send(`lua cmd ${Lua.heavyTithe(bearing)}`);
  const t = titheLua(world, meta.tithe * (0.4 + 0.6 * peaceNow));
  tally.total += t.total;
  tally.upkeep += t.upkeep;
  // The season's true income, as the top bar shows it: what came in besides the
  // tithe (the crown's own towns, its markets) is the purse's rise since last
  // season plus what the King spent, and the tithe less the upkeep on top.
  const gold = crownOf(world)?.gold ?? 0;
  const econ = (meta.econ ??= {});
  const besides = econ.base == null ? 0 : gold - econ.base + (econ.spentSince ?? 0);
  lastSeason.net = besides + t.total - t.upkeep;
  econ.base = gold + t.total - t.upkeep;
  econ.spentSince = 0;
  t.lua.forEach((l) => send(`lua cmd ${l}`));
}

// Every ten seasons the chronicle tells what the tithe brought and cost.
export function reckoning(ctx, turn) {
  const { tally, record } = ctx;
  if (turn % 10 === 0 && (tally.total > 0 || tally.upkeep > 0)) {
    record({ turn, kind: "tithe", text: tally.total > 0
      ? `The royal tithe brings ${tally.total} gold to Kingsmere since the last reckoning; the court, the royal host and the castles cost ${tally.upkeep} gold.`
      : `No tithe has reached Kingsmere since the last reckoning; the court, the royal host and the castles still cost ${tally.upkeep} gold.` });
    tally.total = tally.upkeep = 0;
  }
}
