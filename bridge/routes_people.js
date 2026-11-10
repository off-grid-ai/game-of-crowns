// The realm's people up close: a great house, a person and their fall, the starting
// cast's options and new characters, a town's folk and named people, talking to
// them in the street, and the lord of a town.
// Moved verbatim from server.js's ROUTES table (consolidation C3, step 8): each
// handler is (ctx, req, res, url). Nothing here reads server.js: the bridge's
// state and helpers come in as one context argument (routeCtx), built fresh by
// server.js on each request; the realm's state is read through it (ctx.world,
// ctx.meta...) at the moment it is used, as the handlers read it before, so a
// snapshot or a switch of chronicle during an await is seen.

import fs from "node:fs";
import path from "node:path";
import { BANDS } from "./favour.js";
import { GOALS, ROLES, TRAITS } from "./characters.js";
import * as chron from "./chronicles.js";
import { cityName, houseFor } from "./narrator.js";
import { folkPlain, folkTale, speak } from "./claude.js";
import { townsfolk } from "./townsfolk.js";
import { body, json } from "./http_util.js";

export async function house(ctx, req, res, url) {
  const { detail, favourOf } = ctx;
  // One great house: its numbers over time, its lord, bannermen, wars and allies.
  const pid = Number(url.searchParams.get("id"));
  const p = ctx.world?.players.find((x) => x.id === pid);
  if (!p) return json(res, 404, { error: "no such house" });
  const h = houseFor(p);
  const d = detail()?.players[pid];
  const nameOf = (id) => houseFor(ctx.world.players.find((x) => x.id === id) ?? {}).name;
  const great = (id) => ctx.world.players.some((x) => x.id === id && !houseFor(x).wild);
  const lord = ctx.court.lordOfHouse(pid);
  const person = (c) => c && { id: c.id, gender: c.gender, name: c.name, age: c.age, traits: c.traits, goal: c.goals?.[0]?.text, loyalty: c.loyalty, seat: c.seat != null ? cityName(c.seat) : null, role: c.role ? ROLES[c.role]?.title : null, created: !!c.created };
  return json(res, 200, {
    id: pid, name: h.name, words: h.words, seat: h.seat, color: h.color,
    favour: h.wild || h.crown ? null : favourOf(pid),
    history: ctx.history.slice(-40).map((r) => ({ turn: r.turn, souls: (r.houses[h.name]?.pop ?? 0) * 600, ...(r.houses[h.name] ?? {}) })).filter((r) => r.towns !== undefined),
    lord: person(lord),
    bannermen: ctx.court.alive().filter((c) => c.rank === "bannerman" && c.playerId === pid).map(person),
    // The same truth as the houses table: wars the King has stilled are truces,
    // and a loyal house's engine war with the crown isn't a war.
    ...(() => {
      const me = ctx.court.lordOfHouse(pid);
      const stilled = (q) => { const o = ctx.court.lordOfHouse(q); return !!(me && o && ctx.court.truce(me.id, o.id)); };
      const crownId = ctx.world.players.find((x) => houseFor(x).crown)?.id;
      const loyal = (id) => id !== crownId && favourOf(id) >= BANDS.steady;
      const foes = (d?.atWarWith ?? []).filter(great).filter((q) => !((q === crownId && loyal(pid)) || (pid === crownId && loyal(q))));
      return { wars: foes.filter((q) => !stilled(q)).map(nameOf), truces: foes.filter(stilled).map(nameOf) };
    })(),
    allies: (d?.allies ?? []).filter((id) => id !== pid && great(id)).map(nameOf),
  });
}

export async function person(ctx, req, res, url) {
  // One person up close, for the character view: who they are and what they remember.
  const c = ctx.court.people[url.searchParams.get("id")] ?? ctx.court.alive().find((x) => x.name === url.searchParams.get("name"));
  if (!c) return json(res, 404, { error: "no such person" });
  return json(res, 200, {
    id: c.id, name: c.name, gender: c.gender, age: c.age, alive: c.alive, rank: c.rank, house: c.house,
    traits: c.traits, goals: (c.goals ?? []).map((g) => g.text), goal: c.goals?.[0]?.kind ?? null, role_key: c.role ?? null, loyalty: c.loyalty,
    seat: c.seat != null ? cityName(c.seat) : null, role: c.role ? ROLES[c.role]?.title : null,
    memories: [...new Set(c.memories ?? [])].slice(-6), backstory: c.backstory ?? null,
  });
}

export async function characterOptions(ctx, req, res, url) {
  return json(res, 200, { roles: Object.fromEntries(Object.entries(ROLES).map(([k, v]) => [k, v.title])), goals: GOALS, traits: TRAITS });
}

export async function fall(ctx, req, res, url) {
  // Someone the King walked as fell in a fight: a real death, and their heir inherits.
  const { id, how } = await body(req);
  const c = ctx.court.people[String(id)];
  if (!c || !c.alive || !ctx.world) return json(res, 400, { error: "no such person" });
  if (how) ctx.court.remember(c.id, String(how).slice(0, 200));
  ctx.court.die(c, ctx.world.turn, ctx.world);
  return json(res, 200, { ok: true });
}

export async function editPerson(ctx, req, res, url) {
  const spec = await body(req);
  const out = ctx.court.edit(String(spec.id), spec, ctx.world);
  return json(res, out.error ? 400 : 200, out);
}

export async function createCharacter(ctx, req, res, url) {
  if (!ctx.world) return json(res, 503, { error: "the realm is still forming" });
  const out = ctx.court.create(await body(req), ctx.world);
  return json(res, out.error ? 400 : 200, out);
}

export async function folkOf(ctx, req, res, url) {
  // The folk of a town, and, asked for one person, their story in full.
  const city = ctx.world?.cities.find((c) => c.id === Number(url.searchParams.get("city")));
  if (!city) return json(res, 404, { error: "no such town" });
  const folk = townsfolk(city);
  const i = url.searchParams.get("i");
  if (i === null) return json(res, 200, { town: cityName(city.id), folk });
  const person = folk[Number(i)];
  if (!person) return json(res, 404, { error: "no such person" });
  const file = path.join(ctx.P.state, "folk-tales.json");
  const tales = chron.readJson(file) ?? {};
  const key = `v2:${city.id}:${person.i}:${person.name}`;  // v2: tales about the person, not the realm
  if (!tales[key]) {
    const owner = ctx.world.players.find((p) => p.id === city.owner);
    // Only what happened in their own town touches a commoner's tale.
    const near = ctx.chronicle.filter((e) => e.city === city.id && e.kind !== "tithe").slice(-1).map((e) => e.text);
    const tale = await folkTale(person, cityName(city.id), houseFor(owner).name, near);
    // No local model: their life told plainly, and not kept, so the model can tell it later.
    if (!tale) return json(res, 200, { town: cityName(city.id), person, ...folkPlain(person, cityName(city.id)) });
    tales[key] = tale;
    fs.writeFileSync(file, JSON.stringify(tales, null, 1));
  }
  return json(res, 200, { town: cityName(city.id), person, ...tales[key] });
}

export async function townPeople(ctx, req, res, url) {
  // The named people of a town, for someone walking it: its lord or lady, and
  // the bannermen and heirs seated there.
  // At a house's seat its whole household gathers: the heir and the bannermen too.
  const id = Number(url.searchParams.get("city"));
  const town = ctx.world?.cities.find((c) => c.id === id);
  const here = ctx.court.alive().filter((c) => ["lord", "heir", "bannerman"].includes(c.rank)
    && (c.seat === id || (town?.capital && c.playerId === town.owner && c.rank !== "lord")));
  return json(res, 200, here.slice(0, 6).map((c) => ({ id: c.id, name: c.name, gender: c.gender, rank: c.rank, house: c.house })));
}

export async function talk(ctx, req, res, url) {
  const { talkToNamed, isKing, KING } = ctx;
  // You speak to someone in the street; they answer in their own voice and remember it.
  const b = await body(req);
  const city = ctx.world?.cities.find((c) => c.id === Number(b.city));
  if (!city) return json(res, 404, { error: "no such town" });
  if (b.person) return talkToNamed(res, city, String(b.person), b);
  const person = townsfolk(city)[Number(b.i)];
  // b.greet: they've only just walked up, and the townsperson speaks first.
  const greet = !!b.greet;
  const said = greet ? "(They walk up to you and stop, and say nothing yet: you speak first, as you would to them, by what you know of them and what they have done.)" : String(b.said ?? "").trim().slice(0, 400);
  if (!person || !said) return json(res, 400, { error: "nobody to hear it" });
  const key = `v2:${city.id}:${person.i}:${person.name}`;
  const tales = chron.readJson(path.join(ctx.P.state, "folk-tales.json"), {});
  const file = path.join(ctx.P.state, "talks.json");
  const talks = chron.readJson(file, {});
  const past = (talks[key] ?? []).slice(-10);
  const owner = ctx.world.players.find((p) => p.id === city.owner);
  const speaker = b.you?.id ? ctx.court.people[String(b.you.id)] : null;
  const you = isKing(b) ? { ...KING } : {
    name: speaker?.name ?? String(b.you?.name ?? "a stranger"),
    house: speaker?.house ?? String(b.you?.house ?? ""),
    title: speaker ? (speaker.rank === "lord" ? (speaker.gender === "female" ? "Lady" : "Lord") : speaker.rank) : "",
    lord: speaker ? speaker.playerId === city.owner && speaker.rank === "lord" : false,
  };
  // How a commoner names them to their face.
  if (!isKing(b)) you.address = !speaker ? "stranger" : speaker.rank === "lord" || speaker.rank === "heir" ? (speaker.gender === "female" ? "my lady" : "my lord") : speaker.gender === "female" ? "my lady" : "ser";
  const near = ctx.chronicle.filter((e) => e.city === city.id || (e.text ?? "").includes(cityName(city.id))).slice(-5).map((e) => e.text);
  const mindId = `folk:${city.id}:${person.i}`;
  const out = await speak(person, cityName(city.id), houseFor(owner).name, you, near, tales[key]?.story ?? "", past, said, ctx.meta.options?.language ?? "en", ctx.minds.forTalk(mindId, { id: isKing(b) ? "king" : speaker?.id, name: you.name }));
  if (!out) return json(res, 503, { error: `${person.name} only stares at you. (The local model isn't running.)` });
  talks[key] = [...past, ...(greet ? [] : [{ who: you.name, text: said }]), { who: person.name, text: out.reply }].slice(-16);
  fs.writeFileSync(file, JSON.stringify(talks, null, 1));
  if (!greet) ctx.minds.talked(mindId, { id: isKing(b) ? "king" : speaker?.id, name: you.name }, said, out.reply);
  // A lord remembers being spoken to by their own people, briefly.
  if (speaker) ctx.court.remember(speaker.id, `In ${cityName(city.id)} I spoke with ${person.name}, the ${person.trade}.`);
  return json(res, 200, { name: person.name, trade: person.trade, gender: person.woman ? "female" : "male", ...out });
}

export async function lord(ctx, req, res, url) {
  return json(res, 200, ctx.court.summary(Number(url.searchParams.get("city"))) ?? {});
}
