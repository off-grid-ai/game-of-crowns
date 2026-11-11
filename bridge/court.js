// The court's sitting and its rulings: once a season the court sits and the
// realm holds still (courtSeason, hold, pace, callMatter), the Hand's word on
// each petition (handLine) and what stands before the King (docket); a ruling
// on a petition and how the realm sees it (rule, rulingScene, say); the King
// answering the Hand's matter (answerMatter) or closing the court and letting
// his silence answer (closeCourt, closeIfDone); and the court's own record of
// what it has heard (courtYearOf, heardCtx, courtCtx). Nothing here reads
// server.js: the realm's state and the bridge's own helpers come in as one
// context argument, built fresh by server.js on each call (getters for what it
// reassigns, which the sitting reads again after each await; setSitting for the
// hold); server.js keeps wrappers of the same names.

import * as Treasury from "./treasury.js";
import { houseFor, cityName } from "./narrator.js";
import { BANDS } from "./favour.js";
import { calendar } from "./stakes.js";
import { matterKey } from "./counsel.js";
import { isWatched, ruleFrom, reactTo } from "./claude.js";
import * as chron from "./chronicles.js";
import * as kingDeeds from "./ledger.js";
import { recordRuling } from "./favourbook.js";

// A ruling on a petition, by option: the treasury pays, the realm changes,
// favour shifts, the chronicle and the world show it. Shared by a chosen
// option and a ruling in the King's own words.
export function rule(ctx, id, option) {
  const { world, meta, court, crowns, deed, send, marchOn, shiftAndTell, record } = ctx;
  const asked = court.petitions.find((x) => x.id === id && !x.answered)?.options?.find((o) => o.id === option);
  const petition = court.petitions.find((x) => x.id === id);
  // The price as the docket showed it: worn with use (treasury.js), like a decree's.
  const wearKey = petition ? `court:${petition.kind}:${option}` : null;
  const price = asked?.cost ? Treasury.worn(meta, wearKey, asked.cost, world.turn ?? 0) : 0;
  const purse = world.players.find((p) => houseFor(p).crown)?.gold ?? 0;
  if (price && purse < price) return { error: crowns(`the treasury holds ${purse} gold`) };
  if (petition?.arc === "siege" && !(meta.campaigns ?? []).some((k) => `siege-${k.city}-${k.turn}` === petition.beat)) {
    petition.answered = true;
    return { error: "The siege is already over; the herald's terms no longer stand." };
  }
  const out = court.answer(id, option, world);
  if (out.error) return out;
  if (out.cost && price) out.cost = price;
  // A ruling that raises the tithe (the thin treasury's answer): never lowers it.
  if (out.tithe != null) { meta.tithe = Math.max(meta.tithe ?? 0, out.tithe); chron.saveMeta(meta); }
  if (petition) {
    const tag = petition.deck ? kingDeeds.tagsFor("deck", petition.kind, option) : petition.kind === "arc" ? (kingDeeds.tagsFor("arc", `${petition.arc}:${petition.beat}`, option) ?? kingDeeds.tagsFor("arc", petition.arc, option) ?? kingDeeds.tagsFor("arc", "story", option)) : kingDeeds.tagsFor("court", petition.kind, option);
    const pc = petition.city != null ? world.cities.find((x) => x.id === Number(petition.city)) : null;
    deed(tag ?? { axes: {} }, { favour: out.favour, place: pc ? cityName(pc.id) : (court.people?.[petition.from]?.house ?? "") });
  }
  // The one who asked remembers what the King answered, in their own words.
  if (petition && asked) court.remember(petition.from, `I went before the King, and he ruled: ${String(asked.label ?? asked.id).toLowerCase()}.`);
  const crownNow = world.players.find((p) => houseFor(p).crown);
  if (out.cost && (crownNow?.gold ?? 0) < out.cost) return { error: crowns(`the treasury holds ${crownNow?.gold ?? 0} gold`) };
  if (out.cost) {
    send(`lua cmd for p in players_iterate() do if p.id == ${crownNow.id} then edit.change_gold(p, -${out.cost}) end end`);
    crownNow.gold -= out.cost;
    Treasury.spend(meta, wearKey, out.cost, world.turn ?? 0);
  }
  out.lua.forEach((l) => send(`lua cmd ${l}`));
  // A ruling that sends the royal host (the siege plea's "relieve"): the same march as the decree.
  if (out.march != null) marchOn(Number(out.march));
  const effects = shiftAndTell(out.favour, "your ruling at court", out.cost);
  // The lord who asked will be back about it, by name, in two seasons: to repay a favour or demand amends.
  const asker = petition && court.people?.[petition.from];
  if (asker && asked && court.deedsOf) {
    const d = Number(out.favour?.[asker.playerId] ?? 0);
    const matter = petition.thread ?? null;
    const what = `heard ${matter ? `us on ${matter}` : "our plea"} at court and ruled: ${String(asked.label ?? asked.id).replace(/ \(.*\)$/, "").toLowerCase()}`;
    recordRuling(court.deedsOf(asker.playerId), { d, what, by: asker.id, turn: world.turn ?? 0 });
  }
  // Every ruling is told, even one whose answer has no words of its own written for it.
  if (!String(out.text ?? "").trim()) out.text = `The King gives his answer${petition ? ` to ${petition.name}` : ""}: ${String(asked?.label ?? option).replace(/ \(.*\)$/, "").toLowerCase()}.`;
  record({ turn: world.turn, kind: "decree", text: out.text });
  rulingScene(ctx, id, option, out);
  return { ok: true, text: crowns(out.text) + (effects ? `\n${effects}` : "") };
}

// A ruling at court made visible: what the King gives goes out from
// Kingsmere by wagon, a ward comes to Kingsmere, and any other word is
// carried by a royal rider to the petitioner's seat.
export function rulingScene(ctx, id, option, out) {
  const { world, court, scene } = ctx;
  const p = court.petitions.find((x) => x.id === id);
  const who = p && court.people[p.from];
  const seat = who && (world.cities.find((c) => c.id === who.seat) ?? world.cities.find((c) => c.owner === who.playerId && c.capital) ?? world.cities.find((c) => c.owner === who.playerId));
  const crown = world.players.find((x) => houseFor(x).crown);
  const king = world.cities.find((c) => c.owner === crown?.id && c.capital) ?? world.cities.find((c) => c.title === "Kingsmere");
  const words = `${option} ${out.text}`.toLowerCase();
  // A hanging or a burning is never shown: the town gathers in silence, then goes home (awareness.gd).
  if (/^(hang|burn)$/.test(option) || /\bhang|\bburn(ed|s|ing)? (the|her|him|them)/.test(words)) {
    const at = seat ?? king;
    if (at) scene("vigil", { x: at.x, y: at.y, city: at.id, strength: 0.9 });
    return;
  }
  if (seat && king && seat.id === king.id) {
    // No journey from Kingsmere to itself: a gift is a feast in its square, a call to arms a muster.
    if (out.cost > 0 || /grant|gift|feast|bless|endow|forgive/.test(words)) scene("feast", { x: king.x, y: king.y, city: king.id, owner: king.owner });
    else if (/levy|march|strike|war|arms/.test(words)) scene("muster", { x: king.x, y: king.y, tx: king.x + 3, ty: king.y + 2, city: king.id });
    return;
  }
  if (!seat || !king) return;
  const go = (kind, from, to) => scene(kind, { x: from.x, y: from.y, tx: to.x, ty: to.y, city: to.id, label: out.text.split(/[.!]/)[0].slice(0, 60) });
  if (p.kind === "match" && /bless|wed|consent|approve/.test(words) && !/refuse|forbid|deny/.test(words)) scene("feast", { x: seat.x, y: seat.y, city: seat.id, owner: seat.owner });
  if (/ward|hostage/.test(words)) go("ward", seat, king);
  else if (/grain|feed|harvest/.test(words)) go("grain", king, seat);
  else if (out.cost > 0) go("tribute", king, seat);
  else go("rider", king, seat);
}

// --- the court's season -------------------------------------------------------
// Once a season the court sits and the realm holds still: Freeciv's turn timer
// stops, and the reign's clock with it. Petitioners bring their matters, and the
// realm's own matters come with the lord of the house they touch; the Hand
// speaks a line on each. The King answers, or closes the court and lets his
// silence answer. Then the doors shut and the realm moves until next season.
// One matter early in the reign, rising to three at the climax; a crisis takes
// the head of the next sitting. No matter is put to him twice in a reign.
// (The realm's matters, counselNow, and whether the court holds the realm,
// sitting, stay in server.js: its clock and routes read them.)
export const isCrisis = (o) => o.urgency >= 75 || /are at war$/.test(o.text);
export const courtYearOf = (ctx) => (ctx.meta.court ??= { sitting: null, hand: {}, heard: {}, lastCall: 0 });
export const heardCtx = (ctx) => ({ heard: (k) => courtYearOf(ctx).heard[k] != null, hear: (k) => { courtYearOf(ctx).heard[k] = ctx.world?.turn ?? 0; } });
export const courtCtx = (ctx) => ({ favour: ctx.favourOf, shift: ctx.shiftFavour, send: (l) => ctx.send(`lua cmd ${l}`), watched: isWatched(), options: ctx.meta.options ?? {}, ...heardCtx(ctx) });

export function hold(ctx, on) {
  const { meta, send, timeoutNow } = ctx;
  // An act told back holds the realm until the King has read it, whatever else lets go.
  on = on || (meta?.status === "running" && meta?.interlude != null && !meta.interlude.seen);
  // Only while the King watches: a realm left alone lives on, court or no court.
  on = on && isWatched();
  if (ctx.sitting === on) return;
  ctx.setSitting(on);
  send(`set timeout ${timeoutNow()}`);
}

function callMatter(ctx, o, turn, crisis) {
  const c = courtYearOf(ctx);
  c.hand[o.key] = { crisis, sitting: turn };
  c.heard[o.key] = turn;
}

// The court's pace: it sits only when it has something worth hearing. Through
// the first half of the reign that is one matter every third season; in the
// third quarter one or two every other season; at the climax every season, one
// to three (about two); with no clock, one every other season. The petitions
// setting thins or thickens it. Over a 15-minute reign: about 18 matters in 18
// minutes of play, so one decision a minute, the board the King's about 80%
// of the time (at ten seconds a decision).
function pace(ctx) {
  const { meta } = ctx;
  const k = meta.minutes ? meta.elapsedMs / (meta.minutes * 60000) : null;
  const r = Math.random();
  let want = k == null || k < 0.5 ? 1 : k < 0.75 ? (r < 0.5 ? 1 : 2) : (r < 0.4 ? 1 : r < 0.8 ? 2 : 3);
  const how = meta.options?.petitions;
  if (how === "rare") want = Math.max(1, want - 1);
  if (how === "often") want = Math.min(3, want + 1);
  return { every: courtEvery(meta), want };
}
// Seasons between full sittings (pace above; next.js counts down to the next one).
export function courtEvery(meta) {
  const k = meta.minutes ? meta.elapsedMs / (meta.minutes * 60000) : null;
  let every = k == null ? 2 : k < 0.5 ? 3 : k < 0.75 ? 2 : 1;
  const how = meta.options?.petitions;
  if (how === "rare") every += 1;
  if (how === "often") every = Math.max(1, every - 1);
  return every;
}
export const HAND_YEAR = 4;  // seasons: the Hand calls the King in for a crisis at most once a year

// force (a test reign's /test/court): sit now, watched or not, due or not, even with no one waiting.
export async function courtSeason(ctx, turn, force = false) {
  // world and counselNow are read again after each await: a snapshot may replace them meanwhile.
  let { world, meta, court, counselNow } = ctx;
  const { record, ceasefire, turnHouses } = ctx;
  if (!court || !world) return;
  const c = courtYearOf(ctx);
  // A matter the realm settled on its own (the famine ended, the war is over) goes quietly.
  if (counselNow.length) for (const key of Object.keys(c.hand)) if (!counselNow.some((x) => x.key === key)) delete c.hand[key];
  turnHouses(turn);  // watched or not: a house turns, and warns, either way
  if ((!isWatched() && !force) || c.sitting != null) { chron.saveMeta(meta); return; }
  const { every, want: wanted } = pace(ctx);
  const crises = counselNow.filter((o) => isCrisis(o) && o.acts?.length && c.heard[o.key] == null && !c.hand[o.key]);
  // A herald's terms under a siege can't wait for the next sitting: the court sits for them.
  const herald = court.petitions.some((p) => !p.answered && p.called == null && p.arc === "siege");
  // Back from away with a matter waiting: the court sits at once.
  const back = c.sitOnReturn && court.petitions.some((p) => !p.answered && p.called == null);
  c.sitOnReturn = false;
  const due = force || c.lastSat == null || turn - c.lastSat >= every || herald || back;
  // Between sittings the Hand calls the King in only for a real crisis, at most once a year.
  // An ultimatum always reaches the King the season it's sent (one court flow): a house
  // never rises on terms he didn't see, whatever the Hand's once-a-year rule says.
  const ultimatum = crises.some((o) => o.kind === "ultimatum");
  const push = !due && crises.length > 0 && (ultimatum || c.lastPush == null || turn - c.lastPush >= HAND_YEAR);
  if (!due && !push) { chron.saveMeta(meta); return; }
  let want = wanted;
  // A lord whose town starves or is besieged speaks for it first, ahead of the
  // Hand (the judge: urgency beats the rotation, and a face beats a report).
  const pleas = await court.callCrises(world, turn, Math.min(2, want), courtCtx(ctx));
  ({ world, meta, court, counselNow } = ctx);
  want -= pleas.length;
  const pleading = new Set(pleas.map((p) => court.people[p.from]?.playerId));
  // A lord the King ruled on two seasons ago comes back by name: a seat of their
  // own at a full sitting, ahead of the Hand's matters (a promise kept, not a draw).
  if (due) {
    const returns = await court.callReturns(world, turn, 1, courtCtx(ctx));
    ({ world, meta, court, counselNow } = ctx);
    want -= returns.length;
  }
  const ownerOf = (o) => world.cities.find((x) => x.id === o.acts?.[0]?.city)?.owner;
  // The crises head the sitting, two at most (a realm in crisis is pressed, not
  // flooded); the gravest first, the rest wait for the next sitting.
  for (const o of crises.filter((o) => !pleading.has(ownerOf(o))).slice(0, Math.max(0, 2 - pleas.length))) { callMatter(ctx, o, turn, true); want--; }
  if (!push) {
    // The lords come first (the judge: a court of people, not an advisor's list);
    // the Hand brings his own routine matter only to a seat they left empty.
    const before = court.petitions.filter((p) => !p.answered && p.called === turn).length;
    if (want > 0) await court.callSitting(world, turn, want, courtCtx(ctx));
    ({ world, meta, court, counselNow } = ctx);
    want -= court.petitions.filter((p) => !p.answered && p.called === turn).length - before;
    const own = counselNow.find((o) => !isCrisis(o) && o.acts?.length && c.heard[o.key] == null && !c.hand[o.key]);
    if (own && want > 0) { callMatter(ctx, own, turn, false); want--; }
    // A story's matter waiting in the hall is heard now, whatever the count.
    for (const p of court.petitions) if (!p.answered && p.called == null && p.kind === "arc") p.called = turn;
  }
  // Only now, with the matters called, does the court sit (a reading taken
  // meanwhile must not find an empty court and close it under them).
  const n = Object.keys(c.hand).length + court.petitions.filter((p) => !p.answered && p.called != null).length;
  if (n || force) {
    c.sitting = turn;
    c.forced = force;  // a test's sitting stays open until it is closed (/court/close)
    c.push = push;
    if (push) c.lastPush = turn;
    else c.lastSat = turn;
    c.lastCall = Date.now();
    hold(ctx, true);
    // Ceasefires the King ordered away from court reload now, behind the card.
    const pending = meta.pendingCease ?? [];
    meta.pendingCease = [];
    ceasefire(pending).catch((e) => console.log("ceasefire:", e.message));  // all of them, one reload
    record({ turn, kind: "court", text: push ? `The Hand calls the King to court: ${crises[0].text}.` : `The court sits for the ${calendar(turn).season} of ${calendar(turn).year}: ${n} ${n === 1 ? "matter waits" : "matters wait"} for the King.` });
  } else if (due) c.lastSat = turn;
  chron.saveMeta(meta);
}

// The King closes the court: whatever he left settles itself. Each house takes
// his silence as an answer, the chronicle says so, and the realm moves again.
export function closeCourt(ctx, turn) {
  const { meta, court, counselNow, lapse, lapseOf, shiftFavour } = ctx;
  const c = courtYearOf(ctx);
  for (const key of Object.keys(c.hand)) {
    const o = counselNow.find((x) => x.key === key);
    if (o) {
      lapse({ key: matterKey(o), text: o.text, lapse: lapseOf(o) }, turn);
      // An ultimatum met with silence is refused: now the lord may rise.
      if (o.kind === "ultimatum") for (const t of Object.values(meta.turning ?? {})) if (t.state === "sent" && t.at === o.occur) t.state = "refused";
    }
    delete c.hand[key];
  }
  for (const p of court.petitions.filter((x) => !x.answered && x.called != null)) { court.unheard(p, turn, shiftFavour); kingDeeds.unheard(meta); }
  court.saveCourt?.();
  closeIfDone(ctx, turn, true);
}

// Every matter of the sitting answered (or gone home unheard): the doors close.
export function closeIfDone(ctx, turn, closing = false) {
  const { meta, court, counselNow, record } = ctx;
  const c = courtYearOf(ctx);
  if (c.sitting == null) {
    hold(ctx, false);  // never held with no court sitting
    return;
  }
  // A matter the realm settled on its own while the court sat (the war ended, the
  // famine eased) is off the docket: it must not hold the doors, and the realm, shut.
  if (counselNow.length) for (const key of Object.keys(c.hand)) if (!counselNow.some((x) => x.key === key)) delete c.hand[key];
  const open = Object.keys(c.hand).length || court?.petitions.some((p) => !p.answered && p.called != null);
  if ((open || c.forced) && !closing) return;
  c.sitting = null;
  c.forced = false;
  c.lastCall = Date.now();
  hold(ctx, false);
  record({ turn, kind: "court", text: "The doors of the court close, and the realm moves again." });
  chron.saveMeta(meta);
}

// The Hand's word on a petition, one line, from where the house stands with
// the crown: what the King's answer will cost him with them.
const HAND_ON = {
  remembers: (h) => `${h} has waited a long time to say that, Sire.`,
  informer: () => "Informers are paid by both sides, Sire.",
  justice: (h) => `Rule for ${h} and you make an enemy of the other, Sire.`,
  claim: () => "Whatever you rule, every bannerman is watching, Sire.",
  debt: (h) => `${h} cannot pay, Sire. The question is what it costs you.`,
  grain: () => "Hungry towns remember who fed them, Sire.",
  arc: () => "This is part of a larger tale, Sire. What you rule here, it carries on.",
};
function handLine(ctx, p) {
  const { world, court, favourOf } = ctx;
  const lord = court?.people?.[p.from];
  const h = String(p.house ?? "").replace(/^House /, "");
  if (!lord || !h) return "";
  const f = Math.round(favourOf(lord.playerId));
  const purse = world?.players?.find((x) => houseFor(x).crown)?.gold ?? 0;
  const paid = (p.options ?? []).filter((o) => o.cost);
  if (f < BANDS.cooling) return `${h} is near rising against you, Sire. Send them home empty and they may march.`;
  if (f < 35) return `${h} will remember this, Sire. They are cold to you already.`;
  if (paid.length && paid.every((o) => o.cost > purse)) return "The treasury cannot pay for what they ask, Sire.";
  if (HAND_ON[p.kind]) return HAND_ON[p.kind](h);
  if (f >= 75) return `${h} has served you well, Sire. They will bear a hard answer.`;
  return `${h} will remember this, Sire.`;
}

// What stands before the King now: a crisis first, then the sitting's own
// matters (the realm's, then the petitioners). Empty between sittings.
// Where a matter lives on the map: the town it's about (a deck card's town, a
// story's or the Hand's acts, a threat's own place), else its petitioner's seat,
// else the King's own. {city, x, y, name} in tile coords; the view anchors the
// matter's marker and its choices there (builder 2's anchored card).
export function placeOf(ctx, item) {
  const { world, court } = ctx;
  if (item.place?.x != null) return item.place;
  const town = (id) => (id == null ? null : world?.cities?.find((x) => x.id === Number(id)));
  const seat = (cid) => town(court.people?.[cid]?.seat);
  const crown = world?.players?.find((p) => houseFor(p).crown);
  const c = town(item.city) ?? town(item.roles?.town?.id ?? item.roles?.town) ?? town((item.acts ?? []).find((a) => a.city != null)?.city)
    ?? seat(item.from) ?? world?.cities?.find((x) => crown && x.owner === crown.id && x.capital);
  return c ? { city: c.id, x: c.x, y: c.y, name: c.title ?? c.name } : null;
}

export function docket(ctx) {
  const { world, court, counselNow } = ctx;
  const c = courtYearOf(ctx);
  closeIfDone(ctx, world?.turn ?? 0);
  const ownerOf = (o) => (o.acts ?? []).map((a) => world?.cities?.find((x) => x.id === Number(a.city))).map((x) => x && world.players.find((p) => p.id === x.owner)).find((p) => p && !houseFor(p).crown && !houseFor(p).wild);
  const hand = Object.entries(c.hand).map(([key, m]) => {
    const o = counselNow.find((x) => x.key === key);
    if (!o) return null;
    // Brought by the lord of the house it touches; a matter of the whole realm, by the Hand himself.
    const owner = ownerOf(o);
    const lord = owner ? court.lordOfHouse(owner.id) : null;
    return { id: `hand:${key}`, hand: true, key, crisis: m.crisis, sitting: m.sitting, text: o.text, why: o.why, acts: o.acts, place: o.place ?? null,
      name: lord?.name ?? "The Hand of the King", house: lord ? houseFor(owner).name : "", from: lord?.id ?? null, who: lord ? court.sitter(lord.id) : null, due: null };
  }).filter(Boolean).sort((a, b) => Number(b.crisis) - Number(a.crisis));
  // No fuse at court: the realm holds while it sits, so no timer would tell true.
  // Each option's price as it stands (worn with use), and one line of why when the treasury can't pay it.
  const purse = world?.players?.find((p) => houseFor(p).crown)?.gold ?? 0;
  const priced = (p) => (p.options ?? []).map((o) => {
    if (!o.cost) return o;
    const cost = Treasury.worn(ctx.meta, `court:${p.kind}:${o.id}`, o.cost, world?.turn ?? 0);
    const short = Treasury.shortOf(purse, cost);
    return { ...o, cost, label: String(o.label ?? "").replace(/\(\d[\d,]* gold\)/, `(${cost} gold)`), ...(short ? { short } : {}) };
  }).map((o) => ({ ...o, weighs: court.weighOption?.(court.petitions.find((x) => x.id === p.id) ?? p, o, world) ?? null }));  // whom each answer warms and cools, shown before choosing
  const pets = court.open().filter((p) => p.called != null).map((p) => ({ ...p, options: priced(p), due: null, sitting: p.called, counsel: handLine(ctx, p), push: !!c.push }));
  // A court with nothing left to show the King is no court: the doors close, the realm moves.
  if (c.sitting != null && !hand.length && !pets.length) { c.hand = {}; closeIfDone(ctx, world?.turn ?? 0, true); }
  // Every matter carries its place, and its petitioner's id for their face (null for the Hand himself).
  return [...hand.map((x) => ({ ...x, push: !!c.push })), ...pets].map((x) => ({ ...x, place: placeOf(ctx, x.hand ? x : { ...(court.petitions.find((y) => y.id === x.id) ?? {}), ...x }), petitioner: x.from ?? null }));
}

// --- the court's routes ----------------------------------------------------------

// POST /counsel/answer: the King answered the Hand's matter: it rests a year,
// and the next one comes up.
export function answerMatter(ctx, key) {
  const { world, meta, counselNow } = ctx;
  if (key) {
    // A matter at court is keyed by the matter itself; it rests as its kind does.
    const o = counselNow.find((x) => x.key === String(key));
    (meta.mattersRest ??= {})[o ? matterKey(o) : String(key)] = world?.turn ?? 0;
    // An ultimatum answered: the house's anger starts over (it may turn again).
    // Met only if the answer won the house back above cooling; otherwise it stands refused, and the house rises (season.js).
    if (o?.kind === "ultimatum") for (const [pid, t] of Object.entries(meta.turning ?? {})) if (t.state === "sent" && t.at === o.occur) {
      if ((ctx.favourOf?.(Number(pid)) ?? 50) >= BANDS.cooling) { t.state = null; t.seasons = 0; } else t.state = "refused";
    }
    delete courtYearOf(ctx).hand[String(key)];
    closeIfDone(ctx, world?.turn ?? 0);
    chron.saveMeta(meta);
  }
  return { ok: true };
}

// POST /court/say: the King answers a petition in his own words. The local
// model proposes which ruling he means; nothing happens until he confirms it
// (confirm: the option id), so a misreading can never act on its own.
// Answers [status, body].
export async function say(ctx, { id, words, confirm }) {
  const { meta, court, crowns, record } = ctx;
  const pet = court.petitions.find((x) => x.id === id && !x.answered);
  const said = String(words ?? "").trim().slice(0, 500);
  if (!pet || !said) return [400, { error: "there's no one waiting on that" }];
  const who = court.people[pet.from];
  if (!confirm) {
    const read = await ruleFrom(pet, who, said);
    if (!read) return [503, { error: "Your words hang in the hall unread. (The local model isn't running; choose a ruling instead.)" }];
    const o = pet.options.find((x) => x.id === read.option);
    return [200, { proposed: read.option, label: crowns(o?.label ?? read.option), name: who?.name ?? "" }];
  }
  const reaction = await reactTo(pet, who, said, String(confirm), meta.options?.language ?? "en");
  const out = rule(ctx, id, String(confirm));
  if (out.error) return [400, out];
  record({ turn: ctx.world.turn, kind: "decree", text: `The King to ${who?.name ?? "the petitioner"}: "${said}"` });
  if (who) ctx.court.remember(who.id, `The King told me: "${said.slice(0, 160)}"`);
  return [200, { ...out, option: String(confirm), reaction, name: who?.name ?? "", gender: who?.gender ?? "male" }];
}
