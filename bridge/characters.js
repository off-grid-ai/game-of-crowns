// The people of the realm. Every lord, lady, heir and bannerman is an editable
// JSON file in the chronicle's characters/ folder: identity, allegiance,
// traits, goals, relationships and memories. Each season every character
// weighs their goals and makes a move; moves change others' situations, so
// consequences chain beyond anyone's prediction. Routine choices are scored
// here; pivotal ones go to Claude in the character's own voice. Results land
// in Freeciv (towns change hands, rebellions, gold) and at the King's court.

import fs from "node:fs";
import path from "node:path";
import { cityName, houseFor } from "./narrator.js";
import { decide } from "./claude.js";
import { calendar } from "./stakes.js";

// The court's deck of dilemmas: data, so new ones are written, not coded.
const DECK_FILE = new URL("./data/dilemmas.json", import.meta.url);
function loadDeck() {
  try { return JSON.parse(fs.readFileSync(DECK_FILE, "utf8")); } catch { return []; }
}

const NO_MOOD = { aggression: 0, loyalty: 0, ambition: 0, caution: 0, cunning: 0, piety: 0, greed: 0 };

const M = ["Aldric", "Bran", "Cedric", "Dunstan", "Edric", "Godwin", "Harold", "Jory", "Osric", "Rowan", "Tobin", "Hugh", "Garth", "Alaric", "Ewan", "Roderick", "Leofric", "Merrick", "Corwin", "Tristan", "Benedict", "Gareth", "Lucan", "Willem"];
const F = ["Agnes", "Bryony", "Cecily", "Edith", "Elsbeth", "Gwen", "Hilda", "Isolde", "Joan", "Maud", "Rosalind", "Wynne", "Alys", "Mira", "Tamsin", "Ysolde", "Rhiannon", "Elaine", "Beatrix", "Constance", "Genevieve", "Odette"];
export const TRAITS = ["ambitious", "honourable", "greedy", "vengeful", "pious", "cunning", "craven", "brave", "lustful", "content", "paranoid", "generous", "proud", "patient", "wrathful", "just"];
const SEASONS_PER_YEAR = 4;

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

function rng(seed) {
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
    fs.writeFileSync(this.courtFile, JSON.stringify({ petitions: this.petitions, claims: this.claims ?? [], truces: this.truces ?? {}, debts: this.debts ?? [] }, null, 1));
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

  newPerson(fields, r) {
    const gender = fields.gender ?? (r() < 0.5 ? "male" : "female");
    // Nobody alive shares a full name, so the chronicle can always tell people apart.
    const taken = new Set(this.alive().map((x) => x.name));
    let name = `${pick(gender === "male" ? M : F, r)} ${fields.surname}`;
    for (let i = 0; i < 12 && taken.has(name); i++) name = `${pick(gender === "male" ? M : F, r)} ${fields.surname}`;
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
        const surname = pick(["Ashby", "Greyford", "Hollin", "Marsh", "Thorne", "Varn", "Crane", "Dale", "Brook", "Fenwick", "Holt", "Roswell", "Kettle", "Morrow", "Pell", "Strand"], r);
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
    if (turn % SEASONS_PER_YEAR === 0) {
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
      this.expire(turn, ctx.shift);
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
    this.record({ turn, kind: "death", text: `${c.name} of ${c.house} dies at ${c.age}. The bells toll in ${where}.`, city: c.seat ?? undefined });
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
      opts.push({ kind: "petition", score: 20 + (goal.kind === "court" || goal.kind === "peace" ? 20 : 0) + (favour > 60 ? 10 : 0) });
      if (favour < 25 && !ctx.warded?.(c.playerId)) opts.push({ kind: "rebel", score: 40 + (25 - favour) * 2 + (goal.kind === "crown" ? 40 : 0) + (has("ambitious") ? 15 : 0) - (has("craven") ? 30 : 0) - (c.hostage && this.people[c.hostage]?.alive ? 60 : 0) });
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
Return {"choice": one of the choices exactly, "line": what they say or think, one or two sentences in their voice}.`;
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
        } else {
          this.shift(c.id, father.id, -25, `${father.name} spurned my daughter.`);
          this.record({ turn, kind: "scheme", text: `${father.name} refuses ${c.name}'s offer of his daughter's hand. The insult is remembered.${line}`, city: c.seat });
        }
        return;
      }
      case "defect": {
        const town = world.cities.find((x) => x.id === c.seat);
        if (!town || town.capital) return;
        const d = await this.ask(c, `Your liege's house is ${c.house}. ${houseFor(m.to).name} sends envoys with gold, offering you their protection if you open your gates to them.`, ["defect", "stay loyal"]);
        const go = d ? d.choice === "defect" : true;
        const line = d?.line ? ` "${d.line}"` : "";
        if (!go) {
          c.loyalty = Math.min(100, c.loyalty + 15);
          this.record({ turn, kind: "scheme", text: `${c.name} of ${cityName(c.seat)} sends ${houseFor(m.to).name}'s envoys home empty-handed.${line}`, city: c.seat });
          return;
        }
        ctx.send(`local c = find.city(nil, ${town.id}); local to; for p in players_iterate() do if p.id == ${m.to.id} then to = p end end; if c and to then edit.transfer_city(c, to) end`);
        this.claims ??= [];
        this.claims.push({ city: town.id, from: c.playerId, to: m.to.id, turn });
        const oldLiege = c.liege;
        c.house = houseFor(m.to).name;
        c.playerId = m.to.id;
        c.liege = this.lordOfHouse(m.to.id)?.id ?? null;
        c.loyalty = 55;
        c.goals = [this.goalFor(c, Math.random)];
        if (oldLiege) this.shift(oldLiege, c.id, -60, `${c.name} betrayed me and gave ${cityName(c.seat)} to ${c.house}.`);
        this.record({ turn, kind: "betrayal", text: `Treachery! ${c.name} opens the gates of ${cityName(c.seat)} to ${c.house}.${line}`, city: c.seat });
        return;
      }
      case "alliance": {
        this.shift(c.id, m.target.id, 15, `I sought friendship with ${m.target.name}.`);
        this.shift(m.target.id, c.id, 12);
        this.record({ turn, kind: "alliance", text: `Ravens fly between ${c.house} and ${m.target.house}. ${c.name} and ${m.target.name} speak of friendship.` });
        return;
      }
      case "plot": {
        if (this.truce(c.id, m.target.id)) return;
        const d = await this.ask(c, `You despise ${m.target.name} of ${m.target.house}. You could hire men to raid their lands, spread rumours at court, or let it lie for now.`, ["raid", "slander", "wait"]);
        const md = this.moodFor(c);
        const choice = d?.choice ?? (c.traits.includes("wrathful") || md.aggression > 20 ? "raid" : md.caution > 25 ? "wait" : "slander");
        const line = d?.line ? ` "${d.line}"` : "";
        if (choice === "raid") {
          const prey = world.cities.find((x) => x.owner === m.target.playerId && !x.capital);
          if (prey) {
            ctx.send(`local c = find.city(nil, ${prey.id}); if c then for t in c.tile:square_iterate(1) do for u in t:units_iterate() do if u.owner == c.owner and math.random() < 0.5 then edit.unit_kill(u, "killed", nil) end end end; edit.change_gold(c.owner, -40) end`);
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
        if (seat) ctx.send(`local c = find.city(nil, ${seat.id}); if c then for i = 1, 3 do edit.create_unit(c.owner, c.tile, find.unit_type("Knights") or find.unit_type("Horsemen"), 1, c, -1) end end`);
        const why = ctx.cause?.(c.playerId);
        this.record({ turn, kind: "rebellion", text: `${c.name} raises the banners of ${c.house} against the crown!${why ? ` ${c.house} has not forgotten ${why}.` : ""}${d?.line ? ` "${d.line}"` : ""}`, city: c.seat ?? undefined });
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
  // A court day each season: one lord of a landed house comes with a petition,
  // while fewer than three wait, so the court is never empty for a year.
  async courtDay(world, turn, ctx) {
    const cap = { rare: 2, normal: 3, often: 4 }[ctx.options?.petitions] ?? 3;
    if (!ctx.watched || this.petitions.filter((p) => !p.answered).length >= cap) return;
    if (ctx.options?.petitions === "rare" && turn % 2) return;  // a quieter court sits every other season
    const waiting = new Set(this.petitions.filter((p) => !p.answered).map((p) => p.from));
    const lords = this.alive().filter((c) => c.rank === "lord" && !waiting.has(c.id) && (world.players.find((p) => p.id === c.playerId)?.cities ?? 0) > 0);
    if (!lords.length) return;
    this.turnNow = turn;
    await this.petition(lords[Math.floor(Math.random() * lords.length)], world, turn, ctx);
    this.saveCourt();
  }

  async petition(c, world, turn, ctx) {
    if (this.petitions.filter((p) => !p.answered).length >= 3) return;
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

    // Hunger.
    const hungry = myTowns.filter((x) => x.food !== undefined && x.food < 3).length;
    if (hungry) candidates.push({ kind: "grain", weight: 3 + hungry, make: () => {
      const donor = world.players.filter((x) => !houseFor(x).wild && !houseFor(x).crown && x.id !== c.playerId).sort((a, b) => b.gold - a.gold)[0];
      const donorHouse = donor ? houseFor(donor).name : "";
      const options = [{ id: "grant", label: "The crown pays (150 gold)", hint: `${c.house} +15`, cost: 150 }];
      if (donor) options.push({ id: "order", label: `Order ${donorHouse} to feed them`, hint: `Costs you nothing · ${donorHouse} −20 · ${c.house} +10` });
      options.push({ id: "refuse", label: "Let them starve", hint: `${c.house} −15 · their bannermen's loyalty wavers` });
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
    const troubled = world.cities.filter((x) => x.food !== undefined && x.food < 3).length;
    if (has("pious") || troubled >= 3) candidates.push({ kind: "faith", weight: 1 + Math.min(4, troubled), make: () => ({ kind: "faith", text: `A barefoot friar has come to ${c.house}'s lands with ${troubled ? `${troubled} hungry towns` : "the poor"} at his back. He preaches that the gods have turned from a sinful King. ${c.name}${has("pious") ? ", a pious man," : ""} asks what the crown will do.`, facts: facts(c.playerId), options: [
      { id: "endow", label: "Endow the Faith (150 gold)", hint: "Every house +4 · the Church blesses your name", cost: 150 },
      { id: "silence", label: "Have him silenced", hint: `The preaching stops · ${has("pious") ? `${c.house} −20, ${c.name} is appalled` : `${c.house} −5`} · the poor remember` },
      { id: "ignore", label: "Words are wind", hint: "Every house −3 · the sermon spreads" },
    ] }) });

    // A lord who remembers: a deed of the King's, a year old or more, brought
    // back to his face. The simulation picks the deed; the model only voices it.
    const owed = (this.deedsOf?.(c.playerId) ?? []).filter((x) => Math.abs(x.d) >= 8 && x.turn <= turn - 4 && (!x.raised || x.raised <= turn - 12));
    const fav = ctx.favour?.(c.playerId) ?? 50;
    const grudge = owed.filter((x) => x.d < 0).sort((a, b) => a.d - b.d)[0];
    const kindness = owed.filter((x) => x.d > 0).sort((a, b) => b.d - a.d)[0];
    const deed = fav < 55 ? (grudge ?? kindness) : (kindness ?? grudge);
    if (deed) candidates.push({ kind: "remembers", weight: deed.d < 0 ? 7 : 4, make: () => {
      deed.raised = turn;
      const when = calendar(deed.turn);
      // Once: "Two years ago, in the winter of 352, you took a town that was ours."
      // Year on year: "Since the winter of 352 you have bled us with the tithe, year after year."
      const ago = Math.max(1, Math.floor((turn - deed.turn) / 4));
      const said = deed.last - deed.turn >= 4
        ? `Since the ${when.season} of ${when.year}, you ${deed.what}, year after year`
        : `${ago === 1 ? "A year" : ago === 2 ? "Two years" : ago === 3 ? "Three years" : `${ago} years`} ago, in the ${when.season} of ${when.year}, you ${deed.what}`;
      if (deed.d < 0) {
        const threat = fav < 35 ? " Do not look for our banners until it is set right." : " I would hear the crown set it right.";
        return { kind: "remembers", deed: deed.what, grudge: true, text: `${c.name} of ${c.house}: "${said}. ${c.house} has not forgotten it, Your Grace.${threat}"`, facts: facts(c.playerId), options: [
          { id: "amend", label: "Make amends (120 gold)", hint: `${c.house} +15 · the grudge is laid to rest`, cost: 120 },
          { id: "hear", label: "Hear him out, promise nothing", hint: `${c.house} +3 · the grudge stands` },
          { id: "firm", label: "The crown did what it must", hint: `${c.house} −8 · ${c.name} adds this to the account` },
        ] };
      }
      return { kind: "remembers", deed: deed.what, grudge: false, text: `${c.name} of ${c.house}: "${said}. ${c.house} remembers its friends, Your Grace. Our swords are yours when you call."`, facts: facts(c.playerId), options: [
        { id: "oath", label: "Take their oath", hint: `${c.house} +6 · ${c.name} is bound to the crown` },
        { id: "purse", label: "Ask for gold toward the realm", hint: `The crown gains 60 gold · ${c.house} −4` },
      ] };
    } });

    // A bannerman who has served well asks to be raised.
    const loyal = myBannermen.find((b) => b.loyalty >= 70 && (b.traits.includes("brave") || b.traits.includes("ambitious")));
    if (loyal) candidates.push({ kind: "raise", weight: 2, make: () => ({ kind: "raise", man: loyal.id, text: `${loyal.name}, bannerman of ${c.house}, kneels before the throne. He held the line when others ran and asks to be made a lord in his own right, sworn to the crown alone. ${c.name} stands stiffly beside him.`, facts: facts(c.playerId), options: [
      { id: "raise", label: `Raise ${loyal.name} (80 gold)`, hint: `A lord who owes you everything · ${c.house} −15, a vassal lost`, cost: 80 },
      { id: "honour", label: "Honour him with a sword, not a seat", hint: `${loyal.name} +loyalty to his liege · ${c.house} +5` },
      { id: "refuse", label: "Send him back to his liege", hint: `${c.house} +10 · ${loyal.name} remembers the crown would not reward him` },
    ] }) });

    for (const card of loadDeck()) {
      const roles = this.cast(card, c, world, ctx);
      if (roles) candidates.push({ kind: card.id, weight: card.weight ?? 2, make: () => this.deal(card, roles, c, world, facts) });
    }

    const open = new Set(this.petitions.filter((p) => !p.answered).map((p) => p.kind));
    const recent = this.petitions.slice(-6).map((p) => p.kind);
    const pool = candidates.filter((x) => !open.has(x.kind)).map((x) => ({ ...x, w: x.weight / (1 + 2 * recent.filter((k) => k === x.kind).length) }));
    if (!pool.length) return;
    let roll = Math.random() * pool.reduce((t, x) => t + x.w, 0);
    const chosen = pool.find((x) => (roll -= x.w) < 0) ?? pool[pool.length - 1];
    const p = { ...base, ...chosen.make() };
    // They come to court now; their own words follow when the local model has
    // them (it can be slow or busy, and the court never waits on it).
    this.petitions.push(p);
    if (this.petitions.length > 60) this.petitions = this.petitions.filter((x) => !x.answered || x.turn > turn - 40);
    this.record({ turn, kind: "court", text: `${c.name} of ${c.house} comes to court.` });
    this.saveCourt();
    this.ask(c, `You stand before the King to say: ${p.text}`, ["speak"]).then((d) => {
      if (d?.line && !p.answered) { p.voice = d.line; this.saveCourt(); }
    }).catch(() => {});
  }

  // A matter a story brings to the King (arcs.js toCourt): it comes whatever
  // else is waiting, and his answer goes back to the story.
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
    const hungry = towns.filter((x) => x.food !== undefined && x.food < 3).length;
    if (w.poor && me.gold >= 80) return null;
    if (w.rich && me.gold < 250) return null;
    if (w.hungry && !hungry) return null;
    if (w.fed && hungry) return null;
    if (w.towns && towns.length < w.towns) return null;
    if (w.trait && !w.trait.some((t) => c.traits.includes(t))) return null;
    if (w.favourBelow !== undefined && ctx.favour(c.playerId) >= w.favourBelow) return null;
    if (w.favourAbove !== undefined && ctx.favour(c.playerId) <= w.favourAbove) return null;
    if (w.age && (c.age < w.age[0] || c.age > w.age[1])) return null;
    if (w.chance !== undefined && Math.random() > w.chance) return null;
    const lords = this.alive().filter((o) => o.rank === "lord" && o.id !== c.id && o.house !== c.house);
    const byOpinion = [...lords].sort((a, b) => this.opinion(c.id, a.id) - this.opinion(c.id, b.id));
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
    if (w.feud && !(roles.rival && this.opinion(c.id, roles.rival.id) < -15)) return null;
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
  play(p, option, world, out, gold) {
    const card = loadDeck().find((x) => x.id === p.kind);
    const o = card?.options.find((x) => x.id === option);
    if (!o) return;
    const roles = {};
    for (const [k, id] of Object.entries(p.roles ?? {})) roles[k] = k === "town" || k === "rivalTown" ? world.cities.find((x) => x.id === id) ?? { id } : this.people[id];
    const e = o.effects ?? {};
    const houses = world.players.filter((x) => !houseFor(x).crown && !houseFor(x).wild);
    const crown = world.players.find((x) => houseFor(x).crown);
    const pidOf = (role) => role === "crown" ? crown?.id : roles[role]?.playerId;
    const each = (map, fn) => { for (const [role, v] of Object.entries(map ?? {})) { if (role === "all") houses.forEach((h) => fn(h.id, v, null)); else if (roles[role] || role === "crown") fn(pidOf(role), v, roles[role]); } };
    each(e.favour, (pid, v) => { if (pid !== undefined) out.favour[pid] = (out.favour[pid] ?? 0) + v; });
    each(e.gold, (pid, v) => { if (pid !== undefined) gold(pid, v); });
    each(e.loyalty, (_, v, who) => { if (who?.loyalty !== undefined) { who.loyalty = Math.max(0, Math.min(100, who.loyalty + v)); this.save(who); } });
    each(e.memory, (_, v, who) => { if (who?.memories) { this.remember(who.id, this.fill(v, roles)); this.save(who); } });
    each(e.goal, (_, v, who) => { if (who?.goals) { who.goals.unshift({ kind: v.kind, text: this.fill(v.text, roles) }); who.goals = who.goals.slice(0, 3); this.save(who); } });
    each(e.units, (pid, v) => {
      const seat = world.cities.find((x) => x.owner === pid && x.capital) ?? world.cities.find((x) => x.owner === pid);
      if (seat) out.lua.push(`local c = find.city(nil, ${seat.id}); if c then local t = find.unit_type("${v.type ?? "Pikemen"}") or find.unit_type("Warriors"); for i = 1, ${Number(v.count ?? v) || 1} do edit.create_unit(c.owner, c.tile, t, 1, c, -1) end end`);
    });
    for (const [a, b, d] of e.opinion ?? []) if (roles[a] && roles[b]) { this.shift(roles[a].id, roles[b].id, d); this.save(roles[a]); }
    if (e.truce && roles.me && roles.rival) { this.truces ??= {}; this.truces[[roles.me.id, roles.rival.id].sort().join(":")] = (world.turn ?? 0) + 8 * e.truce; }
    if (e.dies && roles[e.dies.who] && Math.random() < (e.dies.chance ?? 1)) {
      const who = roles[e.dies.who];
      who.alive = false;
      this.save(who);
      this.record({ turn: world.turn, kind: "death", text: this.fill(e.dies.text ?? `{${e.dies.who}} is dead.`, roles) });
    }
    if (e.marry && roles[e.marry[0]] && roles[e.marry[1]]) { const [x, y] = [roles[e.marry[0]], roles[e.marry[1]]]; x.spouse = y.id; y.spouse = x.id; this.save(x); this.save(y); }
    if (e.ward && roles[e.ward]) { roles[e.ward].ward = true; if (roles.me) roles.me.hostage = roles[e.ward].id; this.save(roles[e.ward]); }
    // Men without banners burn a town of the victim's: soldiers die, gold is lost.
    if (e.raid && roles[e.raid[1]]) {
      const prey = roles.rivalTown && roles[e.raid[1]] === roles.rival ? roles.rivalTown : world.cities.find((x) => x.owner === roles[e.raid[1]].playerId && !x.capital);
      if (prey?.x !== undefined) out.lua.push(`local c = find.city(nil, ${prey.id}); if c then for t in c.tile:square_iterate(1) do for u in t:units_iterate() do if u.owner == c.owner and math.random() < 0.5 then edit.unit_kill(u, "killed", nil) end end end; edit.change_gold(c.owner, -60) end`);
      if (roles[e.raid[0]]) this.shift(roles[e.raid[1]].id, roles[e.raid[0]].id, -40);
    }
    // War: a host is raised for the attacker beside the victim's town, and
    // Freeciv's own AI fights the battle that follows.
    if (e.war && roles[e.war[0]] && roles[e.war[1]]) {
      const [atk, def] = [roles[e.war[0]], roles[e.war[1]]];
      const prey = (def === roles.rival && roles.rivalTown) || world.cities.find((x) => x.owner === def.playerId && !x.capital) || world.cities.find((x) => x.owner === def.playerId);
      if (prey?.x !== undefined) out.lua.push(`realm_host(realm_find_player(${atk.playerId}), ${prey.x}, ${prey.y}, {"Pikemen","Archers","Knights","Catapult"}, ${Number(e.warSize ?? 8)})`);
      this.shift(def.id, atk.id, -60);
      this.shift(atk.id, def.id, -30);
      if (this.truces) delete this.truces[[atk.id, def.id].sort().join(":")];
      this.record({ turn: world.turn, kind: "rebellion", text: `${atk.house} marches on ${prey ? cityName(prey.id) : def.house}. War between ${atk.house} and ${def.house}.`, city: prey?.id });
    }
    out.text = this.fill(o.text, roles);
  }

  // Loans from the crown fall due after two years: paid, or defaulted on.
  collect(world, turn, ctx) {
    for (const debt of this.debts ?? []) {
      if (debt.settled || turn < debt.due) continue;
      debt.settled = true;
      const p = world.players.find((x) => x.id === debt.pid);
      const lord = this.lordOfHouse(debt.pid);
      if (p && p.gold >= debt.amount) {
        ctx.send(`for p in players_iterate() do if p.id == ${debt.pid} then edit.change_gold(p, -${debt.amount}) elseif p.id == ${world.players.find((x) => houseFor(x).crown)?.id ?? -1} then edit.change_gold(p, ${debt.amount}) end end`);
        this.record({ turn, kind: "court", text: `${houseFor(p).name} repays the crown ${debt.amount} gold, with interest.` });
      } else if (lord) {
        ctx.shift({ [debt.pid]: -15 }, "shamed over the crown's loan");
        this.remember(lord.id, "The crown's loan came due and I could not pay. The King's men counted my silver in front of my children.");
        this.record({ turn, kind: "unrest", text: `${lord.house} defaults on the crown's loan. ${lord.name} will not meet the King's eye.` });
      }
    }
  }

  // Petitions left unanswered for two years are answered by silence.
  expire(turn, shift) {
    for (const p of this.petitions) {
      // Patience in the King's time too: two years of seasons pass in a minute or
      // two of play, so a petitioner also waits five real minutes before leaving.
      // Only time the King is watching counts: a realm left closed for an hour
      // doesn't empty his court (each watched season adds at most half a minute).
      const now = Date.now();
      p.waitedMs = (p.waitedMs ?? 0) + Math.min(30000, now - (p.tick ?? now));
      p.tick = now;
      p.seasons = (p.seasons ?? 0) + 1;
      if (p.answered || p.seasons < 8 || p.waitedMs < 5 * 60000) continue;
      p.answered = "ignored";
      if (p.kind === "arc") this.onArcRuling?.(p.arc, p.beat, "ignored");
      const c = this.people[p.from];
      if (!c) continue;
      shift({ [c.playerId]: -12 }, "left unheard at court");
      this.remember(c.id, "I waited at court for two years. The King never answered.");
      this.record({ turn, kind: "unrest", text: `${c.name} of ${c.house} leaves Kingsmere unheard, and says so to anyone who will listen.` });
    }
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

  truce(a, b) {
    const k = [a, b].sort().join(":");
    return (this.truces ?? {})[k] > (this.turnNow ?? 0);
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
    const gold = (pid2, amount) => out.lua.push(`for p in players_iterate() do if p.id == ${pid2} then edit.change_gold(p, ${amount}) end end`);
    if (p.kind === "arc") {
      for (const [pid, n] of Object.entries(opt.favour ?? {})) out.favour[pid] = n;
      out.text = opt.result || `The King gives his answer: ${String(opt.label).toLowerCase()}.`;
      this.onArcRuling?.(p.arc, p.beat, option);
    } else if (p.deck) {
      this.play(p, option, world, out, gold);
    } else if (p.kind === "claim") {
      const k = p.claim;
      k.settled = true;
      const town = cityName(k.city);
      const move = (to) => out.lua.push(`local c = find.city(nil, ${k.city}); local to; for p in players_iterate() do if p.id == ${to} then to = p end end; if c and to then edit.transfer_city(c, to) end`);
      if (option === "return") { move(k.from); out.favour[k.from] = 20; out.favour[k.to] = -30; out.text = `By the King's judgment, ${town} is returned to ${c.house}.`; }
      if (option === "confirm") { out.favour[k.to] = 15; out.favour[k.from] = -30; for (const b of this.alive().filter((x) => x.rank === "bannerman")) b.loyalty = Math.max(0, b.loyalty - 5); out.text = `The King confirms ${town} to its new masters. Bannermen across the realm take note.`; }
      if (option === "seize") { const crown = world.players.find((x) => houseFor(x).crown); if (crown) move(crown.id); out.favour[k.from] = -20; out.favour[k.to] = -20; out.text = `The King takes ${town} for the crown. Neither house is pleased.`; }
    } else if (p.kind === "justice") {
      const enemy = this.people[p.enemy];
      if (option === "side" || option === "other") {
        const winner = option === "side" ? c : enemy;
        const loser = option === "side" ? enemy : c;
        out.favour[winner.playerId] = 15;
        out.favour[loser.playerId] = -25;
        this.remember(winner.id, `The King took my side against ${loser.name}.`);
        this.remember(loser.id, `The King humiliated me before ${winner.name}.`);
        this.shift(loser.id, winner.id, -20);
        if (this.warlike(loser)) loser.goals.unshift({ kind: "revenge", text: `make ${winner.house} pay for what the King allowed` });
        out.text = `The King rules for ${winner.house}. ${loser.name} leaves the hall white with fury.`;
      } else if (option === "peace") {
        this.truces ??= {};
        this.truces[[c.id, enemy.id].sort().join(":")] = (world.turn ?? 0) + 8;
        out.favour[c.playerId] = -5;
        out.favour[enemy.playerId] = -5;
        out.text = `The King's peace is proclaimed between ${c.house} and ${enemy.house}. The crown pays for the burned barns. Neither lord smiles.`;
      } else if (option === "combat") {
        const cWins = Math.random() < 0.5 + (this.warlike(c) ? 0.1 : 0) - (this.warlike(enemy) ? 0.1 : 0);
        const winner = cWins ? c : enemy;
        const loser = cWins ? enemy : c;
        const lp = world.players.find((x) => x.id === loser.playerId);
        gold(loser.playerId, -Math.floor((lp?.gold ?? 0) / 3));
        gold(winner.playerId, Math.floor((lp?.gold ?? 0) / 3));
        out.favour[winner.playerId] = 10;
        out.favour[loser.playerId] = -10;
        const son = loser.children.map((id) => this.people[id]).find((k) => k?.alive && k.gender === "male" && k.age >= 16);
        if (son && Math.random() < 0.5) {
          son.alive = false;
          this.remember(loser.id, `My son ${son.name} died in the trial by combat the King allowed.`);
          out.text = `Trial by combat at Kingsmere. ${winner.house}'s champion stands over ${son.name}, son of ${loser.name}. The gods have spoken.`;
        } else {
          out.text = `Trial by combat at Kingsmere. ${winner.house}'s champion wins; ${loser.house} pays a third of its treasury.`;
        }
      }
    } else if (p.kind === "remembers") {
      const deed = (this.deedsOf?.(c.playerId) ?? []).find((x) => x.what === p.deed);
      if (option === "amend") { out.favour[c.playerId] = 15; gold(c.playerId, 120); if (deed) { deed.d = Math.round(deed.d * 0.3); deed.mended = world.turn; } this.remember(c.id, "The King made amends for what was done to my house. It is settled, for now."); out.text = `The King makes amends to ${c.house}. ${c.name} takes the gold and, for now, lets the old wound close.`; }
      if (option === "hear") { out.favour[c.playerId] = 3; out.text = `The King hears ${c.name} out and promises nothing. ${c.house} goes home with its grudge.`; }
      if (option === "firm") { out.favour[c.playerId] = -8; this.remember(c.id, "I reminded the King what he did to my house. He said the crown did what it must."); if (this.warlike(c)) c.goals.unshift({ kind: "revenge", text: "make the crown answer for what it did to my house" }); out.text = `"The crown did what it must." ${c.name} bows, and adds it to the account.`; }
      if (option === "oath") { out.favour[c.playerId] = 6; c.loyalty = Math.min(100, c.loyalty + 10); out.text = `${c.name} kneels and swears ${c.house} to the crown before the whole court.`; }
      if (option === "purse") { out.favour[c.playerId] = -4; gold(c.playerId, -60); const crown = world.players.find((x) => houseFor(x).crown); if (crown) gold(crown.id, 60); out.text = `${c.house} sends 60 gold to Kingsmere. ${c.name} had hoped for thanks, not a bill.`; }
      this.save(c);
    } else if (p.kind === "grain") {
      if (option === "grant") { out.favour[c.playerId] = 15; gold(c.playerId, 150); out.text = `The crown sends grain to ${c.house}.`; }
      if (option === "order") { out.favour[p.donor] = -20; out.favour[c.playerId] = 10; gold(p.donor, -150); gold(c.playerId, 150); out.text = `By royal command, ${houseFor(world.players.find((x) => x.id === p.donor)).name} feeds the starving of ${c.house}, and resents every sack.`; }
      if (option === "refuse") {
        out.favour[c.playerId] = -15;
        for (const b of this.alive().filter((x) => x.rank === "bannerman" && x.playerId === c.playerId)) b.loyalty = Math.max(0, b.loyalty - 15);
        out.text = `The King refuses grain. In ${c.house}'s lands, the bannermen begin to talk.`;
      }
      this.remember(c.id, option === "refuse" ? "The King let my people starve." : "The King fed my people when they starved.");
    } else if (p.kind === "match") {
      const bride = this.people[p.bride];
      const groom = this.people[p.groom];
      const father = this.people[bride.parents[0]];
      const groomLord = this.lordOfHouse(this.people[groom.parents?.[0]]?.playerId ?? -1);
      if (option === "bless") {
        bride.spouse = groom.id; groom.spouse = bride.id; bride.house = groom.house;
        father.loyalty = Math.max(0, father.loyalty - 20);
        if (groomLord) { out.favour[groomLord.playerId] = 10; this.shift(father.id, groomLord.id, 30); }
        out.favour[c.playerId] = -10;
        out.text = `${bride.name} weds ${groom.name} with the King's blessing. ${c.name} smiles thinly.`;
      } else if (option === "forbid") {
        out.favour[c.playerId] = 10;
        if (groomLord) out.favour[groomLord.playerId] = -10;
        this.remember(father.id, "The King forbade my daughter's match.");
        out.text = `The King forbids the match. ${father.name} bows, and does not forget.`;
      } else {
        bride.rank = "ward";
        this.remember(father.id, "The King took my daughter as a royal ward. My house owes the crown.");
        father.loyalty = Math.min(100, father.loyalty + 10);
        out.text = `${bride.name} goes to Kingsmere as a royal ward.`;
      }
      this.save(bride); this.save(groom); this.save(father);
    } else if (p.kind === "debt") {
      if (option === "forgive") { gold(c.playerId, 100); out.favour[c.playerId] = 15; for (const o of world.players) if (o.id !== c.playerId && !houseFor(o).crown && !houseFor(o).wild) out.favour[o.id] = -3; out.text = `The crown returns ${c.house}'s tithe. The other houses grumble that they were not asked.`; }
      if (option === "lend") { gold(c.playerId, 250); out.favour[c.playerId] = 5; (this.debts ??= []).push({ pid: c.playerId, amount: 325, due: (world.turn ?? 0) + 8 }); out.text = `The crown lends ${c.house} 250 gold. The debt is written in the King's ledger: 325, due in two years.`; }
      if (option === "refuse") { out.favour[c.playerId] = c.traits.includes("proud") ? -18 : -10; this.remember(c.id, "I begged the King for relief and was told to pay like everyone else."); out.text = `The King refuses. ${c.house} pays its share, and its lord counts every coin.`; }
    } else if (p.kind === "outlaws") {
      const town = cityName(p.city);
      if (option === "hunt") { out.favour[c.playerId] = 15; out.lua.push(`local c = find.city(nil, ${p.city}); if c then local t = find.unit_type("Knights") or find.unit_type("Horsemen"); for i = 1, 3 do edit.create_unit(c.owner, c.tile, t, 1, c, -1) end end`); out.text = `The King's riders clear the forest road outside ${town}. The oaks bear different fruit now.`; }
      if (option === "pardon") { out.favour[c.playerId] = -15; const crown = world.players.find((x) => houseFor(x).crown); const seat = crown && world.cities.find((x) => x.owner === crown.id); if (seat) out.lua.push(`local c = find.city(nil, ${seat.id}); if c then for i = 1, 2 do edit.create_unit(c.owner, c.tile, find.unit_type("Archers") or find.unit_type("Warriors"), 0, c, -1) end end`); this.remember(c.id, `The King pardoned the outlaws who hanged my men outside ${town}, and put them in royal colours.`); out.text = `The outlaws of ${town} kneel and are pardoned. They march to Kingsmere in the King's colours. ${c.house} does not forgive it.`; }
      if (option === "theirs") { out.favour[c.playerId] = -5; gold(c.playerId, -60); out.text = `The King tells ${c.name} to keep his own roads. The outlaws keep the road, and the taxes of ${town} keep going into the forest.`; }
    } else if (p.kind === "informer") {
      const informer = this.people[p.informer];
      const suspect = this.people[p.suspect];
      const heir = this.people[p.heir];
      if (option === "hostage") { out.favour[suspect.playerId] = -20; suspect.hostage = heir.id; heir.rank = heir.rank === "heir" ? "heir" : heir.rank; heir.ward = true; this.remember(suspect.id, `The King took my child ${heir.name} to Kingsmere on a bannerman's word.`); this.save(heir); out.text = `${heir.name} rides to Kingsmere as a royal ward. ${suspect.name} will not rise while the King holds his child, and will not forget.`; }
      if (option === "reward") { informer.loyalty = Math.min(100, informer.loyalty + 20); this.shift(suspect.id, informer.id, -40, `${informer.name} sold tales of me to the King.`); this.shift(informer.id, suspect.id, -10); out.text = `${informer.name} leaves court with a heavier purse. Within the month, ${suspect.name} knows who talked.`; }
      if (option === "dismiss") { out.favour[suspect.playerId] = 5; this.remember(informer.id, "The King called me a liar before the court."); informer.loyalty = Math.max(0, informer.loyalty - 10); out.text = `The King dismisses the accusation. ${informer.name} leaves court red-faced.`; }
      this.save(informer); this.save(suspect);
    } else if (p.kind === "regency") {
      const regent = this.people[p.regent];
      if (option === "regent") { regent.loyalty = 100; regent.goals = [{ kind: "favour", text: "repay the King who raised me" }]; out.favour[c.playerId] = -10; this.remember(regent.id, "The King named me to govern my house. I owe him everything."); out.text = `${regent.name} is named to govern ${c.house} by the King's word. ${c.house}'s kin bow, and whisper.`; }
      if (option === "crown") { const me = world.players.find((x) => x.id === c.playerId); const take = Math.floor((me?.gold ?? 0) / 4); gold(c.playerId, -take); const crown = world.players.find((x) => houseFor(x).crown); if (crown) gold(crown.id, take); out.favour[c.playerId] = -15; out.text = `The crown governs ${c.house} until the matter is settled, and its stewards take ${take} gold for the trouble.`; }
      if (option === "leave") { regent.goals.unshift({ kind: "crown", text: `take ${c.house} for myself` }); regent.loyalty = Math.max(0, regent.loyalty - 25); out.text = `The King leaves ${c.house} to settle its own succession. ${regent.name} smiles.`; }
      this.save(regent);
    } else if (p.kind === "faith") {
      const houses = world.players.filter((o) => !houseFor(o).crown && !houseFor(o).wild);
      if (option === "endow") { for (const o of houses) out.favour[o.id] = 4; out.text = "The crown endows the Faith. In every church, the King's name is blessed."; }
      if (option === "silence") { out.favour[c.playerId] = c.traits.includes("pious") ? -20 : -5; this.remember(c.id, "The King had a holy man silenced in my lands."); out.text = "The friar is taken in the night. The preaching stops. The poor do not forget his face."; }
      if (option === "ignore") { for (const o of houses) out.favour[o.id] = -3; out.text = "The King ignores the friar. His sermon spreads from village to village."; }
    } else if (p.kind === "raise") {
      const man = this.people[p.man];
      if (option === "raise") { man.liege = null; man.loyalty = 100; man.goals = [{ kind: "favour", text: "prove the King right to raise me" }]; out.favour[c.playerId] = -15; this.remember(c.id, `The King took ${man.name} from my service and made him a lord.`); out.text = `${man.name} rises a lord, sworn to the crown alone. ${c.name} has lost a sword and gained a rival.`; }
      if (option === "honour") { man.loyalty = Math.min(100, man.loyalty + 10); this.shift(man.id, c.id, 15); out.favour[c.playerId] = 5; out.text = `The King gives ${man.name} a sword from the royal armoury and sends him home to his liege, honoured.`; }
      if (option === "refuse") { out.favour[c.playerId] = 10; this.remember(man.id, "I knelt before the King and he sent me home with nothing."); man.loyalty = Math.max(0, man.loyalty - 10); out.text = `The King sends ${man.name} back to ${c.house}. ${c.name} is pleased. ${man.name} is not.`; }
      this.save(man);
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
    return this.petitions.filter((p) => !p.answered).map(({ id, text, voice, facts, options, house, name, from, arc, beat, thread }) => ({ id, text, voice, facts, options, house, name, from, ...(arc ? { arc, beat, thread } : {}) }));
  }
}
