// Guards READY.md line 7's storm rule (casebook, War and sieges: a siege is a season; Total War: Attila's captains
// don't throw a company at a full garrison): the royal host storms a besieged town only when its companies at the
// walls are enough against the house's soldiers inside, the walls' edge counted by their wear (data/siege.json,
// campaigns.js stormCall). The failed capture run it answers: one company stormed Thornvale's seat held by eight,
// was killed, and the siege broke. Drives campaigns.js resolveCampaigns itself on a stand-in realm (no Freeciv), a
// siege past its engines' wait, and reads what it asks of Freeciv (realm_assault) and what the realm is told:
//   - one company against eight, walls whole: no assault; the captains say they wait; lifted after their wait, said why;
//   - six against two: stormed at once;
//   - three against two: waits while the walls stand whole, storms once a section is breached;
//   - the King's pressed siege storms whatever the odds (his word).
// Exits 1 on a failure.   node tools/storm_call_probe.mjs   (from bridge/)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

process.env.GOC_HOME = fs.mkdtempSync(path.join(os.tmpdir(), "goc-stormcall-"));  // before chronicles.js loads
fs.mkdirSync(path.join(process.env.GOC_HOME, "chronicles", "storm-call"), { recursive: true });  // where the siege's meta is saved
const Camp = await import("../campaigns.js");
const { checker } = await import("./fc_probe_lib.mjs");
const { check, done } = checker("STORM CALL");

const CROWN = 7, FOE = 3, CITY = 207, TOWN = { x: 11, y: 60 };
// One siege: `beside` royal companies on the tiles round the town, `inside` of the house's in it, the walls' wear.
function siege({ beside, inside, wear = 0, press = false, seasons = 1 }) {
  const units = [];
  let id = 1000;
  for (let i = 0; i < beside; i++) units.push({ id: id++, owner: CROWN, type: "Pikemen", x: TOWN.x - 1, y: TOWN.y + (i % 3) - 1 });
  for (let i = 0; i < inside; i++) units.push({ id: id++, owner: FOE, type: "Pikemen", x: TOWN.x, y: TOWN.y });
  const world = { turn: 50, players: [{ id: CROWN, nation: "norman", name: "The King", gold: 500 }, { id: FOE, nation: "french", name: "Lord Thornvale", gold: 0 }],
    cities: [{ id: CITY, owner: FOE, x: TOWN.x, y: TOWN.y, size: 6, name: "Rosehall" }], units };
  const meta = { id: "storm-call", status: "running", campaigns: [{ city: CITY, house: FOE, turn: 40, asked: true, ruled: true, ...(press ? { press: true } : {}) }],
    damage: { [CITY]: { walls: Array(8).fill(0).map((_, s) => (s === 2 ? wear : 0)), burnt: 0, heard: 0, kindled: [] } } };
  const sent = [], told = [];
  const ctx = { world, meta, court: null, send: (c) => sent.push(c), record: (r) => told.push(r.text), scene: () => {}, deed: () => {}, shiftFavour: () => {},
    greatHouses: () => world.players.filter((p) => p.id !== CROWN), SOLDIER: (u) => !Camp.CIVILIAN.has(u.type),
    detail: () => ({ players: [{ slot: CROWN, atWarWith: [FOE] }] }), diplomacy: () => {} };
  const per = [];
  for (let s = 0; s < seasons; s++) {
    const before = sent.length;
    Camp.resolveCampaigns(ctx, world.turn + s);
    per.push(sent.slice(before).some((c) => /realm_assault/.test(c)));
  }
  return { stormed: per, told, lifted: !(meta.campaigns ?? []).some((c) => c.city === CITY) };
}

const weak = siege({ beside: 1, inside: 8, seasons: 6 });
console.log(`  1 against 8: stormed ${JSON.stringify(weak.stormed)}, lifted ${weak.lifted}; told: ${weak.told.join(" | ")}`);
check(!weak.stormed.some(Boolean), "one company stormed a town held by eight (it is thrown away)");
check(weak.told.some((t) => /wait for more men or a breach/.test(t)), "the realm isn't told why the host waits");
check(weak.lifted && weak.told.some((t) => /lifts the siege/.test(t) && /too few/.test(t)), "a host too weak to storm never lifts the siege, or lifts it unexplained");

const strong = siege({ beside: 6, inside: 2 });
console.log(`  6 against 2: stormed ${JSON.stringify(strong.stormed)}`);
check(strong.stormed[0], "six companies against two don't storm");

const whole = siege({ beside: 3, inside: 2, wear: 0 });
const breached = siege({ beside: 3, inside: 2, wear: 0.8 });
console.log(`  3 against 2: walls whole stormed ${whole.stormed[0]}, breached stormed ${breached.stormed[0]}`);
check(!whole.stormed[0] && breached.stormed[0], "the walls' wear doesn't decide a close storm (wait while whole, storm through a breach)");

const pressed = siege({ beside: 1, inside: 8, press: true });
check(pressed.stormed[0], "the King's pressed siege doesn't storm (his word)");
done();
