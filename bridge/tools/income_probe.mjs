// Guards READY.md line 12's "income by source per house" (casebook, Every answer costs: the King sees where each
// house's gold comes from; docs/research/freeciv-integration-plan-2026-11-12.md step 3, "per-house mine income").
// Freeciv keeps the books: each season the ruleset (realmrules/script.lua realm_income) reports "income", every
// house's season by source: its towns (Freeciv's own taxes less upkeep), its mines (each worked gold seam pays its
// owner mines.gold_per_season), the tithe (a house hands it over, the crown receives it) and the Royal Court's
// upkeep, and the bridge's dealings (every gold the bridge moves goes through the ruleset's realm_gold, Lua.gold).
// The sources add up to what the house's purse really moved, and /world's houses carry them.
// Bare Freeciv on the baseline, our ruleset, no bridge. Exits 1 on a failure.   node tools/income_probe.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";
import * as Lua from "../lua.js";
import * as Treasury from "../treasury.js";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const { check, done } = checker("INCOME");
const data = fs.readFileSync(path.join(BRIDGE, "data/realmrules/luadata.txt"), "utf8");
const perSeam = Number(data.match(/\[mines\][^[]*?gold_per_season = "(\d+)"/)?.[1]);
check(perSeam > 0, "luadata.txt [mines] has no gold_per_season (what a worked seam pays its house)");
// One rule for a seam's yield: the ruleset's Lua pays it, so Freeciv's Gold tile adds no trade of its own on top.
const gold = fs.readFileSync(path.join(BRIDGE, "data/realmrules/terrain.ruleset"), "utf8").match(/\[resource_gold\][^[]*/)?.[0] ?? "";
check(!/^trade\s*=\s*[1-9]/m.test(gold), "the Gold resource still yields trade beside the seam's own pay");

const b = await bareFreeciv({ port: 5587, save: path.join(BRIDGE, "baseline/aldmere/saves/realm-T0038-Y-2150-auto.sav.zst"), serv: ["set timeout -1", 'aitoggle "The King"'] });
check(await b.until(/Now accepting new client connections/, 30000), "the baseline didn't load");
// Every purse, read after the ruleset's own turn hook (the books closed), each season.
const hook = path.join(b.dir, "income_hook.lua");
fs.writeFileSync(hook, `function probe_income(turn)
  local s = ""
  for p in players_iterate() do s = s .. string.format("%d:%d;", p.id, p:gold()) end
  log.normal("GOLD %d %s", turn, s)
end
signal.connect("turn_begin", "probe_income")
log.normal("HOOKED")`);
await b.cmd(`lua file ${hook}`, /HOOKED/);
await b.cmd(`lua cmd ${Lua.titheRate(0.1)}`);
const from = b.lines.length;
b.send("set endturn 40");
b.send("start");
check(await b.until(/GOLD 40 /, 180000, from), "two seasons didn't turn");
await b.until(/Game ended as the turn limit/, 60000, from);
await b.quit();

const lines = b.lines.slice(from);
const golds = (turn) => Object.fromEntries([...(lines.find((l) => l.includes(`GOLD ${turn} `)) ?? "").matchAll(/(\d+):(-?\d+);/g)].map((m) => [+m[1], +m[2]]));
const events = (kind) => lines.filter((l) => l.includes(`"kind":"${kind}"`)).map((l) => JSON.parse(l.replace(/^.*?EVENT /, "")));
const [g39, g40] = [golds(39), golds(40)];
const income = events("income");
check(income.length >= 1, "Freeciv reported no season's income");
const ev = income.at(-1) ?? { by: "" };
const rows = Object.fromEntries(String(ev.by ?? "").split(";").filter(Boolean).map((r) => { const [id, towns, mines, tithe, court, dealings] = r.split(":").map(Number); return [id, { towns, mines, tithe, court, dealings }]; }));
// The sources add up to what each purse really moved in the season.
let houses = 0;
for (const [id, r] of Object.entries(rows)) {
  houses++;
  const moved = g40[id] - g39[id];
  check(r.towns + r.mines + r.tithe + r.court + r.dealings === moved, `house ${id}'s sources (${JSON.stringify(r)}) don't add up to its purse's move (${moved})`);
}
check(houses >= 6, `the income names ${houses} houses`);
// The mines: what the worked seams pay, to their land's owner.
const worked = events("seams_worked").at(-1)?.at ?? "";
const want = {};
for (const s of String(worked).split(";").filter(Boolean)) { const [, , city, owner] = s.split(",").map(Number); if (city >= 0) want[owner] = (want[owner] ?? 0) + perSeam; }
check(Object.keys(want).length > 0, "no seam was worked (or seams_worked doesn't name the seam's owner)");
for (const [id, r] of Object.entries(rows)) check(r.mines === (want[id] ?? 0), `house ${id}'s mines brought ${r.mines}, its worked seams pay ${want[id] ?? 0}`);
// The tithe: what the houses handed over, and the crown's receipt, as the season's purse says.
const purse = events("purse").at(-1) ?? {};
const crownId = Number(ev.crown);
check(rows[crownId]?.tithe === Number(purse.total) && rows[crownId]?.court === -Number(purse.upkeep), "the crown's tithe and court rows aren't the season's purse");

// The bridge keeps it, and /world's houses carry it.
const meta = {}, lastSeason = { net: 0 };
Treasury.income({ meta, lastSeason }, ev);
check(meta.income?.[crownId]?.tithe === rows[crownId]?.tithe, "treasury.js didn't keep the season's income");
const c = rows[crownId] ?? {};
check(lastSeason.net === c.towns + c.mines + c.tithe + c.court, "the top bar's season isn't the crown's books less its dealings");
const view = fs.readFileSync(path.join(BRIDGE, "view.js"), "utf8");
check(/\.income\s*=\s*meta\.income/.test(view), "/world's houses don't carry their income");
// The crown's season for the top bar is the ledger's, not reckoned again from its purse.
check(!/econ\.base|spentSince/.test(fs.readFileSync(path.join(BRIDGE, "treasury.js"), "utf8")), "treasury.js still reckons the crown's season from its purse itself");
console.log(`  ${houses} houses; mines ${JSON.stringify(want)}; crown ${JSON.stringify(rows[crownId])}`);
done();
