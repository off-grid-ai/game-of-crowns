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
import * as llm from "./claude.js";
import { cityName } from "./narrator.js";

// Who carries news between towns.
const TRAVELLERS = new Set(["carter", "friar", "anchoress", "pedlar", "soldier", "minstrel"]);
// Talkers and the tight-lipped: how many lines they're good for, and how they take each other.
const TALKATIVE = /gossip|busybody|boastful|drunkard|cheerful|sharp-tongued/;
const QUIET = /shy|miser|gentle|lazy/;
const WARMING = /kind|cheerful|generous|gentle|gossip/;
const COOLING = /quarrelsome|jealous|proud|sharp-tongued|miser|sly/;
const MOODS = { fear: "afraid", anger: "angry", joy: "glad", grief: "grieving", faith: "full of faith", hunger: "hungry" };
// Played conversations stay on offer this long; a gathering's own talk is kept for its life.
const FRESH_MS = 120000;
const GROUP_MS = 90000;
// Seasons a rumour keeps travelling after someone heard it (data/thoughts.json rumourSeasons).
const STALE = THOUGHTS.rumourSeasons;

// Which villager of the town they are, or -1 for a visitor (no body there to speak from).
const villagerOf = (m, city) => (m.town === city ? m.i ?? Number(String(m.id).split(":")[2]) : -1);
// A rumour in a few words, for a bond's note: cut at a word, never mid-word.
const short = (t) => {
  const s = String(t).replace(/^they say( that)?\s*/i, "").replace(/[.!]+$/, "");
  return s.length <= 60 ? s : `${s.slice(0, 60).replace(/\s+\S*$/, "")}…`;
};
const clamp = (x, a = -1, b = 1) => Math.max(a, Math.min(b, x));
const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const natureOf = (m) => (Array.isArray(m.nature) ? m.nature.join(", ") : String(m.nature ?? "ordinary"));

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

// --- the model -------------------------------------------------------------------

// A few plain words from the model, through the minds' priority queue (hot before warm).
async function words(hot, system, prompt, max = 60) {
  const out = await llm.think(system, prompt, hot ? "hot" : "warm", max);
  const text = String(out ?? "").replace(/\*[^*]*\*|\([^)]*\)/g, "").replace(/["“”]/g, "").replace(/\s+/g, " ").trim();
  return (text.match(/[^.!?]+[.!?]+/g) ?? [text]).slice(0, 2).join(" ").trim().slice(0, 220) || null;
}

// A small model writes a better exchange as one little scene than it plays
// a part line by line (that way it only echoes). One example sets the voice.
const SCENE = `You write what ordinary people in a gritty medieval town say to each other: blunt, plain, a little crude, each in their own voice. Every line answers the last and moves on.
Example (a tanner, sour, and a widow, nosy, at the well):
Gib: Water's foul again. Somebody's pissing in it upstream.
Maud: That'll be the Ashby boys. Saw them by the mill race at dusk.
Gib: Then I'll have a word with their father, and not a kind one.
Maud: Mind you do it sober this time.`;
const PLACES = { well: "at the well", market: "at the market", tavern: "in the tavern", bench: "on the bench by the green", sept: "outside the sept", field: "at the field's edge", home: "at a doorstep" };
const first = (m) => String(m.name).split(" ")[0];

// How someone takes a bit of gossip, by their nature.
function react(m) {
  const n = natureOf(m);
  return /quarrel|sharp|proud|jealous/.test(n) ? "doesn't believe a word and says so"
    : /pious|gentle|kind/.test(n) ? "thinks it unkind to say, but asks more"
      : /gossip|busybody|sly/.test(n) ? "wants every detail and adds a bit of their own"
        : /drunk|lazy|cheerful|boast/.test(n) ? "laughs and makes a crude joke of it"
          : /superstitious/.test(n) ? "takes it for an ill omen"
            : "is wary, and asks who told them";
}

// Who they are in a few words: trade, nature, mood today, what weighs on them.
function describe(m, others, news = false) {
  const mood = Object.entries(m.mood ?? {}).filter(([, v]) => v >= 0.55).map(([k]) => MOODS[k]).filter(Boolean);
  // Not the gossip they've traded: they'd only recite it.
  const heavy = (m.memories ?? []).filter((x) => x.kind !== "past" && x.kind !== "gossip" && x.weight >= 0.5).at(-1);
  const bits = [`the ${m.station}`, natureOf(m), ...mood.slice(0, 1)];
  // With news to tell, that's the talk; otherwise now and then what weighs on them.
  if (news) { /* nothing else on their mind */ } else if (heavy && Math.random() < 0.6) bits.push(`still full of this: ${heavy.text.replace(/^I saw it myself: /, "").slice(0, 90)}`);
  else if ((m.beliefs ?? []).some((b) => !/^they say/i.test(b))) bits.push(`sure that ${m.beliefs.filter((b) => !/^they say/i.test(b)).at(-1)}`);
  // How they stand with the others, from their bonds.
  const ties = others.map((o) => {
    const note = String(m.bonds?.[o.id]?.note ?? "");
    if (!note || /^(told me|talked|spoke)/.test(note)) return "";
    return /them/.test(note) ? `${note.replace(/\bthem\b/, first(o))}` : `${first(o)}'s ${note}`;
  }).filter(Boolean);
  return `${first(m)} (${[...bits, ...ties].join("; ")})`;
}

// The words that carry a line's meaning.
const SMALL = new Set("a an the and but or so of to in at on for with is was are be it its i you he she we they my your his her our their that this not no do did have has had will would can just as by from up out what".split(" "));
const gist = (t) => new Set((t.toLowerCase().match(/[a-z']+/g) ?? []).filter((w) => !SMALL.has(w)));

// The talk, read back into lines: each one only once, each by someone there.
function readScene(text, order) {
  const lines = [];
  for (const raw of String(text ?? "").split(/\n+/)) {
    const named = raw.match(/^\s*([A-Z][\w'-]+)(?:\s[\w'-]+)?\s*:\s*(.+)$/);
    // The queue strips a leading name, so an unnamed first line is the first speaker's.
    const m = named ? order.find((o) => first(o).toLowerCase() === named[1].toLowerCase()) : !lines.length ? order[0] : null;
    let said = (named ? named[2] : raw).replace(/\*[^*]*\*|\([^)]*\)/g, "").replace(/["“”]/g, "").trim();
    if (!m || !said) continue;
    // A sentence said twice in a line is said once.
    said = [...new Set(said.match(/[^.!?]+[.!?]*/g)?.map((x) => x.trim()) ?? [said])].join(" ");
    // A line that only says again what was said is dropped.
    const mine = gist(said);
    if (lines.some((l) => { const o = gist(l.text); return [...mine].filter((x) => o.has(x)).length >= Math.max(2, 0.8 * Math.min(mine.size, o.size)); })) continue;
    // Two in a row from one mouth run together, unless that makes a speech of it.
    const last = lines.at(-1);
    if (last?.id === m.id && last.text.length + said.length < 160) last.text = `${last.text} ${said}`;
    else lines.push({ id: m.id, text: said.slice(0, 220) });
  }
  return lines;
}

// --- rumours ---------------------------------------------------------------------

// Plain gossip about a neighbour, for when the model isn't there.
const IDLE_TALK = [
  "{n} was seen leaving the mill before dawn, and not alone",
  "{n} owes money all over town and means to run",
  "{n} has a purse hidden under the floor",
  "{n} was heard cursing the lord's bailiff",
  "{n} has been meeting someone in the woods",
];

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
    this.making = new Map();             // group key -> promise of its conversation
    this.groups = new Map();             // group key -> { at, talk }
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
  async chatter(city, who, wait) {
    const turn = this.ctx.turn();
    this.travel(turn);
    let made = null;
    if (who?.length >= 2) {
      const folk = this.minds.town(city);
      const group = who.map((i) => folk[i]).filter(Boolean);
      if (group.length >= 2) {
        const key = `${city}:${who.slice().sort((a, b) => a - b).join(",")}`;
        const had = this.groups.get(key);
        if (had && Date.now() - had.at < GROUP_MS) return [had.talk];
        if (!this.making.has(key)) {
          this.making.set(key, this.converse(group, city, "hot").then((talk) => {
            this.making.delete(key);
            if (talk) this.groups.set(key, { at: Date.now(), talk });
            return talk;
          }));
        }
        if (wait) made = await this.making.get(key);
        return made ? [made] : [];
      }
    } else {
      // A warm town, with nobody gathered on screen: now and then two who meet by their plans talk.
      const last = this.talks.filter((t) => t.city === city).at(-1);
      if (!last || Date.now() - last.at > 60000) {
        const pair = this.meeting(city);
        if (pair) {
          const p = this.converse(pair, city, "warm");
          if (wait) made = await p;
        }
      }
    }
    const fresh = this.talks.filter((t) => t.city === city && Date.now() - t.at < FRESH_MS);
    return made && !fresh.includes(made) ? [...fresh, made] : fresh;
  }

  // Two (or three) who meet by their plans: same place, each `with` the other.
  // Without plans, someone with news finds someone to tell it.
  meeting(city) {
    const here = this.present(city);
    for (const m of here) {
      const mates = (m.plan?.with ?? []).map((x) => here.find((o) => o.i === x || o.id === x)).filter((o) => o && o !== m && (o.plan?.where ?? null) === (m.plan?.where ?? null));
      if (mates.length) return [m, ...mates.slice(0, 2)];
    }
    const teller = here.find((m) => this.minds.rumours(m.id).length) ?? here.find((m) => /gossip/.test(natureOf(m)));
    if (!teller || here.length < 2) return null;
    const others = here.filter((o) => o !== teller);
    return [teller, pick(others)];
  }

  // A rumour they hold that the listener hasn't heard, freshest first.
  news(m, listeners) {
    return this.minds.rumours(m.id).filter((b) => listeners.some((l) => !this.minds.knows(l.id, b.rumour))).at(-1) ?? null;
  }

  // A gossip with nothing to tell makes something up about a neighbour.
  async invent(m, city, hot) {
    const folk = this.minds.town(city).filter((o) => o && o.id !== m.id);
    const about = pick(folk);
    if (!about) return null;
    const said = await words(hot, `You are ${m.name}, ${m.station} in ${cityName(city) ?? "town"}, by nature ${natureOf(m)}. Medieval town. Answer with one sentence of gossip, plain words, no quotation marks.`,
      `What scandal have you lately heard about ${about.name} the ${about.station}? One sentence.`, 60);
    const text = said ?? IDLE_TALK[Math.floor(Math.random() * IDLE_TALK.length)].replace("{n}", about.name);
    return this.startRumour(m, text, about.id);
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

  // The talk itself: 2-6 lines, each in the speaker's voice, written by the
  // model as one scene from who they are, how they feel, what weighs on them
  // and how they stand with each other. Then what it changed: bonds, a
  // rumour passed on (in the listener's own words), and a memory each.
  async converse(group, city, tier) {
    const hot = tier === "hot";
    const where = PLACES[group[0].plan?.where] ? group[0].plan.where : "street";
    let teller = group.find((m) => this.news(m, group.filter((o) => o !== m)));
    let belief = teller ? this.news(teller, group.filter((o) => o !== teller)) : null;
    if (!teller && Math.random() < 0.6) teller = group.find((m) => /gossip|busybody/.test(natureOf(m)));
    if (teller && !belief) belief = await this.invent(teller, city, hot);
    const order = teller ? [teller, ...group.filter((m) => m !== teller)] : group;
    const chatty = order.filter((m) => TALKATIVE.test(natureOf(m))).length - order.filter((m) => QUIET.test(natureOf(m))).length;
    const count = Math.max(2, Math.min(6, 3 + chatty + (Math.random() < 0.4 ? 1 : 0)));
    const who = order.map((m) => describe(m, order.filter((o) => o !== m), Boolean(belief)));
    const worry = pick(order);
    // News is told first, in the teller's own words, so the talk is about it.
    const opener = belief ? await words(hot, `You are ${teller.name}, the ${teller.station}, by nature ${natureOf(teller)}, in a gritty medieval town. You speak blunt, plain words, no quotation marks.`,
      `Tell ${order.slice(1).map(first).join(" and ")} this bit of gossip in one or two sentences of your own: ${belief.text}`, 70) : null;
    const topic = opener ? `It starts:\n${first(teller)}: ${opener}\n${first(order[1])} ${react(order[1])}. Write the next ${count - 1} lines, taking turns, ${first(order[1])} first.`
      : `Talk turns to what ${first(worry)} wants most: ${String(worry.wants?.[0]?.text ?? worry.wants?.[0] ?? "an easier year").replace(/\b(his|her)\b/g, "their")}.
Write ${count} lines of their talk, taking turns, ${first(order[0])} first.`;
    // A small model may only echo the opener back; then once more, asking for something new.
    let said = [];
    for (let attempt = 0; attempt < 2 && said.length < 2; attempt++) {
      const push = attempt ? " Every line must say something new: a doubt, a question, a joke, a bit of their own news." : "";
      const text = await llm.think(SCENE, `Now: ${who.slice(0, -1).join(", ")} and ${who.at(-1)}, ${PLACES[where] ?? "in the street"}. ${topic} Each line one or two short sentences, as Name: words.${push}`, hot ? "hot" : "warm", 60 * count);
      // The queue strips a leading "Name:", so after an opener the first line is the next speaker's.
      said = readScene(opener ? `${first(teller)}: ${opener}\n${first(order[1])}: ${String(text ?? "").replace(new RegExp(`^\\s*${first(teller)}:.*\\n`), "")}` : text, order);
    }
    const lines = said.slice(0, 6).map((l) => {
      const m = order.find((o) => o.id === l.id);
      return { ...l, who: villagerOf(m, city), name: m.name, gender: m.sex ?? "male" };
    });
    if (lines.length < 2) return null;  // no model, no talk to show; the rules still pass gossip (idle)
    const talk = { id: `t${Date.now().toString(36)}${Math.floor(Math.random() * 46656).toString(36)}`, city, at: Date.now(), turn: this.ctx.turn(), where, tier,
      who: group.map((m) => villagerOf(m, city)), lines: lines.map(({ id, ...l }) => l) };
    talk.passed = belief ? await this.pass(teller, group.filter((m) => m !== teller), belief, lines, hot) : [];
    talk.moved = this.after(group, lines, where, talk.passed);
    if (belief) talk.rumour = belief.rumour;
    this.talks.push(talk);
    this.talks = this.talks.slice(-60);
    for (const m of group) if (this.visiting[m.id]) this.visiting[m.id].talks += 1;
    this.save();
    return talk;
  }

  // The listener keeps the rumour as they understood it: in their own words
  // from the model, or a little grown by the rules. Someone who distrusts
  // the teller hears it and doesn't believe a word.
  async pass(teller, listeners, belief, lines, hot) {
    const told = lines.find((l) => l.id === teller.id)?.text || belief.text;
    const out = [];
    for (const l of listeners) {
      if (this.minds.knows(l.id, belief.rumour)) continue;
      const trust = l.bonds?.[teller.id]?.trust ?? 0;
      if (trust < -0.3) {
        this.minds.remember(l.id, { turn: this.ctx.turn(), text: `${teller.name} told me some tale about ${short(belief.text)}; I don't believe a word from that mouth.`, about: [teller.id], weight: 0.3 });
        continue;
      }
      const heard = hot || Math.random() < 0.5
        ? await words(hot, `You are ${l.name}, by nature ${natureOf(l)}. You pass on gossip in one short sentence, plain words, no quotation marks.`,
          `${first(teller)} told you: ${told}\nNow pass it on to a neighbour as gossip, in your own words: one sentence beginning "They say", about the person it concerns, not about who told you.`, 60)
        : null;
      const text = heard && /\w{3}/.test(heard) ? heard : retell(belief.text);
      this.hear(l, teller, belief, text);
      out.push({ to: l.name, from: teller.name, text });
    }
    return out;
  }

  hear(l, teller, belief, text) {
    const turn = this.ctx.turn();
    this.minds.believe(l.id, { text, rumour: belief.rumour, from: teller.id, heard: turn, hops: (belief.hops ?? 0) + 1 });
    const r = this.rumours[belief.rumour];
    r?.trail.push({ id: l.id, name: l.name, town: cityName(this.visiting[l.id]?.town ?? l.town), from: teller.name, text, turn });
  }

  // Bonds move with how it went, and each remembers it in their own words.
  after(group, lines, where, passed) {
    const turn = this.ctx.turn();
    const moved = [];
    for (const m of group) {
      for (const o of group) {
        if (o === m) continue;
        const mine = natureOf(m);
        let warmth = 0.04 + (WARMING.test(mine) ? 0.05 : 0) - (COOLING.test(mine) ? 0.07 : 0) - ((m.mood?.anger ?? 0) > 0.5 ? 0.06 : 0);
        if (/haggl|argu/i.test(where)) warmth -= 0.03;
        const told = passed.find((p) => p.to === m.name && p.from === o.name);
        const trust = told ? 0.05 : 0.01;
        const note = told ? `told me ${short(told.text)}` : `talked at the ${where}, season ${turn}`;
        const b = this.minds.bond(m.id, o.id, { warmth, trust, note });
        moved.push({ who: m.name, toward: o.name, warmth: +warmth.toFixed(2), trust: +trust.toFixed(2), now: b ? { warmth: +b.warmth.toFixed(2), trust: +b.trust.toFixed(2) } : null });
      }
      const heard = passed.find((p) => p.to === m.name);
      const toldIt = passed.filter((p) => p.from === m.name);
      const names = group.filter((o) => o !== m).map((o) => o.name).join(" and ");
      const said = lines.find((l) => l.id !== m.id)?.text ?? "";
      const text = heard ? `${heard.from} told me: ${heard.text}`
        : toldIt.length ? `I told ${toldIt.map((p) => p.to).join(" and ")} what I'd heard.`
          : `I passed the time with ${names} at the ${where}. ${said.slice(0, 80)}`;
      this.minds.remember(m.id, { turn, text, about: group.filter((o) => o !== m).map((o) => o.id), weight: heard || toldIt.length ? 0.5 : 0.25 });
    }
    return moved;
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

  // A ruling at a town becomes the town's talk: Omni words it from the ruling and the town's state
  // when Off Grid AI is running, else a line from thoughts.json by who it helped or hurt.
  // ruling: { city, text, helps: [house names], hurts: [house names] }
  async afterRuling(ruling) {
    if (!THOUGHTS.on || ruling?.city == null) return null;
    const town = cityName(ruling.city);
    const helped = ruling.helps?.[0], hurt = ruling.hurts?.[0];
    const who = helped ? `It helped ${helped}.` : hurt ? `It hurt ${hurt}.` : "";
    const o = THOUGHTS.omni;
    const said = await words(false, o.system.replace("{town}", town ?? "town"), o.prompt.replace("{ruling}", String(ruling.text ?? "").slice(0, 160)).replace("{who}", who), o.max);
    const pool = helped ? THOUGHTS.ruling.helped : hurt ? THOUGHTS.ruling.hurt : THOUGHTS.ruling.plain;
    const line = said ?? pick(pool).replace("{house}", helped ?? hurt ?? "");
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
