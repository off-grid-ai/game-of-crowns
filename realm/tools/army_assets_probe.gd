extends SceneTree
## Headless guard for the army's soldiers (GoC round 12: the Meshy town guard, man-at-arms and ranger regiments drew
## untextured, "Failed loading resource ... albedo.png"). General problem: a baked soldier's textures must be what
## their names say, or Godot's importer refuses them (rig_unit.py had saved Meshy's JPEG paint as albedo.png). No
## realm, no bridge:
##   arch -arm64 godot --headless --path realm -s res://tools/army_assets_probe.gd
## For every soldier in data/army.json meshes, it asserts each texture the army's material reads (army.gd _asset: the
## paint, the house-colour mask where the row's team is "mask", the VAT offsets and normals) is the format its name
## says and loads as a texture.
## Prints "ARMY ASSETS PROBE …" lines and "ARMY ASSETS PROBE PASS" or "ARMY ASSETS PROBE FAIL n"; quits with 0 or 1.

const Data := preload("res://scripts/data.gd")

const MAGIC := {"png": [0x89, 0x50, 0x4E, 0x47], "jpg": [0xFF, 0xD8, 0xFF], "jpeg": [0xFF, 0xD8, 0xFF], "exr": [0x76, 0x2F, 0x31, 0x01]}

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("ARMY ASSETS PROBE %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	var meshes: Dictionary = Data.value("army", "meshes", {})
	for asset in meshes:
		var row: Dictionary = meshes[asset] if meshes[asset] is Dictionary else {}
		var dir := "res://assets/%s/" % asset
		if not DirAccess.dir_exists_absolute(dir):
			print("ARMY ASSETS PROBE skip %s (not on this machine)" % asset)
			continue
		var files := [String(row.get("albedo", "albedo.png")), "offsets.exr", "normals.png"]
		if String(row.get("team", "rects")) == "mask":
			files.append("mask.png")
		for f in files:
			var path: String = dir + f
			_check(_is_what_it_says(path), "%s%s is the format its name says" % [asset + "/", f])
			_check(load(path) is Texture2D, "%s%s loads as a texture" % [asset + "/", f])
	print("ARMY ASSETS PROBE PASS" if _fails == 0 else "ARMY ASSETS PROBE FAIL %d" % _fails)
	quit(0 if _fails == 0 else 1)


## Whether a file's first bytes are its extension's format (a JPEG named .png is refused by the importer).
func _is_what_it_says(path: String) -> bool:
	var want: Array = MAGIC.get(path.get_extension().to_lower(), [])
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return false
	var head := fa.get_buffer(want.size())
	for i in want.size():
		if i >= head.size() or head[i] != want[i]:
			return false
	return true
