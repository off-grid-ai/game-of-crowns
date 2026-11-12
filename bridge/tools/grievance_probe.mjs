// Guards step 4 (docs/research/freeciv-leverage-2026-11-12.md): a house's anger costs it in Freeciv. A house
// under the cooling band bears a Grievance in its seat (lua.js grievance, sent each season by season.js), a
// small wonder that leaves three townsmen fewer content in each of its towns, so its AI must turn workers into
// minstrels to keep order (Freeciv's AI never lets a town riot). Lifted, the Grievance is gone.
// Bare Freeciv on 5571, our ruleset, no bridge. Exits 1 on a failure.
//   node tools/grievance_probe.mjs        (from bridge/)
import fs from "node:fs";
import path from "node:path";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";
import { readSave } from "../savefile.js";
import * as Lua from "../lua.js";

const { check, done } = checker("GRIEVANCE");
check(typeof Lua.grievance === "function", "lua.js has no grievance");
check(/Lua\.grievance\(aggrieved\)/.test(fs.readFileSync(new URL("../season.js", import.meta.url), "utf8")), "season.js doesn't send the Grievance");
const autos = (dir) => fs.readdirSync(dir).filter((f) => /-auto\.sav\.zst$/.test(f)).sort();
// Minstrels (specialist 0) and citizens per player in a save.
const minstrels = (file) => {
  const s = readSave(file), out = {};
  for (let i = 0; s[`player${i}`]; i++) {
    const rows = s[`player${i}`].c ?? [];
    out[i] = { minstrels: rows.reduce((n, c) => n + (Number(c.nspe0) || 0), 0), size: rows.reduce((n, c) => n + (Number(c.size) || 0), 0) };
  }
  return out;
};

const a = await bareFreeciv({ serv: ["set aifill 3", "set minplayers 0", "set timeout -1", "set saveturns 1", 'set autosaves "TURN|GAMEOVER"', 'set savename "probe"', "set endturn 30", "start"] });
check(await a.until(/Game ended as the turn limit/, 150000), "the game didn't run");
const first = autos(a.dir).pop();
await a.quit();
const before = minstrels(path.join(a.dir, first));
const owner = Number(Object.entries(before).sort((x, y) => y[1].size - x[1].size)[0][0]);

const b = await bareFreeciv({ save: path.join(a.dir, first), saves: a.dir });
await b.until(/Now accepting new client connections/, 30000);
const bears = async () => (await b.cmd('lua cmd local g = find.building_type("Grievance"); local s = ""; for p in players_iterate() do for c in p:cities_iterate() do if c:has_building(g) then s = s .. string.format("%d:%s ", p.id, tostring(c:is_primary_capital())) end end end; log.normal("BEARS %s.", s)', /BEARS /)) ?? "";
b.send(`lua cmd ${Lua.grievance([owner])}`);
const on = await bears();
check(on.includes(`${owner}:true`), `the aggrieved house's seat doesn't bear the Grievance (${on})`);
check(!/(\d+):/.test(on.replace(new RegExp(`\\b${owner}:true`, "g"), "")), `another town bears it (${on})`);
const from = b.lines.length;
b.send("set endturn 32");
b.send("start");
check(await b.until(/Game ended as the turn limit/, 120000, from), "the loaded game didn't run on");
const after = minstrels(path.join(a.dir, autos(a.dir).pop()));
await b.quit();
console.log(`  house ${owner}: minstrels ${before[owner].minstrels}/${before[owner].size} citizens before, ${after[owner].minstrels}/${after[owner].size} after`);
check(after[owner].minstrels > before[owner].minstrels, "the Grievance cost the house nothing: no more minstrels");
const c = await bareFreeciv({ save: path.join(a.dir, autos(a.dir).pop()), saves: a.dir });
await c.until(/Now accepting new client connections/, 30000);
b.cmd = c.cmd;
c.send(`lua cmd ${Lua.grievance([])}`);
check(!/(\d+):/.test(await bears()), "a lifted Grievance still stands");
await c.quit();
fs.rmSync(a.dir, { recursive: true, force: true });
done();
