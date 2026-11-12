// Guards the King's crossing (Mac: "ships are just to move armies from one point to another"; supervisor, 2026-11-12):
// a march with no road over land takes ship. Part A, the order (hosts.js), on a staged land: two shores and a strait
// of coastal water, the crown's host on the west, its port on the west shore with a Trireme in it, the goal on the
// east; Freeciv's moves emulated from the bridge's own commands. The march is one order that names the port, the hull
// and the landing; season by season the host walks to the port, boards, sails (shown aboard in /world's hosts), comes
// ashore and marches into the goal. Refused, saying why, with no port the host can reach, and with no hull free in
// it. Part B, Freeciv's own rules on a bare server (5573): a company boards a Trireme in a coastal town of its own
// (realm_ferry_board: Transport Board/Embark), sails with it a tile, and comes ashore (realm_ferry_land: Transport
// Disembark). Exits 1 on a failure.   node tools/crossing_probe.mjs        (from bridge/)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

process.env.GOC_HOME = fs.mkdtempSync(path.join(os.tmpdir(), "crossing-"));
const { checker, bareFreeciv } = await import("./fc_probe_lib.mjs");
const Chron = await import("../chronicles.js");
const Hosts = await import("../hosts.js");
const { crownOf } = await import("../realm.js");
const { check, done } = checker("CROSSING");

// Part A. The land: x 0-3 west shore, x 4-7 coastal water, x 8-11 east shore; 6 rows.
const W = 12, H = 6;
const tiles = [];
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) tiles.push([x, y, x >= 4 && x <= 7 ? "Ocean" : "Grassland"]);
fs.mkdirSync(Chron.paths("probe").state, { recursive: true });
fs.writeFileSync(path.join(Chron.paths("probe").state, "map.json"), JSON.stringify({ width: W, height: H, tiles }));
Chron.setActive("probe");
const fixture = JSON.parse(fs.readFileSync(new URL("../../realm/tools/fixtures/town_build_world.json", import.meta.url), "utf8"));
const crown = crownOf(fixture);
check(crown, "the fixture has no crown");
const stage = (opts = {}) => {
  const cities = [{ id: 900, name: "Westport", x: 3, y: 2, owner: crown.id, size: 4 }, { id: 901, name: "Easthold", x: 10, y: 2, owner: crown.id, size: 4 }];
  const units = [{ id: 1, type: "Pikemen", owner: crown.id, x: 1, y: 2, hp: 10 }, { id: 2, type: "Archers", owner: crown.id, x: 1, y: 3, hp: 10 }, { id: 3, type: "Trireme", owner: crown.id, x: 3, y: 2, hp: 10 }];
  const world = { ...fixture, turn: 50, width: W, height: H, civilian: fixture.civilian ?? [], cities: opts.noPort ? cities.filter((c) => c.id !== 900) : cities,
    units: opts.noHull ? units.filter((u) => u.type !== "Trireme") : units };
  const meta = { id: "probe", status: "running" };
  fs.mkdirSync(path.dirname(Chron.paths("probe").meta), { recursive: true });
  return { world, meta, sworn: () => true, crownSeat: () => null };
};
const host = (ctx) => Hosts.list(ctx).find((h) => h.units.includes(1));
{
  const ctx = stage({ noPort: true });
  const out = Hosts.order(ctx, { host: host(ctx).id, order: "march", city: 901 });
  check(out[0] === 400 && /port/.test(out[1]?.error ?? ""), `with no port the march is refused, saying why: ${out[0]} ${out[1]?.error}`);
}
{
  const ctx = stage({ noHull: true });
  const out = Hosts.order(ctx, { host: host(ctx).id, order: "march", city: 901 });
  check(out[0] === 400 && /No ship lies free/.test(out[1]?.error ?? ""), `with no hull free the march is refused, saying why: ${out[0]} ${out[1]?.error}`);
}
const ctx = stage();
{
  // Asked dry (GoC's render pass, before it spends the host's one order): the plan, nothing given.
  const left = Hosts.ordersLeft(ctx, host(ctx).id);
  const sea = Hosts.order(ctx, { host: host(ctx).id, order: "march", city: 901, dry: true });
  check(sea[0] === 200 && sea[1]?.dry && sea[1]?.by === "sea" && sea[1]?.sea?.port?.id === 900 && sea[1]?.seasons >= 1, `asked dry, the march over water answers by sea, naming the port: ${JSON.stringify(sea)}`);
  const land = Hosts.order(ctx, { host: host(ctx).id, order: "march", city: 900, dry: true });
  check(land[0] === 200 && land[1]?.by === "land" && !land[1]?.sea, `asked dry, a march over land answers by land: ${JSON.stringify(land)}`);
  check(!(ctx.meta.hostOrders ?? []).length && Hosts.ordersLeft(ctx, host(ctx).id) === left, `asked dry, nothing is given: no order, the season's orders untouched (${left})`);
  const hold = Hosts.order(ctx, { host: host(ctx).id, order: "hold", dry: true });
  check(hold[0] === 400 && !(ctx.meta.hostOrders ?? []).length, "only a march is asked dry");
}
const out = Hosts.order(ctx, { host: host(ctx).id, order: "march", city: 901 });
check(out[0] === 200 && /takes ship/.test(out[1]?.text ?? ""), `the march over water is one order that takes ship: ${out[0]} ${out[1]?.text ?? out[1]?.error}`);
const o = ctx.meta.hostOrders?.[0];
check(o?.sea?.port?.id === 900 && o.sea.hulls.includes(3) && o.sea.landing?.x >= 8, `it names the port, the hull and the landing: ${JSON.stringify(o?.sea)}`);
// The seasons, Freeciv's moves emulated from the commands sent.
const aboard = new Map();  // company -> hull
const unit = (id) => ctx.world.units.find((u) => u.id === id);
const emulate = (cmd) => {
  let m = cmd.match(/find\.unit\(nil, (\d+)\).*ipairs\(\{(.*)\}\) do/);
  if (m) {
    const last = [...m[2].matchAll(/\{(\d+),(\d+)\}/g)].pop();
    if (last) {
      const u = unit(Number(m[1]));
      Object.assign(u, { x: Number(last[1]), y: Number(last[2]) });
      for (const [c, h] of aboard) if (h === u.id) Object.assign(unit(c), { x: u.x, y: u.y });
    }
    return;
  }
  if ((m = cmd.match(/realm_ferry_board\("([\d,]*)", "([\d,]*)"\)/))) {
    const hull = Number(m[2].split(",")[0]);
    for (const c of m[1].split(",").map(Number)) { aboard.set(c, hull); Object.assign(unit(c), { x: unit(hull).x, y: unit(hull).y }); }
    return;
  }
  if ((m = cmd.match(/realm_ferry_land\("([\d,]*)", (\d+), (\d+)\)/))) {
    for (const c of m[1].split(",").map(Number)) { aboard.delete(c); Object.assign(unit(c), { x: Number(m[2]), y: Number(m[3]) }); }
  }
};
const said = [];
let sawAboard = false;
for (let s = 0; s < 12; s++) {
  ctx.world.turn += 1;
  Hosts.season({ ...ctx, send: (cmd) => emulate(cmd), record: (r) => said.push(r.text) }, ctx.world.turn);
  if (host(ctx)?.aboard) sawAboard = true;
  if (said.some((t) => /has reached/.test(t))) break;
}
check(said.some((t) => /takes ship at/.test(t)), `it boards at the port: ${said.join(" | ")}`);
check(sawAboard, "while at sea /world shows the host aboard (hosts[].aboard)");
check(said.some((t) => /comes ashore/.test(t)), "it comes ashore");
check(said.some((t) => /has reached/.test(t)) && [1, 2].every((id) => unit(id).x >= 8), `and marches on to the goal: ${JSON.stringify([1, 2].map((id) => [unit(id).x, unit(id).y]))}`);
check(Hosts.list(ctx).every((h) => !h.aboard), "ashore, no host is aboard");

// Part B. Freeciv's own boarding and landing.
const lua = fs.readFileSync(new URL("../data/realmrules/script.lua", import.meta.url), "utf8");
check(/function realm_ferry_board/.test(lua) && /function realm_ferry_land/.test(lua), "the ruleset's Lua boards and lands a host");
const a = await bareFreeciv({ port: 5573, serv: ["set aifill 2", "set minplayers 0", "set timeout -1", "set saveturns 1", 'set autosaves "TURN|GAMEOVER"', 'set savename "probe"', "set endturn 3", "start"] });
check(await a.until(/Game ended as the turn limit/, 120000), "the game didn't run (ruleset failed to load?)");
const last = fs.readdirSync(a.dir).filter((f) => /-auto\.sav\.zst$/.test(f)).sort().pop();
await a.quit();
const fc = await bareFreeciv({ port: 5573, save: path.join(a.dir, last ?? "none"), saves: a.dir });
await fc.until(/Now accepting new client connections/, 30000);
const stageLua = [
  'local me = nil for p in players_iterate() do me = me or p end',
  'local function land(t) return t.terrain:class_name() == "Land" end',
  'local function shallow(t) return t.terrain:rule_name() == "Ocean" or t.terrain:rule_name() == "Lake" end',
  'local f = nil',
  'for c in whole_map_iterate() do if f == nil and land(c) and not c:city() and c:num_units() == 0 then',
  ' for o in c:square_iterate(1) do if f == nil and shallow(o) and o:num_units() == 0 then',
  '  for o2 in o:square_iterate(1) do if f == nil and o2:sq_distance(o) > 0 and shallow(o2) and o2:num_units() == 0 and o2:sq_distance(c) > 2 then',
  '   for b in o2:square_iterate(1) do if f == nil and land(b) and not b:city() and b:num_units() == 0 and b:sq_distance(c) > 8 then f = {c = c, o = o, o2 = o2, b = b} end end',
  '  end end',
  ' end end',
  'end end',
  'if f == nil then log.normal("FERRYPROBE no coast") return end',
  'edit.create_city(me, f.c, "Probeport")',
  'local ship = edit.create_unit(me, f.c, find.unit_type("Trireme"), 0, nil, -1)',
  'local man = edit.create_unit(me, f.c, find.unit_type("Horsemen"), 0, nil, -1)',
  'SHIP, MAN, LAND = ship, man, f.b',
  'realm_ferry_board(string.format("%d", man.id), string.format("%d", ship.id))',
  'log.normal("FERRYPROBE aboard %s", tostring(man:transporter() ~= nil))',
  'realm_release(string.format("%d", ship.id))',
  'for _, t in ipairs({f.o, f.o2}) do pcall(edit.unit_move, ship, t, 0, nil, false, false, false, false, false) end',
  'realm_hold(string.format("%d", ship.id))',
  'log.normal("FERRYPROBE at ship %d,%d man %d,%d want %d,%d", ship.tile.x, ship.tile.y, man.tile.x, man.tile.y, f.o2.x, f.o2.y)',
  'log.normal("FERRYPROBE sailed %s", tostring(man.tile.id == f.o2.id and ship.tile.id == f.o2.id))',
  'realm_ferry_land(string.format("%d", man.id), f.b.x, f.b.y)',
  'log.normal("FERRYPROBE ashore %s", tostring(man.tile.id == f.b.id and man:transporter() == nil))',
].join("\n");
const file = path.join(fc.dir, "ferry.lua");
fs.writeFileSync(file, stageLua + "\n");
await fc.cmd(`lua file ${file}`, /FERRYPROBE (ashore|no coast)/, 30000);
const line = (k) => fc.lines.find((l) => l.includes(`FERRYPROBE ${k}`)) ?? "";
check(!line("no coast"), "the map had no coast to cross");
check(/aboard true/.test(line("aboard")), `the company boards the Trireme by Freeciv's rules: ${line("aboard") || fc.lines.filter((l) => /rror|FERRY/.test(l)).slice(-3)}`);
check(/sailed true/.test(line("sailed")), `the Trireme sails with it: ${line("sailed")}`);
check(/ashore true/.test(line("ashore")), `it comes ashore by Freeciv's rules: ${line("ashore")}`);
await fc.quit();
fs.rmSync(a.dir, { recursive: true, force: true });
fs.rmSync(process.env.GOC_HOME, { recursive: true, force: true });
done();
