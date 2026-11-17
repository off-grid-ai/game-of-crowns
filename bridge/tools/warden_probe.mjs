// Guards a beaten house's land and lord (warden.js, matters/warden.js; Mac 2026-11-17: a conquered house's land always
// goes to a minor house as warden, of the King's choosing; the wrong warden causes trouble; the beaten lord's fate) and
// the alliance path in a war between two houses (matters/house_war.js "Join A against B"). Pure: a made-up realm, a
// stand-in court, no Freeciv, no bridge; the meta is saved under a throwaway GOC_HOME.
//   node tools/warden_probe.mjs        (from bridge/)   exits 1 on a failure
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

process.env.GOC_HOME = fs.mkdtempSync(path.join(os.tmpdir(), "warden-probe-"));
fs.mkdirSync(path.join(process.env.GOC_HOME, "chronicles", "probe"), { recursive: true });
const W = await import("../warden.js");
const { Warden, Fate, Defiant } = await import("../matters/warden.js");
const { HouseWar } = await import("../matters/house_war.js");
const { scope } = await import("../matters/scope.js");
const { houseFor } = await import("../narrator.js");

let bad = 0;
const check = (what, ok) => { if (!ok) bad++; console.log(`${ok ? "PASS" : "FAIL"} ${what}`); };

// 0 the crown, 1 the beaten house (Wolfholt), 2 sworn to the King, 3 sworn, 4 cold.
const players = [0, 1, 2, 3, 4].map((id) => ({ id, nation: ["norman", "scottish", "english", "french", "welsh"][id], atWarWith: [] }));
const cities = [{ id: 10, owner: 0, capital: true }, { id: 11, owner: 0, capital: false }, { id: 12, owner: 0, capital: false },
  { id: 20, owner: 2, capital: true }, { id: 21, owner: 2 }, { id: 30, owner: 3, capital: true }, { id: 31, owner: 3 }, { id: 40, owner: 4, capital: true }]
  .map((c) => ({ x: c.id, y: 0, size: 3, title: `T${c.id}`, ...c }));
const fav = { 2: 70, 3: 55, 4: 20 };
const P = (id, o) => ({ id, alive: true, traits: [], loyalty: 50, relationships: {}, memories: [], children: [], parents: [], ...o });
const people = {
  c1: P("c1", { name: "Lord Wolf", surname: "Wolf", rank: "lord", playerId: 1, house: "House Wolfholt", seat: 11 }),
  c2: P("c2", { name: "Ser Hollin", surname: "Hollin", rank: "bannerman", playerId: 1, seat: 12, traits: ["ambitious", "vengeful"], loyalty: 40 }),
  c3: P("c3", { name: "Ser Pell", surname: "Pell", rank: "bannerman", playerId: 2, seat: 21, traits: ["honourable", "content"], loyalty: 80 }),
  c4: P("c4", { name: "Ser Dale", surname: "Dale", rank: "bannerman", playerId: 3, seat: 31, traits: ["patient"], loyalty: 60 }),
  k0: P("k0", { name: "King", surname: "Crown", rank: "lord", playerId: 0, seat: 10 }),
};
const dead = [];
const court = {
  people, alive: () => Object.values(people).filter((c) => c.alive), lordOfHouse: (pid) => Object.values(people).find((c) => c.rank === "lord" && c.playerId === pid && c.alive),
  opinion: (a, b) => people[a]?.relationships[b]?.opinion ?? 0, remember: () => {}, save: () => {}, die: (c) => { c.alive = false; dead.push(c.id); },
};
const meta = { id: "probe", royals: { king: { name: "Aldric", focus: null, traits: [] }, consort: null, children: [], kin: [] } };
const world = { turn: 8, players, cities };
const ctx = { world, meta, court, favourOf: (pid) => fav[pid] ?? 50, sworn: () => false, record: () => {} };
const view = players.map((p) => ({ ...p, house: houseFor(p) }));
const s = () => scope(ctx, view, cities, {});

// Toppled: the crown holds the towns, the lord kneels landless, a warden is to be named.
W.raise(ctx, { house: 1, seat: 11 }, [11, 12], 8);
const e = W.of(meta, 1);
check("toppled: an entry with its towns, its seat", e && e.seat === 11 && e.towns.length === 2 && e.warden == null);
check("toppled: the beaten lord has no seat", people.c1.seat == null && e.lord === "c1");
check("until a warden is named the house is lost", W.lost(meta, world).includes(1));

const wm = new Warden().build(ctx, s());
check("warden matter: three candidates, no Leave it", wm.length === 1 && wm[0].acts.length === 3 && !wm[0].acts.some((a) => a.ui === "leave"));
const hol = wm[0].acts.find((a) => a.city === 12), pell = wm[0].acts.find((a) => a.city === 21);
check("the beaten house's own bannerman is offered, his tie named", hol && /sworn to Wolfholt/.test(hol.label) && /ambitious/.test(hol.label) && /loyalty 40/.test(hol.label));
check("a sworn house's bannerman is offered as its man", pell && /Goldcrest's man/.test(pell.label) && /honourable/.test(pell.label));
const risk = Object.fromEntries(W.candidates(ctx, e).map((x) => [x.c.id, x.risk]));
check("the ambitious kinsman is riskier than the honourable loyal man", risk.c2 > 50 && risk.c3 < 20 && /may defy/.test(hol.label) && /holds steady/.test(pell.label));
check("the why carries the families' lore", /Hollin: /.test(wm[0].why) && /Pell: /.test(wm[0].why));

// Named: the loyal man holds for the crown, and the house counts.
check("refused: a man not offered", W.refuse(ctx, { action: "warden", to: 1, city: 40 }) != null);
check("allowed: an offered man", W.refuse(ctx, { action: "warden", to: 1, city: 21 }) == null);
const dec = W.decree({ cmd: { action: "warden", to: 1, city: 21, favourOf: ctx.favourOf }, world, cost: 0, pay: "", owner: players[2] });
check("naming a sworn house's man warms that house", dec.favour[2] === W.WARDEN.pick.liege);
W.apply(ctx, dec.warden);
check("the warden is re-lieged to the crown and seated", people.c3.playerId === 0 && people.c3.seat === 11 && people.c3.warden === 1 && e.warden === "c3");
e.defiesAt = null;
check("a loyal warden: the house is the King's", !W.lost(meta, world).includes(1));
check("no warden matter once named", new Warden().build(ctx, s()).length === 0);

// The lord's fate: the axe makes the cold houses fear, the warm ones uneasy; mercy the other way.
const fm = new Fate().build(ctx, s());
check("fate matter: spare, imprison, behead", fm.length === 1 && ["spare", "imprison", "behead"].every((k) => fm[0].acts.some((a) => a.action === k)));
const axe = W.decree({ cmd: { action: "behead", to: 1, city: 11, favourOf: ctx.favourOf }, world, cost: 0, pay: "" });
check("behead: cold house fears (+), warm house uneasy (−)", axe.favour[4] === W.WARDEN.fate.behead.cold && axe.favour[2] === W.WARDEN.fate.behead.warm);
const mercy = W.decree({ cmd: { action: "spare", to: 1, city: 11, favourOf: ctx.favourOf }, world, cost: 0, pay: "" });
check("spare: the cold house thinks him weak (−)", mercy.favour[4] < 0 && mercy.favour[2] > 0);
W.apply(ctx, axe.warden);
check("beheaded: the lord dies, the fate is settled", dead.includes("c1") && e.fate === "behead" && new Fate().build(ctx, s()).length === 0);

// The wrong warden: he defies some seasons later; the house is lost again until the King acts.
e.defiesAt = 12;
world.turn = 12;
check("a defiant warden: the house is lost again", W.lost(meta, world).includes(1));
const dm = new Defiant().build(ctx, s());
check("defiant matter: buy back or strip, and Leave it has a price", dm.length === 1 && dm[0].acts.some((a) => a.action === "regrant") && dm[0].acts.some((a) => a.action === "unseat") && dm[0].acts.at(-1).ui === "leave");
W.apply(ctx, { act: "unseat", house: 1, city: 11 });
check("stripped: the land wants a warden again, not him", e.warden == null && people.c3.seat == null && !W.candidates(ctx, e).some((x) => x.c.id === "c3"));
const again = new Warden().build(ctx, s());
check("the warden matter comes back as a new hearing", again.length === 1 && again[0].occur !== wm[0].occur);

// The alliance path: join one side of a war between two houses.
players[2].atWarWith = [3]; players[3].atWarWith = [2];
const view2 = players.map((p) => ({ ...p, house: houseFor(p) }));
const hw = new HouseWar().build(ctx, scope(ctx, view2, cities, {}));
const side = hw[0]?.acts.find((a) => a.action === "side");
check("house war: Join the warmer house against the other", side && /^Join Goldcrest against Thornvale/.test(side.label) && side.to === 2 && side.city === 30);
process.exit(bad ? 1 : 0);
