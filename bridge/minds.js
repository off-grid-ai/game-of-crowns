// Minds: every person in Aldmere remembers, wants, feels and makes a plan for
// the day (docs/MINDS.md is the contract). Commoners become lasting minds,
// seeded from townsfolk.js, their tale and what they have said to you; the
// named keep their Court record and gain mood, beliefs, bonds and a plan here.
// The chronicle and what the 3D town shows become their memories; attention
// decides who thinks with the model and who goes by rules.

import fs from "node:fs";
import path from "node:path";
import { townsfolk } from "./townsfolk.js";
import { cityName, houseFor } from "./narrator.js";
import { calendar } from "./calendar.js";
import { think, modelQueue } from "./claude.js";

const FEELINGS = ["fear", "anger", "joy", "grief", "faith", "hunger"];
const CALM = { fear: 0.2, anger: 0.15, joy: 0.4, grief: 0.1, faith: 0.4, hunger: 0.2 };
// Each nature leans the resting mood its own way.
const NATURE_MOOD = {
  pious: { faith: 0.75 }, "secretly a drunkard": { joy: 0.5, faith: 0.5 }, "a drunkard": { joy: 0.5, hunger: 0.3 },
  quarrelsome: { anger: 0.4 }, "sharp-tongued": { anger: 0.3 }, jealous: { anger: 0.3, grief: 0.15 }, proud: { anger: 0.25, joy: 0.45 },
  superstitious: { fear: 0.4, faith: 0.55 }, shy: { fear: 0.35, joy: 0.3 }, "a miser": { fear: 0.3, joy: 0.3 },
  cheerful: { joy: 0.65 }, "kind-hearted": { joy: 0.5, faith: 0.5 }, gentle: { joy: 0.5, anger: 0.05 }, generous: { joy: 0.5 },
  boastful: { joy: 0.55 }, lazy: { joy: 0.45, hunger: 0.25 }, sly: { anger: 0.2 },
  "a gossip": { joy: 0.5 }, "a busybody": { anger: 0.2 }, "a hard worker": { joy: 0.4 },
  // The named, by their traits.
  vengeful: { anger: 0.4 }, wrathful: { anger: 0.45 }, paranoid: { fear: 0.45 }, craven: { fear: 0.45 }, brave: { fear: 0.08 },
  content: { joy: 0.55 }, ambitious: { anger: 0.25 }, greedy: { hunger: 0.3 }, honourable: { faith: 0.5 }, just: { faith: 0.5 },
};
const WHY = {
  "a good harvest": "a thin harvest means a hungry winter",
  "to pay off the debt": "the miller's man comes every quarter day",
  "a warm winter": "the last one took the old ones",
  "peace, and the tithe lowered": "the lord's men take more each year",
  "to be left alone": "people only come with trouble",
  "a strip of land of her own": "she has worked other folk's land all her life",
  "a strip of land of his own": "he has worked other folk's land all his life",
  "to see the sea once": "everyone speaks of it and it can't be all lies",
  "revenge on the bailiff": "the bailiff shamed the family before the whole town",
};
const TRADE_WANT = {
  farmer: ["to bring the harvest in dry", "a wet harvest rots in the stook"], shepherd: ["to keep the flock from the wolves", "every ewe lost is a winter's wool gone"],
  smith: ["iron that doesn't crack", "a bad blade is a dead customer"], baker: ["flour enough for the week", "an empty oven is an empty purse"],
  priest: ["to keep the flock in faith", "the sept is emptier every year"], prioress: ["to keep the flock in faith", "the sept is emptier every year"],
  innkeeper: ["full benches every night", "an empty tavern pays no rent"], alewife: ["a good brew for the feast day", "sour ale is talked of for a year"],
  beggar: ["a warm place to sleep", "the cold kills more than hunger"], fisher: ["calm water and full nets", "the sea takes what it likes"],
};

// Where each trade works, and what it looks like to someone passing.
const WORK = {
  farmer: ["field", "working the strip"], shepherd: ["field", "minding the flock"], swineherd: ["field", "driving the pigs to the wood"],
  woodcutter: ["field", "cutting wood"], fisher: ["field", "mending nets by the water"], thatcher: ["home", "thatching a roof"],
  miller: ["home", "at the mill"], baker: ["home", "baking"], brewer: ["tavern", "brewing"], smith: ["home", "at the forge"],
  carpenter: ["home", "at the bench, planing"], weaver: ["home", "at the loom"], tanner: ["home", "scraping hides"], potter: ["home", "at the wheel"],
  cooper: ["home", "hooping barrels"], fuller: ["well", "fulling cloth"], washerwoman: ["well", "washing linen"], carter: ["market", "loading the cart"],
  midwife: ["home", "seeing to a birth"], barber: ["market", "pulling teeth"], "hedge witch": ["home", "brewing simples"], "cunning man": ["home", "brewing simples"],
  alewife: ["tavern", "serving ale"], innkeeper: ["tavern", "keeping the inn"], "tavern girl": ["tavern", "carrying cups"], potboy: ["tavern", "carrying cups"],
  priest: ["sept", "keeping the sept"], prioress: ["sept", "keeping the sept"], friar: ["market", "preaching"], anchoress: ["sept", "at prayer"],
  beggar: ["market", "begging"],
};
const SOCIAL = new Set(["well", "market", "tavern", "bench", "sept"]);
const BONDS = [
  ["neighbour", 0.3, 0.35], ["drinks with them", 0.2, 0.5], ["owes them money", -0.2, -0.1], ["old quarrel over a boundary", -0.4, -0.5],
  ["sweet on them", 0.3, 0.7], ["cousin", 0.5, 0.4], ["works beside them", 0.4, 0.3], ["thinks them a fool", -0.1, -0.3],
];
const BELIEFS = {
  superstitious: "a hare crossing the road means a death in the house", pious: "the Seven hear every prayer said in the sept",
  "a gossip": "the reeve's wife is not as faithful as she looks", "a miser": "a penny spent is a penny the bailiff can't take",
};

// How much a kind of happening matters to common folk, and how it moves them.
const WEIGHT = {
  plague: 0.95, famine: 0.85, razed: 1, sack: 0.9, city_transferred: 0.8, city_destroyed: 1, battle: 0.55, unit_killed: 0.4,
  tithe: 0.7, rebellion: 0.6, rebel: 0.6, unrest: 0.35, raid: 0.6, outlaws: 0.45, death: 0.35, succession: 0.35, marriage: 0.3,
  feast: 0.45, bounty: 0.6, arc: 0.5, grain: 0.5, faith: 0.4, decree: 0.3, justice: 0.3, war: 0.6, peace: 0.5, talk: 0.65, visit: 0.6, rider: 0.25,
};
const MOVES = {
  plague: { fear: 0.4, grief: 0.3, faith: 0.1 }, famine: { hunger: 0.45, fear: 0.2 }, razed: { fear: 0.5, grief: 0.4, anger: 0.2 },
  sack: { fear: 0.45, grief: 0.25, anger: 0.2 }, city_transferred: { fear: 0.3, anger: 0.15 }, battle: { fear: 0.3, grief: 0.1 },
  unit_killed: { fear: 0.15 }, tithe: { anger: 0.3, fear: 0.15, hunger: 0.15 }, rebellion: { fear: 0.2, anger: 0.15 },
  unrest: { anger: 0.15 }, raid: { fear: 0.35, anger: 0.2 }, outlaws: { fear: 0.25 }, death: { grief: 0.15 }, marriage: { joy: 0.2 },
  feast: { joy: 0.35 }, bounty: { joy: 0.35, faith: 0.15, hunger: -0.3 }, grain: { hunger: -0.3, joy: 0.15 }, faith: { faith: 0.25 },
  peace: { joy: 0.2, fear: -0.15 }, war: { fear: 0.3 }, visit: { joy: 0.15 },
};

const NEAR = { here: 1, lands: 0.5, realm: 0.22 };
const CAP = 16;
const HOT_MS = 60000;
const SPOKEN_MS = 5 * 60000;

function hash(s) {
  let h = 2166136261;
  for (const ch of String(s)) h = Math.imul(h ^ ch.charCodeAt(0), 16777619) >>> 0;
  return h;
}
const clamp = (v, lo = 0, hi = 1) => Math.max(lo, Math.min(hi, v));
const round = (m) => Object.fromEntries(FEELINGS.map((k) => [k, Math.round(m[k] * 100) / 100]));
const firstSentence = (t) => (String(t).match(/^[^.!?]+[.!?]?/)?.[0] ?? String(t)).trim();

// The block of the day an hour falls in, as the town in villagers.gd counts it.
function block(h) {
  if (h < 5.5 || h >= 21.5) return ["night", h < 5.5 ? 5.5 : 29.5];
  if (h < 7) return ["dawn", 7];
  if (h < 12) return ["work", 12];
  if (h < 13) return ["meal", 13];
  if (h < 18) return ["work2", 18];
  return ["evening", 21.5];
}

// Their past, as townsfolk.js tells it of them, in their own mouth.
function mine(past) {
  return past
    .replace(/^is /, "am ").replace(/^has /, "have ").replace(/^(?!was )(\w+?)s /, "$1 ")
    .replace(/ and (is|gives) /, (_, v) => ` and ${v === "is" ? "am" : "give"} `)
    .replace(/\b(his|her)\b/g, "my").replace(/\b(he|she)\b/g, "I");
}

// Without an hour from the town, a day of the 3D town's length (240 s) on the clock.
const clockHour = () => ((Date.now() / 1000) % 240) / 240 * 24;

export class Minds {
  // `realm` gives the live realm: world(), court(), chronicle(), tithe(), town(id) -> { plague, famine }.
  constructor(stateDir, realm) {
    this.file = path.join(stateDir, "minds.json");
    this.dir = stateDir;
    this.realm = realm;
    const saved = fs.existsSync(this.file) ? JSON.parse(fs.readFileSync(this.file, "utf8")) : {};
    this.minds = saved.minds ?? {};
    this.seen = saved.seen ?? { seq: null, tithe: null, turn: 0 };
    this.hot = {};      // id -> until (ms)
    this.warm = {};     // city -> until (ms)
    this.hours = {};    // city -> { hour, at } as the town last told us
    this.thinking = new Set();
    this.timer = null;
  }

  // Everyone's minds run to many megabytes: written at most every half minute
  // (and on shutdown), not on every change, so the realm never stalls to save.
  save() {
    if (this.timer) return;
    this.timer = setTimeout(() => this.flush(), 30000);
  }

  flush() {
    clearTimeout(this.timer);
    this.timer = null;
    fs.writeFileSync(this.file, JSON.stringify({ minds: this.minds, seen: this.seen }));
  }

  now() {
    return this.realm.world()?.turn ?? 0;
  }

  // --- the store ---------------------------------------------------------------

  // Every commoner of a town as a mind, made the first time it's needed.
  town(cityId) {
    const city = this.realm.world()?.cities?.find((c) => c.id === Number(cityId));
    if (!city) return null;
    const folk = townsfolk(city);
    const out = folk.map((p) => this.minds[`folk:${city.id}:${p.i}`] ?? this.seedFolk(city, p, folk));
    return { city, folk, minds: out };
  }

  // Minds for the whole realm's commoners, so news reaches towns nobody has opened.
  everyone() {
    for (const c of this.realm.world()?.cities ?? []) this.town(c.id);
  }

  seedFolk(city, p, folk) {
    const id = `folk:${city.id}:${p.i}`;
    const base = { ...CALM, ...(NATURE_MOOD[p.nature] ?? {}) };
    const r = hash(id);
    const tradeWant = TRADE_WANT[p.trade];
    const wants = [{ text: p.wants, why: WHY[p.wants] ?? "it's all I've ever asked for" }];
    if (tradeWant && tradeWant[0] !== p.wants) wants.push({ text: tradeWant[0], why: tradeWant[1] });
    // Two or three people in town they are bound to, for better or worse.
    const bonds = {};
    for (let k = 0; k < 2 + (r % 2); k++) {
      const j = (p.i + 1 + ((r >>> (k * 5)) % (folk.length - 1))) % folk.length;
      const [note, trust, warmth] = BONDS[(r >>> (k * 3 + 1)) % BONDS.length];
      if (j !== p.i) bonds[`folk:${city.id}:${j}`] = { trust, warmth, note };
    }
    const m = {
      id, name: p.name, town: city.id, station: p.trade, sex: p.woman ? "female" : "male", age: p.age, i: p.i,
      nature: [p.nature], wants, base, mood: { ...base }, memories: [], life: "", bonds,
      beliefs: BELIEFS[p.nature] ? [BELIEFS[p.nature]] : [], plan: null, reverie: 0, born: this.now(),
    };
    m.memories.push({ turn: 0, text: `I ${mine(p.past)}.`, about: [], weight: 0.6, kind: "past" });
    // Their tale, once the model wrote it, is their life so far.
    const tales = this.read("folk-tales.json");
    const talks = this.read("talks.json");
    const key = `v2:${city.id}:${p.i}:${p.name}`;
    if (tales[key]?.story) m.life = tales[key].story;
    for (let k = 0; k + 1 < (talks[key] ?? []).length; k += 2) {
      const [said, reply] = [talks[key][k], talks[key][k + 1]];
      m.memories.push({ turn: m.born, text: `${said.who} said to me: "${said.text.slice(0, 100)}" I told them: "${reply.text.slice(0, 80)}"`, about: [said.who], weight: 0.65, kind: "talk" });
    }
    this.minds[id] = m;
    this.save();
    return m;
  }

  read(name) {
    try {
      return JSON.parse(fs.readFileSync(path.join(this.dir, name), "utf8"));
    } catch {
      return {};
    }
  }

  // A named person's mind: their Court record stays the source of who they are.
  named(courtId) {
    const c = this.realm.court()?.people?.[courtId];
    if (!c) return null;
    if (!this.minds[courtId]) {
      const base = { ...CALM };
      for (const t of c.traits ?? []) Object.assign(base, NATURE_MOOD[t] ?? {});
      this.minds[courtId] = {
        id: courtId, name: c.name, town: c.seat ?? null, station: c.rank, sex: c.gender, age: c.age, nature: c.traits ?? [],
        wants: (c.goals ?? []).slice(0, 3).map((g) => ({ text: g.text, why: g.why ?? "" })), base, mood: { ...base },
        memories: [], life: "", bonds: {}, beliefs: [], plan: null, reverie: 0, born: this.now(),
      };
      this.save();
    }
    return this.minds[courtId];
  }

  get(id) {
    id = String(id);
    if (this.minds[id]) return this.minds[id];
    const folk = id.match(/^folk:(\d+):(\d+)$/);
    if (folk) return this.town(folk[1])?.minds[Number(folk[2])] ?? null;
    return this.named(id);
  }

  // --- memory and mood ---------------------------------------------------------

  // A memory, weighted; the faintest old ones fold into their life so far.
  remember(m, text, { about = [], weight = 0.5, kind = "", moves = null, turn = this.now() } = {}) {
    if (typeof m === "string") m = this.get(m);
    if (!m || m.memories.some((x) => x.text === text)) return;
    m.memories.push({ turn, text, about, weight: Math.round(clamp(weight) * 100) / 100, kind });
    if (moves) this.feel(m, moves, weight);
    // Something terrible leaves a mark: they rest a little more afraid, or grieving, ever after.
    if (moves && weight >= 0.5) for (const [k, v] of Object.entries(moves)) if (v > 0 && ["fear", "grief", "anger"].includes(k)) m.base[k] = clamp(m.base[k] + v * weight * 0.25, 0, 0.6);
    m.reverie = clamp(m.reverie + weight * 0.01);
    while (m.memories.length > CAP) this.fold(m);
    this.save();
  }

  // Strength now: weight fading with the seasons, talk with you fading slowest.
  strength(x, turn) {
    const age = Math.max(0, turn - x.turn);
    return x.weight * Math.pow(x.kind === "talk" || x.kind === "past" ? 0.995 : 0.97, age);
  }

  fold(m) {
    const turn = this.now();
    let low = 0;
    for (let k = 1; k < m.memories.length; k++) if (this.strength(m.memories[k], turn) < this.strength(m.memories[low], turn)) low = k;
    const [gone] = m.memories.splice(low, 1);
    const bit = firstSentence(gone.text).replace(/[.!?]$/, "").slice(0, 70);
    const parts = m.life ? m.life.split(" · ") : [];
    // The model-told tale stays first; folded memories follow, the newest five.
    const tale = parts.length && parts[0].length > 90 ? [parts.shift()] : [];
    m.life = [...tale, ...[...parts, bit].slice(-5)].join(" · ");
    m.reverie = clamp(m.reverie + 0.005);
  }

  // Each new blow moves them less the further it already has: fear on fear saturates.
  feel(m, moves, weight = 1) {
    for (const [k, v] of Object.entries(moves)) if (k in m.mood) m.mood[k] = clamp(m.mood[k] + v * weight * (v > 0 ? 1 - m.mood[k] : m.mood[k]));
  }

  // Each season: mood drifts back toward their nature, and the town's state weighs on it.
  season(m, place) {
    for (const k of FEELINGS) m.mood[k] += (m.base[k] - m.mood[k]) * 0.15;
    if (place?.famine) m.mood.hunger = clamp(Math.max(m.mood.hunger, 0.7));
    if (place?.plague) m.mood.fear = clamp(Math.max(m.mood.fear, 0.6));
    // The town's mood and danger (the bridge's one definitions) weigh on everyone in it.
    if (place?.mood === "riot") m.mood.anger = clamp(Math.max(m.mood.anger, 0.6));
    if (place?.mood === "feast") m.mood.joy = clamp(Math.max(m.mood.joy, 0.7));
    if (place?.besieged) m.mood.fear = clamp(Math.max(m.mood.fear, 0.6));
    // New wants rise from what they've lived through lately.
    const recent = m.memories.filter((x) => this.now() - x.turn <= 8 && x.weight >= 0.4);
    const need = recent.some((x) => x.kind === "plague") ? { text: "to keep the sickness from my door", why: "I saw the carts go by" }
      : recent.some((x) => x.kind === "famine") || m.mood.hunger > 0.65 ? { text: "bread enough for the winter", why: "the stores are near empty" }
      : recent.some((x) => x.kind === "tithe") ? { text: "to keep back enough of the harvest", why: "the crown takes more than it did" } : null;
    if (need && !m.wants.some((w) => w.text === need.text)) m.wants = [need, ...m.wants].slice(0, 3);
  }

  tick(turn) {
    if (turn === this.seen.turn) return;
    this.everyone();
    // A change in the King's tithe is felt in every house in the realm.
    const tithe = this.realm.tithe();
    if (this.seen.tithe !== null && tithe > this.seen.tithe + 0.001) {
      this.hearRealm({ kind: "tithe", text: `The crown has raised the tithe to ${Math.round(tithe * 100)} in the hundred.` }, NEAR.here);
    } else if (this.seen.tithe !== null && tithe < this.seen.tithe - 0.001) {
      this.hearRealm({ kind: "peace", text: `The crown has eased the tithe to ${Math.round(tithe * 100)} in the hundred.` }, NEAR.lands);
    }
    this.seen.tithe = tithe;
    const steps = this.seen.turn ? Math.min(8, Math.max(1, turn - this.seen.turn)) : 1;
    for (let s = 0; s < steps; s++) for (const m of Object.values(this.minds)) if (!m.gone) this.season(m, m.town != null ? this.realm.town(m.town) : null);
    this.seen.turn = turn;
    this.warmThoughts();
    this.save();
  }

  // --- perception --------------------------------------------------------------

  // On opening a realm: what happened since the minds last looked. A realm new
  // to minds starts them with its last few seasons' news.
  catchUp(chronicle) {
    const last = chronicle[chronicle.length - 1]?.seq ?? 0;
    if (this.seen.seq === null) this.seen.seq = Math.max(0, last - 30);
    for (const e of chronicle.filter((x) => x.seq > this.seen.seq)) this.perceive(e);
    this.seen.seq = last;
    this.save();
  }

  // A chronicle entry becomes memory for whoever was there or would hear of it.
  perceive(entry) {
    if (!entry?.text || entry.kind === "year") return;
    if (this.seen.seq !== null && entry.seq <= this.seen.seq) return;
    this.seen.seq = entry.seq;
    const world = this.realm.world();
    if (!world) return;
    const kind = /plague/i.test(entry.text) ? "plague" : /famine|drought|starv/i.test(entry.text) ? "famine" : /tithe/i.test(entry.text) && entry.kind !== "crown" ? "tithe"
      : entry.kind === "city_transferred" ? "sack" : entry.kind === "city_destroyed" ? "razed" : entry.kind;
    const base = WEIGHT[kind] ?? 0.25;
    // Where it happened: the entry's town, or a town named in it.
    const at = entry.city ?? world.cities.find((c) => entry.text.includes(cityName(c.id) ?? "\u0000"))?.id;
    const town = world.cities.find((c) => c.id === at);
    const house = town ? houseFor(world.players.find((p) => p.id === town.owner))?.name : world.players.map((p) => houseFor(p)?.name).find((h) => h && entry.text.includes(h.replace("House ", "")));
    this.everyone();
    // Those cast in a story's beat already remember it in their own words (arcs.js).
    const cast = new Set((entry.cast ?? []).map(String));
    for (const m of Object.values(this.minds)) {
      if (m.gone || cast.has(String(m.id))) continue;
      if (!String(m.id).startsWith("folk:") && !this.realm.court()?.people?.[m.id]?.alive) continue;
      const home = world.cities.find((c) => c.id === m.town);
      const mine = home ? houseFor(world.players.find((p) => p.id === home.owner))?.name : null;
      const near = town && m.town === town.id ? "here" : house && mine === house ? "lands" : "realm";
      const weight = base * NEAR[near];
      // Common folk hear little of the far realm: only the great happenings reach them.
      if (weight < 0.15) continue;
      const said = firstSentence(entry.text);
      const text = near === "here" ? `I was in ${cityName(town.id)} when it happened. ${entry.text}` : near === "lands" ? `Word came from ${town ? cityName(town.id) : "our lord's lands"}: ${said}` : `They say in the market: ${said}`;
      this.remember(m, text, { weight, kind, moves: MOVES[kind], turn: Number(entry.turn) || this.now() });
      this.believeOf(m, kind, near);
    }
  }

  // What the realm as a whole hears, at one closeness for everyone.
  hearRealm(ev, near) {
    for (const m of Object.values(this.minds)) {
      if (!String(m.id).startsWith("folk:") || m.gone) continue;
      this.remember(m, near === NEAR.here ? `${ev.text} We can scarce feed ourselves as it is.` : ev.text, { weight: (WEIGHT[ev.kind] ?? 0.4) * near, kind: ev.kind, moves: MOVES[ev.kind] });
      this.believeOf(m, ev.kind, "here");
    }
  }

  believeOf(m, kind, near) {
    const nature = m.nature.join(" ");
    const b = kind === "plague" && near === "here" ? (/superstitious|pious/.test(nature) ? "the sickness is a judgement on the lord's sins" : "the sickness came in on the traders' carts")
      : kind === "tithe" ? (m.mood.anger > 0.45 ? "the crown cares nothing for common folk" : "the King must need the coin for a war")
      : kind === "razed" || kind === "sack" ? "no lord can keep us safe" : null;
    if (b && !m.beliefs.includes(b)) m.beliefs = [...m.beliefs, b].slice(-5);
  }

  // What the 3D world showed them: a battle outside the walls, a rider, a feast, your visit.
  witness({ city, kind = "", text = "", who = [], at } = {}) {
    if (!text) return { error: "nothing to remember" };
    const t = this.town(city);
    if (!t) return { error: "no such town" };
    const ids = (who ?? []).map((x) => (typeof x === "number" || /^\d+$/.test(x) ? `folk:${t.city.id}:${x}` : String(x)));
    const saw = (ids.length ? ids.map((id) => this.get(id)).filter(Boolean) : t.minds).filter((m) => !m.gone);
    const weight = (WEIGHT[kind] ?? 0.4) * (ids.length ? 1 : 0.75);
    for (const m of saw) this.remember(m, `I saw it myself: ${text}`, { weight, kind, moves: MOVES[kind] });
    return { remembered: saw.length, at: at ?? this.now() };
  }

  // What others change in a mind (chatter.js, arcs): a bond nudged, a belief taken up.
  bond(id, other, { trust = 0, warmth = 0, note } = {}) {
    const m = this.get(id);
    if (!m) return;
    const b = (m.bonds[other] ??= { trust: 0, warmth: 0, note: note ?? "" });
    b.trust = clamp(b.trust + trust, -1, 1);
    b.warmth = clamp(b.warmth + warmth, -1, 1);
    if (note) b.note = note;
    this.save();
  }

  believe(id, { text, from } = {}) {
    const m = this.get(id);
    if (!m || !text || m.beliefs.includes(text)) return;
    m.beliefs = [...m.beliefs, text].slice(-5);
    if (from) this.remember(m, `${this.get(from)?.name ?? "Someone"} told me ${text}.`, { about: [from], weight: 0.35, kind: "gossip" });
    this.save();
  }

  // --- talk ----------------------------------------------------------------------

  // What a mind brings to a talk with you: how they feel, what they recall of you.
  forTalk(id, you) {
    const m = this.get(id);
    if (!m) return "";
    const of = m.memories.filter((x) => x.about.includes(you.id ?? you.name) || x.about.includes(you.name));
    const bond = m.bonds[you.id ?? you.name];
    const feel = this.feeling(m);
    const ago = of.length ? Math.max(0, this.now() - of[of.length - 1].turn) : null;
    return [
      `You feel ${feel} these days.`,
      m.memories.filter((x) => x.kind !== "talk").slice(-3).map((x) => x.text).join(" "),
      of.length ? `You have met ${you.name} before, ${ago < 1 ? "earlier this season" : ago === 1 ? "last season" : `${ago} seasons ago`}: ${of[of.length - 1].text}` : `You have never met ${you.name} before.`,
      bond ? `You ${bond.warmth > 0.2 ? "like" : bond.warmth < -0.2 ? "dislike" : "are wary of"} them${bond.trust < -0.2 ? " and don't trust them" : ""}.` : "",
      m.beliefs.length ? `You believe ${m.beliefs[m.beliefs.length - 1]}.` : "",
    ].filter(Boolean).join(" ");
  }

  // After a talk: they remember it, think better or worse of you, and it shows in their mood.
  talked(id, you, said, reply) {
    const m = this.get(id);
    if (!m) return;
    const key = you.id ?? you.name;
    const kind = /thank|bless|friend|help|gift|coin|bread|safe|kind|good/i.test(said) ? 1 : /hang|burn|kill|whip|fool|liar|thief|tax|curse|traitor/i.test(said) ? -1 : 0;
    const b = (m.bonds[key] ??= { trust: 0, warmth: 0, note: `spoke with them in ${cityName(m.town) ?? "town"}` });
    b.trust = clamp(b.trust + 0.08 + kind * 0.1, -1, 1);
    b.warmth = clamp(b.warmth + 0.05 + kind * 0.15, -1, 1);
    this.feel(m, kind > 0 ? { joy: 0.15, fear: -0.05 } : kind < 0 ? { fear: 0.2, anger: 0.15 } : { joy: 0.05 });
    this.remember(m, `${you.name} spoke with me in ${cityName(m.town) ?? "town"}: "${String(said).slice(0, 100)}" I answered: "${String(reply).slice(0, 80)}"`, { about: [key, you.name], weight: WEIGHT.talk, kind: "talk" });
    this.spoken(id);
  }

  feeling(m) {
    const top = FEELINGS.filter((k) => k !== "faith").sort((a, b) => (m.mood[b] - m.base[b] * 0.5) - (m.mood[a] - m.base[a] * 0.5))[0];
    const word = { fear: "afraid", anger: "angry", joy: "content", grief: "grieving", hunger: "hungry" }[top];
    return m.mood[top] > 0.55 ? `very ${word}` : m.mood[top] > 0.35 ? word : "much as ever";
  }

  // --- attention -----------------------------------------------------------------

  // The town tells us who is near the camera and who was spoken to: they are hot.
  attend({ city, near = [], spoken = [], cast = [], hour } = {}) {
    const now = Date.now();
    if (city != null) {
      this.warm[Number(city)] = now + HOT_MS;
      if (hour != null) this.hours[Number(city)] = { hour: Number(hour), at: now };
    }
    for (const i of near) this.hot[`folk:${Number(city)}:${Number(i)}`] = Math.max(this.hot[`folk:${Number(city)}:${Number(i)}`] ?? 0, now + HOT_MS);
    for (const id of [...spoken, ...cast]) this.spoken(String(id));
    // Hot minds think for themselves: the model plans their next stretch of day.
    const hot = this.tiers().hot;
    for (const id of hot) this.thinkPlan(id, "hot");
    return { hot: hot.length, warm: this.tiers().warm.length };
  }

  spoken(id) {
    this.hot[id] = Math.max(this.hot[id] ?? 0, Date.now() + SPOKEN_MS);
  }

  tier(id, tied = null) {
    const now = Date.now();
    if ((this.hot[id] ?? 0) > now) return "hot";
    const m = this.minds[id];
    if (m && (this.warm[m.town] ?? 0) > now) return "warm";
    // Tied to a hot mind: warm.
    if (tied) return tied.has(id) ? "warm" : "cold";
    for (const h of Object.keys(this.hot)) if (this.hot[h] > now && this.minds[h]?.bonds?.[id]) return "warm";
    return "cold";
  }

  tiers() {
    const out = { hot: [], warm: [], cold: 0 };
    // Who is tied to a hot mind, worked out once rather than once per mind.
    const now = Date.now();
    const tied = new Set();
    for (const h of Object.keys(this.hot)) if (this.hot[h] > now) for (const b of Object.keys(this.minds[h]?.bonds ?? {})) tied.add(b);
    for (const id of Object.keys(this.minds)) {
      const t = this.tier(id, tied);
      if (t === "cold") out.cold++;
      else out[t].push(id);
    }
    return out;
  }

  // Now and then a warm mind gets a thought of its own, behind the hot ones in the queue.
  warmThoughts() {
    const warm = this.tiers().warm;
    for (const id of warm) if (hash(id + this.now()) % 12 === 0) this.thinkPlan(id, "warm");
  }

  hour(city, asked) {
    if (asked != null && asked !== "" && !Number.isNaN(Number(asked))) return Number(asked);
    const told = this.hours[city];
    return told ? (told.hour + ((Date.now() - told.at) / 1000) * 24 / 240) % 24 : clockHour();
  }

  // --- the day's plan ------------------------------------------------------------

  // What each commoner of a town is doing at this hour, by villager index.
  plans(cityId, askedHour) {
    const t = this.town(cityId);
    if (!t) return null;
    const hour = this.hour(t.city.id, askedHour);
    const [part, until] = block(hour);
    const season = calendar(this.now()).season;
    const place = this.realm.town(t.city.id) ?? {};
    const out = t.minds.map((m) => {
      // Someone a story took (dead, left, gone into a lord's service) walks no more.
      if (m.gone) return { i: m.i, id: m.id, doing: m.gone, where: "gone", with: [], until: until % 24, mood: round(m.mood), feeling: this.feeling(m), tier: "cold", by: "story", bonds: {} };
      const own = m.plan && m.plan.part === part && m.plan.turn === this.now() && m.plan.by === "model" ? m.plan : null;
      const p = own ?? { ...this.rulePlan(m, part, season, place, hour), by: "rules" };
      return { i: m.i, id: m.id, doing: p.doing, where: p.where, with: [], until: until % 24, mood: round(m.mood), feeling: this.feeling(m), tier: this.tier(m.id), by: p.by, bonds: m.bonds };
    });
    // Who they're with: those they're bound to at the same place, else whoever stands nearest.
    for (const p of out) {
      if (!SOCIAL.has(p.where)) continue;
      const there = out.filter((q) => q !== p && q.where === p.where);
      const friend = there.find((q) => (p.bonds[q.id]?.warmth ?? 0) > 0) ?? there.find((q) => p.bonds[q.id]);
      const other = friend ?? there.sort((a, b) => Math.abs(a.i - p.i) - Math.abs(b.i - p.i))[0];
      if (other && !p.with.includes(other.i)) p.with.push(other.i);
      if (other && !other.with.includes(p.i)) other.with.push(p.i);
    }
    for (const p of out) {
      delete p.bonds;
      this.minds[p.id].plan = { doing: p.doing, where: p.where, with: p.with.map((i) => `folk:${t.city.id}:${i}`), until: p.until, part, turn: this.now(), by: p.by };
    }
    this.save();
    return out;
  }

  rulePlan(m, part, season, place, hour) {
    const mood = m.mood;
    const nature = m.nature.join(" ");
    const [workAt, work] = WORK[m.station] ?? ["home", "about the house"];
    const winter = season === "winter";
    const outdoors = workAt === "field" && winter ? ["home", "mending tools by the fire"] : [workAt, work];
    const r = hash(m.id + part + this.now()) % 100;
    if (part === "night") return mood.fear > 0.7 && r < 30 ? { doing: "lying awake, listening", where: "home" } : { doing: "asleep", where: "home" };
    // A sick town keeps indoors, and the frightened pray.
    if (place.plague || mood.fear > 0.65) {
      if (mood.faith > 0.45 && (part === "evening" || part === "dawn")) return { doing: "praying for the sickness to pass", where: "sept" };
      if (part !== "work" && part !== "work2") return { doing: mood.fear > 0.65 ? "keeping indoors, the door barred" : "keeping indoors", where: "home" };
    }
    if (mood.grief > 0.55 && r < 50) return { doing: "mourning", where: part === "evening" ? "sept" : "home" };
    if (mood.hunger > 0.65 && r < 45) return part === "work" || part === "work2" ? { doing: winter ? "begging bread" : "gleaning the stubble", where: winter ? "market" : "field" } : { doing: "queueing at the well for the dole", where: "well" };
    switch (part) {
      case "dawn":
        return /gossip|busybody/.test(nature) || r < 35 ? { doing: "drawing water and trading news", where: "well" } : { doing: "breaking fast", where: "home" };
      case "work":
        return { doing: outdoors[1], where: outdoors[0] };
      case "meal":
        return /drunkard/.test(nature) || r < 15 ? { doing: "a cup at midday", where: "tavern" } : r < 40 ? { doing: "eating on the bench", where: "bench" } : { doing: "eating at home", where: "home" };
      case "work2":
        if (m.wants.some((w) => /debt|penny|ox|land/.test(w.text)) && workAt === "home" && r < 50) return { doing: "selling at the market", where: "market" };
        if (/busybody|gossip/.test(nature) && r < 30) return { doing: "minding everyone's business", where: "market" };
        if (/lazy/.test(nature) && r < 40) return { doing: "dozing on the bench", where: "bench" };
        return { doing: outdoors[1], where: outdoors[0] };
      default: {
        if (m.station === "priest" || m.station === "prioress" || m.station === "anchoress") return { doing: "saying evensong", where: "sept" };
        if (workAt === "tavern") return { doing: "serving the evening crowd", where: "tavern" };
        if (mood.anger > 0.5) return { doing: "grumbling about the tithe over ale", where: "tavern" };
        if (/drunkard/.test(nature) || (mood.joy > 0.55 && r < 50)) return { doing: mood.joy > 0.6 ? "singing in the tavern" : "drinking", where: "tavern" };
        if (mood.faith > 0.6 && r < 50) return { doing: "at evening prayers", where: "sept" };
        return r < 45 ? { doing: "talking on the bench as the light goes", where: "bench" } : { doing: hour > 20 ? "banking the fire" : "supper at home", where: "home" };
      }
    }
  }

  // A hot mind's plan from the model, in their own words: what they'll do this
  // stretch of the day, and where, from the town's places.
  async thinkPlan(id, pri) {
    const m = this.minds[id];
    if (!m || m.gone || this.thinking.has(id) || m.town == null || !String(id).startsWith("folk:")) return;
    const hour = this.hour(m.town);
    const [part] = block(hour);
    if (part === "night" || (m.plan?.by === "model" && m.plan.part === part && m.plan.turn === this.now())) return;
    this.thinking.add(id);
    const asked = Date.now();
    try {
      const rule = this.rulePlan(m, part, calendar(this.now()).season, this.realm.town(m.town) ?? {}, hour);
      const out = await think(
        `You are ${m.name}, ${m.age}, ${m.station} in ${cityName(m.town)}. By nature ${m.nature.join(", ")}. You feel ${this.feeling(m)}. You want ${m.wants.map((w) => w.text).join("; ")}. You remember: ${m.memories.slice(-3).map((x) => x.text).join(" ")}
Answer with only: a place, a dash, then what you do there in five to eight plain words. Places: home, bench, field, well, market, tavern, sept.`,
        `It is ${part === "work2" ? "afternoon" : part === "dawn" ? "dawn" : part === "meal" ? "midday" : part === "work" ? "morning" : "evening"} in ${calendar(this.now()).season}. Your habit would be: ${rule.where} - ${rule.doing}. What do you do now?`,
        pri,
        30,
      );
      const got = String(out ?? "").toLowerCase().match(/\b(home|bench|field|well|market|tavern|sept)\b\s*[-–—:,]\s*(.{4,60})/);
      if (got) {
        const doing = got[2].replace(/[."]+$/, "").replace(/^i\s+/, "").trim();
        m.plan = { doing, where: got[1], with: [], until: block(hour)[1] % 24, part, turn: this.now(), by: "model", tier: pri, thoughtMs: Date.now() - asked };
        this.save();
      }
    } finally {
      this.thinking.delete(id);
    }
  }

  // --- views ---------------------------------------------------------------------

  view(id) {
    const m = this.get(id);
    if (!m) return null;
    const c = this.realm.court()?.people?.[m.id];
    const turn = this.now();
    const memories = [...m.memories, ...(c?.memories ?? []).map((text) => ({ turn: null, text, about: [], weight: 0.5, kind: "court" }))]
      .map((x) => (x.turn === null ? x : { ...x, now: Math.round(this.strength(x, turn) * 100) / 100 }));
    return {
      ...m, mood: round(m.mood), base: round(m.base), feeling: this.feeling(m), tier: this.tier(m.id), memories,
      ...(c ? { name: c.name, house: c.house, rank: c.rank, seat: c.seat, alive: c.alive } : { townName: cityName(m.town) }),
    };
  }

  queue() {
    return { tiers: (({ hot, warm, cold }) => ({ hot: hot.length, warm: warm.length, cold }))(this.tiers()), thinking: this.thinking.size, model: modelQueue() };
  }
}

// The routes: server.js hands requests here first.
export async function route(minds, url, req, body, reply, res) {
  if (!minds) return false;
  const json = (r, code, out) => (reply(r, code, out), true);
  if (url.pathname === "/minds/town" && req.method === "GET") {
    const out = minds.plans(url.searchParams.get("city"), url.searchParams.get("hour"));
    return out ? json(res, 200, out) : json(res, 404, { error: "no such town" });
  }
  if (url.pathname === "/mind" && req.method === "GET") {
    const out = minds.view(url.searchParams.get("id"));
    return out ? json(res, 200, out) : json(res, 404, { error: "no such person" });
  }
  if (url.pathname === "/minds/witness" && req.method === "POST") {
    const out = minds.witness(await body(req));
    return json(res, out.error ? 400 : 200, out);
  }
  if (url.pathname === "/minds/attention" && req.method === "POST") return json(res, 200, minds.attend(await body(req)));
  if (url.pathname === "/minds/queue" && req.method === "GET") return json(res, 200, minds.queue());
  return false;
}
