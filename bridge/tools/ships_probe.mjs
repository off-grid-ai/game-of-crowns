// Guards Mac's call on ships (2026-11-12: "ships are just to move armies from one point to another, that's it"; no
// war by sea): realmrules keeps only the hulls that carry hosts over water, none of them can attack, the bridge's
// list of hulls (data/hosts.json ships) is exactly those, and a host still boards one, crosses and lands. Bare
// Freeciv on 5572, our ruleset, no bridge: the ruleset loads clean, and a company of horse embarks on a Trireme off
// the coast, the Trireme rows a tile, and the company disembarks on a shore it couldn't walk to (Freeciv's own
// Transport Embark, Unit Move and Transport Disembark actions, through edit.perform_action). Exits 1 on a failure.
//   node tools/ships_probe.mjs        (from bridge/)
import fs from "node:fs";
import path from "node:path";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";

const { check, done } = checker("SHIPS");
const rules = fs.readFileSync(new URL("../data/realmrules/units.ruleset", import.meta.url), "utf8");
const units = [...rules.matchAll(/^\[unit_(\w+)\]\n([\s\S]*?)(?=^\[)/gm)].map(([, id, body]) => ({
  id,
  name: (body.match(/^name\s*=\s*_\("([^"]+)"\)/m) ?? [])[1],
  cls: (body.match(/^class\s*=\s*"([^"]+)"/m) ?? [])[1],
  attack: Number((body.match(/^attack\s*=\s*(\d+)/m) ?? [])[1] ?? 0),
  nobuild: /"NoBuild"/.test(body),
}));
const hulls = units.filter((u) => (u.cls === "Sea" || u.cls === "Trireme") && !u.nobuild);  // Storm: an animal, never built
check(hulls.length >= 1 && hulls.length <= 2, `one or two hulls, found ${hulls.map((u) => u.name)}`);
for (const u of hulls) check(u.attack === 0, `${u.name} can attack (${u.attack}): no war by sea`);
const ships = JSON.parse(fs.readFileSync(new URL("../data/hosts.json", import.meta.url), "utf8")).ships;
check(JSON.stringify([...ships].sort()) === JSON.stringify(hulls.map((u) => u.name).sort()), `hosts.json ships ${ships} aren't the ruleset's hulls ${hulls.map((u) => u.name)}`);
for (const gone of ["Caravel", "Frigate", "Ironclad", "Destroyer", "Cruiser", "AEGIS Cruiser", "Battleship", "Submarine", "Carrier", "Transport"]) {
  check(!units.some((u) => u.name === gone), `${gone} is still in the rules`);
  check(!new RegExp(`"${gone}"`).test(rules), `units.ruleset still names "${gone}"`);
}

// A few seasons played (the ruleset loads and runs), then the save loaded to stage the crossing in.
const a = await bareFreeciv({ port: 5572, serv: ["set aifill 2", "set minplayers 0", "set timeout -1", "set saveturns 1", 'set autosaves "TURN|GAMEOVER"', 'set savename "probe"', "set endturn 3", "start"] });
check(await a.until(/Game ended as the turn limit/, 120000), "the game didn't run (ruleset failed to load?)");
const bad = a.lines.filter((l) => /ruleset|Ruleset/.test(l) && /rror|nknown|nvalid|ailed/.test(l));
check(bad.length === 0, `ruleset errors:\n  ${bad.slice(0, 5).join("\n  ")}`);
const last = fs.readdirSync(a.dir).filter((f) => /-auto\.sav\.zst$/.test(f)).sort().pop();
await a.quit();
const fc = await bareFreeciv({ port: 5572, save: path.join(a.dir, last ?? "none"), saves: a.dir });
await fc.until(/Now accepting new client connections/, 30000);
const lua = [
  'local me = nil for p in players_iterate() do me = me or p end',
  'local function land(t) return t.terrain:class_name() == "Land" end',
  'local function shallow(t) return t.terrain:rule_name() == "Ocean" or t.terrain:rule_name() == "Lake" end',
  'local f = nil',
  'for o in whole_map_iterate() do if f == nil and shallow(o) and o:num_units() == 0 then',
  ' for a in o:square_iterate(1) do if f == nil and land(a) and a:num_units() == 0 and not a:city() then',
  '  for o2 in o:square_iterate(1) do if f == nil and o2:sq_distance(o) > 0 and shallow(o2) and o2:num_units() == 0 then',
  '   for b in o2:square_iterate(1) do if f == nil and land(b) and b:num_units() == 0 and not b:city() and b:sq_distance(o) > 2 and b:sq_distance(a) > 8 then f = {o = o, a = a, o2 = o2, b = b} end end',
  '  end end',
  ' end end',
  'end end',
  'if f == nil then log.normal("SHIP no coast") return end',
  'local boat = edit.create_unit(me, f.o, find.unit_type("Trireme"), 0, nil, -1)',
  'local man = edit.create_unit(me, f.a, find.unit_type("Horsemen"), 0, nil, -1)',
  'local e = edit.perform_action(man, find.action("Transport Embark"), boat)',
  'log.normal("SHIP embark %s %s", tostring(e), tostring(man:transporter() ~= nil))',
  'local m = edit.perform_action(boat, find.action("Unit Move"), f.o2)',
  'log.normal("SHIP cross %s %s", tostring(m), tostring(man.tile.id == f.o2.id and boat.tile.id == f.o2.id))',
  'local d = edit.perform_action(man, find.action("Transport Disembark"), f.b) or edit.perform_action(man, find.action("Transport Disembark 2"), f.b)',
  'log.normal("SHIP land %s %s", tostring(d), tostring(man.tile.id == f.b.id and man:transporter() == nil))',
].join("\n");
const file = `${fc.dir}/ship.lua`;  // a console line is too short for it
fs.writeFileSync(file, lua + "\n");
await fc.cmd(`lua file ${file}`, /SHIP (land|no coast)/, 30000);
const said = (k) => fc.lines.find((l) => l.includes(`SHIP ${k}`)) ?? "";
check(!said("no coast"), "the map had no coast to cross");
check(/SHIP embark \S+ true/.test(said("embark")), `the host didn't board: ${said("embark") || fc.lines.filter((l) => /lua|Lua/.test(l)).slice(-3)}`);
check(/SHIP cross \S+ true/.test(said("cross")), `the ship didn't carry it across: ${said("cross")}`);
check(/SHIP land \S+ true/.test(said("land")), `the host didn't land: ${said("land")}`);
await fc.quit();
fs.rmSync(fc.dir, { recursive: true, force: true });
fs.rmSync(a.dir, { recursive: true, force: true });
done();
