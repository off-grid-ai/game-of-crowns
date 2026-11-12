// Guards risings (READY.md line 9; casebook: Lords with their own needs, Norland; The funeral is the crisis, CK2;
// the failure The AI that doesn't play, Medieval II): on the baseline realm a great house splits by Freeciv's own
// civil war (realm_rising), the rebels' host marches on the lord's nearest town and strikes it by Freeciv's combat,
// and after risings.seasons the rising settles itself. Freeciv alone left its rebels idle (0 attacks in 40 turns:
// docs/research/risings-civil-war-2026-11-12.md). Bare Freeciv, our ruleset, no bridge. Exits 1 on a failure.
//   node tools/rising_probe.mjs        (from bridge/)
import fs from "node:fs";
import os from "node:os";
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

// One trigger path, the stories (Mac: "our stories should be enough... they just need to be wired in"): the
// succession crisis warns of the odds, splits the house when the claimant seizes the hall, and every ending
// settles the rising; the King's answers to the heir at court are its branches. Then risings.js, with Freeciv's
// replies played in: the war declared, the end told, the towns' side in /world.
{
  const arc = JSON.parse(fs.readFileSync(path.join(BRIDGE, "arcs/succession-crisis.json"), "utf8"));
  const beat = (id) => arc.beats.find((b) => b.id === id);
  check(beat("deathbed")?.do?.risingOdds === "hall" && beat("passing")?.do?.risingOdds === "hall", "the succession crisis doesn't warn of the odds before the split");
  check(JSON.stringify(beat("seizes")?.do?.rising) === '["heir","hall"]', "the claimant seizing the hall doesn't split the house");
  check(beat("escape")?.court?.options?.map((o) => o.id).join() === "restore,grant,refuse", "the heir's plea at court lacks its three answers");
  const ends = Object.fromEntries(arc.beats.filter((b) => b.end).map((b) => [b.id, b.do?.risingEnd?.[1] ?? null]));
  check(ends.restored === "return" && ends.exile === "return" && ends["usurper-holds"] === "return" && ends.divided === "keep", `an ending doesn't settle the rising (${JSON.stringify(ends)})`);
  const { Arcs } = await import("../arcs.js");
  const sent = [], told = [], wars = [], rose = [], warned = [];
  const world = { turn: 50, players: [{ id: 4, nation: "Welsh", name: "Lord Robb Stormhold" }, { id: 9, nation: "Cornish", name: "Arthur Gernow" }],
    cities: [{ id: 1, owner: 4, x: 1, y: 1 }, { id: 2, owner: 4, x: 2, y: 2 }, { id: 3, owner: 4, x: 3, y: 3 }, { id: 4, owner: 4, x: 4, y: 4 }] };
  const meta = {};
  const rctx = { world, meta, send: (l) => sent.push(l), record: (e) => told.push(e.text), scene: () => {}, diplomacy: (p) => wars.push(p), saveMeta: () => {} };
  const arcs = new Arcs(fs.mkdtempSync(path.join(os.tmpdir(), "goc-arcs-")), { shift: () => {}, people: {}, save: () => {} }, () => {});
  const roles = { heir: { name: "Owain", playerId: 4 }, hall: { town: true, id: 1, owner: 4 } };
  const actx = { world, send: (l) => sent.push(l), scene: () => {}, rising: (pid, who) => { rose.push([pid, who]); Risings.rise(rctx, pid, who); }, risingOdds: (pid) => { warned.push(pid); Risings.odds(rctx, pid); } };
  arcs.act(beat("deathbed").do.risingOdds ? { risingOdds: "hall" } : {}, { tags: [] }, roles, actx);
  arcs.act({ rising: ["heir", "hall"] }, { tags: [] }, roles, actx);
  check(warned[0] === 4 && sent.some((l) => l.includes("realm_rising_odds(4)")), "the odds beat didn't ask Freeciv");
  check(rose[0]?.[0] === 4 && rose[0][1] === "Owain" && sent.some((l) => l.includes("realm_rising(4, 0)")), "the seizing beat didn't roll Freeciv's own odds for the hall's house");
  world.cities[2].owner = world.cities[3].owner = 9;
  Risings.event(rctx, { kind: "rising", turn: "52", house: "4", rebel: "9", towns: "3,4", muster: "3" });
  check(wars.some((p) => p[0] === 9 && p[1] === 4 && p[3] === "War"), "the split didn't declare the war (Freeciv leaves them at cease-fire)");
  check(Risings.townRising(meta, world.cities[3])?.side === "rebels" && Risings.townRising(meta, world.cities[0])?.side === "lord", "/world doesn't say which side holds a town");
  arcs.act({ risingEnd: ["hall", "keep"] }, { tags: [] }, roles, actx);
  check(sent.some((l) => l.includes('realm_rising_end(4, "keep")')), "the story's ending didn't settle the rising in Freeciv");
  Risings.event(rctx, { kind: "rising_over", turn: "53", house: "4", rebel: "9", how: "keep", towns: "2" });
  check(wars.some((p) => p[0] === 9 && p[1] === 4 && p[3] === "Armistice"), "a lesser house made no peace with its old lord");
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
check(strikes + taken.length > 0, "the rebels never struck a blow nor took a town (The AI that doesn't play)");
check(Number(over?.lord ?? 0) > 0, `the rising wiped the lord's house out (casebook failures; a rising ends in a split or a settlement): ${JSON.stringify(over)}`);
check(!ev.some((e) => e.kind === "city_destroyed" && [STORMHOLD, rebel].includes(Number(e.loser))), "a town was razed in the rising (every conquest takes, never razes)");
check(over, `the rising hadn't settled after ${seasons} seasons`);
await b.quit();
done();
