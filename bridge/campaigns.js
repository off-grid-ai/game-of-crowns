// The royal host and sieges: a town besieged by an enemy host (sieges), the
// King's own campaigns (startCampaign, marchOn), their odds (marchOdds), the
// besieged lord's terms at court and the King's answer (siegeTerms,
// siegeRuled), and each season's outcome (resolveCampaigns); and the oaths
// that send sworn houses with the host (sworn). Nothing here reads server.js:
// the realm's state and the bridge's own helpers come in as one context
// argument, built fresh by server.js on each call (server.js keeps wrappers of
// the same names).

import { houseFor, cityName } from "./narrator.js";
import { decree } from "./crown.js";
import { calendar } from "./stakes.js";
import * as chron from "./chronicles.js";
import * as kingDeeds from "./ledger.js";

// A town is besieged while an enemy host stands at its walls: three or more
// fighting units of another house on the tiles around it. One scene per turn.
export const CIVILIAN = new Set(["Settlers", "Workers", "Migrants", "Engineers", "Explorer", "Caravan", "Freight", "Diplomat", "Spy", "Leader"]);
// The fighting companies of other houses on the tiles around a town: three or
// more is a siege (the one rule, read by sieges() and townStates()).
export function besiegers(ctx, c) {
  const { world } = ctx;
  return (world?.units ?? []).filter((u) => u.owner !== c.owner && !CIVILIAN.has(u.type) && Math.max(Math.abs(u.x - c.x), Math.abs(u.y - c.y)) === 1);
}

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
    const engines = near.filter((u) => /Catapult|Trebuchet|Cannon|Artillery/.test(u.type)).length;
    scene("siege", { x: c.x, y: c.y, city: c.id, owner, defender: c.owner, size: near.length, engines, ax: near[0].x, ay: near[0].y });
    const first = !ctx.scenes.some((x) => x.kind === "siege" && x.city === c.id && x.turn === world.turn - 1);
    if (first) record({ turn: world.turn, kind: "battle", text: `${houseFor(world.players.find((p) => p.id === owner)).name} lays siege to ${cityName(c.id)} with ${near.length} companies.`, city: c.id });
  }
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
  for (const a of allies) send(`lua cmd realm_host(realm_find_player(${a.id}), ${at.x}, ${at.y}, {"Pikemen","Knights"}, 3)`);
  if (allies.length) record({ turn, kind: "decree", text: `${allies.map((p) => houseFor(p).name).join(" and ")} ${allies.length > 1 ? "answer their oaths" : "answers its oath"} and ${allies.length > 1 ? "send" : "sends"} men to march with the King.`, city });
  (meta.campaigns ??= []).push({ city, house, turn, allies: allies.map((p) => p.id) });
  chron.saveMeta(meta);
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
export const SIEGE_PRESS = 20;   // points in a hundred the assault adds, now
export const SIEGE_STARVE = 10;  // points starving them out adds, a season later
export function siegeTerms(ctx, c, turn) {
  const { world, meta, court } = ctx;
  if (c.asked || !court) return;
  c.asked = true;
  const foe = world.players.find((p) => p.id === c.house);
  const lord = court.lordOfHouse(c.house);
  if (!foe || !lord) return;
  const town = cityName(c.city);
  const odds = Math.round(marchOdds(ctx, c.house, c.allies ?? [], { turn: turn + 1 }) * 100);
  // Each answer's own chances, worked the way the siege will resolve them:
  // the assault now, or the starving a season later (winter favours the walls).
  const pressOdds = Math.min(95, odds + SIEGE_PRESS);
  const starveOdds = Math.min(95, Math.round(marchOdds(ctx, c.house, c.allies ?? [], { turn: turn + 2 }) * 100) + SIEGE_STARVE);
  const starveWinter = calendar(turn + 2).season === "winter";
  // Tribute is what the house can pay, taken from its own chest.
  const tribute = Math.min(150, Math.max(0, Math.floor(foe.gold ?? 0)));
  court.arcPetition({ arc: "siege", beat: `siege-${c.city}-${c.turn}`, thread: `the siege of ${town}`, from: lord,
    text: tribute >= 50
      ? `${lord.name}'s herald comes out of ${town} under a white flag: "My ${lord.gender === "female" ? "lady" : "lord"} will pay the Crown ${tribute} gold to see your host gone by morning." The captains put the King's chances at ${odds} in a hundred.`
      : `${lord.name}'s herald comes out of ${town} under a white flag, with nothing to offer but defiance. The captains put the King's chances at ${odds} in a hundred.`,
    options: [
      { id: "press", label: "Press the assault (200 gold)", hint: `${pressOdds} in 100 · ${houseFor(foe).name} −10 · ladders and fire, more dead`, cost: 200, favour: { [c.house]: -10 }, result: `The King orders the assault. Ladders go up against the walls of ${town} at dawn.` },
      { id: "starve", label: "Starve them out", hint: `${starveOdds} in 100, a season longer${starveWinter ? ", in winter" : ""} · ${houseFor(foe).name} −5`, favour: { [c.house]: -5 }, result: `The royal host digs in around ${town}. No cart goes in or out.` },
      ...(tribute >= 50 ? [{ id: "tribute", label: "Take their gold and withdraw", hint: `+${tribute} gold · ${houseFor(foe).name} +10 · the realm sees a King who can be bought`, favour: { [c.house]: 10 }, result: `The King takes ${lord.name}'s gold and the host turns for home. ${town} rings its bells.` }] : []),
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
    if (crown) send(`lua cmd for p in players_iterate() do if p.id == ${crown.id} then edit.change_gold(p, ${paid}) end; if p.id == ${c.house} then edit.change_gold(p, -${paid}) end end`);
  }
  chron.saveMeta(meta);
}

// Each season: a host that has stood two seasons before a town takes it or breaks.
export function resolveCampaigns(ctx, turn) {
  const { world, meta, court, send, record, deed, shiftFavour, greatHouses, SOLDIER } = ctx;
  for (const c of [...(meta.campaigns ?? [])]) {
    if (turn - c.turn >= 1) siegeTerms(ctx, c, turn);
    if (turn - c.turn < 2 + (c.extra ?? 0)) continue;
    // The herald's terms are answered before the siege is decided: it waits for
    // the King's word, two seasons at most, then the captains decide without him.
    if (c.asked && !c.ruled && court?.petitions.some((p) => !p.answered && p.beat === `siege-${c.city}-${c.turn}`) && (c.hold = (c.hold ?? 0) + 1) <= 2) continue;
    meta.campaigns = meta.campaigns.filter((x) => x !== c);
    const town = world.cities.find((x) => x.id === c.city);
    const crown = world.players.find((p) => houseFor(p).crown);
    const foe = world.players.find((p) => p.id === c.house);
    if (!town || !crown || !foe) continue;
    if (town.owner !== c.house) { record({ turn, kind: "decree", text: `The royal host stands down before ${cityName(c.city)}: it is no longer ${houseFor(foe).name}'s to take.`, city: c.city }); continue; }
    // Pressing the assault or starving them out tips the odds the King's way.
    const odds = Math.min(0.95, marchOdds(ctx, c.house, c.allies ?? []) + (c.press ? SIEGE_PRESS : c.starve ? SIEGE_STARVE : 0) / 100);
    // Why it went as it did, in one line: our companies against theirs, and the season.
    const why = `${(world.units ?? []).filter((u) => u.owner === crown.id && SOLDIER(u)).length} royal companies against ${houseFor(foe).name}'s ${(world.units ?? []).filter((u) => u.owner === foe.id && SOLDIER(u)).length}${calendar(turn).season === "winter" ? ", in the cold of winter" : ""}.`;
    if (Math.random() < odds) {
      send(`lua cmd local t = find.city(nil, ${c.city}); local to; for p in players_iterate() do if p.id == ${crown.id} then to = p end end; if t and to then edit.transfer_city(t, to) end`);
      shiftFavour({ [c.house]: -20 }, "the royal host");
      shiftFavour(Object.fromEntries((c.allies ?? []).map((id) => [id, 6])), "the royal host");
      deed(kingDeeds.tagsFor("realm", "sack"), { act: false, place: cityName(c.city) });
      record({ turn, kind: "sack", text: `${cityName(c.city)} falls to the royal host: ${why} ${houseFor(foe).name} has learned what the crown's anger costs.`, city: c.city });
    } else {
      send(`lua cmd local n = 0; for p in players_iterate() do if p.id == ${crown.id} then for u in p:units_iterate() do if n < 5 and u.utype:rule_name() ~= "Workers" then edit.unit_kill(u, "killed", nil); n = n + 1 end end end end`);
      shiftFavour(Object.fromEntries(greatHouses().filter((p) => p.id !== c.house).map((p) => [p.id, -3])), "the royal host");
      shiftFavour({ [c.house]: -10 }, "the royal host");
      record({ turn, kind: "battle", text: `The royal host breaks against the walls of ${cityName(c.city)}: ${why} ${houseFor(foe).name} holds, and the realm sees a King who can be refused.`, city: c.city });
    }
  }
  chron.saveMeta(meta);
}

// The royal host marches on a town for a ruling the court already paid for: the
// decree's own march (crown.js), its fee waived, and the same campaign.
export function marchOn(ctx, cityId) {
  const { world, meta, send, shiftFavour, favourOf, causeOf } = ctx;
  if (!world) return;
  const r = decree({ action: "march", city: cityId, price: 0, favourOf, causeOf, marching: (city) => (meta.campaigns ?? []).some((x) => x.city === city) }, { ...world, players: world.players.map((p) => houseFor(p).crown ? { ...p, gold: 1e9 } : p) });
  if (r.error) { console.error("march:", r.error); return; }
  (r.lua ?? []).slice(1).forEach((l) => send(`lua cmd ${l}`));
  shiftFavour(r.favour, "the royal host");
  if (r.march) startCampaign(ctx, r.march);
}
