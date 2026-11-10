// Bridge between the Freeciv server (the simulation) and the Godot view.
// - Runs one Freeciv server for the active chronicle (see chronicles.js),
//   resuming from that chronicle's newest save; can switch chronicles live.
// - Turns Freeciv's EVENT lines into the chronicle, keeps a per-turn ledger,
//   times and scores reigns.
// - Exposes a small HTTP API on 127.0.0.1:8787 for the view.

import fs from "node:fs";
import zlib from "node:zlib";
import crypto from "node:crypto";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { houseFor, cityName, nameIn, describe, rememberNames, HOUSES } from "./narrator.js";
import { godCommand, healLua } from "./god.js";
import { readSave, extractDetail } from "./savefile.js";
import { townsfolk } from "./townsfolk.js";
import { ROLES, GOALS, TRAITS, setReignSeed } from "./characters.js";
import { editRow, rng as rngFor } from "./fresh.js";
import { folkTale, folkPlain, moodRules, speak, speech, voiceFor, transcribe, aiStatus } from "./claude.js";
import * as chron from "./chronicles.js";
import * as names from "./names.js";
import * as rewrites from "./written.js";
import { decree, titheLua, clampFavour, DECREES, bannersReady, TITHE_HIGH } from "./crown.js";
// Stories the player generates or writes, kept with their realms.
const OWN_STORIES = path.join(chron.HOME, "stories");
ownStories(OWN_STORIES);
import { Court } from "./characters.js";
import { Minds, route as mindsRoute } from "./minds.js";
import { Arcs, templates as arcTemplates, check, ownStories, storiesChanged } from "./arcs.js";
import { Chatter } from "./chatter.js";
import { bible, FAMILIES, LESSER } from "./lore.js";
import { Stakes, calendar } from "./stakes.js";
import * as kingDeeds from "./ledger.js";
import * as Weather from "./weather.js";
import * as Realm from "./realm.js";
import { BANDS } from "./favour.js";
import * as Freeciv from "./freeciv.js";
import * as View from "./view.js";
import * as Camp from "./campaigns.js";
import { CIVILIAN } from "./campaigns.js";
import * as Counsel from "./counsel.js";
import * as Treasury from "./treasury.js";
import { FAVOUR, WORK_SEASONS } from "./treasury.js";
import * as Reign from "./reign.js";
import { GOAL_FAVOUR } from "./reign.js";
import * as Sittings from "./court.js";
import * as Book from "./favourbook.js";
import { LEAN, theirs } from "./favourbook.js";
import { watched, usageToday, moodFrom, isWatched, arcFromWords, beatIdea, premiseIdea, writeFor } from "./claude.js";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 8787);

// --- the active chronicle ----------------------------------------------------

let meta = null; // chronicles.js meta for the running realm
let P = null; // its paths
let chronicle = [];
let world = null;
let scars = [];
let history = [];
let detailCache = { file: null, mtime: 0, data: null };
let turnSeconds = 20;
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
let seasonRunning = false;
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
  scars = chron.readJson(path.join(P.state, "scars.json"), []);
  detailCache = { file: null, mtime: 0, data: null };
  turnSeconds = 40;  // one pace for every realm: a season in forty seconds, with a court at each (GAME_DESIGN)
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

// A ceasefire between two houses in Freeciv itself. Its Lua and its server
// commands can't change diplomacy, but its save holds it: save, set both
// players' diplstate rows to "Cease-fire" with `turns` left, and resume from
// that save. Freeciv then keeps it and ends it by itself.
// pairs: [[houseA, houseB, seasons], ...], all written in one reload.
async function ceasefire(pairs) {
  if (!Freeciv.proc() || switching || !pairs.length) return false;
  switching = true;
  const t0 = Date.now();
  try {
    await stopFreeciv();
    const save = newestSave();
    if (!save) return false;
    let text = zlib.zstdDecompressSync(fs.readFileSync(save)).toString();
    for (const [a, b, turns = 16] of pairs) text = setDipl(setDipl(text, a, b, turns), b, a, turns);
    const out = path.join(P.saves, `realm-T${String(world?.turn ?? 0).padStart(4, "0")}-ceasefire-${Date.now()}.sav.zst`);
    fs.writeFileSync(out, zlib.zstdCompressSync(Buffer.from(text)));
    return true;
  } finally {
    startFreeciv();
    switching = false;
    // The hitch: how long the realm was without Freeciv while the truce went in.
    Freeciv.timeReload(t0);
  }
}

// Player p's diplstate toward player q, set to a ceasefire. Freeciv's AI keeps
// its own war plan per rival (the "ai" table: love, spam, countdown,
// war_reason, ...); left alone it declares war again on its first turn, so the
// King's truce also drops the plan: no countdown, no reason (DAI_WR_NONE = 5).
// The grudge stays, cooled a tenth: a truce stops the swords, not the hatred,
// and war may come back when it ends.
function setDipl(text, p, q, turns) {
  text = editRow(text, p, "diplstate", q, (c) => {
    c[0] = '"Cease-fire"';
    c[1] = '"Cease-fire"';
    c[3] = String(turns);
    c[4] = "0";
  });
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
    snapshot();
  }, 4000);
}

let switching = false;

const stopFreeciv = Freeciv.stop;

async function switchTo(id) {
  switching = true;
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
    great.forEach((id, i) => {
      const want = i < cold ? 18 + Math.floor(r() * 15) : favourOf(id) + Math.floor(r() * 21) - 10;
      const d = clampFavour(want) - favourOf(id);
      if (!d) return;
      favour[id] = favourOf(id) + d;  // their history, not the King's deed: no deed is recorded
      (favourWhy[id] ??= []).push({ d, why: d < 0 ? "an old quarrel with the crown" : "an old kindness from the crown" });
    });
  }
  saveFavour();
  const crown = world.players.find((x) => houseFor(x).crown);
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
const viewCtx = () => ({ world, meta, history, court, stakes, turnSeconds, counselNow, scenes, effects, favourWhy, favourPast, lastSeason, detail, favourOf, marchOdds, greatHouses, sworn, priceOf, seasonsLeft, crownOf, crownSeat, reignInfo, storyNow, marksNow, goalNow, CIVILIAN, TURNING, GOAL_FAVOUR, soulsOf });
// The realm as the view sees it (GET /world): built in view.js.
function worldView() {
  return View.worldView(viewCtx());
}

// The Hand's matters, read from the realm as it stands now.
let counselStale = true;  // the King acted since the last reading: read the realm again
function refreshCounsel() {
  if (!world) return;
  counselStale = false;
  const v = worldView();
  counselNow = counsel(v.players, v.cities, v.threat);
}

// The realm's states, set on each town (view.js).
function townStates() {
  View.townStates({ world, meta, scenes, detail, besiegers, favourOf });
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
    refreshCounsel();
    applyStartOptions();
    applyOpeningMood();
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
  get sitting() { return sitting; }, setSitting: (v) => { sitting = v; }, timeoutNow, send, record, scene, deed, crowns, marchOn, shiftAndTell, shiftFavour, favourOf, ceasefire, turnHouses, lapse, lapseOf });
// A ruling on a petition, by option, and how the realm sees it (court.js).
function rule(id, option) { return Sittings.rule(sittingCtx(), id, option); }

// A town besieged, the royal host and its sieges: campaigns.js. Its context,
// read fresh on every call; scenes is read live, as scene() may replace it.
const campCtx = () => ({ world, meta, court, get scenes() { return scenes; }, send, record, scene, deed, shiftFavour, greatHouses, crownOf, favourOf, causeOf, SOLDIER });
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
      break;
  }
}

function onEvent(line) {
  let ev;
  try { ev = JSON.parse(line.slice(line.indexOf("EVENT {") + 6)); } catch { return; }
  if (ev.kind === "scar") {
    scars.push({ city: Number(ev.city), tiles: ev.tiles, heal: Number(ev.heal) });
    fs.writeFileSync(path.join(P.state, "scars.json"), JSON.stringify(scars));
    return;
  }
  if (ev.kind === "turn") {
    healScars(Number(ev.turn));
    collectTithe(Number(ev.turn));
    setTimeout(() => stakes?.tick(Number(ev.turn), world, { favour: favourOf, sworn, shift: shiftFavour, send: (l) => send(`lua cmd ${l}`), watched: isWatched(), options: meta.options ?? {}, mayRise, ultimatum: askUltimatum, rose }), 2000);
    if (Number(ev.turn) % 4 === 0) setTimeout(runSeason, 2500);
    // The season's weather, rolled once as the season turns (weather.js, from the reign's seed).
    Weather.advance(meta, Number(ev.turn), calendar(Number(ev.turn)).season);
    setTimeout(() => runArcs(1), 4000);
    // Let the AI finish its start-of-turn moves before dumping the world.
    setTimeout(snapshot, 1500);
    setTimeout(() => minds?.tick(Number(ev.turn)), 3000);
    if ((Number(ev.turn) - 1) % 4 === 0) record({ turn: Number(ev.turn), kind: "year", text: `The year ${calendar(ev.turn).year} AC begins.` });
    return;
  }
  const town = ev.city !== undefined ? world?.cities?.find((c) => c.id === Number(ev.city)) : null;
  if (ev.kind === "unit_killed") {
    const loser = world?.players?.find((p) => p.id === Number(ev.owner));
    scene("battle", { x: Number(ev.x), y: Number(ev.y), owner: Number(ev.owner), unit: ev.unit, house: loser ? houseFor(loser).name : null });
  }
  if (ev.kind === "city_transferred" && town) scene(ev.reason === "conquest" ? "sack" : "handover", { x: town.x, y: town.y, city: town.id, from: Number(ev.from), to: Number(ev.to) });
  if (ev.kind === "city_destroyed" && town) scene("razed", { x: town.x, y: town.y, city: town.id });
  // The land keeps its scars (state/marks.json): where men died, a town was stormed, a town was razed.
  // The view burns the ground there, fading with the mark's age, and a razed town leaves a ruin.
  const scar = ev.kind === "unit_killed" ? ["battle", Number(ev.x), Number(ev.y)] : ev.kind === "city_transferred" && ev.reason === "conquest" && town ? ["sack", town.x, town.y] : ev.kind === "city_destroyed" && town ? ["razed", town.x, town.y] : null;
  if (scar) {
    const [kind, x, y] = scar;
    const list = marksNow().filter((m) => !(m.kind === kind && m.x === x && m.y === y));
    list.push({ kind, x, y, turn: Number(ev.turn) });
    fs.writeFileSync(path.join(P.state, "marks.json"), JSON.stringify((marks.list = list.slice(-400))));
  }
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
  get history() { return history; }, get chronicle() { return chronicle; }, record, send, scene, detail, favourOf, saveFavour, crownOf, crownSeat, SOLDIER, soulsOf, theirs });
// The King's ledger and the name the realm gives him (reign.js).
function kingName(outcome = null) { return Reign.kingName(reignCtx(), outcome); }
function deed(tag, opts = {}) { return Reign.deed(reignCtx(), tag, opts); }

// The realm's scars, as long as they show: a battle's ground heals in 12 seasons, a stormed
// town's in 16; a razed town's ruin stands until a town is founded on the spot again.
const MARK_SEASONS = { battle: 12, sack: 16 };
const marks = { file: null, list: [] };
function marksNow() {
  const f = P && path.join(P.state, "marks.json");
  if (f !== marks.file) { marks.file = f; marks.list = f ? chron.readJson(f, []) : []; }
  const turn = Number(world?.turn ?? 0);
  marks.list = marks.list.filter((m) => (m.kind === "razed" ? turn - m.turn < 2 || !world?.cities?.some((c) => c.x === m.x && c.y === m.y) : turn - m.turn < (MARK_SEASONS[m.kind] ?? 12)));
  return marks.list;
}

// Every four turns (a year of seasons), the people of the realm make their moves.
async function runSeason() {
  if (!world || seasonRunning || !court) return;
  seasonRunning = true;
  try {
    await court.season(world, { wetHarvest: () => Weather.wetHarvest(meta.weather), favour: favourOf, cause: causeOf, warded: (pid) => (stakes?.s.wards?.[pid] ?? -1) > (world?.turn ?? 0) || sworn(pid), send: (l) => send(`lua cmd ${l}`), shift: shiftFavour, watched: isWatched(), options: meta.options ?? {}, ...heardCtx(), mayRise, rose });
  } catch (err) {
    console.error("season:", err);
  } finally {
    seasonRunning = false;
  }
}

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
function temper(action, house, changes) { return Book.temper(favourCtx(), action, house, changes); }
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
function courtSeason(turn) { return Sittings.courtSeason(sittingCtx(), turn); }
// The King closes the court; every matter answered, the doors close (court.js).
function closeCourt(turn) { return Sittings.closeCourt(sittingCtx(), turn); }
function closeIfDone(turn, closing = false) { return Sittings.closeIfDone(sittingCtx(), turn, closing); }
// What stands before the King now (court.js).
function docket() { return Sittings.docket(sittingCtx()); }

// A house turning against the King: each season it stays under 25 its anger
// fills; after TURNING seasons its lord sends the crown an ultimatum (a crisis
// at court). Only an ultimatum refused, or left to burn down, lets him raise
// his banners; won back above 25, the anger drains away.
const TURNING = 2;
function turnHouses(turn) {
  const turning = (meta.turning ??= {});
  for (const p of world?.players ?? []) {
    if (houseFor(p).wild || houseFor(p).crown || !world.cities.some((c) => c.owner === p.id)) continue;
    // A realm from before ultimatums: a house already under 25 is one season from sending its own.
    const t = (turning[p.id] ??= { seasons: favourOf(p.id) < BANDS.cooling ? TURNING - 1 : 0, state: null });
    if (favourOf(p.id) < BANDS.cooling) t.seasons = Math.min(TURNING, t.seasons + 1);
    else {
      t.seasons = Math.max(0, t.seasons - 1);
      if (t.seasons === 0 && t.state !== "refused" && t.march == null) t.state = null;  // a story's march keeps its ultimatum standing
    }
    // A story's march, held for its ultimatum: it goes once the King refused, or let it lie.
    if (t.march != null && mayRise(p.id)) {
      stakes?.declare(p.id, world, { send: (l) => send(`lua cmd ${l}`) }, t.march);
      t.march = null;
    }
    // An ultimatum met (favour shown, anger drained) calls the story's march off.
    if (t.march != null && !t.state) t.march = null;
    if (t.seasons >= TURNING && !t.state) {
      t.state = "sent";
      t.at = turn;
      record({ turn, kind: "unrest", text: `${houseFor(p).name} sends a rider to Kingsmere with an ultimatum for the King.` });
    }
  }
}
// A story that would march a house on Kingsmere: if its ultimatum has been
// refused (or gone two seasons unanswered) the host marches now; otherwise
// the ultimatum goes to court first, and the march waits for its answer.
function storyMarch(pid, size) {
  if (mayRise(pid)) return stakes?.declare(pid, world, { send: (l) => send(`lua cmd ${l}`) }, size);
  askUltimatum(pid).march = size ?? 10;
  chron.saveMeta(meta);
}

// A house about to rise sends the crown its ultimatum first (one rule for every
// rising: a story's march, the pretender's claim, a turned house). Sent once; its
// answer decides (mayRise).
function askUltimatum(pid) {
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
const mayRise = (pid) => { const t = meta.turning?.[pid]; return t?.state === "refused" || (t?.state === "sent" && (world?.turn ?? 0) - t.at >= 2); };
function rose(pid) {
  const t = meta.turning?.[pid];
  if (t) { t.state = null; t.seasons = 0; }
}

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

// Each turn the crown takes its tithe; a heavy tithe wears favour down.
const tally = { total: 0, upkeep: 0 };  // the tithe since the last reckoning
const lastSeason = { net: 0 };  // the tithe less upkeep, this season, for the top bar
const favourPast = {};  // turn -> {house id: favour}, the last two years
// The King's own works rise over two seasons, then stand and pay (treasury.js).
function royalWorks(turn) { return Treasury.royalWorks(treasuryCtx(), turn); }

function collectTithe(turn) {
  flushHeld();  // last season's grouped lines
  // The court sits each season (courtSeason).
  courtSeason(turn).catch((err) => console.error("court season:", err));
  if (!world) return;
  royalWorks(turn);
  favourPast[turn] = { ...favour };
  resolveCampaigns(turn);
  // Old grievances and kindnesses fade (about half in five years), so the cause
  // the Hand names is what moves a house now, not a lifetime's sum.
  for (const id of Object.keys(favourWhy)) {
    favourWhy[id] = (favourWhy[id] ?? []).map((r) => ({ ...r, d: r.d * 0.97 })).filter((r) => Math.abs(r.d) >= 1);
  }
  for (const t of Object.keys(favourPast)) if (Number(t) < turn - 8) delete favourPast[t];
  // The season's tithe, its wagons and its deed (treasury.js).
  Treasury.tithe(treasuryCtx(), turn);
  const wear = isWatched() ? meta.tithe * 4 : 0;  // 10% wears 0.4 a season; the drift to 55 outweighs it
  for (const p of world.players) {
    if (houseFor(p).wild || houseFor(p).crown) continue;
    const before = favourOf(p.id);
    // Favour drifts back toward the house's own temper, minus the tithe's wear.
    // Gratitude fades: a house well above its own temper cools faster than one near it.
    const rest = restingFavour(p);
    favour[p.id] = clampFavour(before + (rest - before) * (before - rest > 15 ? 0.08 : 0.03) - wear);
    if (wear) noteFavour(p.id, -wear, "the royal tithe");
    // A heavy tithe, year on year, becomes a deed of its own: what a house paid
    // in a year it remembers at the year's end.
    const pain = (deeds._tithe ??= {});
    pain[p.id] = (pain[p.id] ?? 0) + wear;
    if (turn % 4 === 0) { if (pain[p.id] >= 3) recordDeed(p.id, -pain[p.id], "the royal tithe", turn - 1); pain[p.id] = 0; }
    if (before >= 20 && favour[p.id] < 20) {
      const why = causeOf(p.id);
      record({ turn, kind: "unrest", text: `${houseFor(p).name} speaks openly against the crown. Their loyalty hangs by a thread.${why ? ` They have not forgotten ${why}.` : ""}` });
    }
  }
  saveFavour();
  // The reign's goal: every great house firmly the King's (GOAL_FAVOUR and up)
  // and no war between them. Marked once in the chronicle when won; lost again
  // when a house falls away or two take up arms.
  const united = goalNow().won;
  if (united && !meta.united) {
    meta.united = true;
    chron.saveMeta(meta);
    record({ turn, kind: "decree", text: `All ${goalNow().of} great houses stand behind the King, and none is at war with another. For the first time in a generation the realm answers to one crown, in truth and not in name.` });
  } else if (!united && meta.united) {
    meta.united = false;
    chron.saveMeta(meta);
  }
  Treasury.reckoning(treasuryCtx(), turn);
}

function healScars(turn) {
  const due = scars.filter((s) => s.heal <= turn);
  if (!due.length) return;
  scars = scars.filter((s) => s.heal > turn);
  fs.writeFileSync(path.join(P.state, "scars.json"), JSON.stringify(scars));
  for (const s of due) {
    healLua(s.tiles).forEach((l) => send(`lua cmd ${l}`));
    if (world?.cities?.some((c) => c.id === s.city)) {
      record({ turn, kind: "heal", text: `The land around ${cityName(s.city)} slowly recovers.`, city: s.city });
    }
  }
}

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


// A commanded peace: the two lords' houses keep a truce (no raids, no plots).
// The one truce writer (SSOT): every truce between two houses, from a decree,
// a court ruling, a story or a royal match, comes here. Freeciv's own ceasefire,
// so its AI stops fighting too (it ends by itself after `seasons`); its reload
// runs only behind a sitting court, where the realm is already held and the
// card covers the screen, otherwise it waits for one. The houses' truce is
// keyed to them, whoever leads them; the goal and the panels read Freeciv's.
function houseTruce(pair, seasons = 16) {
  if (!court || pair[0] === pair[1]) return;
  if (meta?.court?.sitting != null) ceasefire([[pair[0], pair[1], seasons]]).catch((e) => console.log("ceasefire:", e.message));
  else (meta.pendingCease ??= []).push([pair[0], pair[1], seasons]);
  court.truces ??= {};
  const key = `h:${Math.min(...pair)}:${Math.max(...pair)}`;
  court.truces[key] = Math.max(court.truces[key] ?? 0, (world?.turn ?? 0) + seasons);
}

function keepTruce(pair) {
  if (!court) return;
  houseTruce(pair, 16);
  const [a, b] = pair.map((pid) => court.lordOfHouse(pid));
  if (!a || !b) { court.saveCourt?.(); return; }
  court.truces[[a.id, b.id].sort().join(":")] = (world?.turn ?? 0) + 16;
  court.remember(a.id, `The King commanded peace with ${b.house}, and I bowed to it.`);
  court.remember(b.id, `The King commanded peace with ${a.house}, and I bowed to it.`);
  court.saveCourt?.();
}

// The royal host marches on a town for a ruling the court already paid for (campaigns.js).
function marchOn(cityId) { return Camp.marchOn(campCtx(), cityId); }

// The King commanded peace at the council: both hosts are turned home, as the
// peace decree does (crown.js), the blood-price already paid at court.
function councilRuled(beat, option) {
  const pair = meta.councilWar?.[beat];
  if (option !== "peace" || !pair || !world) return;
  const [a, b] = world.cities.some((x) => x.owner === pair[0]) ? pair : [pair[1], pair[0]];
  const c = world.cities.find((x) => x.owner === a);
  if (!c) return;
  // The court took the blood-price already: the decree's own fee is waived (its first line pays it).
  const r = decree({ action: "peace", city: c.id, to: b, price: 0, favourOf: () => 60, causeOf }, { ...world, players: world.players.map((p) => houseFor(p).crown ? { ...p, gold: 1e9 } : p) });
  if (r.error) { console.error("council peace:", r.error); return; }
  (r.lua ?? []).slice(1).forEach((l) => send(`lua cmd ${l}`));
  if (r.truce) keepTruce(r.truce);
}

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

function json(res, code, body) {
  res.writeHead(code, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" });
  res.end(JSON.stringify(names.showAll(body)));  // in the player's names (names.js)
}

function body(req) {
  return new Promise((resolve) => {
    let b = "";
    req.on("data", (d) => (b += d));
    req.on("end", () => { try { resolve(names.innerAll(JSON.parse(b || "{}"))); } catch { resolve({}); } });  // the player's names, turned back
  });
}

function bytes(req) {
  return new Promise((resolve) => {
    const parts = [];
    req.on("data", (d) => parts.push(d));
    req.on("end", () => resolve(Buffer.concat(parts)));
  });
}

function reignInfo() { return Reign.reignInfo(reignCtx()); }

// The bridge's routes, "METHOD /path" -> handler(req, res, url). "* /path" answers
// any method; an exact method's entry is looked up first, so "POST /person" wins
// over "* /person" as it did when the routes were a chain of ifs.
const ROUTES = {
  "* /world": async (req, res, url) => {
    townStates();
    if (url.searchParams.get("peek") !== "1") watched(); // the game window polls this every second while open (a test's peek doesn't count)
    if (!world) return json(res, 503, { error: "realm still forming", reign: reignInfo() });
    if (counselStale) refreshCounsel();
    return json(res, 200, worldView());
  },
  "* /map": async (req, res, url) => {
    const map = chron.readJson(path.join(P.state, "map.json"));
    return map ? json(res, 200, { ...map, land: meta?.land ?? null }) : json(res, 503, { error: "map not ready" });
  },
  "* /chronicle": async (req, res, url) => {
    const since = Number(url.searchParams.get("since") || 0);
    return json(res, 200, inCrowns(chronicle.filter((e) => e.seq > since).slice(-200)));
  },
  "* /ledger": async (req, res, url) => { return json(res, 200, history.slice(-400).map((r) => r.souls !== undefined ? r : { ...r, souls: r.pop * 600, houses: Object.fromEntries(Object.entries(r.houses).map(([k, h]) => [k, { ...h, souls: h.pop * 600 }])) })); },
  "* /records": async (req, res, url) => { return json(res, 200, chron.records().sort((a, b) => b.score - a.score)); },
  "* /scenarios": async (req, res, url) => {
    // Saved starting choices, to begin the same kind of realm again.
    const file = path.join(chron.HOME, "scenarios.json");
    const all = chron.readJson(file, []);
    if (req.method !== "POST") return json(res, 200, all);
    const b = await body(req);
    const name = String(b.name || "").trim().slice(0, 40);
    if (!name) return json(res, 400, { error: "a scenario needs a name" });
    const entry = { name, scenario: b.scenario, minutes: Number(b.minutes) || 0, wealth: b.wealth, mood: String(b.mood || "").slice(0, 300), options: chron.cleanOptions(b.options) };
    fs.writeFileSync(file, JSON.stringify([...all.filter((x) => x.name !== name), entry], null, 1));
    return json(res, 200, entry);
  },
  "* /chronicles/options": async (req, res, url) => { return json(res, 200, { defaults: chron.OPTION_DEFAULTS, houses: Object.keys(chron.HOUSE_NATIONS) }); },
  "GET /chronicles": async (req, res, url) => {
    return json(res, 200, { active: meta.id, list: chron.list() });
  },
  "POST /chronicles": async (req, res, url) => {
    const b = await body(req);
    const scenario = ["random", "aldmere", "aldmere_fresh"].includes(b.scenario) ? b.scenario : "aldmere";
    const m = chron.create({ name: String(b.name || "A New Realm").slice(0, 40), scenario, minutes: b.minutes, pace: b.options?.pace ?? turnSeconds, fate: b.fate, wealth: b.wealth, mood: b.mood, options: b.options });
    rewrites.applyTo(path.join(chron.paths(m.id).base, "characters"));  // the starting cast as the player rewrote it
    try { rewrites.distinctNames(chron.paths(m.id).base, JSON.parse(fs.readFileSync(path.join(path.dirname(new URL(import.meta.url).pathname), "data", "first-names.json"), "utf8"))); } catch (e) { console.log("names:", e.message); }  // no two living share a first name
    switchTo(m.id);
    return json(res, 200, m);
  },
  "POST /chronicles/open": async (req, res, url) => {
    const { id } = await body(req);
    if (!chron.list().some((c) => c.id === id)) return json(res, 404, { error: "no such chronicle" });
    switchTo(id);
    return json(res, 200, { ok: true });
  },
  "POST /reign/end": async (req, res, url) => {
    endReign("The King lays down the crown.");
    return json(res, 200, reignInfo());
  },
  "POST /reign/continue": async (req, res, url) => {
    // A timed reign has ended and been scored; the King rules on, with no clock,
    // in the same realm. The score stands in the records as it was.
    if (meta.status !== "ended") return json(res, 400, { error: "this reign has not ended" });
    meta.status = "running";
    meta.minutes = 0;
    paused = false;
    chron.saveMeta(meta);
    send(`set timeout ${timeoutNow()}`);
    record({ turn: world?.turn ?? 0, kind: "decree", text: "The King rules on." });
    return json(res, 200, reignInfo());
  },
  "POST /pause": async (req, res, url) => {
    if (meta.status !== "running") return json(res, 400, { error: "this reign has ended" });
    paused = url.pathname === "/pause";
    send(`set timeout ${timeoutNow()}`);
    return json(res, 200, reignInfo());
  },
  "POST /resume": (req, res, url) => ROUTES["POST /pause"](req, res, url),
  "* /reign/options": async (req, res, url) => {
    // The running reign's choices: read them, or change the ones that can
    // change mid-reign. Start-only choices (the world, which houses, their
    // temper, wealth and trust, the starting host) stay as they were.
    const LIVE = ["pace", "disasters", "raiders", "dead", "usurper", "petitions", "intrigue", "language"];
    const now = { ...chron.cleanOptions(meta.options ?? {}), pace: meta.pace ?? 12 };
    if (req.method !== "POST") return json(res, 200, { options: now, live: LIVE });
    const b = await body(req);
    const next = chron.cleanOptions({ ...now, ...Object.fromEntries(Object.entries(b).filter(([k]) => LIVE.includes(k))) });
    meta.options = { ...now, ...Object.fromEntries(LIVE.map((k) => [k, next[k]])) };
    // The season's length is also set by the speed buttons; only change it when asked.
    if ("pace" in b) {
      meta.pace = meta.options.pace;
      turnSeconds = meta.pace;
      send(`set timeout ${timeoutNow()}`);
    }
    meta.options.pace = meta.pace ?? meta.options.pace;
    chron.saveMeta(meta);
    // Freeciv's own dials, applied now.
    send(`set disasters ${{ none: 0, gentle: 5, normal: 25, cruel: 70 }[meta.options.disasters]}`);
    send(`set barbarians ${{ none: "disabled", normal: "normal", hordes: "hordes" }[meta.options.raiders]}`);
    return json(res, 200, { options: meta.options, live: LIVE });
  },
  "* /ai": async (req, res, url) => {
    // What the local model can do right now, for the settings page.
    return json(res, 200, await aiStatus());
  },
  "POST /speed": async (req, res, url) => {
    const { seconds } = await body(req);
    turnSeconds = Math.max(1, Math.min(600, Number(seconds) || 90));
    meta.pace = turnSeconds;
    chron.saveMeta(meta);
    send(`set timeout ${timeoutNow()}`);
    return json(res, 200, { turnSeconds });
  },
  "POST /counsel/answer": async (req, res, url) => {
    // The King answered the Hand's matter: it rests a year, and the next one comes up (court.js).
    const { key } = await body(req);
    return json(res, 200, Sittings.answerMatter(sittingCtx(), key));
  },
  "POST /decree": async (req, res, url) => {
    counselStale = true;
    decreesIssued++;
    const cmd = await body(req);
    if (meta.status !== "running") return json(res, 400, { error: "this reign has ended" });
    // A royal match needs a pair: an unwed son or daughter of age from each house,
    // one of each, chosen before a crown is spent. Nobody is wed twice.
    let pair = null;
    if (cmd.action === "marriage" && court) {
      // (matchFor below finds the same pair the Hand checks before offering a match.)
      const city = world.cities.find((c) => c.id === Number(cmd.city));
      const [la, lb] = [city?.owner, Number(cmd.to)].map((pid) => court.lordOfHouse(pid));
      const unwed = (lord) => court.alive().filter((k) => k.parents?.includes(lord.id) && !k.spouse && k.age >= 15);
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
    const result = decree({ ...cmd, works: meta.works ?? {}, price: priceOf(cmd.action), favourOf, causeOf, sworn, marching: (city) => (meta.campaigns ?? []).some((x) => x.city === city), usurper: stakes?.s.usurper, seat: stakes?.s.seat }, world);
    if (result.error) return json(res, 400, result);
    {
      const dc = world.cities.find((x) => x.id === Number(cmd.city));
      const dp = dc ? world.players.find((p) => p.id === dc.owner) : world.players.find((p) => p.id === Number(cmd.house ?? cmd.to));
      const taking = cmd.action === "grant" && Object.values(result.favour ?? {}).some((n) => n < 0);
      const place = /\{house\}/.test(kingDeeds.tagsFor("decree", cmd.action)?.says ?? "") ? (dp ? houseFor(dp).name : "") : (dc ? cityName(dc.id) : "");
      deed(kingDeeds.tagsFor("decree", taking ? "grant_take" : cmd.action), { favour: result.favour, place });
      // Marching on a house inside the King's own truce breaks his word.
      if (cmd.action === "march" && dp && court && Object.entries(court.truces ?? {}).some(([k, until]) => k.startsWith("h:") && k.split(":").slice(1).map(Number).includes(dp.id) && until > (world.turn ?? 0)))
        deed(kingDeeds.tagsFor("realm", "truce_march"), { act: false, place: houseFor(dp).name });
    }
    if (result.endUsurper && stakes) { stakes.s.usurper.stage = "none"; stakes.save(); }
    if (result.relieved != null) { (meta.relieved ??= {})[result.relieved] = world.turn ?? 0; chron.saveMeta(meta); }
    if (result.alliance != null) { (meta.alliances ??= {})[result.alliance] = (world.turn ?? 0) + 16; chron.saveMeta(meta); }
    if (result.march) startCampaign(result.march);
    if (yearly) { (meta.decreeAt ??= {})[yearly] = world.turn ?? 0; chron.saveMeta(meta); }
    if (cmd.city != null) { (meta.answeredAt ??= {})[Number(cmd.city)] = world.turn ?? 0; chron.saveMeta(meta); }
    const warmed = world.cities.find((c) => c.id === Number(cmd.city))?.owner ?? (cmd.house != null ? Number(cmd.house) : null);
    result.favour = temper(cmd.action, warmed, result.favour);
    // A ward holds the house for five years.
    if (result.ward != null && stakes) { (stakes.s.wards ??= {})[result.ward] = (world.turn ?? 0) + 20; stakes.save(); }
    // A town taken from a house is remembered, so the Hand can offer it back.
    if (cmd.action === "grant" && cmd.to != null) {
      const town = world.cities.find((c) => c.id === Number(cmd.city));
      if (town && town.owner !== Number(cmd.to)) { (meta.taken ??= {})[town.owner] = { city: town.id, to: Number(cmd.to) }; chron.saveMeta(meta); }
    }
    // Feasting or stripping the house that rose settles what becomes of them.
    const endedU = stakes?.s.usurper.ended;
    if (endedU && !endedU.settled && ["feast", "grant", "ward"].includes(cmd.action) && world.cities.some((c) => c.id === Number(cmd.city) && c.owner === endedU.house)) { endedU.settled = true; stakes.save(); }
    result.lua.forEach((l) => send(`lua cmd ${l}`));
    if (result.work) (meta.works ??= {})[result.work.city] = { building: result.work.building, seasons: WORK_SEASONS, left: WORK_SEASONS, since: Date.now(), paid: result.cost ?? 0 };
    // Spend now, so a second decree before the next snapshot can't overdraw the treasury.
    const crownNow = world.players.find((p) => houseFor(p).crown);
    if (crownNow) crownNow.gold -= result.cost;
    // The result card says what the order cost and whose favour moved, so the
    // King learns the price of his word.
    const effects = shiftAndTell(result.favour, { gift: "a gift of crowns", feast: "a feast in their honour", relief: "grain from the crown", build: "a building paid by the crown", grant: "a town granted or taken", banners: "the King's banners: answered or refused", marriage: "a royal match", peace: "the King's peace", back: "the King took a side", settle: "the King's peace, kept by another house", buyoff: "the King bought off the pretender", ward: "their heir taken as the King's ward", alliance: "an oath to the crown", march: "the royal host" }[cmd.action] ?? "a royal decree", result.cost);
    const seat = world.cities.find((c) => c.owner === crownNow?.id && c.capital);
    const target = world.cities.find((c) => c.id === Number(cmd.city));
    // No journey to where the King already is: an order for his own seat simply takes effect there.
    const away = seat && target && target.id !== seat.id;
    if (away && (cmd.action === "relief" || cmd.action === "gift")) scene(cmd.action === "relief" ? "grain" : "tribute", { x: seat.x, y: seat.y, tx: target.x, ty: target.y, city: target.id });
    // Every decree is seen where it lands: a feast at the seat, a town changing
    // hands, the King's rider carrying the crown's purse for a building.
    // A feast is held at court, as the decree says; the honoured house's colours fly over it.
    if (seat && cmd.action === "feast") scene("feast", { x: seat.x, y: seat.y, city: seat.id, owner: target?.owner ?? crownNow.id });
    if (target && cmd.action === "grant") scene("handover", { x: target.x, y: target.y, city: target.id, from: target.owner, to: Number(cmd.to) });
    if (away && cmd.action === "build") scene("rider", { x: seat.x, y: seat.y, tx: target.x, ty: target.y, city: target.id, label: "The crown's purse for a new building" });
    if (seat && cmd.action === "levy") {
      // The host marches for the town the levy was raised for, else toward the
      // nearest foreign army inside the crown's lands, else down the road a way.
      const foes = world.units.filter((u) => u.owner !== crownNow.id && !["Workers", "Settlers", "Migrants", "Explorer", "Caravan", "Diplomat"].includes(u.type));
      const near = foes.sort((a, b) => Math.hypot(a.x - seat.x, a.y - seat.y) - Math.hypot(b.x - seat.x, b.y - seat.y))[0];
      const goal = target && target.id !== seat.id ? target : near && Math.hypot(near.x - seat.x, near.y - seat.y) < 12 ? near : { x: seat.x + 3, y: seat.y + 2 };
      scene("muster", { x: seat.x, y: seat.y, tx: goal.x, ty: goal.y, city: seat.id });
    }
    // A commanded peace: the two lords' houses keep a truce (no raids, no plots).
    if (result.truce) keepTruce(result.truce);
    // A royal match: the two lords' heirs (or kin) are named, they warm to each
    // other, and a long truce holds their houses from raids and plots.
    if (result.pact && court && pair) {
      const [a, b, ka, kb] = pair;
      {
        ka.spouse = kb.id;
        kb.spouse = ka.id;
        court.save?.(ka);
        court.save?.(kb);
        court.shift(a.id, b.id, 25, `The King bound my house to ${b.house} by marriage.`);
        court.shift(b.id, a.id, 25, `The King bound my house to ${a.house} by marriage.`);
        court.makeTruce(a, b, 24, world);
        court.remember(a.id, `By the King's word, ${ka.name} is to wed ${kb.name} of ${b.house}.`);
        court.remember(b.id, `By the King's word, ${kb.name} is to wed ${ka.name} of ${a.house}.`);
        result.text = `By the King's word, ${ka.name} of ${a.house} will wed ${kb.name} of ${b.house}. The two houses are bound by blood; while the bond holds, neither will raise a hand against the other.`;
        court.saveCourt?.();
      }
    }
    decreeScenes(cmd, result, seat, target);
    record({ turn: world?.turn ?? 0, kind: "decree", text: result.text, city: cmd.city });
    setTimeout(snapshot, 600);
    return json(res, 200, { ok: true, text: crowns(result.text) + (effects ? `\n${effects}` : ""), cost: result.cost ?? 0 });
  },
  // Test hook (films only): stage what a town is making (a building site, a
  // unit in training), so a film is certain to find a site or a drill there.
  "POST /test/stage": async (req, res, url) => {
    if (req.headers["x-test"] !== "1" || !/test|film|check|proof/i.test(String(meta?.name ?? ""))) return json(res, 403, { error: "test reigns only" });
    const b = await body(req);
    // {city, building, kind, progress} stages its work; {city, mood} its mood:
    // riot, feast, hunger, war, peace, prosperity, grief, grasping, calm; {city, mood: "king"} sends the King's banner through it.
    const moods = { riot: { disorder: true }, feast: { celebrating: true }, hunger: { famine: true }, war: { atWar: true }, peace: { atWar: false },
      prosperity: { prosperity: true }, grief: { grief: true }, grasping: { grasping: true },
      calm: { disorder: false, celebrating: false, famine: false, atWar: false, grief: false, grasping: false, prosperity: false } };
    const at = (meta.stage ??= {});
    // {soldiers: wounded|fortified|calm, city}: the crown's three companies nearest the town stand so.
    if (b.soldiers) {
      const c = world.cities.find((x) => x.id === Number(b.city));
      const crownId = Realm.crownOf(world)?.id;
      const near = c ? world.units.filter((u) => u.owner === crownId && !CIVILIAN.has(u.type)).sort((u, v) => Math.hypot(u.x - c.x, u.y - c.y) - Math.hypot(v.x - c.x, v.y - c.y)).slice(0, 3) : [];
      meta.stageUnits ??= {};
      for (const u of near) meta.stageUnits[u.id] = { wounded: { hp: 3 }, fortified: { activity: 4 } }[b.soldiers] ?? {};
      return json(res, 200, { ok: true, units: near.map((u) => u.id) });
    }
    if (b.mood === "king") {
      // {epithet}: the name the King has earned, for this test reign (the Good, the Cruel...).
      if (b.epithet) meta.testEpithet = String(b.epithet).slice(0, 24);
      const c = world.cities.find((x) => x.id === Number(b.city));
      const crownId = Realm.crownOf(world)?.id;
      if (c) scene("rider", { x: c.x - 2, y: c.y, tx: c.x + 2, ty: c.y, city: c.id, owner: crownId, label: "The King's banner" });
      return json(res, 200, { ok: true });
    }
    if (b.mood) at[Number(b.city)] = { ...(at[Number(b.city)] ?? {}), ...moods.calm, ...(moods[b.mood] ?? {}) };
    else at[Number(b.city)] = { ...(at[Number(b.city)] ?? {}), building: String(b.building ?? "Pikemen"), buildingKind: String(b.kind ?? "UnitType"), progress: Number(b.progress ?? 0.5) };
    return json(res, 200, { ok: true });
  },
  // Test hook (films only): a town gains a building now ({city, building}), so the site rising can be filmed.
  "POST /test/grow": async (req, res, url) => {
    if (req.headers["x-test"] !== "1" || !/test|film|check|proof/i.test(String(meta?.name ?? ""))) return json(res, 403, { error: "test reigns only" });
    const b = await body(req);
    const name = String(b.building ?? "Granary").replace(/[^A-Za-z ]/g, "");
    send(`lua cmd local c = find.city(nil, ${Number(b.city)}); local t = find.building_type("${name}"); if c and t and not c:has_building(t) then edit.create_building(c, t) end`);
    return json(res, 200, { ok: true });
  },
  // Test hook (films only): a lord's deed on demand, so its alert can be filmed.
  // Answers only for a reign named as a test, and only with the X-Test header.
  "POST /test/deed": async (req, res, url) => {
    // A proof's deed, test reigns only: {kind: decree|court|deck|arc|realm, key, option, place}, as a ruling or decree would note it.
    if (req.headers["x-test"] !== "1" || !/test|film|check|proof/i.test(String(meta?.name ?? ""))) return json(res, 403, { error: "test reigns only" });
    const b = await body(req);
    const tag = kingDeeds.tagsFor(String(b.kind), String(b.key), b.option === undefined ? undefined : String(b.option));
    if (!tag) return json(res, 400, { error: "no such deed in data/ledger.json" });
    deed(tag, { place: String(b.place ?? ""), act: b.kind !== "realm" });
    return json(res, 200, { ok: true, ledger: meta.ledger, name: kingName() });
  },
  "POST /test/mark": async (req, res, url) => {
    // A film's scar, test reigns only: {kind: battle|sack|razed, x, y, age: seasons ago}.
    if (req.headers["x-test"] !== "1" || !/test|film|check|proof/i.test(String(meta?.name ?? ""))) return json(res, 403, { error: "test reigns only" });
    const b = await body(req);
    if (!["battle", "sack", "razed"].includes(b.kind)) return json(res, 400, { error: "kind: battle, sack or razed" });
    const list = marksNow().filter((m) => !(m.kind === b.kind && m.x === Number(b.x) && m.y === Number(b.y)));
    list.push({ kind: b.kind, x: Number(b.x), y: Number(b.y), turn: Number(world?.turn ?? 0) - Number(b.age ?? 0) });
    fs.writeFileSync(path.join(P.state, "marks.json"), JSON.stringify((marks.list = list)));
    return json(res, 200, { ok: true, marks: marksNow() });
  },
  "POST /test/news": async (req, res, url) => {
    if (req.headers["x-test"] !== "1" || !/test|film|check|proof/i.test(String(meta?.name ?? ""))) return json(res, 403, { error: "test reigns only" });
    const b = await body(req);
    const e = { turn: world?.turn ?? 0, kind: String(b.kind ?? "betrayal"), text: String(b.text ?? "A test of the realm's news."), city: Number(b.city), to: b.to != null ? Number(b.to) : undefined, from: b.from != null ? Number(b.from) : undefined, with: b.with != null ? Number(b.with) : undefined };
    record(e);
    picture(e);
    return json(res, 200, { ok: true });
  },
  "POST /scene/arrived": async (req, res, url) => {
    // The King's grain, gold or word reached the town it was sent to: the realm
    // sees it, the chronicle says so in his name, and the town remembers.
    const b = await body(req);
    const town = world?.cities.find((c) => c.id === Number(b.city));
    const what = { grain: "The King's grain reaches", tribute: "The King's gold reaches", ward: "The ward reaches", rider: "The King's rider reaches" }[String(b.kind)];
    if (!town || !what) return json(res, 400, { error: "nothing arrived" });
    const key = `${b.kind}:${town.id}:${b.sent ?? 0}`;
    if (!arrivals.has(key)) {
      arrivals.add(key);
      record({ turn: world.turn, kind: "crown", city: town.id, text: `${what} ${cityName(town.id)}${b.label ? `: ${String(b.label).slice(0, 80)}` : ""}.` });
    }
    return json(res, 200, { ok: true });
  },
  "* /usage": async (req, res, url) => { return json(res, 200, usageToday()); },
  "GET /mood": async (req, res, url) => { return json(res, 200, court.decrees); },
  "POST /mood/revoke": async (req, res, url) => {
    const { id } = await body(req);
    court.revoke(id);
    return json(res, 200, court.decrees);
  },
  "POST /mood": async (req, res, url) => {
    const { text } = await body(req);
    if (!text || !String(text).trim()) {
      court.setMood(null);
      return json(res, 200, { cleared: true });
    }
    const houses = (world?.players ?? []).map((p) => houseFor(p)).filter((h) => !h.wild && !h.crown).map((h) => h.name);
    const names = court.alive().filter((c) => c.rank === "lord" || c.rank === "bannerman" || c.rank === "heir").map((c) => c.name);
    const mood = (await moodFrom(String(text).slice(0, 300), houses, names)) ?? moodRules(String(text).slice(0, 300), houses, names);
    const touched = court.setMood(mood);
    mood.summary = `${mood.summary} (${touched} ${touched === 1 ? "person" : "people"})`;
    record({ turn: world?.turn ?? 0, kind: "decree", text: `By the King's word: ${mood.summary}` });
    return json(res, 200, mood);
  },
  "GET /court": async (req, res, url) => { return json(res, 200, inCrowns(docket())); },
  "POST /hear": async (req, res, url) => {
    // What the King said into the microphone (a WAV), as words, by Off Grid's Whisper.
    const wav = await bytes(req);
    if (wav.length < 1000) return json(res, 400, { error: "nothing was heard" });
    const text = await transcribe(wav, meta.options?.language);
    return text ? json(res, 200, { text }) : json(res, 503, { error: "Your words were lost. (The local speech model isn't running.)" });
  },
  "POST /voice": async (req, res, url) => {
    // Someone's words, spoken aloud by Off Grid's Kokoro: a voice of their own,
    // in the realm's language. WAV bytes; cached, so a line is only made once.
    const { text, who } = await body(req);
    const line = names.shown(String(text ?? "").trim().slice(0, 600));  // spoken in the player's names
    if (!line) return json(res, 400, { error: "nothing to say" });
    const voice = voiceFor(who ?? {}, meta.options?.language);
    const dir = path.join(P.state, "voices");
    const file = path.join(dir, crypto.createHash("sha1").update(voice + "|" + line).digest("hex") + ".wav");
    if (!fs.existsSync(file)) {
      const wav = await speech(line, voice);
      if (!wav) return json(res, 503, { error: "no voice (the local speech model isn't running)" });
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(file, wav);
    }
    res.writeHead(200, { "content-type": "audio/wav" });
    return res.end(fs.readFileSync(file));
  },
  "POST /interlude/close": async (req, res, url) => {
    if (meta.interlude) meta.interlude.seen = true;
    chron.saveMeta(meta);
    if (meta.court?.sitting == null) hold(false);
    return json(res, 200, { ok: true });
  },
  "POST /court/close": async (req, res, url) => {
    closeCourt(world?.turn ?? 0);
    return json(res, 200, inCrowns(docket()));
  },
  "POST /court/answer": async (req, res, url) => {
    counselStale = true;
    const { id, option } = await body(req);
    const out = rule(id, option);
    closeIfDone(world?.turn ?? 0);
    return json(res, out.error ? 400 : 200, out);
  },
  "POST /court/say": async (req, res, url) => {
    // The King answers a petition in his own words; nothing happens until he confirms it (court.js).
    const [code, out] = await Sittings.say(sittingCtx(), await body(req));
    return json(res, code, out);
  },
  "* /house": async (req, res, url) => {
    // One great house: its numbers over time, its lord, bannermen, wars and allies.
    const pid = Number(url.searchParams.get("id"));
    const p = world?.players.find((x) => x.id === pid);
    if (!p) return json(res, 404, { error: "no such house" });
    const h = houseFor(p);
    const d = detail()?.players[pid];
    const nameOf = (id) => houseFor(world.players.find((x) => x.id === id) ?? {}).name;
    const great = (id) => world.players.some((x) => x.id === id && !houseFor(x).wild);
    const lord = court.lordOfHouse(pid);
    const person = (c) => c && { id: c.id, gender: c.gender, name: c.name, age: c.age, traits: c.traits, goal: c.goals?.[0]?.text, loyalty: c.loyalty, seat: c.seat != null ? cityName(c.seat) : null, role: c.role ? ROLES[c.role]?.title : null, created: !!c.created };
    return json(res, 200, {
      id: pid, name: h.name, words: h.words, seat: h.seat, color: h.color,
      favour: h.wild || h.crown ? null : favourOf(pid),
      history: history.slice(-40).map((r) => ({ turn: r.turn, souls: (r.houses[h.name]?.pop ?? 0) * 600, ...(r.houses[h.name] ?? {}) })).filter((r) => r.towns !== undefined),
      lord: person(lord),
      bannermen: court.alive().filter((c) => c.rank === "bannerman" && c.playerId === pid).map(person),
      // The same truth as the houses table: wars the King has stilled are truces,
      // and a loyal house's engine war with the crown isn't a war.
      ...(() => {
        const me = court.lordOfHouse(pid);
        const stilled = (q) => { const o = court.lordOfHouse(q); return !!(me && o && court.truce(me.id, o.id)); };
        const crownId = world.players.find((x) => houseFor(x).crown)?.id;
        const loyal = (id) => id !== crownId && favourOf(id) >= BANDS.steady;
        const foes = (d?.atWarWith ?? []).filter(great).filter((q) => !((q === crownId && loyal(pid)) || (pid === crownId && loyal(q))));
        return { wars: foes.filter((q) => !stilled(q)).map(nameOf), truces: foes.filter(stilled).map(nameOf) };
      })(),
      allies: (d?.allies ?? []).filter((id) => id !== pid && great(id)).map(nameOf),
    });
  },
  // Aldmere as every new chronicle finds it (the baseline, nine years in): its
  // towns on the map, each with its house, for the Lore's map. Never the reign
  // being played.
  // The player's names for houses and people: GET them, or POST {from, to} to
  // rename one (an empty `to` gives the word its own name back).
  "POST /lore/written/person": async (req, res, url) => {
    // Someone of the starting cast rewritten from the menu's Lore: every chronicle begun after this has them so.
    const b = await body(req);
    const out = rewrites.set(String(b.id ?? ""), b);
    return json(res, out.error ? 400 : 200, out);
  },
  "* /names": async (req, res, url) => {
    if (req.method === "POST") {
      const raw = await new Promise((r) => { let b = ""; req.on("data", (d) => (b += d)); req.on("end", () => { try { r(JSON.parse(b || "{}")); } catch { r({}); } }); });
      const done = names.rename(raw.from, raw.to);
      res.writeHead(done.error ? 400 : 200, { "Content-Type": "application/json" });
      return res.end(JSON.stringify(done));
    }
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ names: names.all() }));
  },
  "* /lore/map": async (req, res, url) => {
    let w = {};
    try { w = JSON.parse(fs.readFileSync(path.join(chron.BASELINE, "state", "world.json"), "utf8")); } catch { /* no baseline */ }
    const players = new Map((w.players ?? []).map((p) => [p.id, p]));
    const towns = (w.cities ?? []).map((c) => {
      const h = players.get(c.owner) ? houseFor(players.get(c.owner)) : null;
      return { title: nameIn(c.id, c.name), x: c.x, y: c.y, size: c.size, capital: !!c.capital, house: h?.name ?? "", key: h?.name ?? "", color: h?.color ?? "#888", sigil: h?.sigil ?? "" };
    });
    let land = [];
    try {
      const m = JSON.parse(fs.readFileSync(path.join(chron.BASELINE, "state", "map.json"), "utf8"));
      land = (m.tiles ?? []).filter((t) => !/Ocean|Lake/.test(String(t[2]))).map((t) => [t[0], t[1]]);
    } catch { /* no map */ }
    if (url.searchParams.get("live") !== "1" || !world?.cities) return json(res, 200, { tiles: [56, 88], towns, land, roads: w.roads ?? [] });
    // The realm as it stands in this reign: each town under whoever holds it now,
    // the hosts in the field (a house's companies within a day's march of each
    // other, as one), and the towns under siege.
    const now = world.cities.map((c) => {
      const h = houseFor(world.players.find((p) => p.id === c.owner) ?? {});
      return { title: cityName(c.id), x: c.x, y: c.y, size: c.size, capital: !!c.capital, house: h?.name ?? "", key: h?.name ?? "", color: h?.color ?? "#888", sigil: h?.sigil ?? "", besieged: Boolean(c.besieged) };
    });
    const hosts = [];
    for (const u of (world.units ?? []).filter((x) => !CIVILIAN.has(x.type) && !/Trireme|Caravel|Galleon|Frigate|Transport/.test(x.type))) {
      if (world.cities.some((c) => c.x === u.x && c.y === u.y)) continue;  // a garrison, not a host
      const near = hosts.find((g) => g.owner === u.owner && Math.max(Math.abs(g.x - u.x), Math.abs(g.y - u.y)) <= 2);
      if (near) { near.x = (near.x * near.companies + u.x) / (near.companies + 1); near.y = (near.y * near.companies + u.y) / (near.companies + 1); near.companies++; }
      else hosts.push({ owner: u.owner, x: u.x, y: u.y, companies: 1 });
    }
    const armies = hosts.filter((g) => g.companies >= 2).map((g) => {
      const h = houseFor(world.players.find((p) => p.id === g.owner) ?? {});
      return { x: g.x, y: g.y, companies: g.companies, house: h?.name ?? "", key: h?.name ?? "", color: h?.color ?? "#888", sigil: h?.sigil ?? "", crown: !!h?.crown };
    });
    return json(res, 200, { tiles: [56, 88], towns: now, land, roads: world.roads ?? w.roads ?? [], armies });
  },
  "* /lore": async (req, res, url) => {
    // The book of the realm: its story from the world bible, and each great
    // house as it stands now, with the people who matter in it.
    const b = bible(path.join(DIR, "..", "WORLD.md"));
    const RANK = { lord: 0, spouse: 1, heir: 2, bannerman: 3, child: 4 };
    // A house born of civil war has no page in the bible; its arms and
    // character come from the lesser houses' lore.
    const rebel = (name) => {
      const f = FAMILIES[name.replace("House ", "")];
      return f ? { region: "Born of civil war", arms: f.arms, character: f.character } : null;
    };
    // As written (the Lore from the menu): the cast as every chronicle begins,
    // read from the baseline realm, never the reign being played.
    const written = url.searchParams.get("as") === "written";
    let cast = null;
    if (written) {
      cast = [];
      const dir = path.join(chron.BASELINE, "characters");
      try { for (const f of fs.readdirSync(dir)) if (f.endsWith(".json")) cast.push(rewrites.apply(JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")))); } catch { /* none */ }
      cast = cast.filter((c) => c.alive !== false);
    }
    let baseCities = [];
    if (written) try { baseCities = JSON.parse(fs.readFileSync(path.join(chron.BASELINE, "state", "world.json"), "utf8")).cities ?? []; } catch { /* none */ }
    const seatName = (id) => {
      if (!written) return cityName(id);
      const c = baseCities.find((x) => x.id === Number(id));
      return c ? nameIn(c.id, c.name) : null;
    };
    const houses = (world?.players ?? []).filter((p) => p.alive !== false && !houseFor(p).wild).map((p) => {
      const h = houseFor(p);
      const seat = world.cities.find((c) => c.owner === p.id && c.capital);
      const people = (written ? cast.filter((c) => c.house === h.name) : court.alive().filter((c) => c.playerId === p.id)).filter((c) => c.rank in RANK)
        .sort((a, c) => RANK[a.rank] - RANK[c.rank] || (c.created ? 1 : 0) - (a.created ? 1 : 0) || c.age - a.age);
      // The lord, the lord's spouse and heir, then the leading bannermen.
      const lord = people.find((c) => c.rank === "lord");
      const family = lord ? people.filter((c) => c.id === lord.spouse || (c.rank === "heir" && c.parents?.includes(lord.id))) : [];
      const notables = [...(lord ? [lord] : []), ...family, ...people.filter((c) => c.rank === "bannerman").slice(0, 4)];
      return {
        id: p.id, name: h.name, key: h.name, words: h.words, color: h.color, sigil: h.sigil, crown: !!h.crown,
        seat: seat ? cityName(seat.id) : null, towns: world.cities.filter((c) => c.owner === p.id).length,
        favour: h.crown ? null : favourOf(p.id), lore: b.houses[h.name] ?? rebel(h.name),
        notables: notables.map((c) => ({
          id: c.id, name: c.name, key: c.name, surname: c.surname ?? null, gender: c.gender, age: c.age, rank: c.rank, traits: c.traits,
          goal: c.goals?.[0]?.text ?? null, role: c.role ? ROLES[c.role]?.title : null,
          seat: c.seat != null ? seatName(c.seat) : null, loyalty: c.loyalty, written,
          memories: [...new Set(c.memories ?? [])].slice(-6), backstory: c.backstory ?? null,
          // In their own words: their latest memory told as theirs, never a
          // story's beat about other people that they heard.
          story: c.backstory ?? [...new Set(c.memories ?? [])].filter((m) => /\b(I|my|me)\b/.test(m) && !/^[^:]{3,60}: /.test(m)).slice(-1)[0] ?? null,
        })),
      };
    }).sort((a, c) => (c.crown ? 1 : 0) - (a.crown ? 1 : 0) || (c.lore ? 1 : 0) - (a.lore ? 1 : 0));
    // A great house that has lost every town is not forgotten: it stays in the
    // book, marked fallen, so the realm's seven are always seven.
    let n = 0;
    for (const h of Object.values(HOUSES)) {
      if (h.wild || h.crown || houses.some((x) => x.name === h.name)) continue;
      houses.push({ id: -100 - n++, name: h.name, key: h.name, words: h.words, color: h.color, sigil: h.sigil, crown: false, fallen: true,
        seat: null, towns: 0, favour: null, lore: b.houses[h.name] ?? null, notables: [] });
    }
    // The lesser families sworn to the great houses: one entry each, with
    // every town a branch of it holds, under which liege, and who heads it.
    const lesser = {};
    // As written, the branches as every chronicle begins (the baseline cast and towns).
    const held = (c) => c.seat != null && (written ? baseCities : world?.cities ?? []).some((t) => t.id === Number(c.seat) && t.owner === c.playerId);
    for (const c of (written ? cast : court.alive()).filter((x) => x.rank === "bannerman" && FAMILIES[x.surname])) {
      const p = world?.players.find((x) => x.id === c.playerId);
      if (!p || p.alive === false) continue;
      const h = houseFor(p);
      const f = (lesser[c.surname] ??= { surname: c.surname, ...FAMILIES[c.surname], branches: [] });
      f.branches.push({
        house: h.name, house_id: p.id, color: h.color, sigil: h.sigil, crown: !!h.crown,
        // A seat lost to another house (or razed) is told as lost, not held.
        seat: held(c) ? seatName(c.seat) : null, lost: c.seat != null && !held(c) ? seatName(c.seat) : null,
        head: { id: c.id, name: c.name, gender: c.gender, age: c.age, loyalty: c.loyalty, traits: c.traits, role: c.role ? ROLES[c.role]?.title : null },
      });
    }
    const families = Object.values(lesser).sort((a, c) => c.branches.length - a.branches.length || a.surname.localeCompare(c.surname));
    return json(res, 200, { intro: b.intro, crown: b.crown, faults: b.faults, fate: b.fate, tone: b.tone, houses, lesser: LESSER, families });
  },
  "* /person": async (req, res, url) => {
    // One person up close, for the character view: who they are and what they remember.
    const c = court.people[url.searchParams.get("id")] ?? court.alive().find((x) => x.name === url.searchParams.get("name"));
    if (!c) return json(res, 404, { error: "no such person" });
    return json(res, 200, {
      id: c.id, name: c.name, gender: c.gender, age: c.age, alive: c.alive, rank: c.rank, house: c.house,
      traits: c.traits, goals: (c.goals ?? []).map((g) => g.text), goal: c.goals?.[0]?.kind ?? null, role_key: c.role ?? null, loyalty: c.loyalty,
      seat: c.seat != null ? cityName(c.seat) : null, role: c.role ? ROLES[c.role]?.title : null,
      memories: [...new Set(c.memories ?? [])].slice(-6), backstory: c.backstory ?? null,
    });
  },
  "* /characters/options": async (req, res, url) => { return json(res, 200, { roles: Object.fromEntries(Object.entries(ROLES).map(([k, v]) => [k, v.title])), goals: GOALS, traits: TRAITS }); },
  "POST /person/fall": async (req, res, url) => {
    // Someone the King walked as fell in a fight: a real death, and their heir inherits.
    const { id, how } = await body(req);
    const c = court.people[String(id)];
    if (!c || !c.alive || !world) return json(res, 400, { error: "no such person" });
    if (how) court.remember(c.id, String(how).slice(0, 200));
    court.die(c, world.turn, world);
    return json(res, 200, { ok: true });
  },
  "POST /person": async (req, res, url) => {
    const spec = await body(req);
    const out = court.edit(String(spec.id), spec, world);
    return json(res, out.error ? 400 : 200, out);
  },
  "POST /characters": async (req, res, url) => {
    if (!world) return json(res, 503, { error: "the realm is still forming" });
    const out = court.create(await body(req), world);
    return json(res, out.error ? 400 : 200, out);
  },
  "* /townsfolk": async (req, res, url) => {
    // The folk of a town, and, asked for one person, their story in full.
    const city = world?.cities.find((c) => c.id === Number(url.searchParams.get("city")));
    if (!city) return json(res, 404, { error: "no such town" });
    const folk = townsfolk(city);
    const i = url.searchParams.get("i");
    if (i === null) return json(res, 200, { town: cityName(city.id), folk });
    const person = folk[Number(i)];
    if (!person) return json(res, 404, { error: "no such person" });
    const file = path.join(P.state, "folk-tales.json");
    const tales = chron.readJson(file) ?? {};
    const key = `v2:${city.id}:${person.i}:${person.name}`;  // v2: tales about the person, not the realm
    if (!tales[key]) {
      const owner = world.players.find((p) => p.id === city.owner);
      // Only what happened in their own town touches a commoner's tale.
      const near = chronicle.filter((e) => e.city === city.id && e.kind !== "tithe").slice(-1).map((e) => e.text);
      const tale = await folkTale(person, cityName(city.id), houseFor(owner).name, near);
      // No local model: their life told plainly, and not kept, so the model can tell it later.
      if (!tale) return json(res, 200, { town: cityName(city.id), person, ...folkPlain(person, cityName(city.id)) });
      tales[key] = tale;
      fs.writeFileSync(file, JSON.stringify(tales, null, 1));
    }
    return json(res, 200, { town: cityName(city.id), person, ...tales[key] });
  },
  "* /town/people": async (req, res, url) => {
    // The named people of a town, for someone walking it: its lord or lady, and
    // the bannermen and heirs seated there.
    // At a house's seat its whole household gathers: the heir and the bannermen too.
    const id = Number(url.searchParams.get("city"));
    const town = world?.cities.find((c) => c.id === id);
    const here = court.alive().filter((c) => ["lord", "heir", "bannerman"].includes(c.rank)
      && (c.seat === id || (town?.capital && c.playerId === town.owner && c.rank !== "lord")));
    return json(res, 200, here.slice(0, 6).map((c) => ({ id: c.id, name: c.name, gender: c.gender, rank: c.rank, house: c.house })));
  },
  "POST /talk": async (req, res, url) => {
    // You speak to someone in the street; they answer in their own voice and remember it.
    const b = await body(req);
    const city = world?.cities.find((c) => c.id === Number(b.city));
    if (!city) return json(res, 404, { error: "no such town" });
    if (b.person) return talkToNamed(res, city, String(b.person), b);
    const person = townsfolk(city)[Number(b.i)];
    // b.greet: they've only just walked up, and the townsperson speaks first.
    const greet = !!b.greet;
    const said = greet ? "(They walk up to you and stop, and say nothing yet: you speak first, as you would to them, by what you know of them and what they have done.)" : String(b.said ?? "").trim().slice(0, 400);
    if (!person || !said) return json(res, 400, { error: "nobody to hear it" });
    const key = `v2:${city.id}:${person.i}:${person.name}`;
    const tales = chron.readJson(path.join(P.state, "folk-tales.json"), {});
    const file = path.join(P.state, "talks.json");
    const talks = chron.readJson(file, {});
    const past = (talks[key] ?? []).slice(-10);
    const owner = world.players.find((p) => p.id === city.owner);
    const speaker = b.you?.id ? court.people[String(b.you.id)] : null;
    const you = isKing(b) ? { ...KING } : {
      name: speaker?.name ?? String(b.you?.name ?? "a stranger"),
      house: speaker?.house ?? String(b.you?.house ?? ""),
      title: speaker ? (speaker.rank === "lord" ? (speaker.gender === "female" ? "Lady" : "Lord") : speaker.rank) : "",
      lord: speaker ? speaker.playerId === city.owner && speaker.rank === "lord" : false,
    };
    // How a commoner names them to their face.
    if (!isKing(b)) you.address = !speaker ? "stranger" : speaker.rank === "lord" || speaker.rank === "heir" ? (speaker.gender === "female" ? "my lady" : "my lord") : speaker.gender === "female" ? "my lady" : "ser";
    const near = chronicle.filter((e) => e.city === city.id || (e.text ?? "").includes(cityName(city.id))).slice(-5).map((e) => e.text);
    const mindId = `folk:${city.id}:${person.i}`;
    const out = await speak(person, cityName(city.id), houseFor(owner).name, you, near, tales[key]?.story ?? "", past, said, meta.options?.language ?? "en", minds.forTalk(mindId, { id: isKing(b) ? "king" : speaker?.id, name: you.name }));
    if (!out) return json(res, 503, { error: `${person.name} only stares at you. (The local model isn't running.)` });
    talks[key] = [...past, ...(greet ? [] : [{ who: you.name, text: said }]), { who: person.name, text: out.reply }].slice(-16);
    fs.writeFileSync(file, JSON.stringify(talks, null, 1));
    if (!greet) minds.talked(mindId, { id: isKing(b) ? "king" : speaker?.id, name: you.name }, said, out.reply);
    // A lord remembers being spoken to by their own people, briefly.
    if (speaker) court.remember(speaker.id, `In ${cityName(city.id)} I spoke with ${person.name}, the ${person.trade}.`);
    return json(res, 200, { name: person.name, trade: person.trade, gender: person.woman ? "female" : "male", ...out });
  },
  "GET /arcs": async (req, res, url) => { return json(res, 200, inCrowns(arcs.view(arcCtx()))); },
  "* /arcs/templates": async (req, res, url) => { return json(res, 200, arcTemplates().map((t) => ({ id: t.id, file: t.file, name: t.name, title: t.title, about: t.about, reign: Boolean(t.reign), own: Boolean(t.own), tags: t.tags ?? [], roles: Object.keys(t.roles ?? {}), beats: (t.beats ?? []).length, problems: t.problems }))); },
  // Fast-forward: n seasons of the realm's stories, against the live realm.
  "POST /arcs/tick": async (req, res, url) => {
    const b = await body(req);
    const ran = await runArcs(Math.max(1, Math.min(60, Number(b.n) || 1)), b.start !== false);
    return json(res, ran ? 200 : 409, ran ? inCrowns(arcs.view(arcCtx())) : { error: "the stories are already moving" });
  },
  // Begin one kind of story now, if the realm has the people for it.
  "POST /arcs/start": async (req, res, url) => {
    const b = await body(req);
    if (arcsRunning) return json(res, 409, { error: "the stories are already moving" });
    arcsRunning = true;
    try {
      const all = arcTemplates().filter((t) => !t.problems.length);
      const arc = await arcs.begin(all, arcCtx(), String(b.template ?? ""));
      arcs.save();
      return arc ? json(res, 200, inCrowns(arcs.view(arcCtx()).active.find((a) => a.id === arc.id))) : json(res, 404, { error: "nobody in the realm fits that story now" });
    } finally {
      arcsRunning = false;
    }
  },
  // The King's own story: an arc file dropped in as JSON, or told in words
  // and shaped by the model from the closest existing arc.
  // A reign story of the player's own: from tags, a few lines of premise, or
  // both. It is built on the tested story that fits best (so every beat holds),
  // carries the player's tags (the dials) and their words, and is named by the
  // local model when it's there, by the tags when it isn't.
  "POST /stories/generate": async (req, res, url) => {
    const b = await body(req);
    const words = String(b.words ?? "").trim().slice(0, 600);
    let tags = (Array.isArray(b.tags) ? b.tags : []).map(String).filter((t) => /^[a-z-]{1,24}$/.test(t)).slice(0, 8);
    if (!words && !tags.length) return json(res, 400, { error: "give it some tags, a few lines, or both" });
    const shapes = arcTemplates().filter((t) => t.reign && !t.problems.length && !t.told);
    if (!shapes.length) return json(res, 503, { error: "no reign stories to build on" });
    // Words with no tags: the words suggest the tags.
    const WORDS = { usurper: /claim|throne|usurp|pretender|crown/, war: /war|feud|battle|siege|raid/, intrigue: /poison|plot|spy|secret|murder|assassin/, "the-dead": /dead|wall|winter|north|undead/, famine: /famine|hunger|starv|grain|harvest/, plague: /plague|fever|sick|pestilence|pox/, money: /debt|bank|gold|coin|loan/, rebellion: /rising|peasant|riot|rebel|revolt|poor/, violent: /blood|slaughter|massacre|burn|kill/, "fast-paced": /sudden|swift|quick|fast/, "slow-burn": /slow|years|generation|creeping/, cunning: /cunning|clever|scheme|deceit|betray/, tragic: /tragic|grief|mourning|loss|doomed/ };
    const asked = tags.length > 0;  // the player chose tags (rather than the words suggesting them)
    if (words && !tags.length) tags = Object.entries(WORDS).filter(([, r]) => r.test(words.toLowerCase())).map(([t]) => t);
    // The tested story that shares most with what was asked.
    const THREATS = /^(usurper|war|intrigue|the-dead|famine|plague|money|rebellion|faith|succession|invasion)$/;
    const score = (t) => (t.tags ?? []).filter((g) => tags.includes(g)).reduce((n, g) => n + (THREATS.test(g) ? 6 : 1), 0) + (words ? (t.about ?? "").toLowerCase().split(/\W+/).filter((w) => w.length > 4 && words.toLowerCase().includes(w)).length : 0);
    let base = shapes.slice().sort((a, b2) => score(b2) - score(a) || Math.random() - 0.5)[0];
    let name = null;
    if (words) {
      const out = await Promise.race([arcFromWords(words, shapes.map((t) => ({ id: t.id, name: t.name, about: t.about }))), new Promise((r) => setTimeout(() => r(null), 20000))]);
      if (out?.shape && !asked) base = shapes.find((t) => t.id === out.shape) ?? base;
      name = out?.name ?? null;
    }
    if (!name) {
      const ADJ = { violent: "Red", gritty: "Grim", cunning: "Silent", "fast-paced": "Swift", tragic: "Bitter", political: "Gilded", mysterious: "Hidden", epic: "Great", aggressive: "Iron", "slow-burn": "Long" };
      const NOUN = { usurper: "Claim", war: "Feud", intrigue: "Cup", "the-dead": "Winter", famine: "Hunger", plague: "Fever", money: "Debt", rebellion: "Rising", faith: "Faith", succession: "Heir", invasion: "Tide" };
      const adj = tags.map((t) => ADJ[t]).find(Boolean) ?? ["Broken", "Last", "Hollow", "Thorned"][Math.floor(Math.random() * 4)];
      const noun = tags.map((t) => NOUN[t]).find(Boolean) ?? (base.kind === "usurper" ? "Claim" : "Reckoning");
      name = `The ${adj} ${noun}`;
    }
    const slug = (x) => String(x).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40);
    const arc = structuredClone(base);
    delete arc.own;
    delete arc.file; delete arc.problems;
    arc.id = `told-${slug(name)}-${Date.now().toString(36).slice(-4)}`;
    arc.name = name;
    arc.title = name;
    arc.about = words || base.about;
    arc.tags = [...new Set([...tags, ...(base.tags ?? []).filter((g) => /^(usurper|war|intrigue|the-dead|famine|plague|money|rebellion|faith|succession|invasion|great-house|the-court|the-people|foreign)$/.test(g))])];
    arc.told = { from: base.id, words, tags };
    const problems = check(arc);
    if (problems.length) return json(res, 400, { error: "that story doesn't hold together", problems });
    fs.writeFileSync(path.join(OWN_STORIES, `${arc.id}.json`), JSON.stringify(arc, null, 2));
    storiesChanged();
    return json(res, 200, { ok: true, id: arc.id, name: arc.name, about: arc.about, tags: arc.tags, from: base.name });
  },
  // A story of the player's own, for the beat form: who is in it (its roles, in
  // words) and the beats they have added so far.
  "GET /stories/own": async (req, res, url) => {
    const t = ownStory(url.searchParams.get("id"));
    if (!t) return json(res, 404, { error: "that isn't a story of your own" });
    return json(res, 200, storyForForm(t));
  },
  // One beat of the player's own, added to (or taken out of) their story: what
  // happens, who is in it, when it happens, and what it does, from short menus.
  // It happens once, when its moment comes, and the story goes on from there.
  // Off Grid AI fills (or carries on) any free-text box: {kind, context, draft}.
  "POST /write": async (req, res, url) => {
    const b = await body(req);
    const text = await Promise.race([writeFor(String(b.kind ?? ""), String(b.context ?? "").slice(0, 1200), String(b.draft ?? "").trim().slice(0, 300)).catch(() => null), new Promise((r) => setTimeout(() => r(null), 45000))]);
    if (!text) return json(res, 503, { error: "Off Grid AI is busy and didn't answer in time. Try again in a moment." });
    return json(res, 200, { text });
  },

  // Off Grid AI writes a story's premise from its tags, or carries on the one begun.
  "POST /stories/premise/idea": async (req, res, url) => {
    const b = await body(req);
    const tags = (Array.isArray(b.tags) ? b.tags : []).map(String).slice(0, 8);
    const draft = String(b.draft ?? "").trim().slice(0, 300);
    const text = await Promise.race([premiseIdea({ tags, draft }).catch(() => null), new Promise((r) => setTimeout(() => r(null), 45000))]);
    if (!text) return json(res, 503, { error: "Off Grid AI is busy and didn't answer in time. Try again in a moment, or write it yourself." });
    return json(res, 200, { text });
  },

  // Off Grid AI writes a beat for the player's own story, or carries on the one begun.
  "POST /stories/beat/idea": async (req, res, url) => {
    const b = await body(req);
    const t = ownStory(b.story);
    if (!t) return json(res, 404, { error: "shape a story of your own first" });
    const roles = rolesOf(t).filter((r) => !r.town);
    const beats = [...(t.beats ?? []), ...(t.asides ?? [])].map((x) => x.text).filter(Boolean);
    const draft = String(b.draft ?? "").trim().slice(0, 300);
    const text = await Promise.race([beatIdea({ name: t.name, about: t.about ?? "", roles, beats, draft }).catch(() => null), new Promise((r) => setTimeout(() => r(null), 45000))]);
    if (!text) return json(res, 503, { error: "Off Grid AI is busy and didn't answer in time. Try again in a moment, or write the beat yourself." });
    return json(res, 200, { text });
  },

  "POST /stories/beat": async (req, res, url) => {
    const b = await body(req);
    const t = ownStory(b.story);
    if (!t) return json(res, 404, { error: "add beats to a story of your own: shape one first" });
    delete t.own; delete t.file; delete t.problems;
    t.asides ??= [];
    if (b.remove) {
      t.asides = t.asides.filter((x) => x.id !== String(b.remove));
    } else {
      const text = String(b.text ?? "").trim().replace(/\s+/g, " ").slice(0, 300);
      if (text.length < 8) return json(res, 400, { error: "say what happens, in a line or two" });
      const people = rolesOf(t).filter((r) => !r.town).map((r) => r.id);
      const who = String(b.who ?? "");
      if (!people.includes(who)) return json(res, 400, { error: "choose who is in it" });
      const when = BEAT_WHEN[b.when];
      if (!when) return json(res, 400, { error: "choose when it happens" });
      const does = BEAT_DOES[b.does ?? "nothing"];
      if (!does) return json(res, 400, { error: "choose what it does" });
      const n = Math.max(0, ...t.asides.map((x) => Number(String(x.id).replace(/\D/g, "")) || 0)) + 1;
      t.asides.push({ id: `yours-${n}`, text, speaker: who, stage: does.stage ?? "rising", when: when.if, do: does.do(who, text), ...(does.court ? { court: does.court(who, text) } : {}), form: { who, when: b.when, does: b.does ?? "nothing" } });
    }
    const problems = check(t);
    if (problems.length) return json(res, 400, { error: "that beat doesn't hold together", problems });
    fs.writeFileSync(path.join(OWN_STORIES, `${t.id}.json`), JSON.stringify(t, null, 2));
    storiesChanged();
    return json(res, 200, storyForForm({ ...t, own: true }));
  },
  "POST /arcs/write": async (req, res, url) => {
    const b = await body(req);
    const dir = path.join(DIR, "arcs");
    const slug = (x) => String(x).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40);
    let arc;
    if (b.arc) {
      arc = typeof b.arc === "string" ? JSON.parse(b.arc) : b.arc;
    } else {
      const words = String(b.words ?? "").trim().slice(0, 600);
      if (!words) return json(res, 400, { error: "say what the story is" });
      const shapes = arcTemplates().filter((t) => !t.problems.length && !t.told);
      const given = shapes.filter((t) => t.id === b.shape);
      const out = await arcFromWords(words, (given.length ? given : shapes).map((t) => ({ id: t.id, name: t.name, about: t.about })));
      const base = given[0] ?? shapes.find((t) => t.id === out?.shape);
      if (!base) return json(res, 503, { error: "the local model isn't there to shape it; drop an arc file in bridge/arcs instead" });
      const name = out?.name || words.split(/[.,;]/)[0].slice(0, 40);
      arc = structuredClone(base);
      delete arc.file; delete arc.problems;
      arc.id = `told-${slug(name)}`;
      arc.name = name;
      arc.about = words;
      arc.told = { from: base.id, words };
      const anchor = Object.keys(base.roles)[0];
      arc.title = /^the /i.test(name) ? `${name} of {${anchor}.seat}` : `The ${name} of {${anchor}.seat}`;
    }
    const problems = check(arc);
    if (problems.length) return json(res, 400, { error: "that arc doesn't hold together", problems });
    const file = path.join(dir, `${slug(arc.id)}.json`);
    fs.writeFileSync(file, JSON.stringify(arc, null, 2));
    storiesChanged();
    return json(res, 200, { ok: true, file: path.relative(DIR, file), arc });
  },
  "* /lord": async (req, res, url) => { return json(res, 200, court.summary(Number(url.searchParams.get("city"))) ?? {}); },
  "POST /season": async (req, res, url) => {
    await runSeason();
    return json(res, 200, { ok: true });
  },
  "POST /tithe": async (req, res, url) => {
    const { rate } = await body(req);
    meta.tithe = Math.max(0, Math.min(0.4, Number(rate) || 0));
    chron.saveMeta(meta);
    return json(res, 200, { tithe: meta.tithe });
  },
  "POST /god": async (req, res, url) => {
    const cmd = await body(req);
    const result = godCommand(cmd, world);
    if (result.error) return json(res, 400, result);
    result.lua.forEach((l) => send(`lua cmd ${l}`));
    record({ turn: world?.turn ?? 0, kind: "god", text: result.text, city: cmd.city });
    setTimeout(snapshot, 600);
    return json(res, 200, { ok: true, text: crowns(result.text) });
  },
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
