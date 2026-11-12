// Guards READY.md line 12's "barracks' free company gone" and "levy and garrison at the rule sizes" (docs/research/world-and-siege-rules.md 3.3; casebook,
// The crowd is the census, Stronghold: a levy is a queue you can count, a garrison a block at the gate). The view's
// gate parties (realm/data/decisions.json) stand at the rule's sizes: 8-12 recruits in a levy's queue, a block of 12
// or more guards with 2 standards. Exits 1 on a breach.   node tools/rule_sizes_probe.mjs        (from bridge/)
import fs from "node:fs";
import { checker } from "./fc_probe_lib.mjs";

const { check, done } = checker("RULE SIZES");
const d = JSON.parse(fs.readFileSync(new URL("../../realm/data/decisions.json", import.meta.url), "utf8"));
check(d.levy?.recruits >= 8 && d.levy.recruits <= 12, `a levy's queue is ${d.levy?.recruits} recruits (rule: 8-12)`);
check(d.garrison?.guards >= 12 && d.garrison.standards === 2, `a garrison is ${d.garrison?.guards} guards and ${d.garrison?.standards} standards (rule: 12 or more, with 2)`);
// The barracks' free company is gone (Freeciv's Barracks make veterans; the crown's men are bought or raised by order).
check(!/includes\("Barracks"\)/.test(fs.readFileSync(new URL("../treasury.js", import.meta.url), "utf8")), "the crown still gets a free company a year from each barracks");
console.log(`  levy ${d.levy?.recruits} recruits; garrison ${d.garrison?.guards} guards, ${d.garrison?.standards} standards`);
done();
