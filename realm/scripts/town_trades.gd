extends RefCounted
## A town's working buildings: which it has and where each belongs (towns.gd stands them).
## A trade stands where the town's real buildings call for it (the bridge's Barracks, Granary,
## Marketplace...) or where a town of that size would have it anyway, the way Manor Lords and
## Banished tie a workplace to its inputs: the forge on the main street, the armoury by the castle
## or barracks, stables by the inn toward the gate, the watermill on the water, the windmill on
## rising open ground by the fields, granary and barn at the edge, tannery and dyer downstream.
## Land comes in that order: landmarks and trades first, then the big and middle houses, and the
## small houses fill what is left (they are the first to give way).
## realm/data/towns.json trades; each component's work spots in realm/data/assets.json (work).

const Data := preload("res://scripts/data.gd")
const Real := preload("res://scripts/realistic.gd")


## The trades this town raises, in the order they claim land: [{component, where, t, model}],
## `model` the catalogue model that will draw it (seeded by the town, so the same every run).
static func plan(size: int, buildings: Array, seat: bool, seed: int) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for row in Data.value("towns", "trades.list", []):
		if not row is Dictionary:
			continue
		var r: Dictionary = row
		var needs: Array = r.get("needs", [])
		var by_building := needs.any(func(b): return String(b) in buildings)
		var by_size := size >= int(r.get("min_size", 99))
		var by_seat := seat and bool(r.get("seat", false))
		if not (by_building or by_size or by_seat):
			continue
		var models: Array = Real.variants(String(r["component"])).filter(func(n): return Real.footprint(String(n)) != Vector2.ZERO)
		if models.is_empty():
			continue  # nothing in this build draws it
		out.append({"component": String(r["component"]), "where": String(r.get("where", "edge")), "t": r.get("t", [0.15, 0.6]), "model": String(models[rng.randi() % models.size()])})
	return out


## Where its people work, town-local: the component's work spots (assets.json
## components.<id>.work_front: {name: [across, out] or [across, out, up]} metres, `out` from its front
## wall's line, negative inside) turned with the building standing at `at` (town-local), its front
## looking along `face`, `foot` its footprint (game units). Named as works.gd's spots are. A Meshy piece standing
## in for it (model "meshy_<piece>") has its own layout: meshy.json pieces.<piece>.work_front, when given (the
## Meshy forge's anvil stands out on its paved yard, not inside the front wall).
static func work_spots(component: String, at: Vector3, face: Vector3, foot: Vector2, model := "") -> Dictionary:
	var spots := {}
	var c: Dictionary = Data.value("assets", "components", {}).get(component, {})
	var along := Vector3(-face.z, 0, face.x)
	var given: Dictionary = c.get("work_front", {})
	if model.begins_with("meshy_"):
		var piece: Dictionary = Data.value("meshy", "pieces", {}).get(model.substr(6), {})
		if piece.has("work_front"):
			given = piece["work_front"]
	var k_m := Real.S * Real.built_scale(model)  # a kit trade built smaller (house_kit.scale_tiers): its spots with it
	for k in given:
		var m: Array = given[k]
		if m.size() < 2:
			continue
		var up := float(m[2]) if m.size() > 2 else 0.0
		spots[String(k)] = at + along * float(m[0]) * k_m + face * (foot.y * 0.5 + float(m[1]) * k_m) + Vector3.UP * up * k_m
	return spots


## The trade it houses, as works.gd names trades (assets.json components.<id>.trade), "" for none.
static func trade_of(component: String) -> String:
	return String(Data.value("assets", "components", {}).get(component, {}).get("trade", ""))
