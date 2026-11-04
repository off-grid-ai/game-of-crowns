// God commands. Freeciv has no "shrink this city" call, so the gods change the
// world's conditions (land, buildings, soldiers) and Freeciv simulates the
// consequences: a desertified town really starves, an irrigated one really grows.
// Scarred land reports itself as a "scar" event so the bridge can heal it later.

import { cityName, houseFor } from "./narrator.js";

const BUILDABLE = {
  temple: "Temple",
  granary: "Granary",
  walls: "City Walls",
  barracks: "Barracks",
  market: "Marketplace",
  cathedral: "Cathedral",
  aqueduct: "Aqueduct",
};

const FARMLAND = `n == "Grassland" or n == "Plains" or n == "Forest" or n == "Jungle" or n == "Swamp" or n == "Tundra"`;

// Turns farmland within the town's work radius into `into`, logging the originals.
function scar(id, into, chance, heal) {
  return `local c = find.city(nil, ${id}); if c then local s = {}; for t in c.tile:circle_iterate(5) do local n = t.terrain:rule_name(); if t ~= c.tile and (${FARMLAND}) and math.random() < ${chance} then s[#s + 1] = string.format("%d,%d,%s", t.x, t.y, n); edit.change_terrain(t, find.terrain("${into}")) end end; log.normal('EVENT {"turn":"%d","kind":"scar","city":"%d","tiles":"%s","heal":"%d"}', game.current_turn(), c.id, table.concat(s, ";"), game.current_turn() + ${heal}) end`;
}

function inCity(id, body) {
  return `local c = find.city(nil, ${id}); if c then ${body} end`;
}

const KILL_GARRISON = `for t in c.tile:square_iterate(1) do for u in t:units_iterate() do if u.owner == c.owner and math.random() < 0.7 then edit.unit_kill(u, "killed", nil) end end end`;

export function healLua(tiles) {
  return tiles.split(";").filter(Boolean).map((t) => {
    const [x, y, terrain] = t.split(",");
    return `local t = find.tile(${Number(x)}, ${Number(y)}); if t then edit.change_terrain(t, find.terrain("${terrain.replace(/[^A-Za-z ]/g, "")}")) end`;
  });
}

export function godCommand(cmd, world) {
  const c = world?.cities?.find((x) => x.id === Number(cmd.city));
  if (!c) return { error: "pick a town first" };
  const owner = world.players.find((p) => p.id === c.owner);
  const town = cityName(c.id);
  const house = houseFor(owner).name;
  const id = Number(c.id);

  switch (cmd.action) {
    case "famine":
      return {
        text: `The gods send drought upon ${town}. The fields of ${house} crack and turn to dust.`,
        lua: [scar(id, "Desert", 0.85, 12)],
      };
    case "bounty":
      return {
        text: `The gods bless ${town}. Rain falls softly, the fields turn green and new families arrive.`,
        lua: [
          inCity(id, `for t in c.tile:circle_iterate(5) do local n = t.terrain:rule_name(); if t ~= c.tile and (${FARMLAND} or n == "Desert") then edit.change_terrain(t, find.terrain("Grassland")); edit.create_owned_extra(t, "Irrigation", c.owner) end end`),
          inCity(id, `for i = 1, 2 do local u = edit.create_unit(c.owner, c.tile, find.unit_type("Migrants"), 0, c, -1); if u then u:perform_action(find.action("Join City"), c) end end; edit.change_gold(c.owner, 100)`),
        ],
      };
    case "plague":
      return {
        text: `A plague spreads through the lands of ${house}. Soldiers die in their barracks; fields go untended.`,
        lua: [
          inCity(id, `for k in c.owner:cities_iterate() do for t in k.tile:square_iterate(1) do for u in t:units_iterate() do if u.owner == k.owner and math.random() < 0.6 then edit.unit_kill(u, "killed", nil) end end end; local a = find.building_type("Aqueduct"); if a and k:has_building(a) then edit.remove_building(k, a) end end`),
          scar(id, "Swamp", 0.5, 8),
        ],
      };
    case "army":
      return {
        text: `The gods raise an army for ${house} at ${town}.`,
        lua: [inCity(id, `local t = find.unit_type("Knights") or find.unit_type("Horsemen"); for i = 1, 4 do edit.create_unit(c.owner, c.tile, t, 1, c, -1) end`)],
      };
    case "settlers":
      return {
        text: `Wanderers arrive at ${town} and swear fealty to ${house}.`,
        lua: [inCity(id, `for i = 1, 3 do local u = edit.create_unit(c.owner, c.tile, find.unit_type("Migrants"), 0, c, -1); if u then u:perform_action(find.action("Join City"), c) end end`)],
      };
    case "gold":
      return { text: `A vein of gold is found near ${town}. ${house} grows rich.`, lua: [inCity(id, `edit.change_gold(c.owner, 400)`)] };
    case "civil_war":
      return { text: `The gods whisper treason in the halls of ${house}.`, lua: [inCity(id, `edit.civil_war(c.owner, 100)`)] };
    case "build": {
      const b = BUILDABLE[cmd.building];
      if (!b) return { error: "unknown building" };
      return {
        text: `By divine will, a ${b.toLowerCase()} rises overnight in ${town}.`,
        lua: [inCity(id, `local b = find.building_type("${b}"); if b and not c:has_building(b) then edit.create_building(c, b) end`)],
      };
    }
    default:
      return { error: "unknown action" };
  }
}
