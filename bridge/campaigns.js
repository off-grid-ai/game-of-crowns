// The royal host and sieges: a town besieged by an enemy host (sieges), the
// King's own campaigns (startCampaign, marchOn), their odds (marchOdds), the
// besieged lord's terms at court and the King's answer (siegeTerms,
// siegeRuled), and each season's outcome (resolveCampaigns); and the oaths
// that send sworn houses with the host (sworn). Nothing here reads server.js:
// the realm's state and the bridge's own helpers come in as one context
// argument, built fresh by server.js on each call (server.js keeps wrappers of
// the same names).

import { houseFor, cityName } from "./narrator.js";
import fs from "node:fs";
import { decree } from "./crown.js";
import { calendar } from "./calendar.js";
import * as chron from "./chronicles.js";
import * as kingDeeds from "./ledger.js";
import * as Lua from "./lua.js";

// A town is besieged while an enemy host stands at its walls: three or more
// fighting units of another house on the tiles around it. One scene per turn.
export const CIVILIAN = new Set(["Settlers", "Workers", "Migrants", "Engineers", "Explorer", "Caravan", "Freight", "Diplomat", "Spy", "Leader"]);
// The fighting companies of other houses on the tiles around a town: three or
// more is a siege (the one rule, read by sieges() and townStates()).
export function besiegers(ctx, c) {
  const { world } = ctx;
  return (world?.units ?? []).filter((u) => u.owner !== c.owner && !CIVILIAN.has(u.type) && Math.max(Math.abs(u.x - c.x), Math.abs(u.y - c.y)) === 1);
}

// The siege engines among a host's companies (Freeciv's catapults and trebuchets): the camp builds as many.
const ENGINE = /Catapult|Trebuchet|Cannon|Artillery/;
export const engines = (units) => units.filter((u) => ENGINE.test(u.type)).length;

export function sieges(ctx) {
  const { world, scene, record } = ctx;
  if (!world?.units || !world?.cities) return;
  for (const c of world.cities) {
    const near = besiegers(ctx, c);
    if (near.length < 3) continue;
    const counts = {};
    for (const u of near) counts[u.owner] = (counts[u.owner] ?? 0) + 1;
    const owner = Number(Object.entries(counts).sort((a, b) => b[1] - a[1])[0][0]);
    if (ctx.scenes.some((x) => x.kind === "siege" && x.city === c.id && x.turn === world.turn)) continue;
    scene("siege", { x: c.x, y: c.y, city: c.id, owner, defender: c.owner, size: near.length, engines: engines(near), ax: near[0].x, ay: near[0].y });
    const first = !ctx.scenes.some((x) => x.kind === "siege" && x.city === c.id && x.turn === world.turn - 1);
    if (first) record({ turn: world.turn, kind: "battle", text: `${houseFor(world.players.find((p) => p.id === owner)).name} lays siege to ${cityName(c.id)} with ${near.length} companies.`, city: c.id });
  }
}

// Freeciv's assault on a town (realmrules/script.lua realm_assault's "assault" EVENT: the men at the walls, the blows
// Freeciv let land, the town's owner after) as the view's storm scene (scenes.gd storm): who stormed and who held,
// and whether Freeciv gave the stormers the town (or razed it). The view storms the siege it shows and ends it so;
// it decides nothing. null for a town that isn't there.
export function stormScene(world, ev, crownId) {
  const town = (world?.cities ?? []).find((c) => c.id === Number(ev.city));
  if (!town) return null;
  const after = Number(ev.owner);
  const near = besiegers({ world }, town).filter((u) => u.owner === crownId);
  return { x: town.x, y: town.y, city: town.id, owner: crownId, defender: town.owner, men: Number(ev.men), blows: Number(ev.blows),
    taken: after === crownId || after < 0, engines: engines(near),
    ax: near[0]?.x ?? town.x + 1, ay: near[0]?.y ?? town.y };
}

// --- Oaths and the royal host ------------------------------------------------------

// A house sworn to the crown (an alliance not yet run out).
export function sworn(ctx, pid) {
  const { world, meta } = ctx;
  return (meta?.alliances?.[pid] ?? -1) > (world?.turn ?? 0);
}

// The royal host goes to a town: sworn houses send their men with it (an ally
// marched upon breaks its own oath, and the realm hears of it).
export function startCampaign(ctx, { city, house }) {
  const { world, meta, send, record, scene, deed, shiftFavour, greatHouses } = ctx;
  const turn = world?.turn ?? 0;
  const at = world.cities.find((c) => c.id === city);
  if (!at) return;
  if (sworn(ctx, house)) {
    deed(kingDeeds.tagsFor("realm", "sworn_march"), { act: false, place: houseFor(world.players.find((p) => p.id === house) ?? {}).name ?? "" });
    delete meta.alliances[house];
    shiftFavour(Object.fromEntries(greatHouses().filter((p) => p.id !== house).map((p) => [p.id, -5])), "an oath to the crown");
    record({ turn, kind: "betrayal", text: `The King marches on a house sworn to him. Every lord who ever knelt to the crown takes note.`, city });
  }
  const allies = greatHouses().filter((p) => p.id !== house && sworn(ctx, p.id) && world.cities.some((c) => c.owner === p.id));
  for (const a of allies) send(`lua cmd ${Lua.host(a.id, at.x, at.y, ["Pikemen", "Knights"], 3)}`);
  if (allies.length) record({ turn, kind: "decree", text: `${allies.map((p) => houseFor(p).name).join(" and ")} ${allies.length > 1 ? "answer their oaths" : "answers its oath"} and ${allies.length > 1 ? "send" : "sends"} men to march with the King.`, city });
  (meta.campaigns ??= []).push({ city, house, turn, allies: allies.map((p) => p.id) });
  chron.saveMeta(meta);
  // In Freeciv the crown is at war with the house (the bridge's one diplomacy writer), so Freeciv fights
  // every blow of the assault (resolveCampaigns, realm_assault).
  const crown = world.players.find((p) => houseFor(p).crown);
  const atWar = ctx.detail?.()?.players?.find((p) => p.slot === crown?.id)?.atWarWith?.includes(house);
  if (crown && !atWar) ctx.diplomacy?.([crown.id, house, 0, "War"]);
  scene("siege", { x: at.x, y: at.y, city, owner: world.players.find((p) => houseFor(p).crown)?.id, defender: house });
}

// The royal host's chance against a house's town, the same reckoning the
// forecast shows and the outcome uses: our companies (and sworn allies') against
// what the house can bring to one town; winter favours whoever holds the walls.
export function marchOdds(ctx, house, allies = [], { extra = 0, turn = ctx.world?.turn ?? 0 } = {}) {
  const { world, SOLDIER } = ctx;
  const crown = world?.players?.find((p) => houseFor(p).crown);
  const foe = world?.players?.find((p) => p.id === house);
  if (!crown || !foe) return 0;
  const soldiers = (pid) => (world.units ?? []).filter((u) => u.owner === pid && SOLDIER(u)).length;
  const allyMen = allies.reduce((t, id) => t + soldiers(id) * 0.25, 0);
  const ours = soldiers(crown.id) + extra + allyMen;
  const theirs = soldiers(foe.id) * 0.6;  // a house can't bring every company to one town
  const winter = calendar(turn).season === "winter" ? 0.8 : 1;
  return (ours * winter) / Math.max(1, ours * winter + theirs);
}

// The siege's middle: a season in, the besieged lord's herald brings terms, and
// the King chooses: press the assault (gold, and better odds), take tribute and
// go home, or starve them out (a season longer, better odds again).
// Assaults the royal host makes on a town before its captains lift the siege (one a season, data/hosts.json).
export const SIEGE_ASSAULTS = JSON.parse(fs.readFileSync(new URL("./data/hosts.json", import.meta.url), "utf8")).siegeAssaults ?? 4;
export function siegeTerms(ctx, c, turn) {
  const { world, meta, court } = ctx;
  if (c.asked || !court) return;
  c.asked = true;
  const foe = world.players.find((p) => p.id === c.house);
  const lord = court.lordOfHouse(c.house);
  if (!foe || !lord) return;
  const town = cityName(c.city);
  const odds = Math.round(marchOdds(ctx, c.house, c.allies ?? [], { turn: turn + 1 }) * 100);
  // The captains' reckoning for a season later, if the King waits (winter favours the walls); Freeciv fights it.
  const starveOdds = Math.round(marchOdds(ctx, c.house, c.allies ?? [], { turn: turn + 2 }) * 100);
  const starveWinter = calendar(turn + 2).season === "winter";
  // Tribute is what the house can pay, taken from its own chest.
  const tribute = Math.min(150, Math.max(0, Math.floor(foe.gold ?? 0)));
  court.arcPetition({ arc: "siege", beat: `siege-${c.city}-${c.turn}`, thread: `the siege of ${town}`, from: lord,
    text: tribute >= 50
      ? `${lord.name}'s herald comes out of ${town} under a white flag: "My ${lord.gender === "female" ? "lady" : "lord"} will pay the Crown ${tribute} gold to see your host gone by morning." The captains put the King's chances at ${odds} in a hundred.`
      : `${lord.name}'s herald comes out of ${town} under a white flag, with nothing to offer but defiance. The captains put the King's chances at ${odds} in a hundred.`,
    options: [
      { id: "press", label: "Press the assault (200 gold)", hint: `${odds} in 100, assaulted now · ${houseFor(foe).name} −10 · ladders and fire, more dead`, cost: 200, favour: { [c.house]: -10 }, result: `The King orders the assault. Ladders go up against the walls of ${town} at dawn.` },
      { id: "starve", label: "Starve them out", hint: `${starveOdds} in 100, a season longer${starveWinter ? ", in winter" : ""} · ${houseFor(foe).name} −5`, favour: { [c.house]: -5 }, result: `The royal host digs in around ${town}. No cart goes in or out.` },
      ...(tribute >= 50 ? [{ id: "tribute", label: "Take their gold and withdraw", hint: `+${tribute} gold · ${houseFor(foe).name} +10 · every other great house −3: a King who can be bought`, favour: { [c.house]: 10, ...Object.fromEntries((world?.players ?? []).filter((p) => p.id !== Number(c.house) && !houseFor(p).crown && !houseFor(p).wild && (world.cities ?? []).some((x) => x.owner === p.id)).map((p) => [p.id, -3])) }, result: `The King takes ${lord.name}'s gold and the host turns for home. ${town} rings its bells.` }] : []),
    ] }, world);
  c.tribute = tribute;
  chron.saveMeta(meta);
}

export function siegeRuled(ctx, beat, option) {
  const { meta, send, crownOf } = ctx;
  const c = (meta.campaigns ?? []).find((x) => `siege-${x.city}-${x.turn}` === beat);
  if (!c) return;
  const crown = crownOf();
  c.ruled = true;
  if (option === "press") c.press = true;
  if (option === "starve") { c.starve = true; c.extra = 1; }
  if (option === "tribute") {
    meta.campaigns = meta.campaigns.filter((x) => x !== c);
    const paid = c.tribute ?? 150;
    if (crown) send(`lua cmd ${Lua.pay(c.house, crown.id, paid)}`);
  }
  chron.saveMeta(meta);
}

// Each season: a host that has stood two seasons before a town takes it or breaks.
export function resolveCampaigns(ctx, turn) {
  const { world, meta, court, send, record, deed, shiftFavour, greatHouses, SOLDIER } = ctx;
  for (const c of [...(meta.campaigns ?? [])]) {
    if (turn - c.turn >= 1) siegeTerms(ctx, c, turn);
    // The assault waits for the host to reach the walls (two seasons), a season more to starve them,
    // none once the King orders it pressed.
    if (!c.press && turn - c.turn < 2 + (c.extra ?? 0)) continue;
    // The herald's terms are answered before the first assault: it waits for the King's word, two
    // seasons at most, then the captains decide without him.
    if (c.asked && !c.ruled && court?.petitions.some((p) => !p.answered && p.beat === `siege-${c.city}-${c.turn}`) && (c.hold = (c.hold ?? 0) + 1) <= 2) continue;
    const town = world.cities.find((x) => x.id === c.city);
    const crown = world.players.find((p) => houseFor(p).crown);
    const foe = world.players.find((p) => p.id === c.house);
    const end = () => { meta.campaigns = meta.campaigns.filter((x) => x !== c); };
    if (!crown || !foe) { end(); continue; }
    // Why it went as it did, in one line: our companies against theirs, and the season.
    const why = `${(world.units ?? []).filter((u) => u.owner === crown.id && SOLDIER(u)).length} royal companies against ${houseFor(foe).name}'s ${(world.units ?? []).filter((u) => u.owner === foe.id && SOLDIER(u)).length}${calendar(turn).season === "winter" ? ", in winter" : ""}.`;
    // Freeciv fought it (realm_assault): the town is the crown's (or razed), still the house's, or the host is gone.
    if (!town || town.owner === crown.id) {
      end();
      shiftFavour({ [c.house]: -20 }, "the royal host");
      shiftFavour(Object.fromEntries((c.allies ?? []).map((id) => [id, 6])), "the royal host");
      deed(kingDeeds.tagsFor("realm", "sack"), { act: false, place: cityName(c.city) });
      record({ turn, kind: "sack", text: `${cityName(c.city)} falls to the royal host: ${why} ${houseFor(foe).name} has learned what the crown's anger costs.`, city: c.city });
      continue;
    }
    if (town.owner !== c.house) { end(); record({ turn, kind: "decree", text: `The royal host stands down before ${cityName(c.city)}: it is no longer ${houseFor(foe).name}'s to take.`, city: c.city }); continue; }
    const men = (world.units ?? []).filter((u) => u.owner === crown.id && SOLDIER(u) && Math.max(Math.abs(u.x - town.x), Math.abs(u.y - town.y)) === 1).length;
    if ((c.assaults ?? 0) > 0 && men === 0 || (c.assaults ?? 0) >= SIEGE_ASSAULTS || (!c.assaults && men === 0 && turn - c.turn >= 2 + (c.extra ?? 0) + 3)) {
      end();
      shiftFavour(Object.fromEntries(greatHouses().filter((p) => p.id !== c.house).map((p) => [p.id, -3])), "the royal host");
      shiftFavour({ [c.house]: -10 }, "the royal host");
      record({ turn, kind: "battle", text: `The royal host breaks against the walls of ${cityName(c.city)}: ${why} ${houseFor(foe).name} holds, and the realm sees a King who can be refused.`, city: c.city });
      continue;
    }
    if (men === 0) continue;  // still on the road to the walls
    // An assault this season: each royal company beside the walls strikes once and Freeciv decides.
    send(`lua cmd ${Lua.assault(c.city, crown.id)}`);
    c.assaults = (c.assaults ?? 0) + 1;
  }
  chron.saveMeta(meta);
}

// The royal host marches on a town for a ruling the court already paid for: the
// decree's own march (crown.js), its fee waived, and the same campaign.
export function marchOn(ctx, cityId) {
  const { world, meta, send, shiftFavour, favourOf, causeOf } = ctx;
  if (!world) return;
  const r = decree({ action: "march", spawn: true, city: cityId, price: 0, favourOf, causeOf, marching: (city) => (meta.campaigns ?? []).some((x) => x.city === city) }, { ...world, players: world.players.map((p) => houseFor(p).crown ? { ...p, gold: 1e9 } : p) });
  if (r.error) { console.error("march:", r.error); return; }
  (r.lua ?? []).slice(1).forEach((l) => send(`lua cmd ${l}`));
  shiftFavour(r.favour, "the royal host");
  if (r.march) startCampaign(ctx, r.march);
}
