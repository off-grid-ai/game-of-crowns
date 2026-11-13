// The King's crossing in a real reign (supervisor, render pass 2243: "the crossing waited 900 s and never boarded").
// crossing_probe.mjs proves the order and the Lua on a staged strait; this plays it on Aldmere itself, on a private
// bridge and Freeciv (8788 / 5557), the way render_pass.sh asks it: every host to every town asked dry, the quickest
// march by sea ordered, then season by season the host must walk to the shore, be aboard (/world hosts[].aboard) and
// come ashore (its order's sea phase "landed"), each within --seasons of the order. The hasty King
// (realm/tools/reign_measure.py) answers the court and the cards so the seasons turn.
//   node tools/crossing_reign_probe.mjs [--seasons 14] [--pace 3]        (from bridge/; exits 1 on a failure)
import { spawn, execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const ROOT = path.join(BRIDGE, "..");
const arg = (k, d) => { const i = process.argv.indexOf(`--${k}`); return i > 0 ? process.argv[i + 1] : d; };
const SEASONS = Number(arg("seasons", 14)), PACE = Number(arg("pace", 3));
const PORT = 8788, FC_PORT = 5557, B = `http://127.0.0.1:${PORT}`;
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), "crossing-reign-"));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const killFc = () => { try { execFileSync("pkill", ["-KILL", "-f", `freeciv-server -p ${FC_PORT} `]); } catch { /* none */ } };

killFc();
const blog = fs.createWriteStream(path.join(OUT, "bridge.log"));
const bridge = spawn("node", ["server.js"], { cwd: BRIDGE, env: { ...process.env, PORT: String(PORT), FC_PORT: String(FC_PORT), GOC_HOME: path.join(OUT, "home") } });
const blines = [];
const takeB = (d) => { blog.write(d); blines.push(...String(d).split("\n")); };
bridge.stdout.on("data", takeB);
bridge.stderr.on("data", takeB);
let king = null;
const stop = () => { try { king?.kill("SIGKILL"); } catch { /* gone */ } try { bridge.kill("SIGKILL"); } catch { /* gone */ } killFc(); };
process.on("exit", stop);
process.on("SIGINT", () => process.exit(130));
const get = async (p) => (await fetch(B + p, { signal: AbortSignal.timeout(30000) })).json();
const post = async (p, body) => (await fetch(B + p, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body), signal: AbortSignal.timeout(60000) })).json();
const end = (ok, text) => { console.log(text); console.log(ok ? "CROSSING REIGN PASS" : `CROSSING REIGN FAIL (log ${OUT})`); process.exit(ok ? 0 : 1); };

for (let t0 = Date.now(); !blines.some((l) => l.includes("Bridge listening")); await sleep(200)) {
  if (bridge.exitCode !== null || Date.now() - t0 > 30000) end(false, `the private bridge didn't start\n${blines.slice(-15).join("\n")}`);
}
await post("/chronicles", { name: "Crossing check", scenario: "aldmere", minutes: 0 });
let w = null;
for (let t0 = Date.now(); !(w?.turn > 0 && (w?.cities?.length ?? 0) > 5); await sleep(1000)) {
  if (Date.now() - t0 > 120000) end(false, "the realm never reported a world");
  try { w = await get("/world"); } catch { /* starting */ }
}

// As render_pass.sh: every host to every town, asked dry; the quickest by sea is ordered.
let best = null;
for (const h of w.hosts ?? []) for (const c of w.cities ?? []) {
  const a = await post("/host/order", { host: h.id, order: "march", city: c.id, dry: true }).catch(() => ({}));
  if (a.by === "sea" && (!best || a.seasons < best.a.seasons)) best = { h, c, a };
}
if (!best) end(false, "no march of the King's host goes by sea on Aldmere");
const r = await post("/host/order", { host: best.h.id, order: "march", city: best.c.id });
if (!r.ok) end(false, `the march by sea was refused: ${JSON.stringify(r)}`);
console.log(`  host ${best.h.id} (${best.h.units.length} companies) by sea for ${best.c.name}: ${JSON.stringify(best.a.sea)}, about ${best.a.seasons} seasons`);

await post("/speed", { seconds: PACE });
king = spawn("python3", ["-I", path.join(ROOT, "realm/tools/reign_measure.py"), `127.0.0.1:${PORT}`, String(SEASONS * PACE * 3), path.join(OUT, "king.json")], { cwd: ROOT, stdio: "ignore" });

const from = w.turn, lead = Math.min(...best.h.units);
let aboardAt = null, landedAt = null, last = w.turn, quietSince = Date.now();
const seen = [];
while (w.turn - from <= SEASONS) {
  await sleep(500);
  if (bridge.exitCode !== null) end(false, `the bridge exited (${bridge.exitCode})`);
  try { w = await get("/world"); } catch { continue; }
  if (w.turn === last) { if (Date.now() - quietSince > 120000) end(false, `no new season in 120 s at T${w.turn}`); continue; }
  last = w.turn; quietSince = Date.now();
  const h = (w.hosts ?? []).find((x) => x.units?.includes(lead));
  const u = (w.units ?? []).find((x) => x.id === lead);
  const line = `T${w.turn}: ${h ? `${h.order?.kind ?? "at ease"} ${h.order?.sea?.phase ?? "-"} aboard=${!!h.aboard}` : "no host"} lead at ${u ? `(${u.x},${u.y})` : "gone"}`;
  seen.push(line);
  console.log(`  ${line}`);
  if (h?.aboard && aboardAt == null) aboardAt = w.turn;
  if (h?.order?.sea?.phase === "landed" && landedAt == null) landedAt = w.turn;
  if (!h?.order?.sea && aboardAt == null && w.turn > from + 1) end(false, `the host left its crossing before boarding (${line})`);
  if (landedAt != null) break;
}
const decrees = await get("/chronicle").then((c) => (c.entries ?? c ?? []).filter?.((e) => /ship|shore|ashore/.test(e.text ?? "")).map((e) => `T${e.turn} ${e.text}`)).catch(() => []);
for (const d of decrees ?? []) console.log(`  ${d}`);
end(aboardAt != null && landedAt != null, `  aboard ${aboardAt != null ? `T${aboardAt}` : "never"}, landed ${landedAt != null ? `T${landedAt}` : "never"} (ordered T${from}, ${SEASONS} seasons allowed)`);
