// The first ten minutes on the bridge (opening v2, the default; docs/review/first-ten-minutes-plan.md
// items 4 and 7; Reigns and Frostpunk: learn the throne before it bites). The one owner of "has the
// first winter passed": until it has, no threat rises and no house sends an ultimatum, and the first
// ruling that slights a lord is the one that comes back, about five minutes in, as the first setback.
// Numbers in data/opening.json.
import fs from "node:fs";
import { calendar } from "./calendar.js";

export const OPENING = JSON.parse(fs.readFileSync(new URL("./data/opening.json", import.meta.url), "utf8"));

export const v2 = (meta) => meta?.options?.opening === "v2";
const state = (meta) => (meta.openingState ??= {});

// Each season (season.js): the first winter is seen, then passes.
export function season(meta, turn) {
  const o = state(meta);
  if (o.at !== turn) { o.at = turn; o.seasons = (o.seasons ?? 0) + 1; calmSeason(meta); }  // the seasons the King has ruled (they pass only while he watches)
  if (!v2(meta)) return;
  if (o.wintered) return;
  if (calendar(turn).season === "winter") o.winterSeen = true;
  else if (o.winterSeen) o.wintered = true;
}

// The act of a timed reign, 1 to 4 by its clock (a reign without a clock stays in the second).
export const actOf = (meta) => (meta?.minutes ? 1 + Math.max(0, Math.min(3, Math.floor(((meta.elapsedMs ?? 0) / (meta.minutes * 60000)) * 4))) : 2);
// The first share of a timed reign's clock is the King's to learn the court (data: calmShare).
const calm = (meta) => meta?.minutes > 0 && (meta.elapsedMs ?? 0) < (OPENING.calmShare ?? 0) * meta.minutes * 60000;
// The realm is quiet: a v2 reign before its first winter has passed (data: quietToWinter), or any
// timed reign in its first calm stretch: no threat rises, no house sends an ultimatum.
// And every reign's first year (data: quietSeasons): no rising, no pretender, no ultimatum before the King has had a year.
export const quiet = (meta) => (meta?.openingState?.seasons ?? 0) < (OPENING.quietSeasons ?? 4) || calm(meta) || (v2(meta) && OPENING.quietToWinter !== false && !meta?.openingState?.wintered);
// Whether a pretender may yet whisper of a better claim (data: usurperFromAct).
export const usurperMay = (meta) => !quiet(meta) && actOf(meta) >= (OPENING.usurperFromAct ?? 1);

// The first ruling that cools a house (the lord who asked, or the house it ruled against): due later than the usual return, so it lands
// about five minutes in (firstSetbackSeasons after it), and always as a plea for amends, never a quiet
// gift or a scheme. Returns the seasons it's due in, or null for an ordinary ruling.
// d: how much the ruling cooled the house that will come back (its asker, or the house it cooled most: court.js).
export function firstSetback(meta, d) {
  if (!v2(meta) || d >= 0 || state(meta).setback) return null;
  state(meta).setback = true;
  return OPENING.firstSetbackSeasons ?? 6;
}

// --- the calm opening: one trouble at a time, its kinds in order (data/opening.json calm) ---------------------------
// The one gate every starter of a trouble that asks something of the King asks first (raids.js, rivals.js, court.js,
// events.js, contagion.js, director.js, the stories in arcs.js, the lords' bold moves in characters.js). Frostpunk's
// and Anno's onboarding: one system at a time. Kept on meta.openingState.calm {step, stepAt, met, live, freeAt}.
const CALM = OPENING.calm ?? {};
const ORDER = CALM.order ?? [];
// Whether the reign is still in its calm opening (its first CALM.seasons seasons the King watched).
export const calmNow = (meta) => !!meta && (meta.openingState?.seasons ?? 0) < (CALM.seasons ?? 0);
const seasonsOf = (meta) => meta.openingState?.seasons ?? 0;
const calmState = (meta) => (state(meta).calm ??= { step: 0, stepAt: 0, met: [], live: null, freeAt: 0 });
// When a live trouble is over, by its owner's own state; a starter without one runs on its lease.
const OVER = {
  firstRaid: (m) => !m.firstRaid || m.firstRaid.done,
  court: (m) => m.court?.sitting == null,
  card: (m) => !m.events?.up,
  plague: (m) => !Object.keys(m.contagion?.towns ?? {}).length,
  threat: (m) => !m.director?.threat,
  demand: (m) => !m.rival?.demand || m.rival.demand.answered,
};
// The live trouble, cleared once it is over or has run its seasons.
function sweep(meta) {
  const c = calmState(meta), l = c.live;
  if (!l) return c;
  const age = seasonsOf(meta) - l.at;
  const over = OVER[l.what] ? OVER[l.what](meta) : age >= (CALM.leaseSeasons ?? 1);
  if (over || age >= (CALM.liveSeasons ?? 3)) { c.live = null; c.freeAt = seasonsOf(meta) + (CALM.restSeasons ?? 0); }
  return c;
}
// Whether a trouble of this kind may start now: always after the opening; in it, only a kind whose turn has come,
// with nothing else live and the rest after the last one over.
export function may(meta, kind) {
  if (!calmNow(meta)) return true;
  const c = sweep(meta), i = ORDER.indexOf(kind);
  return i >= 0 && i <= c.step && !c.live && seasonsOf(meta) >= c.freeAt;
}
// A trouble started (after may): it is the live one, and its kind has had its turn. what: its owner (OVER), for when it ends.
export function began(meta, kind, what) {
  if (!calmNow(meta)) return;
  const c = calmState(meta);
  c.live = { kind, what, at: seasonsOf(meta) };
  if (!c.met.includes(kind)) c.met.push(kind);
  if (ORDER.indexOf(kind) === c.step) { c.step++; c.stepAt = seasonsOf(meta); }
}
// Each season: a kind whose turn has waited long enough with nothing of it lets the next come too.
function calmSeason(meta) {
  if (!calmNow(meta)) return;
  const c = sweep(meta);
  if (c.step < ORDER.length && seasonsOf(meta) - c.stepAt >= (CALM.waitSeasons ?? 2)) { c.step++; c.stepAt = seasonsOf(meta); }
}
// The kind of an event card's deck, and of a director's threat (data: calm.decks, calm.threats).
export const deckKind = (deck) => CALM.decks?.[deck] ?? "court";
export const threatKind = (kind) => CALM.threats?.[kind] ?? "war";
// Stories running at once: one in the calm opening, the stories' own number after.
export const storiesAtOnce = (meta, max) => (calmNow(meta) ? Math.min(max, CALM.stories ?? 1) : max);
