// Guards step 5 (docs/research/freeciv-leverage-2026-11-12.md): the King's siege is fought by Freeciv. The
// King's march puts the crown at war with the house (campaigns.js through the bridge's one diplomacy writer);
// each season at the walls realm_assault (lua.js assault) has each royal company strike once by Freeciv's
// combat and march in when no defender is left (Freeciv's own conquest); the bridge rolls no dice and hands
// over no town. Bare Freeciv on 5571, our ruleset, a Norman crown and one house, no bridge. Exits 1 on a failure.
//   node tools/siege_probe.mjs        (from bridge/)
import fs from "node:fs";
import path from "node:path";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";
import zlib from "node:zlib";
import * as Lua from "../lua.js";
import { editRow } from "../fresh.js";

const { check, done } = checker("SIEGE");
const camp = fs.readFileSync(new URL("../campaigns.js", import.meta.url), "utf8");
check(!/Math\.random\(\)/.test(camp), "campaigns.js still rolls dice for a siege");
check(!/edit\.transfer_city|transferCity/.test(camp), "campaigns.js still hands a besieged town over");
check(/Lua\.assault\(/.test(camp), "campaigns.js doesn't order the assault");
check(/diplomacy\?\.\(\[crown\.id, house, 0, "War"\]\)/.test(camp), "the King's march doesn't declare war on the house");

const a = await bareFreeciv({ serv: ["set aifill 0", "set minplayers 0", "set timeout -1", "set saveturns 1", 'set autosaves "TURN|GAMEOVER"', 'set savename "probe"',
  "create Crown", "create Foe", 'playernation Crown norman 1 "The King"', 'playernation Foe english 1 "Lord Foe"', "set endturn 3", "start"] });
check(await a.until(/Game ended as the turn limit/, 90000), "the game didn't run");
const first = fs.readdirSync(a.dir).filter((f) => /-auto\.sav\.zst$/.test(f)).sort().pop();
await a.quit();

// The King's march declares war on the house (server.js setDiplomacy writes it into the save; done the same here).
const atWar = path.join(a.dir, "probe-war.sav.zst");
let text = zlib.zstdDecompressSync(fs.readFileSync(path.join(a.dir, first))).toString();
for (const [p, q] of [[0, 1], [1, 0]]) text = editRow(text, p, "diplstate", q, (c) => { c[0] = c[1] = '"War"'; if (c[2] === "0") c[2] = "1"; c[3] = c[4] = "0"; });
fs.writeFileSync(atWar, zlib.zstdCompressSync(Buffer.from(text)));
const b = await bareFreeciv({ save: atWar, saves: a.dir });
await b.until(/Now accepting new client connections/, 30000);
const town = async () => {
  const l = await b.cmd('lua cmd local crown = find.player("Crown"); local s = ""; for p in players_iterate() do for c in p:cities_iterate() do s = s .. string.format("%d:%d:%d:%d ", c.id, p.id, crown.id, c.tile:num_units()) end end; log.normal("TOWN %s.", s)', /TOWN /);
  const foe = [...(l ?? "").matchAll(/(\d+):(\d+):(\d+):(\d+)/g)].map((m) => ({ city: +m[1], owner: +m[2], crown: +m[3], units: +m[4] }));
  return foe;
};
const towns = await town();
const crownId = towns[0]?.crown;
const target = towns.find((t) => t.owner !== crownId);
check(target, `no house town to besiege (${JSON.stringify(towns)})`);
if (!target) { await b.quit(); done(); }
// The town's garrison (a fresh town may hold only workers, whom Freeciv captures rather than fights).
await b.cmd(`lua cmd local c = find.city(nil, ${target.city}); edit.create_unit(c.owner, c.tile, find.unit_type("Pikemen"), 0, c, -1)`);
// The crown's host beside the walls (made here for the test; the King's host marches there in play).
b.send(`lua cmd local c = find.city(nil, ${target.city}); local crown = find.player("Crown"); local k = find.unit_type("Knights"); local n = 0; for t in c.tile:square_iterate(1) do if n < 8 and t ~= c.tile and not t:city() and t.terrain:class_name() == "Land" then edit.create_unit(crown, t, k, 2, nil, -1); n = n + 1 end end; log.normal("HOSTSET %d", n)`);
check(await b.until(/HOSTSET [1-9]/, 10000), "couldn't set the host beside the town");
let after = target;
const season = 'lua cmd for u in find.player("Crown"):units_iterate() do edit.unit_add_movepoints(u, 9) end';  // a new season's moves
for (let i = 0; i < 6 && after && after.owner !== crownId; i++) {
  await b.cmd(season);
  await b.cmd(`lua cmd ${Lua.assault(target.city, crownId)}`, /"kind":"assault"/);
  after = (await town()).find((t) => t.city === target.city);
}
const blows = b.lines.filter((l) => l.includes('"kind":"assault"')).map((l) => Number(l.match(/"blows":"(\d+)"/)?.[1] ?? 0)).reduce((x, y) => x + y, 0);
console.log(`  assaults struck ${blows} blows; town ${target.city} held by ${after?.owner} (crown ${crownId}), ${after?.units} units in it`);
check(blows > 0, "no blow was struck: Freeciv fought nothing");
check(!after || after.owner === crownId, "the royal host beside a fresh town didn't take it (or raze it, at size 1)");
await b.quit();
fs.rmSync(a.dir, { recursive: true, force: true });
done();
