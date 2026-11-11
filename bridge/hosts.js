// The King's hosts and their orders: the one owner (Warcraft III: select, then one of a few fixed
// orders; Total War's campaign map: an army is one thing, ordered as one). The view only asks
// (POST /host/order); this decides and moves the army in Freeciv, a few tiles each season.
//   march     to a tile or a town: it stands there when it arrives
//   hold      stop where it is
//   garrison  march into a town of the crown's, or of a house sworn to it, and stay
//   return    march home to the King's seat
//   split     half its companies become a host of their own
// A host is the crown's fighting companies standing together (data/hosts.json near), or the
// companies under one order. Orders are kept with the reign (meta.hostOrders). Numbers: data/hosts.json.
import fs from "node:fs";
import * as chron from "./chronicles.js";
import { houseFor, cityName } from "./narrator.js";
import { CIVILIAN } from "./campaigns.js";

export const HOSTS = JSON.parse(fs.readFileSync(new URL("./data/hosts.json", import.meta.url), "utf8"));
const SHIPS = new Set(HOSTS.ships);
const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));

const crownOf = (world) => world?.players?.find((p) => houseFor(p).crown);
const soldiersOf = (world, pid) => (world?.units ?? []).filter((u) => u.owner === pid && !CIVILIAN.has(u.type) && !SHIPS.has(u.type));

// The crown's hosts as they stand: [{id, x, y, companies, men, at, units, order}]. id: its lowest
// company's id (stable while that company lives). at: the town it stands in, or null. order: its
// order's kind, target and seasons to go, or null when it stands at ease.
export function list(ctx) {
  const { world, meta } = ctx;
  const crown = crownOf(world);
  if (!crown) return [];
  const mine = soldiersOf(world, crown.id);
  const byId = new Map(mine.map((u) => [u.id, u]));
  const orders = (meta?.hostOrders ?? []).map((o) => ({ ...o, units: o.units.filter((id) => byId.has(id)) })).filter((o) => o.units.length);
  const taken = new Set(orders.flatMap((o) => o.units));
  const groups = orders.map((o) => ({ units: o.units.map((id) => byId.get(id)), order: o }));
  // The rest, by where they stand: companies within reach of each other are one host.
  for (const u of mine.filter((x) => !taken.has(x.id))) {
    const g = groups.find((x) => !x.order && x.units.some((v) => cheb(u, v) <= HOSTS.near));
    if (g) g.units.push(u);
    else groups.push({ units: [u], order: null });
  }
  return groups.map((g) => {
    const lead = g.units.reduce((a, b) => (a.id < b.id ? a : b));
    const town = world.cities.find((c) => c.x === lead.x && c.y === lead.y);
    const o = g.order;
    return {
      id: lead.id, x: lead.x, y: lead.y, companies: g.units.length, men: g.units.length * HOSTS.men,
      at: town ? { id: town.id, name: cityName(town.id) } : null, units: g.units.map((u) => u.id),
      order: o ? { kind: o.kind, x: o.x ?? null, y: o.y ?? null, city: o.city ?? null, to: o.city != null ? cityName(o.city) : null,
        seasons: o.x != null ? Math.ceil(cheb(lead, o) / HOSTS.speed) : 0 } : null,
    };
  }).sort((a, b) => b.companies - a.companies);
}

function save(meta, orders) {
  meta.hostOrders = orders;
  chron.saveMeta(meta);
}

// POST /host/order {host, order, x?, y?, city?}: returns [code, {ok, text} | {error}].
export function order(ctx, b) {
  const { world, meta, sworn, crownSeat } = ctx;
  if (!world || meta?.status !== "running") return [400, { error: "no reign is running" }];
  const hosts = list(ctx);
  const h = hosts.find((x) => x.id === Number(b.host));
  if (!h) return [404, { error: "no such host" }];
  const kind = String(b.order ?? "");
  const rest = (meta.hostOrders ?? []).filter((o) => !o.units.some((id) => h.units.includes(id)));
  const name = `The royal host (${h.men.toLocaleString("en-US")} men)`;
  const crown = crownOf(world);
  const town = b.city != null ? world.cities.find((c) => c.id === Number(b.city)) : null;
  const inside = (x, y) => Number.isFinite(x) && Number.isFinite(y) && x >= 0 && y >= 0 && x < (world.width ?? 9999) && y < (world.height ?? 9999);
  switch (kind) {
    case "hold":
      save(meta, [...rest, { kind: "hold", units: h.units, since: world.turn }]);
      return [200, { ok: true, text: `${name} holds its ground${h.at ? ` at ${h.at.name}` : ""}.` }];
    case "march": {
      const to = town ? { x: town.x, y: town.y } : { x: Math.round(Number(b.x)), y: Math.round(Number(b.y)) };
      if (!inside(to.x, to.y)) return [400, { error: "choose where on the map" }];
      // Into a town only where the gates are open to the King's men; before another's walls otherwise.
      save(meta, [...rest, { kind: "march", units: h.units, x: to.x, y: to.y, city: town?.id ?? null, since: world.turn }]);
      const seasons = Math.max(1, Math.ceil(cheb(h, to) / HOSTS.speed));
      return [200, { ok: true, text: `${name} marches${town ? ` for ${cityName(town.id)}` : ""}: ${seasons === 1 ? "a season" : `${seasons} seasons`} on the road.` }];
    }
    case "garrison": {
      if (!town) return [400, { error: "choose a town to garrison" }];
      const open = town.owner === crown?.id || sworn?.(town.owner);
      if (!open) return [400, { error: `${cityName(town.id)}'s gates are not open to the King's men: its house is not sworn to the crown` }];
      save(meta, [...rest, { kind: "garrison", units: h.units, x: town.x, y: town.y, city: town.id, since: world.turn }]);
      const seasons = Math.ceil(cheb(h, town) / HOSTS.speed);
      return [200, { ok: true, text: seasons ? `${name} marches to garrison ${cityName(town.id)}: ${seasons === 1 ? "a season" : `${seasons} seasons`} on the road.` : `${name} garrisons ${cityName(town.id)}.` }];
    }
    case "return": {
      const seat = crownSeat?.();
      if (!seat) return [400, { error: "the crown has no seat to return to" }];
      save(meta, [...rest, { kind: "garrison", units: h.units, x: seat.x, y: seat.y, city: seat.id, home: true, since: world.turn }]);
      return [200, { ok: true, text: `${name} turns for home, to ${cityName(seat.id)}.` }];
    }
    case "split": {
      if (h.companies < HOSTS.splitMin) return [400, { error: "one company can't be split" }];
      const half = Math.floor(h.companies / 2);
      const away = [...h.units].sort((a, b) => b - a).slice(0, half);  // the newest companies go; the host keeps its id
      const stay = h.units.filter((id) => !away.includes(id));
      const was = (meta.hostOrders ?? []).find((o) => o.units.some((id) => h.units.includes(id)));
      save(meta, [...rest, { ...(was ?? { kind: "hold", since: world.turn }), units: stay }, { kind: "hold", units: away, since: world.turn }]);
      return [200, { ok: true, text: `The host divides: ${(half * HOSTS.men).toLocaleString("en-US")} men stand apart under their own captain.` }];
    }
  }
  return [400, { error: "no such order" }];
}

// One company's move toward a tile, in Freeciv: up to n steps, each to the neighbouring land tile
// nearest the goal (never the sea), stopping when it can go no nearer or the way is shut.
const stepLua = (id, x, y, n) => `local u = find.unit(nil, ${id}); if u then for i = 1, ${n} do local t = u.tile; local best, bd = nil, math.max(math.abs(t.x - ${x}), math.abs(t.y - ${y})); for a in t:square_iterate(1) do local nm = a.terrain:rule_name(); local d = math.max(math.abs(a.x - ${x}), math.abs(a.y - ${y})); if d < bd and not nm:find("Ocean") and nm ~= "Lake" then best, bd = a, d end end; if not best then break end; pcall(edit.unit_teleport, u, best); if u.tile ~= best then break end end end`;

// Each season (season.js): every host under a marching order moves; one that has arrived stands
// (a march becomes a hold; a garrison stays a garrison, in the town).
export function season(ctx, turn) {
  const { world, meta, send, record } = ctx;
  if (!world || !(meta?.hostOrders ?? []).length) return;
  const crown = crownOf(world);
  const byId = new Map(soldiersOf(world, crown?.id).map((u) => [u.id, u]));
  const next = [];
  for (const o of meta.hostOrders) {
    const units = o.units.filter((id) => byId.has(id));
    if (!units.length) continue;  // the host is no more
    if (o.x == null) { next.push({ ...o, units }); continue; }
    const there = units.every((id) => cheb(byId.get(id), o) === 0);
    if (there) {
      if (!o.arrived) record?.({ turn, kind: "decree", text: o.kind === "garrison" ? `The royal host ${o.home ? "is home at" : "garrisons"} ${cityName(o.city)}.` : `The royal host has reached ${o.city != null ? cityName(o.city) : "the place the King named"}.`, city: o.city ?? undefined });
      next.push(o.kind === "march" ? { kind: "hold", units, since: turn } : { ...o, units, arrived: true });
      continue;
    }
    // A host that came no nearer last season (the sea, or gates shut to it) stands where it is.
    const far = units.reduce((t, id) => t + cheb(byId.get(id), o), 0);
    if (o.far != null && far >= o.far) {
      record?.({ turn, kind: "decree", text: `The royal host can go no nearer ${o.city != null ? cityName(o.city) : "the place the King named"}, and makes camp.`, city: o.city ?? undefined });
      next.push({ kind: "hold", units, since: turn });
      continue;
    }
    for (const id of units) send(`lua cmd ${stepLua(id, o.x, o.y, HOSTS.speed)}`);
    next.push({ ...o, units, far });
  }
  save(meta, next);
}
