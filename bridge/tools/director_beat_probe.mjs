// The director's beat (director.js beatDue, director.json quietByAct): a threat is due a few seasons after the King's
// last crisis, whatever the houses do among themselves (the Last Accord, 2026-11-16: their own wars held the realm's
// tension high every season and no threat rose in 25 seasons). Pure. Run: node bridge/tools/director_beat_probe.mjs
import { beatDue, DIRECTOR } from "../director.js";
let pass = 0, fail = 0;
const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? "PASS " : "FAIL ") + m); };
const meta = (share) => ({ minutes: 15, elapsedMs: share * 15 * 60000, openingState: { seasons: 99, wintered: true } });
const beat = (share) => { const d = { calm: 0 }; let n = 1; while (!beatDue(meta(share), d) && n < 50) n++; return n; };
const acts = [0.3, 0.4, 0.6, 0.8].map(beat);
ok(acts[1] <= 4, `act 2: a threat due within 4 seasons (${acts[1]})`);
ok(acts[3] <= 2, `act 4: within 2 seasons (${acts[3]})`);
ok(acts[3] <= acts[1], "threats come sooner as the reign builds");
ok(DIRECTOR.breather <= 3, `a breather of at most 3 seasons after a peak (${DIRECTOR.breather})`);
const quiet = { calm: 5 };
ok(!beatDue({ minutes: 15, elapsedMs: 0, openingState: { seasons: 0 } }, quiet) && quiet.calm === 0, "the opening's quiet: nothing due before the King has had his year");
console.log(`${fail ? "FAIL" : "PASS"} ${pass}/${pass + fail}`);
process.exit(fail ? 1 : 0);
