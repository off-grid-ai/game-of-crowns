// Guards READY.md line 8's Attack and line 14's drag to face (casebook, War and sieges; Warcraft III's command card,
// Total War's drag to face): the King selects his host, gives it Attack on a foe's men from the command card, and it
// falls on them by Freeciv's own combat. One path, the bridge's: the card's Attack row (realm/data/host_command.json)
// is asked of POST /host/order as hosts.js order(); each season hosts.js season() follows the foe and, from beside
// him, sends Lua.strike (Freeciv's Attack action: its enablers, war and moves left, and its combat decide).
//   1. The bridge: the order is kept on its target with the face asked; a season with the host still off walks it;
//      a season beside the foe sends the strike for those companies on his tile; the foe gone, the host stands.
//      list() shows the face. No Freeciv (a scratch GOC_HOME; Mac's realm is never touched).
//   2. Freeciv: in a running game at war, the strike Lua.strike writes, from beside a house's men, is fought (the
//      foe's men or the King's fall). Bare Freeciv on 5577 with our ruleset (Freeciv refuses actions in a game
//      loaded but not running, so it runs in a turn hook, as capture_probe does).
// Exits 1 on a failure.   node tools/attack_order_probe.mjs        (from bridge/)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import zlib from "node:zlib";

process.env.GOC_HOME = fs.mkdtempSync(path.join(os.tmpdir(), "goc-attack-"));  // before chronicles.js loads
const { bareFreeciv, checker } = await import("./fc_probe_lib.mjs");
const Hosts = await import("../hosts.js");
const Lua = await import("../lua.js");
const { editRow } = await import("../savefile.js");

const { check, done } = checker("ATTACK ORDER");
const card = JSON.parse(fs.readFileSync(new URL("../../realm/data/host_command.json", import.meta.url), "utf8"));
const row = card.orders.find((o) => o.order === "attack");
check(row, "the command card has no Attack");

// --- 1. The bridge ------------------------------------------------------------------------------------------
const meta = { id: "attack-probe", status: "running", hostOrders: [], campaigns: [] };
fs.mkdirSync(path.join(process.env.GOC_HOME, "chronicles", meta.id, "state"), { recursive: true });
fs.writeFileSync(path.join(process.env.GOC_HOME, "chronicles", "active"), meta.id);
const players = [{ id: 0, nation: "Norman", name: "The King" }, { id: 1, nation: "English", name: "Lord Foe" }];
const world = (units, turn) => ({ turn, width: 40, height: 40, players, cities: [], units });
const knights = (x, y) => [10, 11, 12].map((id, i) => ({ id, owner: 0, x: x + (i === 2 ? 1 : 0), y, type: "Knights" }));
let w = world([...knights(2, 2), { id: 50, owner: 1, x: 8, y: 2, type: "Pikemen" }], 1);
const host = Hosts.list({ world: w, meta })[0];
const face = 1.2;
const body = { host: host?.id, order: row?.send ?? row?.order, x: 8, y: 2, face };
const [code, out] = Hosts.order({ world: w, meta, sworn: () => false, crownSeat: () => null }, body);
check(code === 200, `the bridge refused the card's Attack ${JSON.stringify(body)}: ${JSON.stringify(out)}`);
const kept = (meta.hostOrders ?? [])[0];
check(kept?.kind === "attack" && kept.target === 50 && kept.face === face, `the order isn't kept on its target with its face: ${JSON.stringify(kept)}`);
check(Hosts.list({ world: w, meta })[0]?.order?.face === face, "list() doesn't show the face (the army layer forms the line by it)");
const [bad] = Hosts.order({ world: w, meta, sworn: () => false, crownSeat: () => null }, { host: host?.id, order: "attack", x: 30, y: 30 });
check(bad === 400, "Attack on empty ground was taken");
let sent = [];
const season = (units, turn) => { w = world(units, turn); sent = []; Hosts.season({ world: w, meta, send: (l) => sent.push(l), record: () => {} }, turn); };
// Off: the host walks (no strike yet). The foe has moved a tile: he is followed.
season([...knights(2, 2), { id: 50, owner: 1, x: 9, y: 2, type: "Pikemen" }], 2);
check(sent.length > 0 && !sent.some((l) => l.includes(`find.action("Attack")`)), `a host still off the foe walked: ${sent.length} commands, a strike among them: ${sent.some((l) => l.includes("Attack"))}`);
check(meta.hostOrders[0]?.x === 9, "the host doesn't follow the foe where he goes");
// Beside him: every company strikes his tile, through Lua.strike.
season([{ id: 10, owner: 0, x: 8, y: 2, type: "Knights" }, { id: 11, owner: 0, x: 8, y: 3, type: "Knights" }, { id: 12, owner: 0, x: 9, y: 3, type: "Knights" }, { id: 50, owner: 1, x: 9, y: 2, type: "Pikemen" }], 3);
check(sent.includes(`lua cmd ${Lua.strike([10, 11, 12], 9, 2)}`), `beside the foe, no strike by Lua.strike: ${JSON.stringify(sent).slice(0, 300)}`);
// He is gone: the host stands, keeping its face.
season([{ id: 10, owner: 0, x: 8, y: 2, type: "Knights" }, { id: 11, owner: 0, x: 8, y: 3, type: "Knights" }, { id: 12, owner: 0, x: 9, y: 3, type: "Knights" }], 4);
check(meta.hostOrders[0]?.kind === "hold" && meta.hostOrders[0]?.face === face, `the foe gone, the host doesn't stand: ${JSON.stringify(meta.hostOrders[0])}`);
// A march keeps its face too.
meta.hostOrders = [];
Hosts.order({ world: w, meta, sworn: () => false, crownSeat: () => null }, { host: 10, order: "march", x: 20, y: 20, face: -0.5 });
check(meta.hostOrders[0]?.face === -0.5, "a march doesn't keep its face");

// --- 2. Freeciv -------------------------------------------------------------------------------------------
const PORT = 5577;
const a = await bareFreeciv({ port: PORT, serv: ["set nationset all", "set aifill 0", "set minplayers 0", "set timeout -1", "set saveturns 1", 'set autosaves "TURN|GAMEOVER"', 'set savename "probe"',
  "create Crown", "create Foe", 'playernation Crown norman 1 "The King"', 'playernation Foe english 1 "Lord Foe"', "set endturn 3", "start"] });
check(await a.until(/Game ended as the turn limit/, 90000), "the game didn't run");
const first = fs.readdirSync(a.dir).filter((f) => /-auto\.sav\.zst$/.test(f)).sort().pop();
await a.quit();
const atWar = path.join(a.dir, "probe-war.sav.zst");
let text = zlib.zstdDecompressSync(fs.readFileSync(path.join(a.dir, first))).toString();
for (const [p, q] of [[0, 1], [1, 0]]) text = editRow(text, p, "diplstate", q, (c) => { c[0] = c[1] = '"War"'; if (c[2] === "0") c[2] = "1"; c[3] = c[4] = "0"; });
fs.writeFileSync(atWar, zlib.zstdCompressSync(Buffer.from(text)));
const b = await bareFreeciv({ port: PORT, save: atWar, saves: a.dir, serv: ["set timeout -1"] });
await b.until(/Now accepting new client connections/, 30000);
// Turn 4: a house's company of pikemen on open land, three of the King's knights beside it, and the strike.
// Its Lua is Lua.strike's own, with the knights' ids read back in Lua (FOES/IDS), so the port is what's tested.
const strike = Lua.strike([-1], 0, 0).replace("{-1}", "IDS").replace("find.tile(0, 0)", "SPOT");
// (in a file: the console cuts long lines, as real_moves_probe found)
const hookFile = path.join(a.dir, "strike.lua");
fs.writeFileSync(hookFile, `function probe_turn(turn)
  if turn ~= 4 then return end
  local crown, foe = find.player(0), find.player(1)
  for t in whole_map_iterate() do
    if not SPOT and not t:city() and t.terrain:class_name() == "Land" and t:num_units() == 0 then
      local open = 0 for n in t:square_iterate(1) do if n ~= t and not n:city() and n.terrain:class_name() == "Land" and n:num_units() == 0 then open = open + 1 end end
      if open >= 3 then SPOT = t end
    end
  end
  local p = edit.create_unit(foe, SPOT, find.unit_type("Pikemen"), 0, nil, -1)
  IDS = {} for n in SPOT:square_iterate(1) do if #IDS < 3 and n ~= SPOT and not n:city() and n.terrain:class_name() == "Land" and n:num_units() == 0 then IDS[#IDS + 1] = edit.create_unit(crown, n, find.unit_type("Knights"), 0, nil, -1).id end end
  local function theirs() local k = 0 for v in SPOT:units_iterate() do if v.owner == foe then k = k + 1 end end return k end
  local before = theirs()
  ${strike}
  local knights = 0 for _, id in ipairs(IDS) do if find.unit(nil, id) then knights = knights + 1 end end
  log.normal("PROBE strike: foe %d -> %d, knights %d -> %d", before, theirs(), #IDS, knights)
end
signal.connect("turn_begin", "probe_turn")
log.normal("HOOKED")
`);
await b.cmd(`lua file ${hookFile}`, /HOOKED/);
b.send("set endturn 4");
b.send("start");
check(await b.until(/Game ended as the turn limit/, 90000), "the game didn't run on");
const fought = b.lines.find((l) => /PROBE strike/.test(l));
const [, f0, f1, k0, k1] = (fought ?? "").match(/foe (\d+) -> (\d+), knights (\d+) -> (\d+)/) ?? [];
check(fought && (Number(f1) < Number(f0) || Number(k1) < Number(k0)), `Freeciv fought no strike (${fought ?? b.lines.filter((l) => /error/.test(l)).slice(-3).join(" | ")})`);
console.log(`  ${fought?.replace(/^.*PROBE /, "") ?? "no strike line"}`);
await b.quit();
fs.rmSync(a.dir, { recursive: true, force: true });
fs.rmSync(process.env.GOC_HOME, { recursive: true, force: true });
done();
