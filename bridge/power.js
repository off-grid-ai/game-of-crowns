// A house's power in one figure, 0-100: its share of the best great house in men, land, people, crowns and grain,
// weighted (data/power.json; Mac 2026-11-16: "strength is composite based on money, people, army, resources, land").
// The one rule for it: the houses strip (view.js) and the ledger's Power column (routes_realm.js ledger) both ask here.

import fs from "node:fs";

export const POWER = JSON.parse(fs.readFileSync(new URL("./data/power.json", import.meta.url), "utf8"));

// A measure of power for these houses' measures (a ledger row's houses, or /world's): returns m -> 0-100.
export function powerOf(rows) {
  const best = {};
  for (const k of Object.keys(POWER.weights)) best[k] = Math.max(1, ...rows.map((m) => Number(m?.[k] ?? 0)));
  return (m) => (m ? Math.round(100 * Object.entries(POWER.weights).reduce((t, [k, w]) => t + w * Number(m[k] ?? 0) / best[k], 0)) : 0);
}
