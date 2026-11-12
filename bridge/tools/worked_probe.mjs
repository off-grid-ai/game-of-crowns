// Guards the land facts /world carries for the view (Mac: "combine the engines with the visuals"; realm land_use.gd):
// which town works each tile (Freeciv's worked map) and how each tile is tilled (irrigation, farmland), read from the
// baseline realm's own save as the one /world writer reads it (savefile.extractDetail -> view.js). Every worked tile
// names a town of the save, every town works its own tile and more, and the irrigated tiles the save packs into its
// extras rows come out as "i". No Freeciv, no bridge. Exits 1 on a failure.
//   node tools/worked_probe.mjs        (from bridge/)
import fs from "node:fs";
import zlib from "node:zlib";
import { parseSecfile, extractDetail } from "../savefile.js";
import { checker } from "./fc_probe_lib.mjs";

const { check, done } = checker("WORKED");
const dir = new URL("../baseline/aldmere/saves/", import.meta.url);
const file = fs.readdirSync(dir).filter((f) => f.endsWith(".sav.zst")).sort().pop();
const save = parseSecfile(zlib.zstdDecompressSync(fs.readFileSync(new URL(file, dir))).toString());
const d = extractDetail(save);
d.worked ??= [];
d.tilled ??= [];
check(Array.isArray(d.worked) && d.worked.length === d.owners.length && d.worked.length > 0, `worked rows: ${d.worked?.length}, owners ${d.owners.length}`);
check(Array.isArray(d.tilled) && d.tilled.length === d.owners.length, `tilled rows: ${d.tilled?.length}`);
const ids = new Set(Object.keys(d.cities).map(Number));
const by = {};
d.worked.forEach((row, y) => row.split(",").forEach((v, x) => { if (v !== "-" && v !== "") (by[v] ??= []).push([x, y]); }));
const unknown = Object.keys(by).filter((v) => !ids.has(Number(v)));
check(unknown.length === 0, `worked tiles name towns the save hasn't: ${unknown}`);
check(Object.keys(by).length === ids.size, `${Object.keys(by).length} of ${ids.size} towns work land`);
for (let i = 0; save[`player${i}`]; i++) for (const c of save[`player${i}`].c || []) {
  check((by[c.id] ?? []).some(([x, y]) => x === c.x && y === c.y) && (by[c.id] ?? []).length > 1, `town ${c.name} doesn't work its own tile and more: ${JSON.stringify(by[c.id])}`);
}
const irrigated = d.tilled.reduce((n, r) => n + [...r].filter((ch) => ch === "i" || ch === "f").length, 0);
check(irrigated > 0, "no tile comes out irrigated, though the save has irrigation");
check(d.tilled.every((r, y) => r.length === d.worked[y].split(",").length - (d.worked[y].endsWith(",") ? 1 : 0)), "a tilled row is not as long as its map line");
const view = fs.readFileSync(new URL("../view.js", import.meta.url), "utf8");
check(/worked: d\?\.worked/.test(view) && /tilled: d\?\.tilled/.test(view), "/world (view.js) doesn't carry worked and tilled");
done();
