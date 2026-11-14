// Trade between towns: carts on the roads (Banished's and Anno's carts between markets; Manor Lords' traders). Each
// season every town at peace trades with its nearest towns over land (data/trade.json): what it carries by its
// buildings, how many carts by its size, the way over the land (hosts.js landWay, the same walk a host takes). Read
// from the world each season and kept for the season, never stored: Freeciv owns the towns and the wars, this only
// says where carts go. The view draws them (/world `trade`).
import fs from "node:fs";
import { landWay } from "./hosts.js";

const T = JSON.parse(fs.readFileSync(new URL("./data/trade.json", import.meta.url), "utf8"));
const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
let kept = { turn: null, routes: [] };

// What a town's carts carry: its first building's goods, else its own ware.
function goodsOf(c) {
  const b = T.goods.find(([kind]) => (c.buildings ?? []).some((x) => String(x).startsWith(kind)));
  return b ? b[1] : T.wares[Math.abs(Number(c.id)) % T.wares.length];
}

// The season's routes [{from, to, goods, carts, path: [[x, y]...]}]: each town to its links nearest at reach, once a
// pair, the carts going the way of the turn (one season out, the next back).
// cities: /world's towns (view.js, with besieged); atWar(a, b): Freeciv's diplomacy.
export function list(cities, turn, atWar) {
  if (kept.turn === turn) return kept.routes;
  const towns = (cities ?? []).filter((c) => !c.besieged && !c.closed);  // nor a town whose roads are shut (contagion.js)
  const seen = new Set(), routes = [];
  for (const a of towns) {
    const near = towns.filter((b) => b !== a && cheb(a, b) <= T.reach && !(a.owner !== b.owner && atWar(a.owner, b.owner)))
      .sort((x, y) => cheb(a, x) - cheb(a, y)).slice(0, T.links);
    for (const b of near) {
      const key = [a.id, b.id].sort((x, y) => x - y).join("-");
      if (seen.has(key)) continue;
      seen.add(key);
      const [from, to] = (turn + Number(a.id) + Number(b.id)) % 2 ? [b, a] : [a, b];
      const path = landWay(from, to, T.reach * 2);
      if (!path.length) continue;  // no way over land (across water)
      routes.push({ from: from.id, to: to.id, goods: goodsOf(from), carts: Math.min(T.carts.most, 1 + Math.floor(Number(from.size ?? 1) / T.carts.perSize)), path: [[from.x, from.y], ...path] });
    }
  }
  kept = { turn, routes };
  return routes;
}
