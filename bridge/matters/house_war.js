// Two great houses at war: judge it for a side, make them stop, wed them, or let them bleed. A war the King has
// stilled (his peace, or a royal match) is no longer his worry, though the engine still counts them at war.
import { Matter, MATTERS } from "./matter.js";
import { warChoices } from "./choices.js";

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
    const acts = warChoices(ctx, war, foe, s.cities);
    const wed = acts.some((a) => a.action === "marriage");
    m.why = `Every season of war burns fields and lowers the realm's peace. Judge it for one side and the other gives up a town and hates you; make them stop and the side that was winning resents it${m.cold ? `, and ${m.cold.house.name}, cold to the crown, makes the blood-price dearer` : ""}.${wed ? " Or bind the two by marriage, and they stand together after, against you too." : ""}`;
    return acts;
  }
  silence(ctx, s, m) {
    return { shift: { [m.subject]: MATTERS.silence.warLeft, [m.other]: MATTERS.silence.warLeft }, text: "The King said nothing of the war, and it burns on. Both houses note whose side the crown was on: neither." };
  }
}
