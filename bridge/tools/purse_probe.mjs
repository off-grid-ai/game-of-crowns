// Guards READY.md line 12's "Royal Court upkeep, tithe in ruleset Lua" (casebook, Every answer costs, Reigns: the
// tithe fills the purse, the court empties it, and Freeciv keeps the books). Each season realm_purse takes every
// great house's tithe (its towns' size x per_size x the rate the bridge set) and charges the crown the Royal Court's
// upkeep; it reports "purse", and treasury.js keeps the reckoning from it. Bare Freeciv on the baseline, our
// ruleset, no bridge. Exits 1 on a failure.   node tools/purse_probe.mjs        (from bridge/)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";
import * as Lua from "../lua.js";
import * as Treasury from "../treasury.js";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const { check, done } = checker("PURSE");
const data = fs.readFileSync(path.join(BRIDGE, "data/realmrules/luadata.txt"), "utf8");
const num = (k) => Number(data.match(new RegExp(`\\[purse\\][^[]*?${k} = "([\\d.]+)"`))?.[1]);
const [per, base, perTown, share] = [num("per_size"), num("court_base"), num("court_per_town"), num("court_share")];
check(per > 0 && base >= 0 && perTown >= 0 && share >= 0, "luadata.txt has no [purse]");
check(!/titheLua|crownUpkeep/.test(fs.readFileSync(path.join(BRIDGE, "crown.js"), "utf8") + fs.readFileSync(path.join(BRIDGE, "treasury.js"), "utf8")), "the bridge still reckons the tithe or the court's upkeep itself");

const b = await bareFreeciv({ port: 5586, save: path.join(BRIDGE, "baseline/aldmere/saves/realm-T0038-Y-2150-auto.sav.zst"), serv: ["set timeout -1", 'aitoggle "The King"'] });
check(await b.until(/Now accepting new client connections/, 30000), "the baseline didn't load");
// What Freeciv should take, read in the same instant (a turn hook after the ruleset's own, which runs the purse):
// each great house's towns, and the crown's towns and purse (its purse before the season = after, less what moved).
const hook = path.join(b.dir, "purse_hook.lua");
fs.writeFileSync(hook, `function probe_purse(turn)
  local s = ""
  for p in players_iterate() do
    local size, towns = 0, 0
    for c in p:cities_iterate() do size = size + c.size towns = towns + 1 end
    s = s .. string.format("%d:%s:%d:%d:%d;", p.id, p.nation and p.nation:rule_name() or "", size, towns, p:gold())
  end
  log.normal("SEEN %s", s)
end
signal.connect("turn_begin", "probe_purse")
log.normal("HOOKED")`);
await b.cmd(`lua file ${hook}`, /HOOKED/);
await b.cmd(`lua cmd ${Lua.titheRate(0.1)}`);
const from = b.lines.length;
b.send("set endturn 39");
b.send("start");
check(await b.until(/SEEN /, 120000, from), "the season didn't turn");
const ev = JSON.parse(b.lines.slice(from).find((l) => l.includes('"kind":"purse"')).replace(/^.*?EVENT /, ""));
const rows = [...(b.lines.slice(from).find((l) => /SEEN /.test(l)) ?? "").matchAll(/(\d+):([A-Za-z ]+):(\d+):(\d+):(-?\d+);/g)].map((m) => ({ id: +m[1], nation: m[2], size: +m[3], towns: +m[4], gold: +m[5] }));
const crown = rows.find((r) => r.nation === "Norman");
const houses = rows.filter((r) => !["Norman", "Barbarian", "Pirate", "Animal Kingdom"].includes(r.nation));
const want = houses.reduce((t, h) => t + Math.floor(h.size * per * 0.1), 0);
crown.gold -= Number(ev.total) - Number(ev.upkeep);  // the purse before the season
const court = base + perTown * crown.towns + Math.floor(Math.max(0, crown.gold) * share);
check(Number(ev.total) === want, `the tithe taken was ${ev.total}, the houses' towns owe ${want}`);
check(Number(ev.upkeep) === Math.min(court, Math.max(0, crown.gold + want)), `the Royal Court cost ${ev.upkeep}, its rule says ${court}`);
await b.until(/Game ended as the turn limit/, 120000, from);
await b.quit();

// The bridge keeps the reckoning from it.
const ctx = { world: { players: [{ id: crown.id, nation: "Norman", gold: crown.gold }] }, meta: {}, tally: { total: 0, upkeep: 0 }, lastSeason: {} };
Treasury.purse(ctx, ev);
check(ctx.tally.total === Number(ev.total) && ctx.tally.upkeep === Number(ev.upkeep), "treasury.js didn't tally the season's purse");
console.log(`  tithe ${ev.total} from ${houses.length} houses (${ev.takes}); the Royal Court cost ${ev.upkeep}`);
done();
