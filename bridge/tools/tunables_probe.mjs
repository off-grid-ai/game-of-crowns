// Guards integration audit #20, bridge side (READY.md line 15; Mac tunes while playing: numbers in data with a
// TUNING.md line): no gameplay number is a bare `const NAME = <number>` in bridge code. What may stay in code is
// the calendar's epoch and the minds' engine timings (cache life, memory cap), listed here. Each moved knob is read
// from its data row and named in docs/TUNING.md. Exits 1 on a breach.   node tools/tunables_probe.mjs   (from bridge/)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { checker } from "./fc_probe_lib.mjs";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const { check, done } = checker("TUNABLES");
const ENGINE = new Set(["CONQUEST_YEAR", "FRESH_MS", "GROUP_MS", "CAP", "HOT_MS", "SPOKEN_MS"]);
let n = 0;
for (const f of fs.readdirSync(BRIDGE).filter((x) => x.endsWith(".js"))) {
  fs.readFileSync(path.join(BRIDGE, f), "utf8").split("\n").forEach((line, i) => {
    const m = line.match(/^(?:export )?const ([A-Z][A-Z0-9_]*) = -?[\d.]+(?:\s*\*\s*[\d.]+)?\s*[;,]/);
    if (m && !ENGINE.has(m[1])) check(false, `${f}:${i + 1} keeps a gameplay number in code: ${line.trim().slice(0, 100)}`);
    if (m) n++;
  });
}
const tuning = fs.readFileSync(path.join(BRIDGE, "../docs/TUNING.md"), "utf8");
const rows = { "favour.json": ["turning"], "court.json": ["rulingDue"], "ledger.json": ["strong"], "economy.json": ["workSeasons"], "stories.json": ["maxActive", "startChance", "maxEach", "schemeSeasons", "plagueSeasons"], "thoughts.json": ["rumourSeasons"] };
for (const [file, keys] of Object.entries(rows)) {
  let d = {};
  try { d = JSON.parse(fs.readFileSync(path.join(BRIDGE, "data", file), "utf8")); } catch { /* missing */ }
  for (const k of keys) {
    check(d[k] != null, `data/${file} has no ${k}`);
    check(new RegExp(`${file.replace(".", "\\.")}[^\\n]*\`${k}\``).test(tuning), `TUNING.md doesn't name ${file} ${k}`);
  }
}
console.log(`  ${n} numeric consts in bridge code, all on the engine list`);
done();
