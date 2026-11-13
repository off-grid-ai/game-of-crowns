extends RefCounted
## A house's banners on its towns (split from towns.gd at its seam, integration audit #9). Every decision is seen
## (GAME_DESIGN pillar 3): each banner stands as high as its house's favour toward the crown, full height when loyal,
## half-mast when cooling, near the ground when it may rise, the cloth sliding when it changes; a sworn house's
## banners carry a gold fringe. Read from the view's one store (awareness.gd), over the towns builder's towns (t).

const Awareness := preload("res://scripts/awareness.gd")  # the view's one store: the realm's records (rec)

var t: Node  # the towns builder (towns.gd): its towns
var _banner_at := {}  # house id -> 0..1 of the pole
var _sworn := {}  # house id -> true while sworn to the crown (its banners' gold fringe)


func _init(towns: Node) -> void:
	t = towns


func stand(root: Node3D, pos: Vector3, color: Color, house: Dictionary, height := 0.65) -> Node3D:
	var b: Node3D = preload("res://scripts/heraldry.gd").standard(house, color, height)
	b.position = pos
	root.add_child(b)
	# The house's banners show its favour: kept for raising and lowering.
	var flag := b.get_node_or_null("Banner")
	if flag:
		var all: Array = root.get_meta("banners", [])
		all.append(flag)
		root.set_meta("banners", all)
		flag.set_meta("top", flag.position.y)
		hoist(flag, _banner_at.get(int(root.get_meta("owner", -1)), 1.0), false)
		fringe(flag, _sworn.get(int(root.get_meta("owner", -1)), false))
	return b


## A seat's standard as the realm map shows it (docs/art/target/02-realm.jpg: a castle and a tall banner over every
## house seat): the house's standard over its castle at towns.json map_standard.height, seen only from
## map_standard.from away (map zoom), so the town and street views keep the castle's own. Raised and lowered with
## the house's favour like every banner of its towns.
func map_standard(root: Node3D, pos: Vector3, color: Color, house: Dictionary) -> void:
	var ms: Dictionary = preload("res://scripts/data.gd").value("towns", "map_standard", {})
	if float(ms.get("height", 0.0)) <= 0.0:
		return
	var b := stand(root, pos, color, house, float(ms["height"]))
	var todo: Array = [b]
	while not todo.is_empty():
		var n: Node = todo.pop_back()
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).visibility_range_begin = float(ms.get("from", 40.0))
			(n as GeometryInstance3D).visibility_range_begin_margin = 2.0
		todo.append_array(n.get_children())


## Every decision is seen (GAME_DESIGN pillar 3): a house's banners stand as
## high as its favour toward the crown. Full height when loyal, half-mast when
## cooling, near the ground when it may rise; the cloth slides when it changes.


static func height_for(favour) -> float:
	if favour == null:
		return 1.0  # the crown's own towns, and houses with no favour
	var f := float(favour)
	return 1.0 if f >= 60.0 else (0.8 if f >= 35.0 else (0.5 if f >= 25.0 else 0.18))


func hoist(flag: Node3D, frac: float, slide := true) -> void:
	var top: float = flag.get_meta("top", flag.position.y)
	var y := lerpf(0.04, top, frac)
	if is_equal_approx(float(flag.get_meta("at", -1.0)), frac):
		return
	flag.set_meta("at", frac)
	if slide and flag.is_inside_tree():
		flag.create_tween().tween_property(flag, "position:y", y, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		flag.position.y = y


func raise() -> void:
	var st: Node = Awareness.store()
	var by_owner := {}
	var sworn := {}
	for p in st.rec("players", []):
		by_owner[int(p.get("id", -1))] = height_for(p.get("favour"))
		sworn[int(p.get("id", -1))] = p.get("sworn") != null
	_banner_at = by_owner
	_sworn = sworn
	for id in t.towns:
		var root: Node3D = t.towns[id]["node"]
		if not is_instance_valid(root):
			continue
		var frac: float = by_owner.get(int(root.get_meta("owner", -1)), 1.0)
		var oath: bool = sworn.get(int(root.get_meta("owner", -1)), false)
		for flag in root.get_meta("banners", []):
			if is_instance_valid(flag):
				hoist(flag, frac)
				fringe(flag, oath)


## A sworn house's banners carry a gold fringe (banner_cloth.gdshader).
func fringe(flag: Node, on: bool) -> void:
	for g in ([flag] if flag is GeometryInstance3D else flag.find_children("*", "GeometryInstance3D", true, false)):
		(g as GeometryInstance3D).set_instance_shader_parameter("fringe", 1.0 if on else 0.0)
