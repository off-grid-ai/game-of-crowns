extends RefCounted
## A host's shapes (the army layer's Formation, split from army.gd by the integration audit #12; Total War's
## line and Age of Empires' column; docs/research/army-and-town-rules.md section 1): a regiment's men laid out in
## line or in march column, every regiment's place in the host's line (melee in front, ranged behind, horse on the
## wings, the commander's in the front row's middle), and the march column's order, spacing and pace. Numbers in
## data/army.json (line.*, column.*, gap, jitter.*).

const Data := preload("res://scripts/data.gd")


## The men of a regiment in a shape, in its own frame (+Z its front): {at: positions, w, d}. A line stands
## line.frontage men abreast at full strength, its files cut by the root of drawPerMan so a regiment drawn one figure
## for ten keeps its block's shape, the floor's figures (figureFloor) as more ranks behind; a column 4-6 (column.files); each rank bows a little along its length and each
## man stands a little off his mark, so the ranks read as men, not a printed grid. A short last rank is centred.
static func layout(r: Dictionary, shape: String, frontage: Variant, rng: RandomNumberGenerator) -> Dictionary:
	var count := int(r["figures"])
	var files: int
	var sf: float = r["sf"]
	var sr: float = r["sr"]
	if shape == "column":
		var cf: Array = Data.value("army", "column.files", [4, 6])
		files = rng.randi_range(int(cf[0]), int(cf[1]))
		sr = clampf(sr, Data.num("army", "column.rank", 0.14), Data.num("army", "column.rankMost", 0.32))  # closed ranks on the march, horse too
	else:
		var lf: Array = frontage if frontage is Array else (Data.value("army", "line.frontage", {}) as Dictionary).get(r["role"], [18, 25])  # a battle's regiments stand deeper
		# As wide as one figure for ten men stands (drawPerMan); the regiment's floor of figures (figureFloor) stands as
		# more ranks behind, so a small regiment reads as a deep block, not a long thin line.
		files = roundi(rng.randi_range(int(lf[0]), int(lf[1])) * sqrt(clampf(Data.num("army", "drawPerMan", 0.1), 0.001, 1.0)))
	files = clampi(files, 1, count)
	var ranks := int(ceil(float(count) / files))
	var place := Data.num("army", "jitter.place", 0.014)
	var bow := Data.num("army", "jitter.rank", 0.03)
	var bends: Array = []
	for k in ranks:
		bends.append([rng.randf_range(-bow, bow), rng.randf_range(0.0, TAU), rng.randf_range(0.15, 0.4)])
	var at := PackedVector3Array()
	for s in count:
		var k := s / files
		var in_rank := mini(files, count - k * files)
		var x := (float(s % files) - (in_rank - 1) * 0.5) * sf
		var z := -(float(k) - (ranks - 1) * 0.5) * sr
		var b: Array = bends[k]
		z += float(b[0]) * sin(x * float(b[2]) * TAU / maxf(sf * files, 0.01) * 3.0 + float(b[1]))
		at.append(Vector3(x + rng.randf_range(-place, place), 0.0, z + rng.randf_range(-place, place)))
	return {"at": at, "w": files * sf, "d": ranks * sr, "files": files}


## Every regiment's place in the line, in the line's frame (x right, z forward, its middle at 0): melee rows
## at the front (line.maxFront abreast, more rows behind), cavalry on the front row's wings, ranged rows behind
## the melee. The commander's regiment is the front row's middle. Returns {extent: the line's width and depth,
## commander: that regiment}.
static func line_places(regiments: Array) -> Dictionary:
	var gap := Data.num("army", "gap", 0.35)
	var row_gap := Data.num("army", "line.rowGap", 0.7)
	var wing_gap := Data.num("army", "line.wingGap", 0.6)
	var most := int(Data.num("army", "line.maxFront", 8))
	var melee: Array = regiments.filter(func(r): return r["role"] == "melee")
	var ranged: Array = regiments.filter(func(r): return r["role"] == "ranged")
	var horse: Array = regiments.filter(func(r): return r["role"] == "cavalry")
	if melee.is_empty():  # a host of archers and horse still stands a front
		melee = ranged
		ranged = []
	var rows: Array = []
	for list in [melee, ranged]:
		for i in range(0, list.size(), most):
			rows.append(list.slice(i, i + most))
	var z := 0.0
	var wide := 0.0
	var commander: Dictionary = {}
	for ri in rows.size():
		var row: Array = rows[ri]
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
			x += w + gap
		if ri == 0:
			commander = row[row.size() / 2]
			# The wings: horse outward from the front row's ends, left and right in turn.
			var left := -span * 0.5 - wing_gap
			var right := span * 0.5 + wing_gap
			for i in horse.size():
				var h: Dictionary = horse[i]
				var w := float(h["line"]["w"])
				if i % 2 == 0:
					h["place"] = Vector2(right + w * 0.5, z - deep * 0.5)
					right += w + gap
				else:
					h["place"] = Vector2(left - w * 0.5, z - deep * 0.5)
					left -= w + gap
			span = right - left
		wide = maxf(wide, span)
		z -= deep + row_gap
	var depth := -z - row_gap
	for r in regiments:  # the line's middle at 0
		r["place"] = (r["place"] as Vector2) + Vector2(0.0, depth * 0.5)
	return {"extent": Vector2(wide, depth), "commander": commander}


## The host's regiments in column.order (by role), each given its place in the column (off: its middle's distance
## behind the head, column.gap between regiments) and the host's pace (its slowest regiment's).
static func column_order(regiments: Array) -> Array:
	var order: Array = Data.value("army", "column.order", ["cavalry", "melee", "ranged"])
	var sorted := regiments.duplicate()
	sorted.sort_custom(func(a, b): return order.find(a["role"]) < order.find(b["role"]) if a["role"] != b["role"] else int(a["id"]) > int(b["id"]))
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
