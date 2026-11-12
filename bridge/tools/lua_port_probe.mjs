// Guards the lua.js port (integration audit #2, READY.md line 15: one port to Freeciv): the bridge sends Freeciv
// only Lua written in lua.js (and the ruleset's own realm_* functions it calls). Any `edit.` or `realm_...(` in
// bridge code outside lua.js is a second path round the port. Comments are free to name them. Exits 1 on a breach.
//   node tools/lua_port_probe.mjs        (from bridge/)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";
import * as Lua from "../lua.js";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const { check, done } = checker("LUA PORT");
let files = 0;
for (const f of fs.readdirSync(BRIDGE).filter((x) => x.endsWith(".js") && x !== "lua.js")) {
  files++;
  fs.readFileSync(path.join(BRIDGE, f), "utf8").split("\n").forEach((line, i) => {
    const code = line.replace(/\/\/.*$/, "");
    if (/\bedit\.\w+|\brealm_\w+\s*\(/.test(code)) check(false, `${f}:${i + 1} sends Lua round the port: ${line.trim().slice(0, 110)}`);
  });
}
console.log(`  ${files} bridge files read`);

// The port's own calls do what they say, in Freeciv (the ruleset's realm_levy, realm_building, realm_take_men).
const b = await bareFreeciv({ port: 5585, save: path.join(BRIDGE, "baseline/aldmere/saves/realm-T0038-Y-2150-auto.sav.zst") });
check(await b.until(/Now accepting new client connections/, 30000), "the baseline didn't load");
const town = Number((await b.cmd('lua cmd local p = realm_find_player(1) for c in p:cities_iterate() do log.normal("TOWN %d", c.id) return end', /TOWN /))?.match(/TOWN (\d+)/)?.[1]);
const men = async () => Number((await b.cmd('lua cmd local n = 0 for u in realm_find_player(1):units_iterate() do if not u.utype:has_flag("NonMil") then n = n + 1 end end log.normal("MEN %d", n)', /MEN /))?.match(/MEN (\d+)/)?.[1]);
const has = async (name) => /HAS true/.test((await b.cmd(`lua cmd log.normal("HAS %s", tostring(find.city(nil, ${town}):has_building(find.building_type("${name}"))))`, /HAS /)) ?? "");
const m0 = await men();
await b.cmd(`lua cmd ${Lua.levy(town, ["Knights", "Pikemen|Warriors", "NoSuchUnit|Archers"])}`);
const m1 = await men();
check(m1 === m0 + 3, `Lua.levy raised ${m1 - m0} men (want 3)`);
await b.cmd(`lua cmd ${Lua.takeMen(1, 2)}`);
check((await men()) === m1 - 2, "Lua.takeMen didn't take two men off");
await b.cmd(`lua cmd ${Lua.building(town, "Granary")}`);
check(await has("Granary"), "Lua.building didn't set a Granary down");
await b.cmd(`lua cmd ${Lua.building(town, "Granary", false)}`);
check(!(await has("Granary")), "Lua.building didn't take the Granary up");
console.log(`  levy ${m0} -> ${m1} men, take two off, a granary up and down`);
await b.quit();
done();
