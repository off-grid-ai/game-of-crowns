// The King's ledger: what he did, judged on four axes, and the name the realm
// gives him for it (Bannerlord's traits, Frostpunk's ending: judged by deeds,
// not by the stockpile). Saved in meta.ledger, so it survives a reload; a
// chronicle from before it opens with an empty ledger.
//
// Axes: word (kept / broke), mercy (spared / hanged), give (generous / grasping),
// peace (made / chose war). Each deed is ±1, a grave one ±2. Which deed moves
// which axis is data: data/ledger.json (decrees, court rulings, the realm's own deeds).

import fs from "node:fs";

const TAGS = JSON.parse(fs.readFileSync(new URL("./data/ledger.json", import.meta.url), "utf8"));
const AXES = ["word", "mercy", "give", "peace"];
const NAMES = {
  word: ["the True", "the Oathbreaker"],
  mercy: ["the Merciful", "the Cruel"],
  give: ["the Generous", "the Grasping"],
  peace: ["the Peacemaker", "the Conqueror"],
};
const STRONG = 3;  // an axis names the King once its deeds add up to this much, either way

function book(meta) {
  meta.ledger ??= { sum: { word: 0, mercy: 0, give: 0, peace: 0 }, acts: 0, unheard: 0, favour: {}, deeds: [], name: null };
  return meta.ledger;
}

// The tags for one deed: tagsFor("decree", "gift"), tagsFor("deck", card, option), ...
export function tagsFor(kind, key, option) {
  const t = TAGS[kind]?.[key];
  const tag = option === undefined ? t : t?.[option];
  return tag && typeof tag === "object" ? tag : null;
}

// A deed into the ledger. tag: {axes, says}; favour: {pid: delta} the deed gave.
// Returns the name it earns now and whether that changed (for the ticker).
export function note(meta, tag, { turn = 0, favour = {}, act = true, place = "" } = {}) {
  const l = book(meta);
  if (act) l.acts++;
  for (const [pid, n] of Object.entries(favour ?? {})) if (n > 0) l.favour[pid] = (l.favour[pid] ?? 0) + n;
  const axes = tag?.axes ?? {};
  if (Object.keys(axes).length) {
    for (const a of AXES) if (axes[a]) l.sum[a] += axes[a];
    const says = String(tag.says ?? "").replace("{town}", place || "a town").replace("{house}", place || "a house");
    l.deeds.push({ turn, axes, says });
    if (l.deeds.length > 120) l.deeds.shift();
  }
  return l;
}

// A petitioner sent home unheard: absence, not a deed.
export function unheard(meta) {
  book(meta).unheard++;
}

// The name the realm gives the King, and why, from the ledger. outcome: the
// reign's end ("deposed", "fallen") or null while he rules. realm: {peace, grew}
// averages, which only break a tie. houseName(pid) names a favoured house.
export function epithetOf(meta, outcome, realm = {}, houseName = () => null) {
  const l = book(meta);
  if (outcome === "deposed") return { name: "the Deposed", why: "" };
  if (outcome === "fallen") return { name: "the Last", why: "" };
  const s = l.sum;
  const ranked = AXES.map((a) => [a, s[a]]).filter(([, v]) => Math.abs(v) >= STRONG)
    .sort((x, y) => Math.abs(y[1]) - Math.abs(x[1]) || tieBreak(y[0], realm) - tieBreak(x[0], realm));
  // A King who barely ruled is named for it, never flattered (unless what little he did was grave).
  if (!ranked.length && l.unheard > Math.max(3, l.acts)) return { name: "the Absent", why: `${l.unheard} who came to court went home unheard.` };
  if (!ranked.length && l.acts < 4) return { name: "the Idle", why: l.acts ? `He gave the realm ${l.acts === 1 ? "a single order" : `${l.acts} orders`} in all his reign.` : "He gave the realm no orders at all." };
  const why = (axis, sign) => whyOf(l, axis, sign);
  if (ranked.length >= 2 && Math.abs(Math.abs(ranked[0][1]) - Math.abs(ranked[1][1])) <= 1) {
    const pair = new Set(ranked.slice(0, 2).map(([a, v]) => `${a}${v > 0 ? "+" : "-"}`));
    const both = (x, y) => pair.has(x) && pair.has(y);
    const two = (n) => ({ name: n, why: remembered([...saysOf(l, ranked[0][0], Math.sign(ranked[0][1])).slice(0, 2), ...saysOf(l, ranked[1][0], Math.sign(ranked[1][1])).slice(0, 1)]) });
    if (both("mercy+", "give+")) return two("the Good");
    if (both("mercy-", "peace-")) return two("the Bloody");
    if (both("word-", "give-")) return two("the Faithless");
  }
  if (ranked.length) {
    const [a, v] = ranked[0];
    return { name: NAMES[a][v > 0 ? 0 : 1], why: why(a, Math.sign(v)) };
  }
  // No axis stands out: a house he raised above the rest, or the plain names.
  const given = Object.entries(l.favour);
  const total = given.reduce((t, [, n]) => t + n, 0);
  const [pid, most] = given.sort((x, y) => y[1] - x[1])[0] ?? [null, 0];
  if (total >= 40 && most > total / 2 && houseName(pid)) return { name: `Friend of ${houseName(pid)}`, why: `His favours went to ${houseName(pid)} above every other house.` };
  const neg = AXES.some((x) => s[x] < 0);
  if (l.acts >= 10 && !neg && (realm.peace ?? 0) > 0.8 && (realm.grew ?? 0) > 1.3) return { name: "the Golden", why: "He did no wrong that the realm remembers, and the realm grew rich and quiet under him." };
  return { name: "the Steadfast", why: "He ruled without great wrongs or great deeds." };
}

// The nearest other name: the next axis by strength, for "a few would say".
export function nextName(meta, current) {
  const s = book(meta).sum;
  const near = AXES.map((a) => [NAMES[a][s[a] >= 0 ? 0 : 1], Math.abs(s[a])]).filter(([n, v]) => n !== current && v >= 1).sort((x, y) => y[1] - x[1]);
  return near[0]?.[0] ?? null;
}

// The deed that most made the name: the heaviest on that side, the latest of equals.
export function tipping(meta, axis, sign) {
  // The latest of the heaviest: the deed that tipped it, not the first of its kind.
  const d = book(meta).deeds.map((x, i) => ({ ...x, i })).filter((x) => Math.sign(x.axes[axis] ?? 0) === sign && x.says);
  return d.sort((x, y) => Math.abs(y.axes[axis]) - Math.abs(x.axes[axis]) || y.i - x.i)[0]?.says ?? null;
}

function saysOf(l, axis, sign) {
  return [...new Set(l.deeds.map((x, i) => ({ ...x, i })).filter((x) => Math.sign(x.axes[axis] ?? 0) === sign && x.says).sort((x, y) => Math.abs(y.axes[axis]) - Math.abs(x.axes[axis]) || y.i - x.i).map((x) => x.says))];
}
function remembered(said) {
  said = [...new Set(said)];
  if (!said.length) return "";
  return `The realm remembers ${said.length > 1 ? `${said.slice(0, -1).join(", ")} and ${said[said.length - 1]}` : said[0]}.`;
}
function whyOf(l, axis, sign) {
  return remembered(saysOf(l, axis, sign).slice(0, 2));
}

// Equal deeds either way: the realm's own state leans the name (peace held or war raged).
function tieBreak(axis, realm) {
  if (axis === "peace" && ((realm.peace ?? 0.5) > 0.75 || (realm.peace ?? 0.5) < 0.3)) return 1;
  return 0;
}

export function axisOf(name) {
  for (const a of AXES) { const i = NAMES[a].indexOf(name); if (i >= 0) return [a, i === 0 ? 1 : -1]; }
  return null;
}
