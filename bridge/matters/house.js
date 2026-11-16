// A house's own occasions, lesser matters raised in turn: loyalty unrewarded, an heir of age to wed.
import { Matter, MATTERS } from "./matter.js";
import { matchFor } from "./choices.js";

export class Loyal extends Matter {
  static kind = "loyal";
  static lesser = true;
  find(ctx, s) {
    const loyal = s.great.filter((p) => ctx.favourOf(p.id) >= 75 && s.seatOf(p.id)).sort((a, b) => ctx.favourOf(b.id) - ctx.favourOf(a.id))[0];
    return loyal ? [{ urgency: 30, subject: loyal.id, city: s.seatOf(loyal.id).id, text: `${loyal.house.name} has served you well`, why: `Favour ${Math.round(ctx.favourOf(loyal.id))}: they answer every summons. Loyalty left unrewarded cools, and the other houses watch what it earns.` }] : [];
  }
  answers(ctx, s, m) {
    const p = s.players.find((q) => q.id === m.subject);
    const seat = s.seatOf(p.id);
    return [{ label: `Swear an alliance with ${s.short(p)}`, action: "alliance", city: seat.id },
      s.lacks(seat, "Marketplace") ? { label: `Pay for a market at ${seat.title}`, action: "build", building: "market", city: seat.id } : null];
  }
  silence(ctx, s, m) { const p = s.players.find((q) => q.id === m.subject); return { shift: { [p.id]: MATTERS.silence.loyal }, text: `The King said nothing to ${p.house.name}'s loyalty. Unrewarded, it cools.` }; }
}

export class Match extends Matter {
  static kind = "match";
  static lesser = true;
  find(ctx, s) {
    const { court } = ctx;
    if (!court) return [];
    for (const h of [...s.great].sort(() => 0.5 - ((s.turn * 7 + s.great.length) % 10) / 10)) {
      const lord = court.lordOfHouse(h.id);
      const heir = lord && court.alive().find((k) => k.parents?.includes(lord.id) && !k.spouse && k.age >= 16);
      const match = heir && s.great.filter((g) => g.id !== h.id && s.seatOf(g.id)).map((g) => [g, court.lordOfHouse(g.id)]).find(([, l]) => l && court.alive().some((k) => k.parents?.includes(l.id) && !k.spouse && k.age >= 16 && k.gender !== heir.gender));
      if (heir && match && s.seatOf(h.id)) return [{ urgency: 35, subject: h.id, other: match[0].id, city: s.seatOf(h.id).id, text: `${heir.name} of ${h.house.name} is of age to wed`, why: `A royal match with ${match[0].house.name} would bind both houses to the crown and to each other: no war between them while it holds.` }];
    }
    return [];
  }
  answers(ctx, s, m) {
    const other = s.players.find((p) => p.id === m.other);
    return [matchFor(ctx, m.subject, m.other) ? { label: `Wed them to ${s.short(other)}`, action: "marriage", city: m.city, to: m.other } : null, { label: "A feast for the betrothal talk", action: "feast", city: m.city }];
  }
  silence(ctx, s, m) { const p = s.players.find((q) => q.id === m.subject); return { shift: { [p.id]: MATTERS.silence.match }, text: `The King said nothing of ${p.house.name}'s heir. Another house will make the match instead.` }; }
}
