// How every choice of the King is settled: an order (routes_decree.js), a ruling at court (court.js rule) and an
// answer to an event (events.js answer) alike (Mac 2026-11-16: "ensure SSOT, SRP, SOLID, OOP, DRY so that these kinds
// of mistakes don't happen"; each path settled favour its own way, so an order's rival was jealous and a ruling's was
// not, an order showed what it changed and an event didn't). One owner of the rules a choice passes through:
//   weigh   the favour it moves, as the realm takes it: kindness wears thin (favourbook temper), the warmed house's
//           rival is jealous (rivalry.js), help sent into another house's lands is meddling (meddling.js). The same
//           numbers before the choice (the forecast on its button) and after.
//   before  what stood before it (the treasury, the alarm, the town's lord), for the reckoning.
//   settle  the favour shifted and told, the order kept to come back later (aftermath.js), and the rows of what it
//           changed (reckoning.js): {text, moves, changes}.

import { crownOf } from "./realm.js";
import { cityName, houseFor } from "./narrator.js";
import * as Rivalry from "./rivalry.js";
import * as Meddling from "./meddling.js";
import * as Reckoning from "./reckoning.js";
import * as Aftermath from "./aftermath.js";

const ownerOf = (ctx, city) => (city != null ? ctx.world.cities.find((c) => c.id === Number(city))?.owner ?? null : null);
const short = (ctx, pid) => houseFor(ctx.world.players.find((p) => p.id === Number(pid)) ?? {}).name?.replace(/^House /, "") ?? "";

// The favour a choice moves, as the realm takes it ({pid: delta}). `dry`: a forecast, nothing remembered.
export function weigh(ctx, { action = null, city = null, house = null, favour = {} } = {}, dry = false) {
  const warmed = ownerOf(ctx, city) ?? (house != null ? Number(house) : null);
  let f = action && ctx.temper ? ctx.temper(action, warmed, favour ?? {}, dry) : { ...(favour ?? {}) };
  f = Rivalry.jealous(ctx, f);
  return action ? Meddling.apply(ctx, action, city, f) : f;
}

// What stood before a choice.
export function before(ctx, city = null) {
  return { gold: crownOf(ctx.world)?.gold ?? 0, alarm: ctx.meta.alarm ?? 0, owner: ownerOf(ctx, city) };
}

// A choice settled: its favour (already weighed) shifted and told, kept to come back, and what it changed. The
// treasury row reads the crown's purse now against before, so whatever the choice paid or earned is what it shows.
// c: {action, city, to, building, favour, why, cost, war (the house it made war on)}; was: before(ctx, city).
export function settle(ctx, was, c) {
  const told = ctx.shiftAndTell(c.favour ?? {}, c.why ?? "the King's choice", c.cost ?? 0);
  if (c.action) {
    const touched = c.action === "back" ? was.owner : ownerOf(ctx, c.city) ?? (c.house != null ? Number(c.house) : null);
    Aftermath.keep(ctx, c.action, c.action === "back" ? { house: was.owner, other: Number(c.to), city: Number(c.city) }
      : { house: touched, other: c.to != null ? Number(c.to) : null, city: c.city != null ? Number(c.city) : null, building: c.building ?? null });
  }
  const handed = ["back", "grant", "cede"].includes(c.action) && c.city != null && was.owner != null && c.to != null && Number(c.to) !== was.owner;
  const changes = Reckoning.of({ favour: told.moves, gold: [was.gold, crownOf(ctx.world)?.gold ?? was.gold], alarm: [was.alarm, ctx.meta.alarm ?? 0],
    towns: handed ? [{ town: cityName(Number(c.city)), from: short(ctx, was.owner), to: short(ctx, c.to) }] : [], war: c.war != null ? short(ctx, c.war) : null });
  return { text: told.text, moves: told.moves, changes };
}
