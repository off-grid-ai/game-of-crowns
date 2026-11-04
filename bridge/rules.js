// Facts from our Freeciv ruleset that the save files don't repeat:
// what things cost to build and how big a town's granary is.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const RULES = path.join(path.dirname(fileURLToPath(import.meta.url)), "data", "realmrules");

function costs(file) {
  const out = {};
  const text = fs.readFileSync(path.join(RULES, file), "utf8");
  for (const block of text.split(/^\[/m)) {
    const name = block.match(/^name\s*=\s*_\("([^"]+)"\)/m);
    const cost = block.match(/^build_cost\s*=\s*(\d+)/m);
    if (name && cost) out[name[1]] = Number(cost[1]);
  }
  return out;
}

export const BUILD_COST = { ...costs("units.ruleset"), ...costs("buildings.ruleset") };

const game = fs.readFileSync(path.join(RULES, "game.ruleset"), "utf8");
const GRANARY_INI = (game.match(/^granary_food_ini\s*=\s*([\d,\s]+)$/m)?.[1] ?? "20").split(",").map((n) => Number(n.trim()));
const GRANARY_INC = Number(game.match(/^granary_food_inc\s*=\s*(\d+)/m)?.[1] ?? 0);

export function granarySize(size) {
  const i = Math.max(1, size) - 1;
  if (i < GRANARY_INI.length) return GRANARY_INI[i];
  return GRANARY_INI[GRANARY_INI.length - 1] + GRANARY_INC * (i - GRANARY_INI.length + 1);
}
