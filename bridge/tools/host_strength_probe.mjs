// A host's strength is an engine fact (Mac's realm map: every far standard read "200", one company's flat count).
// hosts.js menOf: a company's men are its Freeciv unit type's (data/hosts.json menOf, `men` for any other) times
// its health (hp over hpFull); a host's men are its companies' summed, and /world's units carry each company's men
// (view.js) so the view's houses' hosts sum the same numbers. No Freeciv, no bridge.
//   node tools/host_strength_probe.mjs        (from bridge/)
import fs from "node:fs";
import { checker } from "./fc_probe_lib.mjs";
import * as Hosts from "../hosts.js";

const { check, done } = checker("HOST STRENGTH");
check(typeof Hosts.menOf === "function", "hosts.js has no menOf (a company's men by its type and health)");
if (typeof Hosts.menOf === "function") {
  const pike = Hosts.menOf({ type: "Pikemen", hp: Hosts.HOSTS.hpFull ?? 10 });
  const hurt = Hosts.menOf({ type: "Pikemen", hp: (Hosts.HOSTS.hpFull ?? 10) / 2 });
  const knight = Hosts.menOf({ type: "Knights", hp: Hosts.HOSTS.hpFull ?? 10 });
  check(pike > 0 && Math.abs(hurt - pike / 2) <= 1, `a company at half health counts half its men (${pike}, ${hurt})`);
  check(pike !== knight, `two kinds of company count differently (Pikemen ${pike}, Knights ${knight})`);
  const world = { players: [{ id: 7, nation: "Norman" }], cities: [],
    units: [{ id: 1, owner: 7, type: "Pikemen", x: 0, y: 0, hp: 10 }, { id: 2, owner: 7, type: "Knights", x: 0, y: 0, hp: 10 },
      { id: 3, owner: 7, type: "Archers", x: 30, y: 30, hp: 4 }] };
  let hosts = [];
  try { hosts = Hosts.list({ world, meta: {} }); } catch (e) { check(false, `hosts.list threw: ${e.message}`); }
  const big = hosts.find((h) => h.units.includes(1)), small = hosts.find((h) => h.units.includes(3));
  check(big && big.men === Hosts.menOf(world.units[0]) + Hosts.menOf(world.units[1]), `a host's men are its companies' summed (${big?.men})`);
  check(big && small && big.men !== small.men, `two hosts of different size show different numbers (${big?.men}, ${small?.men})`);
}
const view = fs.readFileSync(new URL("../view.js", import.meta.url), "utf8");
check(/menOf\(/.test(view), "view.js doesn't give /world's units their men (Hosts.menOf)");
done();
