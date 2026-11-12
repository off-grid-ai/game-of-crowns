// Guards the King's crossing (Mac: "ships are just to move armies from one point to another"; supervisor's ruling,
// 2026-11-12: the crown raises its ships where it needs them, paying Freeciv's price, and they are disbanded on landing).
// Part A, the order (hosts.js), on a staged land: two shores and a strait of coastal water, the crown's host inland on
// the west, no port and no ship of the crown's anywhere, the goal on the east; Freeciv's moves emulated from the
// bridge's own commands. Asked dry, it answers by sea with the shore, the ships and their price, giving nothing. The march
// is one order that names the shore, the ships and the landing; season by season the host walks to the shore, the crown
// raises and pays for a Trireme there and the host boards it, sails (aboard in /world's hosts), comes ashore, the ship
// is disbanded, and the host marches into the goal. Refused, saying why, when the treasury can't pay; a treasury
// emptied before the shore raises nothing and the host makes camp. Part B, Freeciv's own rules on a bare server
// (5573): realm_ferry_raise raises and charges a Trireme on the water beside a company and boards it (Transport
// Embark), the ship sails with it, realm_ferry_land puts it ashore (Transport Disembark) and disbands the ship; with an
// empty treasury nothing is raised. Exits 1 on a failure.   node tools/crossing_probe.mjs        (from bridge/)
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
const COST = 20;  // units.ruleset's Trireme build_cost: one ship carries both companies (transport_cap 2)
const stage = (opts = {}) => {
  const cities = [{ id: 900, name: "Westhold", x: 1, y: 0, owner: crown.id, size: 4 }, { id: 901, name: "Easthold", x: 10, y: 2, owner: crown.id, size: 4 }];
  const units = [{ id: 1, type: "Pikemen", owner: crown.id, x: 0, y: 2, hp: 10 }, { id: 2, type: "Archers", owner: crown.id, x: 0, y: 3, hp: 10 }];
  const players = fixture.players.map((p) => (p.id === crown.id ? { ...p, gold: opts.gold ?? 500 } : p));
  const world = { ...fixture, players, turn: 50, width: W, height: H, civilian: fixture.civilian ?? [], cities, units };
  const meta = { id: "probe", status: "running" };
  fs.mkdirSync(path.dirname(Chron.paths("probe").meta), { recursive: true });
  return { world, meta, sworn: () => true, crownSeat: () => null };
};
const host = (ctx) => Hosts.list(ctx).find((h) => h.units.includes(1));
const purse = (ctx) => ctx.world.players.find((p) => p.id === crown.id).gold;
{
  const ctx = stage({ gold: COST - 1 });
  const out = Hosts.order(ctx, { host: host(ctx).id, order: "march", city: 901 });
  check(out[0] === 400 && /treasury can't pay/.test(out[1]?.error ?? ""), `with too little in the treasury the march is refused, saying why: ${out[0]} ${out[1]?.error}`);
}
// Freeciv's moves, emulated from the commands the bridge sends.
const emulator = (ctx) => {
  const aboard = new Map();  // company -> ship
  const unit = (id) => ctx.world.units.find((u) => u.id === id);
  let next = 100;
  return (cmd) => {
    let m = cmd.match(/find\.unit\(nil, (\d+)\).*ipairs\(\{(.*)\}\) do/);
    if (m) {
      const last = [...m[2].matchAll(/\{(\d+),(\d+)\}/g)].pop();
      const u = unit(Number(m[1]));
      if (last && u) {
        Object.assign(u, { x: Number(last[1]), y: Number(last[2]) });
        for (const [c, h] of aboard) if (h === u.id) Object.assign(unit(c), { x: u.x, y: u.y });
      }
      return;
    }
    if ((m = cmd.match(/realm_ferry_raise\((\d+), "([\d,]*)", (\d+), (\d+), (\d+), (\d+)\)/))) {
      const p = ctx.world.players.find((q) => q.id === Number(m[1]));
      if (!p || p.gold < Number(m[6])) return;
      p.gold -= Number(m[6]);
      const ships = [];
      for (let k = 0; k < Number(m[5]); k++) { ships.push(next); ctx.world.units.push({ id: next++, type: "Trireme", owner: p.id, x: Number(m[3]), y: Number(m[4]), hp: 10 }); }
      m[2].split(",").map(Number).forEach((c, k) => { aboard.set(c, ships[Math.floor(k / 2)]); Object.assign(unit(c), { x: Number(m[3]), y: Number(m[4]) }); });
      return;
    }
    if ((m = cmd.match(/realm_ferry_land\("([\d,]*)", (\d+), (\d+), "([\d,]*)"\)/))) {
      for (const c of m[1].split(",").map(Number)) { aboard.delete(c); Object.assign(unit(c), { x: Number(m[2]), y: Number(m[3]) }); }
      const gone = new Set(m[4].split(",").filter(Boolean).map(Number));
      ctx.world.units = ctx.world.units.filter((u) => !gone.has(u.id));
    }
  };
};
const run = (ctx, seasons, before = () => {}) => {
  const said = [];
  let sawAboard = false;
  const send = emulator(ctx);
  for (let s = 0; s < seasons; s++) {
    ctx.world.turn += 1;
    before(s);
    Hosts.season({ ...ctx, send, record: (r) => said.push(r.text) }, ctx.world.turn);
    if (host(ctx)?.aboard) sawAboard = true;
    if (said.some((t) => /has reached|makes camp/.test(t))) break;
  }
  return { said, sawAboard };
};
const ctx = stage();
{
  // Asked dry (GoC's render pass, before it spends the host's one order): the plan, nothing given.
  const left = Hosts.ordersLeft(ctx, host(ctx).id);
  const sea = Hosts.order(ctx, { host: host(ctx).id, order: "march", city: 901, dry: true });
  check(sea[0] === 200 && sea[1]?.dry && sea[1]?.by === "sea" && sea[1]?.sea?.coast?.x === 3 && sea[1]?.sea?.ships === 1 && sea[1]?.sea?.cost === COST && sea[1]?.seasons >= 1,
    `asked dry, the march over water answers by sea: the shore, one ship, its price: ${JSON.stringify(sea)}`);
  const land = Hosts.order(ctx, { host: host(ctx).id, order: "march", city: 900, dry: true });
  check(land[0] === 200 && land[1]?.by === "land" && !land[1]?.sea, `asked dry, a march over land answers by land: ${JSON.stringify(land)}`);
  check(!(ctx.meta.hostOrders ?? []).length && Hosts.ordersLeft(ctx, host(ctx).id) === left && purse(ctx) === 500, `asked dry, nothing is given: no order, the season's orders untouched (${left}), nothing paid`);
  const hold = Hosts.order(ctx, { host: host(ctx).id, order: "hold", dry: true });
  check(hold[0] === 400 && !(ctx.meta.hostOrders ?? []).length, "only a march is asked dry");
}
check(!ctx.world.units.some((u) => u.type === "Trireme") && !ctx.world.cities.some((c) => c.x === 3), "staged with no port and no ship of the crown's");
const out = Hosts.order(ctx, { host: host(ctx).id, order: "march", city: 901 });
check(out[0] === 200 && /raises a ship for 20 gold/.test(out[1]?.text ?? ""), `the march over water is one order that raises a ship at its price: ${out[0]} ${out[1]?.text ?? out[1]?.error}`);
const o = ctx.meta.hostOrders?.[0];
check(o?.sea?.coast?.x === 3 && o.sea.water?.x === 4 && o.sea.ships === 1 && o.sea.cost === COST && o.sea.landing?.x >= 8, `it names the shore, the water, the ship and the landing: ${JSON.stringify(o?.sea)}`);
const { said, sawAboard } = run(ctx, 12);
check(said.some((t) => /takes ship: the crown raises a ship for 20 gold/.test(t)) && purse(ctx) === 500 - COST, `at the shore the crown raises the ship and pays for it (treasury ${purse(ctx)}): ${said.join(" | ")}`);
check(sawAboard, "while at sea /world shows the host aboard (hosts[].aboard)");
check(said.some((t) => /comes ashore.*the ships are disbanded/.test(t)) && !ctx.world.units.some((u) => u.type === "Trireme"), "it comes ashore and the ship is disbanded");
check(said.some((t) => /has reached/.test(t)) && [1, 2].every((id) => ctx.world.units.find((u) => u.id === id).x >= 8), `and marches on to the goal: ${JSON.stringify([1, 2].map((id) => { const u = ctx.world.units.find((v) => v.id === id); return [u.x, u.y]; }))}`);
check(Hosts.list(ctx).every((h) => !h.aboard), "ashore, no host is aboard");
{
  // The treasury emptied on the road: at the shore nothing is raised, nothing paid, and the host makes camp.
  const c2 = stage();
  Hosts.order(c2, { host: host(c2).id, order: "march", city: 901 });
  const r = run(c2, 8, () => { c2.world.players.find((p) => p.id === crown.id).gold = 0; });
  check(r.said.some((t) => /treasury could not pay/.test(t)) && !c2.world.units.some((u) => u.type === "Trireme") && host(c2)?.order?.kind === "hold",
    `with the treasury emptied before the shore, no ship and the host makes camp: ${r.said.join(" | ")}`);
}

// Part B. Freeciv's own boarding and landing.
const lua = fs.readFileSync(new URL("../data/realmrules/script.lua", import.meta.url), "utf8");
check(/function realm_ferry_raise/.test(lua) && /function realm_ferry_land/.test(lua), "the ruleset's Lua raises the ships and lands a host");
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
  'local man = edit.create_unit(me, f.c, find.unit_type("Horsemen"), 0, nil, -1)',
  'local id = string.format("%d", man.id)',
  'edit.change_gold(me, -me:gold())',
  'realm_ferry_raise(me.id, id, f.o.x, f.o.y, 1, 20)',
  'log.normal("FERRYPROBE unpaid %s", tostring(man:transporter() == nil and f.o:num_units() == 0))',
  'edit.change_gold(me, 100)',
  'realm_ferry_raise(me.id, id, f.o.x, f.o.y, 1, 20)',
  'local ship = man:transporter()',
  'log.normal("FERRYPROBE aboard %s paid %d", tostring(ship ~= nil and ship.utype:rule_name() == "Trireme"), 100 - me:gold())',
  'if ship == nil then return end',
  'local sid = string.format("%d", ship.id)',
  'realm_release(sid)',
  'pcall(edit.unit_move, ship, f.o2, 0, nil, false, false, false, false, false)',
  'realm_hold(sid)',
  'log.normal("FERRYPROBE sailed %s", tostring(man.tile.id == f.o2.id and ship.tile.id == f.o2.id))',
  'realm_ferry_land(id, f.b.x, f.b.y, sid)',
  'log.normal("FERRYPROBE ashore %s disbanded %s", tostring(man.tile.id == f.b.id and man:transporter() == nil), tostring(find.unit(nil, tonumber(sid)) == nil))',
].join("\n");
const file = path.join(fc.dir, "ferry.lua");
fs.writeFileSync(file, stageLua + "\n");
await fc.cmd(`lua file ${file}`, /FERRYPROBE (ashore|no coast)/, 30000);
const line = (k) => fc.lines.find((l) => l.includes(`FERRYPROBE ${k}`)) ?? "";
check(!line("no coast"), "the map had no coast to cross");
check(/unpaid true/.test(line("unpaid")), `with an empty treasury no ship is raised: ${line("unpaid") || fc.lines.filter((l) => /rror|FERRY/.test(l)).slice(-3)}`);
check(/aboard true paid 20/.test(line("aboard")), `the crown raises a Trireme on the water, pays its 20 gold, and the company boards it by Freeciv's rules: ${line("aboard") || fc.lines.filter((l) => /rror|FERRY/.test(l)).slice(-3)}`);
check(/sailed true/.test(line("sailed")), `the Trireme sails with it: ${line("sailed")}`);
check(/ashore true disbanded true/.test(line("ashore")), `it comes ashore by Freeciv's rules and the ship is disbanded: ${line("ashore")}`);
await fc.quit();
fs.rmSync(a.dir, { recursive: true, force: true });
fs.rmSync(process.env.GOC_HOME, { recursive: true, force: true });
done();
