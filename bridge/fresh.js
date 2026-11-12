// Every reign is a new reign. A new chronicle starts from the Aldmere baseline
// (the realm 38 turns in), and for a real reign this deals it a fresh start
// from the reign's seed: Freeciv's own dice, the opening tensions between
// neighbouring great houses, and the lords' grudges. Test reigns never come
// here, so proofs stay repeatable.
import { setPair } from "./diplomacy.js";
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { HOUSES } from "./narrator.js";

export function rng(seed) {
  let s = seed >>> 0 || 1;
  return () => {
    s = (Math.imul(s ^ (s >>> 15), 2246822507) + 0x9e3779b9) >>> 0;
    s = Math.imul(s ^ (s >>> 13), 3266489909) >>> 0;
    return ((s ^ (s >>> 16)) >>> 0) / 4294967296;
  };
}

const greatNation = (n) => { const h = HOUSES[String(n).toLowerCase()]; return h && !h.crown && !h.wild ? h : null; };

// Deals the openings: each great house with its two nearest great houses is a
// pair; a pair is at war, under a truce (some close to breaking) or at peace.
// At least one war, or a truce about to break, always opens the reign.
function tensions(text, world, r) {
  const turn = world.turn ?? 0;
  const seat = new Map();
  for (const c of world.cities ?? []) if (c.capital) seat.set(c.owner, c);
  const great = (world.players ?? []).filter((p) => greatNation(p.nation) && (p.cities ?? 0) > 0 && seat.has(p.id)).map((p) => p.id);
  const d = (a, b) => Math.hypot(seat.get(a).x - seat.get(b).x, seat.get(a).y - seat.get(b).y);
  const pairs = new Map();
  for (const a of great) {
    for (const b of great.filter((x) => x !== a).sort((x, y) => d(a, x) - d(a, y)).slice(0, 2)) pairs.set([a, b].sort().join(":"), [Math.min(a, b), Math.max(a, b)]);
  }
  const dealt = [...pairs.values()].map(([a, b]) => {
    const x = r();
    if (x < 0.35) return { a, b, state: "War", left: 0 };
    if (x < 0.7) return { a, b, state: "Cease-fire", left: 2 + Math.floor(r() * 15) };
    return { a, b, state: "Peace", left: 0 };
  });
  if (dealt.length && !dealt.some((t) => t.state === "War" || (t.state === "Cease-fire" && t.left <= 4))) {
    const t = dealt[Math.floor(r() * dealt.length)];
    Object.assign(t, r() < 0.5 ? { state: "War", left: 0 } : { state: "Cease-fire", left: 2 + Math.floor(r() * 3) });
  }
  for (const t of dealt) {
    const love = t.state === "War" ? -300 - Math.floor(r() * 500) : t.state === "Cease-fire" ? -100 - Math.floor(r() * 500) : 100 + Math.floor(r() * 300);
    text = setPair(text, t.a, t.b, t.state, turn, t.left, love);
    text = setPair(text, t.b, t.a, t.state, turn, t.left, love + Math.floor(r() * 200) - 100);
  }
  return { text, dealt };
}

const LORD_GOALS = [
  { kind: "power", text: "make my house the greatest in the realm" },
  { kind: "marriage", text: "wed my heir into a great house" },
  { kind: "revenge", text: "settle the old grudge" },
  { kind: "crown", text: "sit the throne myself one day" },
  { kind: "peace", text: "keep my people fed and out of other men's wars" },
];

// The lords' grudges follow the openings: a lord hates the lords of a house
// he is at war or truce with, warms to one he is at peace with; every other
// feeling is kept but made stronger or weaker, and each lord's aim is redrawn.
function grudges(dir, dealt, nameOf, r) {
  if (!fs.existsSync(dir)) return;
  const people = fs.readdirSync(dir).filter((f) => f.endsWith(".json")).map((f) => {
    const file = path.join(dir, f);
    return { file, c: JSON.parse(fs.readFileSync(file, "utf8")) };
  });
  const lords = people.filter(({ c }) => c.alive !== false && c.rank === "lord");
  const lordOf = (pid) => lords.find(({ c }) => c.playerId === pid)?.c;
  const clamp = (v) => Math.max(-100, Math.min(100, Math.round(v)));
  for (const { c } of lords) {
    for (const rel of Object.values(c.relationships ?? {})) rel.opinion = clamp(rel.opinion * (0.6 + r() * 0.8));
    const feud = dealt.find((t) => t.state !== "Peace" && (t.a === c.playerId || t.b === c.playerId));
    c.goals = [feud && r() < 0.5 ? LORD_GOALS[2] : LORD_GOALS[Math.floor(r() * LORD_GOALS.length)]];
  }
  for (const t of dealt) {
    for (const [p, q] of [[t.a, t.b], [t.b, t.a]]) {
      const me = lordOf(p), them = lordOf(q);
      if (!me || !them) continue;
      me.relationships ??= {};
      if (t.state === "Peace") {
        me.relationships[them.id] = { opinion: clamp(30 + r() * 40) };
      } else {
        me.relationships[them.id] = { opinion: clamp(-50 - r() * 50) };
        me.memories = [...(me.memories ?? []), `Our quarrel with ${nameOf(q)} is old and bitter.`].slice(-20);
      }
    }
  }
  for (const { file, c } of people) fs.writeFileSync(file, JSON.stringify(c, null, 2));
}

// base: the new chronicle's folder, already copied from the baseline.
export function freshStart(base, seed) {
  const saves = path.join(base, "saves");
  const save = fs.readdirSync(saves).find((f) => f.endsWith(".sav.zst"));
  if (!save) return null;
  const file = path.join(saves, save);
  let text = zlib.zstdDecompressSync(fs.readFileSync(file)).toString();
  // Freeciv's dice: the baseline saved its exact state, so every reign rolled
  // the same. Without it Freeciv seeds them fresh on load.
  text = text.replace("\n[random]\nsaved=TRUE", "\n[random]\nsaved=FALSE");
  let world = {};
  try { world = JSON.parse(fs.readFileSync(path.join(base, "state", "world.json"), "utf8")); } catch { /* none */ }
  const r = rng(Math.imul(seed >>> 0, 0x9e3779b1) ^ 0x85ebca6b);
  for (let i = 0; i < 8; i++) r();  // the first rolls of near seeds are alike
  const t = tensions(text, world, r);
  fs.writeFileSync(file, zlib.zstdCompressSync(Buffer.from(t.text)));
  const nation = new Map((world.players ?? []).map((p) => [p.id, p.nation]));
  grudges(path.join(base, "characters"), t.dealt, (pid) => greatNation(nation.get(pid))?.name ?? "them", r);
  return t.dealt.map((x) => ({ a: x.a, b: x.b, state: x.state, turnsLeft: x.left }));
}
