// The Crown: royal treasury (the Crown player's gold in Freeciv), the tithe on
// the great houses, each house's favour toward the crown, and royal decrees
// that cost gold and move favour. Each decree becomes Freeciv Lua.

import { cityName, houseFor } from "./narrator.js";

export const DECREES = {
  relief: { cost: 120, label: "Send grain to a starving town" },
  gift: { cost: 150, label: "Gift gold to a house" },
  levy: { cost: 200, label: "Raise a royal levy" },
  build: { cost: 180, label: "Raise a building" },
  grant: { cost: 0, label: "Grant this castle to another house" },
  feast: { cost: 100, label: "Hold a feast in the lord's honour" },
};

const BUILDABLE = { temple: "Temple", granary: "Granary", walls: "City Walls", market: "Marketplace", aqueduct: "Aqueduct" };

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
const lastGold = {};  // player id -> treasury after last season's tithe

export function crownUpkeep(crown) {
  return 5 + (crown.units ?? 0) + (crown.cities ?? 0) * 3 + Math.floor(Math.max(0, crown.gold) * 0.02);
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
    const earned = lastGold[p.id] === undefined ? 0 : p.gold - lastGold[p.id];
    const take = rate > 0 && earned > 0 ? Math.floor(earned * rate) : 0;
    lastGold[p.id] = p.gold - take;
    if (take <= 0) continue;
    takes[p.id] = take;
    total += take;
    lua.push(`for p in players_iterate() do if p.id == ${p.id} then edit.change_gold(p, -${take}) end end`);
  }
  const upkeep = Math.min(crownUpkeep(crown), Math.max(0, crown.gold + total));
  const net = total - upkeep;
  if (net !== 0) lua.push(`for p in players_iterate() do if p.id == ${crown.id} then edit.change_gold(p, ${net}) end end`);
  return { lua, total, takes, upkeep };
}

// Returns { error } or { text, lua, cost, favour: {playerId: delta} }.
export function decree(cmd, world) {
  const crown = crownOf(world);
  if (!crown) return { error: "the crown has no seat" };
  const d = DECREES[cmd.action];
  if (!d) return { error: "unknown decree" };
  if (crown.gold < d.cost) return { error: `the treasury holds ${(crown.gold * 100).toLocaleString("en-GB")} crowns; this costs ${(d.cost * 100).toLocaleString("en-GB")}` };
  const pay = `for p in players_iterate() do if p.id == ${crown.id} then edit.change_gold(p, -${d.cost}) end end`;
  const c = world.cities.find((x) => x.id === Number(cmd.city));
  const owner = c ? world.players.find((p) => p.id === c.owner) : world.players.find((p) => p.id === Number(cmd.house));
  const lord = owner ? houseFor(owner).name : "";
  const town = c ? cityName(c.id) : "";
  const inCity = (body) => `local c = find.city(nil, ${Number(c?.id)}); if c then ${body} end`;

  switch (cmd.action) {
    case "relief":
      if (!c) return { error: "choose a town" };
      return {
        cost: d.cost, favour: { [owner.id]: 12 },
        text: `By royal decree, wagons of grain roll into ${town}. ${lord} remembers the King's mercy.`,
        lua: [pay, inCity(`local u = edit.create_unit(c.owner, c.tile, find.unit_type("Migrants"), 0, c, -1); if u then u:perform_action(find.action("Join City"), c) end`)],
      };
    case "gift":
      if (!owner) return { error: "choose a town or house" };
      return {
        cost: d.cost, favour: { [owner.id]: 10 },
        text: `The King sends a chest of gold to ${lord}.`,
        lua: [pay, `for p in players_iterate() do if p.id == ${owner.id} then edit.change_gold(p, ${d.cost}) end end`],
      };
    case "levy": {
      const seat = world.cities.find((x) => x.owner === crown.id && x.capital);
      if (!seat) return { error: "the crown has no seat" };
      return {
        cost: d.cost, favour: {},
        text: "The King raises a levy. Pikemen and knights muster at Kingsmere.",
        lua: [pay, `local c = find.city(nil, ${seat.id}); if c then for _, n in ipairs({"Pikemen", "Pikemen", "Knights"}) do edit.create_unit(c.owner, c.tile, find.unit_type(n), 1, c, -1) end end`],
      };
    }
    case "build": {
      if (!c) return { error: "choose a town" };
      const b = BUILDABLE[cmd.building];
      if (!b) return { error: "unknown building" };
      return {
        cost: d.cost, favour: { [owner.id]: 8 },
        text: `The crown pays for a ${b.toLowerCase()} in ${town}. ${lord} is grateful.`,
        lua: [pay, inCity(`local b = find.building_type("${b}"); if b and not c:has_building(b) then edit.create_building(c, b) end`)],
      };
    }
    case "feast":
      if (!owner) return { error: "choose a town or house" };
      // At the King's own court: every great house is his guest.
      if (houseFor(owner).crown) {
        const guests = Object.fromEntries(world.players.filter((p) => !houseFor(p).crown && !houseFor(p).wild && p.id !== owner.id).map((p) => [p.id, 5]));
        return { cost: d.cost, favour: guests, text: "The King holds a feast at court. Every great house sends someone; tempers cool, for now.", lua: [pay] };
      }
      return {
        cost: d.cost, favour: { [owner.id]: 15 },
        text: `A feast at Kingsmere in honour of ${lord}. Wine flows; old slights are forgotten, for now.`,
        lua: [pay],
      };
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
          lua: [`local c = find.city(nil, ${c.id}); local to; for p in players_iterate() do if p.id == ${to.id} then to = p end end; if c and to then edit.transfer_city(c, to) end`],
        };
      }
      return {
        cost: 0, favour: { [owner.id]: -30, [to.id]: 20 },
        text: `By royal decree, ${town} is taken from ${lord} and granted to ${houseFor(to).name}. ${lord} will not forget.`,
        lua: [`local c = find.city(nil, ${c.id}); local to; for p in players_iterate() do if p.id == ${to.id} then to = p end end; if c and to then edit.transfer_city(c, to) end`],
      };
    }
    default:
      return { error: "unknown decree" };
  }
}
