// The bridge as the packaged game runs it (Game of Crowns.app, started by
// realm/scripts/app_services.gd). Everything it needs is inside the app:
//   Contents/Resources/bridge     this folder
//   Contents/Resources/runtime    node, freeciv (bin, lib, share)
// Realms, records and logs go to ~/Library/Application Support/Game of Crowns.
// No model ships with the game and nothing is downloaded: the realm plays by
// its rules, and when Off Grid AI (https://getoffgridai.co/desktop) is running
// Omni on this Mac, the lords speak in their own words through it (claude.js
// finds it). When the game quits (or dies), this process takes Freeciv with it.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const RUNTIME = path.join(DIR, "..", "runtime");
const HOME = process.env.GOC_HOME || path.join(os.homedir(), "Library", "Application Support", "Game of Crowns");
const LOGS = path.join(HOME, "logs");
fs.mkdirSync(LOGS, { recursive: true });
process.env.GOC_HOME = HOME;
process.env.FREECIV_SERVER = path.join(RUNTIME, "freeciv", "bin", "freeciv-server");
process.env.FREECIV_SHARE = path.join(RUNTIME, "freeciv", "share", "freeciv");

let quitting = false;

function shutdown() {
  if (quitting) return;
  quitting = true;
  // server.js stops Freeciv on SIGTERM, then exits.
  process.kill(process.pid, "SIGTERM");
}

// The game that started us: when it goes, so do we.
const parent = Number(process.env.GOC_PARENT_PID || process.ppid);
setInterval(() => {
  try {
    process.kill(parent, 0);
  } catch {
    shutdown();
  }
  if (process.ppid === 1) shutdown();
}, 1000).unref();

console.log(`Game of Crowns ${new Date().toISOString()}: realms in ${HOME}`);
await import("./server.js");
