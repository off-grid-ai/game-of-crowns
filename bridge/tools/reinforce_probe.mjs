// Guards the reinforce decree (READY.md line 9: supporting a house sends your army to reinforce it; casebook,
// Every answer costs, Reigns: the King's host spent on a friend is not at his own walls). One path: the decree
// (crown.js reinforce) hands the hosts path a garrison order (hosts.js, the same march as any other) to the house's
// town under siege, else its seat, and the house's leave opens its gates. No second march system. Bridge only, a
// scratch GOC_HOME (Mac's realm is never touched). Exits 1 on a failure.   node tools/reinforce_probe.mjs
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

process.env.GOC_HOME = fs.mkdtempSync(path.join(os.tmpdir(), "goc-reinforce-"));  // before chronicles.js loads
const chron = await import("../chronicles.js");
const { decree } = await import("../crown.js");
const Hosts = await import("../hosts.js");
const { checker } = await import("./fc_probe_lib.mjs");
const { check, done } = checker("REINFORCE");

fs.mkdirSync(chron.paths("probe").state, { recursive: true });
fs.writeFileSync(path.join(chron.ROOT, "active"), "probe");
const meta = { id: "probe", status: "running" };
const world = { turn: 10, players: [{ id: 0, nation: "Norman", name: "The King", gold: 1000 }, { id: 4, nation: "Welsh", name: "Lord Robb", gold: 100 }, { id: 5, nation: "Castilian", name: "Ximena", gold: 100 }],
  cities: [{ id: 1, owner: 0, x: 0, y: 0, capital: true }, { id: 2, owner: 4, x: 6, y: 0, capital: true }, { id: 3, owner: 4, x: 9, y: 2, besieged: false }, { id: 4, owner: 5, x: 0, y: 9, capital: true }],
  units: [1, 2, 3].map((id) => ({ id, owner: 0, x: 1, y: 0, type: "Knights" })) };
const ctx = { world, meta, sworn: () => false, crownSeat: () => world.cities[0] };
const host = Hosts.list(ctx)[0];
check(host, "no royal host in the probe's realm");

const send = (city) => decree({ action: "reinforce", city, host, price: 60 }, world);
// The house's seat when no town of it is besieged.
let r = send(3);
check(r.hostMarch?.city === 2 && r.hostMarch.order === "garrison" && r.hostMarch.opens === 4, `reinforce didn't send the host to Stormhold's seat (${JSON.stringify(r)})`);
check((r.favour?.[4] ?? 0) > 0, "reinforcing a house didn't warm it");
// Its town under siege first.
world.cities[2].besieged = true;
r = send(2);
check(r.hostMarch?.city === 3, `reinforce didn't go to the besieged town (${JSON.stringify(r.hostMarch)})`);
// The same march path: the hosts path takes the garrison only with the house's leave (not sworn to the crown).
const open = (pid) => pid === r.hostMarch.opens;
const [okCode, ok] = Hosts.order({ ...ctx, sworn: open }, { host: r.hostMarch.host, order: r.hostMarch.order, city: r.hostMarch.city, declared: true });
check(okCode === 200 && (meta.hostOrders ?? []).some((o) => o.kind === "garrison" && o.city === 3), `the hosts path refused the reinforce (${okCode} ${JSON.stringify(ok)})`);
const [shutCode] = Hosts.order({ ...ctx, meta: { id: "probe", status: "running" } }, { host: r.hostMarch.host, order: "garrison", city: 3, declared: true });
check(shutCode === 400, "a house's gates opened to the King's host without its leave");
// Not for the crown's own towns, nor a house he is besieging.
check(send(1).error, "reinforce accepted the crown's own town");
check(decree({ action: "reinforce", city: 2, host, price: 60, marching: (c) => c === 3 }, world).error, "reinforce accepted a house the King is besieging");
console.log(`  reinforce: ${r.text}`);
fs.rmSync(process.env.GOC_HOME, { recursive: true, force: true });
done();
