// The common folk of each town as the walking crowd: the grown folk of its lasting households (households.js, the
// one owner of every commoner), each named, with a trade, a family that is really theirs and a little history,
// so a walking villager is somebody when you look closer and is still there next season. They don't act,
// petition or reach the chronicle. `i` is a grown person's place in their town's crowd (minds.js and the view know them by
// it): 0..n-1, closing up each season over the dead and departed; minds.js moves each mind with its person.

import * as Households from "./households.js";

const CROWD = { min: 14, max: 54 };  // the crowd draws the grown folk (age 14 and up), at most max of them

// What their family is, from their household: married (and to whom), widowed, living with their parents, single.
function family(p) {
  const kids = p.kids ? `${p.kids} ${p.kids === 1 ? "child" : "children"}` : "no children yet";
  const lost = p.dead ? `, and buried ${p.dead}` : "";
  if (p.spouseOf && !p.spouseOf.died && !p.spouseOf.gone) return `married to ${p.spouseOf.first}, ${kids}${lost}`;
  if (p.widowed != null) return `widowed${p.kids ? `, ${kids}` : ""}${lost}`;
  if (p.parents.length && p.age < 25) return `lives with ${p.woman ? "her" : "his"} parents`;
  return "unmarried";
}

// The folk of a town on its streets: as many grown folk as live there, up to the crowd's most, by their place.
export function townsfolk(city, turn) {
  return Households.folkOf(city, turn ?? 0).filter((p) => p.i != null && p.age >= CROWD.min).slice(0, CROWD.max).map((p) => ({
    i: p.i, id: p.id, name: `${p.first}${p.surname ? ` ${p.surname}` : ""}`, age: p.age, woman: p.woman, trade: p.trade ?? "farmer",
    nature: p.nature, family: family(p), past: p.past, wants: p.wants, life: p.life,
  }));
}
