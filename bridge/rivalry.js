// Favour given makes rivals (docs/TENSION.md, rule 2 "someone loses"; CK3's jealous rivals; Mac 2026-11-16: "I can take
// any action and it doesn't feel like it's that impactful"). An order that warms a great house cools its rival by a share
// of it: the house it is at war with (Freeciv's diplomacy, read through detail()), else its nearest neighbour, seat to
// seat. The one rule for every order (routes_decree.js) and the words that name it on the order before it is given
// (counsel.js priced). Numbers: data/rivalry.json.

import fs from "node:fs";
import { greatHouses } from "./realm.js";
import { houseFor } from "./narrator.js";

const R = JSON.parse(fs.readFileSync(new URL("./data/rivalry.json", import.meta.url), "utf8"));
const seat = (world, pid) => world.cities.find((c) => c.owner === pid && c.capital) ?? world.cities.find((c) => c.owner === pid);

// A great house's rival, or null.
export function rivalOf(ctx, pid) {
  const { world } = ctx;
  const others = greatHouses(world).filter((p) => p.id !== pid);
  const foes = ctx.detail?.()?.players?.[pid]?.atWarWith ?? [];
  const foe = others.find((p) => foes.includes(p.id));
  if (foe) return foe;
  const at = seat(world, pid);
  if (!at) return null;
  const far = (p) => { const s = seat(world, p.id); return s ? Math.hypot(s.x - at.x, s.y - at.y) : Infinity; };
  return others.sort((a, b) => far(a) - far(b))[0] ?? null;
}

// The order's favour with each warmed house's rival cooled ({pid: delta}); a house warmed and cooled at once keeps both.
export function jealous(ctx, favour) {
  const out = { ...(favour ?? {}) };
  const great = new Set(greatHouses(ctx.world).map((p) => p.id));
  for (const [pid, d] of Object.entries(favour ?? {})) {
    if (d < R.min || !great.has(Number(pid))) continue;
    const r = rivalOf(ctx, Number(pid));
    if (r && !(Number(favour[r.id] ?? 0) > 0)) out[r.id] = (out[r.id] ?? 0) - Math.max(1, Math.round(d * R.share));
  }
  return out;
}

// What an order's label says of it: "Thornvale jealous", or "" when it warms no great house with a rival.
export function word(ctx, pid) {
  const r = pid != null ? rivalOf(ctx, pid) : null;
  return r ? R.word.replace("{rival}", houseFor(r).name.replace(/^House /, "")) : "";
}
