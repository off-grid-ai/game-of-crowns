// Guards risings (READY.md line 9; casebook: Lords with their own needs, Norland; The funeral is the crisis, CK2;
// the failure The AI that doesn't play, Medieval II): on the baseline realm a great house splits by Freeciv's own
// civil war (realm_rising), the rebels' host marches on the lord's nearest town and strikes it by Freeciv's combat,
// and after risings.seasons the rising settles itself. Freeciv alone left its rebels idle (0 attacks in 40 turns:
// docs/research/risings-civil-war-2026-11-12.md). Bare Freeciv, our ruleset, no bridge. Exits 1 on a failure.
//   node tools/rising_probe.mjs        (from bridge/)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";
import zlib from "node:zlib";
import * as Lua from "../lua.js";
import { editRow } from "../fresh.js";
import * as Risings from "../risings.js";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const { check, done } = checker("RISING");
const seasons = Number(fs.readFileSync(path.join(BRIDGE, "data/realmrules/luadata.txt"), "utf8").match(/\[risings\][^[]*?seasons = "(\d+)"/)?.[1]);
check(seasons > 0, "luadata.txt has no [risings] seasons");

// The realm's side (risings.js), with Freeciv's replies played in: a claim warns, the roll goes after the
// warning, a split declares the war and puts the matter to court, the King's answer reaches Freeciv, the end is told.
{
  const sent = [], told = [], wars = [], asked = [];
  const world = { turn: 50, players: [{ id: 4, nation: "Welsh", name: "Lord Robb Stormhold" }, { id: 9, nation: "Cornish", name: "Arthur Gernow" }],
    cities: [{ id: 1, owner: 4, x: 1, y: 1 }, { id: 2, owner: 4, x: 2, y: 2 }, { id: 3, owner: 4, x: 3, y: 3 }, { id: 4, owner: 4, x: 4, y: 4 }] };
  const lord = { id: "l", name: "Lord Robb", playerId: 4, rank: "lord", age: 40, relationships: {} };
  const owain = { id: "o", name: "Ser Owain", playerId: 4, rank: "bannerman", age: 30, relationships: { l: { opinion: -40 } } };
  const court = { lordOfHouse: () => lord, alive: () => [lord, owain], arcPetition: (p) => asked.push(p) };
  const meta = {};
  const ctx = { world, meta, court, send: (l) => sent.push(l), record: (e) => told.push(e.text), scene: () => {}, favourOf: () => 50, marchOn: () => {}, diplomacy: (p) => wars.push(p), saveMeta: () => {} };
  Risings.claim(ctx, 4, "child", 50);
  check(meta.risings?.claims?.[4]?.name === "Ser Owain", `the claimant isn't the bannerman who thinks least of his lord (${JSON.stringify(meta.risings?.claims)})`);
  check(sent.some((l) => l.includes("realm_rising_odds(4)")), "the claim didn't ask Freeciv for the odds");
  Risings.season(ctx, 51);
  check(!sent.some((l) => l.includes("realm_rising(4")), "the house split before its warning ran");
  Risings.season(ctx, 50 + Risings.RISINGS.warnSeasons);
  check(sent.some((l) => l.includes("realm_rising(4, 0)")), "the roll didn't go to Freeciv's own odds after the warning");
  world.cities[2].owner = world.cities[3].owner = 9;
  Risings.event(ctx, { kind: "rising", turn: "52", house: "4", rebel: "9", towns: "3,4", muster: "3" });
  check(wars.some((p) => p[0] === 9 && p[1] === 4 && p[3] === "War"), "the split didn't declare the war (Freeciv leaves them at cease-fire)");
  check(asked[0]?.arc === "rising" && asked[0].options.map((o) => o.id).join() === "lord,claimant,terms,out", "the rising didn't go to court with its four answers");
  check(Risings.townRising(meta, world.cities[3])?.side === "rebels" && Risings.townRising(meta, world.cities[0])?.side === "lord", "/world doesn't say which side holds a town");
  Risings.ruled(ctx, "rising-9", "claimant");
  check(sent.some((l) => l.includes('realm_rising_end(9, "keep")')), "backing the claimant didn't reach Freeciv");
  Risings.event(ctx, { kind: "rising_over", turn: "53", house: "4", rebel: "9", how: "keep", towns: "2" });
  check(wars.some((p) => p[0] === 9 && p[1] === 4 && p[3] === "Armistice"), "a claimant who keeps his towns made no peace with his lord");
  check(!Risings.townRising(meta, world.cities[3]), "a settled rising still shows in /world");
  console.log(`  bridge: ${told.length} lines told; last: ${told.at(-1)}`);
}

const STORMHOLD = 4;
const a = await bareFreeciv({ port: 5579, save: path.join(BRIDGE, "baseline/aldmere/saves/realm-T0038-Y-2150-auto.sav.zst"), serv: ["set barbarians disabled", "set timeout -1", 'aitoggle "The King"'] });
check(await a.until(/Now accepting new client connections/, 30000), "the baseline didn't load");
// Freeciv's own odds, told before the roll; realm_rising_odds counts +5 / -5 a town, as game.ruleset does.
const game = fs.readFileSync(path.join(BRIDGE, "data/realmrules/game.ruleset"), "utf8");
check(/civil_war_bonus_unhappy\s*=\s*5\b/.test(game) && /civil_war_bonus_celebrating\s*=\s*-5\b/.test(game), "game.ruleset's civil war bonuses no longer match realm_rising_odds (+5 / -5)");
const odds = await a.cmd(`lua cmd ${Lua.risingOdds(STORMHOLD)}`, /"kind":"rising_odds"/);
check(/"odds":"\d+"/.test(odds ?? ""), `no odds from Freeciv (${odds})`);
console.log(`  ${odds?.slice(odds.indexOf("{"))}`);
const risen = await a.cmd(`lua cmd ${Lua.rising(STORMHOLD, 100)}`, /"kind":"rising"/);
const rebel = Number(risen?.match(/"rebel":"(-?\d+)"/)?.[1] ?? -1);
check(rebel >= 0, `Stormhold didn't split (${risen})`);
console.log(`  ${risen?.slice(risen.indexOf("{"))}`);
const split = path.join(a.dir, "probe-split");
await a.cmd(`save ${split}`, /Game saved as/, 20000);
await a.quit();
// Freeciv leaves the two at cease-fire; the bridge's one diplomacy writer (risings.js -> setDiplomacy) declares
// the war, written into the save the same way here.
const saved = fs.readdirSync(a.dir).find((f) => f.startsWith("probe-split"));
let text = zlib.zstdDecompressSync(fs.readFileSync(path.join(a.dir, saved))).toString();
for (const [p, q] of [[STORMHOLD, rebel], [rebel, STORMHOLD]]) text = editRow(text, p, "diplstate", q, (c) => { c[0] = c[1] = '"War"'; c[3] = c[4] = "0"; });
const atWar = path.join(a.dir, "probe-war.sav.zst");
fs.writeFileSync(atWar, zlib.zstdCompressSync(Buffer.from(text)));
const b = await bareFreeciv({ port: 5579, save: atWar, saves: a.dir, serv: ["set timeout -1"] });
check(await b.until(/Now accepting new client connections/, 30000), "the split realm didn't load");
const from = b.lines.length;
b.send(`set endturn ${38 + seasons + 1}`);
b.send("start");
check(await b.until(/Game ended as the turn limit/, 300000, from), "the realm didn't run on");
const L = b.lines.slice(from);
const ev = L.filter((l) => l.includes("EVENT {")).map((l) => JSON.parse(l.slice(l.indexOf("{"))));
const marches = L.filter((l) => /RISING \d+ marches/.test(l)).map((l) => l.replace(/^.*RISING/, "RISING"));
const strikes = ev.filter((e) => e.kind === "attack" && Number(e.owner) === rebel).length + ev.filter((e) => e.kind === "assault").reduce((n, e) => n + Number(e.blows ?? 0), 0);
const atWalls = marches.some((l) => /: [1-9]\d* of/.test(l));
const over = ev.find((e) => e.kind === "rising_over" && Number(e.rebel) === rebel);
const taken = ev.filter((e) => e.kind === "city_transferred" && e.reason === "conquest" && (Number(e.to) === rebel || Number(e.from) === rebel));
console.log(`  ${marches.length} seasons marched (last: ${marches.at(-1)}); ${strikes} blows by the rebels; ${taken.length} towns taken in the fighting; ended: ${JSON.stringify(over)}`);
console.log("  assaults:", ev.filter((e) => e.kind === "assault").map((e) => JSON.stringify(e)).join(" "));
check(marches.length > 0, "the rebels never marched");
check(atWalls, "the rebels never reached the lord's walls");
check(strikes > 0, "the rebels never struck a blow (The AI that doesn't play)");
check(over, `the rising hadn't settled after ${seasons} seasons`);
await b.quit();
done();
