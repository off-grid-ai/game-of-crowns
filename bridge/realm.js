// Who's who in the realm, defined once (consolidation-plan B2). Every file asks
// these instead of filtering players its own way.
import fs from "node:fs";
import { houseFor } from "./narrator.js";

const GEO = JSON.parse(fs.readFileSync(new URL("./data/geography.json", import.meta.url), "utf8"));

// A great house: not wild, not the crown, and holds at least one town (the
// supervisor's ruling). Pass anyTown=false to count a house with no town but a
// host in the field (the houses' ladder does).
export function greatHouses(world, anyTown = true) {
  return (world?.players ?? []).filter((p) => !houseFor(p).wild && !houseFor(p).crown && (!anyTown || (world.cities ?? []).some((c) => c.owner === p.id)));
}

// A house's name by its player id, or the fallback when no player has it (a house since fallen, raiders).
export function houseName(world, pid, fallback = "A house") {
  const p = (world?.players ?? []).find((x) => x.id === Number(pid));
  return p ? houseFor(p).name : fallback;  // (houseFor names any player, even none, so the fallback is decided here)
}

// The North (data/geography.json): its towns, northernmost first; and the far North, where its seats stand.
export const northTowns = (world) => (world?.cities ?? []).filter((c) => c.y < GEO.north).sort((a, b) => a.y - b.y);
export const farNorthTowns = (world) => (world?.cities ?? []).filter((c) => c.y < GEO.farNorth);

// The crown's player, or undefined.
export function crownOf(world) {
  return (world?.players ?? []).find((p) => houseFor(p).crown);
}

// A house's seat: its capital, else its first town; undefined if it holds none.
export function seatOf(world, pid) {
  const towns = (world?.cities ?? []).filter((c) => c.owner === Number(pid));
  return towns.find((c) => c.capital) ?? towns[0];
}

// Where raiders fall on a house (casebook, Wealth draws the raid: the economy picks the threat): its richest town
// outside its seat, the one with the most people, then the most buildings; its seat only when it holds no other.
export function richestTown(world, pid) {
  const towns = (world?.cities ?? []).filter((c) => c.owner === Number(pid));
  const worth = (c) => Number(c.size ?? 0) * 100 + (c.buildings?.length ?? 0);
  return towns.filter((c) => !c.capital).sort((a, b) => worth(b) - worth(a))[0] ?? towns[0];
}

// The King's seat (Kingsmere): the crown's capital, else the town of that name.
export function kingsSeat(world) {
  const crown = crownOf(world);
  return (crown && seatOf(world, crown.id)) ?? (world?.cities ?? []).find((c) => c.title === "Kingsmere");
}
