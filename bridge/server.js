// Bridge between the Freeciv server (the simulation) and the Godot view.
// - Runs one Freeciv server for the active chronicle (see chronicles.js),
//   resuming from that chronicle's newest save; can switch chronicles live.
// - Turns Freeciv's EVENT lines into the chronicle, keeps a per-turn ledger,
//   times and scores reigns.
// - Exposes a small HTTP API on 127.0.0.1:8787 for the view.

import { spawn, execFileSync } from "node:child_process";
import fs from "node:fs";
import crypto from "node:crypto";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { houseFor, cityName, describe, rememberNames, HOUSES } from "./narrator.js";
import { godCommand, healLua } from "./god.js";
import { readSave, extractDetail } from "./savefile.js";
import { townsfolk } from "./townsfolk.js";
import { ROLES, GOALS, TRAITS } from "./characters.js";
import { folkTale, folkPlain, moodRules, speak, ruleFrom, reactTo, speech, voiceFor, transcribe, aiStatus } from "./claude.js";
import { BUILD_COST, granarySize } from "./rules.js";
import * as chron from "./chronicles.js";
import { decree, titheLua, clampFavour, DECREES, bannersReady } from "./crown.js";
// Lords whose first names were borrowed from A Song of Ice and Fire, renamed
// in realm.serv; realms begun before then still carry the old names in their
// saved game, so they are shown by the new ones.
const RENAMED = {
  "Lady Olenna Thornvale": "Lady Isolde Thornvale",
  "Lord Robb Stormhold": "Lord Rhys Stormhold",
  "Princess Arianne Sunspire": "Princess Ximena Sunspire",
  "Lord Jon Highfell": "Lord Declan Highfell",
};
import { Court } from "./characters.js";
import { Minds, route as mindsRoute } from "./minds.js";
import { Arcs, templates as arcTemplates, check } from "./arcs.js";
import { Chatter } from "./chatter.js";
import { bible, FAMILIES, LESSER } from "./lore.js";
import { Stakes, calendar, epithet } from "./stakes.js";
import { watched, usageToday, moodFrom, isWatched, arcFromWords } from "./claude.js";

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
let turnSeconds = 90;
let paused = false;
// Each great house's regard for the crown (0-100), by Freeciv player id.
let favour = {};
const favourWhy = {};  // player id -> [{ d, why }], newest last: why each house feels as it does
let court = null;
let minds = null;
let arcs = null;
let chatter = null; // talk and gossip between minds (chatter.js)
let arcsRunning = false;
let stakes = null;
let decreesIssued = 0;
let seasonRunning = false;
// Recent events with a place on the map, so the view can show them happening.
let scenes = [];

const arrivals = new Set();  // scenes already credited on arrival

// The King walking among his people (the player, who has no court record):
// everyone knows him, and names him to his face as his station demands.
const KING = { name: "the King", house: "The Crown", title: "King", lord: true, address: "Your Grace" };
const isKing = (b) => String(b?.you?.id ?? "") === "king";

function scene(kind, fields) {
  scenes.push({ kind, turn: world?.turn ?? 0, at: Date.now(), ...fields });
  if (scenes.length > 120) scenes = scenes.slice(-120);
}

function load(id) {
  meta = chron.readJson(chron.paths(id).meta);
  P = chron.paths(id);
  const lines = (f) => (fs.existsSync(f) ? fs.readFileSync(f, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l)) : []);
  chronicle = lines(path.join(P.state, "chronicle.jsonl"));
  history = lines(path.join(P.state, "history.jsonl"));
  world = chron.readJson(path.join(P.state, "world.json"));
  scars = chron.readJson(path.join(P.state, "scars.json"), []);
  detailCache = { file: null, mtime: 0, data: null };
  turnSeconds = 90;  // one pace for every realm: a season a minute and a half
  paused = meta.status !== "running";
  favour = chron.readJson(path.join(P.state, "favour.json"), {});
  for (const k of Object.keys(favourWhy)) delete favourWhy[k];
  Object.assign(favourWhy, chron.readJson(path.join(P.state, "favour-why.json"), {}));
  // The last two years of favour and the season's income, so trends survive a restart.
  const past = chron.readJson(path.join(P.state, "favour-past.json"), {});
  for (const k of Object.keys(favourPast)) delete favourPast[k];
  Object.assign(favourPast, past.byTurn ?? {});
  lastSeason.net = past.net ?? 0;
  meta.tithe ??= 0.1;
  court = new Court(P.base, record);
  arcs = new Arcs(P.base, court, record);
  chatter?.stop();
  chatter = new Chatter(P.state, { world: () => world, turn: () => world?.turn ?? 0, minds: () => minds });
  stakes = new Stakes(P.state, record, endReign);
  rememberNames(world);
  minds = new Minds(P.state, {
    world: () => world, court: () => court, tithe: () => meta.tithe,
    town: (id) => {
      const x = detail()?.cities?.[id];
      return x ? { famine: x.hadFamine, plague: x.plagueTurn >= 0 && (world?.turn ?? 0) - x.plagueTurn <= 4 } : {};
    },
  });
  minds.catchUp(chronicle);
}

function newestSave(kind = "") {
  const saves = fs.readdirSync(P.saves).filter((f) => f.startsWith("realm") && f.includes(".sav") && f.includes(kind));
  if (!saves.length) return null;
  saves.sort((a, b) => fs.statSync(path.join(P.saves, b)).mtimeMs - fs.statSync(path.join(P.saves, a)).mtimeMs);
  return path.join(P.saves, saves[0]);
}

// Details only the save file holds (food stores, construction, orders, wars),
// re-read whenever Freeciv writes a newer autosave.
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
    send(`set timeout ${paused ? 0 : turnSeconds}`);
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
    noteFavour(p.id, ({ loyal: 19, wary: 0, resentful: -21 }[o.trust] ?? 0), "the realm's mood at your crowning");
    noteFavour(p.id, lean, lean > 0 ? "their old loyalty to the crown" : "their old grievances against the crown");
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

function snapshot() {
  send(`lua unsafe-file ${path.join(DIR, "lua", "snapshot.lua")}`);
  setTimeout(() => {
    world = chron.readJson(path.join(P.state, "world.json")) || world;
    rememberNames(world);
    ledger();
    sieges();
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
  const out = court.answer(id, option, world);
  if (out.error) return out;
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
  record({ turn: world.turn, kind: "decree", text: out.text });
  rulingScene(id, option, out);
  return { ok: true, text: crowns(out.text) + (effects ? `\n${effects}` : "") };
}

// A town is besieged while an enemy host stands at its walls: three or more
// fighting units of another house on the tiles around it. One scene per turn.
const CIVILIAN = new Set(["Settlers", "Workers", "Migrants", "Engineers", "Explorer", "Caravan", "Freight", "Diplomat", "Spy", "Leader"]);
function sieges() {
  if (!world?.units || !world?.cities) return;
  for (const c of world.cities) {
    const near = world.units.filter((u) => u.owner !== c.owner && !CIVILIAN.has(u.type) && Math.max(Math.abs(u.x - c.x), Math.abs(u.y - c.y)) === 1);
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

// A ruling at court made visible: what the King gives goes out from
// Kingsmere by wagon, a ward comes to Kingsmere, and any other word is
// carried by a royal rider to the petitioner's seat.
function rulingScene(id, option, out) {
  const p = court.petitions.find((x) => x.id === id);
  const who = p && court.people[p.from];
  const seat = who && (world.cities.find((c) => c.id === who.seat) ?? world.cities.find((c) => c.owner === who.playerId && c.capital) ?? world.cities.find((c) => c.owner === who.playerId));
  const crown = world.players.find((x) => houseFor(x).crown);
  const king = world.cities.find((c) => c.owner === crown?.id && c.capital) ?? world.cities.find((c) => c.title === "Kingsmere");
  if (!seat || !king || seat.id === king.id) return;
  const words = `${option} ${out.text}`.toLowerCase();
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
    setTimeout(() => stakes?.tick(Number(ev.turn), world, { favour: favourOf, shift: shiftFavour, send: (l) => send(`lua cmd ${l}`), watched: isWatched(), options: meta.options ?? {} }), 2000);
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
  if (ev.kind === "city_shrank" && town && (ev.reason === "famine" || ev.reason === "plague")) scene(ev.reason, { x: town.x, y: town.y, city: town.id });
  const text = describe(ev, world);
  if (text) record({ turn: Number(ev.turn), kind: ev.kind, text, city: ev.city ? Number(ev.city) : undefined });
}

// Every four turns (a year of seasons), the people of the realm make their moves.
async function runSeason() {
  if (!world || seasonRunning || !court) return;
  seasonRunning = true;
  try {
    await court.season(world, { favour: favourOf, warded: (pid) => (stakes?.s.wards?.[pid] ?? -1) > (world?.turn ?? 0), send: (l) => send(`lua cmd ${l}`), shift: shiftFavour, watched: isWatched(), options: meta.options ?? {} });
  } catch (err) {
    console.error("season:", err);
  } finally {
    seasonRunning = false;
  }
}

// Each season the realm's story arcs move on (arcs.js); n seasons at once
// fast-forwards them, re-reading the realm whenever a beat pulled a lever.
function arcCtx() {
  const d = detail();
  return {
    world, minds, favour: favourOf, shift: shiftFavour, send: (l) => send(`lua cmd ${l}`),
    atWar: (a, b) => (d?.players?.[a]?.atWarWith ?? []).includes(b),
    town: (id) => {
      const x = d?.cities?.[id];
      return x ? { food: x.foodStock, famine: x.hadFamine, plague: x.plagueTurn >= 0 && world.turn - x.plagueTurn <= 16 } : {};
    },
    recent: (turns = 16) => chronicle.filter((e) => e.turn >= world.turn - turns),
    refresh: () => new Promise((r) => { snapshot(); setTimeout(r, 900); }),
  };
}

async function runArcs(n = 1, start = true) {
  if (!world || !arcs || arcsRunning) return false;
  arcsRunning = true;
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
  const cold = great.filter((p) => favourOf(p.id) < 35).sort((a, b) => favourOf(a.id) - favourOf(b.id))[0];
  if (cold && seatOf(cold.id)) {
    const f = favourOf(cold.id);
    // The Hand names what is cooling them most, from the house's ledger of causes.
    const drain = (favourWhy[cold.id] ?? []).filter((r) => r.d < 0).sort((a, b) => a.d - b.d)[0];
    const cause = drain ? ` What cools them most: ${drain.why} (${Math.round(drain.d)}).` : "";
    // A royal match binds the cold house to the most loyal one: both warm, and a long truce holds.
    const friend = great.filter((p) => p.id !== cold.id && !stilled(cold.id, p.id)).sort((a, b) => favourOf(b.id) - favourOf(a.id))[0];
    const match = friend ? [{ label: `Wed them to ${friend.house.name.replace(/^House /, "")}`, action: "marriage", city: seatOf(cold.id).id, to: friend.id }] : [];
    // A taken town is answered by giving it back, if the other house still holds it.
    const took = meta.taken?.[cold.id];
    const back = drain?.why === "a town granted or taken" && took && cities.some((c) => c.id === took.city && c.owner === took.to)
      ? [{ label: `Return ${cityName(took.city)} to them`, action: "grant", city: took.city, to: cold.id }] : [];
    const lighter = drain?.why === "the royal tithe" && meta.tithe > 0 ? [{ label: `Lower the tithe to ${Math.round(meta.tithe * 100) - 5}%`, ui: "tithe_down" }] : [];
    // The two rules, plainly: under 25 the lord may rise any season; two houses
    // under 25 and one of them claims the throne.
    const angryNow = great.filter((p) => favourOf(p.id) < 25).length;
    const rule = f < 25
      ? `Under 25, their lord may raise his banners any season, likelier the colder he grows.${angryNow >= 2 ? "" : " One more house under 25 and a pretender will claim the throne."}`
      : "Under 25, a lord may raise his banners against you; two such houses and one claims the throne.";
    out.push({ urgency: f < 25 ? 100 : 70, text: `${cold.house.name} grows cold to the crown: favour ${f}`,
      why: rule + cause,
      acts: [...back, ...lighter, { label: "Gift crowns", action: "gift", city: seatOf(cold.id).id }, { label: "A feast in their honour", action: "feast", city: seatOf(cold.id).id }, ...match] });
  }
  // The usurper by name, how long until they march, and how to stop it: the
  // whispers fade once the angry houses (under 25) are won back.
  const pretender = players.find((p) => p.id === threat.pretender);
  const claimant = pretender ? pretender.house.name : "A pretender";
  if (threat.usurper === "rumour") {
    const left = Math.max(1, 8 - (threat.turn - threat.since));
    const angry = great.filter((p) => favourOf(p.id) < 25).map((p) => p.house.name.replace(/^House /, ""));
    out.push({ urgency: 95, text: `${claimant} whispers of a better claim to the throne`,
      why: `In ${left} season${left === 1 ? "" : "s"} they march on Kingsmere, unless the angry houses are won back above 25: ${angry.join(", ") || "none now"}.`,
      acts: [pretender && seatOf(pretender.id) ? { label: `Gift crowns to ${claimant.replace(/^House /, "")}`, action: "gift", city: seatOf(pretender.id).id } : null, { label: "Buy off their claim", action: "buyoff" }, { label: "Call the banners", action: "banners" }].filter(Boolean) });
  } else if (threat.usurper !== "none") out.push({ urgency: 100, text: `${claimant}'s host marches on Kingsmere`,
    why: `${(threat.theirs * 200).toLocaleString("en-US")} of their men about the walls against ${(threat.ours * 200).toLocaleString("en-US")} of yours: ${threat.theirs > threat.ours ? "as things stand, the walls would fall" : "for now, the walls would hold"}. If Kingsmere falls, the crown is lost. Loyal houses (favour 35 and up) send men to the banners; the royal levy is yours to pay for. Or buy them off: gold for their claim.`, acts: [{ label: "Call the banners", action: "banners" }, { label: "Raise the royal levy", action: "levy" }, { label: "Buy them off", action: "buyoff" }] });
  // After a march: the King decides what becomes of the house that rose.
  const rose = players.find((p) => p.id === threat.ended);
  if (rose) {
    const towns = cities.filter((c) => c.owner === rose.id && !c.capital).sort((a, b) => (a.size ?? 0) - (b.size ?? 0));
    const loyal = great.filter((p) => p.id !== rose.id).sort((a, b) => favourOf(b.id) - favourOf(a.id))[0];
    const name = rose.house.name.replace(/^House /, "");
    out.push({ urgency: 90, text: `The march is over. What of House ${name}?`,
      why: `They rose against the throne and went home (favour ${Math.round(favourOf(rose.id))}). Pardon them with a feast to win them back, hold their heir at court so they cannot rise, or take a town and give it to ${loyal ? loyal.house.name : "a loyal house"} so the realm sees the price of treason; a house driven below 25 may rise again.`,
      acts: [seatOf(rose.id) ? { label: "Pardon them with a feast", action: "feast", city: seatOf(rose.id).id } : null,
        seatOf(rose.id) ? { label: `Take their heir as your ward (${name} −5; they cannot rise for five years)`, action: "ward", city: seatOf(rose.id).id } : null,
        towns[0] && loyal ? { label: `Give ${towns[0].title ?? "a town"} to ${loyal.house.name.replace(/^House /, "")} (${name} −30, ${loyal.house.name.replace(/^House /, "")} +20)`, action: "grant", city: towns[0].id, to: loyal.id } : null].filter(Boolean) });
  }
  // The pretender's own coldness is the usurper's story: one matter, not two.
  for (const who of [threat.usurper !== "none" ? pretender : null, rose].filter(Boolean)) {
    const i = out.findIndex((o) => o.text.startsWith(`${who.house.name} grows cold`));
    if (i >= 0) out.splice(i, 1);
  }
  // (Lowering the tithe sits on the cold house's matter when the tithe is its top cause.)
  // What the banners would bring today: two companies from the loyal (60+), one from the willing (35+).
  const bannerMen = !bannersReady(world?.turn ?? 0) ? 0 : great.reduce((n, p) => { const f = favourOf(p.id); const sh = f >= 60 ? 0.25 : f >= 35 ? 0.125 : 0; return n + (sh ? Math.max(1, Math.round((p.units ?? 0) * sh)) : 0); }, 0) * 200;
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
    out.push({ urgency: d.hold ? 40 : 75, text: d.hold ? "The dead come south, and you would hold" : "The dead come south",
      why: `${(d.last ?? 0).toLocaleString("en-US")} of them fell ${where} last time; ${(d.next ?? 0).toLocaleString("en-US")} will come with the next.${when} Against them: your ${(threat.ours * 200).toLocaleString("en-US")} fighting men${bannerMen ? `, and about ${bannerMen.toLocaleString("en-US")} more if you call the banners` : " (the banners are already called this year)"}: ${d.hold ? "your own men would hold" : gap <= 0 ? "with the banners, you would hold" : gap <= 1600 ? `you would lose by ${gap.toLocaleString("en-US")}: a levy (600) and sellswords (1,000) close it` : `you would lose by ${gap.toLocaleString("en-US")}, even with a levy and sellswords`}. If every northern town falls, the realm falls with it.`,
      acts: [{ label: "Call the banners", action: "banners" }, { label: "Raise the royal levy", action: "levy" }, { label: "Hire sellswords", action: "sellswords" }].filter((a) => !d.hold && (!onlyBanners || a.action === "banners")) });
  }
  // A town the King has fed this year isn't brought to him again while the grain lasts.
  const hungry = cities.find((c) => c.famine && !((meta.relieved?.[c.id] ?? -99) > (world?.turn ?? 0) - 4));
  if (hungry) out.push({ urgency: 80, text: `${hungry.title} is starving`, why: "A hungry town shrinks, riots, and blames its King.", acts: [{ label: "Send grain", action: "relief", city: hungry.id }] });
  const waiting = court?.open?.().length ?? 0;
  if (waiting) out.push({ urgency: 60, text: `${waiting} ${waiting === 1 ? "petitioner waits" : "petitioners wait"} at court`, why: "Lords left waiting go home unheard, and say so.", acts: [{ label: "Hear them", ui: "court" }] });
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
      { label: `Back ${weak.house.name.replace(/^House /, "")}, the weaker`, action: "back", city: seatOf(weak.id)?.id, to: strong.id },
      { label: "Sit it out", ui: "sitout", war: `${war.id}:${foe.id}` },
      { label: "Wed them to each other", action: "marriage", city: seatOf(war.id)?.id, to: foe.id },
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
  const DOES = { sellswords: "1,000 men", back: "+12 them, −12 the other", settle: "truce; keeper +6, both −3", sitout: "the war goes on",  tithe_down: `slower to cool; ${(Math.round(lastSeason.net * 50) / 1000).toFixed(1)}k less a season`, grant: "+20 them, −30 the holder", gift: "+10", feast: "+15", relief: "+12, eases it, cannot end it", marriage: "+8 each, bound in peace", peace: "+2 each, truce", banners: "+3 if they come", levy: "600 men", buyoff: "+25, others −2" };
  // An order that can't be given now isn't offered: the banners answer once a year.
  for (const o of out) o.acts = o.acts.filter((a) => a.action !== "banners" || bannersReady(world?.turn ?? 0));
  // The Hand's own pick on each matter: the order that does most for its cost.
  const PREFER = ["court", "ward", "feast", "relief", "tithe_down", "banners", "peace", "settle", "buyoff", "marriage", "gift", "grant", "levy", "tithe_up"];
  for (const o of out) {
    const rank = (a) => { const i = PREFER.indexOf(a.action ?? a.ui); return i < 0 ? 99 : i; };
    const best = [...o.acts].sort((a, b) => rank(a) - rank(b))[0];
    if (best && o.acts.length > 1) best.pick = true;
  }
  for (const o of out) for (const a of o.acts) {
    if (DECREES[a.action]?.cost) a.label += `  ${DECREES[a.action].cost / 10}k cr`;
    const does = DOES[a.action ?? a.ui];
    if (does && !a.label.includes("(")) a.label += ` · ${does}`;
  }
  // Two matters at most: the Hand's card stays clear of the houses table, and the
  // court has its own badge.
  // Up to three; the card drops its last matters itself if it would reach the houses table.
  return out.sort((a, b) => b.urgency - a.urgency).slice(0, 3);
}

// Why each house feels as it does: the last few things that moved its favour,
// shown to the King like a ledger of grievances and kindnesses.

function noteFavour(id, d, why) {
  if (!d || !why) return;
  const list = (favourWhy[id] ??= []);
  const same = list.find((x) => x.why === why);
  if (same) same.d += d;  // the same cause again adds up, not repeats
  else list.push({ d, why });
  while (list.length > 6) list.shift();
}

// Shifts favour and says what it did, for the result card: "6,000 crowns · Thornvale 34 → 29".
function shiftAndTell(changes, why, cost = 0) {
  const was = Object.fromEntries(Object.keys(changes ?? {}).map((id) => [id, Math.round(favourOf(Number(id)))]));
  shiftFavour(changes ?? {}, why);
  const moved = Object.keys(was).map((id) => {
    const p = world?.players.find((x) => x.id === Number(id));
    const now = Math.round(favourOf(Number(id)));
    return p && now !== was[id] ? `${houseFor(p).name.replace(/^House /, "")} ${was[id]} → ${now}` : null;
  }).filter(Boolean);
  const price = cost ? [`${(cost * 100).toLocaleString("en-US")} crowns`] : [];
  const shown = moved.length > 7 ? [...moved.slice(0, 6), `and ${moved.length - 6} more`] : moved;
  return [...price, ...shown].join("  ·  ");
}

function shiftFavour(changes, why = "") {
  for (const [id, delta] of Object.entries(changes)) {
    favour[id] = clampFavour(favourOf(Number(id)) + delta);
    noteFavour(id, delta, why);
  }
  saveFavour();
}

// Each house's own history with the crown (the world bible), within the reign's mood.
const LEAN = { "House Stormhold": 12, "House Goldcrest": 8, "House Wolfholt": 4, "House Highfell": 2, "House Thornvale": -2, "House Ironreach": -10, "House Sunspire": -14 };
// Where a house's favour settles when the King leaves it be: its own temper with
// the crown, so the table keeps friends and doubters rather than one number.
function restingFavour(p) {
  return clampFavour(({ loyal: 74, wary: 55, resentful: 34 }[meta.options?.trust] ?? 55) + (LEAN[houseFor(p).name] ?? 0));
}

// Each turn the crown takes its tithe; a heavy tithe wears favour down.
const tally = { total: 0, upkeep: 0 };  // the tithe since the last reckoning
const lastSeason = { net: 0 };  // the tithe less upkeep, this season, for the top bar
const favourPast = {};  // turn -> {house id: favour}, the last two years
function collectTithe(turn) {
  flushHeld();  // last season's grouped lines
  // The court sits every season: a petitioner comes while fewer than three wait.
  if (court && world) court.courtDay(world, turn, { favour: favourOf, shift: shiftFavour, send: (l) => send(`lua cmd ${l}`), watched: isWatched(), options: meta.options ?? {} }).catch((err) => console.error("court day:", err));
  if (!world) return;
  favourPast[turn] = { ...favour };
  // Old grievances and kindnesses fade (about half in five years), so the cause
  // the Hand names is what moves a house now, not a lifetime's sum.
  for (const id of Object.keys(favourWhy)) {
    favourWhy[id] = (favourWhy[id] ?? []).map((r) => ({ ...r, d: r.d * 0.97 })).filter((r) => Math.abs(r.d) >= 1);
  }
  for (const t of Object.keys(favourPast)) if (Number(t) < turn - 8) delete favourPast[t];
  const t = titheLua(world, meta.tithe);
  tally.total += t.total;
  tally.upkeep += t.upkeep;
  lastSeason.net = t.total - t.upkeep;
  t.lua.forEach((l) => send(`lua cmd ${l}`));
  const wear = isWatched() ? meta.tithe * 4 : 0;  // 10% wears 0.4 a season; the drift to 55 outweighs it
  for (const p of world.players) {
    if (houseFor(p).wild || houseFor(p).crown) continue;
    const before = favourOf(p.id);
    // Favour drifts back toward the house's own temper, minus the tithe's wear.
    favour[p.id] = clampFavour(before + (restingFavour(p) - before) * 0.03 - wear);
    if (wear) noteFavour(p.id, -wear, "the royal tithe");
    if (before >= 20 && favour[p.id] < 20) {
      record({ turn, kind: "unrest", text: `${houseFor(p).name} speaks openly against the crown. Their loyalty hangs by a thread.` });
    }
  }
  saveFavour();
  // The reign's goal: every great house would answer the banners (35 and up).
  // Marked once in the chronicle when won; lost again when a house falls away.
  const great = world.players.filter((p) => !houseFor(p).wild && !houseFor(p).crown && p.cities > 0);
  const united = great.length > 0 && great.every((p) => favourOf(p.id) >= 35);
  if (united && !meta.united) {
    meta.united = true;
    chron.saveMeta(meta);
    record({ turn, kind: "decree", text: `All ${great.length} great houses stand behind the King. For the first time in a generation the realm answers to one crown, in truth and not in name.` });
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

function greatHouses() {
  return (world?.players ?? []).filter((p) => !houseFor(p).wild && !houseFor(p).crown);
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
  if (outcome === "fallen") { s.score = Math.round(s.score * 0.3); s.verdict = "The realm fell to the dead. No one is left to remember."; }
  s.title = `The King ${epithet(history, outcome, decreesIssued)}`;
  s.outcome = outcome;
  meta.status = "ended";
  meta.score = s.score;
  meta.verdict = s.verdict;
  meta.title = s.title;
  chron.saveMeta(meta);
  chron.addRecord({ id: meta.id, name: meta.name, scenario: meta.scenario, minutes: meta.minutes, turns: world?.turn ?? 0, ended: Date.now(), ...s });
  record({ turn: world?.turn ?? 0, kind: "reign_end", text: `${why} So ends the reign of ${s.title}. ${s.verdict} (Score ${s.score}.)` });
  paused = true;
  send("set timeout 0");
}

// The reign's clock only runs while the realm does.
setInterval(() => {
  if (!meta || paused || meta.status !== "running" || !fc) return;
  meta.elapsedMs += 5000;
  if (meta.minutes > 0 && meta.elapsedMs >= meta.minutes * 60000) endReign("The appointed time has passed. The reign ends.");
  else if (meta.elapsedMs % 30000 === 0) chron.saveMeta(meta);
}, 5000);

function shutdown() {
  if (meta) chron.saveMeta(meta);
  switching = true;
  stopFreeciv().then(() => process.exit(0));
  setTimeout(() => process.exit(0), 8000);
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

// --- HTTP API --------------------------------------------------------------------

function json(res, code, body) {
  res.writeHead(code, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" });
  res.end(JSON.stringify(body));
}

function body(req) {
  return new Promise((resolve) => {
    let b = "";
    req.on("data", (d) => (b += d));
    req.on("end", () => { try { resolve(JSON.parse(b || "{}")); } catch { resolve({}); } });
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
    score: meta.score, verdict: meta.verdict, title: meta.title,
  };
}

http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://x");
  if (req.method === "OPTIONS") return json(res, 204, {});
  if (!meta) return json(res, 503, { error: "no chronicle" });
  if (await mindsRoute(minds, url, req, body, json, res)) return;

  if (url.pathname === "/world") {
    watched(); // the game window polls this every second while open
    if (!world) return json(res, 503, { error: "realm still forming", reign: reignInfo() });
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
        food: x.foodStock, granary: granarySize(c.size), famine: x.hadFamine,
        plagueTurn: x.plagueTurn, celebrating: x.celebrating, disorder: x.disorder,
        building: x.building, buildingKind: x.buildingKind,
        progress: cost ? Math.min(1, x.shieldStock / cost) : 0,
      };
    });
    const units = world.units.map((u) => {
      const x = d?.units[u.id];
      return x ? { ...u, hp: x.hp, activity: x.activity, goto: x.goto, home: x.home } : u;
    });
    const last = history[history.length - 1];
    const crownP = players.find((p) => p.house.crown);
    const crown = { treasury: crownP?.gold ?? 0, tithe: meta.tithe, decrees: DECREES, perSeason: lastSeason.net };
    for (const p of players) {
      p.favour = p.house.wild || p.house.crown ? null : favourOf(p.id);
      p.favourWhy = favourWhy[p.id] ?? [];
      // Whom the house is at odds with, by name: wars, and wars the King has
      // stilled (a commanded peace or a royal match) as truces.
      const lordOf = (pid) => court?.lordOfHouse(pid);
      const stilledWith = (q) => { const a = lordOf(p.id), b = lordOf(q.id); return !!(a && b && court.truce(a.id, b.id)); };
      const rivals = (p.atWarWith ?? []).map((id) => players.find((q) => q.id === id)).filter((q) => q && !q.house.wild);
      // A loyal house (35 and up) isn't waging war on the King: the engine's state
      // between them is old diplomacy, not a cause, so it isn't shown as one.
      const loyalToCrown = (q) => !q.house.crown && (favourOf(q.id) ?? 0) >= 35;
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
    return json(res, 200, { ...world, players, cities, units, turnSeconds, reign: reignInfo(), date: calendar(world.turn), threat, counsel: counsel(players, cities, threat), peace: last?.peace ?? 1, prosperity: last?.pop ?? 0, souls: world.cities.reduce((t, c) => t + soulsOf(c.size), 0), crown, owners: d?.owners ?? [], scenes: scenes.filter((x) => Date.now() - x.at < 90000) });
  }
  if (url.pathname === "/map") {
    const map = chron.readJson(path.join(P.state, "map.json"));
    return map ? json(res, 200, { ...map, land: meta?.land ?? null }) : json(res, 503, { error: "map not ready" });
  }
  if (url.pathname === "/chronicle") {
    const since = Number(url.searchParams.get("since") || 0);
    return json(res, 200, inCrowns(chronicle.filter((e) => e.seq > since).slice(-200)));
  }
  if (url.pathname === "/ledger") return json(res, 200, history.slice(-400).map((r) => r.souls !== undefined ? r : { ...r, souls: r.pop * 600, houses: Object.fromEntries(Object.entries(r.houses).map(([k, h]) => [k, { ...h, souls: h.pop * 600 }])) }));
  if (url.pathname === "/records") return json(res, 200, chron.records().sort((a, b) => b.score - a.score));
  if (url.pathname === "/scenarios") {
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
  }
  if (url.pathname === "/chronicles/options") return json(res, 200, { defaults: chron.OPTION_DEFAULTS, houses: Object.keys(chron.HOUSE_NATIONS) });
  if (url.pathname === "/chronicles" && req.method === "GET") {
    return json(res, 200, { active: meta.id, list: chron.list() });
  }
  if (url.pathname === "/chronicles" && req.method === "POST") {
    const b = await body(req);
    const scenario = ["random", "aldmere", "aldmere_fresh"].includes(b.scenario) ? b.scenario : "aldmere";
    const m = chron.create({ name: String(b.name || "A New Realm").slice(0, 40), scenario, minutes: b.minutes, pace: b.options?.pace ?? turnSeconds, fate: b.fate, wealth: b.wealth, mood: b.mood, options: b.options });
    switchTo(m.id);
    return json(res, 200, m);
  }
  if (url.pathname === "/chronicles/open" && req.method === "POST") {
    const { id } = await body(req);
    if (!chron.list().some((c) => c.id === id)) return json(res, 404, { error: "no such chronicle" });
    switchTo(id);
    return json(res, 200, { ok: true });
  }
  if (url.pathname === "/reign/end" && req.method === "POST") {
    endReign("The King lays down the crown.");
    return json(res, 200, reignInfo());
  }
  if (url.pathname === "/reign/continue" && req.method === "POST") {
    // A timed reign has ended and been scored; the King rules on, with no clock,
    // in the same realm. The score stands in the records as it was.
    if (meta.status !== "ended") return json(res, 400, { error: "this reign has not ended" });
    meta.status = "running";
    meta.minutes = 0;
    paused = false;
    chron.saveMeta(meta);
    send(`set timeout ${turnSeconds}`);
    record({ turn: world?.turn ?? 0, kind: "decree", text: "The King rules on." });
    return json(res, 200, reignInfo());
  }
  if ((url.pathname === "/pause" || url.pathname === "/resume") && req.method === "POST") {
    if (meta.status !== "running") return json(res, 400, { error: "this reign has ended" });
    paused = url.pathname === "/pause";
    send(`set timeout ${paused ? 0 : turnSeconds}`);
    return json(res, 200, reignInfo());
  }
  if (url.pathname === "/reign/options") {
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
      if (!paused) send(`set timeout ${turnSeconds}`);
    }
    meta.options.pace = meta.pace ?? meta.options.pace;
    chron.saveMeta(meta);
    // Freeciv's own dials, applied now.
    send(`set disasters ${{ none: 0, gentle: 5, normal: 25, cruel: 70 }[meta.options.disasters]}`);
    send(`set barbarians ${{ none: "disabled", normal: "normal", hordes: "hordes" }[meta.options.raiders]}`);
    return json(res, 200, { options: meta.options, live: LIVE });
  }
  if (url.pathname === "/ai") {
    // What the local model can do right now, for the settings page.
    return json(res, 200, await aiStatus());
  }
  if (url.pathname === "/speed" && req.method === "POST") {
    const { seconds } = await body(req);
    turnSeconds = Math.max(1, Math.min(600, Number(seconds) || 90));
    meta.pace = turnSeconds;
    chron.saveMeta(meta);
    if (!paused) send(`set timeout ${turnSeconds}`);
    return json(res, 200, { turnSeconds });
  }
  if (url.pathname === "/decree" && req.method === "POST") {
    decreesIssued++;
    const cmd = await body(req);
    if (meta.status !== "running") return json(res, 400, { error: "this reign has ended" });
    // A royal match needs a pair: an unwed son or daughter of age from each house,
    // one of each, chosen before a crown is spent. Nobody is wed twice.
    let pair = null;
    if (cmd.action === "marriage" && court) {
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
    const result = decree({ ...cmd, favourOf, usurper: stakes?.s.usurper, seat: stakes?.s.seat }, world);
    if (result.error) return json(res, 400, result);
    if (result.endUsurper && stakes) { stakes.s.usurper.stage = "none"; stakes.save(); }
    if (result.relieved != null) { (meta.relieved ??= {})[result.relieved] = world.turn ?? 0; chron.saveMeta(meta); }
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
    // Spend now, so a second decree before the next snapshot can't overdraw the treasury.
    const crownNow = world.players.find((p) => houseFor(p).crown);
    if (crownNow) crownNow.gold -= result.cost;
    // The result card says what the order cost and whose favour moved, so the
    // King learns the price of his word.
    const effects = shiftAndTell(result.favour, { gift: "a gift of crowns", feast: "a feast in their honour", relief: "grain from the crown", build: "a building paid by the crown", grant: "a town granted or taken", banners: "the King's banners: answered or refused", marriage: "a royal match", peace: "the King's peace", back: "the King took a side", settle: "the King's peace, kept by another house", buyoff: "the King bought off the pretender", ward: "their heir taken as the King's ward" }[cmd.action] ?? "a royal decree", result.cost);
    const seat = world.cities.find((c) => c.owner === crownNow?.id && c.capital);
    const target = world.cities.find((c) => c.id === Number(cmd.city));
    if (seat && target && (cmd.action === "relief" || cmd.action === "gift")) scene(cmd.action === "relief" ? "grain" : "tribute", { x: seat.x, y: seat.y, tx: target.x, ty: target.y, city: target.id });
    // Every decree is seen where it lands: a feast at the seat, a town changing
    // hands, the King's rider carrying the crown's purse for a building.
    if (seat && cmd.action === "feast") scene("feast", { x: seat.x, y: seat.y, city: seat.id, owner: crownNow.id });
    if (target && cmd.action === "grant") scene("handover", { x: target.x, y: target.y, city: target.id, from: target.owner, to: Number(cmd.to) });
    if (seat && target && cmd.action === "build") scene("rider", { x: seat.x, y: seat.y, tx: target.x, ty: target.y, city: target.id, label: "The crown's purse for a new building" });
    if (seat && cmd.action === "levy") {
      // The host marches for the town the levy was raised for, else toward the
      // nearest foreign army inside the crown's lands, else down the road a way.
      const foes = world.units.filter((u) => u.owner !== crownNow.id && !["Workers", "Settlers", "Migrants", "Explorer", "Caravan", "Diplomat"].includes(u.type));
      const near = foes.sort((a, b) => Math.hypot(a.x - seat.x, a.y - seat.y) - Math.hypot(b.x - seat.x, b.y - seat.y))[0];
      const goal = target && target.id !== seat.id ? target : near && Math.hypot(near.x - seat.x, near.y - seat.y) < 12 ? near : { x: seat.x + 3, y: seat.y + 2 };
      scene("muster", { x: seat.x, y: seat.y, tx: goal.x, ty: goal.y, city: seat.id });
    }
    // A commanded peace: the two lords' houses keep a truce (no raids, no plots).
    if (result.truce && court) {
      const [a, b] = result.truce.map((pid) => court.lordOfHouse(pid));
      if (a && b) {
        court.truces ??= {};
        court.truces[[a.id, b.id].sort().join(":")] = (world?.turn ?? 0) + 16;
        court.remember(a.id, `The King commanded peace with ${b.house}, and I bowed to it.`);
        court.remember(b.id, `The King commanded peace with ${a.house}, and I bowed to it.`);
        court.saveCourt?.();
      }
    }
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
        court.truces ??= {};
        court.truces[[a.id, b.id].sort().join(":")] = (world?.turn ?? 0) + 24;
        court.remember(a.id, `By the King's word, ${ka.name} is to wed ${kb.name} of ${b.house}.`);
        court.remember(b.id, `By the King's word, ${kb.name} is to wed ${ka.name} of ${a.house}.`);
        result.text = `By the King's word, ${ka.name} of ${a.house} will wed ${kb.name} of ${b.house}. The two houses are bound by blood; while the bond holds, neither will raise a hand against the other.`;
        court.saveCourt?.();
      }
    }
    record({ turn: world?.turn ?? 0, kind: "decree", text: result.text, city: cmd.city });
    setTimeout(snapshot, 600);
    return json(res, 200, { ok: true, text: crowns(result.text) + (effects ? `\n${effects}` : "") });
  }
  if (url.pathname === "/scene/arrived" && req.method === "POST") {
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
  }
  if (url.pathname === "/usage") return json(res, 200, usageToday());
  if (url.pathname === "/mood" && req.method === "GET") return json(res, 200, court.decrees);
  if (url.pathname === "/mood/revoke" && req.method === "POST") {
    const { id } = await body(req);
    court.revoke(id);
    return json(res, 200, court.decrees);
  }
  if (url.pathname === "/mood" && req.method === "POST") {
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
  }
  if (url.pathname === "/court" && req.method === "GET") return json(res, 200, inCrowns(court.open()));
  if (url.pathname === "/hear" && req.method === "POST") {
    // What the King said into the microphone (a WAV), as words, by Off Grid's Whisper.
    const wav = await bytes(req);
    if (wav.length < 1000) return json(res, 400, { error: "nothing was heard" });
    const text = await transcribe(wav, meta.options?.language);
    return text ? json(res, 200, { text }) : json(res, 503, { error: "Your words were lost. (The local speech model isn't running.)" });
  }
  if (url.pathname === "/voice" && req.method === "POST") {
    // Someone's words, spoken aloud by Off Grid's Kokoro: a voice of their own,
    // in the realm's language. WAV bytes; cached, so a line is only made once.
    const { text, who } = await body(req);
    const line = String(text ?? "").trim().slice(0, 600);
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
  }
  if (url.pathname === "/court/answer" && req.method === "POST") {
    const { id, option } = await body(req);
    const out = rule(id, option);
    return json(res, out.error ? 400 : 200, out);
  }
  if (url.pathname === "/court/say" && req.method === "POST") {
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
  }
  if (url.pathname === "/house") {
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
        const loyal = (id) => id !== crownId && favourOf(id) >= 35;
        const foes = (d?.atWarWith ?? []).filter(great).filter((q) => !((q === crownId && loyal(pid)) || (pid === crownId && loyal(q))));
        return { wars: foes.filter((q) => !stilled(q)).map(nameOf), truces: foes.filter(stilled).map(nameOf) };
      })(),
      allies: (d?.allies ?? []).filter((id) => id !== pid && great(id)).map(nameOf),
    });
  }
  if (url.pathname === "/lore") {
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
    const houses = (world?.players ?? []).filter((p) => p.alive !== false && !houseFor(p).wild).map((p) => {
      const h = houseFor(p);
      const seat = world.cities.find((c) => c.owner === p.id && c.capital);
      const people = court.alive().filter((c) => c.playerId === p.id && c.rank in RANK)
        .sort((a, c) => RANK[a.rank] - RANK[c.rank] || (c.created ? 1 : 0) - (a.created ? 1 : 0) || c.age - a.age);
      // The lord, the lord's spouse and heir, then the leading bannermen.
      const lord = people.find((c) => c.rank === "lord");
      const family = lord ? people.filter((c) => c.id === lord.spouse || (c.rank === "heir" && c.parents?.includes(lord.id))) : [];
      const notables = [...(lord ? [lord] : []), ...family, ...people.filter((c) => c.rank === "bannerman").slice(0, 4)];
      return {
        id: p.id, name: h.name, words: h.words, color: h.color, sigil: h.sigil, crown: !!h.crown,
        seat: seat ? cityName(seat.id) : null, towns: world.cities.filter((c) => c.owner === p.id).length,
        favour: h.crown ? null : favourOf(p.id), lore: b.houses[h.name] ?? rebel(h.name),
        notables: notables.map((c) => ({
          id: c.id, name: c.name, surname: c.surname ?? null, gender: c.gender, age: c.age, rank: c.rank, traits: c.traits,
          goal: c.goals?.[0]?.text ?? null, role: c.role ? ROLES[c.role]?.title : null,
          seat: c.seat != null ? cityName(c.seat) : null, loyalty: c.loyalty,
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
      houses.push({ id: -100 - n++, name: h.name, words: h.words, color: h.color, sigil: h.sigil, crown: false, fallen: true,
        seat: null, towns: 0, favour: null, lore: b.houses[h.name] ?? null, notables: [] });
    }
    // The lesser families sworn to the great houses: one entry each, with
    // every town a branch of it holds, under which liege, and who heads it.
    const lesser = {};
    const held = (c) => c.seat != null && (world?.cities ?? []).some((t) => t.id === c.seat && t.owner === c.playerId);
    for (const c of court.alive().filter((x) => x.rank === "bannerman" && FAMILIES[x.surname])) {
      const p = world?.players.find((x) => x.id === c.playerId);
      if (!p || p.alive === false) continue;
      const h = houseFor(p);
      const f = (lesser[c.surname] ??= { surname: c.surname, ...FAMILIES[c.surname], branches: [] });
      f.branches.push({
        house: h.name, house_id: p.id, color: h.color, sigil: h.sigil, crown: !!h.crown,
        // A seat lost to another house (or razed) is told as lost, not held.
        seat: held(c) ? cityName(c.seat) : null, lost: c.seat != null && !held(c) ? cityName(c.seat) : null,
        head: { id: c.id, name: c.name, gender: c.gender, age: c.age, loyalty: c.loyalty, traits: c.traits, role: c.role ? ROLES[c.role]?.title : null },
      });
    }
    const families = Object.values(lesser).sort((a, c) => c.branches.length - a.branches.length || a.surname.localeCompare(c.surname));
    return json(res, 200, { intro: b.intro, crown: b.crown, faults: b.faults, fate: b.fate, tone: b.tone, houses, lesser: LESSER, families });
  }
  if (url.pathname === "/person" && req.method !== "POST") {
    // One person up close, for the character view: who they are and what they remember.
    const c = court.people[url.searchParams.get("id")] ?? court.alive().find((x) => x.name === url.searchParams.get("name"));
    if (!c) return json(res, 404, { error: "no such person" });
    return json(res, 200, {
      id: c.id, name: c.name, gender: c.gender, age: c.age, alive: c.alive, rank: c.rank, house: c.house,
      traits: c.traits, goals: (c.goals ?? []).map((g) => g.text), goal: c.goals?.[0]?.kind ?? null, role_key: c.role ?? null, loyalty: c.loyalty,
      seat: c.seat != null ? cityName(c.seat) : null, role: c.role ? ROLES[c.role]?.title : null,
      memories: [...new Set(c.memories ?? [])].slice(-6), backstory: c.backstory ?? null,
    });
  }
  if (url.pathname === "/characters/options") return json(res, 200, { roles: Object.fromEntries(Object.entries(ROLES).map(([k, v]) => [k, v.title])), goals: GOALS, traits: TRAITS.filter((t) => t !== "lustful") });
  if (url.pathname === "/person/fall" && req.method === "POST") {
    // Someone the King walked as fell in a fight: a real death, and their heir inherits.
    const { id, how } = await body(req);
    const c = court.people[String(id)];
    if (!c || !c.alive || !world) return json(res, 400, { error: "no such person" });
    if (how) court.remember(c.id, String(how).slice(0, 200));
    court.die(c, world.turn, world);
    return json(res, 200, { ok: true });
  }
  if (url.pathname === "/person" && req.method === "POST") {
    const spec = await body(req);
    const out = court.edit(String(spec.id), spec, world);
    return json(res, out.error ? 400 : 200, out);
  }
  if (url.pathname === "/characters" && req.method === "POST") {
    if (!world) return json(res, 503, { error: "the realm is still forming" });
    const out = court.create(await body(req), world);
    return json(res, out.error ? 400 : 200, out);
  }
  if (url.pathname.startsWith("/minds/") && chatter) {
    const out = await chatter.route(url, req, body);
    if (out) return json(res, ...out);
  }
  if (url.pathname === "/townsfolk") {
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
  }
  if (url.pathname === "/town/people") {
    // The named people of a town, for someone walking it: its lord or lady, and
    // the bannermen and heirs seated there.
    // At a house's seat its whole household gathers: the heir and the bannermen too.
    const id = Number(url.searchParams.get("city"));
    const town = world?.cities.find((c) => c.id === id);
    const here = court.alive().filter((c) => ["lord", "heir", "bannerman"].includes(c.rank)
      && (c.seat === id || (town?.capital && c.playerId === town.owner && c.rank !== "lord")));
    return json(res, 200, here.slice(0, 6).map((c) => ({ id: c.id, name: c.name, gender: c.gender, rank: c.rank, house: c.house })));
  }
  if (url.pathname === "/talk" && req.method === "POST") {
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
  }
  if (url.pathname === "/arcs" && req.method === "GET") return json(res, 200, inCrowns(arcs.view(arcCtx())));
  if (url.pathname === "/arcs/templates") return json(res, 200, arcTemplates().map((t) => ({ id: t.id, file: t.file, name: t.name, title: t.title, about: t.about, roles: Object.keys(t.roles ?? {}), beats: (t.beats ?? []).length, problems: t.problems })));
  // Fast-forward: n seasons of the realm's stories, against the live realm.
  if (url.pathname === "/arcs/tick" && req.method === "POST") {
    const b = await body(req);
    const ran = await runArcs(Math.max(1, Math.min(60, Number(b.n) || 1)), b.start !== false);
    return json(res, ran ? 200 : 409, ran ? inCrowns(arcs.view(arcCtx())) : { error: "the stories are already moving" });
  }
  // Begin one kind of story now, if the realm has the people for it.
  if (url.pathname === "/arcs/start" && req.method === "POST") {
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
  }
  // The King's own story: an arc file dropped in as JSON, or told in words
  // and shaped by the model from the closest existing arc.
  if (url.pathname === "/arcs/write" && req.method === "POST") {
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
    return json(res, 200, { ok: true, file: path.relative(DIR, file), arc });
  }
  if (url.pathname === "/lord") return json(res, 200, court.summary(Number(url.searchParams.get("city"))) ?? {});
  if (url.pathname === "/season" && req.method === "POST") {
    await runSeason();
    return json(res, 200, { ok: true });
  }
  if (url.pathname === "/tithe" && req.method === "POST") {
    const { rate } = await body(req);
    meta.tithe = Math.max(0, Math.min(0.4, Number(rate) || 0));
    chron.saveMeta(meta);
    return json(res, 200, { tithe: meta.tithe });
  }
  if (url.pathname === "/god" && req.method === "POST") {
    const cmd = await body(req);
    const result = godCommand(cmd, world);
    if (result.error) return json(res, 400, result);
    result.lua.forEach((l) => send(`lua cmd ${l}`));
    record({ turn: world?.turn ?? 0, kind: "god", text: result.text, city: cmd.city });
    setTimeout(snapshot, 600);
    return json(res, 200, { ok: true, text: crowns(result.text) });
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
