-- The setup logic shared by every generated world_setup.lua (towns, starting units, the royal host).
local function place_town(p, x, y, name)
  local t = find.tile(x, y)
  if t and not t:city() then edit.create_city(p, t, name) end
end

function realm_setup()
  for p in players_iterate() do
    for u in p:units_iterate() do edit.unit_kill(u, "killed", nil) end
    for c in p:cities_iterate() do edit.remove_city(c) end
  end
  for y = 0, H - 1 do
    local row = ROWS[y + 1]
    for x = 0, W - 1 do
      local t = find.tile(x, y)
      local want = TERRAIN[row:sub(x + 1, x + 1)]
      if t and want and t.terrain:rule_name() ~= want then edit.change_terrain(t, find.terrain(want)) end
    end
  end
  for _, r in ipairs(RIVERS) do
    local t = find.tile(r[1], r[2])
    if t then pcall(edit.create_owned_extra, t, "River", nil) end
  end
  for p in players_iterate() do
    for _, h in ipairs(HOUSES) do
      if p.nation:rule_name() == h.nation then
        place_town(p, h.x, h.y, h.seat)
        log.normal("REALM_SETUP %s seat %s at (%d,%d) terrain %s city %s", p.name, h.seat, h.x, h.y, find.tile(h.x, h.y).terrain:rule_name(), tostring(find.tile(h.x, h.y):city()))
        local seat = find.tile(h.x, h.y)
        -- Daughter towns a few days' ride from the seat, on good land.
        local placed = 0
        for t in seat:square_iterate(4) do
          if placed >= #h.towns then break end
          local n = t.terrain:rule_name()
          local dx, dy = math.abs(t.x - h.x), math.abs(t.y - h.y)
          if (dx >= 3 or dy >= 3) and (n == "Grassland" or n == "Plains" or n == "Hills") and not t:city() then
            placed = placed + 1
            place_town(p, t.x, t.y, h.towns[placed])
          end
        end
        local units = {{"Settlers", 2}, {"Workers", 2}, {"Warriors", 2}, {"Archers", 1}, {"Horsemen", 1}}
        for _, pair in ipairs(units) do
          local ut = find.unit_type(pair[1])
          for i = 1, pair[2] do
            local ok, err = pcall(edit.create_unit, p, seat, ut, 0, seat:city(), -1)
            if not ok then log.normal("REALM_SETUP unit %s failed at %s (%d,%d): %s", pair[1], h.seat, h.x, h.y, tostring(err)) end
          end
        end
      end
    end
  end
  -- The Crown: Kingsmere and the royal host.
  for p in players_iterate() do
    if p.nation:rule_name() == "Norman" then
      place_town(p, KINGSMERE.x, KINGSMERE.y, "Kingsmere")
      edit.change_gold(p, 500)  -- the royal treasury at the start of a reign
      local k = find.tile(KINGSMERE.x, KINGSMERE.y)
      -- The capital starts as a fortress: stone walls, barracks and a strong
      -- royal garrison, so the realm's first years aren't its last.
      for _, b in ipairs({"City Walls", "Barracks", "Granary"}) do
        local bt = find.building_type(b)
        if bt and k:city() then pcall(edit.create_building, k:city(), bt) end
      end
      for _, pair in ipairs({{"Knights", 4}, {"Pikemen", 8}, {"Archers", 6}, {"Catapult", 2}, {"Workers", 2}}) do
        local ut = find.unit_type(pair[1])
        for i = 1, pair[2] do pcall(edit.create_unit, p, k, ut, 1, k:city(), -1) end
      end
      log.normal("REALM_SETUP crown at Kingsmere (%d,%d) city %s", KINGSMERE.x, KINGSMERE.y, tostring(k:city()))
    end
  end
  log.normal("REALM_SETUP done")
end
