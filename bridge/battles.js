// A fight Freeciv has settled, as the realm tells it (the one owner of who fought, how many, and who won).
// Freeciv reports each company killed (realmrules/script.lua unit_killed); the companies of the beaten house on and
// beside that tile were the beaten side, and the nearest other house with men beside it the victors. Many
// companies killed on one tile in one season are one battle: their scene is kept and its fallen counted up.
// The view stages it (scenes.gd: a field battle sized from these men, ending as Freeciv decided).
import { HOSTS, menOf, homeward } from "./hosts.js";
import { CIVILIAN } from "./campaigns.js";
import { houseName } from "./realm.js";
import { cityName } from "./narrator.js";
import { calendar } from "./calendar.js";
import * as Lua from "./lua.js";

const SHIPS = new Set(HOSTS.ships);
const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
const soldier = (u) => !CIVILIAN.has(u.type) && !SHIPS.has(u.type);

// The strikes Freeciv reported this season (realmrules/script.lua attack): who attacked which tile, from where.
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

// The King's battles as result cards (CK3's war panel: where and when, each side's men, losses and kinds, who won),
// for the view to draw when a fight the crown's men were in is over. One card per field a season (a kill within a
// tile of it, the same season, is the same battle), each company killed folded in, kept with the reign (meta.battles,
// the last hosts.json battles.keep). A card: {id, turn, date, x, y, place, sides: [{house, name, men, lost, kinds}]
// (the crown's first; men the most seen on the field, lost the men of its companies killed), victor (a house id: the
// side that lost the smaller share of its men), crown: "won" | "lost"}.
export function card(meta, world, f, turn, crownId) {
  if (crownId == null || (f.owner !== crownId && f.victor !== crownId)) return null;
  const cards = (meta.battles ??= []);
  let c = cards.find((b) => b.turn === turn && cheb(b, f) <= 1);
  if (!c) {
    const near = (world?.cities ?? []).map((t) => [t, cheb(t, f)]).filter(([, d]) => d <= 4).sort((a, b) => a[1] - b[1])[0];
    c = { id: `${turn}-${f.x}-${f.y}`, turn, date: calendar(turn).text, x: f.x, y: f.y,
      place: near ? (near[1] === 0 ? `at ${cityName(near[0].id)}` : `near ${cityName(near[0].id)}`) : "in the open field", sides: [] };
    meta.battles = [...cards, c].slice(-(HOSTS.battles?.keep ?? 12));
  }
  const side = (pid, kinds) => {
    let s = c.sides.find((x) => x.house === pid);
    if (!s) { s = { house: pid, name: houseName(world, pid, "Men without banners"), men: 0, lost: 0, kinds: [] }; c.sides.push(s); }
    s.men = Math.max(s.men, kinds.reduce((t, k) => t + menOf({ type: k }), 0));
    s.kinds = [...new Set([...s.kinds, ...kinds])];
    return s;
  };
  const beaten = side(f.owner, f.kinds[0]);
  beaten.lost += menOf({ type: f.unit });
  beaten.men = Math.max(beaten.men, beaten.lost);
  if (f.victor >= 0) side(f.victor, f.kinds[1]);
  c.sides.sort((a, b) => (b.house === crownId) - (a.house === crownId));
  const share = (s) => s.lost / Math.max(1, s.men);
  c.victor = [...c.sides].sort((a, b) => share(a) - share(b))[0].house;
  c.crown = c.victor === crownId ? "won" : "lost";
  return c;
}

// After a battle's season (season.js, before the captains): each side that lost it, the men who fled the field (those
// who were there and did not fall), and a beaten great house's lord's fate when it lost hosts.json battles.fate.minLost
// men or more (CK3's commanders slain or taken in battle): he escapes, is wounded, taken (ransomed to the victor from
// his house's chest) or slain (court.die, his heir succeeds), by the fate's weights. Set once on the card: sides[].fled,
// sides[].lord {name, fate, odds}; the chronicle line of his fate carries odds {escaped, wounded, taken, slain}, 0..1.
export function season(ctx, turn) {
  const { meta, world, court, send, record } = ctx;
  const F = HOSTS.battles?.fate;
  for (const c of (meta.battles ?? []).filter((b) => b.turn === turn - 1 && !b.settled)) {
    c.settled = true;
    for (const s of c.sides) {
      if (s.house === c.victor) continue;
      s.fled = Math.max(0, s.men - s.lost);
      panic(ctx, c, s, turn);
      if (!F || s.lost < F.minLost) continue;
      const lord = court?.lordOfHouse?.(s.house);
      if (!lord?.alive) continue;
      const total = Object.values(F.weights).reduce((t, w) => t + w, 0);
      const roll = Math.random() * total;
      let acc = 0;
      const fate = Object.entries(F.weights).find(([, w]) => (acc += w) > roll)?.[0] ?? "escaped";
      // The roll's odds go with the news (casebook, Dice that feel like cheating; Battle Brothers' shown odds).
      const odds = Object.fromEntries(Object.entries(F.weights).map(([k, w]) => [k, Math.round((w / total) * 100) / 100]));
      s.lord = { name: lord.name, fate, odds };
      const where = c.place ?? "in the field";
      if (fate === "slain") {
        record({ turn, kind: "battle", text: `${lord.name} of ${lord.house} is cut down ${where}, under his own banner.`, odds });
        court.die(lord, turn, world);
      } else if (fate === "taken") {
        const house = world?.players?.find((p) => p.id === s.house);
        const ransom = Math.max(0, Math.min(F.ransom, Math.floor(house?.gold ?? 0)));
        if (ransom > 0) send(`lua cmd ${Lua.pay(s.house, c.victor, ransom)}`);
        court.remember(lord.id, `I was taken ${where}, and my house paid ${ransom} gold to have me back.`);
        record({ turn, kind: "battle", text: `${lord.name} of ${lord.house} is taken ${where}${ransom ? `, and ransomed home for ${ransom} gold` : ""}.`, odds });
      } else if (fate === "wounded") {
        court.remember(lord.id, `I was wounded ${where}. I still feel it when it rains.`);
        record({ turn, kind: "battle", text: `${lord.name} of ${lord.house} is carried from the field ${where}, wounded.`, odds });
      }
      else record({ turn, kind: "battle", text: `${lord.name} of ${lord.house} escapes ${where}, and rides home with what is left of his host.`, odds });
      if (fate !== "slain") court.save?.(lord);
    }
  }
}

// Panic spreads (casebook, War: morale is contagious; Total War's routs that carry the line): a side that lost
// battles.panic.share of its men or more on a field, its other companies in the open within panic.radius break, each
// with panic.chance, and go home (hosts.js homeward: walked to their seat and disbanded into its work). Said once.
function panic(ctx, c, s, turn) {
  const P = HOSTS.battles?.panic;
  if (!P || s.lost / Math.max(1, s.men) < P.share) return;
  const towns = new Set((ctx.world?.cities ?? []).map((t) => `${t.x},${t.y}`));
  const near = (ctx.world?.units ?? []).filter((u) => u.owner === s.house && soldier(u) && cheb(u, c) <= P.radius && !towns.has(`${u.x},${u.y}`) && Math.random() < P.chance);
  if (!near.length) return;
  homeward(ctx, { owner: s.house, units: near.map((u) => u.id) }, ctx.send);
  s.routed = near.length;
  ctx.record({ turn, kind: "battle", text: `The rout ${c.place ?? "in the field"} spreads: ${near.length} more ${near.length === 1 ? "company" : "companies"} of ${s.name} throw down their banners and make for home.` });
}

// The battle cards for /world: the King's battles of the last hosts.json battles.recent seasons, the newest first.
export function cards(meta, turn) {
  return (meta?.battles ?? []).filter((b) => b.turn >= (turn ?? 0) - (HOSTS.battles?.recent ?? 2)).slice().reverse();
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
