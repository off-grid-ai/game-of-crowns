// Peace terms after a war between the crown and a great house (casebook, War: a war ends at the table; CK3's peace
// offers by war score, Total War's peace treaty). One owner, meta.crownWars {pid: {since, towns, crown, offered}}:
// when the crown went to war with the house (Freeciv's diplomacy, the one writer, read through detail()) and how many
// towns each side held then. A war that has run peace.after seasons brings the house's lord to court with terms
// (court.arcPetition, arc "peace"), which depend on who is winning (towns lost since it began): a house losing offers
// a town or gold; a house winning asks one; an even war, a white peace. Peace is an armistice in Freeciv. /world wars.
import fs from "node:fs";
import * as Lua from "./lua.js";
import { crownOf } from "./realm.js";
import { cityName, houseFor } from "./narrator.js";

const P = JSON.parse(fs.readFileSync(new URL("./data/peace.json", import.meta.url), "utf8"));
const signed = (d) => `${d > 0 ? "+" : "−"}${Math.abs(d)}`;
const townsOf = (world, pid) => (world.cities ?? []).filter((c) => c.owner === pid);
// The smallest town a side can give up: never its seat.
const smallest = (world, pid) => townsOf(world, pid).filter((c) => !c.capital).sort((a, b) => (a.size ?? 0) - (b.size ?? 0))[0] ?? null;

export function season(ctx, turn) {
  const { meta, world, court } = ctx;
  const crown = crownOf(world);
  if (!crown || !court?.arcPetition) return;
  const foes = new Set(ctx.detail?.()?.players?.[crown.id]?.atWarWith ?? []);
  const wars = (meta.crownWars ??= {});
  for (const k of Object.keys(wars)) if (!foes.has(Number(k))) delete wars[k];
  for (const pid of foes) {
    const house = world.players.find((p) => p.id === pid);
    if (!house || houseFor(house).wild || houseFor(house).crown || !townsOf(world, pid).length) continue;
    const w = (wars[pid] ??= { since: turn, towns: townsOf(world, pid).length, crown: townsOf(world, crown.id).length, offered: null });
    if (turn - w.since < P.after || (w.offered != null && turn - w.offered < P.every)) continue;
    const lord = court.lordOfHouse(pid);
    if (!lord) continue;
    w.offered = turn;
    offer(ctx, crown, house, lord, w, turn);
  }
}

function offer(ctx, crown, house, lord, w, turn) {
  const { world, court } = ctx;
  const name = houseFor(house).name;
  const theirLoss = w.towns - townsOf(world, house.id).length, ourLoss = w.crown - townsOf(world, crown.id).length;
  const score = theirLoss - ourLoss;  // > 0: the crown is winning
  const gold = Math.round(P.gold);
  const beat = `peace-${house.id}-${turn}`;
  const fight = { id: "fight", label: "Fight on", favour: { [house.id]: P.favour.fight }, hint: `the war goes on · ${name} ${signed(P.favour.fight)}`, result: `The King sends ${lord.name}'s herald home. The war goes on.` };
  let text, options;
  if (score > 0) {
    const t = smallest(world, house.id);
    const pay = Math.min(gold, Math.max(0, Math.floor(house.gold ?? 0)));
    text = `${lord.name}'s herald kneels. "${name} has lost ${theirLoss} ${theirLoss === 1 ? "town" : "towns"} to the royal host, Your Grace. My ${lord.gender === "female" ? "lady" : "lord"} asks for peace${t ? `, and will give up ${cityName(t.id)} for it` : ""}${pay > 0 ? `, or pay ${pay} in gold` : ""}."`;
    options = [
      ...(t ? [{ id: "town", label: `Peace, and ${cityName(t.id)} is the crown's`, favour: { [house.id]: P.favour.yieldTown }, hint: `${cityName(t.id)} to the crown · ${name} ${signed(P.favour.yieldTown)}`, result: `Peace is sealed. ${cityName(t.id)} opens its gates to the King's men.`, town: t.id }] : []),
      ...(pay > 0 ? [{ id: "gold", label: `Peace for ${pay} gold`, favour: { [house.id]: P.favour.yieldGold }, hint: `+${pay} gold · ${name} ${signed(P.favour.yieldGold)}`, result: `Peace is sealed, and ${name}'s gold comes to Kingsmere in carts.`, gold: pay }] : []),
      { id: "white", label: "Peace, nothing asked", favour: { [house.id]: P.favour.white }, hint: `${name} ${signed(P.favour.white)}: a generous King`, result: `The King asks nothing of ${name} but peace. ${lord.name} did not expect it.` },
      fight,
    ];
  } else if (score < 0) {
    const t = smallest(world, crown.id);
    text = `${lord.name}'s herald does not kneel. "The crown has lost ${-score} ${-score === 1 ? "town" : "towns"} to ${name}, Your Grace. My ${lord.gender === "female" ? "lady" : "lord"} will have peace${t ? ` for ${cityName(t.id)}` : ""}, or ${gold} in gold."`;
    options = [
      ...(t ? [{ id: "cede", label: `Give up ${cityName(t.id)}`, favour: { [house.id]: P.favour.cede, ...others(world, house.id, crown.id, P.favour.weak) }, hint: `${cityName(t.id)} to ${name} · ${name} ${signed(P.favour.cede)} · every other great house ${signed(P.favour.weak)}`, result: `Peace, and ${cityName(t.id)} is ${name}'s. The King's banner comes down over its gate.`, town: t.id }] : []),
      { id: "pay", label: `Pay ${gold} gold`, cost: gold, favour: { [house.id]: P.favour.paid, ...others(world, house.id, crown.id, P.favour.weak) }, hint: `${name} ${signed(P.favour.paid)} · every other great house ${signed(P.favour.weak)}`, result: `The crown pays for its peace. ${name} rides home richer.` },
      fight,
    ];
  } else {
    text = `${lord.name}'s herald comes under a white flag. "Neither side is winning this, Your Grace. My ${lord.gender === "female" ? "lady" : "lord"} offers peace as things stand."`;
    options = [{ id: "white", label: "Peace as things stand", favour: { [house.id]: P.favour.white }, hint: `${name} ${signed(P.favour.white)}`, result: `Peace between the crown and ${name}, and neither side the richer.` }, fight];
  }
  court.arcPetition({ arc: "peace", beat, thread: `terms from ${name}`, from: lord, text, options }, world);
  w.terms = { beat, options: Object.fromEntries(options.map((o) => [o.id, { town: o.town ?? null, gold: o.gold ?? 0, to: o.id === "cede" ? house.id : crown.id }])) };
}

const others = (world, pid, crownId, d) => Object.fromEntries((world.players ?? []).filter((p) => p.id !== pid && p.id !== crownId && !houseFor(p).wild && !houseFor(p).crown && townsOf(world, p.id).length).map((p) => [p.id, d]));

// The King's answer (server.js court.onArcRuling, arc "peace"): a town changes hands, gold is paid, and the war ends in
// an armistice (Freeciv's own, which turns to peace).
export function ruled(ctx, beat, option) {
  const { meta, world, send, record } = ctx;
  const pid = Number(String(beat).split("-")[1]);
  const w = meta.crownWars?.[pid];
  if (!w?.terms || w.terms.beat !== beat || option === "fight" || option === "ignored") return;
  const crown = crownOf(world);
  const o = w.terms.options[option];
  if (!crown || !o) return;
  if (o.town != null) send(`lua cmd ${Lua.transferCity(o.town, o.to)}`);
  if (o.gold > 0) send(`lua cmd ${Lua.pay(pid, crown.id, o.gold)}`);
  ctx.diplomacy?.([crown.id, pid, P.armistice, "Armistice"]);
  record({ turn: world?.turn ?? 0, kind: "court", text: `Peace between the crown and ${houseFor(world.players.find((p) => p.id === pid)).name}, sealed at Kingsmere.` });
  delete meta.crownWars[pid];
}

// For /world wars: the crown's wars with the great houses, since when and the towns each side has lost.
export function view(meta, world) {
  const crown = crownOf(world);
  return Object.entries(meta?.crownWars ?? {}).map(([pid, w]) => ({ a: crown?.id ?? null, b: Number(pid), since: w.since,
    towns_taken: Math.max(0, w.towns - townsOf(world ?? {}, Number(pid)).length), towns_lost: Math.max(0, w.crown - townsOf(world ?? {}, crown?.id).length) }));
}
