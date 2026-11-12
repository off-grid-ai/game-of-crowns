extends SceneTree
## Fails (exit 1) when a farm beast can't live its idle life (animals.gd,
## realm/data/animals.json): a move in its life that its model neither has nor
## can be made for, or a head-down move that doesn't bring the head down to its
## share of standing height (or takes it under the ground). Kinds with no model
## in the game yet are listed, not failed. An asset validation pass, like
## scale_check.gd and feet_check.gd; no window.
## The set (animals.json set, Mac 2026-11-12: "one Meshy look across people, animals and props"): every farm kind
## in set.kinds is drawn from the one painted set (its model, as animals.gd make finds it, under set.dir), and every
## kind in set.walks has a walk its legs step in (animals.gd make and walk play "Walk": a kind without one glided).
##   arch -arm64 godot --headless --path realm -s res://tools/animals_check.gd

const Animals := preload("res://scripts/animals.gd")
const Real := preload("res://scripts/realistic.gd")
const Data := preload("res://scripts/data.gd")
## Models the catalogue doesn't hold as beasts yet (the deer stands in the woods' own code).
const ALSO := {"deer": "res://assets/q/deer-0.glb", "horse_q": "res://assets/q/horse-0.glb"}


func _initialize() -> void:
	var kinds: Dictionary = Data.value("animals", "kinds", {})
	var bad := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for kind in kinds:
		var path := String(kinds[kind].get("model", "")) if String(kinds[kind].get("model", "")) != "" else Real.path_of(kind)
		if path == "" or not ResourceLoader.exists(path):
			path = String(ALSO.get(kind, ""))
		if path == "" or not ResourceLoader.exists(path):
			print("ANIMALS %s: no model in the game yet (its life waits in data)" % kind)
			continue
		var model: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(model)
		var want: Array = (kinds[kind]["life"] as Array).map(func(m): return String(m[0]))
		var got := Animals.live(model, kind, rng)
		var notes := PackedStringArray()
		if got.size() < want.size():
			bad += 1
			notes.append("FAIL only %d of its %d moves play (%s)" % [got.size(), want.size(), ", ".join(got)])
		var sk := model.find_children("*", "Skeleton3D", true, false)
		for move in (kinds[kind].get("derive", {}) as Dictionary):
			var spec: Dictionary = kinds[kind]["derive"][move]
			if sk.is_empty():
				continue
			var skel: Skeleton3D = sk[0]
			var chain: Array = (spec["bones"] as Array).map(func(b): return skel.find_bone(String(b))).filter(func(i): return i >= 0)
			var head := skel.find_bone(String(spec["head"]))
			var frame := Animals.frame_of(skel, model)
			var turn := Animals.head_down(skel, chain, head, float(spec["to"]), frame, float(spec.get("muzzle", 1.0))) if head >= 0 and not chain.is_empty() else []
			if turn.is_empty():
				bad += 1
				notes.append("FAIL %s: the rig's neck or head bones weren't found (%s), or no turn lowers the head" % [move, ", ".join(range(mini(skel.get_bone_count(), 40)).map(func(i): return skel.get_bone_name(i)))])
				continue
			var ground := Animals.ground_of(skel, frame)
			var rest_h := Animals.head_height(skel, chain, head, turn[0], 0.0, frame, float(spec.get("muzzle", 1.0))) - ground
			var h := Animals.head_height(skel, chain, head, turn[0], turn[1], frame, float(spec.get("muzzle", 1.0))) - ground
			var share := h / rest_h
			# Down to its share; or, on a short-necked rig, as low as the neck goes (mostTurn), if that is clearly head-down.
			var reached := share <= float(spec["to"]) + 0.08
			var most := rad_to_deg(turn[1]) >= Data.num("animals", "mostTurn", 85.0) - 1.0
			var ok := share >= 0.0 and (reached or (most and share <= 0.75))
			if not ok:
				bad += 1
			notes.append("%s%s: muzzle to %d%% of its height (wants %d%%%s), neck and head turned %d deg" % ["" if ok else "FAIL ", move, int(round(share * 100)), int(float(spec["to"]) * 100),
				"" if reached else "; as low as its neck goes", int(round(rad_to_deg(turn[1])))])
		print("ANIMALS %s: %s; %s" % [kind, ", ".join(got), "; ".join(notes)])
		model.queue_free()
	var S: Dictionary = Data.value("animals", "set", {})
	for kind in S.get("kinds", []):
		var own := String(Data.value("animals", "kinds.%s.model" % kind, ""))
		var path := own if own != "" else Real.path_of(String(kind))
		if path == "" or not ResourceLoader.exists(path):
			bad += 1
			print("ANIMALS SET FAIL %s: no model in the game" % kind)
			continue
		var fails := bad
		if not path.begins_with(String(S.get("dir", "res://assets/beasts/"))):
			bad += 1
			print("ANIMALS SET FAIL %s: drawn from %s, not the painted set" % [kind, path])
		var model: Node3D = (load(path) as PackedScene).instantiate()
		var ap := model.find_children("*", "AnimationPlayer", true, false)
		if kind in S.get("walks", []) and (ap.is_empty() or Animals._clip(ap[0], "Walk") == ""):
			bad += 1
			print("ANIMALS SET FAIL %s: no Walk (it glides when driven)" % kind)
		if bad == fails:
			print("ANIMALS SET ok %s: %s" % [kind, path])
		model.free()
	for kind in S.get("next", []):
		print("ANIMALS SET next %s: still its kit model, joins the set next" % kind)
	print("ANIMALS %s: %d problems" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad > 0 else 0)
