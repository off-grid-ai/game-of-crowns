// Guards one world-query module (integration audit #4, READY.md line 15: DRY): who the crown is and what a house is
// called are asked of realm.js, never found again in place. Exits 1 on a breach.   node tools/world_query_probe.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { checker } from "./fc_probe_lib.mjs";
import { crownOf, houseName, northTowns, farNorthTowns } from "../realm.js";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const { check, done } = checker("WORLD QUERY");
for (const f of fs.readdirSync(BRIDGE).filter((x) => x.endsWith(".js") && x !== "realm.js")) {
  fs.readFileSync(path.join(BRIDGE, f), "utf8").split("\n").forEach((line, i) => {
    const code = line.replace(/\/\/.*$/, "");
    if (/\.find\(\((\w+)\) => houseFor\(\1\)\.crown\)/.test(code)) check(false, `${f}:${i + 1} finds the crown in place: ${line.trim().slice(0, 100)}`);
    if (/\.y\s*<\s*\d+|NORTH_Y/.test(code) && !/goal\.y|q\.y/.test(code)) check(false, `${f}:${i + 1} draws the North's border in place (data/geography.json, realm.js northTowns): ${line.trim().slice(0, 100)}`);
    if (/(const|function)\s+(crownOf|houseName)\b\s*(=\s*\(|\()/.test(code) && !/crownNow/.test(code)) check(false, `${f}:${i + 1} defines a world query again: ${line.trim().slice(0, 100)}`);
  });
}
const world = { players: [{ id: 0, nation: "Welsh" }, { id: 7, nation: "Norman" }] };
const geo = JSON.parse(fs.readFileSync(path.join(BRIDGE, "data/geography.json"), "utf8"));
const map = { cities: [{ id: 1, y: geo.farNorth - 1 }, { id: 2, y: geo.north - 1 }, { id: 3, y: geo.north + 5 }] };
check(northTowns(map).map((c) => c.id).join() === "1,2" && farNorthTowns(map).map((c) => c.id).join() === "1", "the North's towns aren't read from data/geography.json");
check(crownOf(world)?.id === 7 && houseName(world, 0) === "House Stormhold" && houseName(world, 9, "raiders") === "raiders", "realm.js answers wrong");
done();
