// Guards "war: the armies march out" (READY.md line 3; casebook, War and sieges: "The march feeds the battle"):
// when a ruling or a story arc declares war, the attacker's host musters at its town nearest the prey (where
// realm_war_host raises it) and marches out toward the town it goes for (the view's muster scene, army.gd
// march_out). warMuster gives the scene's fields from that town to the prey; the court shows a ruling's musters (court.js rulingScene) and an arc's war raises
// one (arcs.js). No Freeciv, no bridge. Exits 1 on a failure.   node tools/war_muster_probe.mjs   (from bridge/)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { checker } from "./fc_probe_lib.mjs";

const BRIDGE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const { check, done } = checker("WAR MUSTER");
const read = (f) => fs.readFileSync(path.join(BRIDGE, f), "utf8");

const C = await import("../characters.js");
check(typeof C.warMuster === "function", "a war's muster has one maker (characters.js warMuster)");
if (typeof C.warMuster === "function") {
  const world = { cities: [{ id: 1, owner: 3, x: 10, y: 12, capital: false }, { id: 2, owner: 3, x: 20, y: 22, capital: true }, { id: 7, owner: 5, x: 30, y: 31 }] };
  const prey = world.cities[2];
  const m = C.warMuster(world, 3, prey);
  check(m && m.city === 2 && m.x === 20 && m.y === 22, `it musters at the attacker's town nearest the prey (${JSON.stringify(m)})`);
  check(m && m.tx === 30 && m.ty === 31 && m.owner === 3, "it marches toward the prey, in the attacker's colours (owner)");
  check(C.warMuster(world, 9, prey) === null && C.warMuster(world, 3, null) === null, "no muster for a house with no town or no prey");
}
check(/for \(const m of out\.musters \?\? \[\]\) scene\("muster", m\)/.test(read("court.js")), "a ruling that declares war shows its muster (court.js rulingScene)");
check(/ctx\.scene\("muster", muster\)/.test(read("arcs.js")) && /warMuster\(ctx\.world/.test(read("arcs.js")), "a story arc's war raises the muster (arcs.js)");
check(/\(out\.musters \?\?= \[\]\)\.push\(muster\)/.test(read("characters.js")), "a dilemma's war raises the muster (characters.js)");
done();
