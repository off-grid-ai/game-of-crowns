// The crown's favour book: each great house's regard for the crown and why
// (favourOf, shiftFavour, shiftAndTell, noteFavour, saveFavour), the deeds a
// house will not forget and the grievance the chronicle names as the cause
// (DEED_WORDS, recordDeed, causeOf, theirs), kindness wearing thin (temper),
// and where a house's favour settles when left be (LEAN, restingFavour).
// favour.js keeps the bands (BANDS); this is the book they are read against.
// Nothing here reads server.js: the favour, its reasons, the deeds, the effects
// and the realm come in as one context argument, built fresh by server.js on
// each call (getters for what it reassigns, nextEffect for the effects'
// numbering); server.js keeps wrappers of the same names.

import { COURT } from "./court.js";
import fs from "node:fs";
import path from "node:path";
import { houseFor } from "./narrator.js";
import { clampFavour } from "./crown.js";
import { calendar } from "./calendar.js";

export function saveFavour(ctx) {
  const { P, favour, favourWhy, deeds, favourPast, lastSeason } = ctx;
  fs.writeFileSync(path.join(P.state, "favour.json"), JSON.stringify(favour));
  fs.writeFileSync(path.join(P.state, "favour-why.json"), JSON.stringify(favourWhy));
  fs.writeFileSync(path.join(P.state, "deeds.json"), JSON.stringify(deeds));
  fs.writeFileSync(path.join(P.state, "favour-past.json"), JSON.stringify({ byTurn: favourPast, net: lastSeason.net }));
}

export function favourOf(ctx, id) {
  return ctx.favour[id] ?? 60;
}

// Why each house feels as it does: the last few things that moved its favour,
// shown to the King like a ledger of grievances and kindnesses.

// What a cause means as a deed the lord would name, said to the King's face:
// [when it warmed them, when it cooled them]. Only the King's own acts count.
export const DEED_WORDS = {
  "a gift of crowns": ["sent us a chest of gold", null],
  "a feast in their honour": ["feasted us before the whole court", null],
  "grain from the crown": ["fed our people when they starved", null],
  "a building paid by the crown": ["paid for stone in our town", null],
  "a town granted or taken": ["granted us a town", "took a town that was ours"],
  "a royal match": ["wed our blood into a great house", "married off our blood against our wishes"],
  "the King's peace": ["kept the peace for us", "forced a peace on us"],
  "the King took a side": ["took our side in war", "took our enemy's side in war"],
  "the King's peace, kept by another house": ["sent a house to keep our peace", "set another house over our quarrel"],
  "their heir taken as the King's ward": ["raised our heir at court", "took our heir from us"],
  "your ruling at court": ["ruled for us at court", "ruled against us at court"],
  "shamed over the crown's loan": [null, "shamed us over the crown's loan"],
  "left unheard at court": [null, "left us waiting at court and never answered"],
  "the royal tithe": [null, "bled us with the tithe"],
  "an oath to the crown": ["took our oath and stood by it", "broke the oath we swore to the crown"],
  "the royal host": ["marched for us", "marched the royal host on our walls"],
};

// A deed the house will not forget. The same deed again adds to the old one;
// a house keeps its eight weightiest, so a great grudge never slips away.
export function recordDeed(ctx, id, d, why, turn) {
  const { deeds } = ctx;
  const what = DEED_WORDS[why]?.[d > 0 ? 0 : 1];
  if (!what || !turn) return;
  const list = (deeds[id] ??= []);
  const same = list.find((x) => x.what === what);
  // Done again, it weighs more, up to a point: a lifetime of tithes is one great grudge, not a number without end.
  if (same) { same.d = Math.max(-60, Math.min(60, same.d + d)); same.last = turn; }
  else list.push({ turn, last: turn, d, what });
  if (list.length > 8) deeds[id] = list.sort((a, b) => Math.abs(b.d) - Math.abs(a.d)).slice(0, 8).sort((a, b) => a.turn - b.turn);
}

// A ruling at court the lord who asked will bring back (Mac: "rulings come
// back"): owed to that lord by name, due two seasons on. Not merged with
// other deeds: each ruling is its own. A house keeps its weightiest eight, but
// never drops a ruling still owed.
export const RULING_DUE = 2;  // seasons until the lord comes back about it
export function recordRuling(list, { d, what, by, turn, due = null, setback = false }) {
  if ((Math.abs(d) < 5 && !setback) || !what || by == null) return;  // a small ruling fades; a weighty one comes back (the opening's first setback always does)
  list.push({ turn, last: turn, d, what, by, due: turn + (due ?? RULING_DUE), ruling: true, ...(setback ? { setback: true } : {}) });
  if (list.length > 8) {
    const keep = list.filter((x) => x.due != null && !x.raised);
    const rest = list.filter((x) => !keep.includes(x)).sort((a, b) => Math.abs(b.d) - Math.abs(a.d)).slice(0, Math.max(0, 8 - keep.length));
    list.splice(0, list.length, ...[...keep, ...rest].sort((a, b) => a.turn - b.turn));
  }
}

// "the winter of 352, when the King took a town that was theirs": the
// house's sharpest grievance, for the chronicle to name as the cause.
export const theirs = (t) => t.replace(/\bours\b/g, "theirs").replace(/\bour\b/g, "their").replace(/\bus\b/g, "them");
export function causeOf(ctx, id) {
  const { deeds } = ctx;
  const worst = (deeds[id] ?? []).filter((x) => x.d <= -8).sort((a, b) => a.d - b.d)[0];
  if (!worst) return "";
  const when = calendar(worst.turn);
  return `the ${when.season} of ${when.year}, when the King ${theirs(worst.what)}`;
}

export function noteFavour(ctx, id, d, why) {
  const { world, meta, favourWhy } = ctx;
  if (!d || !why) return;
  if (Math.abs(d) >= 8 && why !== "the royal tithe") recordDeed(ctx, id, d, why, world?.turn);
  // The King's weightiest acts, for the reign's ending to stop at.
  if (Math.abs(d) >= 8 && DEED_WORDS[why]?.[d > 0 ? 0 : 1] && world) {
    const seat = world.cities.find((c) => c.owner === Number(id) && c.capital) ?? world.cities.find((c) => c.owner === Number(id));
    (meta.choices ??= []).push({ turn: world.turn, pid: Number(id), d, what: DEED_WORDS[why][d > 0 ? 0 : 1], city: seat?.id ?? null });
    if (meta.choices.length > 80) meta.choices = meta.choices.sort((a, b) => Math.abs(b.d) - Math.abs(a.d)).slice(0, 60).sort((a, b) => a.turn - b.turn);
  }
  const list = (favourWhy[id] ??= []);
  const same = list.find((x) => x.why === why);
  if (same) same.d += d;  // the same cause again adds up, not repeats
  else list.push({ d, why });
  while (list.length > 6) list.shift();
}

// Kindness wears thin: the same house warmed again within a year is warmed
// less (a half, then a fifth), and the houses at war with it grow colder.
const KIND = new Set(["gift", "feast", "relief", "marriage"]);
export function temper(ctx, action, house, changes, dry = false) {
  const { world, meta, favour, detail } = ctx;
  if (!KIND.has(action) || house == null || !(changes?.[house] > 0)) return changes;
  const turn = world?.turn ?? 0;
  const seen = (meta.kindness ??= {});
  seen[house] = (seen[house] ?? []).filter((t) => t > turn - 4);
  const again = seen[house].length;
  if (!dry) seen[house].push(turn);  // a preview (dry) weighs it without counting it
  const out = { ...changes, [house]: Math.max(1, Math.round(changes[house] * [1, 0.5, 0.2][Math.min(again, 2)])) };
  const foes = detail()?.players?.[house]?.atWarWith ?? [];
  for (const f of foes) if (f !== house && favour[f] != null) out[f] = (out[f] ?? 0) - Math.max(1, Math.round(out[house] * 0.4));
  return out;
}

// A change of favour in words, never the arithmetic (data/court.json favourWords): "warmer", "much colder".
export function favourWord(d) {
  const W = COURT.favourWords;
  return d > 0 ? (d >= W.big ? W.bigUp : W.up) : (-d >= W.big ? W.bigDown : W.down);
}

// Shifts favour and says what it did, for the result card: "6,000 crowns · Thornvale cooler".
export function shiftAndTell(ctx, changes, why, cost = 0) {
  const { world } = ctx;
  const was = Object.fromEntries(Object.keys(changes ?? {}).map((id) => [id, Math.round(favourOf(ctx, Number(id)))]));
  shiftFavour(ctx, changes ?? {}, why, true);
  const moved = Object.keys(was).map((id) => {
    const p = world?.players.find((x) => x.id === Number(id));
    const now = Math.round(favourOf(ctx, Number(id)));
    // Direction and size in words, never the arithmetic (data/court.json favourWords).
    const word = favourWord(now - was[id]);
    return p && now !== was[id] ? `${houseFor(p).name.replace(/^House /, "")} ${word}` : null;
  }).filter(Boolean);
  const price = cost ? [`${(cost * 100).toLocaleString("en-US")} crowns`] : [];
  const shown = moved.length > 7 ? [...moved.slice(0, 6), `and ${moved.length - 6} more`] : moved;
  return [...price, ...shown].join("  ·  ");
}

export function shiftFavour(ctx, changes, why = "", told = false) {
  const { world, favour, effects, P } = ctx;
  const moves = [];
  for (const [id, delta] of Object.entries(changes)) {
    const was = Math.round(favourOf(ctx, Number(id)));
    favour[id] = clampFavour(favourOf(ctx, Number(id)) + delta);
    noteFavour(ctx, id, delta, why);
    const now = Math.round(favourOf(ctx, Number(id)));
    const p = world?.players?.find((x) => x.id === Number(id));
    if (p && now !== was) moves.push({ id: Number(id), house: houseFor(p).name.replace(/^House /, ""), from: was, to: now, word: favourWord(now - was) });
  }
  saveFavour(ctx);
  // Every change is seen (UI rule 13): the game shows what moved and why.
  // A decree's own result card already says it ("told"), so the game doesn't repeat it.
  if (moves.length && why) {
    effects.push({ seq: ctx.nextEffect(), why, told, moves });
    while (effects.length > 20) effects.shift();
    if (P) fs.writeFileSync(path.join(P.state, "effects.json"), JSON.stringify(effects));
  }
}

// Each house's own history with the crown (the world bible), within the reign's mood.
export const LEAN = { "House Stormhold": 12, "House Goldcrest": 8, "House Wolfholt": 4, "House Highfell": 2, "House Thornvale": -2, "House Ironreach": -10, "House Sunspire": -14 };

// Where a house's favour settles when the King leaves it be: its own temper with
// the crown, so the table keeps friends and doubters rather than one number.
export function restingFavour(ctx, p) {
  const { meta } = ctx;
  return clampFavour(({ loyal: 74, wary: 55, resentful: 34 }[meta.options?.trust] ?? 55) + (LEAN[houseFor(p).name] ?? 0));
}
