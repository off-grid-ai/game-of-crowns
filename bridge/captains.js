// The King's named men (casebook, War: Every soldier has a name; Battle Brothers' named men, small and mortal). Every
// company of the crown is led by a named captain and carries a few named soldiers (data/captains.json men), kept for
// the company's life in meta.captains {unit id: {name, seen, men: [{name, rank, fought}]}}. After each of the King's
// battles (battles.js cards) the named men of the companies at the field have fought once more: some fall, some rise
// to sergeant, and a new company is given the most-fought sergeant as its captain. When Freeciv kills a company
// (script.lua unit_killed, uid) its captain and men die with it: the chronicle says who, the battle's card names the
// captain (fell), and the reign remembers its fallen (meta.fallen). /world `captains` {id: name} and `soldiers`
// {id: [{name, rank, fought}]}.
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
const hash = (meta, a, b = 0) => Math.imul((Number(a) + b * 7919) ^ Number(meta.seed ?? 1066), 2654435761) >>> 0;

// A name from a seed and the reign's: none a living named man has.
function nameFor(meta, id, taken, salt = 0) {
  for (let k = 0; k < FIRST.length * 3; k++) {
    const h = hash(meta, id, k + salt * 101);
    const n = `${FIRST[h % FIRST.length]} ${SUR[(h >>> 11) % SUR.length]}`;
    if (!taken.has(n)) { taken.add(n); return n; }
  }
  return `${FIRST[Number(id) % FIRST.length]} ${SUR[Number(id) % SUR.length]}`;
}

const crownSoldiers = (world, crownId) => (world.units ?? []).filter((u) => u.owner === crownId && !CIVILIAN.has(u.type) && !SHIPS.has(u.type));

// The crown's companies' named men now: every living soldier of the crown has a captain and its men. A company no
// longer seen keeps them two seasons (Freeciv's kill can reach the bridge after the world is read again).
function companies(meta, world) {
  const crown = crownOf(world);
  if (!crown) return [];
  const turn = world.turn ?? 0;
  const mine = crownSoldiers(world, crown.id);
  const all = (meta.captains ??= {});
  for (const [id, c] of Object.entries(all)) if (c.seen < turn - 2) delete all[id];
  const taken = new Set(Object.values(all).flatMap((c) => [c.name, ...(c.men ?? []).map((m) => m.name)]));
  for (const u of mine) {
    let c = all[u.id];
    if (!c) {
      // A new company: the most-fought sergeant of the realm's companies is given it (he rises), else a new name.
      const sgt = Object.values(all).flatMap((x) => (x.men ?? []).map((m) => [x, m])).filter(([, m]) => m.rank === "sergeant").sort((a, b) => b[1].fought - a[1].fought)[0];
      if (sgt) sgt[0].men = sgt[0].men.filter((m) => m !== sgt[1]);
      c = all[u.id] = { name: sgt ? sgt[1].name : nameFor(meta, u.id, taken), men: [], risen: sgt ? turn : null };
    }
    c.men ??= [];
    for (let i = c.men.length; i < C.men; i++) c.men.push({ name: nameFor(meta, u.id, taken, i + 1 + (c.seq = (c.seq ?? 0) + 1)), rank: "soldier", fought: 0 });
    c.seen = turn;
  }
  return mine.map((u) => [u, all[u.id]]);
}

export function list(meta, world) {
  return Object.fromEntries(companies(meta, world).map(([u, c]) => [u.id, c.name]));
}

export function soldiers(meta, world) {
  return Object.fromEntries(companies(meta, world).map(([u, c]) => [u.id, c.men.map((m) => ({ name: m.name, rank: m.rank, fought: m.fought }))]));
}

// After the season's battles (season.js): the named men of the King's companies at each field have fought once more;
// some fall, some rise. One chronicle line for each that falls or rises.
export function season(ctx, turn) {
  const { meta, world, record } = ctx;
  const mine = companies(meta, world);
  // A sergeant given a new company (companies): said once.
  for (const [, c] of mine) if (c.risen != null && !c.told) {
    c.told = true;
    record({ turn, kind: "battle", text: `Sergeant ${c.name} is given a company of his own. Captain ${c.name} now.` });
  }
  const fields = (meta.battles ?? []).filter((b) => b.turn === turn - 1);
  if (!fields.length) return;
  for (const [u, c] of mine) {
    const b = fields.find((f) => cheb(f, u) <= 1);
    if (!b) continue;
    const where = b.place ?? "in the field";
    for (const m of [...c.men]) {
      m.fought++;
      if ((hash(meta, u.id, m.fought * 13 + m.name.length) % 1000) / 1000 < C.fall) {
        c.men = c.men.filter((x) => x !== m);
        meta.fallen = [...(meta.fallen ?? []), { name: m.name, rank: m.rank, turn, place: where }].slice(-C.keep);
        b.fell = [...new Set([...(b.fell ?? []), m.name])];  // named on the battle's card (battles.js)
        record({ turn, kind: "battle", text: `${m.rank === "sergeant" ? "Sergeant " : ""}${m.name} of Captain ${c.name}'s company falls ${where}.` });
      } else if (m.rank === "soldier" && m.fought >= C.rise.sergeant) {
        m.rank = "sergeant";
        record({ turn, kind: "battle", text: `${m.name}, who has stood in Captain ${c.name}'s line through ${m.fought} battles, is made sergeant.` });
      }
    }
  }
}

// A company of the crown killed (server.js, unit_killed): its captain and its men fall, told in the chronicle and on
// the card.
export function fell(ctx, ev, card) {
  const { meta, world, record } = ctx;
  const c = meta.captains?.[Number(ev.uid)];
  if (!c) return;
  delete meta.captains[Number(ev.uid)];
  const near = [...(world?.cities ?? [])].sort((a, b) => cheb(a, ev) - cheb(b, ev))[0];
  const place = near ? (cheb(near, ev) === 0 ? `at ${cityName(near.id)}` : `near ${cityName(near.id)}`) : "in the field";
  const turn = world?.turn ?? 0;
  meta.fallen = [...(meta.fallen ?? []), { name: c.name, rank: "captain", turn, place, unit: ev.unit }, ...(c.men ?? []).map((m) => ({ name: m.name, rank: m.rank, turn, place }))].slice(-C.keep);
  if (card) card.fell = [...new Set([...(card.fell ?? []), c.name])];
  const sgts = (c.men ?? []).filter((m) => m.rank === "sergeant").map((m) => m.name);
  record({ turn, kind: "battle", text: `Captain ${c.name} falls ${place}, and his company with him${sgts.length ? `, ${sgts.join(" and ")} among them` : ""}.`, city: near?.id });
}
