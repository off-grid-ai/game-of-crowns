extends SceneTree
## The army layer's headless behaviour probe (a test aid; docs/research/army-layer-2026-11-12.md). No realm, no
## bridge: run with
##   arch -arm64 godot --headless --path realm -s res://tools/army_probe.gd
## It proves:
##  1. every mind row in data/army.json is whole: its start and every state its events lead to are among its
##     states, and every method a state names is one its fight has (army_skirmish, army_assault, army_field);
##  2. the ground (army_ground.gd) shuts water: a field with a round lake in it, a route across goes round it;
##  3. the Mover steers a man by that ground (toward, each frame): he never stands in the lake, and arrives;
##  4. a Mover's follow and go arrive and say so;
##  5. never a straight line while a map is still being made (Mac's clip4: a horse and cart through Kingsmere's
##     well): a man steered on a fight's ground not yet laid stands rather than wade the lake, and a man sent across
##     a town whose walk map is still baking (headless Godot never syncs one, so it stays baking) waits rather than
##     walk through its well;
##  6. one figure for ten (Mac, 12 Nov): every kind's regiment draws ceil(men x drawPerMan) figures and keeps its
##     men; in line and in march column no two figures stand closer than LEAST (about 0.8 m, shoulder room), and a
##     line stays a block (more than one rank);
##  7. panic spreads (the casebook's War and sieges: Bannerlord): on the beaten side, a flanked regiment bleeding
##     hard breaks first; its neighbour breaks sooner than an equal regiment far off (the chain); a fresh regiment
##     beside the rout holds; the commander beside the neighbour steadies it (it breaks later or not at all); the
##     victors never break. Nerve kept on each mind's LimboAI blackboard (army_morale.gd);
##  8. the rout runs along a real line (round 15: one regiment broke at t=29, then three in one tick at t=49): the
##     beaten side drawn up as a field battle draws it (army.gd's own line layout, battle.json field.frontage, its
##     gaps and rows), bleeding at field.fight.loss, its commander in the middle; its first break shakes the next so
##     the breaks run along the line one after another from the flanked end, a second or more apart and no more
##     than SPREAD apart, the far end last; never two in one moment;
##  9. the battle's lens frames the rout (round 15: the camera sat far back over open grass and nothing read): it
##     stands at the town view's distance (camera.json town_view.dist, the square's), and at blows it looks at the
##     beaten regiment that breaks next, then at the next as the rout runs along the line, and stays where it ended;
## 10. the right banner (READY line 4): a regiment raised for a house with arms flies those arms on its banner (its
##     kind's glyph in the canton) and its men wear them on shield and tabard, in its colour; a house with none
##     drawn flies its colour with the glyph; the host's standard flies the same arms (heraldry.gd arms, one place);
## 11. war: the host marches out (READY line 3): a host formed in line at its seat, told to march out, takes the
##     road the realm's roads give (roads.route), leaves regiment by regiment in column order, each only once the
##     one ahead has gone its length, and halts in column along the road's end, no two regiments in one place; then
##     it is gone (march.linger); it tells where it is in that (march_phase: formed, out, halted), and the film has a
##     play step that waits for a phase (autoplay `muster`), so a round films READY 3 without hand timing;
## 12. a click picks a host by its own body (READY line 8; the milestone's command take selected nothing): a
##     standard-bearer (scaled as the map's people are) and a regiment carry pick proxies, and a physics ray from
##     the camera through the standard picks that company, through the regiment picks it with its view, and through
##     open land picks nothing; host_command.gd takes the pick at the press, with no screen-distance guess;
## 13. one body set, one finish (CLAUDE.md: no fallbacks): every kind wears its own baked soldier by its own asset
##     (the Meshy men-at-arms, town guard as spearmen, ranger as archers, the cavalry horse), with no kit/meshy
##     switch (units_set, meshy.<unit>, --units=); every soldier wears the painted finish, with no switch
##     (look.on, --army-look=) and no off branch in army_vat.gdshader;
## 14. a route before any scene stands anyone (READY line 10, the reign replay: 32k route errors, companies that never
##     set out): the real scenes.gd, set up as main sets it up (terrain, roads), gives the Mover a route at once;
##     scenes.gd sets its nav's terrain and roads where it gets them, not lazily in stand();
## 15. an arrow at a fallen man (the reign replay: scenes.gd's volley read a freed mark's position): an archer draws
##     on a mark that is freed before he looses; the shot finds another mark or none, and no freed node is read;
## 16. the map's host marks wait for the land (the reign replay: 72 errors, map_marks drew a host's standard through
##     terrain.tile_at before the land was laid): with a host in the field and the land not yet built, map_marks.gd
##     reads no tile;
## 17. the film waits for the lines to meet (GoC's battle take: a fixed `wait 20` filmed the last of the walk-in and the
##     hold, and no meeting read): army_field.gd says when its lines have met (met()), and autoplay has a `clash`
##     step that waits on it, as `rout` waits on the first break;
## 18. a company's figure keeps up with its company (READY line 10, the reign replay: 310 off-tile faults in 20
##     seasons, the lag growing): sent any distance, it arrives within the season, at its steady march when that
##     does, running (a forced march) when it must go faster (units.gd march_pace);
## 19. a house's host marching on a town shows on the map (docs/research/engine-visual-map-2026-11-12.md gap 3: 40 of
##     52 companies carry a Freeciv goto, and only the crown's orders were drawn): map_look.marches gives a line from
##     each house's companies in the field to where Freeciv sends them; not for one dug in where it stands, the
##     crown's (its orders draw those), a civilian or a ship;
## 20. a ship sails the water (the reign replay: Triremes 46 units from their tiles, never set out, as no land route
##     crosses the sea): the realm's paths give a sea route (land_paths.sea_path) that keeps to water round an island,
##     and units.gd sends a ship by it;
## 21. a mover covers its speed whatever the frame rate (the reign replay: every off-tile figure still moving when its
##     season ended): along a way baked every 0.05 units (a march's road), one frame of a second at speed 1 carries it
##     about 1 unit, through every point it passes, not one point a frame;
## 22. a host's standard on the map reads (Mac's realm map: every far standard said "200" on a blank flag): its men
##     are the companies' own (the bridge's units carry their men, by kind and health), so two hosts differ; the
##     flag flies the house's arms (Heraldry.arms, as the regiments' banners); and its line names the house, the men
##     and where it is bound (map_look.host_line, the hover's words);
## 23. the muster's column takes the road (GoC's muster frames: it marched on the grass): the realm's roads join a
##     road only within roads.reach of each end, and a muster's field keeps off roads, so march_out asks with its
##     own reach (army.json march.roadReach) and its way runs along the road;
## 24. every regiment reads as a formed block (GoC's muster frames: 10-14 figures a regiment, a speck where 03-army is
##     a wall): a regiment draws army.json figureFloor figures and one for ten men above it (drawPerMan, Mac's), so a
##     160-man host draws at least the floor a regiment and a 600-man host more than a 160-man one; the realm's biggest
##     host stays under figureBudget (from the fps bar); and its losses fell figures in step with its men;
## 25. a ship is the transport cog (look-audit's cbc97f6f; Mac: ships only carry armies): units.gd builds a ship's
##     body as assets/meshy/cog at the realm's scale (Units.M, metres), sunk to its waterline, its sail and pennant
##     in the house's colour by the one rule (team_colour.house_colour), never a soldier;
## 26. a marcher is never pinned by the push off buildings (the reign replay: a Worker 'moving' and 17 units off for
##     three seasons, a ship falling one Freeciv move further behind each season): units.gd's keep pushes a figure off
##     a building only where its town has no walk map (a straight line through it); a ship, and a figure on a town's
##     walk map (its route already keeps off every building), go as their route says;
## 27. the push off a building never pins a mover (the reign replay: a Worker 17 units off, five seasons, on a straight
##     line through a town out of sight): with a place's keep pushing it off a building on its way, a mover's progress
##     along its way carries on (only the body is pushed), so it goes round the building's edge and arrives, and it
##     never stands inside the building;
## 28. a war's muster forms as a column on the road out (the render pass: a small block on open grass where 03-army is
##     a dense column on a road): a host raised for war (out_to) stands in column on the road from its seat toward
##     where it is bound, every regiment on the road, halted, in column order with its head toward the goal, no two in
##     one place, its ranks closed up (army.json column.rank at most 0.15, from 0.22), each regiment still at its floor of figures.
## Prints "ARMY PROBE …" lines and "ARMY PROBE PASS" or "ARMY PROBE FAIL n"; quits with 0 or 1.

const Data := preload("res://scripts/data.gd")
const Ground := preload("res://scripts/army_ground.gd")
const Mover := preload("res://scripts/mover.gd")
const TownNav := preload("res://scripts/town_nav.gd")

const OWNERS := {"line_soldier": "res://scripts/army_skirmish.gd", "knight": "res://scripts/army_skirmish.gd",
	"assault_man": "res://scripts/army_assault.gd", "gap_holder": "res://scripts/army_assault.gd",
	"regiment": "res://scripts/army_field.gd", "storm_regiment": "res://scripts/army_field.gd"}
const LAKE := Vector2(0.0, 0.0)
const LAKE_R := 1.2

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("ARMY PROBE %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	_minds()
	await _ground_and_mover()
	await _no_straight_line_while_baking()
	_figures_and_room()
	_panic_spreads()
	_rout_runs_along_the_line()
	_lens_on_the_rout()
	_the_right_banner()
	await _march_out()
	await _pick_by_body()
	_one_body_one_finish()
	await _route_before_any_scene()
	await _marks_wait_for_land()
	_film_waits_for_the_clash()
	_figure_keeps_up()
	_house_marches_show()
	_ship_sails_the_water()
	_mover_keeps_its_speed()
	_standards_read()
	_muster_takes_the_road()
	_regiments_read_as_blocks()
	_ship_is_the_cog()
	_marchers_not_pinned()
	await _push_never_pins()
	_muster_forms_on_the_road()
	print("ARMY PROBE PASS" if _fails == 0 else "ARMY PROBE FAIL %d" % _fails)
	quit(0 if _fails == 0 else 1)


## 28. A war's muster on the road: a stand-in realm whose one road runs east from the seat, then north.
func _muster_forms_on_the_road() -> void:
	var ArmyS: GDScript = load("res://scripts/army.gd")
	var has := ArmyS.get_script_method_list().any(func(m): return m["name"] == "_form_on_road")
	_check(has, "a war's host forms on the road out (army.gd _form_on_road)")
	_check(Data.num("army", "column.rank", 1.0) <= 0.15, "the column's ranks are closed up (column.rank %.3f)" % Data.num("army", "column.rank", 1.0))
	# A regiment on the march is a block, ranks abreast (03-army: 6-10 men to a rank; pass g2's host5: 4 abreast strung
	# a spearmen regiment 14 ranks down the road, and the horse at 0.5 between ranks): every kind's regiment of its
	# full men lays out no deeper than it is wide, the horse's ranks closed up too.
	var Form: GDScript = load("res://scripts/army_formation.gd")
	var ArmyF: GDScript = load("res://scripts/army.gd")
	var rng := RandomNumberGenerator.new()
	for k in (Data.value("army", "units", {}) as Dictionary):
		var row: Dictionary = Data.value("army", "units", {})[k]
		var sp: Dictionary = row.get("spacing", {})
		var r := {"figures": ArmyF.figures(int(row.get("men", 150))), "sf": float(sp.get("file", Data.num("army", "spacing.file", 0.12))),
			"sr": float(sp.get("rank", Data.num("army", "spacing.rank", 0.15))), "role": String(row.get("role", "melee"))}
		rng.seed = 7
		var c: Dictionary = Form.layout(r, "column", null, rng)
		_check(int(c["files"]) >= 6 and float(c["d"]) <= float(c["w"]) * 1.6, "a %s regiment marches as a block: %d abreast, %.2f deep for %.2f wide" % [k, int(c["files"]), float(c["d"]), float(c["w"])])
	if not has:
		return
	var stub := GDScript.new()
	stub.source_code = '''extends Node3D
var terrain: Node3D
var roads: Node
func build(road: PackedVector3Array) -> void:
	terrain = Node3D.new()
	var ts := GDScript.new()
	ts.source_code = "extends Node3D\\nvar width := 0\\nvar built := false\\nfunc height_at(_x: float, _z: float) -> float:\\n\\treturn 0.0\\n"
	ts.reload()
	terrain.set_script(ts)
	add_child(terrain)
	roads = Node.new()
	var rs := GDScript.new()
	rs.source_code = "extends Node\\nvar way := PackedVector3Array()\\nfunc route(_a: Vector3, _b: Vector3, _reach := 2.5) -> PackedVector3Array:\\n\\treturn way\\n"
	rs.reload()
	roads.set_script(rs)
	roads.way = road
	add_child(roads)
'''
	stub.reload()
	var main := Node3D.new()
	main.set_script(stub)
	root.add_child(main)
	var road := PackedVector3Array([Vector3(0, 0, 0), Vector3(14, 0, 0), Vector3(14, 0, 10)])
	main.call("build", road)
	var a: Node3D = ArmyS.new(main, 0, {"side": 0, "colour": Color(0.6, 0.15, 0.15), "quiet": true, "out_to": road[road.size() - 1]})
	var rows: Array = []
	for k in ["archers", "spearmen", "horse", "men_at_arms"]:
		var r: Dictionary = a.call("_regiment", {"id": -(rows.size() + 1), "unit": k, "men": 150}, Color(0.6, 0.15, 0.15), {})
		if not r.is_empty():
			rows.append(r)
	a.set("_regiments", rows)
	main.add_child(a)
	var formed: bool = a.call("_form_on_road", Vector3.ZERO, road[road.size() - 1])
	var on_road := true
	var near := INF
	var along: Array = []
	var order := Formation_column_order(rows)
	for i in order.size():
		var p: Vector3 = (order[i]["node"] as Node3D).global_position
		var s_at := float(a.call("_along", p))
		on_road = on_road and (a.call("_at", s_at) as Vector3).distance_to(p) < 0.05
		along.append(s_at)
		for j in range(i + 1, order.size()):
			near = minf(near, p.distance_to((order[j]["node"] as Node3D).global_position))
	var head_first := true
	for i in range(1, along.size()):
		head_first = head_first and float(along[i]) < float(along[i - 1])
	_check(formed and on_road, "every regiment stands on the road out (%s)" % str(along.map(func(v): return snappedf(v, 0.01))))
	_check(rows.all(func(r): return r["shape"] == "column" and r["state"] == "halt"), "in column, halted until it marches out (%s)" % str(rows.map(func(r): return "%s/%s" % [r["shape"], r["state"]])))
	_check(head_first and near > 0.2, "in column order, its head toward the goal, no two in one place (closest %.2f)" % near)
	_check(rows.all(func(r): return int(r["figures"]) >= int(Data.num("army", "figureFloor", 0.0))), "each regiment at its floor of figures")
	main.queue_free()


func Formation_column_order(rows: Array) -> Array:
	return (load("res://scripts/army_formation.gd") as GDScript).call("column_order", rows)


## 27. The push never pins: a straight way of points 0.05 apart from x 0 to 2, a round building of radius 0.3 at x 1.
func _push_never_pins() -> void:
	var man := Node3D.new()
	root.add_child(man)
	var mo: Node = Mover.of(man)
	var hub := Vector3(1, 0, 0)
	var inside := [0]
	mo.keep = func(p: Vector3) -> Vector3:
		var d := Vector2(p.x - hub.x, p.z - hub.z)
		if d.length() >= 0.3:
			return p
		var out := d.normalized() if d.length() > 0.001 else Vector2(0, 1)
		return Vector3(hub.x + out.x * 0.3, p.y, hub.z + out.y * 0.3)
	var way := PackedVector3Array()
	for i in 41:
		way.append(Vector3(i * 0.05, 0, 0.01))
	mo.speed = 0.5
	mo.clip = ""
	mo.follow(way)
	for k in 400:
		mo.call("_process", 0.05)
		if Vector2(man.global_position.x - hub.x, man.global_position.z - hub.z).length() < 0.299:
			inside[0] += 1
		if not mo.moving():
			break
	_check(man.global_position.x > 1.9, "a mover pushed off a building on its way goes round it and arrives (x %.2f)" % man.global_position.x)
	_check(inside[0] == 0, "and never stands inside the building (%d frames inside)" % inside[0])
	man.queue_free()


## 26. Never pinned: units.gd's keep on a ship and on a town with a walk map.
func _marchers_not_pinned() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/units.gd")
	var at := src.find("func _keep(")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	_check(body.contains("\"ship\"") and body.contains("baked("), "units.gd's keep leaves a ship and a figure on a town's walk map to their route (%s)" % ("ship" if body.contains("\"ship\"") else "no ship rule"))


## 25. A ship is the cog.
func _ship_is_the_cog() -> void:
	var U: GDScript = load("res://scripts/units.gd")
	var TC: GDScript = load("res://scripts/team_colour.gd")
	var has := U.get_script_method_list().any(func(m): return m["name"] == "ship_body")
	_check(has, "units.gd builds a ship's body (ship_body)")
	_check(TC.get_script_method_list().any(func(m): return m["name"] == "house_colour"), "the house colour comes from one rule (team_colour.house_colour)")
	if not has:
		return
	var house := {"name": "House Ashby", "color": "#335599"}
	var ship: Node3D = U.call("ship_body", house)
	var geos := ship.find_children("*", "GeometryInstance3D", true, false)
	var M := float((load("res://scripts/world_units.gd") as GDScript).get("M"))
	_check(not geos.is_empty() and ship.scene_file_path == "" and ship.get_child_count() > 0, "the ship is the cog's meshes (%d)" % geos.size())
	var cog: Node3D = ship.get_child(0)
	_check(is_equal_approx(cog.scale.x, M) and cog.position.y < 0.0, "at the realm's scale (%.3f) and sunk to its waterline (%.3f)" % [cog.scale.x, cog.position.y])
	var want: Color = TC.call("house_colour", house)
	var dyed: bool = geos.all(func(g): return (g as GeometryInstance3D).get_instance_shader_parameter("team_color") == want)
	_check(dyed, "its sail and pennant take the house's colour")
	ship.free()


## 24. Every regiment a formed block: hosts made up as a muster raises them (army.gd _made_up).
func _regiments_read_as_blocks() -> void:
	var ArmyS: GDScript = load("res://scripts/army.gd")
	var a: Object = ArmyS.new(Node.new(), 0, {})
	var floor_n := int(Data.num("army", "figureFloor", 0.0))
	_check(floor_n >= 40, "army.json sets a floor of figures a regiment (figureFloor %d)" % floor_n)
	var drawn := func(men: int) -> Array: return (a.call("_made_up", men) as Array).map(func(sp): return int(ArmyS.call("figures", int(sp["men"]))))
	var small: Array = drawn.call(160)
	var big: Array = drawn.call(600)
	var sum := func(arr: Array) -> int: return arr.reduce(func(x, y): return x + y, 0)
	_check(small.all(func(n): return n >= 40), "a 160-man host draws at least 40 a regiment (%s)" % str(small))
	_check(int(sum.call(big)) > int(sum.call(small)), "a 600-man host draws more than a 160-man host (%d, %d)" % [sum.call(big), sum.call(small)])
	var budget := int(Data.num("army", "figureBudget", 0.0))
	var biggest: Array = drawn.call(17 * 160)  # the reign's biggest house: 17 companies (Freeciv's run2, T38-T78)
	_check(budget > 0 and int(sum.call(biggest)) <= budget, "the realm's biggest host draws %d figures, within the budget %d" % [sum.call(biggest), budget])
	var src := FileAccess.get_file_as_string("res://scripts/army_field.gd")
	var at := src.find("func _fell(")
	_check(src.substr(at, 600).contains("r[\"figures\"]") and not src.substr(at, 600).contains("Army.ratio()"), "a regiment's losses fell figures in step with its men (figures over men, not one per ten)")
	a.free()


## 23. The muster takes the road: the stand-in realm of section 11, its road starting 6 units from the field.
func _muster_takes_the_road() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/army.gd")
	var at := src.find("func march_out(")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	_check(body.contains("roadReach"), "march_out asks the roads with the muster's own reach (army.json march.roadReach)")
	var reach := Data.num("army", "march.roadReach", 0.0)
	_check(reach >= 6.0, "the muster's reach to the road covers a field kept off it (%.1f)" % reach)


## 22. A host's standard reads: the store's armies from a /world with two of House Ashby's hosts, one of three
## companies and one of one, the second bound for a town.
func _standards_read() -> void:
	var Aw: GDScript = load("res://scripts/awareness.gd")
	var ML: GDScript = load("res://scripts/map_look.gd")
	var world := {"cities": [{"id": 5, "x": 40, "y": 40, "name": "Redbridge", "title": "Redbridge"}],
		"units": [{"id": 1, "owner": 2, "type": "Pikemen", "x": 10, "y": 10, "men": 160}, {"id": 2, "owner": 2, "type": "Pikemen", "x": 10, "y": 11, "men": 160},
			{"id": 3, "owner": 2, "type": "Knights", "x": 11, "y": 10, "men": 100}, {"id": 4, "owner": 2, "type": "Archers", "x": 30, "y": 30, "men": 60, "goto": {"x": 40, "y": 40}}]}
	var groups: Array = Aw.call("_armies", world)
	var men := groups.map(func(g): return int(g.get("men", -1)))
	_check(men.has(420) and men.has(60), "two hosts of different strength carry their companies' men (%s)" % str(men))
	var house := {"name": "House Ashby", "color": "#335599"}
	_check(ML.get_script_method_list().any(func(m): return m["name"] == "flag_arms") and ML.call("flag_arms", house) != null,
		"a host's standard on the map flies its house's arms (map_look.flag_arms: Heraldry.arms)")
	var has_line := ML.get_script_method_list().any(func(m): return m["name"] == "host_line")
	var small: Dictionary = {}
	for g in groups:
		if int(g.get("men", 0)) == 60:
			small = g
	var line: String = String(ML.call("host_line", {"x": 30.0, "y": 30.0, "men": 60, "house": house, "goal": small.get("goal")}, world["cities"])) if has_line else ""
	_check(line.contains("Ashby") and line.contains("60") and line.contains("Redbridge"), "the standard's line names the house, its men and where it is bound (%s)" % line)


## 21. A mover keeps its speed: a body on a straight way of points 0.05 apart, one frame of 1 s at speed 1.
func _mover_keeps_its_speed() -> void:
	var man := Node3D.new()
	root.add_child(man)
	var mo: Node = Mover.of(man)
	var way := PackedVector3Array()
	for i in 101:
		way.append(Vector3(i * 0.05, 0, 0))
	mo.speed = 1.0
	mo.clip = ""
	mo.follow(way)
	mo.call("_process", 1.0)
	var went := man.global_position.x
	_check(absf(went - 1.0) < 0.06, "one frame of 1 s at speed 1 along a road baked every 0.05 carries a mover about 1 unit (%.2f)" % went)
	man.queue_free()


## 20. A ship sails the water: a stand-in tile map 12 x 9 of ocean with an island (land) in the middle, 4 x 3 tiles.
func _ship_sails_the_water() -> void:
	var LP: GDScript = load("res://scripts/land_paths.gd")
	var has := LP.get_script_method_list().any(func(m): return m["name"] == "sea_path")
	_check(has, "the realm's paths give a sea route (land_paths.sea_path)")
	_check(FileAccess.get_file_as_string("res://scripts/units.gd").contains("sea_path("), "units.gd sends a ship by the sea route")
	if not has:
		return
	var t := GDScript.new()
	t.source_code = '''extends Node3D
const TILE := 4.0
var width := 12
var height := 9
func tile_at(x: int, y: int) -> String:
	if x == 9 and y == 7:
		return "Forest|river"  # a river tile, a Trireme's water (the ruleset's River extra: native to Trireme)
	if y >= 6 and not (x == 10 and y == 6):
		return "Grassland"  # the shore below, a town at (10, 6), the river at (9, 7) its way inland
	return "Grassland" if x >= 4 and x <= 7 and y >= 3 and y <= 5 else "Ocean"
func world_pos(tx: float, ty: float) -> Vector3:
	return Vector3((tx + 0.5) * TILE, 0, (ty + 0.5) * TILE)
'''
	t.reload()
	var land := Node3D.new()
	land.set_script(t)
	var lp: Object = LP.new(land)
	lp.call("build")
	var from: Vector3 = land.world_pos(1, 4)
	var to: Vector3 = land.world_pos(10, 4)
	var way: PackedVector3Array = lp.call("sea_path", from, to)
	var wet := true
	for i in way.size() - 1:
		for k in 5:
			var p: Vector3 = way[i].lerp(way[i + 1], k / 4.0)
			wet = wet and land.tile_at(floori(p.x / 4.0), floori(p.z / 4.0)) == "Ocean"
	_check(way.size() >= 3 and wet, "a route across goes round the island on water (%d points, all wet: %s)" % [way.size(), wet])
	# A Trireme sails the river (Freeciv moved one from a coastal town up its river: the reign's five 'straight
	# line' moves); a ship with no water between its ends gets no route at all, never a line over the land.
	var up: PackedVector3Array = lp.call("sea_path", land.world_pos(10, 6), land.world_pos(9, 7), true)
	_check(up.size() >= 2, "a Trireme sails from the coastal town up its river, corner to corner as Freeciv moves it (%d points)" % up.size())
	var inland: PackedVector3Array = lp.call("sea_path", land.world_pos(1, 4), land.world_pos(2, 8), true)
	_check(inland.is_empty(), "with no water between its ends a ship gets no route, never a straight line over land (%d points)" % inland.size())
	_check(FileAccess.get_file_as_string("res://tools/reign_army_probe.gd").contains("ship-no-water"), "the reign probe fails a ship move with no water route")
	land.free()


## 19. A house's march on the map: a stand-in store with five companies.
func _house_marches_show() -> void:
	var t := GDScript.new()
	t.source_code = '''extends RefCounted
class Realm extends RefCounted:
	func get_var(_n: StringName, d = null, _c := true):
		return d
var realm := Realm.new()
func rec(key: String, d = null):
	match key:
		"crownId":
			return 7
		"cities":
			return [{"id": 1, "x": 20, "y": 20}]
		"units":
			return [
				{"id": 1, "owner": 3, "type": "Pikemen", "x": 10, "y": 10, "goto": {"x": 15, "y": 10}},
				{"id": 2, "owner": 3, "type": "Pikemen", "x": 11, "y": 10, "goto": {"x": 11, "y": 10}},
				{"id": 3, "owner": 7, "type": "Knights", "x": 4, "y": 4, "goto": {"x": 9, "y": 4}},
				{"id": 4, "owner": 3, "type": "Settlers", "x": 2, "y": 2, "goto": {"x": 6, "y": 2}},
				{"id": 5, "owner": 3, "type": "Trireme", "x": 30, "y": 30, "goto": {"x": 34, "y": 30}}]
	return d
'''
	t.reload()
	var aw: Object = t.new()
	var aw_civ: Array = (load("res://scripts/awareness.gd") as GDScript).get("civilian")
	(load("res://scripts/awareness.gd") as GDScript).set("civilian", ["Settlers", "Workers"])
	var m: Array = (load("res://scripts/map_look.gd") as GDScript).call("marches", aw)
	(load("res://scripts/awareness.gd") as GDScript).set("civilian", aw_civ)
	var ok: bool = m.size() == 1 and (m[0][0] as Vector2).distance_to(Vector2(10, 10)) < 0.01 and (m[0][1] as Vector2) == Vector2(15, 10)
	_check(ok, "a house's company in the field bound elsewhere draws one march line, the rest none (%s)" % str(m))


## 18. A figure keeps up: the pace units.gd marches a company's figure at, for a short move and a long one.
func _figure_keeps_up() -> void:
	var U: GDScript = load("res://scripts/units.gd")
	var has := U.get_script_method_list().any(func(m): return m["name"] == "march_pace")
	_check(has, "units.gd says the pace a company's figure marches at (march_pace)")
	if not has:
		return
	var season := 40.0
	var cap := float(U.get("MARCH_SPEED"))
	var short: Dictionary = U.call("march_pace", 4.0, season)
	var long: Dictionary = U.call("march_pace", 30.0, season)
	_check(4.0 / float(short["speed"]) <= season and not bool(short["run"]) and float(short["speed"]) <= cap,
		"one tile: it walks, at no more than its steady march, and arrives within the season (%s)" % str(short))
	_check(30.0 / float(long["speed"]) <= season and bool(long["run"]),
		"seven tiles' worth of road: it runs, and arrives within the season (%s)" % str(long))


## 17. The film waits for the clash: a field battle whose sides are two stand-in hosts, first walking in, then one
## regiment at blows.
func _film_waits_for_the_clash() -> void:
	var F: GDScript = load("res://scripts/army_field.gd")
	var has := F.get_script_method_list().any(func(m): return m["name"] == "met")
	_check(has, "a field battle says when its lines have met (army_field.gd met)")
	var auto_src := FileAccess.get_file_as_string("res://scripts/autoplay.gd")
	_check(auto_src.contains("\"clash\":") and auto_src.contains(".call(\"met\")"), "the film has a play step that waits for the lines to meet (autoplay clash)")
	if not has:
		return
	var hs := GDScript.new()
	hs.source_code = "extends Node\nvar rs: Array = []\nfunc rows() -> Array:\n\treturn rs\n"
	hs.reload()
	var a := Node.new()
	a.set_script(hs)
	var b := Node.new()
	b.set_script(hs)
	a.rs = [{"state_name": "advance"}, {"state_name": "volley"}]
	b.rs = [{"state_name": "advance"}]
	var f: Object = F.new(Node.new(), "600:foe")
	f.set("sides", [a, b])
	var walking: bool = f.call("met")
	b.rs[0]["state_name"] = "fight"
	var at_blows: bool = f.call("met")
	_check(not walking and at_blows, "met() is false while they walk in, true once a regiment is at blows (%s, %s)" % [walking, at_blows])
	f.free()
	a.free()
	b.free()


## 16. The map's host marks before the land is laid: a stand-in main far out (the marks show), a host in the field,
## and land that isn't built yet and says so when anything reads it.
func _marks_wait_for_land() -> void:
	var t := GDScript.new()
	t.source_code = '''extends Node
class Land extends RefCounted:
	var built := false
	var width := 0
	var read := 0
	func world_pos(tx: float, ty: float) -> Vector3:
		read += 1
		return Vector3(tx, 0, ty)
	func height_at(_x: float, _z: float) -> float:
		read += 1
		return 0.0
class Rig extends RefCounted:
	var distance := 40.0
class Realm extends RefCounted:
	func get_var(name: StringName, d = null, _c := true):
		if name == &"armies":
			return [{"owner": 1, "x": 3.0, "y": 3.0, "companies": 2}]
		return d
class Aw extends RefCounted:
	var realm := Realm.new()
var terrain := Land.new()
var rig := Rig.new()
var labels := CanvasLayer.new()
var awareness := Aw.new()
'''
	t.reload()
	var main := Node.new()
	main.set_script(t)
	root.add_child(main)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	var mm: CanvasLayer = load("res://scripts/map_marks.gd").new()
	mm.main = main
	main.add_child(mm)
	await process_frame
	mm.call("_draw_marks")
	_check(int(main.terrain.read) == 0, "the map's host marks read no land before it is laid (%d reads)" % int(main.terrain.read))
	main.queue_free()


## Counts the engine's errors about a freed object (a lambda or tween reading a node already gone).
class Freed extends Logger:
	var freed := 0
	func _log_error(_f: String, _file: String, _line: int, code: String, rationale: String, _n: bool, _t: int, _bt: Array[ScriptBacktrace]) -> void:
		if (code + " " + rationale).contains("freed"):
			freed += 1


## 14. A route before any scene stands anyone: a stand-in main (flat land everywhere, no towns, no roads) with the
## real scenes.gd added as main.gd adds it, and a Mover asked for a route straight away.
func _route_before_any_scene() -> void:
	var t := GDScript.new()
	t.source_code = '''extends Node3D
var terrain: Node3D
var towns: Node3D
var roads = null
var scenes: Node
func build() -> void:
	terrain = Node3D.new()
	var ts := GDScript.new()
	ts.source_code = "extends Node3D\\nvar built := true\\nvar width := 64\\nvar paths = self\\nfunc height_at(_x: float, _z: float) -> float:\\n\\treturn 0.0\\nfunc is_land(_x: float, _z: float) -> bool:\\n\\treturn true\\nfunc walkable(_x: float, _z: float) -> bool:\\n\\treturn true\\nfunc land_path(a: Vector3, b: Vector3) -> PackedVector3Array:\\n\\treturn PackedVector3Array([a, b])\\nfunc bowed(p: PackedVector3Array) -> PackedVector3Array:\\n\\treturn p\\n"
	ts.reload()
	terrain.set_script(ts)
	add_child(terrain)
	towns = Node3D.new()
	var tw := GDScript.new()
	tw.source_code = "extends Node3D\\nvar towns := {}\\n"
	tw.reload()
	towns.set_script(tw)
	add_child(towns)
'''
	t.reload()
	var main := Node3D.new()
	main.set_script(t)
	main.build()
	root.add_child(main)
	var aw := Node.new()
	main.add_child(aw)
	Engine.set_meta("awareness", aw)
	var sc: Node = load("res://scripts/scenes.gd").new()
	sc.set("terrain", main.terrain)  # as main.gd: scenes.terrain = terrain, then add_child
	main.scenes = sc
	main.add_child(sc)
	await process_frame
	_check(sc.nav.terrain == main.terrain, "scenes.gd's nav has the realm's terrain before any scene stands anyone (%s)" % sc.nav.terrain)
	var body := Node3D.new()
	main.add_child(body)
	var got := [null]
	Mover.of(body).route_to(Vector3(2, 0, 0), func(way: PackedVector3Array): got[0] = way)
	_check(got[0] is PackedVector3Array and (got[0] as PackedVector3Array).size() >= 2, "a Mover asked for a route before any scene stands anyone gets one at once (%s)" % str(got[0]))
	var src := FileAccess.get_file_as_string("res://scripts/scenes.gd")
	var at := src.find("func stand(")
	var stand_src := src.substr(at, src.find("\nfunc ", at + 1) - at) if at >= 0 else ""
	_check(not stand_src.contains("nav.terrain =") and not stand_src.contains("nav.roads ="), "stand() sets no nav terrain or roads (one place, where scenes gets them)")
	# 15. A volley at a mark freed between the draw and the loose.
	var log := Freed.new()
	OS.add_logger(log)
	var archer := Node3D.new()
	main.add_child(archer)
	var mark := Node3D.new()
	main.add_child(mark)
	var rng := RandomNumberGenerator.new()
	sc.call("_arrows", main, [{"alive": true, "kit": "bow", "node": archer, "engaged": false}], [{"node": mark, "alive": true, "rank": 1}], rng)
	mark.free()  # he falls and is gone before the arrow is loosed (0.6 s after the draw)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1800:
		await process_frame
	OS.remove_logger(log)
	_check(log.freed == 0, "a volley at a man gone before it is loosed reads no freed node (%d errors)" % log.freed)
	Engine.remove_meta("awareness")
	main.queue_free()


## 13. One body set, one finish: the data, the scripts and the shader carry no old path, and a raised regiment
## wears its kind's own body with the painted finish on.
func _one_body_one_finish() -> void:
	var units: Dictionary = Data.value("army", "units", {})
	var want := {"men_at_arms": "armies/meshy_man_at_arms", "spearmen": "armies/meshy_town_guard", "archers": "armies/meshy_ranger", "horse": "armies/cavalry"}
	for k in want:
		_check(String((units.get(k, {}) as Dictionary).get("asset", "")) == want[k], "%s wears its own body by its asset (%s)" % [k, want[k]])
	_check(Data.value("army", "units_set", null) == null and Data.value("army", "meshy", null) == null and Data.value("army", "look.on", null) == null,
		"army.json has no kit/meshy switch (units_set, meshy) and no finish switch (look.on)")
	var src := func(path: String) -> String: return FileAccess.get_file_as_string(path)
	var army_src: String = src.call("res://scripts/army.gd")
	var vis_src: String = src.call("res://scripts/army_visual.gd")
	var sh_src: String = src.call("res://scripts/army_vat.gdshader")
	_check(not army_src.contains("--units=") and not army_src.contains("func meshy("), "army.gd has no --units= switch and no meshy()")
	_check(not vis_src.contains("--army-look") and not vis_src.contains("look.on"), "army_visual.gd has no --army-look switch")
	_check(not sh_src.contains("look_painted"), "army_vat.gdshader has no finish-off branch (look_painted)")
	var ArmyS: GDScript = load("res://scripts/army.gd")
	var a: Object = ArmyS.new(Node.new(), 0, {"side": 0, "colour": Color(0.2, 0.3, 0.6)})
	var r: Dictionary = a.call("_regiment", {"id": 1, "unit": "spearmen", "men": 150}, Color(0.2, 0.3, 0.6), {})
	if r.is_empty():
		_check(false, "spearmen raised (their baked soldier loads)")
	else:
		var mat: ShaderMaterial = (r["vat"] as GeometryInstance3D).material_override
		_check(String(r["kit"]["asset"]) == "armies/meshy_town_guard", "a spearmen regiment raised wears the town guard (%s)" % r["kit"]["asset"])
		_check(not is_equal_approx(float(mat.get_shader_parameter("mesh_height")), 2.45), "its men wear the painted finish (mesh_height set: %s)" % mat.get_shader_parameter("mesh_height"))
	a.free()


## 1. Every mind row whole, every method it names there.
func _minds() -> void:
	var minds: Dictionary = Data.value("army", "minds", {})
	for kind in OWNERS:
		_check(minds.has(kind), "mind %s has a row" % kind)
		if not minds.has(kind):
			continue
		var row: Dictionary = minds[kind]
		var states: Dictionary = row.get("states", {})
		var script: GDScript = load(OWNERS[kind])
		var methods := {}
		var s: Script = script
		while s != null:
			for m in s.get_script_method_list():
				methods[m["name"]] = true
			s = s.get_base_script()
		_check(states.has(row.get("start", "")), "mind %s starts in one of its states" % kind)
		for st in states:
			for key in ["enter", "tick", "exit", "guard"]:
				if (states[st] as Dictionary).has(key):
					var m := String(states[st][key])
					_check(methods.has(m), "mind %s state %s %s: %s() is on %s" % [kind, st, key, m, OWNERS[kind].get_file()])
		for t in row.get("go", []):
			_check(states.has(t[0]) and states.has(t[1]), "mind %s event %s leads between its states" % [kind, t[2]])
		for ev in row.get("any", {}):
			_check(states.has(row["any"][ev]), "mind %s event %s leads to one of its states" % [kind, ev])


## 2-4. A field with a lake: the ground shuts it, a route goes round, a steered man never wades and arrives.
func _ground_and_mover() -> void:
	var main := Node3D.new()
	main.name = "ProbeMain"
	main.set_script(_stub_main())
	root.add_child(main)
	var g: RefCounted = Ground.around(main, Vector3.ZERO, 4.0)
	while not g.built:
		await process_frame
	_check(not g.open_at(Vector3(0, 0, 0)), "the ground shuts the lake")
	_check(g.open_at(Vector3(3.0, 0, 0)), "the ground opens dry land")
	var from := Vector3(-2.5, 0, 0.1)
	var to := Vector3(2.5, 0, -0.1)
	var way: PackedVector3Array = g.route(from, to)
	var wet := 0
	var prev := from
	for p in way:
		for k in 10:
			var q := prev.lerp(p, k / 10.0)
			if Vector2(q.x, q.z).distance_to(LAKE) < LAKE_R - 0.05:
				wet += 1
		prev = p
	_check(way.size() >= 2 and wet == 0, "a route across goes round the lake (%d points, %d wet)" % [way.size(), wet])
	# A man steered across by toward(), each frame, as a fighter's mind steers him.
	var man := Node3D.new()
	main.add_child(man)
	man.global_position = from
	var mo: Node = Mover.of(man).on(g)
	mo.clip = ""
	var waded := 0
	var frames := 0
	while man.global_position.distance_to(to) > 0.05 and frames < 3000:
		mo.toward(to, 0.5)
		await process_frame
		frames += 1
		if Vector2(man.global_position.x, man.global_position.z).distance_to(LAKE) < LAKE_R - 0.05:
			waded += 1
	_check(waded == 0, "a steered man never stands in the lake (%d frames in it)" % waded)
	_check(man.global_position.distance_to(to) <= 0.05, "a steered man arrives (%.2f off after %d frames)" % [man.global_position.distance_to(to), frames])
	# Unasked, he stands.
	for k in 30:
		await process_frame
	_check(not mo.moving(), "a man nobody steers stands")
	# go() by the ground's route, and follow() a given way, each say they've arrived.
	var arrived := [false, false]
	mo.speed = 1.0
	mo.go(from, func(): arrived[0] = true)
	var t0 := Time.get_ticks_msec()
	while not arrived[0] and Time.get_ticks_msec() - t0 < 20000:  # by the clock: a headless frame is a few ms
		await process_frame
	_check(arrived[0], "go() arrives round the lake and says so")
	mo.follow(PackedVector3Array([from + Vector3(0, 0, -2.0), from + Vector3(-0.5, 0, -2.0)]), func(): arrived[1] = true)
	t0 = Time.get_ticks_msec()
	while not arrived[1] and Time.get_ticks_msec() - t0 < 20000:  # by the clock: a headless frame is a few ms
		await process_frame
	_check(arrived[1], "follow() arrives and says so")
	main.queue_free()


## 5. While the map is being made, nobody crosses in a straight line.
func _no_straight_line_while_baking() -> void:
	# A fight's ground asked for, not yet laid: a man steered across the lake stands.
	var main := Node3D.new()
	main.set_script(_stub_main())
	root.add_child(main)
	var g: RefCounted = Ground.around(main, Vector3.ZERO, 4.0)
	var man := Node3D.new()
	main.add_child(man)
	man.global_position = Vector3(-1.4, 0, 0)
	var mo: Node = Mover.of(man).on(g)
	mo.clip = ""
	var waded := 0
	var frames := 0
	while not g.built and frames < 600:
		mo.toward(Vector3(1.4, 0, 0), 0.5)
		await process_frame
		frames += 1
		if Vector2(man.global_position.x, man.global_position.z).distance_to(LAKE) < LAKE_R - 0.05:
			waded += 1
	_check(waded == 0, "steered before the ground is laid, he never wades (%d of %d frames in the lake)" % [waded, frames])
	main.queue_free()
	# A town with a well, its walk map asked for and still baking: a man sent across it never stands in the well.
	var town_main = Node3D.new()
	town_main.set_script(_stub_town_main())
	town_main.build()
	root.add_child(town_main)
	var aw := Node.new()
	town_main.add_child(aw)
	Engine.set_meta("awareness", aw)
	var town: Node3D = town_main.towns.get_child(0)
	town_main.scenes.nav.map_for(1, town)  # the town in view: its walk map asked for (town_life does)
	var walker := Node3D.new()
	town_main.add_child(walker)
	walker.global_position = Vector3(-0.8, 0, 0)
	var wm: Node = Mover.of(walker)
	wm.clip = ""
	wm.speed = 0.5
	wm.go(Vector3(0.8, 0, 0))
	var in_well := 0
	var moved := 0.0
	for k in 300:
		await process_frame
		moved = maxf(moved, walker.global_position.distance_to(Vector3(-0.8, 0, 0)))
		if Vector2(walker.global_position.x, walker.global_position.z).length() < WELL_R:
			in_well += 1
	_check(in_well == 0, "while its town's walk map bakes, a man sent across never stands in the well (%d frames in it, moved %.2f)" % [in_well, moved])
	_check(wm.moving(), "while its town's walk map bakes, he waits for it (still on his way)")
	wm.stop()
	town_main.scenes.nav.forget(1)  # its walk map freed with the town
	Engine.remove_meta("awareness")
	town_main.queue_free()


const WELL_R := 0.2
const LEAST := 0.09  # game units: about 0.7 m, the nominal file (0.12) less both men's jitter (jitter.place) between any two men's middles, at rest and on the march (a man is 0.22)


## 7. Panic spreads. A made-up field, 60 seconds in tenths: the beaten side (1) bleeds as army_field's fight does
## (men a second), the flanked one hardest; the broken run off at field.run.
func _panic_spreads() -> void:
	var M: GDScript = load("res://scripts/army_morale.gd") if ResourceLoader.exists("res://scripts/army_morale.gd") else null
	_check(M != null, "a regiment's nerve has one decider (army_morale.gd)")
	if M == null:
		return
	var plain := _panic_run(M, false)
	var steadied := _panic_run(M, true)
	var t: Dictionary = plain["broke"]
	print("ARMY PROBE panic: broke at %s; with the commander by the neighbour: %s" % [str(t), str(steadied["broke"])])
	_check(t.has("flanked") and t.values().min() == t["flanked"], "the flanked regiment breaks first")
	_check(t.has("neighbour") and float(t["neighbour"]) < float(t.get("far", INF)), "its neighbour breaks sooner than an equal regiment far off (the chain)")
	_check(not t.has("fresh"), "a fresh regiment beside the rout holds")
	_check(float((steadied["broke"] as Dictionary).get("neighbour", INF)) > float(t.get("neighbour", INF)), "the commander beside the neighbour steadies it")
	_check(not t.has("victor") and float(plain["victor_low"]) >= Data.num("army", "morale.floor_victor", 0.4) - 0.001, "the victors never break (lowest nerve %.2f)" % float(plain["victor_low"]))


func _panic_run(M: GDScript, commander: bool) -> Dictionary:
	var holder := Node3D.new()
	root.add_child(holder)
	var make := func(nm: String, side: int, at: Vector3) -> Dictionary:
		var n := Node3D.new()
		holder.add_child(n)
		n.global_position = at
		var hsm := LimboHSM.new()
		n.add_child(hsm)
		var r := {"name": nm, "node": n, "side": side, "men": 150, "state_name": "fight", "hsm": hsm, "w": 0.36}
		M.start(r)
		return r
	var rows := {"flanked": make.call("flanked", 1, Vector3(0, 0, 0)), "neighbour": make.call("neighbour", 1, Vector3(0.7, 0, 0)),
		"far": make.call("far", 1, Vector3(5, 0, 0)), "fresh": make.call("fresh", 1, Vector3(-0.7, 0, 0)),
		"victor": make.call("victor", 0, Vector3(0, 0, 1.0))}
	var bleed := {"flanked": 4.0, "neighbour": 2.0, "far": 2.0, "fresh": 0.0, "victor": 2.0}
	var lord := {}
	if commander:
		lord = make.call("lord", 1, Vector3(0.7, 0, -0.5))
	var sides := [[rows["victor"]], [rows["flanked"], rows["neighbour"], rows["far"], rows["fresh"]] + ([lord] if commander else [])]
	var broke := {}
	var owed := {}
	var low := 1.0
	var dt := 0.1
	var run := Data.num("battle", "field.run", 0.42)
	for k in 600:
		for nm in rows:
			var r: Dictionary = rows[nm]
			if r["state_name"] == "rout":
				(r["node"] as Node3D).global_position += Vector3(0, 0, -run * dt)  # running off the field
				continue
			owed[nm] = float(owed.get(nm, 0.0)) + float(bleed[nm]) * dt
			if float(owed[nm]) >= 1.0:
				var men := int(owed[nm])
				owed[nm] = float(owed[nm]) - men
				M.fell(sides, r, men, (r["node"] as Node3D).global_position + Vector3(0, 0, 0.1))
		for r in M.step(sides, dt, 1, [{}, lord], false):
			r["state_name"] = "rout"
			broke[r["name"]] = k * dt
			M.broke(sides, r)
		low = minf(low, M.of(rows["victor"]))
	holder.free()
	return {"broke": broke, "victor_low": low}


const SPREAD := 8.0  # seconds: the most between one regiment's break and the next along the line
const SEED := 3118  # the line's layout (its regiments' frontage)


## 8. The rout runs along a real line. The beaten side (1): three foot regiments abreast and archers a row behind,
## each as army.gd lays a battle's regiment out (its width from field.frontage and its kind's spacing), army.gap
## between them; the victors (0) at sword's length. Steps of a slow frame (0.25 s); the end regiment is flanked.
func _rout_runs_along_the_line() -> void:
	var M: GDScript = load("res://scripts/army_morale.gd")
	var ArmyS: GDScript = load("res://scripts/army.gd")
	var deep: Array = Data.value("battle", "field.frontage", [10, 14])
	var a: Object = ArmyS.new(Node.new(), 0, {"side": 1, "frontage": deep})
	(a.get("_rng") as RandomNumberGenerator).seed = SEED
	var units: Dictionary = Data.value("army", "units", {})
	var kind_of := func(role: String) -> String:
		for k in units:
			if String((units[k] as Dictionary).get("role", "")) == role:
				return k
		return ""
	var holder := Node3D.new()
	root.add_child(holder)
	var make := func(nm: String, side: int, kind: String) -> Dictionary:
		var row: Dictionary = units.get(kind, {})
		var sp: Dictionary = row.get("spacing", {})
		var r := {"name": nm, "side": side, "men": 150, "figures": int(a.call("figures", 150)), "role": String(row.get("role", "melee")),
			"sf": float(sp.get("file", Data.num("army", "spacing.file", 0.1))), "sr": float(sp.get("rank", Data.num("army", "spacing.rank", 0.12))),
			"state_name": "fight"}
		var l: Dictionary = (load("res://scripts/army_formation.gd") as GDScript).call("layout", r, "line", deep, a.get("_rng"))
		r["w"] = float(l["w"])
		r["d"] = float(l["d"])
		var n := Node3D.new()
		holder.add_child(n)
		var hsm := LimboHSM.new()
		n.add_child(hsm)
		r["node"] = n
		r["hsm"] = hsm
		M.start(r)
		return r
	var gap := Data.num("army", "gap", 0.35)
	var beaten: Array = []
	for i in 3:
		beaten.append(make.call("foot%d" % i, 1, kind_of.call("melee")))
	var span := -gap
	for r in beaten:
		span += float(r["w"]) + gap
	var x := -span * 0.5
	for r in beaten:  # the front row, facing -Z (the victors stand at -Z)
		(r["node"] as Node3D).global_position = Vector3(x + float(r["w"]) * 0.5, 0, 0)
		x += float(r["w"]) + gap
	var bows: Dictionary = make.call("archers", 1, kind_of.call("ranged"))
	(bows["node"] as Node3D).global_position = Vector3(0, 0, float(beaten[1]["d"]) * 0.5 + Data.num("army", "line.rowGap", 0.7) + float(bows["d"]) * 0.5)
	beaten.append(bows)
	var victor: Dictionary = make.call("victors", 0, kind_of.call("melee"))
	(victor["node"] as Node3D).global_position = Vector3(0, 0, -float(beaten[1]["d"]) - Data.num("battle", "field.fight.contact", 0.12))
	var sides := [[victor], beaten]
	var loss: Dictionary = Data.value("battle", "field.fight.loss", {"beaten": 2.4, "victors": 0.9})
	var vol: Dictionary = Data.value("battle", "field.volley", {})
	var kills: Array = vol.get("kills", [1, 4])
	var every: Array = vol.get("every", [2.5, 3.6])
	var shot := (float(kills[0]) + float(kills[1])) / (float(every[0]) + float(every[1]))  # the victors' archers on ours: men a second (beaten fall twice as often)
	var bleed := {"foot0": float(loss["beaten"]) * Data.num("battle", "field.fight.flanked", 1.6), "foot1": float(loss["beaten"]), "foot2": float(loss["beaten"]),
		"archers": shot * 2.0, "victors": float(loss["victors"])}
	var longest := Data.num("battle", "field.longest", 45.0)
	var run := Data.num("battle", "field.run", 0.42)
	var spent_aware: bool = M.get_script_method_list().any(func(m): return m["name"] == "step" and (m["args"] as Array).size() >= 5)
	var broke := {}
	var owed := {}
	var dt := 0.25
	var clock := 0.0
	while clock < longest + 30.0 and broke.size() < beaten.size():
		clock += dt
		for r in beaten + [victor]:
			if r["state_name"] == "rout":
				(r["node"] as Node3D).global_position += Vector3(0, 0, run * dt)  # running off, away from the victors
				continue
			owed[r["name"]] = float(owed.get(r["name"], 0.0)) + float(bleed[r["name"]]) * dt
			if float(owed[r["name"]]) >= 1.0:
				var men := int(owed[r["name"]])
				owed[r["name"]] = float(owed[r["name"]]) - men
				var front: Vector3 = (r["node"] as Node3D).global_position + Vector3(0, 0, (-1.0 if int(r["side"]) == 1 else 1.0) * float(r["d"]) * 0.5)
				M.fell(sides, r, men, front if r["role"] != "ranged" else (r["node"] as Node3D).global_position)
		var gone: Array = M.step(sides, dt, 1, [victor, beaten[1]], clock > longest) if spent_aware else M.step(sides, dt, 1, [victor, beaten[1]])
		if not spent_aware and clock > longest:  # HEAD's field: past field.longest every beaten regiment standing breaks
			for r in beaten:
				if r["state_name"] != "rout" and not gone.has(r):
					gone.append(r)
		for r in gone:
			r["state_name"] = "rout"
			broke[r["name"]] = clock
			M.broke(sides, r)
	holder.free()
	a.free()
	var order := broke.keys()
	order.sort_custom(func(p, q): return float(broke[p]) < float(broke[q]))
	var at := PackedStringArray()
	for nm in order:
		at.append("%s %.2f" % [nm, float(broke[nm])])
	print("ARMY PROBE rout along the line (widths %.2f, gap %.2f): %s" % [float(beaten[0]["w"]), gap, ", ".join(at)])
	_check(broke.size() == beaten.size(), "every beaten regiment breaks (%d of %d)" % [broke.size(), beaten.size()])
	_check(order.size() > 0 and order[0] == "foot0", "the flanked end breaks first")
	_check(order.size() > 1 and order[1] != "foot2", "the second break is beside the first (along the line or the archers behind), not the far end")
	_check(order.size() > 2 and order.find("foot2") > order.find("foot1"), "the far end breaks after the middle: the rout runs along the line")
	var worst := 0.0
	var least := INF
	for i in range(1, order.size()):
		var step := float(broke[order[i]]) - float(broke[order[i - 1]])
		worst = maxf(worst, step)
		least = minf(least, step)
	_check(order.size() > 1 and worst <= SPREAD, "each break follows the one before within %.0f s (longest wait %.2f s)" % [SPREAD, worst])
	_check(order.size() > 1 and least >= 1.0, "never two in one moment: a second or more between breaks (closest %.2f s)" % least)


## 9. The lens on the rout: a beaten line of three (nerve 0.9, 0.5, 0.7) and a victor; lens_aim at blows, then as
## they break one by one.
func _lens_on_the_rout() -> void:
	var M: GDScript = load("res://scripts/army_morale.gd")
	var FieldS: GDScript = load("res://scripts/army_field.gd")
	var has := FieldS.get_script_method_list().any(func(m): return m["name"] == "lens_aim") and FieldS.get_script_method_list().any(func(m): return m["name"] == "lens_distance")
	_check(has, "the battle's lens has one rule (army_field.gd lens_aim, lens_distance)")
	if not has:
		return
	_check(FieldS.get_script_method_list().any(func(m): return m["name"] == "routed") and FileAccess.get_file_as_string("res://scripts/autoplay.gd").contains("\"rout\":"),
		"a film can wait for the first break (army_field.routed, autoplay's rout step)")
	var want := Data.num("camera", "town_view.dist", 6.0)
	_check(absf(float(FieldS.call("lens_distance")) - want) < 0.01, "the lens stands at the square's distance (%.1f, want %.1f)" % [float(FieldS.call("lens_distance")), want])
	var holder := Node3D.new()
	root.add_child(holder)
	var make := func(nm: String, side: int, at: Vector3, nerve: float) -> Dictionary:
		var n := Node3D.new()
		holder.add_child(n)
		n.global_position = at
		var hsm := LimboHSM.new()
		n.add_child(hsm)
		var r := {"name": nm, "node": n, "side": side, "men": 150, "state_name": "fight", "hsm": hsm, "w": 0.48}
		hsm.get_blackboard().set_var(&"morale", nerve)
		return r
	var line := [make.call("left", 1, Vector3(-0.85, 0, 0), 0.9), make.call("mid", 1, Vector3(0, 0, 0), 0.5), make.call("right", 1, Vector3(0.85, 0, 0), 0.7)]
	var rows := [[make.call("victor", 0, Vector3(0, 0, -0.5), 1.0)], line]
	var start := Vector3(0, 0, -4.5)  # the middle of the field, where the lines formed
	var aim: Vector3 = FieldS.call("lens_aim", rows, 1, true, start)
	_check(aim.distance_to(Vector3.ZERO) < 0.01, "at blows the lens looks at the regiment that breaks next (%s)" % str(aim))
	line[1]["state_name"] = "rout"
	aim = FieldS.call("lens_aim", rows, 1, true, aim)
	_check(aim.distance_to(Vector3(0.85, 0, 0)) < 0.01, "as it breaks, the lens moves along the line to the next (%s)" % str(aim))
	line[2]["state_name"] = "rout"
	line[0]["state_name"] = "rout"
	var after: Vector3 = FieldS.call("lens_aim", rows, 1, true, aim)
	_check(after.distance_to(aim) < 0.01, "once none stands, the lens stays where the rout ended")
	holder.free()


## 10. The right banner: regiments raised (army.gd _regiment, as every host raises them) for House Ashby, whose arms
## are drawn, and for a house with none.
func _the_right_banner() -> void:
	var H: GDScript = load("res://scripts/heraldry.gd")
	var ArmyS: GDScript = load("res://scripts/army.gd")
	var ashby := {"name": "House Ashby"}
	var none := {"name": "House Nobody"}
	var want: Texture2D = load("res://assets/heraldry/banner-ashby.png")
	_check(H.get_script_method_list().any(func(m): return m["name"] == "arms"), "a house's arms come from one place (heraldry.gd arms)")
	var banner_owner := ResourceLoader.exists("res://scripts/army_banners.gd") and not ArmyS.get_script_method_list().any(func(m): return m["name"] in ["_banner", "_flag_quad", "_standard_place"])
	_check(banner_owner, "a host's banners and standard have one owner (army_banners.gd; integration audit #12)")
	var look_owner := ResourceLoader.exists("res://scripts/army_visual.gd") and not ArmyS.get_script_method_list().any(func(m): return m["name"] in ["_asset", "_soldier_mesh", "_lods", "_wear_arms", "_shadows"])
	_check(look_owner, "the soldiers' look and lighter levels have one owner (army_visual.gd; integration audit #12)")
	var shape_owner := ResourceLoader.exists("res://scripts/army_formation.gd") and not ArmyS.get_script_method_list().any(func(m): return m["name"] in ["_layout", "_line_places", "_in_column_order", "_column_length"])
	_check(shape_owner, "a host's shapes have one owner (army_formation.gd; integration audit #12)")
	var a: Object = ArmyS.new(Node.new(), 0, {"side": 0, "colour": Color(0.2, 0.3, 0.6), "house": ashby})
	var units: Dictionary = Data.value("army", "units", {})
	var colour := Color(0.2, 0.3, 0.6)
	for k in ["spearmen", "archers"]:
		if not units.has(k):
			continue
		var r: Dictionary = a.call("_regiment", {"id": 1, "unit": k, "men": 150}, colour, ashby)
		if r.is_empty():
			_check(false, "%s raised (its baked soldier loads)" % k)
			continue
		var bm: ShaderMaterial = r["banner_mat"]
		var lv: ShaderMaterial = (r["vat"] as GeometryInstance3D).material_override
		_check(bool(bm.get_shader_parameter("use_arms")) and bm.get_shader_parameter("arms") == want and bool(bm.get_shader_parameter("canton")),
			"%s of House Ashby: its banner flies Ashby's arms, its glyph in the canton" % k)
		_check((bm.get_shader_parameter("field_color") as Color).is_equal_approx(colour), "%s: the canton and pips in its house colour" % k)
		_check(bool(lv.get_shader_parameter("emblem_on")) and lv.get_shader_parameter("emblem_texture") == want and (lv.get_shader_parameter("team_color") as Color).is_equal_approx(H.field_colour(ashby, colour)),
			"%s: its men wear Ashby's arms on shield and tabard, in its banner's own colour (Heraldry.field_colour)" % k)
	_check(a.is_in_group(&"host_views") and a.has_method("select_host"), "the command card finds this host view (group host_views, select_host)")
	var of_face := func(h: Dictionary) -> float: return float(ArmyS.call("order_face", h)) if ArmyS.get_script_method_list().any(func(m): return m["name"] == "order_face") else INF
	_check(is_equal_approx(float(of_face.call({"order": {"kind": "march", "face": 1.25}})), 1.25) and is_nan(float(of_face.call({"order": {"kind": "march", "face": null}}))) and is_nan(float(of_face.call({"order": null}))),
		"a host's line faces the way its order says (order.face), its own way when none")
	var plain: Dictionary = a.call("_regiment", {"id": 2, "unit": "spearmen", "men": 150}, colour, none)
	if not plain.is_empty():
		_check((plain["banner_mat"] as ShaderMaterial).get_shader_parameter("use_arms") != true, "a house with no arms drawn flies its colour with the glyph")
	a.free()


## 11. War: the host marches out. Three regiments raised (army.gd _regiment) and stood in line at a field, on a
## stand-in realm whose one road runs east then north; march_out to its end, at 30x the game's pace.
func _march_out() -> void:
	var ArmyS: GDScript = load("res://scripts/army.gd")
	var has := ArmyS.get_script_method_list().any(func(m): return m["name"] == "march_out")
	_check(has, "a host can march out (army.gd march_out)")
	var scenes_src := FileAccess.get_file_as_string("res://scripts/scenes.gd") + FileAccess.get_file_as_string("res://scripts/scene_kinds/muster.gd")
	var muster_at := scenes_src.find("func raise(") if scenes_src.find("func _muster(") < 0 else scenes_src.find("func _muster(")
	var muster_end := scenes_src.find("\nfunc ", muster_at + 1)
	var muster_src := scenes_src.substr(muster_at, (muster_end - muster_at) if muster_end > 0 else -1) if muster_at >= 0 else ""
	_check(muster_src.contains("Army.new(") and muster_src.contains("\"out_to\"") and not scenes_src.contains("func _on_route("),
		"the muster scene raises the army layer's host to march out (army.gd out_to); no marcher is tweened along a route")
	if not has:
		return
	var stub := GDScript.new()
	stub.source_code = """extends Node3D
var terrain: Node3D
var roads: Node
var rig = null
var scenes = null
var towns = null
func build(road: PackedVector3Array) -> void:
	terrain = Node3D.new()
	var ts := GDScript.new()
	ts.source_code = "extends Node3D\\nvar width := 0\\nvar built := false\\nfunc height_at(_x: float, _z: float) -> float:\\n\\treturn 0.0\\n"
	ts.reload()
	terrain.set_script(ts)
	add_child(terrain)
	roads = Node.new()
	var rs := GDScript.new()
	rs.source_code = "extends Node\\nvar way := PackedVector3Array()\\nvar asked := 0\\nvar reach_asked := 0.0\\nfunc route(a: Vector3, _b: Vector3, reach := 2.5) -> PackedVector3Array:\\n\\tasked += 1\\n\\treach_asked = reach\\n\\treturn way if way.is_empty() or Vector2(a.x - way[0].x, a.z - way[0].z).length() <= reach else PackedVector3Array()\\n"
	rs.reload()
	roads.set_script(rs)
	roads.way = road
	add_child(roads)
"""
	stub.reload()
	var main := Node3D.new()
	main.set_script(stub)
	root.add_child(main)
	var road := PackedVector3Array([Vector3(1, 0, 0), Vector3(3, 0, 0), Vector3(3, 0, 12)])  # long enough for a column of regiments drawn to their floor (figureFloor)
	main.call("build", road)
	var a: Node3D = ArmyS.new(main, 0, {"side": 0, "colour": Color(0.6, 0.15, 0.15), "house": {"name": "House Ashby"}, "quiet": true, "out_to": road[road.size() - 1]})
	var rows: Array = []
	for k in ["archers", "spearmen", "horse"]:
		var r: Dictionary = a.call("_regiment", {"id": -(rows.size() + 1), "unit": k, "men": 150}, Color(0.6, 0.15, 0.15), {"name": "House Ashby"})
		if not r.is_empty():
			rows.append(r)
	a.set("_regiments", rows)
	a.set("_field", Vector3.ZERO)
	main.add_child(a)  # its _ready waits for land the stand-in never builds: the probe drives it
	a.set("_commander", rows[0])
	a.call("_standard_up")
	for i in rows.size():
		var r: Dictionary = rows[i]
		a.call("_shape", r, "line")
		a.call("_set_at", r, Vector3((i - 1) * 0.6, 0, -0.3), 0.0)
		r["state"] = "rest"
	var phase := func() -> String: return String(a.call("march_phase")) if a.has_method("march_phase") else "?"
	a.set("mustered", true)
	var formed: String = phase.call()
	a.call("march_out", road[road.size() - 1])
	var out: String = phase.call()
	var auto_src := FileAccess.get_file_as_string("res://scripts/autoplay.gd")
	_check(formed == "formed" and out == "out", "the host says where it is in its march (formed %s, then out %s)" % [formed, out])
	_check(auto_src.contains("\"muster\":") and auto_src.contains("march_phase"), "the film has a play step that waits for the muster's phase (autoplay muster)")
	_check(int(main.roads.asked) > 0, "it asks the realm's roads for its way")
	var order: Array = Data.value("army", "column.order", ["cavalry", "melee", "ranged"])
	var by_leave := rows.duplicate()
	by_leave.sort_custom(func(p, q): return float(p["leave"]) < float(q["leave"]))
	var roles := by_leave.map(func(r): return String(r["role"]))
	var want := roles.duplicate()
	want.sort_custom(func(p, q): return order.find(p) < order.find(q))
	_check(roles == want, "it leaves in column order (%s)" % ", ".join(PackedStringArray(roles)))
	var spaced := true
	for i in range(1, by_leave.size()):
		var gone: float = (float(by_leave[i]["off"]) - float(by_leave[i - 1]["off"]))
		spaced = spaced and absf((float(by_leave[i]["leave"]) - float(by_leave[i - 1]["leave"])) * float(by_leave[i]["speed"]) - gone) < 0.01 and gone > 0.0
	_check(spaced, "each regiment leaves once the one ahead has gone its length up the road")
	Engine.time_scale = 30.0
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < 8000 and not rows.all(func(r): return r["state"] == "halt"):
		await process_frame
	var states := rows.map(func(r): return String(r["state"]))
	_check(rows.all(func(r): return r["state"] == "halt"), "every regiment halts at the road's end (%s)" % str(states))
	_check(phase.call() == "halted", "and the host says it has halted (%s)" % phase.call())
	var near := INF
	var on_road := true
	var along: Array = []
	for i in by_leave.size():
		var p: Vector3 = (by_leave[i]["node"] as Node3D).global_position
		var s_at := float(a.call("_along", p))
		on_road = on_road and (a.call("_at", s_at) as Vector3).distance_to(p) < 0.05
		along.append(s_at)
		for j in range(i + 1, by_leave.size()):
			near = minf(near, p.distance_to((by_leave[j]["node"] as Node3D).global_position))
	var head_first := true
	for i in range(1, along.size()):
		head_first = head_first and float(along[i]) < float(along[i - 1])
	_check(on_road and head_first, "they halt on the road in column, the first out at its head (%s along)" % str(along.map(func(v): return snappedf(v, 0.01))))
	_check(near > 0.2, "no two regiments halt in one place (closest %.2f apart)" % near)
	t0 = Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < 4000 and is_instance_valid(a) and not a.is_queued_for_deletion():
		await process_frame
	_check(not is_instance_valid(a) or a.is_queued_for_deletion(), "then the host is gone (march.linger)")
	Engine.time_scale = 1.0
	main.queue_free()


## 12. A click picks a host by its own body: a bearer (scale 0.5) at the origin, a regiment's node at x 1.2,
## the lens at an oblique, as host 0 6 -25 frames one.
func _pick_by_body() -> void:
	var P: GDScript = load("res://scripts/host_pick.gd") if ResourceLoader.exists("res://scripts/host_pick.gd") else null
	_check(P != null, "a host is picked by its own body (host_pick.gd)")
	var hc_src := FileAccess.get_file_as_string("res://scripts/host_command.gd")
	_check(hc_src.contains("HostPick.pick(") and not hc_src.contains("pick_px") and not hc_src.contains("func _pick_regiment("),
		"host_command.gd takes the pick at the press, with no screen-distance guess")
	if P == null:
		return
	var holder := Node3D.new()
	root.add_child(holder)
	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.look_at_from_position(Vector3(0.6, 2.2, 4.0), Vector3(0.6, 0.2, 0.0))
	cam.current = true
	var bearer := Node3D.new()
	holder.add_child(bearer)
	bearer.scale = Vector3.ONE * 0.5
	P.call("proxy", bearer, 42, Vector3(0.22, 0.62, 0.22))
	var reg := Node3D.new()
	holder.add_child(reg)
	reg.position = Vector3(1.2, 0, 0)
	var view := Node.new()
	holder.add_child(view)
	P.call("proxy", reg, 7, Vector3(0.6, 0.57, 0.5), view)
	for i in 3:
		await physics_frame
	var standard: Dictionary = P.call("pick", cam, cam.unproject_position(Vector3(0.0, 0.5, 0.0)))
	_check(int(standard.get("unit", -1)) == 42, "a click on the standard picks its company (%s)" % str(standard))
	var regiment: Dictionary = P.call("pick", cam, cam.unproject_position(Vector3(1.2, 0.2, 0.0)))
	_check(int(regiment.get("unit", -1)) == 7 and regiment.get("view") == view, "a click on a regiment's men picks it, with its view (%s)" % str(regiment))
	var land: Dictionary = P.call("pick", cam, cam.unproject_position(Vector3(-2.0, 0.0, -1.0)))
	_check(land.is_empty(), "a click on open land picks no host")
	holder.free()


## 6. One figure for ten, each with room about him.
func _figures_and_room() -> void:
	var ArmyS: GDScript = load("res://scripts/army.gd")
	var a: Object = ArmyS.new(Node.new(), 0, {})
	var has: bool = a.has_method("figures")
	_check(has, "a regiment's figures come from one place (army.gd figures)")
	var ratio := Data.num("army", "drawPerMan", 1.0)
	var units: Dictionary = Data.value("army", "units", {})
	for k in units:
		var row: Dictionary = units[k]
		var men := int(row.get("men", 150))
		var want := int(Data.num("army", "figureFloor", 0.0)) + maxi(1, ceili(men * ratio - 0.0001))
		var got: int = int(a.call("figures", men)) if has else men
		_check(got == want, "%s: %d men draw %d figures (want %d)" % [k, men, got, want])
		var sp: Dictionary = row.get("spacing", {})
		var r := {"men": men, "figures": got, "role": String(row.get("role", "melee")),
			"sf": float(sp.get("file", Data.num("army", "spacing.file", 0.1))), "sr": float(sp.get("rank", Data.num("army", "spacing.rank", 0.12)))}
		for shape in ["line", "column"]:
			var l: Dictionary = (load("res://scripts/army_formation.gd") as GDScript).call("layout", r, shape, null, a.get("_rng"))
			var at: PackedVector3Array = l["at"]
			var near := INF
			for i in at.size():
				for j in range(i + 1, at.size()):
					near = minf(near, Vector2(at[i].x - at[j].x, at[i].z - at[j].z).length())
			_check(near >= LEAST, "%s in %s: the closest two of %d stand %.3f apart (least %.2f)" % [k, shape, at.size(), near, LEAST])
			if shape == "line":
				_check(at.size() < 4 or int(l["files"]) < at.size(), "%s in line stays a block (%d files of %d)" % [k, int(l["files"]), at.size()])
	a.free()


## A stand-in for main with one town (a well at its middle) on flat dry land, and the realm's navigation.
func _stub_town_main() -> GDScript:
	var t := GDScript.new()
	t.source_code = '''extends Node3D
var terrain: Node3D
var towns: Node3D
var scenes: Node
func build() -> void:
	terrain = Node3D.new()
	var ts := GDScript.new()
	ts.source_code = "extends Node3D\\nvar built := true\\nvar paths = self\\nfunc height_at(_x: float, _z: float) -> float:\\n\\treturn 0.0\\nfunc is_land(_x: float, _z: float) -> bool:\\n\\treturn true\\nfunc walkable(_x: float, _z: float) -> bool:\\n\\treturn true\\nfunc land_path(a: Vector3, b: Vector3) -> PackedVector3Array:\\n\\treturn PackedVector3Array([a, b])\\nfunc bowed(p: PackedVector3Array) -> PackedVector3Array:\\n\\treturn p\\n"
	ts.reload()
	terrain.set_script(ts)
	add_child(terrain)
	towns = Node3D.new()
	var tw := GDScript.new()
	tw.source_code = "extends Node3D\\nvar towns := {}\\n"
	tw.reload()
	towns.set_script(tw)
	add_child(towns)
	var town := Node3D.new()
	town.set_meta("reach", 1.2)
	towns.add_child(town)
	towns.towns[1] = {"node": town}
	var well := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = %f
	cm.bottom_radius = %f
	cm.height = 0.15
	well.mesh = cm
	town.add_child(well)
	well.position = Vector3(0, 0.075, 0)
	scenes = Node.new()
	var sc := GDScript.new()
	sc.source_code = "extends Node\\nvar nav = preload(\\"res://scripts/town_nav.gd\\").new()\\n"
	sc.reload()
	scenes.set_script(sc)
	add_child(scenes)
	scenes.nav.terrain = terrain
''' % [WELL_R, WELL_R]
	t.reload()
	return t


## A stand-in for main: land everywhere but a round lake at the middle, flat at height 0, no towns.
func _stub_main() -> GDScript:
	var t := GDScript.new()
	t.source_code = '''extends Node3D
var terrain: Object = self
var towns = null
func walkable(x: float, z: float) -> bool:
	return Vector2(x, z).distance_to(Vector2(%f, %f)) >= %f
func height_at(_x: float, _z: float) -> float:
	return 0.0
''' % [LAKE.x, LAKE.y, LAKE_R]
	t.reload()
	return t
