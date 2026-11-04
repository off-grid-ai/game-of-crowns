// Chronicles: each simulation lives in its own folder with its own Freeciv saves,
// chronicle, ledger history and generated world, so many realms can be kept,
// switched between and scored.
//
//   chronicles/<id>/meta.json        name, scenario, length, status, score
//   chronicles/<id>/saves/           Freeciv's own saves (the authoritative state)
//   chronicles/<id>/state/           world/map snapshots, chronicle, history, scars
//   chronicles/<id>/world_setup.lua  the generated continent and house seats
//   chronicles/<id>/data/nation/     this realm's house temperaments
//   chronicles/<id>/realm.serv       the Freeciv start script

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const DIR = path.dirname(fileURLToPath(import.meta.url));
// Where realms are kept: beside the bridge when run from the repo, in
// ~/Library/Application Support/Game of Crowns when run from the app (GOC_HOME).
export const HOME = process.env.GOC_HOME || DIR;
export const ROOT = path.join(HOME, "chronicles");
const ACTIVE = path.join(ROOT, "active");
const RECORDS = path.join(HOME, "records.json");

fs.mkdirSync(ROOT, { recursive: true });

export function readJson(file, fallback = null) {
  try { return JSON.parse(fs.readFileSync(file, "utf8")); } catch { return fallback; }
}

export function paths(id) {
  const base = path.join(ROOT, id);
  return {
    base, meta: path.join(base, "meta.json"), saves: path.join(base, "saves"), state: path.join(base, "state"),
    serv: path.join(base, "realm.serv"), setup: path.join(base, "world_setup.lua"), data: path.join(base, "data"),
  };
}

export function list() {
  return fs.readdirSync(ROOT)
    .filter((d) => fs.existsSync(path.join(ROOT, d, "meta.json")))
    .map((d) => readJson(path.join(ROOT, d, "meta.json")))
    .sort((a, b) => b.created - a.created);
}

export function activeId() {
  try { return fs.readFileSync(ACTIVE, "utf8").trim() || null; } catch { return null; }
}

export function setActive(id) {
  fs.writeFileSync(ACTIVE, id);
}

export function saveMeta(meta) {
  fs.writeFileSync(paths(meta.id).meta, JSON.stringify(meta, null, 1));
}

export function records() {
  return readJson(RECORDS, []);
}

export function addRecord(entry) {
  const all = records();
  all.push(entry);
  fs.writeFileSync(RECORDS, JSON.stringify(all, null, 1));
}

// Everything the King chooses when a chronicle begins, with its default. Each
// one drives the simulation: Freeciv's settings, the houses' AI traits, the
// stakes, the court, or a one-time act when the realm first stirs.
export const OPTION_DEFAULTS = {
  pace: 90,              // seconds a season lasts: six minutes a year, so seasons and lives read
  disasters: "normal",   // floods, fires, famine: none | gentle | normal | cruel
  raiders: "normal",     // barbarians from the wilds: none | normal | hordes
  dead: "normal",        // the dead beyond the wall: off | late | normal | soon
  usurper: true,         // can a disaffected house claim the throne?
  temper: "mixed",       // the great houses: peaceful | mixed | warlike
  cunning: "hard",       // how well the houses' AI plays: easy | normal | hard
  houseWealth: "asis",   // poor | asis | rich
  trust: "wary",         // the houses' faith in the crown at the start: loyal | wary | resentful
  host: "standard",      // the royal host at the start: small | standard | strong
  petitions: "normal",   // lords at court each season: rare | normal | often
  intrigue: "normal",    // bold moves by the court each season: quiet | normal | scheming
  skip: [],              // great houses left out of a fresh realm (by house name)
  language: "en",        // the tongue people speak to you in: en | de | es | fr | it | pt | hi
};
const CHOICES = {
  disasters: ["none", "gentle", "normal", "cruel"], raiders: ["none", "normal", "hordes"], dead: ["off", "late", "normal", "soon"],
  temper: ["peaceful", "mixed", "warlike"], cunning: ["easy", "normal", "hard"], houseWealth: ["poor", "asis", "rich"],
  trust: ["loyal", "wary", "resentful"], host: ["small", "standard", "strong"], petitions: ["rare", "normal", "often"], intrigue: ["quiet", "normal", "scheming"],
  language: ["en", "de", "es", "fr", "it", "pt", "hi"],
};
export const HOUSE_NATIONS = { Wolfholt: "scottish", Goldcrest: "english", Ironreach: "norwegian", Thornvale: "french", Stormhold: "welsh", Sunspire: "castilian", Highfell: "irish" };

// The old single "fate" choice still works: it presets the new ones.
export function cleanOptions(o = {}, fate) {
  const preset = { gentle: { disasters: "gentle", raiders: "none", dead: "late" }, cruel: { disasters: "cruel", raiders: "hordes", dead: "soon" } }[fate] ?? {};
  const out = { ...OPTION_DEFAULTS, ...preset };
  for (const [k, v] of Object.entries(o ?? {})) {
    if (k in CHOICES && CHOICES[k].includes(v)) out[k] = v;
  }
  out.pace = 90;  // one pace for every realm
  out.usurper = o?.usurper === undefined ? true : Boolean(o.usurper);
  out.skip = (Array.isArray(o?.skip) ? o.skip : []).filter((h) => h in HOUSE_NATIONS).slice(0, 5);
  return out;
}

// Freeciv's own settings for the chosen fate, AI skill and pace.
function servFor(text, opt) {
  return text
    .replace(/^set timeout \d+$/m, `set timeout ${opt.pace}`)
    .replace(/^set disasters \d+$/m, `set disasters ${{ none: 0, gentle: 5, normal: 25, cruel: 70 }[opt.disasters]}`)
    .replace(/^set barbarians \w+$/m, `set barbarians ${{ none: "disabled", normal: "normal", hordes: "hordes" }[opt.raiders]}`)
    .replace(/^(hard|normal|easy|novice|cheating)$/m, opt.cunning);
}

// House temperaments: Aldmere's from the world bible, or rolled for random realms.
const TEMPERAMENT = {
  scottish: [70, 30, 35, 70], english: [50, 90, 25, 60], norwegian: [60, 20, 95, 25], french: [55, 75, 30, 85],
  welsh: [55, 30, 85, 40], castilian: [40, 50, 40, 80], irish: [30, 40, 15, 75], norman: [40, 50, 30, 60],
};

function writeNations(dir, random, temper = "mixed") {
  fs.mkdirSync(dir, { recursive: true });
  for (const [nation, base] of Object.entries(TEMPERAMENT)) {
    const vals = random && nation !== "norman" ? base.map(() => 10 + Math.floor(Math.random() * 85)) : [...base];
    // The realm's temper bends every house's aggression (index 2) the same way.
    if (nation !== "norman") vals[2] = Math.round(Math.max(5, Math.min(95, { peaceful: vals[2] * 0.35, mixed: vals[2], warlike: 55 + vals[2] * 0.45 }[temper])));
    const src = fs.readFileSync(path.join(DIR, "data", "nation", `${nation}.ruleset`), "utf8");
    let i = 0;
    const out = src.replace(/^(trait_(expansionist|trader|aggressive|builder)_(min|max|default)) = \d+$/gm, (_m, key, trait) => {
      const v = vals[["expansionist", "trader", "aggressive", "builder"].indexOf(trait)];
      i++;
      return `${key} = ${v}`;
    });
    fs.writeFileSync(path.join(dir, `${nation}.ruleset`), out);
  }
}

function slug(name) {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 32) || "realm";
}

// Creates a chronicle folder ready for Freeciv to start.
// A realm already some years into its history (towns grown, roads built, the
// court's first quarrels done), captured once with tools/make-baseline.sh.
// New Aldmere chronicles begin from it instead of from the founding.
export const BASELINE = path.join(DIR, "baseline", "aldmere");

function fromBaseline(p) {
  for (const part of ["saves", "state", "characters", "data"]) {
    const src = path.join(BASELINE, part);
    if (fs.existsSync(src)) fs.cpSync(src, path.join(p.base, part), { recursive: true });
  }
  for (const f of ["realm.serv", "world_setup.lua", "court.json", "mood.json"]) {
    const src = path.join(BASELINE, f);
    if (fs.existsSync(src)) fs.copyFileSync(src, path.join(p.base, f));
  }
  return readJson(path.join(BASELINE, "baseline.json"), {});
}

export function create({ name, scenario = "aldmere", minutes = 0, pace, fate = "normal", wealth = "comfortable", mood = "", options }) {
  const id = `${slug(name)}-${Date.now().toString(36)}`;
  const p = paths(id);
  const opt = cleanOptions({ pace, ...options }, fate);
  pace = opt.pace;
  if (scenario === "aldmere" && fs.existsSync(path.join(BASELINE, "saves"))) {
    fs.mkdirSync(p.base, { recursive: true });
    const base = fromBaseline(p);
    // The baseline's history is shared; the hardships ahead are the player's choice.
    if (fs.existsSync(p.serv)) fs.writeFileSync(p.serv, servFor(fs.readFileSync(p.serv, "utf8"), opt));
    writeNations(path.join(p.data, "nation"), false, opt.temper);
    const meta = {
      id, name, scenario, seed: 1066, land: base.land ?? null, minutes: Number(minutes) || 0, pace, created: Date.now(), fate, wealth, options: opt,
      openingMood: String(mood || "").slice(0, 300), elapsedMs: 0, status: "running", score: null, verdict: null, fromBaseline: base.turn ?? true,
    };
    saveMeta(meta);
    return meta;
  }
  fs.mkdirSync(p.saves, { recursive: true });
  fs.mkdirSync(p.state, { recursive: true });
  const random = scenario === "random";
  scenario = random ? "random" : "aldmere";
  const seed = random ? Math.floor(Math.random() * 1e6) : 1066;
  // The realm's own continent comes from an Azgaar map (tools/azgaar_world.py);
  // a random realm is still drawn by worldgen.py.
  let land = null;
  if (random) {
    execFileSync("python3", [path.join(DIR, "tools", "worldgen.py"), "--out", p.setup, "--seed", String(seed), "--random"]);
  } else {
    fs.copyFileSync(path.join(DIR, "lua", "world_setup_azgaar.lua"), p.setup);
    land = { file: path.join(DIR, "data", "belia-land.f32"), w: 896, h: 1408, perUnit: 4 };
  }
  const [, mapW, mapH] = fs.readFileSync(p.setup, "utf8").match(/local W, H = (\d+), (\d+)/);
  writeNations(path.join(p.data, "nation"), random, opt.temper);
  // The crown's starting treasury.
  const gold = { poor: 150, comfortable: 500, rich: 1500 }[wealth] ?? 500;
  fs.writeFileSync(p.setup, fs.readFileSync(p.setup, "utf8").replace("edit.change_gold(p, 500)", `edit.change_gold(p, ${gold})`));
  let serv = fs.readFileSync(path.join(DIR, "realm.serv"), "utf8")
    .replace("lua file lua/world_setup.lua", `lua file ${p.setup}`)
    .replace("lua file lua/events.lua", `lua file ${path.join(DIR, "lua", "events.lua")}`)
    .replace(/^set xsize \d+$/m, `set xsize ${mapW}`)
    .replace(/^set ysize \d+$/m, `set ysize ${mapH}`);
  serv = servFor(serv, opt);
  // Houses left out never take a seat: no player, so the founding passes them by.
  for (const h of opt.skip) serv = serv.replace(new RegExp(`^(create|playernation) ${h}\\b.*\n`, "gm"), "");
  fs.writeFileSync(p.serv, serv);
  const meta = {
    id, name, scenario, seed, land, minutes: Number(minutes) || 0, pace, created: Date.now(), fate, wealth, options: opt, openingMood: String(mood || "").slice(0, 300),
    elapsedMs: 0, status: "running", score: null, verdict: null,
  };
  saveMeta(meta);
  return meta;
}

// One-time move of the original single realm (bridge/saves + bridge/state) into a chronicle.
export function adoptLegacy() {
  const legacySaves = path.join(DIR, "saves");
  if (list().length || !fs.existsSync(legacySaves) || !fs.readdirSync(legacySaves).some((f) => f.startsWith("realm"))) return null;
  const id = `aldmere-i-${Date.now().toString(36)}`;
  const p = paths(id);
  fs.mkdirSync(p.base, { recursive: true });
  fs.renameSync(legacySaves, p.saves);
  fs.renameSync(path.join(DIR, "state"), p.state);
  fs.copyFileSync(path.join(DIR, "lua", "world_setup.lua"), p.setup);
  fs.cpSync(path.join(DIR, "data", "nation"), path.join(p.data, "nation"), { recursive: true });
  fs.writeFileSync(p.serv, fs.readFileSync(path.join(DIR, "realm.serv"), "utf8"));
  const meta = {
    id, name: "Aldmere I", scenario: "aldmere", seed: 1066, minutes: 0, pace: 90, created: Date.now(),
    elapsedMs: 0, status: "running", score: null, verdict: null,
  };
  saveMeta(meta);
  setActive(id);
  return meta;
}
