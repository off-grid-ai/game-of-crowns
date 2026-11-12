extends CanvasLayer
## A painterly pass over the world (trial; look.json paint; --paint=kuwahara|off): the Generalized Kuwahara filter
## (paint.gdshader, MIT, Firerabbit's Godot 4 port of Acerola's) over the finished 3D frame, after the grade, so the
## kit's hard edges and flat texture read as soft brush-like patches toward 01-town. It sits under the town names
## (layer 0) and the whole interface, so no text is touched. Off unless look.json paint.mode or --paint says so.

const Data := preload("res://scripts/data.gd")


static func mode() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--paint="):
			return a.substr(8)
	return String(Data.value("look", "paint.mode", "off"))


## Lays the pass over the world when it is on.
static func apply(m: Node) -> void:
	if mode() != "kuwahara":
		return
	var p := new()
	p.name = "Paint"
	m.add_child(p)


func _ready() -> void:
	layer = -1  # over the 3D world, under the town names (0) and the interface
	var k: Dictionary = Data.value("look", "paint", {})
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/paint.gdshader")
	mat.set_shader_parameter("radius", int(k.get("radius", 3)))
	mat.set_shader_parameter("strength", float(k.get("strength", 0.7)))
	mat.set_shader_parameter("hardness", float(k.get("hardness", 8.0)))
	mat.set_shader_parameter("edge_preserve", float(k.get("edge_preserve", 8.0)))
	var r := ColorRect.new()
	r.material = mat
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(r)
