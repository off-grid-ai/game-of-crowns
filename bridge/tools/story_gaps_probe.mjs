// Guards the story options that reach Freeciv (docs/research/story-options-to-freeciv-2026-11-12.md; casebook, The AI
// that doesn't play, Medieval II: a story's war is a war Freeciv fights): a story's `war` declares the war through
// the one diplomacy writer before its host is raised; its `truce` reaches the same writer; a `defect` with a seat
// takes the town with him (Freeciv's transfer); a story's `plague` is Freeciv's own illness (the save's turn_plague).
// Bridge only, a scratch GOC_HOME. Exits 1 on a failure.   node tools/story_gaps_probe.mjs        (from bridge/)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

process.env.GOC_HOME = fs.mkdtempSync(path.join(os.tmpdir(), "goc-gaps-"));
const { Arcs } = await import("../arcs.js");
const { Court } = await import("../characters.js");
const Season = await import("../season.js");
const View = await import("../view.js");
const { checker } = await import("./fc_probe_lib.mjs");
const { check, done } = checker("STORY GAPS");

const world = { turn: 20, players: [{ id: 1, nation: "English", name: "Goldcrest" }, { id: 4, nation: "Welsh", name: "Stormhold" }],
  cities: [{ id: 10, owner: 1, x: 1, y: 1, capital: true, size: 4 }, { id: 11, owner: 4, x: 5, y: 5, capital: true, size: 4 }, { id: 12, owner: 4, x: 7, y: 5, size: 3 }] };
const order = [];
const court = { people: {}, save: () => {}, shift: () => {}, saveCourt: () => {}, lordOfHouse: (pid) => ({ id: `lord${pid}` }),
  onWar: (pair) => order.push(["war", ...pair]), makeTruce: Court.prototype.makeTruce, onTruce: (pair, seasons) => order.push(["truce", ...pair, seasons]) };
const arcs = new Arcs(fs.mkdtempSync(path.join(os.tmpdir(), "goc-arcs-")), court, () => {});
const ctx = { world, send: (l) => order.push(["lua", l]), scene: () => {} };
const roles = { a: { id: "a", name: "Edwin", playerId: 1 }, b: { id: "b", name: "Rhys", playerId: 4 }, town: { town: true, id: 12, owner: 4, x: 7, y: 5 },
  turncoat: { id: "t", name: "Ser Bran", playerId: 4, seat: 12 } };

// 1. war: declared in Freeciv first, then the host.
arcs.act({ war: ["a", "b", "town"] }, { tags: [] }, roles, ctx);
const w = order.findIndex((o) => o[0] === "war"), h = order.findIndex((o) => o[0] === "lua" && o[1].includes("realm_host"));
check(w >= 0 && order[w][1] === 1 && order[w][2] === 4, "a story's war declared no war in Freeciv");
check(w >= 0 && h > w, "the war's host was raised before the war was declared");
// 2. truce: the story's truce reaches the one diplomacy writer (court -> houseTruce -> diplomacy).
order.length = 0;
arcs.act({ truce: ["a", "b", 2] }, { tags: [] }, roles, ctx);
check(order.some((o) => o[0] === "truce" && o[1] === 1 && o[2] === 4), "a story's truce didn't reach the court's truce hook");
const written = [];
Season.houseTruce({ world, meta: {}, court: {}, diplomacy: (p) => written.push(p) }, [1, 4], 8);
check(written.some((p) => p[0] === 1 && p[1] === 4), "the court's truce didn't reach Freeciv's diplomacy writer");
// 3. defect: the bannerman takes his seat to his new house; never the capital.
order.length = 0;
arcs.act({ defect: ["turncoat", "a"] }, { tags: [] }, roles, ctx);
check(order.some((o) => o[0] === "lua" && /find\.city\(nil, 12\).*edit\.transfer_city/.test(o[1]) && /p\.id == 1/.test(o[1])), "a defector's seat didn't go with him");
order.length = 0;
const lordling = { id: "l", name: "Lord Rhys", playerId: 4, seat: 11 };
arcs.act({ defect: ["l", "a"] }, { tags: [] }, { ...roles, l: lordling }, ctx);
check(!order.some((o) => o[0] === "lua" && o[1].includes("transfer_city")), "a defector took his old house's capital");
// 4. plague: the town's plague is Freeciv's illness (savefile.js turn_plague -> view.js townStates -> the story's ctx.town).
const w2 = { turn: 20, players: world.players, cities: world.cities.map((c) => ({ ...c })) };
View.townStates({ world: w2, meta: {}, scenes: [], detail: () => ({ cities: { 12: { plagueTurn: 19 }, 11: { plagueTurn: -1 } } }), besiegers: () => [], favourOf: () => 50 });
check(w2.cities.find((c) => c.id === 12).plague === true && w2.cities.find((c) => c.id === 11).plague === false, "a town's plague isn't Freeciv's illness");
check(/plagueTurn: c\.turn_plague/.test(fs.readFileSync(new URL("../savefile.js", import.meta.url), "utf8")), "the save's turn_plague no longer feeds the town's plague");
fs.rmSync(process.env.GOC_HOME, { recursive: true, force: true });
done();
