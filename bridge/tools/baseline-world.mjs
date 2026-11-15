// The baseline's starting /world and map (state/world.json, state/map.json) read from its own save, the realm every
// new Aldmere reign starts from: a Freeciv of its own on a spare port loads baseline/aldmere/saves' save and runs the
// bridge's snapshot.lua into the baseline's state, then quits. The save is not changed (Freeciv writes its saves to a
// throwaway folder). Beside them, world_served.json: the same realm in the shape the bridge serves it on a new reign's
// first /world (view.js worldView): each town's name and title (narrator.js cityName) and family (the bannerman seated
// there, from the baseline's characters), each house's house (narrator.js houseFor: crown, name, colour), crownId,
// seatId. Square bakes the starting towns from it. make-baseline.sh runs this after it captures a save; run alone after the baseline save changes:
//   node tools/baseline-world.mjs
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { houseFor, cityName, rememberNames } from "../narrator.js";

const DIR = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const BASE = path.join(DIR, "baseline", "aldmere");
const STATE = path.join(BASE, "state");
const PORT = String(process.env.BASELINE_PORT || 5599);  // never the realm's own 5556
const save = fs.readdirSync(path.join(BASE, "saves")).filter((f) => f.endsWith(".sav.zst")).map((f) => path.join(BASE, "saves", f))
  .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs)[0];
if (!save) { console.error("no baseline save"); process.exit(1); }
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "goc-baseline-"));
const share = process.env.FREECIV_SHARE || "/opt/homebrew/share/freeciv";
const env = { ...process.env, FREECIV_DATA_PATH: `${path.join(BASE, "data")}:${path.join(DIR, "data")}:${share}` };
fs.mkdirSync(STATE, { recursive: true });
fs.rmSync(path.join(STATE, "map.json"), { force: true });  // snapshot.lua writes the map only when there is none
const before = fs.existsSync(path.join(STATE, "world.json")) ? fs.statSync(path.join(STATE, "world.json")).mtimeMs : 0;
const fc = spawn(process.env.FREECIV_SERVER || "freeciv-server", ["-p", PORT, "-s", tmp, "-d", "n", "-b", "127.0.0.1", "-f", save], { cwd: DIR, env });
const say = (c) => fc.stdin.write(c + "\n");
let log = "";
fc.stdout.on("data", (d) => { log += d; });
fc.stderr.on("data", (d) => { log += d; });
const done = (code, why) => { try { fc.kill("SIGKILL"); } catch {} fs.rmSync(tmp, { recursive: true, force: true }); if (why) console.error(why, log.slice(-2000)); process.exit(code); };
setTimeout(() => done(1, "timed out"), 60000);
setTimeout(() => {
  say(`lua unsafe-cmd SNAP_DIR = "${STATE}/"`);
  say(`lua unsafe-file ${path.join(DIR, "lua", "snapshot.lua")}`);
  const wait = setInterval(() => {
    const w = path.join(STATE, "world.json"), m = path.join(STATE, "map.json");
    if (fs.existsSync(m) && fs.existsSync(w) && fs.statSync(w).mtimeMs > before) {
      clearInterval(wait);
      const world = JSON.parse(fs.readFileSync(w, "utf8"));
      served(world);
      console.log(`baseline world: turn ${world.turn}, ${world.cities.length} towns, ${world.units.length} units, from ${path.basename(save)}`);
      say("quit");
      setTimeout(() => done(0), 500);
    }
  }, 250);
}, 4000);

// The baseline's /world as a new reign's first sync serves it (view.js worldView's players, cities, crownId, seatId).
function served(world) {
  rememberNames(world);
  const people = fs.readdirSync(path.join(BASE, "characters")).filter((f) => f.endsWith(".json"))
    .map((f) => JSON.parse(fs.readFileSync(path.join(BASE, "characters", f), "utf8")));
  const familyAt = (id) => people.find((c) => c.alive && c.rank === "bannerman" && c.seat === id)?.surname ?? null;
  const players = world.players.map((p) => ({ ...p, house: houseFor(p) }));
  const crown = players.find((p) => p.house.crown);
  const cities = world.cities.map((c) => ({ ...c, name: cityName(c.id), title: cityName(c.id), family: familyAt(c.id) }));
  const seat = cities.find((c) => c.owner === crown?.id && c.capital);
  fs.writeFileSync(path.join(STATE, "world_served.json"), JSON.stringify({ ...world, players, cities, crownId: crown?.id ?? null, seatId: seat?.id ?? null }));
}
