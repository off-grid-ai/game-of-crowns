// The realm's weather, owned here and nowhere else: one roll per season from the
// reign's own seed, so a reign replays the same skies. Kept in meta.weather and
// sent on /world; the view's mirror and everything that answers weather (the sky,
// the rain, the townsfolk, the harvest plea) read it from there.
//
// Weather is what falls: showers, rain, storm, snowfall. Snow lying on the ground
// is the season's (winter lies white even on a clear day), not the weather's.
// Keep the two facts apart.

import { rng } from "./fresh.js";

// Per season: [kind, cumulative chance].
const TABLE = {
  spring: [["showers", 0.45], ["clear", 1]],
  summer: [["clear", 0.8], ["rain", 0.95], ["storm", 1]],
  autumn: [["rain", 0.4], ["storm", 0.65], ["clear", 1]],
  winter: [["snow", 0.7], ["clear", 1]],
};
const WET = new Set(["showers", "rain", "storm"]);

// The weather of one season: the same seed and turn always give the same sky.
export function roll(seed, turn, season) {
  const r = rng(((Number(seed) >>> 0) ^ Math.imul(Number(turn) + 1, 2654435761)) >>> 0)();
  const rows = TABLE[season] ?? TABLE.summer;
  return (rows.find(([, at]) => r < at) ?? rows[rows.length - 1])[0];
}

// The season's weather, rolled once when the season turns and held for it.
// wet counts the wet seasons in a row.
export function advance(meta, turn, season) {
  const w = meta.weather;
  if (w && w.turn === turn) return w;
  // Weather a test staged holds until staged again (routes_test.js), so a film can
  // shoot it from every height; a real reign never stages it.
  if (w?.held) return (meta.weather = { ...w, turn, season });
  const kind = roll(meta.seed ?? 1066, turn, season);
  meta.weather = { turn, season, kind, wet: WET.has(kind) ? (w?.wet ?? 0) + 1 : 0 };
  return meta.weather;
}

// A wet harvest: an autumn after two wet seasons running, or a storm at harvest.
// The poor-harvest plea's gate (data/dilemmas.json "wet_harvest", when.wetHarvest).
export function wetHarvest(w) {
  return Boolean(w) && w.season === "autumn" && (w.wet >= 2 || w.kind === "storm");
}
