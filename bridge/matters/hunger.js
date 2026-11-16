// Hunger in the realm: one matter for every town going hungry (Mac 2026-11-16: two cards of families leaving two
// starving towns, each with the same six buttons). The worst town is its place; the others are named and are its
// places too, so their news shows this one matter's answers. Starving comes first; a thin granary is a lesser matter.
import { Matter, MATTERS } from "./matter.js";
import { WORK_SEASONS } from "../treasury.js";

export class Hunger extends Matter {
  static kind = "hunger";
  find(ctx, s) {
    const { meta } = ctx;
    const fed = (c) => (meta.relieved?.[c.id] ?? -99) > s.turn - 4;  // fed by the King this year: not brought again while the grain lasts
    const starving = s.cities.filter((c) => c.famine && !fed(c)).sort((a, b) => (b.size ?? 0) - (a.size ?? 0));
    const lean = s.cities.filter((c) => !c.famine && c.granaryLow && (c.size ?? 0) >= 5 && s.lacks(c, "Granary") && !fed(c)).sort((a, b) => (b.size ?? 0) - (a.size ?? 0));
    const all = [...starving, ...lean];
    if (!all.length) return [];
    const worst = all[0];
    const others = all.slice(1, 4).map((c) => c.title);
    const now = starving.length > 0;
    return [{ urgency: now ? 80 : 40, lesser: !now, subject: worst.owner, city: worst.id, places: all.map((c) => c.id), starving: now,
      text: now ? `${worst.title} is starving` : `${worst.title}'s granary runs low`,
      why: (now ? "A hungry town shrinks, riots, and blames its King; its people take to the roads." : `${worst.title} eats what it grows and keeps nothing back. One bad harvest and it starves.`)
        + (others.length ? ` Hungry too: ${others.join(", ")}.` : "") }];
  }
  answers(ctx, s, m) {
    const town = s.cities.find((c) => c.id === m.city);
    // Grain now (crowns, and the house's rival or liege takes note), or a granary that carries it next time but not
    // this winter, or the tithe eased so every house keeps more and the crown less.
    return [{ label: "Send grain now", action: "relief", city: m.city },
      s.lacks(town, "Granary") ? { label: `Pay for a granary · ready in ${WORK_SEASONS} seasons`, action: "build", building: "granary", city: m.city } : null,
      ctx.meta.tithe > 0 ? { label: `Lower the tithe to ${Math.round(ctx.meta.tithe * 100) - 5}%`, ui: "tithe_down" } : null];
  }
  silence(ctx, s, m) {
    const owner = s.ownerOf(s.cities.find((c) => c.id === m.city));
    if (!owner || owner.house.crown) return { shift: {}, cost: MATTERS.leave.shrinks, text: `The King said nothing while ${m.text.replace(/ is starving| granary runs low/, "")} went hungry.` };
    return { shift: { [owner.id]: m.starving ? MATTERS.silence.starving : MATTERS.silence.granary }, text: `The King said nothing while ${s.cities.find((c) => c.id === m.city).title} went hungry. ${owner.house.name} counts its dead and remembers.` };
  }
}
