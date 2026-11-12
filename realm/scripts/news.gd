extends RefCounted
## The player's news: the latest moment the King might want to see, its chip,
## the Watch offer and the edge arrow, the lord's cue (from the scene table,
## scene_kinds.gd), and Space to go to it and back. Owned by main.gd, which
## forwards the scenes' staged signal here (_on_staged).

const Main := preload("res://scripts/main.gd")
const SceneKinds := preload("res://scripts/scene_kinds.gd")  # the one table of scene kinds

var main: Main  # the realm that owns the news: its camera, sound, director and interface


func _init(owner: Main) -> void:
	main = owner


## The moments the King should never miss: his own grain, gold, riders, levies,
## feasts and grants always; war and fire, now and then.
const KINGS_OWN := ["grain", "tribute", "rider", "ward", "muster", "feast", "handover"]
const WAR := ["battle", "siege", "sack", "razed"]
var _offered_at := -100000


## The latest news the King might want to see, for Space and the edge arrow.
var _news := {}  # {s, follow, at: Vector3, caption, ms}
var _before_news := {}  # where the camera was before Space took it to the news
var _horn_at := -100000  # when a lord's news last sounded


func _on_staged(s: Dictionary, follow: Node3D) -> void:
	var kind := String(s.get("kind", ""))
	main.sound.staged(kind, main.terrain.world_pos(float(s.get("x", 0)), float(s.get("y", 0))), bool(s.get("lord", false)))
	if kind in KINGS_OWN or kind in WAR:
		# Whose news: the house of the town it happened in (the house it went to, for a handover).
		var owner := int(s.get("to", -1))
		if owner < 0:
			for c in main.bridge.world.get("cities", []):
				if int(c["id"]) == int(s.get("city", -1)):
					owner = int(c["owner"])
		var col := Color.from_string(String(main._houses.get(owner, {}).get("color", "#c9a95a")), Color(0.79, 0.66, 0.35))
		_news = {"s": s, "follow": follow, "at": main.terrain.world_pos(float(s.get("x", 0)), float(s.get("y", 0))), "caption": main.director.caption(s), "ms": Time.get_ticks_msec(), "color": col, "new": true,
			# Its tone on the chip: red for what's hostile (loss), gold for the King's own, plain for the rest.
			"tone": "loss" if kind in ["sack", "razed", "battle", "siege"] or (kind == "handover" and s.get("lord", false)) else ("crown" if kind in KINGS_OWN and not s.get("lord", false) else "")}
		# A lord's deed sounds once, each kind its own (StarCraft: an attack never sounds
		# like news): the horn only for what's hostile, the bell for a death, a cheer for
		# a feast, a letter on the road in silence. Rate-limited with the offers.
		if s.get("lord", false) and Time.get_ticks_msec() - _horn_at > 20000:
			# Which cue, from the one scene table (scene_kinds.gd): hostile a horn, joy a cheer,
			# grief a bell. A battle or siege already sounds through the chronicle's own stinger.
			var cue: String = {SceneKinds.HOSTILE: "horn", SceneKinds.JOY: "feast", SceneKinds.GRIEF: "death"}.get(SceneKinds.tone(kind), "") if kind not in WAR or kind in ["sack", "razed"] else ""
			if kind == "rider" and String(s.get("label", "")).begins_with("Word of a death"):
				cue = "death"
			if cue != "":
				_horn_at = Time.get_ticks_msec()
				main.sound.event(cue)
		elif kind == "handover" and not s.get("lord", false):
			main.sound.event("handover")  # the King's own town given in peace: a quiet fanfare, never the horn
		# One channel for one piece of news: off screen, the edge arrow carries it, so no Watch card as well.
		var cam := main.get_viewport().get_camera_3d()
		if cam and (cam.is_position_behind(_news["at"]) or not main.get_viewport().get_visible_rect().grow(-40).has_point(cam.unproject_position(_news["at"]))):
			return
	if kind in KINGS_OWN or kind in WAR:
		# The King's own deeds are always offered; what the lords do, at most every 20 s.
		_offer(main.director.caption(s), main.director.watch.bind(s, follow), kind in KINGS_OWN and not s.get("lord", false))


## A court matter waiting at its place (court_panel.gd, through ui.court_waits_at): it
## becomes the latest news, so the edge arrow points at it while it's off screen and
## Space (or the arrow) opens it there; pressed again, back. Nothing moves by itself.
func point_at(at: Vector3, caption: String, go: Callable) -> void:
	_news = {"at": at, "caption": caption, "ms": Time.get_ticks_msec(), "new": true, "tone": "crown", "go": go}


## One Watch offer at a time; the realm's own news no more than every 20 s,
## the King's own deeds and a story's turns always.
func _offer(text: String, go: Callable, always: bool) -> void:
	if main.control.active or main._shot.has("path"):
		return
	if not always and Time.get_ticks_msec() - _offered_at < 20000:
		return
	_offered_at = Time.get_ticks_msec()
	main.ui.offer_watch(text, go)


## Space, as in Warcraft and StarCraft: to the latest news, and pressed again,
## back to where the King was. Home also goes back.
func _to_news() -> void:
	if not _before_news.is_empty():
		_back_from_news()
		return
	if _news.is_empty():
		return
	_before_news = {"target": main.rig.goal_target, "distance": main.rig.goal_distance, "yaw": main.rig.goal_yaw, "tilt": main.rig.goal_tilt}
	if _news.get("go") is Callable and (_news["go"] as Callable).is_valid():
		(_news["go"] as Callable).call()
		return
	var f = _news.get("follow")
	main.director.watch(_news["s"], f if is_instance_valid(f) else null)


func _back_from_news() -> void:
	if _before_news.is_empty():
		return
	main.director.active = false
	main.rig.goal_target = _before_news["target"]
	main.rig.goal_distance = _before_news["distance"]
	main.rig.goal_yaw = _before_news["yaw"]
	main.rig.goal_tilt = _before_news["tilt"]
	_before_news = {}


## The edge arrow: the latest news, for 40 s, when it's off screen.
var _edge_left := 0.0


func _edge_tick(delta: float) -> void:
	_edge_left -= delta
	if _edge_left > 0.0:
		return
	_edge_left = 0.15
	var cam := main.get_viewport().get_camera_3d()
	if _news.is_empty() or cam == null or Time.get_ticks_msec() - int(_news["ms"]) > 40000 or not _before_news.is_empty():
		main.ui.edge_arrow(null, 0.0, "", "", false)
		return
	var at: Vector3 = _news["at"]
	var view := main.get_viewport().get_visible_rect().size
	var p := cam.unproject_position(at)
	var behind := cam.is_position_behind(at)
	if not behind and Rect2(Vector2.ZERO, view).grow(-40).has_point(p):
		main.ui.edge_arrow(null, 0.0, "", "", false)  # it's on screen: no arrow
		return
	var mid := view * 0.5
	var dir := (p - mid) * (-1.0 if behind else 1.0)
	if dir.length() < 1.0:
		dir = Vector2.UP
	# Where the line from the centre toward it leaves the screen.
	var k := minf((mid.x - 30) / maxf(absf(dir.x), 0.001), (mid.y - 30) / maxf(absf(dir.y), 0.001))
	main.ui.edge_arrow(mid + dir * k, dir.angle(), String(_news["caption"]), String(_news.get("tone", "")), _news.get("new", false))
	_news["new"] = false
