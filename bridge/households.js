// The common folk's households: families that last a reign, age, marry, bear children, take up a trade, die and
// move away (casebook, People: the crowd is the census; RimWorld's and Dwarf Fortress's folk who live whole lives).
// The rules are Talk of the Town's (James Ryan, MIT: simulation.py and its life-cycle and marriage configs), at
// a season's step: singles of marriageable age wed, and one takes the other's name; a married couple try for a
// child a year with 0.4 / (children + 1); a widow or widower remarries with 1 / (years married + 4) a year; a
// grown child at work moves out on marrying; the old die. Medieval in its numbers (data/households.json).
// Freeciv owns how big a town is; this owns who lives in it: newcomers arrive as a town grows, households move
// away as it shrinks, and famine and plague (Freeciv's own) kill more. The one owner of every commoner, kept
// with the reign (state/households.json); townsfolk.js draws the walking crowd from it, minds.js their minds.
import fs from "node:fs";
import path from "node:path";
import { cityName } from "./narrator.js";
import { SEASONS_PER_YEAR, calendar } from "./calendar.js";

const H = JSON.parse(fs.readFileSync(new URL("./data/households.json", import.meta.url), "utf8"));

const MEN = ["Alfred", "Aldo", "Bertram", "Colin", "Dudley", "Ellis", "Fulk", "Gilbert", "Hamo", "Ivo", "Jocelin", "Lambert", "Martin", "Nicol", "Odo", "Piers", "Ralph", "Simon", "Thurstan", "Walter", "Wat", "Hob", "Dick", "Jack", "Robin", "Tom", "Adam", "Geoffrey", "Hugh", "Roger", "Reynold", "Stephen", "Warin", "Osbert", "Herbert", "Jordan"];
const WOMEN = ["Ada", "Alice", "Avice", "Beatrice", "Cecily", "Christina", "Dulcia", "Emma", "Eva", "Felice", "Hawise", "Isabel", "Juliana", "Lettice", "Mabel", "Margery", "Matilda", "Nichola", "Petronilla", "Rose", "Sabina", "Sybil", "Tiffany", "Wymarc", "Agnes", "Joan", "Maud", "Edith", "Amice", "Idonea", "Godith", "Annora"];
const SURNAMES = ["Miller", "Smith", "Cooper", "Ward", "Fletcher", "Baker", "Thatcher", "Webb", "Hayward", "Shepherd", "Fisher", "Brewer", "Carter", "Wood", "Brook", "Hill", "Green", "Dale", "Ashby", "Underwood", "Reeve", "Marsh", "Holt", "Ford", "Lane", "Croft", "Woolley", "Pyke"];
const TRADES = [
  ["farmer", 6], ["shepherd", 2], ["miller", 1], ["baker", 1], ["brewer", 1], ["smith", 1], ["carpenter", 1],
  ["weaver", 1], ["tanner", 1], ["potter", 1], ["fisher", 2], ["woodcutter", 1], ["carter", 1], ["midwife", 1],
  ["alewife", 2], ["innkeeper", 1], ["tavern girl", 1], ["thatcher", 1], ["friar", 1], ["hedge witch", 1], ["cooper", 1], ["swineherd", 1], ["beggar", 1], ["washerwoman", 1],
];
// Some trades were women's; a man of the same house does the man's version (and the other way).
const AS_MAN = { alewife: "brewer", "tavern girl": "potboy", washerwoman: "fuller", midwife: "barber", "hedge witch": "cunning man" };
const AS_WOMAN = { priest: "prioress", friar: "anchoress" };
const AS_SURNAME = ["miller", "smith", "baker", "brewer", "carter", "cooper", "fisher", "shepherd", "thatcher", "weaver", "potter", "tanner", "carpenter"];
const PASTS = [
  "came to {town} as a child after the famine emptied {their} village",
  "fought in a lord's levy once and won't speak of it",
  "owes the miller more than {they} can repay",
  "was born in {town} and has never been further than the market at the next town",
  "ran away from a harsh master in another house's lands and kept {their} head down since",
  "once saw the King's riders pass and tells everyone about it",
  "lost a brother to the sea and won't set foot in a boat",
  "is said to have the best {trade}'s hands in {town}",
  "keeps bees behind the cottage and sells the honey at market",
  "argued with the reeve over a field boundary for eleven years and finally won",
  "can read a little, taught by a wandering friar",
  "sings in the alehouse on feast days and is not as good as {they} think",
  "is saving every penny to buy a plough ox",
  "nursed half of {town} through the last fever and is owed a great many favours",
  "lost a hand in the mill-wheel and learned to work with the other",
  "came back from a pilgrimage changed, and gives to every beggar",
];
// Every town has its characters; the first grown folk of a town take them.
const TOWN_TYPES = ["a gossip", "a drunkard", "a miser"];
const NATURES = ["a gossip", "a drunkard", "a miser", "a busybody", "pious", "quarrelsome", "kind-hearted", "lazy", "cheerful",
  "proud", "sharp-tongued", "superstitious", "a hard worker", "shy", "boastful", "jealous", "generous", "sly", "gentle"];
const YOUNG = ["shy", "cheerful", "lazy", "boastful", "a hard worker", "gentle", "sly", "kind-hearted"];
const WANTS = ["a good harvest", "to see {their} daughter married well", "to pay off the debt", "a warm winter", "peace, and the tithe lowered",
  "to be left alone", "a son to take on the trade", "a strip of land of {their} own", "to see the sea once", "revenge on the bailiff"];

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const chance = (p) => Math.random() < p;
function trade() {
  let roll = Math.random() * TRADES.reduce((t, [, w]) => t + w, 0);
  for (const [name, w] of TRADES) if ((roll -= w) < 0) return name;
  return "farmer";
}
const asSex = (t, woman) => (woman ? AS_WOMAN[t] ?? t : AS_MAN[t] ?? t);
const plainTrade = (t) => Object.entries({ ...AS_MAN, ...AS_WOMAN }).find(([, v]) => v === t)?.[0] ?? t;

let S = null;     // { seq, towns: {cityId: {size, turn}}, homes: {hid: {id, town, surname}}, people: {pid: person} }
let FILE = null;
let timer = null;

// Open the reign's households (server.js, as each reign opens), writing the last reign's first.
export function open(stateDir) {
  if (timer) flush();
  FILE = path.join(stateDir, "households.json");
  try { S = JSON.parse(fs.readFileSync(FILE, "utf8")); } catch { S = null; }
  S ??= { seq: 0, towns: {}, homes: {}, people: {} };
}
function flush() {
  clearTimeout(timer);
  timer = null;
  if (FILE && S) try { fs.writeFileSync(FILE, JSON.stringify(S)); } catch { /* the next season writes it */ }
}
const save = () => { if (!timer) timer = setTimeout(flush, 30000); };

const years = (p, turn) => Math.floor((turn - p.born) / SEASONS_PER_YEAR);
const living = (town) => Object.values(S.people).filter((p) => p.town === town && !p.died && !p.gone);
const homesOf = (town) => Object.values(S.homes).filter((h) => h.town === town);
const membersOf = (hid) => Object.values(S.people).filter((p) => p.home === hid && !p.died && !p.gone);
const note = (p, turn, text) => { p.life = [...(p.life ?? []), `${calendar(turn).season} ${calendar(turn).year}: ${text}`].slice(-H.lifeKept); };

// One person, born (or arrived) into a home. Their nature, past and want are theirs for life.
function person(town, home, { woman, age, surname, trade: t, turn, parents = [], past = null, nature = null }) {
  const id = `f${++S.seq}`;
  const used = new Set(living(town).map((x) => x.first));
  const pool = (woman ? WOMEN : MEN).filter((n) => !used.has(n));
  const first = pick(pool.length ? pool : woman ? WOMEN : MEN);
  const words = { they: woman ? "she" : "he", their: woman ? "her" : "his", town: cityName(town) ?? "the town", trade: t ?? "farmer" };
  const fill = (s) => s.replace(/\{(\w+)\}/g, (_, k) => words[k] ?? "");
  const p = { id, i: null, town, first, surname, woman, born: turn - age * SEASONS_PER_YEAR - Math.floor(Math.random() * SEASONS_PER_YEAR),
    died: null, gone: null, spouse: null, wed: null, widowed: null, parents, home, trade: age >= H.work ? (t ?? trade()) : null,
    nature: nature ?? pick(age < 18 ? YOUNG : NATURES), past: past ?? fill(pick(PASTS)), wants: fill(pick(WANTS)), life: [] };
  S.people[id] = p;
  if (age >= H.work) p.i = slotFor(town);
  return p;
}

// A grown person's place in their town's crowd (townsfolk.js i, the view's walker and minds.js's key): the lowest
// no living grown neighbour holds; each season the places close up (townSeason), so the crowd's places stay
// 0..n-1 as the view counts them.
function slotFor(town) {
  const held = new Set(living(town).map((x) => x.i).filter((i) => i != null));
  let i = 0;
  while (held.has(i)) i++;
  return i;
}

function home(town, surname) {
  const id = `h${++S.seq}`;
  S.homes[id] = { id, town, surname };
  return id;
}

// A household come to town (seeding, or newcomers as the town grows): a couple most often, their children
// spaced by the years they've been wed, sometimes an old parent; a widow or widower otherwise.
function arrive(town, turn, newcomer) {
  const t = trade();
  const surname = AS_SURNAME.includes(plainTrade(t)) && chance(0.5) ? t[0].toUpperCase() + t.slice(1) : pick(SURNAMES);
  const hid = home(town, surname);
  const age = 22 + Math.floor(Math.random() * 34);
  const past = newcomer ? `came to ${cityName(town) ?? "the town"} not long ago, looking for work` : null;
  const married = chance(H.seed.married);
  const alone = !married && chance(0.5);  // a widow keeps the house as often as a widower
  const head = person(town, hid, { woman: alone, age, surname, trade: asSex(t, alone), turn, past });
  if (married) {
    const wife = person(town, hid, { woman: true, age: Math.max(H.marry.age, age - 1 - Math.floor(Math.random() * 7)), surname, trade: asSex(t, true), turn });
    const wedYears = Math.max(0, years(wife, turn) - H.marry.age - Math.floor(Math.random() * 4));
    head.spouse = wife.id; wife.spouse = head.id; head.wed = wife.wed = turn - wedYears * SEASONS_PER_YEAR;
    for (let y = wedYears - 1; y >= 0; y -= 2 + Math.floor(Math.random() * 2)) {
      if (chance(H.seed.childEvery)) person(town, hid, { woman: chance(0.5), age: y, surname, trade: asSex(t, false), turn, parents: [head.id, wife.id] });
    }
  } else head.widowed = turn - SEASONS_PER_YEAR * (1 + Math.floor(Math.random() * 6));
  if (chance(H.seed.elder)) person(town, hid, { woman: chance(0.6), age: 58 + Math.floor(Math.random() * 14), surname, trade: asSex(t, false), turn });
  return hid;
}

// How many households a town of its size holds (Freeciv's size: data/households.json perSize, min, max).
const target = (size) => Math.max(H.min, Math.min(H.max, Math.round(H.base + size * H.perSize)));

function die(p, turn, why) {
  p.died = turn;
  const spouse = S.people[p.spouse];
  if (spouse && !spouse.died) { spouse.widowed = turn; spouse.spouse = null; note(spouse, turn, `buried ${spouse.woman ? "her husband" : "his wife"} ${p.first}${why ? `, taken by ${why}` : ""}`); }
  for (const pid of p.parents) { const q = S.people[pid]; if (q && !q.died) note(q, turn, `buried ${p.woman ? "a daughter" : "a son"}, ${p.first}`); }
}

// A town's season: deaths, children grown to a trade, weddings, births, and newcomers or leavers to its size.
function townSeason(c, turn) {
  const town = c.id;
  const t = (S.towns[town] ??= { size: c.size, turn: null });
  if (t.turn === turn) return;
  if (!homesOf(town).length) {
    // The town's first season in the reign: its priest, then its households.
    const hid = home(town, "");
    person(town, hid, { woman: false, age: 30 + Math.floor(Math.random() * 30), surname: "", trade: "priest", turn, nature: pick(["pious", "kind-hearted", "sharp-tongued", "a hard worker"]) });
    for (let k = 0; k < target(c.size); k++) arrive(town, turn, false);
    living(town).filter((p) => years(p, turn) >= 18 && p.trade !== "priest").slice(0, TOWN_TYPES.length).forEach((p, k) => { p.nature = TOWN_TYPES[k]; });
    t.turn = turn; t.size = c.size;
    return;
  }
  // Famine and plague (Freeciv's own: the town shrank, or is starving or sick now) take more of the weak.
  const hard = c.size < t.size || c.famine || c.plague ? H.hard : 1;
  const why = c.plague ? "the sickness" : c.famine || c.size < t.size ? "hunger" : null;
  for (const p of living(town)) {
    const age = years(p, turn);
    const yearly = H.death.find(([under]) => age < under)?.[1] ?? H.death.at(-1)[1];
    const weak = age < 5 || age >= 55 ? hard : Math.sqrt(hard);
    if (chance(Math.min(0.9, yearly * weak / SEASONS_PER_YEAR))) die(p, turn, weak > 1 ? why : null);
  }
  // Grown to working age: the parent's trade most often, else one of the town's.
  for (const p of living(town)) if (!p.trade && years(p, turn) >= H.work) {
    const parent = S.people[p.parents[p.woman ? 1 : 0]] ?? S.people[p.parents[0]];
    p.trade = asSex(parent?.trade && chance(H.followTrade) ? plainTrade(parent.trade) : trade(), p.woman);
    p.i = slotFor(town);
    note(p, turn, `took up the ${p.trade}'s work`);
  }
  // Weddings (Talk of the Town: singles of age wed; a widow or widower at 1 / (years married + 4) a year).
  const free = (p) => !p.spouse && years(p, turn) >= H.marry.age && years(p, turn) < H.marry.until && p.trade !== "priest"
    && (!p.widowed || chance(1 / ((turn - p.widowed) / SEASONS_PER_YEAR + H.remarry) / SEASONS_PER_YEAR));
  const men = living(town).filter((p) => !p.woman && free(p)).sort(() => Math.random() - 0.5);
  const women = living(town).filter((p) => p.woman && free(p));
  for (const m of men) {
    if (!chance(H.marry.chance)) continue;
    const kin = (a, b) => a.home === b.home || a.parents.some((x) => b.parents.includes(x));
    const w = women.filter((x) => !x.spouse && !kin(m, x)).sort((a, b) => Math.abs(years(a, turn) + 3 - years(m, turn)) - Math.abs(years(b, turn) + 3 - years(m, turn)))[0];
    if (!w) continue;
    m.spouse = w.id; w.spouse = m.id; m.wed = w.wed = turn; m.widowed = w.widowed = null;
    const takes = chance(H.marry.takesName) ? w : m;
    const giver = takes === w ? m : w;
    // A widower with children keeps his home and she comes to it; a new couple moves out (Talk of the Town).
    const keeps = [m, w].find((x) => membersOf(x.home).some((k) => k.parents.includes(x.id)));
    const hid = keeps ? keeps.home : home(town, giver.surname);
    for (const x of [m, w]) {
      x.home = hid;
      note(x, turn, `married ${x === m ? w.first : m.first} ${x === takes ? giver.surname : x.surname}`.trim());
    }
    takes.surname = giver.surname;
  }
  // Births: a married couple try for a child at perYear / (children + 1) a year while she can bear.
  for (const w of living(town).filter((p) => p.woman && p.spouse)) {
    const m = S.people[w.spouse];
    const age = years(w, turn);
    if (!m || m.died || m.gone || age < H.conceive.from || age > H.conceive.to) continue;
    const kids = Object.values(S.people).filter((k) => k.parents.includes(w.id)).length;
    if (!chance(H.conceive.perYear / (kids + 1) / SEASONS_PER_YEAR)) continue;
    const child = person(town, w.home, { woman: chance(0.5), age: 0, surname: w.surname, trade: null, turn, parents: [m.id, w.id] });
    child.born = turn;
    for (const x of [m, w]) note(x, turn, `had ${child.woman ? "a daughter" : "a son"}, ${child.first}`);
  }
  // Freeciv's size: newcomers as the town grows, a household moving away as it shrinks (one a season).
  const want = target(c.size);
  const homes = homesOf(town).filter((h) => membersOf(h.id).length);
  if (homes.length < want) arrive(town, turn, true);
  else if (homes.length > want + H.slack) {
    const leaving = homes.filter((h) => h.surname).sort((a, b) => membersOf(a.id).length - membersOf(b.id).length)[0];
    if (leaving) for (const p of membersOf(leaving.id)) p.gone = turn;
  }
  // Homes nobody lives in any more are let go.
  for (const h of homesOf(town)) if (!membersOf(h.id).length) delete S.homes[h.id];
  // The crowd's places close up over the dead and departed, in their order, so they stay 0..n-1 (minds.js moves
  // each mind with its person).
  living(town).filter((p) => p.i != null).sort((a, b) => a.i - b.i).forEach((p, k) => { p.i = k; });
  t.turn = turn; t.size = c.size;
}

// The season (season.js, after the world is read): every town's households take their step. Towns no longer on
// the map lose their folk with them.
export function season(world, turn) {
  if (!S || !world?.cities) return;
  for (const c of world.cities) townSeason(c, turn);
  const here = new Set(world.cities.map((c) => c.id));
  for (const p of Object.values(S.people)) if (!here.has(p.town) && !p.died && !p.gone) p.gone = turn;
  // The long dead are let go (their names stay in the living's memories): the store keeps to the reign's folk.
  for (const [id, p] of Object.entries(S.people)) if ((p.died ?? p.gone) != null && turn - (p.died ?? p.gone) > H.forgetAfter) delete S.people[id];
  save();
}

// A town's living folk, the town's own first season made if it has none yet (the crowd and the minds ask before a
// season has passed), each with their age and their household's ties, by place (children have none yet).
export function folkOf(city, turn) {
  if (!S) return [];
  if (!S.towns[city.id] || !homesOf(city.id).length) { townSeason(city, turn); save(); }
  return living(city.id).sort((a, b) => a.i - b.i).map((p) => ({ ...p, age: years(p, turn), spouseOf: S.people[p.spouse] ?? null,
    kids: Object.values(S.people).filter((k) => k.parents.includes(p.id) && !k.died && !k.gone).length,
    dead: Object.values(S.people).filter((k) => k.parents.includes(p.id) && k.died != null).length }));
}
