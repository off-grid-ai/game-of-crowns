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

// The tithe: each turn the crown takes `rate` of every great house's treasury.
// Higher tithes cost favour every turn.
export function titheLua(world, rate) {
  const crown = crownOf(world);
  if (!crown || rate <= 0) return { lua: [], total: 0, takes: {} };
  const takes = {};
  let total = 0;
  const lua = [];
  for (const p of world.players) {
    const h = houseFor(p);
    if (h.wild || h.crown || p.gold <= 0) continue;
    const take = Math.floor(p.gold * rate);
    if (take <= 0) continue;
    takes[p.id] = take;
    total += take;
    lua.push(`for p in players_iterate() do if p.id == ${p.id} then edit.change_gold(p, -${take}) end end`);
  }
  if (total > 0) lua.push(`for p in players_iterate() do if p.id == ${crown.id} then edit.change_gold(p, ${total}) end end`);
  return { lua, total, takes };
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
