// Event cards between courts (screen map D1; references: CK3's event pool for the
// draw, King of Dragon Pass's scenes for the card). A deck of authored cards
// (data/events.json); each season the director (the one decider of pacing) asks for
// one: a bag of every card whose conditions hold now, less those shown within their
// rest and the decks just drawn, weighted by the wave (low stakes in a breather, war
// and famine in the build-up). The card names one lord or town from the realm; its
// two or three choices cost something and doing nothing costs too. A choice may
// start something that lands seasons later. Choices and costs are authored data;
// only a flavour line may be rephrased elsewhere. Behind a switch (options.events,
// else data on), the same way as the seals.

import { crownOf } from "./realm.js";
import * as Rivals from "./rivals.js";
import * as Contagion from "./contagion.js";
import * as Lua from "./lua.js";
import fs from "node:fs";
import { houseFor, cityName } from "./narrator.js";
import { calendar } from "./calendar.js";
import { pick as wording } from "./say.js";  // a choice's, its later's and a card's ignore text may be a list of wordings
import * as chron from "./chronicles.js";

export const EVENTS = JSON.parse(fs.readFileSync(new URL("./data/events.json", import.meta.url), "utf8"));
EVENTS.cards.push(...Rivals.RIVAL.cards);  // the rival King's envoys, drawn with the realm's (rivals.js)
EVENTS.cards.push(...Contagion.CONTAGION.cards);  // the sickness on the roads and the King's answers (contagion.js)
const S = EVENTS.settings;

export const on = (meta) => Boolean(meta?.options?.events ?? S.on);
const state = (meta) => (meta.events ??= { up: null, rested: {}, later: [], decks: [], wintered: false, lapsed: null });

const great = (world) => (world?.players ?? []).filter((p) => !houseFor(p).wild && !houseFor(p).crown && world.cities.some((c) => c.owner === p.id));
const pick = (xs) => xs[Math.floor(Math.random() * xs.length)];

// The card's subject, from the realm as it is: a town, a house, two houses at war, or the realm.
function subject(ctx, kind) {
  const { world, favourOf, detail } = ctx;
  const crown = crownOf(world);
  const houses = great(world);
  const lord = (pid) => ctx.court?.lordOfHouse(pid)?.name ?? null;
  const town = (c) => c && { town: cityName(c.id), city: c.id, house: houseFor(world.players.find((p) => p.id === c.owner) ?? {}).name, pid: c.owner, lord: lord(c.owner) };
  const house = (p) => p && { house: houseFor(p).name, pid: p.id, lord: lord(p.id), town: cityName(world.cities.find((c) => c.owner === p.id && c.capital)?.id ?? -1), city: world.cities.find((c) => c.owner === p.id && c.capital)?.id ?? null };
  switch (kind) {
    case "realm": return { realm: true };
    case "sick_town": return town(pick(world.cities.filter((c) => Contagion.sick(ctx.meta, c.id) && !Contagion.closed(ctx.meta, c.id))) ?? null);
    case "crown_town": return town(pick(world.cities.filter((c) => c.owner === crown?.id && !c.capital)) ?? null);
    case "seat": return town(world.cities.find((c) => c.owner === crown?.id && c.capital));
    case "hungry_town": return town(pick(world.cities.filter((c) => (c.famine || c.granaryLow) && (c.owner === crown?.id || houses.some((h) => h.id === c.owner)))) ?? null);
    case "house_cold": return house([...houses].sort((a, b) => favourOf(a.id) - favourOf(b.id))[0]);
    case "house_warm": return house([...houses].sort((a, b) => favourOf(b.id) - favourOf(a.id))[0]);
    case "house_any": return house(pick(houses));
    case "war_pair": {
      const d = detail?.();
      const pairs = [];
      for (const a of houses) for (const b of houses) if (a.id < b.id && (d?.players?.[a.id]?.atWarWith ?? []).includes(b.id)) pairs.push([a, b]);
      const pr = pick(pairs);
      return pr ? { ...house(pr[0]), rival: houseFor(pr[1]).name, rpid: pr[1].id } : null;
    }
  }
  return null;
}

// Whether a card's conditions hold (beyond having a subject).
function holds(ctx, when = {}) {
  const { world, meta, turn } = ctx;
  const season = calendar(turn).season;
  const crown = crownOf(world);
  const k = meta.minutes ? meta.elapsedMs / (meta.minutes * 60000) : 0.5;
  const peace = ctx.history?.at(-1)?.peace ?? 1;
  if (when.season && ![].concat(when.season).includes(season)) return false;
  if (when.treasuryBelow != null && (crown?.gold ?? 0) >= when.treasuryBelow) return false;
  if (when.treasuryAbove != null && (crown?.gold ?? 0) <= when.treasuryAbove) return false;
  if (when.peaceBelow != null && peace >= when.peaceBelow) return false;
  if (when.peaceAbove != null && peace <= when.peaceAbove) return false;
  if (when.after != null && k < when.after) return false;
  if (when.before != null && k > when.before) return false;
  if (when.rival && !Rivals.holds(meta, when.rival)) return false;
  if (when.contagion && !Contagion.abroad(meta)) return false;
  if (when.spread != null && Contagion.abroad(meta) < when.spread) return false;
  if (when.threat && !(meta.director?.threat && (when.threat === true || meta.director.threat.kind === when.threat))) return false;
  return true;
}

const fill = (s, x) => String(s ?? "").replace(/\{(\w+)\}/g, (_, k) => (x[k] ?? `{${k}}`));

// Each season (director.js): a card left unanswered lapses (its cost of doing nothing
// lands); things started seasons ago land; and maybe a new card is drawn.
export function season(ctx, turn, resting) {
  const { meta, world } = ctx;
  if (!on(meta) || !world || meta.status !== "running") return;
  const e = state(meta);
  ctx.turn = turn;
  // The first winter passes before any card (the opening's quiet: the lead's v2 opening).
  if (!e.wintered) {
    if (calendar(turn).season === "winter") e.winterSeen = true;
    else if (e.winterSeen) e.wintered = true;
    if (!e.wintered) { chron.saveMeta(meta); return; }
  }
  if (e.up && turn > (e.up.due ?? e.up.turn)) lapse(ctx, e, turn);
  for (const l of e.later.filter((x) => x.turn <= turn)) apply(ctx, l.effect, l.subject, turn);
  e.later = e.later.filter((x) => x.turn > turn);
  if (!e.up && meta.court?.sitting == null && Math.random() < (resting ? S.chanceInBreather : S.chance)) draw(ctx, e, turn, resting);
  chron.saveMeta(meta);
}

function draw(ctx, e, turn, resting) {
  const recent = e.decks.slice(-S.noRepeatDecks);
  let bag = [];
  for (const c of EVENTS.cards) {
    if (turn - (e.rested[c.id] ?? -999) < (c.rest ?? S.rest)) continue;
    if (resting && !S.breatherDecks.includes(c.deck)) continue;
    if (!holds(ctx, c.when)) continue;
    const sub = subject(ctx, c.subject ?? "realm");
    if (!sub) continue;
    if (c.deck === "rival") Object.assign(sub, Rivals.words(ctx.meta));
    let w = c.weight ?? 1;
    if (!resting && S.boost[c.deck]) w *= S.boost[c.deck];
    bag.push([c, sub, w]);
  }
  const fresh = bag.filter(([c]) => !recent.includes(c.deck));
  if (fresh.length) bag = fresh;
  if (!bag.length) return;
  let roll = Math.random() * bag.reduce((s, [, , w]) => s + w, 0);
  const [card, sub] = bag.find(([, , w]) => (roll -= w) < 0) ?? bag[0];
  e.rested[card.id] = turn;
  e.decks = [...e.decks, card.deck].slice(-8);
  // One matter at a time, from its town (CK3's event with its deadline, Crusader Kings' rider on the map): a rider
  // brings it from the town to the King's seat, settings.rider.speed tiles a season (none from the seat itself, or a
  // card with no town), and the King has the card's deadline (else settings.deadline) seasons from his arrival to
  // answer before it lapses and doing nothing costs. While he rides the card is seen coming (riding) but not answered.
  const crown = crownOf(ctx.world);
  const seat = ctx.world?.cities?.find((c) => c.owner === crown?.id && c.capital);
  const from = sub.city != null ? ctx.world?.cities?.find((c) => c.id === sub.city) : null;
  const far = seat && from ? Math.max(Math.abs(from.x - seat.x), Math.abs(from.y - seat.y)) : 0;
  const arrives = turn + Math.floor(far / Math.max(1, S.rider?.speed ?? 12));
  const due = arrives + Math.max(0, (card.deadline ?? S.deadline ?? 1) - 1);
  e.up = { id: card.id, turn, arrives, due, subject: sub, title: fill(card.title, sub), text: fill(card.text, sub), bearer: sub.lord ?? null, house: sub.house ?? null, city: sub.city ?? null,
    x: from?.x ?? null, y: from?.y ?? null,
    choices: card.choices.map((ch, i) => ({ i, label: fill(ch.label, sub), cost: ch.cost ?? 0, moves: moves(ctx, ch, sub) })), ignore: fill(wording(`event:${card.id}:ignore`, card.ignore?.text), sub) };
  if (from && seat && from.id !== seat.id) ctx.scene?.("rider", { x: from.x, y: from.y, tx: seat.x, ty: seat.y, city: seat.id, label: e.up.title });
  ctx.record?.({ turn, kind: "event", text: e.up.title, city: sub.city ?? undefined });
}

// Whose favour a choice moves, by name, for the card (who it helps and hurts).
function moves(ctx, ch, sub) {
  return Object.entries(ch.favour ?? {}).flatMap(([who, d]) => who === "all" ? great(ctx.world).map((p) => ({ house: houseFor(p).name, d }))
    : who === "house" && sub.house ? [{ house: sub.house, d }] : who === "rival" && sub.rival ? [{ house: sub.rival, d }] : []);
}

// What an effect does, with the existing verbs: favour, the crown's gold, a line in the chronicle, the threat eased.
function apply(ctx, fx = {}, sub = {}, turn) {
  const { world } = ctx;
  const shift = {};
  for (const [who, d] of Object.entries(fx.favour ?? {})) {
    if (who === "all") for (const p of great(world)) shift[p.id] = (shift[p.id] ?? 0) + d;
    else if (who === "house" && sub.pid != null) shift[sub.pid] = (shift[sub.pid] ?? 0) + d;
    else if (who === "rival" && sub.rpid != null) shift[sub.rpid] = (shift[sub.rpid] ?? 0) + d;
  }
  if (Object.keys(shift).length) ctx.shiftFavour?.(shift, fx.why ?? "the King's answer to an event");
  const crown = crownOf(world);
  if (fx.gold && crown) {
    ctx.send?.(`lua cmd ${Lua.gold(crown.id, Math.round(fx.gold))}`);
    crown.gold = (crown.gold ?? 0) + Math.round(fx.gold);  // now, as the decree route does, so a second payment can't overdraw before the next reading
  }
  if (fx.rival) Rivals.shift(ctx.meta, fx.rival);  // the rival King's mood (rivals.js)
  if (fx.contagion) Contagion.act(ctx.meta, fx.contagion, sub.city, turn);  // the roads shut, physicians, fire (contagion.js)
  if (fx.ease && ctx.meta.director?.threat) ctx.meta.director.threat.level = Math.max(0, ctx.meta.director.threat.level - fx.ease);
  if (fx.text) ctx.record?.({ turn, kind: "event", text: fill(fx.text, sub), city: sub.city ?? undefined });
}

function lapse(ctx, e, turn) {
  const card = EVENTS.cards.find((c) => c.id === e.up.id);
  apply(ctx, { ...(card?.ignore ?? {}), text: e.up.ignore }, e.up.subject, turn);  // the wording drawn with the card
  e.lapsed = { title: e.up.title, text: e.up.ignore, turn, at: Date.now() };
  e.up = null;
}

// POST /event/answer {choice}: the King's answer, its cost paid, its effect now and its later one queued.
export function answer(ctx, i) {
  const { meta, world } = ctx;
  const e = state(meta);
  if (!e.up) return [400, { error: "there's no event before you" }];
  if ((world?.turn ?? 0) < (e.up.arrives ?? 0)) return [400, { error: `the rider from ${e.up.subject?.town ?? "the town"} is still on the road` }];
  const card = EVENTS.cards.find((c) => c.id === e.up.id);
  const ch = card?.choices?.[Number(i)];
  if (!ch) return [400, { error: "no such answer" }];
  const crown = crownOf(world);
  if ((ch.cost ?? 0) > (crown?.gold ?? 0)) return [400, { error: `the treasury holds too little: this costs ${(ch.cost * 100).toLocaleString("en-GB")} crowns` }];
  const turn = world?.turn ?? 0;
  if (ch.cost) apply(ctx, { gold: -ch.cost }, e.up.subject, turn);
  // A text written as a list of wordings: one not heard lately (say.js), the same in the chronicle and the reply.
  const said = wording(`event:${card.id}:${Number(i)}`, ch.text);
  apply(ctx, { ...ch, text: said }, e.up.subject, turn);
  if (ch.later) e.later.push({ turn: turn + (ch.later.in ?? 2), effect: { ...ch.later, text: wording(`event:${card.id}:later:${Number(i)}`, ch.later.text) }, subject: e.up.subject });
  const told = fill(said ?? ch.label, e.up.subject);
  meta.lastRuling = told;  // the save card's line (reign.js saveCard)
  e.up = null;
  chron.saveMeta(meta);
  return [200, { ok: true, text: told }];
}

// A test reign's hook (routes_test.js): draw a card now, past the opening's quiet, or let the one up lapse.
export function testNow(ctx, what) {
  const e = state(ctx.meta);
  ctx.turn = ctx.world?.turn ?? 0;
  if (what === "lapse" && e.up) lapse(ctx, e, ctx.turn);
  else if (what === "draw") { e.up = null; draw(ctx, e, ctx.turn, false); }
  chron.saveMeta(ctx.meta);
  return e;
}

// For /world: the card before the King, and the last one that lapsed (the view's sound and badge).
// up carries riding (the rider not yet at the seat) and left (seasons to answer, counting this one) for the view.
export const view = (meta, turn) => {
  if (!on(meta)) return null;
  const up = meta.events?.up ?? null;
  const t = turn ?? up?.turn ?? 0;
  return { up: up && { ...up, riding: t < (up.arrives ?? up.turn), left: Math.max(0, (up.due ?? up.turn) - t + 1) }, lapsed: meta.events?.lapsed ?? null };
};
