// Checks every story arc in bridge/arcs/ and says what's wrong with any of
// them, so a hand-written arc can be tried before the realm reads it.
//   node bridge/arcs-check.js

import { templates } from "./arcs.js";

let bad = 0;
for (const t of templates()) {
  if (t.problems.length) {
    bad++;
    console.log(`✗ ${t.file}\n  ${t.problems.join("\n  ")}`);
  } else {
    console.log(`✓ ${t.file}: ${t.name ?? t.id}, ${Object.keys(t.roles).length} roles, ${t.beats.length} beats`);
  }
}
process.exit(bad ? 1 : 0);
