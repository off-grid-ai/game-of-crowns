// The reign: the King's name and the deeds that earn it (kingName, deed), the
// reign's goal (goalNow), where it is heading (readings), the royal ladder of
// aims (LADDER, aimNow, aimPlace, aimProgress, ladder) and the King's three
// ambitions, the reign's clock and what it brings (tick: the last act, the
// ambitions, the great council, the reign told in acts), and how it ends
// (epilogue, score, endReign) with what the view reads of it (reignInfo).
// Nothing here reads server.js: the realm's state and the bridge's own helpers
// come in as one context argument, built fresh by server.js on each call
// (getters for what it reassigns, setPaused for the clock's hold); server.js
// keeps wrappers of the same names.

import { crownOf, houseName } from "./realm.js";
import * as Lua from "./lua.js";
import * as Opening from "./opening.js";
import { say } from "./say.js";
import * as Events from "./events.js";
import * as Seals from "./seals.js";
import * as Next from "./next.js";
import * as Director from "./director.js";
import { houseFor, cityName } from "./narrator.js";
import { BANDS } from "./favour.js";
import { calendar } from "./calendar.js";
import * as chron from "./chronicles.js";
import * as kingDeeds from "./ledger.js";

// The King's ledger (ledger.js): each deed he does goes in, and when it changes
// the name the realm gives him, the ticker says which deed tipped it.
export function kingName(ctx, outcome = null) {
  const { meta, world, history } = ctx;
  const realm = history.length ? { peace: history.reduce((t, r) => t + r.peace, 0) / history.length, grew: history[history.length - 1].pop / Math.max(1, history[0].pop) } : {};
  return kingDeeds.epithetOf(meta, outcome, realm, (pid) => { const p = world?.players?.find((x) => x.id === Number(pid)); return p ? houseFor(p).name : null; });
}
export function deed(ctx, tag, opts = {}) {
  const { meta, world, record } = ctx;
  if (!meta || (!tag && opts.act === false)) return;
  const turn = world?.turn ?? 0;
  const before = meta.ledger?.name ?? null;
  if (opts.act !== false) { meta.lastActAt = turn; meta.idleTold = false; }  // the King acted: not idle (season.js idle)
  kingDeeds.note(meta, tag, { turn, ...opts });
  const now = kingName(ctx).name;
  meta.ledger.name = now;
  chron.saveMeta(meta);
  const axis = kingDeeds.axisOf(now);
  // The deed that tipped it: the weightiest on the name's side, or (for a name of two sides) this one.
  const said = tag?.says ? String(tag.says).replace("{town}", opts.place || "a town").replace("{house}", opts.place || "a house") : null;
  const why = (axis && kingDeeds.tipping(meta, ...axis)) || said;
  if (before && now !== before && why) record({ turn, kind: "name", text: `After ${why}, people call you ${now}.` });
}

// The reign's goal, as the top bar shows it: how many great houses stand
// firmly with the King, of how many, and how many are at war with another.
export const GOAL_FAVOUR = BANDS.sworn;  // sworn and up counts as firmly the King's (data/favour.json)
export function goalNow(ctx) {
  const { world, detail, favourOf } = ctx;
  const great = (world?.players ?? []).filter((p) => !houseFor(p).wild && !houseFor(p).crown && p.cities > 0);
  const ids = new Set(great.map((p) => p.id));
  const d = detail();
  const fighting = great.filter((p) => (d?.players?.[p.id]?.atWarWith ?? []).some((q) => ids.has(q))).length;
  const firm = great.filter((p) => favourOf(p.id) >= GOAL_FAVOUR).length;
  return { bar: GOAL_FAVOUR, firm, of: great.length, fighting, won: great.length > 0 && firm === great.length && fighting === 0 };
}

// Where the reign is heading: peace, wealth and strength, each against a year
// ago, and the name history would give the King if it ended today, with the
// one close behind it. A report, not a judgement: the numbers say which way.
export function readings(ctx) {
  const { meta, world, history, favourPast, favourOf } = ctx;
  if (!history.length || !world) return null;
  const last = history[history.length - 1];
  const ago = history.find((r) => r.turn >= last.turn - 4) ?? history[0];
  const great = world.players.filter((p) => !houseFor(p).wild && !houseFor(p).crown && world.cities.some((c) => c.owner === p.id));
  const loyalShare = (fav) => great.length ? great.filter((p) => (fav(p.id) ?? 50) >= BANDS.steady).length / great.length : 0;
  const was = favourPast[ago.turn] ?? favourPast[last.turn - 4];
  const way = (d, eps) => d > eps ? 1 : d < -eps ? -1 : 0;
  const wealth = (r) => r.pop + r.treasury / 50;
  return {
    peace: { now: last.peace, way: way(last.peace - ago.peace, 0.03) },
    wealth: { now: last.pop, treasury: last.treasury, way: way(wealth(last) - wealth(ago), Math.max(2, wealth(ago) * 0.02)) },
    strength: { now: loyalShare(favourOf), way: was ? way(loyalShare(favourOf) - loyalShare((id) => was[id]), 0.01) : 0 },
    ...(() => { const k = kingName(ctx); const name = meta.testEpithet ? `the ${meta.testEpithet}` : k.name; return { name, why: k.why, next: kingDeeds.nextName(meta, name) }; })(),
  };
}

// At three quarters of the reign the last act begins, and is named: the
// gravest thing coming for the throne, so the ending is seen coming.
export function lastAct(ctx) {
  const { meta, world, stakes, arcs, record } = ctx;
  if (!meta.minutes || meta.lastAct || meta.elapsedMs < meta.minutes * 60000 * 0.75) return;
  const u = stakes?.s.usurper;
  const story = arcs?.reignView();
  const pretender = u && u.stage !== "none" ? world?.players?.find((p) => p.id === u.house) : null;
  // kind: what the climax is, so the director knows whether to stay out of its way (director.js finale).
  const kind = pretender ? "pretender" : story && story.status === "running" ? "story" : (stakes?.s.north?.waves ?? 0) > 0 ? "north" : "houses";
  // With no pretender, story or dead, the coldest great house is the threat: its host, by name and by the
  // season it lands (the director's finale raises it there; gameplay review #8: "the houses' own ambitions"
  // had no face and no date).
  const turn = world?.turn ?? 0;
  const cold = kind === "houses" ? (world?.players ?? []).filter((p) => !houseFor(p).wild && !houseFor(p).crown && world.cities.some((c) => c.owner === p.id)).sort((a, b) => ctx.favourOf(a.id) - ctx.favourOf(b.id))[0] : null;
  const landAt = Director.DIRECTOR.finale?.landAt ?? 0.92;
  const lands = turn + Math.max(1, Math.round(((landAt - meta.elapsedMs / (meta.minutes * 60000)) * meta.minutes * 60) / Math.max(1, ctx.turnSeconds ?? 40)));
  const when = calendar(lands);
  const threat = pretender ? `${houseFor(pretender).name}'s claim to the throne`
    : story && story.status === "running" ? story.title
    : (stakes?.s.north?.waves ?? 0) > 0 ? "the dead from the North"
    : cold ? `${houseFor(cold).name}'s host, by the ${when.season} of ${when.year}` : "the houses' own ambitions";
  meta.lastAct = { threat, kind, turn, ...(cold ? { house: cold.id, lands } : {}) };
  chron.saveMeta(meta);
  record({ turn: world?.turn ?? 0, kind: "act", text: `The last act of the reign begins. What comes for the throne now: ${threat}.` });
}

// The King's ambitions: three goals he carries from his first season, each a
// way to be remembered. Met, it is told in the chronicle, the great houses
// warm to a King who does what he set out to do, and history counts it.
// Drawn from the realm as the King finds it (gameplay review #8: "twenty decrees" rewarded spam and
// "200,000 crowns" was out of reach unless he never spent): a war he can end, the seat he must keep,
// houses he can bind. A drawn ambition carries its own subjects (a, b); fail: true once it can't be met.
const atWar = ({ detail, court }, a, b) => {
  const d = detail?.();
  const la = court?.lordOfHouse(a), lb = court?.lordOfHouse(b);
  return (d?.players?.[a]?.atWarWith ?? []).includes(b) && !(la && lb && court.truce(la.id, lb.id));
};
export const AMBITIONS = [
  { key: "endwar", draw: (ctx) => {
      const { world, detail } = ctx;
      const great = (world?.players ?? []).filter((p) => !houseFor(p).wild && !houseFor(p).crown && world.cities.some((c) => c.owner === p.id));
      const power = (p) => world.cities.filter((c) => c.owner === p.id).length * 2 + (p.units ?? 0);
      let pair = null;
      for (const a of great) for (const b of great) if (a.id < b.id && atWar(ctx, a.id, b.id) && (!pair || power(a) + power(b) > power(pair[0]) + power(pair[1]))) pair = [a, b];
      return pair ? { a: pair[0].id, b: pair[1].id, text: `End the war between ${houseName(world, pair[0].id, "a house").replace(/^House /, "")} and ${houseName(world, pair[1].id, "a house").replace(/^House /, "")}` } : null;
    },
    met: (ctx, a) => a.a != null && !atWar(ctx, a.a, a.b) },
  { key: "seat", text: "Keep Kingsmere unbesieged to the last act",
    met: ({ meta }) => !!meta.lastAct && meta.seatBesieged == null, fail: ({ meta }) => meta.seatBesieged != null },
  { key: "wed", text: "Wed two great houses by the King's word", met: ({ meta }) => (meta.matchesMade ?? 0) >= 1 },
  { key: "peace", text: "Keep the realm truly at peace for two whole years", met: ({ history }) => history.length >= 8 && history.slice(-8).every((r) => r.peace >= 0.85) },
  { key: "loyal", text: "Win four of the great houses to the crown", met: ({ world, favourOf }) => (world?.players ?? []).filter((p) => !houseFor(p).wild && !houseFor(p).crown && favourOf(p.id) >= BANDS.loyal).length >= 4 },
  { key: "grow", text: "Grow the realm by a fifth", met: ({ meta, history }) => meta.ambitionsFrom?.pop > 0 && (history.at(-1)?.pop ?? 0) >= meta.ambitionsFrom.pop * 1.2 },
];

// The royal ladder: one aim always before the King, each with a reward he can
// see in the realm, each leading to the next (build, then muster, then win a
// house, then trade, then take land, then hold it). Checked every few seconds;
// met, the reward lands at once and the next aim is named.
const crownHas = ({ world, crownOf }, b, seatOnly = false) => { const c = crownOf(); return !!c && world.cities.some((x) => x.owner === c.id && (!seatOnly || x.capital) && (x.buildings ?? []).includes(b)); };

// The most companies the crown has had under its banner at once, wherever they stand (the muster
// aim never goes backward when the King sends men out or loses some; gameplay review #7).
const companies = ({ world, crownOf, SOLDIER }) => (world?.units ?? []).filter((u) => u.owner === crownOf()?.id && SOLDIER(u)).length;
const mustered = (ctx) => Math.max(companies(ctx), ctx.meta?.ladder?.peak ?? 0);

export const LADDER = [
  { key: "granary", do: "Fund a granary", text: "Raise a granary in Kingsmere", how: "Open Kingsmere's card and fund a granary.",
    met: (ctx) => crownHas(ctx, "Granary", true), reward: "feast", says: "Kingsmere's granary stands full. The town holds a harvest feast in the King's name." },
  { key: "host", do: "Raise the levy", text: "Muster a royal host of 2,400 men", how: "Raise the levy, or call the banners.",
    met: (ctx) => mustered(ctx) >= 12, reward: "knights", says: "Two thousand four hundred men stand under the royal banner. Two knights ride in to join them, unasked." },
  { key: "friend", do: "Win over", text: "Win a great house to the Crown", how: "Favour a house until it stands at 70.",
    met: ({ world, favourOf }) => world.players.some((p) => !houseFor(p).wild && !houseFor(p).crown && favourOf(p.id) >= 70), reward: "gold", says: "A great house swears itself to the Crown, and sends a chest of silver to prove it." },
  { key: "market", do: "Fund a market", text: "Raise a market in a royal town", how: "Fund a market in any town of the Crown.",
    met: (ctx) => crownHas(ctx, "Marketplace"), reward: "gold", says: "The royal market opens. Merchants come from three houses' lands to trade under the King's peace." },
  { key: "town", do: "March the host", text: "Bring a new town under the Crown", how: "March the royal host on a town, or win one by grant.",
    met: ({ world, meta, crownOf }) => { const c = crownOf(); return !!c && world.cities.some((x) => x.owner === c.id && !(meta.ladder?.held ?? []).includes(x.id)); }, reward: "feast", says: "A new town flies the royal banner. Its people line the road to see the King's men ride in." },
  { key: "walls", do: "Fund walls", text: "Wall Kingsmere against what comes", how: "Fund walls in Kingsmere.",
    met: (ctx) => crownHas(ctx, "City Walls", true), reward: "knights", says: "Stone walls ring Kingsmere. Let them come." },
];

// Past the six, the ladder keeps going from the realm itself: win back the
// coldest great house (its lord by name), or raise what a royal town lacks.
export function nextAim(ctx) {
  const { meta, world, court, favourOf, crownOf } = ctx;
  const crown = crownOf();
  const cold = world.players.filter((p) => !houseFor(p).wild && !houseFor(p).crown && world.cities.some((c) => c.owner === p.id))
    .sort((a, b) => favourOf(a.id) - favourOf(b.id))[0];
  const want = (meta.ladder.n ?? 0) % 2 === 0;
  if (cold && favourOf(cold.id) < 45 && want) {
    const lord = court?.lordOfHouse(cold.id);
    const to = Math.min(70, Math.round(favourOf(cold.id)) + 20);
    return { key: `win-${cold.id}-${to}`, do: "Win back", text: `Win back ${lord ? lord.name : houseFor(cold).name} of ${houseFor(cold).name}`, how: `Bring ${houseFor(cold).name} to ${to} favour: a gift, a feast, a match, or a ruling in their favour.`,
      pid: cold.id, to, reward: "gold", says: `${lord ? lord.name : houseFor(cold).name} rides to Kingsmere and kneels before the whole court.` };
  }
  for (const c of world.cities.filter((x) => x.owner === crown.id)) {
    const lacks = [["Granary", "a granary"], ["Marketplace", "a market"], ["City Walls", "walls"], ["Barracks", "a barracks"]].find(([b]) => !(c.buildings ?? []).includes(b) && !meta.works?.[c.id]);
    if (lacks) return { key: `build-${c.id}-${lacks[0]}`, do: `Fund ${lacks[1]}`, text: `Raise ${lacks[1]} in ${cityName(c.id)}`, how: `Open ${cityName(c.id)}'s card and fund ${lacks[1]}.`, city: c.id, building: lacks[0], reward: "feast", says: `${cityName(c.id)} has its ${lacks[1].replace(/^an? /, "")}. The townsfolk drink to the King.` };
  }
  return null;
}
const aimMet = (ctx, a) => { const { world, favourOf } = ctx; return a.met ? a.met(ctx) : a.pid != null ? favourOf(a.pid) >= a.to : a.city != null ? (world.cities.find((x) => x.id === a.city)?.buildings ?? []).includes(a.building) : false; };
export const aimNow = ({ meta }) => meta.ladder ? (LADDER[meta.ladder.i] ?? meta.ladder.dyn ?? null) : null;

// Where the King acts on his aim: the town whose card holds the means (a quest
// log's marker). Kingsmere for its works and the levy, a royal town without a
// market, the warmest house's seat to win, a town he could take.
export function aimPlace(ctx, a) {
  const { meta, world, favourOf, crownOf } = ctx;
  const crown = crownOf();
  if (!a || !crown || !world) return null;
  const seat = world.cities.find((x) => x.owner === crown.id && x.capital);
  const royal = world.cities.filter((x) => x.owner === crown.id);
  switch (a.key) {
    case "granary": case "walls": case "host": return seat?.id ?? null;
    case "market": return (royal.find((x) => !(x.buildings ?? []).includes("Marketplace")) ?? seat)?.id ?? null;
    case "friend": {
      const best = world.players.filter((p) => !houseFor(p).wild && !houseFor(p).crown).sort((x, y) => favourOf(y.id) - favourOf(x.id))[0];
      return best ? (world.cities.find((x) => x.owner === best.id && x.capital)?.id ?? null) : null;
    }
    case "town": return (meta.campaigns ?? [])[0]?.city ?? null;
  }
  if (a.pid != null) return world.cities.find((x) => x.owner === a.pid && x.capital)?.id ?? null;
  return a.city ?? null;
}

// How far along the King is toward his aim, in the realm's words with a fill:
// "7 of 12 companies", "Highfell at 55 of 70", "rising · 57%". Null when the aim
// is all-or-nothing and nothing is under way.
export function aimProgress(ctx, a) {
  const { meta, world, turnSeconds, favourOf, crownOf, SOLDIER } = ctx;
  const crown = crownOf();
  if (!a || !crown || !world) return null;
  const works = (pred) => Object.entries(meta.works ?? {}).find(([id, w]) => pred(Number(id), w.building));
  const rising = (found) => {
    if (!found) return { text: "not begun", frac: 0 };
    const [, w] = found;
    const f = Math.min(0.99, (w.seasons - w.left + Math.min(1, (Date.now() - w.since) / (turnSeconds * 1000))) / w.seasons);
    return { text: `rising · ${w.left} season${w.left === 1 ? "" : "s"} left`, frac: f };
  };
  const seat = world.cities.find((x) => x.owner === crown.id && x.capital);
  const favourTo = (pid, to) => { const f = Math.round(favourOf(pid)); return { text: `${houseFor(world.players.find((p) => p.id === pid)).name} at ${f} of ${to}`, frac: Math.max(0, Math.min(1, f / to)) }; };
  switch (a.key) {
    case "host": { const n = mustered(ctx); return { text: `${(Math.min(n, 12) * 200).toLocaleString("en-US")} of 2,400 men`, frac: Math.min(1, n / 12) }; }  // in men, as the ledger counts them; the best muster so far
    case "friend": {
      const best = world.players.filter((p) => !houseFor(p).wild && !houseFor(p).crown).sort((x, y) => favourOf(y.id) - favourOf(x.id))[0];
      return best ? favourTo(best.id, 70) : null;
    }
    case "granary": return rising(works((id, b) => id === seat?.id && b === "Granary"));
    case "walls": return rising(works((id, b) => id === seat?.id && b === "City Walls"));
    case "market": return rising(works((_, b) => b === "Marketplace"));
    case "town": {
      const s = (meta.campaigns ?? [])[0];
      return s ? { text: `the host before ${cityName(s.city)}`, frac: Math.min(0.9, ((world.turn ?? s.turn) - s.turn + 0.5) / (2 + (s.extra ?? 0))) } : null;
    }
  }
  if (a.pid != null) return favourTo(a.pid, a.to);
  if (a.city != null) return rising(works((id, b) => id === a.city && b === a.building));
  return null;
}

export function ladder(ctx) {
  const { meta, world, send, scene, record, crownOf, crownSeat } = ctx;
  if (meta.status !== "running" || !world || !crownOf()) return;
  // Aims already true when the reign begins are passed over: the King is never asked for what he has.
  meta.ladder ??= { i: 0, held: world.cities.filter((x) => x.owner === crownOf().id).map((x) => x.id), skip: LADDER.filter((a) => a.key !== "town" && a.met(ctx)).map((a) => a.key) };
  const l = meta.ladder;
  l.peak = Math.max(l.peak ?? 0, companies(ctx));
  l.held ??= world.cities.filter((x) => x.owner === crownOf().id).map((x) => x.id);  // a save from before
  while (l.i < LADDER.length && (l.skip ?? []).includes(LADDER[l.i].key)) l.i++;
  // Past the fixed six, an aim drawn from the realm (one at a time).
  if (l.i >= LADDER.length && !l.dyn) { l.dyn = nextAim(ctx); if (l.dyn) chron.saveMeta(meta); }
  const aim = aimNow(ctx);
  if (!aim || !aimMet(ctx, aim)) return;
  const seat = crownSeat();
  if (aim.reward === "feast" && seat) scene("feast", { x: seat.x, y: seat.y, city: seat.id, owner: seat.owner });
  if (aim.reward === "knights" && seat) {
    send(`lua cmd ${Lua.levy(seat.id, ["Knights", "Knights"])}`);
    scene("muster", { x: seat.x, y: seat.y, tx: seat.x + 2, ty: seat.y + 1, city: seat.id });
  }
  if (aim.reward === "gold") send(`lua cmd ${Lua.gold(crownOf().id, 250)}`);
  record({ turn: world.turn, kind: "aim", text: aim.says });
  if (l.i < LADDER.length) l.i++;
  else { l.dyn = null; l.n = (l.n ?? 0) + 1; }
  if (aim.key === "town") l.held = world.cities.filter((x) => x.owner === crownOf().id).map((x) => x.id);
  l.just = { text: aim.text, at: Date.now() };
  chron.saveMeta(meta);
}

export function ambitions(ctx) {
  const { meta, world, history, favour, favourOf, saveFavour, record } = ctx;
  if (!meta.minutes || meta.status !== "running" || !world) return;
  if (!meta.ambitions) {
    // Three that aren't already true when the reign begins, drawn from the realm as the King finds it:
    // a war between two great houses first, when there is one; the rest by the realm's own seed.
    meta.ambitionsFrom = { turn: world.turn, pop: history.at(-1)?.pop ?? 0 };  // what this reign is measured from
    meta.lastActAt ??= world.turn;  // an idle King is counted from his crowning (season.js idle)
    const drawn = AMBITIONS.map((a) => (a.draw ? (() => { const d = a.draw(ctx); return d ? { ...a, ...d } : null; })() : a)).filter((a) => a && !a.met(ctx, a));
    const hash = (t) => t.split("").reduce((h, ch) => (Math.imul(h, 31) + ch.charCodeAt(0)) >>> 0, 7);
    const first = drawn.filter((a) => a.draw);
    const rest = drawn.filter((a) => !a.draw).sort((a, b) => hash(meta.id + a.key) - hash(meta.id + b.key));
    meta.ambitions = [...first, ...rest].slice(0, 3).map((a) => ({ key: a.key, text: a.text, met: null, ...(a.a != null ? { a: a.a, b: a.b } : {}) }));
    chron.saveMeta(meta);
  }
  // Kingsmere besieged (a pretender's host at its walls, or any siege of it) fails "keep it unbesieged".
  const seat = ctx.crownSeat?.();
  if (meta.seatBesieged == null && (ctx.stakes?.s?.usurper?.stage === "march" || seat?.besieged)) { meta.seatBesieged = world.turn; chron.saveMeta(meta); }
  for (const a of meta.ambitions) {
    const spec = AMBITIONS.find((x) => x.key === a.key);
    if (a.met != null || a.failed != null) continue;
    if (spec?.fail?.(ctx, a)) { a.failed = world.turn; chron.saveMeta(meta); continue; }
    if (!spec?.met(ctx, a)) continue;
    a.met = world.turn;
    for (const p of world.players.filter((p) => !houseFor(p).wild && !houseFor(p).crown)) favour[p.id] = Math.min(100, favourOf(p.id) + 5);
    saveFavour();
    record({ turn: world.turn, kind: "ambition", text: `The King's ambition is fulfilled: ${a.text.toLowerCase()}. The great houses take note.` });
    chron.saveMeta(meta);
  }
}

// The council: twice a reign (at two fifths and two thirds of the clock) the
// great houses divide over a war between two of them, and each says where it
// stands. The matter comes to the King's court with the count; whichever camp
// he sides with warms to him, and the other remembers.
export function council(ctx) {
  const { meta, world, court, detail, record } = ctx;
  if (!meta.minutes || meta.status !== "running" || !world || !court) return;
  const at = meta.elapsedMs / (meta.minutes * 60000);
  const passed = [0.4, 0.65].filter((x) => at >= x && !(meta.councils ?? []).includes(x));
  if (!passed.length) return;
  const due = passed[passed.length - 1];
  (meta.councils ??= []).push(...passed);  // after a reload, the thresholds passed are spent at once: one council
  const d = detail();
  const great = world.players.filter((p) => !houseFor(p).wild && !houseFor(p).crown && world.cities.some((c) => c.owner === p.id));
  const stilled = (x, y) => { const l1 = court.lordOfHouse(x), l2 = court.lordOfHouse(y); return !!(l1 && l2 && court.truce(l1.id, l2.id)); };
  const war = (a, b) => (d?.players?.[a.id]?.atWarWith ?? []).includes(b.id) && !stilled(a.id, b.id);
  const power = (p) => world.cities.filter((c) => c.owner === p.id).length * 2 + (p.units ?? 0);
  let pair = null;
  for (const a of great) for (const b of great) if (a.id < b.id && war(a, b) && (!pair || power(a) + power(b) > power(pair[0]) + power(pair[1]))) pair = [a, b];
  if (!pair) { chron.saveMeta(meta); return; }  // the realm at peace: no council this time
  const [a, b] = pair;
  // Each other house stands with the side it isn't fighting; with neither, the stronger.
  const votes = { [a.id]: [], [b.id]: [] };
  for (const h of great.filter((x) => x !== a && x !== b)) {
    const side = war(h, a) && !war(h, b) ? b : war(h, b) && !war(h, a) ? a : power(a) >= power(b) ? a : b;
    votes[side.id].push(houseFor(h).name.replace("House ", ""));
  }
  const lord = (p) => Object.values(court.people).find((c) => c.alive && c.rank === "lord" && c.playerId === p.id);
  const from = lord(a) ?? lord(b);
  if (!from) { chron.saveMeta(meta); return; }
  const name = (p) => houseFor(p).name;
  const camp = (p) => votes[p.id].length ? `${votes[p.id].join(", ")} stand with ${name(p)}` : `no house stands with ${name(p)}`;
  court.arcPetition({ arc: "council", beat: `council-${due}`, thread: "the great council", from,
    text: `The great council divides over the war between ${name(a)} and ${name(b)}. ${camp(a)}; ${camp(b)}. The lords wait on the King's word.`,
    options: [
      { id: "a", label: `Side with ${name(a)}`, hint: `${name(a)} +15 · ${name(b)} −20`, favour: { [a.id]: 15, [b.id]: -20 }, result: say("council.side", { winner: name(a), loser: name(b) }, `The King sides with ${name(a)}. ${name(b)} leaves the council hall without bowing.`) },
      { id: "b", label: `Side with ${name(b)}`, hint: `${name(b)} +15 · ${name(a)} −20`, favour: { [b.id]: 15, [a.id]: -20 }, result: say("council.side", { winner: name(b), loser: name(a) }, `The King sides with ${name(b)}. ${name(a)} leaves the council hall without bowing.`) },
      { id: "peace", label: "Command them both to make peace (300 gold)", hint: `${name(a)} −5 · ${name(b)} −5 · the crown pays the blood-price`, cost: 300, favour: { [a.id]: -5, [b.id]: -5 }, result: `The King orders peace and pays the blood-price himself. Neither house thanks him for it.` },
    ] }, world);
  (meta.councilWar ??= {})[`council-${due}`] = [a.id, b.id];
  record({ turn: world.turn, kind: "council", text: `The great council divides over the war between ${name(a)} and ${name(b)}.` });
  chron.saveMeta(meta);
}

// The reign in acts: at each quarter of its clock the act just gone is told
// back. Two or three of the King's weightiest choices in it, each where it
// happened and what came of it, then the name he is earning. The realm waits
// while he reads it (the clock and the seasons hold), and goes on when he has.
export function interlude(ctx) {
  const { meta, world, favourOf, theirs, record } = ctx;
  if (!meta.minutes || meta.status !== "running") return;
  const q = Math.floor((meta.elapsedMs / (meta.minutes * 60000)) * 4);
  if (q < 1 || q > 3 || (meta.interludes ??= []).includes(q)) return;
  const from = meta.interlude?.turn ?? 0;
  meta.interludes.push(q);
  const picked = [];
  for (const c of [...(meta.choices ?? [])].filter((c) => c.turn > from).sort((a, b) => Math.abs(b.d) - Math.abs(a.d))) {
    if (picked.length >= 3) break;
    if (c.city == null || picked.some((x) => x.pid === c.pid)) continue;
    picked.push(c);
  }
  const named = (() => { const k = kingName(ctx); return { name: k.name, next: kingDeeds.nextName(meta, k.name) }; })();
  const choices = picked.sort((a, b) => a.turn - b.turn).map((c) => {
    const p = world?.players?.find((x) => x.id === c.pid);
    const when = calendar(c.turn);
    const f = Math.round(favourOf(c.pid));
    return { city: c.city, text: `In the ${when.season} of ${when.year} you ${theirs(c.what)}, and ${p ? houseFor(p).name : "a great house"} hasn't forgotten.`,
      after: f >= BANDS.loyal ? "They're with you because of it." : f < BANDS.cooling ? "They still haven't forgiven you." : c.d > 0 ? "They liked that." : "They gave in, but they're still angry." };
  });
  const acts = ["first", "second", "third"];
  // What the realm is calling him, said by the realm (a different mouth each act),
  // and how his sworn ambitions stand, in words.
  const met = (meta.ambitions ?? []).filter((a) => a.met != null).length;
  const ambit = meta.ambitions?.length ? ["You haven't kept any of your three promises yet.", "You've kept one of your three promises.", "You've kept two of your three promises.", "You've kept all three of your promises."][Math.min(3, met)] : "";
  const said = [`People in the taverns are calling you ${named.name}.`, `At court they've started calling you ${named.name}.`, `The chroniclers are writing you down as ${named.name}.`][q - 1];
  choices.push({ city: -1, text: said, after: [named.next ? `Some still say ${named.next}.` : "", ambit].filter(Boolean).join(" ") });
  // The act's one deed to name at its turning (bells, one line at its place): the
  // ledger's weightiest deed since the act began, where it was done.
  const deeds = (meta.ledger?.deeds ?? []).filter((d) => d.turn > from && String(d.says ?? "") !== "");
  const top = deeds.sort((a, b) => Object.values(b.axes ?? {}).reduce((s, n) => s + Math.abs(n), 0) - Object.values(a.axes ?? {}).reduce((s, n) => s + Math.abs(n), 0) || b.turn - a.turn)[0];
  let deed = null;
  if (top) {
    const named = (world?.cities ?? []).find((c) => String(top.says).includes(c.name) || String(top.says).includes(cityName(c.id) ?? "\u0000"));
    // A deed that names a house (a council's side taken) stands at that house's seat, where its banner flies.
    const house = !named ? (world?.players ?? []).find((p) => !houseFor(p).crown && houseFor(p).name && String(top.says).includes(houseFor(p).name)) : null;
    const houseSeat = house ? world.cities.find((c) => c.owner === house.id && c.capital) ?? world.cities.find((c) => c.owner === house.id) : null;
    const at = named ?? houseSeat ?? (picked[0] ? world?.cities?.find((c) => c.id === picked[0].city) : null) ?? world?.cities?.find((c) => houseFor(world.players.find((p) => p.id === c.owner) ?? {}).crown && c.capital);
    const line = String(top.says);
    deed = { line: line.charAt(0).toUpperCase() + line.slice(1), city: at?.id ?? null, x: at?.x ?? null, y: at?.y ?? null };
  }
  meta.interlude = { q, title: `End of the ${acts[q - 1]} act`, turn: world?.turn ?? 0, choices, fates: [], seen: false, deed };
  chron.saveMeta(meta);
  record({ turn: world?.turn ?? 0, kind: "act", text: `The ${acts[q - 1]} act of the reign ends.` });
}

// How the reign ends, shown before its name: the King's weightiest choices,
// three or four, each where it happened, and what became of every great house.
export function epilogue(ctx) {
  const { meta, world, favour, favourOf, theirs } = ctx;
  if (!world?.players || !world?.cities) return { choices: [], fates: [] };
  const great = (world?.players ?? []).filter((p) => !houseFor(p).wild && !houseFor(p).crown && (meta.turning?.[p.id] || favour[p.id] != null));
  const picked = [];
  for (const c of [...(meta.choices ?? [])].sort((a, b) => Math.abs(b.d) - Math.abs(a.d))) {
    if (picked.length >= 4) break;
    if (c.city == null || picked.some((x) => x.pid === c.pid || x.what === c.what)) continue;
    picked.push(c);
  }
  const choices = picked.sort((a, b) => a.turn - b.turn).map((c) => {
    const p = world.players.find((x) => x.id === c.pid);
    const when = calendar(c.turn);
    const f = Math.round(favourOf(c.pid));
    return { city: c.city, text: `In the ${when.season} of ${when.year} you ${theirs(c.what)}, and ${p ? houseFor(p).name : "a great house"} never forgot.`,
      after: f >= BANDS.loyal ? "They stuck by you to the end." : f < BANDS.cooling ? "They never forgave you." : c.d > 0 ? "They thought well of you for it." : "They gave in, but they never let it go." };
  });
  if (meta.ambitions?.length) {
    const met = meta.ambitions.filter((a) => a.met != null);
    choices.push({ city: -1, text: met.length ? `You promised to ${met.map((a) => a.text.charAt(0).toLowerCase() + a.text.slice(1)).join(" and to ")}, and you did.` : "You made three promises and kept none of them.",
      after: ["You kept none of your three promises.", "You kept one of your three promises.", "You kept two of your three promises.", "You kept all three of your promises."][Math.min(3, met.length)] });
  }
  const power = (p) => world.cities.filter((c) => c.owner === p.id).length * 2 + (p.units ?? 0);
  const mightiest = [...great].sort((a, b) => power(b) - power(a))[0];
  const fates = great.map((p) => {
    const f = Math.round(favourOf(p.id));
    const towns = world.cities.filter((c) => c.owner === p.id).length;
    const line = !towns ? "fell, and its halls stand empty."
      : meta.turning?.[p.id]?.state === "refused" ? "rose against the crown, and will again."
      : f >= BANDS.loyal ? "stood by the crown to the end."
      : f < BANDS.cooling ? "never forgave the King."
      : p === mightiest ? "ends the reign the mightiest house in the realm."
      : f >= BANDS.steady ? "kept its oath, and its counsel."
      : "bent the knee, and kept its grudges.";
    return { house: houseFor(p).name, color: houseFor(p).color, line };
  });
  return { choices, fates };
}

export function score(ctx) {
  const { history } = ctx;
  if (!history.length) return { score: 0, peace: 0, pop: 0, verdict: "A reign too short to judge." };
  const peace = history.reduce((s, r) => s + r.peace, 0) / history.length;
  const last = history[history.length - 1];
  const alive = Object.values(last.houses).filter((h) => h.towns > 0).length;
  const total = Math.round(peace * 600 + last.pop * 4 + alive * 30 + last.treasury * 0.5);
  // The verdict is the King's deeds first (the ledger's name and why), the realm's numbers only as
  // support (gameplay review #8: "A steady hand" came from peace and population, whatever he did).
  const realm = peace > 0.8 && last.pop > 150 ? "The realm grew rich and quiet under him."
    : peace > 0.6 ? "The realm endured."
    : peace > 0.35 ? "The houses bled one another while he ruled."
    : "The realm burned, and the songs remember swords.";
  const k = kingName(ctx);
  const verdict = `${k.why || "History found little to say of him."} ${realm}`;
  return { score: total, peace, pop: last.pop, verdict };
}

export function endReign(ctx, why, outcome = "completed") {
  const { meta, world, record, send, setPaused } = ctx;
  if (meta.status !== "running") return;
  const s = score(ctx);
  if (outcome === "deposed") { s.score = Math.round(s.score * 0.4); s.verdict = "Deposed. The crown passed to another while you watched."; }
  if (outcome === "won") { s.score = Math.round(s.score * 1.5); s.verdict = "The crown held. The tale that came for it is told, and the King is still in his seat."; }
  if (outcome === "fallen") { s.score = Math.round(s.score * 0.3); s.verdict = "The realm fell to the dead. No one is left to remember."; }
  { const k = kingName(ctx, outcome); s.title = `The King ${k.name}`; s.why = k.why; }
  meta.epilogue = epilogue(ctx);
  s.outcome = outcome;
  meta.status = "ended";
  meta.score = s.score;
  meta.verdict = s.verdict;
  meta.title = s.title;
  meta.why = s.why;  // the deeds the name was earned by (ledger.js), shown under it
  meta.outcome = outcome;
  meta.endedAt = { turn: world?.turn ?? 0, peace: s.peace, pop: s.pop, houses: world?.players?.filter((p) => !houseFor(p).wild && !houseFor(p).crown && world.cities.some((c) => c.owner === p.id)).length ?? 0 };
  chron.saveMeta(meta);
  chron.addRecord({ id: meta.id, name: meta.name, scenario: meta.scenario, minutes: meta.minutes, turns: world?.turn ?? 0, ended: Date.now(), ...s });
  record({ turn: world?.turn ?? 0, kind: "reign_end", text: `${why} So ends the reign of ${s.title}. ${s.verdict} (Score ${s.score}.)` });
  setPaused(true);
  send("set timeout 0");
}

// The reign's clock, every five seconds while the realm runs and the King
// watches (server.js holds it for a sitting, an unread act or an empty window).
export function tick(ctx) {
  const { meta } = ctx;
  meta.elapsedMs += 5000;
  if (meta.minutes > 0 && meta.elapsedMs >= meta.minutes * 60000) endReign(ctx, "The appointed time has passed. The reign ends.");
  else {
    lastAct(ctx);
    ambitions(ctx);
    council(ctx);
    interlude(ctx);
    if (meta.elapsedMs % 30000 === 0) { meta.save = saveCard(ctx); chron.saveMeta(meta); }
  }
}

// A reign's save card (saves as reigns: the load list shows each reign by it, as any game's save slot shows the
// ruler, the date and the playtime): the season and date in the realm, the crown's towns, its seat and its souls, and
// when it was last played. Kept in the reign's meta (meta.save) with the clock and on a save; the reign's own fields
// (name, minutes, elapsedMs, status, title) are the rest of the slot.
export function saveCard(ctx) {
  const { meta, world, soulsOf } = ctx;
  if (!world) return meta.save ?? null;
  const crown = crownOf(world);
  const towns = (world.cities ?? []).filter((c) => c.owner === crown?.id);
  const seat = towns.find((c) => c.capital);
  return { turn: world.turn ?? 0, date: calendar(world.turn).text, towns: towns.length, seat: seat ? cityName(seat.id) : null,
    souls: towns.reduce((t, c) => t + (soulsOf?.(c.size) ?? 0), 0), playedAt: Date.now() };
}

// Opening v2: until the first winter has passed, the aim is to hold the realm to it, with the seasons left
// (opening.js; the first-ten-minutes plan's tracker). The ladder's aims come after.
function winterAim(meta, world) {
  const left = Opening.toWinter(meta, world?.turn ?? 0);
  if (left == null) return null;
  const a = Opening.OPENING.winterAim ?? {};
  return { n: 0, of: null, text: a.text ?? "Hold the realm whole to the first winter", how: a.how ?? "", at: null,
    progress: { text: left === 1 ? "the last season of winter" : `${left} seasons to the end of winter`, frac: Math.max(0, Math.min(1, 1 - (left - 1) / 4)) } };
}

export function reignInfo(ctx) {
  const { meta, world, paused, soulsOf } = ctx;
  const aim = aimNow(ctx);
  // The next thing, a minute away (next.js): what he can do soonest, with its place and clock.
  // Behind the royal seal's switch with it (seals.js on), so the loop being playtested stays as it is.
  const next = !Seals.on(meta) ? null : Next.nextThing(ctx, aim ? { key: aim.key, do: aim.do, building: aim.building ?? null, at: aimPlace(ctx, aim), progress: aimProgress(ctx, aim) } : null);
  return {
    id: meta.id, name: meta.name, test: chron.isTest(meta), scenario: meta.scenario, status: meta.status, paused, minutes: meta.minutes,
    elapsedMs: meta.elapsedMs, remainingMs: meta.minutes > 0 ? Math.max(0, meta.minutes * 60000 - meta.elapsedMs) : null,
    score: meta.score, verdict: meta.verdict, title: meta.title, why: meta.why ?? null, outcome: meta.outcome, ended: meta.endedAt,
    epilogue: meta.epilogue ?? null, lastAct: meta.lastAct ?? null, interlude: meta.interlude && !meta.interlude.seen ? meta.interlude : null, ambitions: meta.ambitions ?? null, aim: winterAim(meta, world) ?? (aim ? { n: Math.min(meta.ladder.i, LADDER.length) + (meta.ladder.n ?? 0) + 1, of: meta.ladder.i < LADDER.length ? LADDER.length : null, text: aim.text, how: aim.how, progress: aimProgress(ctx, aim), at: aimPlace(ctx, aim) } : null), aimDone: meta.ladder?.just && Date.now() - meta.ladder.just.at < 8000 ? meta.ladder.just.text : null, readings: meta.status === "running" ? readings(ctx) : null,
    souls: world?.cities?.reduce((t, c) => t + soulsOf(c.size), 0) ?? 0,
    next,
    seals: Seals.view(meta),
    // The realm's tension this season (director.js, 0 calm to 1 on fire): the music follows it (realm juice.json).
    tension: meta.director?.curve?.at(-1)?.t ?? null,
    event: (() => { const e = Events.view(meta); return e?.up ? { ...e, seconds: Next.secondsToSeasonEnd(ctx.turnSeconds) } : e; })(),
  };
}
