// What a person wants, in one wording (data/ambitions.json aim, plain, lord, bannerman): a person holds their aim
// as plain words said of them, "their" for their sex (goals[0].text); aimWords says it for whoever speaks.

import fs from "node:fs";

export const AMB = JSON.parse(fs.readFileSync(new URL("./data/ambitions.json", import.meta.url), "utf8"));

const neutral = (s) => String(s ?? "").replace(/\{(\w+)\}/g, (_, k) => k);

// The aim of this kind as a person holds it: {kind, text}.
export const plainAim = (kind) => ({ kind, text: neutral(AMB.plain[kind]) });

// Every aim a person can hold, for the King to give them (the character form).
export const AIMS = Object.keys(AMB.plain).map(plainAim);

// The aims dealt to a lord or a bannerman.
export const dealt = (rank) => (rank === "lord" ? AMB.lord : AMB.bannerman).map(plainAim);

// An aim (held words, or a story's or a ruling's own: "repay the King who raised me") said by `voice`: "they" (of
// them, his or her by `gender`), "I" (their own words) or "you" (to them).
export function aimWords(text, voice, gender) {
  const f = gender === "female";
  const w = voice === "I" ? { their: "my", them: "me", they: "I", themselves: "myself" }
    : voice === "you" ? { their: "your", them: "you", they: "you", themselves: "yourself" }
    : { their: f ? "her" : "his", them: f ? "her" : "him", they: f ? "she" : "he", themselves: f ? "herself" : "himself" };
  return String(text ?? "").replace(/\{(their|them|they|themselves)\}/g, (_, k) => w[k])
    .replace(/\b(my|their)\b/g, w.their).replace(/\b(myself|themselves)\b/g, w.themselves).replace(/\bme\b/g, w.them).replace(/\bI\b/g, w.they);
}

// Whether held words are the plain aim of their kind (so the realm's target can be named in them).
export const isPlain = (g) => !!g && AMB.plain[g.kind] != null && g.text === neutral(AMB.plain[g.kind]);
