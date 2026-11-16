// The pretender: the whispers of a better claim, the host on Kingsmere, and what becomes of the house that rose.
import { Matter, MATTERS } from "./matter.js";
import { BANDS } from "../favour.js";
import { stern } from "./stern.js";

const loyalShift = (ctx, s) => Object.fromEntries(s.great.filter((p) => ctx.favourOf(p.id) >= BANDS.steady).map((p) => [p.id, MATTERS.silence.loyalWonder]));

export class Usurper extends Matter {
  static kind = "usurper";
  find(ctx, s) {
    const { threat } = s;
    const pretender = s.players.find((p) => p.id === threat.pretender);
    const claimant = pretender ? pretender.house.name : "A pretender";
    if (threat.usurper === "rumour") {
      const left = Math.max(1, 8 - (threat.turn - threat.since));
      const angry = s.great.filter((p) => ctx.favourOf(p.id) < BANDS.cooling).map((p) => s.short(p));
      return [{ urgency: 95, covers: true, subject: pretender?.id ?? null, city: pretender ? s.seatOf(pretender.id)?.id : null, occur: threat.since, stage: "rumour", claimant, text: `${claimant} whispers of a better claim to the throne`,
        why: `In ${left} season${left === 1 ? "" : "s"} they march on Kingsmere, unless the angry houses are won back above 25: ${angry.join(", ") || "none now"}.` }];
    }
    if (threat.usurper !== "none") return [{ urgency: 100, kind: "march", covers: true, subject: pretender?.id ?? null, city: s.crownSeat?.id, occur: threat.since, stage: "march", claimant, text: `${claimant}'s host marches on Kingsmere`,
      why: `${(threat.theirs * 200).toLocaleString("en-US")} of their troops about the walls against ${(threat.ours * 200).toLocaleString("en-US")} of yours: ${threat.theirs > threat.ours ? "as things stand, the walls would fall" : "for now, the walls would hold"}. If Kingsmere falls, the crown is lost. Loyal houses (favour 35 and up) send men to the banners; the royal levy is yours to pay for. Or buy them off: gold for their claim.` }];
    return [];
  }
  answers(ctx, s, m) {
    if (m.stage === "rumour") {
      const seat = m.subject != null ? s.seatOf(m.subject) : null;
      return [seat ? { label: `A feast for ${m.claimant.replace(/^House /, "")}`, action: "feast", city: seat.id } : null, { label: "Buy off their claim", action: "buyoff" }, { label: "Call the banners", action: "banners" }, ...(m.subject != null ? stern(ctx, s, m.subject) : [])];
    }
    return [{ label: "Call the banners", action: "banners" }, { label: "Raise the royal levy", action: "levy" }, { label: "Buy them off", action: "buyoff" }];
  }
  silence(ctx, s, m) {
    return { shift: loyalShift(ctx, s), text: `The King said nothing while ${m.text.charAt(0).toLowerCase() + m.text.slice(1)}. The loyal houses wonder whether he still rules.` };
  }
}

// After a march: the King decides what becomes of the house that rose.
export class Rose extends Matter {
  static kind = "rose";
  find(ctx, s) {
    const rose = s.players.find((p) => p.id === s.threat.ended);
    if (!rose) return [];
    const loyal = s.great.filter((p) => p.id !== rose.id).sort((a, b) => ctx.favourOf(b.id) - ctx.favourOf(a.id))[0];
    return [{ urgency: 90, covers: true, subject: rose.id, city: s.seatOf(rose.id)?.id, occur: s.threat.since, text: `The march is over. What of House ${s.short(rose)}?`,
      why: `They rose against the throne and went home (favour ${Math.round(ctx.favourOf(rose.id))}). Pardon them with a feast to win them back, hold their heir at court so they cannot rise, or take a town and give it to ${loyal ? loyal.house.name : "a loyal house"} so the realm sees the price of treason; a house driven below 25 may rise again.` }];
  }
  answers(ctx, s, m) {
    const rose = s.players.find((p) => p.id === m.subject);
    const name = s.short(rose);
    const towns = s.cities.filter((c) => c.owner === rose.id && !c.capital).sort((a, b) => (a.size ?? 0) - (b.size ?? 0));
    const loyal = s.great.filter((p) => p.id !== rose.id).sort((a, b) => ctx.favourOf(b.id) - ctx.favourOf(a.id))[0];
    const seat = s.seatOf(rose.id);
    return [seat ? { label: "Pardon them with a feast", action: "feast", city: seat.id } : null,
      seat && !s.wardTaken(rose.id) ? { label: `Take their heir as your ward (${name} ${s.wardHurt}; ${s.wardFor})`, action: "ward", city: seat.id } : null,
      towns[0] && loyal ? { label: `Give ${towns[0].title ?? "a town"} to ${s.short(loyal)} (${name} −30, ${s.short(loyal)} +20)`, action: "grant", city: towns[0].id, to: loyal.id } : null];
  }
  silence(ctx, s, m) {
    return { shift: loyalShift(ctx, s), text: "The King said nothing of the house that rose. The loyal houses wonder whether treason is free." };
  }
}
