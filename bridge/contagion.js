// A plague that walks the roads (casebook, Sickness from how you built; Banished's and Frostpunk's sickness, CK3's
// epidemics with their choices). One owner, meta.contagion {towns: {id: {since, until, closed}}, burn}: where it is
// and which roads are shut. Each season (season.js) it may begin, it passes along the trade roads (trade.js routes)
// from every sick town whose roads are open, and towns recover. A sick town is plague in the realm's eyes (view.js
// townStates: households, minds and moods follow) and its fields half worked (Freeciv's Blight decree). The King
// answers with event cards (events.js: contagion.json cards, subject sick_town, effect contagion). /world `contagion`.
import fs from "node:fs";
import * as Lua from "./lua.js";
import * as Trade from "./trade.js";
import { cityName } from "./narrator.js";

export const CONTAGION = JSON.parse(fs.readFileSync(new URL("./data/contagion.json", import.meta.url), "utf8"));
const C = CONTAGION;
const state = (meta) => (meta.contagion ??= { towns: {}, burn: null });

// Whether a town is sick with it now; whether its roads are shut.
export const sick = (meta, id) => Boolean(meta?.contagion?.towns?.[id]);
export const closed = (meta, id) => Boolean(meta?.contagion?.towns?.[id]?.closed);
export const abroad = (meta) => Object.keys(meta?.contagion?.towns ?? {}).length;

function fall(ctx, c, turn, from) {
  const s = state(ctx.meta);
  if (s.towns[c.id]) return;
  s.towns[c.id] = { since: turn, until: turn + C.lasts, closed: false };
  ctx.send(`lua cmd ${Lua.decree(c.id, "blight", C.blight)}`);
  ctx.record({ turn, kind: "plague", text: from != null ? `The sickness comes to ${cityName(c.id)} with the carts from ${cityName(from)}.` : `A sickness breaks out in ${cityName(c.id)}. The death-carts go out at night.`, city: c.id });
}

export function season(ctx, turn) {
  const { meta, world } = ctx;
  if (!world?.cities?.length) return;
  const s = state(meta);
  // Burnt out, or run its course.
  for (const [id, t] of Object.entries(s.towns)) if ((s.burn != null && turn > s.burn) || turn >= t.until || !world.cities.some((c) => c.id === Number(id))) {
    delete s.towns[id];
    ctx.record({ turn, kind: "plague", text: `The sickness leaves ${cityName(Number(id))}. The living count the empty houses.`, city: Number(id) });
  }
  if (!Object.keys(s.towns).length) s.burn = null;
  // It begins: a town Freeciv made sick, or now and then the biggest town in summer.
  for (const c of world.cities) if (c.freecivPlague) fall(ctx, c, turn, null);
  if (!Object.keys(s.towns).length && Math.random() < C.start) {
    const big = [...world.cities].sort((a, b) => (b.size ?? 0) - (a.size ?? 0))[0];
    if (big) fall(ctx, big, turn, null);
  }
  // It walks the roads: from each sick town with its roads open, to the towns it trades with.
  const routes = Trade.list(world.cities, turn, (a, b) => (ctx.detail?.()?.players?.[a]?.atWarWith ?? []).includes(b));
  for (const [id, t] of Object.entries(s.towns)) {
    if (t.closed || t.since === turn) continue;
    for (const r of routes.filter((x) => x.from === Number(id) || x.to === Number(id))) {
      const other = world.cities.find((c) => c.id === (r.from === Number(id) ? r.to : r.from));
      if (other && !s.towns[other.id] && Math.random() < C.spread) fall(ctx, other, turn, Number(id));
    }
  }
}

// The King's answer on a card (events.js apply: effects contagion): close a town's roads, heal it, or burn them all.
export function act(meta, kind, city, turn) {
  const s = state(meta);
  const t = s.towns[city];
  if (kind === "close" && t) t.closed = true;
  if (kind === "heal" && t) t.until -= C.heal;
  if (kind === "burn") s.burn = turn;
}

// For /world: the sick towns, when each fell sick and whether its roads are shut.
export function view(meta) {
  return Object.entries(meta?.contagion?.towns ?? {}).map(([id, t]) => ({ town: Number(id), since: t.since, until: t.until, closed: t.closed }));
}
