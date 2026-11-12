// Guards "no unit vanishes" (supervisor, after docs/research/freeciv-leverage-2026-11-12.md): a decree that sends
// a house's men home (buy off, cede, make them stop) no longer kills them. They take a homeward order (hosts.js,
// the one mover): held from their AI (lua.js homewardHold), walked to the house's seat by Freeciv's own moves
// (lua.js homewardStep), and disbanded there into the town's production (lua.js disbandHome: Disband Unit Recover,
// shields back), or kept as its garrison when Freeciv refuses. Bare Freeciv on 5571, our ruleset, no bridge.
//   node tools/homeward_probe.mjs        (from bridge/)
import fs from "node:fs";
import path from "node:path";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";
import * as Lua from "../lua.js";
import { readSave } from "../savefile.js";

const { check, done } = checker("HOMEWARD");
const src = (f) => fs.readFileSync(new URL(`../${f}`, import.meta.url), "utf8");
const crownSrc = src("crown.js");
for (const verb of ["buyoff", "settle", "peace", "cede"]) {
  const body = crownSrc.slice(crownSrc.indexOf(`  ${verb}(x) {`), crownSrc.indexOf("\n  },", crownSrc.indexOf(`  ${verb}(x) {`)));
  check(body.length > 20 && !/unit_kill/.test(body), `crown.js ${verb} still kills the men it sends home`);
  check(/homeward/.test(body), `crown.js ${verb} gives no homeward order`);
}
check(/export function homeward/.test(src("hosts.js")), "hosts.js has no homeward order");
for (const f of ["homewardHold", "homewardStep", "disbandHome"]) check(typeof Lua[f] === "function", `lua.js has no ${f}`);
if (typeof Lua.homewardStep !== "function") done();

const a = await bareFreeciv({ serv: ["set aifill 2", "set minplayers 0", "set timeout -1", "set saveturns 1", 'set autosaves "TURN|GAMEOVER"', 'set savename "probe"', "set endturn 6", "start"] });
check(await a.until(/Game ended as the turn limit/, 90000), "the game didn't run");
const first = fs.readdirSync(a.dir).filter((f) => /-auto\.sav\.zst$/.test(f)).sort().pop();
await a.quit();
const b = await bareFreeciv({ save: path.join(a.dir, first), saves: a.dir });
await b.until(/Now accepting new client connections/, 30000);
// A company of a house standing two steps from its town (set here; in play, the men a decree sends home).
const setup = path.join(a.dir, "setup.lua");
fs.writeFileSync(setup, `
for p in players_iterate() do for c in p:cities_iterate() do
  for t in c.tile:square_iterate(2) do
    local mid
    for m in c.tile:square_iterate(1) do if m ~= c.tile and m:sq_distance(t) <= 2 and not m:city() and m:num_units() == 0 and not m.terrain:rule_name():find("Ocean") and m.terrain:rule_name() ~= "Lake" then mid = mid or m end end
    if mid and t:sq_distance(c.tile) >= 4 and not t:city() and t:num_units() == 0 and not t.terrain:rule_name():find("Ocean") and t.terrain:rule_name() ~= "Lake" then
      local u = edit.create_unit(p, t, find.unit_type("Pikemen"), 0, c, -1)
      log.normal("SET %d %d %d %d %d %d", u.id, c.id, mid.x, mid.y, c.tile.x, c.tile.y)
      return
    end
  end
end end
log.normal("SET none")
`);
const set = await b.cmd(`lua file ${setup}`, /SET /);
const [, uid, cid, mx, my, cx, cy] = (set ?? "").match(/SET (\d+) (\d+) (\d+) (\d+) (\d+) (\d+)/)?.map(Number) ?? [];
check(uid, `couldn't set a company away from its town (${set})`);
if (!uid) { await b.quit(); done(); }
const where = async () => [(await b.cmd(`lua cmd local u = find.unit(nil, ${uid}); log.normal("AT %s", u and string.format("%d,%d", u.tile.x, u.tile.y) or "gone")`, /AT /))?.match(/AT (\S+)/)?.[1]];
// The town's shield stock, from a save written now (Freeciv 3.2's Lua doesn't show it).
let saved = 0;
const shields = async (fc) => {
  const name = path.join(a.dir, `stock-${++saved}`);
  await fc.cmd(`save ${name}`, /saved|Game saved/i, 10000);
  const file = fs.readdirSync(a.dir).filter((f) => f.startsWith(`stock-${saved}`)).map((f) => path.join(a.dir, f))[0];
  const s = file ? readSave(file) : {};
  for (let i = 0; s[`player${i}`]; i++) for (const c of s[`player${i}`].c ?? []) if (Number(c.id) === cid) return Number(c.shield_stock);
  return NaN;
};
b.send(`lua cmd ${Lua.homewardHold([uid])}`);
const [from] = await where();
// A season of the AI's own moves: a held company stays where it is.
const turn0 = b.lines.length;
b.send("set endturn 7");
b.send("start");
check(await b.until(/Game ended as the turn limit/, 90000, turn0), "the game didn't run on");
await b.quit();
const c2 = await bareFreeciv({ save: path.join(a.dir, fs.readdirSync(a.dir).filter((f) => /-auto\.sav\.zst$/.test(f)).sort().pop()), saves: a.dir });
await c2.until(/Now accepting new client connections/, 30000);
b.cmd = c2.cmd;
const [held] = await where();
check(held === from, `a held company was moved by its AI (${from} -> ${held})`);
// Home by Freeciv's moves, then disbanded into the town's work.
c2.send(`lua cmd ${Lua.homewardStep(uid, [[mx, my], [cx, cy]])}`);
const [home] = await where();
const before = await shields(c2);
check(home === `${cx},${cy}`, `the company didn't walk home (${from} -> ${home}, town ${cx},${cy})`);
c2.send(`lua cmd ${Lua.disbandHome(uid, cid)}`);
const [after] = await where();
const now = await shields(c2);
check(after === "gone" && now > before, `the company wasn't disbanded into the town's work (unit ${after}, shields ${before} -> ${now})`);
await c2.quit();
fs.rmSync(a.dir, { recursive: true, force: true });
done();
