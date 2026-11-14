// The world gets harsher (casebook, Pacing: decline, not growth; Frostpunk's and Banished's later winters, CK3's
// rising dangers as a reign wears on): one factor, 1 at the crowning, rising data/harsh.json perYear each year of the
// reign to most, that the realm's outside dangers are scaled by: the rival King's mood at rest and his raids
// (rivals.js), how often a sickness begins (contagion.js). Read, never stored: the reign's years are the one fact.
import fs from "node:fs";
import { SEASONS_PER_YEAR } from "./calendar.js";

const H = JSON.parse(fs.readFileSync(new URL("./data/harsh.json", import.meta.url), "utf8"));

export function harsh(meta, turn) {
  const years = Math.max(0, (turn ?? 0) - (meta?.crownedAt ?? 0)) / SEASONS_PER_YEAR;
  return Math.min(H.most, 1 + H.perYear * years);
}
