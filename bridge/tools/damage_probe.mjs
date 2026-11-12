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
fs.copyFileSync(path.join(here, "../lua.js"), path.join(tmp, "lua.js"));  // damage.js sends a breach to Freeciv through it
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
// Houses by their stable id in the town (realm towns.gd home_id: where each stands, "x_z" in decimetres; audit #16).
const A = "31_-42", B = "-55_18";
check(same(D.kindle(meta, world, 7, A)?.kindled, [A]), "a lit house isn't in the town's damage");
D.kindle(meta, world, 7, B);
D.kindle(meta, world, 7, A);
check(same(meta.damage[7].kindled, [A, B]), `a house lit twice is kept twice (${JSON.stringify(meta.damage[7].kindled)})`);
check(globalThis.saves === 2, `kept houses aren't saved once each (${globalThis.saves} saves)`);
check(D.kindle(meta, world, 9, A) === null && D.kindle(meta, world, 7, 3) === null && D.kindle(meta, world, 7, "") === null, "a house of no town, or one named by its place in the view's laying order (a number) or by nothing, is kept");
const loaded = JSON.parse(JSON.stringify(meta));  // the realm saved and opened again
check(same(D.view(loaded, world.cities[0])?.kindled, [A, B]), "burnt houses are lost on a reload");
const per = D.DAMAGE.kindledRebuiltPerSeason;
check(Number.isInteger(per) && per > 0, "damage.json kindledRebuiltPerSeason missing");
D.season({ world, meta: loaded, marksNow: () => [] }, 10);
check(same(loaded.damage[7].kindled, [A, B].slice(per)), `a season on, the first lit isn't rebuilt first (${JSON.stringify(loaded.damage[7].kindled)})`);
fs.rmSync(tmp, { recursive: true, force: true });
console.log(`DAMAGE ${bad ? "FAIL" : "PASS"}: ${bad} problems`);
process.exit(bad ? 1 : 0);
