// What a raid makes for (casebook, War and sieges: a raid on what the King built; Mount & Blade's raiders on a lord's
// village, Stronghold's raid on the granary). Freeciv decides it and walks the men (realmrules/script.lua raid_goal,
// from the King's works the bridge hands it each season, treasury.js royalWorks): its "raid_goal" event names the
// town a raid makes for. Kept here (meta.raidGoals, by the raid's town), the one owner, and given to /world as
// raids: [{town, goal, building, rising, x, y, units}] for the view to draw the men going at the work on its site.
import { worksOf } from "./treasury.js";
import { crownOf } from "./realm.js";

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
