// The bridge as the packaged game runs it (Game of Crowns.app, started by
// realm/scripts/app_services.gd). Everything it needs is inside the app:
//   Contents/Resources/bridge     this folder
//   Contents/Resources/runtime    node, freeciv (bin, lib, share), llama (llama-server)
// Realms, records and logs go to ~/Library/Application Support/Game of Crowns.
// Omni 2B (text only) is fetched on first run, as Off Grid AI Desktop fetches
// its models: one pinned file, checked against its sha256, then served by
// Off Grid's llama-server on 127.0.0.1:8789. The realm plays by its rules
// until the model is ready. When the game quits (or dies), this process takes
// Freeciv and the model down with it.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { spawn } from "node:child_process";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { fileURLToPath } from "node:url";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const RUNTIME = path.join(DIR, "..", "runtime");
const HOME = process.env.GOC_HOME || path.join(os.homedir(), "Library", "Application Support", "Game of Crowns");
const MODELS = path.join(HOME, "models");
const LOGS = path.join(HOME, "logs");
const LLM_PORT = Number(process.env.GOC_LLM_PORT || 8789);

// LiquidAI/LFM3-Omni-2B-GGUF, pinned to one revision. Q8_0: the text model only.
const OMNI = {
  name: "LFM3-Omni-2B-Q8_0.gguf",
  url: "https://huggingface.co/LiquidAI/LFM3-Omni-2B-GGUF/resolve/d508b88f08a5b4286f2d2805a6a8d69a0ff44c72/LFM3-Omni-2B-Q8_0.gguf",
  size: 1846240768,
  sha256: "59118f661eaacb93d204723d76355b53347f0940b508c11412f6290fd49158d4",
};
// Already on this Mac through Off Grid AI Desktop? Then use that copy.
const OGAD_MODELS = path.join(os.homedir(), "Library", "Application Support", "Off Grid AI Desktop", "models");

fs.mkdirSync(MODELS, { recursive: true });
fs.mkdirSync(LOGS, { recursive: true });
process.env.GOC_HOME = HOME;
process.env.FREECIV_SERVER = path.join(RUNTIME, "freeciv", "bin", "freeciv-server");
process.env.FREECIV_SHARE = path.join(RUNTIME, "freeciv", "share", "freeciv");
process.env.GOC_LLM_URL = `http://127.0.0.1:${LLM_PORT}/v1`;

let llama = null;
let quitting = false;

function localOmni() {
  const own = path.join(MODELS, OMNI.name);
  if (fs.existsSync(own)) return own;
  try {
    const f = fs.readdirSync(OGAD_MODELS).find((n) => /^LFM3-Omni-2B.*\.gguf$/i.test(n));
    if (f) return path.join(OGAD_MODELS, f);
  } catch { /* no Off Grid AI Desktop */ }
  return null;
}

async function fetchOmni() {
  const dest = path.join(MODELS, OMNI.name);
  const part = dest + ".part";
  console.log(`omni: fetching ${OMNI.name} (${(OMNI.size / 1e9).toFixed(1)} GB) for the realm's voices`);
  const res = await fetch(OMNI.url, { redirect: "follow" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const hash = crypto.createHash("sha256");
  let got = 0;
  let shown = 0;
  const body = Readable.fromWeb(res.body);
  body.on("data", (chunk) => {
    hash.update(chunk);
    got += chunk.length;
    if (got - shown > 100e6) {
      shown = got;
      console.log(`omni: ${Math.round((got / OMNI.size) * 100)}%`);
    }
  });
  await pipeline(body, fs.createWriteStream(part));
  if (got !== OMNI.size || hash.digest("hex") !== OMNI.sha256) {
    fs.rmSync(part, { force: true });
    throw new Error("the download didn't match its checksum");
  }
  fs.renameSync(part, dest);
  return dest;
}

function startLlama(model) {
  if (quitting) return;
  const bin = path.join(RUNTIME, "llama", "llama-server");
  const log = fs.openSync(path.join(LOGS, "omni.log"), "a");
  llama = spawn(bin, ["-m", model, "--host", "127.0.0.1", "--port", String(LLM_PORT), "--alias", "LFM3-Omni-2B", "-c", "8192", "-ngl", "99"], { stdio: ["ignore", log, log] });
  llama.on("exit", (code) => {
    console.log(`omni: llama-server exited (${code})`);
    llama = null;
  });
  console.log(`omni: serving ${path.basename(model)} on ${process.env.GOC_LLM_URL}`);
}

async function omni() {
  let model = localOmni();
  for (let attempt = 1; !model && !quitting; attempt++) {
    try {
      model = await fetchOmni();
    } catch (err) {
      console.error(`omni: ${err.message}; trying again in a minute`);
      await new Promise((r) => setTimeout(r, 60000 * Math.min(attempt, 10)));
    }
  }
  if (model) startLlama(model);
}

function shutdown() {
  if (quitting) return;
  quitting = true;
  llama?.kill("SIGTERM");
  // server.js stops Freeciv on SIGTERM, then exits.
  process.kill(process.pid, "SIGTERM");
}
process.on("exit", () => llama?.kill("SIGKILL"));

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
omni();
await import("./server.js");
