// Guards the bridge's half of burnt houses (damage.js, 79aafe9f): a house a fire arrow or a sack's spread lit
// (kindled) is kept once, refused for no town or no house, survives the realm's save and load, and is rebuilt
// kindledRebuiltPerSeason a season, first lit first. Exits 1 on a failure. The view's half is
// realm/tools/ground_truth_probe.gd.
//   node tools/damage_probe.mjs        (from bridge/)
// damage.js is loaded from a temporary copy whose chronicle saving is a counter: nothing touches a live realm.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "damage-probe-"));
fs.mkdirSync(path.join(tmp, "data"));
fs.copyFileSync(path.join(here, "../data/damage.json"), path.join(tmp, "data/damage.json"));
const src = fs.readFileSync(path.join(here, "../damage.js"), "utf8");
const stubbed = src.replace('import * as chron from "./chronicles.js";', "const chron = { saveMeta: () => { globalThis.saves = (globalThis.saves ?? 0) + 1; } };");
fs.writeFileSync(path.join(tmp, "damage.mjs"), stubbed);
const D = await import(pathToFileURL(path.join(tmp, "damage.mjs")).href);

let bad = 0;
const check = (ok, what) => { if (!ok) { bad++; console.log("DAMAGE FAIL", what); } };
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

check(stubbed !== src, "damage.js no longer imports chronicles.js as this probe expects: update the probe");
const world = { cities: [{ id: 7, x: 3, y: 4 }] };
const meta = {};
check(same(D.kindle(meta, world, 7, 2)?.kindled, [2]), "a lit house isn't in the town's damage");
D.kindle(meta, world, 7, 5);
D.kindle(meta, world, 7, 2);
check(same(meta.damage[7].kindled, [2, 5]), `a house lit twice is kept twice (${JSON.stringify(meta.damage[7].kindled)})`);
check(globalThis.saves === 2, `kept houses aren't saved once each (${globalThis.saves} saves)`);
check(D.kindle(meta, world, 9, 1) === null && D.kindle(meta, world, 7, -1) === null, "a house of no town, or no house, is kept");
const loaded = JSON.parse(JSON.stringify(meta));  // the realm saved and opened again
check(same(D.view(loaded, world.cities[0])?.kindled, [2, 5]), "burnt houses are lost on a reload");
const per = D.DAMAGE.kindledRebuiltPerSeason;
check(Number.isInteger(per) && per > 0, "damage.json kindledRebuiltPerSeason missing");
D.season({ world, meta: loaded, marksNow: () => [] }, 10);
check(same(loaded.damage[7].kindled, [2, 5].slice(per)), `a season on, the first lit isn't rebuilt first (${JSON.stringify(loaded.damage[7].kindled)})`);
fs.rmSync(tmp, { recursive: true, force: true });
console.log(`DAMAGE ${bad ? "FAIL" : "PASS"}: ${bad} problems`);
process.exit(bad ? 1 : 0);
