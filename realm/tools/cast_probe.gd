extends SceneTree
## The cast's import guard (no GPU): every Meshy body in realm/data/cast.json is retargeted onto the shared humanoid
## skeleton at import (its .import maps PATH:Armature/Skeleton3D through res://assets/retarget/mixamo_map.tres, so
## Godot names it GeneralSkeleton with our bone names), its cloth mask is on disk when it declares one, and every
## street role has a body in the cast. A body that isn't retargeted is never cast (people.gd _usable) and the crowd
## silently loses it: 12 Nov, 14 of 16 had lost their bone map and the square was two bodies and kit outfits.
## Prints one CAST line per body and per role; exits 1 on any failure.
##   arch -arm64 godot --headless --path realm -s res://tools/cast_probe.gd

const BONES := ["Hips", "Spine", "Chest", "Head", "LeftUpperArm", "RightUpperArm", "LeftFoot", "RightFoot"]
## The roles the street draws from the cast (people.gd make: a role the cast covers is the cast's alone).
const ROLES := {"peasant": ["m", "f"], "townsfolk": ["m", "f"], "soldier": ["m"], "archer": ["m"], "clergy": ["m"]}


func _init() -> void:
	var cast: Dictionary = preload("res://scripts/data.gd").value("cast", "members", {})
	var fails := 0
	var have := {}  # role -> sexes with a usable adult body
	for body in cast:
		var m: Dictionary = cast[body]
		var path := "res://assets/people/mixamo/%s/%s.gltf" % [body, body]
		var why := ""
		if not ResourceLoader.exists(path):
			why = "no model"
		else:
			var n: Node = (load(path) as PackedScene).instantiate()
			var sk := n.find_child("GeneralSkeleton", true, false) as Skeleton3D
			if sk == null:
				why = "not retargeted (no GeneralSkeleton: its .import has no bone map)"
			else:
				var missing := BONES.filter(func(b): return sk.find_bone(b) < 0)
				if not missing.is_empty():
					why = "bones missing: %s" % ", ".join(missing)
			n.free()
		var mask := String(m.get("mask", ""))
		if why == "" and mask != "" and not ResourceLoader.exists(mask):
			why = "mask missing: " + mask
		if why == "":
			if String(m.get("age", "")) == "":
				for r in m.get("roles", []):
					have[r] = have.get(r, []) + [String(m.get("sex", "m"))]
			print("CAST ok   %s" % body)
		else:
			fails += 1
			print("CAST FAIL %s: %s" % [body, why])
	for r in ROLES:
		for sex in ROLES[r]:
			if not sex in have.get(r, []):
				fails += 1
				print("CAST FAIL role %s has no %s body in the cast" % [r, sex])
	print("CAST VERDICT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
