// The threat the storyteller raised (director.js): a matter at its place, more urgent as it grows.
import { Matter, MATTERS } from "./matter.js";
import * as Director from "../director.js";

export class Threat extends Matter {
  static kind = "threat";
  find(ctx) {
    const m = Director.matter(ctx.meta);
    return m ? [{ ...m, city: m.place?.city ?? null, given: m.acts }] : [];
  }
  answers(ctx, s, m) { const acts = m.given; delete m.given; return acts; }
  silence(ctx, s, m) {
    const c = s.cities.find((x) => x.id === m.city);
    const o = s.ownerOf(c);
    return { shift: o && !o.house.crown ? { [o.id]: MATTERS.silence.other } : {}, text: `The King said nothing of it: ${m.text.charAt(0).toLowerCase() + m.text.slice(1).replace(/:.*$/, "")}.` };
  }
}
