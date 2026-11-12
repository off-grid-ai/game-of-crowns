// Guards one order a season to each host, not one for all (supervisor, 2026-11-12; data/hosts.json ordersPerHost;
// Total War's one move a turn per army): on the town_build fixture's world (realm/tools/fixtures) with the crown's
// companies split into two hosts, each host takes its own order in a season; a second order to the same host that
// season is refused, saying why and that another host may still go; each host in /world's list says how many orders
// it has left; a new season gives each its order again. No Freeciv; the chronicle's meta goes to a scratch GOC_HOME.
// Exits 1 on a failure.   node tools/host_orders_probe.mjs        (from bridge/)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

process.env.GOC_HOME = fs.mkdtempSync(path.join(os.tmpdir(), "host-orders-"));
const { checker } = await import("./fc_probe_lib.mjs");
const Hosts = await import("../hosts.js");
const { crownOf } = await import("../realm.js");
const { check, done } = checker("HOST ORDERS");
const world = JSON.parse(fs.readFileSync(new URL("../../realm/tools/fixtures/town_build_world.json", import.meta.url), "utf8"));
const crown = crownOf(world);
check(crown, "the fixture has no crown");
// The crown's men in two hosts far apart: its first two soldiers, each moved to its own corner.
const civ = new Set(world.civilian ?? []);
const men = (world.units ?? []).filter((u) => u.owner === crown?.id && !civ.has(u.type) && !Hosts.SHIPS.has(u.type));
check(men.length >= 2, `the crown has two companies to make two hosts of (${men.length})`);
world.units = (world.units ?? []).filter((u) => u.owner !== crown?.id || u === men[0] || u === men[1]);
Object.assign(men[0], { x: 2, y: 2 });
Object.assign(men[1], { x: 40, y: 60 });
const Chron = await import("../chronicles.js");
fs.mkdirSync(path.dirname(Chron.paths("probe").meta), { recursive: true });
const ctx = { world, meta: { id: "probe", status: "running" }, sworn: () => false, crownSeat: () => null };
let hosts = Hosts.list(ctx);
check(hosts.length === 2, `two hosts (${hosts.length})`);
check(hosts.every((h) => h.ordersLeft === 1), `each host has its one order this season: ${JSON.stringify(hosts.map((h) => h.ordersLeft))}`);
const [a, b] = hosts;
const first = Hosts.order(ctx, { host: a.id, order: "hold" });
const second = Hosts.order(ctx, { host: b.id, order: "hold" });
check(first[0] === 200 && second[0] === 200, `both hosts take an order in one season: ${first[0]} ${second[0]} ${JSON.stringify(second[1]).slice(0, 120)}`);
const again = Hosts.order(ctx, { host: a.id, order: "hold" });
check(again[0] === 400 && /this season/.test(again[1]?.error ?? "") && /Another host/.test(again[1]?.error ?? ""), `a second order to the same host is refused, saying why: ${again[0]} ${again[1]?.error}`);
hosts = Hosts.list(ctx);
check(hosts.every((h) => h.ordersLeft === 0), `both now have none left: ${JSON.stringify(hosts.map((h) => h.ordersLeft))}`);
world.turn += 1;
check(Hosts.list(ctx).every((h) => h.ordersLeft === 1) && Hosts.order(ctx, { host: a.id, order: "hold" })[0] === 200, "the next season each has its order again");
const server = fs.readFileSync(new URL("../server.js", import.meta.url), "utf8");
check(!/hostOrdersLeft/.test(server), "/world still carries one number for all the hosts (hostOrdersLeft)");
fs.rmSync(process.env.GOC_HOME, { recursive: true, force: true });
done();
