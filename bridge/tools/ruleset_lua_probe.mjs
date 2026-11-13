// Guards "the game's Lua is the ruleset's" (docs/research/freeciv-leverage-2026-11-12.md, step 1): our Freeciv
// Lua (events to the bridge, gold seams, the hosts' helpers) loads with realmrules itself, so every game and
// every save has it without a console `lua file`, and its state survives a save and load. Freeciv on its own
// port (5571), our ruleset, no bridge. Exits 1 on a failure.
//   node tools/ruleset_lua_probe.mjs        (from bridge/)
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const { check, done } = checker("RULESET LUA");
const read = (f) => fs.readFileSync(path.join(BRIDGE, f), "utf8");

// Nothing loads game Lua from the console any more (world_setup.lua, a realm's one-off founding, still does).
for (const f of ["realm.serv", "freeciv.js", "chronicles.js", "baseline/aldmere/realm.serv"]) {
  check(!read(f).includes("events.lua"), `${f} still loads lua/events.lua from the console`);
}

const AUTO = ["set aifill 3", "set minplayers 0", "set timeout -1", "set saveturns 1", 'set autosaves "TURN|GAMEOVER"', 'set savename "probe"'];
const defined = async (fc, name) => (await fc.cmd(`lua cmd log.normal("DEF ${name} %s", type(${name}))`, new RegExp(`DEF ${name} `)))?.endsWith(" function");

// A new game: the ruleset's Lua is there before anything is sent.
const a = await bareFreeciv({ serv: [...AUTO, "set endturn 3"] });
await a.until(/Now accepting new client connections/, 20000);
for (const fn of ["realm_host", "realm_war_host", "realm_find_player", "realm_the_dead", "realm_mines"]) check(await defined(a, fn), `${fn} isn't defined in a fresh game`);
check((await a.cmd('lua cmd log.normal("SEAMDATA %s", tostring(luadata.get_str("mines.seam_seasons")))', /SEAMDATA /))?.endsWith(" 40"),
  "the ruleset's luadata.txt doesn't give mines.seam_seasons");
await a.cmd("lua cmd GOC_PROBE_MARK = 7");
a.send("start");
check(await a.until(/Game ended as the turn limit/, 90000), "the game didn't run to its end");
check(a.events("turn").length >= 2, `the ruleset sent ${a.events("turn").length} turn events (want one a turn)`);
const save = fs.readdirSync(a.dir).filter((f) => /-auto\.sav/.test(f)).sort().pop();
await a.quit();
check(save, "no autosave written");

// The same game loaded from its save: the Lua is back, with its state, and it runs on.
if (save) {
  const b = await bareFreeciv({ save: path.join(a.dir, save), saves: a.dir });
  check(await b.until(/Now accepting new client connections/, 30000), "the save didn't load");
  for (const fn of ["realm_host", "realm_mines"]) check(await defined(b, fn), `${fn} isn't defined after loading a save`);
  check((await b.cmd('lua cmd log.normal("MARK %s", tostring(GOC_PROBE_MARK))', /MARK /))?.endsWith(" 7"), "a Lua global didn't survive the save");
  const from = b.lines.length;
  b.send("set endturn 5");
  b.send("start");
  check(await b.until(/Game ended as the turn limit/, 90000, from), "the loaded game didn't run on");
  check(b.lines.slice(from).some((l) => l.includes('"kind":"turn"')), "no turn events after loading the save");
  // The loaded game's own autosave holds the seams' turn in its saved Lua variables.
  const last = fs.readdirSync(a.dir).filter((f) => /-auto\.sav\.zst$/.test(f)).sort().pop();
  const vars = last ? zlib.zstdDecompressSync(fs.readFileSync(path.join(a.dir, last))).toString() : "";
  const seamTurn = Number(vars.match(/GOC_SEAMS_TURN=(\d+)/)?.[1]);
  check(seamTurn >= 4, `the seams didn't run on the loaded game's turns (saved GOC_SEAMS_TURN ${seamTurn}, ${last})`);
  await b.quit();
}
fs.rmSync(a.dir, { recursive: true, force: true });
done();
