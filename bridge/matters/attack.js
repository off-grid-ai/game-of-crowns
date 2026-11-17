// A foe on one of the realm's towns (Mac: "defend yourself? or does it auto defend?"; CK3's liege defends his
// vassals): a host on the warpath to a town of the crown's, a siege of one, or raiders at a town the crown answers
// for (its own, or a house's not at war with it and not men without banners). The answers: send the nearest free
// host (the view picks it and orders it, news_actions.gd _defend), call the banners, raise the levy; or let it stand
// alone, and the town's house remembers.
import { Matter, MATTERS } from "./matter.js";
import * as Hosts from "../hosts.js";
import * as Raids from "../raids.js";

export class Attack extends Matter {
  static kind = "attack";
  find(ctx, s) {
    const { world, meta } = ctx;
    const crown = s.crown?.id;
    const atWarWithCrown = (pid) => (s.players.find((p) => p.id === pid)?.atWarWith ?? []).includes(crown);
    const realm = (c) => c && (c.owner === crown || (!s.ownerOf(c)?.house?.wild && !atWarWithCrown(c.owner)));
    const at = new Map();
    for (const w of Hosts.warHosts({ world, meta })) { const c = s.cities.find((x) => x.id === w.city); if (c?.owner === crown && w.owner !== crown) at.set(c.id, { how: "march", by: w.owner }); }
    for (const c of s.cities) if (c.owner === crown && c.besieged) at.set(c.id, { how: "siege", by: at.get(c.id)?.by ?? null });
    for (const r of Raids.list(meta, world)) { const c = s.cities.find((x) => x.id === r.goal); if (realm(c) && !at.has(c.id)) at.set(c.id, { how: "raid", by: null }); }
    // The reign's first raid (raids.js first) is the King's first matter, from its first seconds (Mac 2026-11-17: 'any new
    // chronicle should start with at least one actionable item').
    const fr = meta?.firstRaid;
    if (fr && !fr.done && fr.city != null) { const c = s.cities.find((x) => x.id === fr.city); if (realm(c) && !at.has(c.id)) at.set(c.id, { how: "raid", by: null }); }
    const words = MATTERS.attack;
    return [...at].map(([id, t]) => {
      const c = s.cities.find((x) => x.id === id);
      const by = t.by != null ? s.players.find((p) => p.id === t.by)?.house?.name : null;
      return { urgency: t.how === "siege" ? 98 : 92, subject: c.owner, city: id, occur: s.turn, text: String(words[t.how]).replace("{house}", by ?? words.foe).replace("{town}", c.title), why: words.why };
    });
  }
  answers(ctx, s, m) {
    return [{ label: MATTERS.attack.defend, ui: "defend", city: m.city }, { label: "Call the banners", action: "banners" }, { label: "Raise the royal levy", action: "levy" }];
  }
  silence(ctx, s, m) {
    const c = s.cities.find((x) => x.id === m.city);
    const o = s.ownerOf(c);
    return { shift: o && !o.house.crown ? { [o.id]: MATTERS.silence.attack } : {}, cost: MATTERS.leave.alone, text: `The King left ${c.title} to stand alone.` };
  }
}
