// The King's captains (casebook, War: Every soldier has a name; Battle Brothers' named men): every company of the
// crown is led by a named captain, given once and kept for the company's life (meta.captains {unit id: {name, seen}}). When
// Freeciv kills one (script.lua unit_killed, uid) the chronicle says who fell and where, the battle's card names him
// (fell), and the reign remembers its fallen (meta.fallen, data/captains.json keep). /world `captains` {id: name}.
import fs from "node:fs";
import { CIVILIAN } from "./campaigns.js";
import { HOSTS } from "./hosts.js";
import { crownOf } from "./realm.js";
import { cityName } from "./narrator.js";

const C = JSON.parse(fs.readFileSync(new URL("./data/captains.json", import.meta.url), "utf8"));
const FIRST = JSON.parse(fs.readFileSync(new URL("./data/first-names.json", import.meta.url), "utf8")).male;
const SUR = JSON.parse(fs.readFileSync(new URL("./data/surnames.json", import.meta.url), "utf8")).bannermen;
const SHIPS = new Set(HOSTS.ships);
const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));

// A captain's name from the company's id and the reign's seed: no two living captains share one.
function nameFor(meta, id, taken) {
  for (let k = 0; k < FIRST.length * 3; k++) {
    const h = Math.imul((Number(id) + k * 7919) ^ Number(meta.seed ?? 1066), 2654435761) >>> 0;
    const n = `${FIRST[h % FIRST.length]} ${SUR[(h >>> 11) % SUR.length]}`;
    if (!taken.has(n)) return n;
  }
  return `${FIRST[Number(id) % FIRST.length]} ${SUR[Number(id) % SUR.length]}`;
}

// The crown's companies' captains now (for /world {id: name}): every living soldier of the crown has one. A company
// no longer seen keeps its captain two seasons (Freeciv's kill can reach the bridge after the world is read again).
export function list(meta, world) {
  const crown = crownOf(world);
  if (!crown) return {};
  const turn = world.turn ?? 0;
  const mine = (world.units ?? []).filter((u) => u.owner === crown.id && !CIVILIAN.has(u.type) && !SHIPS.has(u.type));
  const all = (meta.captains ??= {});
  for (const [id, c] of Object.entries(all)) if (c.seen < turn - 2) delete all[id];
  const taken = new Set(Object.values(all).map((c) => c.name));
  const out = {};
  for (const u of mine) {
    if (!all[u.id]) { all[u.id] = { name: nameFor(meta, u.id, taken) }; taken.add(all[u.id].name); }
    all[u.id].seen = turn;
    out[u.id] = all[u.id].name;
  }
  return out;
}

// A company of the crown killed (server.js, unit_killed): its captain falls, told in the chronicle and on the card.
export function fell(ctx, ev, card) {
  const { meta, world, record } = ctx;
  const name = meta.captains?.[Number(ev.uid)]?.name;
  if (!name) return;
  delete meta.captains[Number(ev.uid)];
  const near = [...(world?.cities ?? [])].sort((a, b) => cheb(a, ev) - cheb(b, ev))[0];
  const place = near ? (cheb(near, ev) === 0 ? `at ${cityName(near.id)}` : `near ${cityName(near.id)}`) : "in the field";
  meta.fallen = [...(meta.fallen ?? []), { name, turn: world?.turn ?? 0, place, unit: ev.unit }].slice(-C.keep);
  if (card) card.fell = [...new Set([...(card.fell ?? []), name])];
  record({ turn: world?.turn ?? 0, kind: "battle", text: `Captain ${name} falls ${place}, and his company with him.`, city: near?.id });
}
