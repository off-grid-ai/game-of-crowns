// Guards "which town works each gold seam" (READY.md line 12, miners and carts at worked mines; casebook, The
// crowd is the census, Stronghold: the miners stand where Freeciv says the seam is worked). One rule, Freeciv's:
// realm_seam_town (realmrules/script.lua) wears the seam down and names the town; realm_mines reports it each season
// ("seams_worked") and mines.js puts it on /world's gold rows as [x, y, owner, town], -1 unworked. Bare Freeciv on
// the baseline, our ruleset, no bridge. Exits 1 on a failure.   node tools/seam_town_probe.mjs        (from bridge/)
import path from "node:path";
import { fileURLToPath } from "node:url";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";
import * as Mines from "../mines.js";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const { check, done } = checker("SEAM TOWN");
const b = await bareFreeciv({ port: 5583, save: path.join(BRIDGE, "baseline/aldmere/saves/realm-T0038-Y-2150-auto.sav.zst"), serv: ["set barbarians disabled", "set timeout -1", 'aitoggle "The King"'] });
check(await b.until(/Now accepting new client connections/, 30000), "the baseline didn't load");
const from = b.lines.length;
b.send("set endturn 40");
b.send("start");
check(await b.until(/Game ended as the turn limit/, 120000, from), "the baseline didn't run on");
const ev = b.lines.slice(from).filter((l) => l.includes('"kind":"seams_worked"')).map((l) => JSON.parse(l.slice(l.indexOf("{")))).pop();
check(ev, "Freeciv reported no seams_worked");
const rows = String(ev?.at ?? "").split(";").filter(Boolean).map((s) => s.split(",").map(Number));
check(rows.length > 0 && rows.every((r) => r.length === 4), `seams_worked isn't "x,y,town,owner;..." (${ev?.at})`);
const worked = rows.filter((r) => r[2] >= 0);
check(worked.length > 0, "no seam is worked by any town on the baseline");
await b.quit();

// Each named town is the land owner's, and in reach: checked against Freeciv on the game's last save.
const c = await bareFreeciv({ port: 5583, save: b.newestSave(), saves: b.dir });
await c.until(/Now accepting new client connections/, 30000);
for (const [x, y, town] of rows) {
  const l = await c.cmd(`lua cmd local t = find.tile(${x}, ${y}); local by = realm_seam_town(t); log.normal("SEAM %d %d %d %s", ${x}, ${y}, by and by.id or -1, tostring(by == nil or (by.owner == t.owner and t:sq_distance(by.tile) <= by:map_sq_radius())))`, /SEAM /);
  check(new RegExp(`SEAM ${x} ${y} ${town} true`).test(l ?? ""), `seam (${x},${y}): reported town ${town}, Freeciv says ${l}`);
}
await c.quit();

// The bridge puts it on /world's gold rows.
const meta = {};
Mines.worked(meta, ev);
const gold = Mines.withTowns(rows.map(([x, y]) => [x, y, 0]).concat([[999, 999, 0]]), meta);
check(gold.slice(0, -1).every((g, i) => g[3] === rows[i][2]) && gold.at(-1)[3] === -1, `/world gold rows don't carry the working town (${JSON.stringify(gold.slice(0, 3))})`);
console.log(`  ${rows.length} seams, ${worked.length} worked: ${worked.map((r) => `(${r[0]},${r[1]}) by town ${r[2]}`).join(", ")}`);
done();
