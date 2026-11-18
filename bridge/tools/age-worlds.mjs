// The realm at the ages reigns reach, for the bake (realm/tools/bake.gd): every saved chronicle's last snapshot, in the
// shape the bridge serves it (served-world.mjs), written to baseline/aldmere/ages/<turn>-<id>.world.json, so the game
// ships its towns as they stand a year, three, nine years into a reign and a player never watches one laid out (Mac,
// 2026-11-18: "you play 9 years once ... and you save it, and the next time you just use that"). Every chronicle is of
// the baseline's map, so only the world is kept. A chronicle whose towns all stand already (in the baseline or an age
// kept before it, by the facts a kept town is keyed by: town_store.gd path_of) adds nothing and is left out.
// Measured on 87 reigns (2026-11-18), a new reign's towns found already baked: 98% in its first year, 89% by its third,
// 83% by its sixth, 69% by its tenth. Run when the chronicles have grown; the ages are committed, as the baseline is:
//   node tools/age-worlds.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { servedWorld } from "./served-world.mjs";

const DIR = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const ROOT = path.join(DIR, "chronicles");
const BASE = path.join(DIR, "baseline", "aldmere");
const OUT = path.join(BASE, "ages");
const MAP = fs.readFileSync(path.join(BASE, "state", "map.json"), "utf8");

// What a kept town is keyed by (town_store.gd path_of), less the land (one map) and the crown's flag (with its holder).
const key = (c) => JSON.stringify([c.id, c.x, c.y, c.size, [...(c.buildings ?? [])].sort(), !!c.capital, c.family ?? null]);
const seen = new Set(JSON.parse(fs.readFileSync(path.join(BASE, "state", "world_served.json"), "utf8")).cities.map(key));

fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(OUT, { recursive: true });
const reigns = [];
for (const id of fs.readdirSync(ROOT)) {
  const at = path.join(ROOT, id);
  const file = path.join(at, "state", "world.json");
  if (!fs.existsSync(file) || !fs.existsSync(path.join(at, "characters"))) continue;
  if (fs.readFileSync(path.join(at, "state", "map.json"), "utf8") !== MAP) continue;  // another land: its towns never key as ours
  try {
    reigns.push({ id, world: servedWorld(JSON.parse(fs.readFileSync(file, "utf8")), path.join(at, "characters")) });
  } catch (e) {
    console.error(`chronicle ${id}: ${e.message}`);
  }
}
reigns.sort((a, b) => a.world.turn - b.world.turn);  // the young first: the towns most reigns pass through
let kept = 0;
for (const { id, world } of reigns) {
  const fresh = world.cities.filter((c) => !seen.has(key(c)));
  if (fresh.length === 0) continue;
  for (const c of world.cities) seen.add(key(c));
  fs.writeFileSync(path.join(OUT, `${String(world.turn).padStart(4, "0")}-${id}.world.json`), JSON.stringify(world));
  console.log(`${id} turn ${world.turn}: ${fresh.length} towns new`);
  kept++;
}
console.log(`ages: ${kept} of ${reigns.length} chronicles kept, ${seen.size} town states`);
