// What came of the King's choices (Mac 2026-11-16: "maybe things are happening but it's not very evident to me"): an
// order comes back a few seasons later, by name, judged on what the realm is now (CK3's memories, Reigns' callbacks:
// "the lord you feasted still speaks of it"; "the town you fed starves again"). One owner, meta.aftermath, a list of
// {action, due, then: what stood when it was given}; each season (season.js) the ones due are read against the
// world and told as a chronicle line with the rows it moved (reckoning.js), so the view shows it like a choice's
// answer. Words and seasons: data/aftermath.json. Orders with their own telling (war, march) are not kept here.

import fs from "node:fs";
import { cityName, houseFor } from "./narrator.js";
import { favourWord } from "./favourbook.js";
import * as Reckoning from "./reckoning.js";
import * as chron from "./chronicles.js";

const A = JSON.parse(fs.readFileSync(new URL("./data/aftermath.json", import.meta.url), "utf8"));
const short = (world, pid) => houseFor(world.players.find((p) => p.id === pid) ?? {}).name?.replace(/^House /, "") ?? "";
const fill = (t, v) => String(t ?? "").replace(/\{(\w+)\}/g, (_, k) => v[k] ?? "");

// Keeps an order to come back to (routes_decree.js): `house` the house it touched, `other` the second house (peace:
// the other side; back: the winner), `city` its town.
export function keep(ctx, action, { house = null, other = null, city = null, building = null } = {}) {
  const spec = A.kinds[action];
  const { meta, world } = ctx;
  if (!spec || !world) return;
  const turn = world.turn ?? 0;
  const then = { favour: house != null ? Math.round(ctx.favourOf(house)) : null };
  (meta.aftermath ??= []).push({ action, due: turn + (spec.after ?? A.after), since: turn, house, other, city, building, then });
  chron.saveMeta(meta);
}

// Each season: the orders due are told, good or bad, by what the realm is now.
export function season(ctx, turn) {
  const { meta, world } = ctx;
  if (!world || !meta.aftermath?.length) return;
  const due = meta.aftermath.filter((x) => x.due <= turn);
  if (!due.length) return;
  meta.aftermath = meta.aftermath.filter((x) => x.due > turn);
  for (const x of due) {
    const told = judge(ctx, x);
    if (told) ctx.record({ turn, kind: "aftermath", text: told.text, city: x.city ?? undefined, changes: told.rows });
  }
  chron.saveMeta(meta);
}

// One order read against the world: {text, rows} or null when there is nothing to tell (the town is gone).
function judge(ctx, x) {
  const { world } = ctx;
  const spec = A.kinds[x.action];
  const town = x.city != null ? world.cities.find((c) => c.id === x.city) : null;
  const v = { town: x.city != null ? cityName(x.city) : "", house: x.house != null ? short(world, x.house) : "", other: x.other != null ? short(world, x.other) : "", seasons: String((world.turn ?? 0) - x.since), building: String(x.building ?? "").replace(/_/g, " ") };
  const rows = [];
  let good;
  if (spec.test === "favour") {
    // A kindness: does the house still feel it?
    const now = Math.round(ctx.favourOf(x.house));
    good = now >= (x.then.favour ?? now) - A.cooled;
    if (now !== x.then.favour) rows.push({ house: v.house, from: x.then.favour, to: now, word: favourWord(now - x.then.favour) });
  } else if (spec.test === "grudge") {
    // A town judged away: the loser remembers.
    const now = Math.round(ctx.favourOf(x.house));
    good = now >= A.forgiven;
    rows.push({ house: v.house, from: x.then.favour, to: now, word: good ? "has let it go" : "remembers" });
  } else if (spec.test === "fed") {
    if (!town) return null;
    good = !(town.famine || town.granaryLow);
  } else if (spec.test === "stands") {
    if (!town) return null;
    good = town.owner === x.house;  // the town the crown built in is still held by the house it was built for
    v.holder = short(world, town.owner);
  } else if (spec.test === "peace") {
    const atWar = ctx.detail?.()?.players?.[x.house]?.atWarWith?.includes(x.other);
    good = !atWar;
  } else return null;
  return { text: fill(good ? spec.good : spec.bad, v), rows: Reckoning.of({ favour: rows }) };
}
