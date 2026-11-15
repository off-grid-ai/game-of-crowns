// The King's war on a great house (Mac 2026-11-16: "a campaign to eliminate a house, that will attack the smaller
// houses and then try to topple the main house"; CK3's war goal and war score, Total War's campaign against a
// faction's settlements, its capital last). One owner, meta.war {house, seat, since, plan, target, ordered, fallen,
// passed, allies, asked, warned, struck, waits, atWarSeen}: declared by the King's decree (crown.js war), it plans the
// house's towns, its bannermen's outlying and weakest first and its seat last, and each season gives the King's
// hosts the next town through the hosts' own orders (hosts.js besiege; campaigns.js lays and storms the siege, and
// sworn houses send their men with it, campaigns.js startCampaign). Freeciv fights every blow and its AI, at war in
// Freeciv (the one diplomacy writer), fights back; the house's lord answers in kind (characters.js retaliate). It ends
// when the seat falls (the house toppled: its towns pass to the crown, the allies who marched ask their share through
// the spoils, characters.js) or at the peace table (peace.js ruled -> ended). /world war. Numbers: data/war.json.
// Nothing here reads server.js: the realm's state and helpers come in as one context (season.js, routes_decree.js).
import fs from "node:fs";
import { crownOf, greatHouses } from "./realm.js";
import { houseFor, cityName } from "./narrator.js";
import { CIVILIAN, sworn as swornOf } from "./campaigns.js";
import { BANDS } from "./favour.js";
import * as Hosts from "./hosts.js";
import * as Lua from "./lua.js";
import * as chron from "./chronicles.js";
import * as kingDeeds from "./ledger.js";

export const WAR = JSON.parse(fs.readFileSync(new URL("./data/war.json", import.meta.url), "utf8"));

const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
const short = (p) => houseFor(p ?? {}).name?.replace(/^House /, "") ?? "the house";
const soldiersAt = (world, pid, at) => (world.units ?? []).filter((u) => u.owner === pid && !CIVILIAN.has(u.type) && u.x === at.x && u.y === at.y).length;
const atWarInFreeciv = (ctx, a, b) => !!ctx.detail?.()?.players?.find((p) => p.slot === a)?.atWarWith?.includes(b);

// The war now, or null.
export const current = (meta) => meta?.war ?? null;

// The house's towns in the order the King's captains take them: its bannermen's first, the weakest held (fewest
// companies inside) and the farthest from its seat before the rest, its seat last. [city ids].
export function plan(world, house) {
  const towns = (world.cities ?? []).filter((c) => c.owner === house);
  const seat = towns.find((c) => c.capital) ?? null;
  const rest = towns.filter((c) => c !== seat)
    .sort((a, b) => soldiersAt(world, house, a) - soldiersAt(world, house, b) || (seat ? cheb(b, seat) - cheb(a, seat) : 0) || a.id - b.id);
  return [...rest, ...(seat ? [seat] : [])].map((c) => c.id);
}

// The King's chances against the whole house, as his captains put them (campaigns.js marchOdds, with his sworn houses
// and the allies of this war beside him): 0..1, or null for a house the King can't make war on.
export function odds(ctx, house) {
  const { world } = ctx;
  const foe = world?.players?.find((p) => p.id === house);
  if (!foe || houseFor(foe).crown || houseFor(foe).wild || !(world.cities ?? []).some((c) => c.owner === house)) return null;
  const allies = greatHouses(world).filter((p) => p.id !== house && swornOf(ctx, p.id)).map((p) => p.id);
  return ctx.marchOdds?.(house, allies, { turn: (world.turn ?? 0) + 2 }) ?? null;
}

// Whether a house would answer the King's envoy and join the war (data/war.json join): {chance 0..1, warns, why}. A
// house bound to the foe by a pact or a marriage, or whose lord likes the foe's lord (join.friendly), refuses and
// sends the foe word; one sworn to the crown comes all but surely; else its favour, and more if it is already at war
// with the foe. null when there is no war, or the house is the foe, the crown's or the wild's.
export function joinChance(ctx, pid) {
  const { world, meta, court } = ctx;
  const w = current(meta);
  const p = world?.players?.find((q) => q.id === pid);
  if (!w || !p || pid === w.house || houseFor(p).crown || houseFor(p).wild || !(world.cities ?? []).some((c) => c.owner === pid)) return null;
  if ((w.allies ?? []).includes(pid)) return null;
  const J = WAR.join;
  const foe = world.players.find((q) => q.id === w.house);
  const bound = court?.boundTo?.(pid)?.includes(w.house);
  const a = court?.lordOfHouse?.(pid), b = court?.lordOfHouse?.(w.house);
  const liking = a && b ? court.opinion(a.id, b.id) : 0;
  if (bound) return { chance: 0, warns: true, why: `bound to ${short(foe)}` };
  if (liking >= J.friendly) return { chance: 0, warns: true, why: `a friend of ${short(foe)}` };
  if (swornOf(ctx, pid)) return { chance: J.sworn, warns: false, why: "sworn to the crown" };
  const f = ctx.favourOf?.(pid) ?? 50;
  let chance = (f - J.floor) / J.span + (atWarInFreeciv(ctx, pid, w.house) ? J.atWar : 0) - Math.max(0, liking) * J.likingWeight;
  chance = Math.max(0, Math.min(J.most, chance));
  return { chance, warns: false, why: f >= BANDS.sworn ? "trusts the crown" : f >= BANDS.steady ? "is wary" : "is cold to the crown" };
}

// How long until the King may ask a house again (seasons), 0 when he may.
export function askWait(meta, pid, turn) {
  const at = current(meta)?.asked?.[pid];
  return at == null ? 0 : Math.max(0, at + WAR.join.again - turn);
}

// The King declares war (routes_decree.js, after crown.js war): the war is kept, Freeciv is told (both ways, its AI
// fights it), the house's lord answers (characters.js answerWar: its own allies called), and the first town is
// ordered this season.
export function declare(ctx, house) {
  const { world, meta, record } = ctx;
  const crown = crownOf(world);
  const foe = world?.players?.find((p) => p.id === house);
  if (!crown || !foe) return;
  const turn = world.turn ?? 0;
  const order = plan(world, house);
  const seat = (world.cities ?? []).find((c) => c.owner === house && c.capital)?.id ?? order.at(-1) ?? null;
  meta.war = { house, seat, since: turn, plan: order, target: null, ordered: null, fallen: [], passed: [], allies: [], asked: {}, warned: [], struck: null, waits: null, atWarSeen: false };
  if (!atWarInFreeciv(ctx, crown.id, house)) ctx.diplomacy?.([crown.id, house, 0, "War"]);
  const called = ctx.court?.answerWar?.(house, crown.id, world, turn) ?? [];
  const towns = order.length;
  record({ turn, kind: "battle", city: seat ?? undefined, attacker: crown.id, defender: house,
    text: `The King declares war on ${houseFor(foe).name}. ${towns} ${towns === 1 ? "town flies" : "towns fly"} its banner; the royal host takes them one by one${seat != null ? `, and ${cityName(seat)} last` : ""}.${called.length ? ` ${called.map((pid) => houseFor(world.players.find((p) => p.id === pid) ?? {}).name).join(" and ")} ${called.length > 1 ? "answer" : "answers"} ${short(foe)}'s call and ${called.length > 1 ? "take" : "takes"} up arms against the crown.` : ""}` });
  chron.saveMeta(meta);
  next(ctx, turn);
}

// The King's envoy has the house's answer (routes_decree.js, after crown.js join): {house, yes, warns}. Yes: the house
// swears the oath for the war (meta.alliances, so it sends its men with each siege, campaigns.js startCampaign) and
// goes to war with the foe in Freeciv. A friend of the foe refuses and sends it word: the foe's next town is warned
// and raises men (Lua.levy, data/war.json join.warnLevy).
export function joined(ctx, { house, yes, warns }) {
  const { world, meta, record } = ctx;
  const w = current(meta);
  if (!w) return;
  const turn = world.turn ?? 0;
  (w.asked ??= {})[house] = turn;
  if (yes) {
    (w.allies ??= []).push(house);
    (meta.alliances ??= {})[house] = Math.max(meta.alliances[house] ?? 0, turn + WAR.join.seasons);
    if (!atWarInFreeciv(ctx, house, w.house)) ctx.diplomacy?.([house, w.house, 0, "War"]);
  } else if (warns) {
    w.warned = [...new Set([...(w.warned ?? []), house])];
    const town = world.cities.find((c) => c.id === (w.target ?? w.plan.find((id) => world.cities.some((c) => c.id === id && c.owner === w.house))));
    if (town) {
      ctx.send(`lua cmd ${Lua.levy(town.id, WAR.join.warnLevy)}`);
      record({ turn, kind: "scheme", city: town.id, text: `${houseFor(world.players.find((p) => p.id === house) ?? {}).name}'s riders reach ${cityName(town.id)} before the King's envoy is home: ${short(world.players.find((p) => p.id === w.house))} knows the crown is seeking friends, and calls more men to its walls.` });
    }
  }
  chron.saveMeta(meta);
}

// The war is over at the peace table (peace.js ruled): said once, kept in the chronicle.
export function ended(ctx, pid) {
  const { world, meta, record } = ctx;
  const w = current(meta);
  if (!w || w.house !== Number(pid)) return;
  const foe = world?.players?.find((p) => p.id === w.house);
  const fell = (w.fallen ?? []).map(cityName);
  record({ turn: world?.turn ?? 0, kind: "decree", text: `The war on ${short(foe)} ends at the peace table${fell.length ? `, with ${andList(fell)} taken` : ", and no town taken"}. ${houseFor(foe ?? {}).name} still stands.` });
  meta.war = null;
  chron.saveMeta(meta);
}

const andList = (xs) => (xs.length > 1 ? `${xs.slice(0, -1).join(", ")} and ${xs.at(-1)}` : xs[0] ?? "");

// Each season (season.js): towns fallen are told, the seat taken topples the house, a siege that came to nothing is
// passed over for now, the next town is ordered, Freeciv kept at war, and the house strikes back.
export function season(ctx, turn) {
  const { world, meta, record } = ctx;
  const w = current(meta);
  if (!w || !world) return;
  const crown = crownOf(world);
  const foe = world.players.find((p) => p.id === w.house);
  const theirs = (id) => world.cities.some((c) => c.id === id && c.owner === w.house);
  if (!crown) return;
  // The house has no town left, or its seat is the crown's: toppled.
  const seat = world.cities.find((c) => c.id === w.seat);
  if (!foe || !world.cities.some((c) => c.owner === w.house) || !seat || seat.owner !== w.house) return topple(ctx, turn);
  // Freeciv must be at war too: once it has been (the decree's diplomacy goes in at the next sitting), a truce its AI
  // made on its own is broken again; the King's war ends only at his peace table.
  const fighting = atWarInFreeciv(ctx, crown.id, w.house);
  if (fighting) w.atWarSeen = true;
  else if (w.atWarSeen) { ctx.diplomacy?.([crown.id, w.house, 0, "War"]); w.atWarSeen = false; }
  // Towns of the plan the house no longer holds: fallen (to the crown or another), told once, with what comes next.
  for (const id of w.plan) {
    if (theirs(id) || w.fallen.includes(id)) continue;
    w.fallen.push(id);
    const to = world.cities.find((c) => c.id === id);
    const nextId = w.plan.find((x) => theirs(x) && x !== id);
    const who = to && to.owner !== crown.id ? ` to ${houseFor(world.players.find((p) => p.id === to.owner) ?? {}).name}` : "";
    record({ turn, kind: "sack", city: id, attacker: crown.id, defender: w.house,
      text: `The war on ${short(foe)}: ${cityName(id)} has fallen${who}${nextId != null ? `; ${cityName(nextId)} next` : ""}.` });
    if (w.target === id) { w.target = null; w.ordered = null; }
  }
  // The siege of the target came to nothing (lifted, broken, bought off): the captains regroup and try the next town,
  // coming back to this one before the seat.
  if (w.target != null && theirs(w.target) && !besieging(meta, w.target) && w.ordered != null && turn > w.ordered) {
    const was = w.target;
    w.passed = [...new Set([...(w.passed ?? []), was])];
    w.plan = [...w.plan.filter((id) => id !== was && id !== w.seat), was, ...(w.seat != null ? [w.seat] : [])];
    w.target = null; w.ordered = null;
    w.rest = turn + WAR.regroup;
    const nextId = w.plan.find((x) => theirs(x));
    record({ turn, kind: "battle", city: was, attacker: crown.id, defender: w.house,
      text: `The war on ${short(foe)}: the royal host is gone from before ${cityName(was)}, and the town still flies ${short(foe)}'s banner. The captains regroup${nextId != null && nextId !== was ? `; ${cityName(nextId)} next` : ""}.` });
  }
  next(ctx, turn);
  // The house answers in kind (characters.js retaliate): a raid on the King's nearest town or its own host on it.
  if (w.struck == null ? turn > w.since : turn - w.struck >= WAR.retaliate.every) {
    const hit = ctx.court?.retaliate?.(w.house, world, { send: (l) => ctx.send(`lua cmd ${l}`), crownId: crown.id, R: WAR.retaliate }, turn);
    if (hit) {
      w.struck = turn;
      record({ turn, kind: hit.kind, city: hit.city, attacker: w.house, defender: crown.id, text: hit.text });
    }
  }
  chron.saveMeta(meta);
}

const besieging = (meta, city) => (meta.campaigns ?? []).some((c) => c.city === city) || (meta.hostOrders ?? []).some((o) => o.kind === "march" && o.siege && o.city === city);

// The next town given to a host: the first of the plan the house still holds, unless a siege of it is on or the
// captains regroup. The King's biggest host standing at ease (no march, no siege) goes; standing in his seat, it
// leaves half there (hosts.js split). With none fit to march (data/war.json minCompanies), said once until one is.
function next(ctx, turn) {
  const { world, meta, record } = ctx;
  const w = current(meta);
  if (!w || (w.rest ?? -1) > turn) return;
  const target = w.target != null && world.cities.some((c) => c.id === w.target && c.owner === w.house) ? w.target : w.plan.find((id) => world.cities.some((c) => c.id === id && c.owner === w.house));
  if (target == null) return;
  if (besieging(meta, target)) { w.target = target; w.ordered ??= turn; return; }
  const foe = world.players.find((p) => p.id === w.house);
  const hctx = { world, meta, sworn: ctx.sworn, crownSeat: ctx.crownSeat, send: ctx.send, record, besiege: (c) => ctx.startCampaign?.(c), detail: ctx.detail?.() };
  const seat = ctx.crownSeat?.();
  const idle = (h) => (!h.order || (h.order.kind === "hold" && !(meta.hostOrders ?? []).some((o) => o.units.includes(h.id) && o.siege != null))) && !h.aboard && Hosts.ordersLeft(hctx, h.id) > 0;
  let host = Hosts.list(hctx).filter(idle).filter((h) => h.companies >= WAR.minCompanies)[0] ?? null;
  if (host && seat && host.at?.id === seat.id && host.companies >= 2 * WAR.minCompanies) {
    const [code] = Hosts.order(hctx, { host: host.id, order: "split" });
    if (code === 200) host = Hosts.list(hctx).filter(idle).find((h) => h.at?.id === seat.id && h.id !== host.id && h.companies >= WAR.minCompanies) ?? null;
  }
  if (!host) {
    if (w.waits !== target) {
      w.waits = target;
      record({ turn, kind: "decree", city: target, text: `The war on ${short(foe)} waits before ${cityName(target)}: the crown has no host fit to march. Raise a levy or call the banners.` });
    }
    return;
  }
  const [code, out] = Hosts.order(hctx, { host: host.id, order: "besiege", city: target, declared: true });
  if (code !== 200) return;
  w.target = target; w.ordered = turn; w.waits = null;
  record({ turn, kind: "decree", city: target, attacker: crownOf(world)?.id, defender: w.house,
    text: `The war on ${short(foe)}: ${cityName(target)} next. ${out.text}` });
}

// The seat has fallen, or the house holds nothing: the house is toppled. Its towns left pass to the crown (Freeciv's
// transfer); the allies who marched beside the host ask their share of them at court (meta.spoils, characters.js).
function topple(ctx, turn) {
  const { world, meta, record, send } = ctx;
  const w = current(meta);
  const crown = crownOf(world);
  const foe = world.players.find((p) => p.id === w.house);
  const left = world.cities.filter((c) => c.owner === w.house);
  const seatNow = world.cities.find((c) => c.id === w.seat && c.owner !== w.house) ?? null;
  for (const c of left) send(`lua cmd ${Lua.transferCity(c.id, crown.id)}`);
  const allies = (w.allies ?? []).filter((pid) => world.players.some((p) => p.id === pid));
  if (allies.length) for (const c of left) meta.spoils = [...(meta.spoils ?? []).filter((s) => turn - s.turn < 8), { city: c.id, allies, turn, settled: false }];
  const fell = [...(w.fallen ?? []), ...left.map((c) => c.id)];
  record({ turn, kind: "sack", city: w.seat ?? undefined, attacker: crown.id, defender: w.house,
    text: `${houseFor(foe ?? {}).name} is toppled: ${seatNow ? `${cityName(w.seat)}, its seat, is ${seatNow.owner === crown.id ? "the crown's" : houseFor(world.players.find((p) => p.id === seatNow.owner) ?? {}).name + "'s"}` : w.seat != null ? `${cityName(w.seat)}, its seat, is no more` : "it holds no town"}${left.length ? `, and ${andList(left.map((c) => cityName(c.id)))} ${left.length > 1 ? "open their gates" : "opens its gates"} to the King` : ""}. ${fell.length} ${fell.length === 1 ? "town" : "towns"} taken in ${Math.max(1, turn - w.since)} ${turn - w.since === 1 ? "season" : "seasons"}.` });
  ctx.deed?.(kingDeeds.tagsFor("realm", "sack"), { act: false, place: w.seat != null ? cityName(w.seat) : "" });
  meta.war = null;
  chron.saveMeta(meta);
}

// For /world war: the war now, in the view's terms, or null. {house, name, since, next, nextName, fallen, allies,
// seat, seatName}.
export function view(meta, world) {
  const w = current(meta);
  if (!w || !world) return null;
  const foe = world.players.find((p) => p.id === w.house);
  const nextId = w.target ?? w.plan.find((id) => world.cities.some((c) => c.id === id && c.owner === w.house)) ?? null;
  return { house: w.house, name: houseFor(foe ?? {}).name ?? "", since: w.since, next: nextId, nextName: nextId != null ? cityName(nextId) : null,
    fallen: (w.fallen ?? []).map((id) => cityName(id)), allies: w.allies ?? [], seat: w.seat, seatName: w.seat != null ? cityName(w.seat) : null };
}
