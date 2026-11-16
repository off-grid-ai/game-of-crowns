// What a choice changed, as rows the reckoning card shows (realm/scripts/reckoning.gd; Mac 2026-11-16: "I can take any
// action and it doesn't feel like it's that impactful ... maybe things are happening but it's not very evident"). Reigns'
// meters that move at the choice, Frostpunk's consequence line: every decree and ruling answers with each thing it
// moved, from and to, in words. One shape for every caller (routes_decree.js, court.js): this file.
//   of({ favour: [{house, from, to, word}], gold: [from, to], alarm: [from, to], towns: [{town, from, to}], war: house })
// -> [{ kind, label, from, to, word, sign }], sign +1 good for the King, -1 bad, 0 neither (the word says it too).

const crowns = (g) => `${Math.round(g * 100).toLocaleString("en-GB")}`;

export function of({ favour = [], gold = null, alarm = null, towns = [], war = null } = {}) {
  const rows = [];
  if (gold && gold[0] !== gold[1]) rows.push({ kind: "crowns", label: "Treasury", from: crowns(gold[0]), to: `${crowns(gold[1])} crowns`, word: gold[1] < gold[0] ? `${crowns(gold[0] - gold[1])} spent` : `${crowns(gold[1] - gold[0])} gained`, sign: gold[1] < gold[0] ? -1 : 1 });
  for (const t of towns) rows.push({ kind: "town", label: t.town, from: `${t.from}'s`, to: `${t.to}'s`, word: "changes hands", sign: 0 });
  if (war) rows.push({ kind: "war", label: `House ${war}`, from: "", to: "at war with the crown", word: "", sign: -1 });
  for (const m of favour) rows.push({ kind: "favour", label: m.house, from: String(m.from), to: String(m.to), word: m.word, sign: m.to > m.from ? 1 : -1 });
  if (alarm && Math.round(alarm[0]) !== Math.round(alarm[1])) rows.push({ kind: "alarm", label: "The realm's alarm", from: String(Math.round(alarm[0])), to: `${Math.round(alarm[1])} of 100`, word: alarm[1] > alarm[0] ? "the houses take fright" : "the houses calm", sign: alarm[1] > alarm[0] ? -1 : 1 });
  return rows;
}
