// Guards READY.md line 7, "capture a town" (casebook, War and sieges: A siege is a season, Total War: Attila): on the
// King's order the royal host takes a house's town in Freeciv (realm_assault, Lua.assault: Freeciv's own conquest),
// and the town changes hands (a size-1 hamlet is razed, Freeciv's rule). The crown's AI still takes none unbidden:
// actions.ruleset keeps Norman out of Freeciv's Conquer City. Bare Freeciv, our ruleset, a Norman crown and one
// house, no bridge. Exits 1 on a failure.   node tools/capture_probe.mjs        (from bridge/)
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";
import * as Lua from "../lua.js";
import { editRow } from "../fresh.js";

const { check, done } = checker("CAPTURE");
const PORT = 5578;
const a = await bareFreeciv({ port: PORT, serv: ["set aifill 0", "set minplayers 0", "set timeout -1", "set saveturns 1", 'set autosaves "TURN|GAMEOVER"', 'set savename "probe"',
  "create Crown", "create Foe", 'playernation Crown norman 1 "The King"', 'playernation Foe english 1 "Lord Foe"', "set endturn 3", "start"] });
check(await a.until(/Game ended as the turn limit/, 90000), "the game didn't run");
const first = fs.readdirSync(a.dir).filter((f) => /-auto\.sav\.zst$/.test(f)).sort().pop();
await a.quit();

// At war, as the King's march makes it (server.js setDiplomacy writes the save; done the same here).
const atWar = path.join(a.dir, "probe-war.sav.zst");
let text = zlib.zstdDecompressSync(fs.readFileSync(path.join(a.dir, first))).toString();
for (const [p, q] of [[0, 1], [1, 0]]) text = editRow(text, p, "diplstate", q, (c) => { c[0] = c[1] = '"War"'; if (c[2] === "0") c[2] = "1"; c[3] = c[4] = "0"; });
fs.writeFileSync(atWar, zlib.zstdCompressSync(Buffer.from(text)));
const b = await bareFreeciv({ port: PORT, save: atWar, saves: a.dir });
await b.until(/Now accepting new client connections/, 30000);

const towns = async () => {
  const l = await b.cmd('lua cmd local crown = find.player("Crown"); local s = ""; for p in players_iterate() do for c in p:cities_iterate() do s = s .. string.format("%d:%d:%d:%d:%d ", c.id, p.id, crown.id, c.tile:num_units(), c.size) end end; log.normal("TOWN %s.", s)', /TOWN /);
  return [...(l ?? "").matchAll(/(\d+):(\d+):(\d+):(\d+):(\d+)/g)].map((m) => ({ city: +m[1], owner: +m[2], crown: +m[3], units: +m[4], size: +m[5] }));
};
// The house's town, founded here so the probe never depends on where the AI settled: land four tiles from the crown's.
await b.cmd('lua cmd local foe = find.player("Foe"); local home; for c in find.player("Crown"):cities_iterate() do home = c end; for t in home.tile:square_iterate(4) do if home.tile:sq_distance(t) >= 13 and not t:city() and t.terrain:class_name() == "Land" and t:num_units() == 0 then edit.create_city(foe, t, "Probeford") break end end; log.normal("FOUNDED")', /FOUNDED/);
const before = await towns();
const crownId = before[0]?.crown;
const target = before.filter((t) => t.owner !== crownId).pop();
check(target, `no house town to take (${JSON.stringify(before)})`);
if (!target) { await b.quit(); done(); }

// An empty town of size 3 (no garrison; its workers out), and the King's host beside it.
await b.cmd(`lua cmd local c = find.city(nil, ${target.city}); local m = find.unit_type("Migrants") or find.unit_type("Settlers"); for i = 1, 2 do local u = edit.create_unit(c.owner, c.tile, m, 0, nil, -1); pcall(edit.perform_action, u, find.action("Join City"), c) end; for u in c.tile:units_iterate() do edit.unit_kill(u, "disbanded", nil) end; log.normal("EMPTIED %d", c.size)`, /EMPTIED/);
b.send(`lua cmd local c = find.city(nil, ${target.city}); local crown = find.player("Crown"); local k = find.unit_type("Knights"); local n = 0; for t in c.tile:square_iterate(1) do if n < 3 and t ~= c.tile and not t:city() and t.terrain:class_name() == "Land" then edit.create_unit(crown, t, k, 2, nil, -1); n = n + 1 end end; log.normal("HOSTSET %d", n)`);
check(await b.until(/HOSTSET [1-9]/, 10000), "couldn't set the host beside the town");

// The crown's AI on its own takes no town: both Conquer City enablers keep Norman out (Freeciv's AI reads them;
// the King's order goes through realm_assault's edit move, which the enablers don't gate).
const rules = fs.readFileSync(new URL("../data/realmrules/actions.ruleset", import.meta.url), "utf8").split(/\n(?=\[)/).filter((x) => /^\[actionenabler_conquer_city/.test(x));
check(rules.length === 2 && rules.every((x) => /"Nation",\s*"Norman",\s*"Player",\s*FALSE/.test(x)), "a Conquer City enabler lets the crown's AI take a town unbidden");

// The King's order: the assault. The town is the crown's now, one size smaller (Freeciv's conquest).
await b.cmd(`lua cmd ${Lua.assault(target.city, crownId)}`, /"kind":"assault"/);
const after = (await towns()).find((t) => t.city === target.city);
check(b.lines.some((l) => /"kind":"city_transferred"/.test(l) && /"reason":"conquest"/.test(l) && l.includes(`"city":"${target.city}"`)), "Freeciv sent no city_transferred for the conquest (the bridge hears hands change by it)");
check(after?.owner === crownId, `the King's host didn't take the empty town (held by ${after?.owner}, crown ${crownId})`);
check(after?.size === 2, `the taken town is size ${after?.size} (want 2: Freeciv takes one citizen on conquest)`);
console.log(`  town ${target.city}: house ${target.owner} -> ${after?.owner} (crown ${crownId}), size 3 -> ${after?.size}`);
await b.quit();
fs.rmSync(a.dir, { recursive: true, force: true });
done();
