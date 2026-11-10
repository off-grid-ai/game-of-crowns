// The realm's stories: the arcs running and their templates, fast-forward and
// begin, and the player's own stories (shaped from tags or words, their beats,
// Off Grid AI's ideas for them, and arc files written to bridge/arcs).
// Moved verbatim from server.js's ROUTES table (consolidation C3, step 8): each
// handler is (ctx, req, res, url). Nothing here reads server.js: the bridge's
// state and helpers come in as one context argument (routeCtx), built fresh by
// server.js on each request; the realm's state is read through it (ctx.world,
// ctx.meta...) at the moment it is used, as the handlers read it before, so a
// snapshot or a switch of chronicle during an await is seen.

import fs from "node:fs";
import path from "node:path";
import { arcFromWords, beatIdea, premiseIdea, writeFor } from "./claude.js";
import { templates as arcTemplates, check, storiesChanged } from "./arcs.js";
import { body, json } from "./http_util.js";

export async function arcs(ctx, req, res, url) {
  const { inCrowns, arcCtx } = ctx;
  return json(res, 200, inCrowns(ctx.arcs.view(arcCtx())));
}

export async function templates(ctx, req, res, url) {
  return json(res, 200, arcTemplates().map((t) => ({ id: t.id, file: t.file, name: t.name, title: t.title, about: t.about, reign: Boolean(t.reign), own: Boolean(t.own), tags: t.tags ?? [], roles: Object.keys(t.roles ?? {}), beats: (t.beats ?? []).length, problems: t.problems })));
}

// Fast-forward: n seasons of the realm's stories, against the live realm.
export async function tick(ctx, req, res, url) {
  const { runArcs, inCrowns, arcCtx } = ctx;
  const b = await body(req);
  const ran = await runArcs(Math.max(1, Math.min(60, Number(b.n) || 1)), b.start !== false);
  return json(res, ran ? 200 : 409, ran ? inCrowns(ctx.arcs.view(arcCtx())) : { error: "the stories are already moving" });
}

// Begin one kind of story now, if the realm has the people for it.
export async function start(ctx, req, res, url) {
  const { arcCtx, inCrowns } = ctx;
  const b = await body(req);
  if (ctx.arcsRunning) return json(res, 409, { error: "the stories are already moving" });
  ctx.arcsRunning = true;
  try {
    const all = arcTemplates().filter((t) => !t.problems.length);
    const arc = await ctx.arcs.begin(all, arcCtx(), String(b.template ?? ""));
    ctx.arcs.save();
    return arc ? json(res, 200, inCrowns(ctx.arcs.view(arcCtx()).active.find((a) => a.id === arc.id))) : json(res, 404, { error: "nobody in the realm fits that story now" });
  } finally {
    ctx.arcsRunning = false;
  }
}

// The King's own story: an arc file dropped in as JSON, or told in words
// and shaped by the model from the closest existing arc.
// A reign story of the player's own: from tags, a few lines of premise, or
// both. It is built on the tested story that fits best (so every beat holds),
// carries the player's tags (the dials) and their words, and is named by the
// local model when it's there, by the tags when it isn't.
export async function generate(ctx, req, res, url) {
  const { OWN_STORIES } = ctx;
  const b = await body(req);
  const words = String(b.words ?? "").trim().slice(0, 600);
  let tags = (Array.isArray(b.tags) ? b.tags : []).map(String).filter((t) => /^[a-z-]{1,24}$/.test(t)).slice(0, 8);
  if (!words && !tags.length) return json(res, 400, { error: "give it some tags, a few lines, or both" });
  const shapes = arcTemplates().filter((t) => t.reign && !t.problems.length && !t.told);
  if (!shapes.length) return json(res, 503, { error: "no reign stories to build on" });
  // Words with no tags: the words suggest the tags.
  const WORDS = { usurper: /claim|throne|usurp|pretender|crown/, war: /war|feud|battle|siege|raid/, intrigue: /poison|plot|spy|secret|murder|assassin/, "the-dead": /dead|wall|winter|north|undead/, famine: /famine|hunger|starv|grain|harvest/, plague: /plague|fever|sick|pestilence|pox/, money: /debt|bank|gold|coin|loan/, rebellion: /rising|peasant|riot|rebel|revolt|poor/, violent: /blood|slaughter|massacre|burn|kill/, "fast-paced": /sudden|swift|quick|fast/, "slow-burn": /slow|years|generation|creeping/, cunning: /cunning|clever|scheme|deceit|betray/, tragic: /tragic|grief|mourning|loss|doomed/ };
  const asked = tags.length > 0;  // the player chose tags (rather than the words suggesting them)
  if (words && !tags.length) tags = Object.entries(WORDS).filter(([, r]) => r.test(words.toLowerCase())).map(([t]) => t);
  // The tested story that shares most with what was asked.
  const THREATS = /^(usurper|war|intrigue|the-dead|famine|plague|money|rebellion|faith|succession|invasion)$/;
  const score = (t) => (t.tags ?? []).filter((g) => tags.includes(g)).reduce((n, g) => n + (THREATS.test(g) ? 6 : 1), 0) + (words ? (t.about ?? "").toLowerCase().split(/\W+/).filter((w) => w.length > 4 && words.toLowerCase().includes(w)).length : 0);
  let base = shapes.slice().sort((a, b2) => score(b2) - score(a) || Math.random() - 0.5)[0];
  let name = null;
  if (words) {
    const out = await Promise.race([arcFromWords(words, shapes.map((t) => ({ id: t.id, name: t.name, about: t.about }))), new Promise((r) => setTimeout(() => r(null), 20000))]);
    if (out?.shape && !asked) base = shapes.find((t) => t.id === out.shape) ?? base;
    name = out?.name ?? null;
  }
  if (!name) {
    const ADJ = { violent: "Red", gritty: "Grim", cunning: "Silent", "fast-paced": "Swift", tragic: "Bitter", political: "Gilded", mysterious: "Hidden", epic: "Great", aggressive: "Iron", "slow-burn": "Long" };
    const NOUN = { usurper: "Claim", war: "Feud", intrigue: "Cup", "the-dead": "Winter", famine: "Hunger", plague: "Fever", money: "Debt", rebellion: "Rising", faith: "Faith", succession: "Heir", invasion: "Tide" };
    const adj = tags.map((t) => ADJ[t]).find(Boolean) ?? ["Broken", "Last", "Hollow", "Thorned"][Math.floor(Math.random() * 4)];
    const noun = tags.map((t) => NOUN[t]).find(Boolean) ?? (base.kind === "usurper" ? "Claim" : "Reckoning");
    name = `The ${adj} ${noun}`;
  }
  const slug = (x) => String(x).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40);
  const arc = structuredClone(base);
  delete arc.own;
  delete arc.file; delete arc.problems;
  arc.id = `told-${slug(name)}-${Date.now().toString(36).slice(-4)}`;
  arc.name = name;
  arc.title = name;
  arc.about = words || base.about;
  arc.tags = [...new Set([...tags, ...(base.tags ?? []).filter((g) => /^(usurper|war|intrigue|the-dead|famine|plague|money|rebellion|faith|succession|invasion|great-house|the-court|the-people|foreign)$/.test(g))])];
  arc.told = { from: base.id, words, tags };
  const problems = check(arc);
  if (problems.length) return json(res, 400, { error: "that story doesn't hold together", problems });
  fs.writeFileSync(path.join(OWN_STORIES, `${arc.id}.json`), JSON.stringify(arc, null, 2));
  storiesChanged();
  return json(res, 200, { ok: true, id: arc.id, name: arc.name, about: arc.about, tags: arc.tags, from: base.name });
}

// A story of the player's own, for the beat form: who is in it (its roles, in
// words) and the beats they have added so far.
export async function own(ctx, req, res, url) {
  const { ownStory, storyForForm } = ctx;
  const t = ownStory(url.searchParams.get("id"));
  if (!t) return json(res, 404, { error: "that isn't a story of your own" });
  return json(res, 200, storyForForm(t));
}

// One beat of the player's own, added to (or taken out of) their story: what
// happens, who is in it, when it happens, and what it does, from short menus.
// It happens once, when its moment comes, and the story goes on from there.
// Off Grid AI fills (or carries on) any free-text box: {kind, context, draft}.
export async function write(ctx, req, res, url) {
  const b = await body(req);
  const text = await Promise.race([writeFor(String(b.kind ?? ""), String(b.context ?? "").slice(0, 1200), String(b.draft ?? "").trim().slice(0, 300)).catch(() => null), new Promise((r) => setTimeout(() => r(null), 45000))]);
  if (!text) return json(res, 503, { error: "Off Grid AI is busy and didn't answer in time. Try again in a moment." });
  return json(res, 200, { text });
}

// Off Grid AI writes a story's premise from its tags, or carries on the one begun.
export async function suggestPremise(ctx, req, res, url) {
  const b = await body(req);
  const tags = (Array.isArray(b.tags) ? b.tags : []).map(String).slice(0, 8);
  const draft = String(b.draft ?? "").trim().slice(0, 300);
  const text = await Promise.race([premiseIdea({ tags, draft }).catch(() => null), new Promise((r) => setTimeout(() => r(null), 45000))]);
  if (!text) return json(res, 503, { error: "Off Grid AI is busy and didn't answer in time. Try again in a moment, or write it yourself." });
  return json(res, 200, { text });
}

// Off Grid AI writes a beat for the player's own story, or carries on the one begun.
export async function suggestBeat(ctx, req, res, url) {
  const { ownStory, rolesOf } = ctx;
  const b = await body(req);
  const t = ownStory(b.story);
  if (!t) return json(res, 404, { error: "shape a story of your own first" });
  const roles = rolesOf(t).filter((r) => !r.town);
  const beats = [...(t.beats ?? []), ...(t.asides ?? [])].map((x) => x.text).filter(Boolean);
  const draft = String(b.draft ?? "").trim().slice(0, 300);
  const text = await Promise.race([beatIdea({ name: t.name, about: t.about ?? "", roles, beats, draft }).catch(() => null), new Promise((r) => setTimeout(() => r(null), 45000))]);
  if (!text) return json(res, 503, { error: "Off Grid AI is busy and didn't answer in time. Try again in a moment, or write the beat yourself." });
  return json(res, 200, { text });
}

export async function beat(ctx, req, res, url) {
  const { ownStory, rolesOf, BEAT_WHEN, BEAT_DOES, OWN_STORIES, storyForForm } = ctx;
  const b = await body(req);
  const t = ownStory(b.story);
  if (!t) return json(res, 404, { error: "add beats to a story of your own: shape one first" });
  delete t.own; delete t.file; delete t.problems;
  t.asides ??= [];
  if (b.remove) {
    t.asides = t.asides.filter((x) => x.id !== String(b.remove));
  } else {
    const text = String(b.text ?? "").trim().replace(/\s+/g, " ").slice(0, 300);
    if (text.length < 8) return json(res, 400, { error: "say what happens, in a line or two" });
    const people = rolesOf(t).filter((r) => !r.town).map((r) => r.id);
    const who = String(b.who ?? "");
    if (!people.includes(who)) return json(res, 400, { error: "choose who is in it" });
    const when = BEAT_WHEN[b.when];
    if (!when) return json(res, 400, { error: "choose when it happens" });
    const does = BEAT_DOES[b.does ?? "nothing"];
    if (!does) return json(res, 400, { error: "choose what it does" });
    const n = Math.max(0, ...t.asides.map((x) => Number(String(x.id).replace(/\D/g, "")) || 0)) + 1;
    t.asides.push({ id: `yours-${n}`, text, speaker: who, stage: does.stage ?? "rising", when: when.if, do: does.do(who, text), ...(does.court ? { court: does.court(who, text) } : {}), form: { who, when: b.when, does: b.does ?? "nothing" } });
  }
  const problems = check(t);
  if (problems.length) return json(res, 400, { error: "that beat doesn't hold together", problems });
  fs.writeFileSync(path.join(OWN_STORIES, `${t.id}.json`), JSON.stringify(t, null, 2));
  storiesChanged();
  return json(res, 200, storyForForm({ ...t, own: true }));
}

export async function writeArc(ctx, req, res, url) {
  const { DIR } = ctx;
  const b = await body(req);
  const dir = path.join(DIR, "arcs");
  const slug = (x) => String(x).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40);
  let arc;
  if (b.arc) {
    arc = typeof b.arc === "string" ? JSON.parse(b.arc) : b.arc;
  } else {
    const words = String(b.words ?? "").trim().slice(0, 600);
    if (!words) return json(res, 400, { error: "say what the story is" });
    const shapes = arcTemplates().filter((t) => !t.problems.length && !t.told);
    const given = shapes.filter((t) => t.id === b.shape);
    const out = await arcFromWords(words, (given.length ? given : shapes).map((t) => ({ id: t.id, name: t.name, about: t.about })));
    const base = given[0] ?? shapes.find((t) => t.id === out?.shape);
    if (!base) return json(res, 503, { error: "the local model isn't there to shape it; drop an arc file in bridge/arcs instead" });
    const name = out?.name || words.split(/[.,;]/)[0].slice(0, 40);
    arc = structuredClone(base);
    delete arc.file; delete arc.problems;
    arc.id = `told-${slug(name)}`;
    arc.name = name;
    arc.about = words;
    arc.told = { from: base.id, words };
    const anchor = Object.keys(base.roles)[0];
    arc.title = /^the /i.test(name) ? `${name} of {${anchor}.seat}` : `The ${name} of {${anchor}.seat}`;
  }
  const problems = check(arc);
  if (problems.length) return json(res, 400, { error: "that arc doesn't hold together", problems });
  const file = path.join(dir, `${slug(arc.id)}.json`);
  fs.writeFileSync(file, JSON.stringify(arc, null, 2));
  storiesChanged();
  return json(res, 200, { ok: true, file: path.relative(DIR, file), arc });
}
