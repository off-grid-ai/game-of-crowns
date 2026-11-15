// A Freeciv snapshot's /world (state/world.json) in the shape the bridge serves it (view.js worldView's players, cities,
// crownId, seatId), with what a town's kept file is keyed by (realm/scripts/town_store.gd path_of): each town's name
// and title (narrator.js cityName), its family (the bannerman seated there: view.js reads court.lordOfTown) and each
// house's house (narrator.js houseFor). One rule for the baseline (tools/baseline-world.mjs) and a saved chronicle
// (tools/chronicle-world.mjs), so the bake keys every town as play does.
import fs from "node:fs";
import path from "node:path";
import { houseFor, cityName, rememberNames } from "../narrator.js";
import { bannerSurname } from "../characters.js";

// `charactersDir`: the chronicle's (or baseline's) characters/*.json. `fill`: a new reign seats a bannerman in each
// town of a house that has no lord or bannerman there (characters.js populate); a running chronicle already has.
export function servedWorld(world, charactersDir, { fill = false } = {}) {
  rememberNames(world);
  const people = fs.readdirSync(charactersDir).filter((f) => f.endsWith(".json"))
    .map((f) => JSON.parse(fs.readFileSync(path.join(charactersDir, f), "utf8")));
  const alive = people.filter((x) => x.alive !== false);
  const family = new Map();
  for (const bm of alive.filter((x) => x.rank === "bannerman" && x.seat != null)) family.set(bm.seat, bm.surname ?? null);
  if (fill) {
    const seated = new Set(alive.filter((x) => (x.rank === "lord" || x.rank === "bannerman") && x.seat != null).map((x) => x.seat));
    for (const p of world.players) {
      if (houseFor(p).wild) continue;
      for (const c of world.cities.filter((t) => t.owner === p.id && !t.capital && !seated.has(t.id))) {
        family.set(c.id, bannerSurname(c.id));
        seated.add(c.id);
      }
    }
  }
  const familyAt = (c) => (fill && c.capital ? null : family.get(c.id) ?? null);
  const players = world.players.map((p) => ({ ...p, house: houseFor(p) }));
  const crown = players.find((p) => p.house.crown);
  const cities = world.cities.map((c) => ({ ...c, name: cityName(c.id), title: cityName(c.id), family: familyAt(c) }));
  const seat = cities.find((c) => c.owner === crown?.id && c.capital);
  return { ...world, players, cities, crownId: crown?.id ?? null, seatId: seat?.id ?? null };
}
