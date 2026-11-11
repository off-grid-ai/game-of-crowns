// The realm's own words, widened by the local model (PLAN.md Phase 1, "kill the repeats": Omni rewords
// flavour). In idle time, once a season, Omni writes one more wording of a court result (say.js keys),
// keeping its {names} as they are; the written wordings stay, and the choices themselves are never
// touched. A wording is kept only if it holds every {name}, no other braces, no digits, one line of a
// sane length; kept ones are saved beside the chronicles and drawn by say.js in every reign after.
import fs from "node:fs";
import path from "node:path";
import { HOME } from "./chronicles.js";
import { think } from "./claude.js";
import * as Say from "./say.js";

const FILE = path.join(HOME, "chronicles", "wordings.json");
const CFG = JSON.parse(fs.readFileSync(new URL("./data/results.json", import.meta.url), "utf8")).reword ?? {};
const MOST = CFG.most ?? 8;  // added wordings kept per result, at most
let loaded = false, busy = false;

function load() {
  if (loaded) return;
  loaded = true;
  try { for (const [k, list] of Object.entries(JSON.parse(fs.readFileSync(FILE, "utf8")))) for (const t of list) Say.add(k, t); } catch { /* none yet */ }
}

function save() {
  const all = Object.fromEntries(Say.keys().map((k) => [k, Say.added(k)]).filter(([, l]) => l.length));
  try { fs.mkdirSync(path.dirname(FILE), { recursive: true }); fs.writeFileSync(FILE, JSON.stringify(all, null, 1)); } catch { /* the next season tries again */ }
}

// Whether a wording the model wrote may stand beside the written ones.
export function fits(text, key) {
  const like = Say.written(key)[0] ?? "";
  const names = (s) => [...String(s).matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort().join(",");
  const t = String(text ?? "").trim().replace(/^["']|["']$/g, "");
  if (!t || /\n/.test(t) || /\d/.test(t) || t.length < 30 || t.length > 200) return null;
  if (names(t) !== names(like)) return null;  // every {name} kept, none made up
  if (/[{}]/.test(t.replace(/\{\w+\}/g, ""))) return null;
  if (Say.written(key).includes(t)) return null;
  return t;
}

// Each season (season.js): one more wording for the result with the fewest, if the model is free.
export async function season() {
  if (!CFG.on) return;
  load();
  if (busy) return;
  const key = Say.keys().filter((k) => Say.added(k).length < MOST).sort((a, b) => Say.added(a).length - Say.added(b).length)[0];
  if (!key) return;
  const shown = Say.written(key);
  busy = true;
  try {
    const out = await think(
      "You write one line of a medieval court chronicle. Plain, dry, a little wry; no modern words. Keep every {placeholder} exactly as written, add none, use no numbers.",
      `Here are ways the chronicle has said this:\n${shown.map((s) => `- ${s}`).join("\n")}\nWrite one new way to say the same thing, with the same {placeholders}. One sentence or two, under 30 words. Only the line.`,
      "cold", 90);
    const t = fits(out, key);
    if (t && !Say.added(key).includes(t)) { Say.add(key, t); save(); }
  } catch { /* the model is away: the written words stand */ }
  busy = false;
}
