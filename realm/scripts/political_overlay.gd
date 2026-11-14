extends RefCounted
## The realm map (integration audit #13: terrain.gd's political overlay, split out): who holds which tile, the
## houses' wars, truces and schemes along their borders, land changing hands flooding in, and the scars of battles
## and sacks, all drawn into the ground's shaders (land3d, and the hand-built land's material). terrain.gd makes it
## (terrain.politics); main.gd hands it the store's owners, houses, intrigue and marks; the minimap reads its
## standing texture and its flood; ruins read how long a scar lasts.

var _t: Node3D  # terrain.gd: the tile map's size, its land3d and its material


func _init(terrain: Node3D) -> void:
	_t = terrain

var _realm_sig := ""
var _realm_rows: Array = []  # the owners' rows as last read: a row is parsed again only when its text changes
var _war_img: Image  # the standing per tile, kept and repainted where it changed
var _war_live: ImageTexture  # standing_tex, updated in place
var _borders := {}  # tiles on a border between two houses (what a change of standing repaints)
var _look_sig := ""  # the houses' colours and oaths: a change repaints everything
var _rel_sig := ""  # wars, truces, schemes: a change repaints the borders


## Repaints territory from Freeciv's owner layer (one "-,0,3,…" row per map
## line) and the houses' wars. players: world players with house and wars (the
## bridge's one reading of who is at war: a truce the King commanded, or a loyal
## house's old diplomacy with the crown, isn't one; Freeciv's raw atWarWith is).
## intrigue: the houses' schemes among themselves (the mirror's intrigue): an
## envoy, a pact the King's spies have revealed, a marriage, drawn on the seam
## between the two houses (a = 0.75 envoy, 0.5 pact, 0.25 marriage; 1 none).
const SCHEME := {"envoy": 0.75, "pact": 0.5, "marriage": 0.25}
## How strongly a house's land carries its colour, from its favour band (the bridge's reading; look.json
## politics.hold): loyal heartland strong, an angry house's land fading. The one rule the ground's map and the
## painted overview map (realm_map.gd) both read.
static func hold_of(player: Dictionary) -> float:
	var bands: Dictionary = (preload("res://scripts/look.gd").LOOK.get("politics", {}) as Dictionary).get("hold", {})
	return float(bands.get(str(player.get("band", "")), 1.0))


## The political map (realm/data/look.json politics): each house's hold from its favour band (the bridge's
## reading) and, for a house slipping away, the colour of the first house it's at war with; to the ground's
## shader as two uniform arrays by owner id, so a change of mood repaints nothing.
func _set_politics(players: Array, colour: Dictionary, by_name: Dictionary) -> void:
	if _t.land3d == null:
		return
	var pol: Dictionary = preload("res://scripts/look.gd").LOOK.get("politics", {})
	var on := bool(pol.get("on", false))
	if preload("res://scripts/map_look.gd").politics():
		on = true  # the realm at map zoom reads who holds it (data/map.json politics)
	var hold := PackedFloat32Array()
	hold.resize(64)
	hold.fill(1.0)
	var lean := PackedVector3Array()
	lean.resize(64)
	for p in players:
		var id := int(p.get("id", -1))
		if id < 0 or id >= 64:
			continue
		hold[id] = hold_of(p)
		var foes: Array = p.get("atWarWith", [])
		if not foes.is_empty() and colour.has(int(foes[0])):
			var c: Color = colour[int(foes[0])]
			lean[id] = Vector3(c.r, c.g, c.b)
	_t.land3d.set_politics(on, hold, lean,
		Vector4(float(pol.get("wash_near", 0.3)), float(pol.get("wash_far", 0.8)), float(pol.get("own_mix", 0.45)), float(pol.get("stripes_below", 0.4))),
		Vector4(float(pol.get("border_bright", 1.35)), float(pol.get("border_px", 3.0)), float(pol.get("stripe_width", 1.4)), float(pol.get("border_glow", 0.0))),
		Vector4(float(pol.get("map_from", 12.0)), float(pol.get("map_to", 30.0)), float(pol.get("band", 0.4)), float(pol.get("band_strength", 0.35))),
		Vector4(float(pol.get("line_from", 9.0)), float(pol.get("line_to", 22.0)), float(pol.get("line_soft", 0.22)), float(pol.get("line_crisp", 0.55))),
		_relief())



## The land's relief at the map's height (data/map.json relief): its strength and the light it is shaded from.
static func _relief() -> Vector4:
	var l: Array = preload("res://scripts/data.gd").value("map", "relief.light", [-0.5, 0.7, -0.5])
	return Vector4(preload("res://scripts/map_look.gd").num("relief.strength", 0.0), float(l[0]), float(l[1]), float(l[2]))


func set_realm(owners: Array, players: Array, intrigue: Array = []) -> void:
	if _t._land_mat == null or owners.size() != _t.height or _t.land3d == null or _t.land3d.land == null:
		return  # (the 3D land is still being raised: the next reading paints it)
	var wars := {}
	var truces := {}
	var sworn := {}
	var colour := {}
	for p in players:
		wars[int(p["id"])] = []
		truces[int(p["id"])] = []
		sworn[int(p["id"])] = p.get("sworn") != null
		var h: Dictionary = p.get("house", {})
		colour[int(p["id"])] = Color(0, 0, 0, 0) if h.get("wild", false) else preload("res://scripts/heraldry.gd").colour(h, Color.GRAY, "#888")
	# The bridge names the foes ("Wolfholt", "the Crown"); the map wants their ids.
	var by_name := {}
	for p in players:
		var h: Dictionary = p.get("house", {})
		by_name["the Crown" if h.get("crown", false) else String(h.get("name", "")).trim_prefix("House ")] = int(p["id"])
	# A vassal house's land in its liege's colour (/world players' liege: the liege's id or house name), so the realm
	# reads whole and the seam between them is drawn thin (land3d.gd pol_vassal); every land is some great house's.
	for p in players:
		var lg = p.get("liege")
		if lg == null:
			continue
		var lid := int(lg) if (lg is int or lg is float) else int(by_name.get(String(lg).trim_prefix("House "), -1))
		if colour.has(lid) and lid != int(p["id"]):
			colour[int(p["id"])] = colour[lid]
	for p in players:
		for foe in p.get("wars", []):
			if by_name.has(String(foe)):
				wars[int(p["id"])].append(by_name[String(foe)])
		for held in p.get("truces", []):
			if by_name.has(String(held)):
				truces[int(p["id"])].append(by_name[String(held)])
	var schemes := {}  # "a:b" (lower id first) -> its seam's code
	for it in intrigue:
		var k := String(it.get("kind", ""))
		if not SCHEME.has(k) or (k == "pact" and it.get("secret", false)):
			continue  # a pact the spies haven't found is not drawn
		var a := int(it.get("from", -1))
		var b := int(it.get("to", -1))
		schemes["%d:%d" % [mini(a, b), maxi(a, b)]] = SCHEME[k]
	_set_politics(players, colour, by_name)
	var sig := str(hash(owners)) + str(hash(wars)) + str(hash(truces)) + str(hash(sworn)) + str(hash(schemes))
	if sig == _realm_sig:
		return
	_realm_sig = sig
	var pt := Time.get_ticks_usec()
	# Only what changed is read and repainted (npc-perf: the whole map redrawn on
	# every change held a frame over a second): a row of the owners is parsed again
	# only if its text changed; a tile is repainted only if its owner changed, it
	# borders one that did, or (when the houses' standing changed) it lies on a border.
	# A change of a house's colour or oath repaints the whole map, as before.
	var look_sig := str(hash(sworn)) + str(hash(colour))
	var rel_sig := str(hash(wars)) + str(hash(truces)) + str(hash(schemes))
	var full: bool = _realm_img == null or _war_img == null or _realm_ids.size() != _t.height or look_sig != _look_sig
	var ids: Array = [] if full else _realm_ids.duplicate()
	if full:
		ids.resize(_t.height)
	var moved: Array[Vector2i] = []
	for y in _t.height:
		var row := String(owners[y])
		if not full and y < _realm_rows.size() and _realm_rows[y] == row:
			continue
		var cells := []
		for v in row.split(","):
			cells.append(-1 if v == "-" or v == "" else int(v))
		if not full:
			var old: Array = ids[y]
			for x in maxi(old.size(), cells.size()):
				if (old[x] if x < old.size() else -1) != (cells[x] if x < cells.size() else -1):
					moved.append(Vector2i(x, y))
		ids[y] = cells
	_realm_rows = owners.duplicate()
	var was_ids := _realm_ids
	_realm_ids = ids
	var owner_at := func(x: int, y: int) -> int:
		return ids[y][x] if y >= 0 and y < _t.height and x >= 0 and x < (ids[y] as Array).size() else -1
	# The houses' standing, per tile: r = at war with a neighbour across the border,
	# g = under a truce with one, b = the owner is sworn to the crown, a = a scheme
	# with that neighbour (SCHEME; 1 for none).
	var paint := func(realm: Image, war: Image, x: int, y: int) -> void:
		var o: int = owner_at.call(x, y)
		var col: Color = colour.get(o, Color(0, 0, 0, 0))
		realm.set_pixel(x, y, Color(col.r, col.g, col.b, (o + 1) / 64.0) if o >= 0 and col.a > 0.0 else Color(0, 0, 0, 0))
		var st := Color(0, 0, 1.0 if o >= 0 and sworn.get(o, false) else 0.0, 1)
		var edge := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: int = owner_at.call(x + d.x, y + d.y)
			if o < 0 or n < 0 or n == o:
				continue
			edge = true
			if n in wars.get(o, []):
				st.r = 1.0
			elif n in truces.get(o, []):
				st.g = 1.0
			if schemes.has("%d:%d" % [mini(o, n), maxi(o, n)]):
				st.a = schemes["%d:%d" % [mini(o, n), maxi(o, n)]]
		war.set_pixel(x, y, st)
		if edge:
			_borders[Vector2i(x, y)] = true
		else:
			_borders.erase(Vector2i(x, y))
	var realm: Image
	if full:
		realm = Image.create(_t.width, _t.height, false, Image.FORMAT_RGBA8)
		_war_img = Image.create(_t.width, _t.height, false, Image.FORMAT_RGBA8)
		_borders = {}
		for y in _t.height:
			for x in _t.width:
				paint.call(realm, _war_img, x, y)
	else:
		realm = _realm_img.duplicate() as Image  # the flood below needs the one before
		var todo := {}
		for t in moved:
			for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = t + d
				if q.x >= 0 and q.y >= 0 and q.x < _t.width and q.y < _t.height:
					todo[q] = true
		if rel_sig != _rel_sig:
			for t in _borders.keys():
				todo[t] = true
		for t in todo:
			paint.call(realm, _war_img, t.x, t.y)
	_look_sig = look_sig
	_rel_sig = rel_sig
	var realm_tex := ImageTexture.create_from_image(realm)
	if full or _war_live == null:
		_war_live = ImageTexture.create_from_image(_war_img)
	else:
		_war_live.update(_war_img)
	var war_tex := _war_live
	standing_tex = war_tex  # the minimap draws the same seams from this one texture
	_t._land_mat.set_shader_parameter("realm_tex", realm_tex)
	_t._land_mat.set_shader_parameter("war_tex", war_tex)
	if _t.land3d:
		var stages := flood_stages(was_ids, ids, _realm_img, realm)
		if stages.is_empty():
			_t.land3d.set_realm(realm_tex, realm_tex, war_tex, {})
		for st in stages:
			_t.land3d.set_realm(st[0], st[1], war_tex, st[2])
	_realm_img = realm
	preload("res://scripts/perf_tools.gd").add("borders", Time.get_ticks_usec() - pt)


## The land's scars (the bridge's marks: where men died, a town was stormed
## or razed) as one texel per tile for Terrain3D's shader (_t.land3d.set_scars):
## r = how hard it burned, g = the season it happened, b = the seasons it
## takes to heal. The shader fades each by its age, so nothing is repainted
## as they heal. A battle burns its own tile; a town its tile and the ring
## round it, fainter out. How long a battle's or a sack's scar shows is the
## bridge's (each mark's `seasons`, server.js MARK_SEASONS); a razed town's
## ruin stands until the bridge drops it, and the scorched ring round it heals
## in RAZED_BURN seasons. SCAR keeps only the look: [how hard, how far].
const SCAR := {"battle": [0.75, 0], "sack": [1.0, 1], "razed": [1.0, 1]}
static var RAZED_BURN: float = preload("res://scripts/data.gd").num("map", "razed_burn", 16.0)


## The seasons a mark's burn takes to heal: the bridge's for a battle or a sack,
## RAZED_BURN for the ground round a ruin.
static func scar_heals(m: Dictionary) -> float:
	if String(m.get("kind", "")) == "razed" or m.get("seasons") == null:
		return RAZED_BURN
	return float(m["seasons"])
var _scar_sig := ""


func set_marks(marks: Array, turn: int) -> void:
	if _t.land3d == null or _t.land3d.land == null or _t.width == 0:
		return
	var sig := str(hash(marks)) + str(turn)
	if sig == _scar_sig:
		return
	_scar_sig = sig
	var img := Image.create(_t.width, _t.height, false, Image.FORMAT_RGBAF)
	var left := func(c: Color) -> float:  # what still shows of a scar
		return c.r * clampf(1.0 - (turn - c.g) / maxf(c.b, 1.0), 0.0, 1.0) if c.b > 0.0 else 0.0
	for m in marks:
		var kind := String(m.get("kind", ""))
		if not SCAR.has(kind):
			continue
		var sc: Array = SCAR[kind]
		var x0 := int(m.get("x", -1))
		var y0 := int(m.get("y", -1))
		var reach: int = sc[1]
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var x := x0 + dx
				var y := y0 + dy
				if x < 0 or y < 0 or x >= _t.width or y >= _t.height:
					continue
				var k := 1.0 if dx == 0 and dy == 0 else 0.55
				var c := Color(float(sc[0]) * k, float(m.get("turn", turn)), scar_heals(m), 1.0)
				if left.call(c) > left.call(img.get_pixel(x, y)):
					img.set_pixel(x, y, c)
	_t.land3d.set_scars(ImageTexture.create_from_image(img), turn)


var _realm_ids := []  # the owner of every tile, as last shown
## The houses' standing per tile (r war, g truce, b sworn), as set_realm last drew it:
## the ground and the minimap both draw their border seams from it.
var standing_tex: Texture2D
var _realm_img: Image  # the house colours as last shown, for a flood to cross


## Where land changed hands since the last reading, flooded in stages: each
## patch of changed land (a town's fields, usually) floods from its own middle,
## FLOODS patches at a time; more wait for the next stage, so none pops. Each
## stage is [the colours after it, the colours before it, {at, reach}]. None
## (shown at once) on the first reading or when much of the realm changed.
const FLOODS := 8
static func flood_stages(was: Array, now: Array, was_img: Image, now_img: Image) -> Array:
	if was.size() != now.size() or was.is_empty() or was_img == null or was_img.get_size() != now_img.get_size():
		return []
	var changed := {}
	for y in now.size():
		var a: Array = was[y]
		var b: Array = now[y]
		for x in mini(a.size(), b.size()):
			if a[x] != b[x]:
				changed[Vector2i(x, y)] = true
	if changed.is_empty() or changed.size() > 400:
		return []
	# Patches: changed tiles that touch, corners included.
	var patches: Array = []
	var seen := {}
	for start in changed:
		if seen.has(start):
			continue
		var patch: Array[Vector2i] = []
		var todo: Array[Vector2i] = [start]
		seen[start] = true
		while not todo.is_empty():
			var t: Vector2i = todo.pop_back()
			patch.append(t)
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var n := t + Vector2i(dx, dy)
					if changed.has(n) and not seen.has(n):
						seen[n] = true
						todo.append(n)
		patches.append(patch)
	patches.sort_custom(func(p, q): return p.size() > q.size())
	var out: Array = []
	var work := was_img.duplicate() as Image
	var before: Texture2D = ImageTexture.create_from_image(work)
	for k in range(0, patches.size(), FLOODS):
		var at := PackedVector2Array()
		var reach := 0.0
		for patch in patches.slice(k, k + FLOODS):
			var mid := Vector2.ZERO
			for t in patch:
				mid += Vector2(t) + Vector2(0.5, 0.5)
				work.set_pixelv(t, now_img.get_pixelv(t))
			mid /= patch.size()
			at.append(mid)
			for t in patch:
				reach = maxf(reach, (Vector2(t) + Vector2(0.5, 0.5)).distance_to(mid))
		var after: Texture2D = ImageTexture.create_from_image(work)
		out.append([after, before, {"at": at, "reach": reach}])
		before = after
	return out


## 0 down among the streets, 1 looking at the whole realm.
var _realm_mix := -1.0
func set_realm_mix(v: float) -> void:
	if absf(v - _realm_mix) <= 0.002:
		return
	_realm_mix = v
	if _t._land_mat:
		_t._land_mat.set_shader_parameter("realm_mix", v)
	if _t.land3d:
		_t.land3d.set_realm_mix(v)
