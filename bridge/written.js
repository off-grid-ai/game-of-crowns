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

// A new chronicle's cast never has two living people sharing a first name (the
// baseline was cast before that rule): each repeat after the first, lords kept
// first, takes a free name of their gender, and the copied court, stories and
// records say the new name too.
export function distinctNames(base, pool) {
  const dir = path.join(base, "characters");
  let cast;
  try { cast = fs.readdirSync(dir).filter((f) => f.endsWith(".json")).map((f) => ({ f: path.join(dir, f), c: JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")) })); } catch { return; }
  const living = cast.filter((x) => x.c.alive !== false);
  const rank = { lord: 0, heir: 1, bannerman: 2 };
  living.sort((a, b) => (rank[a.c.rank] ?? 3) - (rank[b.c.rank] ?? 3));
  const first = (n) => String(n).split(" ")[0];
  const used = new Set(), renames = [];
  const taken = new Set(living.map((x) => first(x.c.name)));  // never rename someone into a name another already has
  for (const x of living) {
    const f = first(x.c.name);
    if (!used.has(f)) { used.add(f); continue; }
    const free = (pool[x.c.gender === "male" ? "male" : "female"] ?? []).filter((n) => !used.has(n) && !taken.has(n));
    if (!free.length) continue;
    const to = free[Math.floor(Math.random() * free.length)];
    used.add(to);
    const was = x.c.name;
    x.c.name = `${to}${String(was).slice(f.length)}`;
    renames.push([was, x.c.name]);
  }
  if (!renames.length) return;
  const swap = (t) => renames.reduce((s, [a, b]) => s.split(a).join(b), t);
  // Others' memories and stories follow the new names; each person keeps exactly
  // the name settled above (two can share a full name, so never by swapping).
  for (const x of cast) { const named = x.c.name; const o = JSON.parse(swap(JSON.stringify(x.c))); o.name = named; fs.writeFileSync(x.f, JSON.stringify(o, null, 2)); }
  const files = ["court.json", "arcs.json", "meta.json"].map((f) => path.join(base, f));
  try { for (const f of fs.readdirSync(path.join(base, "state"))) if (/\.(json|jsonl)$/.test(f)) files.push(path.join(base, "state", f)); } catch { /* none */ }
  for (const f of files) { try { fs.writeFileSync(f, swap(fs.readFileSync(f, "utf8"))); } catch { /* not there */ } }
}

// Fresh minor folk each real reign (PLAN.md, "kill the repeats"; RCT's guests all have names): every
// bannerman's family gets a surname of its own from data/surnames.json, and each of them a first name of
// their sex from the pool, so the same informer isn't back in every reign. Lords, their kin and the dead
// keep theirs. Everything that names them (memories, the court's waiting pleas, the chronicle) follows.
export function freshMinorNames(base, pool, surnames) {
  const dir = path.join(base, "characters");
  let cast;
  try { cast = fs.readdirSync(dir).filter((f) => f.endsWith(".json")).map((f) => ({ f: path.join(dir, f), c: JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")) })); } catch { return; }
  const byId = new Map(cast.map((x) => [x.c.id, x.c]));
  const first = (n) => String(n).split(" ")[0];
  const takenFirst = new Set(cast.map((x) => first(x.c.name)));
  const takenSur = new Set(cast.map((x) => x.c.surname));
  const roll = (list) => list[Math.floor(Math.random() * list.length)];
  const renames = [], surRenames = new Map(), kinSur = new Map();  // kinSur: person id -> [old, new] surname of their family
  const oldSurCount = new Map();
  for (const x of cast) oldSurCount.set(x.c.surname, (oldSurCount.get(x.c.surname) ?? 0) + (x.c.rank === "bannerman" ? 1 : 0));
  for (const bm of cast.map((x) => x.c).filter((c) => c.rank === "bannerman")) {
    const freeSur = surnames.filter((s) => !takenSur.has(s));
    if (!freeSur.length) break;
    const sur = roll(freeSur);
    takenSur.add(sur);
    if (oldSurCount.get(bm.surname) === 1) surRenames.set(bm.surname, sur);  // "the Kettle books": the surname alone, when only one family had it
    const kin = [bm, byId.get(bm.spouse), ...(bm.children ?? []).map((id) => byId.get(id))].filter((c) => c && c.surname === bm.surname);
    for (const c of kin) {
      kinSur.set(c.id, [c.surname, sur]);
      const freeFirst = (pool[c.gender === "male" ? "male" : "female"] ?? []).filter((n) => !takenFirst.has(n));
      const to = c.alive !== false && freeFirst.length ? roll(freeFirst) : first(c.name);
      takenFirst.add(to);
      const was = c.name;
      c.name = `${to} ${sur}`;
      c.surname = sur;
      renames.push([was, c.name]);
    }
  }
  if (!renames.length) return;
  // Longest first, so "Cedric Kettle" isn't caught inside "Cedric Kettle the Younger" half-done.
  renames.sort((a, b) => b[0].length - a[0].length);
  const swap = (t) => [...surRenames].reduce((s, [a, b]) => s.replace(new RegExp(`\\b${a}\\b`, "g"), b), renames.reduce((s, [a, b]) => s.split(a).join(b), t));
  const word = (t, [a, b]) => t.replace(new RegExp(`\\b${a}\\b`, "g"), b);
  for (const x of cast) { const named = x.c.name, sur = x.c.surname; const own = kinSur.get(x.c.id); const o = JSON.parse(own ? word(swap(JSON.stringify(x.c)), own) : swap(JSON.stringify(x.c))); o.name = named; o.surname = sur; fs.writeFileSync(x.f, JSON.stringify(o, null, 2)); }
  const files = ["court.json", "arcs.json", "meta.json"].map((f) => path.join(base, f));
  try { for (const f of fs.readdirSync(path.join(base, "state"))) if (/\.(json|jsonl)$/.test(f)) files.push(path.join(base, "state", f)); } catch { /* none */ }
  for (const f of files) { try { fs.writeFileSync(f, swap(fs.readFileSync(f, "utf8"))); } catch { /* not there */ } }
}
