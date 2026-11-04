local function try(name, f)
  local ok, err = pcall(f)
  log.normal("PROBE %s %s %s", name, ok and "OK" or "FAIL", tostring(err))
end
local c, other
for p in players_iterate() do for k in p:cities_iterate() do if not c then c = k elseif k.owner ~= c.owner and not other then other = k end end end
for i = 1, 3 do local u = edit.create_unit(c.owner, c.tile, find.unit_type("Migrants"), 0, c, -1); u:perform_action(find.action("Join City"), c) end
log.normal("PROBE city %s size %d", c.name, c.size)
for _, an in ipairs({"Poison City", "Poison City Escape", "Spread Plague", "Destroy City", "Sabotage City", "Incite City"}) do
  try("action " .. an, function() return find.action(an) end)
end
local adj
for t in c.tile:square_iterate(1) do if t ~= c.tile and not t.terrain:rule_name():find("Ocean") then adj = adj or t end end
for p in players_iterate() do
  for _, an in ipairs({"Poison City", "Poison City Escape", "Spread Plague"}) do
    try("poison " .. p.name .. " " .. an, function()
      local ut = an == "Spread Plague" and find.unit_type("Warriors") or find.unit_type("Spy")
      local spy = edit.create_unit(p, adj, ut, 0, nil, -1)
      if not spy then return "no unit" end
      local before = c.size
      local r = spy:perform_action(find.action(an), c)
      return tostring(r) .. " " .. before .. "->" .. c.size
    end)
  end
end
try("remove_building", function() local b = find.building_type("Palace"); edit.remove_building(c, b); return c:has_building(b) end)
