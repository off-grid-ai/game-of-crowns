// Guards step 6 (docs/research/freeciv-leverage-2026-11-12.md): seasons and blight are Freeciv's. A turn is a
// season (calendar fragments, Spring first, as stakes.js calendar counts), four to a year; a blight is a Blight
// building that halves a town's food for its seasons (lua.js decree "blight"), lapses by itself and reports
// "decree_lapsed" so the bridge tells the land recovering; no terrain is edited for it any more.
// Bare Freeciv on 5571, our ruleset, no bridge. Exits 1 on a failure.
//   node tools/seasons_probe.mjs        (from bridge/)
import fs from "node:fs";
import path from "node:path";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";
import * as Lua from "../lua.js";
import { calendar } from "../stakes.js";

const { check, done } = checker("SEASONS");
const src = (f) => fs.readFileSync(new URL(`../${f}`, import.meta.url), "utf8");
check(!fs.existsSync(new URL("../blight.js", import.meta.url)), "blight.js (farmland turned to desert) is still there");
check(!/change_terrain/.test(src("director.js")) && /Lua\.decree\([^)]*"blight"/.test(src("director.js")), "the director's famine doesn't send a Blight");

const fc = await bareFreeciv({ serv: ["set aifill 2", "set minplayers 0", "set timeout -1", "set saveturns 1", 'set autosaves "TURN|GAMEOVER"', 'set savename "probe"', "set endturn 5", "start"] });
check(await fc.until(/Game ended as the turn limit/, 90000), "the game didn't run");
const first = fs.readdirSync(fc.dir).filter((f) => /-auto\.sav\.zst$/.test(f)).sort().pop();
await fc.quit();

const b = await bareFreeciv({ save: path.join(fc.dir, first), saves: fc.dir });
await b.until(/Now accepting new client connections/, 30000);
const now = await b.cmd('lua cmd log.normal("CAL %d %d %d %s", game.current_turn(), game.current_fragment(), game.current_year(), game.current_year_text())', /CAL /);
const [, turn, frag, year] = (now ?? "").match(/CAL (\d+) (\d+) (-?\d+)/) ?? [];
const SEASONS = ["spring", "summer", "autumn", "winter"];
check(frag !== undefined && SEASONS[Number(frag)] === calendar(Number(turn)).season, `Freeciv's season (fragment ${frag}) isn't the bridge's on turn ${turn} (${calendar(Number(turn)).season})`);
check(Number(year) === -4000 + Math.floor((Number(turn) - 1) / 4), `Freeciv's year ${year} on turn ${turn}: not one year per four seasons`);
check(/Spring|Summer|Autumn|Winter/.test(now ?? ""), `the season has no name in Freeciv (${now})`);
const town = Number((await b.cmd('lua cmd for p in players_iterate() do for c in p:cities_iterate() do log.normal("TOWN %d", c.id) return end end', /TOWN /))?.match(/TOWN (\d+)/)?.[1]);
b.send(`lua cmd ${Lua.decree(town, "blight", 1)}`);
check((await b.cmd(`lua cmd log.normal("BLIGHT %s", tostring(find.city(nil, ${town}):has_building(find.building_type("Blight"))))`, /BLIGHT /))?.endsWith(" true"), "the blight set no Blight building");
const from = b.lines.length;
b.send("set endturn 8");
b.send("start");
check(await b.until(/Game ended as the turn limit/, 90000, from), "the loaded game didn't run on");
check(b.lines.slice(from).some((l) => l.includes('"kind":"decree_lapsed"') && l.includes('"building":"Blight"')), "the blight never lapsed (no decree_lapsed event)");
await b.quit();
fs.rmSync(fc.dir, { recursive: true, force: true });
done();
