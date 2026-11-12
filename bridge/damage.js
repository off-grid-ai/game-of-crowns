// The damage done to each town: a shared fact with one owner (the finesse catalogue). Its wall sections
// (0 whole .. 1 gone; section 0 faces north, then clockwise), each battered by the besiegers facing it
// until it cracks and breaches, mended season by season once the siege lifts (Stronghold, Total War);
// and the share of its houses burnt by a sack or a razing, rebuilt season by season (Manor Lords), and the houses a
// siege's fire arrows set alight (kindled: each house's stable id in its town, realm towns.gd home_id), rebuilt one a season.
// Read by /world (cities[].damage) for the view's cracks, breaches, burnt shells and rubble; the view
// decides nothing. Tunables: data/damage.json. Saved in the realm's meta (meta.damage).
import fs from "node:fs";
import * as chron from "./chronicles.js";
import * as Lua from "./lua.js";

export const DAMAGE = JSON.parse(fs.readFileSync(new URL("./data/damage.json", import.meta.url), "utf8"));

// Each season (season.js turn): sieges batter, the idle mend, sacks burn, the burnt rebuild.
export function season(ctx, turn) {
  const { world, meta } = ctx;
  if (!DAMAGE.on || !world?.cities) return;
  const all = (meta.damage ??= {});
  const marks = ctx.marksNow?.() ?? [];
  for (const c of world.cities) {
    const d = (all[c.id] ??= fresh());
    const near = ctx.besiegers?.(c) ?? [];
    if (near.length >= DAMAGE.besiegersToBatter) {
      for (const u of near) {
        const s = sectionFacing(c, u);
        d.walls[s] = Math.min(1, d.walls[s] + DAMAGE.perBesiegerSeason);
      }
    } else {
      d.walls = d.walls.map((w) => Math.max(0, w - DAMAGE.mendPerSeason));
    }
    const hit = marks.find((m) => (m.kind === "sack" || m.kind === "razed") && m.x === c.x && m.y === c.y && m.turn > d.heard);
    if (hit) {
      d.burnt = Math.min(1, d.burnt + (hit.kind === "razed" ? DAMAGE.burntOnRazed : DAMAGE.burntOnSack));
      d.heard = hit.turn;
    } else {
      d.burnt = Math.max(0, d.burnt - DAMAGE.rebuildPerSeason);
      d.kindled = (d.kindled ?? []).slice(DAMAGE.kindledRebuiltPerSeason);  // the first lit, the first rebuilt
    }
  }
  // A breach is Freeciv's too: a town with a wall section breached loses its City Walls (their defence
  // bonus with them). The house builds them again in its own time, as Freeciv's AI decides.
  for (const c of world.cities) {
    const d = all[c.id];
    if (d && (c.buildings ?? []).includes("City Walls") && d.walls.some((w) => stageOf(w) === "breached")) {
      ctx.send?.(`lua cmd ${Lua.building(c.id, "City Walls", false)}`);
    }
  }
  for (const id of Object.keys(all)) if (!world.cities.some((c) => c.id === Number(id))) delete all[id];
  chron.saveMeta(meta);
}

// What the view shows for a town: each wall section's stage and wear, and the share of houses burnt.
export function view(meta, c) {
  const d = meta?.damage?.[c.id];
  if (!d) return null;
  return { walls: d.walls.map((w) => ({ stage: stageOf(w), wear: Math.round(w * 100) / 100 })), burnt: Math.round(d.burnt * 100) / 100, kindled: d.kindled ?? [] };
}

// A siege's fire arrow set one of a town's houses alight (the view's fire.gd, as it lands): that house stands
// burnt from now on, through a reload, until the realm rebuilds it. `home` is the house's stable id in its town
// (realm towns.gd home_id: where it stands, "x_z" in decimetres), never its place in the view's laying order.
// Returns the town's damage, or null for no such town or no such id.
export function kindle(meta, world, city, home) {
  const c = world?.cities?.find((x) => x.id === Number(city));
  const h = String(home ?? "");
  if (!c || !/^-?\d+_-?\d+$/.test(h)) return null;
  const d = ((meta.damage ??= {})[c.id] ??= fresh());
  d.kindled ??= [];
  if (!d.kindled.includes(h)) {
    d.kindled.push(h);
    chron.saveMeta(meta);
  }
  return view(meta, c);
}

function fresh() {
  return { walls: Array(DAMAGE.sections).fill(0), burnt: 0, heard: -1, kindled: [] };
}

// A test reign's staged damage (routes_test): a section's wear, or a town's burnt share.
export function stage(meta, city, { section, wear, burnt }) {
  const d = ((meta.damage ??= {})[city] ??= fresh());
  if (section != null && wear != null) d.walls[Number(section) % DAMAGE.sections] = Math.max(0, Math.min(1, Number(wear)));
  if (burnt != null) d.burnt = Math.max(0, Math.min(1, Number(burnt)));
  chron.saveMeta(meta);
  return d;
}

function stageOf(w) {
  return w >= DAMAGE.breachedAt ? "breached" : w >= DAMAGE.crackedAt ? "cracked" : "whole";
}

// The section facing a unit from the town (map y grows south; section 0 faces north, clockwise).
function sectionFacing(c, u) {
  const a = Math.atan2(u.x - c.x, -(u.y - c.y));
  const n = DAMAGE.sections;
  return ((Math.round(a / ((2 * Math.PI) / n)) % n) + n) % n;
}
