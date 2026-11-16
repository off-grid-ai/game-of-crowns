// Guards the realm's matters (matters/*.js; Mac 2026-11-16: "is this really filled with tension?", "both are pussy
// options", "the personality I've chosen should have some weightage"). Pure: a made-up realm, no Freeciv, no bridge.
//   node tools/matters_probe.mjs        (from bridge/)   exits 1 on a failure
import * as Nature from "../matters/nature.js";
import { Hunger } from "../matters/hunger.js";
import { Cold } from "../matters/cold.js";
import { scope } from "../matters/scope.js";

let bad = 0;
const check = (what, ok) => { if (!ok) bad++; console.log(`${ok ? "PASS" : "FAIL"} ${what}`); };
const warlord = { royals: { king: { name: "Aldric", focus: "war", traits: [] }, consort: null, children: [], kin: [] } };
const courtly = { royals: { king: { name: "Aldric", focus: "court", traits: [] }, consort: null, children: [], kin: [] } };

// A warlord sees the hard answers first, keeps one soft one, and it says it goes against him.
const acts = () => [{ label: "A feast", action: "feast" }, { label: "March", action: "march" }, { label: "Ward", action: "ward" }, { label: "Take a town", action: "grant" }];
const w = Nature.pick(warlord, acts(), 3);
check("warlord: hard answers first", w[0].action !== "feast" && w[1].action !== "feast");
check("warlord: one soft answer kept, marked against his nature", w.some((a) => a.action === "feast" && /against your nature/.test(a.label)));
const c = Nature.pick(courtly, acts(), 3);
check("courtly: the feast first", c[0].action === "feast");

const players = [{ id: 0, house: { name: "House Crown", crown: true }, gold: 500 }, { id: 1, house: { name: "House Sunspire" }, atWarWith: [] }, { id: 2, house: { name: "House Highfell" }, atWarWith: [] }];
const cities = [{ id: 10, owner: 0, capital: true, x: 0, y: 0, title: "Kingsmere" }, { id: 11, owner: 1, capital: true, x: 5, y: 0, title: "Sunspire", famine: true, size: 6 },
  { id: 12, owner: 1, x: 6, y: 0, title: "Elder Reach", famine: true, size: 4 }, { id: 13, owner: 2, capital: true, x: 9, y: 0, title: "Highfell" }];
const ctx = { world: { turn: 10, players, cities }, meta: { ...warlord, tithe: 0.1 }, favourOf: (pid) => ({ 1: 20, 2: 80 })[pid] ?? 50, favourWhy: {}, court: null };
const s = scope(ctx, players, cities, {});
// Two starving towns are one matter, both its places.
const h = new Hunger().build(ctx, s);
check("hunger: two starving towns, one matter", h.length === 1 && h[0].places.includes(11) && h[0].places.includes(12));
check("hunger: Leave it carries its price", h[0].acts.some((a) => a.ui === "leave" && /Sunspire −8/.test(a.label)));
// An angry house can be taught a lesson, not only feasted.
const cold = new Cold().build(ctx, s);
check("cold house: a hard answer is offered", cold[0].acts.some((a) => ["march", "grant", "ward"].includes(a.action)));
check("cold house: at most three answers and Leave it", cold[0].acts.length <= 4 && cold[0].acts.at(-1).ui === "leave");
process.exit(bad ? 1 : 0);
