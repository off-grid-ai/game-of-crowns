// Several wordings per result (PLAN.md Phase 1, "kill the repeats"; Reigns' fresh deck): the one
// picker. A result with more than one wording (data/results.json by key, or a dilemma's text written
// as a list) gets one the realm hasn't heard lately: never one of the last half used for that key.
// Each caller fills its own names in; {name} placeholders are filled here for data/results.json.
import fs from "node:fs";

const RESULTS = JSON.parse(fs.readFileSync(new URL("./data/results.json", import.meta.url), "utf8"));
const used = new Map();  // key -> the wordings used lately (indices), oldest first

// One of list's wordings, not one used lately for this key (a plain string passes through).
export function pick(key, list) {
  if (!Array.isArray(list)) return list;
  if (list.length < 2) return list[0];
  const recent = used.get(key) ?? [];
  const fresh = list.map((_, i) => i).filter((i) => !recent.includes(i));
  const i = fresh[Math.floor(Math.random() * fresh.length)];
  used.set(key, [...recent, i].slice(-Math.ceil(list.length / 2)));  // the last half kept out: varied, never close together
  return list[i];
}

// Wordings the local model added (reword.js), by key: drawn alongside the written ones.
const ADDED = {};
export const keys = () => Object.keys(RESULTS).filter((k) => k !== "_");
export const written = (key) => RESULTS[key] ?? [];
export const added = (key) => ADDED[key] ?? [];
export function add(key, text) { (ADDED[key] ??= []).push(text); }

// The result's line: one of data/results.json's wordings for key, or one the model added (fallback when
// it has none), its {names} filled.
export function say(key, vars, fallback) {
  const t = pick(key, [...(RESULTS[key] ?? [fallback]), ...(ADDED[key] ?? [])]);
  return String(t).replace(/\{(\w+)\}/g, (m, k) => (vars[k] ?? m));
}
