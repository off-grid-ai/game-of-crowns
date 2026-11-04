-- Unsafe-instance script: dumps the whole world to JSON files for the Godot view.
-- Run by the bridge after every turn with `lua unsafe-file`.

-- The bridge sets SNAP_DIR to the active chronicle's state folder.
local DIR = SNAP_DIR or "/Users/user/wednesday/civilization/bridge/state/"

local BUILDINGS = {
  "Palace", "City Walls", "Granary", "Temple", "Barracks", "Marketplace", "Library",
  "Aqueduct", "Amphitheater", "Colosseum", "Harbor", "Courthouse", "Cathedral",
  "Great Wall", "Pyramids", "Hanging Gardens", "Great Library", "Colossus",
  "Lighthouse", "Oracle", "Temple of Artemis", "Statue of Zeus", "Mausoleum of Mausolos",
}

local function q(s) return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' end
local function n(v) return string.format("%d", v) end

local btypes = {}
for _, name in ipairs(BUILDINGS) do
  local b = find.building_type(name)
  if b then btypes[#btypes + 1] = {name, b} end
end

local players, cities, units = {}, {}, {}
for p in players_iterate() do
  if not p.is_alive or not p.nation then goto continue end
  local ncities = 0
  for c in p:cities_iterate() do
    ncities = ncities + 1
    local bl = {}
    for _, pair in ipairs(btypes) do
      if c:has_building(pair[2]) then bl[#bl + 1] = q(pair[1]) end
    end
    cities[#cities + 1] = string.format(
      '{"id":%s,"name":%s,"owner":%s,"x":%s,"y":%s,"size":%s,"capital":%s,"buildings":[%s]}',
      n(c.id), q(c.name), n(p.id), n(c.tile.x), n(c.tile.y), n(c.size),
      tostring(c:is_capital()), table.concat(bl, ","))
  end
  local nunits = 0
  for u in p:units_iterate() do
    nunits = nunits + 1
    units[#units + 1] = string.format('{"id":%s,"owner":%s,"type":%s,"x":%s,"y":%s}',
      n(u.id), n(p.id), q(u.utype:rule_name()), n(u.tile.x), n(u.tile.y))
  end
  players[#players + 1] = string.format(
    '{"id":%s,"name":%s,"nation":%s,"gold":%s,"cities":%s,"units":%s,"government":%s}',
    n(p.id), q(p.name), q(p.nation:rule_name()), n(p:gold()), n(ncities), n(nunits),
    q(p.government:rule_name()))
  ::continue::
end

-- Roads the houses' workers have built, so the view can draw the real network.
local roads = {}
for t in whole_map_iterate() do
  local ok, has = pcall(function() return t:has_extra("Road") end)
  if ok and has then roads[#roads + 1] = string.format("[%d,%d]", t.x, t.y) end
end

local f = io.open(DIR .. "world.tmp", "w")
if not f then return end
f:write(string.format('{"turn":%s,"year":%s,"players":[%s],"cities":[%s],"units":[%s],"roads":[%s]}',
  n(game.current_turn()), n(game.current_year()),
  table.concat(players, ","), table.concat(cities, ","), table.concat(units, ","), table.concat(roads, ",")))
f:close()
os.rename(DIR .. "world.tmp", DIR .. "world.json")

-- Terrain only changes rarely; write it once.
local existing = io.open(DIR .. "map.json", "r")
if existing then
  existing:close()
else
  local w, h, tiles = 0, 0, {}
  for t in whole_map_iterate() do
    if t.x + 1 > w then w = t.x + 1 end
    if t.y + 1 > h then h = t.y + 1 end
    local name = t.terrain:rule_name()
    local ok, r = pcall(function() return t:has_extra("River") end)
    if ok and r then name = name .. "|river" end
    tiles[#tiles + 1] = string.format('[%d,%d,%s]', t.x, t.y, q(name))
  end
  local m = io.open(DIR .. "map.json", "w")
  m:write(string.format('{"width":%d,"height":%d,"tiles":[%s]}', w, h, table.concat(tiles, ",")))
  m:close()
end
