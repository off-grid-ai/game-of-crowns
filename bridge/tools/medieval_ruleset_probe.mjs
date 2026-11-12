// Guards step 2 (docs/research/freeciv-leverage-2026-11-12.md): realmrules loads clean, has no modern
// governments, nuclear or industrial disasters or spaceship, and its medieval policies are in play for the
// houses' AI. Bare Freeciv on 5571, our ruleset, no bridge. Exits 1 on a failure.
//   node tools/medieval_ruleset_probe.mjs        (from bridge/)
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";

const { check, done } = checker("MEDIEVAL RULESET");
const fc = await bareFreeciv({ serv: ["set aifill 4", "set minplayers 0", "set timeout -1", "set saveturns 1", 'set autosaves "TURN|GAMEOVER"', 'set savename "probe"', "set endturn 6", "start"] });
check(await fc.until(/Game ended as the turn limit/, 120000), "the game didn't run (ruleset failed to load?)");
const bad = fc.lines.filter((l) => /ruleset|Ruleset/.test(l) && /rror|nknown|nvalid|ailed/.test(l));
check(bad.length === 0, `ruleset errors:\n  ${bad.slice(0, 5).join("\n  ")}`);
const last = fs.readdirSync(fc.dir).filter((f) => /-auto\.sav\.zst$/.test(f)).sort().pop();
const save = last ? zlib.zstdDecompressSync(fs.readFileSync(path.join(fc.dir, last))).toString() : "";
await fc.quit();
const govs = [...fs.readFileSync(new URL("../data/realmrules/governments.ruleset", import.meta.url), "utf8").matchAll(/^\[government_(\w+)\]/gm)].map((m) => m[1]);
check(govs.includes("monarchy"), "no Monarchy in governments.ruleset");
for (const gone of ["communism", "fundamentalism", "federation", "democracy"]) check(!govs.includes(gone), `government ${gone} is still in the rules`);
for (const gone of ["Nuclear Accident", "Industrial Accident", "Spaceship Launch"]) {
  check(!new RegExp(`"${gone}"`).test(save), `${gone} is still in the rules a game saves`);
}
for (const pol of ["Levy Muster", "Market Tolls", "Granary Stores"]) check(save.includes(`"${pol}"`), `policy ${pol} isn't in the game`);
fs.rmSync(fc.dir, { recursive: true, force: true });
done();
