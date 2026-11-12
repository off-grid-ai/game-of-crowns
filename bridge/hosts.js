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
import path from "node:path";
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
        seasons: o.x != null ? Math.ceil(Math.max(0, roadTo(lead, o)) / HOSTS.speed) : 0 } : null,
    };
  }).sort((a, b) => b.companies - a.companies);
}

// Steps over land from a host to a place: -1 when the sea lies between (or the place is water), the
// straight count when the land isn't known yet.
function roadTo(h, to) {
  const steps = stepsTo(to);
  return steps ? steps.at(h) : landOf() ? -1 : cheb(h, to);
}

function save(meta, orders) {
  meta.hostOrders = orders;
  chron.saveMeta(meta);
}

// POST /host/order {host, order, x?, y?, city?}: returns [code, {ok, text} | {error}].
export function order(ctx, b) {
  const out = give(ctx, b);
  if (out[0] === 200) {
    const { world, meta } = ctx;
    meta.hostOrdered = { turn: world.turn, n: (meta.hostOrdered?.turn === world.turn ? meta.hostOrdered.n : 0) + 1 };
    chron.saveMeta(meta);
  }
  return out;
}
// How many more orders the hosts may have this season (for /world and the command card).
export const ordersLeft = (ctx) => Math.max(0, (HOSTS.ordersPerSeason ?? 99) - (ctx.meta?.hostOrdered?.turn === ctx.world?.turn ? ctx.meta.hostOrdered.n : 0));
function give(ctx, b) {
  const { world, meta, sworn, crownSeat } = ctx;
  if (!world || meta?.status !== "running") return [400, { error: "no reign is running" }];
  const hosts = list(ctx);
  const h = hosts.find((x) => x.id === Number(b.host));
  if (!h) return [404, { error: "no such host" }];
  const kind = String(b.order ?? "");
  // One order a season, all hosts together (data/hosts.json ordersPerSeason).
  const given = meta.hostOrdered?.turn === world.turn ? meta.hostOrdered.n : 0;
  if (given >= (HOSTS.ordersPerSeason ?? Infinity)) return [400, { error: "The King's captains have their orders for this season. The next order goes with the season's turn." }];
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
      const road = roadTo(h, to);
      if (road < 0) return [400, { error: `The royal host can find no road over land to ${town ? cityName(town.id) : "that place"}; the sea lies between.` }];
      // Into a town only where the gates are open to the King's men; before another's walls otherwise.
      // A great house's town not sworn to the crown is marched on: the host lays siege when it arrives,
      // and the house hears of it now (declare: the route moves favour and names the deed).
      const owner = town ? world.players.find((p) => p.id === town.owner) : null;
      const foe = owner && !houseFor(owner).crown && !houseFor(owner).wild && !sworn?.(owner.id) ? owner : null;
      save(meta, [...rest, { kind: "march", units: h.units, x: to.x, y: to.y, city: town?.id ?? null, since: world.turn, ...(foe ? { siege: true, house: foe.id } : {}) }]);
      const seasons = Math.max(1, Math.ceil(road / HOSTS.speed));
      return [200, { ok: true, text: `${name} marches${town ? ` ${foe ? "on" : "for"} ${cityName(town.id)}` : ""}: ${seasons === 1 ? "a season" : `${seasons} seasons`} on the road${foe ? ", and lays siege when it reaches the walls" : ""}.`,
        ...(foe && !b.declared ? { declare: { city: town.id, house: foe.id } } : {}) }];
    }
    case "garrison": {
      if (!town) return [400, { error: "choose a town to garrison" }];
      const open = town.owner === crown?.id || sworn?.(town.owner);
      if (!open) return [400, { error: `${cityName(town.id)}'s gates are not open to the King's men: its house is not sworn to the crown` }];
      const road = roadTo(h, town);
      if (road < 0) return [400, { error: `The royal host can find no road over land to ${cityName(town.id)}; the sea lies between.` }];
      save(meta, [...rest, { kind: "garrison", units: h.units, x: town.x, y: town.y, city: town.id, since: world.turn }]);
      const seasons = Math.ceil(road / HOSTS.speed);
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

// A step is a real move in Freeciv (edit.unit_move: its own test of the tile, then its move handling,
// vision and huts), not a teleport; the season's pace stays the hosts' own (data/hosts.json speed), so it
// costs no move points. Arguments: embark_to, disembark, conquer_city, conquer_extra, enter_hut, frighten_hut.
const MOVE = "edit.unit_move, u, t, 0, nil, false, false, false, false, false";

// One company's season on the road, in Freeciv: tile by tile along the way the bridge found, stopping
// where the way is shut (another's men stand there).
const walkLua = (id, tiles) => `local u = find.unit(nil, ${id}); if u then for _, p in ipairs({${tiles.map(([x, y]) => `{${x},${y}}`).join(",")}}) do local t = find.tile(p[1], p[2]); if not t then break end; pcall(${MOVE}); if u.tile ~= t then break end end end`;

// With no way over land known: up to n steps, each to the neighbouring land tile nearest the goal.
const stepLua = (id, x, y, n) => `local u = find.unit(nil, ${id}); if u then for i = 1, ${n} do local c = u.tile; local t, bd = nil, math.max(math.abs(c.x - ${x}), math.abs(c.y - ${y})); for a in c:square_iterate(1) do local nm = a.terrain:rule_name(); local d = math.max(math.abs(a.x - ${x}), math.abs(a.y - ${y})); if d < bd and not nm:find("Ocean") and nm ~= "Lake" then t, bd = a, d end end; if not t then break end; pcall(${MOVE}); if u.tile ~= t then break end end end`;

// The land as Freeciv wrote it for the reign (snapshot.lua's map.json): which tiles a host can walk.
let land = { file: null };
function landOf() {
  const file = path.join(chron.paths(chron.activeId()).state, "map.json");
  if (land.file !== file) {
    const m = chron.readJson(file);
    if (!m?.tiles) return null;
    const walk = new Uint8Array(m.width * m.height);
    for (const [x, y, n] of m.tiles) walk[y * m.width + x] = /Ocean|Lake/.test(String(n)) ? 0 : 1;
    land = { file, w: m.width, h: m.height, walk };
  }
  return land;
}

// How many steps over land each tile is from a goal (breadth-first over the eight neighbours, as a
// unit moves in Freeciv), or null when the goal isn't on the land. shut: tiles ("x,y") no host can
// pass this season (another house's town or men stand there; Freeciv won't put the King's men in).
function stepsTo(goal, shut = null) {
  const L = landOf();
  if (!L || goal.x < 0 || goal.y < 0 || goal.x >= L.w || goal.y >= L.h || !L.walk[goal.y * L.w + goal.x]) return null;
  const d = new Int32Array(L.w * L.h).fill(-1);
  const q = [goal.y * L.w + goal.x];
  d[q[0]] = 0;
  for (let i = 0; i < q.length; i++) {
    const x = q[i] % L.w, y = (q[i] / L.w) | 0;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= L.w || ny >= L.h) continue;
      const k = ny * L.w + nx;
      if (d[k] < 0 && L.walk[k] && !shut?.has(`${nx},${ny}`)) { d[k] = d[q[i]] + 1; q.push(k); }
    }
  }
  return { at: (p) => d[p.y * L.w + p.x], w: L.w, h: L.h };
}

// The next n tiles of a company's way down the steps, or [] when it can't reach the goal over land.
function wayOn(steps, from, n) {
  const out = [];
  let p = { x: from.x, y: from.y }, here = steps.at(p);
  if (here < 0) return out;
  while (out.length < n && here > 0) {
    let best = null;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      const q = { x: p.x + dx, y: p.y + dy };
      if (q.x < 0 || q.y < 0 || q.x >= steps.w || q.y >= steps.h) continue;
      const v = steps.at(q);
      if (v >= 0 && v < here && (!best || v < best.v)) best = { ...q, v };
    }
    if (!best) break;
    out.push([best.x, best.y]);
    p = best;
    here = best.v;
  }
  return out;
}

// Each season (season.js): every host under a marching order moves; one that has arrived stands
// (a march becomes a hold; a garrison stays a garrison, in the town).
export function season(ctx, turn) {
  const { world, meta, send, record, besiege } = ctx;
  if (!world || !(meta?.hostOrders ?? []).length) return;
  const crown = crownOf(world);
  const byId = new Map(soldiersOf(world, crown?.id).map((u) => [u.id, u]));
  const next = [];
  const shut = new Set([...(world.cities ?? []), ...(world.units ?? [])].filter((x) => x.owner !== crown?.id).map((x) => `${x.x},${x.y}`));
  for (const o of meta.hostOrders) {
    const units = o.units.filter((id) => byId.has(id));
    if (!units.length) continue;  // the host is no more
    if (o.x == null) { next.push({ ...o, units }); continue; }
    // There: on the place, or before the walls of a town that isn't the crown's (a march halts at another's gates).
    const goal = o.city != null ? world.cities.find((c) => c.id === o.city) : null;
    const reach0 = goal && goal.owner !== crown?.id && o.kind === "march" ? 1 : 0;
    const there = units.every((id) => cheb(byId.get(id), o) <= reach0);
    if (there) {
      // At the walls of the house it marched on: the siege begins (campaigns.js), the host holds before them.
      if (o.siege && goal && goal.owner === o.house && !(meta.campaigns ?? []).some((k) => k.city === goal.id)) {
        record?.({ turn, kind: "decree", text: `The royal host reaches ${cityName(goal.id)} and lays siege.`, city: goal.id });
        besiege?.({ city: goal.id, house: o.house });
        next.push({ kind: "hold", units, since: turn });
        continue;
      }
      if (!o.arrived) record?.({ turn, kind: "decree", text: o.kind === "garrison" ? `The royal host ${o.home ? "is home at" : "garrisons"} ${cityName(o.city)}.` : `The royal host has reached ${o.city != null ? cityName(o.city) : "the place the King named"}.`, city: o.city ?? undefined });
      next.push(o.kind === "march" ? { kind: "hold", units, since: turn } : { ...o, units, arrived: true });
      continue;
    }
    // A host that came no nearer last season (the sea, or gates shut to it) stands where it is.
    // Nearer is counted in steps over land where the way is known (around a lake is nearer too).
    const steps = stepsTo(o, new Set([...shut].filter((k) => k !== `${o.x},${o.y}`))) ?? stepsTo(o);
    const reach = (u) => (steps && steps.at(u) >= 0 ? steps.at(u) : cheb(u, o));
    const far = units.reduce((t, id) => t + reach(byId.get(id)), 0);
    if (o.far != null && far >= o.far) {
      record?.({ turn, kind: "decree", text: `The royal host can go no nearer ${o.city != null ? cityName(o.city) : "the place the King named"}, and makes camp.`, city: o.city ?? undefined });
      next.push({ kind: "hold", units, since: turn });
      continue;
    }
    for (const id of units) {
      const way = steps ? wayOn(steps, byId.get(id), HOSTS.speed) : [];
      send(`lua cmd ${way.length ? walkLua(id, way) : stepLua(id, o.x, o.y, HOSTS.speed)}`);
    }
    next.push({ ...o, units, far });
  }
  save(meta, next);
}
