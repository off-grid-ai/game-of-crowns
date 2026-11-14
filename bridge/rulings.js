// A court ruling's answer, seen in the town where it lands: the one owner of "the King ruled
// here, and this is what came of it" (docs/review/decisions-in-the-world.md; CK3's feasts and
// granted titles, Manor Lords' market and building sites, Stronghold's gallows, Total War's
// recruitment). When the King gives a ruling (court.js rule), it is read once into one kind
// (data/rulings.json: relief, justice, levy, feast, build, grant) and kept with the reign at the
// town it touches (meta.rulings, so it survives a restart) for its seasons. The view only draws it
// (cities[].ruling in /world; realm town_life.gd and realm/data/moods.json).
import fs from "node:fs";
import * as chron from "./chronicles.js";
import { cityName } from "./narrator.js";

export const RULINGS = JSON.parse(fs.readFileSync(new URL("./data/rulings.json", import.meta.url), "utf8"));
export const KINDS = [...new Set(RULINGS.kinds.map((k) => k.kind))];

const live = (meta, turn) => (meta.rulings ?? []).filter((r) => r.until > turn);

// The kind of a ruling, from its option, label and words (and whether it cost the crown gold); null when none fits.
export function kindOf(option, label, text, cost) {
  const words = `${option ?? ""} ${label ?? ""} ${text ?? ""}`.toLowerCase();
  for (const row of RULINGS.kinds) {
    if (row.cost && !(cost > 0)) continue;
    if (new RegExp(row.match).test(words)) return row.kind;
  }
  return null;
}

// Keeps a ruling's kind at a town from this season. A newer ruling there takes its place.
export function post(meta, cityId, kind, turn) {
  if (!meta || cityId == null || !KINDS.includes(kind)) return null;
  const r = { city: Number(cityId), kind, since: turn, until: turn + Number(RULINGS.seasons ?? 2) };
  meta.rulings = [...live(meta, turn).filter((x) => x.city !== r.city), r];
  chron.saveMeta(meta);
  return r;
}

// A ruling given at court (court.js rule): read and kept at the town it touches (the petition's town,
// else the asker's seat, else the King's own).
export function note(ctx, petition, asked, out) {
  const { world, court, meta } = ctx;
  if (!meta || !world) return null;
  const who = petition && court?.people?.[petition.from];
  const crown = world.players.find((p) => p.crown || p.house?.crown);
  const at = (petition?.city != null && world.cities.find((c) => c.id === Number(petition.city)))
    || (who && (world.cities.find((c) => c.id === who.seat) ?? world.cities.find((c) => c.owner === who.playerId && c.capital) ?? world.cities.find((c) => c.owner === who.playerId)))
    || world.cities.find((c) => c.title === "Kingsmere") || world.cities.find((c) => c.owner === crown?.id && c.capital);
  const kind = kindOf(asked?.id, asked?.label, out?.text, out?.cost);
  if (!at || !kind) return null;
  const r = post(meta, at.id, kind, world.turn ?? 0);
  echo(ctx, at, kind);
  return r;
}

// A harsh ruling heard around (data/rulings.json echo): every town within reach of where it was given takes its
// dread for a season (meta.echoes, read by heardOf), and its townsfolk remember the word (minds.js hearTown).
export function echo(ctx, at, kind) {
  const E = RULINGS.echo;
  const { world, meta } = ctx;
  if (!E || !E.harsh.includes(kind)) return [];
  const turn = world.turn ?? 0;
  const near = world.cities.filter((c) => c.id !== at.id && Math.max(Math.abs(c.x - at.x), Math.abs(c.y - at.y)) <= E.reach);
  const ids = new Set(near.map((c) => c.id));
  meta.echoes = [...(meta.echoes ?? []).filter((e) => e.until > turn && !ids.has(e.city)), ...near.map((c) => ({ city: c.id, from: at.id, kind, since: turn, until: turn + E.seasons }))];
  const words = String(E.words?.[kind] ?? "").replace("{town}", cityName(at.id) ?? at.name);
  for (const c of near) ctx.minds?.hearTown?.(c.id, words, "dread");
  chron.saveMeta(meta);
  return near;
}

// For /world (view.js townStates): a harsh ruling heard here from a town nearby, or null: {kind, from (the town's
// name), mood (echo.mood), left}.
export function heardOf(meta, city, turn) {
  const e = (meta?.echoes ?? []).find((x) => x.city === city.id && x.until > turn);
  return e ? { kind: e.kind, from: cityName(e.from), mood: RULINGS.echo.mood, left: e.until - turn } : null;
}

// A decree that leaves its mark in the town it names (rulings.json decrees: relief, grant, build), as a ruling would.
export function decreed(meta, action, cityId, turn) {
  const kind = RULINGS.decrees?.[action];
  return kind ? post(meta, cityId, kind, turn) : null;
}

// For /world (view.js townStates): the ruling standing at this town, or null. left: its seasons still to stand.
export function view(meta, city, turn) {
  const r = live(meta ?? {}, turn).find((x) => x.city === city.id);
  return r ? { kind: r.kind, since: r.since, left: r.until - turn } : null;
}
