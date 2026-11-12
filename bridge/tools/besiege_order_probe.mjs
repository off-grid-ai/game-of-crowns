// Guards READY.md line 7's order half, "capture a town" (casebook, War and sieges: A siege is a season, Total War:
// Attila): the King selects his host and gives it Besiege on a house's town from the command card, and the town
// ends in the crown's hands. One path, the bridge's (one writer): the card's Besiege row (realm/data/host_command.json,
// send) is asked of POST /host/order as hosts.js order(); each season hosts.js season() walks the host by Freeciv's
// moves and, at the walls, starts the siege (campaigns.js startCampaign); campaigns.js resolveCampaigns has Freeciv
// assault (realm_assault) until Freeciv's own conquest takes the town (tools/capture_probe.mjs guards that last step
// on its own). Bare Freeciv on 5579 with our ruleset, a Norman crown and one house at war; the bridge's own functions
// with a probe context and a scratch GOC_HOME (Mac's realm is never touched). Exits 1 on a failure.
//   node tools/besiege_order_probe.mjs        (from bridge/)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import zlib from "node:zlib";

process.env.GOC_HOME = fs.mkdtempSync(path.join(os.tmpdir(), "goc-besiege-"));  // before chronicles.js loads
const { bareFreeciv, checker } = await import("./fc_probe_lib.mjs");
const Hosts = await import("../hosts.js");
const Camp = await import("../campaigns.js");
const { editRow } = await import("../savefile.js");
const { houseFor } = await import("../narrator.js");

const { check, done } = checker("BESIEGE ORDER");
const PORT = 5579;
const card = JSON.parse(fs.readFileSync(new URL("../../realm/data/host_command.json", import.meta.url), "utf8"));
const row = card.orders.find((o) => o.order === "besiege");
check(row, "the command card has no Besiege");

const a = await bareFreeciv({ port: PORT, serv: ["set nationset all", "set aifill 0", "set minplayers 0", "set timeout -1", "set saveturns 1", 'set autosaves "TURN|GAMEOVER"', 'set savename "probe"',
  "create Crown", "create Foe", 'playernation Crown norman 1 "The King"', 'playernation Foe english 1 "Lord Foe"', "set endturn 50", "start"] });
check(await a.until(/Game ended as the turn limit/, 180000), "the game didn't run");
const first = fs.readdirSync(a.dir).filter((f) => /-auto\.sav\.zst$/.test(f)).sort().pop();
await a.quit();
// At war, as the King's march makes it (the bridge's diplomacy writer; written into the save here, as capture_probe does).
const atWar = path.join(a.dir, "probe-war.sav.zst");
let text = zlib.zstdDecompressSync(fs.readFileSync(path.join(a.dir, first))).toString();
for (const [p, q] of [[0, 1], [1, 0]]) text = editRow(text, p, "diplstate", q, (c) => { c[0] = c[1] = '"War"'; if (c[2] === "0") c[2] = "1"; c[3] = c[4] = "0"; });
fs.writeFileSync(atWar, zlib.zstdCompressSync(Buffer.from(text)));
const b = await bareFreeciv({ port: PORT, save: atWar, saves: a.dir });
await b.until(/Now accepting new client connections/, 30000);
check(/WHO 2/.test((await b.cmd('lua cmd local n = 0; for p in players_iterate() do local r = p.nation and p.nation:rule_name() if r == "Norman" then PCROWN = p n = n + 1 elseif r == "English" then PFOE = p n = n + 1 end end; log.normal("WHO %d", n)', /WHO /)) ?? ""), "no Norman crown and English house");

// The realm as the bridge's /world holds it, read off Freeciv: players, towns, units.
let seq = 0;
async function snapshot(turn) {
  const tag = `SNAP${++seq}`;
  const line = await b.cmd(`lua cmd local s = ""; for p in players_iterate() do s = s .. string.format("P%d:%s;", p.id, p.nation:rule_name()); for c in p:cities_iterate() do s = s .. string.format("C%d:%d:%d:%d:%d;", c.id, p.id, c.tile.x, c.tile.y, c.size) end; for u in p:units_iterate() do s = s .. string.format("U%d:%d:%d:%d:%s;", u.id, p.id, u.tile.x, u.tile.y, u.utype:rule_name()) end end; log.normal("${tag} %s.", s)`, new RegExp(`${tag} `));
  const w = { turn, players: [], cities: [], units: [] };
  for (const m of (line ?? "").matchAll(/P(\d+):([A-Za-z]+);/g)) w.players.push({ id: +m[1], nation: m[2], name: m[2] === "Norman" ? "The King" : "Lord Foe" });
  for (const m of (line ?? "").matchAll(/C(\d+):(\d+):(\d+):(\d+):(\d+);/g)) w.cities.push({ id: +m[1], owner: +m[2], x: +m[3], y: +m[4], size: +m[5] });
  for (const m of (line ?? "").matchAll(/U(\d+):(\d+):(\d+):(\d+):([A-Za-z ]+);/g)) w.units.push({ id: +m[1], owner: +m[2], x: +m[3], y: +m[4], type: m[5] });
  return w;
}

// The house's largest town, grown on its own over fifty seasons, emptied of its men. (Freeciv razes a size-1 town
// it conquers; a loaded game that isn't running refuses Join City, and one that runs to its end removes its players,
// so the bridge's seasons are stepped in the loaded game.)
let world = await snapshot(1);
const crown = world.players.find((p) => houseFor(p).crown);
const foe = world.players.find((p) => p !== crown);
const town = world.cities.filter((c) => c.owner === foe?.id).sort((x, y) => y.size - x.size)[0];
check(crown && foe && town, `no crown, house and town (${JSON.stringify(world.players)} ${JSON.stringify(world.cities)})`);
if (!town) { await b.quit(); done(); }
// Its men cleared from three tiles round, too: a company of theirs in the fields would hold the King's men off by
// Freeciv's zones of control, which is the realm's rule but not what this probe tests.
const emptied = await b.cmd(`lua cmd local c = find.city(nil, ${town.id}); local gone = {}; for t in c.tile:square_iterate(3) do for u in t:units_iterate() do if u.owner == c.owner then gone[#gone + 1] = u end end end; for _, u in ipairs(gone) do edit.unit_kill(u, "disbanded", nil) end; log.normal("EMPTIED %d", c.size)`, /EMPTIED/);
check(/EMPTIED [2-9]/.test(emptied ?? ""), `the house's town is still a hamlet (${emptied}): Freeciv razes a size-1 town it conquers`);
// The host two tiles off, with land between it and the walls (so its walk is one step: the step that must stop
// short of the town's tile).
const placed = await b.cmd(`lua cmd local c = find.city(nil, ${town.id}); local crown = PCROWN; local k = find.unit_type("Knights"); local n = 0; for t in c.tile:square_iterate(2) do local between = false; if t:sq_distance(c.tile) >= 4 and not t:city() and t.terrain:class_name() == "Land" and t:num_units() == 0 then for m in t:square_iterate(1) do if m:sq_distance(c.tile) <= 2 and m ~= c.tile and m.terrain:class_name() == "Land" then between = true end end end; if n < 3 and between then edit.create_unit(crown, t, k, 2, nil, -1); n = n + 1 end end; log.normal("HOSTSET %d", n)`, /HOSTSET/);
check(/HOSTSET [1-9]/.test(placed ?? ""), `couldn't set the host near the town (${placed})`);

// The probe's realm: a reign running under a scratch chronicle; what the bridge would do beside (favour, deeds,
// scenes) is noted, not done.
const meta = { id: "besiege-probe", status: "running", hostOrders: [], campaigns: [] };
fs.mkdirSync(path.join(process.env.GOC_HOME, "chronicles", meta.id, "state"), { recursive: true });
fs.writeFileSync(path.join(process.env.GOC_HOME, "chronicles", "active"), meta.id);  // the reign running (no map.json: hosts.js counts straight steps)
const records = [];
const send = (l) => b.send(l);
const campCtx = () => ({ world, meta, send, record: (r) => records.push(r), scene: () => {}, deed: () => {}, shiftFavour: () => {},
  greatHouses: () => world.players.filter((p) => !houseFor(p).crown && !houseFor(p).wild), SOLDIER: (u) => !Camp.CIVILIAN.has(u.type),
  detail: () => ({ players: [{ slot: crown.id, atWarWith: [foe.id] }] }), diplomacy: () => {} });

// The King selects his host and gives it Besiege on the town: the card's row, asked of the bridge.
world = await snapshot(1);
const host = Hosts.list({ world, meta })[0];
check(host, "the crown has no host in the field");
const body = { host: host?.id, order: row?.send ?? row?.order, city: town.id };
const [code, out] = Hosts.order({ world, meta, sworn: () => false, crownSeat: () => null }, body);
check(code === 200, `the bridge refused the card's Besiege ${JSON.stringify(body)}: ${JSON.stringify(out)}`);
check(/lays siege/.test(out?.text ?? ""), `the bridge's answer doesn't lay siege: ${out?.text ?? out?.error}`);
console.log(`  card: ${JSON.stringify(body)} -> ${code} ${out?.text ?? out?.error}`);

// Season by season, as season.js runs them: the host walks (Freeciv's moves), lays siege at the walls, assaults.
let took = -1;
let sieged = -1;
let inside = false;  // the King's men stood in the house's town while it was still the house's
for (let turn = 2; turn <= 12 && took < 0; turn++) {
  world = await snapshot(turn);
  Hosts.season({ world, meta, send, record: (r) => records.push(r), besiege: (c) => Camp.startCampaign(campCtx(), c) }, turn);
  await b.cmd("lua cmd log.normal(\"SEASON\")", /SEASON/);
  world = await snapshot(turn);
  if (sieged < 0 && (meta.campaigns ?? []).some((c) => c.city === town.id)) sieged = turn;
  if (world.cities.find((c) => c.id === town.id)?.owner === foe.id && world.units.some((u) => u.owner === crown.id && u.x === town.x && u.y === town.y)) inside = true;
  Camp.resolveCampaigns(campCtx(), turn);
  await b.cmd("lua cmd log.normal(\"ASSAULTED\")", /ASSAULTED/);
  world = await snapshot(turn);
  if (world.cities.find((c) => c.id === town.id)?.owner === crown.id) took = turn;
}
check(sieged > 0, "the host never laid siege to the town (hosts.js season, campaigns.js startCampaign)");
check(!inside, "the host walked into the house's town without taking it (its march must halt at the walls)");
check(took > 0, `the town never fell to the crown (sieged in season ${sieged}; ${records.map((r) => r.text).slice(-3).join(" | ")})`);
console.log(`  siege laid in season ${sieged}, the town the crown's in season ${took}`);
await b.quit();
fs.rmSync(a.dir, { recursive: true, force: true });
fs.rmSync(process.env.GOC_HOME, { recursive: true, force: true });
done();
