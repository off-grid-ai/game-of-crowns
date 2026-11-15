extends Node
## A person's own portrait from the player's photo (Mac 2026-11-15): picked with the system's own file dialog, sent to
## the bridge (likeness.js), which paints it in the realm's style with Off Grid AI Desktop's image model, or keeps the
## photo as is. Painting runs on the bridge; this asks every few seconds until it's done, then lays the portrait over
## the person's dealt face (painted_faces.gd own), so every card shows it. One per game (main.gd), reached as
## Likeness.one.

const PaintedFaces := preload("res://scripts/painted_faces.gd")

signal changed(id: String)  # a portrait began painting, or arrived: cards showing that person draw it again

static var one: Node
var _painting := {}  # id -> true while the bridge paints it
var _ask: Timer


func _ready() -> void:
	one = self
	_ask = Timer.new()
	_ask.wait_time = 3.0
	_ask.timeout.connect(_check)
	add_child(_ask)


## Whether this person's portrait is being painted now.
func painting(id: String) -> bool:
	return _painting.has(id)


## Every portrait the reign keeps (on a new reign or a load): laid over the dealt faces.
func load_all() -> void:
	_ask_bridge("/portraits", func(code, body, _type):
		var d = JSON.parse_string(body.get_string_from_utf8()) if code == 200 else null
		if not (d is Dictionary):
			return
		for id in d.get("ids", []):
			if not d.get("painting", []).has(id):
				_fetch(String(id)))


## The player chooses a photo for this person (who: a few words of who they are, for the painter).
func pick(id: String, who: String) -> void:
	var fd := FileDialog.new()
	fd.use_native_dialog = true
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg ; Photos"])
	fd.title = "Choose a photo"
	add_child(fd)
	fd.file_selected.connect(func(path: String):
		fd.queue_free()
		_send(id, path, who))
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered()


func _send(id: String, path: String, who: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return
	var ext := "png" if path.get_extension().to_lower() == "png" else "jpg"
	_bridge().send_photo(id, ext, who, bytes, func(code):
		if code == 202:
			_painting[id] = true
			changed.emit(id)
			_ask.start())


## Still painting? When a portrait is done, fetch it.
func _check() -> void:
	if _painting.is_empty():
		_ask.stop()
		return
	_ask_bridge("/portraits", func(code, body, _type):
		var d = JSON.parse_string(body.get_string_from_utf8()) if code == 200 else null
		if not (d is Dictionary):
			return
		for id in _painting.keys():
			if not d.get("painting", []).has(id):
				_painting.erase(id)
				_fetch(String(id)))


func _fetch(id: String) -> void:
	_ask_bridge("/portrait?id=" + id.uri_encode(), func(code, body: PackedByteArray, type: String):
		if code != 200:
			return
		var img := Image.new()
		var err := img.load_png_from_buffer(body) if type.contains("png") else img.load_jpg_from_buffer(body)
		if err != OK:
			return
		PaintedFaces.own(id, ImageTexture.create_from_image(img))
		changed.emit(id))


func _ask_bridge(path: String, cb: Callable) -> void:
	_bridge().fetch_raw(path, cb)


func _bridge() -> Node:
	return get_tree().current_scene.get("bridge")
