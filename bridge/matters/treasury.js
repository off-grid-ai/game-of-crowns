// The royal purse: thin (every decree costs crowns) or full (gold in a chest wins nobody).
import { Matter } from "./matter.js";
import { ECONOMY } from "../crown.js";

export class ThinTreasury extends Matter {
  static kind = "thin";
  find(ctx, s) {
    return s.purse < ECONOMY.thin ? [{ urgency: 40, text: "The royal treasury is thin", why: "Every decree costs crowns; a higher tithe fills the purse but cools the houses." }] : [];
  }
  answers() { return [{ label: "Raise the tithe", ui: "tithe_up" }]; }
}

export class FullTreasury extends Matter {
  static kind = "rich";
  static lesser = true;
  find(ctx, s) {
    return s.purse >= 600 && s.crownSeat ? [{ urgency: 30, city: s.crownSeat.id, text: "The royal treasury is full", why: "Gold in a chest wins nobody. Spend it where the realm will see it, or ease the tithe and let the houses keep more." }] : [];
  }
  answers(ctx, s) {
    return [{ label: "Hold a feast at court", action: "feast", city: s.crownSeat.id }, ctx.meta.tithe > 0 ? { label: `Lower the tithe to ${Math.round(ctx.meta.tithe * 100) - 5}%`, ui: "tithe_down" } : null,
      s.lacks(s.crownSeat, "Marketplace") ? { label: "Pay for a market at Kingsmere", action: "build", building: "market", city: s.crownSeat.id } : null];
  }
  silence() { return { shift: {}, text: "The King said nothing while the gold sat in the royal chest. The houses saw it sit." }; }
}
