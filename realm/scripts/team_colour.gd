extends Node
## Team colour (Mac's North Star, docs/art/target/02-realm.jpg; the Warcraft III way): every building wears
## its holder's colours. The one owner: the kit materials named in data/look.json team.materials are
## swapped for one shared shader (team_colour.gdshader: roof tiles and trims take the colour, walls and
## stone stay natural), and each town's batches get its holder's colour per instance, from the realm as
## the bridge reports it. A town that changes hands recolours over a season, as the land's colour spreads.
## The army's armour uses the same shader (team_colour.gdshader). On with look.json team.on.

const SHADER := preload("res://scripts/team_colour.gdshader")
const CameraRig := preload("res://scripts/camera_rig.gd")

var main: Node
var _team_of := {}  # a source material -> its team material, made once and shared
var _done := {}  # a mesh already given team materials (by instance id)
var _members: Array = []  # [GeometryInstance3D, town id] in a town
var _shown := {}  # a geometry's instance id -> the colour it shows now
var _tick := 0.0


static func cfg() -> Dictionary:
	var t = preload("res://scripts/look.gd").LOOK.get("team")
	return t if t is Dictionary else {}


static func on() -> bool:
	return bool(cfg().get("on", false))


static func apply(m: Node) -> void:
	if not on():
		return
	var t := new()
	t.name = "TeamColour"
	t.main = m
	m.add_child(t)


func _ready() -> void:
	get_tree().node_added.connect(func(n): if n is GeometryInstance3D: _take.call_deferred(n))
	for g in main.find_children("*", "GeometryInstance3D", true, false):
		_take(g)


func _mesh_of(g: GeometryInstance3D) -> Mesh:
	if g is MeshInstance3D:
		return (g as MeshInstance3D).mesh
	if g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
		return (g as MultiMeshInstance3D).multimesh.mesh
	return null


## A kit material named in team.materials, as the shared team shader (its texture, colour, normal kept).
func _team_mat(src: BaseMaterial3D, amount: float) -> ShaderMaterial:
	if _team_of.has(src):
		return _team_of[src]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.resource_name = src.resource_name
	m.set_shader_parameter("albedo", src.albedo_color)
	m.set_shader_parameter("has_albedo_tex", src.albedo_texture != null)
	if src.albedo_texture:
		m.set_shader_parameter("albedo_tex", src.albedo_texture)
	m.set_shader_parameter("has_normal", src.normal_enabled and src.normal_texture != null)
	if src.normal_texture:
		m.set_shader_parameter("normal_tex", src.normal_texture)
	m.set_shader_parameter("roughness", src.roughness)
	m.set_shader_parameter("uv_scale", Vector2(src.uv1_scale.x, src.uv1_scale.y))
	m.set_shader_parameter("team_amount", amount)
	# The roofs' mix and the colour's tone (data/look.json team.roofs, team.paint; art target 01-town).
	var roofs: Dictionary = cfg().get("roofs", {})
	m.set_shader_parameter("is_roof", (roofs.get("materials", ["MI_RoundTiles"]) as Array).any(func(k): return String(src.resource_name).begins_with(String(k))))
	# A tiered kit house names its roof's covering (house_tiers.gd: MI_RoundTiles_thatch...): that, not the seed.
	var cover := String(src.resource_name).get_slice("_", 2) if String(src.resource_name).begins_with("MI_RoundTiles_") else ""
	m.set_shader_parameter("roof_kind", {"thatch": 1, "tile": 2, "slate": 3, "house": 4, "shingle": 5}.get(cover, 0))
	m.set_shader_parameter("roof_cottage", _v4(roofs.get("cottage"), Vector4(0.55, 0.25, 0.1, 0.1)))
	m.set_shader_parameter("roof_town", _v4(roofs.get("town"), Vector4(0.15, 0.4, 0.2, 0.25)))
	m.set_shader_parameter("thatch", _rgb(roofs.get("thatch"), Color(0.8, 0.64, 0.34)))
	m.set_shader_parameter("house_roof_share", float(roofs.get("house_share", 1.0)))
	m.set_shader_parameter("dark_tile", _rgb(roofs.get("dark_tile"), Color(0.5, 0.42, 0.4)))
	m.set_shader_parameter("thatch_old", _rgb(roofs.get("thatch_old"), Color(0.5, 0.42, 0.31)))
	var straw: Dictionary = roofs.get("straw", {})
	m.set_shader_parameter("thatch_fibre", float(straw.get("fibre", 0.14)))
	m.set_shader_parameter("thatch_clump", float(straw.get("clump", 0.16)))
	m.set_shader_parameter("thatch_eave_dark", float(straw.get("eave_dark", 0.62)))
	m.set_shader_parameter("thatch_eave_band", float(straw.get("eave_band", 0.16)))
	m.set_shader_parameter("thatch_storey", float(straw.get("storey", 0.36)))
	var paint: Dictionary = cfg().get("paint", {})
	m.set_shader_parameter("ordinary_share", float(paint.get("ordinary_share", 0.5)))
	m.set_shader_parameter("paint_sat", float(paint.get("saturation", 0.8)))
	m.set_shader_parameter("paint_warm", _rgb(paint.get("warm"), Color(1.0, 0.93, 0.84)))
	m.set_shader_parameter("fade_gone", CameraRig.fade_knob("near_fade.buildings.gone", 1.2))  # clarity: only what touches the lens
	m.set_shader_parameter("fade_solid", CameraRig.fade_knob("near_fade.buildings.solid", 2.6))
	_team_of[src] = m
	return m


func _take(g: GeometryInstance3D) -> void:
	if not is_instance_valid(g):
		return
	var mesh := _mesh_of(g)
	if mesh == null:
		return
	var want: Dictionary = cfg().get("materials", {})
	var any := false
	if not _done.has(mesh.get_instance_id()):
		_done[mesh.get_instance_id()] = false
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			if src is ShaderMaterial and (src as ShaderMaterial).shader == SHADER:
				_done[mesh.get_instance_id()] = true
				continue
			if not src is BaseMaterial3D:
				continue
			for key in want:
				if String(src.resource_name).begins_with(String(key)):
					mesh.surface_set_material(i, _team_mat(src, float(want[key])))
					_done[mesh.get_instance_id()] = true
					break
	any = _done[mesh.get_instance_id()]
	if not any:
		return
	# What it is: a cottage (0) or a townhouse or inn (1) carries a smaller share of the colour and a roof of
	# its own; the castle, the hall and anything else (2, the shader's default) the full colour.
	var rank := _rank_of(g)
	if rank < 2:
		g.set_instance_shader_parameter("team_rank", float(rank))
	# Which town it stands in: the town whose node holds it (towns.gd keeps each town's root).
	var town := _town_of(g)
	if town >= 0:
		_members.append([g, town])


static var _ranks := {}  # kit model name -> 0 cottage, 1 townhouse or inn


func _rank_of(g: Node) -> int:
	if not g.has_meta("kind"):
		return 2
	if _ranks.is_empty():
		var Real := preload("res://scripts/realistic.gd")
		var by: Dictionary = cfg().get("ranks", {"house_poor": 0, "house_rich": 1, "tavern": 1})
		for comp in by:
			for n in Real.variants(String(comp)):
				_ranks[String(n)] = int(by[comp])
	return int(_ranks.get(String(g.get_meta("kind")), 2))


static func _v4(a, fallback: Vector4) -> Vector4:
	return Vector4(float(a[0]), float(a[1]), float(a[2]), float(a[3])) if a is Array and a.size() >= 4 else fallback


static func _rgb(a, fallback: Color) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else fallback


func _town_of(n: Node) -> int:
	var ts: Dictionary = main.towns.towns if main.get("towns") else {}
	var roots := {}
	for id in ts:
		var node = ts[id].get("node")
		if node is Node and is_instance_valid(node):
			roots[node.get_instance_id()] = int(id)
	var p := n
	while p:
		if roots.has(p.get_instance_id()):
			return roots[p.get_instance_id()]
		p = p.get_parent()
	return -1


## Every half second: each town's holder colour, eased toward it over a season.
func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.5:
		return
	var dt := _tick
	_tick = 0.0
	var owner_of := {}
	for c in main.bridge.world.get("cities", []):
		owner_of[int(c.get("id", -1))] = int(c.get("owner", -1))
	var secs: float = preload("res://scripts/awareness.gd").season_seconds
	var season := maxf(5.0, secs if secs > 0.0 else 40.0)
	var step := clampf(dt / season, 0.0, 1.0)
	_members = _members.filter(func(m): return is_instance_valid(m[0]))
	for m in _members:
		var g: GeometryInstance3D = m[0]
		var house: Dictionary = main._houses.get(owner_of.get(int(m[1]), -1), {})
		var target := Color(1, 1, 1, 0) if house.is_empty() or house.get("wild", false) else _colour(house)
		var key := g.get_instance_id()
		var now: Color = _shown.get(key, target)  # a new town takes its colour at once; a change of hands eases
		var next := now.lerp(target, step) if now != target and _shown.has(key) else target
		if not _shown.has(key) or next != now:
			g.set_instance_shader_parameter("team_color", next)
			_shown[key] = next


func _colour(house: Dictionary) -> Color:
	var c: Color = preload("res://scripts/heraldry.gd").colour(house, Color.GRAY, "#888")
	var sat := float(cfg().get("saturation", 1.15))
	var l := c.get_luminance()
	return Color(clampf(l + (c.r - l) * sat, 0, 1), clampf(l + (c.g - l) * sat, 0, 1), clampf(l + (c.b - l) * sat, 0, 1), 1.0)
