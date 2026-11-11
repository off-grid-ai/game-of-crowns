// The first ten minutes on the bridge (opening v2, the default; docs/review/first-ten-minutes-plan.md
// items 4 and 7; Reigns and Frostpunk: learn the throne before it bites). The one owner of "has the
// first winter passed": until it has, no threat rises and no house sends an ultimatum, and the first
// ruling that slights a lord is the one that comes back, about five minutes in, as the first setback.
// Numbers in data/opening.json.
import fs from "node:fs";
import { calendar } from "./stakes.js";

export const OPENING = JSON.parse(fs.readFileSync(new URL("./data/opening.json", import.meta.url), "utf8"));

export const v2 = (meta) => meta?.options?.opening === "v2";
const state = (meta) => (meta.openingState ??= {});

// Each season (season.js): the first winter is seen, then passes.
export function season(meta, turn) {
  if (!v2(meta)) return;
  const o = state(meta);
  if (o.wintered) return;
  if (calendar(turn).season === "winter") o.winterSeen = true;
  else if (o.winterSeen) o.wintered = true;
}

// The realm is quiet: a v2 reign before its first winter has passed (data: quietToWinter).
export const quiet = (meta) => v2(meta) && OPENING.quietToWinter !== false && !meta?.openingState?.wintered;

// Seasons until the first winter is over (the top bar's tracker), or null once it is (or not a v2 reign).
export function toWinter(meta, turn) {
  if (!v2(meta) || meta?.openingState?.wintered) return null;
  const seasons = ["spring", "summer", "autumn", "winter"];
  const i = seasons.indexOf(calendar(turn).season);
  return i < 0 ? null : 3 - i + 1;  // this season to the end of winter, counted whole
}

// The first ruling that slights the lord who asked: due later than the usual return, so it lands
// about five minutes in (firstSetbackSeasons after it), and always as a plea for amends, never a quiet
// gift or a scheme. Returns the seasons it's due in, or null for an ordinary ruling.
export function firstSetback(meta, d) {
  if (!v2(meta) || d >= 0 || state(meta).setback) return null;
  state(meta).setback = true;
  return OPENING.firstSetbackSeasons ?? 6;
}
