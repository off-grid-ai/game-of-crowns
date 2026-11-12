extends SceneTree
## A guard: Kingsmere's square is built from its Meshy set (docs/research/meshy-square-set.md; Mac: "I still don't see
## the meshy stuff integrated"). The square's landmarks resolve to the set's pieces (the well, the King's statue, the
## market stalls, the smithy, the square's cart), and every house the crown raises facing its square or along its
## main streets resolves to the set's houses by its wealth (cottage, townhouse, merchant house), while a lane's house
## and another town's stay the kit's; every rank's square centrepiece is the set's too. Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/square_set_probe.gd

const Real := preload("res://scripts/realistic.gd")
const TownTiers := preload("res://scripts/town_tiers.gd")


func _init() -> void:
	var fail := 0
	var meshy := 0
	var kit := 0
	for c in ["well", "square_statue", "market_stall", "forge"]:
		var n := Real.one(c)
		var ok := n.begins_with("meshy_sq_")
		print("CHECK square landmark %s -> %s: %s" % [c, n, "meshy" if ok else "KIT"])
		if ok:
			meshy += 1
		else:
			kit += 1
			fail += 1
	var cart: Node3D = Real.meshy_piece("square_cart")
	var cart_path := cart.scene_file_path if cart else "none"
	var cart_ok := cart_path.contains("sq_cart")
	print("CHECK square landmark square_cart -> %s: %s" % [cart_path, "meshy" if cart_ok else "KIT"])
	if cart_ok:
		meshy += 1
	else:
		kit += 1
		fail += 1
	if cart:
		cart.free()
	var houses := ["house_hovel", "house_poor", "house_rich", "house_merchant", "house_burgher", "house_corner"]
	var tiers = TownTiers.new(1, false)
	var has_front: bool = tiers.has_method("front_set")
	for comp in houses:
		var kind := Real.one(comp)
		for zone in ["square", "main"]:
			var got := String(tiers.call("front_set", "crown", zone, kind)) if has_front else kind
			var ok := got.begins_with("meshy_sq_")
			print("CHECK crown %s front %s (%s) -> %s: %s" % [zone, comp, kind, got, "meshy" if ok else "KIT"])
			if ok:
				meshy += 1
			else:
				kit += 1
				fail += 1
		for other in [["crown", "lane"], ["town", "square"]]:
			var stay := String(tiers.call("front_set", other[0], other[1], kind)) if has_front else kind
			if stay != kind:
				print("CHECK %s %s %s -> %s: FAIL (should stay the kit's)" % [other[0], other[1], comp, stay])
				fail += 1
	# Every rank's square heart and what stands beside it are the set's (round 11: a seat's centre was the kit's grey
	# fountain, square_fountain, "SUPER weird").
	var market: Dictionary = preload("res://scripts/data.gd").value("towns", "market", {})
	for rank in market:
		for knob in ["centre", "beside"]:
			var comp := String((market[rank] as Dictionary).get(knob, ""))
			if comp == "":
				continue
			var got := Real.one(comp)
			var ok := got.begins_with("meshy_sq_")
			print("CHECK %s square %s %s -> %s: %s" % [rank, knob, comp, got, "meshy" if ok else "KIT"])
			if ok:
				meshy += 1
			else:
				kit += 1
				fail += 1
	# No house-colour patches on the set's roofs (round 11: the importer's roof mask split Meshy's baked atlas face by face,
	# and the Crown's colour lay on the red tiles as smears). Only the statue keeps its mask (its banner, the bar Mac
	# liked: "this actually looks good").
	for piece in ["sq_townhouse", "sq_cottage", "sq_merchant_house", "sq_smithy", "sq_well"]:
		var path := "res://assets/meshy/%s/%s.glb" % [piece, piece]
		var n: Node = (load(path) as PackedScene).instantiate() if ResourceLoader.exists(path) else null
		var patches := 0
		if n:
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				var mesh: Mesh = (mi as MeshInstance3D).mesh
				for i in (mesh.get_surface_count() if mesh else 0):
					var m := mesh.surface_get_material(i)
					if m and m.resource_name.ends_with("_house"):
						patches += 1
			n.free()
		print("CHECK %s roof house-colour patches: %d (want 0)%s" % [piece, patches, "" if patches == 0 else ": FAIL"])
		if patches > 0:
			fail += 1
	print("CHECK square set: %d meshy, %d kit where the set belongs; %d fail" % [meshy, kit, fail])
	quit(1 if fail > 0 else 0)
