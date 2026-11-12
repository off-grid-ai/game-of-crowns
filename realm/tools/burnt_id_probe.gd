extends SceneTree
## A guard (integration audit #16): a burnt house is kept in the realm's damage fact (bridge/damage.js kindled) by a
## stable id from the town plan (towns.gd home_id: where the house stands in its town), never by its place in the
## order the view happened to lay the town's houses, so a change in that order can't move every ruin onto other
## houses. Lays one town's houses in two different orders and checks: each house's id is the same in both; the ids
## the fact names find the same houses (by where they stand) in both; the burnt share's fixed order picks the same
## houses in both. Prints CHECK lines; exits 1 on a fail. The bridge's half: bridge/tools/damage_probe.mjs.
##   arch -arm64 godot --headless --path realm -s res://tools/burnt_id_probe.gd



func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	var towns: Script = load("res://scripts/towns.gd")
	var fire: Script = load("res://scripts/fire.gd")
	var t_names: Array = towns.get_script_method_list().map(func(m): return String(m["name"]))
	var f_names: Array = fire.get_script_method_list().map(func(m): return String(m["name"]))
	if not t_names.has("home_id") or not f_names.has("named_homes") or not f_names.has("share_order"):
		print("CHECK burnt ids: towns.gd has no home_id, or fire.gd no named_homes/share_order (burnt houses kept by the view's order): FAIL")
		quit(1)
		return
	var spots := [Vector3(0.31, 0, -0.42), Vector3(-0.55, 0, 0.18), Vector3(0.9, 0, 0.77), Vector3(-1.2, 0, -0.66), Vector3(0.05, 0, 1.31)]
	var one: Array = spots.map(func(p: Vector3) -> Array: return [p, Vector3.FORWARD, p, "kit", 0, towns.call("home_id", p)])
	var two: Array = one.duplicate()
	two.reverse()
	var fail := 0
	var same_id := true
	for h in one:
		var k := two.find(h)
		same_id = same_id and k >= 0 and String(two[k][5]) == String(h[5])
	var named := [String(one[1][5]), String(one[3][5])]
	var a: Array = fire.call("named_homes", named, one)
	var b: Array = fire.call("named_homes", named, two)
	var same_named: bool = a.size() == 2 and b.size() == 2 and a.all(func(i): return b.any(func(j): return two[j][2] == one[i][2]))
	var oa: Array = fire.call("share_order", 7, one)
	var ob: Array = fire.call("share_order", 7, two)
	var same_order := oa.size() == ob.size()
	for i in oa.size():
		same_order = same_order and one[oa[i]][2] == two[ob[i]][2]
	var gone: Array = fire.call("named_homes", ["999_999"], one)
	var ok := same_id and same_named and same_order and gone.is_empty()
	print("CHECK burnt ids: ids stable %s, the fact's ids find the same houses %s, the burnt share's order the same %s, an id no house has finds none %s: %s" % [same_id, same_named, same_order, gone.is_empty(), "PASS" if ok else "FAIL"])
	if not ok:
		fail += 1
	quit(1 if fail > 0 else 0)
