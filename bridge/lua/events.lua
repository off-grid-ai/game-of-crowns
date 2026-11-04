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
  {"turn_begin", "ev_turn"},
}
for _, h in ipairs(hooks) do
  local ok, err = pcall(signal.connect, h[1], h[2])
  if not ok then log.normal("HOOKFAIL %s %s", h[1], tostring(err)) end
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
