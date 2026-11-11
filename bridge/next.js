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

// When the season now running began (season.js turn), for the countdown.
let seasonAt = Date.now();
export function seasonBegan() { seasonAt = Date.now(); }

const SOON = 2;  // seasons: a threat this close comes before anything else

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
  // How many things are worth a seal now: the choice is real only when there's more than one (reign_measure.py).
  const options = threats.length + (hungry ? 1 : 0) + (aim?.do ? 1 : 0);
  // The order each candidate needs, so the line's pick and the others can be told apart (the measuring King uses alts).
  const seat = world.cities.find((c) => c.owner === crown?.id && c.capital);
  const aimTown = aim?.at != null ? town(aim.at) : null;
  const aimAct = !aim?.do ? null : aim.key === "host" ? { action: "levy", city: seat?.id ?? null }
    : ["granary", "walls"].includes(aim.key) ? { action: "build", city: seat?.id ?? null, building: aim.key === "granary" ? "Granary" : "City Walls" }
    : aim.key === "market" ? { action: "build", city: aimTown?.id ?? null, building: "Marketplace" }
    : aim.building ? { action: "build", city: aimTown?.id ?? null, building: aim.building }
    : aimTown && (aim.key === "friend" || String(aim.key).startsWith("win-")) ? { action: "feast", city: aimTown.id } : null;
  const alts = [...threats.map((t) => t.act), hungry ? { action: "relief", city: hungry.id } : null, aimAct].filter((a) => a && a.city != null);
  const line = (x, tone) => ({ kind: x.kind, text: x.text, city: x.city ?? null, seconds: x.seasons != null ? secs(x.seasons) : null,
    count: x.count ?? null, frac: Math.max(0, Math.min(1, x.frac ?? 0)), tone, options, act: x.act ?? null, alts });
  // With the royal seal on and none in hand, nothing is his until the season brings one: the court's next sitting.
  const sealed = Seals.on(meta) && (meta.seals?.n ?? 1) < 1;
  if (!sealed && threats[0] && threats[0].seasons <= SOON) return line(threats[0], threats[0].seasons <= 1 ? "loss" : "act");
  if (!sealed && hungry) return line({ kind: "own", text: `${hungry.famine ? "Starving" : "Granary low"}. Send grain to ${cityName(hungry.id)}`, city: hungry.id, seasons: 1, act: { action: "relief", city: hungry.id },
    frac: 1 - Math.min(1, (hungry.food ?? 0) / Math.max(1, hungry.granary ?? 1)) }, hungry.famine ? "loss" : "act");
  if (!sealed && threats[0]) return line(threats[0], "act");
  // The next step of his aim: its verb, at its place.
  if (!sealed && aim?.do) {
    const at = aim.at != null ? town(aim.at) : null;
    const who = aim.key === "friend" && at ? houseFor(world.players.find((p) => p.id === at.owner) ?? {}).name : null;
    const text = who ? `${aim.do} ${who} at ${cityName(at.id)}` : at ? `${aim.do} at ${cityName(at.id)}` : aim.do;
    return line({ kind: "ladder", text, city: at?.id ?? null, count: aim.progress?.text ?? null, frac: aim.progress?.frac ?? 0, act: aimAct }, "act");
  }
  // Nothing of his: the court's next sitting.
  const c = meta.court ?? {};
  if (c.sitting != null) return null;  // it's sitting now: the board is up
  const every = courtEvery(meta);
  const seasons = c.lastSat == null ? 1 : Math.max(1, c.lastSat + every - (world.turn ?? 0));
  const waiting = (ctx.court?.petitions ?? []).filter((p) => !p.answered && p.called == null).length;
  return line({ kind: "court", text: waiting ? `The court sits. ${waiting} waiting` : "The court sits", seasons, frac: 1 - seasons / Math.max(1, every) }, "quiet");
}
