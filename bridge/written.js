// The starting cast as the player has rewritten it from the menu's Lore: their
// story, what they remember, their nature and their loyalty. Kept on the
// player's Mac only (HOME/written.json); laid over the book as written wherever
// it's read, and over each new chronicle's cast as it's copied from the baseline.
import fs from "fs";
import path from "path";
import { HOME } from "./chronicles.js";
import { TRAITS } from "./characters.js";

let edits = null;  // id -> { backstory?, memories?, traits?, loyalty? }
const file = () => path.join(HOME, "written.json");

function load() {
  if (edits) return edits;
  try { edits = JSON.parse(fs.readFileSync(file(), "utf8")); } catch { edits = {}; }
  return edits;
}

// One person rewritten; only what's given changes.
export function set(id, spec) {
  if (!/^c\d+$/.test(String(id))) return { error: "no such person" };
  const e = (load()[id] ??= {});
  if (spec.backstory != null) e.backstory = String(spec.backstory).trim().slice(0, 300);
  if (Array.isArray(spec.memories)) e.memories = spec.memories.map((m) => String(m).trim().slice(0, 200)).filter(Boolean).slice(0, 8);
  if (Array.isArray(spec.traits)) e.traits = spec.traits.filter((t) => TRAITS.includes(t)).slice(0, 4);
  if (spec.loyalty != null) e.loyalty = Math.max(0, Math.min(100, Math.round(Number(spec.loyalty) || 0)));
  fs.mkdirSync(path.dirname(file()), { recursive: true });
  fs.writeFileSync(file(), JSON.stringify(edits, null, 1));
  return { ok: true, person: e };
}

// A starting character with the player's rewrites laid over it.
export function apply(c) {
  const e = load()[c?.id];
  if (!e) return c;
  const out = { ...c };
  if (e.backstory != null) out.backstory = e.backstory || undefined;
  if (e.memories) out.memories = e.memories;
  if (e.traits && e.traits.length) out.traits = [...e.traits, ...(c.traits ?? []).filter((t) => !TRAITS.includes(t))].slice(0, 7);
  if (e.loyalty != null) out.loyalty = e.loyalty;
  return out;
}

// A new chronicle's cast, just copied from the baseline, rewritten as the player wants it.
export function applyTo(dir) {
  for (const id of Object.keys(load())) {
    const f = path.join(dir, `${id}.json`);
    try { fs.writeFileSync(f, JSON.stringify(apply(JSON.parse(fs.readFileSync(f, "utf8"))), null, 2)); } catch { /* not in this cast */ }
  }
}
