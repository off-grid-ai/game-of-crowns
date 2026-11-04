// Story arcs: tales that run over many seasons, cast from the realm's own
// people by what they remember. Each kind of story is one JSON file in
// bridge/arcs/ (see docs/STORY_ARCS.md): the parts it needs, when it begins,
// and its beats with their branches. Nothing here knows any one story.
//
// The memories cast the people: a role can ask for someone who remembers a
// wrong, and for whoever that memory names. The simulation decides the
// ending: every branch reads live Freeciv state (armies, gold, towns held,
// hunger, war) and beats act through the same levers the court uses. The
// local model only writes the words. Every beat goes into the chronicle under
// the arc's name and into the memories of the people in it, so one story's
// beats can cast the next.
//
// With minds (minds.js) the stories reach the common folk too: a role can be
// cast from any commoner's mind, and every beat moves the minds of those in
// it (memories, mood, bonds, beliefs, reverie). Those who only hear of it
// learn from the chronicle, as minds hear everything.
//
// State lives in the chronicle folder: <chronicle>/arcs.json.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { cityName, houseFor } from "./narrator.js";
import { arcLine } from "./claude.js";

const DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), "arcs");
const MAX_ACTIVE = 5;      // stories running at once
const START_CHANCE = 0.4;  // a season's chance that a new one begins
const MAX_ARCS_EACH = 2;   // stories one person can be caught up in at once
const PERSON_RANKS = ["lord", "bannerman", "heir", "child", "spouse", "ward", "sworn", "exile"];
// How a beat moves those in it, when the file doesn't say.
const STAGE_MOOD = { rising: { fear: 0.05 }, crisis: { fear: 0.15, anger: 0.15 }, resolved: { joy: 0.1, fear: -0.1 }, failed: { grief: 0.2 }, faded: {} };
const clamp = (v, lo = 0, hi = 1) => Math.max(lo, Math.min(hi, v));

// Every arc file, read fresh each time so a dropped-in file joins the realm
// without a restart. A file that doesn't parse or check is skipped and named.
export function templates() {
  const out = [];
  for (const f of fs.existsSync(DIR) ? fs.readdirSync(DIR).filter((x) => x.endsWith(".json")).sort() : []) {
    try {
      const t = JSON.parse(fs.readFileSync(path.join(DIR, f), "utf8"));
      t.file = f;
      t.problems = check(t);
      out.push(t);
    } catch (err) {
      out.push({ id: f.replace(/\.json$/, ""), file: f, problems: [`not valid JSON: ${err.message}`] });
    }
  }
  return out;
}

// What's wrong with an arc file, in words, or [] if nothing.
export function check(t) {
  const errs = [];
  if (!t.id) errs.push("no id");
  if (!t.title) errs.push("no title");
  const roles = Object.keys(t.roles ?? {});
  if (!roles.length) errs.push("no roles");
  const seen = [];
  for (const [k, spec] of Object.entries(t.roles ?? {})) {
    for (const ref of refsIn(spec)) if (!seen.includes(ref)) errs.push(`role ${k} refers to ${ref}, which must come before it`);
    seen.push(k);
  }
  const beats = t.beats ?? [];
  const ids = beats.map((b) => b.id);
  if (!beats.length) errs.push("no beats");
  if (!beats.some((b) => b.end)) errs.push("no beat ends the story (give one \"end\")");
  for (const b of beats) {
    if (!b.id) errs.push("a beat has no id");
    if (!b.text) errs.push(`beat ${b.id} has no text`);
    for (const n of [...(b.next ?? []).map((x) => x.to), b.otherwise].filter(Boolean)) if (!ids.includes(n)) errs.push(`beat ${b.id} goes to ${n}, which isn't a beat`);
    if (!b.end && !(b.next ?? []).length && !b.otherwise) errs.push(`beat ${b.id} neither ends nor goes anywhere`);
    for (const text of [b.text, ...Object.values(b.memory ?? {})].flat()) {
      for (const [, r] of String(text ?? "").matchAll(/\{(\w+)/g)) if (!roles.includes(r) && r !== "thread") errs.push(`beat ${b.id} names {${r}}, which isn't a role`);
    }
  }
  for (const n of t.interrupts ?? []) if (!ids.includes(n.to)) errs.push(`an interrupt goes to ${n.to}, which isn't a beat`);
  for (const [r, id] of Object.entries(t.onDeath ?? {})) if (!ids.includes(id)) errs.push(`onDeath ${r} goes to ${id}, which isn't a beat`);
  return [...new Set(errs)];
}

// Roles a role's filters lean on (they must be cast first).
function refsIn(spec) {
  const out = [];
  const walk = (s) => {
    if (!s || typeof s !== "object") return;
    for (const k of ["house", "otherHouse", "otherGender", "rules", "kinOf", "childOf", "parentOf", "spouseOf", "swornTo", "liegeOf", "ownedBy", "seatOf", "homeOf", "notOwnedBy", "townOf", "bondOf"]) if (typeof s[k] === "string") out.push(s[k]);
    if (s.namedBy?.role) out.push(s.namedBy.role);
    for (const k of ["opinion", "opinionOf"]) if (Array.isArray(s[k])) out.push(s[k][0]);
    for (const e of s.either ?? []) walk(e);
  };
  walk(spec);
  return out;
}

function rand(range, r = Math.random) {
  if (Array.isArray(range)) return range[0] + Math.floor(r() * (range[1] - range[0] + 1));
  return Number(range ?? 1);
}

const re = (p) => new RegExp(p, "i");
const cmp = (a, op, b) => ({ "<": a < b, ">": a > b, "<=": a <= b, ">=": a >= b, "=": a === b, "!=": a !== b })[op] ?? false;

export class Arcs {
  constructor(dir, court, record) {
    this.file = path.join(dir, "arcs.json");
    this.court = court;
    this.record = record;
    const saved = fs.existsSync(this.file) ? JSON.parse(fs.readFileSync(this.file, "utf8")) : {};
    this.clock = saved.clock ?? 0;
    this.active = saved.active ?? [];
    this.done = saved.done ?? [];
    this.cooldown = saved.cooldown ?? {};
    this.seq = saved.seq ?? 1;
    this.voice = arcLine; // the words; the story never waits on them
  }

  save() {
    fs.writeFileSync(this.file, JSON.stringify({ clock: this.clock, seq: this.seq, cooldown: this.cooldown, active: this.active, done: this.done.slice(-80) }, null, 1));
  }

  // --- the season --------------------------------------------------------------

  // One season of every running story, and perhaps a new one.
  // ctx: { world, favour(pid), shift({pid: d}), send(lua), atWar(a, b), town(id), recent(), refresh(), minds? }
  async season(ctx, { start = true } = {}) {
    this.clock++;
    this.touched = new Set();
    const files = templates();
    const all = files.filter((t) => !t.problems.length);
    for (const arc of [...this.active]) {
      const t = all.find((x) => x.id === arc.template);
      // A file being edited (or briefly broken) pauses its stories; only a
      // file that's gone for good ends them.
      if (!t && files.some((x) => x.id === arc.template || x.file === `${arc.template}.json`)) continue;
      if (!t) { this.finish(arc, "faded", ctx, "Its tale is no longer told."); continue; }
      await this.advance(arc, t, ctx);
    }
    if (start && this.active.length < MAX_ACTIVE && Math.random() < START_CHANCE) await this.begin(all, ctx);
    // Whoever a story touched this season is in it now: their minds think hot.
    if (ctx.minds && this.touched.size) ctx.minds.attend({ cast: [...this.touched] });
    this.save();
  }

  // A new story, drawn by weight from those that can be cast right now.
  async begin(all, ctx, only = null) {
    const ready = [];
    for (const t of all) {
      if (only && t.id !== only) continue;
      if (!only && this.clock < (this.cooldown[t.id] ?? 0)) continue;
      if (!only && this.active.some((a) => a.template === t.id)) continue;
      const roles = this.cast(t, ctx);
      if (roles) ready.push({ t, roles });
    }
    if (!ready.length) return null;
    let roll = Math.random() * ready.reduce((s, x) => s + (x.t.weight ?? 1), 0);
    const { t, roles } = ready.find((x) => (roll -= x.t.weight ?? 1) < 0) ?? ready[ready.length - 1];
    const arc = { id: `a${this.seq++}`, template: t.id, kind: t.kind ?? t.id, roles: {}, at: null, wait: 0, stalled: 0, started: this.clock, turn: ctx.world.turn, beats: [] };
    for (const [k, v] of Object.entries(roles)) arc.roles[k] = v.town ? `town:${v.id}` : v.id;
    arc.title = this.fill(t.title, arc, ctx);
    this.active.push(arc);
    this.cooldown[t.id] = this.clock + (t.cooldown ?? 12);
    await this.enter(arc, t, t.beats[0], ctx);
    return arc;
  }

  // One season of one story: who died, then which branch the realm now allows.
  async advance(arc, t, ctx) {
    const beat = t.beats.find((b) => b.id === arc.at);
    if (!beat) return this.finish(arc, "faded", ctx);
    const roles = this.roles(arc, ctx);
    // Someone in the story has died, perhaps in another story, or of age.
    // Each death is met once: by the beat the file names for it, by a branch
    // waiting on it, or, for someone the story can't go on without, the end.
    const core = t.core ?? Object.keys(t.roles).filter((k) => !t.roles[k].town && !t.roles[k].optional);
    arc.mourned ??= [];
    const dead = Object.keys(roles).find((k) => !roles[k].town && !roles[k].alive && !arc.mourned.includes(k));
    if (dead) {
      arc.mourned.push(dead);
      const fired = (beat.next ?? []).find((n) => JSON.stringify(n.if ?? {}).includes("dead") && this.test(n.if, arc, ctx));
      if (fired) return this.enter(arc, t, t.beats.find((b) => b.id === fired.to), ctx);
      const to = t.onDeath?.[dead];
      if (to && to !== arc.at) return this.enter(arc, t, t.beats.find((b) => b.id === to), ctx);
      if (core.includes(dead)) return this.finish(arc, "failed", ctx, `With ${roles[dead].name} in the grave, ${arc.title} ends unfinished.`);
    }
    // What another story (or the realm) did can overtake this one at any time.
    const over = (t.interrupts ?? []).find((n) => n.to !== arc.at && this.test(n.if, arc, ctx));
    if (over) return this.enter(arc, t, t.beats.find((b) => b.id === over.to), ctx);
    if (arc.wait > 0) { arc.wait--; return; }
    const next = (beat.next ?? []).find((n) => this.test(n.if, arc, ctx));
    if (next) return this.enter(arc, t, t.beats.find((b) => b.id === next.to), ctx);
    // Nothing the realm allows yet: the story stalls, and in time moves on or fades.
    arc.stalled++;
    if (arc.stalled >= (beat.patience ?? 4)) {
      if (beat.otherwise) return this.enter(arc, t, t.beats.find((b) => b.id === beat.otherwise), ctx);
      return this.finish(arc, "faded", ctx, this.fill(t.fade ?? "{thread} is spoken of less each season, and then not at all.", arc, ctx));
    }
  }

  // A beat happens: the chronicle tells it under the arc's name, its people
  // remember it, the realm feels it, and the story waits for the next.
  async enter(arc, t, beat, ctx) {
    const roles = this.roles(arc, ctx);
    const text = this.fill(Array.isArray(beat.text) ? beat.text[Math.floor(Math.random() * beat.text.length)] : beat.text, arc, ctx);
    const lua = this.act(beat.do ?? {}, arc, roles, ctx);
    let line = "";
    const speaker = beat.speaker && roles[beat.speaker];
    if (speaker?.alive) {
      const also = this.active.filter((a) => a !== arc && Object.values(a.roles).includes(speaker.id)).map((a) => a.title);
      line = (await this.voice(speaker, arc.title, text, also)) ?? "";
    }
    const town = this.placeOf(beat, roles);
    const said = line ? ` ${speaker.name.split(" ")[0]}: "${line}"` : "";
    // `cast`: who is in it, so minds tell it to them as their own memory, not as news.
    const cast = Object.values(roles).filter((x) => !x.town).map((x) => x.id);
    this.record({ turn: ctx.world.turn, kind: "arc", thread: arc.title, arc: arc.id, stage: beat.stage ?? "rising", text: text + said, cast, ...(town != null ? { city: town } : {}) });
    // Everyone in the story remembers the beat, in their own words where the
    // file gives them; it moves their mood, more in a crisis than a rumour.
    const ids = Object.values(roles).filter((x) => !x.town).map((x) => x.id);
    const moves = (k) => beat.feel?.[k] ?? STAGE_MOOD[beat.end ?? beat.stage ?? "rising"] ?? {};
    const weight = { rising: 0.6, crisis: 0.8, resolution: 0.9 }[beat.stage ?? "rising"] ?? 0.6;
    for (const [k, who] of Object.entries(roles)) {
      if (who.town || !who.alive) continue;
      (this.touched ??= new Set()).add(who.id);
      const own = beat.memory === false ? false : beat.memory?.[k];
      const text2 = own === false ? null : own ? this.fill(own, arc, ctx) : `${arc.title}: ${text}`;
      const mind = this.mindOf(who, ctx);
      if (who.folk) {
        if (text2) ctx.minds.remember(mind, text2, { about: ids.filter((x) => x !== who.id), weight, kind: "arc", moves: moves(k) });
        else ctx.minds.feel(mind, moves(k), weight);
        continue;
      }
      if (text2) { this.court.remember(who.id, text2); this.court.save(who); }
      // A named person's memories stay in their Court record; the mind carries how it felt.
      if (mind) { ctx.minds.feel(mind, moves(k), weight); ctx.minds.save(); }
    }
    arc.at = beat.id;
    arc.stalled = 0;
    arc.wait = Math.max(0, rand(beat.after ?? [1, 2]) - 1);
    arc.beats.push({ beat: beat.id, stage: beat.stage ?? "rising", clock: this.clock, turn: ctx.world.turn, text: text + said });
    if (lua.length && ctx.refresh) await ctx.refresh();
    if (beat.end) this.finish(arc, beat.end, ctx);
  }

  finish(arc, how, ctx, text) {
    arc.status = how;
    arc.ended = this.clock;
    if (text) {
      this.record({ turn: ctx.world.turn, kind: "arc", thread: arc.title, arc: arc.id, stage: "resolution", text });
      arc.beats.push({ beat: how, stage: "resolution", clock: this.clock, turn: ctx.world.turn, text });
    }
    this.active = this.active.filter((a) => a !== arc);
    this.done.push(arc);
  }

  placeOf(beat, roles) {
    const at = beat.at ? roles[beat.at] : Object.values(roles).find((x) => x.town) ?? Object.values(roles).find((x) => (x.seat ?? x.home) != null);
    return at ? (at.town ? at.id : at.seat ?? at.home ?? null) : null;
  }

  // --- minds -----------------------------------------------------------------------

  // A commoner's mind, seen as a person the stories can cast. Changes are
  // made to the mind itself; this is only a view of it.
  folkPerson(m, ctx) {
    if (!m) return undefined;
    const town = ctx.world.cities.find((x) => x.id === m.town);
    const p = town && ctx.world.players.find((x) => x.id === town.owner);
    return {
      id: m.id, folk: true, mind: m, name: m.name, gender: m.sex, age: m.age, alive: m.gone !== "dead", rank: "commoner", station: m.station, born: m.station,
      traits: m.nature ?? [], memories: (m.memories ?? []).map((x) => x.text), goals: (m.wants ?? []).map((w) => ({ kind: "want", text: w.text })),
      relationships: {}, children: [], spouse: null, home: m.town, seat: null, playerId: town?.owner ?? null,
      house: p ? houseFor(p).name : "the realm", loyalty: 50, reverie: m.reverie ?? 0,
    };
  }

  person(id, ctx) {
    if (this.court.people[id]) return this.court.people[id];
    if (ctx.minds && String(id).startsWith("folk:")) return this.folkPerson(ctx.minds.get(id), ctx);
    return undefined;
  }

  mindOf(who, ctx) {
    if (!ctx.minds || !who || who.town) return null;
    return who.folk ? who.mind : ctx.minds.get(who.id);
  }

  reverieOf(c, ctx) {
    return c.folk ? c.reverie : ctx.minds?.minds?.[c.id]?.reverie ?? 0;
  }

  // Bonds move with opinion: in the mind, trust and warmth, on -1..1.
  bond(a, b, n, ctx) {
    const m = this.mindOf(a, ctx);
    if (!m || !b || b.town) return;
    const x = (m.bonds[b.id] ??= { trust: 0, warmth: 0, note: "" });
    x.trust = clamp(x.trust + n / 200, -1, 1);
    x.warmth = clamp(x.warmth + n / 100, -1, 1);
  }

  // A commoner taken up into a lord's service becomes a person of the court,
  // carrying their mind (and its memories) with them.
  lift(p, ctx) {
    const m = p.mind;
    const lord = this.court.lordOfHouse(p.playerId);
    const c = {
      id: `c${this.court.seq++}`, name: p.name, surname: p.name.split(" ").slice(-1)[0], gender: p.gender, age: p.age, alive: true,
      traits: [...p.traits].slice(0, 7), loyalty: 60, goals: p.goals.slice(0, 2), relationships: {}, memories: p.memories.slice(-6),
      spouse: null, children: [], house: p.house, playerId: p.playerId, rank: "sworn", seat: null, liege: lord?.id ?? null,
      created: "arc", born: p.station, station: p.station, fromFolk: p.id,
    };
    while (this.court.people[c.id]) c.id = `c${this.court.seq++}`;
    this.court.people[c.id] = c;
    this.court.save(c);
    ctx.minds.minds[c.id] = { ...m, id: c.id, station: "sworn" };
    m.gone = `taken into the service of ${p.house}`;
    ctx.minds.save();
    return c;
  }

  // --- casting -------------------------------------------------------------------

  busy(id) {
    return this.active.filter((a) => Object.values(a.roles).includes(id)).length >= MAX_ARCS_EACH;
  }

  // Finds people (and towns) for every role, or null. Each role is filled in
  // the order the file gives; later roles can lean on earlier ones. People
  // whose memories, traits and aims fit a role best are the likeliest picks.
  cast(t, ctx) {
    const keys = Object.keys(t.roles);
    for (let attempt = 0; attempt < 30; attempt++) {
      const roles = {};
      let ok = true;
      for (const k of keys) {
        const spec = t.roles[k];
        const pool = spec.new ? [] : spec.town ? this.towns(spec, roles, ctx) : this.people(spec, roles, ctx);
        const used = new Set(Object.values(roles).map((x) => x.id));
        const free = pool.filter((x) => !used.has(x.c.id));
        if (!free.length) {
          if (spec.create || spec.new) { roles[k] = this.spawn(spec.create ?? spec.new, roles, ctx); continue; }
          if (spec.optional) continue;
          ok = false;
          break;
        }
        let roll = Math.random() * free.reduce((s, x) => s + x.w, 0);
        roles[k] = (free.find((x) => (roll -= x.w) < 0) ?? free[free.length - 1]).c;
      }
      if (!ok) continue;
      // Two people the chronicle can't tell apart can't share a story.
      const names = Object.values(roles).filter((x) => !x.town).map((x) => x.name);
      if (new Set(names).size !== names.length) continue;
      // The same person doesn't lead the same kind of story twice running.
      const leadKey = keys.find((k) => roles[k] && !roles[k].town);
      const lead = roles[leadKey];
      if (lead && this.done.some((d) => d.template === t.id && d.roles[leadKey] === lead.id && this.clock - (d.ended ?? 0) < (t.cooldown ?? 12) * 4)) continue;
      const arc = { roles: Object.fromEntries(Object.entries(roles).map(([k, v]) => [k, v.town ? `town:${v.id}` : v.id])), started: this.clock };
      if (this.test(t.when ?? {}, arc, ctx, roles)) {
        // Someone made for the story only joins the realm once it begins.
        for (const v of Object.values(roles)) if (v.unborn) { delete v.unborn; this.court.people[v.id] = v; this.court.save(v); }
        for (const k of keys) if (t.roles[k].lift && roles[k]?.folk) roles[k] = this.lift(roles[k], ctx);
        return roles;
      }
    }
    return null;
  }

  people(spec, roles, ctx) {
    const out = [];
    // Commoners are cast only where a role names them ("rank": "commoner").
    const ranks = [spec.rank, ...(spec.either ?? []).map((e) => e.rank)].flat().filter(Boolean);
    const folk = ctx.minds && ranks.includes("commoner")
      ? Object.values(ctx.minds.minds).filter((m) => String(m.id).startsWith("folk:") && !m.gone).map((m) => this.folkPerson(m, ctx))
      : [];
    for (const c of [...this.court.alive(), ...folk]) {
      if (this.busy(c.id) || c.ward && !spec.ward) continue;
      const w = this.fits(spec, c, roles, ctx);
      if (w > 0) out.push({ c, w });
    }
    return out;
  }

  // How well someone fits a role: 0 if they can't play it at all.
  fits(spec, c, roles, ctx) {
    if (spec.either) {
      const best = Math.max(0, ...spec.either.map((s) => this.fits({ ...spec, either: undefined, ...s }, c, roles, ctx)));
      return best;
    }
    const has = (t) => c.traits.includes(t);
    const list = (v) => (Array.isArray(v) ? v : [v]);
    if (spec.rank && !list(spec.rank).includes(c.rank)) return 0;
    if (spec.gender && c.gender !== spec.gender) return 0;
    if (spec.otherGender && roles[spec.otherGender] && c.gender === roles[spec.otherGender].gender) return 0;
    // Rules a town role: holds it as a seat, or leads the house that owns it.
    if (spec.rules) { const town = roles[spec.rules]; if (!town || !(c.seat === town.id || (c.rank === "lord" && c.playerId === town.owner))) return 0; }
    if (spec.age && (c.age < spec.age[0] || c.age > spec.age[1])) return 0;
    if (spec.station && !re(spec.station).test(c.station ?? c.rank)) return 0;
    if (spec.reverie && (this.reverieOf(c, ctx) < spec.reverie[0] || this.reverieOf(c, ctx) > spec.reverie[1])) return 0;
    if (spec.townOf) { const town = roles[spec.townOf]; if (!town || (c.home ?? c.seat) !== town.id) return 0; }
    if (spec.bondOf) { const m = this.mindOf(roles[spec.bondOf], ctx); if (!m || !((m.bonds?.[c.id]?.warmth ?? 0) > 0)) return 0; }
    if (spec.traits && !list(spec.traits).some(has)) return 0;
    if (spec.notTraits && list(spec.notTraits).some(has)) return 0;
    if (spec.unwed && c.spouse) return 0;
    if (spec.wed && !c.spouse) return 0;
    if (spec.seat && c.seat == null) return 0;
    if (spec.loyalty && (c.loyalty < spec.loyalty[0] || c.loyalty > spec.loyalty[1])) return 0;
    if (spec.goal && !c.goals?.some((g) => re(spec.goal).test(g.kind) || re(spec.goal).test(g.text))) return 0;
    if (spec.remembers && !c.memories.some((m) => re(spec.remembers).test(m))) return 0;
    if (spec.parents && !(c.parents ?? []).some((p) => this.court.people[p])) return 0;
    if (spec.children && !(c.children ?? []).some((id) => this.court.people[id]?.alive)) return 0;
    const of = (k) => roles[spec[k]];
    if (spec.house && of("house") && c.playerId !== of("house").playerId) return 0;
    if (spec.otherHouse && of("otherHouse") && c.playerId === of("otherHouse").playerId) return 0;
    if (spec.childOf && !(of("childOf")?.children ?? []).includes(c.id)) return 0;
    if (spec.parentOf && !(c.children ?? []).includes(of("parentOf")?.id)) return 0;
    if (spec.spouseOf && of("spouseOf")?.spouse !== c.id) return 0;
    if (spec.kinOf) {
      const k = of("kinOf");
      if (!k || !(k.children?.includes(c.id) || c.children?.includes(k.id) || k.spouse === c.id || (k.parents ?? []).some((p) => c.parents?.includes(p)))) return 0;
    }
    if (spec.swornTo && c.liege !== of("swornTo")?.id) return 0;
    if (spec.liegeOf && of("liegeOf")?.liege !== c.id) return 0;
    if (spec.opinion) { const [r, op, n] = spec.opinion; if (!roles[r] || !cmp(this.court.opinion(c.id, roles[r].id), op, n)) return 0; }
    if (spec.opinionOf) { const [r, op, n] = spec.opinionOf; if (!roles[r] || !cmp(this.court.opinion(roles[r].id, c.id), op, n)) return 0; }
    const p = ctx.world.players.find((x) => x.id === c.playerId);
    if (spec.houseGold && !(p && p.gold >= spec.houseGold[0] && p.gold <= spec.houseGold[1])) return 0;
    if (spec.houseTowns && !(p && p.cities >= spec.houseTowns[0] && p.cities <= spec.houseTowns[1])) return 0;
    if (spec.favour && !(p && ctx.favour(p.id) >= spec.favour[0] && ctx.favour(p.id) <= spec.favour[1])) return 0;
    if (spec.hungry && !this.hungryTowns(c.playerId, ctx).length) return 0;
    if (spec.plague && !ctx.world.cities.some((x) => x.owner === c.playerId && ctx.town(x.id).plague)) return 0;
    // Named in someone's memory: the person (or, if they're dead, whoever now
    // leads their house) that a remembered wrong points at.
    if (spec.namedBy) {
      const by = roles[spec.namedBy.role];
      if (!by || !this.named(by, spec.namedBy.memory).some((n) => n === c.id)) return 0;
    }
    let w = 1;
    if (spec.rules && c.seat === roles[spec.rules].id) w += 4;
    const likes = spec.likes ?? {};
    if (likes.remembers) w += 3 * c.memories.filter((m) => re(likes.remembers).test(m)).length;
    if (likes.traits) w += 2 * list(likes.traits).filter(has).length;
    if (likes.goal && c.goals?.some((g) => re(likes.goal).test(g.kind))) w += 3;
    if (spec.remembers) w += 2 * c.memories.filter((m) => re(spec.remembers).test(m)).length;
    if (likes.reverie) w += 100 * this.reverieOf(c, ctx);
    return w;
  }

  // Who someone's matching memories name: by full name, by house, or the
  // living lord of a named house when the named one is dead.
  named(by, pattern) {
    const out = new Set();
    const alive = this.court.alive();
    for (const m of by.memories.filter((x) => re(pattern).test(x))) {
      for (const c of Object.values(this.court.people)) {
        if (c.id === by.id || !c.name || !m.includes(c.name)) continue;
        if (c.alive) out.add(c.id);
        else { const heir = alive.find((x) => x.playerId === c.playerId && x.rank === "lord"); if (heir && heir.id !== by.id) out.add(heir.id); }
      }
      for (const lord of alive.filter((x) => x.rank === "lord" && x.id !== by.id)) if (m.includes(lord.house)) out.add(lord.id);
    }
    return [...out];
  }

  towns(spec, roles, ctx) {
    const out = [];
    for (const town of ctx.world.cities) {
      const x = { ...town, ...ctx.town(town.id), town: true };
      if (spec.ownedBy && roles[spec.ownedBy] && town.owner !== roles[spec.ownedBy].playerId) continue;
      if (spec.notOwnedBy && roles[spec.notOwnedBy] && town.owner === roles[spec.notOwnedBy].playerId) continue;
      if (spec.seatOf && town.id !== roles[spec.seatOf]?.seat) continue;
      if (spec.homeOf && town.id !== (roles[spec.homeOf]?.seat ?? roles[spec.homeOf]?.home)) continue;
      if (spec.notCapital && town.capital) continue;
      if (spec.size && (town.size < spec.size[0] || town.size > spec.size[1])) continue;
      if (spec.hungry && !this.isHungry(x)) continue;
      if (spec.plague && !x.plague) continue;
      if (spec.afflicted && !(x.plague || x.famine || ctx.recent().some((e) => e.city === town.id && /plague|famine|sickness|starve/i.test(e.text ?? "")))) continue;
      if (spec.unheld && this.court.lordOfTown(town.id)) continue;
      if (spec.struck && !ctx.recent().some((e) => e.city === town.id && re(spec.struck).test(e.text ?? ""))) continue;
      out.push({ c: x, w: 1 + town.size * 0.2 });
    }
    return out;
  }

  isHungry(t) {
    return (t.food !== undefined && t.food < 3) || Boolean(t.famine) || Boolean(t.plague);
  }

  hungryTowns(pid, ctx) {
    return ctx.world.cities.filter((x) => x.owner === pid && this.isHungry({ ...x, ...ctx.town(x.id) }));
  }

  // Someone the story needs who isn't in the realm yet: a bastard come to
  // court, a friar off the road, a boy from the stables.
  spawn(spec, roles, ctx) {
    const like = roles[spec.like] ?? Object.values(roles).find((x) => !x.town);
    const r = Math.random;
    const gender = spec.gender ?? (r() < 0.5 ? "male" : "female");
    const first = (gender === "male" ? ["Jon", "Wat", "Hob", "Ned", "Piers", "Col", "Dickon", "Alun", "Rafe", "Tam"] : ["Meg", "Bess", "Nan", "Elin", "Kat", "Moll", "Jenet", "Sybil"])[Math.floor(r() * 8)];
    const pickOne = (v) => (Array.isArray(v) ? v[Math.floor(r() * v.length)] : v);
    const surname = this.fillRoles(pickOne(spec.surname ?? "Hill"), roles);
    const name = spec.name ? this.fillRoles(pickOne(spec.name), roles).replace("{first}", first) : `${first} ${surname}`;
    const c = {
      id: `c${this.court.seq++}`, name, surname, gender,
      age: rand(spec.age ?? [18, 30]), alive: true, traits: [...(spec.traits ?? [])], loyalty: spec.loyalty ?? 50,
      goals: spec.goal ? [{ kind: spec.goal.kind, text: this.fillRoles(spec.goal.text, roles) }] : [], relationships: {}, memories: spec.memory ? [this.fillRoles(spec.memory, roles)] : [],
      spouse: null, children: [], house: like?.house ?? "the realm", playerId: like?.playerId ?? null,
      rank: spec.rank ?? "sworn", seat: null, liege: like?.rank === "lord" ? like.id : like?.liege ?? null, created: "arc", unborn: true,
      ...(spec.born ? { born: spec.born, station: spec.station ?? spec.born } : spec.station ? { station: spec.station } : {}),
    };
    while (this.court.people[c.id]) c.id = `c${this.court.seq++}`;
    if (spec.childOf && roles[spec.childOf]) c.parents = [roles[spec.childOf].id];
    return c;
  }

  // --- the realm's state -----------------------------------------------------------

  roles(arc, ctx) {
    const out = {};
    for (const [k, v] of Object.entries(arc.roles)) {
      if (String(v).startsWith("town:")) {
        const id = Number(String(v).slice(5));
        const town = ctx.world.cities.find((x) => x.id === id);
        out[k] = { id, town: true, gone: !town, ...(town ?? {}), ...ctx.town(id) };
      } else { const p = this.person(v, ctx); if (p) out[k] = p; }
    }
    return out;
  }

  house(role, ctx) {
    if (!role || role.folk) return null;
    const pid = role.town ? role.owner : role.playerId;
    return ctx.world.players.find((x) => x.id === pid) ?? null;
  }

  // The branch language: every key must hold. Reads people and the live realm.
  test(cond, arc, ctx, cast = null) {
    if (!cond) return true;
    const roles = cast ?? this.roles(arc, ctx);
    const R = (k) => roles[k];
    const H = (k) => this.house(R(k), ctx);
    const num = (pick, [k, op, n]) => { const h = H(k); return h ? cmp(pick(h), op, n) : false; };
    for (const [key, v] of Object.entries(cond)) {
      const ok = (() => {
        switch (key) {
          case "all": return v.every((c) => this.test(c, arc, ctx, cast));
          case "any": return v.some((c) => this.test(c, arc, ctx, cast));
          case "not": return !this.test(v, arc, ctx, cast);
          case "chance": return Math.random() < v;
          case "alive": return [v].flat().every((k) => R(k)?.alive);
          case "dead": return [v].flat().some((k) => R(k) && !R(k).town && !R(k).alive);
          case "gold": return num((h) => h.gold, v);
          case "units": return num((h) => h.units, v);
          case "towns": return num((h) => h.cities, v);
          case "favour": { const h = H(v[0]); return h ? cmp(ctx.favour(h.id), v[1], v[2]) : false; }
          case "stronger": { const [a, b] = [H(v[0]), H(v[1])]; return a && b ? a.units > b.units * (v[2] ?? 1) : false; }
          case "richer": { const [a, b] = [H(v[0]), H(v[1])]; return a && b ? a.gold > b.gold * (v[2] ?? 1) : false; }
          case "sameHouse": return R(v[0])?.playerId === R(v[1])?.playerId;
          case "holds": { const [who, town] = [R(v[0]), R(v[1])]; return who && town && !town.gone && town.owner === who.playerId; }
          case "razed": return Boolean(R(v)?.gone);
          case "hungry": { const x = R(v); return x ? (x.town ? this.isHungry(x) : this.hungryTowns(x.playerId, ctx).length > 0) : false; }
          case "plague": { const x = R(v); return x ? (x.town ? Boolean(x.plague) : ctx.world.cities.some((c) => c.owner === x.playerId && ctx.town(c.id).plague)) : false; }
          case "realmHungry": return ctx.world.cities.filter((x) => this.isHungry({ ...x, ...ctx.town(x.id) })).length >= v;
          case "atWar": { const [a, b] = [H(v[0]), H(v[1])]; return a && b ? ctx.atWar(a.id, b.id) : false; }
          case "opinion": { const [a, b, op, n] = v; return R(a) && R(b) ? cmp(this.court.opinion(R(a).id, R(b).id), op, n) : false; }
          case "loyalty": return R(v[0]) ? cmp(R(v[0]).loyalty ?? 50, v[1], v[2]) : false;
          case "age": return R(v[0]) ? cmp(R(v[0]).age, v[1], v[2]) : false;
          case "trait": return R(v[0]) ? R(v[0]).traits.some((t) => re(v[1]).test(t)) : false;
          case "remembers": return R(v[0]) ? R(v[0]).memories.some((m) => re(v[1]).test(m)) : false;
          case "rank": return R(v[0]) ? re(`^(${v[1]})$`).test(R(v[0]).rank) : false;
          case "married": return R(v[0])?.spouse === R(v[1])?.id;
          case "wed": return Boolean(R(v)?.spouse);
          case "inArc": { const who = R(v[0]); return Boolean(who) && this.active.some((a) => a !== arc && a.roles && Object.values(a.roles).includes(who.id) && (!v[1] || re(v[1]).test(a.kind))); }
          case "reverie": return R(v[0]) ? cmp(this.reverieOf(R(v[0]), ctx), v[1], v[2]) : false;
          case "mood": { const m = this.mindOf(R(v[0]), ctx); return m ? cmp(m.mood?.[v[1]] ?? 0, v[2], v[3]) : false; }
          case "believes": { const m = this.mindOf(R(v[0]), ctx); return Boolean(m?.beliefs?.some((b) => re(v[1]).test(b))); }
          case "gone": return Boolean(R(v)?.folk && R(v).mind.gone);
          case "seasons": return cmp(this.clock - (arc.started ?? this.clock), v[0], v[1]);
          case "happened": return ctx.recent().some((e) => re(v.kind ?? ".").test(e.kind) && re(v.text ?? ".").test(e.text ?? "") && (!v.town || e.city === R(v.town)?.id) && (!v.house || (e.text ?? "").includes(R(v.house)?.house ?? "\0")));
          default: return false; // a key no one knows holds nothing, so a typo can't fire a branch
        }
      })();
      if (!ok) return false;
    }
    return true;
  }

  // --- what a beat does to the realm ------------------------------------------------

  // The levers, the same ones the court pulls. Returns the Lua sent to Freeciv.
  act(d, arc, roles, ctx) {
    const lua = [];
    const send = (l) => { lua.push(l); ctx.send(l); };
    const R = (k) => roles[k];
    const court = this.court;
    const gold = (pid, n) => send(`for p in players_iterate() do if p.id == ${pid} then edit.change_gold(p, ${Math.round(n)}) end end`);
    for (const [a, b, n] of d.opinion ?? []) {
      if (!R(a) || !R(b) || R(a).town) continue;
      if (court.people[R(a).id]) court.shift(R(a).id, R(b).id, n);
      this.bond(R(a), R(b), n, ctx);
    }
    for (const [k, n] of Object.entries(d.loyalty ?? {})) if (!R(k)?.folk && R(k)?.loyalty !== undefined) R(k).loyalty = Math.max(0, Math.min(100, R(k).loyalty + n));
    const fav = {};
    for (const [k, n] of Object.entries(d.favour ?? {})) { const h = this.house(R(k), ctx); if (h) fav[h.id] = (fav[h.id] ?? 0) + n; }
    if (Object.keys(fav).length) ctx.shift(fav);
    for (const [k, n] of Object.entries(d.gold ?? {})) { const h = this.house(R(k), ctx); if (h) gold(h.id, n); }
    // Gold from one house to another: what a bribe, a dowry or a blood price costs.
    for (const [from, to, n] of d.pay ?? []) { const [a, b] = [this.house(R(from), ctx), this.house(R(to), ctx)]; if (a && b) { const amt = Math.min(n, Math.max(0, a.gold)); gold(a.id, -amt); gold(b.id, amt); } }
    for (const [k, v] of Object.entries(d.units ?? {})) {
      const who = R(k);
      const h = this.house(who, ctx);
      const at = who?.town ? who : ctx.world.cities.find((x) => x.id === who?.seat) ?? ctx.world.cities.find((x) => x.owner === h?.id && x.capital) ?? ctx.world.cities.find((x) => x.owner === h?.id);
      if (at) send(`local c = find.city(nil, ${at.id}); if c then local t = find.unit_type("${v.type ?? "Pikemen"}") or find.unit_type("Warriors"); for i = 1, ${Number(v.count ?? v) || 1} do edit.create_unit(c.owner, c.tile, t, 1, c, -1) end end`);
    }
    // Men without banners: soldiers by the victim's town die, its house loses gold.
    if (d.raid && R(d.raid[0]) && R(d.raid[1])) {
      const [atk, def] = [R(d.raid[0]), R(d.raid[1])];
      const prey = d.raid[2] && R(d.raid[2])?.town ? R(d.raid[2]) : ctx.world.cities.find((x) => x.owner === def.playerId && !x.capital) ?? ctx.world.cities.find((x) => x.owner === def.playerId);
      if (prey) send(`local c = find.city(nil, ${prey.id}); if c then for t in c.tile:square_iterate(1) do for u in t:units_iterate() do if u.owner == c.owner and math.random() < 0.5 then edit.unit_kill(u, "killed", nil) end end end; edit.change_gold(c.owner, -50) end`);
      if (court.people[def.id]) court.shift(def.id, atk.id, -35);
    }
    // War: a host raised beside the victim's town; Freeciv's AI fights it out.
    if (d.war && R(d.war[0]) && R(d.war[1])) {
      const [atk, def] = [R(d.war[0]), R(d.war[1])];
      const prey = (d.war[2] && R(d.war[2])?.town && R(d.war[2])) || ctx.world.cities.find((x) => x.owner === def.playerId && !x.capital) || ctx.world.cities.find((x) => x.owner === def.playerId);
      if (prey && atk.playerId !== def.playerId) {
        send(`realm_host(realm_find_player(${atk.playerId}), ${prey.x}, ${prey.y}, {"Pikemen","Archers","Knights","Catapult"}, ${Number(d.warSize ?? 6)})`);
        court.shift(def.id, atk.id, -50);
        if (court.truces) delete court.truces[[atk.id, def.id].sort().join(":")];
      }
    }
    if (d.truce && R(d.truce[0]) && R(d.truce[1])) { court.truces ??= {}; court.truces[[R(d.truce[0]).id, R(d.truce[1]).id].sort().join(":")] = (ctx.world.turn ?? 0) + 4 * (d.truce[2] ?? 2); court.saveCourt(); }
    // A town changes hands; whoever holds it as a seat goes with it.
    if (d.transfer && R(d.transfer[0])?.town && R(d.transfer[1])) {
      const [town, to] = [R(d.transfer[0]), R(d.transfer[1])];
      const toPid = to.town ? to.owner : to.playerId;
      if (!town.gone && town.owner !== toPid) {
        send(`local c = find.city(nil, ${town.id}); local to; for p in players_iterate() do if p.id == ${toPid} then to = p end end; if c and to then edit.transfer_city(c, to) end`);
        (court.claims ??= []).push({ city: town.id, from: town.owner, to: toPid, turn: ctx.world.turn });
        court.saveCourt();
      }
    }
    // Someone changes sides: they serve the other role's house from now on.
    if (d.defect && R(d.defect[0]) && R(d.defect[1])) {
      const [who, to] = [R(d.defect[0]), R(d.defect[1])];
      const p = ctx.world.players.find((x) => x.id === to.playerId);
      if (p && who.playerId !== to.playerId) {
        who.house = houseFor(p).name; who.playerId = p.id; who.liege = court.lordOfHouse(p.id)?.id ?? null; who.loyalty = 55;
      }
    }
    for (const [k, v] of Object.entries(d.goal ?? {})) if (R(k)?.folk) { const m = R(k).mind; m.wants = [{ text: this.fill(v.text, arc, ctx, roles), why: v.why ?? "" }, ...m.wants].slice(0, 3); } else if (R(k)?.goals) { R(k).goals = [{ kind: v.kind, text: this.fill(v.text, arc, ctx, roles) }, ...R(k).goals.filter((g) => g.kind !== v.kind)].slice(0, 3); }
    for (const [k, v] of Object.entries(d.traits ?? {})) if (R(k)?.folk) { const m = R(k).mind; m.nature = [...new Set([...m.nature.filter((t) => !(v.remove ?? []).includes(t)), ...(v.add ?? [])])]; } else if (R(k)?.traits) { R(k).traits = [...new Set([...R(k).traits.filter((t) => !(v.remove ?? []).includes(t)), ...(v.add ?? [])])].slice(0, 7); }
    for (const [k, rank] of Object.entries(d.rank ?? {})) {
      if (R(k)?.folk) { if (rank === "exile") R(k).mind.gone = "left"; continue; }
      if (R(k) && PERSON_RANKS.includes(rank)) R(k).rank = rank;
    }
    // Gone from the story's town: a commoner walks away; a named person into exile.
    for (const k of [d.leave ?? []].flat()) { if (R(k)?.folk) R(k).mind.gone = "left"; else if (R(k)) R(k).rank = "exile"; }
    // The mind itself: reverie, beliefs, wants and feelings, for named and common alike.
    for (const [k, n] of Object.entries(d.reverie ?? {})) { const m = this.mindOf(R(k), ctx); if (m) m.reverie = clamp((m.reverie ?? 0) + n); }
    for (const [k, b] of Object.entries(d.believe ?? {})) { const m = this.mindOf(R(k), ctx); const text = this.fill(b, arc, ctx, roles); if (m && !m.beliefs.includes(text)) m.beliefs = [...m.beliefs, text].slice(-5); }
    for (const [k, w] of Object.entries(d.want ?? {})) { const m = this.mindOf(R(k), ctx); const text = this.fill(w, arc, ctx, roles); if (m && !m.wants.some((x) => x.text === text)) m.wants = [{ text, why: "" }, ...m.wants].slice(0, 3); }
    // A seat granted or taken: [who, town] gives it; [who, null] takes it away.
    if (d.seat && R(d.seat[0])) { const town = d.seat[1] ? R(d.seat[1]) : null; R(d.seat[0]).seat = town?.town ? town.id : null; }
    // Taken into a house: name, house and a father, as when a bastard is acknowledged.
    if (d.adopt && R(d.adopt[0]) && R(d.adopt[1])) {
      const [kid, parent] = [R(d.adopt[0]), R(d.adopt[1])];
      kid.surname = parent.surname; kid.name = `${kid.name.split(" ")[0]} ${parent.surname}`; kid.house = parent.house; kid.playerId = parent.playerId;
      kid.parents = [parent.id]; if (!parent.children.includes(kid.id)) parent.children.push(kid.id);
    }
    if (d.marry && R(d.marry[0]) && R(d.marry[1])) { const [x, y] = [R(d.marry[0]), R(d.marry[1])]; x.spouse = y.id; y.spouse = x.id; }
    for (const k of [d.unwed ?? []].flat()) { const x = R(k); if (x?.spouse) { const y = court.people[x.spouse]; if (y?.spouse === x.id) y.spouse = null; x.spouse = null; if (y) court.save(y); } }
    if (d.die) {
      for (const spec of [d.die].flat()) {
        const who = R(spec.who);
        if (who?.alive && Math.random() < (spec.chance ?? 1)) {
          if (who.folk) {
            if (spec.how) ctx.minds.remember(who.mind, this.fill(spec.how, arc, ctx, roles), { weight: 1, kind: "arc", moves: { fear: 0.5, grief: 0.3 } });
            who.mind.gone = "dead";
            (arc.mourned ??= []).push(spec.who);
            continue;
          }
          if (spec.how) court.remember(who.id, this.fill(spec.how, arc, ctx, roles));
          court.die(who, ctx.world.turn, ctx.world);
          (arc.mourned ??= []).push(spec.who);
        }
      }
    }
    for (const who of Object.values(roles)) if (!who.town && court.people[who.id]) court.save(who);
    ctx.minds?.save();
    return lua;
  }

  // --- words -----------------------------------------------------------------------

  // {role} is a name; {role.house}, {role.houseName}, {role.first}, {role.seat},
  // {role.surname}, {role.age} and pronouns ({role.he}, {role.his}, {role.lord},
  // {role.son}...) as in the court's deck; a town role is its name; {thread}
  // is the arc's own title.
  fill(text, arc, ctx, roles = null) {
    return this.fillRoles(String(text ?? "").replace(/\{thread\}/g, arc.title ?? "the tale"), roles ?? this.roles(arc, ctx));
  }

  fillRoles(text, roles) {
    return String(text ?? "").replace(/\{(\w+)(?:\.(\w+))?\}/g, (all, role, field) => {
      const r = roles[role];
      if (!r) return all;
      if (r.town) return cityName(r.id);
      const f = r.gender === "female";
      const pron = { he: f ? "she" : "he", He: f ? "She" : "He", his: f ? "her" : "his", His: f ? "Her" : "His", him: f ? "her" : "him", himself: f ? "herself" : "himself", wife: f ? "husband" : "wife", son: f ? "daughter" : "son", man: f ? "woman" : "man", lord: f ? "lady" : "lord", Lord: f ? "Lady" : "Lord", father: f ? "mother" : "father", brother: f ? "sister" : "brother", king: f ? "queen" : "king", sir: f ? "lady" : "ser", Sir: f ? "Dame" : "Ser" };
      if (!field) return r.name;
      if (field in pron) return pron[field];
      if (field === "first") return r.name.split(" ")[0];
      if (field === "houseName") return String(r.house ?? "").replace(/^House /, "");
      if (field === "seat") return (r.seat ?? r.home) != null ? cityName(r.seat ?? r.home) : String(r.house ?? "").replace(/^House /, "");
      if (field === "station" || field === "born") return String(r[field] ?? r.station ?? r.rank ?? "");
      return String(r[field] ?? "");
    });
  }

  // --- for the view and the King -------------------------------------------------------

  view(ctx) {
    const show = (a) => ({
      id: a.id, title: a.title, kind: a.kind, template: a.template, status: a.status ?? "running", at: a.at, started: a.started, ended: a.ended,
      cast: Object.fromEntries(Object.entries(this.roles(a, ctx)).map(([k, v]) => [k, v.town ? cityName(v.id) : `${v.name}${v.alive ? "" : " (dead)"}`])),
      beats: a.beats,
    });
    return { clock: this.clock, active: this.active.map(show), done: this.done.slice(-30).reverse().map(show) };
  }
}
