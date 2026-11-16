// Every answer to a chronicle matter but Leave it takes the season's seal (routes_court counselAnswer, seals.js).
// Mac 2026-11-16: "I can still rule on multiple things one after the other" (the host's, defend's and the tithe's answers
// went free). Pure: a fake request and reply, no bridge. Run: node bridge/tools/matter_seal_probe.mjs
import { EventEmitter } from "node:events";
import { counselAnswer } from "../routes_court.js";
let pass = 0, fail = 0;
const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? "PASS " : "FAIL ") + m); };
const req = (o) => { const r = new EventEmitter(); setTimeout(() => { r.emit("data", JSON.stringify(o)); r.emit("end"); }, 0); return r; };
const res = () => ({ code: 0, writeHead(c) { this.code = c; }, end() {} });
const meta = { status: "running", seals: { n: 1, spent: [] }, options: {} };
const ctx = { meta, world: { turn: 5 }, counselNow: () => [] };
let r = res();
await counselAnswer(ctx, req({ key: "nokey-a" }), r).catch(() => {});
ok(meta.seals.n === 0, `the first answer takes the seal (left ${meta.seals.n})`);
r = res();
await counselAnswer(ctx, req({ key: "nokey-b" }), r).catch(() => {});
ok(r.code === 400, `a second answer the same season is refused (${r.code})`);
r = res();
await counselAnswer(ctx, req({ key: "nokey-c", leave: true }), r).catch(() => {});
ok(r.code !== 400, `Leave it takes no seal and is never refused (${r.code})`);
console.log(`${fail ? "FAIL" : "PASS"} ${pass}/${pass + fail}`);
process.exit(fail ? 1 : 0);
