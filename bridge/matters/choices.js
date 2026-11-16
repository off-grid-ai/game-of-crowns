// The King's answers that more than one matter offers: his choices in a war between two great houses, and whether
// two houses have heirs to wed (matters cold, match, house_war; reign.js).
import { cityName } from "../narrator.js";
import { peaceScale } from "../crown.js";

// The King's answers to a war between two great houses, each with its own cost (Mac 2026-11-16: "it doesn't really
// feel like I'm making a tough decision"; CK3's arbitration, Reigns' two-sided card): judge it for either side (the
// loser gives up a town, free of crowns, and hates him), make them stop (crowns; the house that was winning resents
// being robbed of it), or wed them (if each has an heir to give; bound, they stand together, against him too).
export function warChoices(ctx, a, b, cities) {
  const { favourOf } = ctx;
  const power = (p) => (p.units ?? 0) + cities.filter((c) => c.owner === p.id).length * 2;
  const [strong, weak] = [a, b].sort((p, q) => power(q) - power(p));
  const seat = (pid) => cities.find((c) => c.owner === pid && c.capital) ?? cities.find((c) => c.owner === pid);
  const short = (p) => p.house.name.replace(/^House /, "");
  // The town a judgement takes: the loser's nearest to the winner's seat, never its own seat.
  const ceded = (loser, winner) => {
    const at = seat(winner.id);
    return at ? cities.filter((c) => c.owner === loser.id && !c.capital).sort((x, y) => Math.hypot(x.x - at.x, x.y - at.y) - Math.hypot(y.x - at.x, y.y - at.y))[0] : null;
  };
  const judge = (winner, loser) => {
    const t = ceded(loser, winner);
    return t ? { label: `Judge for ${short(winner)}: ${short(loser)} gives up ${cityName(t.id)}`, action: "back", city: t.id, to: winner.id } : null;
  };
  return [
    judge(strong, weak),
    judge(weak, strong),
    { label: "Make them stop", action: "peace", city: seat(a.id)?.id, to: b.id, scale: peaceScale(favourOf(a.id), favourOf(b.id)) },
    matchFor(ctx, a.id, b.id) ? { label: "Wed them to each other", action: "marriage", city: seat(a.id)?.id, to: b.id } : null,
  ].filter((x) => x && x.city != null);
}

export function matchFor(ctx, pa, pb) {
  const { court } = ctx;
  if (!court) return null;
  const [la, lb] = [pa, pb].map((pid) => court.lordOfHouse(pid));
  if (!la || !lb) return null;
  const unwed = (lord) => court.alive().filter((k) => k.parents?.includes(lord.id) && !k.spouse && k.age >= 15);
  for (const ka of unwed(la)) { const kb = unwed(lb).find((k) => k.gender !== ka.gender); if (kb) return [la, lb, ka, kb]; }
  return null;
}

