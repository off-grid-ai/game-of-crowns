// A rival King beyond the realm (casebook, the reign's pressure from outside; CK3's neighbours, Total War's border
// probes). One owner, meta.rival {realm, king, edge, hostility 0..100, probes}: dealt once from the reign's seed
// (data/rivals.json). Each season (season.js) his hostility drifts toward its rest, and he may probe the border: his
// riders raid the realm's town nearest his edge (Freeciv's raiders, script.lua realm_raid). His envoys come as event
// cards drawn with the realm's (events.js: rivals.json cards, when.rival, the effect rival). /world `rival`.
import fs from "node:fs";
import * as Lua from "./lua.js";
import { cityName } from "./narrator.js";

export const RIVAL = JSON.parse(fs.readFileSync(new URL("./data/rivals.json", import.meta.url), "utf8"));
const R = RIVAL;

export function of(meta) {
  if (meta.rival) return meta.rival;
  const s = Number(meta.seed ?? 1066) >>> 0;
  const [realm, king] = R.kings[s % R.kings.length];
  return (meta.rival = { realm, king, edge: R.edges[(s >>> 3) % R.edges.length], hostility: R.start, probes: 0 });
}

// Whether a card's when.rival holds: his hostility above / below.
export function holds(meta, w) {
  const h = of(meta).hostility;
  return (w.above == null || h > w.above) && (w.below == null || h < w.below);
}

// A choice moves him (events.js apply: effects rival).
export function shift(meta, d) {
  const r = of(meta);
  r.hostility = Math.max(0, Math.min(100, r.hostility + Number(d)));
}

// The words a card may use: {foreign}, {foreignking}.
export const words = (meta) => ({ foreign: of(meta).realm, foreignking: of(meta).king });

// The realm's town nearest his edge (the border he probes).
function border(world, edge) {
  const towns = world.cities ?? [];
  const key = { north: (c) => c.y, south: (c) => -c.y, west: (c) => c.x, east: (c) => -c.x }[edge];
  return [...towns].sort((a, b) => key(a) - key(b))[0] ?? null;
}

// The season: hostility drifts, and he may probe the border with a raid.
export function season(ctx, turn) {
  const { meta, world, send, record } = ctx;
  if (!world?.cities?.length) return;
  const r = of(meta);
  r.hostility += Math.sign(R.rest - r.hostility) * Math.min(R.drift, Math.abs(R.rest - r.hostility));
  if (Math.random() >= R.raid * r.hostility / 100) return;
  const t = border(world, r.edge);
  if (!t) return;
  send(`lua cmd ${Lua.raid(t.id)}`);
  r.probes++;
  record({ turn, kind: "raid", text: `Riders out of ${r.realm} cross the border and fall on the fields of ${cityName(t.id)}. ${r.king} says they are outlaws; nobody believes it.`, city: t.id });
}

export function view(meta) {
  const r = meta?.rival;
  return r ? { realm: r.realm, king: r.king, edge: r.edge, hostility: Math.round(r.hostility), probes: r.probes } : null;
}
