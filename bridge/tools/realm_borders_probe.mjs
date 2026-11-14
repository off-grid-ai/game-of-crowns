// Guards Mac's order (2026-11-14): the whole continent is held by the crown and the great houses from a reign's first
// frame. Loads the Aldmere baseline (what every new reign starts from) in a bare Freeciv, saves at once, and counts
// the land of the realm's main continent (the landmass with most towns) no house's border claims. Exits 1 on any.
//   node tools/realm_borders_probe.mjs        (from bridge/)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import zlib from "node:zlib";
import { bareFreeciv, checker } from "./fc_probe_lib.mjs";

const { check, done } = checker("REALM BORDERS");
const base = path.join(path.dirname(new URL(import.meta.url).pathname), "..", "baseline", "aldmere", "saves");
const src = path.join(base, fs.readdirSync(base).find((f) => f.endsWith(".sav.zst")));
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "fc-borders-"));
const copy = path.join(dir, path.basename(src));
fs.copyFileSync(src, copy);
const fc = await bareFreeciv({ port: 5574, save: copy, saves: dir, serv: ["set timeout -1", "set autosaves \"\""] });
check(await fc.until(/Loading saved game|Now accepting/i, 60000), "the baseline didn't load");
await fc.cmd("save probe_at_load", /saved|Game saved/i, 20000);
await new Promise((r) => setTimeout(r, 1500));
const file = fs.readdirSync(dir).filter((f) => f.startsWith("probe_at_load")).map((f) => path.join(dir, f))[0];
check(file, "no save written");
await fc.quit();
if (file) {
  const raw = fs.readFileSync(file);
  const text = (file.endsWith(".zst") ? zlib.zstdDecompressSync(raw) : raw).toString();
  const rows = (k) => [...text.matchAll(new RegExp(`^${k}(\\d{4})="(.*)"`, "gm"))].map((m) => m[2]);
  const ter = rows("t"), own = rows("owner").map((r) => r.split(","));
  const water = new Set([" ", ":", "+"]);  // Ocean, Deep Ocean, Lake (terrain.ruleset identifiers)
  const land = (x, y) => ter[y]?.[x] != null && !water.has(ter[y][x]);
  // The landmasses (8-way), and the one with most towns is the realm's.
  const mass = new Map();
  let k = 0;
  for (let y = 0; y < ter.length; y++) for (let x = 0; x < ter[y].length; x++) {
    if (!land(x, y) || mass.has(`${x},${y}`)) continue;
    k++;
    const st = [[x, y]];
    mass.set(`${x},${y}`, k);
    while (st.length) {
      const [a, b] = st.pop();
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const n = `${a + dx},${b + dy}`;
        if (land(a + dx, b + dy) && !mass.has(n)) { mass.set(n, k); st.push([a + dx, b + dy]); }
      }
    }
  }
  const towns = [...text.matchAll(/^c=\{"y","x",/gm)].length;  // sanity: the save has towns
  check(towns > 0, "no towns in the save");
  const cityTiles = [...text.matchAll(/^(\d+),(\d+),(\d+),/gm)].map((m) => `${m[2]},${m[1]}`).filter((t) => mass.has(t));
  const count = new Map();
  for (const t of cityTiles) count.set(mass.get(t), (count.get(mass.get(t)) ?? 0) + 1);
  const main = [...count.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  const tiles = [...mass.entries()].filter(([, m]) => m === main).map(([t]) => t.split(",").map(Number));
  const open = tiles.filter(([x, y]) => (own[y]?.[x] ?? "-") === "-");
  console.log(`main continent: ${tiles.length} land tiles, ${open.length} unclaimed`);
  check(tiles.length > 500, "couldn't find the main continent");
  check(open.length === 0, `${open.length} of ${tiles.length} land tiles unclaimed at the first frame, e.g. ${open.slice(0, 5).map((t) => t.join(",")).join(" ")}`);
}
fs.rmSync(dir, { recursive: true, force: true });
done();
