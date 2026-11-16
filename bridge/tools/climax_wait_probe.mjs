// The reign's clock waits for the climax the last act named (reign.js climaxComing, director.json finale.grace).
// The Last Accord (2026-11-16): Thornvale's claim named at turn 55, its host still marching when the clock ended the
// reign at 63. Pure: no bridge, no Freeciv. Run: node bridge/tools/climax_wait_probe.mjs
import { climaxComing } from "../reign.js";
let pass = 0, fail = 0;
const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? "PASS " : "FAIL ") + m); };
const ctx = (kind, extra = {}) => ({ meta: { lastAct: kind ? { kind, threat: "x" } : null, director: extra.director ?? {} }, stakes: { s: { usurper: { stage: extra.stage ?? "none" } } }, arcs: { reignView: () => ({ status: extra.story ?? "done" }) } });
ok(climaxComing(ctx("pretender", { stage: "march" })), "a pretender on the march holds the clock");
ok(climaxComing(ctx("pretender", { stage: "rumour" })), "a pretender's rumour holds the clock");
ok(!climaxComing(ctx("pretender", { stage: "none" })), "a broken pretender lets the reign end");
ok(climaxComing(ctx("houses", { director: { threat: { finale: true } } })), "the finale's host on the road holds the clock");
ok(!climaxComing(ctx("houses", { director: { threat: { finale: false } } })), "an ordinary threat does not");
ok(climaxComing(ctx("story", { story: "running" })), "the named story running holds the clock");
ok(!climaxComing(ctx(null)), "no last act: the clock rules");
console.log(`${fail ? "FAIL" : "PASS"} ${pass}/${pass + fail}`);
process.exit(fail ? 1 : 0);
