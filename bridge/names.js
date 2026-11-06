// Names the player gives: a house or a person shown by another name. Inside, the
// realm keeps its own names (House Wolfholt, Constance) as fixed keys; on the way
// out every word of text is shown in the player's names, and on the way in their
// names are turned back. So a rename reaches every reign, old chronicle lines
// included, and nothing that is found by name (paintings, banners, the world
// bible) ever loses its way. Kept on the player's Mac only (HOME/names.json).
import fs from "fs";
import path from "path";
import { HOME } from "./chronicles.js";

const FILE = path.join(HOME, "names.json");
let names = {};  // inner word -> shown word(s): { "Wolfholt": "Blackwater" }
let out = null;  // [RegExp, shown] pairs, longest first
let back = null;

function load() {
  try { names = JSON.parse(fs.readFileSync(FILE, "utf8")); } catch { names = {}; }
  build();
}

function build() {
  const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pairs = Object.entries(names).filter(([a, b]) => a && b && a !== b);
  pairs.sort((x, y) => y[0].length - x[0].length);
  out = pairs.map(([a, b]) => [new RegExp(`\\b${esc(a)}\\b`, "g"), b]);
  back = pairs.slice().sort((x, y) => y[1].length - x[1].length).map(([a, b]) => [new RegExp(`\\b${esc(b)}\\b`, "g"), a]);
}

export function all() {
  return { ...names };
}

// Give a word a new name (or its own back, with an empty `to`).
export function rename(from, to) {
  from = String(from ?? "").trim();
  to = String(to ?? "").trim().replace(/\s+/g, " ").slice(0, 40);
  if (!/^[A-Za-z'’-]{2,40}$/.test(from)) return { error: "name a single word to rename, like Wolfholt" };
  if (to && !/^[A-Za-z'’ -]{2,40}$/.test(to)) return { error: "a name of letters only, please" };
  if (!to || to === from) delete names[from];
  else names[from] = to;
  fs.mkdirSync(path.dirname(FILE), { recursive: true });
  fs.writeFileSync(FILE, JSON.stringify(names, null, 1));
  build();
  return { names: all() };
}

export function active() {
  return out && out.length > 0;
}

export function shown(text) {
  if (!active() || typeof text !== "string") return text;
  for (const [re, b] of out) text = text.replace(re, b);
  return text;
}

export function inner(text) {
  if (!active() || typeof text !== "string") return text;
  for (const [re, a] of back) text = text.replace(re, a);
  return text;
}

// Every string in a reply, shown in the player's names; `key` fields (what the
// game finds art and lore by) are left as they are.
export function showAll(v, field = "") {
  if (!active()) return v;
  if (typeof v === "string") return field === "key" ? v : shown(v);
  if (Array.isArray(v)) return v.map((x) => showAll(x));
  if (v && typeof v === "object") {
    const o = {};
    for (const [k, x] of Object.entries(v)) o[k] = showAll(x, k);
    return o;
  }
  return v;
}

export function innerAll(v) {
  if (!active()) return v;
  if (typeof v === "string") return inner(v);
  if (Array.isArray(v)) return v.map(innerAll);
  if (v && typeof v === "object") {
    const o = {};
    for (const [k, x] of Object.entries(v)) o[k] = innerAll(x);
    return o;
  }
  return v;
}

load();
