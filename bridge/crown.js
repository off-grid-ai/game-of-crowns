// The Crown: royal treasury (the Crown player's gold in Freeciv), the tithe on
// the great houses, each house's favour toward the crown, and royal decrees
// that cost gold and move favour. Each decree becomes Freeciv Lua.

import { cityName, houseFor } from "./narrator.js";
import { greatHouses } from "./realm.js";
import { BANDS } from "./favour.js";
import * as Lua from "./lua.js";

// The decrees, their prices and words: data/decrees.json (one place for both the
// bridge and the town card).
import fs from "node:fs";
export const DECREES = Object.fromEntries(Object.entries(JSON.parse(fs.readFileSync(new URL("./data/decrees.json", import.meta.url), "utf8"))).filter(([k]) => k !== "_"));

// When the banners were last called: the houses won't answer twice in a year.
let bannersCalled = -99;
// Whether the houses would answer the banners now (once a year).
export const bannersReady = (turn) => turn - bannersCalled >= 4;

const BUILDABLE = { temple: "Temple", granary: "Granary", walls: "City Walls", market: "Marketplace", aqueduct: "Aqueduct", barracks: "Barracks" };

function crownOf(world) {
  return world?.players?.find((p) => houseFor(p).crown);
}

export function clampFavour(v) {
  return Math.max(0, Math.min(100, Math.round(v)));
}

// The tithe: each season the crown takes `rate` of what every great house
// EARNED since the last (its treasury's rise), not of its savings: a tithe on
// savings, taken every season, drained the houses to nothing and piled their
// whole wealth up at Kingsmere. Higher tithes still cost favour every season.
//
// And the crown pays its way: the court, the royal host's wages and its
// castles' keep, plus the cost of a great treasury itself (stewards, gifts,
// loans called in), so royal gold is a choice to spend, not a heap that grows.

// The court and the castles' keep, plus a little for a great treasury's
// stewards. Not the soldiers: the engine already charges a town for its units,
// and charging again left the crown at 0 crowns for good, unable to decree.
export function crownUpkeep(crown) {
  return 2 + (crown.cities ?? 0) * 2 + Math.floor(Math.max(0, crown.gold) * 0.01);
}

export function titheLua(world, rate) {
  const crown = crownOf(world);
  if (!crown) return { lua: [], total: 0, takes: {}, upkeep: 0 };
  const takes = {};
  let total = 0;
  const lua = [];
  for (const p of world.players) {
    const h = houseFor(p);
    if (h.wild || h.crown) continue;
    // The tithe is a share of each house's treasury: the rate a year, a quarter
    // of it each season. (A share of their gains came to nothing: the houses
    // spend as fast as they earn, so the crown starved while favour still wore.)
    const take = rate > 0 && p.gold > 0 ? Math.floor((p.gold * rate) / 4) : 0;
    if (take <= 0) continue;
    takes[p.id] = take;
    total += take;
    lua.push(Lua.gold(p.id, -take));
  }
  const upkeep = Math.min(crownUpkeep(crown), Math.max(0, crown.gold + total));
  const net = total - upkeep;
  if (net !== 0) lua.push(Lua.gold(crown.id, net));
  return { lua, total, takes, upkeep };
}

// Returns { error } or { text, lua, cost, favour: {playerId: delta} }.
export function decree(cmd, world) {
  const crown = crownOf(world);
  if (!crown) return { error: "the crown has no seat" };
  const d = DECREES[cmd.action];
  if (!d) return { error: "unknown decree" };
  // What the decree costs now: the server scales it with the treasury (cmd.price).
  const cost = Math.max(d.cost, Math.round(cmd.price ?? d.cost));
  if (crown.gold < cost) return { error: `the treasury holds ${(crown.gold * 100).toLocaleString("en-GB")} crowns; this costs ${(cost * 100).toLocaleString("en-GB")}` };
  const pay = Lua.gold(crown.id, -cost);
  const c = world.cities.find((x) => x.id === Number(cmd.city));
  const owner = c ? world.players.find((p) => p.id === c.owner) : world.players.find((p) => p.id === Number(cmd.house));
  const lord = owner ? houseFor(owner).name : "";
  const town = c ? cityName(c.id) : "";
  const inCity = (body) => Lua.inCity(c?.id, body);

  switch (cmd.action) {
    case "banners": {
      // The King summons every great house to send men to Kingsmere. Each
      // answers by its favour: the loyal march at once, the wary send a few
      // with excuses, the cold refuse to his face. One decree, and the King
      // learns who he can count on; the men who come join the royal host.
      const seat = world.cities.find((x) => x.owner === crown.id && x.capital);
      if (!seat) return { error: "the crown has no seat to muster at" };
      const since = (world.turn ?? 0) - bannersCalled;
      if (since < 4) return { error: `the banners were called ${since === 0 ? "this season" : since === 1 ? "last season" : `${since} seasons ago`}; the houses won't answer again before the year is out` };
      bannersCalled = world.turn ?? 0;
      const fav = cmd.favourOf ?? (() => 60);
      const came = [], few = [], refused = [];
      const lua = [pay];
      const favour = {};
      let men = 0;
      for (const p of world.players) {
        const h = houseFor(p);
        if (h.wild || h.crown || !world.cities.some((x) => x.owner === p.id)) continue;
        const f = fav(p.id);
        const name = h.name.replace("House ", "");
        // What a house sends scales with its strength: a quarter of a loyal
        // house's companies, an eighth of a willing one's, at least one.
        // A house sworn to the crown answers gladly, whatever its mood.
        const oath = (cmd.sworn ?? (() => false))(p.id);
        const share = f >= BANDS.loyal || oath ? 0.25 : f >= BANDS.steady ? 0.125 : 0;
        const n = share ? Math.max(1, Math.round((p.units ?? 0) * share)) : 0;
        const sent = `${name} ${(n * 200).toLocaleString("en-US")}`;
        if (f >= BANDS.loyal || oath) came.push(sent);
        else if (n) few.push(sent);
        else refused.push(name);
        // A house that answers is bound closer by fighting beside the crown; one
        // that refuses has defied the King to his face and cools further.
        favour[p.id] = f >= BANDS.loyal ? 3 : n ? 1 : -3;  // gladly, grudgingly, or not at all
        if (n) {
          men += n;
          lua.push(`for p in players_iterate() do if p.id == ${p.id} then local i = 0; for u in p:units_iterate() do local r = u.utype:rule_name(); if i < ${n} and r ~= "Workers" and r ~= "Settlers" and r ~= "Explorer" then edit.unit_kill(u, "killed", nil); i = i + 1 end end end end`);
        }
      }
      if (men) lua.push(`local c = find.city(nil, ${seat.id}); if c then for i = 1, ${men} do edit.create_unit(c.owner, c.tile, find.unit_type(i % 2 == 0 and "Knights" or "Pikemen"), 1, c, -1) end end`);
      const list = (xs) => xs.length > 1 ? `${xs.slice(0, -1).join(", ")} and ${xs.at(-1)}` : xs[0];
      const parts = [];
      const verb = (xs, one, many) => (xs.length > 1 ? many : one);
      // Each house by the men it sent: gladly (loyal) or grudgingly (willing).
      if (came.length) parts.push(`gladly: ${list(came)}`);
      if (few.length) parts.push(`grudgingly: ${list(few)}`);
      if (refused.length) parts.push(`${list(refused)} ${verb(refused, "refuses", "refuse")} the summons`);
      // The coldest refusal says why, from what that house has not forgotten.
      const firstNo = world.players.find((p) => houseFor(p).name.replace("House ", "") === refused[0]);
      const why = firstNo && cmd.causeOf ? cmd.causeOf(firstNo.id) : "";
      if (why) parts.push(`${refused[0]} has not forgotten ${why}`);
      return { cost, favour, text: `The King calls the banners. ${parts.join("; ").replace(/^./, (c) => c.toUpperCase())}.${men ? ` ${(men * 200).toLocaleString("en-US")} men march to Kingsmere.` : " No one marches."}`, lua, refused };
    }
    case "relief":
      if (!c) return { error: "choose a town" };
      return {
        cost, favour: { [owner.id]: 12 },
        text: `By royal decree, wagons of grain roll into ${town}. ${lord} remembers the King's mercy.`,
        // (It used to send Migrants to join the town: one more mouth, a worse famine.)
        lua: [pay], relieved: c.id,
      };
    case "gift":
      if (!owner) return { error: "choose a town or house" };
      return {
        cost, favour: { [owner.id]: 10 },
        text: `The King sends a chest of gold to ${lord}.`,
        lua: [pay, Lua.gold(owner.id, cost)],
      };
    case "sellswords": {
      // Free companies, paid in gold: a thousand men at Kingsmere, owing nothing to any house.
      const seat = world.cities.find((x) => x.owner === crown.id && x.capital);
      if (!seat) return { error: "the crown has no seat" };
      return { cost, favour: {}, text: "The King hires sellswords: a thousand men of the free companies march into Kingsmere, loyal to his gold.",
        lua: [pay, `local c = find.city(nil, ${seat.id}); if c then for i = 1, 5 do edit.create_unit(c.owner, c.tile, find.unit_type(i % 2 == 0 and "Knights" or "Pikemen"), 1, c, -1) end end`] };
    }
    case "levy": {
      const seat = world.cities.find((x) => x.owner === crown.id && x.capital);
      if (!seat) return { error: "the crown has no seat" };
      return {
        cost, favour: {},
        text: "The King raises a levy: 600 men, pikemen and knights, muster at Kingsmere.",
        lua: [pay, `local c = find.city(nil, ${seat.id}); if c then for _, n in ipairs({"Pikemen", "Pikemen", "Knights"}) do edit.create_unit(c.owner, c.tile, find.unit_type(n), 1, c, -1) end end`],
      };
    }
    case "build": {
      if (!c) return { error: "choose a town" };
      const b = BUILDABLE[cmd.building];
      if (!b) return { error: "unknown building" };
      // "new city walls", "a granary", "an aqueduct": the building as it reads.
      const what = b.toLowerCase();
      const thing = what.endsWith("s") ? `new ${what}` : `${/^[aeiou]/.test(what) ? "an" : "a"} ${what}`;
      // In the King's own town the crown builds for itself: nobody to thank.
      const own = houseFor(owner).crown;
      // The King's own works rise over two seasons on the town's site (server.js royal works);
      // a house's town builds the gift at once, and so do the sept and aqueduct the Hand calls
      // for against plague and unrest (they were always at once, and a crisis can't wait).
      if (own && (cmd.works ?? {})[c.id]) return { error: `the King's masons are already at work in ${town}` };
      if (own && !["Temple", "Aqueduct"].includes(b)) return {
        cost, favour: {},
        text: `The King's masons break ground on ${thing} in ${town}. It will stand in two seasons.`,
        lua: [pay], work: { city: c.id, building: b },
      };
      return {
        cost, favour: own ? {} : { [owner.id]: 8 },
        text: own ? `The King raises ${thing} in ${town} at the crown's cost.` : `The crown pays for ${thing} in ${town}. ${lord} is grateful.`,
        lua: [pay, inCity(`local b = find.building_type("${b}"); if b and not c:has_building(b) then edit.create_building(c, b) end`)],
      };
    }
    case "feast":
      if (!owner) return { error: "choose a town or house" };
      // At the King's own court: every great house is his guest.
      if (houseFor(owner).crown) {
        const guests = Object.fromEntries(world.players.filter((p) => !houseFor(p).crown && !houseFor(p).wild && p.id !== owner.id).map((p) => [p.id, 5]));
        return { cost, favour: guests, text: "The King holds a feast at court. Every great house sends someone; tempers cool, for now.", lua: [pay] };
      }
      return {
        cost, favour: { [owner.id]: 15 },
        text: `A feast at Kingsmere in honour of ${lord}. Wine flows; old slights are forgotten, for now.`,
        lua: [pay],
      };
    case "ward": {
      // The heir lives at court: the house cannot rise while the King holds them.
      const owner = c ? world.players.find((p) => p.id === c.owner) : null;
      if (!owner || houseFor(owner).crown) return { error: "choose a great house's town" };
      return { cost, favour: { [owner.id]: -5 }, lua: [pay], ward: owner.id,
        text: `${houseFor(owner).name}'s heir rides to Kingsmere as the King's ward. While the child lives at court, the house will not rise.` };
    }
    case "buyoff": {
      // Gold for the pretender's claim: their host about Kingsmere goes home and
      // the whispers stop, at a price every other house will remember.
      const u = cmd.usurper;
      const who = world.players.find((p) => p.id === u?.house);
      if (!u || u.stage === "none" || !who) return { error: "no pretender threatens the throne" };
      const at = cmd.seat;
      const home = at ? `for p in players_iterate() do if p.id == ${who.id} then for u in p:units_iterate() do local r = u.utype:rule_name(); if r ~= "Workers" and r ~= "Settlers" and math.sqrt(u.tile:sq_distance(find.tile(${at.x}, ${at.y}))) <= 6 then edit.unit_kill(u, "killed", nil) end end end end` : null;
      const lord = houseFor(who).name;
      const others = Object.fromEntries(world.players.filter((p) => p.id !== who.id && !houseFor(p).wild && !houseFor(p).crown).map((p) => [p.id, -2]));
      return { cost, favour: { [who.id]: 25, ...others }, lua: [pay, home].filter(Boolean), endUsurper: true,
        text: `The King buys off ${lord}: gold for their claim. Their host breaks camp and goes home, and the other houses mutter that treason pays.` };
    }
    case "back": {
      // The King takes a side: gold to the house he favours (the town chosen is
      // theirs). They love him for it; the other side will not forget.
      const to = world.players.find((p) => p.id === Number(cmd.to));
      if (!owner || !to || houseFor(owner).crown || houseFor(to).crown) return { error: "choose two great houses" };
      return { cost, favour: { [owner.id]: 12, [to.id]: -12 }, lua: [pay, Lua.gold(owner.id, cost)],
        text: `The King backs ${houseFor(owner).name} against ${houseFor(to).name}: crowns for swords, and every lord at court knows whose side the crown is on.` };
    }
    case "settle": {
      // Another house keeps the King's peace with its own men: the warring hosts
      // are turned home whether or not they love the crown; the peacekeeper is
      // honoured, the two warring houses resent the meddling.
      const to = world.players.find((p) => p.id === Number(cmd.to));
      // The keeper: the most loyal great house not in this war.
      const fav = cmd.favourOf ?? (() => 50);
      const keeper = world.players.filter((p) => p.id !== owner?.id && p.id !== Number(cmd.to) && !houseFor(p).wild && !houseFor(p).crown && p.cities > 0)
        .sort((x, y) => fav(y.id) - fav(x.id))[0];
      if (!owner || !to || !keeper) return { error: "choose two warring houses and a house to settle it" };
      const home = (x, y) => `for p in players_iterate() do if p.id == ${x} then for u in p:units_iterate() do local r = u.utype:rule_name(); if r ~= "Workers" and r ~= "Settlers" then for q in players_iterate() do if q.id == ${y} then for c in q:cities_iterate() do if u.tile:sq_distance(c.tile) <= 9 then edit.unit_kill(u, "killed", nil); break end end end end end end end end`;
      const k = houseFor(keeper).name;
      return { cost, favour: { [keeper.id]: 6, [owner.id]: -3, [to.id]: -3 }, lua: [pay, home(owner.id, to.id), home(to.id, owner.id)], truce: [owner.id, to.id],
        text: `At the King's word, ${k} rides between ${houseFor(owner).name} and ${houseFor(to).name}. ${k}'s men turn back the hosts near their towns, and riders carry the King's word to both houses: a truce for sixteen seasons.` };
    }
    case "peace": {
      // The King commands two warring houses to lay down arms. Each obeys by its
      // favour: if both are warm enough, the soldiers camped by the other's towns
      // go home and both lose their taste for war a while (the engine still
      // counts them at war; the fighting stops). A cold house refuses to his face.
      if (!c) return { error: "choose a town of one of the two houses" };
      const to = world.players.find((p) => p.id === Number(cmd.to));
      if (!to || to.id === owner.id || houseFor(to).wild || houseFor(to).crown || houseFor(owner).crown) return { error: "choose two great houses" };
      const fav = cmd.favourOf ?? (() => 60);
      const a = houseFor(owner).name, b = houseFor(to).name;
      const cold = [owner, to].filter((p) => fav(p.id) < 40);
      if (cold.length) {
        const who = cold.map((p) => houseFor(p).name).join(" and ");
        return { cost, favour: Object.fromEntries(cold.map((p) => [p.id, -5])), lua: [pay], text: `The King commands peace between ${a} and ${b}. ${who} ${cold.length > 1 ? "refuse" : "refuses"} the King's peace, and the war goes on.` };
      }
      const home = (x, y) => `for p in players_iterate() do if p.id == ${x} then for u in p:units_iterate() do local r = u.utype:rule_name(); if r ~= "Workers" and r ~= "Settlers" then for q in players_iterate() do if q.id == ${y} then for c in q:cities_iterate() do if u.tile:sq_distance(c.tile) <= 9 then edit.unit_kill(u, "killed", nil); break end end end end end end end end`;
      return { cost, favour: { [owner.id]: 2, [to.id]: 2 }, lua: [pay, home(owner.id, to.id), home(to.id, owner.id)], text: `The King commands peace between ${a} and ${b}. Both bow to the crown and pull their hosts back from each other's towns. Riders carry the King's word to both houses: a truce for sixteen seasons.`, truce: [owner.id, to.id] };
    }
    case "marriage": {
      // A royal match binds two great houses by blood: both thank the crown,
      // and the bond holds them from each other's throats (the court's truce;
      // the names and the vows come from the court, in server.js).
      if (!c) return { error: "choose a town of one of the two houses" };
      const to = world.players.find((p) => p.id === Number(cmd.to));
      if (!to || to.id === owner.id || houseFor(to).wild || houseFor(to).crown || houseFor(owner).crown) return { error: "choose two great houses to wed" };
      return { cost, favour: { [owner.id]: 8, [to.id]: 8 }, text: `By the King's word, ${lord} and ${houseFor(to).name} are to be joined by marriage.`, lua: [pay], pact: [owner.id, to.id] };
    }
    case "grant": {
      if (!c) return { error: "choose a town" };
      const to = world.players.find((p) => p.id === Number(cmd.to));
      if (!to || to.id === owner.id || houseFor(to).wild) return { error: "choose a house to grant it to" };
      if (c.capital) return { error: "a house's seat cannot be granted away" };
      // One of the crown's own towns, given as a reward.
      if (houseFor(owner).crown) {
        return {
          cost: 0, favour: { [to.id]: 25 },
          text: `The King grants ${town} to ${houseFor(to).name}, a reward for loyal service.`,
          lua: [Lua.transferCity(c.id, to.id)],
        };
      }
      return {
        cost: 0, favour: { [owner.id]: -30, [to.id]: 20 },
        text: `By royal decree, ${town} is taken from ${lord} and granted to ${houseFor(to).name}. ${lord} will not forget.`,
        lua: [Lua.transferCity(c.id, to.id)],
      };
    }
    case "alliance": {
      // An oath: the house fights the King's wars and won't rise against him
      // for four years. A house that doesn't trust the crown won't swear it.
      if (!owner || houseFor(owner).crown || houseFor(owner).wild) return { error: "choose a great house's town" };
      const f = (cmd.favourOf ?? (() => 60))(owner.id);
      if (f < BANDS.sworn) return { error: `${lord} will not swear an oath to a crown it does not trust (favour ${Math.round(f)}; it needs ${BANDS.sworn}). Win them first.` };
      if ((cmd.sworn ?? (() => false))(owner.id)) return { error: `${lord} is already sworn to the crown` };
      return { cost, lua: [pay], favour: { [owner.id]: 5 }, alliance: owner.id,
        text: `${lord} kneels and swears an oath to the crown: its swords are the King's for four years, and it will not rise against him while the oath holds.` };
    }
    case "march": {
      // The royal host marches on a town. The King's sworn houses send men with
      // it; in two seasons the town falls to the crown, or the host breaks.
      if (!c || !owner || houseFor(owner).crown || houseFor(owner).wild) return { error: "choose a great house's town to march on" };
      if ((cmd.marching ?? (() => false))(c.id)) return { error: `the royal host is already before ${town}` };
      const others = greatHouses(world).filter((p) => p.id !== owner.id);
      return { cost, lua: [pay, `realm_host(realm_find_player(${crown.id}), ${c.x}, ${c.y}, {"Pikemen","Knights","Archers","Catapult"}, 8)`],
        favour: { [owner.id]: -25, ...Object.fromEntries(others.map((p) => [p.id, -2])) }, march: { city: c.id, house: owner.id },
        text: `The royal host marches on ${town}. ${lord} calls every man to its walls, and every house in the realm watches.` };
    }
    default:
      return { error: "unknown decree" };
  }
}
