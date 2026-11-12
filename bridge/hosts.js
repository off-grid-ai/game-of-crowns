// The King's hosts and their orders: the one owner (Warcraft III: select, then one of a few fixed
// orders; Total War's campaign map: an army is one thing, ordered as one). The view only asks
// (POST /host/order); this decides and moves the army in Freeciv, a few tiles each season.
//   march     to a tile or a town: it stands there when it arrives; on another's town it halts at the walls and
//             lays siege (campaigns.js), which the card calls Besiege
//   attack    on a foe's men in the field: it follows them, and from beside them strikes each season by
//             Freeciv's Attack (Lua.strike) until they are gone
//   face      (march, attack) the way the host forms its line on arrival: a yaw, atan2 of x and z in the
//             view's world XZ (Total War's drag to face); kept on the order and shown in list()
//   hold      stop where it is
//   garrison  march into a town of the crown's, or of a house sworn to it, and stay
//   return    march home to the King's seat
//   split     half its companies become a host of their own
// A host is the crown's fighting companies standing together (data/hosts.json near), or the
// companies under one order. Orders are kept with the reign (meta.hostOrders). Numbers: data/hosts.json.
import { crownOf } from "./realm.js";
import fs from "node:fs";
import path from "node:path";
import * as chron from "./chronicles.js";
import { houseFor, cityName } from "./narrator.js";
import { CIVILIAN, sworn } from "./campaigns.js";
import * as Lua from "./lua.js";
import { HITPOINTS, HULLS } from "./rules.js";

export const HOSTS = JSON.parse(fs.readFileSync(new URL("./data/hosts.json", import.meta.url), "utf8"));

// A company's men, as the realm counts them: its Freeciv unit type's (data/hosts.json menOf, `men` for any other kind)
// by its health, its hit points over its type's full (the ruleset's hitpoints). Every host's strength is their sum.
export function menOf(u) {
  const full = HITPOINTS[u.type] ?? 10;
  const share = u.hp == null ? 1 : Math.max(0, Math.min(1, Number(u.hp) / full));
  return Math.round((HOSTS.menOf?.[u.type] ?? HOSTS.men) * share);
}
export const SHIPS = new Set(HOSTS.ships);  // the hulls that carry hosts over water (data/hosts.json ships)
const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));

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
      id: lead.id, x: lead.x, y: lead.y, companies: g.units.length, men: g.units.reduce((n, u) => n + menOf(u), 0),
      at: town ? { id: town.id, name: cityName(town.id) } : null, units: g.units.map((u) => u.id),
      order: o ? { kind: o.kind, x: o.x ?? null, y: o.y ?? null, city: o.city ?? null, to: o.city != null ? cityName(o.city) : null,
        seasons: o.x != null ? Math.ceil(Math.max(0, roadTo(lead, o)) / HOSTS.speed) : 0, face: o.face ?? null,
        sea: o.sea ? { phase: o.sea.phase, port: cityName(o.sea.port.id), landing: o.sea.landing, hulls: o.sea.hulls } : null } : null,
      aboard: o?.sea?.phase === "sail",  // at sea in the crown's hulls (its crossing: hosts.js crossing)
      ordersLeft: ordersLeft(ctx, lead.id),  // this host's orders still to give this season (data/hosts.json ordersPerHost)
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
// dry: true (a march only) answers as the order would, by land or by sea, and gives nothing: no order, none of the
// season's orders spent, no declaration (GoC's render pass asks before it spends a host's one order).
export function order(ctx, b) {
  const out = give(ctx, b);
  if (out[0] === 200 && !b.dry) {
    const { world, meta } = ctx;
    const by = meta.hostOrdered?.turn === world.turn ? { ...meta.hostOrdered.by } : {};
    by[Number(b.host)] = (by[Number(b.host)] ?? 0) + 1;
    meta.hostOrdered = { turn: world.turn, by };  // orders given this season, by host (its id: its lowest company's)
    chron.saveMeta(meta);
  }
  return out;
}
// How many more orders host `id` may have this season (each host its own: data/hosts.json ordersPerHost; for /world's
// hosts and the command card).
export const ordersLeft = (ctx, id) => Math.max(0, (HOSTS.ordersPerHost ?? 99) - (ctx.meta?.hostOrdered?.turn === ctx.world?.turn ? (ctx.meta.hostOrdered.by?.[Number(id)] ?? 0) : 0));
function give(ctx, b) {
  const { world, meta, sworn, crownSeat } = ctx;
  if (!world || meta?.status !== "running") return [400, { error: "no reign is running" }];
  const hosts = list(ctx);
  const h = hosts.find((x) => x.id === Number(b.host));
  if (!h) return [404, { error: "no such host" }];
  const kind = String(b.order ?? "");
  if (b.dry && kind !== "march") return [400, { error: "only a march can be asked dry" }];
  // One order a season to each host (data/hosts.json ordersPerHost): another host may still be ordered.
  if (ordersLeft(ctx, h.id) < 1) return [400, { error: "This host has its orders for this season; the next goes with the season's turn. Another host may still be ordered." }];
  const rest = (meta.hostOrders ?? []).filter((o) => !o.units.some((id) => h.units.includes(id)));
  const name = `The royal host (${h.men.toLocaleString("en-US")} men)`;
  const crown = crownOf(world);
  const town = b.city != null ? world.cities.find((c) => c.id === Number(b.city)) : null;
  const inside = (x, y) => Number.isFinite(x) && Number.isFinite(y) && x >= 0 && y >= 0 && x < (world.width ?? 9999) && y < (world.height ?? 9999);
  const face = Number.isFinite(Number(b.face)) && b.face !== null && b.face !== "" ? { face: Number(b.face) } : {};
  switch (kind) {
    case "hold":
      save(meta, [...rest, { kind: "hold", units: h.units, since: world.turn }]);
      return [200, { ok: true, text: `${name} holds its ground${h.at ? ` at ${h.at.name}` : ""}.` }];
    case "march": {
      const to = town ? { x: town.x, y: town.y } : { x: Math.round(Number(b.x)), y: Math.round(Number(b.y)) };
      if (!inside(to.x, to.y)) return [400, { error: "choose where on the map" }];
      const road = roadTo(h, to);
      // No road over land: the host takes ship (Mac: "ships are just to move armies from one point to another").
      const sea = road < 0 ? crossing(ctx, h, to) : null;
      if (sea?.error) return [400, { error: sea.error }];
      // Into a town only where the gates are open to the King's men; before another's walls otherwise.
      // A great house's town not sworn to the crown is marched on: the host lays siege when it arrives,
      // and the house hears of it now (declare: the route moves favour and names the deed).
      const owner = town ? world.players.find((p) => p.id === town.owner) : null;
      const foe = owner && !houseFor(owner).crown && !houseFor(owner).wild && !sworn?.(owner.id) ? owner : null;
      if (b.dry) {
        const seasons = sea ? Math.max(1, Math.ceil(sea.walk / HOSTS.speed) + Math.ceil(sea.sail / sea.speed) + Math.ceil(sea.ashore / HOSTS.speed)) : Math.max(1, Math.ceil(road / HOSTS.speed));
        return [200, { ok: true, dry: true, by: sea ? "sea" : "land", seasons, ...(foe ? { siege: true } : {}), ...(sea ? { sea: { port: sea.port, hulls: sea.hulls, landing: sea.landing } } : {}) }];
      }
      save(meta, [...rest, { kind: "march", units: h.units, x: to.x, y: to.y, city: town?.id ?? null, since: world.turn, ...(foe ? { siege: true, house: foe.id } : {}), ...face,
        ...(sea ? { sea: { phase: "port", port: sea.port, hulls: sea.hulls, landing: sea.landing } } : {}) }]);
      if (sea) {
        const seasons = Math.max(1, Math.ceil(sea.walk / HOSTS.speed) + Math.ceil(sea.sail / sea.speed) + Math.ceil(sea.ashore / HOSTS.speed));
        return [200, { ok: true, text: `${name} marches to ${cityName(sea.port.id)}, takes ship and lands on the far shore${town ? ` for ${cityName(town.id)}` : ""}: about ${seasons === 1 ? "a season" : `${seasons} seasons`}${foe ? ", and lays siege when it reaches the walls" : ""}.`,
          ...(foe && !b.declared ? { declare: { city: town.id, house: foe.id } } : {}) }];
      }
      const seasons = Math.max(1, Math.ceil(road / HOSTS.speed));
      return [200, { ok: true, text: `${name} marches${town ? ` ${foe ? "on" : "for"} ${cityName(town.id)}` : ""}: ${seasons === 1 ? "a season" : `${seasons} seasons`} on the road${foe ? ", and lays siege when it reaches the walls" : ""}.`,
        ...(foe && !b.declared ? { declare: { city: town.id, house: foe.id } } : {}) }];
    }
    case "attack": {
      // The foe's men on the tile named or beside it: another house's, not sworn to the crown, nor the wild's.
      const at = { x: Math.round(Number(b.x)), y: Math.round(Number(b.y)) };
      if (!inside(at.x, at.y)) return [400, { error: "choose the foe's men on the map" }];
      const theirs = (world.units ?? []).filter((u) => u.owner !== crown?.id && !CIVILIAN.has(u.type) && cheb(u, at) <= 1)
        .filter((u) => { const p = world.players.find((q) => q.id === u.owner); return p && !houseFor(p).crown && !sworn?.(p.id); })
        .sort((u, v) => cheb(u, at) - cheb(v, at));
      const target = theirs[0];
      if (!target) return [400, { error: "No foe's men stand there for the royal host to fall on." }];
      const road = roadTo(h, target);
      if (road < 0) return [400, { error: "The royal host can find no road over land to them; the sea lies between." }];
      const who = houseFor(world.players.find((p) => p.id === target.owner) ?? {}).name ?? "the foe";
      save(meta, [...rest, { kind: "attack", units: h.units, x: target.x, y: target.y, target: target.id, house: target.owner, since: world.turn, ...face }]);
      const seasons = Math.max(1, Math.ceil(road / HOSTS.speed));
      return [200, { ok: true, text: `${name} marches to fall on ${who}'s men: ${seasons === 1 ? "a season" : `${seasons} seasons`} on the road.` }];
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
      const men = away.reduce((n, id) => n + menOf(world.units.find((u) => u.id === id) ?? {}), 0);
      return [200, { ok: true, text: `The host divides: ${men.toLocaleString("en-US")} men stand apart under their own captain.` }];
    }
  }
  return [400, { error: "no such order" }];
}

// The land as Freeciv wrote it for the reign (snapshot.lua's map.json): which tiles a host can walk.
let land = { file: null };
function landOf() {
  const file = path.join(chron.paths(chron.activeId()).state, "map.json");
  if (land.file !== file) {
    const m = chron.readJson(file);
    if (!m?.tiles) return null;
    const walk = new Uint8Array(m.width * m.height);
    const sea = new Uint8Array(m.width * m.height);  // 0 land, 1 coastal water (Ocean, Lake), 2 deep water
    for (const [x, y, n] of m.tiles) {
      walk[y * m.width + x] = /Ocean|Lake/.test(String(n)) ? 0 : 1;
      sea[y * m.width + x] = /Deep Ocean/.test(String(n)) ? 2 : /Ocean|Lake/.test(String(n)) ? 1 : 0;
    }
    land = { file, w: m.width, h: m.height, walk, sea };
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
function wayOn(steps, from, n, stop = 0) {
  const out = [];
  let p = { x: from.x, y: from.y }, here = steps.at(p);
  if (here < 0) return out;
  while (out.length < n && here > stop) {
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

// The eight tiles round (x, y) on the map.
function round(L, x, y) {
  const out = [];
  for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
    const nx = x + dx, ny = y + dy;
    if ((dx || dy) && nx >= 0 && ny >= 0 && nx < L.w && ny < L.h) out.push([nx, ny]);
  }
  return out;
}
const sails = (L, x, y, deep) => L.sea[y * L.w + x] === 1 || (deep && L.sea[y * L.w + x] === 2);

// A sea road for hulls (deep: they may cross deep water) from any of the tiles `from` to any of `to`: the tiles in
// order, its first a start, or null.
function seaRoad(L, from, to, deep) {
  const goal = new Set(to.map(([x, y]) => y * L.w + x));
  const prev = new Int32Array(L.w * L.h).fill(-2);
  const q = from.map(([x, y]) => y * L.w + x);
  for (const k of q) prev[k] = -1;
  for (let i = 0; i < q.length; i++) {
    if (goal.has(q[i])) {
      const out = [];
      for (let k = q[i]; k >= 0; k = prev[k]) out.unshift([k % L.w, (k / L.w) | 0]);
      return out;
    }
    for (const [nx, ny] of round(L, q[i] % L.w, (q[i] / L.w) | 0)) {
      const k = ny * L.w + nx;
      if (prev[k] === -2 && sails(L, nx, ny, deep)) { prev[k] = q[i]; q.push(k); }
    }
  }
  return null;
}

// How a host crosses the water to `to` (Mac: "ships are just to move armies from one point to another"): it walks to
// the nearest town the crown holds on the water that it can reach over land, takes ship there in the crown's hulls
// standing free in or beside it (enough room for every company: the ruleset's transport_cap), sails the sea road to
// the shore nearest the goal (a Trireme keeps to coastal water), lands, and marches on. {port, hulls, landing, walk,
// sail, ashore, speed} or {error: the reason, for the card}.
function crossing(ctx, h, to) {
  const { world, meta } = ctx;
  const L = landOf();
  const crown = crownOf(world);
  const toSteps = stepsTo(to);
  if (!L || !toSteps) return { error: "Choose a place on the land for the royal host." };
  const busy = new Set((meta.hostOrders ?? []).flatMap((o) => [...o.units, ...(o.sea?.hulls ?? [])]));
  const free = (world.units ?? []).filter((u) => u.owner === crown?.id && HULLS[u.type] && !busy.has(u.id));
  const ports = (world.cities ?? []).filter((c) => c.owner === crown?.id && round(L, c.x, c.y).some(([x, y]) => L.sea[y * L.w + x]))
    .map((c) => ({ c, walk: stepsTo(c)?.at(h) ?? -1 })).filter((p) => p.walk >= 0).sort((a, b) => a.walk - b.walk);
  if (!ports.length) return { error: "The crown holds no port the royal host can reach to take ship." };
  const shores = [];
  for (let y = 0; y < L.h; y++) for (let x = 0; x < L.w; x++) {
    const ashore = toSteps.at({ x, y });
    if (ashore >= 0 && round(L, x, y).some(([a, b]) => L.sea[b * L.w + a])) shores.push({ x, y, ashore });
  }
  shores.sort((a, b) => a.ashore - b.ashore);
  let why = "";
  for (const p of ports) {
    const at = free.filter((u) => cheb(u, p.c) <= 1).sort((a, b) => HULLS[b.type].carry - HULLS[a.type].carry);
    const take = [];
    let room = 0;
    for (const u of at) if (room < h.units.length) { take.push(u); room += HULLS[u.type].carry; }
    if (room < h.units.length) {
      why ||= `No ship lies free at ${cityName(p.c.id)} for the royal host: room for ${room} of its ${h.units.length} companies.`;
      continue;
    }
    const deep = take.every((u) => HULLS[u.type].deep);
    const from = round(L, p.c.x, p.c.y).filter(([x, y]) => sails(L, x, y, deep));
    for (const s of shores.slice(0, 60)) {
      const road = seaRoad(L, from, round(L, s.x, s.y).filter(([x, y]) => sails(L, x, y, deep)), deep);
      if (road) return { port: { id: p.c.id, x: p.c.x, y: p.c.y }, hulls: take.map((u) => u.id), landing: { x: s.x, y: s.y }, walk: p.walk, sail: road.length, ashore: s.ashore, speed: Math.min(...take.map((u) => HULLS[u.type].speed)) };
    }
    why ||= `No sea road from ${cityName(p.c.id)} reaches a shore near the goal${deep ? "" : " for a coastal ship"}.`;
  }
  return { error: why };
}

// A house's men sent home by a decree (crown.js buyoff, settle, peace, cede): one order, walked each season
// like the King's hosts, to the house's seat, where they disband into its work (lua.js disbandHome). Held from
// their house's AI meanwhile, so the march is Freeciv's moves and nothing vanishes. units: their ids.
export function homeward(ctx, { owner, units }, send) {
  const { world, meta } = ctx;
  const seat = world?.cities?.find((c) => c.owner === owner && c.capital) ?? world?.cities?.find((c) => c.owner === owner);
  const ids = (units ?? []).filter((id) => (world?.units ?? []).some((u) => u.id === id && u.owner === owner));
  if (!seat || !ids.length) return;
  send(`lua cmd ${Lua.homewardHold(ids)}`);
  save(meta, [...(meta.hostOrders ?? []).filter((o) => !o.units.some((id) => ids.includes(id))), { kind: "homeward", owner, units: ids, x: seat.x, y: seat.y, city: seat.id }]);
}

// Each season (season.js): every host under a marching order moves; one that has arrived stands
// (a march becomes a hold; a garrison stays a garrison, in the town).
export function season(ctx, turn) {
  const { world, meta, send, record, besiege } = ctx;
  if (!world) return;
  // A host under the King's order is the King's, not Freeciv's AI's: the crown is AI-marshalled (realm.serv), and
  // the AI walked the King's men off the walls between seasons (and a marching host a tile off its road the season
  // it arrived), so no assault came and the siege broke (realm/tools/capture_chain_probe.sh). A host marching or
  // garrisoning, or holding before walls it besieges, is held from the AI (realm_hold, as the homeward men are),
  // let go only for its own steps; freed the season its order ends (a plain hold, at ease) or its siege does.
  const besieging = new Set((meta.campaigns ?? []).map((k) => k.city));
  for (const o of meta.hostOrders ?? []) if (o.siege != null && o.kind === "hold" && !besieging.has(o.siege)) delete o.siege;
  const keep = (orders) => orders.filter((o) => o.kind === "march" || o.kind === "garrison" || (o.kind === "hold" && o.siege != null)).flatMap((o) => o.units);
  const freed = (meta.hostsHeld ?? []).filter((id) => !keep(meta.hostOrders ?? []).includes(id));
  if (freed.length) send(`lua cmd ${Lua.homewardRelease(freed)}`);
  meta.hostsHeld = (meta.hostsHeld ?? []).filter((id) => !freed.includes(id));
  if (!(meta.hostOrders ?? []).length) { if (freed.length) chron.saveMeta(meta); return; }
  const crown = crownOf(world);
  const next = [];
  for (const o of meta.hostOrders) {
    // The King's hosts, or (homeward) a house's men going home: each walks among its own side's men.
    const side = o.owner ?? crown?.id;
    const byId = new Map(soldiersOf(world, side).map((u) => [u.id, u]));
    const shut = new Set([...(world.cities ?? []), ...(world.units ?? [])].filter((x) => x.owner !== side).map((x) => `${x.x},${x.y}`));
    const units = o.units.filter((id) => byId.has(id));
    if (!units.length) continue;  // the host is no more
    if (o.kind === "homeward") {
      const seat = world.cities.find((c) => c.id === o.city && c.owner === o.owner);
      // Home (or the seat lost): the men disband into its work, or stand where they are, free again.
      if (!seat || units.every((id) => cheb(byId.get(id), o) === 0)) {
        if (seat) for (const id of units) send(`lua cmd ${Lua.disbandHome(id, seat.id)}`);
        else send(`lua cmd ${Lua.homewardRelease(units)}`);
        continue;
      }
      const steps = stepsTo(o, new Set([...shut].filter((k) => k !== `${o.x},${o.y}`))) ?? stepsTo(o);
      const far = units.reduce((t, id) => t + (steps && steps.at(byId.get(id)) >= 0 ? steps.at(byId.get(id)) : cheb(byId.get(id), o)), 0);
      if (o.far != null && far >= o.far) {  // no nearer: they stay where they are, free again
        send(`lua cmd ${Lua.homewardRelease(units)}`);
        continue;
      }
      for (const id of units) send(`lua cmd ${Lua.homewardStep(id, steps ? wayOn(steps, byId.get(id), HOSTS.speed) : [])}`);
      next.push({ ...o, units, far });
      continue;
    }
    if (o.x == null) { next.push({ ...o, units }); continue; }
    if (o.kind === "attack") {
      // The foe's men are followed where they go; gone (fallen, or home behind walls), the host stands.
      const foe = (world.units ?? []).find((u) => u.id === o.target);
      if (!foe) {
        record?.({ turn, kind: "decree", text: "The foe the royal host marched on is gone from the field; the host makes camp." });
        next.push({ kind: "hold", units, since: turn, ...(o.face != null ? { face: o.face } : {}) });
        continue;
      }
      o.x = foe.x;
      o.y = foe.y;
      const beside = units.filter((id) => cheb(byId.get(id), foe) === 1);
      if (beside.length) send(`lua cmd ${Lua.strike(beside, foe.x, foe.y)}`);  // from beside them, each strikes once
      if (beside.length === units.length) { next.push({ ...o, units, far: null }); continue; }
    }
    // Over the water (crossing): to the port, aboard, at sea, ashore; then the march goes on to its goal. The hulls are
    // the King's while they carry his host: held from Freeciv's AI (realm_hold) and let go only for their own sailing,
    // freed when the host is ashore.
    if (o.sea && o.sea.phase !== "landed") {
      const sea = o.sea;
      const L = landOf();
      const hulls = sea.hulls.map((id) => (world.units ?? []).find((u) => u.id === id && u.owner === crown?.id)).filter(Boolean);
      if (!L || hulls.length < sea.hulls.length) {
        record?.({ turn, kind: "decree", text: "The ships meant for the royal host are lost; the host makes camp." });
        if (hulls.length) send(`lua cmd ${Lua.homewardRelease(hulls.map((u) => u.id))}`);
        next.push({ kind: "hold", units, since: turn });
        continue;
      }
      const held = new Set([...(meta.hostsHeld ?? []), ...(meta.siegeHeld ?? [])]);
      const go = (way) => {  // a step of the King's own, let go from any hold for it
        const ids = way.filter(([, w]) => w.length).map(([id]) => id);
        if (ids.length) send(`lua cmd ${Lua.homewardRelease(ids)}`);
        for (const [id, w] of way) if (w.length) send(`lua cmd ${Lua.walk(id, w)}`);
        const back = ids.filter((id) => held.has(id) || sea.hulls.includes(id));
        if (back.length) send(`lua cmd ${Lua.homewardHold(back)}`);
      };
      if (sea.phase === "port") {
        send(`lua cmd ${Lua.homewardHold(sea.hulls)}`);  // the hulls wait in port for the host
        if (units.every((id) => cheb(byId.get(id), sea.port) === 0)) {
          send(`lua cmd ${Lua.ferryBoard(units, sea.hulls)}`);
          record?.({ turn, kind: "decree", text: `The royal host takes ship at ${cityName(sea.port.id)}.`, city: sea.port.id });
          next.push({ ...o, units, sea: { ...sea, phase: "sail" } });
          continue;
        }
        const steps = stepsTo(sea.port, new Set([...shut].filter((k) => k !== `${sea.port.x},${sea.port.y}`))) ?? stepsTo(sea.port);
        go(units.map((id) => [id, steps ? wayOn(steps, byId.get(id), HOSTS.speed) : []]));
        next.push({ ...o, units });
        continue;
      }
      // At sea: the hulls (and the host in them) sail toward the water beside the landing; there, the host comes ashore.
      const deep = hulls.every((u) => HULLS[u.type]?.deep);
      const beside = round(L, sea.landing.x, sea.landing.y).filter(([x, y]) => sails(L, x, y, deep));
      const near = new Set(beside.map(([x, y]) => `${x},${y}`));
      if (hulls.every((u) => near.has(`${u.x},${u.y}`))) {
        send(`lua cmd ${Lua.ferryLand(units, sea.landing.x, sea.landing.y)}`);
        send(`lua cmd ${Lua.homewardRelease(sea.hulls)}`);  // the ships are free again
        record?.({ turn, kind: "decree", text: `The royal host comes ashore${o.city != null ? ` on the road to ${cityName(o.city)}` : ""}.`, city: o.city ?? undefined });
        next.push({ ...o, units, far: null, sea: { ...sea, phase: "landed" } });
        continue;
      }
      go(hulls.map((u) => [u.id, (seaRoad(L, [[u.x, u.y]], beside, deep) ?? []).slice(1, 1 + (HULLS[u.type]?.speed ?? 1))]));
      next.push({ ...o, units });
      continue;
    }
    // There: on the place, or before the walls of a town that isn't the crown's (a march halts at another's gates).
    const goal = o.city != null ? world.cities.find((c) => c.id === o.city) : null;
    const reach0 = (goal && goal.owner !== crown?.id && o.kind === "march") || o.kind === "attack" ? 1 : 0;
    const there = units.every((id) => cheb(byId.get(id), o) <= reach0);
    if (there) {
      // At the walls of a town it marched on: the siege begins (campaigns.js) on whoever holds it now (the town
      // may have changed hands on the road: a rising, a war), if that is still a foe, and the host holds before them.
      const holder = goal && o.siege ? world.players.find((p) => p.id === goal.owner) : null;
      if (holder && holder.id !== crown?.id && !sworn(ctx, holder.id) && !(meta.campaigns ?? []).some((k) => k.city === goal.id)) {
        record?.({ turn, kind: "decree", text: `The royal host reaches ${cityName(goal.id)} and lays siege.`, city: goal.id });
        besiege?.({ city: goal.id, house: holder.id });
        next.push({ kind: "hold", units, since: turn, siege: goal.id });
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
    if (o.far != null && far >= o.far && o.kind !== "attack") {  // (a foe followed may draw off a season; it isn't a wall)
      record?.({ turn, kind: "decree", text: `The royal host can go no nearer ${o.city != null ? cityName(o.city) : "the place the King named"}, and makes camp.`, city: o.city ?? undefined });
      next.push({ kind: "hold", units, since: turn });
      continue;
    }
    const pinned = units.filter((id) => meta.hostsHeld.includes(id));  // let go for their own steps, held again after
    if (pinned.length) send(`lua cmd ${Lua.homewardRelease(pinned)}`);
    for (const id of units) {
      // A march on another's town halts at its walls (reach0): the walk never steps onto the town's own tile, where
      // Freeciv's edit move would put the King's men inside an empty town without taking it (besiege_order_probe).
      const way = steps ? wayOn(steps, byId.get(id), HOSTS.speed, reach0) : [];
      send(`lua cmd ${way.length ? Lua.walk(id, way) : Lua.step(id, o.x, o.y, HOSTS.speed, reach0)}`);
    }
    if (pinned.length) send(`lua cmd ${Lua.homewardHold(pinned)}`);
    next.push({ ...o, units, far });
  }
  const held = keep(next).filter((id) => !meta.hostsHeld.includes(id));
  if (held.length) send(`lua cmd ${Lua.homewardHold(held)}`);
  meta.hostsHeld.push(...held);
  save(meta, next);
}
