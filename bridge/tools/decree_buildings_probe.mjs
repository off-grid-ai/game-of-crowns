// Guards step 3 (docs/research/freeciv-leverage-2026-11-12.md): a decree is a building in Freeciv. A feast or
// relief sets one down in a town (realm_decree), it stands its seasons (luadata.txt [decrees]) and is taken up,
// the heavy tithe stands in the bearing houses' towns only, and a save keeps all of it. The bridge's own Lua
// strings (lua.js) are what is sent. Bare Freeciv on 5571, our ruleset, no bridge. Exits 1 on a failure.
//   node tools/decree_buildings_probe.mjs        (from bridge/)
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";
import * as Lua from "../lua.js";

const { check, done } = checker("DECREE BUILDINGS");
check(typeof Lua.decree === "function" && typeof Lua.heavyTithe === "function", "lua.js has no decree / heavyTithe");

const fc = await bareFreeciv({ serv: ["set aifill 3", "set minplayers 0", "set timeout -1", "set saveturns 1", 'set autosaves "TURN|GAMEOVER"', 'set savename "probe"', "set endturn 4", "start"] });
check(await fc.until(/Game ended as the turn limit/, 90000), "the game didn't run");
const first = fs.readdirSync(fc.dir).filter((f) => /-auto\.sav\.zst$/.test(f)).sort().pop();
await fc.quit();

// Load turn 4 and act like the bridge: a feast in one town, relief in another, the heavy tithe on player 0.
const b = await bareFreeciv({ save: path.join(fc.dir, first), saves: fc.dir });
await b.until(/Now accepting new client connections/, 30000);
const has = async (city, building) => (await b.cmd(`lua cmd local c = find.city(nil, ${city}); log.normal("HAS ${city} ${building} %s", tostring(c and c:has_building(find.building_type("${building}"))))`, new RegExp(`HAS ${city} ${building} `)))?.endsWith(" true");
const ids = [];
const listed = await b.cmd('lua cmd local s = ""; for p in players_iterate() do for c in p:cities_iterate() do s = s .. string.format("%d:%d:%s ", c.id, p.id, tostring(c:is_primary_capital())) end end; log.normal("CITIES %s", s)', /CITIES /);
for (const m of (listed ?? "").matchAll(/(\d+):(\d+):(true|false)/g)) ids.push({ city: Number(m[1]), owner: Number(m[2]), seat: m[3] === "true" });
check(ids.length >= 2, `need two towns, found ${ids.length}: ${listed}`);
if (ids.length < 2) { await b.quit(); done(); }
const [x, y] = ids;
b.send(`lua cmd ${Lua.decree(x.city, "feast")}`);
b.send(`lua cmd ${Lua.decree(y.city, "relief")}`);
b.send(`lua cmd ${Lua.heavyTithe([x.owner])}`);
check(await has(x.city, "Royal Feast"), "the feast decree set no Royal Feast");
check(await has(y.city, "Royal Relief"), "the relief decree set no Royal Relief");
const seatX = ids.find((c) => c.owner === x.owner);
const otherSeat = ids.find((c) => c.owner !== x.owner);
if (seatX) check(await has(seatX.city, "Heavy Tithe"), "the bearing house's town has no Heavy Tithe");
if (otherSeat) check(!(await has(otherSeat.city, "Heavy Tithe")), "a house not bearing the tithe has it");
b.send(`lua cmd ${Lua.heavyTithe([])}`);
if (seatX) check(!(await has(seatX.city, "Heavy Tithe")), "a lifted tithe still stands");
// Relief lasts 2 seasons, the feast 4: by turn 7 the relief is gone, the feast stands; a save keeps both facts.
const from = b.lines.length;
b.send("set endturn 7");
b.send("start");
check(await b.until(/Game ended as the turn limit/, 90000, from), "the loaded game didn't run on");
const last = fs.readdirSync(fc.dir).filter((f) => /-auto\.sav\.zst$/.test(f)).sort().pop();
const save = zlib.zstdDecompressSync(fs.readFileSync(path.join(fc.dir, last))).toString();
await b.quit();
check(/GOC_DECREES=".*Royal Feast/.test(save), "the save doesn't keep the standing feast");
check(!/GOC_DECREES=".*Royal Relief/.test(save), `the relief didn't lapse after its seasons (${last})`);
fs.rmSync(fc.dir, { recursive: true, force: true });
done();
