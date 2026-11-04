-- Emit every interesting simulation event as one JSON-ish line for the narrator.
local function emit(kind, fields)
  local parts = {}
  for k, v in pairs(fields) do parts[#parts + 1] = string.format('"%s":"%s"', k, tostring(v)) end
  log.normal('EVENT {"turn":"%d","kind":"%s",%s}', game.current_turn(), kind, table.concat(parts, ","))
end

function on_city_built(city)
  emit("city_built", {city = city.name, owner = city.owner.name})
end
function on_city_size_change(city, change, reason)
  if reason ~= "growth" or city.size % 4 == 0 then
    emit("city_size", {city = city.name, owner = city.owner.name, change = change, reason = reason, size = city.size})
  end
end
function on_city_destroyed(city, loser, destroyer)
  emit("city_destroyed", {city = city.name, loser = loser.name, destroyer = destroyer and destroyer.name or "none"})
end
function on_city_transferred(city, old, new, reason)
  emit("city_transferred", {city = city.name, from = old.name, to = new.name, reason = reason})
end
function on_disaster(disaster, city, had_effect)
  emit("disaster", {disaster = disaster:rule_name(), city = city.name, owner = city.owner.name})
end
function on_player_destroyed(player)
  emit("kingdom_fell", {player = player.name})
end
function on_civil_war(player)
  emit("civil_war", {player = player.name})
end
function on_turn(turn, year)
  for p in players_iterate() do
    if p.is_alive then
      local n, pop = 0, 0
      for c in p:cities_iterate() do n = n + 1; pop = pop + c.size end
      if turn % 10 == 0 then emit("census", {player = p.name, cities = n, size = pop, gold = p:gold()}) end
    end
  end
end

signal.connect("city_built", "on_city_built")
signal.connect("city_size_change", "on_city_size_change")
signal.connect("city_destroyed", "on_city_destroyed")
signal.connect("city_transferred", "on_city_transferred")
signal.connect("disaster_occurred", "on_disaster")
signal.connect("player_destroyed", "on_player_destroyed")
signal.connect("civil_war", "on_civil_war")
signal.connect("turn_begin", "on_turn")
