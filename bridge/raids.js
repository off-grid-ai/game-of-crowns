// What a raid makes for (casebook, War and sieges: a raid on what the King built; Mount & Blade's raiders on a lord's
// village, Stronghold's raid on the granary). Freeciv decides it and walks the men (realmrules/script.lua raid_goal,
// from the King's works the bridge hands it each season, treasury.js royalWorks): its "raid_goal" event names the
// town a raid makes for. Kept here (meta.raidGoals, by the raid's town), the one owner, and given to /world as
// raids: [{town, goal, building, rising, x, y, units}] for the view to draw the men going at the work on its site.
import fs from "node:fs";
import { worksOf } from "./treasury.js";
import { crownOf } from "./realm.js";
import { houseFor, cityName } from "./narrator.js";
import * as Lua from "./lua.js";
import * as Opening from "./opening.js";

const RAIDS = JSON.parse(fs.readFileSync(new URL("./data/raids.json", import.meta.url), "utf8"));

export function goal(meta, ev) {
  const town = Number(ev.city), to = Number(ev.goal);
  const units = String(ev.units ?? "").split(",").filter(Boolean).map(Number);
  meta.raidGoals ??= {};
  if (!to || !units.length) delete meta.raidGoals[town];
  else meta.raidGoals[town] = { goal: to, units, turn: Number(ev.turn) };
}

export function list(meta, world) {
  const alive = new Set((world?.units ?? []).map((u) => u.id));
  const works = worksOf(meta, world, crownOf(world)?.id);
  return Object.entries(meta?.raidGoals ?? {}).map(([town, r]) => {
    const units = r.units.filter((id) => alive.has(id));
    const c = world?.cities?.find((x) => x.id === r.goal);
    const w = works.find((x) => x.city === r.goal);
    return units.length && c && w ? { town: Number(town), goal: r.goal, building: w.building, rising: w.rising, x: c.x, y: c.y, units } : null;
  }).filter(Boolean);
}

// The reign's first raid (data/raids.json first): a few seconds of the reign's clock in, men without banners rise
// beside the town nearest Kingsmere and burn its land, so the King has a foe for his host from the first minute; when
// his host has beaten them, a reward. One owner: meta.firstRaid {city, turn, units, done}. Called by the bridge's clock.
export function first(ctx) {
  const { meta, world, send, record } = ctx;
  const F = RAIDS.first;
  if (!F || !world?.cities?.length || meta?.status !== "running" || meta.firstRaid?.done) return;
  const crown = crownOf(world);
  if (!crown) return;
  const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
  const wild = (u) => houseFor(world.players.find((p) => p.id === u.owner) ?? {}).wild;
  if (!meta.firstRaid) {
    if ((meta.elapsedMs ?? 0) < F.afterS * 1000 || !Opening.may(meta, "raiders")) return;  // the calm opening: raiders come first, alone (opening.js)
    const seat = world.cities.find((c) => c.owner === crown.id && c.capital);
    if (!seat) return;
    const town = world.cities.filter((c) => c.id !== seat.id && cheb(c, seat) <= F.near && !wild(c))
      .sort((a, b) => (b.owner === crown.id) - (a.owner === crown.id) || cheb(a, seat) - cheb(b, seat))[0];
    if (!town) { meta.firstRaid = { done: true }; return; }
    meta.firstRaid = { city: town.id, turn: world.turn, units: [] };
    send(`lua cmd ${Lua.raid(town.id)}`);
    Opening.began(meta, "raiders", "firstRaid");
    record({ turn: world.turn, kind: "raid", city: town.id, text: `Raiders are burning the fields of ${cityName(town.id)}, a short march from Kingsmere. Send the royal host.` });
    return;
  }
  const r = meta.firstRaid;
  const town = world.cities.find((c) => c.id === r.city);
  if (!town) { r.done = true; return; }
  const near = (world.units ?? []).filter((u) => cheb(u, town) <= F.reach);
  const theirs = near.filter(wild).map((u) => u.id);
  for (const id of theirs) if (!r.units.includes(id)) r.units.push(id);
  if (!r.units.length || theirs.length) return;  // not risen yet, or still burning
  r.done = true;
  if (near.some((u) => u.owner === crown.id)) {
    send(`lua cmd ${Lua.gold(crown.id, F.reward)}`);
    record({ turn: world.turn, kind: "battle", city: town.id, text: `The royal host has driven the raiders from ${cityName(town.id)}. Its people bring the King what the raiders left: ${F.reward} gold.` });
  } else {
    record({ turn: world.turn, kind: "raid", city: town.id, text: `The raiders have gone from ${cityName(town.id)} with their plunder, and no royal host came.` });
  }
}
