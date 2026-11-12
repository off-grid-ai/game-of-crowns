// Facts from our Freeciv ruleset that the save files don't repeat:
// what things cost to build, a unit's full hit points and how big a town's granary is.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const RULES = path.join(path.dirname(fileURLToPath(import.meta.url)), "data", "realmrules");

// A number every section of a ruleset file gives, by the section's name: { name: value }.
// unqualified: a name's "?unit:" qualifier dropped ("?unit:Workers" is Workers in a save).
function field(file, key, unqualified = false) {
  const out = {};
  const text = fs.readFileSync(path.join(RULES, file), "utf8");
  for (const block of text.split(/^\[/m)) {
    const name = block.match(unqualified ? /^name\s*=\s*_\("(?:\?unit:)?([^"]+)"\)/m : /^name\s*=\s*_\("([^"]+)"\)/m);
    const value = block.match(new RegExp(`^${key}\\s*=\\s*(\\d+)`, "m"));
    if (name && value) out[name[1]] = Number(value[1]);
  }
  return out;
}

export const BUILD_COST = { ...field("units.ruleset", "build_cost"), ...field("buildings.ruleset", "build_cost") };
export const HITPOINTS = field("units.ruleset", "hitpoints", true);  // a unit type's full health

// The hulls that carry hosts over water (units.ruleset: a buildable Sea or Trireme class unit): { name: { carry (its
// transport_cap), speed (its move_rate, tiles a season), deep (a Sea class hull crosses deep water; a Trireme keeps
// to the coast and the lakes) } }.
export const HULLS = (() => {
  const out = {};
  for (const block of fs.readFileSync(path.join(RULES, "units.ruleset"), "utf8").split(/^\[/m)) {
    const name = block.match(/^name\s*=\s*_\("([^"]+)"\)/m)?.[1];
    const cls = block.match(/^class\s*=\s*"([^"]+)"/m)?.[1];
    if (!name || !(cls === "Sea" || cls === "Trireme") || /"NoBuild"/.test(block)) continue;
    out[name] = { carry: Number(block.match(/^transport_cap\s*=\s*(\d+)/m)?.[1] ?? 0), speed: Number(block.match(/^move_rate\s*=\s*(\d+)/m)?.[1] ?? 1), deep: cls === "Sea" };
  }
  return out;
})();

const game = fs.readFileSync(path.join(RULES, "game.ruleset"), "utf8");
const GRANARY_INI = (game.match(/^granary_food_ini\s*=\s*([\d,\s]+)$/m)?.[1] ?? "20").split(",").map((n) => Number(n.trim()));
const GRANARY_INC = Number(game.match(/^granary_food_inc\s*=\s*(\d+)/m)?.[1] ?? 0);

export function granarySize(size) {
  const i = Math.max(1, size) - 1;
  if (i < GRANARY_INI.length) return GRANARY_INI[i];
  return GRANARY_INI[GRANARY_INI.length - 1] + GRANARY_INC * (i - GRANARY_INI.length + 1);
}
