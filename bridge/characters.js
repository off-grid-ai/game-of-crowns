// The people of the realm. Every lord, lady, heir and bannerman is an editable
// JSON file in the chronicle's characters/ folder: identity, allegiance,
// traits, goals, relationships and memories. Each season every character
// weighs their goals and makes a move; moves change others' situations, so
// consequences chain beyond anyone's prediction. Routine choices are scored
// here; pivotal ones go to Claude in the character's own voice. Results land
// in Freeciv (towns change hands, rebellions, gold) and at the King's court.

import { crownOf, northTowns, richestTown } from "./realm.js";
import * as Lua from "./lua.js";
import { pick as wording, say } from "./say.js";  // one of a result's wordings (data/dilemmas.json text lists)
import fs from "node:fs";
import path from "node:path";
import { cityName, houseFor } from "./narrator.js";
import { decide } from "./claude.js";

import { calendar, SEASONS_PER_YEAR, yearsIn, isYearEnd } from "./calendar.js";
import { ANSWERS } from "./petitions.js";
import { BANDS } from "./favour.js";
import * as names from "./names.js";


// War seen (READY.md line 3; casebook, War and sieges: "The march feeds the battle"): the attacker's host musters
// at its town nearest the prey, where Freeciv raises it (realmrules realm_war_host), and marches out toward the town
// it goes for (the view's muster scene: army.gd march_out). The muster scene's fields, or null when the attacker
// holds no town or the prey is unknown.
export function warMuster(world, pid, prey) {
  const d2 = (c) => (c.x - prey.x) ** 2 + (c.y - prey.y) ** 2;
  const seat = prey?.x === undefined ? null : world.cities.filter((c) => c.owner === pid).sort((a, b) => d2(a) - d2(b))[0];
  return seat && prey?.x !== undefined ? { x: seat.x, y: seat.y, tx: prey.x, ty: prey.y, city: seat.id, owner: pid } : null;
}

// The court's deck of dilemmas: data, so new ones are written, not coded.
const DECK_FILE = new URL("./data/dilemmas.json", import.meta.url);
// Each lord's one want, made a thing in the realm (data/ambitions.json; ambitionOf).
const AMB = JSON.parse(fs.readFileSync(new URL("./data/ambitions.json", import.meta.url), "utf8"));
function loadDeck() {
  try { return JSON.parse(fs.readFileSync(DECK_FILE, "utf8")); } catch { return []; }
}

const NO_MOOD = { aggression: 0, loyalty: 0, ambition: 0, caution: 0, cunning: 0, piety: 0, greed: 0 };

// First names for the realm's people (data/first-names.json): no two living
// people share one, so "Cecily" is always the one Cecily. M and F are the old
// short lists, kept for anything that still reads them.
const NAMES_FILE = new URL("./data/first-names.json", import.meta.url);
// Bannermen's surnames (data/surnames.json): one list, here and for each reign's fresh names (written.js).
const SURNAMES = JSON.parse(fs.readFileSync(new URL("./data/surnames.json", import.meta.url), "utf8")).bannermen;
let firstNames = null;
function namePool(gender) {
  if (!firstNames) { try { firstNames = JSON.parse(fs.readFileSync(NAMES_FILE, "utf8")); } catch { firstNames = { male: M, female: F }; } }
  return gender === "male" ? firstNames.male : firstNames.female;
}
const M = ["Aldric", "Bran", "Cedric", "Dunstan", "Edric", "Godwin", "Harold", "Jory", "Osric", "Rowan", "Tobin", "Hugh", "Garth", "Alaric", "Ewan", "Roderick", "Leofric", "Merrick", "Corwin", "Tristan", "Benedict", "Gareth", "Lucan", "Willem"];
const F = ["Agnes", "Bryony", "Cecily", "Edith", "Elsbeth", "Gwen", "Hilda", "Isolde", "Joan", "Maud", "Rosalind", "Wynne", "Alys", "Mira", "Tamsin", "Ysolde", "Rhiannon", "Elaine", "Beatrix", "Constance", "Genevieve", "Odette"];
export const TRAITS = ["ambitious", "honourable", "greedy", "vengeful", "pious", "cunning", "craven", "brave", "content", "paranoid", "generous", "proud", "patient", "wrathful", "just"];

// Roles a player can give a character: a title, and the leanings that come with it.
export const ROLES = {
  knight: { title: "a sworn knight", traits: ["brave"], loyalty: 70 },
  spymaster: { title: "a spymaster", traits: ["cunning", "paranoid"], loyalty: 50 },
  steward: { title: "a steward", traits: ["patient"], loyalty: 65 },
  priest: { title: "a priest", traits: ["pious"], loyalty: 60 },
  scholar: { title: "a court scholar", traits: ["just"], loyalty: 60 },
  sellsword: { title: "a sellsword captain", traits: ["greedy"], loyalty: 30 },
  merchant: { title: "a merchant prince", traits: ["greedy", "cunning"], loyalty: 45 },
  hedge_knight: { title: "a landless knight", traits: ["brave", "proud"], loyalty: 55 },
  lady: { title: "a lady of the court", traits: ["cunning"], loyalty: 55 },
  ward: { title: "a ward", traits: ["content"], loyalty: 60 },
  outlaw: { title: "a pardoned outlaw", traits: ["wrathful"], loyalty: 25 },
};
// Aims a player can set; the kinds the season's moves already weigh.
export const GOALS = [
  { kind: "favour", text: "rise in my liege's esteem" },
  { kind: "court", text: "be noticed by the King himself" },
  { kind: "land", text: "win more land for my family" },
  { kind: "marriage", text: "see my daughter wed above her station" },
  { kind: "defect", text: "find a liege more worthy of my sword" },
  { kind: "revenge", text: "settle the old grudge" },
];

function pick(arr, r) {
  return arr[Math.floor(r() * arr.length)];
}

// The reign's own seed, mixed into every roll (0 for the baseline's dice).
let REIGN = 0;
export function setReignSeed(seed) {
  REIGN = seed && seed !== 1066 ? seed >>> 0 : 0;
}

function rng(seed) {
  seed = (seed ^ REIGN) >>> 0;
  let s = seed >>> 0 || 1;
  return () => {
    s = (Math.imul(s ^ (s >>> 15), 2246822507) + 0x9e3779b9) >>> 0;
    s = Math.imul(s ^ (s >>> 13), 3266489909) >>> 0;
    return ((s ^ (s >>> 16)) >>> 0) / 4294967296;
  };
}

export class Court {
  constructor(dir, record) {
    this.dir = path.join(dir, "characters");
    this.courtFile = path.join(dir, "court.json");
    this.record = record; // (entry) => void, writes to the chronicle
    fs.mkdirSync(this.dir, { recursive: true });
    this.people = {};
    for (const f of fs.readdirSync(this.dir).filter((x) => x.endsWith(".json"))) {
      try {
        const c = JSON.parse(fs.readFileSync(path.join(this.dir, f), "utf8"));
        this.people[c.id] = c;
      } catch { /* a hand-edited file with a typo is skipped, not fatal */ }
    }
    const saved = fs.existsSync(this.courtFile) ? JSON.parse(fs.readFileSync(this.courtFile, "utf8")) : {};
    this.petitions = Array.isArray(saved) ? saved : saved.petitions ?? [];
    this.claims = saved.claims ?? [];
    this.truces = saved.truces ?? {};
    this.debts = saved.debts ?? [];
    this.intrigue = saved.intrigue ?? [];  // the houses' schemes the map shows (scheme(), intrigue.js)
    this.moodFile = path.join(dir, "mood.json");
    const savedMoods = fs.existsSync(this.moodFile) ? JSON.parse(fs.readFileSync(this.moodFile, "utf8")) : [];
    this.decrees = Array.isArray(savedMoods) ? savedMoods : [];
    // Past the highest id ever given, so a new person never takes an old one's file.
    this.seq = Math.max(0, ...Object.keys(this.people).map((id) => Number(String(id).slice(1)) || 0)) + 1;
  }

  save(c) {
    this._alive = null;  // whoever changed may have changed rank, seat or life
    fs.writeFileSync(path.join(this.dir, `${c.id}.json`), JSON.stringify(c, null, 2));
  }

  // Decrees about people: each has a scope (all, houses, characters, a group)
  // and changes moods, traits or goals for everyone it matches.
  matches(d, c) {
    if (!d || !c.alive) return false;
    if (d.scope === "all") return true;
    if (d.scope === "houses") return d.houses.includes(c.house);
    if (d.scope === "characters") return d.characters.some((n) => c.name.toLowerCase().includes(n) || n.includes(c.name.toLowerCase()));
    const g = d.group ?? {};
    if (g.rank && g.rank !== "any" && c.rank !== g.rank) return false;
    if (g.gender && g.gender !== "any" && c.gender !== g.gender) return false;
    if (g.minAge && c.age < g.minAge) return false;
    if (g.maxAge && c.age > g.maxAge) return false;
    if (g.trait && !c.traits.includes(String(g.trait).toLowerCase())) return false;
    return true;
  }

  // Applies a decree; returns how many people it touched.
  setMood(d) {
    if (!d) {
      this.decrees = [];
    } else {
      this.decrees.push(d);
      let n = 0;
      for (const c of this.alive()) {
        if (!this.matches(d, c)) continue;
        n++;
        c.traits = c.traits.filter((t) => !d.removeTraits?.includes(t));
        for (const t of d.addTraits ?? []) if (!c.traits.includes(t)) c.traits.push(t);
        if (d.goal) c.goals = [{ kind: "decreed", text: d.goal }, ...c.goals].slice(0, 3);
        this.save(c);
      }
      d.touched = n;
    }
    fs.writeFileSync(this.moodFile, JSON.stringify(this.decrees, null, 1));
    return d?.touched ?? 0;
  }

  revoke(id) {
    this.decrees = this.decrees.filter((d) => d.id !== id);
    fs.writeFileSync(this.moodFile, JSON.stringify(this.decrees, null, 1));
  }

  // Every decree that matches this character, combined.
  moodFor(c) {
    const out = { ...NO_MOOD };
    const lines = [];
    for (const d of this.decrees) {
      if (!this.matches(d, c)) continue;
      for (const k of Object.keys(NO_MOOD)) out[k] += d[k] ?? 0;
      lines.push(d.summary);
    }
    out.summary = lines.join(" ");
    return out;
  }

  saveCourt() {
    fs.writeFileSync(this.courtFile, JSON.stringify({ petitions: this.petitions, claims: this.claims ?? [], truces: this.truces ?? {}, debts: this.debts ?? [], intrigue: this.intrigue ?? [] }, null, 1));
  }

  // A scheme between two houses, for the map (intrigue.js reads it out): an
  // envoy, a pact or a match. The same scheme between the same houses is
  // updated, not repeated. kind: "envoy" | "pact" | "marriage".
  scheme({ kind, from, to, line, secret = false, turn }) {
    if (from == null || to == null || Number(from) === Number(to)) return;
    const list = (this.intrigue ??= []);
    const id = `${kind}:${Math.min(from, to)}:${Math.max(from, to)}`;
    const same = list.find((s) => s.id === id);
    if (same) Object.assign(same, { from: Number(from), to: Number(to), line, secret, last: turn });
    else list.push({ id, kind, from: Number(from), to: Number(to), line, secret, since: turn, last: turn });
    if (list.length > 16) list.splice(0, list.length - 16);
  }

  // A scheme that ended (a match refused, gates opened): off the map.
  unscheme(kind, a, b) {
    const id = `${kind}:${Math.min(a, b)}:${Math.max(a, b)}`;
    this.intrigue = (this.intrigue ?? []).filter((s) => s.id !== id);
  }

  // Everyone living, rebuilt at most a few times a second: the game asks for a
  // town's lord for every town every second, and a fresh list each time was
  // most of the bridge's work. Lords by seat and by house come from the same pass.
  alive() {
    const now = Date.now();
    if (!this._alive || now - this._aliveAt > 250) {
      this._alive = Object.values(this.people).filter((c) => c.alive);
      this._aliveAt = now;
      this._bySeat = new Map();
      this._byHouse = new Map();
      for (const c of this._alive) {
        if ((c.rank === "lord" || c.rank === "bannerman") && c.seat != null && !this._bySeat.has(c.seat)) this._bySeat.set(c.seat, c);
        if (c.rank === "lord" && !this._byHouse.has(c.playerId)) this._byHouse.set(c.playerId, c);
      }
    }
    return this._alive;
  }

  // A death, a birth or a new lord changes who is living and where: rebuild at the next ask.
  stale() {
    this._alive = null;
  }

  lordOfHouse(pid) {
    this.alive();
    const c = this._byHouse.get(pid);
    return c?.alive ? c : this.stale() ?? this.alive().find((x) => x.playerId === pid && x.rank === "lord");
  }

  lordOfTown(cityId) {
    this.alive();
    const c = this._bySeat.get(cityId);
    return c?.alive && c.seat === cityId ? c : (c ? this.stale() ?? this.alive().find((x) => x.seat === cityId && (x.rank === "lord" || x.rank === "bannerman")) : undefined);
  }

  // --- population ----------------------------------------------------------

  // A first name nobody alive in the realm has, so no two people share one
  // (`prefer` first, if any of those is free). With every name taken, the
  // one fewest share.
  firstName(gender, r = Math.random, prefer = []) {
    const used = new Map();
    for (const x of this.alive()) { const f = String(x.name).split(" ")[0]; used.set(f, (used.get(f) ?? 0) + 1); }
    const freePrefer = prefer.filter((n) => !used.has(n));
    if (freePrefer.length) return pick(freePrefer, r);
    const pool = namePool(gender);
    const free = pool.filter((n) => !used.has(n));
    if (free.length) return pick(free, r);
    return [...pool].sort((a, b) => (used.get(a) ?? 0) - (used.get(b) ?? 0))[0];
  }

  newPerson(fields, r) {
    const gender = fields.gender ?? (r() < 0.5 ? "male" : "female");
    // Nobody alive shares a first name, so the chronicle can always tell people apart.
    const name = `${this.firstName(gender, r)} ${fields.surname}`;
    while (this.people[`c${this.seq}`]) this.seq++;
    const c = {
      id: `c${this.seq++}`,
      name,
      gender, age: 30, alive: true, traits: [pick(TRAITS, r), pick(TRAITS, r)].filter((t, i, a) => a.indexOf(t) === i),
      loyalty: 50 + Math.floor(r() * 40), goals: [], relationships: {}, memories: [], spouse: null, children: [],
      ...fields,
    };
    this.people[c.id] = c;
    return c;
  }

  family(lord, r) {
    const spouse = this.newPerson({ surname: lord.surname, house: lord.house, playerId: lord.playerId, gender: lord.gender === "male" ? "female" : "male", age: lord.age - Math.floor(r() * 8), rank: "spouse", liege: lord.id }, r);
    lord.spouse = spouse.id;
    spouse.spouse = lord.id;
    const kids = 1 + Math.floor(r() * 3);
    for (let i = 0; i < kids; i++) {
      const kid = this.newPerson({ surname: lord.surname, house: lord.house, playerId: lord.playerId, age: 8 + Math.floor(r() * 14), rank: i === 0 ? "heir" : "child", liege: lord.id }, r);
      lord.children.push(kid.id);
      spouse.children.push(kid.id);
      kid.parents = [lord.id, spouse.id];
    }
  }

  // Lords for every great house, bannermen for their towns; called each season
  // so new towns get a minor lord of their own.
  populate(world) {
    const r = rng((world.turn + 7) * 7919);
    for (const p of world.players) {
      const h = houseFor(p);
      if (h.wild || h.crown) continue;
      if (!this.lordOfHouse(p.id)) {
        const seat = world.cities.find((c) => c.owner === p.id && c.capital);
        const surname = h.name.replace("House ", "");
        const lord = this.newPerson({ surname, house: h.name, playerId: p.id, rank: "lord", seat: seat?.id ?? null, age: 35 + Math.floor(r() * 25), loyalty: 40 + Math.floor(r() * 40) }, r);
        lord.goals = [this.goalFor(lord, r)];
        this.family(lord, r);
        lord.voice = `${lord.traits.join(", ")} lord of ${h.name}; speaks like a ${lord.traits.includes("cunning") ? "courtier" : lord.traits.includes("brave") ? "soldier" : "proud noble"}`;
        for (const id of [lord.id, lord.spouse, ...lord.children]) this.save(this.people[id]);
        this.record({ turn: world.turn, kind: "person", text: `${lord.name} rules ${h.name}, ${lord.traits.join(" and ")}.` });
      }
      for (const town of world.cities.filter((c) => c.owner === p.id && !c.capital)) {
        if (this.lordOfTown(town.id)) continue;
        const surname = pick(SURNAMES, r);
        const liege = this.lordOfHouse(p.id);
        const bm = this.newPerson({ surname, house: h.name, playerId: p.id, rank: "bannerman", seat: town.id, liege: liege?.id ?? null, age: 25 + Math.floor(r() * 35) }, r);
        bm.goals = [this.goalFor(bm, r)];
        if (r() < 0.7) this.family(bm, r);
        for (const id of [bm.id, bm.spouse, ...bm.children].filter(Boolean)) this.save(this.people[id]);
      }
    }
  }

  // A character the King writes into the realm: a sworn member of a house
  // (the rank that acts each season), with the role, nature and aims he gives.
  create(spec, world) {
    const p = world.players.find((x) => x.id === Number(spec.house));
    if (!p) return { error: "no such house" };
    const towns = world.cities.filter((c) => c.owner === p.id);
    const seat = towns.find((c) => c.id === Number(spec.seat)) ?? towns[Math.floor(Math.random() * towns.length)];
    const role = ROLES[spec.role] ?? ROLES.knight;
    // Up to three traits from the list the rules know, plus up to three in the
    // King's own words, which the storyteller reads when they make big choices.
    const own = String(spec.other ?? "").split(",").map((t) => t.trim().toLowerCase().replace(/[^a-z' -]/g, "").slice(0, 30)).filter(Boolean).slice(0, 3);
    const traits = [...new Set([...(spec.traits ?? []).filter((t) => TRAITS.includes(t)).slice(0, 3), ...role.traits, ...own])].slice(0, 7);
    const goal = GOALS.find((g) => g.kind === spec.goal) ?? GOALS[0];
    const lord = this.lordOfHouse(p.id);
    const name = String(spec.name || "").trim().slice(0, 40) || "A nameless stranger";
    const c = this.newPerson({
      name, surname: name.split(" ").slice(-1)[0], gender: spec.gender === "female" ? "female" : "male",
      age: Math.max(14, Math.min(80, Number(spec.age) || 30)),
      house: houseFor(p).name, playerId: p.id, rank: "bannerman", role: spec.role in ROLES ? spec.role : "knight",
      seat: seat?.id ?? null, liege: lord?.id ?? null, traits,
      loyalty: Math.max(0, Math.min(100, Number(spec.loyalty ?? role.loyalty))),
      goals: [{ kind: goal.kind, text: goal.text }], created: true,
    }, Math.random);
    if (spec.past) c.backstory = String(spec.past).slice(0, 300);  // their past, as their card tells it
    if (spec.backstory) this.remember(c.id, String(spec.backstory).slice(0, 300));
    if (lord) this.shift(c.id, lord.id, role.loyalty - 50);
    this.save(c);
    const at = seat ? ` at ${cityName(seat.id)}` : "";
    this.record({ turn: world.turn, kind: "person", text: `${name}, ${role.title}, enters the service of ${houseFor(p).name}${at}.`, city: seat?.id });
    return { ok: true, character: c };
  }

  // The King reshapes someone already in the realm: their nature, aim, loyalty,
  // name or age. Unset fields stay as they were; they act on the new self from
  // the next season, and remember the line of past they were given.
  edit(id, spec, world) {
    const c = this.people[id];
    if (!c || !c.alive) return { error: "no such person" };
    const newGoal = spec.goal && spec.goal !== c.goals?.[0]?.kind ? GOALS.find((g) => g.kind === spec.goal) : null;
    if (spec.goal && spec.goal !== c.goals?.[0]?.kind && !newGoal) return { error: "no such aim" };
    if (spec.name) c.name = String(spec.name).trim().slice(0, 40) || c.name;
    if (spec.gender) c.gender = spec.gender === "female" ? "female" : "male";
    if (spec.age != null) c.age = Math.max(14, Math.min(90, Number(spec.age) || c.age));
    if (spec.traits || spec.other != null) {
      const own = String(spec.other ?? "").split(",").map((t) => t.trim().toLowerCase().replace(/[^a-z' -]/g, "").slice(0, 30)).filter(Boolean).slice(0, 3);
      const ruled = (spec.traits ?? c.traits.filter((t) => TRAITS.includes(t))).filter((t) => TRAITS.includes(t)).slice(0, 4);
      c.traits = [...new Set([...ruled, ...own])].slice(0, 7);
    }
    if (newGoal) {
      c.goals = [{ kind: newGoal.kind, text: newGoal.text }, ...(c.goals ?? []).filter((g) => g.kind !== newGoal.kind)].slice(0, 3);
    }
    if (spec.loyalty != null) c.loyalty = Math.max(0, Math.min(100, Number(spec.loyalty)));
    if (spec.role && spec.role in ROLES) c.role = spec.role;
    if (Array.isArray(spec.memories)) c.memories = spec.memories.map((m) => String(m).trim().slice(0, 200)).filter(Boolean).slice(-12);  // what they remember, as the King rewrites it
    if (spec.past != null) c.backstory = String(spec.past).slice(0, 300) || undefined;  // rewritten, or cleared
    if (spec.backstory) this.remember(c.id, String(spec.backstory).slice(0, 300));
    this.save(c);
    this.record({ turn: world?.turn ?? 0, kind: "person", text: `By the King's hand, ${c.name} of ${c.house} is changed: ${c.traits.join(", ")}.${c.goals?.[0] ? ` "I mean to ${c.goals[0].text}."` : ""}`, city: c.seat });
    return { ok: true, character: c };
  }

  goalFor(c, r) {
    const options = c.rank === "lord"
      ? [{ kind: "power", text: "make my house the greatest in the realm" }, { kind: "marriage", text: "wed my heir into a great house" }, { kind: "revenge", text: "settle the old grudge" }, { kind: "crown", text: "sit the throne myself one day" }, { kind: "peace", text: "keep my people fed and out of other men's wars" }]
      : [{ kind: "marriage", text: "see my daughter wed above her station" }, { kind: "land", text: "win more land for my family" }, { kind: "favour", text: "rise in my liege's esteem" }, { kind: "defect", text: "find a liege more worthy of my sword" }, { kind: "court", text: "be noticed by the King himself" }];
    return pick(options, r);
  }

  opinion(a, b) {
    return this.people[a]?.relationships[b]?.opinion ?? 0;
  }

  // What a lord wants, as a thing in the realm (CK3's ambitions): his goal (goals[0], the one he holds) with its
  // target read from the realm now: the town nearest his seat another great house holds (land, power), the great
  // house whose lord he likes best (marriage), the lord he likes least (revenge). {kind, text, line, target}: line
  // as he says it on his sheet; target {kind: town|house|person, id, name, house}. Derived, never stored.
  ambitionOf(c, world) {
    const g = c?.goals?.[0];
    if (!g) return null;
    const lords = this.alive().filter((o) => o.rank === "lord" && o.id !== c.id && o.playerId !== c.playerId);
    const seat = world?.cities?.find((x) => x.id === c.seat) ?? world?.cities?.find((x) => x.owner === c.playerId);
    let target = null;
    if ((g.kind === "land" || g.kind === "power") && seat) {
      const great = (pid) => { const p = world.players.find((x) => x.id === pid); return p && !houseFor(p).crown && !houseFor(p).wild && pid !== c.playerId; };
      const t = world.cities.filter((x) => great(x.owner)).map((x) => [x, Math.max(Math.abs(x.x - seat.x), Math.abs(x.y - seat.y))])
        .filter(([, d]) => d <= AMB.plea.reach).sort((a, b) => a[1] - b[1])[0]?.[0];
      if (t) target = { kind: "town", id: t.id, name: cityName(t.id), house: houseFor(world.players.find((x) => x.id === t.owner)).name, pid: t.owner };
    }
    const by = (dir) => [...lords].sort((a, b) => dir * (this.opinion(c.id, b.id) - this.opinion(c.id, a.id)))[0];
    if (g.kind === "marriage" && c.rank === "lord") { const o = by(1); if (o) target = { kind: "house", id: o.playerId, name: o.house, house: o.house }; }
    if (g.kind === "revenge") { const o = by(-1); if (o) target = { kind: "person", id: o.id, name: o.name, house: o.house }; }
    const line = target || !["land", "power", "marriage", "revenge"].includes(g.kind)
      ? String(AMB.lines[g.kind] ?? "").replace(/\{(\w+)\}/g, (_, k) => ({ town: target?.name, house: target?.house, name: target?.name }[k] ?? "")) : `I mean to ${g.text}.`;
    return { kind: g.kind, text: g.text, line: line || `I mean to ${g.text}.`, target };
  }

  shift(a, b, delta, why) {
    const rel = (this.people[a].relationships[b] ??= { opinion: 0 });
    rel.opinion = Math.max(-100, Math.min(100, rel.opinion + delta));
    if (why) this.remember(a, why);
  }

  remember(id, text) {
    const c = this.people[id];
    // The same thing done again isn't a new memory: it moves to the front.
    c.memories = c.memories.filter((m) => m !== text);
    c.memories.push(text);
    if (c.memories.length > 12) c.memories.shift();
  }

  // --- the season ------------------------------------------------------------

  // world: live world; ctx: { favour(pid), send(lua), crownId }
  async season(world, ctx) {
    this.populate(world);
    const r = rng(world.turn * 104729);
    const turn = world.turn;
    // Age, and sometimes death; heirs inherit.
    if (isYearEnd(turn)) {
      for (const c of this.alive()) {
        c.age++;
        const risk = c.age > 75 ? 0.2 : c.age > 60 ? 0.06 : 0.004;
        if (r() < risk) this.die(c, turn, world);
      }
    }
    // Each acting character weighs moves; the strongest few act this season.
    const actors = this.alive().filter((c) => (c.rank === "lord" || c.rank === "bannerman") && c.goals.length);
    const moves = [];
    for (const c of actors) {
      const m = this.bestMove(c, world, ctx, r);
      if (m) moves.push(m);
    }
    moves.sort((a, b) => b.score - a.score);
    // Drama needs rarity: at most one of each kind of move a year, and only bold ones.
    const done = new Set();
    let acted = 0;
    // Every year at least one lord comes to court, if any has cause to.
    this.turnNow = turn;
    if (ctx.watched) {
      this.endTruces(turn);
      this.collect(world, turn, ctx);
    }
    const pet = moves.find((m) => m.kind === "petition");
    if (pet) await this.act(pet, world, ctx, turn);
    else {
      // Only lords of houses that hold land (the houses table's rows) bring petitions.
      const lords = this.alive().filter((c) => c.rank === "lord" && (world.players.find((p) => p.id === c.playerId)?.cities ?? 0) > 0);
      const askers = { rare: 1, normal: 3, often: 5 }[ctx.options?.petitions] ?? 3;
      for (const l of lords.sort(() => r() - 0.5).slice(0, askers)) await this.petition(l, world, turn, ctx);
    }
    done.add("petition");
    for (const m of moves) {
      const bold = { quiet: [2, 60], normal: [4, 45], scheming: [7, 30] }[ctx.options?.intrigue] ?? [4, 45];
      if (acted >= bold[0] || done.has(m.kind) || (m.score < bold[1] && m.kind !== "petition")) continue;
      done.add(m.kind);
      acted++;
      await this.act(m, world, ctx, turn);
    }
    for (const c of Object.values(this.people)) this.save(c);
    this.saveCourt();
  }

  die(c, turn, world) {
    c.alive = false;
    const where = c.seat ? cityName(c.seat) : c.house;
    this.record({ turn, kind: "death", text: say("event.death", { name: c.name, house: c.house, age: c.age, where }), city: c.seat ?? undefined });
    if (c.rank !== "lord" && c.rank !== "bannerman") return;
    const heir = c.children.map((id) => this.people[id]).filter((k) => k?.alive).sort((a, b) => b.age - a.age)[0];
    if (heir) {
      heir.rank = c.rank;
      heir.seat = c.seat;
      heir.liege = c.liege;
      heir.goals = c.goals.length ? c.goals : [this.goalFor(heir, Math.random)];
      heir.memories.push(`I buried my parent, ${c.name}, and took up their seat.`);
      for (const [id, rel] of Object.entries(c.relationships)) heir.relationships[id] = { opinion: Math.round(rel.opinion * 0.6) };
      this.record({ turn, kind: "succession", text: `${heir.name}, ${heir.age}, succeeds as ${c.rank === "lord" ? "lord of " + c.house : "lord of " + cityName(c.seat)}.`, city: c.seat ?? undefined });
      if (heir.age < 16) this.record({ turn, kind: "unrest", text: `A child sits the seat of ${cityName(c.seat)}. Ambitious men take note.`, city: c.seat ?? undefined });
    } else if (c.rank === "lord") {
      this.record({ turn, kind: "unrest", text: `${c.house} has no heir. The succession is contested.` });
    }
  }

  // Utility scoring: traits × goal × situation.
  bestMove(c, world, ctx, r) {
    const goal = c.goals[0];
    const has = (t) => c.traits.includes(t);
    const liege = c.liege ? this.people[c.liege] : null;
    const opts = [];
    // A minor lord seeks a match for a daughter with a great lord's son.
    const daughter = c.children.map((id) => this.people[id]).find((k) => k?.alive && k.gender === "female" && k.age >= 14 && !k.spouse);
    if (daughter) {
      const sons = this.alive().filter((k) => k.gender === "male" && k.age >= 15 && !k.spouse && k.house !== c.house && (k.rank === "heir" || k.rank === "child") && this.people[k.parents?.[0]]?.rank === "lord");
      if (sons.length) opts.push({ kind: "match", score: 30 + (goal.kind === "marriage" ? 40 : 0) + (has("ambitious") ? 15 : 0), target: pick(sons, r), daughter });
    }
    // A bannerman with little love for his liege may turn his coat.
    if (c.rank === "bannerman" && liege) {
      const rivals = world.players.filter((p) => !houseFor(p).wild && !houseFor(p).crown && p.id !== c.playerId && p.cities > 0);
      const unhappy = Math.max(0, 70 - c.loyalty) + Math.max(0, -this.opinion(c.id, liege.id)) * 0.5;
      if (rivals.length) opts.push({ kind: "defect", score: unhappy * 0.7 + (goal.kind === "defect" ? 35 : 0) + (has("cunning") || has("greedy") ? 15 : 0) - (has("honourable") ? 40 : 0), to: pick(rivals, r) });
      opts.push({ kind: "serve", score: 20 + (goal.kind === "favour" ? 25 : 0) + (has("honourable") ? 15 : 0) });
    }
    // Great lords: alliances, plots, petitions.
    if (c.rank === "lord") {
      const others = this.alive().filter((o) => o.rank === "lord" && o.id !== c.id);
      if (others.length) {
        const friend = others.sort((a, b) => this.opinion(c.id, b.id) - this.opinion(c.id, a.id))[0];
        const foe = others.sort((a, b) => this.opinion(c.id, a.id) - this.opinion(c.id, b.id))[0];
        opts.push({ kind: "alliance", score: 25 + this.opinion(c.id, friend.id) * 0.4 + (has("cunning") ? 10 : 0) + (goal.kind === "power" ? 15 : 0), target: friend });
        opts.push({ kind: "plot", score: 10 - this.opinion(c.id, foe.id) * 0.5 + (has("vengeful") || has("wrathful") ? 20 : 0) + (goal.kind === "revenge" ? 30 : 0) - (has("honourable") ? 20 : 0), target: foe });
      }
      const favour = ctx.favour(c.playerId);
      opts.push({ kind: "petition", score: 20 + (goal.kind === "court" || goal.kind === "peace" ? 20 : 0) + (favour >= BANDS.loyal ? 10 : 0) });
      // Only after the house's ultimatum to the crown was refused (server.js turnHouses).
      if (favour < BANDS.cooling && !ctx.warded?.(c.playerId) && (ctx.mayRise?.(c.playerId) ?? true)) opts.push({ kind: "rebel", score: 40 + (BANDS.cooling - favour) * 2 + (goal.kind === "crown" ? 40 : 0) + (has("ambitious") ? 15 : 0) - (has("craven") ? 30 : 0) - (c.hostage && this.people[c.hostage]?.alive ? 60 : 0) });
    }
    if (!opts.length) return null;
    // The realm's mood, set by the King in words, tilts everyone at once.
    const md = this.moodFor(c);
    const tilt = {
      match: md.ambition * 0.4 + md.cunning * 0.4,
      defect: -md.loyalty * 0.8 + md.greed * 0.5 + md.ambition * 0.3 - md.caution * 0.3,
      serve: md.loyalty * 0.6 + md.caution * 0.3,
      alliance: md.cunning * 0.6 + md.caution * 0.4 - md.aggression * 0.2,
      plot: md.aggression * 0.8 + md.cunning * 0.3 - md.caution * 0.4 - md.piety * 0.2,
      petition: md.loyalty * 0.4 + md.caution * 0.3 + md.piety * 0.2,
      rebel: md.aggression * 0.6 - md.loyalty * 0.7 + md.ambition * 0.4 - md.caution * 0.4,
    };
    for (const o of opts) o.score += (tilt[o.kind] ?? 0) + r() * 18; // nobody is perfectly predictable
    const best = opts.sort((a, b) => b.score - a.score)[0];
    return best.kind === "serve" ? null : { ...best, who: c };
  }

  async ask(c, situation, choices) {
    const system = "You are the inner voice of a character in a gritty medieval realm (tone: Game of Thrones, Vikings). Decide as THIS character would, given their traits, goals, loyalties and memories, not as a reasonable person would. Reply with JSON only.";
    const ms = this.moodFor(c).summary;
    const moodLine = ms ? `\nThe mood: ${ms}` : "";
    const prompt = `Character: ${c.name}, ${c.age}, ${c.gender}, ${c.rank} of ${c.house}${c.seat ? ", holding " + cityName(c.seat) : ""}.
Traits: ${c.traits.join(", ")}. Goal: ${c.goals[0]?.text}. Loyalty to liege: ${c.loyalty}/100.
Memories: ${c.memories.slice(-6).join(" | ") || "none yet"}.
Situation: ${situation}${moodLine}
Choices: ${choices.join(" / ")}
Return {"choice": one of the choices exactly, "line": what they say, one short sentence the way a person would say it out loud: plain everyday words, no flourishes, no "Let the King hear" or "sworn blood"}.`;
    return decide(system, prompt);
  }

  async act(m, world, ctx, turn) {
    const c = m.who;
    switch (m.kind) {
      case "match": {
        const father = this.people[m.target.parents?.[0]];
        if (!father) return;
        // The great lord decides; this is a pivotal choice, so Claude weighs it.
        const yes = this.opinion(father.id, c.id) + (father.traits.includes("greedy") ? 10 : 0) + Math.random() * 40 > 30;
        const d = await this.ask(father, `${c.name}, a minor lord of ${c.house}, offers his daughter ${m.daughter.name} (${m.daughter.age}) to marry your son ${m.target.name}. Her house is lesser than yours.`, ["accept", "refuse"]);
        const accept = d ? d.choice === "accept" : yes;
        const line = d?.line ? ` "${d.line}"` : "";
        if (accept) {
          m.daughter.spouse = m.target.id;
          m.target.spouse = m.daughter.id;
          m.daughter.house = m.target.house;
          this.shift(c.id, father.id, 30, `${father.name} took my daughter into ${father.house}.`);
          this.shift(father.id, c.id, 15);
          this.record({ turn, kind: "marriage", text: `${m.daughter.name} of ${cityName(c.seat)} weds ${m.target.name}, heir of ${father.house}. A minor house rises.${line}`, city: c.seat });
          this.scheme({ kind: "marriage", from: c.playerId, to: father.playerId, turn, line: `${m.daughter.name} of ${c.house} weds ${m.target.name}, heir of ${father.house}: two houses bound by blood.` });
        } else {
          this.shift(c.id, father.id, -25, `${father.name} spurned my daughter.`);
          this.record({ turn, kind: "scheme", text: `${father.name} refuses ${c.name}'s offer of his daughter's hand. The insult is remembered.${line}`, city: c.seat });
          this.unscheme("marriage", c.playerId, father.playerId);
        }
        return;
      }
      case "defect": {
        const town = world.cities.find((x) => x.id === c.seat);
        if (!town || town.capital) return;
        // Gold-laden envoys ride from the tempting house to this lord's liege's lands: secret until it's settled.
        this.scheme({ kind: "envoy", from: m.to.id, to: c.playerId, turn, secret: true, line: `${houseFor(m.to).name}'s envoys ride to ${cityName(c.seat)} with gold: a lord of ${c.house} is being bought?` });
        const d = await this.ask(c, `Your liege's house is ${c.house}. ${houseFor(m.to).name} sends envoys with gold, offering you their protection if you open your gates to them.`, ["defect", "stay loyal"]);
        const go = d ? d.choice === "defect" : true;
        const line = d?.line ? ` "${d.line}"` : "";
        if (!go) {
          c.loyalty = Math.min(100, c.loyalty + 15);
          this.scheme({ kind: "envoy", from: m.to.id, to: c.playerId, turn, line: `${c.name} of ${cityName(c.seat)} sent ${houseFor(m.to).name}'s envoys home empty-handed.` });
          this.record({ turn, kind: "scheme", text: `${c.name} of ${cityName(c.seat)} sends ${houseFor(m.to).name}'s envoys home empty-handed.${line}`, city: c.seat, with: world.cities.find((x) => x.owner === m.to.id && x.capital)?.id });
          return;
        }
        ctx.send(Lua.transferCity(town.id, m.to.id));
        this.unscheme("envoy", m.to.id, c.playerId);  // the gold did its work: the gates are open
        this.claims ??= [];
        this.claims.push({ city: town.id, from: c.playerId, to: m.to.id, turn });
        const oldLiege = c.liege;
        c.house = houseFor(m.to).name;
        c.playerId = m.to.id;
        c.liege = this.lordOfHouse(m.to.id)?.id ?? null;
        c.loyalty = 55;
        c.goals = [this.goalFor(c, Math.random)];
        if (oldLiege) this.shift(oldLiege, c.id, -60, `${c.name} betrayed me and gave ${cityName(c.seat)} to ${c.house}.`);
        this.record({ turn, kind: "betrayal", text: `Treachery! ${c.name} opens the gates of ${cityName(c.seat)} to ${c.house}.${line}`, city: c.seat, from: town.owner, to: m.to.id });
        return;
      }
      case "alliance": {
        this.shift(c.id, m.target.id, 15, `I sought friendship with ${m.target.name}.`);
        this.shift(m.target.id, c.id, 12);
        this.record({ turn, kind: "alliance", text: say("event.alliance", { house: c.house, other: m.target.house, name: c.name, othername: m.target.name }), city: c.seat ?? undefined, with: m.target.seat ?? undefined });
        this.scheme({ kind: "pact", from: c.playerId, to: m.target.playerId, turn, line: `Ravens fly between ${c.house} and ${m.target.house}: a pact in the making.` });
        return;
      }
      case "plot": {
        if (this.truce(c.id, m.target.id)) return;
        const d = await this.ask(c, `You despise ${m.target.name} of ${m.target.house}. You could hire men to raid their lands, spread rumours at court, or let it lie for now.`, ["raid", "slander", "wait"]);
        const md = this.moodFor(c);
        const choice = d?.choice ?? (c.traits.includes("wrathful") || md.aggression > 20 ? "raid" : md.caution > 25 ? "wait" : "slander");
        const line = d?.line ? ` "${d.line}"` : "";
        if (choice === "raid") {
          const prey = richestTown(world, m.target.playerId);
          if (prey) {
            ctx.send(Lua.raid(prey.id));
            this.shift(m.target.id, c.id, -40, `${c.name}'s men raided ${cityName(prey.id)}.`);
            this.record({ turn, kind: "raid", text: `Men without banners raid ${cityName(prey.id)}. Everyone knows who paid them: ${c.house}.${line}`, city: prey.id });
          }
        } else if (choice === "slander") {
          this.shift(m.target.id, c.id, -15);
          this.record({ turn, kind: "scheme", text: `Whispers at court: ${m.target.name} of ${m.target.house} is said to be a coward and a cheat. The rumour starts in ${c.house}'s halls.${line}` });
        }
        return;
      }
      case "petition":
        return this.petition(c, world, turn, ctx);
      case "rebel": {
        const d = await this.ask(c, `Your house has lost faith in the King. You could raise your banners against the crown, or swallow your pride.`, ["rebel", "endure"]);
        if (d && d.choice !== "rebel") return;
        const seat = world.cities.find((x) => x.id === c.seat);
        if (seat) ctx.send(Lua.levy(seat.id, Array(3).fill("Knights|Horsemen")));
        const why = ctx.cause?.(c.playerId);
        this.record({ turn, kind: "rebellion", text: `${c.name} raises the banners of ${c.house} against the crown!${why ? ` ${c.house} has not forgotten ${why}.` : ""}${d?.line ? ` "${d.line}"` : ""}`, city: c.seat ?? undefined });
        ctx.rose?.(c.playerId);
        return;
      }
    }
  }

  // --- the court: dilemmas with a price on every answer ------------------------

  // Every choice states what it does to favour, from the effects it declares:
  // "Elsbeth owes the crown · Ysolde is shamed · House Thornvale −10".
  withFavour(hint, favour, roles) {
    if (/[+−-]\d/.test(hint)) return hint;  // it already says its numbers
    const said = Object.entries(favour ?? {}).map(([k, n]) => {
      const house = roles[k]?.house;
      if (!house || hint.includes(house)) return null;
      return `${house} ${n > 0 ? "+" : "−"}${Math.abs(n)}`;
    }).filter(Boolean);
    return said.length ? `${hint} · ${said.join(" · ")}` : hint;
  }

  houseFacts(pid, world, ctx) {
    const p = world.players.find((x) => x.id === pid);
    if (!p) return "";
    const h = houseFor(p);
    const temper = this.lordOfHouse(pid)?.traits.join(", ") ?? "";
    return `${h.name}: ${p.cities} towns, ${p.units} soldiers, ${p.gold} gold, favour ${Math.round(ctx.favour(pid))}${temper ? `, lord is ${temper}` : ""}`;
  }

  warlike(c) {
    return c.traits.some((t) => ["wrathful", "vengeful", "brave", "proud", "ambitious"].includes(t));
  }

  // A petition at court: a dilemma where every answer costs something. Every
  // kind the lord has cause for is a candidate; one is drawn by weight, and
  // kinds the King has heard lately are drawn less, so the court stays varied.
  // The court sits once a year (server.js): those already waiting in the hall
  // are called first, then lords with cause come, until `want` stand before
  // the King. Only called petitioners wait on a fuse.
  // A crisis comes first (the judge, from CK3 and Reigns): the lord of a
  // starving or besieged town jumps the rotation and speaks for it at this
  // sitting, once a year for the same crisis. The rotation is for ordinary
  // matters. Returns the pleas made (the bridge calls this before the Hand's
  // own matters, and drops the Hand's for a house whose lord already pleads).
  // A ruling owed back (favourbook.recordRuling): the lord the King ruled on,
  // two seasons later, by name, to repay a favour or demand amends. Ahead of
  // the rotation, after any crisis. Returns the petitions made.
  async callReturns(world, turn, want, ctx) {
    const made = [];
    // Returns are at most about one in four of the King's matters lately.
    const lately = this.petitions.filter((p) => (p.turn ?? 0) > turn - 2 * SEASONS_PER_YEAR);
    if (lately.length >= 3 && lately.filter((p) => p.kind === "remembers").length / lately.length >= 0.25) return made;
    for (const c of this.alive()) {
      if (want <= 0) break;
      if ((world.players.find((p) => p.id === c.playerId)?.cities ?? 1) === 0) continue;  // a fallen house has left the play
      if (this.petitions.some((p) => !p.answered && p.from === c.id && p.called != null)) continue;  // already before the King
      if (this.petitions.some((p) => p.from === c.id && p.kind === "remembers" && (p.turn ?? 0) > turn - SEASONS_PER_YEAR)) continue;  // once a year
      const owed = (this.deedsOf?.(c.playerId) ?? []).filter((x) => x.by === c.id && x.due != null && x.due <= turn && !x.raised).sort((a, b) => a.due - b.due)[0];
      if (!owed) continue;
      // Not always a plea (the judge: vary the return by what the ruling did). A
      // lord who was favoured may simply repay; one who was slighted may scheme;
      // one gravely wronged comes to court to demand amends.
      if (owed.d > 0 && !owed.setback && Math.random() < 0.5) {
        owed.raised = turn;
        ctx.send?.(Lua.gold(crownOf(world)?.id ?? -1, 40));
        this.record({ turn, kind: "loyalty", text: `${c.name} of ${c.house} has not forgotten the King's ruling: a chest of 40 gold comes to Kingsmere, "for the crown's kindness".`, city: c.seat ?? undefined });
        continue;
      }
      if (owed.d < 0 && owed.d > -15 && !owed.setback && Math.random() < 0.5) {
        owed.raised = turn;
        const cold = world.players.filter((x) => x.id !== c.playerId && !houseFor(x).crown && !houseFor(x).wild).sort((a, b) => (ctx.favour?.(a.id) ?? 50) - (ctx.favour?.(b.id) ?? 50))[0];
        if (cold) this.scheme({ kind: "envoy", from: c.playerId, to: cold.id, turn, secret: true, line: `${c.house}'s envoys ride to ${houseFor(cold).name}: the King's ruling at court is not forgotten.` });
        this.record({ turn, kind: "scheme", text: `${c.name} of ${c.house} says nothing of the King's ruling at court. Riders leave ${cityName(c.seat)} by night.`, city: c.seat ?? undefined });
        continue;
      }
      this.turnNow = turn;
      // What they were waiting in the hall to ask can wait: the ruling owed comes first (as a crisis does).
      this.petitions = this.petitions.filter((p) => p.answered || p.from !== c.id || p.called != null || p.kind === "arc");
      const p = await this.petition(c, world, turn, ctx, true, { urgent: true, prefer: "remembers", deed: owed });
      if (p) { p.called = turn; made.push(p); want--; }
    }
    if (made.length) this.saveCourt();
    return made;
  }

  async callCrises(world, turn, want, ctx) {
    const made = [];
    const crisisOf = (c) => {
      const mine = world.cities.filter((x) => x.owner === c.playerId);
      // A crisis with a plea of its own: a starving town's lord asks for grain,
      // a besieged one for the siege to be broken.
      return mine.some((x) => x.famine) ? "grain" : mine.some((x) => x.besieged) ? "siege" : null;
    };
    for (const c of this.alive().filter((x) => x.rank === "lord")) {
      if (want <= 0) break;
      const crisis = crisisOf(c);
      if (!crisis || this.petitions.some((p) => !p.answered && p.from === c.id && p.called != null)) continue;
      // What they were waiting in the hall to ask can wait: the crisis comes first.
      this.petitions = this.petitions.filter((p) => p.answered || p.from !== c.id || p.called != null || p.kind === "arc");
      if (this.petitions.some((p) => p.from === c.id && p.crisis === crisis && (p.turn ?? 0) > turn - SEASONS_PER_YEAR)) continue;
      this.turnNow = turn;
      const p = await this.petition(c, world, turn, ctx, true, { urgent: true, prefer: crisis });
      if (p) { p.called = turn; p.crisis = crisis; made.push(p); want--; }
    }
    if (made.length) this.saveCourt();
    return made;
  }

  async callSitting(world, turn, want, ctx) {
    for (const p of this.petitions.filter((x) => !x.answered && !x.called)) {
      if (want <= 0) break;
      p.called = turn;
      want--;
    }
    for (let tries = 0; want > 0 && tries < 8; tries++) {
      const waiting = new Set(this.petitions.filter((p) => !p.answered).map((p) => p.from));
      const all = this.alive().filter((c) => c.rank === "lord" && !waiting.has(c.id) && (world.players.find((p) => p.id === c.playerId)?.cities ?? 0) > 0);
      if (!all.length) break;
      // The lords heard longest ago come first.
      const lastHeard = (id) => Math.max(-1, ...this.petitions.filter((p) => p.from === id).map((p) => p.turn ?? 0));
      const lords = all.sort((a, b) => lastHeard(a.id) - lastHeard(b.id)).slice(0, 3);
      this.turnNow = turn;
      const made = await this.petition(lords[Math.floor(Math.random() * lords.length)], world, turn, ctx, true);
      if (made) { made.called = turn; want--; }
    }
    this.saveCourt();
  }

  async petition(c, world, turn, ctx, sitting = false, opts = {}) {
    // Outside a sitting, at most three wait in the hall for the next one.
    if (!sitting && this.petitions.filter((p) => !p.answered).length >= 3) return;
    // Many voices at court: a lord who brought one of the last few matters waits
    // their turn, so no one face fills the reign (a story's matter comes regardless).
    if (!opts.urgent && this.petitions.filter((p) => p.kind !== "arc").slice(-3).some((p) => p.from === c.id)) return;
    const base = { id: `p${Date.now().toString(36)}${Math.floor(Math.random() * 999)}`, turn, from: c.id, name: c.name, house: c.house, answered: false };
    const me = world.players.find((x) => x.id === c.playerId);
    const facts = (...pids) => pids.filter((x) => x !== undefined && x !== null && x >= 0).map((x) => this.houseFacts(x, world, ctx)).filter(Boolean);
    const myBannermen = this.alive().filter((x) => x.rank === "bannerman" && x.playerId === c.playerId);
    const myTowns = world.cities.filter((x) => x.owner === c.playerId);
    const has = (t) => c.traits.includes(t);
    const candidates = [];

    // A town taken by treachery: the old house wants it back.
    const claim = (this.claims ?? []).find((k) => k.from === c.playerId && !k.settled && world.cities.some((x) => x.id === k.city && x.owner === k.to));
    if (claim) candidates.push({ kind: "claim", weight: 6, make: () => {
      const town = cityName(claim.city);
      const thiefHouse = houseFor(world.players.find((x) => x.id === claim.to)).name;
      return { kind: "claim", claim, text: `${c.name} of ${c.house}: "${town} was ours until a traitor opened its gates to ${thiefHouse}. Give it back, Your Grace, or tell me the crown rewards treachery."`, facts: facts(c.playerId, claim.to), options: [
        { id: "return", label: `Return ${town} to ${c.house}`, hint: `${c.house} +20 · ${thiefHouse} −30, and they keep their army` },
        { id: "confirm", label: `Confirm ${thiefHouse}'s hold`, hint: `${thiefHouse} +15 · ${c.house} −30 · every bannerman learns betrayal pays` },
        { id: "seize", label: `Take ${town} for the crown`, hint: `You gain a town · both houses −20` },
      ] };
    } });

    // A feud with raids.
    const enemy = this.alive().filter((o) => o.rank === "lord" && o.id !== c.id).sort((a, b) => this.opinion(c.id, a.id) - this.opinion(c.id, b.id))[0];
    if (enemy && this.opinion(c.id, enemy.id) < -20) candidates.push({ kind: "justice", weight: 4, make: () => {
      const wrath = this.warlike(enemy);
      return { kind: "justice", enemy: enemy.id, text: `${c.name} of ${c.house} demands justice against ${enemy.name} of ${enemy.house}: "${(c.memories.filter((m) => m.includes(enemy.name) || m.includes(enemy.house)).slice(-1)[0] ?? "They raid my lands and slander my name.")} Will the King act, or must I?"`, facts: facts(c.playerId, enemy.playerId), options: [
        { id: "side", label: `Rule for ${c.house}`, hint: `${c.house} +15 · ${enemy.house} −25${wrath ? `, and ${enemy.name} is not one to swallow it` : ""}` },
        { id: "other", label: `Rule for ${enemy.house}`, hint: `${enemy.house} +15 · ${c.house} −25, and stops trusting the crown's justice` },
        { id: "peace", label: "Impose the King's peace (200 gold)", hint: "You pay reparations · both −5 · no raids between them for 2 years", cost: 200 },
        { id: "combat", label: "Trial by combat", hint: "The gods decide · the loser pays a third of their gold, and may lose a son" },
      ] };
    } });

    // A town under siege by another house: its lord begs the King to break it.
    // (A siege by the King's own host is the herald's to bring, not his.)
    const crownPid = crownOf(world)?.id;
    const ringed = myTowns.find((x) => x.besieged);
    const foe = ringed ? Object.entries((world.units ?? []).filter((u) => u.owner !== c.playerId && Math.max(Math.abs(u.x - ringed.x), Math.abs(u.y - ringed.y)) === 1)
      .reduce((n, u) => ({ ...n, [u.owner]: (n[u.owner] ?? 0) + 1 }), {})).sort((a, b) => b[1] - a[1])[0] : null;
    const besieger = foe ? world.players.find((x) => x.id === Number(foe[0])) : null;
    if (ringed && besieger && besieger.id !== crownPid && !houseFor(besieger).wild) candidates.push({ kind: "siege", weight: 6, make: () => {
      const town = cityName(ringed.id);
      const them = houseFor(besieger).name;
      return { kind: "siege", city: ringed.id, besieger: besieger.id, text: `${c.name} of ${c.house}: "${them} has ${town} ringed with spears. My people eat their boots behind the walls. Send the royal host, Your Grace, or ${town} falls."`, facts: facts(c.playerId, besieger.id), options: [
        { id: "relieve", label: `March the royal host to ${town}`, hint: `${c.house} +15 · ${them} −20 · the host leaves Kingsmere` },
        { id: "pay", label: `Pay ${them} to lift the siege (200 gold)`, hint: `${c.house} +5 · ${them} +5 · a truce between them`, cost: 200 },
        { id: "abandon", label: `Let ${town} hold or fall`, hint: `${c.house} −20 · their bannermen remember` },
      ] };
    } });

    // Hunger.
    const hungry = myTowns.filter((x) => x.famine).length;  // the bridge's one definition (server.js townStates)
    if (hungry) candidates.push({ kind: "grain", weight: 3 + hungry, make: () => {
      const donor = world.players.filter((x) => !houseFor(x).wild && !houseFor(x).crown && x.id !== c.playerId).sort((a, b) => b.gold - a.gold)[0];
      const donorHouse = donor ? houseFor(donor).name : "";
      // Each answer carries its favour as data: the hint, the weighs and the ruling (petitions.js) read the same numbers.
      const options = [{ id: "grant", label: "The crown pays (150 gold)", hint: `${c.house} +15`, cost: 150, favour: { [c.playerId]: 15 } }];
      if (donor) options.push({ id: "order", label: `Order ${donorHouse} to feed them`, hint: `Costs you nothing · ${donorHouse} −20 · ${c.house} +10`, favour: { [donor.id]: -20, [c.playerId]: 10 } });
      options.push({ id: "refuse", label: "Let them starve", hint: `${c.house} −15 · their bannermen's loyalty wavers`, favour: { [c.playerId]: -15 } });
      return { kind: "grain", donor: donor?.id, text: `${c.name} of ${c.house}: "${hungry} of my towns have empty granaries. Children are dying in the streets of my lands. I beg the crown for grain."`, facts: facts(c.playerId, donor?.id), options };
    } });

    // A match that needs the King's blessing.
    const bride = this.alive().find((k) => k.gender === "female" && k.age >= 15 && !k.spouse && this.people[k.parents?.[0]]?.house === c.house && this.people[k.parents?.[0]]?.rank === "bannerman");
    const groom = bride && this.alive().find((k) => k.gender === "male" && k.age >= 15 && !k.spouse && k.rank === "heir" && k.house !== c.house);
    if (bride && groom) candidates.push({ kind: "match", weight: 2, make: () => {
      const father = this.people[bride.parents[0]];
      return { kind: "match", bride: bride.id, groom: groom.id, text: `${father.name}, a bannerman of ${c.house}, seeks the King's blessing to wed his daughter ${bride.name} (${bride.age}) to ${groom.name}, heir of ${groom.house}. ${c.name} watches you closely: a bannerman tied to another great house is a bannerman half-lost.`, facts: facts(c.playerId, this.people[groom.parents?.[0]]?.playerId), options: [
        { id: "bless", label: "Bless the match", hint: `${groom.house} +10 · ${c.house} −10 · ${father.name}'s loyalty drifts to ${groom.house}` },
        { id: "forbid", label: "Forbid it", hint: `${c.house} +10 · ${groom.house} −10 · ${father.name} resents you` },
        { id: "ward", label: "Take her as a royal ward (100 gold)", hint: `Neither house gains · ${father.name} owes the crown`, cost: 100 },
      ] };
    } });

    // A thin treasury: the house asks to be spared the tithe, or for a loan.
    if (me && me.gold < 80) candidates.push({ kind: "debt", weight: 3, make: () => ({ kind: "debt", text: `${c.name} of ${c.house}: "The tithe has bled my coffers dry, Your Grace. ${me.gold} gold is all that stands between my house and ruin. Spare us, or lend us enough to stand."`, facts: facts(c.playerId), options: [
      { id: "forgive", label: "Return this year's tithe (100 gold)", hint: `${c.house} +15 · other houses ask why they still pay`, cost: 100 },
      { id: "lend", label: "Lend 250 gold, repaid with interest", hint: `They owe the crown 325 gold in two years · if they cannot pay, they will hate you for asking`, cost: 250 },
      { id: "refuse", label: "Every house pays its share", hint: `${c.house} −10${has("proud") ? ` · ${c.name} is proud, and will not beg twice` : ""}` },
    ] }) });

    // Outlaws on the roads of the house's lands.
    if (myTowns.length >= 2) candidates.push({ kind: "outlaws", weight: 2, make: () => {
      const town = myTowns[Math.floor(Math.random() * myTowns.length)];
      return { kind: "outlaws", city: town.id, text: `${c.name} of ${c.house}: "Outlaws hold the forest road outside ${cityName(town.id)}. They rob the carts and hang my tax collectors from the oaks. My own men are spread thin."`, facts: facts(c.playerId), options: [
        { id: "hunt", label: "Send the King's riders (120 gold)", hint: `Three knights ride for ${c.house} · ${c.house} +15`, cost: 120 },
        { id: "pardon", label: "Pardon them into the King's service", hint: `The crown gains two companies · ${c.house} −15, their dead unavenged` },
        { id: "theirs", label: "It is a lord's duty to keep his roads", hint: `${c.house} −5 · the outlaws keep taking their taxes (−60 gold)` },
      ] };
    } });

    // An informer: a bannerman warns that another great lord is arming.
    const suspect = this.alive().find((o) => o.rank === "lord" && o.house !== c.house && !o.hostage && ctx.favour(o.playerId) < 45 && o.children.some((id) => this.people[id]?.alive));
    if (suspect && myBannermen.length) candidates.push({ kind: "informer", weight: 3, make: () => {
      const informer = myBannermen[Math.floor(Math.random() * myBannermen.length)];
      const heir = suspect.children.map((id) => this.people[id]).find((k) => k?.alive);
      return { kind: "informer", informer: informer.id, suspect: suspect.id, heir: heir.id, text: `${informer.name}, sworn to ${c.house}, speaks low: "${suspect.name} of ${suspect.house} is buying swords and sending ravens at night. I have seen it, Your Grace. Act before he does."`, facts: facts(c.playerId, suspect.playerId), options: [
        { id: "hostage", label: `Demand ${heir.name} as a royal ward`, hint: `${suspect.house} −20 · but ${suspect.name} will not rise while you hold his child` },
        { id: "reward", label: `Pay the informer (60 gold)`, hint: `${informer.name} becomes the crown's man · ${suspect.name} learns who talked`, cost: 60 },
        { id: "dismiss", label: "Dismiss it as slander", hint: `${suspect.house} +5 · ${informer.name} resents being called a liar` },
      ] };
    } });

    // A child lord, or an old one with no grown son: who governs?
    const regentFor = c.age < 16 || (c.age > 60 && !c.children.some((id) => this.people[id]?.alive && this.people[id].gender === "male" && this.people[id].age >= 16));
    if (regentFor && myBannermen.length) candidates.push({ kind: "regency", weight: 4, make: () => {
      const strong = [...myBannermen].sort((a, b) => b.loyalty - a.loyalty)[0];
      return { kind: "regency", regent: strong.id, text: c.age < 16
        ? `The bannermen of ${c.house} come to court with their young lord ${c.name}, who is ${c.age}. ${strong.name} offers to govern until the boy is grown. Others whisper he means to govern for good.`
        : `${c.name} of ${c.house} is ${c.age} and has no grown son. ${strong.name}, his strongest bannerman, asks to be named his heir. The lord's kin protest.`, facts: facts(c.playerId), options: [
        { id: "regent", label: `Name ${strong.name}`, hint: `${strong.name} is bound to the crown · ${c.house}'s kin −10` },
        { id: "crown", label: "The crown governs (takes a quarter of their gold)", hint: `You gain gold · ${c.house} −15 · their bannermen are leaderless no longer` },
        { id: "leave", label: "Let the house settle it", hint: `Costs nothing · ${strong.name} may decide he needs no one's leave` },
      ] };
    } });

    // The Faith: a preacher blames the King for the realm's troubles.
    const troubled = world.cities.filter((x) => x.famine).length;
    if (has("pious") || troubled >= 3) candidates.push({ kind: "faith", weight: 1 + Math.min(4, troubled), make: () => ({ kind: "faith", text: `A barefoot friar has come to ${c.house}'s lands with ${troubled ? `${troubled} hungry towns` : "the poor"} at his back. He preaches that the gods have turned from a sinful King. ${c.name}${has("pious") ? ", a pious man," : ""} asks what the crown will do.`, facts: facts(c.playerId), options: [
      { id: "endow", label: "Endow the Faith (150 gold)", hint: "Every house +4 · the Faith blesses your name", cost: 150 },
      { id: "silence", label: "Have him silenced", hint: `The preaching stops · ${has("pious") ? `${c.house} −20, ${c.name} is appalled` : `${c.house} −5`} · the poor remember` },
      { id: "ignore", label: "Words are wind", hint: "Every house −3 · the sermon spreads" },
    ] }) });

    // A lord who remembers: a deed of the King's, a year old or more, brought
    // back to his face. The simulation picks the deed; the model only voices it.
    // A lord comes back about the past at most once a year (Builder 2's check: one lord returned 7 times in a reign).
    const backLately = this.petitions.some((x) => x.from === c.id && x.kind === "remembers" && (x.turn ?? 0) > turn - SEASONS_PER_YEAR);
    const lately = this.petitions.filter((x) => (x.turn ?? 0) > turn - 2 * SEASONS_PER_YEAR);
    const tooMany = lately.length >= 3 && lately.filter((x) => x.kind === "remembers").length / lately.length >= 0.25;
    const owed = backLately || tooMany ? [] : (this.deedsOf?.(c.playerId) ?? []).filter((x) => Math.abs(x.d) >= 8 && x.turn <= turn - 4 && (!x.raised || x.raised <= turn - 12));
    const fav = ctx.favour?.(c.playerId) ?? 50;
    const grudge = owed.filter((x) => x.d < 0).sort((a, b) => a.d - b.d)[0];
    const kindness = owed.filter((x) => x.d > 0).sort((a, b) => b.d - a.d)[0];
    const deed = opts.deed ?? (fav < 55 ? (grudge ?? kindness) : (kindness ?? grudge));
    // The lord this one hates most (sworn enemy): an oath to the crown sets their house against the crown too.
    const sworn = this.alive().filter((x) => x.rank === "lord" && x.playerId !== c.playerId).sort((a, b) => this.opinion(c.id, a.id) - this.opinion(c.id, b.id))[0];
    if (deed) candidates.push({ kind: "remembers", deed: deed.what, weight: deed.d < 0 ? 7 : 4, make: () => {
      deed.raised = turn;
      const when = calendar(deed.turn);
      // Once: "Two years ago, in the winter of 352, you took a town that was ours."
      // Year on year: "Since the winter of 352 you have bled us with the tithe, year after year."
      const ago = Math.max(1, Math.floor(yearsIn(turn - deed.turn)));
      // A ruling a season or two old: "In the spring of 312, you heard our plea at court and ruled: ...".
      const said = deed.last - deed.turn >= 4
        ? `Since the ${when.season} of ${when.year}, you ${deed.what}, year after year`
        : turn - deed.turn < 4 ? `In the ${when.season} of ${when.year}, you ${deed.what}`
        : `${ago === 1 ? "A year" : ago === 2 ? "Two years" : ago === 3 ? "Three years" : `${ago} years`} ago, in the ${when.season} of ${when.year}, you ${deed.what}`;
      if (deed.d < 0) {
        const threat = fav < 35 ? " Do not look for our banners until it is set right." : " I would hear the crown set it right.";
        return { kind: "remembers", deed: deed.what, grudge: true, text: `${c.name} of ${c.house}: "${said}. ${c.house} has not forgotten it, Your Grace.${threat}"`, facts: facts(c.playerId), options: [
          { id: "amend", label: "Make amends (120 gold)", hint: `${c.house} +15 · the grudge is laid to rest`, cost: 120, favour: { [c.playerId]: 15 } },
          { id: "hear", label: "Hear him out, promise nothing", hint: `${c.house} +3 now · the grudge deepens, and they'll be back within the year`, favour: { [c.playerId]: 3 } },
          { id: "firm", label: "The crown did what it must", hint: `${c.house} −8 · ${c.name} adds this to the account`, favour: { [c.playerId]: -8 } },
        ] };
      }
      return { kind: "remembers", deed: deed.what, grudge: false, text: `${c.name} of ${c.house}: "${said}. ${c.house} remembers its friends, Your Grace. Our swords are yours when you call."`, facts: facts(c.playerId), options: [
        // Neither answer is free: an oath binds them, and sets their sworn enemy against the crown; gold is gold, and costs thanks.
        { id: "oath", label: "Take their oath", hint: `${c.house} +6 · ${c.name} is bound to the crown${sworn ? ` · ${sworn.house} −6, wary of the crown's new sword` : ""}`, favour: { [c.playerId]: 6, ...(sworn ? { [sworn.playerId]: -6 } : {}) } },
        { id: "purse", label: "Ask for gold toward the realm", hint: `The crown gains 60 gold · ${c.house} −4`, favour: { [c.playerId]: -4 } },
      ] };
    } });

    // A bannerman who has served well asks to be raised.
    const loyal = myBannermen.find((b) => b.loyalty >= 70 && (b.traits.includes("brave") || b.traits.includes("ambitious")));
    if (loyal) candidates.push({ kind: "raise", weight: 2, make: () => ({ kind: "raise", man: loyal.id, text: `${loyal.name}, bannerman of ${c.house}, kneels before the throne. He held the line when others ran and asks to be made a lord in his own right, sworn to the crown alone. ${c.name} stands stiffly beside him.`, facts: facts(c.playerId), options: [
      { id: "raise", label: `Raise ${loyal.name} (80 gold)`, hint: `A lord who owes you everything · ${c.house} −15, a vassal lost`, cost: 80 },
      { id: "honour", label: "Honour him with a sword, not a seat", hint: `${loyal.name} +loyalty to his liege · ${c.house} +5` },
      { id: "refuse", label: "Send him back to his liege", hint: `${c.house} +10 · ${loyal.name} remembers the crown would not reward him` },
    ] }) });

    // His want itself (data/ambitions.json plea): a lord who wants land or power asks the King's leave to take a
    // town from another great house.
    const want = c.rank === "lord" ? this.ambitionOf(c, world) : null;
    if (want?.target?.kind === "town") candidates.push({ kind: "ambition", weight: AMB.plea.weight, make: () => {
      const t = want.target;
      return { kind: "ambition", city: t.id, holder: t.pid, text: `${c.name} of ${c.house}: "${t.name} should be ours, Your Grace, and ${t.house} holds it badly. Give me your leave and I will take it."`, facts: facts(c.playerId, t.pid), options: [
        { id: "back", label: `Give ${c.name} leave to take ${t.name}`, hint: `${c.house} +${AMB.plea.back.him} · ${t.house} ${AMB.plea.back.holder}, and war between them`, favour: { [c.playerId]: AMB.plea.back.him, [t.pid]: AMB.plea.back.holder } },
        { id: "forbid", label: "Forbid it", hint: `${c.house} ${AMB.plea.forbid.him} · ${t.house} +${AMB.plea.forbid.holder}`, favour: { [c.playerId]: AMB.plea.forbid.him, [t.pid]: AMB.plea.forbid.holder } },
        { id: "promise", label: `Promise him something smaller (${AMB.plea.promise.cost} gold)`, hint: `${c.house} +${AMB.plea.promise.him} · the want stays`, cost: AMB.plea.promise.cost, favour: { [c.playerId]: AMB.plea.promise.him } },
      ] };
    } });

    for (const card of loadDeck()) {
      const roles = this.cast(card, c, world, ctx);
      if (roles) candidates.push({ kind: card.id, deck: true, weight: card.weight ?? 2, make: () => this.deal(card, roles, c, world, facts) });
    }

    const open = new Set(this.petitions.filter((p) => !p.answered).map((p) => p.kind));
    const recent = this.petitions.slice(-6).map((p) => p.kind);
    // No matter is put to the King twice in a reign: a dealt dilemma once, a
    // lord's own kind of plea once per house, a remembered deed once.
    const heard = (x) => x.deck ? `card:${x.kind}` : x.deed ? `remembers:${c.house}:${x.deed}` : `${x.kind}:${c.house}`;
    // A plea his want drives weighs more (data/ambitions.json drives, boost): his want shows in what he brings.
    const driven = new Set(AMB.drives[c.goals?.[0]?.kind] ?? []);
    const pool = candidates.filter((x) => !open.has(x.kind) && !ctx.heard?.(heard(x))).map((x) => ({ ...x, w: x.weight * (driven.has(x.kind) ? AMB.boost : 1) / (1 + 2 * recent.filter((k) => k === x.kind).length) }));
    // A crisis brings its own plea (a starving town's lord asks for grain), whatever was heard lately.
    const forced = opts.prefer ? candidates.find((x) => x.kind === opts.prefer) : null;
    if (opts.prefer && !forced) return;  // a crisis plea is that plea or nothing
    if (!pool.length && !forced) return;
    let roll = Math.random() * pool.reduce((t, x) => t + x.w, 0);
    const chosen = forced ?? pool.find((x) => (roll -= x.w) < 0) ?? pool[pool.length - 1];
    const p = { ...base, ...chosen.make(), heard: heard(chosen) };
    ctx.hear?.(p.heard);
    // They come to court now; their own words follow when the local model has
    // them (it can be slow or busy, and the court never waits on it).
    this.petitions.push(p);
    if (this.petitions.length > 60) this.petitions = this.petitions.filter((x) => !x.answered || x.turn > turn - 40);
    this.record({ turn, kind: "court", text: say("event.court", { name: c.name, house: c.house }) });
    this.saveCourt();
    this.ask(c, `You stand before the King to say: ${p.text}`, ["speak"]).then((d) => {
      if (d?.line && !p.answered) { p.voice = d.line; this.saveCourt(); }
    }).catch(() => {});
    return p;
  }

  // A matter a story brings to the King (arcs.js toCourt): it comes whatever
  // else is waiting, and his answer goes back to the story.
  // Who stands before the King on a card: enough to paint them and say what
  // they want of the reign. A lord's aim is in their own words ("see my
  // daughter wed"); the card says it of them.
  sitter(cid) {
    const c = cid != null ? this.people[cid] : null;
    if (!c) return null;
    const theirWords = (t) => t.replace(/\bmy\b/g, "their").replace(/\bme\b/g, "them").replace(/\bI am\b/g, "they are").replace(/\bI\b/g, "they");
    return { id: c.id, name: c.name, age: c.age, gender: c.gender, role: c.role ?? null, rank: c.rank ?? null, want: c.goals?.[0]?.text ? theirWords(c.goals[0].text) : null };
  }

  arcPetition({ arc, beat, thread, from, text, options }, world) {
    if (this.petitions.some((p) => !p.answered && p.arc === arc && p.beat === beat)) return;
    const p = { id: `p${Date.now().toString(36)}${Math.floor(Math.random() * 999)}`, turn: world?.turn ?? 0, from: from.id, name: from.name, house: from.house, answered: false, kind: "arc", arc, beat, thread, text, options };
    this.petitions.push(p);
    this.record({ turn: p.turn, kind: "court", text: `${from.name} of ${from.house} comes to court: ${thread}.` });
    this.saveCourt();
  }

  // --- the deck: dilemmas written as data (data/dilemmas.json) ----------------

  // Finds who plays each part a card needs, or null if the card can't be dealt
  // to this lord now. Roles: me, rival, friend, bannerman, heir, daughter, town.
  cast(card, c, world, ctx) {
    const w = card.when ?? {};
    const me = world.players.find((x) => x.id === c.playerId);
    if (!me) return null;
    const towns = world.cities.filter((x) => x.owner === c.playerId);
    const hungry = towns.filter((x) => x.famine).length;
    if (w.poor && me.gold >= 80) return null;
    if (w.rich && me.gold < 250) return null;
    if (w.hungry && !hungry) return null;
    if (w.fed && hungry) return null;
    if (w.towns && towns.length < w.towns) return null;
    if (w.trait && !w.trait.some((t) => c.traits.includes(t))) return null;
    if (w.favourBelow !== undefined && ctx.favour(c.playerId) >= w.favourBelow) return null;
    if (w.favourAbove !== undefined && ctx.favour(c.playerId) <= w.favourAbove) return null;
    // A wet harvest (bridge weather.js): only after two wet seasons running, or a storm at harvest.
    if (w.wetHarvest && !ctx.wetHarvest?.()) return null;
    // The crown's purse below one big thing's worth (economy.json thin); a lender with the gold to lend.
    if (w.thinTreasury && !ctx.thinTreasury?.()) return null;
    if (w.goldAbove !== undefined && (me.gold ?? 0) < w.goldAbove) return null;
    if (w.age && (c.age < w.age[0] || c.age > w.age[1])) return null;
    if (w.chance !== undefined && Math.random() > w.chance) return null;
    // The realm's own state (the bridge's one definitions on each town; Freeciv's wars):
    // a card is dealt only where the realm makes it true.
    const hot = towns.filter((x) => x.disorder);
    const thriving = towns.filter((x) => x.prosperity);
    const isWild = (pid) => houseFor(world.players.find((p) => p.id === pid) ?? {}).wild;
    // Raiders are men (barbarians, sea raiders), not the wild beasts.
    const raider = (pid) => { const p = world.players.find((x) => x.id === pid); return !!p && /raiders/.test(houseFor(p).name ?? ""); };
    const raided = towns.filter((x) => (world.units ?? []).some((u) => raider(u.owner) && Math.max(Math.abs(u.x - x.x), Math.abs(u.y - x.y)) <= 3));
    const north = northTowns({ cities: towns });
    const warring = world.players.some((p) => p.id !== c.playerId && !isWild(p.id) && ctx.atWar?.(c.playerId, p.id));
    if (w.atWar && !warring) return null;
    if (w.disorder && !hot.length) return null;
    if (w.prosperity && !thriving.length) return null;
    if (w.raiders && !raided.length) return null;
    if (w.north && !north.length) return null;
    const lords = this.alive().filter((o) => o.rank === "lord" && o.id !== c.id && o.house !== c.house);
    // A war card's rival is a lord his house is at war with; otherwise the one he likes least.
    const foes = lords.filter((l) => ctx.atWar?.(c.playerId, l.playerId));
    const byOpinion = [...(w.rivalWar && foes.length ? foes : w.rivalPeace ? lords.filter((l) => !foes.includes(l)) : lords)].sort((a, b) => this.opinion(c.id, a.id) - this.opinion(c.id, b.id));
    const kids = c.children.map((id) => this.people[id]).filter((k) => k?.alive).sort((a, b) => b.age - a.age);
    const bms = this.alive().filter((x) => x.rank === "bannerman" && x.playerId === c.playerId);
    const anyOf = (arr) => arr[Math.floor(Math.random() * arr.length)];
    const roles = {
      me: c,
      rival: byOpinion[0],
      friend: byOpinion[byOpinion.length - 1],
      bannerman: anyOf(bms),
      heir: kids.find((k) => k.age >= 12),
      daughter: kids.find((k) => k.gender === "female" && k.age >= 14 && !k.spouse),
      town: anyOf(towns),
    };
    // The rival's unwed son: a suitor, an abductor, a runaway's lover.
    roles.suitor = roles.rival && roles.rival.children.map((id) => this.people[id]).find((k) => k?.alive && k.gender === "male" && k.age >= 15 && !k.spouse);
    roles.rivalTown = roles.rival && anyOf(world.cities.filter((x) => x.owner === roles.rival.playerId && !x.capital));
    if (roles.friend === roles.rival) roles.friend = undefined;
    for (const need of card.needs ?? []) if (!roles[need]) return null;
    // A role the card names in its words is needed too, listed or not: no "{rivalTown}" left in the hall.
    for (const named of new Set((JSON.stringify([card.text, card.options]).match(/\{(\w+)(?:\.\w+)?\}/g) ?? []).map((m) => m.slice(1, -1).split(".")[0])))
      if (named !== "me" && !roles[named]) return null;
    if (w.feud && !(roles.rival && this.opinion(c.id, roles.rival.id) < -15)) return null;
    if (w.rivalWar && !(roles.rival && ctx.atWar?.(c.playerId, roles.rival.playerId))) return null;
    if (w.rivalPeace && roles.rival && ctx.atWar?.(c.playerId, roles.rival.playerId)) return null;
    // The town the card is about is the one the realm's state is in.
    if (w.disorder) roles.town = anyOf(hot);
    else if (w.raiders) roles.town = anyOf(raided);
    else if (w.prosperity) roles.town = anyOf(thriving);
    else if (w.north) roles.town = anyOf(north);
    return roles;
  }

  fill(text, roles) {
    return String(text ?? "").replace(/\{(\w+)(?:\.(\w+))?\}/g, (_, role, field) => {
      const r = roles[role];
      if (!r) return _;
      if (role === "town" || role === "rivalTown") return cityName(r.id);
      if (field === "house") return r.house;
      const f = r.gender === "female";
      const pron = { he: f ? "she" : "he", He: f ? "She" : "He", his: f ? "her" : "his", His: f ? "Her" : "His", him: f ? "her" : "him", himself: f ? "herself" : "himself", wife: f ? "husband" : "wife", son: f ? "daughter" : "son", man: f ? "woman" : "man", lord: f ? "lady" : "lord", father: f ? "mother" : "father" };
      if (field in pron) return pron[field];
      return field ? String(r[field] ?? "") : r.name;
    });
  }

  deal(card, roles, c, world, facts) {
    const ids = {};
    for (const [k, v] of Object.entries(roles)) if (v) ids[k] = v.id;
    const housesIn = [c.playerId, ...["rival", "friend"].filter((r) => (card.needs ?? []).includes(r)).map((r) => roles[r].playerId)];
    return {
      kind: card.id, deck: true, roles: ids,
      text: this.fill(card.text, roles),
      facts: facts(...housesIn),
      options: card.options.map((o) => ({ id: o.id, label: this.fill(o.label, roles), hint: this.withFavour(this.fill(o.hint, roles), o.effects?.favour, roles), ...(o.cost ? { cost: o.cost } : {}) })),
    };
  }

  // Applies a deck answer's effects. Each effect names roles; "all" is every great house.
  // What an answer would do to the houses' favour, before it's given (bet 5),
  // read from the card's own effects (a deck card) or the option's favour (a
  // story's): {cost, helps: [{house, d}], hurts: [{house, d}]}, or null for a
  // plea whose answer is worked out in code (petitions.js).
  weighOption(p, o, world) {
    let map = null;
    if (p.deck) {
      const card = loadDeck().find((x) => x.id === p.kind);
      const e = card?.options.find((x) => x.id === o.id)?.effects;
      if (!e) return null;
      const houses = world.players.filter((x) => !houseFor(x).crown && !houseFor(x).wild);
      const crown = crownOf(world);
      const pidOf = (role) => role === "crown" ? crown?.id : (role === "town" || role === "rivalTown" ? world.cities.find((x) => x.id === p.roles?.[role])?.owner : this.people[p.roles?.[role]]?.playerId);
      map = {};
      for (const [role, v] of Object.entries(e.favour ?? {})) {
        if (role === "all") houses.forEach((h) => { map[h.id] = (map[h.id] ?? 0) + v; });
        else { const pid = pidOf(role); if (pid != null) map[pid] = (map[pid] ?? 0) + v; }
      }
    } else if (p.kind === "arc" || o.favour) map = o.favour ?? {};  // a story's, or a plea that carries its favour with its options
    if (!map) return null;
    const name = (pid) => names.shown(houseFor(world.players.find((x) => x.id === Number(pid)) ?? {}).name);
    const rows = Object.entries(map).filter(([, d]) => d).map(([pid, d]) => ({ house: name(pid), d })).filter((r) => r.house);
    return { cost: o.cost ?? 0, helps: rows.filter((r) => r.d > 0).sort((a, b) => b.d - a.d), hurts: rows.filter((r) => r.d < 0).sort((a, b) => a.d - b.d) };
  }

  play(p, option, world, out, gold) {
    const card = loadDeck().find((x) => x.id === p.kind);
    const o = card?.options.find((x) => x.id === option);
    if (!o) return;
    const roles = {};
    for (const [k, id] of Object.entries(p.roles ?? {})) roles[k] = k === "town" || k === "rivalTown" ? world.cities.find((x) => x.id === id) ?? { id } : this.people[id];
    const e = o.effects ?? {};
    const houses = world.players.filter((x) => !houseFor(x).crown && !houseFor(x).wild);
    const crown = crownOf(world);
    const pidOf = (role) => role === "crown" ? crown?.id : roles[role]?.playerId;
    const each = (map, fn) => { for (const [role, v] of Object.entries(map ?? {})) { if (role === "all") houses.forEach((h) => fn(h.id, v, null)); else if (roles[role] || role === "crown") fn(pidOf(role), v, roles[role]); } };
    each(e.favour, (pid, v) => { if (pid !== undefined) out.favour[pid] = (out.favour[pid] ?? 0) + v; });
    each(e.gold, (pid, v) => { if (pid !== undefined) gold(pid, v); });
    each(e.loyalty, (_, v, who) => { if (who?.loyalty !== undefined) { who.loyalty = Math.max(0, Math.min(100, who.loyalty + v)); this.save(who); } });
    each(e.memory, (_, v, who) => { if (who?.memories) { this.remember(who.id, this.fill(v, roles)); this.save(who); } });
    each(e.goal, (_, v, who) => { if (who?.goals) { who.goals.unshift({ kind: v.kind, text: this.fill(v.text, roles) }); who.goals = who.goals.slice(0, 3); this.save(who); } });
    each(e.units, (pid, v) => {
      const seat = world.cities.find((x) => x.owner === pid && x.capital) ?? world.cities.find((x) => x.owner === pid);
      if (seat) out.lua.push(Lua.levy(seat.id, Array(Number(v.count ?? v) || 1).fill(`${v.type ?? "Pikemen"}|Warriors`)));
    });
    for (const [a, b, d] of e.opinion ?? []) if (roles[a] && roles[b]) { this.shift(roles[a].id, roles[b].id, d); this.save(roles[a]); }
    // The crown borrows: repaid with interest in loan.seasons, or the King's word is broken (collect).
    if (e.loan && roles.me) (this.debts ??= []).push({ pid: roles.me.playerId, amount: Number(e.loan.amount), due: (world.turn ?? 0) + Number(e.loan.seasons ?? 8), owed: true });
    // The tithe raised to the card's rate (never lowered by it): the court applies it (court.js rule).
    if (e.tithe != null) out.tithe = Number(e.tithe);
    if (e.truce && roles.me && roles.rival) this.makeTruce(roles.me, roles.rival, 8 * e.truce, world);
    if (e.dies && roles[e.dies.who] && Math.random() < (e.dies.chance ?? 1)) {
      const who = roles[e.dies.who];
      who.alive = false;
      this.save(who);
      this.record({ turn: world.turn, kind: "death", text: this.fill(e.dies.text ?? `{${e.dies.who}} is dead.`, roles) });
    }
    if (e.marry && roles[e.marry[0]] && roles[e.marry[1]]) { const [x, y] = [roles[e.marry[0]], roles[e.marry[1]]]; x.spouse = y.id; y.spouse = x.id; this.save(x); this.save(y); }
    if (e.ward && roles[e.ward]) { roles[e.ward].ward = true; if (roles.me) roles.me.hostage = roles[e.ward].id; this.save(roles[e.ward]); }
    // Men without banners fall on a town of the victim's: Freeciv's barbarians, raised beside it (realm_raid).
    if (e.raid && roles[e.raid[1]]) {
      const prey = roles.rivalTown && roles[e.raid[1]] === roles.rival ? roles.rivalTown : richestTown(world, roles[e.raid[1]].playerId);
      if (prey?.x !== undefined) out.lua.push(Lua.raid(prey.id));
      if (roles[e.raid[0]]) this.shift(roles[e.raid[1]].id, roles[e.raid[0]].id, -40);
    }
    // War: a host is raised at the attacker's town nearest the victim's and marches on it (hosts.js warpath),
    // and Freeciv's own AI fights the battle at its walls.
    if (e.war && roles[e.war[0]] && roles[e.war[1]]) {
      const [atk, def] = [roles[e.war[0]], roles[e.war[1]]];
      const prey = (def === roles.rival && roles.rivalTown) || world.cities.find((x) => x.owner === def.playerId && !x.capital) || world.cities.find((x) => x.owner === def.playerId);
      if (prey?.x !== undefined) {
        this.onWar?.([atk.playerId, def.playerId]);  // the war itself, in Freeciv (the one diplomacy writer), so the host fights
        out.lua.push(Lua.warHost(atk.playerId, prey.id, ["Pikemen", "Archers", "Knights", "Catapult"], Number(e.warSize ?? 8)));  // raised at home, it marches (hosts.js warpath)
      }
      const muster = warMuster(world, atk.playerId, prey);
      if (muster) (out.musters ??= []).push(muster);  // court.js rulingScene shows it
      this.shift(def.id, atk.id, -60);
      this.shift(atk.id, def.id, -30);
      if (this.truces) delete this.truces[[atk.id, def.id].sort().join(":")];
      this.record({ turn: world.turn, kind: "rebellion", text: `${atk.house} marches on ${prey ? cityName(prey.id) : def.house}. War between ${atk.house} and ${def.house}.`, city: prey?.id });
    }
    out.text = this.fill(wording(`${card.id}.${o.id}`, o.text), roles);  // a list: one of its wordings, not one heard lately (say.js)
  }

  // Loans from the crown fall due after two years: paid, or defaulted on.
  collect(world, turn, ctx) {
    for (const debt of this.debts ?? []) {
      if (debt.settled || turn < debt.due) continue;
      debt.settled = true;
      const p = world.players.find((x) => x.id === debt.pid);
      const lord = this.lordOfHouse(debt.pid);
      // What the crown owes a house: paid back if the treasury can, else the King's word is broken.
      if (debt.owed) {
        const crown = crownOf(world);
        if (p && crown && crown.gold >= debt.amount) {
          ctx.send(Lua.pay(crown.id, debt.pid, debt.amount));
          this.record({ turn, kind: "court", text: `The crown repays ${houseFor(p).name} the ${debt.amount} gold it borrowed, with interest.` });
        } else if (p) {
          ctx.shift({ [debt.pid]: -15 }, "the crown's unpaid debt");
          if (lord) { this.remember(lord.id, "I lent the King gold when his treasury was empty. He never paid it back."); this.save(lord); }
          ctx.deed?.("loan_unpaid", debt.pid);
          this.record({ turn, kind: "unrest", text: `The crown cannot repay the ${debt.amount} gold it owes ${houseFor(p).name}. They say the King's word is worth less than his coin.` });
        }
        continue;
      }
      if (p && p.gold >= debt.amount) {
        ctx.send(Lua.pay(debt.pid, crownOf(world)?.id ?? -1, debt.amount));
        this.record({ turn, kind: "court", text: `${houseFor(p).name} repays the crown ${debt.amount} gold, with interest.` });
      } else if (lord) {
        ctx.shift({ [debt.pid]: -15 }, "shamed over the crown's loan");
        this.remember(lord.id, "The crown's loan came due and I could not pay. The King's men counted my silver in front of my children.");
        this.record({ turn, kind: "unrest", text: `${lord.house} defaults on the crown's loan. ${lord.name} will not meet the King's eye.` });
      }
    }
  }

  // The court closed with this petitioner unheard (server.js closeCourt): they
  // go home, and their house takes the King's silence as an answer.
  unheard(p, turn, shift) {
    p.answered = "ignored";
    if (p.kind === "arc") this.onArcRuling?.(p.arc, p.beat, "ignored");
    const c = this.people[p.from];
    if (!c) return;
    shift({ [c.playerId]: -12 }, "left unheard at court");
    this.remember(c.id, "I waited at court, and the King never answered.");
    this.record({ turn, kind: "unrest", text: `The King said nothing to ${c.name} of ${c.house}, who leaves Kingsmere unheard and says so to anyone who will listen.` });
  }

  // A truce that runs out is news: the King's peace between two houses has ended.
  endTruces(turn) {
    for (const [k, until] of Object.entries(this.truces ?? {})) {
      if (until > turn) continue;
      delete this.truces[k];
      const [a, b] = k.split(":").map((id) => this.people[id]);
      if (a && b && a.alive !== false && b.alive !== false && a.house !== b.house)
        this.record({ turn, kind: "betrayal", text: `The truce between ${a.house} and ${b.house} has run its course. Nothing now holds their swords.` });
    }
  }

  // A truce between two lords, by whatever cause (a ruling, a story, a match):
  // their own key, and through onTruce (the bridge's houseTruce) the houses'
  // truce and Freeciv's ceasefire. The one way a truce is made.
  makeTruce(a, b, seasons, world) {
    if (!a || !b) return;
    this.truces ??= {};
    this.truces[[a.id, b.id].sort().join(":")] = (world?.turn ?? 0) + seasons;
    if (a.playerId != null && b.playerId != null && a.playerId !== b.playerId) this.onTruce?.([a.playerId, b.playerId], seasons);
  }

  truce(a, b) {
    const k = [a, b].sort().join(":");
    if ((this.truces ?? {})[k] > (this.turnNow ?? 0)) return true;
    // A peace the King commanded binds the houses, whoever leads them now.
    const [pa, pb] = [a, b].map((id) => this.people[id]?.playerId);
    return pa != null && pb != null && (this.truces ?? {})[`h:${Math.min(pa, pb)}:${Math.max(pa, pb)}`] > (this.turnNow ?? 0);
  }

  // The King's answer. Returns {text, cost, favour: {pid: delta}, lua: []}.
  answer(pid, option, world) {
    const p = this.petitions.find((x) => x.id === pid && !x.answered);
    if (!p) return { error: "no such petition" };
    const c = this.people[p.from];
    const opt = p.options.find((o) => o.id === option);
    if (!opt) return { error: "no such answer" };
    p.answered = option;
    const out = { cost: opt.cost ?? 0, favour: {}, lua: [], text: "" };
    const gold = (pid2, amount) => out.lua.push(Lua.gold(pid2, amount));
    const handler = ANSWERS[p.kind];
    if (handler) {
      handler.call(this, { p, c, opt, option, out, gold, world });
    } else if (p.kind === "arc") {
      for (const [pid, n] of Object.entries(opt.favour ?? {})) out.favour[pid] = n;
      out.text = opt.result || `The King gives his answer: ${String(opt.label).toLowerCase()}.`;
      // The petitioner keeps the King's answer: it comes back in what they ask later.
      if (c) { this.remember(c.id, `I came before the King and he chose: ${String(opt.label).toLowerCase()}.`); this.save(c); }
      this.onArcRuling?.(p.arc, p.beat, option);
    } else if (p.deck) {
      this.play(p, option, world, out, gold);
    }
    this.saveCourt();
    this.save(c);
    return out;
  }

  // For the view: a town's lord and family, and open petitions.
  summary(cityId) {
    const lord = this.lordOfTown(cityId);
    if (!lord) return null;
    const fam = [lord.spouse, ...lord.children].map((id) => this.people[id]).filter((x) => x?.alive);
    return {
      lord: { name: lord.name, age: lord.age, gender: lord.gender, rank: lord.rank, traits: lord.traits, goal: lord.goals[0]?.text, loyalty: lord.loyalty, memories: lord.memories.slice(-3) },
      family: fam.map((x) => ({ name: x.name, age: x.age, rank: x.rank, spouse: x.spouse ? this.people[x.spouse]?.name : null })),
    };
  }

  open() {
    // Who stands before the King, enough to paint them on the card (portrait.gd).
    // Each great house speaks in its own register before its matter: plain in the
    // North, by the ledger in the West, by the tide on the islands, and so on.
    const ADDRESS = {
      "House Wolfholt": "Plain words from the North, Your Grace.",
      "House Goldcrest": "Your Grace, a matter of accounts, and of what is owed.",
      "House Ironreach": "The sea doesn't wait, Sire, and neither will we.",
      "House Thornvale": "With respect, and the gods' blessing on the King.",
      "House Stormhold": "We have weathered worse, Your Grace. Hear us all the same.",
      "House Sunspire": "The South has waited long enough, Your Grace.",
      "House Highfell": "On our oath to the crown, Your Grace.",
    };
    // And the one thing they want of this reign, shown on their card.
    const who = (cid) => this.sitter(cid);
    return this.petitions.filter((p) => !p.answered).map(({ id, text, voice, facts, options, house, name, from, arc, beat, thread, called, kind }) => ({ id, text, voice, facts, options, house, name, from, who: who(from), address: ADDRESS[house] ?? null, kind, called: called ?? null, ...(arc ? { arc, beat, thread } : {}), due: null }));
  }
}
