extends RefCounted
## A host's shapes (the army layer's Formation, split from army.gd by the integration audit #12; Total War's
## line and Age of Empires' column; docs/research/army-and-town-rules.md section 1): a regiment's men laid out in
## a formation template (data/formations.json: line, column, wedge, shield_wall, loose, square, deck; 0 A.D.'s
## templates), every regiment's place in the host's line (melee in front, ranged behind, horse on the wings, the
## commander's in the front row's middle), and the march column's order, spacing and pace. Numbers in
## data/formations.json and data/army.json (line.*, column.gap/order, gap, jitter.*).

const Data := preload("res://scripts/data.gd")
const Troops := preload("res://scripts/troops.gd")


## A formation template's row (data/formations.json templates.<name>; 0 A.D.'s formation templates), line's if unknown.
static func template(name: String) -> Dictionary:
	var all: Dictionary = Data.value("formations", "templates", {})
	return all.get(name, all.get("line", {}))


## The template a regiment of `role` stands in on the field (formations.json field.<role>): foot in line, archers loose.
static func field_form(role: String) -> String:
	return String((Data.value("formations", "field", {}) as Dictionary).get(role, "line"))


## The men of a regiment in a formation template (formations.json templates.<form>), in its own frame (+Z its front):
## {at: positions, w, d, files, form}. As 0 A.D. lays a formation: its files from the template's width-to-depth
## ratio over the ground the men stand on (its spacing, times the template's separation), held between its least
## and most columns, so a 150-man regiment stands 8-12 abreast and 4-5 deep in line and 6-8 abreast in column,
## whatever drawPerMan draws (the files were cut by drawPerMan's root before: 2-3 abreast, a column on the field).
## A rect stands rank behind rank (shiftRows: every other rank half a file aside); a triangle is a wedge, each rank
## `widen` wider than the one before, to its most columns (its ratio unused). Each rank bows a little along its length and each man stands a little off his mark
## (jitter.place times its sloppiness), so the ranks read as men, not a printed grid. A short last rank is centred.
## Its w and d are the ground its men stand on (a file and a rank round them): the regiment's claim (army.gd _claim).
static func layout(r: Dictionary, form: String, rng: RandomNumberGenerator) -> Dictionary:
	var t := template(form)
	var count := int(r["figures"])
	var sep: Array = t.get("separation", [1.0, 1.0])
	var sf: float = float(r["sf"]) * float(sep[0])
	var sr: float = float(r["sr"]) * float(sep[1])
	var closed: Dictionary = t.get("closed", {})
	if not closed.is_empty():  # on the march or a deck: closed ranks, men shoulder to shoulder; a horse keeps its own room
		var horse: bool = Troops.of(r).mounted()
		sr = maxf(sr, float(closed.get("rankLeast", 0.0)))
		if horse:
			sr = minf(sr, float(closed.get("horseRankMost", sr)))
		else:
			sf = minf(sf, float(closed.get("fileMost", sf)))
			sr = minf(sr, float(closed.get("rankMost", sr)))
	var ratio := float(t.get("widthDepthRatio", 1.75))
	var files := roundi(sqrt(count * ratio * sr / maxf(sf, 0.001)))
	files = clampi(files, int(t.get("minColumns", 1)), int(t.get("maxColumns", 12)))
	if String(t.get("shape", "rect")) == "triangle":
		files = int(t.get("maxColumns", 12))  # a wedge widens rank by rank to its most
	files = clampi(files, 1, maxi(count, 1))
	var rows: Array = []  # men in each rank, front first
	if String(t.get("shape", "rect")) == "triangle":
		var left := count
		var n := 1
		while left > 0:
			rows.append(mini(n, left))
			left -= n
			n = mini(n + int(t.get("widen", 2)), files)
	else:
		for k in int(ceil(float(count) / files)):
			rows.append(mini(files, count - k * files))
	var ranks := rows.size()
	var shift: bool = t.get("shiftRows", false)
	var place := Data.num("army", "jitter.place", 0.014) * float(t.get("sloppiness", 1.0))
	var bow := Data.num("army", "jitter.rank", 0.03)
	var at := PackedVector3Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in ranks:
		var bend := [rng.randf_range(-bow, bow), rng.randf_range(0.0, TAU), rng.randf_range(0.15, 0.4)]
		var in_rank := int(rows[k])
		var off := sf * 0.25 * (1.0 if k % 2 == 1 else -1.0) if shift else 0.0
		for i in in_rank:
			var x := (float(i) - (in_rank - 1) * 0.5) * sf + off
			var z := -(float(k) - (ranks - 1) * 0.5) * sr
			z += float(bend[0]) * sin(x * float(bend[2]) * TAU / maxf(sf * files, 0.01) * 3.0 + float(bend[1]))
			var p := Vector3(x + rng.randf_range(-place, place), 0.0, z + rng.randf_range(-place, place))
			at.append(p)
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	# Centred on its ground (a wedge's ranks or a bow leave it off middle), so its rectangle is its men's.
	var mid := (lo + hi) * 0.5
	for s in at.size():
		at[s] -= Vector3(mid.x, 0.0, mid.y)
	return {"at": at, "w": hi.x - lo.x + sf, "d": hi.y - lo.y + sr, "files": files, "form": form}


## Each man to his nearest free place in a new shape (0 A.D.'s formation: every member takes its closest free offset),
## so a reform doesn't send men through each other across the block: `to` reordered, man s to the place returned at s.
## Greedy by the men nearest their best place first; a regiment is a few dozen figures.
static func assign(from: PackedVector3Array, to: PackedVector3Array) -> PackedVector3Array:
	var n := mini(from.size(), to.size())
	var out := to.duplicate()
	if n < 2:
		return out
	var pairs: Array = []
	for s in n:
		for p in n:
			pairs.append([Vector2(from[s].x - to[p].x, from[s].z - to[p].z).length_squared(), s, p])
	pairs.sort_custom(func(a, b): return a[0] < b[0])
	var man_done := PackedByteArray()
	man_done.resize(n)
	var place_done := PackedByteArray()
	place_done.resize(n)
	var left := n
	for e in pairs:
		if man_done[e[1]] == 1 or place_done[e[2]] == 1:
			continue
		man_done[e[1]] = 1
		place_done[e[2]] = 1
		out[e[1]] = to[e[2]]
		left -= 1
		if left == 0:
			break
	return out


## Every regiment's place in the line, in the line's frame (x right, z forward, its middle at 0), by a battle order
## (data/battle_orders.json orders.<order>, the approved formation pictures in docs/art/battle_formations): its rows
## front to back, each up to `abreast` regiments of a role, `gap` before it; the horse on the wings, in reserve behind,
## or on one flank; regiments no row took in rows of two behind. Each regiment is told its line (r.line_no: 1 the front,
## 2 a second line that relieves it) and its post (r.post: row, wing, reserve, flank). The commander's regiment is the
## front row's middle. `packed` (across, between rows), when given, sets the gaps instead (a battle's field: troops
## packed a cell apart across and rank on rank, battle.json field.cells.packed). Returns {extent: the line's width and depth, commander: that regiment, order: the order's key}.
static func line_places(regiments: Array, order := "", mirror := false, packed := Vector2(-1.0, -1.0)) -> Dictionary:
	var gap := packed.x if packed.x >= 0.0 else Data.num("army", "gap", 0.35)
	var row_gap := packed.y if packed.y >= 0.0 else Data.num("army", "line.rowGap", 0.7)
	var wing_gap := Data.num("army", "line.wingGap", 0.6)
	var orders: Dictionary = Data.value("battle_orders", "orders", {})
	if not orders.has(order):
		order = String(Data.value("battle_orders", "default", "line"))
	var spec: Dictionary = orders.get(order, {"rows": [], "horse": "wings"})
	# Every troop stands in the row its kind names (troop.gd line_row): horse in the front row with the foot.
	var left_by: Dictionary = {"melee": [], "ranged": []}
	for r in regiments:
		(left_by[Troops.of(r).line_row()] as Array).append(r)
	var rows: Array = []  # [regiments, gap before, line]
	for row in (spec.get("rows", []) as Array):
		var role := String(row.get("role", "melee"))
		var pool: Array = left_by.get(role, [])
		if pool.is_empty() and role == "melee":
			pool = left_by["ranged"]  # no foot of the line: whatever foot is left stands its front
		var n := mini(int(row.get("abreast", 2)), pool.size())
		if n == 0:
			continue
		rows.append([pool.slice(0, n), row_gap if packed.y >= 0.0 else float(row.get("gap", row_gap)), int(row.get("line", 0))])
		for k in n:
			pool.pop_front()
	for role in ["melee", "ranged"]:  # what no row took: rows of two behind
		var pool: Array = left_by[role]
		for i in range(0, pool.size(), 2):
			rows.append([pool.slice(i, i + 2), row_gap, 0])
	var z := 0.0
	var wide := 0.0
	var commander: Dictionary = {}
	for ri in rows.size():
		var row: Array = rows[ri][0]
		if ri > 0:
			z -= float(rows[ri][1])
		var deep := 0.0
		var span := 0.0
		for r in row:
			deep = maxf(deep, float(r["line"]["d"]))
			span += float(r["line"]["w"]) + gap
		span -= gap
		var x := -span * 0.5
		for r in row:
			var w := float(r["line"]["w"])
			r["place"] = Vector2(x + w * 0.5, z - deep * 0.5)
			r["line_no"] = int(rows[ri][2])
			r["post"] = "row"
			x += w + gap
		if ri == 0:
			commander = row[row.size() / 2]
		wide = maxf(wide, span)
		z -= deep
	var depth := -z
	# The line's middle at 0. A host that faces another is laid the other way round (mirror), so the two lines are the
	# same line seen from each side: every block stands square before the block across from it, horse before horse.
	for r in regiments:
		var pl: Vector2 = (r.get("place", Vector2.ZERO) as Vector2) + Vector2(0.0, depth * 0.5)
		r["place"] = Vector2(-pl.x, pl.y) if mirror else pl
	return {"extent": Vector2(wide, depth), "commander": commander, "order": order}


## The host's regiments in column.order (by role), each given its place in the column (off: its middle's distance
## behind the head, column.gap between regiments) and the host's pace (its slowest regiment's).
static func column_order(regiments: Array) -> Array:
	var order: Array = Data.value("army", "column.order", ["cavalry", "melee", "ranged"])
	var sorted := regiments.duplicate()
	var rank := func(r: Dictionary) -> int: return order.find(r["role"])
	sorted.sort_custom(func(a, b): return int(rank.call(a)) < int(rank.call(b)) if int(rank.call(a)) != int(rank.call(b)) else int(a["id"]) > int(b["id"]))
	var gap := Data.num("army", "column.gap", 0.3)
	var off := 0.0
	var slowest := INF
	for r in sorted:
		slowest = minf(slowest, float(r["speed"]))
	for r in sorted:
		off += float(r["column"]["d"]) * 0.5
		r["off"] = off
		off += float(r["column"]["d"]) * 0.5 + gap
		r["speed"] = slowest  # the host marches at its slowest regiment's pace
	return sorted


## The column's length: every regiment's column depth and the gaps between them.
static func column_length(regiments: Array) -> float:
	var gap := Data.num("army", "column.gap", 0.3)
	var n := 0.0
	for r in regiments:
		n += float(r["column"]["d"]) + gap
	return n
