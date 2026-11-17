// A beaten great house's land and its lord (Mac 2026-11-17, GAME_DESIGN "The game": "a minor house of his choosing
// becomes warden of its land, loyal to him"; "choosing the wrong warden must cause trouble"; CK3's title grant to a
// vassal whose traits and ties decide if he stays loyal). One owner, meta.wardens [{house, name, seat, towns, turn,
// lord, fate, warden, wardenName, liege, kin, risk, since, defiesAt, passed}], one a house the King toppled (war.js
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
    text = `${e.wardenName} takes the King's gold and swears again to hold ${lands} for the crown.`;
  } else if (act === "unseat") {
    const w = court.people?.[e.warden];
    if (w) { w.seat = null; w.warden = null; court.remember(w.id, "I defied the King, and he took the lands he gave me."); court.save(w); }
    e.passed = [...(e.passed ?? []), e.warden];
    text = `The King strips ${e.wardenName} of ${lands}. Another must be named to hold them.`;
    Object.assign(e, { warden: null, wardenName: null, liege: null, kin: false, risk: 0, since: null, defiesAt: null });
  }
  chron.saveMeta(meta);
  return text;
}

// How a defiant warden defies, by what made him: his blood, his ambition, or his greed.
export function defiance(ctx, e) {
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
