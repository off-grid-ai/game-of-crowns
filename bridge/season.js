// The season and the turn: what happens each time Freeciv turns (turn: the
// land heals, the tithe and the season's reckoning, then, staggered so the AI
// can finish its moves, the stakes, the people's yearly moves, the weather,
// the story arcs, the world's snapshot and the minds); the season's sequence
// itself (collectTithe: the court sits, the King's works, the campaigns,
// favour fading and drifting, the tithe, the goal); the people's yearly moves
// (runSeason); a house turning against the crown and the one rule for every
// rising (turnHouses, storyMarch, askUltimatum, mayRise, rose); the one truce
// writer (houseTruce, keepTruce, councilRuled). Nothing here reads server.js: the realm's state and the
// bridge's own helpers come in as one context argument, built fresh by
// server.js on each call (getters for what it reassigns, read live inside the
// turn's timers), and server.js keeps wrappers of the
// same names where its own code still calls them.

import * as Damage from "./damage.js";
import * as Opening from "./opening.js";
import * as Reword from "./reword.js";
import * as Seals from "./seals.js";
import * as Next from "./next.js";
import * as Director from "./director.js";
import * as Lua from "./lua.js";
import { houseFor, cityName } from "./narrator.js";
import { decree, clampFavour } from "./crown.js";
import { BANDS, IDLE } from "./favour.js";
import { calendar } from "./stakes.js";
import { isWatched } from "./claude.js";
import * as Weather from "./weather.js";
import * as Hosts from "./hosts.js";
import * as Treasury from "./treasury.js";
import * as chron from "./chronicles.js";
import * as kingDeeds from "./ledger.js";

// --- the turn (onEvent's "turn" branch) ------------------------------------------

export function turn(ctx, ev) {
  const { send } = ctx;
  Next.seasonBegan();  // the next thing's countdown runs from here
  Opening.season(ctx.meta, Number(ev.turn));  // the first winter seen and passed (opening.js)
  Seals.season(ctx.meta, Number(ev.turn));  // the season's royal seal (seals.js)
  Hosts.season({ world: ctx.world, meta: ctx.meta, send, record: ctx.record, besiege: (c) => ctx.startCampaign?.(c) }, Number(ev.turn));  // the King's hosts move on their orders (hosts.js)
  Reword.season();  // one more wording of a court result from the local model, in idle time (reword.js)
  Damage.season(ctx, Number(ev.turn));  // walls battered and mended, houses burnt and rebuilt (damage.js)
  collectTithe(ctx, Number(ev.turn));
  // The storyteller's pace: a threat rises after a quiet stretch and grows until answered (director.js).
  const tc = ctx.treasuryCtx();
  Director.season({ world: ctx.world, meta: ctx.meta, history: tc.history, usurper: ctx.stakes?.s?.usurper?.stage ?? "none", send: ctx.send, record: ctx.record, scene: tc.scene, favourOf: ctx.favourOf, shiftFavour: ctx.shiftFavour, addMark: ctx.addMark, court: ctx.court, detail: ctx.detail }, Number(ev.turn));
  setTimeout(() => ctx.stakes?.tick(Number(ev.turn), ctx.world, { favour: ctx.favourOf, sworn: ctx.sworn, shift: ctx.shiftFavour, send: (l) => send(`lua cmd ${l}`), watched: isWatched(), options: ctx.meta.options ?? {}, usurperMay: Opening.usurperMay(ctx.meta), mayRise: (pid) => mayRise(ctx, pid), ultimatum: (pid) => askUltimatum(ctx, pid), rose: (pid) => rose(ctx, pid) }), 2000);
  if (Number(ev.turn) % 4 === 0) setTimeout(() => runSeason(ctx), 2500);
  // The season's weather, rolled once as the season turns (weather.js, from the reign's seed).
  Weather.advance(ctx.meta, Number(ev.turn), calendar(Number(ev.turn)).season);
  setTimeout(() => ctx.runArcs(1), 4000);
  // Let the AI finish its start-of-turn moves before dumping the world.
  setTimeout(ctx.snapshot, 1500);
  setTimeout(() => ctx.minds?.tick(Number(ev.turn)), 3000);
  if ((Number(ev.turn) - 1) % 4 === 0) ctx.record({ turn: Number(ev.turn), kind: "year", text: `The year ${calendar(ev.turn).year} AC begins.` });
}

// Every four turns (a year of seasons), the people of the realm make their moves.
// (One run at a time, across realms, as the bridge's own flag was.)
let seasonRunning = false;
export async function runSeason(ctx) {
  const { world, meta, court, stakes, send } = ctx;
  if (!world || seasonRunning || !court) return;
  seasonRunning = true;
  try {
    await court.season(world, { wetHarvest: () => Weather.wetHarvest(meta.weather),
      // The crown's purse below one big thing's worth: the court may hear of it (economy.json thin).
      thinTreasury: () => (ctx.world?.players?.find((p) => houseFor(p).crown)?.gold ?? 0) < Treasury.ECONOMY.thin,
      deed: (key, pid) => ctx.treasuryCtx().deed(kingDeeds.tagsFor("realm", key), { act: false, place: houseFor(ctx.world?.players?.find((p) => p.id === pid) ?? {}).name ?? "" }),
      favour: ctx.favourOf, cause: ctx.causeOf, warded: (pid) => (stakes?.s.wards?.[pid] ?? -1) > (ctx.world?.turn ?? 0) || ctx.sworn(pid), send: (l) => send(`lua cmd ${l}`), shift: ctx.shiftFavour, watched: isWatched(), options: meta.options ?? {}, ...ctx.heardCtx(), mayRise: (pid) => mayRise(ctx, pid), rose: (pid) => rose(ctx, pid) });
  } catch (err) {
    console.error("season:", err);
  } finally {
    seasonRunning = false;
  }
}

// --- a house turning, and the rising gate ------------------------------------------

// A house turning against the King: each season it stays under 25 its anger
// fills; after TURNING seasons its lord sends the crown an ultimatum (a crisis
// at court). Only an ultimatum refused, or left to burn down, lets him raise
// his banners; won back above 25, the anger drains away. While it stays under 25
// its seat raises a Grievance (realmrules: three townsmen fewer content in each of
// its towns), so Freeciv's AI has to calm its people (minstrels, luxury) at the
// cost of their work. Freeciv's AI never lets a town riot, so riots can't be the clock.
export const TURNING = 2;
export const RISE_IN = 2;  // seasons from a refused ultimatum to the host marching
export function turnHouses(ctx, turn) {
  const { world, meta, stakes, send, record, favourOf } = ctx;
  const turning = (meta.turning ??= {});
  const aggrieved = [];
  for (const p of world?.players ?? []) {
    if (houseFor(p).wild || houseFor(p).crown || !world.cities.some((c) => c.owner === p.id)) continue;
    // A house whose heir is the King's ward neither threatens nor rises while the ward lives at court
    // (the ward's promise, kept: gameplay review #2); its anger waits for the child to go home.
    if (warded(ctx, p.id)) continue;
    if (favourOf(p.id) < BANDS.cooling) aggrieved.push(p.id);
    // A realm from before ultimatums: a house already under 25 is one season from sending its own.
    const t = (turning[p.id] ??= { seasons: favourOf(p.id) < BANDS.cooling ? TURNING - 1 : 0, state: null });
    if (favourOf(p.id) < BANDS.cooling) t.seasons = Math.min(TURNING, t.seasons + 1);
    else {
      t.seasons = Math.max(0, t.seasons - 1);
      if (t.seasons === 0 && t.state !== "refused" && t.march == null) t.state = null;  // a story's march keeps its ultimatum standing
      // Won back while its host gathered: the banners come down, the march is off.
      if (t.riseAt != null) {
        Object.assign(t, { state: null, march: null, riseAt: null, seasons: 0 });
        record({ turn, kind: "decree", text: `${houseFor(p).name} lowers its banners. The King has won them back, for now.` });
      }
    }
    // An ultimatum refused (or met with nothing that won the house back) becomes the
    // rising itself, not a fresh ultimatum: the banners gather at the house's seat,
    // seen on the map, and the host marches in two seasons unless the King wins
    // the house back first (the judge: a threat you can ignore for free is no threat).
    // (Not while its host already marches on Kingsmere: the banners gathered once; gameplay review #9.)
    const marching = stakes?.s?.usurper?.stage === "march" && stakes.s.usurper.house === p.id;
    if (t.state === "refused" && t.march == null && !marching && favourOf(p.id) < BANDS.cooling) {
      t.march = 8;
      t.riseAt = turn + RISE_IN;
      const seat = world.cities.find((c) => c.owner === p.id && c.capital) ?? world.cities.find((c) => c.owner === p.id);
      if (seat) ctx.scene?.("muster", { x: seat.x, y: seat.y, city: seat.id, owner: p.id, strength: 0.8 });
      record({ turn, kind: "unrest", text: `${houseFor(p).name}'s banners gather${seat ? ` at ${cityName(seat.id)}` : ""}. The King's answer did not satisfy them: in ${RISE_IN} seasons their host marches on Kingsmere.`, city: seat?.id });
    }
    // A story's march, held for its ultimatum: it goes once the King refused, or let it lie (and a gathering host, once its seasons are out).
    if (t.march != null && mayRise(ctx, p.id) && (t.riseAt == null || turn >= t.riseAt)) {
      if (stakes?.declare(p.id, world, { send: (l) => send(`lua cmd ${l}`) }, t.march)) Director.crisis(meta);
      t.march = null;
      t.riseAt = null;
    }
    // An ultimatum met (favour shown, anger drained) calls the story's march off.
    if (t.march != null && !t.state) t.march = null;
    if (t.seasons >= TURNING && !t.state && !Opening.quiet(meta)) {  // no ultimatum before the first winter has passed (opening.js)
      t.state = "sent";
      t.at = turn;
      record({ turn, kind: "unrest", text: `${houseFor(p).name} sends a rider to Kingsmere with an ultimatum for the King.` });
    }
  }
  send(`lua cmd ${Lua.grievance(aggrieved)}`);  // the cold houses' towns bear their Grievance; the rest are free of it
}
// A story that would march a house on Kingsmere: if its ultimatum has been
// refused (or gone two seasons unanswered) the host marches now; otherwise
// the ultimatum goes to court first, and the march waits for its answer.
export function storyMarch(ctx, pid, size) {
  const { world, meta, stakes, send } = ctx;
  if (mayRise(ctx, pid)) {
    const marched = stakes?.declare(pid, world, { send: (l) => send(`lua cmd ${l}`) }, size);
    if (marched) Director.crisis(meta);
    return marched;
  }
  askUltimatum(ctx, pid).march = size ?? 10;
  chron.saveMeta(meta);
}

// A house about to rise sends the crown its ultimatum first (one rule for every
// rising: a story's march, the pretender's claim, a turned house). Sent once; its
// answer decides (mayRise).
export function askUltimatum(ctx, pid) {
  const { world, meta, record } = ctx;
  const t = ((meta.turning ??= {})[pid] ??= { seasons: TURNING, state: null });
  if (!t.state) {
    t.state = "sent";
    t.at = world?.turn ?? 0;
    const p = world?.players?.find((x) => x.id === pid);
    if (p) record({ turn: t.at, kind: "unrest", text: `${houseFor(p).name} sends a rider to Kingsmere with an ultimatum for the King.` });
    chron.saveMeta(meta);
  }
  return t;
}

// Whether a lord may raise his banners against the crown: only after his ultimatum.
// Refused, or two seasons gone since it came with no favour shown: then the rising.
// After a crisis the realm gets its breather first (director.js resting): the rising waits, it isn't lost.
export const warded = (ctx, pid) => (ctx.stakes?.s?.wards?.[pid] ?? -1) > (ctx.world?.turn ?? 0);
export const mayRise = (ctx, pid) => { const { world, meta } = ctx; const t = meta.turning?.[pid]; return !warded(ctx, pid) && !Director.resting(meta) && (t?.state === "refused" || (t?.state === "sent" && (world?.turn ?? 0) - t.at >= 2)); };
export function rose(ctx, pid) {
  const t = ctx.meta.turning?.[pid];
  if (t) { t.state = null; t.seasons = 0; }
  Director.crisis(ctx.meta);  // a house has risen: the breather follows
}

// --- the season's sequence ---------------------------------------------------------

// Each turn the crown takes its tithe; a heavy tithe wears favour down.
// (The tally, lastSeason and favourPast objects stay in server.js: the view,
// the treasury and the favour book read them.)
export function collectTithe(ctx, turn) {
  const { world, meta, favour, favourWhy, favourPast, deeds, record, favourOf } = ctx;
  ctx.flushHeld();  // last season's grouped lines
  // The court sits each season (courtSeason).
  ctx.courtSeason(turn).catch((err) => console.error("court season:", err));
  if (!world) return;
  ctx.royalWorks(turn);
  favourPast[turn] = { ...favour };
  ctx.resolveCampaigns(turn);
  // Old grievances and kindnesses fade (about half in five years), so the cause
  // the Hand names is what moves a house now, not a lifetime's sum.
  for (const id of Object.keys(favourWhy)) {
    favourWhy[id] = (favourWhy[id] ?? []).map((r) => ({ ...r, d: r.d * 0.97 })).filter((r) => Math.abs(r.d) >= 1);
  }
  for (const t of Object.keys(favourPast)) if (Number(t) < turn - 8) delete favourPast[t];
  // The season's tithe, its wagons and its deed (treasury.js).
  Treasury.tithe(ctx.treasuryCtx(), turn);
  const wear = isWatched() ? meta.tithe * Treasury.ECONOMY.tithe.wear : 0;  // data/economy.json: at 10%, 0.4 a season; the drift to 55 outweighs it
  for (const p of world.players) {
    if (houseFor(p).wild || houseFor(p).crown) continue;
    const before = favourOf(p.id);
    // Favour drifts back toward the house's own temper, minus the tithe's wear.
    // Gratitude fades: a house well above its own temper cools faster than one near it.
    const rest = ctx.restingFavour(p);
    favour[p.id] = clampFavour(before + (rest - before) * (before - rest > 15 ? 0.08 : 0.03) - wear);
    if (wear) ctx.noteFavour(p.id, -wear, "the royal tithe");
    // A heavy tithe, year on year, becomes a deed of its own: what a house paid
    // in a year it remembers at the year's end.
    const pain = (deeds._tithe ??= {});
    pain[p.id] = (pain[p.id] ?? 0) + wear;
    if (turn % 4 === 0) { if (pain[p.id] >= 3) ctx.recordDeed(p.id, -pain[p.id], "the royal tithe", turn - 1); pain[p.id] = 0; }
    if (before >= 20 && favour[p.id] < 20) {
      const why = ctx.causeOf(p.id);
      record({ turn, kind: "unrest", text: `${houseFor(p).name} speaks openly against the crown. Their loyalty hangs by a thread.${why ? ` They have not forgotten ${why}.` : ""}` });
    }
  }
  ctx.saveFavour();
  idle(ctx, turn);
  // The reign's goal: every great house firmly the King's (GOAL_FAVOUR and up)
  // and no war between them. Marked once in the chronicle when won; lost again
  // when a house falls away or two take up arms.
  const united = ctx.goalNow().won;
  if (united && !meta.united) {
    meta.united = true;
    chron.saveMeta(meta);
    record({ turn, kind: "decree", text: `All ${ctx.goalNow().of} great houses stand behind the King, and none is at war with another. For the first time in a generation the realm answers to one crown, in truth and not in name.` });
  } else if (!united && meta.united) {
    meta.united = false;
    chron.saveMeta(meta);
  }
  Treasury.reckoning(ctx.treasuryCtx(), turn);
}

// A King who gives no order and no ruling for a year is thought asleep (data/favour.json idle;
// gameplay review #8: a reign run out with no orders at all was "A steady hand"): every great house
// cools each season after, and the chronicle says so once, until he acts again (reign.js deed).
export function idle(ctx, turn) {
  const { world, meta, record } = ctx;
  if (!world || meta.status !== "running" || !meta.minutes || !isWatched() || meta.lastActAt == null) return;
  const since = turn - meta.lastActAt;
  if (since < IDLE.seasons) return;
  const great = world.players.filter((p) => !houseFor(p).wild && !houseFor(p).crown && world.cities.some((c) => c.owner === p.id));
  ctx.shiftFavour(Object.fromEntries(great.map((p) => [p.id, -IDLE.cool])), "the King's long silence");
  if (!meta.idleTold) {
    meta.idleTold = true;
    chron.saveMeta(meta);
    record({ turn, kind: "unrest", text: `No word has come from the throne in ${since} seasons. The great houses whisper that the King sleeps, and each begins to look to its own.` });
  }
}

// --- truces ----------------------------------------------------------------------

// A commanded peace: the two lords' houses keep a truce (no raids, no plots).
// The one truce writer (SSOT): every truce between two houses, from a decree,
// a court ruling, a story or a royal match, comes here. Freeciv's own ceasefire,
// so its AI stops fighting too (it ends by itself after `seasons`); its reload
// runs only behind a sitting court, where the realm is already held and the
// card covers the screen, otherwise it waits for one. The houses' truce is
// keyed to them, whoever leads them; the goal and the panels read Freeciv's.
export function houseTruce(ctx, pair, seasons = 16) {
  const { world, meta, court } = ctx;
  if (!court || pair[0] === pair[1]) return;
  ctx.diplomacy([pair[0], pair[1], seasons]);
  court.truces ??= {};
  const key = `h:${Math.min(...pair)}:${Math.max(...pair)}`;
  court.truces[key] = Math.max(court.truces[key] ?? 0, (world?.turn ?? 0) + seasons);
}

export function keepTruce(ctx, pair) {
  const { world, court } = ctx;
  if (!court) return;
  houseTruce(ctx, pair, 16);
  const [a, b] = pair.map((pid) => court.lordOfHouse(pid));
  if (!a || !b) { court.saveCourt?.(); return; }
  court.truces[[a.id, b.id].sort().join(":")] = (world?.turn ?? 0) + 16;
  court.remember(a.id, `The King commanded peace with ${b.house}, and I bowed to it.`);
  court.remember(b.id, `The King commanded peace with ${a.house}, and I bowed to it.`);
  court.saveCourt?.();
}

// The King commanded peace at the council: both hosts are turned home, as the
// peace decree does (crown.js), the blood-price already paid at court.
export function councilRuled(ctx, beat, option) {
  const { world, meta, send, causeOf } = ctx;
  const pair = meta.councilWar?.[beat];
  if (option !== "peace" || !pair || !world) return;
  const [a, b] = world.cities.some((x) => x.owner === pair[0]) ? pair : [pair[1], pair[0]];
  const c = world.cities.find((x) => x.owner === a);
  if (!c) return;
  // The court took the blood-price already: the decree's own fee is waived (its first line pays it).
  const r = decree({ action: "peace", city: c.id, to: b, price: 0, favourOf: () => 60, causeOf }, { ...world, players: world.players.map((p) => houseFor(p).crown ? { ...p, gold: 1e9 } : p) });
  if (r.error) { console.error("council peace:", r.error); return; }
  (r.lua ?? []).slice(1).forEach((l) => send(`lua cmd ${l}`));
  if (r.truce) keepTruce(ctx, r.truce);
}
