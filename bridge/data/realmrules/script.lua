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
  -- Every unit Freeciv takes off the map, and why (the reign harness checks no unit vanishes without one).
  log.normal("UNIT_LOST %d %s %d", unit.id, tostring(reason), loser and loser.id or -1)
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
  realm_books_open()
  realm_mines_turn()
  realm_decrees_lapse()
  realm_raids_turn()
  realm_risings_turn()
  realm_purse()
  realm_books_close()
end

-- Any conquest, by any house's AI or the rebels, takes the town, never razes it (realm_spare_hamlet): Freeciv
-- says the action is starting before it runs, so the hamlet gains its townsman first.
function ev_conquer(action, actor, city)
  local ok, name = pcall(function() return action:rule_name() end)
  if ok and name and name:find("^Conquer City") then realm_spare_hamlet(city) end
end

-- A player's phase begins with its men's moves restored: the rebels march and strike then (realm_risings_phase).
function ev_phase(player, is_new_phase)
  realm_risings_phase(player)
end

local hooks = {
  {"city_built", "ev_city_built"}, {"city_size_change", "ev_city_size"},
  {"city_destroyed", "ev_city_destroyed"}, {"city_transferred", "ev_city_transferred"},
  {"disaster_occurred", "ev_disaster"}, {"building_built", "ev_building_built"},
  {"building_lost", "ev_building_lost"}, {"unit_lost", "ev_unit_lost"},
  {"tech_researched", "ev_tech"},
  {"turn_begin", "ev_turn"}, {"player_phase_begin", "ev_phase"}, {"action_started_unit_city", "ev_conquer"}, {"action_started_unit_units", "ev_attack"}, {"action_started_unit_unit", "ev_attack"}, {"action_started_unit_tile", "ev_attack"},  -- Freeciv 3.2 reports an attack as unit-on-tile
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
-- The town that works a gold seam: the land owner's town nearest it whose radius reaches it, else nil. The one
-- rule (Freeciv 3.2's Lua has no worked-tile call): the seam wears down by it, and the snapshot's gold rows
-- name it, so the miners and the ore carts go to the town that really works it.
function realm_seam_town(t)
  local owner = t.owner
  if not owner then return nil end
  local best, bd = nil, nil
  for c in owner:cities_iterate() do
    local d = t:sq_distance(c.tile)
    if d <= c:map_sq_radius() and (not bd or d < bd) then best, bd = c, d end
  end
  return best
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
  local kept, worked = {}, {}
  for x, y, left in GOC_SEAMS:gmatch("(%d+),(%d+),(%-?%d+)") do
    local t = find.tile(tonumber(x), tonumber(y))
    left = tonumber(left)
    if t and t:has_extra("Gold") then
      local by = realm_seam_town(t)
      if by then
        left = left - 1
        local pay = tonumber(luadata.get_str("mines.gold_per_season")) or 0
        if pay > 0 then edit.change_gold(by.owner, pay) realm_book(by.owner.id, "mines", pay) end
      end
      worked[#worked + 1] = string.format("%d,%d,%d,%d", t.x, t.y, by and by.id or -1, t.owner and t.owner.id or -1)
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
  -- Which town works each seam this season (x,y,town,owner), for the view's miners and ore carts (mines.js puts it on /world).
  emit("seams_worked", {at = table.concat(worked, ";")})
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
  if not who then log.normal("HOST no owner"); return {} end
  local tiles = {}
  for t in find.tile(x, y):square_iterate(2) do
    local n = t.terrain:rule_name()
    if not n:find("Ocean") and n ~= "Lake" and t:city() == nil then tiles[#tiles + 1] = t end
  end
  -- Each company is the house's to feed: homed to its town nearest the muster, so Freeciv charges its
  -- upkeep there (the dead and other townless hosts have no home).
  local home, best = nil, nil
  local at = find.tile(x, y)
  for c in who:cities_iterate() do
    local d = c.tile:sq_distance(at)
    if not best or d < best then home, best = c, d end
  end
  local made = {}
  for i = 1, count do
    local ut = find.unit_type(kinds[(i - 1) % #kinds + 1])
    local t = tiles[(i - 1) % math.max(1, #tiles) + 1]
    if ut and t then
      local ok, u = pcall(edit.create_unit, who, t, ut, 1, home, -1)
      if ok and u then made[#made + 1] = u.id end
    end
  end
  log.normal("HOST %s raised %d of %d near (%d,%d)", who.name, #made, count, x, y)
  return made
end

-- A house goes to war on a town (a story's war): its host is raised at its own town nearest the prey, not at the
-- prey's gates, and marches there by road (casebook, War and sieges: The march feeds the battle). The bridge walks
-- it (hosts.js warpath) once told who was raised; at the walls the men are their house's AI's again, and it fights.
-- A house that holds no town has nowhere to march from: its men gather beside the prey, as before.
function realm_war_host(who, city_id, kinds, count)
  local prey = find.city(nil, city_id)
  if not who or not prey then log.normal("WARHOST no house or prey"); return end
  local home, best = nil, nil
  for c in who:cities_iterate() do
    local d = c.tile:sq_distance(prey.tile)
    if not best or d < best then home, best = c, d end
  end
  local at = home and home.tile or prey.tile
  local made = realm_host(who, at.x, at.y, kinds, count)
  if home and #made > 0 then
    local ids = {}
    for i, id in ipairs(made) do ids[i] = tostring(id) end
    emit("war_host", {owner = who.id, city = prey.id, from = home.id, units = table.concat(ids, ",")})
  end
end

-- A house's gathered host marches out (director.js: a threat left unanswered breaks): its soldiers standing round
-- its town, not in it (the garrison stays), are told to the bridge as a war host on the crown's town (war_host),
-- which walks them there by the road (hosts.js warpath); the town falls only when they reach its walls.
function realm_war_march(who, from_id, to_id)
  local from, to = find.city(nil, from_id), find.city(nil, to_id)
  if not who or not from or not to then log.normal("WARMARCH no house or town"); return end
  local ids = {}
  for t in from.tile:square_iterate(2) do
    if t:city() == nil then
      for u in t:units_iterate() do
        if u.owner == who and not u.utype:has_flag("NonMil") then ids[#ids + 1] = tostring(u.id) end
      end
    end
  end
  if #ids > 0 then emit("war_host", {owner = who.id, city = to.id, units = table.concat(ids, ",")}) end
  log.normal("WARMARCH %s %d men from %s on %s", who.name, #ids, from.name, to.name)
end

-- The banners answered (bridge crown.js banners): n of a house's fighting men, those nearest the King's town first,
-- set out for it; the bridge walks them there by the road (hosts.js warpath, join) and they join the royal host at
-- its walls (realm_banners_join).
function realm_banners(who, city_id, n)
  local to = find.city(nil, city_id)
  if not who or not to then log.normal("BANNERS no house or town"); return end
  local men = {}
  for u in who:units_iterate() do
    if not u.utype:has_flag("NonMil") then men[#men + 1] = {id = u.id, d = u.tile:sq_distance(to.tile)} end
  end
  table.sort(men, function(a, b) return a.d < b.d end)
  local ids = {}
  for i = 1, math.min(n, #men) do ids[i] = tostring(men[i].id) end
  if #ids > 0 then emit("war_host", {owner = who.id, city = to.id, units = table.concat(ids, ","), join = "1"}) end
  log.normal("BANNERS %s sends %d men to %s", who.name, #ids, to.name)
end

-- Banner men at the King's walls join the royal host: Freeciv 3.2's Lua can't give a unit to another player, so each
-- is taken off and one of his kind raised in the town for its holder; reports banners_joined (the house, the men who
-- came, the companies they are now: hosts.js joined).
function realm_banners_join(ids, city_id)
  local c = find.city(nil, city_id)
  if not c then return end
  local owner, from, made = nil, {}, {}
  for id in tostring(ids or ""):gmatch("%d+") do
    local u = find.unit(nil, tonumber(id))
    if u then
      local t = u.utype
      owner = owner or u.owner.id
      from[#from + 1] = tostring(u.id)
      edit.unit_kill(u, "disbanded", nil)
      local n = edit.create_unit(c.owner, c.tile, t, 1, c, -1)
      if n then made[#made + 1] = tostring(n.id) end
    end
  end
  if #made > 0 then emit("banners_joined", {owner = owner, city = c.id, from = table.concat(from, ","), units = table.concat(made, ",")}) end
  log.normal("BANNERS %d men join the host at %s", #made, c.name)
end

-- Men without banners: a raid is an event, not a standing army. Freeciv's own barbarians are raised beside a
-- town (a paid raid, a story's raid), on an empty land tile two out, never on anyone's men (unleashing wipes the
-- tile's units). They can't take the town (actions.ruleset); each season they pillage the land around it with
-- Freeciv's own Pillage order, and after raids.seasons seasons they walk off to wild land and go (Disband Unit). Needs the barbarians
-- setting above "disabled" and onsetbarbs passed (game.ruleset sets it to 1); with raiders off, nothing comes.
-- Freeciv's own barbarians (a hut's, the wild hordes) get the same season: realm_raids_turn takes in any raider it
-- hasn't seen, beside the town nearest him. Kept as a plain string ("unit,unit|town|until;..."), which the save keeps.
GOC_RAIDS = GOC_RAIDS or ""
-- The King's works (the bridge's royal works, treasury.js: rising or standing in a royal town), as "town,town": what
-- a raid makes for first (Mount & Blade's raiders on a lord's village, Stronghold's raid on the granary). Saved.
GOC_WORKS = GOC_WORKS or ""
function realm_royal_works(towns) GOC_WORKS = tostring(towns or "") end
local RAID_SPOILS = {"Farmland", "Railroad", "Mine", "Irrigation", "Road", "Fortress", "Fort"}

-- Freeciv's barbarians, land and sea. The dead wear the Barbarian nation too but are a player of their own
-- (realm_the_dead): they march to take the North, not to raid.
local function raiders_now()
  local ids = {}
  for p in players_iterate() do
    local n = p.nation and p.nation:rule_name() or ""
    if (n == "Barbarian" or n == "Pirate") and p.name ~= "The Dead" then for u in p:units_iterate() do ids[u.id] = u end end
  end
  return ids
end

local function raid_seasons() return tonumber(luadata.get_str("raids.seasons")) or 8 end
local function raid_num(k, d) return tonumber(luadata.get_str("raids." .. k)) or d end

-- Where raiders go when the raid is over: wild land (no house's) or the map's edge (a tile with fewer than eight
-- neighbours on this unwrapped map).
local function raid_wild(t)
  if t.owner == nil then return true end
  local n = 0
  for _ in t:square_iterate(1) do n = n + 1 end
  return n < 9
end

-- Land a raider may walk onto: no water, no town, nobody else's men.
local function raid_open(t, u)
  local n = t.terrain:rule_name()
  if n:find("Ocean") or n == "Lake" or t:city() ~= nil then return false end
  for o in t:units_iterate() do if o.owner ~= u.owner then return false end end
  return true
end

-- The raider's way out: the tiles of the shortest walk over open land to wild land or the edge (breadth-first over
-- the eight neighbours, out to `reach` steps); {} when he stands on wild land, nil when no way out is in reach.
local function raid_way_out(u, reach)
  if raid_wild(u.tile) then return {} end
  local start = u.tile.id
  local from, depth, q, head = {}, {[start] = 0}, {u.tile}, 1
  while head <= #q do
    local t = q[head]
    head = head + 1
    if depth[t.id] < reach then
      for n in t:square_iterate(1) do
        if depth[n.id] == nil and raid_open(n, u) then
          from[n.id], depth[n.id] = t, depth[t.id] + 1
          if raid_wild(n) then
            local way, p = {}, n
            while p.id ~= start do table.insert(way, 1, p); p = from[p.id] end
            return way
          end
          q[#q + 1] = n
        end
      end
    end
  end
  return nil
end

-- A raider leaving: up to raids.leave_steps tiles a season along his way out, by Freeciv's own unit_move; true once he
-- is gone (disbanded on wild land, or where he stands when no way out is in reach or on the raid's last season).
local function raid_leave(u, last)
  local way = not last and raid_way_out(u, raid_num("leave_reach", 30)) or nil
  if way and #way > 0 then
    for i = 1, math.min(#way, raid_num("leave_steps", 3)) do
      pcall(edit.unit_move, u, way[i], 0, nil, false, false, false, false, false)
      if u.tile.id ~= way[i].id then break end
    end
    if not raid_wild(u.tile) then return false end
  end
  pcall(edit.perform_action, u, find.action("Disband Unit"))
  return true
end

-- Raiders Freeciv raised on its own, not yet in a raid: one raid per town they rise nearest to.
local function raids_take_in()
  local known = {}
  for id in GOC_RAIDS:gmatch("%d+") do known[tonumber(id)] = true end
  local by_town, order = {}, {}
  for id, u in pairs(raiders_now()) do
    if not known[id] then
      local best, bd = nil, nil
      for p in players_iterate() do
        if p ~= u.owner then
          for c in p:cities_iterate() do
            local d = c.tile:sq_distance(u.tile)
            if not bd or d < bd then best, bd = c, d end
          end
        end
      end
      if best then
        if not by_town[best.id] then by_town[best.id] = {}; order[#order + 1] = best.id end
        table.insert(by_town[best.id], string.format("%d", id))
      end
    end
  end
  local til = game.current_turn() + raid_seasons()
  for _, cid in ipairs(order) do
    GOC_RAIDS = GOC_RAIDS .. (GOC_RAIDS == "" and "" or ";") .. string.format("%s|%d|%d|0", table.concat(by_town[cid], ","), cid, til)
    log.normal("RAID wild raiders by %s: %d", find.city(nil, cid).name, #by_town[cid])
  end
end

-- Ground a raider stands on to burn and be seen: fields and open country, not wood, marsh or crag (raids.cover:
-- g31's band rose in the wood west of Saltkeep and stood under its canopy, unseen, for the raid's first seasons).
local function raid_cover(t)
  local n = t.terrain:rule_name()
  for k in tostring(luadata.get_str("raids.cover") or "Forest,Jungle,Swamp,Mountains"):gmatch("[^,]+") do if n == k then return true end end
  return false
end

function realm_raid(city_id)
  local c = find.city(nil, city_id)
  if not c then log.normal("RAID no town %s", tostring(city_id)); return end
  local spots, covered = {}, {}
  for t in c.tile:square_iterate(2) do
    local n = t.terrain:rule_name()
    if t:city() == nil and t:num_units() == 0 and not n:find("Ocean") and n ~= "Lake" and c.tile:sq_distance(t) >= 4 then
      if raid_cover(t) then covered[#covered + 1] = t else spots[#spots + 1] = t end
    end
  end
  -- The band rises on the open ground round the town; in the wood only where there is none.
  if #spots == 0 then spots = covered end
  if #spots == 0 then log.normal("RAID no open ground by %s", c.name); return end
  local before = raiders_now()
  local spot = spots[random(1, #spots)]
  spot:unleash_barbarians()
  local raised = {}
  for id in pairs(raiders_now()) do if not before[id] then raised[#raised + 1] = id end end
  -- Wealth draws the raid: beside the few riders Freeciv unleashes (its land barbarians are Horsemen, cut down by a
  -- town's knights in a season or two, g29), a band of hardened men sized by the town's wealth, raids.band plus one
  -- for every raids.band_per of its size, of raids.kinds in turn at raids.veteran, spread over the open ground two out:
  -- men who can burn and carry off.
  local owner = #raised > 0 and find.unit(nil, raised[1]).owner or nil
  if owner then
    local kinds = {}
    for k in tostring(luadata.get_str("raids.kinds") or "Legion"):gmatch("[^,]+") do kinds[#kinds + 1] = find.unit_type(k) end
    local n = raid_num("band", 3) + math.floor(c.size / raid_num("band_per", 3))
    for i = 1, (#kinds > 0 and n or 0) do
      -- one to a tile of the open ground round the town, not stacked: one lost fight kills a stack (killstack)
      local u = edit.create_unit(owner, spots[(i - 1) % #spots + 1], kinds[(i - 1) % #kinds + 1], raid_num("veteran", 2), nil, -1)
      if u then raised[#raised + 1] = u.id end
    end
  end
  if #raised > 0 then
    local til = game.current_turn() + raid_seasons()
    for i, id in ipairs(raised) do raised[i] = string.format("%d", id) end
    GOC_RAIDS = GOC_RAIDS .. (GOC_RAIDS == "" and "" or ";") .. string.format("%s|%d|%d|0", table.concat(raised, ","), c.id, til)
  end
  log.normal("RAID %s raised %d", c.name, #raised)
end

-- A raider on spoiled ground pillages it; otherwise he steps to the next spoil by the town and starts there.
local function raid_pillage(u, t)
  local pillage = find.action("Pillage")
  for _, e in ipairs(RAID_SPOILS) do
    if t:has_extra(e) then
      local ok, done = pcall(edit.perform_action, u, pillage, t, e)
      if ok and done then log.normal("RAID pillage %s at (%d,%d)", e, t.x, t.y); return true end
    end
  end
  return false
end

local function raid_season(u, town)
  if raid_pillage(u, u.tile) then return end
  local best, bd = nil, nil
  for t in u.tile:square_iterate(1) do
    local clear = true
    for o in t:units_iterate() do if o.owner ~= u.owner then clear = false end end
    if t ~= u.tile and t:city() == nil and clear then
      for _, e in ipairs(RAID_SPOILS) do
        if t:has_extra(e) then
          local d = town and town.tile:sq_distance(t) or 0
          if not bd or d < bd then best, bd = t, d end
          break
        end
      end
    end
  end
  if best then
    pcall(edit.unit_move, u, best, 0, nil, false, false, false, false, false)
    if u.tile == best then raid_pillage(u, best) end
  elseif raid_cover(u.tile) then
    -- Nothing to burn in reach and standing in the wood: out onto the open ground nearest the town.
    local out, od = nil, nil
    for t in u.tile:square_iterate(1) do
      if t ~= u.tile and t:city() == nil and raid_open(t, u) and not raid_cover(t) then
        local d = town and town.tile:sq_distance(t) or 0
        if not od or d < od then out, od = t, d end
      end
    end
    if out then pcall(edit.unit_move, u, out, 0, nil, false, false, false, false, false) end
  end
end

-- The royal work a raid makes for: the King's town with a work, rising or standing, nearest the raid's own town and
-- within raids.work_reach tiles of it (the raid's town itself first when it has one); nil when none is.
local function raid_goal(town)
  if not town then return nil end
  local best, bd = nil, nil
  local reach = raid_num("work_reach", 6)
  for id in GOC_WORKS:gmatch("%d+") do
    local c = find.city(nil, tonumber(id))
    if c then
      local d = c.tile:sq_distance(town.tile)
      if d <= reach * reach and (not bd or d < bd) then best, bd = c, d end
    end
  end
  return best
end

-- A raider making for the work: up to raids.march_steps tiles a season over open land, each the open neighbour
-- nearest the work's town, by Freeciv's own unit_move; true while he is still more than a tile off it.
local function raid_march(u, goal)
  for _ = 1, raid_num("march_steps", 2) do
    if u.tile:sq_distance(goal.tile) <= 2 then return false end
    local best, bd = nil, u.tile:sq_distance(goal.tile)
    for t in u.tile:square_iterate(1) do
      if t ~= u.tile and raid_open(t, u) then
        local d = t:sq_distance(goal.tile) + (raid_cover(t) and 1 or 0)  -- open ground before wood at the same reach
        if d < bd then best, bd = t, d end
      end
    end
    if not best then return true end
    pcall(edit.unit_move, u, best, 0, nil, false, false, false, false, false)
    if u.tile ~= best then return true end
  end
  return u.tile:sq_distance(goal.tile) > 2
end

function realm_raids_turn()
  raids_take_in()
  if GOC_RAIDS == "" then return end
  local kept = {}
  for ids, city_id, til, was in GOC_RAIDS:gmatch("([%d,]+)|(%d+)|(%d+)|(%d+)") do
    local town = find.city(nil, tonumber(city_id))
    local alive = {}
    for id in ids:gmatch("%d+") do
      local u = find.unit(nil, tonumber(id))
      if u then alive[#alive + 1] = u end
    end
    if game.current_turn() >= tonumber(til) then
      -- The raid is over: the raiders walk off to wild land or the map's edge and go there (no man vanishes where he
      -- stood), for at most raids.leave_seasons seasons; then any still on the road go where they stand.
      local last = game.current_turn() >= tonumber(til) + raid_num("leave_seasons", 4)
      local left, gone = {}, 0
      for _, u in ipairs(alive) do
        local id = u.id
        if raid_leave(u, last) or not find.unit(nil, id) then gone = gone + 1 else left[#left + 1] = string.format("%d", id) end
      end
      if #left > 0 then kept[#kept + 1] = string.format("%s|%s|%s|%s", table.concat(left, ","), city_id, til, was) end
      log.normal("RAID over by %s: %d raiders gone, %d on the road out", town and town.name or city_id, gone, #left)
    elseif #alive > 0 then
      -- A royal work near the raid's town draws it first: the raiders march on its town, then burn the land round it.
      local goal = raid_goal(town)
      local gid = goal and goal.id or 0
      local left = {}
      for _, u in ipairs(alive) do
        local id = u.id
        if not (goal and raid_march(u, goal)) then raid_season(u, goal or town) end
        if find.unit(nil, id) then left[#left + 1] = string.format("%d", id) end
      end
      if gid ~= tonumber(was) then
        emit("raid_goal", {city = tonumber(city_id), goal = gid, units = table.concat(left, ",")})
        log.normal("RAID by %s makes for %s", town and town.name or city_id, goal and goal.name or "the land")
      end
      if #left > 0 then kept[#kept + 1] = string.format("%s|%s|%s|%d", table.concat(left, ","), city_id, til, gid) end
    end
  end
  GOC_RAIDS = table.concat(kept, ";")
end

-- Risings: a great house split by Freeciv's own civil war (edit.civil_war: Freeciv's odds from its government and its
-- unhappy and celebrating towns, or a fixed chance; about half its towns other than its seat go over to a new AI
-- player). Left alone, Freeciv's rebels sit still (measured: 0 attacks in 40 turns, docs/research/risings-civil-war-
-- 2026-11-12.md), so the rising has a host and a march: the rebels' men raised at their town nearest the lord's seat
-- (realm_host), walking each season by Freeciv's own moves on the lord's nearest town and assaulting it at the walls
-- (realm_assault, Freeciv's combat and conquest). After risings.seasons it settles itself: the side with more towns
-- keeps them (the rebels as a lesser house, or their towns go back to the lord). The bridge (risings.js) decides when
-- and how the King rules on it. Kept as a plain string ("rebel|house|until;..."), which the save keeps.
GOC_RISINGS = GOC_RISINGS or ""

local function rising_num(key, default) return tonumber(luadata.get_str("risings." .. key)) or default end

local function soldiers_of(p)
  local out = {}
  for u in p:units_iterate() do if not u.utype:has_flag("NonMil") and u.utype:can_exist_at_tile(u.tile) then out[#out + 1] = u end end
  return out
end

local function nearest_town(p, from)
  local best, bd = nil, nil
  for c in p:cities_iterate() do
    local d = c.tile:sq_distance(from)
    if not bd or d < bd then best, bd = c, d end
  end
  return best
end

function realm_rising(house_id, chance)
  local p = realm_find_player(house_id)
  if not p then return end
  local r = edit.civil_war(p, chance or 0)
  if not r then emit("rising", {house = house_id, rebel = -1}); return end
  local seat = nil
  for c in p:cities_iterate() do if c:is_capital() then seat = c end end
  seat = seat or nearest_town(p, r:cities_iterate()().tile)
  local muster = nearest_town(r, seat.tile)
  local kinds = {}
  for k in tostring(luadata.get_str("risings.host_kinds") or "Pikemen,Archers,Knights"):gmatch("[^,]+") do kinds[#kinds + 1] = k end
  realm_host(r, muster.tile.x, muster.tile.y, kinds, rising_num("host", 6))
  -- The host is the rising's, not its AI's: held from Freeciv's AI (which would spend its moves wandering) and
  -- freed only for its march and assault each season (realm_risings_phase), as the homeward march is.
  for _, u in ipairs(soldiers_of(r)) do edit.movement_disallow(u) end
  local banners = find.building_type("Rebel Banners")
  if banners then edit.create_building(muster, banners) end
  local til = game.current_turn() + rising_num("seasons", 8)
  GOC_RISINGS = GOC_RISINGS .. (GOC_RISINGS == "" and "" or ";") .. string.format("%d|%d|%d|%d", r.id, house_id, til, seat.id)
  local towns = {}
  for c in r:cities_iterate() do towns[#towns + 1] = string.format("%d", c.id) end
  emit("rising", {house = house_id, rebel = r.id, towns = table.concat(towns, ","), muster = muster.id, til = til})
end

-- Freeciv's own odds that a house splits if a rising is tried now (plrhand.c civil_war_triggered): its
-- government's Civil_War_Chance, +5 for each unhappy town and -5 for each celebrating one (game.ruleset
-- civil_war_bonus_unhappy / civil_war_bonus_celebrating; rising_probe checks they still match). Reports
-- "rising_odds", so the King sees the chance before it's rolled, and what a feast or relief does to it.
function realm_rising_odds(house_id)
  local p = realm_find_player(house_id)
  if not p then return end
  local odds, unhappy, glad, towns = effects.player_bonus(p, "Civil_War_Chance"), 0, 0, 0
  for c in p:cities_iterate() do
    towns = towns + 1
    if c:is_unhappy() then unhappy = unhappy + 1 end
    if c:is_celebrating() then glad = glad + 1 end
  end
  odds = math.max(0, math.min(100, odds + 5 * unhappy - 5 * glad))
  emit("rising_odds", {house = house_id, odds = odds, unhappy = unhappy, celebrating = glad, towns = towns})
end

-- How a rising ends (id: the rebels' player or the house they rose in): "return" (the rebels' towns go back to the lord by Freeciv's transfer, their men disband),
-- "keep" (the rebels hold what they hold, a lesser house), "auto" (the side with more towns keeps them).
function realm_rising_end(id, how)
  local kept = {}
  local rebel, house, rebel_id = nil, nil, nil
  for rid, hid, til, seat in GOC_RISINGS:gmatch("(%d+)|(%d+)|(%d+)|(%d+)") do
    if (tonumber(rid) == id or tonumber(hid) == id) and not rebel then
      rebel_id = tonumber(rid)
      rebel, house = realm_find_player(rebel_id), realm_find_player(tonumber(hid))
    else kept[#kept + 1] = rid .. "|" .. hid .. "|" .. til .. "|" .. seat end
  end
  GOC_RISINGS = table.concat(kept, ";")
  if not rebel then return end
  if not house then emit("rising_over", {house = -1, rebel = rebel_id, how = "keep", towns = 0}); return end
  local mine, theirs = 0, 0
  for c in rebel:cities_iterate() do mine = mine + 1 end
  for c in house:cities_iterate() do theirs = theirs + 1 end
  if how == "auto" then how = theirs >= mine and "return" or "keep" end
  local banners = find.building_type("Rebel Banners")
  if banners then for c in rebel:cities_iterate() do if c:has_building(banners) then edit.remove_building(c, banners) end end end
  if how == "return" then
    local towns = {}
    for c in rebel:cities_iterate() do towns[#towns + 1] = c end
    for _, c in ipairs(towns) do edit.transfer_city(c, house) end
    local disband = find.action("Disband Unit")
    local men = {}
    for u in rebel:units_iterate() do men[#men + 1] = u end
    for _, u in ipairs(men) do pcall(edit.perform_action, u, disband) end
  end
  local left = 0
  for c in house:cities_iterate() do left = left + 1 end
  emit("rising_over", {house = house.id, rebel = rebel_id, how = how, towns = mine, lord = left})
end

function realm_risings_turn()
  if GOC_RISINGS == "" then return end
  local todo = {}
  for rid, hid, til, seat in GOC_RISINGS:gmatch("(%d+)|(%d+)|(%d+)|(%d+)") do todo[#todo + 1] = {tonumber(rid), tonumber(hid), tonumber(til), tonumber(seat)} end
  for _, r in ipairs(todo) do
    local rebel, house = realm_find_player(r[1]), realm_find_player(r[2])
    local towns = 0
    if rebel then for c in rebel:cities_iterate() do towns = towns + 1 end end
    local held = 0
    if house and house.is_alive then for c in house:cities_iterate() do held = held + 1 end end
    if held == 0 then
      realm_rising_end(r[1], "keep")  -- the lord's house is gone: the rising has won
    elseif not (rebel and rebel.is_alive and towns > 0) then
      realm_rising_end(r[1], "return")  -- crushed
    elseif find.city(nil, r[4]) == nil or find.city(nil, r[4]).owner == rebel then
      realm_rising_end(r[1], "keep")  -- the lord's seat has fallen to them: the rising has won what it holds
    elseif game.current_turn() >= r[3] then
      realm_rising_end(r[1], "auto")
    end
  end
end

-- The rebels' own phase, their men's moves restored: the host marches on the lord's nearest town, a few tiles a season, and
-- strikes at its walls (Freeciv's Attack needs moves left, so not at the turn's start).
function realm_risings_phase(rebel)
  if GOC_RISINGS == "" then return end
  local speed = rising_num("speed", 2)
  for rid, hid, seat_id in GOC_RISINGS:gmatch("(%d+)|(%d+)|%d+|(%d+)") do
    local house = realm_find_player(tonumber(hid))
    if tonumber(rid) == rebel.id and house and house.is_alive then
      -- They march on the lord's seat, the prize of a succession fight, not on every town in reach: take it and
      -- the rising has won; hold it and the house stays two (a split, settled at the end).
      local men = soldiers_of(rebel)
      local target = find.city(nil, tonumber(seat_id))
      if target then
        local at_walls = 0
        for _, u in ipairs(men) do
          edit.movement_allow(u)
          for i = 1, speed do
            if u.tile:sq_distance(target.tile) <= 2 then break end
            local best, bd = nil, u.tile:sq_distance(target.tile)
            for t in u.tile:square_iterate(1) do
              local clear = t:city() == nil and t.terrain:class_name() == "Land"
              for o in t:units_iterate() do if o.owner ~= rebel then clear = false end end
              local d = t:sq_distance(target.tile)
              if clear and d < bd then best, bd = t, d end
            end
            if not best then break end
            pcall(edit.unit_move, u, best, 0, nil, false, false, false, false, false)
            if u.tile ~= best then break end
          end
          if u.tile:sq_distance(target.tile) <= 2 then at_walls = at_walls + 1 end
        end
        log.normal("RISING %d marches on %s: %d of %d at the walls", rebel.id, target.name, at_walls, #men)
        if at_walls > 0 then realm_assault(target.id, rebel.id) end
        for _, u in ipairs(soldiers_of(rebel)) do edit.movement_disallow(u) end
      end
    end
  end
end

-- Every house's books (READY.md line 12, income by source per house): where its gold came from each season.
-- The season opens at turn_begin: what the purse moved since the last close is the house's towns (Freeciv's own
-- taxes, less its upkeep and what its towns buy) and the bridge's dealings (every gold the bridge moves goes
-- through realm_gold). The ruleset's own moves this turn are booked as they happen (realm_book: the seams'
-- "mines", the "tithe", the Royal Court's "court"); the close reports "income" (by: "id:towns:mines:tithe:court:
-- dealings:purse;...", the purse as the close leaves it; crown: its id) and takes each purse as the next season's start. Plain text globals, which the
-- save keeps ("id:gold;..." at the close, "id:gold;..." dealt since). A house first seen at a close reports from
-- the next season on.
GOC_BOOKS = GOC_BOOKS or ""
GOC_DEALT = GOC_DEALT or ""
local BOOK_SOURCES = {"towns", "mines", "tithe", "court", "dealings"}
local season_books = {}

local function book_read(text)
  local t = {}
  for id, g in tostring(text):gmatch("(%-?%d+):(%-?%d+)") do t[tonumber(id)] = tonumber(g) end
  return t
end
local function book_write(t)
  local rows = {}
  for id, g in pairs(t) do rows[#rows + 1] = string.format("%d:%d", id, g) end
  return table.concat(rows, ";")
end

function realm_book(pid, source, amount)
  local b = season_books[pid]
  if b then b[source] = b[source] + amount end
end

-- Gold the bridge gives (or takes, negative) a house: a decree's price, a gift, a debt (lua.js gold and pay).
function realm_gold(pid, amount)
  local p = realm_find_player(pid)
  amount = math.floor(tonumber(amount) or 0)
  if not p or amount == 0 then return end
  edit.change_gold(p, amount)
  local dealt = book_read(GOC_DEALT)
  dealt[p.id] = (dealt[p.id] or 0) + amount
  GOC_DEALT = book_write(dealt)
end

function realm_books_open()
  local start, dealt = book_read(GOC_BOOKS), book_read(GOC_DEALT)
  season_books = {}
  for p in players_iterate() do
    if p.is_alive and start[p.id] then
      local d = dealt[p.id] or 0
      season_books[p.id] = {towns = p:gold() - start[p.id] - d, mines = 0, tithe = 0, court = 0, dealings = d}
    end
  end
  GOC_DEALT = ""
end

function realm_books_close()
  local crown, rows, start = -1, {}, {}
  for p in players_iterate() do
    if p.is_alive then
      start[p.id] = p:gold()
      if p.nation and p.nation:rule_name() == "Norman" then crown = p.id end
      local b = season_books[p.id]
      if b then
        local r = {p.id}
        for _, k in ipairs(BOOK_SOURCES) do r[#r + 1] = b[k] end
        r[#r + 1] = p:gold()  -- the purse at the close
        rows[#rows + 1] = table.concat(r, ":")
      end
    end
  end
  GOC_BOOKS = book_write(start)
  season_books = {}
  if #rows > 0 then emit("income", {by = table.concat(rows, ";"), crown = crown}) end
end

-- The crown's purse each season (READY.md line 12: the tithe and the Royal Court's upkeep in Freeciv): every great
-- house pays its tithe, the rate of what its towns yield (their size), handing over what it can spare from its
-- purse (purse.house_pays) while the rest is taken at its town gates; the crown receives it all, less the Royal
-- Court's upkeep (purse.court_base, purse.court_per_town for each crown town, purse.court_share of the purse).
-- The rate is the King's tithe as the bridge last set it (realm_tithe_rate: his rate, thinned by the realm's wars),
-- kept with the save. Reports "purse" (what came in, what the court cost, each house's take).
GOC_TITHE_RATE = GOC_TITHE_RATE or 0
function realm_tithe_rate(rate) GOC_TITHE_RATE = tonumber(rate) or 0 end

local function purse_num(key, default) return tonumber(luadata.get_str("purse." .. key)) or default end

local function tithed(p)
  local n = p.nation and p.nation:rule_name() or ""
  return p.is_alive and n ~= "Norman" and n ~= "Barbarian" and n ~= "Pirate" and n ~= "Animal Kingdom" and p.name ~= "The Dead"
end

function realm_purse()
  local crown = nil
  for p in players_iterate() do if p.nation and p.nation:rule_name() == "Norman" then crown = p end end
  if not crown then return end
  local per, pays, total, takes = purse_num("per_size", 7.5), purse_num("house_pays", 0.25), 0, {}
  if GOC_TITHE_RATE > 0 then
    for p in players_iterate() do
      if tithed(p) then
        local size = 0
        for c in p:cities_iterate() do size = size + c.size end
        local take = math.floor(size * per * GOC_TITHE_RATE)
        if take > 0 then
          local paid = math.min(take, math.floor(math.max(0, p:gold()) * pays))
          if paid > 0 then edit.change_gold(p, -paid) realm_book(p.id, "tithe", -paid) end
          total = total + take
          takes[#takes + 1] = string.format("%d:%d", p.id, take)
        end
      end
    end
  end
  local towns = 0
  for c in crown:cities_iterate() do towns = towns + 1 end
  local court = purse_num("court_base", 2) + purse_num("court_per_town", 2) * towns + math.floor(math.max(0, crown:gold()) * purse_num("court_share", 0.02))
  local upkeep = math.min(court, math.max(0, crown:gold() + total))
  if total - upkeep ~= 0 then edit.change_gold(crown, total - upkeep) end
  realm_book(crown.id, "tithe", total)
  realm_book(crown.id, "court", -upkeep)
  emit("purse", {total = total, upkeep = upkeep, takes = table.concat(takes, ";")})
end

-- Men raised in a town for its house, homed there so Freeciv charges their upkeep (a levy, sellswords, a garrison,
-- a story's or a petition's men). kinds: "Knights,Pikemen|Warriors": one company each, the first type of each
-- "|" list that the ruleset has. vet: their veteran level. The bridge's one call for it is Lua.levy (lua.js).
function realm_levy(city_id, kinds, vet)
  local c = find.city(nil, city_id)
  if not c then return end
  for alts in tostring(kinds):gmatch("[^,]+") do
    local t = nil
    for a in alts:gmatch("[^|]+") do t = t or find.unit_type(a) end
    if t then edit.create_unit(c.owner, c.tile, t, vet or 1, c, -1) end
  end
end

-- A building set down in a town or taken up (a royal work finished, a famine's granary, a breach's walls, a test).
function realm_building(city_id, name, on)
  local c, b = find.city(nil, city_id), find.building_type(name)
  if not (c and b) then return end
  if on and not c:has_building(b) then edit.create_building(c, b) end
  if not on and c:has_building(b) then edit.remove_building(c, b) end
end

-- A house's fighting men taken off (banners raised again for the crown elsewhere; a small royal host never raised):
-- n of them, never its workers, settlers or scouts.
function realm_take_men(pid, n)
  local p = realm_find_player(pid)
  if not p then return end
  local men = {}
  for u in p:units_iterate() do if not u.utype:has_flag("NonMil") and #men < n then men[#men + 1] = u end end
  for _, u in ipairs(men) do edit.unit_kill(u, "disbanded", nil) end
end

-- Decree buildings (buildings.ruleset "Royal Feast", "Royal Relief", "Blight", "Heavy Tithe"; their effects in
-- effects.ruleset). The King's decree sets one down in a town for a number of seasons (luadata.txt
-- [decrees]); each turn the lapsed ones are taken up. Kept as a plain string ("city,building,until;..."),
-- which the save keeps.
GOC_DECREES = GOC_DECREES or ""
local DECREE_BUILDING = {feast = "Royal Feast", relief = "Royal Relief", blight = "Blight"}

function realm_decree(city_id, kind, seasons)
  local c = find.city(nil, city_id)
  local name = DECREE_BUILDING[kind]
  local b = name and find.building_type(name)
  if not (c and b) then log.normal("DECREE no %s in %s", tostring(kind), tostring(city_id)); return end
  if not c:has_building(b) then edit.create_building(c, b) end
  local til = game.current_turn() + (seasons or tonumber(luadata.get_str("decrees." .. kind)) or 1)
  local kept = {}
  for id, bn, t in GOC_DECREES:gmatch("(%d+),([^,;]+),(%d+)") do
    if not (tonumber(id) == city_id and bn == name) then kept[#kept + 1] = string.format("%s,%s,%s", id, bn, t) end
  end
  kept[#kept + 1] = string.format("%d,%s,%d", city_id, name, til)
  GOC_DECREES = table.concat(kept, ";")
end

function realm_decrees_lapse()
  local turn, kept = game.current_turn(), {}
  for id, bn, t in GOC_DECREES:gmatch("(%d+),([^,;]+),(%d+)") do
    local c, b = find.city(nil, tonumber(id)), find.building_type(bn)
    if c and b and tonumber(t) > turn then kept[#kept + 1] = string.format("%s,%s,%s", id, bn, t)
    elseif c and b and c:has_building(b) then
      edit.remove_building(c, b)
      emit("decree_lapsed", {city = c.id, building = bn})
    end
  end
  GOC_DECREES = table.concat(kept, ";")
end

-- A mark a house bears ("Heavy Tithe", "Grievance", small wonders felt in all its towns): the houses
-- ("3,5,6", player ids) bear it in their seat, every other town is free of it.
function realm_bear(name, houses)
  local bearing = {}
  for id in tostring(houses or ""):gmatch("%d+") do bearing[tonumber(id)] = true end
  local b = find.building_type(name)
  if not b then log.normal("BEAR no building %s", tostring(name)); return end
  for p in players_iterate() do
    for c in p:cities_iterate() do
      local want = bearing[p.id] and c:is_primary_capital()
      if want and not c:has_building(b) then edit.create_building(c, b)
      elseif not want and c:has_building(b) then edit.remove_building(c, b) end
    end
  end
end

-- The King's word to take a town (actions.ruleset: the crown conquers only while its Royal Warrant stands):
-- raised in one of the crown's towns for the moment of the march-in, and taken down again. Only the crown
-- needs it; returns whether it raised one.
function realm_warrant(p, up)
  local b = find.building_type("Royal Warrant")
  if not b or not p or not p.nation or p.nation:rule_name() ~= "Norman" then return false end
  for c in p:cities_iterate() do
    if up and not c:has_building(b) then edit.create_building(c, b); return true end
    if not up and c:has_building(b) then edit.remove_building(c, b) end
  end
  return false
end

-- A town is taken, never razed (Mac, 2026-11-12: capturing must never lose a town the world had). Freeciv's
-- conquest always costs a town one townsman and razes a size-1 one (citytools.c unit_conquer_city; no ruleset
-- or server setting changes it), so a hamlet about to be taken first gains one by Freeciv's own Join City: a
-- settler of its own house joins it, and the conquest takes him instead.
function realm_spare_hamlet(c)
  if not c or c.size > 1 then return end
  local kind = find.unit_type("Migrants") or find.unit_type("Settlers")
  local ok, u = pcall(edit.create_unit, c.owner, c.tile, kind, 0, c, -1)
  if not (ok and u) then return end
  local id = u.id
  pcall(edit.perform_action, u, find.action("Join City"), c)
  local left = find.unit(nil, id)  -- refused: the settler doesn't stay
  if left then edit.unit_kill(left, "disbanded", nil) end
end

-- The King's assault on a house's town (the crown is at war with it: the bridge's one diplomacy writer):
-- each of the crown's fighting men beside its walls strikes once (Freeciv's combat: walls, veterans,
-- terrain), and when no defender is left one of them marches in and takes it (Freeciv's own conquest:
-- a size-1 town is razed, a bigger one shrinks and changes hands). The crown's AI takes no town
-- unbidden (actions.ruleset forbids Norman "Conquer City"); this is the King's bidding. Reports "assault"
-- with the blows struck and who holds the town after (-1: razed).
function realm_assault(city_id, crown_id)
  local c, crown = find.city(nil, city_id), find.player(crown_id)
  if not (c and crown) then return end
  local attack, tile = find.action("Attack"), c.tile
  local men = {}
  for t in tile:square_iterate(1) do
    if t ~= tile then
      for u in t:units_iterate() do
        if u.owner == crown and not u.utype:has_flag("NonMil") then men[#men + 1] = u.id end
      end
    end
  end
  local blows = 0  -- attacks Freeciv let happen (perform_action is false when refused)
  for _, id in ipairs(men) do
    local u, town = find.unit(crown, id), find.city(nil, city_id)
    if u and town and town.owner ~= crown then
      if tile:num_units() > 0 then
        local ok, done = pcall(edit.perform_action, u, attack, tile)
        if ok and done then blows = blows + 1 end
      else
        realm_spare_hamlet(town)
        edit.movement_allow(u)  -- a host held at the walls (its AI kept from wandering it off) marches in on the order
        local warrant = realm_warrant(u.owner, true)
        pcall(edit.unit_move, u, tile, 0, nil, false, true, false, false, false)
        if warrant then realm_warrant(u.owner, false) end
      end
    end
  end
  local after = find.city(nil, city_id)
  emit("assault", {city = city_id, men = #men, blows = blows, owner = after and after.owner.id or -1})
end

-- Men a decree sends home (hosts.js homeward orders): held from their house's AI while they march
-- (edit.movement_disallow), walked by Freeciv's own moves, and at their seat disbanded into its work
-- (Disband Unit Recover: half their shields to the town's production); kept as its garrison if
-- Freeciv refuses. No unit vanishes.
function realm_hold(ids)
  for id in tostring(ids or ""):gmatch("%d+") do
    local u = find.unit(nil, tonumber(id))
    if u then edit.movement_disallow(u) end
  end
end

function realm_walk_home(id, way)
  local u = find.unit(nil, id)
  if not u then return end
  edit.movement_allow(u)
  for x, y in tostring(way or ""):gmatch("(%d+),(%d+)") do
    local t = find.tile(tonumber(x), tonumber(y))
    if not t then break end
    pcall(edit.unit_move, u, t, 0, nil, false, false, false, false, false)
    if u.tile ~= t then break end
  end
  edit.movement_disallow(u)
end

function realm_disband_home(id, city_id)
  local u, c = find.unit(nil, id), find.city(nil, city_id)
  if not (u and c) then return end
  edit.movement_allow(u)
  local ok, done = pcall(edit.perform_action, u, find.action("Disband Unit Recover"), c)
  if not (ok and done) then log.normal("HOMEWARD %d stays in %s as its garrison", id, c.name) end
end

-- Men who can go no nearer home (or whose seat is lost) are their house's AI's again, where they stand.
-- The King's host takes ship (bridge hosts.js crossing): each company boards one of the hulls named, on the water
-- beside it (the hull's room is the ruleset's transport_cap).
local function realm_ferry_board(units, hulls)
  -- The host steps aboard the hulls raised beside it as part of the one decree, by Freeciv's own unit_move (its
  -- embark bookkeeping: the company becomes the hull's cargo), not by Transport Embark: that wants a move left, and
  -- a host raises its ships the season it reaches the shore, its moves spent on the road (crossing_reign_probe: on
  -- Aldmere "FERRY board 0 of 1", the host camped). Each hull takes what its type may carry, up to its capacity.
  -- Aboard, each company and hull is held from the AI (it goes where its hull goes; the bridge lets a hull go to sail).
  -- All or none: a company left on the shore brings back those already aboard, and the bridge is told false.
  local hs, us = {}, {}
  for id in tostring(hulls or ""):gmatch("%d+") do
    local h = find.unit(nil, tonumber(id))
    if h then hs[#hs + 1] = h end
  end
  for id in tostring(units or ""):gmatch("%d+") do us[#us + 1] = {u = find.unit(nil, tonumber(id))} end
  local ok = 0
  for _, c in ipairs(us) do
    local u = c.u
    if u then
      c.from = u.tile
      edit.movement_allow(u)
      for _, h in ipairs(hs) do
        if u:transporter() then break end
        pcall(edit.unit_move, u, h.tile, 0, h, false, false, false, false, false)
      end
      if u:transporter() then ok = ok + 1 end
    end
  end
  log.normal("FERRY board %d of %d", ok, #us)
  if ok < #us then
    for _, c in ipairs(us) do
      if c.u and c.u:transporter() then pcall(edit.unit_move, c.u, c.from, 0, nil, true, false, false, false, false) end
    end
    return false
  end
  for _, c in ipairs(us) do edit.movement_disallow(c.u) end
  for _, h in ipairs(hs) do edit.movement_disallow(h) end
  return true
end

-- The crown raises the King's host its ships (bridge hosts.js crossing; the supervisor's ruling, 2026-11-12): `ships`
-- Triremes on the water tile (x, y) beside the shore where the host stands, paid from the treasury (`cost` gold,
-- realm_gold: booked as the crown's dealings), then the host boards them. Nothing is raised when the crown can't pay.
function realm_ferry_raise(pid, units, x, y, ships, cost)
  local p = realm_find_player(pid)
  local t = find.tile(x, y)
  local ut = find.unit_type("Trireme")
  if not (p and t and ut) then log.normal("FERRY raise 0 of %d: no crown, water or ship", ships); return end
  if p:gold() < cost then log.normal("FERRY raise 0 of %d: the treasury holds %d of %d", ships, p:gold(), cost); return end
  local ids = {}
  for i = 1, ships do
    local ok, u = pcall(edit.create_unit, p, t, ut, 0, nil, -1)
    if ok and u then ids[#ids + 1] = string.format("%d", u.id) end
  end
  if #ids < ships then
    for id in table.concat(ids, ","):gmatch("%d+") do local u = find.unit(nil, tonumber(id)); if u then edit.unit_kill(u, "disbanded", nil) end end
    log.normal("FERRY raise 0 of %d: the water took no ship", ships)
    return
  end
  log.normal("FERRY raise %d of %d", #ids, ships)
  if not realm_ferry_board(units, table.concat(ids, ",")) then
    -- Not all aboard (a company a Trireme can't carry): no ship sails half a host; none raised, nothing paid.
    for _, id in ipairs(ids) do local u = find.unit(nil, tonumber(id)); if u then edit.unit_kill(u, "disbanded", nil) end end
    return
  end
  realm_gold(p.id, -cost)
end

-- The King's host comes ashore on the tile (x, y) beside its hulls, by Freeciv's own unit_move (its disembark
-- bookkeeping), as it boarded (realm_ferry_board: the crossing is the crown's one decree, whatever moves the men have
-- left); never onto a tile another's men hold. The ships, raised for this crossing alone, then sail off and go
-- (realm_ferry_off, realm_ferry_gone; the bridge's hosts.js shipsOff).
function realm_ferry_land(units, x, y)
  local t = find.tile(x, y)
  local n, ok = 0, 0
  for id in tostring(units or ""):gmatch("%d+") do
    local u = find.unit(nil, tonumber(id))
    n = n + 1
    if u and t then
      edit.movement_allow(u)
      local theirs = false
      for v in t:units_iterate() do if v.owner ~= u.owner then theirs = true end end
      if u:transporter() and not theirs then pcall(edit.unit_move, u, t, 0, nil, true, false, false, false, false) end
      if u.tile == t then ok = ok + 1 end  -- ashore, free to march on (the bridge holds it again if its order does)
    end
  end
  log.normal("FERRY land %d of %d", ok, n)
end

-- Whether a hull still carries men (a ship sailed off or disbanded with men aboard would take or drown them).
local function ferry_laden(h)
  for v in h.tile:units_iterate() do
    local tr = v:transporter()
    if tr and tr.id == h.id then return true end
  end
  return false
end

-- A hull that has put its host ashore sails off toward open sea (bridge hosts.js shipsOff): along `way` ("x,y;..."),
-- by Freeciv's own unit_move as a host's road (realm_walk_home), only when it carries no one.
function realm_ferry_off(id, way)
  local h = find.unit(nil, id)
  if h and not ferry_laden(h) then realm_walk_home(id, way) end
end

-- The hulls go, out at sea (a season after they put their host ashore): each disbanded unless it still carries men.
function realm_ferry_gone(hulls)
  local gone = 0
  for id in tostring(hulls or ""):gmatch("%d+") do
    local h = find.unit(nil, tonumber(id))
    if h and not ferry_laden(h) then edit.unit_kill(h, "disbanded", nil); gone = gone + 1 end
  end
  log.normal("FERRY gone %d", gone)
end

function realm_release(ids)
  for id in tostring(ids or ""):gmatch("%d+") do
    local u = find.unit(nil, tonumber(id))
    if u then edit.movement_allow(u) end
  end
end
