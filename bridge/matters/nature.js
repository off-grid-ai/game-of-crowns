// The King's nature on his answers (data/nature.json): the one reading of which way he leans, hard (feared) or soft
// (loved), from his chosen focus and his traits. A matter puts the answers that fit him first and keeps one of the
// other kind, so every card is a choice between who he is and what the moment may need; an answer against his
// nature says so on its face and weighs on him when given (routes_decree.js, royals.js ruled).
import fs from "node:fs";
import * as Royals from "../royals.js";

const N = JSON.parse(fs.readFileSync(new URL("../data/nature.json", import.meta.url), "utf8"));
const kindOf = (a) => (N.hard.includes(a?.action) ? "hard" : N.soft.includes(a?.action) ? "soft" : null);

// "hard", "soft" or null (no lean): his focus first, else the most of his traits.
export function lean(meta) {
  const k = Royals.of(meta)?.king;
  if (!k) return null;
  if (N.leans[k.focus]) return N.leans[k.focus];
  const votes = (k.traits ?? []).map((t) => N.traits[t]).filter(Boolean);
  const hard = votes.filter((v) => v === "hard").length, soft = votes.length - hard;
  return hard > soft ? "hard" : soft > hard ? "soft" : null;
}

// Whether an order goes against the King's nature.
export const against = (meta, a) => { const l = lean(meta), k = kindOf(a); return !!(l && k && k !== l); };

// The answers a matter offers, most: those that fit him first, at least one of each kind when both are there.
export function pick(meta, acts, most) {
  const l = lean(meta);
  const list = acts.filter(Boolean);
  const fits = list.filter((a) => !l || kindOf(a) !== (l === "hard" ? "soft" : "hard"));
  const other = list.filter((a) => !fits.includes(a));
  const out = [...fits.slice(0, other.length ? most - 1 : most), ...other.slice(0, 1)];
  for (const a of out) if (against(meta, a)) a.label += ` · ${N.against}`;
  return out;
}
