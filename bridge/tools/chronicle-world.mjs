// A saved chronicle's realm as the game will continue it, for the bake (realm/tools/bake.gd): its last snapshot
// (state/world.json, written each season by snapshot.lua) in the shape the bridge serves it (served-world.mjs), with
// its map (state/map.json) and land (meta.json land). The bridge needn't run: everything is read from the chronicle's
// folder. Which chronicle: the ones named, else the one the game continues (chronicles/active).
//   node tools/chronicle-world.mjs <out dir> [chronicle id ...]
// Writes <out dir>/<id>.world.json and <id>.map.json (land folded in), one pair a chronicle; prints each id.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { servedWorld } from "./served-world.mjs";

const DIR = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const ROOT = path.join(DIR, "chronicles");
const [out, ...named] = process.argv.slice(2);
if (!out) { console.error("usage: node tools/chronicle-world.mjs <out dir> [chronicle id ...]"); process.exit(2); }
const active = fs.existsSync(path.join(ROOT, "active")) ? fs.readFileSync(path.join(ROOT, "active"), "utf8").trim() : "";
const ids = named.length ? named : active ? [active] : [];
fs.mkdirSync(out, { recursive: true });
let made = 0;
for (const id of ids) {
  const at = path.join(ROOT, id);
  const read = (f) => JSON.parse(fs.readFileSync(path.join(at, f), "utf8"));
  if (!fs.existsSync(path.join(at, "state", "world.json")) || !fs.existsSync(path.join(at, "state", "map.json"))) {
    console.error(`chronicle ${id}: no state/world.json or state/map.json (never played a season)`);
    continue;
  }
  const map = read("state/map.json");
  map.land = read("meta.json").land;
  fs.writeFileSync(path.join(out, `${id}.world.json`), JSON.stringify(servedWorld(read("state/world.json"), path.join(at, "characters"))));
  fs.writeFileSync(path.join(out, `${id}.map.json`), JSON.stringify(map));
  console.log(id);
  made++;
}
process.exit(made > 0 || ids.length === 0 ? 0 : 1);
