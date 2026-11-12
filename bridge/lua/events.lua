-- Ruleset-instance script: turns Freeciv signals into EVENT lines the bridge reads from stdout.
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
