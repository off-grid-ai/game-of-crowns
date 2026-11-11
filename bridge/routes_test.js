// Test hooks (films and proofs only): each answers only for a reign named as a test,
// and only with the X-Test header.
// Moved verbatim from server.js's ROUTES table (consolidation C3, step 8): each
// handler is (ctx, req, res, url). Nothing here reads server.js: the bridge's
// state and helpers come in as one context argument (routeCtx), built fresh by
// server.js on each request; the realm's state is read through it (ctx.world,
// ctx.meta...) at the moment it is used, as the handlers read it before, so a
// snapshot or a switch of chronicle during an await is seen.

import * as Damage from "./damage.js";
import * as Director from "./director.js";
import * as Events from "./events.js";
import * as Lua from "./lua.js";
import { houseFor } from "./narrator.js";
import * as chron from "./chronicles.js";
import fs from "node:fs";
import path from "node:path";
import { CIVILIAN } from "./campaigns.js";
import * as Realm from "./realm.js";
import * as kingDeeds from "./ledger.js";
import { body, json } from "./http_util.js";

// Test hook (films only): the court sits now ({sit: true}), as a season's sitting does,
// so a film can stage what happens behind the court's card (a truce's reload).
// Test hook (films and proofs only): the court sits now ({sit: true}), or a card is dealt ({card}).
export async function sit(ctx, req, res, url) {
  const { courtSeason } = ctx;
  if (req.headers["x-test"] !== "1" || !/test|film|check|proof/i.test(String(ctx.meta?.name ?? ""))) return json(res, 403, { error: "test reigns only" });
  const b = await body(req);
  // {card: "<id>"} deals that card of the deck (data/dilemmas.json) now, from the
  // first lord its gates allow (its treasury gate counted as met), and the court sits for it.
  if (b.card) {
    const world = ctx.world;
    const court = ctx.court;
    const lords = court.alive().filter((c) => c.rank === "lord" && (world.players.find((p) => p.id === c.playerId)?.cities ?? 0) > 0)
      .sort((x, y) => (world.players.find((p) => p.id === y.playerId)?.gold ?? 0) - (world.players.find((p) => p.id === x.playerId)?.gold ?? 0));
    let dealt = null;
    for (const lord of lords) {
      dealt = await court.petition(lord, world, world.turn ?? 0, { favour: ctx.favourOf, thinTreasury: () => true, wetHarvest: () => true }, true, { prefer: String(b.card), urgent: true });
      if (dealt) break;
    }
    if (!dealt) return json(res, 400, { error: `no lord can be dealt ${b.card} now` });
    dealt.called = ctx.world.turn ?? 0;
    court.saveCourt();
    await courtSeason(ctx.world?.turn ?? 0, true);
    return json(res, 200, { ok: true, id: dealt.id, from: dealt.name, options: dealt.options.map((o) => o.id) });
  }
  if (!b.sit) return json(res, 400, { error: "{sit: true}" });
  await courtSeason(ctx.world?.turn ?? 0, true);
  return json(res, 200, { ok: true, sitting: ctx.meta.court?.sitting ?? null });
}

// Test hook (films only): stage what a town is making (a building site, a
// unit in training), so a film is certain to find a site or a drill there.
export async function stage(ctx, req, res, url) {
  const { scene } = ctx;
  if (req.headers["x-test"] !== "1" || !/test|film|check|proof/i.test(String(ctx.meta?.name ?? ""))) return json(res, 403, { error: "test reigns only" });
  const b = await body(req);
  // {city, building, kind, progress} stages its work; {city, mood} its mood:
  // riot, feast, hunger, war, peace, prosperity, grief, grasping, calm; {city, mood: "king"} sends the King's banner through it.
  const moods = { riot: { disorder: true }, feast: { celebrating: true }, hunger: { famine: true }, war: { atWar: true }, peace: { atWar: false },
    prosperity: { prosperity: true }, grief: { grief: true }, grasping: { grasping: true },
    calm: { disorder: false, celebrating: false, famine: false, atWar: false, grief: false, grasping: false, prosperity: false } };
  const at = (ctx.meta.stage ??= {});
  // {soldiers: wounded|fortified|calm, city}: the crown's three companies nearest the town stand so.
  // {intrigue: [{kind: envoy|pact|marriage, from, to (house ids), secret?, line?}]}: houses' schemes as the map
  // shows them, until builder 1's own intrigue lands (it merges these in); [] clears them.
  if (Array.isArray(b.intrigue)) {
    const seat = (pid) => ctx.world.cities.find((c) => c.owner === Number(pid) && c.capital) ?? ctx.world.cities.find((c) => c.owner === Number(pid));
    const name = (pid) => houseFor(ctx.world.players.find((p) => p.id === Number(pid)) ?? {}).name ?? "A house";
    (ctx.meta.stage ??= {}).intrigue = b.intrigue.map((x, i) => {
      const a = seat(x.from), z = seat(x.to);
      const says = { envoy: `${name(x.from)}'s envoy rides to ${name(x.to)}: a pact against the crown?`, pact: `${name(x.from)} and ${name(x.to)} have sworn something in secret`, marriage: `${name(x.from)} and ${name(x.to)} are joined by marriage` };
      return { id: `stage-${i}-${x.kind}`, kind: x.kind, from: Number(x.from), to: Number(x.to), x: a?.x, y: a?.y, tx: z?.x, ty: z?.y, since: ctx.world.turn ?? 0, secret: !!x.secret, line: x.line ?? says[x.kind] ?? "", matter: null };
    });
    chron.saveMeta(ctx.meta);
    return json(res, 200, { ok: true, intrigue: ctx.meta.stage.intrigue });
  }
  // {crown: <city id>}: that town passes to the crown through Freeciv (as a town is taken or
  // granted in play), so a film can have two royal towns, one of them starving ({city, mood: "hunger"}).
  if (b.crown != null) {
    const town = ctx.world.cities.find((c) => c.id === Number(b.crown));
    const crown = ctx.world.players.find((p) => houseFor(p).crown);
    if (!town || !crown) return json(res, 400, { error: "{crown: <city id>} of a town that stands" });
    ctx.send(`lua cmd ${Lua.transferCity(town.id, crown.id)}`);
    setTimeout(ctx.snapshot ?? (() => {}), 1500);
    return json(res, 200, { ok: true, city: town.id, to: crown.id });
  }
  // {event: "draw" | "lapse"}: an event card drawn now (past the opening's quiet), or the one up lapses (events.js).
  if (b.event) {
    const e = Events.testNow({ meta: ctx.meta, world: ctx.world, court: ctx.court, detail: ctx.detail, send: ctx.send, record: ctx.record,
      shiftFavour: (c, why) => ctx.shiftAndTell(c, why), favourOf: ctx.favourOf, history: ctx.history }, String(b.event));
    return json(res, 200, { ok: true, up: e.up, lapsed: e.lapsed });
  }
  // {favour: {<house id>: value}}: a house's favour set to that value, through the one favour writer.
  if (b.favour && typeof b.favour === "object") {
    const moves = Object.fromEntries(Object.entries(b.favour).map(([pid, v]) => [pid, Number(v) - (ctx.favourOf(Number(pid)) ?? 50)]));
    ctx.shiftAndTell(moves, "a test's staging");
    return json(res, 200, { ok: true, favour: Object.fromEntries(Object.keys(b.favour).map((pid) => [pid, ctx.favourOf(Number(pid))])) });
  }
  // {ultimatum: <house id>}: the house sends the crown its ultimatum now, as season.js askUltimatum does.
  if (b.ultimatum != null) {
    const pid = Number(b.ultimatum);
    const t = ((ctx.meta.turning ??= {})[pid] ??= { seasons: 2, state: null });
    Object.assign(t, { state: "sent", at: ctx.world?.turn ?? 0 });
    const hp = ctx.world?.players?.find((p) => p.id === pid);
    if (hp) ctx.record({ turn: t.at, kind: "unrest", text: `${houseFor(hp).name} sends a rider to Kingsmere with an ultimatum for the King.` });  // as askUltimatum tells it
    chron.saveMeta(ctx.meta);
    ctx.counselStale = true;
    return json(res, 200, { ok: true, turning: t });
  }
  // {sack: city} or {razed: city}: that town's sack (or razing) plays now, as the director's own does
  // (director.js: scene "sack" at the town), so a film can shoot a stormed town's aftermath on demand.
  for (const kind of ["sack", "razed"]) {
    if (b[kind] == null) continue;
    const c = (ctx.world?.cities ?? []).find((x) => x.id === Number(b[kind]));
    if (!c) return json(res, 404, { ok: false, error: "no such city" });
    ctx.scene(kind, { x: c.x, y: c.y, city: c.id, owner: c.owner });
    return json(res, 200, { ok: true, [kind]: c.id });
  }
  // {damage: {city, section, wear} or {city, burnt}}: a town's walls or houses damaged now (damage.js), for a film.
  if (b.damage) {
    const c = (ctx.world?.cities ?? []).find((x) => x.id === Number(b.damage.city));
    if (!c) return json(res, 404, { ok: false, error: "no such city" });
    return json(res, 200, { ok: true, damage: Damage.stage(ctx.meta, c.id, b.damage) });
  }
  // {threat: host|famine|pretender}: the director raises that threat now, at its place (director.js).
  if (b.threat) {
    const d = (ctx.meta.director ??= { calm: 0, rest: 0, threat: null, pushedAt: -99, curve: [] });
    d.threat = null;
    Director.raise({ world: ctx.world, meta: ctx.meta, send: ctx.send, record: ctx.record, scene: ctx.scene, favourOf: ctx.favourOf, shiftFavour: (c, why) => ctx.shiftAndTell(c, why), usurper: ctx.stakes?.s?.usurper?.stage ?? "none" }, d, ctx.world?.turn ?? 0, String(b.threat));
    chron.saveMeta(ctx.meta);
    ctx.counselStale = true;
    return json(res, d.threat ? 200 : 400, d.threat ?? { error: `no ${b.threat} can rise now` });
  }
  // {weather: clear|showers|rain|storm|snow}: the weather now, held through the seasons until staged again (weather.js).
  if (b.weather) {
    const kinds = ["clear", "showers", "rain", "storm", "snow"];
    if (!kinds.includes(String(b.weather))) return json(res, 400, { error: `weather: ${kinds.join(", ")}` });
    const prev = ctx.meta.weather;
    ctx.meta.weather = { turn: ctx.world?.turn ?? 0, season: prev?.season ?? "summer", kind: String(b.weather), wet: ["showers", "rain", "storm"].includes(String(b.weather)) ? Math.max(1, (prev?.wet ?? 0)) : 0, held: true };
    return json(res, 200, { ok: true, weather: ctx.meta.weather });
  }
  if (b.soldiers) {
    const c = ctx.world.cities.find((x) => x.id === Number(b.city));
    const crownId = Realm.crownOf(ctx.world)?.id;
    const near = c ? ctx.world.units.filter((u) => u.owner === crownId && !CIVILIAN.has(u.type)).sort((u, v) => Math.hypot(u.x - c.x, u.y - c.y) - Math.hypot(v.x - c.x, v.y - c.y)).slice(0, 3) : [];
    ctx.meta.stageUnits ??= {};
    for (const u of near) ctx.meta.stageUnits[u.id] = { wounded: { hp: 3 }, fortified: { activity: 4 } }[b.soldiers] ?? {};
    return json(res, 200, { ok: true, units: near.map((u) => u.id) });
  }
  if (b.mood === "king") {
    // {epithet}: the name the King has earned, for this test reign (the Good, the Cruel...).
    if (b.epithet) ctx.meta.testEpithet = String(b.epithet).slice(0, 24);
    const c = ctx.world.cities.find((x) => x.id === Number(b.city));
    const crownId = Realm.crownOf(ctx.world)?.id;
    if (c) scene("rider", { x: c.x - 2, y: c.y, tx: c.x + 2, ty: c.y, city: c.id, owner: crownId, label: "The King's banner" });
    return json(res, 200, { ok: true });
  }
  if (b.mood) at[Number(b.city)] = { ...(at[Number(b.city)] ?? {}), ...moods.calm, ...(moods[b.mood] ?? {}) };
  else at[Number(b.city)] = { ...(at[Number(b.city)] ?? {}), building: String(b.building ?? "Pikemen"), buildingKind: String(b.kind ?? "UnitType"), progress: Number(b.progress ?? 0.5) };
  return json(res, 200, { ok: true });
}

// Test hook (films only): a town gains a building now ({city, building}), so the site rising can be filmed.
export async function grow(ctx, req, res, url) {
  const { send } = ctx;
  if (req.headers["x-test"] !== "1" || !/test|film|check|proof/i.test(String(ctx.meta?.name ?? ""))) return json(res, 403, { error: "test reigns only" });
  const b = await body(req);
  const name = String(b.building ?? "Granary").replace(/[^A-Za-z ]/g, "");
  send(`lua cmd local c = find.city(nil, ${Number(b.city)}); local t = find.building_type("${name}"); if c and t and not c:has_building(t) then edit.create_building(c, t) end`);
  return json(res, 200, { ok: true });
}

// Test hook (films only): a lord's deed on demand, so its alert can be filmed.
// Answers only for a reign named as a test, and only with the X-Test header.
export async function noteDeed(ctx, req, res, url) {
  const { deed, kingName } = ctx;
  // A proof's deed, test reigns only: {kind: decree|court|deck|arc|realm, key, option, place}, as a ruling or decree would note it.
  if (req.headers["x-test"] !== "1" || !/test|film|check|proof/i.test(String(ctx.meta?.name ?? ""))) return json(res, 403, { error: "test reigns only" });
  const b = await body(req);
  const tag = kingDeeds.tagsFor(String(b.kind), String(b.key), b.option === undefined ? undefined : String(b.option));
  if (!tag) return json(res, 400, { error: "no such deed in data/ledger.json" });
  deed(tag, { place: String(b.place ?? ""), act: b.kind !== "realm" });
  return json(res, 200, { ok: true, ledger: ctx.meta.ledger, name: kingName() });
}

export async function mark(ctx, req, res, url) {
  const { marksNow, marks } = ctx;
  // A film's scar, test reigns only: {kind: battle|sack|razed, x, y, age: seasons ago}.
  if (req.headers["x-test"] !== "1" || !/test|film|check|proof/i.test(String(ctx.meta?.name ?? ""))) return json(res, 403, { error: "test reigns only" });
  const b = await body(req);
  if (!["battle", "sack", "razed"].includes(b.kind)) return json(res, 400, { error: "kind: battle, sack or razed" });
  const list = marksNow().filter((m) => !(m.kind === b.kind && m.x === Number(b.x) && m.y === Number(b.y)));
  list.push({ kind: b.kind, x: Number(b.x), y: Number(b.y), turn: Number(ctx.world?.turn ?? 0) - Number(b.age ?? 0) });
  fs.writeFileSync(path.join(ctx.P.state, "marks.json"), JSON.stringify((marks.list = list)));
  return json(res, 200, { ok: true, marks: marksNow() });
}

export async function news(ctx, req, res, url) {
  const { record, picture } = ctx;
  if (req.headers["x-test"] !== "1" || !/test|film|check|proof/i.test(String(ctx.meta?.name ?? ""))) return json(res, 403, { error: "test reigns only" });
  const b = await body(req);
  const e = { turn: ctx.world?.turn ?? 0, kind: String(b.kind ?? "betrayal"), text: String(b.text ?? "A test of the realm's news."), city: Number(b.city), to: b.to != null ? Number(b.to) : undefined, from: b.from != null ? Number(b.from) : undefined, with: b.with != null ? Number(b.with) : undefined };
  record(e);
  picture(e);
  return json(res, 200, { ok: true });
}

// Test hook (test reigns only): set the reign's clock, so a film can stage what
// the clock brings (an act's interlude at 0.25/0.5/0.75 of the reign, the final
// threat, the reign's end at 1). {at: 0..1}, the share of the reign gone, or
// {to: "act_end" | "reign_end"}; the
// next tick of the clock (reign.js, every 5 s while the realm runs) plays it.
export async function clock(ctx, req, res, url) {
  if (req.headers["x-test"] !== "1" || !/test|film|check|proof/i.test(String(ctx.meta?.name ?? ""))) return json(res, 403, { error: "test reigns only" });
  const b = await body(req);
  if (!(ctx.meta.minutes > 0)) return json(res, 400, { error: "this reign has no clock (endless)" });
  // {to: "act_end"}: just past the next quarter (that act's interlude); {to: "reign_end"}: its last tick.
  const gone = ctx.meta.elapsedMs / (ctx.meta.minutes * 60000);
  const at = b.to === "act_end" ? Math.min(0.76, (Math.floor(gone * 4) + 1) / 4 + 0.01) : b.to === "reign_end" ? 1 : Number(b.at);
  if (!(at >= 0 && at <= 1)) return json(res, 400, { error: "{at: 0..1}" });
  ctx.meta.elapsedMs = Math.min(ctx.meta.minutes * 60000 - 5000, Math.floor((at * ctx.meta.minutes * 60000) / 5000) * 5000);
  chron.saveMeta(ctx.meta);
  return json(res, 200, { ok: true, elapsedMs: ctx.meta.elapsedMs, minutes: ctx.meta.minutes });
}
