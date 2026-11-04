// The common folk of each town: named, with a trade, a family and a little
// history, so a walking villager is somebody when you look closer. They live
// beside the story, never in it: they don't act, petition or reach the
// chronicle, and they're generated from the town's id, so nothing to track.

import { cityName } from "./narrator.js";

const MEN = ["Alfred", "Aldo", "Bertram", "Colin", "Dudley", "Ellis", "Fulk", "Gilbert", "Hamo", "Ivo", "Jocelin", "Lambert", "Martin", "Nicol", "Odo", "Piers", "Ralph", "Simon", "Thurstan", "Walter", "Wat", "Hob", "Dick", "Jack", "Robin", "Tom"];
const WOMEN = ["Ada", "Alice", "Avice", "Beatrice", "Cecily", "Christina", "Dulcia", "Emma", "Eva", "Felice", "Hawise", "Isabel", "Juliana", "Lettice", "Mabel", "Margery", "Matilda", "Nichola", "Petronilla", "Rose", "Sabina", "Sybil", "Tiffany", "Wymarc"];
const TRADES = [
  ["farmer", 6], ["shepherd", 2], ["miller", 1], ["baker", 1], ["brewer", 1], ["smith", 1], ["carpenter", 1],
  ["weaver", 1], ["tanner", 1], ["potter", 1], ["fisher", 2], ["woodcutter", 1], ["carter", 1], ["midwife", 1],
  ["alewife", 2], ["innkeeper", 1], ["tavern girl", 1], ["thatcher", 1], ["friar", 1], ["hedge witch", 1], ["cooper", 1], ["swineherd", 1], ["beggar", 1], ["washerwoman", 1],
];
const PASTS = [
  "came to {town} as a child after the famine emptied {their} village",
  "lost {their} first {spouse} to the coughing sickness one hard winter",
  "fought in a lord's levy once and won't speak of it",
  "owes the miller more than {they} can repay",
  "was born in {town} and has never been further than the market at the next town",
  "ran away from a harsh master in another house's lands and kept {their} head down since",
  "once saw the King's riders pass and tells everyone about it",
  "lost a brother to the sea and won't set foot in a boat",
  "is said to have the best {trade}'s hands in {town}",
  "buried three children and raised five",
  "keeps bees behind the cottage and sells the honey at market",
  "argued with the reeve over a field boundary for eleven years and finally won",
  "was a soldier's widow at twenty and remarried at twenty-two",
  "can read a little, taught by a wandering friar",
  "sings in the alehouse on feast days and is not as good as {they} think",
  "is saving every penny to buy a plough ox",
  "nursed half of {town} through the last fever and is owed a great many favours",
  "lost a hand in the mill-wheel and learned to work with the other",
  "is quietly courting the {otherTrade}'s {otherKin}",
  "came back from a pilgrimage changed, and gives to every beggar",
];
// Every town has its characters; the first few are guaranteed in each town.
const TOWN_TYPES = ["flirtatious", "a gossip", "a drunkard", "a miser"];
const NATURES = [
  "flirtatious", "a gossip", "a drunkard", "a miser", "a busybody", "pious", "quarrelsome", "kind-hearted", "lazy", "cheerful",
  "proud", "sharp-tongued", "superstitious", "a hard worker", "shy", "boastful", "jealous", "generous", "sly", "gentle",
];
const WANTS = [
  "a good harvest", "to see {their} daughter married well", "to pay off the debt", "a warm winter", "peace, and the tithe lowered",
  "to be left alone", "a son to take on the trade", "a strip of land of {their} own", "to see the sea once", "revenge on the bailiff",
];

function rng(seed) {
  let s = seed >>> 0 || 1;
  return () => {
    s = (Math.imul(s ^ (s >>> 15), 2246822507) + 0x9e3779b9) >>> 0;
    s = Math.imul(s ^ (s >>> 13), 3266489909) >>> 0;
    return ((s ^ (s >>> 16)) >>> 0) / 4294967296;
  };
}

const pick = (arr, r) => arr[Math.floor(r() * arr.length)];

function trade(r) {
  const total = TRADES.reduce((t, [, w]) => t + w, 0);
  let roll = r() * total;
  for (const [name, w] of TRADES) if ((roll -= w) < 0) return name;
  return "farmer";
}

// The folk of a town: as many as its walking crowd, so each villager on screen
// can be one of them. Stable for a town of a given size.
export function townsfolk(city) {
  const r = rng(city.id * 7919 + 13);
  const town = cityName(city.id) ?? city.name;
  const count = Math.min(54, Math.max(8, 6 + city.size * 5));
  const surnames = ["Miller", "Smith", "Cooper", "Ward", "Fletcher", "Baker", "Thatcher", "Webb", "Hayward", "Shepherd", "Fisher", "Brewer", "Carter", "Wood", "Brook", "Hill", "Green", "Dale", "Ashby", "Underwood"];
  const folk = [];
  for (let i = 0; i < count; i++) {
    const woman = r() < 0.5;
    // Some trades were women's; a man of the same house does the man's version.
    const AS_MAN = { alewife: "brewer", "tavern girl": "potboy", washerwoman: "fuller", midwife: "barber", "hedge witch": "cunning man" };
    const AS_WOMAN = { priest: "prioress", friar: "anchoress" };
    // Every town keeps a priest at its church; the rest of the folk are drawn by trade.
    const raw = i === 0 ? "priest" : trade(r);
    const t = woman ? AS_WOMAN[raw] ?? raw : AS_MAN[raw] ?? raw;
    // The priest and the town's stock characters are always grown.
    const age = (i <= TOWN_TYPES.length ? 20 : 14) + Math.floor(r() * (i <= TOWN_TYPES.length ? 46 : 52));
    // Trade surnames only where the trade really became a name (Miller, Smith…).
    const asSurname = ["miller", "smith", "baker", "brewer", "carter", "cooper", "fisher", "shepherd", "thatcher", "weaver", "potter", "tanner", "carpenter"].includes(t);
    const name = `${pick(woman ? WOMEN : MEN, r)} ${asSurname && r() < 0.5 ? t[0].toUpperCase() + t.slice(1) : pick(surnames, r)}`;
    const words = { they: woman ? "she" : "he", their: woman ? "her" : "his", spouse: woman ? "husband" : "wife", town, trade: t, otherTrade: trade(r), otherKin: pick(["daughter", "son", "widow", "sister"], r) };
    const fill = (s) => s.replace(/\{(\w+)\}/g, (_, k) => words[k] ?? "");
    const children = age > 22 ? Math.floor(r() * 5) : 0;
    const family = age < 18 ? "lives with " + words.their + " parents" : r() < 0.7 ? `married, ${children ? children + (children === 1 ? " child" : " children") : "no children yet"}` : r() < 0.5 ? "widowed" : "unmarried";
    let past = fill(pick(PASTS, r));
    if (family.startsWith("married") && past.includes("courting")) past = fill(PASTS[9]);
    // The town's stock characters go to grown folk first; everyone else gets a nature at random.
    const YOUNG = ["shy", "cheerful", "lazy", "boastful", "a hard worker", "gentle", "sly", "kind-hearted"];
    const nature = i === 0 ? pick(["pious", "kind-hearted", "sharp-tongued", "secretly a drunkard", "a hard worker"], r) : i <= TOWN_TYPES.length ? TOWN_TYPES[i - 1] : pick(age < 18 ? YOUNG : NATURES, r);
    folk.push({
      i, name, age, woman, trade: t, nature,
      family,
      past,
      wants: fill(pick(WANTS, r)),
    });
  }
  return folk;
}
