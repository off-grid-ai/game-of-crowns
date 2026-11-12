// Guards opening a realm: the bridge must live through a new chronicle being made and switched to (POST
// /chronicles), the moment the old realm is gone and the new one has no world yet. Before the fix, load()
// queued townStates() with `world` still null and its `world.intrigue` threw outside any handler, killing
// the bridge (and with it a film round). A private bridge on its own ports and GOC_HOME; Mac's realm is
// never touched. Exits 1 on a failure.
//   node tools/switch_probe.mjs        (from bridge/)
import { spawn, execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { checker } from "./fc_probe_lib.mjs";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 8795, FC_PORT = 5579;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const { check, done } = checker("SWITCH");
const home = fs.mkdtempSync(path.join(os.tmpdir(), "switch-probe-"));
const kill = () => { try { execFileSync("pkill", ["-KILL", "-f", `freeciv-server -p ${FC_PORT} `]); } catch { /* none */ } };
kill();

const bridge = spawn("node", ["server.js"], { cwd: BRIDGE, env: { ...process.env, PORT: String(PORT), FC_PORT: String(FC_PORT), GOC_HOME: home } });
let log = "";
bridge.stdout.on("data", (d) => { log += d; });
bridge.stderr.on("data", (d) => { log += d; });
const until = async (ok, ms) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (ok()) return true; if (bridge.exitCode !== null) return false; await sleep(200); } return false; };

check(await until(() => log.includes("Bridge listening"), 30000), "the private bridge didn't start");
// A new realm of every kind, one straight after the other: each switch drops the realm open before it, and the
// fresh and random ones have no world at all until Freeciv first reports.
for (const scenario of ["aldmere", "aldmere_fresh", "random"]) {
  const name = `Switch probe test ${scenario}`;
  const r = await fetch(`http://127.0.0.1:${PORT}/chronicles`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ name, scenario }) }).catch((e) => ({ ok: false, status: e.message }));
  check(r.ok, `POST /chronicles "${name}" failed (${r.status})`);
  await sleep(4000);
  check(bridge.exitCode === null, `the bridge died opening "${name}" (exit ${bridge.exitCode})`);
}
const thrown = log.split("\n").filter((l) => /TypeError|ReferenceError|Uncaught/.test(l));
check(!thrown.length, `the bridge threw: ${thrown.slice(0, 3).join(" | ")}`);
if (bridge.exitCode !== null) console.log(log.split("\n").slice(-15).join("\n"));
bridge.kill("SIGKILL");
kill();
fs.rmSync(home, { recursive: true, force: true });
done();
