// Guards the camps moving while a war runs (war.js camps; WAR.md step 8). Pure: a made-up realm, no Freeciv, no bridge.
//   node tools/war_camps_probe.mjs        (from bridge/)   exits 1 on a failure
import * as War from "../war.js";

let bad = 0;
const check = (what, ok) => { if (!ok) bad++; console.log(`${ok ? "PASS" : "FAIL"} ${what}`); };
for (const k of ["leave", "bandwagon", "balance"]) War.WAR.camps[k] = 1;  // every roll comes up, so the rule is what decides
// 0 crown, 1 the foe, 2 an ally, 3 waits, 4 waits cold.
const players = [0, 1, 2, 3, 4].map((id) => ({ id, nation: ["norman", "scottish", "english", "french", "welsh"][id] }));
const cities = players.map((p) => ({ id: 10 + p.id, owner: p.id, capital: true, x: p.id, y: 0, size: 3 }));
const make = (favour, crownWar, alarm = 0) => {
  const lines = [], dip = [], onWar = [];
  const w = { house: 1, since: 0, allies: [2], against: [], waiting: [3, 4], commit: { 2: 0.3 } };
  const meta = { wars: [w], alliances: { 2: 20 }, alarm, crownWars: { 1: crownWar } };
  const ctx = { world: { turn: 4, players, cities }, meta, favourOf: (pid) => favour[pid] ?? 50, record: (r) => lines.push(r.text),
    diplomacy: (x) => dip.push(x), court: { onWar: (x) => onWar.push(x) }, detail: () => ({ players: [] }) };
  return { ctx, w, lines, dip, onWar };
};
// Even war, everyone content: nobody moves.
let r = make({ 2: 70, 3: 60, 4: 60 }, { since: 0, towns: 1, crown: 1 });
War.camps(r.ctx, 4, r.w);
check("an even war: nobody moves", r.lines.length === 0 && r.w.allies.includes(2));
// The ally gone cold leaves, and makes its armistice with the foe.
r = make({ 2: 20, 3: 60, 4: 60 }, { since: 0, towns: 1, crown: 1 });
War.camps(r.ctx, 4, r.w);
check("a cold ally leaves the war", !r.w.allies.includes(2) && r.w.waiting.includes(2) && r.dip.some((d) => d[0] === 2 && d[1] === 1 && d[3] === "Armistice"));
check("one house moves a look", r.lines.length === 1);
// The crown well ahead (two battles and the seat would be more; here 3 battles won = +30): a content waiter joins it.
r = make({ 2: 70, 3: 60, 4: 60 }, { since: 0, towns: 1, crown: 1, won: 3 });
War.camps(r.ctx, 4, r.w);
check("ahead by 30: a waiter rides with the King", r.w.allies.includes(3) && r.dip.some((d) => d[0] === 3 && d[3] === "War"));
// The same, with the realm afraid of the King: a cold waiter takes the foe's side.
r = make({ 2: 70, 3: 60, 4: 10 }, { since: 0, towns: 1, crown: 1, won: 3 }, 80);
r.w.waiting = [4, 3];
War.camps(r.ctx, 4, r.w);
check("alarm high: a cold waiter balances against the King", r.w.against.includes(4) && r.onWar.some((x) => x[0] === 4 && x[1] === 0));
// Looked at only every camps.every seasons, and never in the war's first.
r = make({ 2: 20 }, { since: 0, towns: 1, crown: 1 });
War.camps(r.ctx, 3, r.w);
check("off-season: no look", r.lines.length === 0);
process.exit(bad ? 1 : 0);
