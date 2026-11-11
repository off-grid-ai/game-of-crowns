// The storyteller's pace (Left 4 Dead's director; CK3's pushback against a King
// too comfortable). Each season it reads the realm's tension from its one state
// (wars between the houses, towns rioting or starving, a usurper, the threat
// itself). After a quiet stretch one threat rises at a place (a house's host
// gathering, a famine, a pretender's banners) and grows each season, seen in the
// world, until the King answers it there or it breaks. Then a breather. The
// numbers and words are data (data/director.json); this is the one decider.
// Nothing here reads server.js: what it needs comes in as one context argument.

import * as Opening from "./opening.js";
import * as Events from "./events.js";
import fs from "node:fs";
import { houseFor, cityName } from "./narrator.js";
import { blightLua } from "./blight.js";
import * as chron from "./chronicles.js";
import * as Lua from "./lua.js";
import { BANDS } from "./favour.js";
import * as Stakes from "./stakes.js";
import * as kingDeeds from "./ledger.js";

export const DIRECTOR = JSON.parse(fs.readFileSync(new URL("./data/director.json", import.meta.url), "utf8"));

const great = (world) => (world?.players ?? []).filter((p) => !houseFor(p).wild && !houseFor(p).crown && world.cities.some((c) => c.owner === p.id));
const crownOf = (world) => (world?.players ?? []).find((p) => houseFor(p).crown);
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const fill = (s, t) => String(s ?? "").replace(/\{house\}/g, t.houseName ?? "").replace(/\{town\}/g, t.townName ?? "").replace(/\{n\}/g, String(t.n ?? 0));

// The realm's tension, 0 calm to 1 on fire, from the one state.
export function tension(world, meta, peace = 1, usurperStage = "none") {
  const towns = (world?.cities ?? []).filter((c) => !houseFor(world.players.find((p) => p.id === c.owner) ?? {}).wild);
  const troubled = towns.filter((c) => c.disorder || c.famine).length / Math.max(1, towns.length);
  const usurper = usurperStage && usurperStage !== "none" ? 0.5 : 0;
  const threat = meta?.director?.threat?.level ?? 0;
  return Math.min(1, (1 - peace) * 1.2 + troubled * 2 + usurper + threat * 0.5);
}

// Each season (season.js turn). ctx: world, meta, history, usurper (its stage), send(lua), record, scene, favourOf, shiftFavour, addMark.
export function season(ctx, turn) {
  const { world, meta } = ctx;
  if (!world || !meta || meta.status !== "running") return;
  const d = (meta.director ??= { calm: 0, rest: 0, threat: null, pushedAt: -99, curve: [] });
  d.from ??= { turn, ms: meta.elapsedMs ?? 0 };  // where the reign's clock and its seasons started, to pace the finale
  const peace = ctx.history?.[ctx.history.length - 1]?.peace ?? 1;
  const t = tension(world, meta, peace, ctx.usurper ?? "none");
  d.curve = [...(d.curve ?? []), { turn, t: Math.round(t * 100) / 100, threat: d.threat?.kind ?? null, level: d.threat?.level ?? 0 }].slice(-60);
  if (d.threat) grow(ctx, d, turn);
  else if (d.rest > 0) d.rest -= 1;
  else if (meta.lastAct) finale(ctx, d, turn);
  else {
    // The build-up: each act the realm stays quiet for less long before the next threat.
    d.calm = Opening.quiet(meta) ? 0 : t < DIRECTOR.quietBelow ? d.calm + 1 : 0;  // the opening's quiet: nothing rises before the first winter (opening.js)
    if (d.calm >= (DIRECTOR.quietByAct?.[actOf(meta)] ?? DIRECTOR.quietSeasons)) raise(ctx, d, turn);
  }
  // A town taken from the crown or a sworn ally is a crisis to the King, whoever took it
  // (Freeciv's own wars included): the breather follows. Wars between other houses stay background.
  const crown = crownOf(world);
  const ours = (c) => crown && (c.owner === crown.id || (meta.alliances?.[c.owner] ?? -1) > turn);
  const before = d.held ?? {};
  if (Object.entries(before).some(([id, owner]) => world.cities.find((c) => c.id === Number(id))?.owner !== owner)) crisis(meta);
  d.held = Object.fromEntries(world.cities.filter(ours).map((c) => [c.id, c.owner]));
  pushback(ctx, d, turn, peace);
  // Between courts, a card from the realm as it is (events.js): the director decides the
  // wave (a breather draws only low stakes, and seldom); the deck decides which card.
  Events.season(ctx, turn, resting(meta));
  chron.saveMeta(meta);
}

// The act of the reign (0-3) by its clock; a reign without a clock stays in the second.
const actOf = (meta) => meta?.minutes ? Math.max(0, Math.min(3, Math.floor((meta.elapsedMs ?? 0) / (meta.minutes * 60000) * 4))) : 1;

// After a crisis, a breather (tension in waves): while it lasts no house rises
// (season.js mayRise) and no threat of the director's begins. The last act starts
// no new one (crisis): once the breather it opened with is out, it builds to the end.
export const resting = (meta) => (meta?.director?.rest ?? 0) > 0;

// A crisis struck from elsewhere in the realm (a house rising, a story's march):
// the breather that follows is the same one the director's own threats get.
export function crisis(meta) {
  if (!meta || meta.lastAct) return;
  const d = (meta.director ??= { calm: 0, rest: 0, threat: null, pushedAt: -99, curve: [] });
  d.rest = Math.max(d.rest ?? 0, DIRECTOR.breather);
  d.calm = 0;
  chron.saveMeta(meta);
}

// The last act's climax. A named story or pretender is the climax: the director
// stays out of its way. Named only as the houses' ambitions, one threat rises now
// and grows to land near the reign's end (finale.landAt), so the ending is a peak.
function finale(ctx, d, turn) {
  const named = ctx.meta.lastAct?.kind ?? ((ctx.usurper ?? "none") !== "none" ? "pretender" : "houses");
  if (d.finaleDone || named !== "houses") return;
  // The house the last act named (reign.js lastAct) is the one whose host masses: what was named comes.
  const house = ctx.meta.lastAct?.house;
  if (house != null && (ctx.world?.cities ?? []).some((c) => c.owner === house)) d.envious = house;
  raise(ctx, d, turn, house != null ? DIRECTOR.finale?.kind ?? "host" : null, true);
  if (!d.threat && house != null) raise(ctx, d, turn, null, true);  // that house can't mass a host now: whatever the realm can raise
  d.finaleDone = !!d.threat;  // none possible this season: it tries again the next
}

// The finale's growth a season: what is left of it, over the seasons left before it lands.
function paced(meta, d, turn, level, grow) {
  const total = (meta.minutes ?? 0) * 60000;
  const perTurn = ((meta.elapsedMs ?? 0) - (d.from?.ms ?? 0)) / Math.max(1, turn - (d.from?.turn ?? turn));
  if (!total || !(perTurn > 0)) return grow;
  const left = Math.max(1, Math.round((DIRECTOR.finale.landAt * total - meta.elapsedMs) / perTurn));
  return Math.min(0.5, Math.max(grow * 0.5, (1 - level) / left));
}

// A threat rises: the kind the realm makes possible, at its place. A house that
// envies the King (pushback) is the one whose host masses next: threats come
// from the scheming houses, not from nowhere. want: a kind asked for (a test stage).
export function raise(ctx, d, turn, want = null, isFinale = false) {
  const { world, favourOf } = ctx;
  const crown = crownOf(world);
  const mine = world.cities.filter((c) => c.owner === crown?.id);
  const houses = great(world);
  if (!crown || !mine.length || !houses.length) return;
  const envious = d.envious != null ? houses.find((h) => h.id === d.envious) : null;
  const coldest = envious ?? [...houses].sort((a, b) => favourOf(a.id) - favourOf(b.id))[0];
  const theirs = world.cities.filter((c) => c.owner === coldest.id);
  // The cold house's town nearest the crown's lands: where a host gathers, where a claim is spoken.
  const border = [...theirs].sort((a, b) => Math.min(...mine.map((m) => dist(a, m))) - Math.min(...mine.map((m) => dist(b, m))))[0];
  // The realm's biggest town not the crown's: where a famine bites hardest.
  const big = world.cities.filter((c) => houses.some((h) => h.id === c.owner)).sort((a, b) => b.size - a.size)[0];
  const can = { host: !!border, famine: !!big, pretender: !!border && favourOf(coldest.id) < BANDS.sworn && (ctx.usurper ?? "none") === "none" };
  if (envious) can.famine = false;  // an envious house schemes: it masses men or raises a claim
  const pool = Object.entries(DIRECTOR.threats).filter(([k]) => can[k] && k !== d.last && (!want || k === want));
  if (!pool.length) return;
  let roll = Math.random() * pool.reduce((s, [, v]) => s + v.weight, 0);
  const [kind] = pool.find(([, v]) => (roll -= v.weight) < 0) ?? pool[0];
  const at = kind === "famine" ? big : border;
  const owner = world.players.find((p) => p.id === at.owner);
  d.envious = null;
  d.threat = { kind, city: at.id, x: at.x, y: at.y, house: owner.id, houseName: houseFor(owner).name, townName: cityName(at.id), level: 0, n: 0, since: turn, ...(isFinale ? { finale: true } : {}) };
  d.calm = 0;
  grow(ctx, d, turn);
}

// The threat grows a season: seen in the world, and told.
function grow(ctx, d, turn) {
  const { world, send, record, scene } = ctx;
  const th = d.threat;
  const spec = DIRECTOR.threats[th.kind];
  const at = world.cities.find((c) => c.id === th.city);
  if (!at) { d.threat = null; return; }
  th.step = th.finale ? paced(ctx.meta, d, turn, th.level, spec.grow) : spec.grow;  // kept, so its countdown is honest (due)
  th.level = Math.min(1, th.level + th.step);
  if (th.level >= 1 && turn > th.since) return breaks(ctx, d, turn);
  const stage = Math.min(spec.says.length - 1, Math.floor(th.level * spec.says.length));
  if (th.kind === "host") {
    // Men gather at the town: a company or two more each season, by Freeciv's own units.
    th.n += 2;
    send(`lua cmd realm_host(realm_find_player(${th.house}), ${at.x}, ${at.y}, {"Pikemen","Archers","Knights"}, 2)`);
    scene("muster", { x: at.x, y: at.y, tx: at.x, ty: at.y, city: at.id });
  } else if (th.kind === "famine") {
    // The fields round the town fail: Freeciv's own farmland turned to waste, so it really starves.
    send(`lua cmd ${blightLua(at.id, "Desert", 0.25 + th.level * 0.4, 12)}`);
  } else if (th.kind === "pretender") {
    scene("vigil", { x: at.x, y: at.y, city: at.id, strength: 0.5 + th.level * 0.5 });
  }
  record({ turn, kind: "unrest", text: `${fill(spec.says[stage], th)}.`, city: at.id });
}

// Left unanswered, it lands, with a cost the realm can see (Into the Breach,
// Frostpunk: an ignored threat never fizzles): the host takes a crown town and
// burns it, the famine starves a town for real (its fields waste, its granary
// gone) and spreads, the pretender is proclaimed; and the King's silence counts
// toward his name (the Absent).
function breaks(ctx, d, turn) {
  const { world, send, record, shiftFavour, scene, addMark, meta } = ctx;
  const th = d.threat;
  const spec = DIRECTOR.threats[th.kind];
  const at = world.cities.find((c) => c.id === th.city);
  const crown = crownOf(world);
  let cost = "";
  if (at && th.kind === "host") {
    // The nearest crown town not the King's seat is taken (the seat itself is only sacked).
    const near = world.cities.filter((c) => c.owner === crown?.id).sort((a, b) => dist(a, at) - dist(b, at));
    const target = near.find((c) => !c.capital) ?? near[0];
    if (target) {
      if (!target.capital) send(`lua cmd ${Lua.transferCity(target.id, th.house)}`);
      send(`lua cmd realm_host(realm_find_player(${th.house}), ${target.x}, ${target.y}, {"Pikemen","Archers","Knights"}, ${3 + Math.floor(th.n / 2)})`);
      addMark?.("sack", target.x, target.y, turn);
      scene("sack", { x: target.x, y: target.y, city: target.id, owner: th.house });
      cost = target.capital ? `${cityName(target.id)} is sacked under the King's own walls` : `${cityName(target.id)} is stormed and taken; it flies ${th.houseName}'s banner now`;
    }
  } else if (at && th.kind === "famine") {
    // The town's own fields waste and its granary is lost: Freeciv starves it, and it shrinks.
    send(`lua cmd ${blightLua(at.id, "Desert", 0.9, 16)}`);
    send(`lua cmd local c = find.city(nil, ${at.id}); local g = find.building_type("Granary"); if c and g and c:has_building(g) then edit.remove_building(c, g) end`);
    for (const c of world.cities.filter((x) => x.owner === at.owner && x.id !== at.id).sort((a, b) => dist(a, at) - dist(b, at)).slice(0, 2)) send(`lua cmd ${blightLua(c.id, "Desert", 0.5, 12)}`);
    scene("famine", { x: at.x, y: at.y, city: at.id });
    shiftFavour({ [th.house]: -8 }, "the famine the crown let spread");
    record({ turn, kind: "death", text: `At ${th.townName} the old and the young die first; the granary is eaten and burnt for warmth.`, city: at.id });
    cost = `${th.townName} starves, and its neighbours' fields fail`;
  } else if (th.kind === "pretender") {
    // The claim is proclaimed: the usurper's path in stakes.js once it takes one (builder 1), and the houses' trust meanwhile.
    if (typeof Stakes.raisePretender === "function") Stakes.raisePretender(th.house);
    if (at) scene("vigil", { x: at.x, y: at.y, city: at.id, strength: 1 });
    shiftFavour({ [th.house]: -15 }, "a pretender's claim");
    for (const p of great(world)) if (p.id !== th.house) shiftFavour({ [p.id]: -3 }, "a pretender in the realm, and the King silent");
    cost = "the loyal houses ask why the crown stayed silent";
  }
  kingDeeds.unheard(meta);  // the realm waited on him, and he said nothing: toward the Absent
  record({ turn, kind: "rebellion", text: `${fill(spec.broke, th)}${cost ? `: ${cost}` : ""}.`, city: th.city });
  d.last = th.kind;
  d.threat = null;
  d.rest = th.finale ? 0 : DIRECTOR.breather;  // the finale is the end's own peak: no breather after it
}

// A decree given (routes_decree.js), weighed against the threat (data answers):
// one that ends it ends it; a cheap gesture only buys a season or two, which the
// lord remembers; grain eases a famine, and ends it only if enough arrives in time.
export function answered(meta, cmd, world, record) {
  const th = meta?.director?.threat;
  if (!th) return false;
  const spec = DIRECTOR.threats[th.kind];
  const ans = spec.answers[cmd.action];
  if (!ans) return false;
  const city = world?.cities?.find((c) => c.id === Number(cmd.city));
  const here = ans.anywhere || (ans.toHouse && Number(cmd.to) === th.house) || (city && (city.id === th.city || (th.kind !== "famine" && city.owner === th.house)));
  if (!here) return false;
  const turn = world?.turn ?? 0;
  const pass = () => {
    record({ turn, kind: "court", text: `${fill(spec.passed, th)}.`, city: th.city });
    meta.director.last = th.kind;
    meta.director.threat = null;
    meta.director.rest = meta.lastAct ? 0 : DIRECTOR.breather;
  };
  if (ans.ends) pass();
  else if (ans.ease) {
    th.level = Math.max(0, th.level - ans.ease);
    if (th.level <= 0.01) pass();
    else record({ turn, kind: "court", text: `The King's grain reaches ${th.townName}; the hunger eases, but it is not over.`, city: th.city });
  } else if (ans.delay) {
    const seasons = th.n >= 6 && ans.bigDelay ? ans.bigDelay : ans.delay;
    th.level = Math.max(0, th.level - spec.grow * seasons);
    th.bought = (th.bought ?? 0) + 1;
    record({ turn, kind: "court", text: `${th.houseName} takes the King's gift and waits at ${th.townName}${th.bought > 1 ? ", and asks for more" : ""}. The host is not sent home.`, city: th.city });
  }
  chron.saveMeta(meta);
  return true;
}

// How soon the threat lands, in seasons, and what it's called in a line (next.js):
// it breaks on the season its growth would carry it to 1.
export function due(meta) {
  const th = meta?.director?.threat;
  if (!th) return null;
  const spec = DIRECTOR.threats[th.kind];
  const step = th.step ?? spec.grow;
  return { seasons: Math.max(1, Math.ceil((1 - th.level) / step - 1e-6)), level: th.level, city: th.city, town: th.townName, short: fill(spec.short ?? spec.says[0], th) };
}

// The threat as a matter for the Hand (counsel.js): its place, how near it is to breaking, the orders that answer it there.
export function matter(meta) {
  const th = meta?.director?.threat;
  if (!th) return null;
  const spec = DIRECTOR.threats[th.kind];
  const stage = Math.min(spec.says.length - 1, Math.floor(th.level * spec.says.length));
  return {
    urgency: Math.round(70 + th.level * 30), occur: th.since, kind: `threat:${th.kind}`,
    text: fill(spec.says[stage], th), why: fill(spec.why, th),
    place: { city: th.city, x: th.x, y: th.y, name: th.townName },
    // The Hand offers what one order can do; a grant or a match (which need the King's own town, or a second house) he gives from a town's card.
    acts: Object.entries(spec.answers).filter(([action, a]) => !a.toHouse && action !== "marriage").map(([action, a]) => ({ label: a.label, action, ...(a.anywhere ? {} : { city: th.city }) })),
  };
}

// A King too comfortable draws envy: the strongest other house cools, and the next threat comes sooner.
function pushback(ctx, d, turn, peace) {
  const { world, favourOf, shiftFavour, record } = ctx;
  const p = DIRECTOR.pushback;
  const houses = great(world);
  const purse = crownOf(world)?.gold ?? 0;
  const warm = houses.reduce((s, h) => s + favourOf(h.id), 0) / Math.max(1, houses.length);
  if (peace < p.peace || purse < p.purse || warm < p.favour || turn - d.pushedAt < p.every || d.threat) return;
  const strongest = [...houses].sort((a, b) => world.cities.filter((c) => c.owner === b.id).length - world.cities.filter((c) => c.owner === a.id).length)[0];
  d.pushedAt = turn;
  d.envious = strongest.id;  // the next threat is theirs
  d.calm = Math.max(d.calm, DIRECTOR.quietSeasons - 1);  // the next threat comes sooner
  shiftFavour({ [strongest.id]: -p.envy }, "envy of a crown grown too strong");
  record({ turn, kind: "unrest", text: `${houseFor(strongest).name} watches the crown grow rich and sure of itself, and does not like it.` });
}
