// A rival King beyond the realm (casebook, the reign's pressure from outside; CK3's neighbours, Total War's border
// probes). One owner, meta.rival {realm, king, edge, hostility 0..100, probes}: dealt once from the reign's seed
// (data/rivals.json). Each season (season.js) his hostility drifts toward its rest, and he may probe the border: his
// riders raid the realm's town nearest his edge (Freeciv's raiders, script.lua realm_raid). When he is cold enough
// his envoy comes to court with a demand (court.arcPetition, arc "rival"; the King's answer comes back through
// ruled): tribute, then the border town; a claim refused is war, fought by his own host (a Freeciv player of his
// own, script.lua realm_rival) until the town is his, peace is bought, or the war wears out. His lesser envoys come
// as event cards drawn with the realm's (events.js: rivals.json cards, when.rival, the effect rival). /world `rival`.
import fs from "node:fs";
import path from "node:path";
import * as Lua from "./lua.js";
import { cityName, houseFor, FOREIGN } from "./narrator.js";

const STEP = { north: [0, -1], south: [0, 1], west: [-1, 0], east: [1, 0] };
export const RIVAL = JSON.parse(fs.readFileSync(new URL("./data/rivals.json", import.meta.url), "utf8"));
const R = RIVAL;
const ARMS = (realm) => R.arms[realm] ?? { colour: "#4a4a6a", sigil: "banner" };
const known = (realm) => FOREIGN.set(realm, ARMS(realm));

export function of(meta) {
  if (meta.rival) { known(meta.rival.realm); return meta.rival; }
  const s = Number(meta.seed ?? 1066) >>> 0;
  const [realm, king] = R.kings[s % R.kings.length];
  known(realm);
  return (meta.rival = { realm, king, edge: R.edges[(s >>> 3) % R.edges.length], hostility: R.start, probes: 0 });
}

// Whether a card's when.rival holds: his hostility above / below.
export function holds(meta, w) {
  const h = of(meta).hostility;
  return (w.above == null || h > w.above) && (w.below == null || h < w.below);
}

// A choice moves him (events.js apply: effects rival).
export function shift(meta, d) {
  const r = of(meta);
  r.hostility = Math.max(0, Math.min(100, r.hostility + Number(d)));
}

// The words a card may use: {foreign}, {foreignking}.
export const words = (meta) => ({ foreign: of(meta).realm, foreignking: of(meta).king });

// The realm's town nearest his edge (the border he probes, and claims): none of his own.
function border(world, edge, realm) {
  const his = new Set((world.players ?? []).filter((p) => p.name === realm).map((p) => p.id));
  const towns = (world.cities ?? []).filter((c) => !his.has(c.owner));
  const key = { north: (c) => c.y, south: (c) => -c.y, west: (c) => c.x, east: (c) => -c.x }[edge];
  return [...towns].sort((a, b) => key(a) - key(b))[0] ?? null;
}

// Where his road into the realm starts (data/rivals.json gate): the town nearest his edge, stepped gate.out tiles
// toward it, inside the map (the reign's map.json size).
function gate(ctx, r) {
  const t = border(ctx.world, r.edge, r.realm);
  if (!t) return r.gate ?? null;
  let size = null;
  try { size = JSON.parse(fs.readFileSync(path.join(ctx.P.state, "map.json"), "utf8")); } catch { /* no map yet */ }
  const [dx, dy] = STEP[r.edge] ?? [0, -1];
  const w = size?.width ?? t.x + 1, h = size?.height ?? t.y + 1;
  return { x: Math.max(0, Math.min(w - 1, t.x + dx * R.gate.out)), y: Math.max(0, Math.min(h - 1, t.y + dy * R.gate.out)) };
}

// His raiders, told by Freeciv when his raid rises (server.js raid_raised, by "rival"): they wear his colours.
export function raised(meta, ev) {
  if (ev.by !== "rival") return;
  of(meta).raiders = String(ev.units ?? "").split(",").filter(Boolean).map(Number);
}

// The season: hostility drifts, and he may probe the border with a raid.
export function season(ctx, turn) {
  const { meta, world, send, record } = ctx;
  if (!world?.cities?.length) return;
  const r = of(meta);
  r.gate = gate(ctx, r);
  if (r.war) return war(ctx, r, turn);
  // A treaty holds: no envoys with demands, no riders over the border, until it runs out.
  if (r.treaty && turn < r.treaty.until) return;
  if (r.treaty) { ctx.record({ turn, kind: "court", text: `The peace with ${r.realm} has run its years. ${r.king}'s riders are seen on the border hills again.` }); r.treaty = null; }
  r.hostility += Math.sign(R.rest - r.hostility) * Math.min(R.drift, Math.abs(R.rest - r.hostility));
  if (r.hostility >= R.war.above) return declare(ctx, r, border(world, r.edge, r.realm), turn, `${r.king} has waited long enough.`);
  demand(ctx, r, turn);
  if (Math.random() >= R.raid * r.hostility / 100) return;
  const t = border(world, r.edge, r.realm);
  if (!t) return;
  send(`lua cmd ${Lua.raid(t.id, "rival")}`);
  r.probes++;
  record({ turn, kind: "raid", text: `Riders out of ${r.realm} cross the border and fall on the fields of ${cityName(t.id)}. ${r.king} says they are outlaws; nobody believes it.`, city: t.id });
}

// --- his envoy at court (data/rivals.json demand) ---------------------------------------------------------------

const D = R.demand;

// The great houses, for favour that moves with the crown's pride: every house of the realm that holds a town.
function great(world) {
  return (world?.players ?? []).filter((p) => !houseFor(p).wild && !houseFor(p).crown && (world.cities ?? []).some((c) => c.owner === p.id));
}
const all = (world, d) => Object.fromEntries(great(world).map((p) => [p.id, d]));
const signed = (d) => `${d > 0 ? "+" : "−"}${Math.abs(d)}`;

// The envoy comes when he is cold enough and has not come lately: at war, offering peace; past land, claiming the
// border town; else asking tribute. One open demand at a time (meta.rival.demand).
function demand(ctx, r, turn) {
  const { world, court } = ctx;
  if ((r.demand && !r.demand.answered) || !court?.arcPetition) return;
  const since = turn - (r.demand?.turn ?? -99);
  if (r.war ? since < R.war.every : (r.hostility < D.above || since < D.every)) return;
  const t = r.war ? (world.cities ?? []).find((c) => c.id === r.war.town) : border(world, r.edge, r.realm);
  if (!t) return;
  const kind = r.war ? "peace" : r.hostility >= D.land ? "land" : "tribute";
  const gold = kind === "peace" ? D.peaceGold : Math.round(D.gold + D.goldPer * Math.max(0, r.hostility - D.above));
  const beat = `rival-${turn}-${kind}`;
  const town = cityName(t.id);
  const holder = (world.players ?? []).find((p) => p.id === t.owner);
  const lordly = holder && !houseFor(holder).crown && !houseFor(holder).wild;
  const cedeFavour = { ...all(world, D.favour.yield), ...(lordly ? { [holder.id]: D.cede } : {}) };
  const cedeHint = `${r.king} ${signed(D.yield)}${lordly ? ` · ${houseFor(holder).name} ${signed(D.cede)}` : ""} · every great house ${signed(D.favour.yield)}`;
  const refuse = { id: "refuse", label: kind === "peace" ? "Fight on" : "Refuse him", favour: all(world, D.favour.refuse),
    hint: kind === "tribute" ? `${r.king} ${signed(D.refuse)} · every great house ${signed(D.favour.refuse)}` : kind === "land" ? `war with ${r.realm} over ${town} · every great house ${signed(D.favour.refuse)}` : `the war goes on · every great house ${signed(D.favour.refuse)}`,
    result: kind === "peace" ? `The King sends the envoy home with no answer but the war. ${town} holds.` : kind === "land" ? `The King will not give up ${town}. The envoy says nothing, bows, and rides for the border to tell his master.` : `The King sends ${r.realm}'s envoy home with nothing. The lords like it.` };
  const insult = { id: "insult", label: "Send him home shaved", favour: all(world, D.favour.insult), hint: `${r.king} ${signed(D.insult)}${kind === "land" ? `, and war over ${town}` : ""} · every great house ${signed(D.favour.insult)}`,
    result: `The envoy goes home without his beard. ${r.king} will not forget it, and the lords laugh about it for a year.` };
  const options = kind === "tribute" ? [
    { id: "pay", label: `Pay ${gold} gold`, cost: gold, favour: all(world, D.favour.yield), hint: `${r.king} ${signed(D.pay)} · every great house ${signed(D.favour.yield)}`, result: `The gold goes over the border with the envoy. At court the lords look at their boots.` },
    refuse, insult,
  ] : kind === "land" ? [
    { id: "cede", label: `Give him ${town}`, favour: cedeFavour, hint: cedeHint, result: `${town} is ${r.realm}'s by the King's word. Its folk wake under another crown.` },
    { id: "pay", label: `Buy him off: ${gold * 2} gold`, cost: gold * 2, favour: all(world, D.favour.yield), hint: `${r.king} ${signed(D.pay)} · every great house ${signed(D.favour.yield)}`, result: `${r.king} takes the gold and lets the claim to ${town} sleep. For now.` },
    refuse, insult,
  ] : [
    { id: "cede", label: `Peace for ${town}`, favour: cedeFavour, hint: `the war ends · ${cedeHint}`, result: `Peace, and ${town} goes to ${r.realm}. The bells ring, and nobody in ${town} rings them.` },
    { id: "pay", label: `Peace for ${gold} gold`, cost: gold, favour: all(world, D.favour.yield), hint: `the war ends · every great house ${signed(D.favour.yield)}`, result: `${r.king} takes the gold and his host goes home. ${town} keeps its own crown.` },
    refuse,
  ];
  const text = kind === "tribute"
    ? `${r.king}'s envoy bows no lower than he must. "My master asks a gift of friendship from the crown, Your Grace. ${gold} in gold, and his riders stay home."`
    : kind === "land"
      ? `${r.king}'s envoy unrolls an old map on the floor of the hall. "${town} was ${r.realm}'s before your grandfather's grandfather, Your Grace. My master asks for it back. He would rather not come for it."`
      : `${r.king}'s envoy comes under a white flag. "My master is tired of this war, Your Grace, if you are. ${town}, or ${gold} in gold, and his men go home."`;
  court.arcPetition({ arc: "rival", beat, thread: kind === "peace" ? `terms from ${r.realm}` : `an envoy from ${r.realm}`, from: { id: null, name: `${r.king}'s envoy`, house: r.realm }, text, options }, world);
  r.demand = { beat, kind, town: t.id, turn };
}

// The King's answer to the envoy (server.js court.onArcRuling, arc "rival"); ignored is taken as refused.
export function ruled(ctx, beat, option) {
  const { meta, world, send, record } = ctx;
  const r = of(meta);
  const d = r.demand;
  if (!d || d.beat !== beat || d.answered) return;
  d.answered = option;
  const turn = world?.turn ?? 0;
  const t = (world?.cities ?? []).find((c) => c.id === d.town);
  if (option === "pay") {
    shift(meta, D.pay);
    if (d.kind === "peace") return peace(ctx, r, turn, `${r.king} takes the crown's gold, and the war is over.`, "bought");
  } else if (option === "cede") {
    shift(meta, D.yield);
    if (t) send(`lua cmd ${Lua.rivalCede(r.realm, t.id)}`);
    record({ turn, kind: "battle", text: `By the King's word ${cityName(d.town)} passes to ${r.realm}. ${r.king}'s banner goes up over its gate.`, city: d.town });
    if (d.kind === "peace") return peace(ctx, r, turn, null, "ceded");
  } else if (option === "insult" || option === "ignored") {
    shift(meta, option === "insult" ? D.insult : D.refuse);
    if (option === "ignored") record({ turn, kind: "court", text: `${r.king}'s envoy waits a season for the King's answer and goes home without one.` });
    if (d.kind === "land") return declare(ctx, r, t, turn, `${r.king}'s envoy came home ${option === "insult" ? "shaved" : "unheard"}.`);
  } else if (option === "refuse") {
    if (d.kind === "tribute") shift(meta, D.refuse);
    if (d.kind === "land") return declare(ctx, r, t, turn, `The King would not give up ${cityName(d.town)}.`);
  }
}

// --- his war over the border town (data/rivals.json war) ---------------------------------------------------------

function host(ctx, r, t) {
  const W = R.war;
  const [dx, dy] = STEP[r.edge] ?? [0, -1];
  ctx.send(`lua cmd ${Lua.rivalHost(r.realm, t.id, dx, dy, W.out, W.kinds, Math.round(W.host + W.hostPer * r.hostility))}`);
}

function declare(ctx, r, t, turn, why) {
  if (!t || r.war) return;
  r.war = { town: t.id, since: turn, until: turn + R.war.seasons, waves: 1 };
  r.hostility = Math.max(r.hostility, R.war.above);
  host(ctx, r, t);
  ctx.record({ turn, kind: "battle", text: `${why} ${r.realm} declares war on the crown and claims ${cityName(t.id)}. ${r.king}'s host crosses the border.`, city: t.id });
}

// A season of his war: the town his, or the war worn out, ends it; else another wave every war.every seasons, and
// the envoy may come with terms.
function war(ctx, r, turn) {
  const { world } = ctx;
  const w = r.war;
  const t = (world.cities ?? []).find((c) => c.id === w.town);
  const his = !t || (world.players ?? []).find((p) => p.id === t.owner)?.name === r.realm;
  if (his) return peace(ctx, r, turn, `${cityName(w.town)} has fallen to ${r.realm}. ${r.king} has what he came for, and his host goes home.`, "lost");
  // Worn out before the walls: he sues for peace and pays for it (war.reparations to the crown).
  if (turn >= w.until) {
    const crown = ctx.crownOf?.();
    if (crown) ctx.send(`lua cmd ${Lua.gold(crown.id, R.war.reparations)}`);
    return peace(ctx, r, turn, `${r.realm}'s war wears itself out before the walls of ${cityName(w.town)}. ${r.king} sues for peace and sends ${R.war.reparations} in gold to have it.`, "won");
  }
  if ((turn - w.since) % R.war.every === 0) { w.waves++; host(ctx, r, t); }
  demand(ctx, r, turn);
}

// The war over, by how (won: he sued for peace; lost: the town fell; bought; ceded): his men go home, and a treaty
// keeps the border quiet for war.treaty seasons (no demands, no raids), sealed in the chronicle.
function peace(ctx, r, turn, why, how) {
  ctx.send(`lua cmd ${Lua.rivalHome(r.realm)}`);
  if (why) ctx.record({ turn, kind: "battle", text: why, city: r.war?.town });
  ctx.record({ turn, kind: "court", text: `A treaty is sealed with ${r.realm}: ${R.war.treaty / 4} years of peace on the border, sworn on both crowns.` });
  r.treaty = { since: turn, until: turn + R.war.treaty, how, town: r.war?.town ?? null };
  r.war = null;
  r.demand = r.demand && !r.demand.answered ? { ...r.demand, answered: "peace" } : r.demand;
  r.hostility = Math.min(r.hostility, R.war.peace);
}

export function view(meta, world) {
  const r = meta?.rival;
  if (!r) return null;
  known(r.realm);  // his men are his, from the first /world after a restart
  const alive = new Set((world?.units ?? []).map((u) => u.id));
  const a = ARMS(r.realm);
  const d = r.demand && !r.demand.answered ? { kind: r.demand.kind, town: r.demand.town } : null;
  return { realm: r.realm, king: r.king, edge: r.edge, hostility: Math.round(r.hostility), probes: r.probes, demand: d,
    colour: a.colour, sigil: a.sigil, gate: r.gate ?? null, raiders: (r.raiders ?? []).filter((id) => alive.has(id)),
    player: (world?.players ?? []).find((p) => p.name === r.realm)?.id ?? null,
    war: r.war ? { town: r.war.town, since: r.war.since, until: r.war.until, waves: r.war.waves } : null,
    treaty: r.treaty ? { since: r.treaty.since, until: r.treaty.until, how: r.treaty.how, town: r.treaty.town } : null };
}
