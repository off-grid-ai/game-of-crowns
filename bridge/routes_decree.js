// The crown's orders: a decree and all it sets moving, the King's mood for the court
// (set, revoked, read), the tithe, and the crown's carts and riders arriving
// where they were sent.
// Moved verbatim from server.js's ROUTES table (consolidation C3, step 8): each
// handler is (ctx, req, res, url). Nothing here reads server.js: the bridge's
// state and helpers come in as one context argument (routeCtx), built fresh by
// server.js on each request; the realm's state is read through it (ctx.world,
// ctx.meta...) at the moment it is used, as the handlers read it before, so a
// snapshot or a switch of chronicle during an await is seen.

import * as Seals from "./seals.js";
import * as Hosts from "./hosts.js";
import * as Sittings from "./court.js";
import * as Director from "./director.js";
import * as Treasury from "./treasury.js";
import { WORK_SEASONS } from "./treasury.js";
import * as chron from "./chronicles.js";
import { cityName, houseFor } from "./narrator.js";
import { decree, DECREES } from "./crown.js";
import * as kingDeeds from "./ledger.js";
import * as Damage from "./damage.js";
import * as Rulings from "./rulings.js";
import { moodFrom, moodRules } from "./claude.js";
import { body, json } from "./http_util.js";
import * as names from "./names.js";

export async function issueDecree(ctx, req, res, url) {
  const { yearlyKey, seasonsLeft, priceOf, favourOf, causeOf, sworn, deed, startCampaign, temper, send, shiftAndTell, scene, keepTruce, decreeScenes, record, snapshot, crowns } = ctx;
  ctx.counselStale = true;
  ctx.decreesIssued++;
  const cmd = await body(req);
  if (ctx.meta.status !== "running") return json(res, 400, { error: "this reign has ended" });
  // An order that answers a matter put to him at court (cmd.matter: its key) is a ruling:
  // free of the royal seal, and the matter is answered with it once the order has landed,
  // in this one request (an ultimatum is judged on the favour the order moved).
  const ruling = cmd.matter != null && String(cmd.matter) !== "";
  // Some answers are given only at court, to a matter put to the King (data/decrees.json courtOnly),
  // and some a house has of him once a reign (oncePerHouse: a ward, a promised council seat).
  const spec = DECREES[cmd.action];
  if (spec?.off) return json(res, 400, { error: "the King no longer gives that order" });
  if (spec?.courtOnly && !ruling) return json(res, 400, { error: "that is given only as an answer at court" });
  const onceFor = spec?.oncePerHouse ? (ctx.world.cities.find((c) => c.id === Number(cmd.city))?.owner ?? null) : null;
  if (onceFor != null && ctx.meta.oncePerHouse?.[cmd.action]?.[onceFor] != null) {
    const h = houseFor(ctx.world.players.find((p) => p.id === onceFor) ?? {}).name ?? "That house";
    return json(res, 400, { error: `${h} has had that of the King once this reign` });
  }
  // Between sittings each decree takes a royal seal (seals.js); at a sitting it's a ruling, and free.
  const noSeal = Seals.refuse(ctx.meta, ruling);
  if (noSeal) return json(res, 400, { error: noSeal });
  // A royal match needs a pair: an unwed son or daughter of age from each house,
  // one of each, chosen before a crown is spent. Nobody is wed twice.
  let pair = null;
  if (cmd.action === "marriage" && ctx.court) {
    // (matchFor below finds the same pair the Hand checks before offering a match.)
    const city = ctx.world.cities.find((c) => c.id === Number(cmd.city));
    const [la, lb] = [city?.owner, Number(cmd.to)].map((pid) => ctx.court.lordOfHouse(pid));
    const unwed = (lord) => ctx.court.alive().filter((k) => k.parents?.includes(lord.id) && !k.spouse && k.age >= 15);
    if (la && lb) {
      const kids = unwed(la);
      for (const ka of kids) {
        const kb = unwed(lb).find((k) => k.gender !== ka.gender);
        if (kb) { pair = [la, lb, ka, kb]; break; }
      }
      if (!pair) {
        const none = !kids.length ? la : lb;
        return json(res, 400, { error: `${none.house} has no unwed son or daughter of age to wed to the other house` });
      }
    }
  }
  const yearly = yearlyKey(cmd);
  if (yearly && seasonsLeft(yearly) > 0) {
    const n = seasonsLeft(yearly);
    return json(res, 400, { error: `once a year: again in ${n} season${n === 1 ? "" : "s"}` });
  }
  // March: the King's own biggest host goes (hosts.js), and it is the season's order to his hosts.
  let host = null;
  if (cmd.action === "march" || cmd.action === "reinforce") {
    const hctx = { world: ctx.world, meta: ctx.meta, sworn, crownSeat: ctx.crownSeat };
    host = Hosts.list(hctx)[0] ?? null;
    if (!host) return json(res, 400, { error: "The crown has no host to march" });
    if (Hosts.ordersLeft(hctx) < 1) return json(res, 400, { error: "The King's captains have their orders for this season. The next order goes with the season's turn." });
  }
  const price = priceOf(cmd.action);
  const result = decree({ ...cmd, host, works: ctx.meta.works ?? {}, price, favourOf, causeOf, sworn, warded: (pid) => (ctx.stakes?.s.wards?.[pid] ?? -1) > (ctx.world.turn ?? 0), marching: (city) => (ctx.meta.campaigns ?? []).some((x) => x.city === city), usurper: ctx.stakes?.s.usurper, seat: ctx.stakes?.s.seat }, ctx.world);
  if (result.error) return json(res, 400, result);
  {
    const dc = ctx.world.cities.find((x) => x.id === Number(cmd.city));
    const dp = dc ? ctx.world.players.find((p) => p.id === dc.owner) : ctx.world.players.find((p) => p.id === Number(cmd.house ?? cmd.to));
    const taking = cmd.action === "grant" && Object.values(result.favour ?? {}).some((n) => n < 0);
    const place = /\{house\}/.test(kingDeeds.tagsFor("decree", cmd.action)?.says ?? "") ? (dp ? houseFor(dp).name : "") : (dc ? cityName(dc.id) : "");
    deed(kingDeeds.tagsFor("decree", taking ? "grant_take" : cmd.action), { favour: result.favour, place });
    // Marching on a house inside the King's own truce breaks his word.
    if (cmd.action === "march" && dp && ctx.court && Object.entries(ctx.court.truces ?? {}).some(([k, until]) => k.startsWith("h:") && k.split(":").slice(1).map(Number).includes(dp.id) && until > (ctx.world.turn ?? 0)))
      deed(kingDeeds.tagsFor("realm", "truce_march"), { act: false, place: houseFor(dp).name });
  }
  if (result.endUsurper && ctx.stakes) { ctx.stakes.s.usurper.stage = "none"; ctx.stakes.save(); }
  if (result.relieved != null) { (ctx.meta.relieved ??= {})[result.relieved] = ctx.world.turn ?? 0; chron.saveMeta(ctx.meta); }
  if (result.alliance != null) { (ctx.meta.alliances ??= {})[result.alliance] = (ctx.world.turn ?? 0) + 16; chron.saveMeta(ctx.meta); }
  if (result.march) startCampaign(result.march);
  if (result.hostMarch) {
    // A house that asked the King's help opens its gates to his host (reinforce): its town may be garrisoned.
    const open = result.hostMarch.opens != null ? (pid) => pid === result.hostMarch.opens || sworn(pid) : sworn;
    const [code, out] = Hosts.order({ world: ctx.world, meta: ctx.meta, sworn: open, crownSeat: ctx.crownSeat }, { host: result.hostMarch.host, order: result.hostMarch.order ?? "march", city: result.hostMarch.city, declared: true });
    if (code === 200) result.text = `${result.text} ${out.text.replace(/^.*?: /, "").replace(/^./, (c) => c.toUpperCase())}`;
  }
  if (yearly) { (ctx.meta.decreeAt ??= {})[yearly] = ctx.world.turn ?? 0; chron.saveMeta(ctx.meta); }
  if (onceFor != null) { ((ctx.meta.oncePerHouse ??= {})[cmd.action] ??= {})[onceFor] = ctx.world.turn ?? 0; chron.saveMeta(ctx.meta); }
  // An order given at the threat's place, of a kind that answers it: the threat passes (director.js).
  Director.answered(ctx.meta, cmd, ctx.world, ctx.record);
  // Bought: the same decree again within the year costs more (treasury.js wear).
  Treasury.spend(ctx.meta, `decree:${cmd.action}`, price, ctx.world.turn ?? 0); chron.saveMeta(ctx.meta);
  if (cmd.city != null) { (ctx.meta.answeredAt ??= {})[Number(cmd.city)] = ctx.world.turn ?? 0; chron.saveMeta(ctx.meta); }
  const warmed = ctx.world.cities.find((c) => c.id === Number(cmd.city))?.owner ?? (cmd.house != null ? Number(cmd.house) : null);
  result.favour = temper(cmd.action, warmed, result.favour);
  // A ward holds the house for its seasons (data/decrees.json ward.seasons).
  if (result.ward != null && ctx.stakes) { (ctx.stakes.s.wards ??= {})[result.ward] = (ctx.world.turn ?? 0) + (DECREES.ward.seasons ?? 12); ctx.stakes.save(); }
  // A town taken from a house is remembered, so the Hand can offer it back.
  if (cmd.action === "grant" && cmd.to != null) {
    const town = ctx.world.cities.find((c) => c.id === Number(cmd.city));
    if (town && town.owner !== Number(cmd.to)) { (ctx.meta.taken ??= {})[town.owner] = { city: town.id, to: Number(cmd.to) }; chron.saveMeta(ctx.meta); }
  }
  // Feasting or stripping the house that rose settles what becomes of them.
  const endedU = ctx.stakes?.s.usurper.ended;
  if (endedU && !endedU.settled && ["feast", "grant", "ward"].includes(cmd.action) && ctx.world.cities.some((c) => c.id === Number(cmd.city) && c.owner === endedU.house)) { endedU.settled = true; ctx.stakes.save(); }
  result.lua.forEach((l) => send(`lua cmd ${l}`));
  // Men the decree sends home march there by Freeciv's moves and disband into their seat's work (hosts.js).
  for (const h of result.homeward ?? []) Hosts.homeward({ world: ctx.world, meta: ctx.meta }, h, send);
  if (result.work) (ctx.meta.works ??= {})[result.work.city] = { building: result.work.building, seasons: WORK_SEASONS, left: WORK_SEASONS, since: Date.now(), paid: result.cost ?? 0 };
  // Spend now, so a second decree before the next snapshot can't overdraw the treasury.
  const crownNow = ctx.world.players.find((p) => houseFor(p).crown);
  if (crownNow) crownNow.gold -= result.cost;
  // The result card says what the order cost and whose favour moved, so the
  // King learns the price of his word.
  const effects = shiftAndTell(result.favour, { gift: "a gift of crowns", feast: "a feast in their honour", relief: "grain from the crown", build: "a building paid by the crown", grant: "a town granted or taken", banners: "the King's banners: answered or refused", marriage: "a royal match", peace: "the King's peace", back: "the King took a side", settle: "the King's peace, kept by another house", buyoff: "the King bought off the pretender", ward: "their heir taken as the King's ward", alliance: "an oath to the crown", march: "the royal host" }[cmd.action] ?? "a royal decree", result.cost);
  const seat = ctx.world.cities.find((c) => c.owner === crownNow?.id && c.capital);
  const target = ctx.world.cities.find((c) => c.id === Number(cmd.city));
  // No journey to where the King already is: an order for his own seat simply takes effect there.
  const away = seat && target && target.id !== seat.id;
  if (away && (cmd.action === "relief" || cmd.action === "gift")) scene(cmd.action === "relief" ? "grain" : "tribute", { x: seat.x, y: seat.y, tx: target.x, ty: target.y, city: target.id });
  // Every decree is seen where it lands: a feast at the seat, a town changing
  // hands, the King's rider carrying the crown's purse for a building.
  // A feast is held at court, as the decree says; the honoured house's colours fly over it.
  if (seat && cmd.action === "feast") scene("feast", { x: seat.x, y: seat.y, city: seat.id, owner: target?.owner ?? crownNow.id });
  if (target && cmd.action === "grant") scene("handover", { x: target.x, y: target.y, city: target.id, from: target.owner, to: Number(cmd.to) });
  // Relief, a grant, a building: the town shows it as the same ruling would (rulings.js decreed): the herald cries it.
  if (target) Rulings.decreed(ctx.meta, cmd.action, target.id, ctx.world.turn ?? 0);
  // A word carried (decrees.json <action>.rider: the rider's label): the King's promise rides to the lord's town.
  if (away && DECREES[cmd.action]?.rider) scene("rider", { x: seat.x, y: seat.y, tx: target.x, ty: target.y, city: target.id, label: DECREES[cmd.action].rider });
  if (away && cmd.action === "build") scene("rider", { x: seat.x, y: seat.y, tx: target.x, ty: target.y, city: target.id, label: "The crown's purse for a new building" });
  if (seat && cmd.action === "levy") {
    // The host marches for the town the levy was raised for, else toward the
    // nearest foreign army inside the crown's lands, else down the road a way.
    const foes = ctx.world.units.filter((u) => u.owner !== crownNow.id && !["Workers", "Settlers", "Migrants", "Explorer", "Caravan", "Diplomat"].includes(u.type));
    const near = foes.sort((a, b) => Math.hypot(a.x - seat.x, a.y - seat.y) - Math.hypot(b.x - seat.x, b.y - seat.y))[0];
    const goal = target && target.id !== seat.id ? target : near && Math.hypot(near.x - seat.x, near.y - seat.y) < 12 ? near : { x: seat.x + 3, y: seat.y + 2 };
    scene("muster", { x: seat.x, y: seat.y, tx: goal.x, ty: goal.y, city: seat.id });
  }
  // A commanded peace: the two lords' houses keep a truce (no raids, no plots).
  if (result.truce) keepTruce(result.truce);
  // A royal match: the two lords' heirs (or kin) are named, they warm to each
  // other, and a long truce holds their houses from raids and plots.
  if (result.pact) { ctx.meta.matchesMade = (ctx.meta.matchesMade ?? 0) + 1; chron.saveMeta(ctx.meta); }  // the "wed two houses" ambition (reign.js)
  if (result.pact && ctx.court && pair) {
    const [a, b, ka, kb] = pair;
    {
      ka.spouse = kb.id;
      kb.spouse = ka.id;
      ctx.court.save?.(ka);
      ctx.court.save?.(kb);
      ctx.court.shift(a.id, b.id, 25, `The King bound my house to ${b.house} by marriage.`);
      ctx.court.shift(b.id, a.id, 25, `The King bound my house to ${a.house} by marriage.`);
      ctx.court.makeTruce(a, b, 24, ctx.world);
      ctx.court.remember(a.id, `By the King's word, ${ka.name} is to wed ${kb.name} of ${b.house}.`);
      ctx.court.remember(b.id, `By the King's word, ${kb.name} is to wed ${ka.name} of ${a.house}.`);
      result.text = `By the King's word, ${ka.name} of ${a.house} will wed ${kb.name} of ${b.house}. The two houses are bound by blood; while the bond holds, neither will raise a hand against the other.`;
      ctx.court.saveCourt?.();
    }
  }
  decreeScenes(cmd, result, seat, target);
  record({ turn: ctx.world?.turn ?? 0, kind: "decree", text: result.text, city: cmd.city });
  setTimeout(snapshot, 600);
  const sealed = Seals.spend(ctx.meta, cmd.action, ctx.world.turn ?? 0, ruling);
  if (ruling && ctx.sittingCtx) Sittings.answerMatter(ctx.sittingCtx(), String(cmd.matter));
  // A matter ruled by an order becomes its town's talk too (chatter.afterRuling, as routes_court.answer does).
  if (ruling) {
    const house = (pid) => ctx.world?.players?.find((x) => x.id === Number(pid))?.house?.name;
    const fav = Object.entries(result.favour ?? {});
    ctx.chatter?.afterRuling({ city: cmd.city ?? seat?.id, text: result.text, helps: fav.filter(([, d]) => d > 0).map(([k]) => house(k)).filter(Boolean), hurts: fav.filter(([, d]) => d < 0).map(([k]) => house(k)).filter(Boolean) })?.catch?.(() => {});
  }
  return json(res, 200, { ok: true, text: crowns(result.text) + (effects ? `\n${effects}` : ""), cost: result.cost ?? 0, sealed });
}

export async function arrived(ctx, req, res, url) {
  const { arrivals, record } = ctx;
  // The King's grain, gold or word reached the town it was sent to: the realm
  // sees it, the chronicle says so in his name, and the town remembers.
  const b = await body(req);
  const town = ctx.world?.cities.find((c) => c.id === Number(b.city));
  const what = { grain: "The King's grain reaches", tribute: "The King's gold reaches", ward: "The ward reaches", rider: "The King's rider reaches" }[String(b.kind)];
  if (!town || !what) return json(res, 400, { error: "nothing arrived" });
  const key = `${b.kind}:${town.id}:${b.sent ?? 0}`;
  if (!arrivals.has(key)) {
    arrivals.add(key);
    record({ turn: ctx.world.turn, kind: "crown", city: town.id, text: `${what} ${cityName(town.id)}${b.label ? `: ${String(b.label).slice(0, 80)}` : ""}.` });
  }
  return json(res, 200, { ok: true });
}

// A siege's fire arrow set a town's house alight in the view (fire.gd): the town's damage fact keeps it burnt
// (damage.js), so it survives a reload and the realm rebuilds it in time.
export async function kindled(ctx, req, res, url) {
  const b = await body(req);
  const d = Damage.kindle(ctx.meta, ctx.world, b.city, b.home);
  return d ? json(res, 200, { ok: true, damage: d }) : json(res, 400, { error: "no such town or house" });
}

export async function moods(ctx, req, res, url) {
  return json(res, 200, ctx.court.decrees);
}

export async function revokeMood(ctx, req, res, url) {
  const { id } = await body(req);
  ctx.court.revoke(id);
  return json(res, 200, ctx.court.decrees);
}

export async function setMood(ctx, req, res, url) {
  const { record } = ctx;
  const { text } = await body(req);
  if (!text || !String(text).trim()) {
    ctx.court.setMood(null);
    return json(res, 200, { cleared: true });
  }
  const houses = (ctx.world?.players ?? []).map((p) => houseFor(p)).filter((h) => !h.wild && !h.crown).map((h) => h.name);
  const names = ctx.court.alive().filter((c) => c.rank === "lord" || c.rank === "bannerman" || c.rank === "heir").map((c) => c.name);
  const mood = (await moodFrom(String(text).slice(0, 300), houses, names)) ?? moodRules(String(text).slice(0, 300), houses, names);
  const touched = ctx.court.setMood(mood);
  mood.summary = `${mood.summary} (${touched} ${touched === 1 ? "person" : "people"})`;
  record({ turn: ctx.world?.turn ?? 0, kind: "decree", text: `By the King's word: ${mood.summary}` });
  return json(res, 200, mood);
}

export async function tithe(ctx, req, res, url) {
  const { rate } = await body(req);
  const want = Math.max(0, Math.min(Treasury.ECONOMY.tithe.max, Number(rate) || 0));  // data/economy.json
  if (Math.abs(want - (ctx.meta.tithe ?? 0)) < 0.001) return json(res, 200, { tithe: ctx.meta.tithe });
  // Once a year (data/economy.json tithe.changeEvery): the houses are told the crown's rate for the year.
  const turn = ctx.world?.turn ?? 0;
  const wait = Treasury.titheWait(ctx.meta, turn);
  if (wait > 0) return json(res, 400, { error: `The tithe was set this year. It may change again in ${wait} season${wait === 1 ? "" : "s"}.`, tithe: ctx.meta.tithe, wait });
  ctx.meta.tithe = want;
  ctx.meta.titheSetAt = turn;
  chron.saveMeta(ctx.meta);
  return json(res, 200, { tithe: ctx.meta.tithe, wait: Treasury.titheWait(ctx.meta, turn) });
}



// What an order would do, weighed before it's given (bet 5: who an answer helps
// and hurts is shown before choosing): the same decree and the same tempering
// as the real one, run dry. {cost, helps: [{house, d}], hurts: [{house, d}]},
// or null when it can't be weighed (an unknown order, or one with no favour).
const UNWEIGHED = new Set(["banners"]);  // its answer depends on the houses' mood on the day, and running it counts the call
export function weigh(ctx, act) {
  const { priceOf, favourOf, causeOf, sworn, temper } = ctx;
  if (!act?.action || UNWEIGHED.has(act.action) || !ctx.world) return null;
  const price = priceOf(act.action);
  const plan = decree({ ...act, works: ctx.meta.works ?? {}, price, favourOf, causeOf, sworn, marching: (city) => (ctx.meta.campaigns ?? []).some((x) => x.city === city), usurper: ctx.stakes?.s.usurper, seat: ctx.stakes?.s.seat }, { ...ctx.world, players: ctx.world.players.map((p) => houseFor(p).crown ? { ...p, gold: Math.max(p.gold ?? 0, price) } : p) });
  if (!plan || plan.error) return null;
  const warmed = ctx.world.cities.find((c) => c.id === Number(act.city))?.owner ?? (act.house != null ? Number(act.house) : null);
  const favour = temper(act.action, warmed, plan.favour ?? {}, true);
  const name = (pid) => names.shown(houseFor(ctx.world.players.find((p) => p.id === Number(pid)) ?? {}).name);
  const rows = Object.entries(favour).filter(([, d]) => d).map(([pid, d]) => ({ house: name(pid), d })).filter((r) => r.house);
  return { cost: price, helps: rows.filter((r) => r.d > 0).sort((a, b) => b.d - a.d), hurts: rows.filter((r) => r.d < 0).sort((a, b) => a.d - b.d) };
}
