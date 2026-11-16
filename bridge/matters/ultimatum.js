// A house that has turned: its lord's ultimatum, before any banners are raised.
import { Matter, MATTERS } from "./matter.js";
import { calendar } from "../calendar.js";
import { stern } from "./stern.js";

export class Ultimatum extends Matter {
  static kind = "ultimatum";
  find(ctx, s) {
    const { meta, court, deeds, world } = ctx;
    const out = [];
    for (const p of s.great) {
      const t = meta.turning?.[p.id];
      if (t?.state !== "sent" || !s.seatOf(p.id)) continue;
      const lord = court?.lordOfHouse(p.id);
      const short = s.short(p);
      // The grievance is something the King did, by name and season; without one, the plain truth.
      const worst = (deeds[p.id] ?? []).filter((x) => x.d <= -8).sort((a, b) => a.d - b.d)[0];
      const when = worst ? calendar(worst.turn) : null;
      const now = world?.turn ?? 0;
      const since = Math.max(1, now - (meta.crownedAt ?? meta.ambitionsFrom?.turn ?? now));
      const other = Object.entries(deeds ?? {}).filter(([pid, xs]) => Number(pid) !== p.id && Array.isArray(xs)).flatMap(([pid, xs]) => (xs ?? []).filter((x) => x.d >= 8 && (x.last ?? x.turn) >= now - 4).map((x) => ({ ...x, pid: Number(pid) }))).sort((a, b) => b.turn - a.turn)[0];
      const favoured = other ? s.players.find((q) => q.id === other.pid) : null;
      const grievance = worst ? `You ${worst.what}, in the ${when.season} of ${when.year}. Set that right`
        : favoured ? `You honoured ${favoured.house.name} and passed ${short} over. Set that right`
        : `You have done nothing for us in ${since === 1 ? "a season" : `${since} seasons`}. Set that right`;
      out.push({ urgency: 100, kind: "ultimatum", covers: true, subject: p.id, city: s.seatOf(p.id).id, occur: t.at, text: `${p.house.name} sends the crown an ultimatum`,
        why: `${lord ? lord.name : `The lord of ${short}`}: "${grievance}, or ${short} raises its banners." Answer with a favour they can see; silence is a refusal.` });
    }
    return out;
  }
  answers(ctx, s, m) {
    const seat = s.seatOf(m.subject);
    return [{ label: "A feast in their honour", action: "feast", city: seat.id }, ...stern(ctx, s, m.subject)];
  }
  silence(ctx, s, m) {
    const p = s.players.find((q) => q.id === m.subject);
    return { shift: { [m.subject]: MATTERS.silence.ultimatum }, text: `The King said nothing to ${p.house.name}'s ultimatum. Silence is a refusal.` };
  }
}
