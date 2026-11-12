// Guards "raids are Freeciv's barbarians" (casebook, Every answer costs: an unguarded town is the one raiders
// find; ledger 89286083): realm_raid(city) raises Freeciv's own barbarians beside a town from the first turns,
// under the raiders choice "Some" (huts_only: no wild hordes of their own), and none with raiders off. The town's
// own men are never touched by the raising itself. Freeciv on its own port, our ruleset, no bridge. Exits 1 on a
// failure.   node tools/raid_probe.mjs        (from bridge/)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";
import { BARBARIANS } from "../chronicles.js";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const { check, done } = checker("RAID");
const read = (f) => fs.readFileSync(path.join(BRIDGE, f), "utf8");

// No dice raid is left: nothing kills a town's men by a coin toss.
for (const f of ["arcs.js", "characters.js"]) check(!/math\.random\(\) < 0\.5 then edit\.unit_kill/.test(read(f)), `${f} still has a dice raid`);

// Raiders never take a town: both conquer enablers exclude Freeciv's barbarians (the dead, a player of their own, still can).
const enablers = read("data/realmrules/actions.ruleset").split(/\n(?=\[)/).filter((s) => /^\[actionenabler_conquer_city/.test(s));
check(enablers.length === 2 && enablers.every((s) => /"PlayerState",\s*"Barbarian",\s*"Player",\s*FALSE/.test(s)), "a Conquer City enabler lets barbarians take a town");

// A short game, then its save loaded the way the bridge loads a realm.
const a = await bareFreeciv({ port: 5574, serv: ["set aifill 3", "set minplayers 0", "set timeout -1", `set barbarians ${BARBARIANS.normal}`, "set endturn 3", "start"] });
check(await a.until(/Game ended as the turn limit/, 90000), "the game didn't run to its end");
const save = fs.readdirSync(a.dir).filter((f) => /-auto\.sav/.test(f)).sort().pop();
await a.quit();

for (const [raiders, want] of [["normal", true], ["none", false]]) {
  const b = await bareFreeciv({ port: 5574, save: path.join(a.dir, save), saves: a.dir, serv: [`set barbarians ${BARBARIANS[raiders]}`] });
  check(await b.until(/Now accepting new client connections/, 30000), "the save didn't load");
  const onset = await b.cmd("lua cmd log.normal('ONSET %s %s', server.setting.get('onsetbarbs'), server.setting.get('barbarians'))", /ONSET /);
  check(/ONSET 1 /.test(onset ?? ""), `the ruleset's barbarian onset isn't turn 1: ${onset}`);
  const town = await b.cmd("lua cmd for p in players_iterate() do for c in p:cities_iterate() do local n = 0 for t in c.tile:square_iterate(1) do for u in t:units_iterate() do if u.owner == p then n = n + 1 end end end log.normal('TOWN %d %d', c.id, n) return end end", /TOWN /);
  const [, id, men] = (town ?? "").match(/TOWN (\d+) (\d+)/) ?? [];
  check(id, "no town to raid");
  const raised = Number((await b.cmd(`lua cmd realm_raid(${id})`, /RAID /))?.match(/raised (\d+)/)?.[1] ?? -1);
  const after = await b.cmd(`lua cmd local c = find.city(nil, ${id}); local n = 0 for t in c.tile:square_iterate(1) do for u in t:units_iterate() do if u.owner == c.owner then n = n + 1 end end end log.normal('AFTER %d', n)`, /AFTER /);
  if (want) check(raised >= 3, `raiders "${raiders}" (${BARBARIANS[raiders]}): realm_raid raised ${raised} barbarians (want 3 or more)`);
  else check(raised === 0, `raiders "none": realm_raid raised ${raised} barbarians (want none)`);
  check(Number(after?.match(/AFTER (\d+)/)?.[1]) === Number(men), `raising the raiders touched the town's own men (${men} -> ${after})`);
  console.log(`raiders ${raiders}: ${raised} barbarians raised beside town ${id}; its ${men} men untouched`);
  await b.quit();
}
done();
