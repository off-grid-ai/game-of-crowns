// The Freeciv server process and the line protocol to it: spawning
// freeciv-server for a realm, writing server commands to its stdin, reading
// its stdout and stderr line by line, stopping it, and finding the realm's
// newest save. No game logic here: what an EVENT line means, and what to do
// when Freeciv exits, belong to the caller (server.js), passed in as callbacks.

import { spawn, execFileSync } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";

export const FC_PORT = Number(process.env.FC_PORT || 5556);

let fc = null; // the Freeciv process

// The running Freeciv process, or null.
export const proc = () => fc;

export function send(line) {
  if (fc && !fc.killed) fc.stdin.write(line + "\n");
}

// The game asks every second; a reign keeps hundreds of saves. Each file's time is
// read once, and the folder is only listed again when Freeciv has written to it.
const savesSeen = { dir: null, mtime: 0, list: [] };

export function newestSave(saves, kind = "") {
  const mtime = fs.statSync(saves).mtimeMs;
  if (savesSeen.dir !== saves || savesSeen.mtime !== mtime) {
    savesSeen.list = fs.readdirSync(saves).filter((f) => f.startsWith("realm") && f.includes(".sav"))
      .map((f) => ({ f, t: fs.statSync(path.join(saves, f)).mtimeMs })).sort((a, b) => b.t - a.t);
    savesSeen.dir = saves;
    savesSeen.mtime = mtime;
  }
  // An autosave, or the King's truce save written in its place (the newer of
  // the two is the realm as Freeciv now holds it, wars and all).
  const hit = savesSeen.list.find((x) => x.f.includes(kind) || (kind === "auto" && x.f.includes("ceasefire")));
  return hit ? path.join(saves, hit.f) : null;
}

// Start Freeciv for a realm, from its newest save (or its .serv for a new one).
// opts: { name, P (chronicle paths), dir (the bridge folder), onEvent(line) for
// "EVENT {" lines, onExit(code) when the running Freeciv exits by itself or is
// stopped }. Returns the save it resumed from, or null for a new realm.
export function start({ name, P, dir, onEvent, onExit }) {
  // A Freeciv left behind by an earlier bridge (restarts kill Node, not its
  // child) would hold the port and stop this one starting: clear it first.
  // It may be busy saving and ignore a polite request, so it's killed outright.
  try {
    execFileSync("pkill", ["-KILL", "-f", `freeciv-server -p ${FC_PORT} `]);
  } catch { /* none running */ }
  const save = newestSave(P.saves);
  const resume = path.join(P.base, "resume.serv");
  fs.writeFileSync(resume, `lua file ${path.join(dir, "lua", "events.lua")}\nstart\n`);
  const args = ["-p", String(FC_PORT), "-s", P.saves, "-d", "n", "-b", "127.0.0.1"];
  if (save) args.push("-f", save, "-r", resume);
  else args.push("-r", P.serv);
  console.log(`${name}: ${save ? `resuming from ${path.basename(save)}` : "creating a new realm"}`);
  // This realm's temperaments, then our medieval ruleset, then Freeciv's own data.
  // The app brings its own Freeciv (bridge/app.js sets FREECIV_SERVER and FREECIV_SHARE).
  const share = process.env.FREECIV_SHARE || "/opt/homebrew/share/freeciv";
  const env = { ...process.env, FREECIV_DATA_PATH: `${P.data}:${path.join(dir, "data")}:${share}` };
  const proc = spawn(process.env.FREECIV_SERVER || "freeciv-server", args, { cwd: dir, env });
  fc = proc;
  const log = fs.createWriteStream(path.join(P.state, "freeciv.log"), { flags: "a" });
  let pending = "";
  const onLine = (line) => (line.includes("EVENT {") ? onEvent(line) : log.write(line + "\n"));
  proc.stdout.on("data", (d) => {
    pending += d;
    const lines = pending.split("\n");
    pending = lines.pop();
    lines.forEach(onLine);
  });
  proc.stderr.on("data", (d) => String(d).split("\n").forEach(onLine));
  proc.on("exit", (code) => {
    console.log(`freeciv-server exited (${code})`);
    log.end();
    if (fc === proc) {
      fc = null;
      onExit?.(code);
    }
  });
  return save;
}

export function stop() {
  return new Promise((resolve) => {
    if (!fc) return resolve();
    const proc = fc;
    proc.once("exit", () => resolve());
    send("save");
    setTimeout(() => send("quit"), 800);
    setTimeout(() => proc.kill("SIGKILL"), 6000);
  });
}

// The hitch: how long the realm was without Freeciv while the truce went in.
// Logs once Freeciv answers on its port again, counted from t0.
export function timeReload(t0) {
  const probe = () => {
    const c = net.connect(FC_PORT, "127.0.0.1", () => { c.destroy(); console.log(`ceasefire reload: ${Date.now() - t0} ms`); });
    c.on("error", () => (Date.now() - t0 < 120000 ? setTimeout(probe, 100) : console.log("ceasefire reload: no answer in 120 s")));
  };
  probe();
}
