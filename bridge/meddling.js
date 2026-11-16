// Orders given inside another house's lands (CK3's interference in a vassal's realm; Mac 2026-11-16: "shouldn't the
// liege lord be pissed with me for bypassing him?"). Grain or a building sent into a town the crown does not hold is
// meddling: in a lesser lord's town (court.vassals) the great house that holds it was passed over and takes it ill; in a
// great house's own town, help it never asked for warms it a little, not as a gift would. The one rule for every order
// (routes_decree.js) and the words that name it first (counsel.js priced). Numbers: data/meddling.json.

import fs from "node:fs";
import { greatHouses } from "./realm.js";
import { houseFor } from "./narrator.js";

const M = JSON.parse(fs.readFileSync(new URL("./data/meddling.json", import.meta.url), "utf8"));

// The great house whose town it is, and the lesser lord who holds it for them, if any; null for the crown's own town.
function lands(ctx, cityId) {
  const town = ctx.world.cities.find((c) => c.id === Number(cityId));
  const owner = town && greatHouses(ctx.world).find((p) => p.id === town.owner);
  if (!owner) return null;
  return { owner, vassal: (ctx.court?.vassals?.(ctx.world) ?? []).find((v) => v.town === town.id) ?? null };
}

// The order's favour as the house whose lands it reached takes it ({pid: delta}).
export function apply(ctx, action, cityId, favour) {
  if (!M.actions.includes(action) || cityId == null) return favour;
  const l = lands(ctx, cityId);
  if (!l) return favour;
  const out = { ...(favour ?? {}) };
  const d = Number(out[l.owner.id] ?? 0);
  out[l.owner.id] = l.vassal ? M.liege : Math.round(d * M.keep);
  if (!out[l.owner.id]) delete out[l.owner.id];
  return out;
}

// What the order's label says of it: "over Thornvale's head" in a lesser lord's town, else "".
export function word(ctx, action, cityId) {
  const l = M.actions.includes(action) && cityId != null ? lands(ctx, cityId) : null;
  return l?.vassal ? M.word.replace("{liege}", houseFor(l.owner).name.replace(/^House /, "")) : "";
}
