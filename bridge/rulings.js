// A court ruling's answer, seen in the town where it lands: the one owner of "the King ruled
// here, and this is what came of it" (docs/review/decisions-in-the-world.md; CK3's feasts and
// granted titles, Manor Lords' market and building sites, Stronghold's gallows, Total War's
// recruitment). When the King gives a ruling (court.js rule), it is read once into one kind
// (data/rulings.json: relief, justice, levy, feast, build, grant) and kept with the reign at the
// town it touches (meta.rulings, so it survives a restart) for its seasons. The view only draws it
// (cities[].ruling in /world; realm town_life.gd and realm/data/moods.json).
import fs from "node:fs";
import * as chron from "./chronicles.js";

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
  return at && kind ? post(meta, at.id, kind, world.turn ?? 0) : null;
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
