// What the bridge shows the game: the /world response (worldView), and the
// towns' states (townStates) and their uproar news (uproar), set at each
// snapshot. Nothing here reads server.js: the realm's state and the bridge's
// own helpers come in as one context argument, built fresh by server.js on
// each call (server.js keeps wrappers of the same names).

import { crownOf, northTowns } from "./realm.js";
import * as Risings from "./risings.js";
import * as Households from "./households.js";
import { houseFor, cityName, HOUSES } from "./narrator.js";
import { BUILD_COST, granarySize } from "./rules.js";
import { menOf, SHIPS } from "./hosts.js";
import { DECREES, TITHE_HIGH } from "./crown.js";
import { shortOf, titheWait } from "./treasury.js";
import { BANDS, band } from "./favour.js";
import { calendar } from "./calendar.js";
import { readJson } from "./chronicles.js";
import * as names from "./names.js";
import { situation, scarLine } from "./situation.js";

// Lords whose first names were borrowed from A Song of Ice and Fire, renamed
// in realm.serv; realms begun before then still carry the old names in their
// saved game, so they are shown by the new ones.
const RENAMED = {
  "Lady Olenna Thornvale": "Lady Isolde Thornvale",
  "Lord Robb Stormhold": "Lord Rhys Stormhold",
  "Princess Arianne Sunspire": "Princess Ximena Sunspire",
  "Lord Jon Highfell": "Lord Declan Highfell",
};

// The realm as the view sees it (GET /world): the bridge's world with each
// house, town and unit filled in from the save, the crown, the threat and the
// rest. counsel() reads the same, once a season and after the King acts
// (refreshCounsel), never on every poll.
export function worldView(ctx) {
  const { world, meta, history, court, stakes, turnSeconds, counselNow, scenes, effects, favourWhy, favourPast, lastSeason, detail, favourOf, marchOdds, greatHouses, sworn, priceOf, seasonsLeft, crownOf, crownSeat, reignInfo, storyNow, marksNow, goalNow, CIVILIAN, TURNING, GOAL_FAVOUR, soulsOf } = ctx;
  const d = detail();
  // Each house's head by the one name the court knows them by (gameplay review #10: one lady had three
  // names, Freeciv's leader on /world, another on her court card, a third in the counsel); the title
  // (Lord, Lady, Princess) stays Freeciv's.
  const headOf = (p) => {
    const l = court?.lordOfHouse(p.id);
    const was = RENAMED[p.name] ?? p.name;
    if (!l?.name) return was;
    // The title by the head's own sex (a fresh reign may seat a lady where Freeciv has a lord); a prince stays a prince.
    const royal = /^(Prince|Princess)\b/.test(was);
    return `${l.gender === "female" ? (royal ? "Princess" : "Lady") : royal ? "Prince" : "Lord"} ${l.name}`;
  };
  const players = world.players.map((p) => ({ ...p, name: houseFor(p).crown || houseFor(p).wild ? RENAMED[p.name] ?? p.name : headOf(p), house: houseFor(p), atWarWith: d?.players[p.id]?.atWarWith ?? [] }));
  const cities = world.cities.map((c) => {
    const x = d?.cities[c.id];
    // The lesser family seated here (a bannerman), whose banner the town flies.
    const holder = court?.lordOfTown(c.id);
    const family = holder?.rank === "bannerman" ? holder.surname ?? null : null;
    if (!x) return { ...c, title: cityName(c.id), family };
    const cost = BUILD_COST[x.building] ?? 0;
    return {
      ...c, title: cityName(c.id), family,
      building: x.building, buildingKind: x.buildingKind,
      progress: cost ? Math.min(1, x.shieldStock / cost) : 0,
      ...(!houseFor(world.players.find((p) => p.id === c.owner)).crown && !houseFor(world.players.find((p) => p.id === c.owner)).wild && world.players.some((p) => p.id === c.owner) ? { odds: Math.round(marchOdds(c.owner, greatHouses().filter((p) => p.id !== c.owner && sworn(p.id)).map((p) => p.id), { extra: 8, turn: (world?.turn ?? 0) + 2 }) * 100) / 100 } : {}),
      // The King's own works under way show as the town's building site, rising season by season.
      ...(meta.works?.[c.id] && houseFor(world.players.find((p) => p.id === c.owner)).crown ? { building: meta.works[c.id].building, buildingKind: "Building", royal: true,
        progress: Math.min(0.99, (meta.works[c.id].seasons - meta.works[c.id].left + Math.min(1, (Date.now() - meta.works[c.id].since) / (turnSeconds * 1000))) / meta.works[c.id].seasons), worksLeft: meta.works[c.id].left } : {}),
      // A film's staged work (test reigns only, /test/stage).
      ...(meta.stage?.[c.id] ?? {}),
      // The royal host before this town: seasons until it falls or holds.
      ...((() => { const s = (meta.campaigns ?? []).find((k) => k.city === c.id); return s ? { siegeLeft: Math.max(1, 2 + (s.extra ?? 0) - ((world?.turn ?? s.turn) - s.turn)) } : {}; })()),
    };
  });
  const units = world.units.map((u) => {
    const x = d?.units[u.id];
    // A test reign's staged soldiers (/test/stage soldiers) over the save's own.
    const w = x ? { ...u, hp: x.hp, activity: x.activity, goto: x.goto, home: x.home, ...(meta?.stageUnits?.[u.id] ?? {}) } : u;
    return { ...w, men: menOf(w) };  // the company's men by its kind and health (hosts.js): every host's strength sums them
  });
  const last = history[history.length - 1];
  const crownP = players.find((p) => p.house.crown);
  const crown = { treasury: crownP?.gold ?? 0, tithe: meta.tithe, titheWait: titheWait(meta, world.turn ?? 0), titheHigh: TITHE_HIGH, decrees: Object.fromEntries(Object.entries(DECREES).map(([k, v]) => { const cost = priceOf(k); const short = shortOf(crownP?.gold ?? 0, cost); return [k, { ...v, cost, wait: seasonsLeft(k === "feast" ? "feast:court" : k), ...(short ? { short } : {}) }]; })), favourWait: Object.fromEntries(world.players.map((p) => [p.id, seasonsLeft(`favour:${p.id}`)]).filter(([, n]) => n > 0)), perSeason: lastSeason.net, threat: meta.director?.threat ?? null };
  for (const p of players) {
    p.favour = p.house.wild || p.house.crown ? null : favourOf(p.id);
    p.favourWhy = favourWhy[p.id] ?? [];
    p.sworn = sworn(p.id) ? meta.alliances[p.id] : null;  // until what turn the house is sworn to the crown
    p.besieged = (meta.campaigns ?? []).filter((x) => x.house === p.id).map((x) => x.city);
    // Whom the house is at odds with, by name: wars, and wars the King has
    // stilled (a commanded peace or a royal match) as truces.
    const lordOf = (pid) => court?.lordOfHouse(pid);
    const stilledWith = (q) => { const a = lordOf(p.id), b = lordOf(q.id); return !!(a && b && court.truce(a.id, b.id)); };
    const rivals = (p.atWarWith ?? []).map((id) => players.find((q) => q.id === id)).filter((q) => q && !q.house.wild);
    // A loyal house (35 and up) isn't waging war on the King: the engine's state
    // between them is old diplomacy, not a cause, so it isn't shown as one.
    const loyalToCrown = (q) => !q.house.crown && (favourOf(q.id) ?? 0) >= BANDS.steady;
    p.wars = rivals.filter((q) => !stilledWith(q) && !(q.house.crown && loyalToCrown(p)) && !(p.house.crown && loyalToCrown(q)))
      .map((q) => q.house.crown ? "the Crown" : q.house.name.replace(/^House /, ""));
    // A pretender on the march is at war with the crown, whatever the engine's treaties say.
    const u = stakes?.s.usurper;
    if (u?.stage === "march") {
      const claimant = players.find((q) => q.id === u.house);
      if (p.id === u.house && !p.wars.includes("the Crown")) p.wars.unshift("the Crown");
      if (p.house.crown && claimant && !p.wars.includes(claimant.house.name.replace(/^House /, ""))) p.wars.unshift(claimant.house.name.replace(/^House /, ""));
    }
    p.truces = rivals.filter(stilledWith).map((q) => q.house.name.replace(/^House /, ""));
    // How far favour has moved in the last year (four seasons), shown beside it.
    const yearAgo = favourPast[(world?.turn ?? 0) - 4];
    p.favourTrend = p.favour == null || !yearAgo || yearAgo[p.id] == null ? 0 : Math.round(p.favour - yearAgo[p.id]);
    // How far the house has turned against the King (0-1): full, its ultimatum comes.
    p.turning = Math.min(1, (meta.turning?.[p.id]?.seasons ?? 0) / TURNING);
    // Where the house stands with the King, in one word (the goal's bar and the banners' 35).
    p.band = p.favour == null ? null : band(p.favour);  // loyal, sworn, steady, cooling or angry (favour.js, data/favour.json)
    // Its last season's gold by source, as Freeciv's books say (treasury.js income): towns, mines, tithe, court, dealings.
    p.income = meta.income?.[p.id] ?? null;
  }
  // Each house's measures as the ledger keeps them (one reckoning, recordTurn).
  // The Crown's own row reads like the houses' (the ledger keeps only theirs).
  const own = (p) => {
    const mine = world.cities.filter((c) => c.owner === p.id);
    return { towns: mine.length, pop: mine.reduce((t, c) => t + c.size, 0), souls: mine.reduce((t, c) => t + soulsOf(c.size), 0), gold: p.gold, armies: p.units, grain: mine.reduce((t, c) => t + (d?.cities[c.id]?.foodStock ?? 0), 0) };
  };
  for (const p of players) p.measures = last?.houses?.[p.house.name] ?? (p.house.crown ? own(p) : null);
  const usurper = stakes?.s.usurper.stage ?? "none";
  const u = stakes?.s.usurper;
  // The odds at Kingsmere: fighting companies of the pretender and of the crown
  // within a few leagues of the walls (200 men to a company, as the table counts).
  const seatNow = stakes?.s.seat;
  const fighting = (pid) => seatNow ? (world?.units ?? []).filter((x) => x.owner === pid && !CIVILIAN.has(x.type) && Math.hypot(x.x - seatNow.x, x.y - seatNow.y) <= 6).length : 0;
  const crownId = players.find((p) => p.house.crown)?.id;
  // The dead: which northern town they strike, how many came, and when the next comes.
  const nn = stakes?.s.north ?? {};
  const northTown = northTowns(world)[0];
  const dead = { town: northTown ? cityName(northTown.id) : null, owner: northTown?.owner ?? null,
    last: (3 + (nn.waves ?? 0) * 2) * 200, next: (3 + ((nn.waves ?? 0) + 1) * 2) * 200, in: nn.nextAt ? Math.max(0, nn.nextAt - (world?.turn ?? 0)) : null };
  const threat = { usurper, north: (stakes?.s.north.waves ?? 0), dead, pretender: u?.house ?? null, since: u?.since ?? 0, turn: world?.turn ?? 0,
    // The King's side is his whole host: the garrisons defend Kingsmere too.
    ended: u?.ended && !u.ended.settled && (world?.turn ?? 0) - u.ended.turn <= 8 ? u.ended.house : null,
    theirs: u?.house != null ? fighting(u.house) : 0, ours: crownId != null ? (world?.units ?? []).filter((x) => x.owner === crownId && !CIVILIAN.has(x.type)).length : 0 };
return { ...world, spentSeams: meta.spentSeams ?? [], players, cities, units, turnSeconds, bands: BANDS, civilian: [...CIVILIAN], ships: [...SHIPS], crownId: crownOf()?.id ?? null, seatId: crownSeat()?.id ?? null, reign: reignInfo(), story: storyNow(), date: calendar(world.turn), threat, counsel: counselNow, sitting: meta.court?.sitting ?? null, fallen: Object.values(HOUSES).filter((h) => !h.crown && !h.wild && !world.players.some((p) => houseFor(p).key === h.key && (world.cities.some((c) => c.owner === p.id) || (world.units ?? []).some((u) => u.owner === p.id)))).map((h) => ({ ...h, name: names.shown(h.name) })), effects: effects.slice(-10), peace: last?.peace ?? 1, prosperity: last?.pop ?? 0, souls: world.cities.reduce((t, c) => t + soulsOf(c.size), 0), crown, owners: d?.owners ?? [], worked: d?.worked ?? [], tilled: d?.tilled ?? [], scenes: scenes.filter((x) => Date.now() - x.at < 90000), marks: marksNow().map((m) => ({ ...m, seasons: ctx.markSeasons?.[m.kind] ?? null, line: scarLine({ world }, m) })), goal: goalNow(), weather: meta.weather ?? null, intrigue: [...(world.intrigue ?? []), ...(meta.stage?.intrigue ?? [])] };
}

// The realm's states, one definition each (SSOT, Mac 2026-11-10): set on each
// town in the bridge's world from Freeciv's own fields, at load, each reckoning
// and on every /world. The court, the deck, the arcs, counsel, the minds and
// the view all read these fields; none works them out again.
const PLAGUE_SEASONS = readJson(new URL("./data/stories.json", import.meta.url)).plagueSeasons;  // a town is still sick this many seasons after plague strikes
export function townStates(ctx) {
  const { world, meta, scenes, detail, besiegers, favourOf } = ctx;  // and marksNow, for the situation line
  if (!world?.cities) return;
  const d = detail();
  const turn = world.turn ?? 0;
  for (const c of world.cities) {
    const x = d?.cities?.[c.id];
    const food = x?.foodStock ?? null;
    const store = granarySize(c.size);
    Object.assign(c, {
      food, granary: store,
      famine: Boolean(x?.hadFamine),  // Freeciv's word: the town starved this season
      granaryLow: food != null && store > 0 && food / store < 0.25,
      plagueTurn: x?.plagueTurn ?? null,
      plague: x?.plagueTurn != null && x.plagueTurn >= 0 && turn - x.plagueTurn <= PLAGUE_SEASONS,
      disorder: Boolean(x?.disorder),
      // Freeciv's rapture, or a feast the King gave there this season or last.
      celebrating: Boolean(c.rapture ?? x?.celebrating) || scenes.some((s) => s.kind === "feast" && s.city === c.id && s.turn >= turn - 1),
      // The royal host before its walls, or an enemy host at them.
      besieged: (meta?.campaigns ?? []).some((k) => k.city === c.id) || besiegers(c).length >= 3,
    });
    // The town's house at war with another great house or the crown (Freeciv's diplomacy, wild raiders aside).
    const owner = world.players.find((p) => p.id === c.owner);
    const great = (id) => { const q = world.players.find((p) => p.id === id); return q && !houseFor(q).wild; };
    c.atWar = (d?.players?.[c.owner]?.atWarWith ?? []).some(great);
    // The crown grasps: a heavy tithe weighs on every town but the King's own.
    c.grasping = (meta?.tithe ?? 0) >= TITHE_HIGH && !houseFor(owner ?? {}).crown;
    // Grief: put to the sword, burnt, a death mourned, want or sickness, these last two seasons.
    c.grief = scenes.some((s) => s.city === c.id && ["sack", "razed", "vigil", "death", "famine", "plague"].includes(s.kind) && s.turn >= turn - 2);
    // Good times: a house that loves the crown (the crown's own: a full treasury), no want, no riot, no grief.
    const fond = houseFor(owner ?? {}).crown ? (owner?.gold ?? 0) >= 1500 : favourOf(c.owner) >= BANDS.loyal;
    c.prosperity = fond && !c.famine && !c.disorder && !c.grief;
    // A test reign's staged mood (/test/stage), so the court sees what the film shows.
    const st = meta?.stage?.[c.id];
    if (st) for (const k of ["famine", "celebrating", "disorder", "atWar", "grasping", "grief", "prosperity"]) if (k in st) c[k] = st[k];
    // The town's mood, one word everyone reads: a riot outweighs hunger, hunger a feast.
    // A harsh ruling given nearby (rulings.js heardOf) leaves the town in dread when nothing stronger stands.
    c.heard = ctx.heardOf?.(c) ?? null;
    c.mood = c.disorder ? "riot" : c.famine ? "hunger" : c.celebrating ? "feast" : c.heard?.mood ?? "";
    // Why the town looks as it does, in one line (situation.js): the card's first line.
    c.situation = situation({ world, scenes, marks: ctx.marksNow?.() ?? [], besiegers }, c);
    c.thoughts = ctx.thoughtsOf?.(c.id) ?? [];  // what the town is saying (chatter.js; the crowd thinks out loud)
    c.garrison = ctx.garrisonOf?.(c) ?? null;  // a royal company standing here, and its seasons left (garrison.js, the one owner)
    c.rising = Risings.townRising(meta, c);  // a house split in a rising: which side holds the town (risings.js)
    c.ruling = ctx.rulingOf?.(c) ?? null;  // the King's latest ruling here and its seasons left (rulings.js, the one owner)
    c.damage = ctx.damageOf?.(c) ?? null;  // its walls' sections and its burnt houses (damage.js, the one owner)
    c.lives = Households.lately(c.id, turn);  // this season's weddings, births and burials (households.js, the one owner)
  }
}

// A town falling into disorder is news: told once as it starts, so the minds
// and the townsfolk's talk hear of it (the state itself is townStates').
let inUproar = null;  // town ids in disorder at the last reckoning
export function uproar(ctx) {
  const { world, record } = ctx;
  const now = new Set((world?.cities ?? []).filter((c) => c.disorder).map((c) => c.id));
  if (inUproar) for (const id of now) if (!inUproar.has(id)) {
    const c = world.cities.find((x) => x.id === id);
    const h = houseFor(world.players.find((p) => p.id === c.owner) ?? {});
    record({ turn: world.turn, kind: "unrest", text: `${cityName(id)} is in uproar: the people take to the streets against ${h.crown ? "the crown" : h.name}.`, city: id });
  }
  inUproar = now;
}
