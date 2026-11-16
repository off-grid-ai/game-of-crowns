// A house sliding toward rebellion: the coldest great house under the banners' line (35).
import { Matter, MATTERS } from "./matter.js";
import { BANDS } from "../favour.js";
import { cityName } from "../narrator.js";
import { matchFor } from "./choices.js";
import { stern } from "./stern.js";

export class Cold extends Matter {
  static kind = "cold";
  find(ctx, s) {
    const { favourOf, favourWhy } = ctx;
    const cold = s.great.filter((p) => favourOf(p.id) < BANDS.steady).sort((a, b) => favourOf(a.id) - favourOf(b.id))[0];
    if (!cold || !s.seatOf(cold.id)) return [];
    const f = favourOf(cold.id);
    // The Hand names what is cooling them most, from the house's ledger of causes, in words, never a number.
    const drain = (favourWhy[cold.id] ?? []).filter((r) => r.d < 0).sort((a, b) => a.d - b.d)[0];
    const depth = (d) => (d <= -15 ? "and it cuts deep" : d <= -8 ? "and they have not forgotten it" : "though it is a small thing");
    const cause = drain ? ` What cools them most: ${drain.why}, ${depth(drain.d)}.` : "";
    const angryNow = s.great.filter((p) => favourOf(p.id) < BANDS.cooling).length;
    const rule = f < BANDS.cooling
      ? `Under 25, their lord may raise his banners any season, likelier the colder he grows.${angryNow >= 2 ? "" : " One more house under 25 and a pretender will claim the throne."}`
      : "Under 25, a lord may raise his banners against you; two such houses and one claims the throne.";
    return [{ urgency: f < BANDS.cooling ? 100 : 70, subject: cold.id, city: s.seatOf(cold.id).id, drain, text: `${cold.house.name} grows cold to the crown: favour ${f}`, why: rule + cause }];
  }
  answers(ctx, s, m) {
    const { meta } = ctx;
    const cold = s.players.find((p) => p.id === m.subject);
    // A taken town is answered by giving it back, if the other house still holds it.
    const took = meta.taken?.[cold.id];
    const back = m.drain?.why === "a town granted or taken" && took && s.cities.some((c) => c.id === took.city && c.owner === took.to)
      ? { label: `Return ${cityName(took.city)} to them`, action: "grant", city: took.city, to: cold.id } : null;
    const lighter = m.drain?.why === "the royal tithe" && meta.tithe > 0 ? { label: `Lower the tithe to ${Math.round(meta.tithe * 100) - 5}%`, ui: "tithe_down" } : null;
    // A royal match binds the cold house to the most loyal one: both warm, and a long truce holds.
    const friend = s.great.filter((p) => p.id !== cold.id && !s.stilled(cold.id, p.id)).sort((a, b) => ctx.favourOf(b.id) - ctx.favourOf(a.id))[0];
    const match = friend && matchFor(ctx, cold.id, friend.id) ? { label: `Wed them to ${s.short(friend)}`, action: "marriage", city: s.seatOf(cold.id).id, to: friend.id } : null;
    // Win them back (their town returned, the tithe eased, a feast, a match) or teach them their place (stern.js).
    return [back, lighter, { label: "A feast in their honour", action: "feast", city: s.seatOf(cold.id).id }, match, ...stern(ctx, s, cold.id)];
  }
  silence(ctx, s, m) {
    const p = s.players.find((q) => q.id === m.subject);
    return { shift: { [m.subject]: MATTERS.silence.cold }, text: `The King said nothing to ${p.house.name}. They take it as an answer.` };
  }
}
