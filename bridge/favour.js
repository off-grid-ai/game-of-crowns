import fs from "node:fs";
// What a house's favour toward the crown means, defined once (consolidation-plan
// B2). Every threshold the bridge (and, through /world, the view) uses is here.
// The numbers are data (data/favour.json: loyal, sworn, steady, cooling), read once here.
const _bands = JSON.parse(fs.readFileSync(new URL("./data/favour.json", import.meta.url), "utf8"));
export const BANDS = { loyal: _bands.loyal, sworn: _bands.sworn, steady: _bands.steady, cooling: _bands.cooling };
// Where a new reign's houses may start (no house begins under the floor; a resentful realm's is lower),
// and what an idle King costs (data/favour.json startFloor, startFloorResentful, idle).
export const START = { floor: _bands.startFloor ?? 35, resentful: _bands.startFloorResentful ?? 26 };
export const IDLE = { seasons: _bands.idle?.seasons ?? 3, cool: _bands.idle?.cool ?? 2 };
// How a cold house turns against the King (data/favour.json turning: seasons to its ultimatum, riseIn to its host).
export const TURN = _bands.turning;
// A grudge carried into the next reign (data/favour.json grudge.carry): how much colder its house starts.
// A rebel lord's own host (data/favour.json rebel): its size and its kinds.
export const REBEL = _bands.rebel;
export const GRUDGE = { carry: _bands.grudge?.carry ?? 12 };

// The band a favour falls in: "loyal", "sworn", "steady", "cooling" or "angry".
export function band(f) {
  const v = Number(f ?? 50);
  return v >= BANDS.loyal ? "loyal" : v >= BANDS.sworn ? "sworn" : v >= BANDS.steady ? "steady" : v >= BANDS.cooling ? "cooling" : "angry";
}

export const isLoyal = (f) => Number(f) >= BANDS.loyal;
export const isSteady = (f) => Number(f) >= BANDS.steady;
export const mayRiseAt = (f) => Number(f) < BANDS.cooling;
