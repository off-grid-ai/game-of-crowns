// Bridge between the Freeciv server (the simulation) and the Godot view.
// - Runs one Freeciv server for the active chronicle (see chronicles.js),
//   resuming from that chronicle's newest save; can switch chronicles live.
// - Turns Freeciv's EVENT lines into the chronicle, keeps a per-turn ledger,
//   times and scores reigns.
// - Exposes a small HTTP API on 127.0.0.1:8787 for the view.

import * as Damage from "./damage.js";
import * as Mines from "./mines.js";
import * as Events from "./events.js";
import fs from "node:fs";
import zlib from "node:zlib";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { houseFor, cityName, describe, rememberNames } from "./narrator.js";
import { readSave, extractDetail } from "./savefile.js";
import { setReignSeed } from "./characters.js";
import { editRow, rng as rngFor } from "./fresh.js";
import { moodRules, speak } from "./claude.js";
import * as chron from "./chronicles.js";
import { clampFavour, DECREES } from "./crown.js";
import * as kingDeeds from "./ledger.js";
import { START } from "./favour.js";
// Stories the player generates or writes, kept with their realms.
const OWN_STORIES = path.join(chron.HOME, "stories");
ownStories(OWN_STORIES);
import { Court } from "./characters.js";
import { Minds, route as mindsRoute } from "./minds.js";
import { Arcs, ownStories } from "./arcs.js";
import { Chatter } from "./chatter.js";
import { Stakes, calendar } from "./stakes.js";
import * as Weather from "./weather.js";
import * as Realm from "./realm.js";
import * as Freeciv from "./freeciv.js";
import * as View from "./view.js";
import * as Camp from "./campaigns.js";
import { CIVILIAN } from "./campaigns.js";
import * as Counsel from "./counsel.js";
import * as Treasury from "./treasury.js";
import { FAVOUR } from "./treasury.js";
import * as Reign from "./reign.js";
import { GOAL_FAVOUR } from "./reign.js";
import * as Sittings from "./court.js";
import { json, body } from "./http_util.js";
import * as RealmRoutes from "./routes_realm.js";
import * as CourtRoutes from "./routes_court.js";
import * as DecreeRoutes from "./routes_decree.js";
import * as TestRoutes from "./routes_test.js";
import * as PeopleRoutes from "./routes_people.js";
import * as StoryRoutes from "./routes_stories.js";
import * as Book from "./favourbook.js";
import { LEAN, theirs } from "./favourbook.js";
import { moodFrom, isWatched } from "./claude.js";
import * as Season from "./season.js";
import * as Garrison from "./garrison.js";
import * as Rulings from "./rulings.js";
import * as Hosts from "./hosts.js";
import * as Battles from "./battles.js";
import { TURNING } from "./season.js";
import { intrigueNow } from "./intrigue.js";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 8787);

// --- the active chronicle ----------------------------------------------------

let meta = null; // chronicles.js meta for the running realm
let P = null; // its paths
let chronicle = [];
let world = null;
let history = [];
let detailCache = { file: null, mtime: 0, data: null };
let turnSeconds = chron.PACE.season;  // data/pace.json
let paused = false;
// Each great house's regard for the crown (0-100), by Freeciv player id.
let favour = {};
const favourWhy = {};  // player id -> [{ d, why }], newest last: why each house feels as it does
// What the King has done to each house, kept for good: favourWhy fades, a
// house's memory of the crown does not. player id -> [{ turn, last, d, what }].
let deeds = {};
let court = null;
let minds = null;
let arcs = null;
let chatter = null; // talk and gossip between minds (chatter.js)
let arcsRunning = false;
let stakes = null;
const effects = [];  // recent favour changes and their causes, for the game to show
let effectSeq = 0;
let decreesIssued = 0;
// Recent events with a place on the map, so the view can show them happening.
let scenes = [];

const arrivals = new Set();  // scenes already credited on arrival

// The King walking among his people (the player, who has no court record):
// everyone knows him, and names him to his face as his station demands.
const KING = { name: "the King", house: "The Crown", title: "King", lord: true, address: "Your Grace" };
const isKing = (b) => String(b?.you?.id ?? "") === "king";

// Tell only what the world can show: each lord's deed plays a scene the realm
// already has, where it happened (Mac, 2026-11-10). Offered to the King to
// watch; the camera never goes by itself.
function picture(e) {
  if (!world?.cities) return;
  const at = world.cities.find((x) => x.id === e.city);
  const other = e.with != null ? world.cities.find((x) => x.id === e.with) : null;
  const seat = crownSeat();
  if (!at) return;
  const here = { x: at.x, y: at.y, city: at.id, lord: true };
  switch (e.kind) {
    // The caption says who did what to which town, in the chronicle's own words.
    case "betrayal": if (e.to != null) scene("handover", { ...here, from: e.from ?? at.owner, to: e.to, label: `Treachery: ${cityName(at.id)} opens its gates to ${houseFor(world.players.find((p) => p.id === e.to)).name}` }); break;
    case "raid": scene("sack", { ...here, label: `Raiders burn the farms of ${cityName(at.id)}` }); break;
    case "succession": scene("feast", { ...here, owner: at.owner }); break;
    case "death": if (seat && seat.id !== at.id) scene("rider", { ...here, tx: seat.x, ty: seat.y, label: `Word of a death rides from ${cityName(at.id)}` }); break;
    case "alliance": if (other) scene("rider", { ...here, tx: other.x, ty: other.y, label: `A rider carries a letter to ${cityName(other.id)}` }); break;
    case "scheme": if (other) scene("rider", { ...here, tx: other.x, ty: other.y, label: `Envoys ride home to ${cityName(other.id)}, empty-handed` }); break;
  }
}

// Each scene has its own id (the view's seen-set keys on it) and says whether
// it's the crown's own doing (its owner is the crown).
let sceneSeq = 0;
function scene(kind, fields) {
  const crownId = world?.players?.find((p) => houseFor(p).crown)?.id;
  scenes.push({ id: `${meta?.id ?? ""}:${++sceneSeq}:${Date.now()}`, kind, turn: world?.turn ?? 0, at: Date.now(), ...fields, royal: fields?.owner != null && fields.owner === crownId });
  if (scenes.length > 120) scenes = scenes.slice(-120);
}

function load(id) {
  meta = chron.readJson(chron.paths(id).meta);
  setReignSeed(meta?.seed);
  P = chron.paths(id);
  const lines = (f) => (fs.existsSync(f) ? fs.readFileSync(f, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l)) : []);
  chronicle = lines(path.join(P.state, "chronicle.jsonl"));
  history = lines(path.join(P.state, "history.jsonl"));
  world = chron.readJson(path.join(P.state, "world.json"));
  queueMicrotask(townStates);  // the towns' states, once the realm is loaded
  detailCache = { file: null, mtime: 0, data: null };
  turnSeconds = chron.PACE.season;  // one pace for every realm, with a court at each season (data/pace.json; GAME_DESIGN)
  sitting = meta.court?.sitting != null;  // a realm reopened mid-sitting still holds
  paused = meta.status !== "running";
  favour = chron.readJson(path.join(P.state, "favour.json"), {});
  for (const k of Object.keys(favourWhy)) delete favourWhy[k];
  Object.assign(favourWhy, chron.readJson(path.join(P.state, "favour-why.json"), {}));
  deeds = chron.readJson(path.join(P.state, "deeds.json"), {});
  for (const [k, list] of Object.entries(deeds)) if (Array.isArray(list)) for (const x of list) x.d = Math.max(-60, Math.min(60, x.d));
  // What belongs to this realm only: the scenes playing in it start empty, and its
  // recent favour changes (with their numbering, so the view's "already shown" holds)
  // come from its own file, never from the realm open before it.
  scenes = [];
  arrivals.clear();
  if (world) Weather.advance(meta, Number(world.turn ?? 0), calendar(Number(world.turn ?? 0)).season);  // its sky at once
  effects.length = 0;
  effects.push(...chron.readJson(path.join(P.state, "effects.json"), []));
  effectSeq = effects.reduce((m, e) => Math.max(m, Number(e.seq) || 0), 0);
  // The last two years of favour and the season's income, so trends survive a restart.
  const past = chron.readJson(path.join(P.state, "favour-past.json"), {});
  for (const k of Object.keys(favourPast)) delete favourPast[k];
  Object.assign(favourPast, past.byTurn ?? {});
  lastSeason.net = past.net ?? 0;
  meta.tithe ??= 0.1;
  court = new Court(P.base, (e) => { record(e); picture(e); });  // what the lords do is told, and shown
  court.onTruce = (pair, seasons) => houseTruce(pair, seasons);  // every truce reaches Freeciv (the one writer)
  court.deedsOf = (pid) => (deeds[pid] ??= []);
  arcs = new Arcs(P.base, court, record);
  arcsRunning = false;  // a new realm's stories start free of the last one's
  court.onArcRuling = (arc, beat, option) => arc === "council" ? councilRuled(beat, option) : arc === "siege" ? siegeRuled(beat, option) : arcs.rule(arc, beat, option);
  chatter?.stop();
  chatter = new Chatter(P.state, { world: () => world, turn: () => world?.turn ?? 0, minds: () => minds });
  stakes = new Stakes(P.state, record, endReign);
  rememberNames(world);
  if (minds?.timer) minds.flush();  // the last realm's minds, written before the next is opened
  minds = new Minds(P.state, {
    world: () => world, court: () => court, tithe: () => meta.tithe,
    town: (id) => {
      const c = world?.cities?.find((t) => t.id === id);
      return c ? { famine: c.famine, plague: c.plague, mood: c.mood, besieged: c.besieged } : {};
    },
  });
  minds.catchUp(chronicle);
}

// Diplomacy between two houses in Freeciv itself, the bridge's one writer of it: the King's truce (a
// ceasefire) and the King's march (war on the house he besieges). Freeciv 3.2's Lua and server commands
// can't change diplomacy (3.3 adds Player:cancel_pact and add_love; docs/research/freeciv-leverage-2026-11-12.md),
// but its save holds it: save, set both players' diplstate rows, and resume from that save. Freeciv then
// keeps it (a ceasefire ends by itself; a war lasts until its AI makes peace).
// pairs: [[houseA, houseB, seasons, state], ...] (state "Cease-fire", the default, or "War"), one reload.
async function setDiplomacy(pairs) {
  if (!Freeciv.proc() || switching || !pairs.length) return false;
  switching = true;
  const t0 = Date.now();
  try {
    await stopFreeciv();
    const save = newestSave();
    if (!save) return false;
    let text = zlib.zstdDecompressSync(fs.readFileSync(save)).toString();
    for (const [a, b, turns = 16, state = "Cease-fire"] of pairs) text = setDipl(setDipl(text, a, b, turns, state), b, a, turns, state);
    const out = path.join(P.saves, `realm-T${String(world?.turn ?? 0).padStart(4, "0")}-diplomacy-${Date.now()}.sav.zst`);
    fs.writeFileSync(out, zlib.zstdCompressSync(Buffer.from(text)));
    return true;
  } finally {
    startFreeciv();
    switching = false;
    // The hitch: how long the realm was without Freeciv while the diplomacy went in.
    Freeciv.timeReload(t0);
  }
}

// A truce or a war, [houseA, houseB, seasons, state]: written now behind a sitting court, where the realm is
// already held and the card covers the screen; otherwise it waits for the next sitting (court.js sends them).
function diplomacyNow(pair) {
  if (meta?.court?.sitting != null) setDiplomacy([pair]).catch((e) => console.log("diplomacy:", e.message));
  else (meta.pendingDiplomacy ??= []).push(pair);
}

// Player p's diplstate toward player q. A ceasefire: Freeciv's AI keeps its own war plan per rival (the "ai"
// table: love, spam, countdown, war_reason, ...); left alone it declares war again on its first turn, so the
// King's truce also drops the plan: no countdown, no reason (DAI_WR_NONE = 5). The grudge stays, cooled a
// tenth: a truce stops the swords, not the hatred, and war may come back when it ends. A war: the rows say
// "War", and each side's AI fights it as its own.
function setDipl(text, p, q, turns, state = "Cease-fire") {
  const war = state === "War";
  text = editRow(text, p, "diplstate", q, (c) => {
    c[0] = war ? '"War"' : '"Cease-fire"';
    c[1] = war ? '"War"' : '"Cease-fire"';
    c[3] = war ? "0" : String(turns);
    c[4] = "0";
  });
  if (war) return text;
  return editRow(text, p, "ai", q, (c) => {
    const love = Number(c[0]) || 0;
    c[0] = String(love < 0 ? Math.round(love * 0.9) : love);
    c[2] = "-1";
    c[3] = "5";
  });
}

// The active realm's newest save (freeciv.js keeps the folder listing).
function newestSave(kind = "") {
  return Freeciv.newestSave(P.saves, kind);
}

// Details only the save file holds (food stores, construction, orders, wars),
// re-read whenever Freeciv writes a newer autosave. Freeciv 3.2's Lua gives
// none of these live (checked: no food stock, unit hp or activity, or
// diplomacy), so the save is their one source; rapture comes live (snapshot.lua).
function detail() {
  try {
    const newest = newestSave("auto");
    if (!newest) return detailCache.data;
    const mtime = fs.statSync(newest).mtimeMs;
    if (newest !== detailCache.file || mtime !== detailCache.mtime) {
      detailCache = { file: newest, mtime, data: extractDetail(readSave(newest)) };
    }
  } catch (err) {
    console.error("save detail:", err.message);
  }
  return detailCache.data;
}

// Lines that repeat across towns in one season are held and written once,
// grouped: "Plague sweeps through Riverwood and Lionkeep." Keyed by the rest
// of the sentence, so famine in two houses stays two lines.
const GROUPED = [
  [/^Plague sweeps through (.+?)\. (The dead are carted out by night\.)$/, (towns, rest) => `Plague sweeps through ${towns}. ${rest}`],
  [/^Famine in (.+?)\. (The granaries are empty and .+ starve\.)$/, (towns, rest) => `Famine in ${towns}. ${rest}`],
  [/^Barracks rise in (.+?)\. (.+ is arming\.)$/, (towns, rest) => `Barracks rise in ${towns}. ${rest}`],
];
const held = new Map();  // key -> { entry, towns[], make }
const andList = (xs) => (xs.length > 1 ? `${xs.slice(0, -1).join(", ")} and ${xs.at(-1)}` : xs[0]);
function flushHeld() {
  for (const { entry, towns, make, rest } of held.values()) writeRecord({ ...entry, text: make(andList(towns), rest) });
  held.clear();
}

function record(entry) {
  for (const [re, make] of GROUPED) {
    const m = String(entry.text ?? "").match(re);
    if (!m) continue;
    const key = `${re.source}|${m[2]}`;
    const h = held.get(key);
    if (h) { if (!h.towns.includes(m[1])) h.towns.push(m[1]); }
    else held.set(key, { entry, towns: [m[1]], make, rest: m[2] });
    return;
  }
  writeRecord(entry);
}

function writeRecord(entry) {
  // The same line again within a year (a siege that drags on) is news once.
  const recent = chronicle.slice(-12);
  if (entry.text && recent.some((e) => e.text === entry.text && (entry.turn ?? 0) - (e.turn ?? 0) <= 4)) return;
  entry.seq = chronicle.length ? chronicle[chronicle.length - 1].seq + 1 : 1;
  entry.at = Date.now();
  // Whether the line touches the crown (the ticker shows other houses' news only in the drawer;
  // realm/data/ticker.json): a royal or sworn town, or the King, the crown or Kingsmere named.
  if (entry.crown == null) {
    const town = entry.city != null ? world?.cities?.find((c) => c.id === Number(entry.city)) : null;
    const owner = town ? world.players.find((p) => p.id === town.owner) : null;
    entry.crown = !!(owner && (houseFor(owner).crown || sworn(owner.id))) || /\b(King|King's|crown|Crown|Kingsmere|royal)\b/.test(String(entry.text ?? ""));
  }
  chronicle.push(entry);
  fs.appendFileSync(path.join(P.state, "chronicle.jsonl"), JSON.stringify(entry) + "\n");
  minds?.perceive(entry);
  // A wedding is a feast in the bride's town.
  if (entry.kind === "marriage" && entry.city != null) {
    const town = world?.cities?.find((c) => c.id === entry.city);
    if (town) scene("feast", { x: town.x, y: town.y, city: town.id, owner: town.owner });
  }
}

// --- Freeciv process (the process and its line protocol live in freeciv.js) ---

function send(line) {
  Freeciv.send(line);
}

function startFreeciv() {
  const save = Freeciv.start({
    name: meta.name, P, dir: DIR, onEvent,
    // An unexpected exit takes the bridge down so launchd restarts it cleanly.
    onExit: (code) => { if (!switching) process.exit(code ?? 1); },
  });
  // The Crown's soldiers are commanded by Freeciv's AI (the King rules by decree,
  // the AI marshals the host). Older realms saved the Crown as human; hand it over.
  if (save) {
    try {
      const crownBlock = readSave(save)["player7"];
      if (crownBlock && crownBlock.name === "The King" && !String(crownBlock.flags ?? "").includes("ai")) {
        setTimeout(() => send('aitoggle "The King"'), 3000);
      }
    } catch { /* not fatal */ }
  }
  setTimeout(() => {
    send(`lua unsafe-cmd SNAP_DIR = "${P.state}/"`);
    // The Crown's soldiers defend and never take a town unbidden: the ruleset
    // forbids the Normans "Conquer City" (data/realmrules/actions.ruleset).
    send(`set timeout ${timeoutNow()}`);
    // A save keeps the barbarian settings it was made with: a realm in play gets the raiders choice and the
    // ruleset's first-turn onset (raids are Freeciv's barbarians, realm_raid).
    send(`set barbarians ${chron.BARBARIANS[chron.cleanOptions(meta.options ?? {}).raiders]}`);
    send("set onsetbarbs 1");
    snapshot();
  }, 4000);
}

let switching = false;

const stopFreeciv = Freeciv.stop;

async function switchTo(id) {
  switching = true;
  // The last realm's matters are not this one's: the Hand reads the new realm afresh (gameplay review #4).
  counselNow = [];
  counselStale = true;
  await stopFreeciv();
  if (meta) chron.saveMeta(meta);
  load(id);
  chron.setActive(id);
  startFreeciv();
  switching = false;
}

async function applyOpeningMood() {
  if (!meta.openingMood || meta.openingMoodApplied || !world) return;
  meta.openingMoodApplied = true;
  chron.saveMeta(meta);
  const houses = world.players.map((p) => houseFor(p)).filter((h) => !h.wild && !h.crown).map((h) => h.name);
  court.populate(world);
  const lords = court.alive().filter((c) => c.rank === "lord").map((c) => c.name);
  const mood = (await moodFrom(meta.openingMood, houses, lords)) ?? moodRules(meta.openingMood, houses, lords);
  if (mood) {
    court.setMood(mood);
    record({ turn: world.turn, kind: "decree", text: `So the chronicle begins: ${mood.summary}` });
  }
}

// The King's starting choices that act once, when the realm first stirs: the
// houses' purses, how far they trust the crown, and the royal host's size.
function applyStartOptions() {
  const o = meta.options;
  if (!o || meta.optionsApplied || !world) return;
  meta.optionsApplied = true;
  meta.crownedAt ??= world.turn;  // the reign's chronicle begins here (routes_realm.js chronicle)
  chron.saveMeta(meta);
  const lua = [];
  const who = (id) => `for q in players_iterate() do if q.id == ${id} then`;
  for (const p of world.players.filter((x) => !houseFor(x).wild && !houseFor(x).crown)) {
    const gold = { poor: -Math.floor((p.gold ?? 0) * 0.7), asis: 0, rich: 400 }[o.houseWealth] ?? 0;
    if (gold) lua.push(`${who(p.id)} edit.change_gold(q, ${gold}) end end`);
    // The reign's mood sets the level; each house's own history with the crown
    // (the world bible) sets where it stands within it, so the table starts
    // with friends, doubters and an obvious problem, not seven equal numbers.
    const lean = LEAN[houseFor(p).name] ?? 0;
    favour[p.id] = restingFavour(p);
    favourWhy[p.id] = [];
    deeds[p.id] = [];
    noteFavour(p.id, ({ loyal: 19, wary: 0, resentful: -21 }[o.trust] ?? 0), "the realm's mood at your crowning");
    noteFavour(p.id, lean, lean > 0 ? "their old loyalty to the crown" : "their old grievances against the crown");
  }
  // A real reign deals the houses' old feelings from its seed: two or three
  // begin cold to the crown (below the banners' 35), the rest a little warmer
  // or cooler than their history alone. Test reigns keep the history as it is.
  if (meta.seed && meta.seed !== 1066) {
    const r = rngFor(meta.seed ^ 0x5bd1e995);
    const great = world.players.filter((x) => !houseFor(x).wild && !houseFor(x).crown).map((x) => x.id).sort((a, b) => a - b);
    for (let i = great.length - 1; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [great[i], great[j]] = [great[j], great[i]]; }
    const cold = 2 + (r() < 0.5 ? 1 : 0);
    // The cold ones start at the banners' line, not at the rising line: the King learns the court
    // before the first crisis (data/favour.json startFloor; gameplay review #1).
    great.forEach((id, i) => {
      const want = i < cold ? START.floor + Math.floor(r() * 8) : favourOf(id) + Math.floor(r() * 21) - 10;
      const d = clampFavour(want) - favourOf(id);
      if (!d) return;
      favour[id] = favourOf(id) + d;  // their history, not the King's deed: no deed is recorded
      (favourWhy[id] ??= []).push({ d, why: d < 0 ? "an old quarrel with the crown" : "an old kindness from the crown" });
    });
  }
  // No great house begins under the floor (a resentful realm's floor is just above the rising line).
  const floor = o.trust === "resentful" ? START.resentful : START.floor;
  for (const p of world.players.filter((x) => !houseFor(x).wild && !houseFor(x).crown)) if (favourOf(p.id) < floor) favour[p.id] = floor;
  saveFavour();
  const crown = world.players.find((x) => houseFor(x).crown);
  // The King's purse at his crowning (economy.json start, by the reign's wealth): the
  // shared Aldmere baseline's heap would carry him through a whole reign unfelt.
  const purse = Treasury.ECONOMY.start[meta.wealth] ?? Treasury.ECONOMY.start.comfortable;
  if (crown && crown.gold !== purse) { lua.push(`${who(crown.id)} edit.change_gold(q, ${purse - crown.gold}) end end`); crown.gold = purse; }
  if (crown && o.host === "strong") {
    lua.push(`local k = find.city(nil, ${world.cities.find((c) => c.owner === crown.id && c.capital)?.id ?? -1}); if k then for _, n in ipairs({"Knights", "Knights", "Knights", "Pikemen", "Pikemen", "Pikemen", "Pikemen", "Archers", "Archers", "Catapult"}) do edit.create_unit(k.owner, k.tile, find.unit_type(n), 1, k, -1) end end`);
  } else if (crown && o.host === "small") {
    // Half the royal garrison was never raised.
    lua.push(`${who(crown.id)} local i = 0; for u in q:units_iterate() do if u.utype:rule_name() ~= "Workers" then i = i + 1; if i % 2 == 0 then edit.unit_kill(u, "disbanded", nil) end end end end end`);
  }
  lua.forEach((l) => send(`lua cmd ${l}`));
  record({ turn: world.turn, kind: "decree", text: `The realm as the King found it: the great houses ${{ loyal: "loyal to the crown", wary: "wary of the crown", resentful: "resentful of the crown" }[o.trust]}, ${{ peaceful: "slow to war", mixed: "of mixed temper", warlike: "spoiling for war" }[o.temper]}.` });
}

// What view.js needs to build the /world answer, read fresh on every call.
const viewCtx = () => ({ markSeasons: MARK_SEASONS, world, meta, history, court, stakes, turnSeconds, counselNow, scenes, effects, favourWhy, favourPast, lastSeason, detail, favourOf, marchOdds, greatHouses, sworn, priceOf, seasonsLeft, crownOf, crownSeat, reignInfo, storyNow, marksNow, goalNow, CIVILIAN, TURNING, GOAL_FAVOUR, soulsOf });
// The realm as the view sees it (GET /world): built in view.js.
function worldView() {
  return { ...View.worldView(viewCtx()), hosts: Hosts.list({ world, meta }), hostOrdersLeft: Hosts.ordersLeft({ world, meta }) };  // the King's hosts and their orders, and how many more orders this season (hosts.js)
}

// The Hand's matters, read from the realm as it stands now.
let counselStale = true;  // the King acted since the last reading: read the realm again
function refreshCounsel() {
  if (!world) return;
  counselStale = false;
  const v = worldView();
  counselNow = counsel(v.players, v.cities, v.threat);
}

// The realm's states, set on each town (view.js). A realm just made has no world until Freeciv first
// reports (snapshot): nothing to set yet (tools/switch_probe.mjs).
function townStates() {
  if (!world) return;
  View.townStates({ world, meta, scenes, detail, besiegers, favourOf, marksNow, thoughtsOf: (id) => chatter?.thoughtsOf(id) ?? [], damageOf: (c) => Damage.view(meta, c), garrisonOf: (c) => Garrison.view(meta, c, world?.turn ?? 0), rulingOf: (c) => Rulings.view(meta, c, world?.turn ?? 0) });
  world.intrigue = intrigueNow({ world, court });  // the houses' schemes, for the map (intrigue.js)
}

// A town falling into disorder is news, told once as it starts (view.js).
function uproar() {
  View.uproar({ world, record });
}

function snapshot() {
  send(`lua unsafe-file ${path.join(DIR, "lua", "snapshot.lua")}`);
  setTimeout(() => {
    world = chron.readJson(path.join(P.state, "world.json")) || world;
    rememberNames(world);
    ledger();
    sieges();
    townStates();
    uproar();
    // The start options first (the houses' favour at the crowning), then the Hand reads the realm:
    // a counsel read before them named the favour the baseline had (gameplay review #4: "favour 6").
    applyStartOptions();
    applyOpeningMood();
    refreshCounsel();
  }, 500);
}

// A named lord, lady or bannerman, face to face: they answer as themselves
// (their traits, aims and memories) and remember what passed between you.
async function talkToNamed(res, city, id, b) {
  const c = court.people[id];
  const greet = !!b.greet;  // they've only just walked up: the lord or lady speaks first
  const said = greet ? "(They walk up to you and stop, and say nothing yet: you speak first, as you would to them, by what you know of them and what they have done.)" : String(b.said ?? "").trim().slice(0, 400);
  if (!c || !c.alive || !said) return json(res, 400, { error: "nobody to hear it" });
  const speaker = b.you?.id ? court.people[String(b.you.id)] : null;
  const you = isKing(b) ? KING : {
    name: speaker?.name ?? String(b.you?.name ?? "a stranger"),
    house: speaker?.house ?? "",
    lord: speaker ? speaker.playerId === c.playerId && speaker.rank === "lord" && c.rank !== "lord" : false,
    address: !speaker ? "stranger" : speaker.rank === "lord" ? (speaker.gender === "female" ? "my lady" : "my lord") : speaker.gender === "female" ? "my lady" : "ser",
  };
  const opinion = speaker ? court.opinion(c.id, speaker.id) : 0;
  const person = {
    name: c.name, age: c.age, woman: c.gender === "female", trade: `${c.rank === "lord" ? (c.gender === "female" ? "Lady" : "Lord") : c.rank} of ${c.house}`,
    nature: (c.traits ?? []).join(", "), family: c.spouse ? "married" : "unwed",
    wants: c.goals?.[0]?.text ?? "to endure", past: (c.memories ?? []).slice(-1)[0] ?? "",
  };
  const story = `You remember: ${(c.memories ?? []).slice(-3).join(" ") || "nothing of note"}. Of ${you.name} you think ${opinion > 20 ? "well" : opinion < -20 ? "ill" : "little either way"}.`;
  const file = path.join(P.state, "talks.json");
  const talks = chron.readJson(file, {});
  const key = `char:${c.id}`;
  const past = (talks[key] ?? []).slice(-10);
  const near = chronicle.filter((e) => e.city === city.id || (e.text ?? "").includes(c.house)).slice(-4).map((e) => e.text);
  const out = await speak(person, cityName(city.id), c.house, you, near, story, past, said, meta.options?.language ?? "en", minds.forTalk(c.id, { id: isKing(b) ? "king" : speaker?.id, name: you.name }));
  if (!out) return json(res, 503, { error: `${c.name} regards you in silence. (The local model isn't running.)` });
  talks[key] = [...past, ...(greet ? [] : [{ who: you.name, text: said }]), { who: c.name, text: out.reply }].slice(-16);
  fs.writeFileSync(file, JSON.stringify(talks, null, 1));
  if (!greet) {
    court.remember(c.id, `${you.name} sought me out in ${cityName(city.id)} and said: "${said.slice(0, 120)}"`);
    minds.talked(c.id, { id: isKing(b) ? "king" : speaker?.id, name: you.name }, said, out.reply);
  }
  return json(res, 200, { name: c.name, gender: c.gender, ...out });
}

// The court's sitting and its rulings (court.js). Its context, read fresh on
// every call: getters for what the bridge reassigns (the sitting reads them
// again after each await), setSitting for the hold.
const sittingCtx = () => ({ get world() { return world; }, get meta() { return meta; }, get court() { return court; }, get counselNow() { return counselNow; },
  get sitting() { return sitting; }, setSitting: (v) => { sitting = v; }, timeoutNow, send, record, scene, deed, crowns, marchOn, shiftAndTell, shiftFavour, favourOf, setDiplomacy, turnHouses, lapse, lapseOf });
// A ruling on a petition, by option, and how the realm sees it (court.js).
function rule(id, option) { return Sittings.rule(sittingCtx(), id, option); }

// A town besieged, the royal host and its sieges: campaigns.js. Its context,
// read fresh on every call; scenes is read live, as scene() may replace it.
const campCtx = () => ({ world, meta, court, get scenes() { return scenes; }, send, record, scene, deed, shiftFavour, greatHouses, crownOf, favourOf, causeOf, SOLDIER, detail, diplomacy: diplomacyNow });
// The fighting companies of other houses on the tiles around a town (campaigns.js).
function besiegers(c) { return Camp.besiegers(campCtx(), c); }
// A town besieged is seen, once a turn (campaigns.js).
function sieges() { return Camp.sieges(campCtx()); }

// Every decree is seen in the world, with the scenes the realm already plays
// (scenes.gd); the townsfolk's awareness hears each one (world.scenes).
function decreeScenes(cmd, result, seat, target) {
  if (!seat) return;
  const seatOf = (pid) => world.cities.find((c) => c.owner === Number(pid) && c.capital) ?? world.cities.find((c) => c.owner === Number(pid));
  const ride = (to, label) => to && to.id !== seat.id && scene("rider", { x: seat.x, y: seat.y, tx: to.x, ty: to.y, city: to.id, label });
  switch (cmd.action) {
    case "marriage":  // a feast at both houses' seats
      for (const pid of result.pact ?? []) { const s = seatOf(pid); if (s) scene("feast", { x: s.x, y: s.y, city: s.id, owner: s.owner, strength: 0.8 }); }
      break;
    case "peace": case "settle":  // the King's word rides to both houses
      for (const pid of result.truce ?? []) ride(seatOf(pid), "The King's peace");
      break;
    case "alliance": ride(target, "The King's oath"); break;
    case "buyoff": ride(target, "The crown's gold for the pretender"); break;
    case "ward": if (target && target.id !== seat.id) scene("ward", { x: target.x, y: target.y, tx: seat.x, ty: seat.y, city: seat.id }); break;
    case "banners": case "sellswords": case "back":  // men gather at Kingsmere and march out
      scene("muster", { x: seat.x, y: seat.y, tx: target ? target.x : seat.x + 3, ty: target ? target.y : seat.y + 2, city: seat.id });
      // Marched to another town, the company stands there (garrison.js, the one owner; kept with the reign).
      if (target && target.id !== seat.id) Garrison.post(meta, cmd.action, target, world.turn ?? 0, send);
      break;
  }
}

function onEvent(line) {
  let ev;
  try { ev = JSON.parse(line.slice(line.indexOf("EVENT {") + 6)); } catch { return; }
  // A blight run its course (realmrules/script.lua: its Blight building taken up): the land recovers.
  if (ev.kind === "decree_lapsed") {
    if (ev.building === "Blight" && world?.cities?.some((c) => c.id === Number(ev.city))) record({ turn: Number(ev.turn), kind: "heal", text: `The land around ${cityName(Number(ev.city))} slowly recovers.`, city: Number(ev.city) });
    return;
  }
  if (ev.kind === "turn") return Season.turn(seasonCtx(), ev);  // the turn's sequence (season.js)
  if (ev.kind === "attack") return Battles.struck(ev, world?.turn ?? 0);  // who struck where (battles.js)
  // Freeciv fought the King's assault (realm_assault): the view storms the siege and ends it as Freeciv did (campaigns.js).
  if (ev.kind === "assault") { const storm = Camp.stormScene(world, ev, crownOf()?.id); if (storm) scene("storm", storm); return; }
  const town = ev.city !== undefined ? world?.cities?.find((c) => c.id === Number(ev.city)) : null;
  if (ev.kind === "unit_killed") {
    const loser = world?.players?.find((p) => p.id === Number(ev.owner));
    // Who fought, how many and who won (battles.js); one battle per tile a season.
    const f = Battles.fields(world, ev);
    if (!Battles.merge(scenes, f, world?.turn ?? 0)) scene("battle", { ...f, house: loser ? houseFor(loser).name : null });
  }
  if (ev.kind === "city_transferred" && town) scene(ev.reason === "conquest" ? "sack" : "handover", { x: town.x, y: town.y, city: town.id, from: Number(ev.from), to: Number(ev.to) });
  if (ev.kind === "city_destroyed" && town) scene("razed", { x: town.x, y: town.y, city: town.id });
  if (ev.kind === "seam_spent") Mines.spent(meta, ev);  // the old workings stay where the gold ran out (mines.js)
  // The land keeps its scars (state/marks.json): where men died, a town was stormed, a town was razed.
  // The view burns the ground there, fading with the mark's age, and a razed town leaves a ruin.
  const scar = ev.kind === "unit_killed" ? ["battle", Number(ev.x), Number(ev.y)] : ev.kind === "city_transferred" && ev.reason === "conquest" && town ? ["sack", town.x, town.y] : ev.kind === "city_destroyed" && town ? ["razed", town.x, town.y] : null;
  if (scar) addMark(scar[0], scar[1], scar[2], Number(ev.turn));
  if (ev.kind === "city_shrank" && town && (ev.reason === "famine" || ev.reason === "plague")) scene(ev.reason, { x: town.x, y: town.y, city: town.id });
  const text = describe(ev, world);
  // A town changing hands keeps why, and from which house to which (scenes and sound tell a conquest from a handover).
  const hands = ev.kind === "city_transferred" ? { reason: ev.reason, from: Number(ev.from), to: Number(ev.to) } : {};
  if (text) record({ turn: Number(ev.turn), kind: ev.kind, text, city: ev.city ? Number(ev.city) : undefined, ...hands });
}

// The reign (reign.js): its clock and acts, the King's name and deeds, his aims
// and ambitions, its goal, its readings and how it ends. Its context, read fresh
// on every call (getters for what the bridge reassigns; endReign pauses through setPaused).
const reignCtx = () => ({ meta, world, court, stakes, arcs, favour, favourPast, turnSeconds, get paused() { return paused; }, setPaused: (v) => { paused = v; },
  get history() { return history; }, get chronicle() { return chronicle; }, get counselNow() { return counselNow; }, record, send, scene, detail, favourOf, saveFavour, crownOf, crownSeat, SOLDIER, soulsOf, theirs, canDecree });
// Whether the realm would take this order now, by the decree route's own once-a-year and price rules (next.js offers only these).
// purse: the gold to judge the price against (Infinity: by the yearly rules only, for what he'd want if he could pay).
function canDecree(cmd, purse = null) {
  if (DECREES[cmd.action]?.off) return false;  // cut from the King's orders (data/decrees.json off)
  const y = yearlyKey(cmd);
  if (y && seasonsLeft(y) > 0) return false;
  const crown = crownOf();
  return !!crown && (purse ?? crown.gold ?? 0) >= priceOf(cmd.action);
}
// The King's ledger and the name the realm gives him (reign.js).
function kingName(outcome = null) { return Reign.kingName(reignCtx(), outcome); }
function deed(tag, opts = {}) { return Reign.deed(reignCtx(), tag, opts); }

// The realm's scars, as long as they show: a battle's ground heals in 12 seasons, a stormed
// town's in 16; a razed town's ruin stands until a town is founded on the spot again.
const MARK_SEASONS = { battle: 12, sack: 16 };
const marks = { file: null, list: [] };
// A scar on the land (state/marks.json), one owner for writing them: the realm's own events, and the director's threats that land.
function addMark(kind, x, y, turn) {
  const list = marksNow().filter((m) => !(m.kind === kind && m.x === x && m.y === y));
  list.push({ kind, x, y, turn });
  fs.writeFileSync(path.join(P.state, "marks.json"), JSON.stringify((marks.list = list.slice(-400))));
}

function marksNow() {
  const f = P && path.join(P.state, "marks.json");
  if (f !== marks.file) { marks.file = f; marks.list = f ? chron.readJson(f, []) : []; }
  const turn = Number(world?.turn ?? 0);
  marks.list = marks.list.filter((m) => (m.kind === "razed" ? turn - m.turn < 2 || !world?.cities?.some((c) => c.x === m.x && c.y === m.y) : turn - m.turn < (MARK_SEASONS[m.kind] ?? 12)));
  return marks.list;
}

// The season and the turn (season.js): the turn's sequence, the season's tithe and
// reckoning, the people's yearly moves, the rising gate and the one truce writer. Its
// context, read fresh on every call (getters for what the bridge reassigns, read live in
// the turn's timers).
const seasonCtx = () => ({ get world() { return world; }, get meta() { return meta; }, get court() { return court; }, get stakes() { return stakes; }, get minds() { return minds; },
  get P() { return P; }, get favour() { return favour; }, get deeds() { return deeds; },
  favourWhy, favourPast, treasuryCtx, send, record, flushHeld, courtSeason, royalWorks, resolveCampaigns, favourOf, restingFavour, noteFavour, recordDeed,
  causeOf, saveFavour, goalNow, sworn, shiftFavour, heardCtx, setDiplomacy, diplomacy: diplomacyNow, snapshot, runArcs, addMark, detail, marksNow, besiegers, startCampaign });
function runSeason() { return Season.runSeason(seasonCtx()); }
function turnHouses(turn) { return Season.turnHouses(seasonCtx(), turn); }
function storyMarch(pid, size) { return Season.storyMarch(seasonCtx(), pid, size); }
function houseTruce(pair, seasons = 16) { return Season.houseTruce(seasonCtx(), pair, seasons); }
function keepTruce(pair) { return Season.keepTruce(seasonCtx(), pair); }
function councilRuled(beat, option) { return Season.councilRuled(seasonCtx(), beat, option); }

// Each season the realm's story arcs move on (arcs.js); n seasons at once
// fast-forwards them, re-reading the realm whenever a beat pulled a lever.
// --- the player's own beats (the beat form on the title screen) -------------------

// A story file of the player's own, read fresh (never one of the game's).
function ownStory(id) {
  if (!/^[a-z0-9-]{1,80}$/.test(String(id ?? ""))) return null;
  const file = path.join(OWN_STORIES, `${id}.json`);
  try { return fs.existsSync(file) ? { ...JSON.parse(fs.readFileSync(file, "utf8")), own: true } : null; } catch { return null; }
}

// A story's roles in words for the form: "firstChild" is "the first child".
function rolesOf(t) {
  const word = (id) => id.replace(/([A-Z])/g, " $1").toLowerCase();
  // A town is named by whose it is: "the warden's seat", "a town of the rival".
  const town = (spec) => spec.seatOf || spec.homeOf ? `the ${word(spec.seatOf ?? spec.homeOf)}'s seat` : spec.ownedBy ? `a town of the ${word(spec.ownedBy)}` : "the town";
  return Object.entries(t.roles ?? {}).map(([id, spec]) => ({ id, town: Boolean(spec.town), label: spec.label ?? (spec.town ? town(spec) : `the ${word(id)}`) }));
}

// When a beat of the player's own happens.
const BEAT_WHEN = {
  act1: { label: "In the first act", if: { act: [">=", 1] } },
  act2: { label: "In the second act", if: { act: [">=", 2] } },
  act3: { label: "In the third act", if: { act: [">=", 3] } },
  act4: { label: "In the last act", if: { act: [">=", 4] } },
  late: { label: "Late in the story", if: { seasons: [">=", 8] } },
  dire: { label: "When the threat runs high", if: { threat: [">=", 60] } },
  march: { label: "When a usurper marches", if: { usurper: "march" } },
};

// What it does, to whoever is in it.
const BEAT_DOES = {
  nothing: { label: "Only what is told", do: () => ({}) },
  darker: { label: "Raises the threat", stage: "crisis", do: () => ({ threat: 15 }) },
  calmer: { label: "Eases the threat", do: () => ({ threat: -15 }) },
  arms: { label: "They raise soldiers", do: (who) => ({ units: { [who]: { type: "Pikemen", count: 3 } } }) },
  costs: { label: "Their house loses gold", do: (who) => ({ gold: { [who]: -80 } }) },
  turns: { label: "Their house turns from the crown", do: (who) => ({ favour: { [who]: -15 } }) },
  warms: { label: "Their house warms to the crown", do: (who) => ({ favour: { [who]: 15 } }) },
  dies: { label: "They die", stage: "crisis", do: (who, text) => ({ die: { who, how: text.replace(/\{\w+(\.\w+)?\}/g, "").slice(0, 120) } }) },
  // They come before the King with it: two answers, and neither is free.
  court: { label: "They bring it to the King", do: () => ({}), court: (who, text) => ({ from: who, text: `{${who}} comes before the King: "${text.replace(/"/g, "'")}"`, options: [
    { id: "grant", label: "Grant {" + who + "} what they ask (200 gold)", hint: "{" + who + ".houseName} +15 · the treasury pays for it", cost: 200, favour: { [who]: 15 }, result: "The King grants it. {" + who + "} bows low, and {" + who + ".he} will remember." },
    { id: "refuse", label: "Send {" + who + "} away", hint: "{" + who + ".houseName} −15 · they leave with nothing", favour: { [who]: -15 }, result: "The King refuses. {" + who + "} leaves the hall without a word." },
  ] }) },
};

function storyForForm(t) {
  return {
    id: t.id, name: t.name, roles: rolesOf(t),
    when: Object.entries(BEAT_WHEN).map(([id, w]) => ({ id, label: w.label })),
    does: Object.entries(BEAT_DOES).map(([id, d]) => ({ id, label: d.label })),
    beats: (t.asides ?? []).map((b) => ({ id: b.id, text: b.text, who: b.form?.who ?? b.speaker, when: BEAT_WHEN[b.form?.when]?.label ?? "", does: BEAT_DOES[b.form?.does]?.label ?? "" })),
  };
}

function arcCtx() {
  const d = detail();
  return {
    world, minds, favour: favourOf, shift: shiftFavour, send: (l) => send(`lua cmd ${l}`),
    atWar: (a, b) => (d?.players?.[a]?.atWarWith ?? []).includes(b),
    town: (id) => {
      const c = world.cities.find((t) => t.id === id);
      return c ? { food: c.food, famine: c.famine, plague: c.plague, granaryLow: c.granaryLow, besieged: c.besieged, mood: c.mood } : {};
    },
    recent: (turns = 16) => chronicle.filter((e) => e.turn >= world.turn - turns),
    // The reign's story, chosen when the chronicle began, and how it ends the reign.
    story: meta.options?.story ?? null,
    storyTags: meta.options?.storyTags ?? [],
    endReign: (why, outcome = "deposed") => endReign(why, outcome),
    // The throne's own war: a story's pretender marches on Kingsmere (stakes.js runs the march).
    // A story's march waits on the house's ultimatum, as any rising does (turnHouses).
    declare: (pid, size) => storyMarch(pid, size),
    usurperStage: () => stakes?.s.usurper.stage ?? "none",
    // How far through its clock the reign is (0-1): a story's acts land at its quarters.
    reignAt: meta.minutes > 0 ? Math.min(1, meta.elapsedMs / (meta.minutes * 60000)) : null,
    refresh: () => new Promise((r) => { snapshot(); setTimeout(r, 900); }),
  };
}

let arcsSince = 0;
async function runArcs(n = 1, start = true) {
  // A run stuck for over a minute (a call that never came back) frees itself.
  if (arcsRunning && Date.now() - arcsSince > 60000) arcsRunning = false;
  if (!world || !arcs || arcsRunning) return false;
  arcsRunning = true;
  arcsSince = Date.now();
  try {
    for (let i = 0; i < n; i++) await arcs.season(arcCtx(), { start });
  } catch (err) {
    console.error("arcs:", err);
  } finally {
    arcsRunning = false;
  }
  return true;
}

// The crown's favour book (favourbook.js): each house's favour and why, the
// deeds it will not forget, kindness wearing thin, and where favour settles.
// Its context, read fresh on every call; nextEffect numbers the effects.
const favourCtx = () => ({ world, meta, P, favour, deeds, favourWhy, favourPast, lastSeason, effects, nextEffect: () => ++effectSeq, detail });
function saveFavour() { return Book.saveFavour(favourCtx()); }
function favourOf(id) { return Book.favourOf(favourCtx(), id); }
// A deed the house will not forget, and the grievance named as the cause (favourbook.js).
function recordDeed(id, d, why, turn) { return Book.recordDeed(favourCtx(), id, d, why, turn); }
function causeOf(id) { return Book.causeOf(favourCtx(), id); }
function noteFavour(id, d, why) { return Book.noteFavour(favourCtx(), id, d, why); }
// Kindness wears thin (favourbook.js).
function temper(action, house, changes, dry = false) { return Book.temper(favourCtx(), action, house, changes, dry); }
// Shifts favour, and says what it did for the result card (favourbook.js).
function shiftAndTell(changes, why, cost = 0) { return Book.shiftAndTell(favourCtx(), changes, why, cost); }
function shiftFavour(changes, why = "", told = false) { return Book.shiftFavour(favourCtx(), changes, why, told); }
// Where a house's favour settles when the King leaves it be (favourbook.js).
function restingFavour(p) { return Book.restingFavour(favourCtx(), p); }

// The Hand of the King advises: the realm's matters, worst first, with the
// orders that answer them (counsel.js). Its context, read fresh on every call.
const counselCtx = () => ({ world, meta, court, stakes, deeds, favourWhy, lastSeason, favourOf, seasonsLeft, priceOf, yearlyKey, FAVOUR, shiftFavour, record });
function counsel(players, cities, threat) { return Counsel.counsel(counselCtx(), players, cities, threat); }

// --- the court's season (court.js) ------------------------------------------------
// Once a season the court sits and the realm holds still: its sitting, pace,
// docket and rulings live in court.js. What the bridge's clock and routes read
// stays here: the realm's matters, whether the court holds the realm, and
// whether the King is away.
let counselNow = [];  // the realm's matters, as the last reading of the world found them
let sitting = false;  // a sitting holds the realm until the court closes
let away = false;  // no window is watching: the realm waits for the King (every strategy game pauses when the player isn't there)
const timeoutNow = () => (paused || sitting || away ? 0 : turnSeconds);
const courtYearOf = () => Sittings.courtYearOf(sittingCtx());
const heardCtx = () => Sittings.heardCtx(sittingCtx());
function hold(on) { return Sittings.hold(sittingCtx(), on); }
function courtSeason(turn, force = false) { return Sittings.courtSeason(sittingCtx(), turn, force); }
// The King closes the court; every matter answered, the doors close (court.js).
function closeCourt(turn) { return Sittings.closeCourt(sittingCtx(), turn); }
function closeIfDone(turn, closing = false) { return Sittings.closeIfDone(sittingCtx(), turn, closing); }
// What stands before the King now (court.js).
function docket() { return Sittings.docket(sittingCtx()); }

// What the King's silence costs, matter by matter (counsel.js).
function lapseOf(o) { return Counsel.lapseOf(counselCtx(), o); }
function lapse(m, turn) { return Counsel.lapse(counselCtx(), m, turn); }

// A royal match needs an unwed son or daughter of age from each house (counsel.js).
function matchFor(pa, pb) { return Counsel.matchFor(counselCtx(), pa, pb); }

// --- What the crown's favour costs -------------------------------------------------

// The reign's story for the view: each beat so far dated by the realm's calendar.
function storyNow() {
  const s = arcs?.reignView();
  if (!s) return null;
  return { ...s, beats: (s.beats ?? []).map((b) => ({ ...b, when: b.turn != null ? calendar(b.turn) : null })) };
}

// The crown's great occasions come once a year, and a decree's price grows with
// the treasury (treasury.js). Its context, read fresh on every call.
const treasuryCtx = () => ({ world, meta, history, tally, lastSeason, send, record, scene, deed, crownOf });
function yearlyKey(cmd) { return Treasury.yearlyKey(treasuryCtx(), cmd); }
function seasonsLeft(key) { return Treasury.seasonsLeft(treasuryCtx(), key); }
function priceOf(action) { return Treasury.priceOf(treasuryCtx(), action); }

// --- Oaths and the royal host (campaigns.js) ---------------------------------------

function sworn(pid) { return Camp.sworn(campCtx(), pid); }
function startCampaign(c) { return Camp.startCampaign(campCtx(), c); }
function marchOdds(house, allies, opts) { return Camp.marchOdds(campCtx(), house, allies, opts); }
function siegeRuled(beat, option) { return Camp.siegeRuled(campCtx(), beat, option); }
function resolveCampaigns(turn) { return Camp.resolveCampaigns(campCtx(), turn); }

// The reign's goal, as the top bar shows it (reign.js; GOAL_FAVOUR comes from there).
function goalNow() { return Reign.goalNow(reignCtx()); }

// Each turn the crown takes its tithe (season.js); what it keeps between turns stays here.
const tally = { total: 0, upkeep: 0 };  // the tithe since the last reckoning
const lastSeason = { net: 0 };  // the tithe less upkeep, this season, for the top bar
const favourPast = {};  // turn -> {house id: favour}, the last two years
// The King's own works rise over two seasons, then stand and pay (treasury.js).
function royalWorks(turn) { return Treasury.royalWorks(treasuryCtx(), turn); }

function yearText(y) {
  const n = Number(y);
  return n < 0 ? `${-n} BC` : `${n} AD`;
}

// --- ledger, timing and scoring ------------------------------------------------

// The great houses (realm.js: not wild, not the crown, and holding a town).
function greatHouses() {
  return Realm.greatHouses(world);
}

// One line per turn: each house's towns, people, gold, armies and grain; plus
// the realm's Peace (share of house pairs not at war) and totals.
// Money in words is in crowns, a hundred to each Freeciv gold, so every figure
// the King reads (court prices, rulings, the chronicle) matches the ledger.
const crowns = (text) => String(text ?? "").replace(/(\d+) gold\b/g, (_, n) => `${(Number(n) * 100).toLocaleString("en-GB")} crowns`).replace(/(\d+) gold\)/g, (_, n) => `${(Number(n) * 100).toLocaleString("en-GB")} crowns)`);
const inCrowns = (v) => JSON.parse(JSON.stringify(v), (k, x) => (typeof x === "string" && ["text", "label", "hint", "voice", "summary"].includes(k) ? crowns(x) : k === "facts" && Array.isArray(x) ? x.map(crowns) : x));

// Heads, not Freeciv points: a size-1 village is about 500 souls, a size-5
// market town 7,500, a size-10 city 27,500. Grows faster than size, as towns do.
const soulsOf = (size) => 250 * size * (size + 1);

function ledger() {
  if (!world || history.length && history[history.length - 1].turn >= world.turn) return;
  const d = detail();
  const houses = {};
  const ids = new Set(greatHouses().map((p) => p.id));
  let pop = 0;
  let soulsAll = 0;
  let food = 0;
  let wars = 0;
  for (const p of greatHouses()) {
    const mine = world.cities.filter((c) => c.owner === p.id);
    const size = mine.reduce((s, c) => s + c.size, 0);
    const grain = mine.reduce((s, c) => s + (d?.cities[c.id]?.foodStock ?? 0), 0);
    const souls = mine.reduce((s, c) => s + soulsOf(c.size), 0);
    houses[houseFor(p).name] = { towns: mine.length, pop: size, souls, gold: p.gold, armies: p.units, grain };
    pop += size;
    soulsAll += souls;
    food += grain;
    // A war the King has stilled (a truce, a match) is peace in the realm's eyes,
    // though the engine still counts the two houses at war.
    const calm = (o) => { const a = court?.lordOfHouse(p.id), b = court?.lordOfHouse(o); return !!(a && b && court.truce(a.id, b.id)); };
    wars += (d?.players[p.id]?.atWarWith ?? []).filter((o) => ids.has(o) && !calm(o)).length;
  }
  const n = ids.size;
  const pairs = (n * (n - 1)) / 2 || 1;
  const crown = (world.players ?? []).find((p) => houseFor(p).crown);
  const row = {
    // A host marching on the throne is war at the realm's heart: it halves the peace.
    turn: world.turn, at: Date.now(), peace: Math.max(0, 1 - wars / 2 / pairs) * (stakes?.s.usurper.stage === "march" ? 0.5 : 1), pop, souls: soulsAll, food,
    treasury: crown?.gold ?? 0, houses,
  };
  history.push(row);
  fs.appendFileSync(path.join(P.state, "history.jsonl"), JSON.stringify(row) + "\n");
}

// The crown, its seat, and a soldier (the ladder in reign.js and the campaigns use them).
const crownOf = () => world?.players?.find((p) => houseFor(p).crown);
const crownSeat = () => { const c = crownOf(); return c ? world.cities.find((x) => x.owner === c.id && x.capital) ?? world.cities.find((x) => x.owner === c.id) : null; };
const SOLDIER = (u) => !CIVILIAN.has(u.type);
// The royal ladder of aims and the King's three ambitions (reign.js).
function ladder() { return Reign.ladder(reignCtx()); }


// The royal host marches on a town for a ruling the court already paid for (campaigns.js).
function marchOn(cityId) { return Camp.marchOn(campCtx(), cityId); }

// How the reign ends: its epilogue, its score, its name (reign.js).
function endReign(why, outcome = "completed") { return Reign.endReign(reignCtx(), why, outcome); }

// The reign's clock only runs while the realm does.
setInterval(() => {
  // No window watching for 15 s: the realm waits, clock and all, so nothing is
  // decided behind the King's back; when he's back, a waiting matter is heard at once.
  const gone = meta?.status === "running" && !isWatched();
  if (gone !== away) {
    away = gone;
    send(`set timeout ${timeoutNow()}`);
    if (!away && world && meta?.court) {
      courtYearOf().sitOnReturn = true;
      courtSeason(world.turn);
    }
  }
  if (away) return;
  // The court holds the realm while the King watches.
  if (meta?.court?.sitting != null || (meta?.status === "running" && meta?.interlude && !meta.interlude.seen)) hold(true);
  // An aim met is met at once, held clock or not: the King never reads "21 of 12".
  if (meta?.status === "running" && Freeciv.proc()) ladder();
  if (!meta || paused || sitting || meta.status !== "running" || !Freeciv.proc()) return;  // the court sitting holds the clock too
  Reign.tick(reignCtx());  // the clock, and what it brings: the last act, ambitions, the council, an act's end (reign.js)
}, 5000);

function shutdown() {
  if (meta) chron.saveMeta(meta);
  try { minds?.flush?.(); } catch (err) { console.error("minds flush:", err); }
  switching = true;
  stopFreeciv().then(() => process.exit(0));
  setTimeout(() => process.exit(0), 8000);
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

// --- HTTP API --------------------------------------------------------------------

// json, body and bytes: http_util.js.

function reignInfo() { return Reign.reignInfo(reignCtx()); }

// The routes' context (routes_*.js), built fresh for each request: the realm's
// state through getters (read when a handler uses it, so a snapshot or a switch
// of chronicle during an await is seen), setters for what a route changes, and
// the bridge's own helpers.
const routeCtx = () => ({
  get world() { return world; },
  get counselStale() { return counselStale; }, set counselStale(v) { counselStale = v; },
  get P() { return P; },
  get meta() { return meta; },
  get chronicle() { return chronicle; },
  get history() { return history; },
  get turnSeconds() { return turnSeconds; }, set turnSeconds(v) { turnSeconds = v; },
  get paused() { return paused; }, set paused(v) { paused = v; },
  get court() { return court; }, get chatter() { return chatter; },
  get decreesIssued() { return decreesIssued; }, set decreesIssued(v) { decreesIssued = v; },
  get stakes() { return stakes; },
  get minds() { return minds; },
  get arcs() { return arcs; },
  get arcsRunning() { return arcsRunning; }, set arcsRunning(v) { arcsRunning = v; },
  townStates, reignInfo, refreshCounsel, worldView, inCrowns, switchTo, endReign, send, timeoutNow, record,
  DIR, favourOf, runSeason, sittingCtx, docket, hold, closeCourt, rule, closeIfDone, yearlyKey, seasonsLeft,
  priceOf, causeOf, sworn, deed, startCampaign, temper, shiftAndTell, scene, keepTruce, decreeScenes, snapshot,
  crowns, arrivals, courtSeason, kingName, marksNow, marks, picture, detail, talkToNamed, isKing, KING, arcCtx,
  runArcs, OWN_STORIES, ownStory, storyForForm, rolesOf, BEAT_WHEN, BEAT_DOES
});

// The bridge's routes, "METHOD /path" -> handler(req, res, url). "* /path" answers
// any method; an exact method's entry is looked up first, so "POST /person" wins
// over "* /person" as it did when the routes were a chain of ifs.
const ROUTES = {
  "* /world": (req, res, url) => RealmRoutes.world(routeCtx(), req, res, url),
  "* /map": (req, res, url) => RealmRoutes.realmMap(routeCtx(), req, res, url),
  "* /chronicle": (req, res, url) => RealmRoutes.chronicle(routeCtx(), req, res, url),
  "* /ledger": (req, res, url) => RealmRoutes.ledger(routeCtx(), req, res, url),
  "* /records": (req, res, url) => RealmRoutes.records(routeCtx(), req, res, url),
  "* /scenarios": (req, res, url) => RealmRoutes.scenarios(routeCtx(), req, res, url),
  "* /chronicles/options": (req, res, url) => RealmRoutes.chronicleOptions(routeCtx(), req, res, url),
  "GET /chronicles": (req, res, url) => RealmRoutes.listChronicles(routeCtx(), req, res, url),
  "POST /chronicles": (req, res, url) => RealmRoutes.createChronicle(routeCtx(), req, res, url),
  "POST /chronicles/open": (req, res, url) => RealmRoutes.openChronicle(routeCtx(), req, res, url),
  "POST /reign/end": (req, res, url) => RealmRoutes.end(routeCtx(), req, res, url),
  "POST /reign/continue": (req, res, url) => RealmRoutes.continueReign(routeCtx(), req, res, url),
  "POST /reign/opening": (req, res, url) => RealmRoutes.opening(routeCtx(), req, res, url),
  "POST /pause": (req, res, url) => RealmRoutes.pause(routeCtx(), req, res, url),
  "POST /resume": (req, res, url) => ROUTES["POST /pause"](req, res, url),
  "* /reign/options": (req, res, url) => RealmRoutes.reignOptions(routeCtx(), req, res, url),
  "* /ai": (req, res, url) => RealmRoutes.ai(routeCtx(), req, res, url),
  "POST /speed": (req, res, url) => RealmRoutes.speed(routeCtx(), req, res, url),
  "POST /counsel/answer": (req, res, url) => CourtRoutes.counselAnswer(routeCtx(), req, res, url),
  // An event card answered (events.js): its cost paid, its effect now, its later one queued.
  "POST /event/answer": async (req, res, url) => {
    const b = await body(req);
    const [code, out] = Events.answer({ meta, world, court, detail, send, record, shiftFavour, favourOf }, b.choice);
    return json(res, code, out);
  },
  // An order to one of the King's hosts (hosts.js: the view asks, the bridge decides and moves it).
  "POST /host/order": async (req, res, url) => {
    const [code, out] = Hosts.order({ world, meta, sworn, crownSeat }, await body(req));
    if (code === 200) { record({ turn: world?.turn ?? 0, kind: "decree", text: out.text }); meta.lastActAt = world?.turn ?? 0; meta.idleTold = false; }  // an order is an act (season.js idle)
    // A march on a great house's town is declared as it is ordered: the house and the realm hear of it.
    if (code === 200 && out.declare) {
      const d = DECREES.march;
      const town = world.cities.find((c) => c.id === out.declare.city);
      const fav = { [out.declare.house]: d.favour ?? -25, ...Object.fromEntries(greatHouses().filter((p) => p.id !== out.declare.house).map((p) => [p.id, d.others ?? -2])) };
      shiftFavour(fav, "the royal host");
      deed(kingDeeds.tagsFor("decree", "march"), { favour: fav, place: town ? cityName(town.id) : "" });
      counselStale = true;
    }
    return json(res, code, out);
  },
  "POST /decree": (req, res, url) => DecreeRoutes.issueDecree(routeCtx(), req, res, url),
  "POST /test/court": (req, res, url) => TestRoutes.sit(routeCtx(), req, res, url),
  "POST /test/stage": (req, res, url) => TestRoutes.stage(routeCtx(), req, res, url),
  "POST /test/grow": (req, res, url) => TestRoutes.grow(routeCtx(), req, res, url),
  "POST /test/deed": (req, res, url) => TestRoutes.noteDeed(routeCtx(), req, res, url),
  "POST /test/mark": (req, res, url) => TestRoutes.mark(routeCtx(), req, res, url),
  "POST /test/news": (req, res, url) => TestRoutes.news(routeCtx(), req, res, url),
  "POST /test/clock": (req, res, url) => TestRoutes.clock(routeCtx(), req, res, url),
  "POST /scene/arrived": (req, res, url) => DecreeRoutes.arrived(routeCtx(), req, res, url),
  "POST /scene/kindled": (req, res, url) => DecreeRoutes.kindled(routeCtx(), req, res, url),
  "* /usage": (req, res, url) => RealmRoutes.usage(routeCtx(), req, res, url),
  "GET /mood": (req, res, url) => DecreeRoutes.moods(routeCtx(), req, res, url),
  "POST /mood/revoke": (req, res, url) => DecreeRoutes.revokeMood(routeCtx(), req, res, url),
  "POST /mood": (req, res, url) => DecreeRoutes.setMood(routeCtx(), req, res, url),
  "GET /court": (req, res, url) => CourtRoutes.court(routeCtx(), req, res, url),
  "POST /hear": (req, res, url) => CourtRoutes.hear(routeCtx(), req, res, url),
  "POST /voice": (req, res, url) => CourtRoutes.sayAloud(routeCtx(), req, res, url),
  "POST /interlude/close": (req, res, url) => CourtRoutes.closeInterlude(routeCtx(), req, res, url),
  "POST /court/close": (req, res, url) => CourtRoutes.close(routeCtx(), req, res, url),
  "POST /court/answer": (req, res, url) => CourtRoutes.answer(routeCtx(), req, res, url),
  "POST /court/say": (req, res, url) => CourtRoutes.say(routeCtx(), req, res, url),
  "* /house": (req, res, url) => PeopleRoutes.house(routeCtx(), req, res, url),
  "POST /lore/written/person": (req, res, url) => RealmRoutes.writePerson(routeCtx(), req, res, url),
  "* /names": (req, res, url) => RealmRoutes.playerNames(routeCtx(), req, res, url),
  "* /lore/map": (req, res, url) => RealmRoutes.loreMap(routeCtx(), req, res, url),
  "* /lore": (req, res, url) => RealmRoutes.lore(routeCtx(), req, res, url),
  "* /person": (req, res, url) => PeopleRoutes.person(routeCtx(), req, res, url),
  "* /characters/options": (req, res, url) => PeopleRoutes.characterOptions(routeCtx(), req, res, url),
  "POST /person/fall": (req, res, url) => PeopleRoutes.fall(routeCtx(), req, res, url),
  "POST /person": (req, res, url) => PeopleRoutes.editPerson(routeCtx(), req, res, url),
  "POST /characters": (req, res, url) => PeopleRoutes.createCharacter(routeCtx(), req, res, url),
  "* /townsfolk": (req, res, url) => PeopleRoutes.folkOf(routeCtx(), req, res, url),
  "* /town/people": (req, res, url) => PeopleRoutes.townPeople(routeCtx(), req, res, url),
  "POST /talk": (req, res, url) => PeopleRoutes.talk(routeCtx(), req, res, url),
  "GET /arcs": (req, res, url) => StoryRoutes.arcs(routeCtx(), req, res, url),
  "* /arcs/templates": (req, res, url) => StoryRoutes.templates(routeCtx(), req, res, url),
  "POST /arcs/tick": (req, res, url) => StoryRoutes.tick(routeCtx(), req, res, url),
  "POST /arcs/start": (req, res, url) => StoryRoutes.start(routeCtx(), req, res, url),
  "POST /stories/generate": (req, res, url) => StoryRoutes.generate(routeCtx(), req, res, url),
  "GET /stories/own": (req, res, url) => StoryRoutes.own(routeCtx(), req, res, url),
  "POST /write": (req, res, url) => StoryRoutes.write(routeCtx(), req, res, url),
  "POST /stories/premise/idea": (req, res, url) => StoryRoutes.suggestPremise(routeCtx(), req, res, url),
  "POST /stories/beat/idea": (req, res, url) => StoryRoutes.suggestBeat(routeCtx(), req, res, url),
  "POST /stories/beat": (req, res, url) => StoryRoutes.beat(routeCtx(), req, res, url),
  "POST /arcs/write": (req, res, url) => StoryRoutes.writeArc(routeCtx(), req, res, url),
  "* /lord": (req, res, url) => PeopleRoutes.lord(routeCtx(), req, res, url),
  "POST /season": (req, res, url) => RealmRoutes.season(routeCtx(), req, res, url),
  "POST /tithe": (req, res, url) => DecreeRoutes.tithe(routeCtx(), req, res, url),
};

http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://x");
  if (req.method === "OPTIONS") return json(res, 204, {});
  if (!meta) return json(res, 503, { error: "no chronicle" });
  if (await mindsRoute(minds, url, req, body, json, res)) return;

  const route = ROUTES[`${req.method} ${url.pathname}`] ?? ROUTES[`* ${url.pathname}`];
  if (route) return route(req, res, url);
  // Routes matched by prefix, in order, after the table (no table path starts with one).
  if (url.pathname.startsWith("/minds/") && chatter) {
    const out = await chatter.route(url, req, body);
    if (out) return json(res, ...out);
  }
  json(res, 404, { error: "not found" });
}).listen(PORT, "127.0.0.1", () => console.log(`Bridge listening on http://localhost:${PORT}`));

// --- start ---------------------------------------------------------------------

chron.adoptLegacy();
let startId = chron.activeId();
if (!startId || !chron.list().some((c) => c.id === startId)) {
  startId = (chron.list()[0] ?? chron.create({ name: "Aldmere I" })).id;
  chron.setActive(startId);
}
load(startId);
startFreeciv();
