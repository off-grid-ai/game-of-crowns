// Guards integration audit #14 (READY.md line 15: SSOT, SOLID): server.js gives every module one context, whose
// realm state is read through getters (a copy taken when a context was made went stale), and diplomacy has one
// writer, diplomacy.js. Its writer is driven here against a copy of the baseline save. Exits 1 on a breach.
//   node tools/one_ctx_probe.mjs        (from bridge/)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";
import { checker } from "./fc_probe_lib.mjs";
import * as Diplomacy from "../diplomacy.js";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const { check, done } = checker("ONE CTX");
const server = fs.readFileSync(path.join(BRIDGE, "server.js"), "utf8");
check(!/const \w+Ctx = \(\) => \(\{/.test(server), "server.js still hand-wires a context of its own beside realmCtx");
const lets = [...server.matchAll(/^let (\w+) = /gm)].map((m) => m[1]);
const ctx = server.slice(server.indexOf("function realmCtx()"), server.indexOf("});", server.indexOf("function realmCtx()")));
for (const v of ["meta", "world", "court", "stakes", "scenes", "paused", "turnSeconds", "counselNow", "sitting"]) {
  check(lets.includes(v) && ctx.includes(`get ${v}() { return ${v}; }`), `realmCtx doesn't read ${v} through a getter`);
}
check(!/function setDipl\(|async function setDiplomacy|editRow\(/.test(server), "server.js still writes diplomacy itself");
for (const f of fs.readdirSync(BRIDGE).filter((x) => x.endsWith(".js") && x !== "diplomacy.js")) {
  if (/editRow\([^)]*"(diplstate|ai)"/.test(fs.readFileSync(path.join(BRIDGE, f), "utf8"))) check(false, `${f} writes diplomacy rows beside diplomacy.js`);
}

// The writer: a war and a truce written into a copy of the baseline save, one reload.
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "goc-dipl-"));
const base = path.join(dir, "realm-T0038-base.sav.zst");
fs.copyFileSync(path.join(BRIDGE, "baseline/aldmere/saves/realm-T0038-Y-2150-auto.sav.zst"), base);
let held = false, stopped = 0, started = 0;
const realm = { proc: () => true, busy: () => held, hold: (v) => { held = v; }, stop: async () => { stopped++; }, start: () => { started++; },
  newestSave: () => base, saves: dir, turn: () => 38, timeReload: () => {} };
check(await Diplomacy.write(realm, [[1, 4, 0, "War"], [2, 3, 8]]), "diplomacy.js didn't write");
const out = fs.readdirSync(dir).find((f) => f.includes("-diplomacy-"));
const text = out ? zlib.zstdDecompressSync(fs.readFileSync(path.join(dir, out))).toString() : "";
const row = (p, q) => { const blk = text.slice(text.indexOf(`[player${p}]`)); return blk.slice(blk.indexOf("diplstate=")).split("\n")[1 + q]; };
check(/^"War","War"/.test(row(1, 4) ?? "") && /^"War","War"/.test(row(4, 1) ?? ""), `the war isn't in the save both ways (${row(1, 4)})`);
check(/^"Cease-fire","Cease-fire"/.test(row(2, 3) ?? "") && /^"Cease-fire","Cease-fire"/.test(row(3, 2) ?? ""), `the truce isn't in the save both ways (${row(2, 3)})`);
check(stopped === 1 && started === 1 && held === false, "the writer didn't stop, restart and release the realm once");
fs.rmSync(dir, { recursive: true, force: true });
done();
