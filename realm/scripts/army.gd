extends Node3D
## A host of regiments: the army layer's massed army (docs/research/army-layer-2026-11-12.md; targets
## docs/art/target/03-army.jpg and docs/research/army-and-town-rules.md section 1: Total War's regiment and banner,
## Warcraft III's worn colour, Age of Empires' column and line). The far look of every army in the realm: the
## muster by the seat (--army-spike=<men> in a shot, --dist=<height>; --army-spike=host for the crown's largest
## host as the bridge reports it, /world hosts, bridge/hosts.js), both sides of a field battle and the storm of a
## siege (army_field.gd raises them as battle sides and gives their regiments their minds).
##
## Every regiment is one body with one Mover (mover.gd, CLAUDE.md's one way to move) standing on the host's
## ground (army_ground.gd: round water, houses and walls): it marches the road in by the way the roads gave
## (Mover.follow), goes to its place in the line by a route (Mover.go), and a battle steers it (Mover.toward). Its
## men hold their places in it, laid out by the formation rows in data/army.json (line, column); changing shape
## walks each man from his place in the one to his place in the other.
##
## The host is commanded by regiment, never by man. A regiment (100-200 men) is one VATMultiMeshInstance3D
## (antzGames' VAT plugin, MIT) of its unit's baked soldier, wearing the house colour (army_vat.gdshader), under
## ONE banner (army_banner.gdshader: house colour, its type's glyph, strength as pips). The host has one larger
## standard over the commander's regiment. Two shapes, chosen by the game: a column 4-6 men wide marching along
## the road, then a line at the muster (melee in front, archers behind, cavalry on the wings); ranks loose, each
## man a little off his mark. Marching men keep their regiment's step, each a little off it; men at ease shift,
## turn and change their stance now and then. From afar (far.at) the host shows as coloured blocks with its
## standard and its strength. select(id) lays a rectangle on the ground under a regiment and lights its banner;
## regiments() lists them (the command card will call both). Ids follow the bridge: a regiment is a company (its
## Freeciv unit id), the host its lead company's; a made-up host's regiments have negative ids.
##
## Switches: --army-shape=auto (march in, then form the line; the default), march (stay in column), line (stand
## in line from the start); --army-select=<n>|all (select the n-th regiment, or the whole host by its standard,
## once it stands). Prints "ARMY …" lines (a test aid). Off in play; nothing else reads it. Numbers in
## data/army.json (docs/TUNING.md); units, their roles, meshes and clips are rows there (tools/rig/README.md's hook).

const Formation := preload("res://scripts/army_formation.gd")  # its shapes: line, column, places, order
const Visual := preload("res://scripts/army_visual.gd")
const HostPick := preload("res://scripts/host_pick.gd")  # a click on a regiment picks it by its own body  # its baked soldiers, their look and lighter levels
const KNIGHT := Visual.KNIGHT
const Data := preload("res://scripts/data.gd")
const Mover := preload("res://scripts/mover.gd")  # the one way to move (CLAUDE.md)
const Ground := preload("res://scripts/army_ground.gd")
const TownNav := preload("res://scripts/town_nav.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const VAT := preload("res://addons/godot_vat/vat_multi_mesh_instance_3d.gd")
const Banners := preload("res://scripts/army_banners.gd")  # its banners and standard (READY.md line 4)
const Terrain := preload("res://scripts/terrain.gd")
const Awareness := preload("res://scripts/awareness.gd")  # how long a season lasts (a field host's march fills it)
const HOUSES := [Color(0.82, 0.62, 0.12), Color(0.72, 0.12, 0.12), Color(0.15, 0.32, 0.72), Color(0.18, 0.5, 0.22), Color(0.45, 0.2, 0.55), Color(0.85, 0.85, 0.82)]

## A regiment is shown or selected (the command card listens; no one else does yet).
signal selection_changed(ids: Array)

var main: Node
var men := 0
var host_id := 0  # the bridge's host id (its lead company), 0 for a made-up host
var _regiments: Array = []  # see _regiment()
var _by_id := {}  # regiment id -> its regiment
var _shade_t := 0.0  # seconds to the next look at who casts shadows (army_visual.gd cast_near)
var banners := Banners.new()  # every regiment's banner and the host's standard (army_banners.gd)
var _commander: Dictionary = {}
var _report := 0.0
var _field := Vector3.ZERO  # the line's middle, on the ground
var _face := 0.0  # the line's facing (yaw; the soldier faces +Z)
var _path := PackedVector3Array()  # the column's road in, ending where it turns off for the muster
var _cum := PackedFloat32Array()  # distance along _path at each point
var _goal := "line"  # the shape the game wants: line (form at the muster) or column (stay on the road)
var _far := false
var _dist := 12.0
var _hold := false  # the camera held on the army (the whole take)
var _focus := Vector3.ZERO
var _yaw := 0.6  # the lens's heading now
var _yaw_line := 0.6  # onto the line, from its front quarter
var _yaw_march := 0.6  # onto the column, from its front quarter
var _tilt := 0.0
var _want_select := ""
var _rng := RandomNumberGenerator.new()
## One side of a battle (army_field.gd raises two): {side: 0 or 1, field: the line's middle, face: its facing,
## colour, house, shape, ground: the battle's one ground (army_ground.gd)}. Empty for the muster by the seat. A host in
## the field (units.gd keeps one per King's host on the map): {host: its /world hosts entry, quiet}.
var battle := {}
var _pending := Vector3.INF  # a field host's march Freeciv gave before its regiments were raised (march_to)
var mustered := false
var _order_face := NAN  # the way its order says its front looks (/world hosts[i].order.face), NAN for its own
var _seat_root: Node3D = null  # the seat's town (towns.gd), whose edge the muster forms past (_form_on_way)
var _then_free := false  # marching into a town (march_in): gone once halted there
var _aboard := false  # taken ship (board): its regiments filing to the hulls, then on their decks
var _pending_hulls: Array = []  # hulls to board once mustered
var _out := false  # marching out (march_out): halted at the road's end, it is gone after march.linger
var _gone_in := 0.0
var ground: RefCounted  # army_ground.gd: where its regiments may stand
var _extent := Vector2.ZERO  # the line's width and depth (for re-placing it: stand_at)  # its regiments raised and its line placed (the battle waits on both sides)
signal raised


func _init(owner: Node, count: int, side: Dictionary = {}) -> void:
	main = owner
	men = count
	battle = side
	name = "ArmySpike" if side.is_empty() else ("Host%d" % int((side["host"] as Dictionary).get("id", 0)) if side.has("host") else "ArmySide%d" % int(side.get("side", 0)))
	add_to_group(&"host_views")  # the command card (host_command.gd) finds host views here: regiments(), select_host()


func _ready() -> void:
	_rng.seed = 3017 + int(battle.get("side", 0)) * 101
	var shape := String(battle.get("shape", "auto"))
	for a in (OS.get_cmdline_user_args() if battle.is_empty() else PackedStringArray()):
		if a.begins_with("--dist="):
			_dist = float(a.substr(7))
		elif a.begins_with("--army-shape="):
			shape = a.substr(13)
		elif a.begins_with("--army-select="):
			_want_select = a.substr(14)
	for a in (OS.get_cmdline_user_args() if battle.has("out_to") else PackedStringArray()):
		if a.begins_with("--dist="):  # a muster shot's lens (shot_harness --muster takes the army's own: _hold)
			_dist = float(a.substr(7))  # g6: unread for a muster, the lens stood at 12, high over two towns
	# Wait for the land and the realm's towns as the bridge reports them.
	while main.terrain.width == 0 or not main.terrain.built or (main.awareness.rec("cities", []) as Array).is_empty():
		await get_tree().create_timer(0.5).timeout
	var in_field := battle.has("field") or battle.has("host")  # a battle side or a host in the field: no seat to muster by
	var seat := _seat() if not in_field else {"name": "the field"}
	var town: Vector3 = _ground_at(battle["field"]) if battle.has("field") else Vector3.ZERO
	if battle.has("host"):
		town = main.terrain.world_pos(float(battle["host"].get("x", 0)), float(battle["host"].get("y", 0)))
	if not in_field:
		if seat.is_empty():
			push_error("ARMY no seat in the realm to muster by")
			return
		var id := int(seat["id"])
		# Its town raised first (its buildings are what the field keeps clear of); a while at most.
		main.towns.ensure(id)
		var waited := 0.0
		while not main.towns.towns.has(id) and waited < 30.0:
			await get_tree().create_timer(0.5).timeout
			waited += 0.5
		_seat_root = main.towns.towns[id]["node"] if main.towns.towns.has(id) else null
		town = _seat_root.global_position if _seat_root else main.terrain.world_pos(float(seat["x"]), float(seat["y"]))
	# A battle side brings its own regiments (army_field.gd: one per company that fought, from Freeciv's types).
	var specs: Array = battle["specs"] if battle.has("specs") else (_made_up(men) if men > 0 else (_from_world() if not battle.has("house") else []))
	if specs.is_empty() and battle.has("out_to"):  # a muster with no host in the field (or a house's): new levies
		specs = _made_up(int(Data.num("army", "march.men", 600)))
	if specs.is_empty():
		push_error("ARMY no host to show (the crown has no soldiers, and no head count was given)")
		return
	var colours := _colours()
	for i in specs.size():
		var k := i % colours.size() if colour_mode() == "houses" else 0
		var r := _regiment(specs[i], battle["colour"], battle.get("house", {})) if battle.has("colour") else _regiment(specs[i], colours[k], _worn[k] if k < _worn.size() else {})
		if r.is_empty():
			continue
		_regiments.append(r)
		_by_id[r["id"]] = r
	if _regiments.is_empty():
		push_error("ARMY no soldier mesh to raise the host with")
		return
	# The line: where it stands and the way it faces, every regiment's place in it.
	var placed := Formation.line_places(_regiments)
	var extent: Vector2 = placed["extent"]
	_commander = placed["commander"]
	ground = battle["ground"] if battle.has("ground") else null
	_extent = extent
	if battle.has("host"):  # a host in the field: in column on its tile, marching where Freeciv moves it (march_to)
		_stand_on_tile(town, _bound_yaw(battle["host"], town))
		for r in _regiments:
			var mo: Node = Mover.of(r["node"]).on(null)  # the realm's navigation, as every marcher on the map
			mo.clip = ""
			mo.turn_rate = 3.0
		_standard_up()
		mustered = true
		raised.emit()
		if not _pending_hulls.is_empty():
			board(_pending_hulls)
		elif _pending != Vector3.INF:
			march_to(_pending)
		return
	var on_road := false
	if battle.has("field"):  # a battle side stands where the battle puts it
		_face = float(battle.get("face", 0.0))
		_field = _ground_at(battle["field"])
		_take_field(extent)
	elif battle.has("out_to"):
		_form_on_way(town, battle["out_to"], _seat_root)
		on_road = true  # war: the host forms in column on its way out, as 03-army marches
	elif not _field_for(town, extent):
		push_error("ARMY no open ground by the seat")
		_regiments.clear()
		return
	if not is_nan(_order_face):  # its order's facing (the card's drag): the line turns to it where it stands
		_face = _order_face
		_take_field(extent)
	if ground == null:
		ground = Ground.around(main, _field, maxf(extent.x, extent.y) * 0.5 + Data.num("army", "march.lead", 5.0) + 3.0)
	for r in _regiments:
		var mo: Node = Mover.of(r["node"]).on(ground)
		mo.keep = _block_keep(r)
		mo.clip = ""  # its men's clips are the regiment's (VAT tracks)
		mo.turn_rate = 3.0
		mo.speed = float(r["speed"])
	_standard_up()
	# The column on the road in, unless the host starts in line (or already stands in column on the road out).
	_goal = "column" if shape == "march" or on_road else "line"
	if on_road:
		pass
	elif shape == "line":
		for r in _regiments:
			_stand_in_line(r)
	else:
		_road_in(town)
		_column_up()
	# 03-army's pitch at the shot's own distance (camera_rig.tilt_for): pass 2243's host5 at d9 and the old -8 under the
	# map's pitch looked 24 degrees down, the column a thread across the fields.
	_tilt = main.rig.tilt_for(Data.num("army", "camera.pitch", 38.0), maxf(_dist, main.rig.min_distance)) if main.rig else 0.0
	# The spike's own lens (it fells the trees in its way): never for a battle side, which frames nothing.
	_yaw_line = _lens_yaw(_field, _face + Data.num("army", "camera.quarter", 0.4)) if battle.is_empty() else _face
	_yaw = _yaw_line
	_focus = _middle()
	if shape != "line" and battle.is_empty():
		var mid := _at(maxf(0.0, _cum[_cum.size() - 1] - Data.num("army", "march.lead", 5.0) - Formation.column_length(_regiments) * 0.5))
		var ahead := _at(_cum[_cum.size() - 1]) - mid
		_yaw_march = _lens_yaw(mid, atan2(ahead.x, ahead.z) + Data.num("army", "camera.marchQuarter", 0.9))
		_yaw = _yaw_march
	elif on_road:  # war's muster: from behind the column, a little off its line, looking down it (03-army), whatever it does next
		# far enough back to hold every block (g13: one cut off in the corner, the lens on a field)
		_dist = maxf(_dist, Formation.column_length(_regiments) * Data.num("army", "camera.musterHold", 0.75))
		_tilt = main.rig.tilt_for(Data.num("army", "camera.pitch", 38.0), maxf(_dist, main.rig.min_distance)) if main.rig else 0.0
		_yaw_march = _lens_yaw(_middle(), _face + PI + Data.num("army", "camera.musterOff", 0.5))
		_yaw_line = _yaw_march
		_yaw = _yaw_march
	var roles := {}
	for r in _regiments:
		roles[r["role"]] = int(roles.get(r["role"], 0)) + 1
	if not battle.get("quiet", false):
		print("ARMY mustered men=%d regiments=%d %s host=%d shape=%s by %s at %s, line at %s facing %.2f, road in %.1f units" % [_men(), _regiments.size(), str(roles), host_id, shape,
		String(seat.get("name", "?")), str(town), str(_field), _face, _cum[_cum.size() - 1] if not _cum.is_empty() else 0.0])
	_hold = battle.is_empty()  # the camera on the army itself, at the shot's own --dist, for the whole take (a test aid); a battle frames itself
	mustered = true
	raised.emit()
	if battle.has("out_to"):  # war: formed at its seat a while, then out along the roads (march_out)
		await get_tree().create_timer(Data.num("army", "march.form", 6.0)).timeout
		march_out(battle["out_to"])


## March out (READY.md line 3, war; casebook, War and sieges: "The march feeds the battle"): the host formed in line
## at its seat turns into column and goes out along the roads to `to` (roads.route: the realm's road graph, Godot's
## AStar3D), in column.order at its slowest regiment's pace. Each regiment turns into column and leaves once the one
## ahead has gone its column's length up the road, follows it by its Mover on the realm's navigation (off the
## muster's ground), and halts at its own place in the column at the road's end; the host is gone march.linger
## seconds after the last halts. It marches on along the way it formed on (_form_on_way: its _path runs to `to`).
func march_out(_to: Vector3) -> void:
	_goal = "column"
	_out = true
	var first := -1.0
	for r in Formation.column_order(_regiments):
		first = float(r["off"]) if first < 0.0 else first
		r["leave"] = (float(r["off"]) - first) / maxf(float(r["speed"]), 0.01)
		r["state"] = "out"
		Mover.of(r["node"]).on(null)


## A host in the field stands in column with its head on its lead company's tile, facing `yaw`, closed up behind it
## (03-army: a column of regiments, each under its banner), halted and at ease.
func _stand_on_tile(at: Vector3, yaw: float) -> void:
	var dir := Vector3(sin(yaw), 0, cos(yaw))
	_path = PackedVector3Array([_ground_at(at - dir * (Formation.column_length(_regiments) + 1.0)), _ground_at(at)])
	_cum = PackedFloat32Array([0.0, _path[0].distance_to(_path[1])])
	_field = _path[1]
	_face = yaw
	_goal = "column"
	for r in Formation.column_order(_regiments):
		r["s"] = _cum[1] - float(r["off"])
		_shape(r, "column")
		_set_at(r, _at(r["s"]), yaw)
		r["state"] = "halt"
		_clips(r, "rest")


## The way a field host faces: toward where its order sends it, else the way it last marched, else north.
func _bound_yaw(h: Dictionary, at: Vector3) -> float:
	var o: Variant = h.get("order")
	if o is Dictionary and (o as Dictionary).get("x") != null and (o as Dictionary).get("y") != null:
		var to: Vector3 = main.terrain.world_pos(float(o["x"]), float(o["y"]))
		if Vector2(to.x - at.x, to.z - at.z).length() > 0.01:
			return atan2(to.x - at.x, to.z - at.z)
	return _face


## Freeciv moved a host in the field (units.gd sync): its column marches to `to` along the realm's roads (roads.route,
## else over the land), the regiments behind following the head's trail, each by its Mover at the pace that brings
## the head there within the season (as a company's figure keeps it: never seasons behind its company), and halts
## closed up behind it, in column.order.
func march_to(to: Vector3) -> void:
	_then_free = false
	if not mustered:
		_pending = to
		return
	var order := Formation.column_order(_regiments)
	var trail := PackedVector3Array()
	for i in range(order.size() - 1, -1, -1):  # tail to head: the way the column already stands
		trail.append(_ground_at((order[i]["node"] as Node3D).global_position))
	var head: Vector3 = trail[trail.size() - 1]
	var roads = main.get("roads")
	var road: PackedVector3Array = roads.route(head, to, Data.num("army", "march.roadReach", 12.0)) if roads and roads.has_method("route") else PackedVector3Array()
	_path = trail
	if road.size() >= 2:
		_path.append_array(road.slice(1))
	_path.append(_ground_at(to))
	_cum = PackedFloat32Array([0.0])
	for j in range(1, _path.size()):
		_cum.append(_cum[j - 1] + _path[j].distance_to(_path[j - 1]))
	var ahead := _cum[_cum.size() - 1] - _cum[trail.size() - 1]
	if ahead < 0.05:
		return  # already there
	var slowest := INF
	for r in order:
		slowest = minf(slowest, Data.num("army", "march.speed", 0.16) * float(_unit(String(r["unit"])).get("speed", 1.0)))
	var pace := maxf(slowest, ahead / maxf(2.0, Awareness.season_seconds * 0.9))
	_field = _ground_at(to)
	_goal = "column"
	for r in order:
		r["s"] = _along((r["node"] as Node3D).global_position)
		r["speed"] = pace
		_clips(r, "walk")
		_march(r)


## A host come into a town (units.gd field_hosts: the bridge has it `at` a town): its column marches in along the
## road through the gate (march_to) and is gone once every regiment has halted there; its companies are the town's
## figures from then. A host that leaves again first takes a new march_to and stays.
func march_in(to: Vector3) -> void:
	march_to(to)
	_then_free = true


## A host takes ship (units.gd field_hosts: the bridge has it aboard the hulls the crown raised; 08-reinforce, the
## column marching down to the ship, men on the deck): its regiments file to the hulls in column order, one every
## deck.file seconds, each walking down to its hull by its Mover, and once there it stands on the deck as a small
## packed block (the "deck" layout, its length along the hull), a child of the hull so it sails with it. Shared out
## over the hulls in turn, each hull's regiments spaced along its deck (deck.length). Ashore again, units.gd raises the
## host's column afresh where it lands.
func board(hulls: Array) -> void:
	if not mustered:
		_pending_hulls = hulls
		return
	if _aboard or hulls.is_empty():
		return
	_aboard = true
	_then_free = false
	var order := Formation.column_order(_regiments)
	var per := ceili(float(order.size()) / hulls.size())
	var length := Data.num("army", "deck.length", 1.1)
	for i in order.size():
		var r: Dictionary = order[i]
		var hull: Node3D = hulls[i % hulls.size()]
		var slot := i / hulls.size()
		var along := (float(slot) - (per - 1) * 0.5) * length / per
		r["state"] = "board"
		var at: Vector3 = (r["node"] as Node3D).global_position
		if not main.terrain.is_land(at.x, at.z):
			_on_deck(r, hull, along)  # already at sea when first drawn: on the deck at once (g11: a host raised aboard stood under the sea)
			continue
		# Down to the water's edge toward its hull, by its Mover, then aboard (never walking under the sea).
		var edge := at
		for k in 40:
			var p := at.lerp(hull.global_position, (k + 1) / 40.0)
			if not main.terrain.is_land(p.x, p.z):
				break
			edge = p
		var mo: Node = Mover.of(r["node"]).on(null)
		mo.speed = Data.num("army", "march.speed", 0.16)
		get_tree().create_timer(i * Data.num("army", "deck.file", 1.5)).timeout.connect(func():
			if not is_instance_valid(hull) or not is_instance_valid(r["node"]):
				return
			_clips(r, "walk")
			mo.follow(PackedVector3Array([(r["node"] as Node3D).global_position, edge]), func(): _on_deck(r, hull, along)))


## Gone (ashore, or the host disbanded): its regiments on a hull's deck go with it, since they are the hull's children.
func _exit_tree() -> void:
	for r in _regiments:
		var n: Variant = r.get("node")
		if n != null and is_instance_valid(n) and not is_ancestor_of(n):
			(n as Node).queue_free()


## A regiment come to its hull: on the deck as a packed block, a child of the hull (it sails with it), at ease.
func _on_deck(r: Dictionary, hull: Node3D, along: float) -> void:
	if not is_instance_valid(hull):
		return
	var node: Node3D = r["node"]
	node.reparent(hull, false)
	# The deck over the hull's base, which units.gd ship_body sinks by map.ship_sink under the holder (the waterline).
	node.position = Vector3(along, (Data.num("army", "deck.y_m", 2.2) - Data.num("army", "map.ship_sink", 1.2)) * preload("res://scripts/world_units.gd").M, 0.0)
	node.rotation = Vector3(0.0, PI / 2.0, 0.0)  # the cog's length runs along its own x (assets/meshy/cog bounds)
	_shape(r, "deck")
	r["state"] = "halt"
	_clips(r, "rest")


## Where a host raised for war is in its march (the film's muster step waits on it): forming (its regiments not yet
## raised and placed), formed (in line at its seat), out (marching out along the road), halted (every regiment at
## its place at the road's end; gone march.linger later).
func march_phase() -> String:
	if not mustered:
		return "forming"
	if not _out:
		return "formed"
	return "halted" if _regiments.all(func(r): return r["state"] == "halt") else "out"


# --- The command hooks (the command card calls these; nothing in play does yet) -------------------------

## The host's regiments as the command card shows them: [{id, host, unit, role, glyph, men, strength, colour,
## shape, at, selected, commander}].
func regiments() -> Array:
	var out: Array = []
	for r in _regiments:
		out.append({"id": r["id"], "host": host_id, "unit": r["unit"], "role": r["role"], "glyph": r["glyph"], "men": r["men"],
			"strength": r["strength"], "colour": r["colour"], "shape": r["shape"], "at": (r["node"] as Node3D).global_position,
			"selected": r["selected"], "commander": is_same(r, _commander)})
	return out


## Selects one regiment (its ground rectangle and its banner's glow); the others are let go. False when no
## regiment has that id.
func select(regiment_id: int) -> bool:
	if not _by_id.has(regiment_id):
		return false
	for r in _regiments:
		_mark(r, r["id"] == regiment_id)
	selection_changed.emit([regiment_id])
	return true


## The whole host, as a click on its standard selects it.
func select_all() -> void:
	for r in _regiments:
		_mark(r, true)
	selection_changed.emit(_regiments.map(func(r): return r["id"]))


func deselect() -> void:
	for r in _regiments:
		_mark(r, false)
	selection_changed.emit([])


## The command card's selected host changed (host_command.gd select): this host is marked whole when it is the one,
## let go otherwise ({} for none).
func select_host(h: Dictionary) -> void:
	if not h.is_empty() and int(h.get("id", -1)) == host_id:
		select_all()
	else:
		deselect()


## A regiment's strength (0..1: its men left over its full muster), shown as its banner's pips.
func set_strength(regiment_id: int, share: float) -> void:
	if _by_id.has(regiment_id):
		var r: Dictionary = _by_id[regiment_id]
		r["strength"] = clampf(share, 0.0, 1.0)
		banners.strength(r)


## The shape the game wants: "line" (each regiment marches to its place at the muster and turns into line),
## or "column" (each regiment closes up into column where it stands).
func set_shape(shape: String) -> void:
	_goal = "column" if shape == "column" else "line"
	for r in _regiments:
		if _goal == "line" and r["state"] in ["halt", "rest"] and r["shape"] == "column":
			_deploy(r)
		elif _goal == "column" and r["shape"] == "line" and r["state"] == "rest":
			_reform(r, "column")
		elif r["state"] == "road":
			r["s"] = _along((r["node"] as Node3D).global_position)
			_march(r)  # its end on the road changes with the order


# --- For a battle (army_field.gd gives the regiments their minds; the host draws them) ---------------------

## The regiments themselves (their state is "battle" while the battle has them: the spike leaves them be).
func rows() -> Array:
	return _regiments


## The regiment the host's commander rides with (his presence steadies those about him: army_morale.gd); {} if none.
func commander() -> Dictionary:
	return _commander


func field() -> Vector3:
	return _field


## The whole line stands again at `at`, facing `face` (army_field.gd turns a battle to fit the ground), formed.
func stand_at(at: Vector3, face: float) -> void:
	_field = _ground_at(at)
	_face = face
	_take_field(_extent)
	for r in _regiments:
		_stand_in_line(r)
	banners.place()


## Whether a line of the given width and depth, its middle at `at` facing `face`, stands on ground fit for men
## (the same test as the muster's): the share of a grid of cells over it that do.
func ground_share(at: Vector3, face: float, extent: Vector2) -> float:
	var pitch := Data.num("army", "muster.cell", 2.0)
	var fwd := Vector3(sin(face), 0, cos(face))
	var right := Vector3(cos(face), 0, -sin(face))
	var nx := maxi(1, int(ceil(extent.x / pitch)) + 1)
	var nz := maxi(1, int(ceil(extent.y / pitch)) + 1)
	var ok := 0
	for i in nx:
		for j in nz:
			if _ground(at + right * (float(i) - (nx - 1) * 0.5) * pitch + fwd * (float(j) - (nz - 1) * 0.5) * pitch, pitch * 0.9):
				ok += 1
	return float(ok) / float(nx * nz)


func extent() -> Vector2:
	return _extent


func facing() -> float:
	return _face


## A regiment turned where it stands (an about-turn, a wheel in place): no travel, so no Mover.
func turn(r: Dictionary, yaw: float) -> void:
	r["yaw"] = yaw
	(r["node"] as Node3D).rotation.y = yaw


func dress(r: Dictionary) -> void:
	_dress(r)


## Every man of a regiment plays a role's clip (walk, rest, ready, attack...).
func play(r: Dictionary, role: String) -> void:
	_clips(r, role)


func track(r: Dictionary, role: String) -> int:
	return _track(r, role)


## Its banner wavers (0 steady .. 1 about to break; army_banner.gdshader's waver).
func waver(r: Dictionary, w: float) -> void:
	banners.waver(r, w)


# --- Raising the host -------------------------------------------------------------------------------------

## The crown's largest host from /world (bridge/hosts.js), a regiment per company: [{id, unit, men, strength}].
## The way a host's order says its line should face (READY.md line 8: the command card's drag to face; /world
## hosts[i].order.face, a yaw like node.rotation.y), or NAN when its order gives none.
static func order_face(h: Dictionary) -> float:
	var o: Variant = h.get("order")
	var f: Variant = (o as Dictionary).get("face") if o is Dictionary else null
	return float(f) if f is float or f is int else NAN


func _from_world() -> Array:
	var hosts: Array = main.awareness.hosts()
	if hosts.is_empty() and not battle.has("host"):
		return []
	var h: Dictionary = battle["host"] if battle.has("host") else hosts[0]  # a field host its own; else the largest (the bridge sorts them)
	host_id = int(h.get("id", 0))
	_order_face = order_face(h)
	var types := {}
	for u in main.awareness.rec("units", []):
		types[int(u.get("id", -1))] = u
	var each := float(h.get("men", 0)) / maxf(1.0, float(h.get("companies", 1)))
	var full := Data.num("army", "hpFull", 10.0)
	var out: Array = []
	for uid in h.get("units", []):
		var u: Dictionary = types.get(int(uid), {})
		var unit := _unit_for(String(u.get("type", "")))
		var hp: float = float(u.get("hp", full)) if u.get("hp") != null else full
		out.append({"id": int(uid), "unit": unit, "men": int(clampf(each, 100.0, 200.0)), "strength": clampf(hp / full, 0.05, 1.0)})
	return out


## A made-up host of about `count` men, its regiments shared out among the units by their share (largest
## remainder), with negative ids.
func _made_up(count: int) -> Array:
	var units: Dictionary = Data.value("army", "units", {})
	var mean := 0.0
	var total := 0.0
	for k in units:
		mean += float(units[k].get("share", 0.0)) * float(units[k].get("men", 150))
		total += float(units[k].get("share", 0.0))
	mean = mean / total if total > 0.0 else 150.0
	var n := maxi(1, roundi(count / mean))
	var counts := {}
	var rest: Array = []
	var given := 0
	for k in units:
		var want := n * float(units[k].get("share", 0.0)) / maxf(total, 0.001)
		counts[k] = int(floor(want))
		given += int(counts[k])
		rest.append([want - floor(want), k])
	rest.sort_custom(func(a, b): return a[0] > b[0])
	for i in n - given:
		counts[rest[i % rest.size()][1]] += 1
	var low_high: Array = Data.value("army", "spike.strength", [1.0, 1.0])
	var out: Array = []
	for k in units:
		for i in int(counts[k]):
			out.append({"id": -(out.size() + 1), "unit": String(k), "men": int(units[k].get("men", 150)), "strength": _rng.randf_range(float(low_high[0]), float(low_high[1]))})
	return out


## A regiment's spec for a company of a Freeciv type, of `count` men (army_field.gd sizes a battle's sides).
func spec_for(kind: String, count: int, id: int) -> Dictionary:
	return {"id": id, "unit": _unit_for(kind), "men": count, "strength": 1.0}


## The unit a Freeciv type raises (data/army.json units.<name>.freeciv), else fallbackUnit.
func _unit_for(kind: String) -> String:
	var units: Dictionary = Data.value("army", "units", {})
	for k in units:
		if (units[k].get("freeciv", []) as Array).has(kind):
			return String(k)
	return String(Data.value("army", "fallbackUnit", "men_at_arms"))


## One drawn soldier stands for this many men (data/army.json drawPerMan: 0.1, one figure for ten; Mac: fewer and
## further apart). Every regiment's figures come from here (_regiment); its men, the number the player reads, stay
## its full strength.
static func ratio() -> float:
	return clampf(Data.num("army", "drawPerMan", 0.1), 0.001, 1.0)


## How many figures a regiment of `men` draws: army.json figureFloor, so every regiment reads as a formed block, and
## one for every 1 / ratio() men above it (drawPerMan, Mac's), so a bigger regiment still looks bigger. The plate and
## the card show its real men.
static func figures(men: int) -> int:
	return int(Data.num("army", "figureFloor", 0.0)) + maxi(1, ceili(men * ratio() - 0.0001))


## crown (every regiment in the crown's colour and arms) or houses (each its house's): data/army.json colours, or
## --army-colours=houses|crown for a per-house shot.
static func colour_mode() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--army-colours="):
			return a.substr(15)
	return String(Data.value("army", "colours", "crown"))


## A unit's row, with its mesh's fields under it (meshes.<asset>) and its own over them.
func _unit(name: String) -> Dictionary:
	var row: Dictionary = (Data.value("army", "units", {}) as Dictionary).get(name, {})
	var asset := String(row.get("asset", KNIGHT))  # the baked soldier this kind wears
	var out: Dictionary = ((Data.value("army", "meshes", {}) as Dictionary).get(asset, {}) as Dictionary).duplicate(true)
	for k in row:
		if k == "tracks" and out.has("tracks"):
			(out["tracks"] as Dictionary).merge(row[k], true)
		else:
			out[k] = row[k]
	out["asset"] = asset
	return out


## One regiment: its node (at its middle, on the ground), its men (one VAT draw), its banner, its ground
## rectangle and its far block. Its men keep who they are (turn, size) through every shape.
func _regiment(spec: Dictionary, colour: Color, house: Dictionary = {}) -> Dictionary:
	var row := _unit(String(spec["unit"]))
	var kit := Visual.soldier(String(row["asset"]), row, battle.get("quiet", false))
	if kit.is_empty():
		return {}
	var count := figures(int(spec["men"]))  # drawn: one figure for every 1 / ratio() men
	var node := Node3D.new()
	add_child(node)
	var vat: VATMultiMeshInstance3D = VAT.new()
	vat.exported_mesh = kit["mesh"]
	# The plugin's own advice: the VAT material in the Material Override slot, one per regiment (its colour).
	var own := (kit["mat"] as ShaderMaterial).duplicate() as ShaderMaterial
	own.set_shader_parameter("team_color", Heraldry.field_colour(house, colour) if not house.is_empty() else colour)  # its banner's own field, value and hue
	Visual.wear_arms(own, house)
	var dress: Dictionary = row.get("cloth", {})  # a kind in plain cloth, its house's colour on a band (the levy)
	if not dress.is_empty():
		var band: Array = dress.get("band", [-1.0, 9.0])
		own.set_shader_parameter("team_band", Vector2(float(band[0]), float(band[1])))
		own.set_shader_parameter("undyed", Data.colour(dress.get("undyed"), Color(0.52, 0.45, 0.35)))
	vat.material_override = own
	vat.instance_count = count
	vat.rand_anim_offset = true
	vat.vat_animation_tracks = kit["tracks"]
	vat.lod_bias = Data.num("army", "lod.bias", 1.0)
	node.add_child(vat)
	var turn := Data.num("army", "jitter.turn", 0.18)
	var size := Data.num("army", "jitter.size", 0.06)
	var yaws := PackedFloat32Array()
	var sizes := PackedFloat32Array()
	for s in count:
		yaws.append(_rng.randf_range(-turn, turn))
		sizes.append(_rng.randf_range(1.0 - size, 1.0 + size))
	var spacing: Dictionary = row.get("spacing", {})
	var r := {"id": int(spec["id"]), "unit": String(spec["unit"]), "role": String(row.get("role", "melee")), "glyph": String(row.get("glyph", "sword")),
		"men": int(spec["men"]), "figures": count, "strength": float(spec.get("strength", 1.0)), "colour": colour, "node": node, "vat": vat, "kit": kit,
		"tracks": row.get("tracks", {}) if kit["asset"] == row["asset"] else kit["roles"],
		"sf": float(spacing.get("file", Data.num("army", "spacing.file", 0.1))), "sr": float(spacing.get("rank", Data.num("army", "spacing.rank", 0.12))),
		"speed": Data.num("army", "march.speed", 0.16) * float(row.get("speed", 1.0)),
		"yaws": yaws, "sizes": sizes, "local": PackedVector3Array(), "from": PackedVector3Array(), "to": PackedVector3Array(),
		"shape": "line", "state": "rest", "s": 0.0, "off": 0.0, "slot": Vector3.ZERO, "place": Vector2.ZERO, "t": 0.0,
		"fidget": _rng.randf_range(0.5, 3.0), "backs": [], "selected": false, "w": 1.0, "d": 1.0, "house": house}
	r["line"] = Formation.layout(r, "line", battle.get("frontage"), _rng)
	r["column"] = Formation.layout(r, "column", battle.get("frontage"), _rng)
	r["deck"] = Formation.layout(r, "deck", null, _rng)
	banners.banner(r)
	_ground_marks(r)
	return r


## Lays every man of a regiment at its current positions (its `local`), with his own turn and size.
func _dress(r: Dictionary) -> void:
	var vat: VATMultiMeshInstance3D = r["vat"]
	var tall: float = float(r["kit"].get("tall", Data.num("army", "man", 0.22))) / float(r["kit"]["height"])  # a body's own height (meshes.<dir>.tall: a horse and rider stand taller than a man)
	var at: PackedVector3Array = r["local"]
	var yaws: PackedFloat32Array = r["yaws"]
	var sizes: PackedFloat32Array = r["sizes"]
	for s in at.size():
		var b := Basis(Vector3.UP, yaws[s]).scaled(Vector3.ONE * tall * sizes[s])
		vat.multimesh.set_instance_transform(s, Transform3D(b, at[s]))


## Takes a regiment's shape at once (its men's places, its banner's pips, its rectangle and block fitted).
func _shape(r: Dictionary, shape: String) -> void:
	var l: Dictionary = r[shape]
	r["shape"] = shape
	r["local"] = (l["at"] as PackedVector3Array).duplicate()
	r["w"] = l["w"]
	r["d"] = l["d"]
	_dress(r)
	_fit(r)
	_bear(r)


## The regiment's standard bearer (Total War: the colours carried by a man in the front rank, not a pole among
## the ranks): its middle man of the front rank holds the banner at his side (banner.bearer: how far to his
## right, in men's heights), so it marches, wheels and stands where he does.
func _bear(r: Dictionary) -> void:
	if not r.has("banner"):
		return
	var at: PackedVector3Array = r["local"]
	if at.is_empty():
		return
	var front := -INF
	for p in at:
		front = maxf(front, p.z)
	var best := 0
	var near := INF
	for i in at.size():
		if at[i].z > front - 0.05 and absf(at[i].x) < near:
			near = absf(at[i].x)
			best = i
	r["bearer"] = best
	var man := Data.num("army", "man", 0.22)
	(r["banner"] as Node3D).position = at[best] + Vector3(man * Data.num("army", "banner.bearer", 0.25), 0, 0)


## Plays a regiment's men a role's clip. walk: the whole regiment on one step, each man a little off it
## (jitter.step). rest: each man his own pick from the rest pool (name: weight), at his own point in it.
func _clips(r: Dictionary, role: String) -> void:
	var vat: VATMultiMeshInstance3D = r["vat"]
	var step := Data.num("army", "jitter.step", 0.06)
	var phase := _rng.randf()
	for s in vat.multimesh.instance_count:
		vat.update_instance_track(s, _track(r, role))
		vat.update_instance_animation_offset(s, fposmod(phase + _rng.randf_range(-step, step), 1.0) if role == "walk" else _rng.randf())
		vat.update_instance_alpha(s, 1.0)
	r["backs"] = []


## A track index for a role on a regiment's mesh: the role's clip name, one of a list, or one of a pool by
## weight (data/army.json meshes.<dir>.tracks); the mesh's first track when it has no such clip.
func _track(r: Dictionary, role: String) -> int:
	var want: Variant = (r["tracks"] as Dictionary).get(role, (r["tracks"] as Dictionary).get("idle", "Idle"))
	var name := ""
	if want is Array and not (want as Array).is_empty():
		name = String(want[_rng.randi() % (want as Array).size()])
	elif want is Dictionary:
		var sum := 0.0
		for k in want:
			sum += float(want[k])
		var roll := _rng.randf() * sum
		for k in want:
			roll -= float(want[k])
			name = String(k)
			if roll <= 0.0:
				break
	else:
		name = String(want)
	return int((r["kit"]["index"] as Dictionary).get(name, 0))


# --- Banner, standard, ground rectangle, far block -------------------------------------------------------

## The host's standard over its commander's regiment (the middle of the front row; army_banners.gd), in its
## house's arms, its strength in men under it from afar.
func _standard_up() -> void:
	var c: Dictionary = _commander if not _commander.is_empty() else _regiments[0]
	_commander = c
	banners.raise_standard(c, battle.get("house", _crown_house()), _men())


## The ground rectangle under a regiment (a decal on the land alone, terrain.gd's GROUND_LAYER, so it never
## paints the men) and the block it shows as from afar.
func _ground_marks(r: Dictionary) -> void:
	var d := Decal.new()
	d.texture_albedo = _rect_texture()
	d.modulate = r["colour"]
	d.cull_mask = Terrain.GROUND_LAYER
	d.upper_fade = 0.0
	d.lower_fade = 0.0
	d.albedo_mix = 1.0
	d.emission_energy = 0.6
	d.texture_emission = d.texture_albedo
	(r["node"] as Node3D).add_child(d)
	r["ring"] = d
	var block := MeshInstance3D.new()
	block.mesh = BoxMesh.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = r["colour"]
	m.emission_enabled = true
	m.emission = (r["colour"] as Color) * 0.35
	m.roughness = 0.9
	block.material_override = m
	block.visible = false
	(r["node"] as Node3D).add_child(block)
	r["block"] = block
	_mark(r, false)


## Fits the rectangle and the block to a regiment's shape.
func _fit(r: Dictionary) -> void:
	var margin := Data.num("army", "select.margin", 0.15)
	var man := Data.num("army", "man", 0.22)
	var d: Decal = r["ring"]
	d.size = Vector3(float(r["w"]) + margin * 2.0, 1.2, float(r["d"]) + margin * 2.0)
	var block: MeshInstance3D = r["block"]
	(block.mesh as BoxMesh).size = Vector3(float(r["w"]), man, float(r["d"]))
	var tall := man * Data.num("army", "banner.height", 2.6)  # its men and its banner, to click (host_command.gd)
	if r.has("pick"):
		HostPick.fit(r["pick"], Vector3(float(r["w"]), tall, float(r["d"])))
	else:
		r["pick"] = HostPick.proxy(r["node"], int(r["id"]), Vector3(float(r["w"]), tall, float(r["d"])), self)
	block.position = Vector3(0.0, man * 0.5, 0.0)
	if banners.rides_with(r):
		banners.place()


static var _rect_tex: ImageTexture
## A rectangle's outline with a faint fill, white (the decal tints it): made once.
static func _rect_texture() -> ImageTexture:
	if _rect_tex:
		return _rect_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var e := mini(mini(x, y), mini(n - 1 - x, n - 1 - y))
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if e < 3 else (0.5 if e < 5 else 0.12)))
	_rect_tex = ImageTexture.create_from_image(img)
	return _rect_tex


## A regiment selected or let go: its rectangle shown (select.alpha) or at rest (select.idle), its banner lit.
func _mark(r: Dictionary, on: bool) -> void:
	r["selected"] = on
	var a := Data.num("army", "select.alpha", 0.9) if on else Data.num("army", "select.idle", 0.0)
	var d: Decal = r["ring"]
	var c: Color = r["colour"]
	d.modulate = Color(c.r, c.g, c.b, a)
	d.visible = a > 0.0 and not _far
	banners.lit(r, on)


# --- The two shapes ---------------------------------------------------------------------------------------

## Where the line stands: every cell of a grid round the seat is asked whether its ground suits men (_ground:
## dry land, no building, road or track, level enough) and how many trees stand on it; then each cell is tried
## as the line's middle, facing away from the seat or half a quarter either side, and scored on the line's
## ground (cells unsuitable, trees to fell) and its way from the seat (muster.missCost, treeCost, nearCost).
## The best is taken; the trees under it are felled (forest.clear, as a town or a battle clears its ground).
func _field_for(town: Vector3, extent: Vector2) -> bool:
	var pitch := Data.num("army", "muster.cell", 2.0)
	var clear := Data.num("army", "muster.clear", 4.5)
	var reach := Data.num("army", "muster.reach", 40.0)
	var keep := pitch * Data.num("army", "muster.keepOff", 0.75)
	var tree_cost := Data.num("army", "muster.treeCost", 0.15)
	var miss_cost := Data.num("army", "muster.missCost", 4.0)
	var near_cost := Data.num("army", "muster.nearCost", 0.25)
	var woods = main.terrain.get("forest")
	var span := int(ceil(reach / pitch))
	var ok := {}  # Vector2i cell -> trees on it, for the cells whose ground suits men
	for gx in range(-span, span + 1):
		for gz in range(-span, span + 1):
			var off := Vector2(gx, gz) * pitch
			if off.length() < clear or off.length() > reach:
				continue
			var p := town + Vector3(off.x, 0, off.y)
			if _ground(p, pitch * 0.9):
				ok[Vector2i(gx, gz)] = int(woods.trees_near(p, keep)) if woods and woods.has_method("trees_near") else 0
	if ok.is_empty():
		return false
	var nx := maxi(1, int(ceil(extent.x / pitch)) + 1)
	var nz := maxi(1, int(ceil(extent.y / pitch)) + 1)
	var best_score := INF
	var best_c := Vector2.ZERO
	var best_a := 0.0
	for c in ok:
		var mid := Vector2(c) * pitch
		var base := atan2(mid.x, mid.y)
		var near := Vector2(c).length() * near_cost
		for turn in [0.0, -PI / 4.0, PI / 4.0]:
			var a: float = base + turn
			var fwd := Vector2(sin(a), cos(a))
			var right := Vector2(cos(a), -sin(a))
			var score := near
			for i in nx:
				for j in nz:
					var p := mid + right * (float(i) - (nx - 1) * 0.5) * pitch + fwd * (float(j) - (nz - 1) * 0.5) * pitch
					var cell := Vector2i(roundi(p.x / pitch), roundi(p.y / pitch))
					score += float(ok[cell]) * tree_cost if ok.has(cell) else miss_cost
				if score >= best_score:
					break
			if score < best_score:
				best_score = score
				best_c = mid
				best_a = a
	_face = best_a
	_field = town + Vector3(best_c.x, 0, best_c.y)
	_field.y = main.terrain.height_at(_field.x, _field.z)
	_take_field(extent)
	return true


## The line's ground (at _field, facing _face) cleared of trees, and every regiment's slot on it.
func _take_field(extent: Vector2) -> void:
	var pitch := Data.num("army", "muster.cell", 2.0)
	var keep := pitch * Data.num("army", "muster.keepOff", 0.75)
	var woods = main.terrain.get("forest")
	var nx := maxi(1, int(ceil(extent.x / pitch)) + 1)
	var nz := maxi(1, int(ceil(extent.y / pitch)) + 1)
	var fwd3 := Vector3(sin(_face), 0, cos(_face))
	var right3 := Vector3(cos(_face), 0, -sin(_face))
	for i in nx:
		for j in nz:
			var p := _field + right3 * (float(i) - (nx - 1) * 0.5) * pitch + fwd3 * (float(j) - (nz - 1) * 0.5) * pitch
			if woods and woods.has_method("clear"):
				woods.clear(p, keep)
	for r in _regiments:
		var pl: Vector2 = r["place"]
		var p := _field + right3 * pl.x + fwd3 * pl.y
		r["slot"] = Vector3(p.x, main.terrain.height_at(p.x, p.z), p.z)
	if battle.is_empty():
		_clear_slots(right3, fwd3)


## A farm's yard or hedged field at q (countryside.occupied): what a muster keeps off.
func _farmed(q: Vector3, r: float) -> bool:
	var land = main.get("countryside")
	return land != null and land.has_method("occupied") and land.occupied(q, r)


## Whether a regiment's ground (its line's rectangle round `mid`, turned to the line, and muster.margin round it)
## is clear: dry land, no building, no farm or field, no road; and no other regiment's ground in `taken`.
func _clear_at(mid: Vector3, right3: Vector3, fwd3: Vector3, w: float, d: float, taken: Array) -> bool:
	var m := Data.num("army", "muster.margin", 0.15)
	var step := Data.num("army", "muster.probe", 0.35)
	var gap := Data.num("army", "gap", 0.35) * 0.5
	for t in taken:  # in the line's own frame: rectangles side by side, rows behind rows
		var o: Dictionary = t
		var off: Vector3 = mid - (o["at"] as Vector3)
		if absf(off.dot(right3)) < (w + float(o["w"])) * 0.5 + gap and absf(off.dot(fwd3)) < (d + float(o["d"])) * 0.5 + gap:
			return false
	var roads = main.get("roads")
	var nx := maxi(2, int(ceil((w + m * 2.0) / step)) + 1)
	var nz := maxi(2, int(ceil((d + m * 2.0) / step)) + 1)
	for i in nx:
		for j in nz:
			var q := mid + right3 * ((float(i) / (nx - 1) - 0.5) * (w + m * 2.0)) + fwd3 * ((float(j) / (nz - 1) - 0.5) * (d + m * 2.0))
			if not main.terrain.is_land(q.x, q.z) or TownNav.in_building(main.towns, q, 0.05) or _farmed(q, 0.0):
				return false
			if roads and roads.has_method("on_path") and roads.on_path(q, 0.05):
				return false
	return true


## Every regiment on clear ground (Total War's deployment never stands men in a house): a regiment whose place in
## the line falls on a building, a farm, a field or a road moves to the nearest clear ground round it, keeping
## its facing, rings of muster.cell outward up to muster.reach; one that finds none keeps its place.
func _clear_slots(right3: Vector3, fwd3: Vector3) -> void:
	var pitch := Data.num("army", "muster.cell", 2.0) * 0.5
	var reach := Data.num("army", "muster.search", 8.0)
	var taken: Array = []
	var moved := 0
	var stuck := 0
	for r in _regiments:
		var w := float(r["line"]["w"])
		var d := float(r["line"]["d"])
		var at: Vector3 = r["slot"]
		at.y = 0.0
		var found := _clear_at(at, right3, fwd3, w, d, taken)
		if not found:
			var ring := 1
			while not found and ring * pitch <= reach:
				var n := ring * 8
				for k in n:
					var a := TAU * float(k) / n
					var q := at + (right3 * cos(a) + fwd3 * sin(a)) * ring * pitch
					if _clear_at(q, right3, fwd3, w, d, taken):
						at = q
						found = true
						break
				ring += 1
			if found:
				at.y = main.terrain.height_at(at.x, at.z)
				moved += 1
			else:
				stuck += 1
		r["slot"] = Vector3(at.x, main.terrain.height_at(at.x, at.z), at.z)
		taken.append({"at": Vector3(at.x, 0, at.z), "w": w, "d": d})
	if moved + stuck > 0 and not battle.get("quiet", false):
		print("ARMY muster: %d regiments moved to clear ground, %d found none" % [moved, stuck])


## A regiment stands in its place in the line at once, at ease.
func _stand_in_line(r: Dictionary) -> void:
	_shape(r, "line")
	r["state"] = "rest"
	_set_at(r, r["slot"], _face)
	_clips(r, "rest")


## The road in: from the nearest town with a road to the seat (roads.route, the great roads and the King's
## road), cut where it passes nearest the muster, so the host marches in along it and turns off to its line.
## Its last stretch is kept, long enough for the whole column (lengthened straight back where the road is
## short). With no road, the host comes straight over open land along its line's flank.
func _road_in(town: Vector3) -> void:
	var need := Formation.column_length(_regiments) + Data.num("army", "march.lead", 5.0) + 1.0
	var roads = main.get("roads")
	var way := PackedVector3Array()
	if roads and roads.has_method("route") and not battle.has("field"):
		var others: Array = (main.awareness.rec("cities", []) as Array).duplicate()
		var seat_xy := Vector2(town.x, town.z)
		var pos := func(c) -> Vector3: return main.terrain.world_pos(float(c["x"]), float(c["y"]))
		others = others.filter(func(c): return Vector2((pos.call(c) as Vector3).x, (pos.call(c) as Vector3).z).distance_to(seat_xy) > 1.0)
		others.sort_custom(func(a, b): return Vector2((pos.call(a) as Vector3).x, (pos.call(a) as Vector3).z).distance_to(seat_xy) < Vector2((pos.call(b) as Vector3).x, (pos.call(b) as Vector3).z).distance_to(seat_xy))
		for c in others.slice(0, int(Data.num("army", "march.roadTries", 6))):
			way = roads.route(pos.call(c), town)
			if way.size() >= 2:
				break
	if way.size() >= 2:
		var k := 1
		for i in way.size():
			if Vector2(way[i].x - _field.x, way[i].z - _field.z).length() < Vector2(way[k].x - _field.x, way[k].z - _field.z).length():
				k = i
		way = way.slice(0, maxi(k, 1) + 1)
	if way.size() < 2:  # in along the line's right flank, clear of the seat behind it
		var side := Vector3(cos(_face), 0, -sin(_face))
		way = PackedVector3Array([_field + side * need, _field + side * 2.0])
	# Its last `need` units, lengthened straight back where it is shorter.
	var total := 0.0
	var i := way.size() - 1
	while i > 0 and total + way[i].distance_to(way[i - 1]) < need:
		total += way[i].distance_to(way[i - 1])
		i -= 1
	var keep := way.slice(i)
	if i > 0:
		var cut := keep[0].lerp(way[i - 1], (need - total) / maxf(keep[0].distance_to(way[i - 1]), 0.001))
		keep.insert(0, cut)
	elif total < need and keep.size() >= 2:
		keep.insert(0, keep[0] + (keep[0] - keep[1]).normalized() * (need - total))
	_path = keep
	_cum = PackedFloat32Array([0.0])
	for j in range(1, _path.size()):
		_cum.append(_cum[j - 1] + _path[j].distance_to(_path[j - 1]))
	var road_w := 0.5
	for j in range(1, _path.size()):
		_fell(_path[j - 1], _path[j], road_w)


## War's muster on its way out (03-army: one column on the open road past the walls, regiments nose to tail): out of
## the town by the main way (towns.gd ways_main) whose stretch past the town's edge is dry land for the whole column
## (terrain is_land), the one that best faces `to` among those, and on from there along the realm's road toward `to`
## (roads.route), or straight over the land with none. The host stands on it in column.order, halted, its tail
## muster.gateClear past where the way leaves the town (towns.gd edge_outline, where the wall's gate stands), so it
## marches on along the way it stands on. Group renders g3/g4: in line on a field with no road out; g5: through the
## lanes inside the walls; g6: on the waterside road to Eaglehaven, its blocks over the strait.
func _form_on_way(town: Vector3, to: Vector3, root: Node3D) -> void:
	var roads = main.get("roads")
	var aim := Vector2(to.x - town.x, to.z - town.z).normalized()
	var reach := Data.num("army", "muster.wayReach", 16.0)
	var need := Data.num("army", "muster.gateClear", 0.6) + Formation.column_length(_regiments)
	var edge: PackedVector2Array = root.get_meta("edge_outline", PackedVector2Array()) if root else PackedVector2Array()
	var half := 0.0
	for r in _regiments:
		half = maxf(half, float((r["column"] as Dictionary).get("w", 0.0)) * 0.5)
	half += Data.num("army", "muster.roadClear", 0.3)
	# Ground the whole column may stand on: dry land, no building, wall, fence or stall of any town
	# (TownNav.in_building) and no farm, field, hedge or cottage of the countryside (countryside occupied), across each
	# block's half width and muster.roadClear more either side: the ground a muster's line asks for (_clear_at).
	var blocked := func(at: float) -> bool:
		var q := _at(at)
		var h := _heading(at)
		var side := Vector3(cos(h), 0, -sin(h))
		for k in 5:
			var t := q + side * half * (k / 2.0 - 1.0)
			if not main.terrain.is_land(t.x, t.z) or (main.get("towns") and TownNav.in_building(main.get("towns"), t, 0.05)) or _farmed(t, 0.05):
				return true
		return false
	# Every main way out of the town (towns.gd ways_main: where the realm's roads leave it), carried on straight out
	# over the land muster.wayReach: on each, from where it leaves the town's edge (edge_outline, the wall's gate), the
	# first stretch that holds the whole column clear. The column stands on the way whose clear stretch lies nearest
	# the gate (facing `to` the better on a tie); with none clear for its length, on the longest clear stretch of
	# any. Group renders g7-g16 muster.jpg: one way out searched, its farms and the strait leaving no stretch clear, the
	# blocks among the cottages and hedges outside Kingsmere's gate.
	var ways: Array = []
	for w in (root.get_meta("ways_main", []) if root else []):
		var pw := PackedVector2Array(w)
		if pw.size() >= 2:
			ways.append(pw)
	if ways.is_empty():
		ways.append(PackedVector2Array([Vector2.ZERO, aim * 0.1]))
	var pick := {}
	for pw: PackedVector2Array in ways:
		var dir := (pw[pw.size() - 1] - pw[pw.size() - 2]).normalized()
		var way := PackedVector3Array([town])
		for q in pw:
			way.append(town + Vector3(q.x, 0, q.y))
		way.append(way[way.size() - 1] + Vector3(dir.x, 0, dir.y) * reach)
		_path = way
		_cum = PackedFloat32Array([0.0])
		for j in range(1, _path.size()):
			_cum.append(_cum[j - 1] + _path[j].distance_to(_path[j - 1]))
		var out := 0.0
		if edge.size() >= 3:
			while out < _cum[_cum.size() - 1] and Geometry2D.is_point_in_polygon(Vector2(_at(out).x - town.x, _at(out).z - town.z), edge):
				out += 0.1
		var run_from := out
		var best_from := out
		var best_len := 0.0
		var at_s := out
		while at_s < _cum[_cum.size() - 1]:
			if blocked.call(at_s):
				run_from = at_s + 0.1
			elif at_s - run_from > best_len:
				best_len = at_s - run_from
				best_from = run_from
				if best_len >= need:
					break
			at_s += 0.1
		var fits := best_len >= need
		var score := (1000.0 if fits else best_len) - (best_from if fits else 0.0) + pw[pw.size() - 1].normalized().dot(aim) * 0.5
		if pick.is_empty() or score > float(pick["score"]):
			pick = {"score": score, "way": way, "from": best_from}
	# On toward `to` from the way's end: the realm's road, never back toward the town, else straight on.
	var chosen: PackedVector3Array = pick["way"]
	var from := chosen[chosen.size() - 1]
	var road: PackedVector3Array = roads.route(from, to, Data.num("army", "march.roadReach", 12.0)) if roads and roads.has_method("route") else PackedVector3Array()
	var gone := Vector2(from.x - town.x, from.z - town.z).length()
	_path = chosen
	for p in (road.slice(1) if road.size() >= 3 else PackedVector3Array([to])):
		if Vector2(p.x - town.x, p.z - town.z).length() > gone or p == to:
			_path.append(p)
	_cum = PackedFloat32Array([0.0])
	for j in range(1, _path.size()):
		_cum.append(_cum[j - 1] + _path[j].distance_to(_path[j - 1]))
	var out: float = pick["from"]
	var order := Formation.column_order(_regiments)
	var head := minf(_cum[_cum.size() - 1], out + Data.num("army", "muster.gateClear", 0.6) + Formation.column_length(_regiments))
	_field = _at(head)
	_face = _heading(head)
	for r in order:
		r["s"] = head - float(r["off"])
		_shape(r, "column")
		_set_at(r, _at(r["s"]), _heading(r["s"]))
		r["state"] = "halt"
		_clips(r, "rest")


## The host in column on the road, its head march.lead short of the turn-off, in column.order (by role), each
## regiment marching on its own step.
func _column_up() -> void:
	var head := _cum[_cum.size() - 1] - Data.num("army", "march.lead", 5.0)
	for r in Formation.column_order(_regiments):
		r["s"] = head - float(r["off"])
		_shape(r, "column")
		var p := _at(r["s"])
		_set_at(r, p, _heading(r["s"]))
		_clips(r, "walk")
		_march(r)


## Along the road in at the host's pace (the Mover follows the road's own way, laid by roads.gd); at the turn-off
## out to its place in the line, or, on a column order, halted at its own place in the column.
func _march(r: Dictionary) -> void:
	var end := (_halt_head() - float(r["off"])) if _goal == "column" else _cum[_cum.size() - 1]
	var from := float(r["s"])
	var way := PackedVector3Array()
	for i in _path.size():
		if _cum[i] > from + 0.01 and _cum[i] < end - 0.01:
			way.append(_path[i])
	way.append(_at(end))
	r["state"] = "road"
	var mo: Node = Mover.of(r["node"])
	mo.speed = float(r["speed"])
	mo.follow(way, func():
		r["s"] = end
		if _goal == "column":
			r["state"] = "halt"
			_clips(r, "rest")
		else:
			_deploy(r))


## Where the column's head halts on a column order: the road's end, or back along the road until no regiment's place
## in the column falls on a building (its ground's open_at), so the column halts whole and spaced, not each
## regiment shoved off the building to its nearest open cell (group render g5, host5.jpg: the blocks piled at a cottage).
func _halt_head() -> float:
	var head := _cum[_cum.size() - 1]
	if ground == null or not ground.has_method("open_at"):
		return head
	var step := 0.1
	var least := Formation.column_length(_regiments)
	while head - step >= least and not _regiments.all(func(r): return ground.open_at(_at(head - float(r["off"])))):
		head -= step
	return head


## A regiment's keep on its ground (mover.gd keep, each step): its block, not only its middle, clear of what the
## ground shuts (a cottage by the road): where one flank's edge falls on a building and the other is open, the block
## steps aside toward the open side, up to half its width, and slides past (Total War's regiments edge round a house
## on the march). The mover's own walk goes on along the road (fe1b86f1), so it comes back once past. Group render
## g6, host5.jpg: three blocks pressed against one cottage's walls.
func _block_keep(r: Dictionary) -> Callable:
	return func(p: Vector3) -> Vector3:
		if ground == null or not ground.has_method("open_at"):
			return p
		var yaw := (r["node"] as Node3D).rotation.y
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var half := float(r.get("w", 0.0)) * 0.5
		var step := 0.05
		for k in int(ceil(half / step)):
			var lo: bool = ground.open_at(p - right * half)
			var hi: bool = ground.open_at(p + right * half)
			if lo == hi:
				break
			p += right * (step if lo == false else -step)
		return p


## Off the road to its place in the line by the ground's route, where it turns into line.
func _deploy(r: Dictionary) -> void:
	r["state"] = "deploy"
	_clips(r, "walk")
	var mo: Node = Mover.of(r["node"])
	mo.speed = float(r["speed"])
	mo.go(r["slot"], func(): _reform(r, "line"))


## How far along the road in `p` (world) stands: its nearest point on it.
func _along(p: Vector3) -> float:
	var best := 0.0
	var near := INF
	for i in range(1, _path.size()):
		var q := Geometry3D.get_closest_point_to_segment(p, _path[i - 1], _path[i])
		var d := q.distance_to(p)
		if d < near:
			near = d
			best = _cum[i - 1] + q.distance_to(_path[i - 1])
	return best


## A point `s` units along the road in (clamped to its ends), on the ground.
func _at(s: float) -> Vector3:
	if _path.is_empty():
		return _field
	s = clampf(s, 0.0, _cum[_cum.size() - 1])
	var i := _cum.bsearch(s)
	if i <= 0:
		return _ground_at(_path[0])
	var a := _path[i - 1]
	var b := _path[mini(i, _path.size() - 1)]
	var t := (s - _cum[i - 1]) / maxf(_cum[mini(i, _cum.size() - 1)] - _cum[i - 1], 0.0001)
	return _ground_at(a.lerp(b, clampf(t, 0.0, 1.0)))


## The road's heading at `s` (yaw), over a regiment's length so a bend turns it smoothly.
func _heading(s: float) -> float:
	var d := _at(s + 0.6) - _at(s - 0.6)
	return atan2(d.x, d.z) if Vector2(d.x, d.z).length() > 0.001 else _face


func _ground_at(p: Vector3) -> Vector3:
	return Vector3(p.x, main.terrain.height_at(p.x, p.z), p.z)


func _set_at(r: Dictionary, p: Vector3, yaw: float) -> void:
	r["yaw"] = yaw
	(r["node"] as Node3D).global_transform = Transform3D(Basis(Vector3.UP, yaw), _ground_at(p))


## A regiment turns from one shape to the other where it stands: each man walks from his place in the one to
## his place in the other over line.reform seconds, the regiment turning to its facing as it does.
func _reform(r: Dictionary, shape: String) -> void:
	r["from"] = (r["local"] as PackedVector3Array).duplicate()
	r["to"] = r[shape]["at"]
	r["into"] = shape
	r["t"] = 0.0
	r["turn_from"] = r["yaw"]
	r["state"] = "reform"
	_clips(r, "walk")


# --- Each frame -------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _regiments.is_empty() or banners.standard == null:
		return
	for r in _regiments:
		r["yaw"] = (r["node"] as Node3D).rotation.y  # its Mover turns it as it goes
		match String(r["state"]):
			"reform":
				r["t"] = minf(1.0, float(r["t"]) + delta / maxf(Data.num("army", "line.reform", 5.0), 0.1))
				var e := smoothstep(0.0, 1.0, float(r["t"]))
				var from: PackedVector3Array = r["from"]
				var to: PackedVector3Array = r["to"]
				var local: PackedVector3Array = r["local"]
				for s in local.size():
					local[s] = from[s].lerp(to[s], e)
				r["local"] = local
				_dress(r)
				var face := _face if r["into"] == "line" else float(r["turn_from"])
				_set_at(r, (r["node"] as Node3D).global_position, lerp_angle(float(r["turn_from"]), face, e))
				if float(r["t"]) >= 1.0:
					_shape(r, String(r["into"]))
					r["state"] = "rest"
					_clips(r, "rest")
					if _out and r["into"] == "column":  # marching out: in column, on from where it stands
						_march(r)
			"out":
				r["leave"] = float(r["leave"]) - delta
				if float(r["leave"]) <= 0.0:
					_reform(r, "column")
			"halt", "rest":
				_at_ease(r, delta)
	_far_view()
	if _then_free and _regiments.all(func(r): return r["state"] == "halt"):
		queue_free()
		return
	if _out and _regiments.all(func(r): return r["state"] == "halt"):
		_gone_in += delta
		if _gone_in > Data.num("army", "march.linger", 40.0):
			queue_free()
	if _want_select != "" and _regiments.all(func(r): return r["state"] in ["rest", "halt"]):
		if _want_select == "all":
			select_all()
		else:
			var i := int(_want_select)
			if i >= 0 and i < _regiments.size():
				select(int(_regiments[i]["id"]))
		_want_select = ""
	if _hold and main.rig:
		var mid := _middle()
		_focus = _focus.lerp(mid, minf(1.0, delta * 1.5))
		var want := _yaw_line if _regiments.any(func(r): return r["state"] in ["deploy", "reform", "rest"]) else _yaw_march
		_yaw = lerp_angle(_yaw, want, minf(1.0, delta * 0.6))
		main.rig.snap(_focus, _dist, _yaw)
		main.rig.tilt = _tilt  # lower than the map view's own pitch: a low oblique, as the art targets
		main.rig.goal_tilt = _tilt
	_report -= delta
	if _report <= 0.0 and not battle.get("quiet", false):
		_report = 2.0
		var states := {}
		for r in _regiments:
			states[r["state"]] = int(states.get(r["state"], 0)) + 1
		print("ARMY men=%d regiments=%d %s far=%s fps=%d process=%.1fms draws=%d prims=%dk cam=%.1f" % [_men(), _regiments.size(), str(states), str(_far),
			Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
			main.rig.distance if main.rig else 0.0])


## Men at ease shift now and then: every rest.every seconds a few of a regiment's men (rest.men) take another
## clip from the rest pool and turn a little (rest.turn), so no two moments of a standing host look alike.
## A clip that plays once returns its man to the regiment's idle when it ends.
func _at_ease(r: Dictionary, delta: float) -> void:
	var vat: VATMultiMeshInstance3D = r["vat"]
	var backs: Array = r["backs"]
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(backs.size() - 1, -1, -1):
		if float(backs[i][1]) <= now:
			var s := int(backs[i][0])
			vat.update_instance_track(s, _track(r, "idle"))
			vat.update_instance_animation_offset(s, _rng.randf())
			backs.remove_at(i)
	r["fidget"] = float(r["fidget"]) - delta
	if float(r["fidget"]) > 0.0:
		return
	var every: Array = Data.value("army", "rest.every", [1.5, 4.0])
	var some: Array = Data.value("army", "rest.men", [3, 9])
	var turn := Data.num("army", "rest.turn", 0.35)
	var most := Data.num("army", "jitter.turn", 0.18) + turn
	r["fidget"] = _rng.randf_range(float(every[0]), float(every[1]))
	var yaws: PackedFloat32Array = r["yaws"]
	var tracks: Array = r["kit"]["tracks"]
	for n in _rng.randi_range(int(some[0]), int(some[1])):
		var s := _rng.randi() % int(r["figures"])
		var t := _track(r, "rest")
		vat.update_instance_track(s, t)
		vat.update_instance_animation_offset(s, _rng.randf())
		yaws[s] = clampf(yaws[s] + _rng.randf_range(-turn, turn), -most, most)
		var clip: VATAnimationTrack = tracks[t]
		if not clip.isLooping:
			backs.append([s, now + float(clip.endFrame - clip.startFrame) / maxf(float(clip.framerate), 1.0)])
	r["yaws"] = yaws
	_dress(r)


## From afar (far.at; back to men under far.back) the host shows as one coloured block per regiment, nose to
## tail on the march or side by side in line, with its standard and its strength; banners and the standard
## keep their size on screen beyond banner.fixedFrom.
func _far_view() -> void:
	_shade_t -= get_process_delta_time()
	if _shade_t <= 0.0:
		_shade_t = 0.5
		Visual.cast_near(_regiments, get_viewport().get_camera_3d())
	var d: float = main.rig.distance if main.rig else _dist
	var far := d > Data.num("army", "far.at", 34.0) if not _far else d > Data.num("army", "far.back", 30.0)
	if far != _far:
		_far = far
		for r in _regiments:
			(r["vat"] as Node3D).visible = not far
			(r["block"] as Node3D).visible = far
			_mark(r, r["selected"])
	banners.view(_regiments, d, _far)


## The host's middle on the ground: where its regiments stand, on average.
func _middle() -> Vector3:
	var sum := Vector3.ZERO
	for r in _regiments:
		sum += (r["node"] as Node3D).global_position
	return sum / _regiments.size()


func _men() -> int:
	var n := 0
	for r in _regiments:
		n += int(r["men"])
	return n


# --- The realm around it ----------------------------------------------------------------------------------

## The host's seat: the town its muster names (battle seat: a city id), else the crown's (/world seatId), or
## Kingsmere by name.
func _seat() -> Dictionary:
	var cities: Array = main.awareness.rec("cities", [])
	for c in cities if battle.has("seat") else []:
		if int(c.get("id", -2)) == int(battle["seat"]):
			return c
	var want := int(main.awareness.rec("seatId", -1))
	for c in cities:
		if int(c.get("id", -2)) == want:
			return c
	for c in cities:
		if String(c.get("name", "")) == "Kingsmere":
			return c
	return {}


## The crown's house as the view knows it ({} when not yet known).
func _crown_house() -> Dictionary:
	var houses: Variant = main.get("_houses")
	for h in (houses as Dictionary).values() if houses is Dictionary else []:
		if h is Dictionary and h.get("crown", false):
			return h
	return {}


## The colours the regiments wear: the crown's first (colours "crown" takes only it), then the realm's other
## houses as heraldry draws them; the stock six when there are none yet.
func _colours() -> Array:
	var out: Array = []
	_worn = []
	var crown := _crown_house()
	if not crown.is_empty() and crown.has("color"):
		out.append(Heraldry.colour(crown))
		_worn.append(crown)
	var houses: Variant = main.get("_houses")
	for h in (houses as Dictionary).values() if houses is Dictionary else []:
		if h is Dictionary and not h.get("wild", false) and h.has("color"):
			var c: Color = Heraldry.colour(h)
			if not out.has(c):
				out.append(c)
				_worn.append(h)
	if out.size() < 2:
		_worn = []
		return HOUSES
	return out


var _worn: Array = []  # the houses whose colours _colours() gave, in its order ({} for the stock six)


## The lens's heading onto `look`: from `start`, the first of 24 turns either way from which, at the shot's
## distance, no tree crown and no roof stands between the lens and the host (forest.blocking,
## camera_rig.blocked_from); with none clear, the least blocked, and the trees on that line felled, so the
## camera never has to climb over a canopy to see.
func _lens_yaw(look: Vector3, start: float) -> float:
	var rig = main.rig
	var woods = main.terrain.get("forest")
	if rig == null or not rig.has_method("eye_at"):
		return start
	look += Vector3.UP * 0.1
	var best := start
	var least := 1 << 30
	for k in 24:
		var y := start + (TAU / 24.0) * ((k + 1) / 2) * (1 if k % 2 == 0 else -1)
		var eye: Vector3 = rig.eye_at(look, y, _tilt, maxf(_dist, float(rig.min_distance)))
		var n := 0
		if woods and woods.has_method("blocking"):
			n += int(woods.blocking(eye, look))
		if rig.has_method("blocked_from"):
			n += int(rig.blocked_from(eye, look)) * 10
		if n < least:
			least = n
			best = y
		if n == 0:
			break
	if least > 0:
		_fell(look, rig.eye_at(look, best, _tilt, maxf(_dist, float(rig.min_distance))), 1.0)
	return best


## Fells the trees along a line on the ground (a sight line, the road in), `width` either side.
func _fell(a: Vector3, b: Vector3, width: float) -> void:
	var woods = main.terrain.get("forest")
	if not woods or not woods.has_method("clear"):
		return
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var steps := int(ceil(flat.length() / maxf(width, 0.3))) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		woods.clear(Vector3(p.x, 0, p.z), width)


## A cell's ground: dry land all over, clear of buildings, roads and tracks, and level enough
## (trees are counted by the muster, and felled where the host stands).
func _ground(p: Vector3, size: float) -> bool:
	var h: float = main.terrain.height_at(p.x, p.z)
	var slope := Data.num("army", "muster.slope", 0.2)
	var keep := size * Data.num("army", "muster.keepOff", 0.75)
	var roads = main.get("roads")
	if roads and roads.has_method("on_path") and roads.on_path(p, keep):
		return false
	# Every point of a 5 by 5 grid over its square, not only its middle and corners: a house
	# (0.7 units across) stood between the corners of a regiment 2.5 wide, and the men stood in it.
	for gx in 5:
		for gz in 5:
			var q := Vector3(p.x + (gx / 4.0 - 0.5) * size, 0, p.z + (gz / 4.0 - 0.5) * size)
			if not main.terrain.is_land(q.x, q.z) or TownNav.in_building(main.towns, q, 0.1) or _farmed(q, 0.05):
				return false
			if absf(main.terrain.height_at(q.x, q.z) - h) > slope:
				return false
	return true


# --- The baked soldiers -----------------------------------------------------------------------------------

