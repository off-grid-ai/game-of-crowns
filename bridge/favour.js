import fs from "node:fs";
// What a house's favour toward the crown means, defined once (consolidation-plan
// B2). Every threshold the bridge (and, through /world, the view) uses is here.
// The numbers are data (data/favour.json: loyal, sworn, steady, cooling), read once here.
const _bands = JSON.parse(fs.readFileSync(new URL("./data/favour.json", import.meta.url), "utf8"));
export const BANDS = { loyal: _bands.loyal, sworn: _bands.sworn, steady: _bands.steady, cooling: _bands.cooling };

// The band a favour falls in: "loyal", "sworn", "steady", "cooling" or "angry".
export function band(f) {
  const v = Number(f ?? 50);
  return v >= BANDS.loyal ? "loyal" : v >= BANDS.sworn ? "sworn" : v >= BANDS.steady ? "steady" : v >= BANDS.cooling ? "cooling" : "angry";
}

export const isLoyal = (f) => Number(f) >= BANDS.loyal;
export const isSteady = (f) => Number(f) >= BANDS.steady;
export const mayRiseAt = (f) => Number(f) < BANDS.cooling;
