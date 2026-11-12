// Guards READY.md line 7, "capture a town" (casebook, War and sieges: A siege is a season, Total War: Attila): on the
// King's order the royal host takes a house's town in Freeciv (realm_assault: Freeciv's own conquest) and the town
// changes hands; a hamlet (size 1) is taken, never razed (Mac, 2026-11-12: realm_spare_hamlet grows it by Freeciv's
// Join City first). The crown's AI still takes none unbidden: actions.ruleset keeps Norman out of Freeciv's Conquer
// City. Bare Freeciv, our ruleset, a Norman crown and an English house, no bridge. Exits 1 on a failure.
//   node tools/capture_probe.mjs        (from bridge/)
// Freeciv refuses actions (Join City) in a game loaded but not started, so the setup and the assault run in turn
// hooks of a running game, and the probe judges by Freeciv's own events.
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";
import * as Lua from "../lua.js";
import { editRow } from "../savefile.js";

const { check, done } = checker("CAPTURE");
const PORT = 5578;

// The crown's AI on its own takes no town: the two Conquer City enablers keep Norman out, and the third lets the
// crown conquer only while the Royal Warrant stands (realm_assault raises it for the King's march-in alone).
const rules = fs.readFileSync(new URL("../data/realmrules/actions.ruleset", import.meta.url), "utf8").split(/\n(?=\[)/).filter((x) => /^\[actionenabler_conquer_city/.test(x));
const royal = rules.filter((x) => /_royal\]/.test(x));
check(rules.length === 3 && rules.filter((x) => !royal.includes(x)).every((x) => /"Nation",\s*"Norman",\s*"Player",\s*FALSE/.test(x)), "a Conquer City enabler lets the crown's AI take a town unbidden");
check(royal.length === 1 && /"Building",\s*"Royal Warrant",\s*"Player",\s*TRUE/.test(royal[0]), "the crown's conquest isn't bound to the King's Royal Warrant");

const a = await bareFreeciv({ port: PORT, serv: ["set nationset all", "set aifill 0", "set minplayers 0", "set timeout -1", "set saveturns 1", 'set autosaves "TURN|GAMEOVER"', 'set savename "probe"',
  "create Crown", "create Foe", 'playernation Crown norman 1 "The King"', 'playernation Foe english 1 "Lord Foe"', "set endturn 3", "start"] });
check(await a.until(/Game ended as the turn limit/, 90000), "the game didn't run");
const first = fs.readdirSync(a.dir).filter((f) => /-auto\.sav\.zst$/.test(f)).sort().pop();
await a.quit();

// At war, as the King's march makes it (server.js setDiplomacy writes the save; done the same here). Crown and
// house are players 0 and 1, as created.
const CROWN = 0, FOE = 1;
const atWar = path.join(a.dir, "probe-war.sav.zst");
let text = zlib.zstdDecompressSync(fs.readFileSync(path.join(a.dir, first))).toString();
for (const [p, q] of [[CROWN, FOE], [FOE, CROWN]]) text = editRow(text, p, "diplstate", q, (c) => { c[0] = c[1] = '"War"'; if (c[2] === "0") c[2] = "1"; c[3] = c[4] = "0"; });
fs.writeFileSync(atWar, zlib.zstdCompressSync(Buffer.from(text)));
const b = await bareFreeciv({ port: PORT, save: atWar, saves: a.dir, serv: ["set timeout -1"] });
await b.until(/Now accepting new client connections/, 30000);

// Two towns of the house, founded here so the probe never depends on where its AI settled: one to grow to size 3,
// and a hamlet left at size 1.
const who = await b.cmd(`lua cmd PCROWN, PFOE = find.player(${CROWN}), find.player(${FOE}); function open_ground(t) local k = 0 for x in t:square_iterate(1) do if x ~= t and not x:city() and x.terrain:class_name() == "Land" then k = k + 1 end end return k >= 4 and not t:city() and t.terrain:class_name() == "Land" and t:num_units() == 0 end; local n = 0; for t in whole_map_iterate() do if n < 2 and open_ground(t) then pcall(edit.create_city, PFOE, t, "Probe" .. n) if t:city() then n = n + 1; if n == 1 then TOWN = t:city() else HAMLET = t:city() end end end end; for t in whole_map_iterate() do if not OURS and open_ground(t) then pcall(edit.create_city, PCROWN, t, "Probe2") OURS = t:city() end end; log.normal("SETUP %s %s %d %d %d %d", PCROWN.nation:rule_name(), PFOE.nation:rule_name(), n, TOWN and TOWN.id or -1, HAMLET and HAMLET.id or -1, OURS and OURS.id or -1)`, /SETUP /);
const [, crownNation, , made, townId, hamletId, oursId] = (who ?? "").match(/SETUP (\w+) (\w+) (\d+) (-?\d+) (-?\d+) (-?\d+)/) ?? [];
check(crownNation === "Norman" && made === "2" && Number(oursId) >= 0, `no Norman crown or no three towns founded (${who})`);

// Turn 4: the town grows to 3 by Freeciv's Join City. Turn 5: the towns emptied, two of the King's companies
// beside each of the house's, the King's order (Lua.assault, realm_assault); and a house's knight takes the crown's.
// The hook goes in as a file (the console cuts a long line).
const hook = path.join(a.dir, "probe_hook.lua");
fs.writeFileSync(hook, `function probe_turn(turn)
  if turn == 4 then
    local m = find.unit_type("Migrants")
    for i = 1, 2 do local u = edit.create_unit(PFOE, TOWN.tile, m, 0, TOWN, -1); pcall(edit.perform_action, u, find.action("Join City"), TOWN) end
    log.normal("PROBE grown %d hamlet %d", TOWN.size, HAMLET.size)
  elseif turn == 5 then
    -- All in one breath (between turns the AIs move men in and out): each town emptied, the attackers set
    -- beside it, then the King's assault on the house's two, and the house's own Conquer City on the crown's.
    local function empty(c) local gone = {} for u in c.tile:units_iterate() do gone[#gone + 1] = u end for _, u in ipairs(gone) do edit.unit_kill(u, "disbanded", nil) end end
    local function beside(c, owner, n)
      local made = {}
      for t in c.tile:square_iterate(1) do
        if #made < n and t ~= c.tile and not t:city() and t.terrain:class_name() == "Land" then
          local gone = {} for u in t:units_iterate() do gone[#gone + 1] = u end for _, u in ipairs(gone) do edit.unit_kill(u, "disbanded", nil) end
          made[#made + 1] = edit.create_unit(owner, t, find.unit_type("Knights"), 2, nil, -1)
        end
      end
      return made
    end
    for _, c in ipairs({TOWN, HAMLET, OURS}) do empty(c) end
    beside(TOWN, PCROWN, 2) beside(HAMLET, PCROWN, 2)
    local foeman = beside(OURS, PFOE, 1)[1]
    ${Lua.assault(townId, CROWN)}
    ${Lua.assault(hamletId, CROWN)}
    if foeman then pcall(edit.perform_action, foeman, find.action("Conquer City"), OURS) end
  end
end; signal.connect("turn_begin", "probe_turn"); log.normal("HOOKED")`);
await b.cmd(`lua file ${hook}`, /HOOKED/);
b.send("set endturn 5");
b.send("start");
check(await b.until(/Game ended as the turn limit/, 90000), "the game didn't run on");
const ev = b.lines.filter((l) => l.includes("EVENT {")).map((l) => JSON.parse(l.slice(l.indexOf("{"))));
const grown = b.lines.find((l) => /PROBE grown/.test(l));
check(/PROBE grown 3 hamlet 1/.test(grown ?? ""), `the setup didn't give a size-3 town and a hamlet (${grown})`);
const taken = (id) => ev.find((e) => e.kind === "city_transferred" && Number(e.city) === Number(id) && e.reason === "conquest" && Number(e.to) === CROWN);
const razed = (id) => ev.some((e) => e.kind === "city_destroyed" && Number(e.city) === Number(id));
check(taken(townId), `the King's host didn't take the empty town ${townId} (Freeciv sent no conquest to the crown)`);
check(taken(hamletId) && !razed(hamletId), `the King's capture razed or missed the hamlet ${hamletId}`);
// Any conquest, not only the King's: the house takes a crown hamlet by Freeciv's own Conquer City, and it stays a town.
const foeTook = ev.find((e) => e.kind === "city_transferred" && Number(e.city) === Number(oursId) && e.reason === "conquest" && Number(e.to) === FOE);
check(foeTook && !razed(oursId), `a house's conquest razed or missed the crown's hamlet ${oursId}`);
console.log(`  assaults: ${ev.filter((e) => e.kind === "assault").map((e) => `${e.city} men ${e.men} blows ${e.blows} -> ${e.owner}`).join("; ")}`);
console.log(`  town ${townId}: ${taken(townId) ? "taken" : "not taken"}; hamlet ${hamletId}: ${razed(hamletId) ? "razed" : taken(hamletId) ? "taken, still a town" : "not taken"}; the house's conquest of hamlet ${oursId}: ${razed(oursId) ? "razed" : foeTook ? "taken, still a town" : "not taken"}`);
await b.quit();
fs.rmSync(a.dir, { recursive: true, force: true });
done();
