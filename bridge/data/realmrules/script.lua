-- Freeciv - Copyright (C) 2007 - The Freeciv Project
--   This program is free software; you can redistribute it and/or modify
--   it under the terms of the GNU General Public License as published by
--   the Free Software Foundation; either version 2, or (at your option)
--   any later version.
--
--   This program is distributed in the hope that it will be useful,
--   but WITHOUT ANY WARRANTY; without even the implied warranty of
--   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--   GNU General Public License for more details.

-- This file is for lua-functionality that is specific to a given
-- ruleset. When freeciv loads a ruleset, it also loads script
-- file called 'default.lua'. The one loaded if your ruleset
-- does not provide an override is default/default.lua.


-- Place Ruins at the location of the destroyed city.
function city_destroyed_callback(city, loser, destroyer)
  city.tile:create_extra("Ruins", NIL)
  -- continue processing
  return false
end

signal.connect("city_destroyed", "city_destroyed_callback")

-- Check if there is certain terrain in ANY CAdjacent tile.
function adjacent_to(tile, terrain_name)
  for adj_tile in tile:circle_iterate(1) do
    if adj_tile.id ~= tile.id then
      local adj_terr = adj_tile.terrain
      local adj_name = adj_terr:rule_name()
      if adj_name == terrain_name then
        return true
      end
    end
  end
  return false
end

-- Check if there is certain terrain in ALL CAdjacent tiles.
function surrounded_by(tile, terrain_name)
  for adj_tile in tile:circle_iterate(1) do
    if adj_tile.id ~= tile.id then
      local adj_terr = adj_tile.terrain
      local adj_name = adj_terr:rule_name()
      if adj_name ~= terrain_name then
        return false
      end
    end
  end
  return true
end

-- Add random labels to the map.
function place_map_labels()
  local rivers = 0
  local deeps = 0
  local oceans = 0
  local lakes = 0
  local swamps = 0
  local glaciers = 0
  local tundras = 0
  local deserts = 0
  local plains = 0
  local grasslands = 0
  local jungles = 0
  local forests = 0
  local hills = 0
  local mountains = 0

  local selected_river = 0
  local selected_deep = 0
  local selected_ocean = 0
  local selected_lake = 0
  local selected_swamp = 0
  local selected_glacier = 0
  local selected_tundra = 0
  local selected_desert = 0
  local selected_plain = 0
  local selected_grassland = 0
  local selected_jungle = 0
  local selected_forest = 0
  local selected_hill = 0
  local selected_mountain = 0

  -- Count the tiles that has a terrain type that may get a label.
  for place in whole_map_iterate() do
    local terr = place.terrain
    local tname = terr:rule_name()

    if place:has_extra("River") then
      rivers = rivers + 1
    elseif tname == "Deep Ocean" then
      deeps = deeps + 1
    elseif tname == "Ocean" then
      oceans = oceans + 1
    elseif tname == "Lake" then
      lakes = lakes + 1
    elseif tname == "Swamp" then
      swamps = swamps + 1
    elseif tname == "Glacier" then
      glaciers = glaciers + 1
    elseif tname == "Tundra" then
      tundras = tundras + 1
    elseif tname == "Desert" then
      deserts = deserts + 1
    elseif tname == "Plains" then
      plains = plains + 1
    elseif tname == "Grassland" then
      grasslands = grasslands + 1
    elseif tname == "Jungle" then
      jungles = jungles + 1
    elseif tname == "Forest" then
      forests = forests + 1
    elseif tname == "Hills" then
      hills = hills + 1
    elseif tname == "Mountains" then
      mountains = mountains + 1
    end
  end

  -- Decide if a label should be included and, in case it should, where.
    if random(1, 100) <= rivers then
      selected_river = random(1, rivers)
    end
    if random(1, 100) <= deeps then
      selected_deep = random(1, deeps)
    end
    if random(1, 100) <= oceans then
      selected_ocean = random(1, oceans)
    end
    if random(1, 100) <= lakes then
      selected_lake = random(1, lakes)
    end
    if random(1, 100) <= swamps then
      selected_swamp = random(1, swamps)
    end
    if random(1, 100) <= glaciers then
      selected_glacier = random(1, glaciers)
    end
    if random(1, 100) <= tundras then
      selected_tundra = random(1, tundras)
    end
    if random(1, 100) <= deserts then
      selected_desert = random(1, deserts)
    end
    if random(1, 100) <= plains then
      selected_plain = random(1, plains)
    end
    if random(1, 100) <= grasslands then
      selected_grassland = random(1, grasslands)
    end
    if random(1, 100) <= jungles then
      selected_jungle = random(1, jungles)
    end
    if random(1, 100) <= forests then
      selected_forest = random(1, forests)
    end
    if random(1, 100) <= hills then
      selected_hill = random(1, hills)
    end
    if random(1, 100) <= mountains then
      selected_mountain = random(1, mountains)
    end

  -- Place the included labels at the location determined above.
  for place in whole_map_iterate() do
    local terr = place.terrain
    local tname = terr:rule_name()

    if place:has_extra("River") then
      selected_river = selected_river - 1
      if selected_river == 0 then
        if tname == "Hills" then
          place:set_label(_("Grand Canyon"))
        elseif tname == "Mountains" then
          place:set_label(_("Deep Gorge"))
        elseif tname == "Tundra" then
          place:set_label(_("Fjords"))
        elseif random(1, 100) <= 50 then
          place:set_label(_("Waterfalls"))
        else
          place:set_label(_("Travertine Terraces"))
        end
      end
    elseif tname == "Deep Ocean" then
      selected_deep = selected_deep - 1
      if selected_deep == 0 then
        if surrounded_by(place, "Deep Ocean") then
          -- Fully surrounded
          place:set_label(_("Deep Trench"))
        else
          place:set_label(_("Thermal Vent"))
        end
      end
    elseif tname == "Ocean" then
      selected_ocean = selected_ocean - 1
      if selected_ocean == 0 then
        if surrounded_by(place, "Ocean") then
          -- Fully surrounded
          place:set_label(_("Atoll Chain"))
        elseif adjacent_to(place, "Glacier") then
          place:set_label(_("Glacier Bay"))
        elseif adjacent_to(place, "Deep Ocean") then
          place:set_label(_("Great Barrier Reef"))
        else
          -- Coast (not adjacent to glacier nor deep ocean)
          place:set_label(_("Great Blue Hole"))
        end
      end
    elseif tname == "Lake" then
      selected_lake = selected_lake - 1
      if selected_lake == 0 then
        if surrounded_by(place, "Lake") then
          -- Fully surrounded
          place:set_label(_("Great Lakes"))
        elseif not adjacent_to(place, "Lake") then
          -- Isolated
          place:set_label(_("Dead Sea"))
        else
          place:set_label(_("Rift Lake"))
        end
      end
    elseif tname == "Swamp" then
      selected_swamp = selected_swamp - 1
      if selected_swamp == 0 then
        if not adjacent_to(place, "Swamp") then
          -- Isolated
          place:set_label(_("Grand Prismatic Spring"))
        elseif adjacent_to(place, "Ocean") then
          -- Coast
          place:set_label(_("Mangrove Forest"))
        else
          place:set_label(_("Cenotes"))
        end
      end
    elseif tname == "Glacier" then
      selected_glacier = selected_glacier - 1
      if selected_glacier == 0 then
        if surrounded_by(place, "Glacier") then
          -- Fully surrounded
          place:set_label(_("Ice Sheet"))
        elseif not adjacent_to(place, "Glacier") then
          -- Isolated
          place:set_label(_("Frozen Lake"))
        elseif adjacent_to(place, "Ocean") then
          -- Coast
          place:set_label(_("Ice Shelf"))
        else
          place:set_label(_("Advancing Glacier"))
        end
      end
    elseif tname == "Tundra" then
      selected_tundra = selected_tundra - 1
      if selected_tundra == 0 then
          place:set_label(_("Geothermal Area"))
      end
    elseif tname == "Desert" then
      selected_desert = selected_desert - 1
      if selected_desert == 0 then
        if surrounded_by(place, "Desert") then
          -- Fully surrounded
          place:set_label(_("Sand Sea"))
        elseif not adjacent_to(place, "Desert") then
          -- Isolated
          place:set_label(_("Salt Flat"))
        elseif random(1, 100) <= 50 then
          place:set_label(_("Singing Dunes"))
        else
          place:set_label(_("White Desert"))
        end
      end
    elseif tname == "Plains" then
      selected_plain = selected_plain - 1
      if selected_plain == 0 then
        if adjacent_to(place, "Ocean") then
          -- Coast
          place:set_label(_("Long Beach"))
        elseif random(1, 100) <= 50 then
          place:set_label(_("Valley of Geysers"))
        else
          place:set_label(_("Rock Pillars"))
        end
      end
    elseif tname == "Grassland" then
      selected_grassland = selected_grassland - 1
      if selected_grassland == 0 then
        if adjacent_to(place, "Ocean") then
          -- Coast
          place:set_label(_("White Cliffs"))
        elseif random(1, 100) <= 50 then
          place:set_label(_("Giant Cave"))
        else
          place:set_label(_("Rock Formation"))
        end
      end
    elseif tname == "Jungle" then
      selected_jungle = selected_jungle - 1
      if selected_jungle == 0 then
        if surrounded_by(place, "Jungle") then
          -- Fully surrounded
          place:set_label(_("Rainforest"))
        elseif adjacent_to(place, "Ocean") then
          -- Coast
          place:set_label(_("Subterranean River"))
        else
          place:set_label(_("Sinkholes"))
        end
      end
    elseif tname == "Forest" then
      selected_forest = selected_forest - 1
      if selected_forest == 0 then
        if adjacent_to(place, "Mountains") then
          place:set_label(_("Stone Forest"))
        elseif surrounded_by(place, "Forest") then
          -- Fully surrounded
          place:set_label(_("Sequoia Forest"))
        else
          place:set_label(_("Millenary Trees"))
        end
      end
    elseif tname == "Hills" then
      selected_hill = selected_hill - 1
      if selected_hill == 0 then
        if not adjacent_to(place, "Hills") then
          if adjacent_to(place, "Mountains") then
            -- Isolated (but adjacent to mountains)
            place:set_label(_("Table Mountain"))
          else
            -- Isolated (not adjacent to hills nor mountains)
            place:set_label(_("Inselberg"))
          end
        elseif random(1, 100) <= 50 then
          place:set_label(_("Karst Landscape"))
        else
          place:set_label(_("Mud Volcanoes"))
        end
      end
    elseif tname == "Mountains" then
      selected_mountain = selected_mountain - 1
      if selected_mountain == 0 then
        if surrounded_by(place, "Mountains") then
          -- Fully surrounded
          place:set_label(_("Highest Peak"))
        elseif not adjacent_to(place, "Mountains") then
          -- Isolated
          place:set_label(_("Sacred Mount"))
        elseif adjacent_to(place, "Ocean") then
          -- Coast
          place:set_label(_("Cliff Coast"))
        elseif random(1, 100) <= 50 then
          place:set_label(_("Active Volcano"))
        else
          place:set_label(_("High Summit"))
        end
      end
    end
  end
  return false
end

signal.connect("map_generated", "place_map_labels")


-- ===========================================================================
-- Game of Crowns. Loaded with the ruleset, so every game and every save has it
-- (docs/research/freeciv-leverage-2026-11-12.md). It turns Freeciv's signals
-- into EVENT lines the bridge reads from stdout, runs the gold seams each
-- season, and gives the bridge short helpers (realm_host and friends).
-- Lua globals are saved with the game only as numbers, strings, booleans and
-- Freeciv objects, never tables (tolua_common_a.pkg _freeciv_state_dump).
-- ===========================================================================

local function esc(v)
  if type(v) == "number" and v == math.floor(v) then v = string.format("%d", v) end
  return (tostring(v):gsub('\\', '\\\\'):gsub('"', '\\"')) end
local function emit(kind, fields)
  local parts = {}
  for k, v in pairs(fields) do parts[#parts + 1] = string.format('"%s":"%s"', k, esc(v)) end
  log.normal('EVENT {"turn":"%d","kind":"%s",%s}', game.current_turn(), kind, table.concat(parts, ","))
end

function ev_city_built(city) emit("city_built", {city = city.id, owner = city.owner.id}) end
function ev_city_size(city, change, reason)
  if reason == "famine" or reason == "plague" or reason == "disaster" or reason == "conquest" or reason == "migration" then
    emit("city_shrank", {city = city.id, owner = city.owner.id, change = change, reason = reason, size = city.size})
  end
end
function ev_city_destroyed(city, loser, destroyer)
  emit("city_destroyed", {city = city.id, loser = loser.id, destroyer = destroyer and destroyer.id or -1})
end
function ev_city_transferred(city, old, new, reason)
  emit("city_transferred", {city = city.id, from = old.id, to = new.id, reason = reason})
end
function ev_disaster(disaster, city, had_effect)
  emit("disaster", {disaster = disaster:rule_name(), city = city.id, owner = city.owner.id})
end
function ev_building_built(btype, city)
  emit("building_built", {building = btype:rule_name(), city = city.id, owner = city.owner.id})
end
function ev_building_lost(city, btype, reason, destroyer)
  emit("building_lost", {building = btype:rule_name(), city = city.id, owner = city.owner.id, reason = reason})
end
function ev_unit_lost(unit, loser, reason)
  if reason == "killed" then
    emit("unit_killed", {unit = unit.utype:rule_name(), owner = loser.id, x = unit.tile.x, y = unit.tile.y})
  end
end
-- Who struck: an attack on a tile, so the bridge knows the victors when a company dies there (battles.js).
function ev_attack(action, actor, target)
  local ok, name = pcall(function() return action:rule_name() end)
  local t = target and (target.tile or target)  -- a unit struck, or a tile
  if ok and name and name:find("Attack") and actor and t then
    emit("attack", {owner = actor.owner.id, unit = actor.utype:rule_name(), x = t.x, y = t.y, ax = actor.tile.x, ay = actor.tile.y})
  end
end
function ev_tech(tech, player, source)
  emit("tech", {tech = tech:rule_name(), owner = player.id, source = source})
end
function ev_civil_war(player) emit("civil_war", {owner = player.id}) end
-- The realm starts in its medieval age: every house already knows these.
local MEDIEVAL = {"Alphabet", "Bronze Working", "Ceremonial Burial", "Masonry", "Horseback Riding", "Warrior Code",
  "Iron Working", "Pottery", "The Wheel", "Code of Laws", "Writing", "Monarchy", "Mathematics", "Currency",
  "Mysticism", "Construction", "Polytheism", "Feudalism", "Map Making", "Seafaring"}

function ev_turn(turn, year)
  if turn == 1 and realm_setup then realm_setup() end
  if turn == 1 then
    for p in players_iterate() do
      for _, name in ipairs(MEDIEVAL) do
        local t = find.tech_type(name)
        if t then edit.give_technology(p, t, 0, false, "script") end
      end
    end
  end
  emit("turn", {year = year})
  realm_mines_turn()
end

local hooks = {
  {"city_built", "ev_city_built"}, {"city_size_change", "ev_city_size"},
  {"city_destroyed", "ev_city_destroyed"}, {"city_transferred", "ev_city_transferred"},
  {"disaster_occurred", "ev_disaster"}, {"building_built", "ev_building_built"},
  {"building_lost", "ev_building_lost"}, {"unit_lost", "ev_unit_lost"},
  {"tech_researched", "ev_tech"}, {"civil_war_triggered", "ev_civil_war"},
  {"turn_begin", "ev_turn"}, {"action_started_unit_units", "ev_attack"}, {"action_started_unit_unit", "ev_attack"}, {"action_started_unit_tile", "ev_attack"},  -- Freeciv 3.2 reports an attack as unit-on-tile
}
for _, h in ipairs(hooks) do
  local ok, err = pcall(signal.connect, h[1], h[2])
  if not ok then log.normal("HOOKFAIL %s %s", h[1], tostring(err)) end
end

-- Gold seams (bridge/mines.js, data/mines.json). Freeciv's Gold never runs out; a seam here is
-- worked out over a number of seasons, then the Gold leaves the land. Kept as plain text globals
-- ("x,y,left;..."), because Freeciv's save keeps a script's plain globals but not its tables.
GOC_SEAMS = GOC_SEAMS or ""
GOC_SEAMS_LAID = GOC_SEAMS_LAID or false
GOC_SEAMS_TURN = GOC_SEAMS_TURN or -1

-- Close enough to a town of the land's owner to be worked (Freeciv's Lua can't say which tiles a town works).
local function seam_worked(t)
  local owner = t.owner
  if not owner then return false end
  for c in owner:cities_iterate() do
    if t:sq_distance(c.tile) <= c:map_sq_radius() then return true end
  end
  return false
end

-- One seam in reach of each of the gold house's towns, until `count`: on a mountain there, or, where
-- its land is all field and forest (the realm's map rarely puts mountains by a town), a forest tile
-- raised into a mountain. Our rules let Gold lie only on mountains (realmrules/terrain.ruleset), and
-- Freeciv clears it from any other land when a save loads. Fields stay fields: the town has to eat.
local function seam_in_reach(c)
  local hill, wood
  for t in c.tile:circle_iterate(c:map_sq_radius()) do
    local n = t.terrain:rule_name()
    if t:city() == nil and not t:has_extra("Gold") then
      if not hill and n == "Mountains" then hill = t end
      if not wood and n == "Forest" then wood = t end
    end
  end
  if not hill and wood then
    local peak = find.terrain("Mountains")
    if peak and pcall(edit.change_terrain, wood, peak) then hill = wood end
  end
  return hill
end

local function seams_lay(seasons, house, count)
  local laid, towns = 0, 0
  for p in players_iterate() do
    if laid < count and p.is_alive and p.nation and p.nation:rule_name() == house then
      for c in p:cities_iterate() do
        towns = towns + 1
        local t = laid < count and seam_in_reach(c)
        if t and pcall(edit.create_owned_extra, t, "Gold", nil) and t:has_extra("Gold") then laid = laid + 1 end
      end
    end
  end
  local seams = {}
  for t in whole_map_iterate() do
    if t:has_extra("Gold") then seams[#seams + 1] = string.format("%d,%d,%d", t.x, t.y, seasons) end
  end
  GOC_SEAMS = table.concat(seams, ";")
  GOC_SEAMS_LAID = towns > 0  -- a realm whose gold house has no town yet tries again next season
  log.normal("SEAMS laid %d for %s; %d in the realm", laid, house, #seams)
end

-- Each season the seams run down; their numbers are the ruleset's (realmrules/luadata.txt [mines]).
function realm_mines_turn()
  local on = luadata.get_str("mines.on")
  if on ~= "yes" then return end
  realm_mines(tonumber(luadata.get_str("mines.seam_seasons")), luadata.get_str("mines.gold_house"),
    tonumber(luadata.get_str("mines.gold_seams")))
end

function realm_mines(seasons, house, count)
  local turn = game.current_turn()
  if GOC_SEAMS_TURN == turn then return end  -- once a season, however often the bridge asks
  GOC_SEAMS_TURN = turn
  if not GOC_SEAMS_LAID then seams_lay(seasons, house, count) return end
  local kept = {}
  for x, y, left in GOC_SEAMS:gmatch("(%d+),(%d+),(%-?%d+)") do
    local t = find.tile(tonumber(x), tonumber(y))
    left = tonumber(left)
    if t and t:has_extra("Gold") then
      if seam_worked(t) then left = left - 1 end
      if left <= 0 then
        local owner = t.owner
        edit.remove_extra(t, "Gold")
        emit("seam_spent", {x = t.x, y = t.y, owner = owner and owner.id or -1})
      else
        kept[#kept + 1] = string.format("%d,%d,%d", t.x, t.y, left)
      end
    elseif t then  -- its Gold gone some other way (the land changed under it): the workings are spent all the same
      emit("seam_spent", {x = t.x, y = t.y, owner = t.owner and t.owner.id or -1})
    end
  end
  GOC_SEAMS = table.concat(kept, ";")
end

-- Hosts raised by the bridge's stakes (the usurper, the dead). Defined here so
-- the bridge sends a short call instead of a long console line.
function realm_find_player(id)
  for p in players_iterate() do if p.id == id then return p end end
end

function realm_the_dead()
  for p in players_iterate() do if p.name == "The Dead" then return p end end
  return edit.create_player("The Dead", find.nation_type("Barbarian"), "classic")
end

function realm_host(who, x, y, kinds, count)
  if not who then log.normal("HOST no owner"); return end
  local tiles = {}
  for t in find.tile(x, y):square_iterate(2) do
    local n = t.terrain:rule_name()
    if not n:find("Ocean") and n ~= "Lake" and t:city() == nil then tiles[#tiles + 1] = t end
  end
  local made = 0
  for i = 1, count do
    local ut = find.unit_type(kinds[(i - 1) % #kinds + 1])
    local t = tiles[(i - 1) % math.max(1, #tiles) + 1]
    if ut and t then
      local ok, u = pcall(edit.create_unit, who, t, ut, 1, nil, -1)
      if ok and u then made = made + 1 end
    end
  end
  log.normal("HOST %s raised %d of %d near (%d,%d)", who.name, made, count, x, y)
end
