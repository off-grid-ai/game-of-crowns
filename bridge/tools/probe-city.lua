local c
for p in players_iterate() do for k in p:cities_iterate() do c = c or k end end
local names = {"size", "food_stock", "shield_stock", "production", "production_kind", "production_value", "food_surplus",
  "shield_surplus", "surplus", "granary_size", "culture", "history", "is_happy", "is_unhappy", "is_celebrating",
  "is_coastal", "is_capital", "is_gov_center", "map_sq_radius", "inspire_partisans", "build_shield_cost",
  "build_slots", "happy_count", "unhappy_count", "angry_count", "content_count", "specialists", "citizens",
  "nationality_citizens", "turns_to_grow", "trade", "buy_cost", "pollution", "illness", "plague", "waste", "corruption"}
for _, n in ipairs(names) do
  local ok, v = pcall(function() local f = c[n]; if type(f) == "function" then return "fn->" .. tostring(f(c)) end; return tostring(f) end)
  log.normal("CITYPROBE %s %s %s", n, ok and "OK" or "ERR", tostring(v):sub(1, 60))
end
