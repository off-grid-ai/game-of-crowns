// The King's own household and the crown's succession (CK3's dynasty and heirs: when the King dies the game goes on as
// his heir). One owner, meta.royals {king, consort, children, kin, line}: the King, his consort, their children and
// the King's brothers and sisters (kin), each {id, name, age, woman, alive}, and the Kings before him in this reign
// (line: [{name, from, to, how, age}]). They age at
// each year's end (season.js), the King dies by his age and children are born (data/royals.json); a death or an
// abdication (POST /abdicate) passes the crown by law to the heir, and the reign goes on. No heir: the reign ends.
// The houses' lords and their heirs stay characters.js's; the crown's family is only here.
import fs from "node:fs";
import { rng } from "./fresh.js";
import { greatHouses } from "./realm.js";
import * as Lua from "./lua.js";
import { TRAITS } from "./characters.js";  // read only at run time (characters.js imports this module too)

const R = JSON.parse(fs.readFileSync(new URL("./data/royals.json", import.meta.url), "utf8"));
const NAMES = JSON.parse(fs.readFileSync(new URL("./data/first-names.json", import.meta.url), "utf8"));
const between = (r, [a, b]) => a + Math.floor(r() * (b - a + 1));

// A royal's two traits (CK3's traits as heirlooms): a child takes each of its parents' traits by data/royals.json
// traits.inherit, the rest by chance; the first King and his consort, by chance.
function traitsOf(r, parents = []) {
  const out = [];
  for (const t of parents.flatMap((p) => p?.traits ?? [])) if (out.length < 2 && !out.includes(t) && r() < R.traits.inherit) out.push(t);
  while (out.length < 2) { const t = TRAITS[Math.floor(r() * TRAITS.length)]; if (!out.includes(t)) out.push(t); }
  return out;
}

// A new royal: a first name no living royal has, and traits from the parents.
function born(h, r, woman, age, parents = []) {
  const taken = new Set([h.king, h.consort, ...h.children, ...h.kin].filter((p) => p?.alive).map((p) => p.name));
  const pool = (woman ? NAMES.female : NAMES.male).filter((n) => !taken.has(n));
  h.seq = (h.seq ?? 0) + 1;
  return { id: `r${h.seq}`, name: pool[Math.floor(r() * pool.length)] ?? "Edric", age, woman, alive: true, traits: traitsOf(r, parents) };
}

// The household, seeded once for a reign from its seed (the same seed, the same family).
export function of(meta) {
  if (!meta.royals && meta.dynasty?.king) {
    // One more generation (CK2): a real reign after one that ended with an heir begins as that heir's (chronicles.js
    // create, from the Hall of Records): the heir is King, with their traits and their brothers and sisters.
    const d = meta.dynasty;
    const h = { children: [], kin: [], line: [{ name: d.of, from: null, to: null, how: "the last reign", age: null }], seq: 0 };
    const seat = (p) => ({ ...p, id: `r${++h.seq}`, alive: true });
    h.king = seat(d.king);
    h.kin = (d.kin ?? []).map(seat);
    h.consort = null;
    h.since = meta.crownedAt ?? 0;
    return (meta.royals = h);
  }
  if (meta.royals) {
    // A household from before royals had traits: they are dealt now, once.
    const r = rng((Number(meta.seed ?? 1066) ^ 0x7a17) >>> 0);
    for (const p of [meta.royals.king, meta.royals.consort, ...meta.royals.children, ...(meta.royals.kin ?? [])]) if (p && !p.traits) p.traits = traitsOf(r);
    return meta.royals;
  }
  const r = rng((Number(meta.seed ?? 1066) ^ 0x5eed) >>> 0);
  const h = { children: [], kin: [], line: [] };
  h.king = born(h, r, false, between(r, R.king.age));
  h.consort = born(h, r, true, h.king.age - between(r, R.consort.younger));
  let age = between(r, R.children.age);
  for (let i = between(r, R.children.count); i > 0 && age >= 0; i--) {
    h.children.push(born(h, r, r() < 0.5, age, [h.king, h.consort]));
    age -= between(r, R.children.gap);
  }
  h.since = meta.crownedAt ?? 0;
  return (meta.royals = h);
}

// Who the crown passes to now, by law (male-preference: the eldest son, else the eldest daughter; with no child, the
// King's eldest brother, else sister), or null.
export function heir(h) {
  const first = (list) => {
    const alive = list.filter((k) => k.alive).sort((a, b) => b.age - a.age);
    return (R.law === "male-preference" ? alive.find((k) => !k.woman) : null) ?? alive[0] ?? null;
  };
  return first(h.children) ?? first(h.kin ?? []);
}

// The crown passes to the heir: the old King goes into the line, the heir is King, the reign goes on.
function pass(ctx, h, how, turn) {
  const next = heir(h);
  const old = h.king;
  h.line.push({ name: old.name, from: h.since ?? 0, to: turn, how, age: old.age });
  if (!next) {
    ctx.endReign(`${old.woman ? "Queen" : "King"} ${old.name} is dead, and no heir of the blood lives.`, "heirless");
    return;
  }
  // The new King's brothers and sisters are his kin; he has no consort or children yet (he weds in time, year()).
  h.kin = [...h.children, ...(h.children.includes(next) ? [] : h.kin)].filter((k) => k !== next && k.alive);
  h.children = [];
  h.king = next;
  h.consort = next.spouse ?? null;  // the heir's match (characters.js royalwed) is the new consort
  delete next.spouse;
  h.since = turn;
  const title = next.woman ? "Queen" : "King", was = old.woman ? "Queen" : "King";
  const minor = next.age < R.majority;
  const told = how === "abdicated"
    ? `${was} ${old.name} lays down the crown. ${next.name}, ${next.age}, is crowned in Kingsmere${minor ? ", and a regency rules until they come of age" : ""}.`
    : `${was} ${old.name} is dead at ${old.age}. Long live ${title} ${next.name}${minor ? `, a child of ${next.age}: a regency rules in their name` : ""}.`;
  ctx.record({ turn, kind: "succession", text: told });
  // The funeral is the crisis (CK2, Old World: oaths were sworn to the man, not the crown): every great house's favour
  // falls back toward data/royals.json funeral.to by funeral.pull, the love and the grudges alike; the new King earns his own.
  const swing = Object.fromEntries(greatHouses(ctx.world).map((p) => [p.id, Math.round((R.funeral.to - ctx.favourOf(p.id)) * R.funeral.pull)]).filter(([, d]) => d));
  if (Object.keys(swing).length) {
    ctx.shiftFavour(swing, `the oaths sworn to ${old.name}`);
    ctx.record({ turn, kind: "court", text: `The great houses swore to ${old.name}, not to ${next.name}. Old friends wait to be won again, and old grudges are half forgotten.` });
  }
  temper(ctx, next, turn);
  if (minor) {
    const cool = Object.fromEntries(greatHouses(ctx.world).map((p) => [p.id, R.minor.favour]));
    ctx.shiftFavour(cool, "a child on the throne");
    ctx.record({ turn, kind: "unrest", text: "A child wears the crown. The great houses take note." });
  }
}

// The great lords take the new King's measure (CK3's opinion of a like or an unlike ruler): each warms by
// data/royals.json traits.like for every trait he shares with the King and cools by traits.unlike for every trait the
// King has that is the opposite of one of his. Said for the warmest and the coldest.
function temper(ctx, king, turn) {
  const opp = new Map(R.traits.opposed.flatMap(([a, b]) => [[a, b], [b, a]]));
  const swing = {};
  for (const p of greatHouses(ctx.world)) {
    const lord = ctx.court?.lordOfHouse(p.id);
    if (!lord) continue;
    const kt = king.traits ?? [];
    const d = kt.filter((t) => lord.traits.includes(t)).length * R.traits.like - kt.filter((t) => lord.traits.includes(opp.get(t))).length * R.traits.unlike;
    if (d) swing[p.id] = d;
  }
  if (!Object.keys(swing).length) return;
  ctx.shiftFavour(swing, `what they make of ${king.name}, ${(king.traits ?? []).join(" and ")}`);
  const by = Object.entries(swing).sort((a, b) => b[1] - a[1]);
  const name = (pid) => ctx.court.lordOfHouse(Number(pid))?.name;
  const [hi, lo] = [by[0], by.at(-1)];
  const words = [hi[1] > 0 ? `${name(hi[0])} is pleased` : null, lo[1] < 0 ? `${name(lo[0])} is not` : null].filter(Boolean);
  if (words.length) ctx.record({ turn, kind: "court", text: `The lords take the measure of ${king.name}, ${(king.traits ?? []).join(" and ")}. ${words.join("; ")}.` });
}

// A year turns (season.js, at the year's end): the royals age; the young may die; children are born; the King may die.
export function year(ctx, turn) {
  const h = of(ctx.meta);
  const r = rng(((Number(ctx.meta.seed ?? 1066) >>> 0) ^ Math.imul(turn + 7, 2654435761)) >>> 0);
  for (const p of [h.king, h.consort, ...h.children, ...h.kin]) if (p?.alive) p.age++;
  for (const k of h.children) if (k.alive && k.age < 6 && r() < R.childDeath) {
    k.alive = false;
    ctx.record({ turn, kind: "death", text: `The King's ${k.woman ? "daughter" : "son"} ${k.name} dies in the nursery, ${k.age} years old. Kingsmere mourns.` });
  }
  for (const k of h.kin) if (k.alive && r() < (R.death.find(([from]) => k.age >= from) ?? [0, 0])[1]) k.alive = false;
  // A King of age without a consort weds (data/royals.json wed): the crown needs heirs of his body.
  if (!h.consort?.alive && h.king.age >= R.majority && r() < R.wed.chance) {
    h.consort = born(h, r, !h.king.woman, Math.max(R.majority, h.king.age - between(r, R.consort.younger)));
    ctx.record({ turn, kind: "marriage", text: `${h.king.woman ? "Queen" : "King"} ${h.king.name} weds ${h.consort.name} in Kingsmere. The realm drinks to the match.` });
  }
  const c = h.consort;
  if (c?.alive && c.age <= R.birth.until && h.children.length < R.birth.most && r() < R.birth.chance) {
    const k = born(h, r, r() < 0.5, 0, [h.king, c]);
    h.children.push(k);
    ctx.record({ turn, kind: "birth", text: `${h.king.woman ? `Queen ${h.king.name}` : "The Queen"} is delivered of a ${k.woman ? "daughter" : "son"}, ${k.name}. The bells ring in Kingsmere.` });
  }
  h.king.stress = Math.max(0, (h.king.stress ?? 0) - R.stress.ease);
  const risk = (R.death.find(([from]) => h.king.age >= from) ?? [0, 0])[1] + Math.max(0, (h.king.stress ?? 0) - R.stress.high) * R.stress.risk
    + (h.king.wound != null && turn - h.king.wound < 4 ? R.rest.hunt.wound : 0);
  if (r() < risk) { h.king.alive = false; pass(ctx, h, "died", turn); }
}

// The King gives up the crown (POST /abdicate): only to an heir of age; else why not.
export function abdicate(ctx) {
  const h = of(ctx.meta);
  const next = heir(h);
  if (!next) return { error: "The King has no heir to take the crown." };
  if (next.age < R.abdicate.age) return { error: `${next.name} is ${next.age}, too young to be crowned.` };
  pass(ctx, h, "abdicated", ctx.world?.turn ?? 0);
  return { ok: true, king: h.king.name };
}

// The blood a reign hands the next (reign.js endReign, in the Hall of Records; CK2's "one more generation"): its heir
// now, with traits and kin, and whose child they are; none when the reign ended with the line lost (deposed, fallen,
// heirless) or no heir lives.
export function dynastyOf(meta, outcome) {
  const h = meta.royals;
  if (!h || ["deposed", "fallen", "heirless"].includes(outcome)) return null;
  const next = heir(h);
  if (!next) return null;
  const who = (p) => ({ name: p.name, age: p.age, woman: p.woman, traits: p.traits ?? [] });
  const kin = [...h.children, ...(h.kin ?? [])].filter((k) => k.alive && k !== next);
  return { king: who(next), kin: kin.map(who), of: h.king.name };
}

// How a reign that ends heirless is judged (reign.js endReign): its score's share and its verdict.
export const HEIRLESS = R.heirless;
// A great lord's child offered for the heir's hand at court (characters.js royalwed): the age, the plea's weight, the favour.
export const MATCH = R.match;
// A child on the throne emboldens the cold houses (characters.js rebel): a rising weighs minor.rising more, and a lord
// who wants the crown himself minor.claim more again.
export const REGENCY = { rising: R.minor.rising ?? 0, claim: R.minor.claim ?? 0 };
export const isRegency = (h) => Boolean(h?.king && h.king.age < R.majority);

// A ruling at court (court.js answer): against the King's own nature it weighs on him (data/royals.json stress; CK3's
// stress). Over high, the chronicle says it once, and each point over makes his yearly death likelier (year).
export function ruled(ctx, kind, option) {
  const h = ctx.meta.royals;
  if (!h?.king) return;
  const k = h.king, S = R.stress;
  const against = (k.traits ?? []).filter((t) => (S.against[t] ?? []).includes(`${kind}.${option}`));
  if (!against.length) return;
  const was = k.stress ?? 0;
  k.stress = was + S.per * against.length;
  if (was <= S.high && k.stress > S.high) ctx.record({ turn: ctx.world?.turn ?? 0, kind: "court", text: `${k.woman ? "Queen" : "King"} ${k.name} sleeps badly. A ${against[0]} soul made to rule against itself, season after season; the physicians shake their heads.` });
}

// The King eases his stress (POST /king/rest {kind}; data/royals.json rest: a hunt, a feast, a pilgrimage), each once
// in its seasons, for gold from the crown's chest. The hunt may wound him (a year's added death risk); the feast warms
// the great houses; the pilgrimage, the pious lords.
export function rest(ctx, kind) {
  const h = of(ctx.meta), k = h.king, Rk = R.rest[kind];
  const turn = ctx.world?.turn ?? 0;
  if (!Rk || kind === "_") return { error: "No such rest." };
  const last = h.rested?.[kind];
  if (last != null && turn - last < Rk.seasons) return { error: `Not again so soon: in ${Rk.seasons - (turn - last)} seasons.` };
  const crown = ctx.crownOf?.();
  if ((crown?.gold ?? 0) < Rk.gold) return { error: `The treasury holds ${crown?.gold ?? 0} gold; it costs ${Rk.gold}.` };
  ctx.send(`lua cmd ${Lua.gold(crown.id, -Rk.gold)}`);
  crown.gold -= Rk.gold;
  (h.rested ??= {})[kind] = turn;
  k.stress = Math.max(0, (k.stress ?? 0) - Rk.ease);
  let told = Rk.words;
  if (kind === "hunt" && Math.random() < Rk.risk) { k.wound = turn; told += ` His horse falls at a ditch, and he is carried home hurt.`; }
  if (kind === "feast") ctx.shiftFavour(Object.fromEntries(greatHouses(ctx.world).map((p) => [p.id, Rk.favour])), "the King's feast");
  if (kind === "pilgrimage") {
    const pious = greatHouses(ctx.world).filter((p) => ctx.court?.lordOfHouse(p.id)?.traits?.includes("pious"));
    if (pious.length) ctx.shiftFavour(Object.fromEntries(pious.map((p) => [p.id, Rk.pious])), "the King's pilgrimage");
  }
  ctx.record({ turn, kind: kind === "feast" ? "feast" : "court", text: told });
  return { ok: true, stress: k.stress };
}

// For /world: the King, his consort, his heir and the rest of his children, and the Kings before him.
export function view(meta, turn = 0) {
  const h = meta?.royals;
  if (!h) return null;
  const who = (p) => p && { id: p.id, name: p.name, age: p.age, woman: p.woman, traits: p.traits ?? [], ...(p === h.king ? { stress: p.stress ?? 0 } : {}) };
  const next = heir(h);
  return {
    king: who(h.king), consort: h.consort?.alive ? who(h.consort) : null, heir: who(next), match: next?.spouse ? { name: next.spouse.name, house: next.spouse.house } : null,
    children: h.children.filter((k) => k.alive).map(who), kin: h.kin.filter((k) => k.alive).map(who), regency: isRegency(h),
    line: h.line, rest: Object.fromEntries(Object.entries(R.rest).filter(([k]) => k !== "_").map(([k, v]) => [k, { gold: v.gold, ease: v.ease, ready: h.rested?.[k] == null || turn - h.rested[k] >= v.seasons, last: h.rested?.[k] ?? null, seasons: v.seasons }])), abdicate: Boolean(next && next.age >= R.abdicate.age),
  };
}
