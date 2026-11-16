// The Hand's counsel: the realm's matters, worst first, each with why it
// matters and the orders that answer it (counsel), the lesser occasions he
// raises in turn (plague, unrest, a thin granary, bare walls, a loyal one unrewarded, a full treasury, an heir of age), what a
// matter is for resting it (matterKey), and what the King's silence costs
// (lapse; what silence costs is each matter's own, matters/*.js silence). Nothing here reads server.js: the realm's state and the
// bridge's own helpers come in as one context argument, built fresh by
// server.js on each call (server.js keeps wrappers of the same names).

import { crownOf, greatHouses } from "./realm.js";
import { houseFor, cityName } from "./narrator.js";
import { DECREES, bannersReady, ECONOMY, peaceScale } from "./crown.js";  // ECONOMY.thin: below it the treasury is thin (data/economy.json)
import { BANDS } from "./favour.js";
import { calendar, yearsIn } from "./calendar.js";
import * as chron from "./chronicles.js";
import { shortOf } from "./treasury.js";
import * as Rivalry from "./rivalry.js";
import * as Meddling from "./meddling.js";
import { KINDS } from "./matters/index.js";
import { scope } from "./matters/scope.js";

// The Hand of the King advises: the two or three most pressing matters in the
// realm, worst first, each with why it matters in one line and the decrees that
// answer it, so a new King always knows what to do next and learns by doing it.
export function counsel(ctx, players, cities, threat) {
  const { world, meta, seasonsLeft, yearlyKey, FAVOUR, favourOf } = ctx;
  const s = scope(ctx, players, cities, threat);
  const { great, seatOf, short } = s;
  // Every kind of matter, each its own class (matters/index.js): where it stands, its answers, what silence costs.
  const all = KINDS.flatMap((k) => k.build(ctx, s));
  // A house that has turned, claims the throne or rose is its own story: its coldness is not a second matter.
  const covered = new Set(all.filter((o) => o.covers && o.subject != null).map((o) => o.subject));
  const built = all.filter((o) => !(o.kind === "cold" && covered.has(o.subject)));
  const out = built.filter((o) => !o.lesser);
  if (!out.length) out.push({ urgency: 0, text: "The realm is quiet", why: "A good season to win a house's love before you need it.", acts: [] });
  // The realm's lesser matters (plague, uproar, a thin granary, bare walls, a loyal house unrewarded, a full
  // treasury, an heir of age): the Hand raises the ones he has raised least lately, two at most, so his counsel
  // changes with the realm. Those on the card stay a year; a matter the King has answered (an order at its town)
  // rests a year.
  const turn = s.turn;
  const told = (meta.counselTold ??= {});
  const answered = meta.answeredAt ?? {};
  const open = built.filter((o) => o.lesser && o.acts.some((a) => a.ui !== "leave") && !o.acts.some((a) => a.city != null && turn - (answered[a.city] ?? -99) < 4));
  const now = meta.counselNow ?? { kinds: [], since: -99 };
  let lesser = turn - now.since < 4 ? open.filter((o) => now.kinds.includes(o.kind)) : [];
  if (!lesser.length) {
    lesser = open.sort((a, b) => (told[a.kind] ?? -99) - (told[b.kind] ?? -99) || b.urgency - a.urgency).slice(0, 2);
    for (const o of lesser) told[o.kind] = turn;
    meta.counselNow = { kinds: lesser.map((o) => o.kind), since: turn };
    if (lesser.length) chron.saveMeta(meta);
  }
  if (lesser.length) for (let i = out.length - 1; i >= 0; i--) if (out[i].urgency === 0) out.splice(i, 1);  // not "quiet" after all
  out.push(...lesser);
  // An order cut from the King's orders (data/decrees.json off) is never offered, whoever raised the matter.
  for (const o of out) o.acts = o.acts.filter((a) => !DECREES[a.action]?.off);
  for (const o of out) o.acts = o.acts.filter((a) => !(a.action === "banners" && (!bannersReady(world?.turn ?? 0) || seasonsLeft("banners") > 0)) && !(a.action === "levy" && seasonsLeft("levy") > 0) && !(FAVOUR.has(a.action) && a.city != null && seasonsLeft(yearlyKey(a) ?? "") > 0));
  // An order offered once is not offered again under another matter (the
  // banners answer the usurper and the dead alike): the first matter keeps it.
  const given = new Set();
  for (const o of out.sort((a, b) => b.urgency - a.urgency)) o.acts = o.acts.filter((a) => {
    if (a.ui === "leave") return true;  // every matter may be left, at its own price
    const k = `${a.action ?? a.ui}:${a.city ?? ""}:${a.to ?? ""}:${a.building ?? ""}`;
    if (given.has(k)) return false;
    given.add(k);
    return true;
  });
  // The Hand's own pick on each matter: the order that does most for its cost. Never the ward: an
  // heir taken hostage is the King's own hard choice, not the Hand's advice (gameplay review #2).
  const PREFER = ["court", "feast", "relief", "tithe_down", "banners", "peace", "settle", "buyoff", "marriage", "gift", "grant", "levy", "ward", "promise", "cede", "tithe_up"];
  for (const o of out) {
    const rank = (a) => { const i = PREFER.indexOf(a.action ?? a.ui); return i < 0 ? 99 : i; };
    const best = [...o.acts].sort((a, b) => rank(a) - rank(b))[0];
    if (best && o.acts.length > 1) best.pick = true;
  }
  for (const o of out) for (const a of o.acts) priced(ctx, a);
  // Every crisis has at least one answer the King can give (gameplay review #1): when the purse can
  // pay for none of its orders, the crown pays in something else. A march on Kingsmere is answered with
  // a royal town for their claim; any other, with a seat at the council promised to the house, paid
  // for in the favour of the house the King has favoured most (data/decrees.json promise, cede).
  const crownP = players.find((p) => p.house.crown);
  const payable = (a) => a.action && !a.short && DECREES[a.action] && !DECREES[a.action].off;
  for (const o of out) {
    if (!(o.urgency >= 75 || o.kind === "ultimatum") || o.acts.some(payable)) continue;
    const who = players.find((p) => p.id === o.subject);
    if (!who || who.house.crown || who.house.wild || !seatOf(who.id)) continue;
    const name = who.house.name.replace(/^House /, "");
    const spare = o.kind === "march" && crownP ? cities.filter((c) => c.owner === crownP.id && !c.capital).sort((a, b) => (a.size ?? 0) - (b.size ?? 0))[0] : null;
    if (spare) { o.acts.push({ label: `Cede ${spare.title ?? cityName(spare.id)} to ${name} for their claim`, action: "cede", city: spare.id, to: who.id }); continue; }
    if ((meta.oncePerHouse?.promise ?? {})[who.id] != null) continue;
    const rival = great.filter((p) => p.id !== who.id).sort((a, b) => favourOf(b.id) - favourOf(a.id))[0];
    const P = DECREES.promise;
    o.acts.push({ label: `Promise ${name} a seat at council (${name} +${P.favour}${rival ? `, ${short(rival)} ${String(P.rival).replace("-", "−")}` : ""})`, action: "promise", city: seatOf(who.id).id, ...(rival ? { to: rival.id } : {}) });
  }
  // Every matter the realm has, worst first: the court (courtYear) chooses
  // which are put to the King, and when.
  // Never a card that reads "undefined" or "NaN": a matter built from a missing number is dropped, not shown.
  const broken = (o) => /\bundefined\b|\bNaN\b/.test(`${o.text} ${o.why ?? ""} ${(o.acts ?? []).map((a) => a.label).join(" ")}`);
  return out.sort((a, b) => b.urgency - a.urgency).filter((o) => !matterResting(ctx, o) && !broken(o)).map((o) => ({ ...o, key: heardKey(o) }));
}

// What a matter is, for resting it after it is answered.
export const matterKey = (o) => o.kind ?? (/is starving$/.test(o.text) ? "starving" : o.text.replace(/[\d.,]+/g, "#").replace(/:.*$/, ""));
function matterResting(ctx, o) {
  const { world, meta } = ctx;
  const at = meta.mattersRest?.[matterKey(o)];
  return at != null && (world?.turn ?? 0) - at < 4;
}
// The matter itself, for "never twice in a reign": its words without numbers,
// and for a threat that comes again (a march, a host of the dead, a famine
// year) the time it came.
const heardKey = (o) => `${o.text.replace(/[\d.,]+/g, "#").replace(/:.*$/, "")}${o.occur != null ? `@${o.occur}` : ""}`;

// An answer's price and what it does, on its label (the court's cards and the King's promises alike): the price the
// crown will really pay (a share of a full treasury), never the base, and whether the purse can bear it.
export function priced(ctx, a) {
  const { world, lastSeason, priceOf } = ctx;
  const DOES = {  tithe_down: `slower to cool; ${(Math.round((lastSeason?.net ?? 0) * 50) / 1000).toFixed(1)}k less a season`, grant: "+20 them, −30 the holder", gift: "+10", feast: "+15", relief: "+12, eases it, cannot end it", marriage: "+8 each, bound in peace", peace: "a truce; the house that was winning resents it", back: "free; the loser hates you", banners: "+3 if they come", levy: "600 men", buyoff: "+25, others −2", alliance: "sworn 4 years, +5", march: "the host besieges; −25 them" };
  if (DECREES[a.action]?.cost) {
    a.cost = Math.round(priceOf(a.action) * (a.scale ?? 1));  // "Make them stop" is dearer the colder the two houses (crown.js peaceScale)
    const short = shortOf(crownOf(world)?.gold ?? 0, a.cost);
    if (short) a.short = short;
    a.label += `  ${a.cost >= 10000 ? `${Math.round(a.cost / 1000) / 10}m` : `${Math.round(a.cost / 10)}k`} cr`;  // gold ×100 crowns
  }
  const does = DOES[a.action ?? a.ui];
  if (does && !a.label.includes("(")) a.label += ` · ${does}`;
  // Who loses by it (rivalry.js): an order that warms a great house names its rival, jealous, before it is given.
  if (["gift", "feast", "relief", "build", "alliance", "reinforce"].includes(a.action)) {
    const pid = a.to != null && a.to >= 0 ? Number(a.to) : world.cities.find((c) => c.id === Number(a.city))?.owner;
    const jealous = greatHouses(world).some((p) => p.id === pid) ? Rivalry.word(ctx, pid) : "";
    if (jealous) a.label += ` · ${jealous}`;
  }
  const over = Meddling.word(ctx, a.action, a.city);  // grain or a building in a lesser lord's town passes over his liege
  if (over) a.label += ` · ${over}`;
  return a;
}

export function lapse(ctx, m, turn) {
  const { meta, shiftFavour, record } = ctx;
  const told = m.lapse ?? { shift: {}, text: `The King said nothing of it: ${m.text}.` };
  if (Object.keys(told.shift).length) shiftFavour(Object.fromEntries(Object.entries(told.shift).map(([id, d]) => [Number(id), d])), "the King's silence");
  record({ turn, kind: "unrest", text: told.text });
  (meta.mattersRest ??= {})[m.key] = turn;
  meta.matter = null;
  chron.saveMeta(meta);
}
