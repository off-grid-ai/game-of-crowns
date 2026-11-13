extends Node3D
## A house seat as the realm map shows it (docs/art/target/02-realm.jpg: every seat a castle you can read from map
## height under a tall banner in its house's colours and arms; Total War's campaign map grows its settlements as the
## camera draws back): the castle set's keep (ck_keep) with the house's standard over it, standing on the seat's own
## castle. Hidden up close, where the town's real castle stands; from towns.json map_seat.from away it shows, and past
## map_seat.ref it grows with the camera's distance (at most map_seat.most times), so it keeps its size on the screen.
## It decides nothing: its house and banner are the town's (town_banners.gd map_seat raises it).

const Data := preload("res://scripts/data.gd")

var _from := 40.0
var _ref := 40.0
var _most := 4.0
var _base := 1.0


## Built over a seat's castle: the keep `keep_h` world units tall (towns.json map_seat.keep), its standard over it.
func build(keep_h: float) -> float:
	var ms: Dictionary = Data.value("towns", "map_seat", {})
	_from = float(ms.get("from", 40.0))
	_ref = maxf(float(ms.get("ref", _from)), 0.01)
	_most = float(ms.get("most", 4.0))
	var path := "res://assets/meshy/ck_keep/ck_keep.glb"
	if ResourceLoader.exists(path):
		var keep: Node3D = (load(path) as PackedScene).instantiate()
		var tall := 20.0  # metres, the piece as imported (assets/meshy/ck_keep/import.json size_m)
		var f := FileAccess.open("res://assets/meshy/ck_keep/import.json", FileAccess.READ)
		var j: Variant = JSON.parse_string(f.get_as_text()) if f else null
		if j is Dictionary and (j as Dictionary).has("size_m"):
			tall = float((j as Dictionary)["size_m"][2])
		keep.scale = Vector3.ONE * keep_h / maxf(tall, 0.01)
		add_child(keep)
	visible = false
	return keep_h


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := cam.global_position.distance_to(global_position)
	visible = d >= _from
	if visible:
		scale = Vector3.ONE * clampf(d / _ref, 1.0, _most)
