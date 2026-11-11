// A fight Freeciv has settled, as the realm tells it (the one owner of who fought, how many, and who won).
// Freeciv reports each company killed (lua/events.lua unit_killed); the companies of the beaten house on and
// beside that tile were the beaten side, and the nearest other house with men beside it the victors. Many
// companies killed on one tile in one season are one battle: their scene is kept and its fallen counted up.
// The view stages it (scenes.gd: a field battle sized from these men, ending as Freeciv decided).
import { HOSTS } from "./hosts.js";
import { CIVILIAN } from "./campaigns.js";

const SHIPS = new Set(HOSTS.ships);
const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
const soldier = (u) => !CIVILIAN.has(u.type) && !SHIPS.has(u.type);

// The strikes Freeciv reported this season (lua/events.lua attack): who attacked which tile, from where.
let strikes = [];
export function struck(ev, turn) {
  strikes = strikes.filter((x) => x.turn >= turn - 1).slice(-60);
  strikes.push({ owner: Number(ev.owner), unit: ev.unit, x: Number(ev.x), y: Number(ev.y), ax: Number(ev.ax), ay: Number(ev.ay), turn });
}

// The battle's fields for a company killed at (x, y), owned by `owner`: {x, y, owner (the beaten), victor
// (-1 when no one is there), men: [the beaten's men, the victors' men], kinds: [the beaten's unit types, the
// victors'], fallen: companies killed}. world is the realm as last read (the fight's men still in it).
export function fields(world, ev) {
  const at = { x: Number(ev.x), y: Number(ev.y) };
  const owner = Number(ev.owner);
  const units = (world?.units ?? []).filter(soldier);
  // The victors: whoever struck this tile (the defenders died), or the defenders of the tile this company struck
  // (the attackers died); failing a strike, the nearest other house with men beside it.
  const hit = strikes.findLast((x) => x.x === at.x && x.y === at.y && x.owner !== owner);
  const failed = strikes.findLast((x) => x.ax === at.x && x.ay === at.y && x.owner === owner);
  let victor = hit ? hit.owner : -1;
  let near = Infinity;
  const defenders = failed ? units.filter((u) => u.x === failed.x && u.y === failed.y && u.owner !== owner) : [];
  if (victor < 0 && defenders.length) victor = defenders[0].owner;
  if (victor < 0) for (const u of units) {
    if (u.owner === owner) continue;
    const d = Math.hypot(u.x - at.x, u.y - at.y);
    if (d <= 1.5 && d < near) { near = d; victor = u.owner; }
  }
  const field = failed ? { x: failed.x, y: failed.y } : at;
  const side = (pid) => units.filter((u) => u.owner === pid && (cheb(u, at) <= 1 || cheb(u, field) <= 1));
  const beaten = side(owner);
  const won = victor >= 0 ? side(victor) : [];
  if (hit && !won.some((u) => u.type === hit.unit)) won.push({ type: hit.unit });
  // The killed company is counted even when the reading no longer holds it.
  const lost = Math.max(1, beaten.length);
  return {
    x: at.x, y: at.y, owner, victor, fallen: 1, unit: ev.unit,
    men: [lost * HOSTS.men, Math.max(won.length, victor >= 0 ? 1 : 0) * HOSTS.men],
    kinds: [beaten.length ? beaten.map((u) => u.type) : [ev.unit], won.map((u) => u.type)],
  };
}

// The battle already told this season on this tile, if there is one: it takes the new company's fall.
export function merge(scenes, f, turn) {
  const same = scenes.find((s) => s.kind === "battle" && s.x === f.x && s.y === f.y && s.turn === turn && s.owner === f.owner);
  if (!same) return false;
  same.fallen = (same.fallen ?? 1) + 1;
  same.men = [Math.max(same.men?.[0] ?? 0, f.men[0]), Math.max(same.men?.[1] ?? 0, f.men[1])];
  if (same.victor < 0) same.victor = f.victor;
  return true;
}
