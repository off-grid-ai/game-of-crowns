// Guards READY.md line 6, "They lay siege" (casebook, War and sieges: "A siege is a season", Total War: Attila): the
// siege on screen is Freeciv's siege. Freeciv fights each assault (realmrules/script.lua realm_assault, which reports
// an "assault" EVENT: the men at the walls, the blows Freeciv let land, the town's owner after); the bridge turns that
// report into a "storm" scene (campaigns.js stormScene: who stormed, who held, taken or thrown back), and the view
// storms the siege it already shows only on that scene, ending it the way Freeciv did (taken: the holders give way,
// the besiegers pour in; held: the gap is held and the waves fall back). No switch storms a siege, and every siege
// pitches its camp and engines (the engines are the bridge's: Freeciv's catapults and trebuchets at the walls).
// No Freeciv needed. Exits 1 on a failure.
//   node tools/storm_probe.mjs        (from bridge/)
import fs from "node:fs";
import { checker } from "./fc_probe_lib.mjs";

const { check, done } = checker("STORM");
const read = (p) => fs.readFileSync(new URL(p, import.meta.url), "utf8");

// The bridge: Freeciv's assault report to a storm scene.
const camp = await import("../campaigns.js");
check(typeof camp.stormScene === "function", "campaigns.js has no stormScene (Freeciv's assault never reaches the view)");
if (typeof camp.stormScene === "function") {
  const world = { turn: 9, cities: [{ id: 4, x: 10, y: 12, owner: 2, size: 5 }], players: [{ id: 0, name: "Crown" }, { id: 2, name: "Foe" }] };
  const held = camp.stormScene(world, { kind: "assault", city: "4", men: "5", blows: "3", owner: "2" }, 0);
  check(held && held.city === 4 && held.x === 10 && held.y === 12, "a storm scene doesn't stand at the town");
  check(held && held.owner === 0 && held.defender === 2, "a storm scene doesn't say who stormed and who held");
  check(held && held.taken === false && held.blows === 3 && held.men === 5, "an assault Freeciv threw back isn't a storm thrown back");
  const taken = camp.stormScene(world, { kind: "assault", city: "4", men: "5", blows: "5", owner: "0" }, 0);
  check(taken && taken.taken === true, "a town Freeciv gave the crown isn't a storm that took it");
  const razed = camp.stormScene(world, { kind: "assault", city: "4", men: "2", blows: "2", owner: "-1" }, 0);
  check(razed && razed.taken === true, "a town Freeciv razed isn't a storm that took it");
  check(camp.stormScene(world, { kind: "assault", city: "99", men: "1", blows: "0", owner: "2" }, 0) === null, "a storm scene for a town that isn't there");
}
const server = read("../server.js");
check(/ev\.kind === "assault"[^\n]*stormScene\(/.test(server) && /scene\("storm"/.test(server), "server.js doesn't turn Freeciv's assault EVENT into a storm scene");

// The view: storms on the scene, never on a switch; the camp always pitched.
// (scene_kinds.gd's "storm" row is played by scene_kinds/siege.gd since the scenes.gd split, integration audit #11.)
const kinds = read("../../realm/scripts/scene_kinds.gd");
const siegeKind = read("../../realm/scripts/scene_kinds/siege.gd");
check(/"storm":[^\n]*"play": "res:\/\/scripts\/scene_kinds\/siege\.gd"/.test(kinds) && /"storm"[\s\S]*storm\(city/.test(siegeKind) && /func storm\(/.test(siegeKind), "the view doesn't storm a siege on the bridge's storm scene (scene_kinds.gd storm row, scene_kinds/siege.gd storm)");
const assault = read("../../realm/scripts/army_assault.gd");
check(/func storm\(taken: bool\)/.test(assault), "army_assault.gd has no storm(taken) to end the storm Freeciv's way");
check(!/"--storm=on"|"--storm=off"|assault\.storm"/.test(assault), "army_assault.gd still storms on a switch (--storm, walls.json assault.storm)");
const field = read("../../realm/scripts/army_field.gd");
check(!/"--storm-host=on"|"--storm-host=off"|storm_host\.on"/.test(field), "army_field.gd's massed storm still waits on a switch (--storm-host, storm_host.on)");
const siegeCamp = read("../../realm/scripts/siege_camp.gd");
check(!/"--camp=on"|"--camp=off"/.test(siegeCamp) && !/SiegeCamp\.on\(\)/.test(read("../../realm/scripts/scenes.gd") + siegeKind), "a siege's camp and engines still wait on a switch (--camp, siege.json on)");
done();
