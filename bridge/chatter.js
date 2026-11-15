// Talk between the people of Aldmere (docs/MINDS.md, "Talk"). When minds meet
// they say a few lines to each other, each in their own voice, nature and
// mood, drawn from what they remember, believe and feel about each other.
// Afterwards their bonds shift, rumours pass on a little changed in the
// telling, and both remember the talk. Travellers (carters, friars) carry
// what they heard along the roads, so a rumour started in one town turns up
// in the next, and every belief keeps who it came from: it can be traced.
//
// Only hot and warm minds get lines from the local model. Cold ones still
// pass gossip on, by rules, without words.

import fs from "node:fs";
import path from "node:path";

// What a town says about the King and its own state (the crowd thinks out loud).
const THOUGHTS = JSON.parse(fs.readFileSync(new URL("./data/thoughts.json", import.meta.url), "utf8"));
import { cityName } from "./narrator.js";

// Who carries news between towns.
const TRAVELLERS = new Set(["carter", "friar", "anchoress", "pedlar", "soldier", "minstrel"]);
// Seasons a rumour keeps travelling after someone heard it (data/thoughts.json rumourSeasons).
const STALE = THOUGHTS.rumourSeasons;

// --- the minds (bridge/minds.js) ---------------------------------------------------

// What talk needs of the minds' store. Beliefs in a mind stay plain words, as
// minds.js keeps them; where each rumour came from is kept here, in `heard`.
class Store {
  constructor(minds, heard, turn) {
    this.of = minds;   // () -> the Minds of the open realm
    this.heard = heard; // mind id -> rumour id -> { text, from, heard, hops }
    this.turn = turn;
  }

  town(cityId) {
    return this.of()?.town(cityId)?.minds ?? [];
  }

  get(id) {
    return this.of()?.get(id) ?? null;
  }

  remember(id, { text, about = [], weight = 0.4 }) {
    const m = this.get(id);
    if (m) this.of().remember(m, text, { about, weight, kind: "gossip" });
  }

  bond(id, other, d) {
    this.of()?.bond(id, other, d);
    return this.get(id)?.bonds?.[other] ?? null;
  }

  // Their belief, in the words they heard it in; a retelling replaces their older version.
  believe(id, belief) {
    const m = this.get(id);
    if (!m) return;
    const mine = (this.heard[id] ??= {});
    const old = mine[belief.rumour]?.text;
    mine[belief.rumour] = belief;
    m.beliefs = [...(m.beliefs ?? []).filter((b) => b !== old && b !== belief.text), belief.text].slice(-5);
    this.of().save();
  }

  knows(id, rumour) {
    return Boolean(this.heard[id]?.[rumour]);
  }

  // Rumours they hold, oldest first.
  rumours(id) {
    return Object.entries(this.heard[id] ?? {}).map(([rumour, b]) => ({ ...b, rumour })).sort((a, b) => (a.heard ?? 0) - (b.heard ?? 0));
  }

  tier(id) {
    return this.of()?.tier(id) ?? "cold";
  }
}

// --- rumours ---------------------------------------------------------------------

// A tale grows in the telling, when nobody's there to write it better: a
// word made worse, or one more thing tacked on (each only once).
const WORSE = [
  [/\bseen\b/, "caught"], [/\bonce\b/, "twice"], [/\btwice\b/, "three times"], [/\bsome\b/, "a great deal of"], [/\bsold\b/, "has been selling"],
  [/\bmeeting\b/, "lying with"], [/\bcursing\b/, "threatening"], [/\bmoney\b/, "a fortune"], [/\ba purse\b/, "a chest of silver"], [/\bfake\b/, "poisoned"],
  [/\btoo much\b/, "till she fell"], [/\blast night\b/, "every night this week"], [/\bmerchants\b/, "merchants, and the reeve knows"],
];
const MORE = ["and the priest knows it", "and that's not the half of it", "and nobody dares say so to their face", "or so the carters tell it"];

function retell(text) {
  let t = String(text).trim().replace(/[.!]+$/, "");
  const worse = WORSE.find(([a, b]) => a.test(t) && !t.includes(b));
  if (worse) t = t.replace(worse[0], worse[1]);
  else {
    const more = MORE.find((x) => !t.includes(x));
    if (more) t = `${t}, ${more}`;
  }
  // "They say" in front, leaving a name its capital.
  if (!/^they say/i.test(t)) t = `They say ${/^(The|A|An|He|She|It|There|His|Her)\b/.test(t) ? t[0].toLowerCase() + t.slice(1) : t}`;
  return `${t}.`;
}

// --- chatter ---------------------------------------------------------------------

export class Chatter {
  // ctx: { world(): the realm, turn(): its season, minds(): the Minds (minds.js) }
  constructor(state, ctx) {
    this.file = path.join(state, "chatter.json");
    this.ctx = ctx;
    let saved = {};
    try { saved = JSON.parse(fs.readFileSync(this.file, "utf8")); } catch { /* a new realm */ }
    this.rumours = saved.rumours ?? {};  // id -> { text, origin, trail: [{ id, name, town, from, text, turn }] }
    this.roads = saved.roads ?? {};      // traveller id -> { from, to, arrive }
    this.visiting = saved.visiting ?? {}; // traveller id -> { town, since, talks }
    this.home = saved.home ?? {};        // traveller id -> when they last came home
    this.talks = saved.talks ?? [];      // recent conversations, newest last
    this.heard = saved.heard ?? {};
    this.minds = new Store(ctx.minds, this.heard, ctx.turn);
    // Cold towns gossip by rules, and travellers walk the roads, whether or not anyone watches.
    this.timer = setInterval(() => this.idle(), 60000);
    this.timer.unref?.();
  }

  save() {
    clearTimeout(this.saving);
    this.saving = setTimeout(() => {
      const keep = { rumours: this.rumours, heard: this.heard, roads: this.roads, visiting: this.visiting, home: this.home, talks: this.talks.slice(-60) };
      fs.writeFileSync(this.file, JSON.stringify(keep, null, 1));
    }, 500);
  }

  // Everyone standing in a town now: its own folk at home, and travellers visiting.
  present(city) {
    const home = this.minds.town(city).filter((m) => m && !this.roads[m.id] && !this.visiting[m.id]);
    const guests = Object.entries(this.visiting).filter(([, v]) => v.town === city).map(([id]) => this.minds.get(id)).filter(Boolean);
    return [...home, ...guests];
  }

  // GET /minds/chatter?city=ID[&who=i,j][&wait=1]: what to play in that town now.
  // `who` is a gathering on screen (near the camera, so hot): it gets talk of its own.
  // Townsfolk no longer talk (Mac 2026-11-15, the fps round: "we don't need the townsfolk speech bubbles... remove
  // all those calls"): the model was busy 139% of the time on them, on the GPU the game draws with. Rumours still
  // travel between towns (travel) and a ruling still becomes the town's talk (afterRuling).
  async chatter() {
    this.travel(this.ctx.turn());
    return [];
  }

  // A rumour begins with one person (a gossip's invention, a story arc, something seen).
  startRumour(m, text, about = null) {
    const id = `r${Date.now().toString(36)}${Math.floor(Math.random() * 1296).toString(36)}`;
    const turn = this.ctx.turn();
    this.rumours[id] = { text, about, origin: { id: m.id, name: m.name, town: cityName(m.town) }, trail: [{ id: m.id, name: m.name, town: cityName(m.town), from: null, text, turn }] };
    const belief = { text, rumour: id, from: null, heard: turn, hops: 0 };
    this.minds.believe(m.id, belief);
    this.save();
    return belief;
  }

  hear(l, teller, belief, text) {
    const turn = this.ctx.turn();
    this.minds.believe(l.id, { text, rumour: belief.rumour, from: teller.id, heard: turn, hops: (belief.hops ?? 0) + 1 });
    const r = this.rumours[belief.rumour];
    r?.trail.push({ id: l.id, name: l.name, town: cityName(this.visiting[l.id]?.town ?? l.town), from: teller.name, text, turn });
  }

  // --- the roads -------------------------------------------------------------------

  // Travellers who've done their business in a town set off for the next one,
  // and arrive in time, carrying all they've heard.
  travel(turn = this.ctx.turn()) {
    const world = this.ctx.world();
    if (!world) return;
    const now = Date.now();
    for (const [id, road] of Object.entries(this.roads)) {
      if (now < road.arrive) continue;
      delete this.roads[id];
      const home = this.minds.get(id);
      if (home && road.to !== home.town) this.visiting[id] = { town: road.to, since: now, talks: 0 };
      else {
        delete this.visiting[id];
        this.home[id] = now;
      }
      // Arriving, they tell someone at once: the alehouse, the well.
      if (home && road.to !== home.town) this.ruleTalk(home, road.to, turn);
      this.save();
    }
    // Who sets off: a traveller who knows a rumour and has told it where they are.
    const knowers = new Set(Object.values(this.rumours).flatMap((r) => r.trail.map((t) => t.id)));
    for (const id of knowers) {
      const m = this.minds.get(id);
      if (!m || !TRAVELLERS.has(m.station) || this.roads[m.id]) continue;
      const v = this.visiting[m.id];
      const ready = v ? v.talks >= 1 && now - v.since > 60000 : this.minds.rumours(m.id).some((b) => turn - (b.heard ?? 0) <= 8) && now - (this.home[m.id] ?? 0) > 120000;
      if (!ready) continue;
      // Visiting: home again. At home: the nearest town.
      const c = world.cities.find((x) => x.id === (v?.town ?? m.town));
      const next = v ? m.town : c && this.nearest(c, world);
      const to = world.cities.find((x) => x.id === next);
      if (!c || !to) continue;
      this.roads[m.id] = { from: c.id, to: next, arrive: now + Math.max(30000, Math.hypot(to.x - c.x, to.y - c.y) * 6000) };
      this.minds.remember(m.id, { turn, text: `I set off for ${cityName(next) ?? to.name}${v ? ", home" : " with my news"}.`, about: [], weight: 0.2 });
      this.save();
    }
  }

  nearest(c, world) {
    let best = null;
    let d = Infinity;
    for (const o of world.cities) {
      if (o.id === c.id) continue;
      const x = Math.hypot(o.x - c.x, o.y - c.y);
      if (x < d) { d = x; best = o.id; }
    }
    return best;
  }

  // Gossip without words (cold minds): the teller's freshest rumour passes on, grown a little.
  ruleTalk(teller, city, turn) {
    const here = this.present(city).filter((o) => o.id !== teller.id);
    const belief = this.news(teller, here);
    if (!belief || turn - (belief.heard ?? 0) > STALE) return null;
    const fresh = here.filter((o) => !this.minds.knows(o.id, belief.rumour));
    const l = pick(fresh.length ? fresh : here);
    const text = retell(belief.text);
    this.hear(l, teller, belief, text);
    this.minds.bond(l.id, teller.id, { trust: 0.03, warmth: 0.03, note: `told me ${short(text)}` });
    this.minds.remember(l.id, { turn, text: `${teller.name}${teller.town !== city ? ` from ${cityName(teller.town)}` : ""} told me: ${text}`, about: [teller.id], weight: 0.4 });
    this.minds.remember(teller.id, { turn, text: `In ${cityName(city)} I told ${l.name} what I'd heard.`, about: [l.id], weight: 0.3 });
    if (this.visiting[teller.id]) this.visiting[teller.id].talks += 1;
    return { to: l.name, from: teller.name, text };
  }

  // Every little while: the roads, and one rule-told rumour in a town whose minds aren't being watched.
  idle() {
    try {
      const turn = this.ctx.turn();
      this.fromState(this.ctx.world());  // a town's hunger, siege or levy becomes its talk
      this.travel(turn);
      // Old news stops travelling: only rumours heard in the last few seasons are told on.
      const live = Object.keys(this.heard).filter((id) => this.minds.rumours(id).some((b) => turn - (b.heard ?? 0) <= STALE));
      const tellers = live.map((id) => this.minds.get(id)).filter((m) => m && !this.roads[m.id] && this.minds.tier(m.id) === "cold");
      const m = pick(tellers);
      if (m) {
        this.ruleTalk(m, this.visiting[m.id]?.town ?? m.town, turn);
        this.save();
      }
    } catch (err) {
      console.error("chatter:", err.message);
    }
  }

  // GET /minds/rumours[?id=]: every rumour with its trail, person by person.
  trace(id) {
    return id ? this.rumours[id] ?? null : Object.entries(this.rumours).map(([k, r]) => ({ id: k, ...r }));
  }

  // POST /minds/rumour { city, i, text }: a rumour starts with one person (story arcs, something seen).
  // --- the crowd thinks out loud (bridge/data/thoughts.json; RCT's guest thoughts) ---------

  // A ruling at a town becomes the town's talk: a line from thoughts.json by who it helped or hurt.
  // ruling: { city, text, helps: [house names], hurts: [house names] }
  async afterRuling(ruling) {
    if (!THOUGHTS.on || ruling?.city == null) return null;
    const helped = ruling.helps?.[0], hurt = ruling.hurts?.[0];
    const pool = helped ? THOUGHTS.ruling.helped : hurt ? THOUGHTS.ruling.hurt : THOUGHTS.ruling.plain;
    const line = pick(pool).replace("{house}", helped ?? hurt ?? "");
    return this.think(ruling.city, line);
  }

  // What a town's state says before any number does: hunger, siege, a levy (once per spell).
  fromState(world) {
    if (!THOUGHTS.on) return;
    const seen = (this.stateSeen ??= {});
    for (const c of world?.cities ?? []) {
      for (const [kind, on] of [["hunger", c.famine], ["siege", c.besieged], ["levy", (c.levy ?? 0) > 0]]) {
        const key = `${c.id}:${kind}`;
        if (on && !seen[key]) { seen[key] = true; this.think(c.id, pick(THOUGHTS[kind])); }
        else if (!on) delete seen[key];
      }
    }
  }

  // One of the town's folk takes it up; travellers carry it on from there.
  think(city, text) {
    const folk = (this.minds.town(city) ?? []).filter(Boolean);
    const m = pick(folk);
    return m && text ? this.startRumour(m, String(text).slice(0, 200)) : null;
  }

  // The town's loudest thoughts: what most of its folk now hold, freshest first.
  thoughtsOf(city) {
    const count = {};
    // Read from what the town's folk have heard (this.heard, by mind id), never seeding minds for a town.
    const prefix = `folk:${city}:`;
    for (const id of Object.keys(this.heard).filter((k) => k.startsWith(prefix))) {
      for (const b of this.minds.rumours(id)) {
        const k = b.rumour;
        count[k] ??= { text: b.text, n: 0, heard: b.heard ?? 0 };
        count[k].n++;
        count[k].heard = Math.max(count[k].heard, b.heard ?? 0);
      }
    }
    return Object.values(count).sort((a, b) => b.n - a.n || b.heard - a.heard).slice(0, THOUGHTS.perTown).map((t) => t.text);
  }

  plant(city, i, text) {
    const m = this.minds.town(city)[i];
    return m && text ? { id: this.startRumour(m, String(text).slice(0, 200)).rumour } : null;
  }

  stop() {
    clearInterval(this.timer);
  }

  // The routes, for server.js.
  async route(url, req, body) {
    const city = Number(url.searchParams.get("city"));
    if (url.pathname === "/minds/chatter") {
      if (!this.ctx.world()?.cities.some((c) => c.id === city)) return [404, { error: "no such town" }];
      const who = (url.searchParams.get("who") ?? "").split(",").filter(Boolean).map(Number);
      return [200, await this.chatter(city, who, url.searchParams.has("wait"))];
    }
    if (url.pathname === "/minds/rumours") {
      const r = this.trace(url.searchParams.get("id"));
      return r ? [200, r] : [404, { error: "no such rumour" }];
    }
    if (url.pathname === "/minds/rumour" && req.method === "POST") {
      const b = await body(req);
      const out = this.plant(Number(b.city), Number(b.i), b.text);
      return out ? [200, out] : [400, { error: "nobody to start it" }];
    }
    return null;
  }
}
