// What every matter reads of the realm, worked out once per reading (counsel.js): the great houses, their seats, the
// purse, and the small helpers every kind shares, so no kind counts a house's towns its own way.

import { BANDS } from "../favour.js";
import { DECREES, bannersReady } from "../crown.js";
import { yearsIn } from "../calendar.js";

export function scope(ctx, players, cities, threat) {
  const { world, meta, court, stakes, favourOf } = ctx;
  // A house's towns, counted from the towns themselves (/world carries a player's cities as a number, not a list).
  const townsOf = (pid) => cities.filter((c) => c.owner === pid).length;
  const great = players.filter((p) => !p.house.wild && !p.house.crown && townsOf(p.id) > 0);
  const seatOf = (pid) => cities.find((c) => c.owner === pid && c.capital) ?? cities.find((c) => c.owner === pid);
  const crown = players.find((p) => p.house.crown);
  const turn = world?.turn ?? 0;
  // A ward is had of a house once a reign, and holds it for its seasons (data/decrees.json ward).
  const wardTaken = (pid) => (meta.oncePerHouse?.ward ?? {})[pid] != null || (stakes?.s.wards?.[pid] ?? -1) > turn;
  const wardYears = Math.round(yearsIn(DECREES.ward.seasons ?? 12));
  // What the banners would bring today: a share of each loyal or willing house's companies.
  const bannerMen = !bannersReady(turn) ? 0 : great.reduce((n, p) => { const f = favourOf(p.id); const sh = f >= BANDS.loyal ? 0.25 : f >= BANDS.steady ? 0.125 : 0; return n + (sh ? Math.max(1, Math.round((p.units ?? 0) * sh)) : 0); }, 0) * 200;
  return {
    players, cities, threat, great, seatOf, townsOf, crown, turn, bannerMen,
    purse: crown?.gold ?? 0,
    crownSeat: cities.find((c) => c.owner === crown?.id && c.capital),
    short: (p) => (p?.house?.name ?? "").replace(/^House /, ""),
    ofHouse: (c) => great.find((p) => p.id === c.owner),
    ownerOf: (c) => players.find((p) => p.id === c?.owner),
    lacks: (c, b) => !(c.buildings ?? []).some((x) => String(x).startsWith(b)) && !meta.works?.[c.id],
    // A war or bond the King has stilled (his peace, or a royal match).
    stilled: (x, y) => { const a = court?.lordOfHouse(x), b = court?.lordOfHouse(y); return !!(a && b && court.truce(a.id, b.id)); },
    wardTaken,
    wardHurt: String(DECREES.ward.favour ?? -15).replace("-", "−"),
    wardFor: `they cannot rise for ${wardYears === 1 ? "a year" : `${["", "one", "two", "three", "four", "five", "six"][wardYears] ?? wardYears} years`}`,
  };
}
