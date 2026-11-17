// Two great houses at war: join one side's war (the alliance path, Mac 2026-11-17: stand by a house in its wars and in
// time it swears to you; crown.js side, war.js declare), judge it for a side, make them stop, wed them, or let them bleed. A war the King has
// stilled (his peace, or a royal match) is no longer his worry, though the engine still counts them at war.
import { Matter, MATTERS } from "./matter.js";
import { warChoices } from "./choices.js";
import { warOn } from "../war.js";

export class HouseWar extends Matter {
  static kind = "house_war";
  find(ctx, s) {
    const war = s.great.find((p) => (p.atWarWith ?? []).some((o) => s.great.some((g) => g.id === o) && !s.stilled(p.id, o)));
    if (!war) return [];
    const foe = s.great.find((g) => war.atWarWith.includes(g.id) && !s.stilled(war.id, g.id));
    // The Hand never offers an order he knows will be refused: a house too cold to obey (under 40) is said.
    const cold = [war, foe].filter((p) => ctx.favourOf(p.id) < 40).sort((a, b) => ctx.favourOf(a.id) - ctx.favourOf(b.id))[0];
    return [{ urgency: 50, subject: war.id, other: foe.id, city: s.seatOf(war.id)?.id, places: [s.seatOf(war.id)?.id, s.seatOf(foe.id)?.id].filter((x) => x != null), cold,
      text: `${war.house.name} and ${foe.house.name} are at war` }];
  }
  answers(ctx, s, m) {
    const war = s.players.find((p) => p.id === m.subject), foe = s.players.find((p) => p.id === m.other);
    const rest = warChoices(ctx, war, foe, s.cities);
    const wed = rest.some((a) => a.action === "marriage");
    // Join a side: the King's war on the other house, beside this one; never on a house he is at war with or sworn to.
    const join = (a, b) => (warOn(ctx.meta, b.id) || ctx.sworn?.(b.id) || !s.seatOf(b.id) ? null : { label: `Join ${s.short(a)} against ${s.short(b)}`, action: "side", city: s.seatOf(b.id).id, to: a.id });
    const [warm, cold] = [war, foe].sort((a, b) => ctx.favourOf(b.id) - ctx.favourOf(a.id));
    const acts = [join(warm, cold), ...rest.filter((a) => a.action === "peace"), join(cold, warm), ...rest.filter((a) => a.action !== "peace")].filter(Boolean);
    m.why = `Every season of war burns fields and lowers the realm's peace. Judge it for one side and the other gives up a town and hates you; make them stop and the side that was winning resents it${m.cold ? `, and ${m.cold.house.name}, cold to the crown, makes the blood-price dearer` : ""}.${wed ? " Or bind the two by marriage, and they stand together after, against you too." : ""} Or join one side: war on the other, and the house you stand by may swear to you in time.`;
    return acts;
  }
  silence(ctx, s, m) {
    return { shift: { [m.subject]: MATTERS.silence.warLeft, [m.other]: MATTERS.silence.warLeft }, text: "The King said nothing of the war, and it burns on. Both houses note whose side the crown was on: neither." };
  }
}
