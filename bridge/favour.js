// What a house's favour toward the crown means, defined once (consolidation-plan
// B2). Every threshold the bridge (and, through /world, the view) uses is here.
export const BANDS = {
  loyal: 60,   // with the crown: full banners, answers the call gladly, a quarter of its men
  sworn: 50,   // trusts the crown enough to swear an oath
  steady: 35,  // keeps its oath and its counsel; a loyal house in the ladder
  cooling: 25, // under this it may rise against the King
};

// The band a favour falls in: "loyal", "sworn", "steady", "cooling" or "angry".
export function band(f) {
  const v = Number(f ?? 50);
  return v >= BANDS.loyal ? "loyal" : v >= BANDS.sworn ? "sworn" : v >= BANDS.steady ? "steady" : v >= BANDS.cooling ? "cooling" : "angry";
}

export const isLoyal = (f) => Number(f) >= BANDS.loyal;
export const isSteady = (f) => Number(f) >= BANDS.steady;
export const mayRiseAt = (f) => Number(f) < BANDS.cooling;
