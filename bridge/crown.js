// The Crown: royal treasury (the Crown player's gold in Freeciv), the tithe on
// the great houses, each house's favour toward the crown, and royal decrees
// that cost gold and move favour. Each decree becomes Freeciv Lua.

import { cityName, houseFor } from "./narrator.js";
import { greatHouses } from "./realm.js";
import { BANDS } from "./favour.js";
import * as Lua from "./lua.js";
import fs from "node:fs";
// The crown's money in one place (the purse, the tithe's yield, wear, thin): data/economy.json.
export const ECONOMY = JSON.parse(fs.readFileSync(new URL("./data/economy.json", import.meta.url), "utf8"));

// The decrees, their prices and words: data/decrees.json (one place for both the
// bridge and the town card).
export const DECREES = Object.fromEntries(Object.entries(JSON.parse(fs.readFileSync(new URL("./data/decrees.json", import.meta.url), "utf8"))).filter(([k]) => k !== "_"));

// When the banners were last called: the houses won't answer twice in a year.
let bannersCalled = -99;
// Whether the houses would answer the banners now (once a year).
export const bannersReady = (turn) => turn - bannersCalled >= 4;

const BUILDABLE = { temple: "Temple", granary: "Granary", walls: "City Walls", market: "Marketplace", aqueduct: "Aqueduct", barracks: "Barracks" };
// The build decree's key for a building's own name ("Marketplace" -> "market"), or null.
export const buildKey = (name) => Object.keys(BUILDABLE).find((k) => BUILDABLE[k] === name) ?? null;

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
  return 2 + (crown.cities ?? 0) * 2 + Math.floor(Math.max(0, crown.gold) * ECONOMY.upkeepShare);
}

// A tithe this heavy grasps: the ledger's tithe_high, and the towns mutter (view.js townStates).
export const TITHE_HIGH = ECONOMY.tithe.high;  // data/economy.json

export function titheLua(world, rate) {
  const crown = crownOf(world);
  if (!crown) return { lua: [], total: 0, takes: {}, upkeep: 0 };
  const takes = {};
  let total = 0;
  const lua = [];
  const { perSize, housePays } = ECONOMY.tithe;
  for (const p of world.players) {
    const h = houseFor(p);
    if (h.wild || h.crown) continue;
    // The tithe is the rate of what a house's towns yield (their size), a quarter
    // each season: a share of the houses' own small purses brought the crown next
    // to nothing. A house hands over what it can spare from its purse; the rest is
    // taken at its town gates.
    const size = (world.cities ?? []).filter((c) => c.owner === p.id).reduce((n, c) => n + (c.size ?? 0), 0);
    const take = rate > 0 ? Math.floor((size * perSize * rate) / 4) : 0;
    if (take <= 0) continue;
    takes[p.id] = take;
    total += take;
    const paid = Math.min(take, Math.floor(Math.max(0, p.gold ?? 0) * housePays));
    if (paid > 0) lua.push(Lua.gold(p.id, -paid));
  }
  const upkeep = Math.min(crownUpkeep(crown), Math.max(0, crown.gold + total));
  const net = total - upkeep;
  if (net !== 0) lua.push(Lua.gold(crown.id, net));
  return { lua, total, takes, upkeep };
}

// The decrees, one handler each. A new decree is a row in data/decrees.json plus
// a handler here; x is what decree() reckoned for it (the crown, the price, the
// town and its lord).
const HANDLERS = {
  banners(x) {
    const { cmd, world, crown, cost, pay } = x;
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
  },
  relief(x) {
    const { cost, pay, c, owner, lord, town } = x;
    if (!c) return { error: "choose a town" };
    return {
      cost, favour: { [owner.id]: 12 },
      text: `By royal decree, wagons of grain roll into ${town}. ${lord} remembers the King's mercy.`,
      // (It used to send Migrants to join the town: one more mouth, a worse famine.)
      lua: [pay], relieved: c.id,
    };
  },
  gift(x) {
    const { cost, pay, owner, lord } = x;
    if (!owner) return { error: "choose a town or house" };
    return {
      cost, favour: { [owner.id]: 10 },
      text: `The King sends a chest of gold to ${lord}.`,
      lua: [pay, Lua.gold(owner.id, cost)],
    };
  },
  sellswords(x) {
    const { world, crown, cost, pay } = x;
    // Free companies, paid in gold: a thousand men at Kingsmere, owing nothing to any house.
    const seat = world.cities.find((x) => x.owner === crown.id && x.capital);
    if (!seat) return { error: "the crown has no seat" };
    return { cost, favour: {}, text: "The King hires sellswords: a thousand men of the free companies march into Kingsmere, loyal to his gold.",
      lua: [pay, `local c = find.city(nil, ${seat.id}); if c then for i = 1, 5 do edit.create_unit(c.owner, c.tile, find.unit_type(i % 2 == 0 and "Knights" or "Pikemen"), 1, c, -1) end end`] };
  },
  levy(x) {
    const { world, crown, cost, pay } = x;
    const seat = world.cities.find((x) => x.owner === crown.id && x.capital);
    if (!seat) return { error: "the crown has no seat" };
    return {
      cost, favour: {},
      text: "The King raises a levy: 600 men, pikemen and knights, muster at Kingsmere.",
      lua: [pay, `local c = find.city(nil, ${seat.id}); if c then for _, n in ipairs({"Pikemen", "Pikemen", "Knights"}) do edit.create_unit(c.owner, c.tile, find.unit_type(n), 1, c, -1) end end`],
    };
  },
  build(x) {
    const { cmd, cost, pay, c, owner, lord, town, inCity } = x;
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
  },
  feast(x) {
    const { world, cost, pay, owner, lord } = x;
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
  },
  ward(x) {
    const { world, cost, pay, c, cmd } = x;
    // The heir lives at court: the house cannot rise while the King holds them.
    const owner = c ? world.players.find((p) => p.id === c.owner) : null;
    if (!owner || houseFor(owner).crown) return { error: "choose a great house's town" };
    if ((cmd.warded ?? (() => false))(owner.id)) return { error: `${houseFor(owner).name}'s heir is already at court` };
    return { cost, favour: { [owner.id]: DECREES.ward.favour ?? -15 }, lua: [pay], ward: owner.id,
      text: `${houseFor(owner).name}'s heir rides to Kingsmere as the King's ward. While the child lives at court, the house will not rise, and it will not forget who took them.` };
  },
  buyoff(x) {
    const { cmd, world, cost, pay } = x;
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
  },
  back(x) {
    const { cmd, world, cost, pay, owner } = x;
    // The King takes a side: gold to the house he favours (the town chosen is
    // theirs). They love him for it; the other side will not forget.
    const to = world.players.find((p) => p.id === Number(cmd.to));
    if (!owner || !to || houseFor(owner).crown || houseFor(to).crown) return { error: "choose two great houses" };
    return { cost, favour: { [owner.id]: 12, [to.id]: -12 }, lua: [pay, Lua.gold(owner.id, cost)],
      text: `The King backs ${houseFor(owner).name} against ${houseFor(to).name}: crowns for swords, and every lord at court knows whose side the crown is on.` };
  },
  settle(x) {
    const { cmd, world, cost, pay, owner } = x;
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
  },
  peace(x) {
    const { cmd, world, crown, c, owner } = x;
    // The King commands two warring houses to lay down arms. Each obeys by its
    // favour: if both are warm enough, the soldiers camped by the other's towns
    // go home and both lose their taste for war a while (the engine still
    // counts them at war; the fighting stops). A cold house refuses to his face.
    if (!c) return { error: "choose a town of one of the two houses" };
    const to = world.players.find((p) => p.id === Number(cmd.to));
    if (!to || to.id === owner.id || houseFor(to).wild || houseFor(to).crown || houseFor(owner).crown) return { error: "choose two great houses" };
    const fav = cmd.favourOf ?? (() => 60);
    const a = houseFor(owner).name, b = houseFor(to).name;
    // One peace verb, "Make them stop" (the cut list: peace, settle and back were three): it always
    // holds, but the colder the two houses are, the dearer the blood-price the crown pays, and a cold
    // house resents being made to stop where a warm one is grateful.
    const cost = Math.round(x.cost * peaceScale(fav(owner.id), fav(to.id)));
    if (crown.gold < cost) return { error: `the treasury holds ${(crown.gold * 100).toLocaleString("en-GB")} crowns; this costs ${(cost * 100).toLocaleString("en-GB")}` };
    const pay = Lua.gold(crown.id, -cost);
    const cold = [owner, to].filter((p) => fav(p.id) < (DECREES.peace.coldBelow ?? 40));
    const home = (x, y) => `for p in players_iterate() do if p.id == ${x} then for u in p:units_iterate() do local r = u.utype:rule_name(); if r ~= "Workers" and r ~= "Settlers" then for q in players_iterate() do if q.id == ${y} then for c in q:cities_iterate() do if u.tile:sq_distance(c.tile) <= 9 then edit.unit_kill(u, "killed", nil); break end end end end end end end end`;
    const favour = Object.fromEntries([owner, to].map((p) => [p.id, cold.includes(p) ? -3 : 2]));
    const grudging = cold.length ? ` ${cold.map((p) => houseFor(p).name).join(" and ")} ${cold.length > 1 ? "obey" : "obeys"} with bad grace, and the crown pays the blood-price.` : " Both bow to the crown.";
    return { cost, favour, lua: [pay, home(owner.id, to.id), home(to.id, owner.id)], text: `The King tells ${a} and ${b} to stop.${grudging} They pull their hosts back from each other's towns, and riders carry the King's word to both houses: a truce for sixteen seasons.`, truce: [owner.id, to.id] };
  },
  marriage(x) {
    const { cmd, world, cost, pay, c, owner, lord } = x;
    // A royal match binds two great houses by blood: both thank the crown,
    // and the bond holds them from each other's throats (the court's truce;
    // the names and the vows come from the court, in server.js).
    if (!c) return { error: "choose a town of one of the two houses" };
    const to = world.players.find((p) => p.id === Number(cmd.to));
    if (!to || to.id === owner.id || houseFor(to).wild || houseFor(to).crown || houseFor(owner).crown) return { error: "choose two great houses to wed" };
    return { cost, favour: { [owner.id]: 8, [to.id]: 8 }, text: `By the King's word, ${lord} and ${houseFor(to).name} are to be joined by marriage.`, lua: [pay], pact: [owner.id, to.id] };
  },
  grant(x) {
    const { cmd, world, c, owner, lord, town } = x;
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
  },
  alliance(x) {
    const { cmd, cost, pay, owner, lord } = x;
    // An oath: the house fights the King's wars and won't rise against him
    // for four years. A house that doesn't trust the crown won't swear it.
    if (!owner || houseFor(owner).crown || houseFor(owner).wild) return { error: "choose a great house's town" };
    const f = (cmd.favourOf ?? (() => 60))(owner.id);
    if (f < BANDS.sworn) return { error: `${lord} will not swear an oath to a crown it does not trust (favour ${Math.round(f)}; it needs ${BANDS.sworn}). Win them first.` };
    if ((cmd.sworn ?? (() => false))(owner.id)) return { error: `${lord} is already sworn to the crown` };
    return { cost, lua: [pay], favour: { [owner.id]: 5 }, alliance: owner.id,
      text: `${lord} kneels and swears an oath to the crown: its swords are the King's for four years, and it will not rise against him while the oath holds.` };
  },
  promise(x) {
    const { cmd, world, owner, lord } = x;
    // The answer a broke crown can always give (gameplay review #1): a seat at the King's council,
    // paid for in the favour of the house he had favoured most (cmd.to), which thought it theirs.
    const d = DECREES.promise;
    const rival = world.players.find((p) => p.id === Number(cmd.to));
    if (!owner || houseFor(owner).crown || houseFor(owner).wild) return { error: "choose a great house's town" };
    const favour = { [owner.id]: d.favour ?? 10, ...(rival && rival.id !== owner.id ? { [rival.id]: d.rival ?? -8 } : {}) };
    return { cost: 0, favour, lua: [],
      text: `The King promises ${lord} a seat at his council.${rival && rival.id !== owner.id ? ` ${houseFor(rival).name} had thought that seat was theirs.` : ""}` };
  },
  cede(x) {
    const { cmd, world, crown, c, town } = x;
    // A royal town for the pretender's claim (gameplay review #1): their host goes home with
    // something to show for it, and every house marks what rising against the crown bought.
    const d = DECREES.cede;
    const to = world.players.find((p) => p.id === Number(cmd.to));
    if (!c || c.owner !== crown.id) return { error: "choose a town of the crown's" };
    if (c.capital) return { error: "Kingsmere is the crown itself; it cannot be ceded" };
    if (!to || houseFor(to).crown || houseFor(to).wild) return { error: "choose a great house to cede it to" };
    const u = cmd.usurper;
    const at = cmd.seat;
    const home = u && u.stage !== "none" && u.house === to.id && at ? `for p in players_iterate() do if p.id == ${to.id} then for u in p:units_iterate() do local r = u.utype:rule_name(); if r ~= "Workers" and r ~= "Settlers" and math.sqrt(u.tile:sq_distance(find.tile(${at.x}, ${at.y}))) <= 6 then edit.unit_kill(u, "killed", nil) end end end end` : null;
    const others = Object.fromEntries(greatHouses(world).filter((p) => p.id !== to.id).map((p) => [p.id, d.others ?? -2]));
    return { cost: 0, favour: { [to.id]: d.favour ?? 25, ...others }, lua: [Lua.transferCity(c.id, to.id), home].filter(Boolean), endUsurper: !!home,
      text: `The King cedes ${town} to ${houseFor(to).name} for their claim. ${home ? "Their host goes home with a town to show for it, and" : "And"} every house marks what rising against the crown can buy.` };
  },
  march(x) {
    const { cmd, world, crown, cost, pay, c, owner, lord, town } = x;
    // The royal host marches on a town, and lays siege when it reaches the walls (hosts.js, then
    // campaigns.js): one verb, one army (gameplay review #7). The King's sworn houses send men
    // with it; two seasons before the walls the town falls to the crown, or the host breaks.
    if (!c || !owner || houseFor(owner).crown || houseFor(owner).wild) return { error: "choose a great house's town to march on" };
    if ((cmd.marching ?? (() => false))(c.id)) return { error: `the royal host is already before ${town}` };
    const d = DECREES.march;
    const others = greatHouses(world).filter((p) => p.id !== owner.id);
    const favour = { [owner.id]: d.favour ?? -25, ...Object.fromEntries(others.map((p) => [p.id, d.others ?? -2])) };
    // A ruling that sends the host (a siege plea answered) raises one at the town, as it always did.
    if (cmd.spawn) return { cost, lua: [pay, `realm_host(realm_find_player(${crown.id}), ${c.x}, ${c.y}, {"Pikemen","Knights","Archers","Catapult"}, 8)`], favour, march: { city: c.id, house: owner.id },
      text: `The royal host marches on ${town}. ${lord} calls every man to its walls, and every house in the realm watches.` };
    const h = cmd.host;
    if (!h) return { error: "the crown has no host to march" };
    return { cost, lua: [pay], favour, hostMarch: { host: h.id, city: c.id, house: owner.id },
      text: `The royal host, ${h.men.toLocaleString("en-US")} men, marches on ${town}. ${lord} calls every man to its walls, and every house in the realm watches.` };
  },
};

// The price of making two warring houses stop, as a multiple of the base: each point under coldBelow
// adds 1/coldBelow, up to coldMost times (data/decrees.json peace).
export function peaceScale(fa, fb) {
  const p = DECREES.peace ?? {};
  const below = p.coldBelow ?? 40;
  const cold = Math.max(0, below - fa) + Math.max(0, below - fb);
  return Math.min(p.coldMost ?? 2, 1 + cold / below);
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

  if (d.off) return { error: "the King no longer gives that order" };
  const h = Object.hasOwn(HANDLERS, cmd.action) ? HANDLERS[cmd.action] : null;
  if (!h) return { error: "unknown decree" };
  return h({ cmd, world, crown, cost, pay, c, owner, lord, town, inCity });
}
