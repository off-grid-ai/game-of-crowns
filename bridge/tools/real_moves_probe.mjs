// Guards step 7 (docs/research/freeciv-leverage-2026-11-12.md): hosts move and muster by Freeciv's rules. The
// King's hosts step by edit.unit_move (Freeciv's own move test and handling), never a teleport: a step onto land
// is made, a step onto water is refused. A host raised by realm_host is homed to its house's nearest town, so
// Freeciv charges its upkeep. Bare Freeciv on 5571, our ruleset, no bridge. Exits 1 on a failure.
//   node tools/real_moves_probe.mjs        (from bridge/)
import fs from "node:fs";
import path from "node:path";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";

const { check, done } = checker("REAL MOVES");
const hosts = fs.readFileSync(new URL("../hosts.js", import.meta.url), "utf8");
check(!/unit_teleport/.test(hosts), "hosts.js still teleports its companies");
const MOVE = hosts.match(/const MOVE = "([^"]+)"/)?.[1];
check(MOVE && MOVE.startsWith("edit.unit_move, u, t,"), "hosts.js has no edit.unit_move step");

const a = await bareFreeciv({ serv: ["set aifill 2", "set minplayers 0", "set timeout -1", "set saveturns 1", 'set autosaves "TURN|GAMEOVER"', 'set savename "probe"', "set endturn 4", "start"] });
check(await a.until(/Game ended as the turn limit/, 90000), "the game didn't run");
const first = fs.readdirSync(a.dir).filter((f) => /-auto\.sav\.zst$/.test(f)).sort().pop();
await a.quit();
const b = await bareFreeciv({ save: path.join(a.dir, first), saves: a.dir });
await b.until(/Now accepting new client connections/, 30000);
// A host raised beside a house's town: every company homed there.
const raised = await b.cmd('lua cmd for p in players_iterate() do for c in p:cities_iterate() do realm_host(p, c.tile.x, c.tile.y, {"Pikemen"}, 2); local n, homed = 0, 0; for u in p:units_iterate() do if u.utype:rule_name() == "Pikemen" then n = n + 1; if u:get_homecity() then homed = homed + 1 end end end; log.normal("RAISED %d %d", n, homed) return end end', /RAISED /);
const [, n, homed] = (raised ?? "").match(/RAISED (\d+) (\d+)/) ?? [];
check(Number(n) >= 1 && n === homed, `a raised host isn't homed to a town (${raised})`);
// One step on land is made, one onto water refused (the same call hosts.js sends, MOVE), by a company set on
// open land beside both (the Lua goes in a file: the console cuts long lines).
const stepFile = path.join(a.dir, "step.lua");
fs.writeFileSync(stepFile, `
local p
for q in players_iterate() do if q:num_cities() > 0 then p = q break end end
local function open(t) return t and not t:city() and t:num_units() == 0 end
local function wet(t) local n = t.terrain:rule_name(); return n:find("Ocean") or n == "Lake" end
for t in whole_map_iterate() do
  if open(t) and not wet(t) then
    local land, water
    for a in t:square_iterate(1) do
      if a ~= t and open(a) then if wet(a) then water = water or a else land = land or a end end
    end
    if land and water then
      local u = edit.create_unit(p, t, find.unit_type("Pikemen"), 0, nil, -1)
      local s = ""
      local t = water; pcall(${MOVE}); s = s .. "water:" .. tostring(u.tile == water) .. " "
      t = land; pcall(${MOVE}); s = s .. "land:" .. tostring(u.tile == land)
      log.normal("STEP %s.", s)
      return
    end
  end
end
log.normal("STEP none.")
`);
const step = await b.cmd(`lua file ${stepFile}`, /STEP /);
check(/land:true/.test(step ?? ""), `a step onto open land wasn't made (${step})`);
check(!/water:true/.test(step ?? ""), `a foot company stepped onto water (${step})`);
await b.quit();
fs.rmSync(a.dir, { recursive: true, force: true });
done();
