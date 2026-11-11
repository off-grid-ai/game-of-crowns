// The next thing: a goal a minute away (Civ's "3 turns" on every build,
// Frostpunk's next-law timer, Into the Breach's "what lands next turn"). The
// one decider of what the King can do soonest, with its place and its clock;
// the view only shows it, one line under the aim (top_bar.gd). A goal is
// something he can do: when the soonest loop is his, the line ends in the verb
// and the place ("Answer at Redmarch"); when nothing is his, the court's next
// sitting. Kinds, in order: threat (something about to land that he can still
// answer), own (a royal town in need), ladder (the next step of his aim), court.

import { houseFor, cityName } from "./narrator.js";
import * as Director from "./director.js";
import { courtEvery } from "./court.js";
import * as Seals from "./seals.js";
import { buildKey } from "./crown.js";

// When the season now running began (season.js turn), for the countdown.
let seasonAt = Date.now();
export function seasonBegan() { seasonAt = Date.now(); }
// Seconds left of the season now running (an event card lapses at its end).
export const secondsToSeasonEnd = (turnSeconds) => Math.max(0, Math.round(turnSeconds - (Date.now() - seasonAt) / 1000));

import fs from "node:fs";
// seasons: a threat this close comes before anything else (data/next.json; docs/TUNING.md)
const NEXT = JSON.parse(fs.readFileSync(new URL("./data/next.json", import.meta.url), "utf8"));
const SOON = NEXT.soon ?? 2;

// ctx: meta, world, court, turnSeconds, paused, crownOf. aim: the ladder's aim
// with its place (city id) and progress (reign.js reignInfo).
export function nextThing(ctx, aim) {
  const { meta, world, turnSeconds } = ctx;
  if (!world || meta?.status !== "running") return null;
  const crown = ctx.crownOf?.();
  // Seconds left of the season now running; paused (the court sitting, an act's end), the clock holds.
  const inSeason = Math.max(0, turnSeconds - (Date.now() - seasonAt) / 1000);
  const secs = (seasons) => Math.round(inSeason + Math.max(0, seasons - 1) * turnSeconds);
  const town = (id) => world.cities.find((c) => c.id === id);
  const threats = [];
  // The director's threat: answered at its place.
  const d = Director.due(meta);
  const answers = Director.matter(meta)?.acts ?? [];
  if (d && town(d.city)) threats.push({ kind: "threat", text: `${d.short}. Answer at ${d.town}`, city: d.city, seasons: d.seasons, frac: d.level,
    act: answers[0] ? { action: answers[0].action, city: answers[0].city ?? world.cities.find((c) => c.owner === crown?.id && c.capital)?.id ?? null } : null });  // one given "anywhere" is given at Kingsmere
  // A house whose banners gather after a refused ultimatum: won back at its seat before it marches.
  for (const [pid, t] of Object.entries(meta.turning ?? {})) {
    if (t.riseAt == null) continue;
    const p = world.players.find((x) => x.id === Number(pid));
    const seat = world.cities.find((c) => c.owner === Number(pid) && c.capital) ?? world.cities.find((c) => c.owner === Number(pid));
    if (!p || !seat) continue;
    const seasons = Math.max(1, t.riseAt - (world.turn ?? 0));
    threats.push({ kind: "threat", text: `${houseFor(p).name}'s banners. Win them back at ${cityName(seat.id)}`, city: seat.id, seasons, frac: 1 - seasons / 3, act: { action: "gift", city: seat.id } });
  }
  threats.sort((a, b) => a.seasons - b.seasons);
  // A royal town going hungry: grain from the royal stores, sent to it (its card offers it; the seat feeds itself).
  const hungry = world.cities.filter((c) => c.owner === crown?.id && !c.capital && (c.famine || c.granaryLow)).sort((a, b) => (a.food ?? 0) / Math.max(1, a.granary ?? 1) - (b.food ?? 0) / Math.max(1, b.granary ?? 1))[0];
  // The order each candidate needs.
  const seat = world.cities.find((c) => c.owner === crown?.id && c.capital);
  const aimTown = aim?.at != null ? town(aim.at) : null;
  const aimAct = !aim?.do ? null : aim.key === "host" ? { action: "levy", city: seat?.id ?? null }
    : ["granary", "walls"].includes(aim.key) ? { action: "build", city: seat?.id ?? null, building: aim.key }
    : aim.key === "market" ? { action: "build", city: aimTown?.id ?? null, building: "market" }
    : aim.building ? { action: "build", city: aimTown?.id ?? null, building: buildKey(aim.building) }
    : aimTown && (aim.key === "friend" || String(aim.key).startsWith("win-")) ? { action: "feast", city: aimTown.id } : null;
  const ladder = !aim?.do ? null : (() => {
    const who = aim.key === "friend" && aimTown ? houseFor(world.players.find((p) => p.id === aimTown.owner) ?? {}).name : null;
    const text = who ? `${aim.do} ${who} at ${cityName(aimTown.id)}` : aimTown ? `${aim.do} at ${cityName(aimTown.id)}` : aim.do;
    return { kind: "ladder", text, city: aimTown?.id ?? null, count: aim.progress?.text ?? null, frac: aim.progress?.frac ?? 0, act: aimAct };
  })();
  const feed = hungry ? { kind: "own", text: `${hungry.famine ? "Starving" : "Granary low"}. Send grain to ${cityName(hungry.id)}`, city: hungry.id, seasons: 1,
    act: { action: "relief", city: hungry.id }, frac: 1 - Math.min(1, (hungry.food ?? 0) / Math.max(1, hungry.granary ?? 1)) } : null;
  // What the Hand's counsel finds worth doing in the realm (counsel.js decides it; not a crisis, which
  // goes to court): each matter's first order the realm would take, as one more use for a seal.
  const counsel = (ctx.counselNow ?? []).filter((o) => o.urgency < 75 && o.acts?.length).map((o) => {
    const a = o.acts.find((x) => !x.ui && x.action);
    const city = a?.city ?? seat?.id ?? null;
    return a && city != null ? { kind: "counsel", text: `${o.text}. ${String(a.label).split("  ")[0]} at ${cityName(city)}`, city, act: { action: a.action, city, ...(a.to != null ? { to: a.to } : {}), ...(a.building ? { building: a.building } : {}) } } : null;
  }).filter(Boolean);
  // The wider pool (data/next.json pool): what the realm's state makes worth a seal beyond the above.
  const great = world.players.filter((p) => !houseFor(p).wild && !houseFor(p).crown && world.cities.some((c) => c.owner === p.id));
  const pool = [];
  for (const p of great.filter((h) => (ctx.favourOf?.(h.id) ?? 50) < NEXT.pool.coldBelow)) {
    const s = world.cities.find((c) => c.owner === p.id && c.capital);
    if (s) pool.push({ kind: "house", text: `${houseFor(p).name} grows cold. Feast them at ${cityName(s.id)}`, city: s.id, act: { action: "feast", city: s.id } });
  }
  const th = meta.director?.threat;
  if (th && ["host", "pretender"].includes(th.kind)) {
    const near = world.cities.filter((c) => c.owner === crown?.id && !(c.buildings ?? []).includes("City Walls") && Math.hypot(c.x - th.x, c.y - th.y) <= NEXT.pool.wallsWithin)
      .sort((a, b) => Math.hypot(a.x - th.x, a.y - th.y) - Math.hypot(b.x - th.x, b.y - th.y))[0];
    if (near) pool.push({ kind: "walls", text: `${th.houseName} gathers. Wall ${cityName(near.id)}`, city: near.id, act: { action: "build", city: near.id, building: "walls" } });
    if (seat) pool.push({ kind: "levy", text: `${th.houseName} gathers. Raise the levy at ${cityName(seat.id)}`, city: seat.id, act: { action: "levy", city: seat.id } });
  }
  // Standing uses (data/next.json standing): always on offer after the rest, so each voice has one in a quiet
  // season and a thin purse; the price filter below keeps only what the treasury can pay.
  const coldest = great.map((p) => [p, ctx.favourOf?.(p.id) ?? 50]).sort((a, b) => a[1] - b[1])[0]?.[0];
  const coldSeat = coldest ? world.cities.find((c) => c.owner === coldest.id && c.capital) : null;
  const theirs = world.cities.filter((c) => great.some((p) => p.id === c.owner));
  const exposed = world.cities.filter((c) => c.owner === crown?.id && !(c.buildings ?? []).includes("City Walls"))
    .map((c) => [c, Math.min(...theirs.map((t) => Math.hypot(c.x - t.x, c.y - t.y)))]).sort((a, b) => a[1] - b[1])[0]?.[0];
  for (const s of NEXT.standing ?? []) {
    const at = s.at === "coldest" ? coldSeat : s.at === "exposed" ? exposed : seat;
    if (!at) continue;
    const text = s.text.replace("{house}", coldest ? houseFor(coldest).name : "").replace("{town}", cityName(at.id));
    pool.push({ kind: "standing", text, city: at.id, act: { action: s.action, city: at.id, ...(s.building ? { building: s.building } : {}) } });
  }
  // In order: a threat about to land, a royal town going hungry, a threat further off, the aim's next step, the Hand's counsel, the wider pool.
  // A goal is something he can do now: only what the realm would let him order (the decree's own once-a-year
  // and price rules, canDecree) is offered; the rest wait for the season they can be given in.
  const order = [...threats.filter((t) => t.seasons <= SOON).map((t) => [t, t.seasons <= 1 ? "loss" : "act"]),
    ...(feed ? [[feed, hungry.famine ? "loss" : "act"]] : []), ...threats.filter((t) => t.seasons > SOON).map((t) => [t, "act"]), ...(ladder ? [[ladder, "act"]] : []),
    ...counsel.map((c) => [c, "act"]), ...pool.map((c) => [c, "act"])];
  // Scarcity, measured (PLAN.md, the seals row): of the three most urgent uses the yearly rules allow, how many
  // the treasury covers now. The economy aims at two of three: just short, never empty (Frostpunk, Against the Storm).
  const wanted = [], wseen = new Set();
  for (const [x] of order) {
    const k = x.act ? `${x.act.action}:${x.act.city}:${x.act.building ?? ""}` : "";
    if (!x.act || x.act.city == null || wseen.has(k) || (ctx.canDecree && !ctx.canDecree(x.act, Infinity))) continue;
    wseen.add(k); wanted.push(x.act);
    if (wanted.length === 3) break;
  }
  const reach = { of: wanted.length, can: ctx.canDecree ? wanted.filter((a) => ctx.canDecree(a)).length : wanted.length };
  const seen = new Set();
  const doable = order.filter(([x]) => {
    const k = x.act ? `${x.act.action}:${x.act.city}:${x.act.building ?? ""}` : "";
    if (!x.act || x.act.city == null || seen.has(k) || (ctx.canDecree && !ctx.canDecree(x.act))) return false;
    seen.add(k);
    return true;
  });
  // How many things are worth a seal now (an event card waiting competes for him too): the choice is real
  // only when there's more than one (reign_measure.py).
  const options = doable.length + (meta.events?.up ? 1 : 0);
  const alts = doable.map(([x]) => x.act);
  // Two voices, each with his own leaning (KoDP's council, CK3's councillors): each names the most urgent
  // use he favours; neither is marked best. The Hand's is 'act' (what an always-the-Hand King takes).
  const [V1, V2] = NEXT.voices;
  const favours = (v, x) => v.likes.includes(x.act.action);
  const first = doable.find(([x]) => favours(V1, x)) ?? doable[0];
  const second = doable.find(([x]) => x !== first?.[0] && favours(V2, x)) ?? doable.find(([x]) => x !== first?.[0]);
  const line = (x, tone, extra = {}) => ({ kind: x.kind, text: x.text, city: x.city ?? null, seconds: x.seasons != null ? secs(x.seasons) : null,
    count: x.count ?? null, frac: Math.max(0, Math.min(1, x.frac ?? 0)), tone, options, reach, act: x.act ?? null, alts, ...extra });
  // With the royal seal on and none in hand, nothing is his until the season brings one: the court's next sitting.
  const sealed = Seals.on(meta) && (meta.seals?.n ?? 1) < 1;
  // One prompt (data/next.json oneVoice): the most urgent use, whoever would favour it.
  if (!sealed && NEXT.oneVoice && doable.length) return line(doable[0][0], doable[0][1]);
  if (!sealed && first && second) {
    const [a, b] = [first[0], second[0]];
    const soonest = [a, b].filter((x) => x.seasons != null).sort((x, y) => x.seasons - y.seasons)[0];
    return line({ kind: "choice", text: `${V1.name}: ${a.text}  ·  ${V2.name}: ${b.text}`, city: a.city, seasons: soonest?.seasons, act: a.act }, [first[1], second[1]].includes("loss") ? "loss" : "act",
      { voices: [{ who: V1.name, text: a.text, act: a.act, city: a.city }, { who: V2.name, text: b.text, act: b.act, city: b.city }] });
  }
  if (!sealed && first) return line(first[0], first[1]);
  // Nothing of his: the court's next sitting.
  const c = meta.court ?? {};
  if (c.sitting != null) return null;  // it's sitting now: the board is up
  const every = courtEvery(meta);
  const seasons = c.lastSat == null ? 1 : Math.max(1, c.lastSat + every - (world.turn ?? 0));
  const waiting = (ctx.court?.petitions ?? []).filter((p) => !p.answered && p.called == null).length;
  return line({ kind: "court", text: waiting ? `The court sits. ${waiting} waiting` : "The court sits", seasons, frac: 1 - seasons / Math.max(1, every) }, "quiet");
}
