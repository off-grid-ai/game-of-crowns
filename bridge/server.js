// Bridge between the Freeciv server (the simulation) and the Godot view.
// - Runs one Freeciv server for the active chronicle (see chronicles.js),
//   resuming from that chronicle's newest save; can switch chronicles live.
// - Turns Freeciv's EVENT lines into the chronicle, keeps a per-turn ledger,
//   times and scores reigns.
// - Exposes a small HTTP API on 127.0.0.1:8787 for the view.

import { spawn, execFileSync } from "node:child_process";
import fs from "node:fs";
import zlib from "node:zlib";
import net from "node:net";
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
import { folkTale, folkPlain, moodRules, speak, ruleFrom, reactTo, speech, voiceFor, transcribe, aiStatus } from "./claude.js";
import { BUILD_COST, granarySize } from "./rules.js";
import * as chron from "./chronicles.js";
import * as names from "./names.js";
import * as rewrites from "./written.js";
import { decree, titheLua, clampFavour, DECREES, bannersReady } from "./crown.js";
// Lords whose first names were borrowed from A Song of Ice and Fire, renamed
// in realm.serv; realms begun before then still carry the old names in their
// saved game, so they are shown by the new ones.
// Stories the player generates or writes, kept with their realms.
const OWN_STORIES = path.join(chron.HOME, "stories");
ownStories(OWN_STORIES);
const RENAMED = {
  "Lady Olenna Thornvale": "Lady Isolde Thornvale",
  "Lord Robb Stormhold": "Lord Rhys Stormhold",
  "Princess Arianne Sunspire": "Princess Ximena Sunspire",
  "Lord Jon Highfell": "Lord Declan Highfell",
};
import { Court } from "./characters.js";
import { Minds, route as mindsRoute } from "./minds.js";
import { Arcs, templates as arcTemplates, check, ownStories, storiesChanged } from "./arcs.js";
import { Chatter } from "./chatter.js";
import { bible, FAMILIES, LESSER } from "./lore.js";
import { Stakes, calendar } from "./stakes.js";
import * as kingDeeds from "./ledger.js";
import * as Realm from "./realm.js";
import { BANDS } from "./favour.js";
import { watched, usageToday, moodFrom, isWatched, arcFromWords, beatIdea, premiseIdea, writeFor } from "./claude.js";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 8787);
const FC_PORT = Number(process.env.FC_PORT || 5556);

// --- the active chronicle ----------------------------------------------------

let meta = null; // chronicles.js meta for the running realm
let P = null; // its paths
let fc = null; // the Freeciv process
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

// The game asks every second; a reign keeps hundreds of saves. Each file's time is
// read once, and the folder is only listed again when Freeciv has written to it.
const savesSeen = { dir: null, mtime: 0, list: [] };
// A ceasefire between two houses in Freeciv itself. Its Lua and its server
// commands can't change diplomacy, but its save holds it: save, set both
// players' diplstate rows to "Cease-fire" with `turns` left, and resume from
// that save. Freeciv then keeps it and ends it by itself.
// pairs: [[houseA, houseB, seasons], ...], all written in one reload.
async function ceasefire(pairs) {
  if (!fc || switching || !pairs.length) return false;
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
    const probe = () => {
      const c = net.connect(FC_PORT, "127.0.0.1", () => { c.destroy(); console.log(`ceasefire reload: ${Date.now() - t0} ms`); });
      c.on("error", () => (Date.now() - t0 < 120000 ? setTimeout(probe, 100) : console.log("ceasefire reload: no answer in 120 s")));
    };
    probe();
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

function newestSave(kind = "") {
  const mtime = fs.statSync(P.saves).mtimeMs;
  if (savesSeen.dir !== P.saves || savesSeen.mtime !== mtime) {
    savesSeen.list = fs.readdirSync(P.saves).filter((f) => f.startsWith("realm") && f.includes(".sav"))
      .map((f) => ({ f, t: fs.statSync(path.join(P.saves, f)).mtimeMs })).sort((a, b) => b.t - a.t);
    savesSeen.dir = P.saves;
    savesSeen.mtime = mtime;
  }
  // An autosave, or the King's truce save written in its place (the newer of
  // the two is the realm as Freeciv now holds it, wars and all).
  const hit = savesSeen.list.find((x) => x.f.includes(kind) || (kind === "auto" && x.f.includes("ceasefire")));
  return hit ? path.join(P.saves, hit.f) : null;
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

// --- Freeciv process ---------------------------------------------------------

function send(line) {
  if (fc && !fc.killed) fc.stdin.write(line + "\n");
}

function startFreeciv() {
  // A Freeciv left behind by an earlier bridge (restarts kill Node, not its
  // child) would hold the port and stop this one starting: clear it first.
  // It may be busy saving and ignore a polite request, so it's killed outright.
  try {
    execFileSync("pkill", ["-KILL", "-f", `freeciv-server -p ${FC_PORT} `]);
  } catch { /* none running */ }
  const save = newestSave();
  const resume = path.join(P.base, "resume.serv");
  fs.writeFileSync(resume, `lua file ${path.join(DIR, "lua", "events.lua")}\nstart\n`);
  const args = ["-p", String(FC_PORT), "-s", P.saves, "-d", "n", "-b", "127.0.0.1"];
  if (save) args.push("-f", save, "-r", resume);
  else args.push("-r", P.serv);
  console.log(`${meta.name}: ${save ? `resuming from ${path.basename(save)}` : "creating a new realm"}`);
  // This realm's temperaments, then our medieval ruleset, then Freeciv's own data.
  // The app brings its own Freeciv (bridge/app.js sets FREECIV_SERVER and FREECIV_SHARE).
  const share = process.env.FREECIV_SHARE || "/opt/homebrew/share/freeciv";
  const env = { ...process.env, FREECIV_DATA_PATH: `${P.data}:${path.join(DIR, "data")}:${share}` };
  const proc = spawn(process.env.FREECIV_SERVER || "freeciv-server", args, { cwd: DIR, env });
  fc = proc;
  const log = fs.createWriteStream(path.join(P.state, "freeciv.log"), { flags: "a" });
  let pending = "";
  const onLine = (line) => (line.includes("EVENT {") ? onEvent(line) : log.write(line + "\n"));
  proc.stdout.on("data", (d) => {
    pending += d;
    const lines = pending.split("\n");
    pending = lines.pop();
    lines.forEach(onLine);
  });
  proc.stderr.on("data", (d) => String(d).split("\n").forEach(onLine));
  proc.on("exit", (code) => {
    console.log(`freeciv-server exited (${code})`);
    log.end();
    if (fc === proc) {
      fc = null;
      // An unexpected exit takes the bridge down so launchd restarts it cleanly.
      if (!switching) process.exit(code ?? 1);
    }
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

function stopFreeciv() {
  return new Promise((resolve) => {
    if (!fc) return resolve();
    const proc = fc;
    proc.once("exit", () => resolve());
    send("save");
    setTimeout(() => send("quit"), 800);
    setTimeout(() => proc.kill("SIGKILL"), 6000);
  });
}

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

// The realm as the view sees it (GET /world): the bridge's world with each
// house, town and unit filled in from the save, the crown, the threat and the
// rest. counsel() reads the same, once a season and after the King acts
// (refreshCounsel), never on every poll.
function worldView() {
  const d = detail();
  const players = world.players.map((p) => ({ ...p, name: RENAMED[p.name] ?? p.name, house: houseFor(p), atWarWith: d?.players[p.id]?.atWarWith ?? [] }));
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
    return x ? { ...u, hp: x.hp, activity: x.activity, goto: x.goto, home: x.home } : u;
  });
  const last = history[history.length - 1];
  const crownP = players.find((p) => p.house.crown);
  const crown = { treasury: crownP?.gold ?? 0, tithe: meta.tithe, decrees: Object.fromEntries(Object.entries(DECREES).map(([k, v]) => [k, { ...v, cost: priceOf(k), wait: seasonsLeft(k === "feast" ? "feast:court" : k) }])), favourWait: Object.fromEntries(world.players.map((p) => [p.id, seasonsLeft(`favour:${p.id}`)]).filter(([, n]) => n > 0)), perSeason: lastSeason.net };
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
    p.band = p.favour == null ? null : p.favour >= GOAL_FAVOUR ? "firm" : p.favour >= 35 ? "wavering" : "cold";
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
  const northTown = (world?.cities ?? []).filter((c) => c.y < 30).sort((a, b) => a.y - b.y)[0];
  const dead = { town: northTown ? cityName(northTown.id) : null, owner: northTown?.owner ?? null,
    last: (3 + (nn.waves ?? 0) * 2) * 200, next: (3 + ((nn.waves ?? 0) + 1) * 2) * 200, in: nn.nextAt ? Math.max(0, nn.nextAt - (world?.turn ?? 0)) : null };
  const threat = { usurper, north: (stakes?.s.north.waves ?? 0), dead, pretender: u?.house ?? null, since: u?.since ?? 0, turn: world?.turn ?? 0,
    // The King's side is his whole host: the garrisons defend Kingsmere too.
    ended: u?.ended && !u.ended.settled && (world?.turn ?? 0) - u.ended.turn <= 8 ? u.ended.house : null,
    theirs: u?.house != null ? fighting(u.house) : 0, ours: crownId != null ? (world?.units ?? []).filter((x) => x.owner === crownId && !CIVILIAN.has(x.type)).length : 0 };
return { ...world, players, cities, units, turnSeconds, crownId: crownOf()?.id ?? null, seatId: crownSeat()?.id ?? null, reign: reignInfo(), story: storyNow(), date: calendar(world.turn), threat, counsel: counselNow, sitting: meta.court?.sitting ?? null, fallen: Object.values(HOUSES).filter((h) => !h.crown && !h.wild && !world.players.some((p) => houseFor(p).key === h.key && (world.cities.some((c) => c.owner === p.id) || (world.units ?? []).some((u) => u.owner === p.id)))).map((h) => ({ ...h, name: names.shown(h.name) })), effects: effects.slice(-10), peace: last?.peace ?? 1, prosperity: last?.pop ?? 0, souls: world.cities.reduce((t, c) => t + soulsOf(c.size), 0), crown, owners: d?.owners ?? [], scenes: scenes.filter((x) => Date.now() - x.at < 90000), marks: marksNow(), goal: goalNow() };
}

// The Hand's matters, read from the realm as it stands now.
let counselStale = true;  // the King acted since the last reading: read the realm again
function refreshCounsel() {
  if (!world) return;
  counselStale = false;
  const v = worldView();
  counselNow = counsel(v.players, v.cities, v.threat);
}

// The realm's states, one definition each (SSOT, Mac 2026-11-10): set on each
// town in the bridge's world from Freeciv's own fields, at load, each reckoning
// and on every /world. The court, the deck, the arcs, counsel, the minds and
// the view all read these fields; none works them out again.
const PLAGUE_SEASONS = 4;  // a town is still sick this many seasons after plague strikes
function townStates() {
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
    // A test reign's staged mood (/test/stage), so the court sees what the film shows.
    const st = meta?.stage?.[c.id];
    if (st) for (const k of ["famine", "celebrating", "disorder"]) if (k in st) c[k] = st[k];
    // The town's mood, one word everyone reads: a riot outweighs hunger, hunger a feast.
    c.mood = c.disorder ? "riot" : c.famine ? "hunger" : c.celebrating ? "feast" : "";
  }
}

// A town falling into disorder is news: told once as it starts, so the minds
// and the townsfolk's talk hear of it (the state itself is townStates').
let inUproar = null;  // town ids in disorder at the last reckoning
function uproar() {
  const now = new Set((world?.cities ?? []).filter((c) => c.disorder).map((c) => c.id));
  if (inUproar) for (const id of now) if (!inUproar.has(id)) {
    const c = world.cities.find((x) => x.id === id);
    const h = houseFor(world.players.find((p) => p.id === c.owner) ?? {});
    record({ turn: world.turn, kind: "unrest", text: `${cityName(id)} is in uproar: the people take to the streets against ${h.crown ? "the crown" : h.name}.`, city: id });
  }
  inUproar = now;
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

// A ruling on a petition, by option: the treasury pays, the realm changes,
// favour shifts, the chronicle and the world show it. Shared by a chosen
// option and a ruling in the King's own words.
function rule(id, option) {
  const asked = court.petitions.find((x) => x.id === id && !x.answered)?.options?.find((o) => o.id === option);
  const purse = world.players.find((p) => houseFor(p).crown)?.gold ?? 0;
  if (asked?.cost && purse < asked.cost) return { error: crowns(`the treasury holds ${purse} gold`) };
  const petition = court.petitions.find((x) => x.id === id);
  if (petition?.arc === "siege" && !(meta.campaigns ?? []).some((k) => `siege-${k.city}-${k.turn}` === petition.beat)) {
    petition.answered = true;
    return { error: "The siege is already over; the herald's terms no longer stand." };
  }
  const out = court.answer(id, option, world);
  if (out.error) return out;
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
  }
  out.lua.forEach((l) => send(`lua cmd ${l}`));
  const effects = shiftAndTell(out.favour, "your ruling at court", out.cost);
  // Every ruling is told, even one whose answer has no words of its own written for it.
  if (!String(out.text ?? "").trim()) out.text = `The King gives his answer${petition ? ` to ${petition.name}` : ""}: ${String(asked?.label ?? option).replace(/ \(.*\)$/, "").toLowerCase()}.`;
  record({ turn: world.turn, kind: "decree", text: out.text });
  rulingScene(id, option, out);
  return { ok: true, text: crowns(out.text) + (effects ? `\n${effects}` : "") };
}

// A town is besieged while an enemy host stands at its walls: three or more
// fighting units of another house on the tiles around it. One scene per turn.
const CIVILIAN = new Set(["Settlers", "Workers", "Migrants", "Engineers", "Explorer", "Caravan", "Freight", "Diplomat", "Spy", "Leader"]);
// The fighting companies of other houses on the tiles around a town: three or
// more is a siege (the one rule, read by sieges() and townStates()).
function besiegers(c) {
  return (world?.units ?? []).filter((u) => u.owner !== c.owner && !CIVILIAN.has(u.type) && Math.max(Math.abs(u.x - c.x), Math.abs(u.y - c.y)) === 1);
}

function sieges() {
  if (!world?.units || !world?.cities) return;
  for (const c of world.cities) {
    const near = besiegers(c);
    if (near.length < 3) continue;
    const counts = {};
    for (const u of near) counts[u.owner] = (counts[u.owner] ?? 0) + 1;
    const owner = Number(Object.entries(counts).sort((a, b) => b[1] - a[1])[0][0]);
    if (scenes.some((x) => x.kind === "siege" && x.city === c.id && x.turn === world.turn)) continue;
    const engines = near.filter((u) => /Catapult|Trebuchet|Cannon|Artillery/.test(u.type)).length;
    scene("siege", { x: c.x, y: c.y, city: c.id, owner, defender: c.owner, size: near.length, engines, ax: near[0].x, ay: near[0].y });
    const first = !scenes.some((x) => x.kind === "siege" && x.city === c.id && x.turn === world.turn - 1);
    if (first) record({ turn: world.turn, kind: "battle", text: `${houseFor(world.players.find((p) => p.id === owner)).name} lays siege to ${cityName(c.id)} with ${near.length} companies.`, city: c.id });
  }
}

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

// A ruling at court made visible: what the King gives goes out from
// Kingsmere by wagon, a ward comes to Kingsmere, and any other word is
// carried by a royal rider to the petitioner's seat.
function rulingScene(id, option, out) {
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

// The King's ledger (ledger.js): each deed he does goes in, and when it changes
// the name the realm gives him, the ticker says which deed tipped it.
function kingName(outcome = null) {
  const realm = history.length ? { peace: history.reduce((t, r) => t + r.peace, 0) / history.length, grew: history[history.length - 1].pop / Math.max(1, history[0].pop) } : {};
  return kingDeeds.epithetOf(meta, outcome, realm, (pid) => { const p = world?.players?.find((x) => x.id === Number(pid)); return p ? houseFor(p).name : null; });
}
function deed(tag, opts = {}) {
  if (!meta || (!tag && opts.act === false)) return;
  const turn = world?.turn ?? 0;
  const before = meta.ledger?.name ?? null;
  kingDeeds.note(meta, tag, { turn, ...opts });
  const now = kingName().name;
  meta.ledger.name = now;
  chron.saveMeta(meta);
  const axis = kingDeeds.axisOf(now);
  // The deed that tipped it: the weightiest on the name's side, or (for a name of two sides) this one.
  const said = tag?.says ? String(tag.says).replace("{town}", opts.place || "a town").replace("{house}", opts.place || "a house") : null;
  const why = (axis && kingDeeds.tipping(meta, ...axis)) || said;
  if (before && now !== before && why) record({ turn, kind: "name", text: `After ${why}, people call you ${now}.` });
}

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
    await court.season(world, { favour: favourOf, cause: causeOf, warded: (pid) => (stakes?.s.wards?.[pid] ?? -1) > (world?.turn ?? 0) || sworn(pid), send: (l) => send(`lua cmd ${l}`), shift: shiftFavour, watched: isWatched(), options: meta.options ?? {}, ...heardCtx(), mayRise, rose });
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

function saveFavour() {
  fs.writeFileSync(path.join(P.state, "favour.json"), JSON.stringify(favour));
  fs.writeFileSync(path.join(P.state, "favour-why.json"), JSON.stringify(favourWhy));
  fs.writeFileSync(path.join(P.state, "deeds.json"), JSON.stringify(deeds));
  fs.writeFileSync(path.join(P.state, "favour-past.json"), JSON.stringify({ byTurn: favourPast, net: lastSeason.net }));
}

function favourOf(id) {
  return favour[id] ?? 60;
}

// The Hand of the King advises: the two or three most pressing matters in the
// realm, worst first, each with why it matters in one line and the decrees that
// answer it, so a new King always knows what to do next and learns by doing it.
function counsel(players, cities, threat) {
  const out = [];
  const great = players.filter((p) => !p.house.wild && !p.house.crown && p.cities?.length !== 0);
  const seatOf = (pid) => cities.find((c) => c.owner === pid && c.capital) ?? cities.find((c) => c.owner === pid);
  const purse = players.find((p) => p.house.crown)?.gold ?? 0;
  // A war or bond the King has stilled (his peace, or a royal match).
  const stilled = (x, y) => { const a = court?.lordOfHouse(x), b = court?.lordOfHouse(y); return !!(a && b && court.truce(a.id, b.id)); };
  // A house sliding toward rebellion.
  // Cold is below the banners' line (35): a house that would still answer isn't the Hand's worry.
  const cold = great.filter((p) => favourOf(p.id) < BANDS.steady).sort((a, b) => favourOf(a.id) - favourOf(b.id))[0];
  if (cold && seatOf(cold.id)) {
    const f = favourOf(cold.id);
    // The Hand names what is cooling them most, from the house's ledger of causes.
    const drain = (favourWhy[cold.id] ?? []).filter((r) => r.d < 0).sort((a, b) => a.d - b.d)[0];
    const cause = drain ? ` What cools them most: ${drain.why} (${Math.round(drain.d)}).` : "";
    // A royal match binds the cold house to the most loyal one: both warm, and a long truce holds.
    const friend = great.filter((p) => p.id !== cold.id && !stilled(cold.id, p.id)).sort((a, b) => favourOf(b.id) - favourOf(a.id))[0];
    const match = friend && matchFor(cold.id, friend.id) ? [{ label: `Wed them to ${friend.house.name.replace(/^House /, "")}`, action: "marriage", city: seatOf(cold.id).id, to: friend.id }] : [];
    // A taken town is answered by giving it back, if the other house still holds it.
    const took = meta.taken?.[cold.id];
    const back = drain?.why === "a town granted or taken" && took && cities.some((c) => c.id === took.city && c.owner === took.to)
      ? [{ label: `Return ${cityName(took.city)} to them`, action: "grant", city: took.city, to: cold.id }] : [];
    const lighter = drain?.why === "the royal tithe" && meta.tithe > 0 ? [{ label: `Lower the tithe to ${Math.round(meta.tithe * 100) - 5}%`, ui: "tithe_down" }] : [];
    // The two rules, plainly: under 25 the lord may rise any season; two houses
    // under 25 and one of them claims the throne.
    const angryNow = great.filter((p) => favourOf(p.id) < BANDS.cooling).length;
    const rule = f < BANDS.cooling
      ? `Under 25, their lord may raise his banners any season, likelier the colder he grows.${angryNow >= 2 ? "" : " One more house under 25 and a pretender will claim the throne."}`
      : "Under 25, a lord may raise his banners against you; two such houses and one claims the throne.";
    out.push({ urgency: f < BANDS.cooling ? 100 : 70, text: `${cold.house.name} grows cold to the crown: favour ${f}`,
      why: rule + cause,
      acts: [...back, ...lighter, { label: "Gift crowns", action: "gift", city: seatOf(cold.id).id }, { label: "A feast in their honour", action: "feast", city: seatOf(cold.id).id }, ...match] });
  }
  // The usurper by name, how long until they march, and how to stop it: the
  // whispers fade once the angry houses (under 25) are won back.
  const pretender = players.find((p) => p.id === threat.pretender);
  const claimant = pretender ? pretender.house.name : "A pretender";
  if (threat.usurper === "rumour") {
    const left = Math.max(1, 8 - (threat.turn - threat.since));
    const angry = great.filter((p) => favourOf(p.id) < BANDS.cooling).map((p) => p.house.name.replace(/^House /, ""));
    out.push({ urgency: 95, occur: threat.since, text: `${claimant} whispers of a better claim to the throne`,
      why: `In ${left} season${left === 1 ? "" : "s"} they march on Kingsmere, unless the angry houses are won back above 25: ${angry.join(", ") || "none now"}.`,
      acts: [pretender && seatOf(pretender.id) ? { label: `Gift crowns to ${claimant.replace(/^House /, "")}`, action: "gift", city: seatOf(pretender.id).id } : null, { label: "Buy off their claim", action: "buyoff" }, { label: "Call the banners", action: "banners" }].filter(Boolean) });
  } else if (threat.usurper !== "none") out.push({ urgency: 100, occur: threat.since, text: `${claimant}'s host marches on Kingsmere`,
    why: `${(threat.theirs * 200).toLocaleString("en-US")} of their men about the walls against ${(threat.ours * 200).toLocaleString("en-US")} of yours: ${threat.theirs > threat.ours ? "as things stand, the walls would fall" : "for now, the walls would hold"}. If Kingsmere falls, the crown is lost. Loyal houses (favour 35 and up) send men to the banners; the royal levy is yours to pay for. Or buy them off: gold for their claim.`, acts: [{ label: "Call the banners", action: "banners" }, { label: "Raise the royal levy", action: "levy" }, { label: "Buy them off", action: "buyoff" }] });
  // After a march: the King decides what becomes of the house that rose.
  const rose = players.find((p) => p.id === threat.ended);
  if (rose) {
    const towns = cities.filter((c) => c.owner === rose.id && !c.capital).sort((a, b) => (a.size ?? 0) - (b.size ?? 0));
    const loyal = great.filter((p) => p.id !== rose.id).sort((a, b) => favourOf(b.id) - favourOf(a.id))[0];
    const name = rose.house.name.replace(/^House /, "");
    out.push({ urgency: 90, occur: threat.since, text: `The march is over. What of House ${name}?`,
      why: `They rose against the throne and went home (favour ${Math.round(favourOf(rose.id))}). Pardon them with a feast to win them back, hold their heir at court so they cannot rise, or take a town and give it to ${loyal ? loyal.house.name : "a loyal house"} so the realm sees the price of treason; a house driven below 25 may rise again.`,
      acts: [seatOf(rose.id) ? { label: "Pardon them with a feast", action: "feast", city: seatOf(rose.id).id } : null,
        seatOf(rose.id) ? { label: `Take their heir as your ward (${name} −5; they cannot rise for five years)`, action: "ward", city: seatOf(rose.id).id } : null,
        towns[0] && loyal ? { label: `Give ${towns[0].title ?? "a town"} to ${loyal.house.name.replace(/^House /, "")} (${name} −30, ${loyal.house.name.replace(/^House /, "")} +20)`, action: "grant", city: towns[0].id, to: loyal.id } : null].filter(Boolean) });
  }
  // A house that has turned: its lord's ultimatum, before any banners are raised.
  for (const p of great) {
    const t = meta.turning?.[p.id];
    if (t?.state !== "sent" || !seatOf(p.id)) continue;
    const lord = court?.lordOfHouse(p.id);
    const short = p.house.name.replace(/^House /, "");
    // The grievance is something the King did, by name and season ("You marched the
    // royal host on our walls, in the autumn of 309"); without one, the plain truth.
    const worst = (deeds[p.id] ?? []).filter((x) => x.d <= -8).sort((a, b) => a.d - b.d)[0];
    const when = worst ? calendar(worst.turn) : null;
    const grievance = worst ? `You ${worst.what}, in the ${when.season} of ${when.year}. Set that right` : `The crown has done nothing for ${short} since you were crowned. Set that right`;
    out.push({ urgency: 100, kind: "ultimatum", occur: t.at, text: `${p.house.name} sends the crown an ultimatum`,
      why: `${lord ? lord.name : `The lord of ${short}`}: "${grievance}, or ${short} raises its banners." Answer with a favour they can see; silence is a refusal.`,
      acts: [{ label: "A feast in their honour", action: "feast", city: seatOf(p.id).id }, { label: "Gift crowns", action: "gift", city: seatOf(p.id).id },
        { label: `Take their heir as your ward (they cannot rise for five years)`, action: "ward", city: seatOf(p.id).id }] });
    for (let i = out.length - 2; i >= 0; i--) if (out[i].text.startsWith(`${p.house.name} grows cold`)) out.splice(i, 1);
  }
  // The pretender's own coldness is the usurper's story: one matter, not two.
  for (const who of [threat.usurper !== "none" ? pretender : null, rose].filter(Boolean)) {
    const i = out.findIndex((o) => o.text.startsWith(`${who.house.name} grows cold`));
    if (i >= 0) out.splice(i, 1);
  }
  // (Lowering the tithe sits on the cold house's matter when the tithe is its top cause.)
  // What the banners would bring today: two companies from the loyal (60+), one from the willing (35+).
  const bannerMen = !bannersReady(world?.turn ?? 0) ? 0 : great.reduce((n, p) => { const f = favourOf(p.id); const sh = f >= BANDS.loyal ? 0.25 : f >= BANDS.steady ? 0.125 : 0; return n + (sh ? Math.max(1, Math.round((p.units ?? 0) * sh)) : 0); }, 0) * 200;
  if (threat.north > 0) {
    const d = threat.dead ?? {};
    const gap = (d.next ?? 0) - threat.ours * 200 - bannerMen;
    const lord = players.find((p) => p.id === d.owner);
    const where = d.town ? `on ${d.town}${lord ? ` (${lord.house.crown ? "the crown's own" : lord.house.name})` : ""}` : "on the North";
    const when = d.in == null ? "" : d.in <= 1 ? " The next host comes next season." : ` The next host comes in ${d.in} seasons.`;
    // Once the King's own men outnumber the host, the Hand says so and advises
    // nothing more; if only the banners are needed, he advises only the banners.
    if ((d.next ?? 0) - threat.ours * 200 <= 0) d.hold = true;
    const onlyBanners = !d.hold && gap <= 0;
    out.push({ urgency: d.hold ? 40 : 75, occur: (world?.turn ?? 0) + (d.in ?? 0), text: d.hold ? "The dead come south, and you would hold" : "The dead come south",
      why: `${(d.last ?? 0).toLocaleString("en-US")} of them fell ${where} last time; ${(d.next ?? 0).toLocaleString("en-US")} will come with the next.${when} Against them: your ${(threat.ours * 200).toLocaleString("en-US")} fighting men${bannerMen ? `, and about ${bannerMen.toLocaleString("en-US")} more if you call the banners` : " (the banners are already called this year)"}: ${d.hold ? "your own men would hold" : gap <= 0 ? "with the banners, you would hold" : gap <= 1600 ? `you would lose by ${gap.toLocaleString("en-US")}: a levy (600) and sellswords (1,000) close it` : `you would lose by ${gap.toLocaleString("en-US")}, even with a levy and sellswords`}. If every northern town falls, the realm falls with it.`,
      acts: [{ label: "Call the banners", action: "banners" }, { label: "Raise the royal levy", action: "levy" }, { label: "Hire sellswords", action: "sellswords" }].filter((a) => !d.hold && (!onlyBanners || a.action === "banners")) });
  }
  // A town the King has fed this year isn't brought to him again while the grain lasts.
  const hungry = cities.find((c) => c.famine && !((meta.relieved?.[c.id] ?? -99) > (world?.turn ?? 0) - 4));
  if (hungry) out.push({ urgency: 80, occur: calendar(world?.turn ?? 0).year, text: `${hungry.title} is starving`, why: "A hungry town shrinks, riots, and blames its King.", acts: [{ label: "Send grain", action: "relief", city: hungry.id }] });
  // (Petitioners are the court's own: the Hand's matters stand beside them there.)
  // A war the King has stilled (his peace, or a royal match) is no longer the
  // Hand's worry, though the engine still counts the two houses at war.
  const war = great.find((p) => (p.atWarWith ?? []).some((o) => great.some((g) => g.id === o) && !stilled(p.id, o)));
  if (war) {
    const foe = great.find((g) => war.atWarWith.includes(g.id) && !stilled(war.id, g.id));
    // The Hand never offers an order he knows will be refused: a house too cold
    // to obey (under 40) is to be won first, and he says so.
    const cold = [war, foe].filter((p) => favourOf(p.id) < 40).sort((a, b) => favourOf(a.id) - favourOf(b.id))[0];
    // The King's answers to a war: stop it (by command if both are warm, else by
    // sending a loyal house to keep the peace), take a side (the weaker one), or
    // let them bleed. A royal match is the rare, dear bond.
    const [weak, strong] = [war, foe].sort((a, b) => (a.units ?? 0) - (b.units ?? 0));
    const keeper = great.filter((p) => p.id !== war.id && p.id !== foe.id).sort((a, b) => favourOf(b.id) - favourOf(a.id))[0];
    const acts = [
      cold
        ? (keeper ? { label: `Send ${keeper.house.name.replace(/^House /, "")} to keep the peace`, action: "settle", city: seatOf(war.id)?.id, to: foe.id } : null)
        : { label: "Command peace", action: "peace", city: seatOf(war.id)?.id, to: foe.id },
      { label: `Back ${weak.house.name.replace(/^House /, "")}, the weaker (${((weak.units ?? 0) * 200).toLocaleString("en-US")} men to ${((strong.units ?? 0) * 200).toLocaleString("en-US")})`, action: "back", city: seatOf(weak.id)?.id, to: strong.id },
      { label: "Sit it out", ui: "sitout", war: `${war.id}:${foe.id}` },
      matchFor(war.id, foe.id) ? { label: "Wed them to each other", action: "marriage", city: seatOf(war.id)?.id, to: foe.id } : null,
    ].filter((a) => a && (a.ui || a.city !== undefined));
    const why = cold
      ? `${cold.house.name} is too cold to obey a royal peace (favour ${Math.round(favourOf(cold.id))}, it needs 40). Warm them first, or bind the two by marriage.`
      : "Every season of war burns fields and lowers the realm's peace. Both are warm enough to obey the King's peace.";
    out.push({ urgency: 50, text: `${war.house.name} and ${foe.house.name} are at war`, why, acts: acts.filter((a) => a.city !== undefined) });
  }
  if (purse < 150) out.push({ urgency: 40, text: "The royal treasury is thin", why: "Every decree costs crowns; a higher tithe fills the purse but cools the houses.", acts: [{ label: "Raise the tithe", ui: "tithe_up" }] });
  if (!out.length) out.push({ urgency: 0, text: "The realm is quiet", why: "A good season to win a house's love before you need it.", acts: [] });
  // Every order shows its price before the King gives it, as the town card does: "Command peace  6k cr".
  // And what it does, so the King weighs effect against price: "Gift crowns  15k cr · +10".
  const DOES = { sellswords: "1,000 men", back: "+12 them, −12 the other", settle: "truce; keeper +6, both −3", sitout: "the war goes on",  tithe_down: `slower to cool; ${(Math.round(lastSeason.net * 50) / 1000).toFixed(1)}k less a season`, grant: "+20 them, −30 the holder", gift: "+10", feast: "+15", relief: "+12, eases it, cannot end it", marriage: "+8 each, bound in peace", peace: "+2 each, truce", banners: "+3 if they come", levy: "600 men", buyoff: "+25, others −2", alliance: "sworn 4 years, +5", march: "the host besieges; −25 them" };
  // The realm's lesser matters: plague, unrest, a thin granary, bare walls, a
  // house grown too strong, a loyal one unrewarded, a full treasury, an heir of
  // age. The Hand raises the one he has raised least lately, so his counsel
  // changes with the realm instead of saying the same thing every season.
  const turn = world?.turn ?? 0;
  const short = (h) => h.house.name.replace(/^House /, "");
  const ofHouse = (c) => great.find((p) => p.id === c.owner);
  const lacks = (c, b) => !(c.buildings ?? []).some((x) => String(x).startsWith(b)) && !meta.works?.[c.id];
  const occasions = [];
  const sick = cities.find((c) => c.plague && !c.famine);
  if (sick) occasions.push({ kind: "plague", urgency: 55, text: `Plague in ${sick.title}`, why: "The death-carts go out at night. Clean water slows it; a sept tends the dying and keeps the people from blaming the crown.",
    acts: [lacks(sick, "Aqueduct") ? { label: `Pay for an aqueduct in ${sick.title}`, action: "build", building: "aqueduct", city: sick.id } : null,
      lacks(sick, "Temple") ? { label: `Pay for a sept in ${sick.title}`, action: "build", building: "temple", city: sick.id } : null,
      { label: "Send grain", action: "relief", city: sick.id }].filter(Boolean) });
  const riot = cities.find((c) => c.disorder);
  if (riot) { const h = ofHouse(riot); occasions.push({ kind: "unrest", urgency: 55, text: `${riot.title} is in uproar`, why: "The people have stopped working and started shouting. Bread quiets a crowd; a sept or a market gives it something to lose.",
    acts: [{ label: "Send grain", action: "relief", city: riot.id }, lacks(riot, "Temple") ? { label: "Pay for a sept", action: "build", building: "temple", city: riot.id } : null,
      lacks(riot, "Marketplace") ? { label: "Pay for a market", action: "build", building: "market", city: riot.id } : null, h ? { label: `A feast for ${short(h)}`, action: "feast", city: riot.id } : null].filter(Boolean) }); }
  const lean = cities.filter((c) => !c.famine && c.granaryLow && (c.size ?? 0) >= 5 && lacks(c, "Granary")).sort((a, b) => (b.size ?? 0) - (a.size ?? 0))[0];
  if (lean) occasions.push({ kind: "granary", urgency: 40, text: `${lean.title}'s granary runs low`, why: `${lean.title} eats what it grows and keeps nothing back. One bad harvest and it starves; a granary carries it through.`,
    acts: [{ label: `Pay for a granary in ${lean.title}`, action: "build", building: "granary", city: lean.id }, { label: "Send grain now", action: "relief", city: lean.id }] });
  const fighting = great.filter((p) => (p.atWarWith ?? []).length);
  const bare = cities.filter((c) => fighting.some((p) => p.id === c.owner) && lacks(c, "City Walls") && (c.size ?? 0) >= 4).sort((a, b) => (b.size ?? 0) - (a.size ?? 0))[0];
  if (bare) { const h = ofHouse(bare); occasions.push({ kind: "walls", urgency: 45, text: `${bare.title} has no walls, and war is near`, why: `${h ? h.house.name : "Its house"} is at war, and ${bare.title} would fall to the first host that reaches it. Walls paid by the crown are remembered.`,
    acts: [{ label: `Pay for walls at ${bare.title}`, action: "build", building: "walls", city: bare.id }, h && favourOf(h.id) >= BANDS.sworn ? { label: `Swear an alliance with ${short(h)}`, action: "alliance", city: bare.id } : null].filter(Boolean) }); }
  const mighty = [...great].sort((a, b) => (b.cities?.length ?? 0) * 2 + (b.units ?? 0) - (a.cities?.length ?? 0) * 2 - (a.units ?? 0))[0];
  const avgTowns = great.reduce((n, p) => n + (p.cities?.length ?? 0), 0) / Math.max(1, great.length);
  if (mighty && (mighty.cities?.length ?? 0) >= avgTowns * 1.5 && seatOf(mighty.id) && !(stakes?.s.wards?.[mighty.id] > turn)) {
    const f = favourOf(mighty.id);
    occasions.push({ kind: "mighty", urgency: 45, text: `${mighty.house.name} grows too strong`, why: `${mighty.cities.length} towns, more than any other house. Today they kneel; a house that size could take the throne tomorrow. Bind them to you, or hold their heir at court.`,
      acts: [f >= 50 ? { label: `Swear an alliance with ${short(mighty)}`, action: "alliance", city: seatOf(mighty.id).id } : null,
        { label: `Take their heir as your ward`, action: "ward", city: seatOf(mighty.id).id },
        { label: `A feast in their honour`, action: "feast", city: seatOf(mighty.id).id }].filter(Boolean) });
  }
  const loyal = great.filter((p) => favourOf(p.id) >= 75 && seatOf(p.id)).sort((a, b) => favourOf(b.id) - favourOf(a.id))[0];
  if (loyal) occasions.push({ kind: "loyal", urgency: 30, text: `${loyal.house.name} has served you well`, why: `Favour ${Math.round(favourOf(loyal.id))}: they answer every summons. Loyalty left unrewarded cools, and the other houses watch what it earns.`,
    acts: [{ label: `Swear an alliance with ${short(loyal)}`, action: "alliance", city: seatOf(loyal.id).id }, { label: "Gift crowns", action: "gift", city: seatOf(loyal.id).id },
      lacks(seatOf(loyal.id), "Marketplace") ? { label: `Pay for a market at ${seatOf(loyal.id).title}`, action: "build", building: "market", city: seatOf(loyal.id).id } : null].filter(Boolean) });
  const crownSeat = cities.find((c) => players.find((p) => p.id === c.owner)?.house.crown && c.capital);
  if (purse >= 600 && crownSeat) occasions.push({ kind: "rich", urgency: 30, text: "The royal treasury is full", why: "Gold in a chest wins nobody. Spend it where the realm will see it, or ease the tithe and let the houses keep more.",
    acts: [{ label: "Hold a feast at court", action: "feast", city: crownSeat.id }, meta.tithe > 0 ? { label: `Lower the tithe to ${Math.round(meta.tithe * 100) - 5}%`, ui: "tithe_down" } : null,
      lacks(crownSeat, "Marketplace") ? { label: "Pay for a market at Kingsmere", action: "build", building: "market", city: crownSeat.id } : null].filter(Boolean) });
  if (court) {
    for (const h of [...great].sort(() => 0.5 - ((turn * 7 + great.length) % 10) / 10)) {
      const lord = court.lordOfHouse(h.id);
      const heir = lord && court.alive().find((k) => k.parents?.includes(lord.id) && !k.spouse && k.age >= 16);
      const match = heir && great.filter((g) => g.id !== h.id && seatOf(g.id)).map((g) => [g, court.lordOfHouse(g.id)]).find(([, l]) => l && court.alive().some((k) => k.parents?.includes(l.id) && !k.spouse && k.age >= 16 && k.gender !== heir.gender));
      if (heir && match && seatOf(h.id)) {
        const [other] = match;
        occasions.push({ kind: "match", urgency: 35, text: `${heir.name} of ${h.house.name} is of age to wed`, why: `A royal match with ${other.house.name} would bind both houses to the crown and to each other: no war between them while it holds.`,
          acts: [matchFor(h.id, other.id) ? { label: `Wed them to ${short(other)}`, action: "marriage", city: seatOf(h.id).id, to: other.id } : null, { label: "A feast for the betrothal talk", action: "feast", city: seatOf(h.id).id }].filter(Boolean) });
        break;
      }
    }
  }
  // Two of them at most. Those on the card stay a year (nothing swaps each
  // season); then the ones raised least lately come up. A matter the King has
  // answered (an order at its town) is put to rest for a year.
  const told = (meta.counselTold ??= {});
  const answered = meta.answeredAt ?? {};
  const open = occasions.filter((o) => o.acts.length && !o.acts.some((a) => a.city != null && turn - (answered[a.city] ?? -99) < 4));
  const now = meta.counselNow ?? { kinds: [], since: -99 };
  let lesser = turn - now.since < 4 ? open.filter((o) => now.kinds.includes(o.kind)) : [];
  if (!lesser.length) {
    lesser = open.sort((a, b) => (told[a.kind] ?? -99) - (told[b.kind] ?? -99) || b.urgency - a.urgency).slice(0, 2);
    for (const o of lesser) told[o.kind] = turn;
    meta.counselNow = { kinds: lesser.map((o) => o.kind), since: turn };
    if (lesser.length) chron.saveMeta(meta);
  }
  if (lesser.length) for (let i = out.length - 1; i >= 0; i--) if (out[i].urgency === 0) out.splice(i, 1);  // not "quiet" after all
  out.push(...lesser);
  // An order that can't be given now isn't offered: the banners answer once a year.
  // Once a year means once a year here too: the banners and the levy aren't
  // offered again until their year is out (the decree would refuse them anyway).
  for (const o of out) o.acts = o.acts.filter((a) => !(a.action === "banners" && (!bannersReady(world?.turn ?? 0) || seasonsLeft("banners") > 0)) && !(a.action === "levy" && seasonsLeft("levy") > 0) && !(FAVOUR.has(a.action) && a.city != null && seasonsLeft(yearlyKey(a) ?? "") > 0));
  // An order offered once is not offered again under another matter (the
  // banners answer the usurper and the dead alike): the first matter keeps it.
  const given = new Set();
  for (const o of out.sort((a, b) => b.urgency - a.urgency)) o.acts = o.acts.filter((a) => {
    const k = `${a.action ?? a.ui}:${a.city ?? ""}:${a.to ?? ""}:${a.building ?? ""}`;
    if (given.has(k)) return false;
    given.add(k);
    return true;
  });
  // The Hand's own pick on each matter: the order that does most for its cost.
  const PREFER = ["court", "ward", "feast", "relief", "tithe_down", "banners", "peace", "settle", "buyoff", "marriage", "gift", "grant", "levy", "tithe_up"];
  for (const o of out) {
    const rank = (a) => { const i = PREFER.indexOf(a.action ?? a.ui); return i < 0 ? 99 : i; };
    const best = [...o.acts].sort((a, b) => rank(a) - rank(b))[0];
    if (best && o.acts.length > 1) best.pick = true;
  }
  for (const o of out) for (const a of o.acts) {
    // The price the crown will really pay (a share of a full treasury), never the base.
    if (DECREES[a.action]?.cost) {
      a.cost = priceOf(a.action);
      a.label += `  ${a.cost >= 10000 ? `${Math.round(a.cost / 1000) / 10}m` : `${Math.round(a.cost / 10)}k`} cr`;  // gold ×100 crowns
    }
    const does = DOES[a.action ?? a.ui];
    if (does && !a.label.includes("(")) a.label += ` · ${does}`;
  }
  // Every matter the realm has, worst first: the court (courtYear) chooses
  // which are put to the King, and when.
  return out.sort((a, b) => b.urgency - a.urgency).filter((o) => !matterResting(o)).map((o) => ({ ...o, key: heardKey(o) }));
}

// What a matter is, for resting it after it is answered.
const matterKey = (o) => o.kind ?? (/is starving$/.test(o.text) ? "starving" : o.text.replace(/[\d.,]+/g, "#").replace(/:.*$/, ""));
function matterResting(o) {
  const at = meta.mattersRest?.[matterKey(o)];
  return at != null && (world?.turn ?? 0) - at < 4;
}
// The matter itself, for "never twice in a reign": its words without numbers,
// and for a threat that comes again (a march, a host of the dead, a famine
// year) the time it came.
const heardKey = (o) => `${o.text.replace(/[\d.,]+/g, "#").replace(/:.*$/, "")}${o.occur != null ? `@${o.occur}` : ""}`;

// --- the court's season -------------------------------------------------------
// Once a season the court sits and the realm holds still: Freeciv's turn timer
// stops, and the reign's clock with it. Petitioners bring their matters, and the
// realm's own matters come with the lord of the house they touch; the Hand
// speaks a line on each. The King answers, or closes the court and lets his
// silence answer. Then the doors shut and the realm moves until next season.
// One matter early in the reign, rising to three at the climax; a crisis takes
// the head of the next sitting. No matter is put to him twice in a reign.
let counselNow = [];  // the realm's matters, as the last reading of the world found them
let sitting = false;  // a sitting holds the realm until the court closes
let away = false;  // no window is watching: the realm waits for the King (every strategy game pauses when the player isn't there)
const timeoutNow = () => (paused || sitting || away ? 0 : turnSeconds);
const isCrisis = (o) => o.urgency >= 75 || /are at war$/.test(o.text);
const courtYearOf = () => (meta.court ??= { sitting: null, hand: {}, heard: {}, lastCall: 0 });
const heardCtx = () => ({ heard: (k) => courtYearOf().heard[k] != null, hear: (k) => { courtYearOf().heard[k] = world?.turn ?? 0; } });
const courtCtx = () => ({ favour: favourOf, shift: shiftFavour, send: (l) => send(`lua cmd ${l}`), watched: isWatched(), options: meta.options ?? {}, ...heardCtx() });

function hold(on) {
  // An act told back holds the realm until the King has read it, whatever else lets go.
  on = on || (meta?.status === "running" && meta?.interlude != null && !meta.interlude.seen);
  // Only while the King watches: a realm left alone lives on, court or no court.
  on = on && isWatched();
  if (sitting === on) return;
  sitting = on;
  send(`set timeout ${timeoutNow()}`);
}

function callMatter(o, turn, crisis) {
  const c = courtYearOf();
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
function pace() {
  const k = meta.minutes ? meta.elapsedMs / (meta.minutes * 60000) : null;
  const r = Math.random();
  let [every, want] = k == null ? [2, 1] : k < 0.5 ? [3, 1] : k < 0.75 ? [2, r < 0.5 ? 1 : 2] : [1, r < 0.4 ? 1 : r < 0.8 ? 2 : 3];
  const how = meta.options?.petitions;
  if (how === "rare") { every += 1; want = Math.max(1, want - 1); }
  if (how === "often") { every = Math.max(1, every - 1); want = Math.min(3, want + 1); }
  return { every, want };
}
const HAND_YEAR = 4;  // seasons: the Hand calls the King in for a crisis at most once a year

async function courtSeason(turn) {
  if (!court || !world) return;
  const c = courtYearOf();
  // A matter the realm settled on its own (the famine ended, the war is over) goes quietly.
  if (counselNow.length) for (const key of Object.keys(c.hand)) if (!counselNow.some((x) => x.key === key)) delete c.hand[key];
  turnHouses(turn);  // watched or not: a house turns, and warns, either way
  if (!isWatched() || c.sitting != null) { chron.saveMeta(meta); return; }
  const { every, want: wanted } = pace();
  const crises = counselNow.filter((o) => isCrisis(o) && o.acts?.length && c.heard[o.key] == null && !c.hand[o.key]);
  // A herald's terms under a siege can't wait for the next sitting: the court sits for them.
  const herald = court.petitions.some((p) => !p.answered && p.called == null && p.arc === "siege");
  // Back from away with a matter waiting: the court sits at once.
  const back = c.sitOnReturn && court.petitions.some((p) => !p.answered && p.called == null);
  c.sitOnReturn = false;
  const due = c.lastSat == null || turn - c.lastSat >= every || herald || back;
  // Between sittings the Hand calls the King in only for a real crisis, at most once a year.
  const push = !due && crises.length > 0 && (c.lastPush == null || turn - c.lastPush >= HAND_YEAR);
  if (!due && !push) { chron.saveMeta(meta); return; }
  let want = wanted;
  // A lord whose town starves or is besieged speaks for it first, ahead of the
  // Hand (the judge: urgency beats the rotation, and a face beats a report).
  const pleas = await court.callCrises(world, turn, Math.min(2, want), courtCtx());
  want -= pleas.length;
  const pleading = new Set(pleas.map((p) => court.people[p.from]?.playerId));
  const ownerOf = (o) => world.cities.find((x) => x.id === o.acts?.[0]?.city)?.owner;
  // The crises head the sitting, two at most (a realm in crisis is pressed, not
  // flooded); the gravest first, the rest wait for the next sitting.
  for (const o of crises.filter((o) => !pleading.has(ownerOf(o))).slice(0, Math.max(0, 2 - pleas.length))) { callMatter(o, turn, true); want--; }
  if (!push) {
    const own = counselNow.find((o) => !isCrisis(o) && o.acts?.length && c.heard[o.key] == null && !c.hand[o.key]);
    if (own && want > 0 && (want > 1 || Math.random() < 0.4)) { callMatter(own, turn, false); want--; }
    if (want > 0) await court.callSitting(world, turn, want, courtCtx());
    // A story's matter waiting in the hall is heard now, whatever the count.
    for (const p of court.petitions) if (!p.answered && p.called == null && p.kind === "arc") p.called = turn;
  }
  // Only now, with the matters called, does the court sit (a reading taken
  // meanwhile must not find an empty court and close it under them).
  const n = Object.keys(c.hand).length + court.petitions.filter((p) => !p.answered && p.called != null).length;
  if (n) {
    c.sitting = turn;
    c.push = push;
    if (push) c.lastPush = turn;
    else c.lastSat = turn;
    c.lastCall = Date.now();
    hold(true);
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
function closeCourt(turn) {
  const c = courtYearOf();
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
  closeIfDone(turn, true);
}

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

// Every matter of the sitting answered (or gone home unheard): the doors close.
function closeIfDone(turn, closing = false) {
  const c = courtYearOf();
  if (c.sitting == null) {
    hold(false);  // never held with no court sitting
    return;
  }
  // A matter the realm settled on its own while the court sat (the war ended, the
  // famine eased) is off the docket: it must not hold the doors, and the realm, shut.
  if (counselNow.length) for (const key of Object.keys(c.hand)) if (!counselNow.some((x) => x.key === key)) delete c.hand[key];
  const open = Object.keys(c.hand).length || court?.petitions.some((p) => !p.answered && p.called != null);
  if (open && !closing) return;
  c.sitting = null;
  c.lastCall = Date.now();
  hold(false);
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
function handLine(p) {
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
function docket() {
  const c = courtYearOf();
  closeIfDone(world?.turn ?? 0);
  const ownerOf = (o) => (o.acts ?? []).map((a) => world?.cities?.find((x) => x.id === Number(a.city))).map((x) => x && world.players.find((p) => p.id === x.owner)).find((p) => p && !houseFor(p).crown && !houseFor(p).wild);
  const hand = Object.entries(c.hand).map(([key, m]) => {
    const o = counselNow.find((x) => x.key === key);
    if (!o) return null;
    // Brought by the lord of the house it touches; a matter of the whole realm, by the Hand himself.
    const owner = ownerOf(o);
    const lord = owner ? court.lordOfHouse(owner.id) : null;
    return { id: `hand:${key}`, hand: true, key, crisis: m.crisis, sitting: m.sitting, text: o.text, why: o.why, acts: o.acts,
      name: lord?.name ?? "The Hand of the King", house: lord ? houseFor(owner).name : "", from: lord?.id ?? null, who: lord ? court.sitter(lord.id) : null, due: null };
  }).filter(Boolean).sort((a, b) => Number(b.crisis) - Number(a.crisis));
  // No fuse at court: the realm holds while it sits, so no timer would tell true.
  const pets = court.open().filter((p) => p.called != null).map((p) => ({ ...p, due: null, sitting: p.called, counsel: handLine(p), push: !!c.push }));
  // A court with nothing left to show the King is no court: the doors close, the realm moves.
  if (c.sitting != null && !hand.length && !pets.length) { c.hand = {}; closeIfDone(world?.turn ?? 0, true); }
  return [...hand.map((x) => ({ ...x, push: !!c.push })), ...pets];
}

// What the King's silence costs, matter by matter: the house it touches takes
// it as an answer, in its favour and in the chronicle.
function lapseOf(o) {
  const ownerOf = (c) => world.players.find((p) => p.id === c.owner);
  const city = (o.acts ?? []).map((a) => world?.cities?.find((c) => c.id === Number(a.city))).find((c) => c && ownerOf(c) && !houseFor(ownerOf(c)).crown);
  const owner = city ? world.players.find((p) => p.id === city.owner) : null;
  const house = owner ? houseFor(owner).name : null;
  const loyal = (world?.players ?? []).filter((p) => !houseFor(p).wild && !houseFor(p).crown && favourOf(p.id) >= BANDS.steady);
  const t = o.text;
  const said = (rest) => `The King said nothing ${rest}`;
  if (/grows cold/.test(t) && owner) return { shift: { [owner.id]: -6 }, text: said(`to ${house}. They take it as an answer.`) };
  if (/is starving/.test(t) && owner) return { shift: { [owner.id]: -8 }, text: said(`while ${city.title ?? city.name} starved. ${house} counts its dead and remembers.`) };
  if (/at war/.test(t)) { const ids = o.acts.map((a) => world.cities.find((c) => c.id === Number(a.city))?.owner).concat(o.acts.map((a) => a.to)).filter((x) => x != null); return { shift: Object.fromEntries([...new Set(ids)].map((id) => [id, -3])), text: said("of the war, and it burns on. Both houses note whose side the crown was on: neither.") }; }
  if (o.kind === "plague" && owner) return { shift: { [owner.id]: -5 }, text: said(`while plague emptied ${city.title ?? city.name}. ${house} buries its dead alone.`) };
  if (o.kind === "unrest" && owner) return { shift: { [owner.id]: -5 }, text: said(`to the crowds of ${city.title ?? city.name}. They shout louder.`) };
  if (o.kind === "granary" && owner) return { shift: { [owner.id]: -3 }, text: said(`of ${city.title ?? city.name}'s empty granary. Its people store their grudge instead.`) };
  if (o.kind === "walls" && owner) return { shift: { [owner.id]: -4 }, text: said(`of ${city.title ?? city.name}'s walls. ${house} builds its own, and remembers who didn't.`) };
  if (o.kind === "loyal" && owner) return { shift: { [owner.id]: -5 }, text: said(`to ${house}'s loyalty. Unrewarded, it cools.`) };
  if (o.kind === "mighty" && owner) return { shift: { [owner.id]: 3 }, text: said(`as ${house} grew. They take the crown's silence for weakness, and grow bolder.`) };
  if (o.kind === "match" && owner) return { shift: { [owner.id]: -3 }, text: said(`of ${house}'s heir. Another house will make the match instead.`) };
  if (o.kind === "rich") return { shift: {}, text: said("while the gold sat in the royal chest. The houses saw it sit.") };
  if (/claim to the throne|marches on Kingsmere|march is over|dead come south/.test(t)) return { shift: Object.fromEntries(loyal.map((p) => [p.id, -2])), text: said(`while ${t.replace(/[:.].*$/, "").toLowerCase()}. The loyal houses wonder whether the crown will act at all.`) };
  return { shift: owner ? { [owner.id]: -4 } : {}, text: said(`of it: ${t.replace(/:.*$/, "").toLowerCase()}.`) };
}

function lapse(m, turn) {
  const told = m.lapse ?? { shift: {}, text: `The King said nothing of it: ${m.text}.` };
  if (Object.keys(told.shift).length) shiftFavour(Object.fromEntries(Object.entries(told.shift).map(([id, d]) => [Number(id), d])), "the King's silence");
  record({ turn, kind: "unrest", text: told.text });
  (meta.mattersRest ??= {})[m.key] = turn;
  meta.matter = null;
  chron.saveMeta(meta);
}

// Why each house feels as it does: the last few things that moved its favour,
// shown to the King like a ledger of grievances and kindnesses.

// What a cause means as a deed the lord would name, said to the King's face:
// [when it warmed them, when it cooled them]. Only the King's own acts count.
const DEED_WORDS = {
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

// A royal match needs an unwed son or daughter of age from each house, one of
// each. The Hand offers a match only when this finds one.
function matchFor(pa, pb) {
  if (!court) return null;
  const [la, lb] = [pa, pb].map((pid) => court.lordOfHouse(pid));
  if (!la || !lb) return null;
  const unwed = (lord) => court.alive().filter((k) => k.parents?.includes(lord.id) && !k.spouse && k.age >= 15);
  for (const ka of unwed(la)) { const kb = unwed(lb).find((k) => k.gender !== ka.gender); if (kb) return [la, lb, ka, kb]; }
  return null;
}

// A deed the house will not forget. The same deed again adds to the old one;
// a house keeps its eight weightiest, so a great grudge never slips away.
function recordDeed(id, d, why, turn) {
  const what = DEED_WORDS[why]?.[d > 0 ? 0 : 1];
  if (!what || !turn) return;
  const list = (deeds[id] ??= []);
  const same = list.find((x) => x.what === what);
  // Done again, it weighs more, up to a point: a lifetime of tithes is one great grudge, not a number without end.
  if (same) { same.d = Math.max(-60, Math.min(60, same.d + d)); same.last = turn; }
  else list.push({ turn, last: turn, d, what });
  if (list.length > 8) deeds[id] = list.sort((a, b) => Math.abs(b.d) - Math.abs(a.d)).slice(0, 8).sort((a, b) => a.turn - b.turn);
}

// "the winter of 352, when the King took a town that was theirs": the
// house's sharpest grievance, for the chronicle to name as the cause.
const theirs = (t) => t.replace(/\bours\b/g, "theirs").replace(/\bour\b/g, "their").replace(/\bus\b/g, "them");
function causeOf(id) {
  const worst = (deeds[id] ?? []).filter((x) => x.d <= -8).sort((a, b) => a.d - b.d)[0];
  if (!worst) return "";
  const when = calendar(worst.turn);
  return `the ${when.season} of ${when.year}, when the King ${theirs(worst.what)}`;
}

function noteFavour(id, d, why) {
  if (!d || !why) return;
  if (Math.abs(d) >= 8 && why !== "the royal tithe") recordDeed(id, d, why, world?.turn);
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

// --- What the crown's favour costs -------------------------------------------------

// A decree's price grows with the treasury: a rich King's gift must be a real
// share of what he holds, or it means nothing to the house that gets it.
const SHARE = { gift: 0.04, feast: 0.03, relief: 0.03, marriage: 0.08, alliance: 0.06, march: 0.08, buyoff: 0.1, build: 0.04 };
// The reign's story for the view: each beat so far dated by the realm's calendar.
function storyNow() {
  const s = arcs?.reignView();
  if (!s) return null;
  return { ...s, beats: (s.beats ?? []).map((b) => ({ ...b, when: b.turn != null ? calendar(b.turn) : null })) };
}

// The crown's great occasions come once a year: a levy drains the countryside of
// men, a feast at court is an event, the banners answer once. The turn each was
// last given is kept with the reign; seat feasts are keyed apart from a lord's.
const YEARLY = 4;  // seasons
const FAVOUR = new Set(["gift", "feast", "relief"]);
function yearlyKey(cmd) {
  if (cmd.action === "levy" || cmd.action === "banners") return cmd.action;
  if (cmd.action === "feast") {
    const c = world?.cities?.find((x) => x.id === Number(cmd.city));
    const owner = c ? world.players.find((p) => p.id === c.owner) : null;
    if (owner && houseFor(owner).crown) return "feast:court";
  }
  // One royal favour to a house a year: grain, crowns or a feast in their honour.
  if (FAVOUR.has(cmd.action)) {
    const c = world?.cities?.find((x) => x.id === Number(cmd.city));
    // Grain to the crown's own towns is counted town by town.
    const own = world.players.find((p) => p.id === c?.owner);
    if (c) return own && houseFor(own).crown ? `relief:${c.id}` : `favour:${c.owner}`;
  }
  return null;
}
function seasonsLeft(key) {
  const at = meta?.decreeAt?.[key];
  return at == null ? 0 : Math.max(0, YEARLY - ((world?.turn ?? 0) - at));
}

function priceOf(action) {
  const base = DECREES[action]?.cost ?? 0;
  const purse = world?.players?.find((p) => houseFor(p).crown)?.gold ?? 0;
  return Math.max(base, Math.round(purse * (SHARE[action] ?? 0)));
}

// Kindness wears thin: the same house warmed again within a year is warmed
// less (a half, then a fifth), and the houses at war with it grow colder.
const KIND = new Set(["gift", "feast", "relief", "marriage"]);
function temper(action, house, changes) {
  if (!KIND.has(action) || house == null || !(changes?.[house] > 0)) return changes;
  const turn = world?.turn ?? 0;
  const seen = (meta.kindness ??= {});
  seen[house] = (seen[house] ?? []).filter((t) => t > turn - 4);
  const again = seen[house].length;
  seen[house].push(turn);
  const out = { ...changes, [house]: Math.max(1, Math.round(changes[house] * [1, 0.5, 0.2][Math.min(again, 2)])) };
  const foes = detail()?.players?.[house]?.atWarWith ?? [];
  for (const f of foes) if (f !== house && favour[f] != null) out[f] = (out[f] ?? 0) - Math.max(1, Math.round(out[house] * 0.4));
  return out;
}

// --- Oaths and the royal host ------------------------------------------------------

// A house sworn to the crown (an alliance not yet run out).
function sworn(pid) {
  return (meta?.alliances?.[pid] ?? -1) > (world?.turn ?? 0);
}

// The royal host goes to a town: sworn houses send their men with it (an ally
// marched upon breaks its own oath, and the realm hears of it).
function startCampaign({ city, house }) {
  const turn = world?.turn ?? 0;
  const at = world.cities.find((c) => c.id === city);
  if (!at) return;
  if (sworn(house)) {
    deed(kingDeeds.tagsFor("realm", "sworn_march"), { act: false, place: houseFor(world.players.find((p) => p.id === house) ?? {}).name ?? "" });
    delete meta.alliances[house];
    shiftFavour(Object.fromEntries(greatHouses().filter((p) => p.id !== house).map((p) => [p.id, -5])), "an oath to the crown");
    record({ turn, kind: "betrayal", text: `The King marches on a house sworn to him. Every lord who ever knelt to the crown takes note.`, city });
  }
  const allies = greatHouses().filter((p) => p.id !== house && sworn(p.id) && world.cities.some((c) => c.owner === p.id));
  for (const a of allies) send(`lua cmd realm_host(realm_find_player(${a.id}), ${at.x}, ${at.y}, {"Pikemen","Knights"}, 3)`);
  if (allies.length) record({ turn, kind: "decree", text: `${allies.map((p) => houseFor(p).name).join(" and ")} ${allies.length > 1 ? "answer their oaths" : "answers its oath"} and ${allies.length > 1 ? "send" : "sends"} men to march with the King.`, city });
  (meta.campaigns ??= []).push({ city, house, turn, allies: allies.map((p) => p.id) });
  chron.saveMeta(meta);
  scene("siege", { x: at.x, y: at.y, city, owner: world.players.find((p) => houseFor(p).crown)?.id, defender: house });
}

// The royal host's chance against a house's town, the same reckoning the
// forecast shows and the outcome uses: our companies (and sworn allies') against
// what the house can bring to one town; winter favours whoever holds the walls.
function marchOdds(house, allies = [], { extra = 0, turn = world?.turn ?? 0 } = {}) {
  const crown = world?.players?.find((p) => houseFor(p).crown);
  const foe = world?.players?.find((p) => p.id === house);
  if (!crown || !foe) return 0;
  const soldiers = (pid) => (world.units ?? []).filter((u) => u.owner === pid && SOLDIER(u)).length;
  const allyMen = allies.reduce((t, id) => t + soldiers(id) * 0.25, 0);
  const ours = soldiers(crown.id) + extra + allyMen;
  const theirs = soldiers(foe.id) * 0.6;  // a house can't bring every company to one town
  const winter = calendar(turn).season === "winter" ? 0.8 : 1;
  return (ours * winter) / Math.max(1, ours * winter + theirs);
}

// The siege's middle: a season in, the besieged lord's herald brings terms, and
// the King chooses: press the assault (gold, and better odds), take tribute and
// go home, or starve them out (a season longer, better odds again).
const SIEGE_PRESS = 20;   // points in a hundred the assault adds, now
const SIEGE_STARVE = 10;  // points starving them out adds, a season later
function siegeTerms(c, turn) {
  if (c.asked || !court) return;
  c.asked = true;
  const foe = world.players.find((p) => p.id === c.house);
  const lord = court.lordOfHouse(c.house);
  if (!foe || !lord) return;
  const town = cityName(c.city);
  const odds = Math.round(marchOdds(c.house, c.allies ?? [], { turn: turn + 1 }) * 100);
  // Each answer's own chances, worked the way the siege will resolve them:
  // the assault now, or the starving a season later (winter favours the walls).
  const pressOdds = Math.min(95, odds + SIEGE_PRESS);
  const starveOdds = Math.min(95, Math.round(marchOdds(c.house, c.allies ?? [], { turn: turn + 2 }) * 100) + SIEGE_STARVE);
  const starveWinter = calendar(turn + 2).season === "winter";
  // Tribute is what the house can pay, taken from its own chest.
  const tribute = Math.min(150, Math.max(0, Math.floor(foe.gold ?? 0)));
  court.arcPetition({ arc: "siege", beat: `siege-${c.city}-${c.turn}`, thread: `the siege of ${town}`, from: lord,
    text: tribute >= 50
      ? `${lord.name}'s herald comes out of ${town} under a white flag: "My ${lord.gender === "female" ? "lady" : "lord"} will pay the Crown ${tribute} gold to see your host gone by morning." The captains put the King's chances at ${odds} in a hundred.`
      : `${lord.name}'s herald comes out of ${town} under a white flag, with nothing to offer but defiance. The captains put the King's chances at ${odds} in a hundred.`,
    options: [
      { id: "press", label: "Press the assault (200 gold)", hint: `${pressOdds} in 100 · ${houseFor(foe).name} −10 · ladders and fire, more dead`, cost: 200, favour: { [c.house]: -10 }, result: `The King orders the assault. Ladders go up against the walls of ${town} at dawn.` },
      { id: "starve", label: "Starve them out", hint: `${starveOdds} in 100, a season longer${starveWinter ? ", in winter" : ""} · ${houseFor(foe).name} −5`, favour: { [c.house]: -5 }, result: `The royal host digs in around ${town}. No cart goes in or out.` },
      ...(tribute >= 50 ? [{ id: "tribute", label: "Take their gold and withdraw", hint: `+${tribute} gold · ${houseFor(foe).name} +10 · the realm sees a King who can be bought`, favour: { [c.house]: 10 }, result: `The King takes ${lord.name}'s gold and the host turns for home. ${town} rings its bells.` }] : []),
    ] }, world);
  c.tribute = tribute;
  chron.saveMeta(meta);
}

function siegeRuled(beat, option) {
  const c = (meta.campaigns ?? []).find((x) => `siege-${x.city}-${x.turn}` === beat);
  if (!c) return;
  const crown = crownOf();
  c.ruled = true;
  if (option === "press") c.press = true;
  if (option === "starve") { c.starve = true; c.extra = 1; }
  if (option === "tribute") {
    meta.campaigns = meta.campaigns.filter((x) => x !== c);
    const paid = c.tribute ?? 150;
    if (crown) send(`lua cmd for p in players_iterate() do if p.id == ${crown.id} then edit.change_gold(p, ${paid}) end; if p.id == ${c.house} then edit.change_gold(p, -${paid}) end end`);
  }
  chron.saveMeta(meta);
}

// Each season: a host that has stood two seasons before a town takes it or breaks.
function resolveCampaigns(turn) {
  for (const c of [...(meta.campaigns ?? [])]) {
    if (turn - c.turn >= 1) siegeTerms(c, turn);
    if (turn - c.turn < 2 + (c.extra ?? 0)) continue;
    // The herald's terms are answered before the siege is decided: it waits for
    // the King's word, two seasons at most, then the captains decide without him.
    if (c.asked && !c.ruled && court?.petitions.some((p) => !p.answered && p.beat === `siege-${c.city}-${c.turn}`) && (c.hold = (c.hold ?? 0) + 1) <= 2) continue;
    meta.campaigns = meta.campaigns.filter((x) => x !== c);
    const town = world.cities.find((x) => x.id === c.city);
    const crown = world.players.find((p) => houseFor(p).crown);
    const foe = world.players.find((p) => p.id === c.house);
    if (!town || !crown || !foe) continue;
    if (town.owner !== c.house) { record({ turn, kind: "decree", text: `The royal host stands down before ${cityName(c.city)}: it is no longer ${houseFor(foe).name}'s to take.`, city: c.city }); continue; }
    // Pressing the assault or starving them out tips the odds the King's way.
    const odds = Math.min(0.95, marchOdds(c.house, c.allies ?? []) + (c.press ? SIEGE_PRESS : c.starve ? SIEGE_STARVE : 0) / 100);
    // Why it went as it did, in one line: our companies against theirs, and the season.
    const why = `${(world.units ?? []).filter((u) => u.owner === crown.id && SOLDIER(u)).length} royal companies against ${houseFor(foe).name}'s ${(world.units ?? []).filter((u) => u.owner === foe.id && SOLDIER(u)).length}${calendar(turn).season === "winter" ? ", in the cold of winter" : ""}.`;
    if (Math.random() < odds) {
      send(`lua cmd local t = find.city(nil, ${c.city}); local to; for p in players_iterate() do if p.id == ${crown.id} then to = p end end; if t and to then edit.transfer_city(t, to) end`);
      shiftFavour({ [c.house]: -20 }, "the royal host");
      shiftFavour(Object.fromEntries((c.allies ?? []).map((id) => [id, 6])), "the royal host");
      deed(kingDeeds.tagsFor("realm", "sack"), { act: false, place: cityName(c.city) });
      record({ turn, kind: "sack", text: `${cityName(c.city)} falls to the royal host: ${why} ${houseFor(foe).name} has learned what the crown's anger costs.`, city: c.city });
    } else {
      send(`lua cmd local n = 0; for p in players_iterate() do if p.id == ${crown.id} then for u in p:units_iterate() do if n < 5 and u.utype:rule_name() ~= "Workers" then edit.unit_kill(u, "killed", nil); n = n + 1 end end end end`);
      shiftFavour(Object.fromEntries(greatHouses().filter((p) => p.id !== c.house).map((p) => [p.id, -3])), "the royal host");
      shiftFavour({ [c.house]: -10 }, "the royal host");
      record({ turn, kind: "battle", text: `The royal host breaks against the walls of ${cityName(c.city)}: ${why} ${houseFor(foe).name} holds, and the realm sees a King who can be refused.`, city: c.city });
    }
  }
  chron.saveMeta(meta);
}

// Shifts favour and says what it did, for the result card: "6,000 crowns · Thornvale 34 → 29".
function shiftAndTell(changes, why, cost = 0) {
  const was = Object.fromEntries(Object.keys(changes ?? {}).map((id) => [id, Math.round(favourOf(Number(id)))]));
  shiftFavour(changes ?? {}, why, true);
  const moved = Object.keys(was).map((id) => {
    const p = world?.players.find((x) => x.id === Number(id));
    const now = Math.round(favourOf(Number(id)));
    return p && now !== was[id] ? `${houseFor(p).name.replace(/^House /, "")} ${was[id]} → ${now}` : null;
  }).filter(Boolean);
  const price = cost ? [`${(cost * 100).toLocaleString("en-US")} crowns`] : [];
  const shown = moved.length > 7 ? [...moved.slice(0, 6), `and ${moved.length - 6} more`] : moved;
  return [...price, ...shown].join("  ·  ");
}

function shiftFavour(changes, why = "", told = false) {
  const moves = [];
  for (const [id, delta] of Object.entries(changes)) {
    const was = Math.round(favourOf(Number(id)));
    favour[id] = clampFavour(favourOf(Number(id)) + delta);
    noteFavour(id, delta, why);
    const now = Math.round(favourOf(Number(id)));
    const p = world?.players?.find((x) => x.id === Number(id));
    if (p && now !== was) moves.push({ id: Number(id), house: houseFor(p).name.replace(/^House /, ""), from: was, to: now });
  }
  saveFavour();
  // Every change is seen (UI rule 13): the game shows what moved and why.
  // A decree's own result card already says it ("told"), so the game doesn't repeat it.
  if (moves.length && why) {
    effects.push({ seq: ++effectSeq, why, told, moves });
    while (effects.length > 20) effects.shift();
    if (P) fs.writeFileSync(path.join(P.state, "effects.json"), JSON.stringify(effects));
  }
}

// Each house's own history with the crown (the world bible), within the reign's mood.
const LEAN = { "House Stormhold": 12, "House Goldcrest": 8, "House Wolfholt": 4, "House Highfell": 2, "House Thornvale": -2, "House Ironreach": -10, "House Sunspire": -14 };
// Where a house's favour settles when the King leaves it be: its own temper with
// the crown, so the table keeps friends and doubters rather than one number.
// The reign's goal, as the top bar shows it: how many great houses stand
// firmly with the King, of how many, and how many are at war with another.
const GOAL_FAVOUR = 50;
function goalNow() {
  const great = (world?.players ?? []).filter((p) => !houseFor(p).wild && !houseFor(p).crown && p.cities > 0);
  const ids = new Set(great.map((p) => p.id));
  const d = detail();
  const fighting = great.filter((p) => (d?.players?.[p.id]?.atWarWith ?? []).some((q) => ids.has(q))).length;
  const firm = great.filter((p) => favourOf(p.id) >= GOAL_FAVOUR).length;
  return { bar: GOAL_FAVOUR, firm, of: great.length, fighting, won: great.length > 0 && firm === great.length && fighting === 0 };
}

function restingFavour(p) {
  return clampFavour(({ loyal: 74, wary: 55, resentful: 34 }[meta.options?.trust] ?? 55) + (LEAN[houseFor(p).name] ?? 0));
}

// Each turn the crown takes its tithe; a heavy tithe wears favour down.
const tally = { total: 0, upkeep: 0 };  // the tithe since the last reckoning
const lastSeason = { net: 0 };  // the tithe less upkeep, this season, for the top bar
const favourPast = {};  // turn -> {house id: favour}, the last two years
// The King's own works: what he funds in a royal town rises over two seasons
// (shown as a building site), then stands and works for him: a market brings
// coin each season, a barracks a company each year, a granary feeds the town.
const WORK_SEASONS = 2;
function royalWorks(turn) {
  const crown = crownOf();
  if (!crown) return;
  for (const [cid, w] of Object.entries(meta.works ?? {})) {
    w.left -= 1;
    w.since = Date.now();
    if (w.left > 0) continue;
    const c = world.cities.find((x) => x.id === Number(cid));
    delete meta.works[cid];
    if (!c || c.owner !== crown.id) {
      if (w.paid) send(`lua cmd for p in players_iterate() do if p.id == ${crown.id} then edit.change_gold(p, ${w.paid}) end end`);
      record({ turn, kind: "works", text: `The King's masons leave their half-built ${w.building.toLowerCase()} in ${cityName(Number(cid))}: the town is no longer the Crown's. The coin comes home.` });
      continue;
    }
    send(`lua cmd local c = find.city(nil, ${c.id}); local b = find.building_type("${w.building}"); if c and b and not c:has_building(b) then edit.create_building(c, b) end`);
    record({ turn, kind: "works", text: `The King's ${w.building.toLowerCase()} stands finished in ${cityName(c.id)}.`, city: c.id });
    scene("feast", { x: c.x, y: c.y, city: c.id, owner: c.owner });
  }
  // What his finished works bring in.
  const mine = world.cities.filter((x) => x.owner === crown.id);
  const markets = mine.filter((x) => (x.buildings ?? []).includes("Marketplace")).length;
  if (markets) send(`lua cmd for p in players_iterate() do if p.id == ${crown.id} then edit.change_gold(p, ${markets * 40}) end end`);
  if (turn % 4 === 0) for (const x of mine.filter((y) => (y.buildings ?? []).includes("Barracks"))) {
    send(`lua cmd local c = find.city(nil, ${x.id}); if c then edit.create_unit(c.owner, c.tile, find.unit_type("Pikemen"), 1, c, -1) end`);
  }
  chron.saveMeta(meta);
}

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
  // War between the houses chokes the roads: the less peace, the less tithe reaches Kingsmere.
  const peaceNow = history[history.length - 1]?.peace ?? 1;
  // The tithe, seen: at the year's turn wagons roll to Kingsmere from the realm's
  // biggest towns, more of them the higher the tithe.
  if (turn % 4 === 0 && meta.tithe > 0) {
    const crownId = world.players.find((p) => houseFor(p).crown)?.id;
    const king = world.cities.find((c) => c.owner === crownId && c.capital);
    const from = world.cities.filter((c) => c.owner !== crownId && !houseFor(world.players.find((p) => p.id === c.owner) ?? {}).wild).sort((x, y) => y.size - x.size).slice(0, Math.max(1, Math.round(meta.tithe * 20)));
    if (king) for (const c of from) scene("tribute", { x: c.x, y: c.y, tx: king.x, ty: king.y, city: king.id, tithe: true });
  }
  if (turn % 4 === 0 && (meta.tithe >= 0.19 || meta.tithe <= 0.05)) deed(kingDeeds.tagsFor("realm", meta.tithe >= 0.19 ? "tithe_high" : "tithe_low"), { act: false });
  const t = titheLua(world, meta.tithe * (0.4 + 0.6 * peaceNow));
  tally.total += t.total;
  tally.upkeep += t.upkeep;
  lastSeason.net = t.total - t.upkeep;
  t.lua.forEach((l) => send(`lua cmd ${l}`));
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
  if (turn % 10 === 0 && (tally.total > 0 || tally.upkeep > 0)) {
    record({ turn, kind: "tithe", text: tally.total > 0
      ? `The royal tithe brings ${tally.total} gold to Kingsmere since the last reckoning; the court, the royal host and the castles cost ${tally.upkeep} gold.`
      : `No tithe has reached Kingsmere since the last reckoning; the court, the royal host and the castles still cost ${tally.upkeep} gold.` });
    tally.total = tally.upkeep = 0;
  }
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

// Where the reign is heading: peace, wealth and strength, each against a year
// ago, and the name history would give the King if it ended today, with the
// one close behind it. A report, not a judgement: the numbers say which way.
function readings() {
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
    ...(() => { const k = kingName(); return { name: k.name, why: k.why, next: kingDeeds.nextName(meta, k.name) }; })(),
  };
}

// At three quarters of the reign the last act begins, and is named: the
// gravest thing coming for the throne, so the ending is seen coming.
function lastAct() {
  if (!meta.minutes || meta.lastAct || meta.elapsedMs < meta.minutes * 60000 * 0.75) return;
  const u = stakes?.s.usurper;
  const story = arcs?.reignView();
  const pretender = u && u.stage !== "none" ? world?.players?.find((p) => p.id === u.house) : null;
  const threat = pretender ? `${houseFor(pretender).name}'s claim to the throne`
    : story && story.status === "running" ? story.title
    : (stakes?.s.north?.waves ?? 0) > 0 ? "the dead from the North" : "the houses' own ambitions";
  meta.lastAct = { threat, turn: world?.turn ?? 0 };
  chron.saveMeta(meta);
  record({ turn: world?.turn ?? 0, kind: "act", text: `The last act of the reign begins. What comes for the throne now: ${threat}.` });
}

// The King's ambitions: three goals he carries from his first season, each a
// way to be remembered. Met, it is told in the chronicle, the great houses
// warm to a King who does what he set out to do, and history counts it.
const AMBITIONS = [
  { key: "peace", text: "Keep the realm truly at peace for two whole years", met: () => history.length >= 8 && history.slice(-8).every((r) => r.peace >= 0.85) },
  { key: "treasury", text: "Fill the royal treasury to 200,000 crowns", met: () => (history.at(-1)?.treasury ?? 0) >= 2000 },  // history keeps gold; a crown is a hundredth of it
  { key: "loyal", text: "Win four of the great houses to the crown", met: () => (world?.players ?? []).filter((p) => !houseFor(p).wild && !houseFor(p).crown && favourOf(p.id) >= 60).length >= 4 },
  { key: "grow", text: "Grow the realm by a fifth", met: () => meta.ambitionsFrom?.pop > 0 && (history.at(-1)?.pop ?? 0) >= meta.ambitionsFrom.pop * 1.2 },
  { key: "decrees", text: "Rule with a firm hand: twenty decrees in the King's name", met: () => chronicle.filter((e) => e.kind === "decree" && e.turn >= (meta.ambitionsFrom?.turn ?? 0)).length >= 20 },
];

// The royal ladder: one aim always before the King, each with a reward he can
// see in the realm, each leading to the next (build, then muster, then win a
// house, then trade, then take land, then hold it). Checked every few seconds;
// met, the reward lands at once and the next aim is named.
const crownOf = () => world?.players?.find((p) => houseFor(p).crown);
const crownSeat = () => { const c = crownOf(); return c ? world.cities.find((x) => x.owner === c.id && x.capital) ?? world.cities.find((x) => x.owner === c.id) : null; };
const crownHas = (b, seatOnly = false) => { const c = crownOf(); return !!c && world.cities.some((x) => x.owner === c.id && (!seatOnly || x.capital) && (x.buildings ?? []).includes(b)); };
const SOLDIER = (u) => !CIVILIAN.has(u.type);
const LADDER = [
  { key: "granary", text: "Raise a granary in Kingsmere", how: "Open Kingsmere's card and fund a granary.",
    met: () => crownHas("Granary", true), reward: "feast", says: "Kingsmere's granary stands full. The town holds a harvest feast in the King's name." },
  { key: "host", text: "Muster a royal host of 2,400 men", how: "Raise the levy, or call the banners.",
    met: () => (world.units ?? []).filter((u) => u.owner === crownOf()?.id && SOLDIER(u)).length >= 12, reward: "knights", says: "Two thousand four hundred men stand under the royal banner. Two knights ride in to join them, unasked." },
  { key: "friend", text: "Win a great house to the Crown", how: "Favour a house until it stands at 70.",
    met: () => world.players.some((p) => !houseFor(p).wild && !houseFor(p).crown && favourOf(p.id) >= 70), reward: "gold", says: "A great house swears itself to the Crown, and sends a chest of silver to prove it." },
  { key: "market", text: "Raise a market in a royal town", how: "Fund a market in any town of the Crown.",
    met: () => crownHas("Marketplace"), reward: "gold", says: "The royal market opens. Merchants come from three houses' lands to trade under the King's peace." },
  { key: "town", text: "Bring a new town under the Crown", how: "March the royal host on a town, or win one by grant.",
    met: () => { const c = crownOf(); return !!c && world.cities.some((x) => x.owner === c.id && !(meta.ladder?.held ?? []).includes(x.id)); }, reward: "feast", says: "A new town flies the royal banner. Its people line the road to see the King's men ride in." },
  { key: "walls", text: "Wall Kingsmere against what comes", how: "Fund walls in Kingsmere.",
    met: () => crownHas("City Walls", true), reward: "knights", says: "Stone walls ring Kingsmere. Let them come." },
];

// Past the six, the ladder keeps going from the realm itself: win back the
// coldest great house (its lord by name), or raise what a royal town lacks.
function nextAim() {
  const crown = crownOf();
  const cold = world.players.filter((p) => !houseFor(p).wild && !houseFor(p).crown && world.cities.some((c) => c.owner === p.id))
    .sort((a, b) => favourOf(a.id) - favourOf(b.id))[0];
  const want = (meta.ladder.n ?? 0) % 2 === 0;
  if (cold && favourOf(cold.id) < 45 && want) {
    const lord = court?.lordOfHouse(cold.id);
    const to = Math.min(70, Math.round(favourOf(cold.id)) + 20);
    return { key: `win-${cold.id}-${to}`, text: `Win back ${lord ? lord.name : houseFor(cold).name} of ${houseFor(cold).name}`, how: `Bring ${houseFor(cold).name} to ${to} favour: a gift, a feast, a match, or a ruling in their favour.`,
      pid: cold.id, to, reward: "gold", says: `${lord ? lord.name : houseFor(cold).name} rides to Kingsmere and kneels before the whole court.` };
  }
  for (const c of world.cities.filter((x) => x.owner === crown.id)) {
    const lacks = [["Granary", "a granary"], ["Marketplace", "a market"], ["City Walls", "walls"], ["Barracks", "a barracks"]].find(([b]) => !(c.buildings ?? []).includes(b) && !meta.works?.[c.id]);
    if (lacks) return { key: `build-${c.id}-${lacks[0]}`, text: `Raise ${lacks[1]} in ${cityName(c.id)}`, how: `Open ${cityName(c.id)}'s card and fund ${lacks[1]}.`, city: c.id, building: lacks[0], reward: "feast", says: `${cityName(c.id)} has its ${lacks[1].replace(/^an? /, "")}. The townsfolk drink to the King.` };
  }
  return null;
}
const aimMet = (a) => a.met ? a.met() : a.pid != null ? favourOf(a.pid) >= a.to : a.city != null ? (world.cities.find((x) => x.id === a.city)?.buildings ?? []).includes(a.building) : false;
const aimNow = () => meta.ladder ? (LADDER[meta.ladder.i] ?? meta.ladder.dyn ?? null) : null;

// Where the King acts on his aim: the town whose card holds the means (a quest
// log's marker). Kingsmere for its works and the levy, a royal town without a
// market, the warmest house's seat to win, a town he could take.
function aimPlace(a) {
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
function aimProgress(a) {
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
    case "host": { const n = (world.units ?? []).filter((u) => u.owner === crown.id && SOLDIER(u)).length; return { text: `${(Math.min(n, 12) * 200).toLocaleString("en-US")} of 2,400 men`, frac: Math.min(1, n / 12) }; }  // in men, as the ledger counts them
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

function ladder() {
  if (meta.status !== "running" || !world || !crownOf()) return;
  // Aims already true when the reign begins are passed over: the King is never asked for what he has.
  meta.ladder ??= { i: 0, held: world.cities.filter((x) => x.owner === crownOf().id).map((x) => x.id), skip: LADDER.filter((a) => a.key !== "town" && a.met()).map((a) => a.key) };
  const l = meta.ladder;
  l.held ??= world.cities.filter((x) => x.owner === crownOf().id).map((x) => x.id);  // a save from before
  while (l.i < LADDER.length && (l.skip ?? []).includes(LADDER[l.i].key)) l.i++;
  // Past the fixed six, an aim drawn from the realm (one at a time).
  if (l.i >= LADDER.length && !l.dyn) { l.dyn = nextAim(); if (l.dyn) chron.saveMeta(meta); }
  const aim = aimNow();
  if (!aim || !aimMet(aim)) return;
  const seat = crownSeat();
  if (aim.reward === "feast" && seat) scene("feast", { x: seat.x, y: seat.y, city: seat.id, owner: seat.owner });
  if (aim.reward === "knights" && seat) {
    send(`lua cmd local c = find.city(nil, ${seat.id}); if c then for i = 1, 2 do edit.create_unit(c.owner, c.tile, find.unit_type("Knights"), 1, c, -1) end end`);
    scene("muster", { x: seat.x, y: seat.y, tx: seat.x + 2, ty: seat.y + 1, city: seat.id });
  }
  if (aim.reward === "gold") send(`lua cmd for p in players_iterate() do if p.id == ${crownOf().id} then edit.change_gold(p, 250) end end`);
  record({ turn: world.turn, kind: "aim", text: aim.says });
  if (l.i < LADDER.length) l.i++;
  else { l.dyn = null; l.n = (l.n ?? 0) + 1; }
  if (aim.key === "town") l.held = world.cities.filter((x) => x.owner === crownOf().id).map((x) => x.id);
  l.just = { text: aim.text, at: Date.now() };
  chron.saveMeta(meta);
}

function ambitions() {
  if (!meta.minutes || meta.status !== "running" || !world) return;
  if (!meta.ambitions) {
    // Three that aren't already true when the reign begins, chosen by the realm's own seed.
    meta.ambitionsFrom = { turn: world.turn, pop: history.at(-1)?.pop ?? 0 };  // what this reign is measured from
    const open = AMBITIONS.filter((a) => !a.met());
    const hash = (t) => t.split("").reduce((h, ch) => (Math.imul(h, 31) + ch.charCodeAt(0)) >>> 0, 7);
    meta.ambitions = [...open].sort((a, b) => hash(meta.id + a.key) - hash(meta.id + b.key)).slice(0, 3).map((a) => ({ key: a.key, text: a.text, met: null }));
    chron.saveMeta(meta);
  }
  for (const a of meta.ambitions) {
    if (a.met != null || !AMBITIONS.find((x) => x.key === a.key)?.met()) continue;
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
function council() {
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
      { id: "a", label: `Side with ${name(a)}`, hint: `${name(a)} +15 · ${name(b)} −20`, favour: { [a.id]: 15, [b.id]: -20 }, result: `The King sides with ${name(a)}. ${name(b)} leaves the council hall without bowing.` },
      { id: "b", label: `Side with ${name(b)}`, hint: `${name(b)} +15 · ${name(a)} −20`, favour: { [b.id]: 15, [a.id]: -20 }, result: `The King sides with ${name(b)}. ${name(a)} leaves the council hall without bowing.` },
      { id: "peace", label: "Command them both to make peace (300 gold)", hint: `${name(a)} −5 · ${name(b)} −5 · the crown pays the blood-price`, cost: 300, favour: { [a.id]: -5, [b.id]: -5 }, result: `The King orders peace and pays the blood-price himself. Neither house thanks him for it.` },
    ] }, world);
  (meta.councilWar ??= {})[`council-${due}`] = [a.id, b.id];
  record({ turn: world.turn, kind: "council", text: `The great council divides over the war between ${name(a)} and ${name(b)}.` });
  chron.saveMeta(meta);
}

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

// The reign in acts: at each quarter of its clock the act just gone is told
// back. Two or three of the King's weightiest choices in it, each where it
// happened and what came of it, then the name he is earning. The realm waits
// while he reads it (the clock and the seasons hold), and goes on when he has.
function interlude() {
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
  const named = (() => { const k = kingName(); return { name: k.name, next: kingDeeds.nextName(meta, k.name) }; })();
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
  meta.interlude = { q, title: `End of the ${acts[q - 1]} act`, turn: world?.turn ?? 0, choices, fates: [], seen: false };
  chron.saveMeta(meta);
  record({ turn: world?.turn ?? 0, kind: "act", text: `The ${acts[q - 1]} act of the reign ends.` });
}

// How the reign ends, shown before its name: the King's weightiest choices,
// three or four, each where it happened, and what became of every great house.
function epilogue() {
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

function score() {
  if (!history.length) return { score: 0, peace: 0, pop: 0, verdict: "A reign too short to judge." };
  const peace = history.reduce((s, r) => s + r.peace, 0) / history.length;
  const last = history[history.length - 1];
  const alive = Object.values(last.houses).filter((h) => h.towns > 0).length;
  const total = Math.round(peace * 600 + last.pop * 4 + alive * 30 + last.treasury * 0.5);
  const verdict = peace > 0.8 && last.pop > 150 ? "A golden age. Songs will be sung of your reign."
    : peace > 0.6 ? "A steady hand. The realm endured and grew."
    : peace > 0.35 ? "A troubled reign. The houses bled one another while you watched."
    : "A realm on fire. History will remember your reign as the age of swords.";
  return { score: total, peace, pop: last.pop, verdict };
}

function endReign(why, outcome = "completed") {
  if (meta.status !== "running") return;
  const s = score();
  if (outcome === "deposed") { s.score = Math.round(s.score * 0.4); s.verdict = "Deposed. The crown passed to another while you watched."; }
  if (outcome === "won") { s.score = Math.round(s.score * 1.5); s.verdict = "The crown held. The tale that came for it is told, and the King is still in his seat."; }
  if (outcome === "fallen") { s.score = Math.round(s.score * 0.3); s.verdict = "The realm fell to the dead. No one is left to remember."; }
  { const k = kingName(outcome); s.title = `The King ${k.name}`; s.why = k.why; }
  meta.epilogue = epilogue();
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
  paused = true;
  send("set timeout 0");
}

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
  if (meta?.status === "running" && fc) ladder();
  if (!meta || paused || sitting || meta.status !== "running" || !fc) return;  // the court sitting holds the clock too
  meta.elapsedMs += 5000;
  if (meta.minutes > 0 && meta.elapsedMs >= meta.minutes * 60000) endReign("The appointed time has passed. The reign ends.");
  else {
    lastAct();
    ambitions();
    council();
    interlude();
    if (meta.elapsedMs % 30000 === 0) chron.saveMeta(meta);
  }
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

function reignInfo() {
  return {
    id: meta.id, name: meta.name, scenario: meta.scenario, status: meta.status, paused, minutes: meta.minutes,
    elapsedMs: meta.elapsedMs, remainingMs: meta.minutes > 0 ? Math.max(0, meta.minutes * 60000 - meta.elapsedMs) : null,
    score: meta.score, verdict: meta.verdict, title: meta.title, why: meta.why ?? null, outcome: meta.outcome, ended: meta.endedAt,
    epilogue: meta.epilogue ?? null, lastAct: meta.lastAct ?? null, interlude: meta.interlude && !meta.interlude.seen ? meta.interlude : null, ambitions: meta.ambitions ?? null, aim: aimNow() ? { n: Math.min(meta.ladder.i, LADDER.length) + (meta.ladder.n ?? 0) + 1, of: meta.ladder.i < LADDER.length ? LADDER.length : null, text: aimNow().text, how: aimNow().how, progress: aimProgress(aimNow()), at: aimPlace(aimNow()) } : null, aimDone: meta.ladder?.just && Date.now() - meta.ladder.just.at < 8000 ? meta.ladder.just.text : null, readings: meta.status === "running" ? readings() : null,
    souls: world?.cities?.reduce((t, c) => t + soulsOf(c.size), 0) ?? 0,
  };
}

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
    // The King answered the Hand's matter: it rests a year, and the next one comes up.
    const { key } = await body(req);
    if (key) {
      // A matter at court is keyed by the matter itself; it rests as its kind does.
      const o = counselNow.find((x) => x.key === String(key));
      (meta.mattersRest ??= {})[o ? matterKey(o) : String(key)] = world?.turn ?? 0;
      // An ultimatum answered: the house's anger starts over (it may turn again).
      if (o?.kind === "ultimatum") for (const t of Object.values(meta.turning ?? {})) if (t.state === "sent" && t.at === o.occur) { t.state = null; t.seasons = 0; }
      delete courtYearOf().hand[String(key)];
      closeIfDone(world?.turn ?? 0);
      chron.saveMeta(meta);
    }
    return json(res, 200, { ok: true });
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
    // {city, building, kind, progress} stages its work; {city, mood: riot|feast|hunger|calm} its mood.
    const moods = { riot: { disorder: true }, feast: { celebrating: true }, hunger: { famine: true }, calm: { disorder: false, celebrating: false, famine: false } };
    const at = (meta.stage ??= {});
    if (b.mood) at[Number(b.city)] = { ...(at[Number(b.city)] ?? {}), ...moods.calm, ...(moods[b.mood] ?? {}) };
    else at[Number(b.city)] = { ...(at[Number(b.city)] ?? {}), building: String(b.building ?? "Pikemen"), buildingKind: String(b.kind ?? "UnitType"), progress: Number(b.progress ?? 0.5) };
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
    // The King answers a petition in his own words. The local model proposes
    // which ruling he means; nothing happens until he confirms it (confirm:
    // the option id), so a misreading can never act on its own.
    const { id, words, confirm } = await body(req);
    const pet = court.petitions.find((x) => x.id === id && !x.answered);
    const said = String(words ?? "").trim().slice(0, 500);
    if (!pet || !said) return json(res, 400, { error: "there's no one waiting on that" });
    const who = court.people[pet.from];
    if (!confirm) {
      const read = await ruleFrom(pet, who, said);
      if (!read) return json(res, 503, { error: "Your words hang in the hall unread. (The local model isn't running; choose a ruling instead.)" });
      const o = pet.options.find((x) => x.id === read.option);
      return json(res, 200, { proposed: read.option, label: crowns(o?.label ?? read.option), name: who?.name ?? "" });
    }
    const reaction = await reactTo(pet, who, said, String(confirm), meta.options?.language ?? "en");
    const out = rule(id, String(confirm));
    if (out.error) return json(res, 400, out);
    record({ turn: world.turn, kind: "decree", text: `The King to ${who?.name ?? "the petitioner"}: "${said}"` });
    if (who) court.remember(who.id, `The King told me: "${said.slice(0, 160)}"`);
    return json(res, 200, { ...out, option: String(confirm), reaction, name: who?.name ?? "", gender: who?.gender ?? "male" });
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
