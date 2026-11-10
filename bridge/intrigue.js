// The houses' schemes as the map shows them (Mac: houses scheme on their own, and
// you see it): an envoy riding between seats, a pact sworn, a match being made.
// The court (characters.js) writes them as its lords act (scheme()); this reads
// them out for /world as `intrigue`, each from one seat to the other, with one
// line for the hover. Builder 2's view draws them (riders, seams, markers).
import { houseFor } from "./narrator.js";

export const INTRIGUE_SEASONS = 6;  // a scheme stays on the map this long after its last news

export function intrigueNow(ctx) {
  const { world, court } = ctx;
  if (!world?.cities || !court?.intrigue) return [];
  const turn = world.turn ?? 0;
  const seat = (pid) => world.cities.find((c) => c.owner === Number(pid) && c.capital) ?? world.cities.find((c) => c.owner === Number(pid));
  return court.intrigue
    .filter((s) => turn - (s.last ?? s.since) < INTRIGUE_SEASONS)
    .map((s) => {
      const a = seat(s.from), z = seat(s.to);
      if (!a || !z || a.id === z.id) return null;
      const matter = court.petitions?.find((p) => !p.answered && p.scheme === s.id)?.id ?? null;
      return { id: s.id, kind: s.kind, from: s.from, to: s.to, x: a.x, y: a.y, tx: z.x, ty: z.y, since: s.since, secret: !!s.secret, line: s.line, matter };
    })
    .filter(Boolean);
}

// "Varn's envoy rides to Thornvale" in the house names the realm uses.
export const houseName = (world, pid) => houseFor(world?.players?.find((p) => p.id === Number(pid)) ?? {}).name ?? "A house";
