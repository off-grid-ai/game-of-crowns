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
	b.set_meta("height", height)  # rehouse sets the new holder's standard up the same
	root.add_child(b)
	if root.name != "MapSeat":  # a seat's great standard is what the far view reads the realm by: it stays
		for g in b.find_children("*", "GeometryInstance3D", true, false):
			t.detail(g)  # a town's or castle's standard, cloth and pole, is detail: gone at the far view (towns.gd detail)
	# The house's banners show its favour: kept for raising and lowering.
	var flag := b.get_node_or_null("Banner")
	if flag:
		var all: Array = root.get_meta("banners", [])
		all.append(flag)
		root.set_meta("banners", all)
		flag.set_meta("top", flag.position.y)
		hoist(flag, _banner_at.get(int(root.get_meta("owner", -1)), 1.0), false)
		fringe(flag, _sworn.get(int(root.get_meta("owner", -1)), false))
		if root.has_meta("taken_at"):  # a castle dressed after the town was taken: its banners are raised too
			run_up(root, flag)
	return b


## The town changed hands: every standard it flies is struck and the new holder's put up in its place, at its
## height, run up the pole (taken). The town itself stands as it was: nothing else is rebuilt.
func rehouse(root: Node3D, house: Dictionary, color: Color, owner: int) -> void:
	var old: Array = root.get_meta("banners", [])
	root.set_meta("banners", [])
	root.set_meta("owner", owner)
	for flag in old:
		if not is_instance_valid(flag):
			continue
		var b := (flag as Node).get_parent() as Node3D
		var holder := b.get_parent() as Node3D if b else null
		if holder == null:
			continue
		if b.has_meta("arms"):  # a bannerman's own arms: not the holder's to strike (the town's merge adds or drops them)
			var kept: Array = root.get_meta("banners", [])
			kept.append(flag)
			root.set_meta("banners", kept)
			continue
		var at := b.position
		var h := float(b.get_meta("height", 0.65))
		b.queue_free()
		var fresh := stand(holder, at, color, house, h)
		if holder != root:  # a map seat's standard: kept on the town's list too
			var f := fresh.get_node_or_null("Banner")
			if f:
				var all: Array = root.get_meta("banners", [])
				all.append(f)
				root.set_meta("banners", all)
				holder.set_meta("banners", (holder.get_meta("banners", []) as Array).filter(func(x): return is_instance_valid(x) and x != flag))
	taken(root)


## A seat as the realm map shows it (map_seat.gd: the castle set's keep under the house's standard, hidden up close,
## grown with the camera's distance at map zoom; docs/art/target/02-realm.jpg), stood at `pos` over the seat's castle.
## Its standard joins the town's banners, so it rises and falls with the house's favour and carries the sworn fringe.
## `manor`: a vassal's manor (towns.json map_seat.manor over the seat's own knobs), its manor house in place of the keep.
func map_seat(root: Node3D, pos: Vector3, color: Color, house: Dictionary, manor := "") -> void:
	var ms: Dictionary = (preload("res://scripts/data.gd").value("towns", "map_seat", {}) as Dictionary).duplicate()
	if manor != "":
		ms.merge(ms.get("manor", {}), true)
	if float(ms.get("keep", 0.0)) <= 0.0:
		return
	var seat: Node3D = preload("res://scripts/map_seat.gd").new()
	seat.name = "MapSeat"
	seat.position = pos
	root.add_child(seat)
	var top: float = seat.build(float(ms["keep"]), ms, manor)
	stand(seat, Vector3(0, top, 0), color, house, float(ms.get("standard", 2.6)))
	var all: Array = root.get_meta("banners", [])
	all.append_array(seat.get_meta("banners", []))
	root.set_meta("banners", all)


## Every decision is seen (GAME_DESIGN pillar 3): a house's banners stand as
## high as its favour toward the crown. Full height when loyal, half-mast when
## cooling, near the ground when it may rise; the cloth slides when it changes.


static func height_for(favour) -> float:
	if favour == null:
		return 1.0  # the crown's own towns, and houses with no favour
	var f := float(favour)
	return 1.0 if f >= 60.0 else (0.8 if f >= 35.0 else (0.5 if f >= 25.0 else 0.18))


## A town just taken (towns.gd: rebuilt under a new owner): every one of its banners, the keep's and towers' with
## them, starts at the foot of its pole and is run up to its house's height (Total War and Stronghold: the taker's
## colours raised over the keep), the first after castle.json banners.taken.delay, the rest a beat apart. Banners
## stood later than taken.window seconds after the taking stand as any other.
func taken(root: Node3D) -> void:
	root.set_meta("taken_at", Time.get_ticks_msec())
	for flag in root.get_meta("banners", []):
		if is_instance_valid(flag):
			run_up(root, flag)


func run_up(root: Node3D, flag: Node3D) -> void:
	var k: Dictionary = (preload("res://scripts/data.gd").value("castle", "banners", {}) as Dictionary).get("taken", {})
	var since := (Time.get_ticks_msec() - int(root.get_meta("taken_at", 0))) / 1000.0
	if since > float(k.get("window", 30.0)) or not flag.is_inside_tree():
		return
	var top: float = flag.get_meta("top", flag.position.y)
	var frac := float(flag.get_meta("at", 1.0))
	var n := int(root.get_meta("taken_n", 0))
	root.set_meta("taken_n", n + 1)
	flag.position.y = 0.04
	flag.create_tween().tween_property(flag, "position:y", lerpf(0.04, top, frac), float(k.get("run_s", 6.0))) \
			.set_delay(maxf(0.0, float(k.get("delay", 1.5)) - since) + n * float(k.get("beat", 0.4))).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


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
