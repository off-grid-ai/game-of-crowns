extends RefCounted
## Arms in the hand: the realistic weapons (Sketchfab scans, CC-BY) held on a
## Mixamo character's bones with BoneAttachment3D, so they follow every move.
## Each model is measured as it loads and scaled to its real length, and turned
## so its grip sits in the fist: blade out past the thumb, edge along the
## knuckles. Anyone built on Godot's humanoid skeleton can be armed:
##   Weapons.arm(person, "axe")            # one-handed, right hand
##   Weapons.arm(person, "sword", true)    # sword and shield
##   Weapons.disarm(person)
## Kinds: sword, greatsword, axe, spear, dagger, bow (left hand), plus shield
## and quiver (worn). Sizes are metres, in the character's own space.

const DIR := "res://assets/props/weapons/"

# file: the model's folder. length: real length (m). tip: the model's own axis
# from butt to point. edge: the axis the edge or guard lies along. grip: where
# the fist closes, as a fraction of the length from the butt. keep: mesh names
# to show when the file holds more than the one item. core: mesh whose middle
# is the shaft's line (when the head sits off to one side).
const KINDS := {
	"sword": {"file": "sword", "length": 0.98, "tip": Vector3(0, 0, 1), "edge": Vector3(1, 0, 0), "grip": 0.09},
	"greatsword": {"file": "greatsword", "length": 1.6, "tip": Vector3(1, 0, 0), "edge": Vector3(0, 0, 1), "grip": 0.13},
	"axe": {"file": "axe", "length": 0.8, "tip": Vector3(0.971, 0.238, 0), "edge": Vector3(0.238, -0.971, 0), "grip": 0.14, "core": "Wood"},
	"spear": {"file": "spear", "length": 2.2, "tip": Vector3(0, 0.636, 0.772), "edge": Vector3(1, 0, 0), "grip": 0.42, "core": "Cylinder2"},
	"dagger": {"file": "dagger", "length": 0.34, "tip": Vector3(0.69, 0.07, -0.72), "edge": Vector3(0.72, 0, 0.69), "grip": 0.2, "keep": ["blade_Low", "handle_Low"]},
	"bow": {"file": "bows", "length": 1.8, "tip": Vector3(0, 1, 0), "edge": Vector3(1, 0, 0), "grip": 0.5, "keep": ["Object_41"]},
	"shield": {"file": "shield", "length": 0.78, "tip": Vector3(0, 1, 0), "edge": Vector3(0, 0, 1), "grip": 0.5},
	"quiver": {"file": "quiver", "length": 0.66, "tip": Vector3(0.270263, 0.946188, -0.178006), "edge": Vector3(0, 0, 1), "grip": 0.5, "keep": ["Object_4"]},
}
# What fills each hand for a kind, and whether a shield can go with it.
const TWO_HANDED := ["greatsword", "spear", "bow"]

## Tools in the hand, held the same way as arms (the one hand-held module,
## animation-pipeline.md section 4). path: the model; the rest as KINDS. Up
## is +Y in these glTFs: a handle's butt below its head, a pail's handle at its top.
const TOOLS := {
	"bowl": {"path": "res://assets/props/tools/wooden_bowl_01/wooden_bowl_01_1k.gltf", "length": 0.14, "tip": Vector3(1, 0, 0), "edge": Vector3(0, 1, 0), "grip": 0.5},  # a mazer, the commoner's cup
	"hammer": {"path": "res://assets/props/tools/wooden_hammer_01/wooden_hammer_01_1k.gltf", "length": 0.3, "tip": Vector3(0, 1, 0), "edge": Vector3(1, 0, 0), "grip": 0.15},
	"broom": {"path": "res://assets/props/tools/wooden_broom/wooden_broom_1k.gltf", "length": 1.4, "tip": Vector3(0, -1, 0), "edge": Vector3(1, 0, 0), "grip": 0.3},
	"pail": {"path": "res://assets/realistic/ph/wooden_bucket_01/wooden_bucket_01_1k.gltf", "length": 0.32, "tip": Vector3(0, -1, 0), "edge": Vector3(1, 0, 0), "grip": 0.02},
	"basket": {"path": "res://assets/realistic/ph/wicker_basket_01/wicker_basket_01_1k.gltf", "length": 0.34, "tip": Vector3(0, -1, 0), "edge": Vector3(1, 0, 0), "grip": 0.02},
	"mattock": {"path": "res://assets/props/Pickaxe_Bronze.gltf", "length": 0.85, "tip": Vector3(0, 1, 0), "edge": Vector3(1, 0, 0), "grip": 0.25},
	"torch": {"path": "res://assets/props/Torch_Metal.gltf", "length": 0.5, "tip": Vector3(0, 1, 0), "edge": Vector3(1, 0, 0), "grip": 0.3},
	"axe": KINDS["axe"],
}
## One row per move that needs something in hand: the tool, and the hand.
## The tool is in the hand exactly while the move plays (motion.gd asks).
## Moves with no row here hold nothing. Still without a model: a lute, a
## barrow, a stone to throw, a rod (Lute_Playing, Wheelbarrow, Throw_Object,
## Fishing_*), and no move yet for the broom (a sweep).
const CLIP_TOOLS := {
	"Drinking": ["bowl", "Right"], "Sitting_Drinking": ["bowl", "Right"],
	"Hammer_Swing": ["hammer", "Right"],
	"Watering": ["pail", "Right"],
	"Carrying": ["basket", "Left"], "Box_Walk": ["basket", "Left"], "Pick_Fruit": ["basket", "Left"],
	"Digging": ["mattock", "Right"], "Dig_And_Plant": ["mattock", "Right"],
	"Idle_Torch_Loop": ["torch", "Right"],
}

static var _cache := {}  # kind -> [PackedScene, Transform3D fitting it to its grip]


## Puts `kind` in a person's hand (a bow in the left), and a shield on the left
## forearm when asked and the weapon leaves that hand free. Replaces whatever
## they held before. Returns the weapon node.
static func arm(person: Node3D, kind: String, shield := false) -> Node3D:
	disarm(person)
	var skel := _skeleton(person)
	if skel == null or not KINDS.has(kind):
		return null
	var left := kind == "bow"
	var held := _hold(skel, kind, ("Left" if left else "Right") + "Hand", _hand_frame(left))
	if shield and not kind in TWO_HANDED:
		# Strapped along the outside of the forearm, point down, face out.
		_hold(skel, "shield", "LeftLowerArm", Transform3D(_frame(Vector3(0, 0, 1), Vector3(-1, 0, 0)), Vector3(-0.07, 0.14, 0)), "Shield")
	if kind == "bow":
		_hold(skel, "quiver", "UpperChest", Transform3D(_frame(Vector3(0.3, 1, -0.1), Vector3(0, 0, -1)), Vector3(0.06, 0.02, -0.16)), "Quiver")
	person.set_meta("weapon", kind)
	return held


## Empty hands: takes away whatever `arm` put on them.
static func disarm(person: Node3D) -> void:
	var skel := _skeleton(person)
	if skel == null:
		return
	for c in skel.get_children():
		if c is BoneAttachment3D and c.has_meta("weapon"):
			skel.remove_child(c)
			c.queue_free()
	person.remove_meta("weapon")


## The tool a move needs, in hand while it plays and gone after (CLIP_TOOLS);
## a soldier's weapon hand keeps its weapon, and the tool goes in the other.
static func hold_for(person: Node3D, clip: String) -> void:
	var skel := _skeleton(person)
	if skel == null:
		return
	var row: Array = CLIP_TOOLS.get(clip, [])
	if String(person.get_meta("tool", "")) == (String(row[0]) if not row.is_empty() else ""):
		return
	for c in skel.get_children():
		if c is BoneAttachment3D and c.get_meta("weapon", "") == "Tool":
			skel.remove_child(c)
			c.queue_free()
	person.remove_meta("tool")
	if row.is_empty() or not ResourceLoader.exists(String(TOOLS[row[0]].get("path", DIR + String(TOOLS[row[0]].get("file", "")) + "/scene.gltf"))):
		return
	var left: bool = row[1] == "Left"
	if held(person) != "" and not left:
		left = true  # the sword stays in the right hand
	_hold(skel, row[0], ("Left" if left else "Right") + "Hand", _hand_frame(left), "Tool")
	person.set_meta("tool", String(row[0]))


## What a person holds ("" for nothing).
static func held(person: Node3D) -> String:
	return String(person.get_meta("weapon", ""))


## The world position of a held weapon's point, for where a blow lands.
static func tip(person: Node3D) -> Vector3:
	var skel := _skeleton(person)
	if skel:
		for c in skel.get_children():
			if c is BoneAttachment3D and c.get_meta("weapon", "") == "Weapon" and c.get_child_count() > 0:
				var w: Node3D = c.get_child(0)
				return w.global_transform * (w.get_meta("tip_at", Vector3.ZERO) as Vector3)
	return person.global_position


static func _skeleton(person: Node3D) -> Skeleton3D:
	return person.get_node_or_null("Armature/GeneralSkeleton") as Skeleton3D


## The fist in a hand bone's space: the grip runs across the palm toward the
## index finger (+X in the right hand, -X in the left), the knuckles lie along
## the fingers (+Y), and the palm faces +Z. The handle sits in the curl.
static func _hand_frame(left: bool) -> Transform3D:
	var across := Vector3(-1, 0, 0) if left else Vector3(1, 0, 0)
	return Transform3D(_frame(across, Vector3(0, 1, 0)), Vector3(0, 0.075, 0.03))


## A basis taking a model's (tip, edge) onto (to_tip, to_edge).
static func _frame(to_tip: Vector3, to_edge: Vector3) -> Basis:
	var t := to_tip.normalized()
	var e := (to_edge - t * to_edge.dot(t)).normalized()
	return Basis(t, e, t.cross(e))


static func _hold(skel: Skeleton3D, kind: String, bone: String, socket: Transform3D, role := "Weapon") -> Node3D:
	if skel.find_bone(bone) < 0:
		return null
	var fit := _fitted(kind)
	var model: Node3D = (fit[0] as PackedScene).instantiate()
	_keep(model, _spec(kind).get("keep", []))
	model.transform = socket * (fit[1] as Transform3D)
	model.set_meta("tip_at", fit[2])
	var at := BoneAttachment3D.new()
	at.name = role
	at.bone_name = bone
	at.set_meta("weapon", role)
	skel.add_child(at)
	at.add_child(model)
	return model


## The model loaded once per kind, with the transform that scales it to its
## real length and puts its grip at the origin, tip along +X, edge along +Y.
## A weapon's or a tool's row.
static func _spec(kind: String) -> Dictionary:
	return KINDS[kind] if KINDS.has(kind) else TOOLS.get(kind, {})


static func _fitted(kind: String) -> Array:
	if _cache.has(kind):
		return _cache[kind]
	var k: Dictionary = _spec(kind)
	var scene: PackedScene = load(String(k.get("path", DIR + String(k.get("file", "")) + "/scene.gltf")))
	var probe: Node3D = scene.instantiate()
	var tip_dir: Vector3 = (k["tip"] as Vector3).normalized()
	var edge_dir: Vector3 = k["edge"]
	var lo := INF
	var hi := -INF
	var core := AABB()
	var core_found := false
	var all := AABB()
	var first := true
	for mi in probe.find_children("*", "MeshInstance3D", true, false):
		if not _kept(mi, k.get("keep", [])):
			continue
		var xf := _to_root(mi, probe)
		var box: AABB = xf * (mi as MeshInstance3D).get_aabb()
		for i in 8:
			var d := box.get_endpoint(i).dot(tip_dir)
			lo = minf(lo, d)
			hi = maxf(hi, d)
		all = box if first else all.merge(box)
		first = false
		if k.has("core") and _kept(mi, [k["core"]]):
			core = box if not core_found else core.merge(box)
			core_found = true
	probe.free()
	var mid: Vector3 = (core if core_found else all).get_center()
	var off := mid - tip_dir * mid.dot(tip_dir)  # the shaft's line, off the tip axis
	var grip: Vector3 = off + tip_dir * lerpf(lo, hi, float(k["grip"]))
	var s: float = float(k["length"]) / maxf(hi - lo, 0.0001)
	# Model space -> (tip, edge) frame, scaled, grip at the origin.
	var to_frame := _frame(tip_dir, edge_dir).inverse()
	var fit := Transform3D(to_frame.scaled(Vector3.ONE * s), Vector3.ZERO)
	fit.origin = -(fit.basis * grip)
	var point: Vector3 = off + tip_dir * hi
	_cache[kind] = [scene, fit, point]
	return _cache[kind]


static func _to_root(n: Node, root: Node) -> Transform3D:
	var xf: Transform3D = (n as Node3D).transform
	var up := n.get_parent()
	while up != root and up is Node3D:
		xf = (up as Node3D).transform * xf
		up = up.get_parent()
	return xf


static func _kept(mi: Node, keep: Array) -> bool:
	if keep.is_empty():
		return true
	for k in keep:
		if String(mi.name).contains(k) or String(mi.get_parent().name).contains(k):
			return true
	return false


static func _keep(model: Node, keep: Array) -> void:
	if keep.is_empty():
		return
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if not _kept(mi, keep):
			mi.free()
