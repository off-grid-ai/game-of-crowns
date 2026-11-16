// Guards the "someone loses" rules (rivalry.js, meddling.js; Mac 2026-11-16: "if they are at war, why am I sending
// food?", "shouldn't the liege lord be pissed with me for bypassing him?"). Pure: a made-up realm, no Freeciv, no bridge.
//   node tools/tension_rules_probe.mjs        (from bridge/)   exits 1 on a failure
import * as Rivalry from "../rivalry.js";
import * as Meddling from "../meddling.js";

const world = {
  players: [
    { id: 0, nation: "scottish" }, { id: 1, nation: "english" }, { id: 2, nation: "norwegian" }, { id: 9, nation: "norman" },
  ],
  cities: [
    { id: 10, owner: 0, capital: true, x: 0, y: 0 }, { id: 11, owner: 1, capital: true, x: 3, y: 0 },
    { id: 12, owner: 2, capital: true, x: 30, y: 30 }, { id: 13, owner: 2, x: 31, y: 30 }, { id: 14, owner: 9, capital: true, x: 15, y: 15 },
  ],
};
const ctx = (wars) => ({ world, detail: () => ({ players: { 0: { atWarWith: [] }, 1: { atWarWith: wars ? [2] : [] }, 2: { atWarWith: wars ? [1] : [] } } }),
  court: { vassals: () => [{ town: 13, liege: "House Ironreach", owner: 2 }] } });
let bad = 0;
const check = (what, ok) => { if (!ok) bad++; console.log(`${ok ? "PASS" : "FAIL"} ${what}`); };

// Grain to a house at war is aid to its foe: the foe cools as much as it warms.
const atWar = Rivalry.jealous(ctx(true), { 2: 12 });
check("war aid: Goldcrest cools by the aid Ironreach gets", atWar[1] === -12);
check("war aid named first", Rivalry.word(ctx(true), 2).includes("war aid"));
// In peace, the nearest neighbour is jealous by half.
const peace = Rivalry.jealous(ctx(false), { 0: 12 });
check("peace: the neighbour cools by half", peace[1] === -6);
// Grain into a lesser lord's town passes over his liege, who takes it ill.
const vassal = Meddling.apply(ctx(true), "relief", 13, { 2: 12 });
check("meddling: the liege is passed over and cools", vassal[2] < 0);
check("meddling named first", Meddling.word(ctx(true), "relief", 13).includes("Ironreach"));
// Into a great house's own town, help it never asked for warms it a little.
const own = Meddling.apply(ctx(true), "relief", 12, { 2: 12 });
check("meddling: unasked help warms little", own[2] > 0 && own[2] < 12);
// The crown's own town is no one's lands but the King's.
check("the crown's town is not meddling", Meddling.apply(ctx(true), "relief", 14, { 9: 0 })[9] === 0);
process.exit(bad ? 1 : 0);
