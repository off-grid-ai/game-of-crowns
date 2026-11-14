extends RefCounted
## The realm's painted map, past where the land can be read: the far view the
## realm opens on (realm_map.gd) before the reign frames a town, closed when you
## zoom past it, press a town, or the game takes the camera down to the land. The
## camera's own zoom never jumps to it: it draws back over the land itself. Owned by main.gd, which sets it up once the bridge
## is in (_overview_setup) and opens it on the whole realm when the map comes.

const Main := preload("res://scripts/main.gd")
const MapLook := preload("res://scripts/map_look.gd")
const PoliticalOverlay := preload("res://scripts/political_overlay.gd")

var main: Main  # the realm that owns the map: its camera, land, names and bridge


func _init(owner: Main) -> void:
	main = owner


# --- the realm's painted map, past where the land can be read ----------------------

var overview: CanvasLayer
var _over_map: Control
var _over_open := false


func _overview_setup() -> void:
	overview = CanvasLayer.new()
	overview.layer = 0  # under the interface; the towns' name tags give way to it
	overview.visible = false
	main.add_child(overview)
	_over_map = preload("res://scripts/realm_map.gd").new()
	_over_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The painting holds up to about four times the whole realm; closer than
	# that the land itself is the better view.
	_over_map.max_zoom = 4.0
	if bool(MapLook.Data.value(MapLook.F, "overview.match", true)):
		_over_map.max_zoom = MapLook.num("overview.match_most", 7.0)  # it opens at the camera's own scale
	_over_map.modulate.a = 0.0
	overview.add_child(_over_map)
	_over_map.zoomed_past.connect(func(c: Vector2): _overview_close(c))
	_over_map.town_pressed.connect(func(t: Dictionary): _overview_close(Vector2(float(t["x"]), float(t["y"])), int(t.get("size", 4))))
	main.awareness.synced.connect(func():
		if _over_open:
			_mirror()
			main.bridge.realm_map(func(d): _over_map.data = d))


## The realm as it stands now, from the mirror: who holds the land and how firmly, the hosts, marches, sieges and
## towns in uproar.
func _mirror() -> void:
	if main.awareness == null:
		return
	var aw: Object = main.awareness
	var houses := {}
	for p in aw.realm.get_var(&"houses", [], false):
		houses[int(p.get("id", -1))] = p.get("house", {})
	_over_map.houses = houses
	var holds := {}
	for p in aw.realm.get_var(&"houses", [], false):
		holds[int(p.get("id", -1))] = PoliticalOverlay.hold_of(p)  # an angry house's land fades, as on the ground's map
	_over_map.holds = holds
	_over_map.unrest = MapLook.unrest(aw)
	_over_map.owners = aw.realm.get_var(&"owners", [], false)
	_over_map.hosts = MapLook.armies(aw)
	_over_map.marches = MapLook.marches(aw)
	_over_map.sieges = MapLook.sieges(aw)
	_over_map.queue_redraw()


## The painting's zoom that shows as much of the realm as the camera saw from its distance (CK3's map switch at one scale).
func _matched_zoom() -> float:
	var seen: float = 2.0 * float(main.rig.distance) * tan(deg_to_rad(main.rig.cam.fov / 2.0)) / main.terrain.TILE
	return clampf(_over_map.tiles().y / maxf(seen, 1.0), _over_map.min_zoom(), _over_map.max_zoom)


## Draws back from the land to the painted map, centred where you were looking
## (or on the whole realm).
func _overview_open(whole := false) -> void:
	if _over_open:
		return
	_over_open = true
	_mirror()
	if whole:
		_over_map.fit()
	else:
		_over_map.zoom = _matched_zoom() if bool(MapLook.Data.value(MapLook.F, "overview.match", true)) else _over_map.max_zoom
		_over_map.center = Vector2(main.rig.target.x, main.rig.target.z) / main.terrain.TILE - Vector2(0.5, 0.5)
	overview.visible = true
	main.labels.visible = false
	main.bridge.realm_map(func(d): _over_map.data = d)
	var tw := main.create_tween().set_parallel(true)
	tw.tween_property(_over_map, "modulate:a", 1.0, 0.0 if whole else 0.35)
	if not whole:  # still drawing back as the painting comes up
		tw.tween_property(_over_map, "zoom", maxf(MapLook.num("overview.ease_to", 2.6), _over_map.min_zoom()), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(_v): _over_map.queue_redraw(), 0.0, 1.0, 0.5)
	tw = tw.chain()
	tw.tween_callback(func():
		if _over_open:
			main.get_viewport().disable_3d = true)  # nothing of the land shows under it: spare the drawing


## Back down to the land at `tile`: a town framed (size >= 0), or the country
## around it as the map last showed it. With no tile, the game has taken the
## camera somewhere itself: just step aside.
func _overview_close(tile := Vector2.INF, size := -1) -> void:
	if not _over_open:
		return
	_over_open = false
	main.get_viewport().disable_3d = false
	if tile != Vector2.INF:
		var p: Vector3 = main.terrain.world_pos(tile.x, tile.y)
		main.rig.snap(p, main.rig.OVERVIEW, 0.0)
		if size >= 0:
			main.rig.frame_town(p, size)
		else:
			main.rig.focus(p, main.rig.OVERVIEW * 0.8)
	main.labels.visible = true
	var tw := main.create_tween()
	tw.tween_property(_over_map, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func():
		if not _over_open:
			overview.visible = false)
