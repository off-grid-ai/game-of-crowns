// A beaten great house's land and its lord (Mac 2026-11-17, GAME_DESIGN "The game": "a minor house of his choosing
// becomes warden of its land, loyal to him"; "choosing the wrong warden must cause trouble"; CK3's title grant to a
// vassal whose traits and ties decide if he stays loyal). One owner, meta.wardens [{house, name, seat, towns, turn,
// lord, fate, warden, wardenName, liege, kin, risk, since, defiesAt, passed, risen}], one a house the King toppled (war.js
// topple): until the King names a warden its towns are held by the crown; the warden he names, a bannerman of the
// beaten house or of a house loyal to him, holds them for the crown. Who he is decides how he holds them: his traits,
// his loyalty, his ties to the beaten house (kin, a friend of its lord) give a risk, read on the card, and a warden
// who will defy does so some seasons later (defiesAt): while he defies, the house is not the King's (lost). The beaten
// lord kneels: spared, imprisoned or beheaded, and the other houses read it by how they see the King. The matters
// that ask him are matters/warden.js; the answers are decrees (crown.js warden, spare, imprison, behead, regrant,
// unseat; this module's decree), applied here (apply). Numbers: data/warden.json.
import fs from "node:fs";
import { crownOf, greatHouses } from "./realm.js";
import { houseFor, cityName } from "./narrator.js";
import { BANDS } from "./favour.js";
import { FAMILIES } from "./lore.js";
import * as chron from "./chronicles.js";
import * as Lua from "./lua.js";
import { crownFoe, warOn } from "./war.js";

export const WARDEN = JSON.parse(fs.readFileSync(new URL("./data/warden.json", import.meta.url), "utf8"));
export const ACTS = new Set(["warden", "spare", "imprison", "behead", "regrant", "unseat"]);

const short = (p) => houseFor(p ?? {}).name?.replace(/^House /, "") ?? "the house";
const list = (meta) => meta?.wardens ?? [];
export const of = (meta, house) => list(meta).find((e) => e.house === Number(house)) ?? null;
const andList = (xs) => (xs.length < 2 ? xs.join("") : `${xs.slice(0, -1).join(", ")} and ${xs.at(-1)}`);

// The house is toppled (war.js topple): its towns are the crown's to hold, its lord kneels, a warden is to be named.
export function raise(ctx, w, towns, turn) {
  const { world, meta, court } = ctx;
  const foe = world.players.find((p) => p.id === w.house);
  const lord = court?.lordOfHouse(w.house) ?? null;
  if (lord) { lord.seat = null; court.remember(lord.id, "The King took my house's lands, and I knelt before him."); court.save(lord); }
  const seat = towns.includes(w.seat) ? w.seat : towns[0] ?? null;
  meta.wardens = [...list(meta).filter((e) => e.house !== w.house), { house: w.house, name: houseFor(foe ?? {}).name ?? "", seat, towns, turn,
    lord: lord?.id ?? null, fate: lord ? null : "none", warden: null, wardenName: null, liege: null, kin: false, risk: 0, since: null, defiesAt: null, passed: [] }];
  chron.saveMeta(meta);
}

// The beaten houses not the King's: no warden named yet, or the warden defies him. [pid]. (reign.js goalNow: a beaten
// house counts as won only while it is held; Mac 2026-11-17.)
export function lost(meta, world) {
  const turn = world?.turn ?? 0;
  return list(meta).filter((e) => e.warden == null || defies(e, turn)).map((e) => e.house);
}
export const defies = (e, turn) => e.warden != null && e.defiesAt != null && turn >= e.defiesAt;

// Who could hold the land: the beaten house's own bannermen (they know it; their oath was to the beaten lord) and the
// bannermen of the houses sworn to the King, warmest first. [{c, liege, kin, friend, risk}], at most WARDEN.candidates.
export function candidates(ctx, e) {
  const { world, court, favourOf } = ctx;
  if (!court) return [];
  const crown = crownOf(world);
  const held = new Map((world.cities ?? []).map((c) => [c.id, c.owner]));
  const free = court.alive().filter((c) => c.rank === "bannerman" && c.seat != null && c.warden == null && !(e.passed ?? []).includes(c.id));
  const kinOf = (c) => c.playerId === e.house || [c.spouse, ...(c.parents ?? [])].some((id) => court.people?.[id]?.playerId === e.house);
  const kin = free.filter((c) => c.playerId === e.house && held.get(c.seat) === crown?.id);
  const loyal = greatHouses(world).filter((p) => p.id !== e.house && (favourOf?.(p.id) ?? 0) >= BANDS.sworn).sort((a, b) => favourOf(b.id) - favourOf(a.id));
  const sworn = loyal.flatMap((p) => free.filter((c) => c.playerId === p.id && held.get(c.seat) === p.id).slice(0, 1));
  const want = WARDEN.candidates ?? 3;
  const pick = [...kin.slice(0, Math.max(1, want - sworn.length)), ...sworn].slice(0, want);
  const steady = greatHouses(world).filter((p) => p.id !== e.house && !loyal.includes(p)).sort((a, b) => (favourOf?.(b.id) ?? 0) - (favourOf?.(a.id) ?? 0));
  for (const p of steady) if (pick.length < want) { const c = free.find((x) => x.playerId === p.id && held.get(x.seat) === p.id); if (c) pick.push(c); }
  return pick.map((c) => {
    const friend = e.lord != null && court.opinion(c.id, e.lord) > (WARDEN.risk.friendAt ?? 20);
    const k = kinOf(c);
    return { c, liege: c.playerId === e.house ? null : c.playerId, kin: k, friend, risk: riskOf(ctx, e, c, k, friend) };
  });
}

// How likely he is to defy the King, 0..most (data/warden.json risk).
function riskOf(ctx, e, c, kin, friend) {
  const R = WARDEN.risk;
  let r = R.base + (c.traits ?? []).reduce((n, t) => n + (R.traits[t] ?? 0), 0) + (R.loyaltyMid - (c.loyalty ?? 50)) * R.perLoyalty;
  if (kin) r += R.kin + (e.fate === "behead" ? R.kinBeheaded : e.fate === "spare" ? R.kinSpared : 0);
  if (friend) r += R.friend;
  if (c.playerId !== e.house) r -= Math.max(0, (ctx.favourOf?.(c.playerId) ?? BANDS.sworn) - BANDS.sworn) * R.perFavour;
  return Math.round(Math.max(0, Math.min(R.most, r)));
}
export const riskWord = (r) => (WARDEN.risk.words.find(([under]) => r < under) ?? WARDEN.risk.words.at(-1))[1];

// Whether he will defy, and when: rolled once when he is named (and again when the beaten lord's fate changes how his
// kin sees the crown, or when the King buys his oath back).
function schedule(e, turn, roll = Math.random) {
  const [lo, hi] = WARDEN.defy.after;
  e.defiesAt = roll() * 100 < e.risk ? turn + lo + Math.floor(roll() * (hi - lo + 1)) : null;
}

// The order is refused before it is given: not a matter that stands, or not a man who can take it. Error or null.
export function refuse(ctx, cmd) {
  const e = of(ctx.meta, cmd.to);
  if (!e) return "that house's lands are not the King's to give";
  const turn = ctx.world?.turn ?? 0;
  if (cmd.action === "warden") {
    if (e.warden != null) return `${e.wardenName} already holds ${e.name}'s lands`;
    if (!candidates(ctx, e).some((x) => x.c.seat === Number(cmd.city))) return "that lord cannot be named warden";
  } else if (["spare", "imprison", "behead"].includes(cmd.action)) {
    if (e.fate != null) return "the beaten lord's fate is decided";
  } else if (!defies(e, turn)) return `${e.wardenName ?? "The warden"} keeps his oath`;
  return null;
}

// The decree, as crown.js reckons every decree (x: its handler's argument): what it costs and whose favour it moves,
// nothing changed yet (routes_decree.js weigh runs it dry). The realm changes in apply.
export function decree(x) {
  const { cmd, world, cost, pay, owner } = x;
  const fav = cmd.favourOf ?? (() => 50);
  const great = greatHouses(world).filter((p) => p.id !== Number(cmd.to));
  let favour = {};
  if (cmd.action === "warden" && owner && !houseFor(owner).crown && greatHouses(world).some((p) => p.id === owner.id)) favour = { [owner.id]: WARDEN.pick.liege };
  if (WARDEN.fate[cmd.action]) { const F = WARDEN.fate[cmd.action]; favour = Object.fromEntries(great.map((p) => [p.id, fav(p.id) >= BANDS.steady ? F.warm : F.cold]).filter(([, d]) => d)); }
  return { cost, lua: [pay], favour, warden: { act: cmd.action, house: Number(cmd.to), city: Number(cmd.city) }, text: "" };
}

// The order given (routes_decree.js): the warden named, the lord's fate dealt, a defiant warden bought back or unseated.
// Returns the chronicle's words.
export function apply(ctx, { act, house, city }) {
  const { world, meta, court } = ctx;
  const e = of(meta, house);
  if (!e || !court) return "";
  const turn = world.turn ?? 0;
  const crown = crownOf(world);
  const lands = `${e.name}'s lands (${andList(e.towns.map(cityName))})`;
  let text = "";
  if (act === "warden") {
    const x = candidates(ctx, e).find((y) => y.c.seat === city);
    if (!x) return "";
    const c = x.c;
    const was = c.house;
    c.playerId = crown.id; c.house = houseFor(crown).name; c.liege = court.lordOfHouse(crown.id)?.id ?? null;
    c.seat = e.seat; c.warden = e.house;
    court.remember(c.id, `The King made my house warden of ${lands}.`);
    court.save(c);
    Object.assign(e, { warden: c.id, wardenName: `House ${c.surname}`, liege: x.liege, kin: x.kin, risk: x.risk, since: turn });
    schedule(e, turn);
    text = `The King names House ${c.surname}, ${x.kin ? `once sworn to ${e.name}` : `of ${was}'s banners`}, warden of ${lands}. ${c.name} kneels and swears to hold them for the crown.`;
  } else if (WARDEN.fate[act]) {
    const lord = court.people?.[e.lord];
    e.fate = act;
    if (lord?.alive) {
      if (act === "behead") { lord.seat = null; court.die(lord, turn, world); }
      else { lord.captive = act === "imprison" ? turn : null; court.remember(lord.id, act === "spare" ? "I knelt before the King, and he spared me." : "The King keeps me in chains in his tower."); court.save(lord); }
    }
    // The warden, if he is the beaten lord's kin, hears how his lord was dealt with.
    const w = court.people?.[e.warden];
    if (w?.alive && e.kin) { e.risk = riskOf(ctx, e, w, true, court.opinion(w.id, e.lord) > (WARDEN.risk.friendAt ?? 20)); schedule(e, turn); }
    const name = lord?.name ?? `the lord of ${e.name}`;
    text = act === "behead" ? `${name} is beheaded before the gate of Kingsmere. Every lord who hears of it remembers what the crown does with a beaten house.`
      : act === "imprison" ? `${name} is taken to the King's tower in chains, to sit there at the crown's pleasure.`
      : `The King raises ${name} from his knees and lets him go, landless, with his life. Some call it greatness; some call it weakness.`;
  } else if (act === "regrant") {
    const w = court.people?.[e.warden];
    if (w) { w.loyalty = Math.min(100, (w.loyalty ?? 50) + WARDEN.regrant.loyalty); court.remember(w.id, "I defied the King, and he bought my oath back."); court.save(w); }
    e.risk = w ? riskOf(ctx, e, w, e.kin, false) : e.risk;
    schedule(e, turn);
    // Risen, his towns come back to the crown with his oath (the side he went to keeps the men it raised).
    const back = e.risen ? e.towns.filter((id) => world.cities?.some((c) => c.id === id && c.owner === e.risen.side)) : [];
    for (const id of back) ctx.send?.(`lua cmd ${Lua.transferCity(id, crown.id)}`);
    e.risen = null;
    text = `${e.wardenName} takes the King's gold and swears again to hold ${lands} for the crown.${back.length ? ` ${andList(back.map(cityName))} ${back.length > 1 ? "open their gates" : "opens its gates"} to the King's men again.` : ""}`;
  } else if (act === "unseat") {
    const w = court.people?.[e.warden];
    if (w) { w.seat = null; w.warden = null; court.remember(w.id, "I defied the King, and he took the lands he gave me."); court.save(w); }
    e.passed = [...(e.passed ?? []), e.warden];
    text = `The King strips ${e.wardenName} of ${lands}. Another must be named to hold them.`;
    Object.assign(e, { warden: null, wardenName: null, liege: null, kin: false, risk: 0, since: null, defiesAt: null, risen: null });
  }
  chron.saveMeta(meta);
  return text;
}

// A defiant warden takes up arms (Mac 2026-11-17: the wrong warden must cause real trouble). The season he defies, his
// towns go over to a house that will have them, by Freeciv's own transfer (Lua.transferCity): the house he is tied to
// (his old liege, or the beaten house when he is its kin) if it is at war with the crown; else the beaten house itself,
// raised again under him, if Freeciv still has it; else the King's coldest foe (at war with the crown, or under
// data/warden.json rise.coldBelow, which goes to war for the towns). That house raises a host at his towns and marches
// it on the crown's town nearest his seat (Lua.warHost: realm_war_host, hosts.js warpath), the war its own; if the King
// wars on that house, the towns join his war's plan (war.js), taken before its seat. Once risen, the crown's host
// taking his seat back puts him down: he is stripped, and the land wants a warden again. e.risen {turn, side, towns,
// prey}. Called each season (season.js); returns nothing, tells the chronicle.
export function season(ctx, turn) {
  const { world, meta, court, record } = ctx;
  const crown = crownOf(world);
  if (!crown || !court) return;
  for (const e of list(meta)) {
    if (e.risen) { putDown(ctx, e, turn, crown); continue; }
    if (!defies(e, turn)) continue;
    rise(ctx, e, turn, crown);
  }
}

const alive = (world, pid) => pid != null && (world.players ?? []).some((p) => p.id === pid && p.alive !== false);

// Who takes his towns: [pid, why] or null.
export function sideOf(ctx, e) {
  const { world, favourOf } = ctx;
  const R = WARDEN.rise;
  const crown = crownOf(world);
  const foe = (pid) => alive(world, pid) && pid !== crown?.id && crownFoe(ctx, pid);
  const ties = [e.liege, e.kin ? e.house : null].filter((pid) => pid != null);
  const tied = ties.find(foe);
  if (tied != null) return [tied, "tie"];
  if (alive(world, e.house) && !houseFor(world.players.find((p) => p.id === e.house)).wild) return [e.house, "old"];
  const cold = greatHouses(world).filter((p) => p.id !== e.house && (foe(p.id) || (favourOf?.(p.id) ?? 50) < R.coldBelow))
    .sort((a, b) => (favourOf?.(a.id) ?? 50) - (favourOf?.(b.id) ?? 50))[0];
  return cold ? [cold.id, "cold"] : null;
}

function rise(ctx, e, turn, crown) {
  const { world, meta, record } = ctx;
  const R = WARDEN.rise;
  const s = sideOf(ctx, e);
  const towns = e.towns.filter((id) => world.cities?.some((c) => c.id === id && c.owner === crown.id));
  if (!s || !towns.length) return;
  const [side, why] = s;
  const send = (l) => ctx.send?.(`lua cmd ${l}`);
  for (const id of towns) send(Lua.transferCity(id, side));
  const seat = world.cities.find((c) => c.id === e.seat) ?? world.cities.find((c) => c.id === towns[0]);
  const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
  const prey = world.cities.filter((c) => c.owner === crown.id && !towns.includes(c.id)).sort((a, b) => cheb(a, seat) - cheb(b, seat))[0] ?? null;
  const men = R.host + R.perTown * towns.length;
  if (prey) send(Lua.warHost(side, prey.id, R.kinds, men));
  // The crown and the side are at war in Freeciv (the one writer): taking the King's towns is war.
  ctx.diplomacy?.([crown.id, side, 0, "War"]);
  // The King's war on that house, if he wages one, takes his towns before its seat.
  const w = warOn(meta, side);
  if (w) w.plan = [...towns.filter((id) => !w.plan.includes(id)), ...w.plan];
  e.risen = { turn, side, why, towns, prey: prey?.id ?? null };
  const sideName = houseFor(world.players.find((p) => p.id === side) ?? {}).name ?? "the King's foes";
  const went = why === "old" ? `raises the old banner of ${e.name} over ${andList(towns.map(cityName))}`
    : `opens the gates of ${andList(towns.map(cityName))} to ${sideName}${why === "tie" ? `, ${e.kin && side === e.house ? "the house it was sworn to" : "its old liege"}, at war with the crown` : ", the crown's foe"}`;
  record({ turn, kind: "rebellion", city: e.seat ?? towns[0], attacker: side, defender: crown.id,
    text: `${e.wardenName} breaks its oath and ${went}. ${prey ? `${men} companies march out of ${cityName(seat.id)} on ${cityName(prey.id)}.` : ""} ${e.name}'s lands are in arms against the King.`.replace(/\s+/g, " ").trim() });
  chron.saveMeta(meta);
}

// The crown holds his seat again (the royal host took it): the warden is put down, stripped, and the land wants another.
function putDown(ctx, e, turn, crown) {
  const { world, meta, court, record } = ctx;
  const seat = world.cities?.find((c) => c.id === e.seat);
  if (seat && seat.owner === e.risen.side && !e.risen.held) { e.risen.held = true; chron.saveMeta(meta); }  // his rising has his seat
  if (!seat || seat.owner !== crown.id || !e.risen.held) return;
  const w = court.people?.[e.warden];
  if (w) { w.seat = null; w.warden = null; w.loyalty = Math.max(0, (w.loyalty ?? 50) - (WARDEN.rise.putDownLoyalty ?? 0)); court.remember(w.id, "I defied the King, and his host took my seat from me."); court.save(w); }
  const name = e.wardenName;
  e.passed = [...(e.passed ?? []), e.warden];
  Object.assign(e, { warden: null, wardenName: null, liege: null, kin: false, risk: 0, since: null, defiesAt: null, risen: null });
  record({ turn, kind: "rebellion", city: seat.id, attacker: crown.id, text: `The royal host takes ${cityName(seat.id)} back: ${name} is put down and stripped of ${e.name}'s lands. Another must be named to hold them.` });
  chron.saveMeta(meta);
}

// A town of a beaten house's land, or of a house the King wars on (its towns go to a warden when it is toppled): never
// an ally's to claim as spoils (campaigns.js).
export const wardenLand = (meta, city, house) => list(meta).some((e) => e.towns.includes(Number(city))) || warOn(meta, house) != null;

// How a defiant warden defies, by what made him: his blood, his ambition, or his greed.
export function defiance(ctx, e) {
  if (e.risen) {
    const side = houseFor(ctx.world.players.find((p) => p.id === e.risen.side) ?? {}).name ?? "the King's foes";
    return `${e.wardenName} is in arms: ${andList(e.risen.towns.map(cityName))} ${e.risen.towns.length > 1 ? "fly" : "flies"} ${e.risen.why === "old" ? `${e.name}'s old banner again` : `${side}'s banner`}${e.risen.prey != null ? `, and its host marches on ${cityName(e.risen.prey)}` : ""}`;
  }
  const w = ctx.court?.people?.[e.warden];
  const traits = w?.traits ?? [];
  if (e.kin) return `${e.wardenName} remembers whose banner it once flew: it shuts the gates of ${cityName(e.seat)} to the King's men and sends word to his foes`;
  if (traits.includes("ambitious") || traits.includes("proud")) return `${e.wardenName} calls itself lord of ${e.name}'s lands in its own right and keeps the crown's tithe`;
  return `${e.wardenName} keeps the tithe and the men of ${e.name}'s lands for itself`;
}

// The warden's card line: his house, his liege, his nature, his loyalty, the tie that matters, and how he would hold.
export function label(ctx, e, x) {
  const { c, liege, kin, friend, risk } = x;
  const ofLiege = liege != null ? ` (${short(ctx.world.players.find((p) => p.id === liege))}'s man)` : "";
  const tie = kin && c.playerId === e.house ? `sworn to ${e.name.replace(/^House /, "")} till now` : kin ? `wed into ${e.name.replace(/^House /, "")}` : friend ? "a friend of the beaten lord" : "no tie to the beaten house";
  const traits = (c.traits ?? []).slice(0, 2).join(", ") || "plain";
  return `House ${c.surname}${ofLiege}: ${traits} · loyalty ${Math.round(c.loyalty ?? 50)} · ${tie} · ${riskWord(risk)}`;
}

// The family's lore (lore.js), its first sentence: who they are, for the card's why.
export const lore = (c) => String(FAMILIES[c.surname]?.character ?? "").split(/(?<=\.)\s/)[0];
