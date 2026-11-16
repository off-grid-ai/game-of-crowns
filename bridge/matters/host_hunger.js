// The King's own host starving far from his granaries (hosts.js supply): it loses men every season it stays out.
import { Matter } from "./matter.js";
import * as Hosts from "../hosts.js";

const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));

export class HostHunger extends Matter {
  static kind = "host_hunger";
  find(ctx, s) {
    const thin = Hosts.list(ctx).filter((h) => (h.supply ?? 1) < 0.5).sort((a, b) => (a.supply ?? 1) - (b.supply ?? 1))[0];
    if (!thin) return [];
    const home = s.cities.filter((c) => c.owner === s.crown?.id).sort((a, b) => cheb(a, thin) - cheb(b, thin))[0];
    const near = [...s.cities].sort((a, b) => cheb(a, thin) - cheb(b, thin))[0];
    return [{ urgency: 75, subject: s.crown?.id, city: near?.id, host: thin.id, home: home?.id, places: [near?.id].filter((x) => x != null),
      text: `Your host near ${near?.title ?? "the border"} is starving`,
      why: `${thin.men.toLocaleString("en-US")} men, ${Math.round((thin.stragglers ?? 0) * 100)}% already fallen out of the line. Out of the carts' reach they lose men every season, twice as fast in winter.` }];
  }
  answers(ctx, s, m) {
    const home = s.cities.find((c) => c.id === m.home);
    const near = s.cities.find((c) => c.id === m.city);
    // Bring them home and give up the ground; feed them where they stand from the crown's purse (grain to the
    // nearest town); or press on and let them thin.
    return [home ? { label: `Bring them home to ${home.title}`, ui: "host", order: "garrison", host: m.host, city: home.id } : null,
      near && near.owner !== s.crown?.id ? { label: `Buy grain at ${near.title}`, action: "relief", city: near.id } : null];
  }
  silence() {
    return { shift: {}, cost: "the host thins every season", text: "The King left his host where it stood. Men fell out of the line every day." };
  }
}
