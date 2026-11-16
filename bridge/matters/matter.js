// A matter: one kind of trouble that needs the King (Mac 2026-11-16: "is this really filled with tension?"; "SSOT,
// SRP, DRY, OOP, SOLID ... use what's right"). The one decider of what needs him and how he may answer it: the
// bridge, here, kind by kind; the view only shows what a matter says (news_actions.gd, court_panel.gd). Each kind is a
// class with the same three parts (Reigns' two-sided card, Frostpunk's law with its cost, CK3's event options):
//   find(ctx, s)          where it stands now: [{subject, city, text, why, urgency, occur}]
//   answers(ctx, s, m)    at most three answers, each a different trade (crowns, a house's favour, men, time)
//   silence(ctx, s, m)    what saying nothing costs: {shift: {pid: delta}, text}
// build() puts them together and adds "Leave it" with its cost, so ignoring a matter is a choice with a price on its
// face, not a card left unread. counsel.js runs every kind in the registry (matters/index.js) and applies the rules
// all matters share (the price on each answer, one order per matter, a crisis always answerable).

import fs from "node:fs";
import * as Nature from "./nature.js";

export const MATTERS = JSON.parse(fs.readFileSync(new URL("../data/matters.json", import.meta.url), "utf8"));

const signed = (d) => (d > 0 ? `+${d}` : `−${-d}`);

export class Matter {
  static kind = "";
  static lesser = false;  // raised in turn with the other lesser matters (counsel.js), two at a time
  get kind() { return this.constructor.kind; }
  get lesser() { return this.constructor.lesser; }
  find(_ctx, _s) { return []; }
  answers(_ctx, _s, _m) { return []; }
  silence(_ctx, _s, _m) { return null; }

  // The matter whole: its answers (at most MATTERS.answers), what silence costs, and Leave it priced with that.
  build(ctx, s) {
    return this.find(ctx, s).map((m) => {
      const acts = Nature.pick(ctx.meta, this.answers(ctx, s, m), MATTERS.answers ?? 3);  // who he is, first (nature.js)
      const lapse = this.silence(ctx, s, m);
      const o = { kind: this.kind, lesser: this.lesser, ...m, acts, lapse };
      if (lapse) o.acts.push(leave(ctx, s, lapse));
      return o;
    });
  }
}

// Saying nothing, as an answer with its price: who cools and by how much, in the houses' names.
export function leave(ctx, s, lapse) {
  const names = Object.entries(lapse.shift ?? {}).filter(([, d]) => d).map(([pid, d]) => `${s.short(s.players.find((p) => p.id === Number(pid)))} ${signed(d)}`);
  return { label: MATTERS.leave.label + (names.length ? ` · ${names.join(", ")}` : lapse.cost ? ` · ${lapse.cost}` : ""), ui: "leave" };
}
