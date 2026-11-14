// The harvest, from the weather (weather.js owns the sky; this owns what it does to the granaries). A wet harvest
// rots in the fields: every town without a granary eats lean for data/harvest.json seasons (Freeciv's own Blight
// decree, script.lua: the land gives half its food), while a town with one is carried through (Banished's and
// Stronghold's granaries, the Hand's "one bad harvest and it starves"). Told once in the chronicle; kept as
// meta.harvest {turn, kind, lean: [town ids]} for /world and the court's poor-harvest plea (dilemmas.json).
import fs from "node:fs";
import * as Lua from "./lua.js";
import { wetHarvest } from "./weather.js";
import { cityName } from "./narrator.js";

const H = JSON.parse(fs.readFileSync(new URL("./data/harvest.json", import.meta.url), "utf8"));

// The season's harvest (season.js, as the season turns, after the weather is rolled): only an autumn brings one.
export function season(ctx, turn) {
  const { meta, world, send, record } = ctx;
  const w = meta.weather;
  if (!world?.cities || w?.season !== "autumn" || w.turn !== turn || meta.harvest?.turn === turn) return;
  if (!wetHarvest(w)) { meta.harvest = { turn, kind: "good", lean: [] }; return; }
  const lean = world.cities.filter((c) => !(c.buildings ?? []).includes(H.store));
  for (const c of lean) send(`lua cmd ${Lua.decree(c.id, "blight", H.seasons)}`);
  meta.harvest = { turn, kind: "poor", lean: lean.map((c) => c.id) };
  const names = lean.slice(0, 4).map((c) => cityName(c.id));
  const more = lean.length > 4 ? ` and ${lean.length - 4} more` : "";
  record({ turn, kind: "famine", text: lean.length
    ? `The harvest rots in the wet fields. Towns without a granary will eat lean this winter: ${names.join(", ")}${more}.`
    : "The harvest rots in the wet fields, but every town has a granary to carry it through." });
}

// For /world: this year's harvest while its lean seasons last, else null.
export function view(meta, turn) {
  const h = meta?.harvest;
  return h && turn - h.turn < Math.max(1, H.seasons) ? h : null;
}
