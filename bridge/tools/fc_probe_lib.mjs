// A bare Freeciv for probes: our ruleset (bridge/data), its own saves folder and port, driven through its
// console like the bridge drives the realm's. No bridge, no chronicle, nothing of Mac's realm touched.
//   const fc = await bareFreeciv({ port, serv });  await fc.cmd("lua cmd ...");  fc.lines; await fc.quit();
// Probes built on it live beside it (tools/*_probe.mjs) and exit 1 on a failure.
import { spawn, execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const SHARE = process.env.FREECIV_SHARE || "/opt/homebrew/share/freeciv";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// serv: the start script's lines (rulesetdir realmrules is added first). save: a save to load instead.
export async function bareFreeciv({ port = 5571, serv = [], save = null, saves = null } = {}) {
  try { execFileSync("pkill", ["-KILL", "-f", `freeciv-server -p ${port} `]); } catch { /* none */ }
  const dir = saves ?? fs.mkdtempSync(path.join(os.tmpdir(), "fc-probe-"));
  const script = path.join(dir, `start-${Date.now()}.serv`);
  // A new game is laid out as the realm is (realm.serv: flat, no wrap), so map coordinates mean the same.
  fs.writeFileSync(script, (save ? serv : ["rulesetdir realmrules", 'set topology ""', 'set wrap ""', ...serv]).join("\n") + "\n");
  const args = ["-p", String(port), "-s", dir, "-d", "n", "-b", "127.0.0.1", "-r", script];
  if (save) args.push("-f", save);
  const env = { ...process.env, FREECIV_DATA_PATH: `${path.join(BRIDGE, "data")}:${SHARE}` };
  const proc = spawn(process.env.FREECIV_SERVER || "freeciv-server", args, { cwd: BRIDGE, env });
  const lines = [];
  let pending = "";
  const take = (d) => { pending += d; const l = pending.split("\n"); pending = l.pop(); lines.push(...l); };
  proc.stdout.on("data", take);
  proc.stderr.on("data", take);
  proc.stdin.on("error", () => {});  // the server gone mid-write: the checks say so
  const fc = {
    dir, lines, proc,
    send: (l) => { if (proc.exitCode === null && !proc.stdin.destroyed) proc.stdin.write(l + "\n"); },
    // Wait until a line matches (from line `from` on); null after `ms`.
    async until(re, ms = 60000, from = 0) {
      const t0 = Date.now();
      while (Date.now() - t0 < ms) {
        const hit = lines.slice(from).find((l) => re.test(l));
        if (hit) return hit;
        if (proc.exitCode !== null) return null;
        await sleep(100);
      }
      return null;
    },
    // Run a console line and return what it printed that matches re.
    async cmd(line, re = null, ms = 10000) {
      const from = lines.length;
      fc.send(line);
      return re ? fc.until(re, ms, from) : (await sleep(300), null);
    },
    events: (kind) => lines.filter((l) => l.includes("EVENT {") && l.includes(`"kind":"${kind}"`)),
    newestSave() {
      const f = fs.readdirSync(dir).filter((x) => x.includes(".sav")).map((x) => ({ x, t: fs.statSync(path.join(dir, x)).mtimeMs })).sort((a, b) => b.t - a.t)[0];
      return f ? path.join(dir, f.x) : null;
    },
    async quit() {
      if (proc.exitCode !== null) return;
      fc.send("quit");
      const t0 = Date.now();
      while (proc.exitCode === null && Date.now() - t0 < 5000) await sleep(100);
      if (proc.exitCode === null) proc.kill("SIGKILL");
    },
  };
  return fc;
}

// A probe's failures, counted; done() prints PASS or exits 1.
export function checker(name) {
  let bad = 0;
  return {
    check(ok, what) { if (!ok) { bad++; console.log(`${name} FAIL`, what); } },
    done() { if (bad) { console.log(`${name}: ${bad} failed`); process.exit(1); } console.log(`${name} PASS`); },
  };
}
