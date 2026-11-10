// Test hooks (films and proofs only): each answers only for a reign named as a test,
// and only with the X-Test header.
// Moved verbatim from server.js's ROUTES table (consolidation C3, step 8): each
// handler is (ctx, req, res, url). Nothing here reads server.js: the bridge's
// state and helpers come in as one context argument (routeCtx), built fresh by
// server.js on each request; the realm's state is read through it (ctx.world,
// ctx.meta...) at the moment it is used, as the handlers read it before, so a
// snapshot or a switch of chronicle during an await is seen.

import fs from "node:fs";
import path from "node:path";
import { CIVILIAN } from "./campaigns.js";
import * as Realm from "./realm.js";
import * as kingDeeds from "./ledger.js";
import { body, json } from "./http_util.js";

// Test hook (films only): the court sits now ({sit: true}), as a season's sitting does,
// so a film can stage what happens behind the court's card (a truce's reload).
export async function sit(ctx, req, res, url) {
  const { courtSeason } = ctx;
  if (req.headers["x-test"] !== "1" || !/test|film|check|proof/i.test(String(ctx.meta?.name ?? ""))) return json(res, 403, { error: "test reigns only" });
  const b = await body(req);
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
