// The fixed starts as one chain of snapshots, each made from the last (Mac 2026-11-19: "the world building should just
// be done once and it should be a snapshot, then from there to first year another snapshot, then from there to 9 years
// another snapshot"). Run by tools/make-baseline.sh:
//   1. the founding (baseline/aldmere_founding): Freeciv alone builds Aldmere from the founding files (world_setup.lua,
//      realm.serv) with fixed map and game seeds, saved on turn 1 before any season is played;
//   2. year one (baseline/aldmere_year_one): a private bridge opens a copy of the founding and lets the realm run, nobody
//      on the throne, to the spring of year one (turn 5), when the realm's people, court and chronicle stand;
//   3. nine years in (baseline/aldmere): a private bridge opens a copy of year one and runs on to turn 38.
// Each snapshot is the run's own history: nothing is hand-patched. Pleas nobody answered are cleared (a new King never
// inherits a plea from a lord who sat before him), every character's seat is checked against its house's towns, and the
// check goes in its baseline.json beside where it came from (its parent snapshot and turn) and the seeds.
// Private ports and GOC_HOME (bridge 8791, Freeciv 5591; baseline-world.mjs 5599): Mac's realm on 8787/5556 is never touched.
//   node tools/baseline-chain.mjs [--seed 1066] [--pace 3]      (from bridge/; make-baseline.sh runs it)
import { spawn, execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import zlib from "node:zlib";
import { row } from "../savefile.js";

const DIR = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const arg = (k, d) => { const i = process.argv.indexOf(`--${k}`); return i > 0 ? process.argv[i + 1] : d; };
const SEED = Number(arg("seed", 1066)), PACE = Number(arg("pace", 3));
const YEAR_ONE = 5, NINE_YEARS = 38;  // calendar.js: turn 5 is the spring of year one, turn 38 the summer of year nine
const PORT = 8791, FC_PORT = 5591;
const B = `http://127.0.0.1:${PORT}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const t0 = Date.now();
const secs = () => `${Math.round((Date.now() - t0) / 1000)} s`;

const HOME = fs.mkdtempSync(path.join(os.tmpdir(), "goc-chain-"));
process.env.GOC_HOME = HOME;
process.env.FREECIV_SHARE ??= ["/opt/homebrew/share/freeciv", "/usr/share/games/freeciv", "/usr/share/freeciv"].find((d) => fs.existsSync(d));
const chron = await import("../chronicles.js");
const killFc = () => { try { execFileSync("pkill", ["-KILL", "-f", `freeciv-server -p ${FC_PORT} `]); } catch { /* none */ } };
let bridge = null;  // the private bridge running, taken down with the chain however it ends
const die = (why) => { console.error(`BASELINE CHAIN: ${why}`); process.exit(1); };
process.on("exit", () => { try { bridge?.kill("SIGKILL"); } catch { /* gone */ } killFc(); });
process.on("SIGINT", () => process.exit(130));
process.on("SIGTERM", () => process.exit(143));

// --- 1. the founding: Freeciv alone ---------------------------------------------------------------------------------
async function found() {
  const m = chron.create({ name: "Baseline chain test founding", scenario: "founding" });
  const P = chron.paths(m.id);
  // Fixed seeds, so the founding is made again exactly; time held (timeout 0) so no season passes before the save.
  const serv = fs.readFileSync(P.serv, "utf8").replace(/^set timeout \d+$/m, "set timeout 0").replace(/^start$/m, `set mapseed ${SEED}\nset gameseed ${SEED}\nstart`);
  fs.writeFileSync(P.serv, serv);
  killFc();
  const env = { ...process.env, FREECIV_DATA_PATH: `${P.data}:${path.join(DIR, "data")}:${process.env.FREECIV_SHARE}` };
  const fc = spawn(process.env.FREECIV_SERVER || "freeciv-server", ["-p", String(FC_PORT), "-s", P.saves, "-d", "n", "-b", "127.0.0.1", "-r", P.serv], { cwd: DIR, env });
  let log = "";
  fc.stdout.on("data", (d) => { log += d; });
  fc.stderr.on("data", (d) => { log += d; });
  const say = (c) => fc.stdin.write(c + "\n");
  const until = async (ok, ms, why) => { for (const s = Date.now(); !ok(); await sleep(250)) if (Date.now() - s > ms || fc.exitCode !== null) die(`${why}\n${log.slice(-1500)}`); };
  const saves = () => fs.readdirSync(P.saves).filter((f) => f.startsWith("realm") && f.endsWith(".sav.zst"));
  await until(() => /Starting game|Start of turn|Turn 1\b/i.test(log) || saves().length, 120000, "the founding never started");
  await sleep(2000);
  say("save");
  await until(() => saves().length, 60000, "the founding was never saved");
  say(`lua unsafe-cmd SNAP_DIR = "${P.state}/"`);
  say(`lua unsafe-file ${path.join(DIR, "lua", "snapshot.lua")}`);
  await until(() => fs.existsSync(path.join(P.state, "world.json")) && fs.existsSync(path.join(P.state, "map.json")), 60000, "the founding's world was never written");
  say("quit");
  await sleep(1500);
  fc.kill("SIGKILL");
  killFc();
  fs.writeFileSync(path.join(P.state, "founding.log"), log);
  return m.id;
}

// --- 2, 3. a private bridge runs a copy of a snapshot on to a turn -----------------------------------------------------
async function runOn(scenario, name, turn) {
  const m = chron.create({ name, scenario });
  // The realm runs with a King crowned as a reign's defaults crown him (the houses' favour, his purse), but no royal
  // host raised for him (server.js applyStartOptions): a reign begun on the snapshot raises its own, and deals its
  // own favour and purse over the run's.
  m.snapshot = true;
  chron.saveMeta(m);
  chron.setActive(m.id);
  // The load rule: at most two private bridges across sessions besides Mac's.
  for (let waited = 0; ; waited += 10) {
    let n = 0;
    try { n = execFileSync("pgrep", ["-f", "node(.*[ /])?server\\.js( |$)"]).toString().trim().split("\n").filter(Boolean).length; } catch { /* none */ }
    if (n - 1 < 2) break;
    if (waited > 1800) die("no private bridge slot in 30 min");
    await sleep(10000);
  }
  killFc();
  const blog = path.join(HOME, `bridge-${m.id}.log`);
  const out = fs.openSync(blog, "w");
  bridge = spawn("node", ["server.js"], { cwd: DIR, env: { ...process.env, PORT: String(PORT), FC_PORT: String(FC_PORT), GOC_HOME: HOME }, stdio: ["ignore", out, out] });
  const text = () => fs.readFileSync(blog, "utf8");
  for (const s = Date.now(); !text().includes("Bridge listening"); await sleep(200)) if (bridge.exitCode !== null || Date.now() - s > 30000) die(`the private bridge didn't start\n${text().slice(-1500)}`);
  const get = async (p) => (await fetch(B + p, { signal: AbortSignal.timeout(30000) })).json();
  const post = async (p, body) => (await fetch(B + p, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body ?? {}), signal: AbortSignal.timeout(60000) })).json();
  // Polling /world is a window watching (claude.js watched): the realm's clock runs only while someone does.
  let w = null, sped = false, last = 0, still = Date.now();
  while (!(w?.turn >= turn)) {
    if (bridge.exitCode !== null) die(`the private bridge died\n${text().slice(-1500)}`);
    try { w = await get("/world"); } catch { /* starting */ }
    if (w?.turn > 0 && !sped) { await post("/speed", { seconds: PACE }); sped = true; }
    // The last seasons slowed, so the season to stop on is seen while it still runs (/world reads the realm a few
    // seconds into a season; at the fast pace the next one would already have begun).
    if (w?.turn >= turn - 2 && sped !== "slow") { await post("/speed", { seconds: 20 }); sped = "slow"; }
    if ((w?.turn ?? 0) !== last) { last = w?.turn ?? 0; still = Date.now(); console.log(`  ${name}: turn ${last} (${secs()})`); }
    if (w?.reign?.status && w.reign.status !== "running") die(`${name}: the reign ended at turn ${w.turn} (${w.reign.verdict ?? w.reign.status})`);
    if (Date.now() - still > 180000) die(`${name} stalled at turn ${last}\n${text().slice(-1500)}`);
    await sleep(1000);
  }
  // The last season held still (the slowest pace; a pause, timeout 0, lets Freeciv end the season at once) while
  // its own work (court, people, chronicle) is written, then the realm is put away.
  await post("/speed", { seconds: chron.PACE.slowest });
  await sleep(8000);  // the season's own work (court, people, chronicle) written before the realm is put away
  bridge.kill("SIGTERM");  // server.js shutdown: the meta and minds written, Freeciv saved and stopped
  for (const s = Date.now(); bridge.exitCode === null && Date.now() - s < 20000; await sleep(250));
  if (bridge.exitCode === null) bridge.kill("SIGKILL");
  bridge = null;
  killFc();
  const meta = chron.readJson(chron.paths(m.id).meta);
  if (meta?.status !== "running") die(`${name}: the reign ended (${meta?.status}) before turn ${turn}`);
  const thrown = text().split("\n").filter((l) => /TypeError|ReferenceError|RangeError|Unhandled|Uncaught/.test(l));
  return { id: m.id, thrown };
}

// --- capture: a chronicle as a snapshot -----------------------------------------------------------------------------
function capture(id, dir, parent, thrown = []) {
  const P = chron.paths(id);
  const dst = path.join(DIR, "baseline", dir);
  fs.rmSync(dst, { recursive: true, force: true });
  fs.mkdirSync(path.join(dst, "saves"), { recursive: true });
  const save = fs.readdirSync(P.saves).filter((f) => f.endsWith(".sav.zst")).map((f) => path.join(P.saves, f))
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs)[0];
  fs.copyFileSync(save, path.join(dst, "saves", path.basename(save)));
  for (const part of ["state", "characters", "data"]) if (fs.existsSync(path.join(P.base, part))) fs.cpSync(path.join(P.base, part), path.join(dst, part), { recursive: true });
  for (const f of ["realm.serv", "world_setup.lua", "court.json", "mood.json"]) if (fs.existsSync(path.join(P.base, f))) fs.copyFileSync(path.join(P.base, f), path.join(dst, f));
  // Not the realm: the townsfolk's stories (written fresh in each chronicle) and the run's logs.
  for (const f of ["folk-tales.json", "freeciv.log", "founding.log"]) fs.rmSync(path.join(dst, "state", f), { force: true });
  // A plea nobody answered dies with the run: a new King hears only his own court's.
  const courtFile = path.join(dst, "court.json");
  let cleared = 0;
  if (fs.existsSync(courtFile)) {
    const c = JSON.parse(fs.readFileSync(courtFile, "utf8"));
    const kept = (c.petitions ?? []).filter((p) => p.answered);
    cleared = (c.petitions ?? []).length - kept.length;
    fs.writeFileSync(courtFile, JSON.stringify({ ...c, petitions: kept }, null, 1));
  }
  // The starting /world read from the snapshot's own save (and served as a new reign's first /world).
  execFileSync("node", [path.join(DIR, "tools", "baseline-world.mjs"), dir], { cwd: DIR, stdio: "inherit" });
  const world = JSON.parse(fs.readFileSync(path.join(dst, "state", "world.json"), "utf8"));
  // Every character's seat is a town of their own house (the lore audit of 11-19: seats that didn't exist, or another house's).
  const seats = [];
  const cdir = path.join(dst, "characters");
  for (const f of fs.existsSync(cdir) ? fs.readdirSync(cdir).filter((x) => x.endsWith(".json")) : []) {
    const c = JSON.parse(fs.readFileSync(path.join(cdir, f), "utf8"));
    if (c.alive === false || c.seat == null || !["lord", "bannerman"].includes(c.rank)) continue;
    const town = world.cities.find((t) => t.id === Number(c.seat));
    if (!town || town.owner !== c.playerId) seats.push({ id: c.id, name: c.name, house: c.house, seat: c.seat, why: town ? `held by player ${town.owner}` : "no such town" });
  }
  // The King's opening (GAME_DESIGN "The game"): who the crown is at peace or war with in the save, and the raiders out.
  const text = zlib.zstdDecompressSync(fs.readFileSync(save)).toString();
  const crown = world.players.find((p) => /norman/i.test(p.nation));
  const seat = world.cities.find((c) => c.owner === crown?.id && c.capital);
  const pacts = Object.fromEntries(world.players.filter((p) => p !== crown && !/barbarian|pirate/i.test(p.nation))
    .map((p) => [p.nation, String(row(text, crown?.id, "diplstate", p.id)?.cells?.[0] ?? "?").replace(/"/g, "")]));
  const wild = new Set(world.players.filter((p) => /barbarian|pirate/i.test(p.nation)).map((p) => p.id));
  const raiders = (world.units ?? []).filter((u) => wild.has(u.owner));
  const nearKing = seat ? raiders.filter((u) => Math.max(Math.abs(u.x - seat.x), Math.abs(u.y - seat.y)) <= 8).length : 0;
  const meta = chron.readJson(P.meta);
  const fc = (k) => fs.readFileSync(P.serv, "utf8").match(new RegExp(`^set ${k} (\\d+)$`, "m"))?.[1];
  const base = {
    name: dir, from: meta.id, parent: parent ?? null, turn: world.turn, save: path.basename(save), land: meta.land,
    seed: { chain: SEED, mapseed: Number(fc("mapseed") ?? SEED), gameseed: Number(fc("gameseed") ?? SEED), reign: meta.seed, pace: PACE },
    made: Date.now(), checks: { pleasCleared: cleared, seats, crownPacts: pacts, raiders: raiders.length, raidersNearKingsmere: nearKing, thrown: thrown.slice(0, 20) },
  };
  fs.writeFileSync(path.join(dst, "baseline.json"), JSON.stringify(base, null, 1));
  console.log(`${dir}: turn ${world.turn}, ${world.cities.length} towns, ${world.players.length} houses, ${cleared} pleas cleared, ${seats.length} seats amiss, ${thrown.length} errors in the bridge log (${secs()})`);
  console.log(`  the crown's pacts: ${JSON.stringify(pacts)}; ${raiders.length} raiders out, ${nearKing} near Kingsmere`);
  for (const s of seats) console.log(`  seat amiss: ${s.id} ${s.name} (${s.house}) seat ${s.seat}: ${s.why}`);
  return base;
}

const founding = await found();
const f = capture(founding, "aldmere_founding", null);
const one = await runOn("aldmere_founding", "Baseline chain test year one", YEAR_ONE);
const y = capture(one.id, "aldmere_year_one", { name: f.name, turn: f.turn }, one.thrown);
const nine = await runOn("aldmere_fresh", "Baseline chain test nine years", NINE_YEARS);
capture(nine.id, "aldmere", { name: y.name, turn: y.turn }, nine.thrown);
fs.rmSync(HOME, { recursive: true, force: true });
console.log(`baseline chain made in ${secs()}`);
process.exit(0);
