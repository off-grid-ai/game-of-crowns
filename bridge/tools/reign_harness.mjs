// READY.md line 10, "The world makes sense", the rules half: one reign played end to end on a private bridge and
// Freeciv, as fast as the realm steps, checked every season. The King is realm/tools/reign_measure.py (the hasty
// King: he answers every court, interlude and event card), so nothing here plays; this only watches and judges.
//
// Each season it writes the season's /world to <out>/world.jsonl (one line: {"turn", "at", "world"}) for other
// probes to read (the army layer's hosts and views read it instead of running a reign of their own), and the land
// once to <out>/map.json (GET /map); <out> is linked as /tmp/goc-reign/latest. It asserts:
//   1. the bridge threw nothing (its log has no TypeError, ReferenceError, RangeError, unhandled rejection or stack);
//   2. the turn advances (no stall longer than --stall seconds while no court, interlude or event card holds it);
//   3. each house's gold moved by exactly its reported income (Freeciv's books, /world players[].income);
//   4. every story arc that started is still live or has ended (/arcs);
//   5. no unit id leaves /world without Freeciv taking it off (realmrules UNIT_LOST lines in the realm's freeciv.log).
// Writes <out>/report.json (every failure with its turn) and exits 1 on any failure.
//   node tools/reign_harness.mjs [--seasons 40] [--pace 3] [--stall 90] [--out /tmp/goc-reign/<stamp>]   (from bridge/)
// A private bridge (PORT 8797, FC_PORT 5581, its own GOC_HOME under <out>): never Mac's realm. Load rule: at most two
// private bridges at once across sessions, so it waits for a free slot first.
import { spawn, execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const ROOT = path.join(BRIDGE, "..");
const arg = (k, d) => { const i = process.argv.indexOf(`--${k}`); return i > 0 ? process.argv[i + 1] : d; };
const SEASONS = Number(arg("seasons", 40)), PACE = Number(arg("pace", 3)), STALL = Number(arg("stall", 90));
const OUT = arg("out", path.join("/tmp/goc-reign", new Date().toISOString().replace(/[:.]/g, "-")));
const PORT = 8797, FC_PORT = 5581;
const B = `http://127.0.0.1:${PORT}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
fs.mkdirSync(path.join(OUT, "home"), { recursive: true });
try { fs.rmSync("/tmp/goc-reign/latest", { force: true }); fs.symlinkSync(OUT, "/tmp/goc-reign/latest"); } catch { /* another run's link */ }

const failures = [];
const fail = (turn, check, text) => { failures.push({ turn, check, text }); console.log(`  T${turn} ${check}: ${text}`); };
const killFc = () => { try { execFileSync("pkill", ["-KILL", "-f", `freeciv-server -p ${FC_PORT} `]); } catch { /* none */ } };

// A free slot: fewer than two private bridges (any node server.js but the main one on 8787) besides ours. The pattern matches
// server.js as its own file name only: "node.*server.js" also counted tsserver.js (an editor's TypeScript server), so a
// harness waited the whole 30 min with no bridge running.
for (let waited = 0; ; waited += 10) {
  let n = 0;
  try { n = execFileSync("pgrep", ["-f", "node(.*[ /])?server\\.js( |$)"]).toString().trim().split("\n").filter(Boolean).length; } catch { /* none */ }
  if (n - 1 < 2) break;  // the main bridge is one of them
  if (waited === 0) console.log(`  waiting for a private bridge slot (${n - 1} running)`);
  if (waited > 1800) { console.log("REIGN HARNESS: no private bridge slot in 30 min"); process.exit(2); }
  await sleep(10000);
}

killFc();
const blog = fs.createWriteStream(path.join(OUT, "bridge.log"));
const bridge = spawn("node", ["server.js"], { cwd: BRIDGE, env: { ...process.env, PORT: String(PORT), FC_PORT: String(FC_PORT), GOC_HOME: path.join(OUT, "home") } });
let blines = [];
const takeB = (d) => { blog.write(d); blines.push(...String(d).split("\n")); };
bridge.stdout.on("data", takeB);
bridge.stderr.on("data", takeB);
let king = null;
const stop = () => { try { king?.kill("SIGKILL"); } catch { /* gone */ } try { bridge.kill("SIGKILL"); } catch { /* gone */ } killFc(); };
process.on("exit", stop);
process.on("SIGINT", () => process.exit(130));

const get = async (p) => { const r = await fetch(B + p, { signal: AbortSignal.timeout(30000) }); return r.json(); };
const post = async (p, body) => { const r = await fetch(B + p, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body), signal: AbortSignal.timeout(60000) }); return r.json(); };

for (let t0 = Date.now(); !blines.some((l) => l.includes("Bridge listening")); await sleep(200)) {
  if (bridge.exitCode !== null || Date.now() - t0 > 30000) { console.log("REIGN HARNESS: the private bridge didn't start"); console.log(blines.slice(-15).join("\n")); process.exit(2); }
}
await post("/chronicles", { name: "Reign check", scenario: "aldmere", minutes: 0 });
let w = null;
for (let t0 = Date.now(); !(w?.turn > 0 && w?.players?.length); await sleep(1000)) {
  if (Date.now() - t0 > 120000) { console.log("REIGN HARNESS: the realm never reported a world"); process.exit(2); }
  try { w = await get("/world"); } catch { /* starting */ }
}
// The land, once (the army layer's replay serves it beside world.jsonl as the view's bridge).
try { fs.writeFileSync(path.join(OUT, "map.json"), JSON.stringify(await get("/map"))); } catch (e) { console.log(`  no /map: ${e.message}`); }
await post("/speed", { seconds: PACE });
king = spawn("python3", ["-I", path.join(ROOT, "realm/tools/reign_measure.py"), `127.0.0.1:${PORT}`, String(SEASONS * PACE), path.join(OUT, "king.json")], { cwd: ROOT, stdio: "ignore" });

// The realm's Freeciv log, where the ruleset writes UNIT_LOST <id> <reason> <owner>.
const fclog = () => { const d = path.join(OUT, "home", "chronicles"); for (const c of fs.existsSync(d) ? fs.readdirSync(d) : []) { const f = path.join(d, c, "state", "freeciv.log"); if (c.startsWith("reign-check") && fs.existsSync(f)) return f; } return null; };
const lost = new Map();
let fcRead = 0;
const readLost = () => {
  const f = fclog();
  if (!f) return;
  const text = fs.readFileSync(f, "utf8");
  for (const m of text.slice(fcRead).matchAll(/UNIT_LOST (\d+) (\S+) (-?\d+)/g)) lost.set(Number(m[1]), m[2]);
  fcRead = text.length;
};

const worldLog = fs.createWriteStream(path.join(OUT, "world.jsonl"));
const startTurn = w.turn;
let prev = null, lastTurnAt = Date.now(), bSeen = 0;
const arcsSeen = new Map();  // id -> title
const THROWN = /TypeError|ReferenceError|RangeError|SyntaxError|Unhandled|unhandledRejection|uncaughtException|^\s+at .+\.m?js:\d+:\d+\)?$/;
console.log(`  reign check: ${SEASONS} seasons from T${startTurn}, ${PACE} s a season; out ${OUT}`);

while (true) {
  await sleep(500);
  if (bridge.exitCode !== null) { fail(prev?.turn ?? startTurn, "bridge", `the bridge exited (${bridge.exitCode})`); break; }
  try { w = await get("/world"); } catch (e) { continue; }
  const turn = w.turn ?? 0;
  const held = async () => {
    const court = await get("/court").catch(() => null);
    const r = w.reign ?? {};
    return (Array.isArray(court) ? court.length : court && Object.keys(court).length) || (r.interlude && !r.interlude.seen) || r.event?.up;
  };
  if (!prev || turn === prev.turn) {
    const quiet = (Date.now() - lastTurnAt) / 1000;
    if (prev && quiet > STALL && (!(await held()) || quiet > STALL * 4)) { fail(turn, "stall", `no new season in ${Math.round(quiet)} s${(await held()) ? " (a card is up and nobody answered it)" : ""}`); lastTurnAt = Date.now(); }
    if (!prev) { prev = w; lastTurnAt = Date.now(); worldLog.write(JSON.stringify({ turn, at: Date.now(), world: w }) + "\n"); }
    if (w.reign?.status && w.reign.status !== "running") break;
    continue;
  }
  lastTurnAt = Date.now();
  worldLog.write(JSON.stringify({ turn, at: Date.now(), world: w }) + "\n");
  // 1. The bridge threw nothing since the last season.
  const thrown = blines.slice(bSeen).filter((l) => THROWN.test(l));
  bSeen = blines.length;
  if (thrown.length) fail(turn, "exception", thrown.slice(0, 4).join(" | ").slice(0, 400));
  // 2. One season at a time (a skipped season means the bridge missed a world, or the poll did).
  const step = turn - prev.turn;
  if (step !== 1) fail(turn, "stall", `the turn went ${prev.turn} -> ${turn}`);
  // 3. Each house's purse moved by its books, close to close (/world's gold is read at another moment of the season,
  // so it runs a season's dealings ahead or behind; the books' close is the one instant both sides share).
  if (step === 1) for (const p of w.players ?? []) {
    const q = (prev.players ?? []).find((x) => x.id === p.id);
    if (!q?.income || !p.income || p.income.purse == null || q.income.purse == null) continue;
    const { purse, ...src } = p.income;
    const sum = Object.values(src).reduce((t, v) => t + v, 0);
    if (purse - q.income.purse !== sum) fail(turn, "gold", `${p.house?.name ?? p.name} (${p.id}): purse ${q.income.purse} -> ${purse} (${purse - q.income.purse}), its income says ${sum} ${JSON.stringify(src)}`);
  }
  if (turn - startTurn >= 2 && !(w.players ?? []).some((p) => p.income?.purse != null)) fail(turn, "gold", "no house has books (Freeciv's income report never reached /world)");
  // 4. Every arc that started is live or ended.
  const arcs = await get("/arcs").catch(() => null);
  if (arcs) {
    const now = new Set([...(arcs.active ?? []), ...(arcs.done ?? [])].map((a) => a.id));
    for (const a of arcs.active ?? []) arcsSeen.set(a.id, a.title);
    for (const [id, title] of arcsSeen) if (!now.has(id)) { fail(turn, "arc", `"${title}" (${id}) vanished without ending`); arcsSeen.delete(id); }
  }
  // 5. No unit leaves without Freeciv taking it off.
  readLost();
  const ids = new Set((w.units ?? []).map((u) => u.id));
  for (const u of prev.units ?? []) if (!ids.has(u.id) && !lost.has(u.id)) fail(turn, "unit", `${u.type} ${u.id} (owner ${u.owner}) at (${u.x},${u.y}) vanished with no loss in Freeciv`);
  prev = w;
  if (turn - startTurn >= SEASONS || (w.reign?.status && w.reign.status !== "running")) break;
}

const by = failures.reduce((t, f) => ({ ...t, [f.check]: (t[f.check] ?? 0) + 1 }), {});
const report = { seasons: (prev?.turn ?? startTurn) - startTurn, from: startTurn, to: prev?.turn, pace: PACE, failures: failures.length, by, list: failures, world: path.join(OUT, "world.jsonl"), unitsLost: lost.size };
fs.writeFileSync(path.join(OUT, "report.json"), JSON.stringify(report, null, 1));
console.log(`  ${report.seasons} seasons (T${startTurn}-T${prev?.turn}); failures ${JSON.stringify(by)}; log ${report.world}`);
console.log(failures.length ? `REIGN HARNESS: ${failures.length} failed` : "REIGN HARNESS PASS");
worldLog.end();
stop();
process.exit(failures.length ? 1 : 0);
