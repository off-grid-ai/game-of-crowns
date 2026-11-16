// A town's own troubles, lesser matters raised in turn: plague, uproar, bare walls in a time of war.
import { Matter, MATTERS } from "./matter.js";
import { BANDS } from "../favour.js";

const said = (s, c, rest) => rest.replace("{town}", c.title ?? c.name).replace("{house}", s.ownerOf(c)?.house?.name ?? "");
const cools = (s, c, d, text) => { const o = s.ownerOf(c); return o && !o.house.crown ? { shift: { [o.id]: d }, text: said(s, c, text) } : { shift: {}, text: said(s, c, text) }; };

export class Plague extends Matter {
  static kind = "plague";
  static lesser = true;
  find(ctx, s) {
    const sick = s.cities.find((c) => c.plague && !c.famine);
    return sick ? [{ urgency: 55, subject: sick.owner, city: sick.id, text: `Plague in ${sick.title}`, why: "The death-carts go out at night. Clean water slows it; a sept tends the dying and keeps the people from blaming the crown." }] : [];
  }
  answers(ctx, s, m) {
    const c = s.cities.find((x) => x.id === m.city);
    return [s.lacks(c, "Aqueduct") ? { label: `Pay for an aqueduct in ${c.title}`, action: "build", building: "aqueduct", city: c.id } : null,
      s.lacks(c, "Temple") ? { label: `Pay for a sept in ${c.title}`, action: "build", building: "temple", city: c.id } : null,
      { label: "Send grain", action: "relief", city: c.id }];
  }
  silence(ctx, s, m) { return cools(s, s.cities.find((x) => x.id === m.city), MATTERS.silence.plague, "The King said nothing while plague emptied {town}. {house} buries its dead alone."); }
}

export class Unrest extends Matter {
  static kind = "unrest";
  static lesser = true;
  find(ctx, s) {
    const riot = s.cities.find((c) => c.disorder);
    return riot ? [{ urgency: 55, subject: riot.owner, city: riot.id, text: `${riot.title} is in uproar`, why: "The people have stopped working and started shouting. Bread quiets a crowd; a sept or a market gives it something to lose." }] : [];
  }
  answers(ctx, s, m) {
    const c = s.cities.find((x) => x.id === m.city);
    const h = s.ofHouse(c);
    return [{ label: "Send grain", action: "relief", city: c.id }, s.lacks(c, "Temple") ? { label: "Pay for a sept", action: "build", building: "temple", city: c.id } : null,
      s.lacks(c, "Marketplace") ? { label: "Pay for a market", action: "build", building: "market", city: c.id } : null, h ? { label: `A feast for ${s.short(h)}`, action: "feast", city: c.id } : null];
  }
  silence(ctx, s, m) { return cools(s, s.cities.find((x) => x.id === m.city), MATTERS.silence.unrest, "The King said nothing to the crowds of {town}. They shout louder."); }
}

export class Walls extends Matter {
  static kind = "walls";
  static lesser = true;
  find(ctx, s) {
    const fighting = s.great.filter((p) => (p.atWarWith ?? []).length);
    const bare = s.cities.filter((c) => fighting.some((p) => p.id === c.owner) && s.lacks(c, "City Walls") && (c.size ?? 0) >= 4).sort((a, b) => (b.size ?? 0) - (a.size ?? 0))[0];
    if (!bare) return [];
    const h = s.ofHouse(bare);
    return [{ urgency: 45, subject: bare.owner, city: bare.id, text: `${bare.title} has no walls, and war is near`, why: `${h ? h.house.name : "Its house"} is at war, and ${bare.title} would fall to the first host that reaches it. Walls paid by the crown are remembered.` }];
  }
  answers(ctx, s, m) {
    const c = s.cities.find((x) => x.id === m.city);
    const h = s.ofHouse(c);
    return [{ label: `Pay for walls at ${c.title}`, action: "build", building: "walls", city: c.id }, h && ctx.favourOf(h.id) >= BANDS.sworn ? { label: `Swear an alliance with ${s.short(h)}`, action: "alliance", city: c.id } : null];
  }
  silence(ctx, s, m) { return cools(s, s.cities.find((x) => x.id === m.city), MATTERS.silence.walls, "The King said nothing of {town}'s walls. {house} builds its own, and remembers who didn't."); }
}
