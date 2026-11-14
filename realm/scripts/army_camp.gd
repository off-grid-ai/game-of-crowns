extends Node3D
## A host's camp where it holds in the field (Total War's encamped army, Age of Empires' and Warcraft III's camps of
## a halted force; casebook, War and sieges: "The march feeds the battle", an army at rest is seen to be one): beside
## its halted column, rows of tents in its house's canvas with its pennant over every few, cook fires with men sat
## round them, and a picket line of its horses tethered between two posts. army.gd pitches it when the host halts
## under an order in army.json camp.when and strikes it when it marches or takes ship. Numbers: army.json camp.

const Data := preload("res://scripts/data.gd")
const CampKit := preload("res://scripts/camp_kit.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const Bulk := preload("res://scripts/bulk.gd")  # the one drawer of repeated small things: the tents
const Horse := preload("res://scripts/horse.gd")


## Pitched beside the column whose middle is `mid`, heading `yaw` (forward (sin, 0, cos)), `length` long, on the
## side away from the road's verge it is given (`side` +1 its right, -1 its left).
func pitch(scenes: Node, mid: Vector3, yaw: float, length: float, side: float, col: Color, house: Dictionary, r: RandomNumberGenerator, hungry := false) -> void:
	name = "HostCamp"
	var k: Dictionary = Data.value("army", "camp", {})
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw)) * side
	var span := maxf(length, float(k.get("least", 1.0)))
	# Tents: rows along the column, ridges along it, the house's canvas and now and then plain linen.
	var t: Dictionary = k.get("tents", {})
	var sz: Array = t.get("size", [0.26, 0.2, 0.36])
	var canvas := CampKit.cloth(col.lerp(Color(0.9, 0.85, 0.72), float(t.get("canvas", 0.15))))
	var plain := CampKit.cloth(Color(0.82, 0.76, 0.62))
	var tents := []  # the house's canvas and plain linen, one prism each that every tent copies (bulk.gd)
	for cloth in [canvas, plain]:
		var mesh := PrismMesh.new()
		mesh.size = Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
		mesh.material = cloth
		tents.append(mesh)
	var n := 0
	for row in t.get("rows", [0.45, 0.8]):
		var along := -span * 0.5
		while along <= span * 0.5:
			var p: Vector3 = scenes.ground(mid + right * (float(row) + r.randf_range(-0.04, 0.04)) + fwd * (along + r.randf_range(-0.03, 0.03)))
			if scenes._footing(p):
				var place := Transform3D(Basis(Vector3.UP, yaw + r.randf_range(-0.15, 0.15)), p + Vector3(0, float(sz[1]) * 0.5, 0))
				Bulk.add(tents[0] if n % 3 != 2 else tents[1], global_transform * place, self, 1000.0, true)  # drawn in bulk, gone with the camp
				if n % int(t.get("pennant_every", 3)) == 0:
					var flag := Heraldry.standard(house, col, float(t.get("pennant", 0.14)))
					flag.transform = place * Transform3D(Basis.IDENTITY, Vector3(0, float(sz[1]) * 0.5, float(sz[2]) * 0.45))
					add_child(flag)
				n += 1
			along += float(t.get("every", 0.38))
	# Cook fires between the rows; a hungry host's more of them, its men huddled round what little there is (The march
	# feeds the battle; bridge hosts.js hungry; army.json camp.hungry).
	var f: Dictionary = k.get("fires", {})
	if hungry:
		f = f.merged(k.get("hungry", {}), true)
	var fires := int(f.get("count", 2))
	for i in fires:
		var p: Vector3 = scenes.ground(mid + right * float(f.get("at", 0.62)) + fwd * lerpf(-span * 0.35, span * 0.35, (i + 0.5) / float(fires)))
		if scenes._footing(p):
			CampKit.fire(scenes, self, p, col, int(f.get("sitters", 3)), r)
	# The picket line: two posts and a rope behind the tents, the horses tethered along it facing it.
	var pk: Dictionary = k.get("picket", {})
	var behind := float(pk.get("at", 1.15))
	var half := minf(span * 0.5, float(pk.get("half", 0.6)))
	var a: Vector3 = scenes.ground(mid + right * behind - fwd * half)
	var b: Vector3 = scenes.ground(mid + right * behind + fwd * half)
	if not (scenes._footing(a) and scenes._footing(b)):
		return
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.22, 0.15)
	var high := float(pk.get("height", 0.09))
	for q in [a, b]:
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.006
		cyl.bottom_radius = 0.008
		cyl.height = high
		post.mesh = cyl
		post.material_override = wood
		post.position = q + Vector3(0, high * 0.5, 0)
		add_child(post)
	var rope := MeshInstance3D.new()
	var line := CylinderMesh.new()
	line.top_radius = 0.0015
	line.bottom_radius = 0.0015
	line.height = a.distance_to(b)
	rope.mesh = line
	rope.material_override = wood
	add_child(rope)
	rope.look_at_from_position((a + b) * 0.5 + Vector3(0, high * 0.9, 0), b + Vector3(0, high * 0.9, 0), Vector3.UP)
	rope.rotate_object_local(Vector3.RIGHT, PI * 0.5)  # the cylinder's length along the rope
	var horses := int(pk.get("horses", 5))
	for i in horses:
		var at := a.lerp(b, (i + 0.5) / float(horses))
		var p: Vector3 = scenes.stand(at + right * float(pk.get("off", 0.09)))
		var h: Node3D = Horse.new(r.randi() % Horse.COATS.size())
		h.position = p
		h.rotation.y = atan2(-right.x, -right.z) + r.randf_range(-0.25, 0.25)  # nose to the rope
		add_child(h)
		h.live_idle(r)
