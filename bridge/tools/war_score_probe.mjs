// Guards the war score and the peace terms it sets (peace.js standing/offer; WAR.md step 9, CK3's war score). Pure: a
// made-up realm, no Freeciv, no bridge.
//   node tools/war_score_probe.mjs        (from bridge/)   exits 1 on a failure
import * as Peace from "../peace.js";

let bad = 0;
const check = (what, ok) => { if (!ok) bad++; console.log(`${ok ? "PASS" : "FAIL"} ${what}`); };
const players = [{ id: 0, nation: "norman", gold: 500 }, { id: 1, nation: "scottish", gold: 400 }];
const town = (id, owner, capital = false) => ({ id, owner, capital, x: id, y: 0, size: 3, title: `T${id}` });
const realm = (owners) => ({ turn: 20, players, cities: owners.map(([id, o, cap]) => town(id, o, cap)) });
let asked = null;
const court = { lordOfHouse: () => ({ id: "l1", name: "Lord Rorik", gender: "male" }), arcPetition: (p) => { asked = p; } };
const run = (world, meta) => { asked = null; Peace.season({ meta, world, court, detail: () => ({ players: { 0: { atWarWith: [1] } } }) }, world.turn); return asked; };

// The war begins: four towns each, nothing yet.
const meta = { battles: [] };
run(realm([[1, 0, true], [2, 0], [3, 0], [4, 0], [5, 1, true], [6, 1], [7, 1], [8, 1]]), meta);
meta.crownWars[1].since = 0;
check("a fresh war stands at 0", Peace.standing(meta, realm([[1, 0, true], [5, 1, true]].concat([[2, 0], [3, 0], [4, 0], [6, 1], [7, 1], [8, 1]])), 1).score === 0);

// One town taken: +20, gold asked but no town.
let w = realm([[1, 0, true], [2, 0], [3, 0], [4, 0], [5, 1, true], [6, 0], [7, 1], [8, 1]]);
meta.crownWars[1].offered = null;
let p = run(w, meta);
check("one town taken: score +20", Peace.standing(meta, w, 1).score === 20);
check("winning a little: gold asked, no town", p && p.options.some((o) => o.id === "gold") && !p.options.some((o) => o.id === "town"));

// Two battles won as well: +40, a town asked.
meta.battles = [{ id: "a", turn: 5, crown: "won", sides: [{ house: 0 }, { house: 1 }] }, { id: "b", turn: 6, crown: "won", sides: [{ house: 0 }, { house: 1 }] }];
meta.crownWars[1].offered = null;
p = run(w, meta);
check("a town and two battles: score +40", Peace.standing(meta, w, 1).score === 40);
check("winning well: a town asked", p && p.options.some((o) => o.id === "town"));
meta.crownWars[1].offered = null;
run(w, meta);
check("a battle is counted once", Peace.standing(meta, w, 1).score === 40);

// The seat taken counts double, and the score is held to ±100.
w = realm([[1, 0, true], [2, 0], [3, 0], [4, 0], [5, 0], [6, 0], [7, 0], [8, 1]]);
check("the seat and every town: held at 100", Peace.standing(meta, w, 1).score === 100);

// Losing: the crown pays, and cedes a town when it is losing badly.
const lost = { battles: [] };
run(realm([[1, 0, true], [2, 0], [3, 0], [4, 0], [5, 1, true], [6, 1]]), lost);
lost.crownWars[1].since = 0;
lost.crownWars[1].offered = null;
w = realm([[1, 0, true], [2, 1], [3, 1], [4, 0], [5, 1, true], [6, 1]]);  // never the seat: the crown keeps a town to give
p = run(w, lost);
check("two towns lost: score −40", Peace.standing(lost, w, 1).score === -40);
check("losing badly: the crown is asked a town or gold", p && p.options.some((o) => o.id === "cede") && p.options.some((o) => o.id === "pay"));

process.exit(bad ? 1 : 0);
