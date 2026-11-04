local c
for p in players_iterate() do for k in p:cities_iterate() do c = c or k end end
local ok1, e1 = pcall(edit.create_player, "The Dead", find.nation_type("Barbarian"), "classic")
log.normal("HOSTPROBE create_player %s %s", tostring(ok1), tostring(e1))
local ok2, e2 = pcall(edit.create_player, "The Dead2", find.nation_type("Barbarian"), nil)
log.normal("HOSTPROBE create_player nil-ai %s %s", tostring(ok2), tostring(e2))
local t
for tt in c.tile:square_iterate(2) do if tt:city() == nil and not tt.terrain:rule_name():find("Ocean") then t = t or tt end end
local ok3, e3 = pcall(edit.create_unit, c.owner, t, find.unit_type("Knights"), 1, nil, -1)
log.normal("HOSTPROBE create_unit %s %s", tostring(ok3), tostring(e3))
local ok4, e4 = pcall(edit.create_unit, c.owner, t, find.unit_type("Knights"), 1, c, -1)
log.normal("HOSTPROBE create_unit homed %s %s", tostring(ok4), tostring(e4))
