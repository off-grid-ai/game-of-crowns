// The realm's own routes: the world and its map, the chronicle, ledger and records,
// the chronicles (list, create, open), the reign (end, continue, pause and resume, its
// options, its pace), the local model's status, the Lore (the book, its map, the
// player's names and written cast) and a season run on demand.
// Moved verbatim from server.js's ROUTES table (consolidation C3, step 8): each
// handler is (ctx, req, res, url). Nothing here reads server.js: the bridge's
// state and helpers come in as one context argument (routeCtx), built fresh by
// server.js on each request; the realm's state is read through it (ctx.world,
// ctx.meta...) at the moment it is used, as the handlers read it before, so a
// snapshot or a switch of chronicle during an await is seen.

import fs from "node:fs";
import path from "node:path";
import { CIVILIAN } from "./campaigns.js";
import { FAMILIES, LESSER, bible } from "./lore.js";
import { HOUSES, cityName, houseFor, nameIn } from "./narrator.js";
import { ROLES } from "./characters.js";
import { aiStatus, usageToday, watched } from "./claude.js";
import * as chron from "./chronicles.js";
import { OPENING } from "./court.js";
import * as names from "./names.js";
import * as rewrites from "./written.js";
import { body, json } from "./http_util.js";

export async function world(ctx, req, res, url) {
  const { townStates, reignInfo, refreshCounsel, worldView } = ctx;
  townStates();
  if (url.searchParams.get("peek") !== "1") watched(); // the game window polls this every second while open (a test's peek doesn't count)
  if (!ctx.world) return json(res, 503, { error: "realm still forming", reign: reignInfo() });
  if (ctx.counselStale) refreshCounsel();
  return json(res, 200, worldView());
}

export async function realmMap(ctx, req, res, url) {
  const map = chron.readJson(path.join(ctx.P.state, "map.json"));
  return map ? json(res, 200, { ...map, land: ctx.meta?.land ?? null }) : json(res, 503, { error: "map not ready" });
}

export async function chronicle(ctx, req, res, url) {
  const { inCrowns } = ctx;
  const since = Number(url.searchParams.get("since") || 0);
  // The reign's own chronicle, from the crowning: the realm's history before it is not his to read
  // through (gameplay review #9; ?all=1 for the whole of it).
  const from = url.searchParams.get("all") === "1" ? -Infinity : (ctx.meta?.crownedAt ?? ctx.meta?.ambitionsFrom?.turn ?? -Infinity);
  return json(res, 200, inCrowns(ctx.chronicle.filter((e) => e.seq > since && (e.turn ?? 0) >= from).slice(-200)));
}

export async function ledger(ctx, req, res, url) {
  return json(res, 200, ctx.history.slice(-400).map((r) => r.souls !== undefined ? r : { ...r, souls: r.pop * 600, houses: Object.fromEntries(Object.entries(r.houses).map(([k, h]) => [k, { ...h, souls: h.pop * 600 }])) }));
}

export async function records(ctx, req, res, url) {
  return json(res, 200, chron.records().sort((a, b) => b.score - a.score));
}

export async function scenarios(ctx, req, res, url) {
  // Saved starting choices, to begin the same kind of realm again.
  const file = path.join(chron.HOME, "scenarios.json");
  const all = chron.readJson(file, []);
  if (req.method !== "POST") return json(res, 200, all);
  const b = await body(req);
  const name = String(b.name || "").trim().slice(0, 40);
  if (!name) return json(res, 400, { error: "a scenario needs a name" });
  const entry = { name, scenario: b.scenario, minutes: Number(b.minutes) || 0, wealth: b.wealth, mood: String(b.mood || "").slice(0, 300), options: chron.cleanOptions(b.options) };
  fs.writeFileSync(file, JSON.stringify([...all.filter((x) => x.name !== name), entry], null, 1));
  return json(res, 200, entry);
}

export async function chronicleOptions(ctx, req, res, url) {
  return json(res, 200, { defaults: chron.OPTION_DEFAULTS, houses: Object.keys(chron.HOUSE_NATIONS) });
}

export async function listChronicles(ctx, req, res, url) {
  return json(res, 200, { active: ctx.meta.id, list: chron.list().filter((c) => !chron.isTest(c)) });  // the player's reigns only (chronicles.isTest)
}

export async function createChronicle(ctx, req, res, url) {
  const { switchTo } = ctx;
  const b = await body(req);
  const scenario = ["random", "aldmere", "aldmere_fresh"].includes(b.scenario) ? b.scenario : "aldmere";
  const m = chron.create({ name: String(b.name || "A New Realm").slice(0, 40), scenario, minutes: b.minutes, pace: b.options?.pace ?? ctx.turnSeconds, fate: b.fate, wealth: b.wealth, mood: b.mood, options: b.options });
  rewrites.applyTo(path.join(chron.paths(m.id).base, "characters"));  // the starting cast as the player rewrote it
  // A real reign deals its minor folk fresh names; test, film and check reigns keep the baseline's, so proofs repeat.
  if (!/test|film|check|proof/i.test(m.name)) try { rewrites.freshMinorNames(chron.paths(m.id).base, JSON.parse(fs.readFileSync(path.join(path.dirname(new URL(import.meta.url).pathname), "data", "first-names.json"), "utf8")), JSON.parse(fs.readFileSync(path.join(path.dirname(new URL(import.meta.url).pathname), "data", "surnames.json"), "utf8")).bannermen); } catch (e) { console.log("fresh names:", e.message); }
  try { rewrites.distinctNames(chron.paths(m.id).base, JSON.parse(fs.readFileSync(path.join(path.dirname(new URL(import.meta.url).pathname), "data", "first-names.json"), "utf8"))); } catch (e) { console.log("names:", e.message); }  // no two living share a first name
  switchTo(m.id);
  return json(res, 200, m);
}

export async function openChronicle(ctx, req, res, url) {
  const { switchTo } = ctx;
  const { id } = await body(req);
  if (!chron.list().some((c) => c.id === id)) return json(res, 404, { error: "no such chronicle" });
  switchTo(id);
  return json(res, 200, { ok: true });
}

export async function end(ctx, req, res, url) {
  const { endReign, reignInfo } = ctx;
  endReign("The King lays down the crown.");
  return json(res, 200, reignInfo());
}

// The opening (--opening=v2, docs/review/first-ten-minutes-plan.md item 2; Reigns: the first
// input is the core verb, and it comes once the player is in the world): the view says when a new
// reign's story begins ({at: "intro"}) and when the King has landed in his realm ({at: "realm"}).
// While meta.firstCourt is set and he hasn't been in the realm FIRST_COURT_MS, the court doesn't
// sit (court.js). A view that never says (today's opening) leaves the court as it was.
export async function opening(ctx, req, res) {
  const { at } = await body(req);
  const f = (ctx.meta.firstCourt ??= { landedAt: null });
  if (at === "realm" && f.landedAt == null) {
    f.landedAt = Date.now();
    // The court looks again just after the wait, not at the next season's turn (up to 40 s later):
    // the same gate decides (court.js), unforced.
    const court = ctx.courtSeason;
    setTimeout(() => court(ctx.world?.turn ?? 0).catch(() => {}), OPENING.firstCourtAfterLandingSec * 1000 + 500);
  }
  chron.saveMeta(ctx.meta);
  return json(res, 200, { ok: true, firstCourt: f });
}

export async function continueReign(ctx, req, res, url) {
  const { send, timeoutNow, record, reignInfo } = ctx;
  // A timed reign has ended and been scored; the King rules on, with no clock,
  // in the same realm. The score stands in the records as it was.
  if (ctx.meta.status !== "ended") return json(res, 400, { error: "this reign has not ended" });
  ctx.meta.status = "running";
  ctx.meta.minutes = 0;
  ctx.paused = false;
  chron.saveMeta(ctx.meta);
  send(`set timeout ${timeoutNow()}`);
  record({ turn: ctx.world?.turn ?? 0, kind: "decree", text: "The King rules on." });
  return json(res, 200, reignInfo());
}

export async function pause(ctx, req, res, url) {
  const { send, timeoutNow, reignInfo } = ctx;
  if (ctx.meta.status !== "running") return json(res, 400, { error: "this reign has ended" });
  ctx.paused = url.pathname === "/pause";
  send(`set timeout ${timeoutNow()}`);
  return json(res, 200, reignInfo());
}

export async function reignOptions(ctx, req, res, url) {
  const { send, timeoutNow } = ctx;
  // The running reign's choices: read them, or change the ones that can
  // change mid-reign. Start-only choices (the world, which houses, their
  // temper, wealth and trust, the starting host) stay as they were.
  const LIVE = ["pace", "disasters", "raiders", "dead", "usurper", "petitions", "intrigue", "language"];
  const now = { ...chron.cleanOptions(ctx.meta.options ?? {}), pace: ctx.meta.pace ?? chron.PACE.season };
  if (req.method !== "POST") return json(res, 200, { options: now, live: LIVE });
  const b = await body(req);
  const next = chron.cleanOptions({ ...now, ...Object.fromEntries(Object.entries(b).filter(([k]) => LIVE.includes(k))) });
  ctx.meta.options = { ...now, ...Object.fromEntries(LIVE.map((k) => [k, next[k]])) };
  // The season's length is also set by the speed buttons; only change it when asked.
  if ("pace" in b) {
    ctx.meta.pace = ctx.meta.options.pace;
    ctx.turnSeconds = ctx.meta.pace;
    send(`set timeout ${timeoutNow()}`);
  }
  ctx.meta.options.pace = ctx.meta.pace ?? ctx.meta.options.pace;
  chron.saveMeta(ctx.meta);
  // Freeciv's own dials, applied now.
  send(`set disasters ${{ none: 0, gentle: 5, normal: 25, cruel: 70 }[ctx.meta.options.disasters]}`);
  send(`set barbarians ${chron.BARBARIANS[ctx.meta.options.raiders]}`);
  return json(res, 200, { options: ctx.meta.options, live: LIVE });
}

export async function ai(ctx, req, res, url) {
  // What the local model can do right now, for the settings page.
  return json(res, 200, await aiStatus());
}

export async function speed(ctx, req, res, url) {
  const { send, timeoutNow } = ctx;
  const { seconds } = await body(req);
  ctx.turnSeconds = Math.max(chron.PACE.fastest, Math.min(chron.PACE.slowest, Number(seconds) || chron.PACE.season));  // data/pace.json
  ctx.meta.pace = ctx.turnSeconds;
  chron.saveMeta(ctx.meta);
  send(`set timeout ${timeoutNow()}`);
  return json(res, 200, { turnSeconds: ctx.turnSeconds });
}

export async function usage(ctx, req, res, url) {
  return json(res, 200, usageToday());
}

// Aldmere as every new chronicle finds it (the baseline, nine years in): its
// towns on the map, each with its house, for the Lore's map. Never the reign
// being played.
// The player's names for houses and people: GET them, or POST {from, to} to
// rename one (an empty `to` gives the word its own name back).
export async function writePerson(ctx, req, res, url) {
  // Someone of the starting cast rewritten from the menu's Lore: every chronicle begun after this has them so.
  const b = await body(req);
  const out = rewrites.set(String(b.id ?? ""), b);
  return json(res, out.error ? 400 : 200, out);
}

export async function playerNames(ctx, req, res, url) {
  if (req.method === "POST") {
    const raw = await new Promise((r) => { let b = ""; req.on("data", (d) => (b += d)); req.on("end", () => { try { r(JSON.parse(b || "{}")); } catch { r({}); } }); });
    const done = names.rename(raw.from, raw.to);
    res.writeHead(done.error ? 400 : 200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify(done));
  }
  res.writeHead(200, { "Content-Type": "application/json" });
  return res.end(JSON.stringify({ names: names.all() }));
}

export async function loreMap(ctx, req, res, url) {
  let w = {};
  try { w = JSON.parse(fs.readFileSync(path.join(chron.BASELINE, "state", "world.json"), "utf8")); } catch { /* no baseline */ }
  const players = new Map((w.players ?? []).map((p) => [p.id, p]));
  const towns = (w.cities ?? []).map((c) => {
    const h = players.get(c.owner) ? houseFor(players.get(c.owner)) : null;
    return { title: nameIn(c.id, c.name), x: c.x, y: c.y, size: c.size, capital: !!c.capital, house: h?.name ?? "", key: h?.name ?? "", color: h?.color ?? "#888", sigil: h?.sigil ?? "" };
  });
  let land = [];
  try {
    const m = JSON.parse(fs.readFileSync(path.join(chron.BASELINE, "state", "map.json"), "utf8"));
    land = (m.tiles ?? []).filter((t) => !/Ocean|Lake/.test(String(t[2]))).map((t) => [t[0], t[1]]);
  } catch { /* no map */ }
  if (url.searchParams.get("live") !== "1" || !ctx.world?.cities) return json(res, 200, { tiles: [56, 88], towns, land, roads: w.roads ?? [] });
  // The realm as it stands in this reign: each town under whoever holds it now,
  // the hosts in the field (a house's companies within a day's march of each
  // other, as one), and the towns under siege.
  const now = ctx.world.cities.map((c) => {
    const h = houseFor(ctx.world.players.find((p) => p.id === c.owner) ?? {});
    return { title: cityName(c.id), x: c.x, y: c.y, size: c.size, capital: !!c.capital, house: h?.name ?? "", key: h?.name ?? "", color: h?.color ?? "#888", sigil: h?.sigil ?? "", besieged: Boolean(c.besieged) };
  });
  const hosts = [];
  for (const u of (ctx.world.units ?? []).filter((x) => !CIVILIAN.has(x.type) && !/Trireme|Caravel|Galleon|Frigate|Transport/.test(x.type))) {
    if (ctx.world.cities.some((c) => c.x === u.x && c.y === u.y)) continue;  // a garrison, not a host
    const near = hosts.find((g) => g.owner === u.owner && Math.max(Math.abs(g.x - u.x), Math.abs(g.y - u.y)) <= 2);
    if (near) { near.x = (near.x * near.companies + u.x) / (near.companies + 1); near.y = (near.y * near.companies + u.y) / (near.companies + 1); near.companies++; }
    else hosts.push({ owner: u.owner, x: u.x, y: u.y, companies: 1 });
  }
  const armies = hosts.filter((g) => g.companies >= 2).map((g) => {
    const h = houseFor(ctx.world.players.find((p) => p.id === g.owner) ?? {});
    return { x: g.x, y: g.y, companies: g.companies, house: h?.name ?? "", key: h?.name ?? "", color: h?.color ?? "#888", sigil: h?.sigil ?? "", crown: !!h?.crown };
  });
  return json(res, 200, { tiles: [56, 88], towns: now, land, roads: ctx.world.roads ?? w.roads ?? [], armies });
}

export async function lore(ctx, req, res, url) {
  const { DIR, favourOf } = ctx;
  // The book of the realm: its story from the world bible, and each great
  // house as it stands now, with the people who matter in it.
  const b = bible(path.join(DIR, "..", "WORLD.md"));
  const RANK = { lord: 0, spouse: 1, heir: 2, bannerman: 3, child: 4 };
  // A house born of civil war has no page in the bible; its arms and
  // character come from the lesser houses' lore.
  const rebel = (name) => {
    const f = FAMILIES[name.replace("House ", "")];
    return f ? { region: "Born of civil war", arms: f.arms, character: f.character } : null;
  };
  // As written (the Lore from the menu): the cast as every chronicle begins,
  // read from the baseline realm, never the reign being played.
  const written = url.searchParams.get("as") === "written";
  let cast = null;
  if (written) {
    cast = [];
    const dir = path.join(chron.BASELINE, "characters");
    try { for (const f of fs.readdirSync(dir)) if (f.endsWith(".json")) cast.push(rewrites.apply(JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")))); } catch { /* none */ }
    cast = cast.filter((c) => c.alive !== false);
  }
  let baseCities = [];
  if (written) try { baseCities = JSON.parse(fs.readFileSync(path.join(chron.BASELINE, "state", "world.json"), "utf8")).cities ?? []; } catch { /* none */ }
  const seatName = (id) => {
    if (!written) return cityName(id);
    const c = baseCities.find((x) => x.id === Number(id));
    return c ? nameIn(c.id, c.name) : null;
  };
  const houses = (ctx.world?.players ?? []).filter((p) => p.alive !== false && !houseFor(p).wild).map((p) => {
    const h = houseFor(p);
    const seat = ctx.world.cities.find((c) => c.owner === p.id && c.capital);
    const people = (written ? cast.filter((c) => c.house === h.name) : ctx.court.alive().filter((c) => c.playerId === p.id)).filter((c) => c.rank in RANK)
      .sort((a, c) => RANK[a.rank] - RANK[c.rank] || (c.created ? 1 : 0) - (a.created ? 1 : 0) || c.age - a.age);
    // The lord, the lord's spouse and heir, then the leading bannermen.
    const lord = people.find((c) => c.rank === "lord");
    const family = lord ? people.filter((c) => c.id === lord.spouse || (c.rank === "heir" && c.parents?.includes(lord.id))) : [];
    const notables = [...(lord ? [lord] : []), ...family, ...people.filter((c) => c.rank === "bannerman").slice(0, 4)];
    return {
      id: p.id, name: h.name, key: h.name, words: h.words, color: h.color, sigil: h.sigil, crown: !!h.crown,
      seat: seat ? cityName(seat.id) : null, towns: ctx.world.cities.filter((c) => c.owner === p.id).length,
      favour: h.crown ? null : favourOf(p.id), lore: b.houses[h.name] ?? rebel(h.name),
      notables: notables.map((c) => ({
        id: c.id, name: c.name, key: c.name, surname: c.surname ?? null, gender: c.gender, age: c.age, rank: c.rank, traits: c.traits,
        goal: c.goals?.[0]?.text ?? null, role: c.role ? ROLES[c.role]?.title : null,
        seat: c.seat != null ? seatName(c.seat) : null, loyalty: c.loyalty, written,
        memories: [...new Set(c.memories ?? [])].slice(-6), backstory: c.backstory ?? null,
        // In their own words: their latest memory told as theirs, never a
        // story's beat about other people that they heard.
        story: c.backstory ?? [...new Set(c.memories ?? [])].filter((m) => /\b(I|my|me)\b/.test(m) && !/^[^:]{3,60}: /.test(m)).slice(-1)[0] ?? null,
      })),
    };
  }).sort((a, c) => (c.crown ? 1 : 0) - (a.crown ? 1 : 0) || (c.lore ? 1 : 0) - (a.lore ? 1 : 0));
  // A great house that has lost every town is not forgotten: it stays in the
  // book, marked fallen, so the realm's seven are always seven.
  let n = 0;
  for (const h of Object.values(HOUSES)) {
    if (h.wild || h.crown || houses.some((x) => x.name === h.name)) continue;
    houses.push({ id: -100 - n++, name: h.name, key: h.name, words: h.words, color: h.color, sigil: h.sigil, crown: false, fallen: true,
      seat: null, towns: 0, favour: null, lore: b.houses[h.name] ?? null, notables: [] });
  }
  // The lesser families sworn to the great houses: one entry each, with
  // every town a branch of it holds, under which liege, and who heads it.
  const lesser = {};
  // As written, the branches as every chronicle begins (the baseline cast and towns).
  const held = (c) => c.seat != null && (written ? baseCities : ctx.world?.cities ?? []).some((t) => t.id === Number(c.seat) && t.owner === c.playerId);
  for (const c of (written ? cast : ctx.court.alive()).filter((x) => x.rank === "bannerman" && FAMILIES[x.surname])) {
    const p = ctx.world?.players.find((x) => x.id === c.playerId);
    if (!p || p.alive === false) continue;
    const h = houseFor(p);
    const f = (lesser[c.surname] ??= { surname: c.surname, ...FAMILIES[c.surname], branches: [] });
    f.branches.push({
      house: h.name, house_id: p.id, color: h.color, sigil: h.sigil, crown: !!h.crown,
      // A seat lost to another house (or razed) is told as lost, not held.
      seat: held(c) ? seatName(c.seat) : null, lost: c.seat != null && !held(c) ? seatName(c.seat) : null,
      head: { id: c.id, name: c.name, gender: c.gender, age: c.age, loyalty: c.loyalty, traits: c.traits, role: c.role ? ROLES[c.role]?.title : null },
    });
  }
  const families = Object.values(lesser).sort((a, c) => c.branches.length - a.branches.length || a.surname.localeCompare(c.surname));
  return json(res, 200, { intro: b.intro, crown: b.crown, faults: b.faults, fate: b.fate, tone: b.tone, houses, lesser: LESSER, families });
}

export async function season(ctx, req, res, url) {
  const { runSeason } = ctx;
  await runSeason();
  return json(res, 200, { ok: true });
}
