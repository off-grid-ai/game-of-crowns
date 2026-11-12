extends RefCounted
## Which house stands on a plot: the one decider for a town's houses (towns.gd asks it per plot).
## Wealth falls from the square outward, the way Manor Lords' burgage plots upgrade near the
## market and Anno 1800's residences tier up round the town centre: the square and the first
## stretch of the main streets hold merchants and burghers (a manor in a big town), the main
## streets further out townhouses, the lanes cottages, the edge hovels. A corner plot takes a
## rung up and a house built for two streets. No two neighbours on a street are the same model.
## Everything in realm/data/towns.json tiers (docs/TUNING.md).

const Data := preload("res://scripts/data.gd")
const Real := preload("res://scripts/realistic.gd")

var _rungs: Array = []  # per rung of the ladder (poorest first): its kit models that stand in this build
var _cfg: Dictionary = {}
var _size := 0
var _manors := 0
var _last := {}  # a street side's key -> the model last stood there
var _corner: Array = []  # corner houses' models


## `size`: the town's size; a seat counts as bigger (towns.json tiers.seat_size).
func _init(size: int, seat: bool) -> void:
	_cfg = Data.value("towns", "tiers", {})
	_size = size + (int(_cfg.get("seat_size", 3)) if seat else 0)
	for comp in _cfg.get("ladder", ["house_poor", "house_rich"]):
		_rungs.append(_built(String(comp)))
	_corner = _built(String(_cfg.get("corner", "")))
	# A rung this build has no models for (the downloaded set has no hovel, no manor) borrows its
	# nearest neighbour's, poorer first.
	for i in _rungs.size():
		if (_rungs[i] as Array).is_empty():
			for dist in range(1, _rungs.size()):
				for j in [i - dist, i + dist]:
					if j >= 0 and j < _rungs.size() and (_rungs[j] as Array).is_empty() == false and (_rungs[i] as Array).is_empty():
						_rungs[i] = _rungs[j]


## The house that stands in a kit tier's place for this rank and zone (towns.json fronts: the crown's square and
## main streets take the Meshy square set, by the tier's wealth); else `kind` itself.
static func front_set(rank: String, zone: String, kind: String) -> String:
	var r: Dictionary = (Data.value("towns", "fronts", {}) as Dictionary).get(rank, {})
	if not zone in (r.get("zones", []) as Array):
		return kind
	var to := String((r.get("map", {}) as Dictionary).get(Real.component_of(kind), ""))
	if to == "":
		return kind
	var vs: Array = _built(to)
	return String(vs[absi(kind.hash()) % vs.size()]) if not vs.is_empty() else kind


static func _built(comp: String) -> Array:
	return Real.variants(comp).filter(func(n): return Real.footprint(String(n)) != Vector2.ZERO)


## Whether the ladder has any house at all.
func any() -> bool:
	return _rungs.any(func(r): return not (r as Array).is_empty())


## The rungs' weights for a zone ("square", "main", "lane", "edge") at `t` (0 at the square,
## 1 at the town's edge), with rungs this town is too small for passed down to the one below.
func weights(zone: String, t: float) -> Array:
	var z = _cfg.get("wealth", {}).get(zone, [])
	var w: Array = []
	if z is Dictionary:
		var near: Array = z.get("near", [])
		var far: Array = z.get("far", near)
		for i in _rungs.size():
			w.append(lerpf(float(near[i]) if i < near.size() else 0.0, float(far[i]) if i < far.size() else 0.0, clampf(t, 0.0, 1.0)))
	else:
		for i in _rungs.size():
			w.append(float(z[i]) if z is Array and i < (z as Array).size() else (1.0 if i == 1 else 0.0))
	var mins: Array = _cfg.get("min_size", [])
	var most := int(_cfg.get("manor_most", 1))
	for i in range(w.size() - 1, 0, -1):
		var too_small := i < mins.size() and _size < int(mins[i])
		var full := i == w.size() - 1 and _manors >= most
		if too_small or full:
			w[i - 1] = float(w[i - 1]) + float(w[i])
			w[i] = 0.0
	return w


## The rung for a plot: by weight, a corner a rung up.
func rung(rng: RandomNumberGenerator, zone: String, t: float, corner := false) -> int:
	var w := weights(zone, t)
	var total := 0.0
	for x in w:
		total += float(x)
	var r := rng.randf() * total
	var at := 0
	for i in w.size():
		r -= float(w[i])
		if r <= 0.0:
			at = i
			break
	if corner:
		at = mini(at + int(_cfg.get("corner_up", 1)), w.size() - 2)  # a corner moves up, never to a manor
	return at


## The model for a plot. `key` names its street side, so the next plot there never repeats it.
func pick(rng: RandomNumberGenerator, zone: String, t: float, key := "", corner := false) -> String:
	var i := rung(rng, zone, t, corner)
	var pool: Array = _rungs[i] if i < _rungs.size() else []
	if corner and not _corner.is_empty() and rng.randf() < float(_cfg.get("corner_share", 0.7)):
		pool = _corner
	if pool.is_empty():
		return ""
	var choices: Array = pool.filter(func(n): return n != _last.get(key, ""))
	if choices.is_empty():
		choices = pool
	var kind: String = choices[rng.randi() % choices.size()]
	if key != "":
		_last[key] = kind
	if i == _rungs.size() - 1 and pool != _corner:
		_manors += 1
	return kind


## The rung a model stands on (-1 when it is not on the ladder): which houses may give way first.
func rung_of(kind: String) -> int:
	for i in _rungs.size():
		if kind in _rungs[i]:
			return i
	return -1
