extends "res://scripts/scene_kind.gd"
## A siege and its storming (scene_kinds.gd "siege", "storm"): a host's camp at a town's walls (siege_camp.gd), its
## engines, the defenders on the walls and the assault parties (army_assault.gd); kept while the bridge reports the
## siege, broken up a turn and a half after. A storm is Freeciv's assault on it (campaigns.js stormScene), pitched
## first when none stands there yet, ending as Freeciv decided. One of these serves both kinds (scenes.kind).

const ArmyAssault := preload("res://scripts/army_assault.gd")
const Ground := preload("res://scripts/ground.gd")  # the one answer to where a body may stand
const Awareness := preload("res://scripts/awareness.gd")
const Data := preload("res://scripts/data.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const SiegeCamp := preload("res://scripts/siege_camp.gd")

var sieges := {}  # city id -> {root, until, front, assault}: one camp per besieged town, kept while the host stays


func play(s: Dictionary, at: Vector3, houses: Dictionary) -> Node3D:
	var city := int(s["city"])
	var town_size := 4
	for c in Awareness.store().rec("cities", []):
		if int(c["id"]) == city:
			town_size = int(c.get("size", 4))
	var approach: Vector3 = stage.terrain.world_pos(float(s.get("ax", s["x"])), float(s.get("ay", s["y"])))
	var turn := int(s.get("turn", 0))
	besiege(city, at, approach, town_size, int(s.get("engines", 0)), houses.get(int(s.get("owner", -1)), {}), houses.get(int(s.get("defender", -1)), {}), Awareness.season_seconds,
			maxi(0, turn - int(s.get("since", turn))))  # seasons it has run (bridge campaigns.js since): its works grow
	var how: Dictionary = Awareness.store().siege_of(city)  # a great house's way at these walls after a failed storm (bridge siegecraft.js)
	if sieges.has(city) and is_instance_valid(sieges[city].get("camp")):
		sieges[city]["camp"].approach(String(how.get("approach", "") if how.get("approach") != null else ""), int(how.get("dug", 0)))
	if String(s["kind"]) == "storm":
		storm(city, bool(s.get("taken", false)))
	return null


## A host at a town's walls: its camp spreads in an arc on the side it came
## from, engines throw stones over the walls, assault parties rush the walls
## and fall back, and the defenders hold the line. The camp stays while the
## bridge keeps reporting the siege, and breaks up a turn and a half after.
func besiege(id: int, at: Vector3, approach: Vector3, size: int, engines: int, foe: Dictionary, held: Dictionary, turn_secs: float, seasons := 0) -> void:
	if sieges.has(id) and is_instance_valid(sieges[id]["root"]):
		sieges[id]["until"] = Time.get_ticks_msec() / 1000.0 + turn_secs * 1.5
		if is_instance_valid(sieges[id].get("camp")):
			sieges[id]["camp"].works(seasons)  # another season: the works grow
		return
	if not stage._towns_up():
		# Pitched once the town stands; until then, where it will be.
		sieges[id] = {"root": null, "until": 0.0, "front": stage.ground(approach)}
		stage.get_tree().create_timer(1.0).timeout.connect(besiege.bind(id, at, approach, size, engines, foe, held, turn_secs, seasons))
		return
	var root := Node3D.new()
	root.name = "Siege"
	root.set_meta("fallen", [])  # the dead lie clear of each other, never in a heap
	stage.add_child(root)
	sieges[id] = {"root": root, "until": Time.get_ticks_msec() / 1000.0 + turn_secs * 1.5}
	# The siege's dead are carried off after a minute, so the living never fight on them.
	var sweep := Timer.new()
	sweep.wait_time = 10.0
	root.add_child(sweep)
	sweep.timeout.connect(func():
		var now := Time.get_ticks_msec()
		for n in root.get_children():
			if n is Node3D and n.has_meta("dead"):
				if not n.has_meta("dead_ms"):
					n.set_meta("dead_ms", now)
				elif now - int(n.get_meta("dead_ms")) > 60000:
					n.queue_free())
	sweep.start()
	var r: RandomNumberGenerator = stage.rng(at)
	# Each side in its banner's own colour (heraldry.gd field_colour, as its men in the field wear it): a house's colour
	# washed toward white (0.2 the besieger, 0.3 the held) put the camp's tents and the storm in candy pink beside a red
	# house's men (group render g1, the breach).
	var foe_col := Heraldry.field_colour(foe, Color.from_string(String(foe.get("color", "#7a2222")), Color.DARK_RED))
	var held_col := Heraldry.field_colour(held, Color.from_string(String(held.get("color", "#888")), Color.GRAY))
	# The siege stands outside where the town really stands: its houses' outermost corner (round 2's
	# ring streets and packed plots reach past the old size rule), so the wall, the breach, the band of
	# engines and the camp are out on open ground with nothing built between them and the camera.
	var reach := maxf(clampf(1.6 + size * 0.32, 2.0, 6.0), stage._town_extent(id) + Data.num("siege", "clear_of_town", 0.25))
	var wall := reach + 0.35
	var out := Vector3(approach.x - at.x, 0, approach.z - at.z)
	var want := atan2(out.z, out.x) if out.length() > 0.01 else r.randf() * TAU
	var camp_r := wall + Data.num("siege", "band", 6.0)  # the camp line: room for the engines, the host and the parties (siege.json band)
	var base := _camp_side(at, want, wall, camp_r)
	var arc := func(a: float, rad: float) -> Vector3:
		return stage.ground(at + Vector3(cos(base + a), 0, sin(base + a)) * rad)
	sieges[id]["front"] = arc.call(0.0, wall + 0.6)
	# Seen from behind the camp, on the open ground it was pitched on, over the
	# engines and companies to the walls.
	stage.framing.emit(sieges[id]["front"], 4.5, PI / 2 - base)
	# The besiegers' companies are the storm's regiments (army_field.gd storm, raised with the assault below) and the
	# host in the field: no loose men stand about the camp (Mac 2026-11-15: single men scattered between the blocks).
	# The camp and its engines (siege_camp.gd): tents, palisade, fires, wagons, and the bridge's engines (Freeciv's
	# catapults and trebuchets at the walls) built on the spot and worked by their crews.
	var camp: Node3D = SiegeCamp.new()
	camp.pitch(stage, root, at, base, camp_r, foe_col, engines, r, foe)
	camp.works(seasons)
	sieges[id]["camp"] = camp
	# The garrison by lanes (research note step 9; Bannerlord's siege lanes, Stronghold's manned walls): every way the
	# besiegers come at the wall (each assault party's stretch, the ram's gate, the tower's face) gets a defender block
	# on the wall walk opposite it (walls.gd walk_toward): garrison.lane.men men side by side garrison.lane.file apart
	# along the walk, bows the share of them archers, facing out; with no wall in reach they stand on the ground behind
	# the line. Each block's archers shoot down its own lane, its spearmen meet whoever reaches the wall's foot there
	# and the tower's bridge when it docks.
	var gk: Dictionary = Data.value("siege", "garrison", {})
	var walls: Node = Engine.get_meta("stone_walls") if Engine.has_meta("stone_walls") else null
	var archers := []
	var spears := []  # the wall's spearmen, who fight back at whoever reaches its foot
	var up_top := []  # [man, his mark or null]: men on the walk, who fall when it gives way under them
	var lanes := []  # {at: the lane's wall point, archers: [marks], spears: [men], tower: the rolling tower's lane}
	var lane_at := [-0.25, 0.25]  # the two assault parties' stretches (their arc angles, _assault below)
	var lane_pts := lane_at.map(func(a): return arc.call(a, wall))
	for l in camp.lanes():
		lane_pts.append(l)
	var lk: Dictionary = gk.get("lane", {})
	var lane_men := int(lk.get("men", 6))
	var lane_file := float(lk.get("file", 0.1))
	for li in lane_pts.size():
		var lp: Vector3 = lane_pts[li]
		var la := wrapf(atan2(lp.z - at.z, lp.x - at.x) - base, -PI, PI)
		var lane := {"at": lp, "archers": [], "spears": [], "tower": li >= lane_at.size()}
		for i in lane_men:
			var a := la + (i - (lane_men - 1) * 0.5) * lane_file / maxf(wall, 0.1)
			var p: Vector3 = arc.call(a, wall - 0.3)
			var walk: Vector3 = walls.walk_toward(p, float(gk.get("reach", 1.5))) if walls else Vector3.INF
			if walk != Vector3.INF:
				p = walk
			else:
				p = stage.stand(p)
				if not stage._footing(p):
					continue
			var f: Node3D = stage.people.make(r, "soldier", held_col, "adult")
			f.position = p
			var face := (p - at).normalized()
			f.rotation.y = atan2(face.x, face.z)
			root.add_child(f)
			var bow := fmod(i * float(gk.get("bows", 0.67)), 1.0) < float(gk.get("bows", 0.67))
			stage.arm(f, "bow" if bow else "spear")
			stage.people.play(f, "Bow_Idle" if bow else "Sword_Idle", r.randf_range(0.9, 1.1))
			var mark: Variant = null
			if bow:
				mark = {"node": f, "alive": true, "kit": "bow", "engaged": false}
				archers.append(mark)
				lane["archers"].append(mark)
			else:
				spears.append(f)
				lane["spears"].append(f)
			if walk != Vector3.INF:
				up_top.append([f, mark])
		lanes.append(lane)
	# Assault parties rush the walls in turn under the archers' arrows, fight there, and fall back; fought by the
	# men in them (army_assault.gd, the army layer's close fight).
	var parties := []
	if OS.get_cmdline_user_args().has("--probe"):
		print("SIEGE staged: parties=%d" % 2)
	for party in 2:
		parties.append(_assault(arc, float(lane_at[party]), wall))  # each on its own lane, a defender block opposite
	var assault := ArmyAssault.new()
	assault.start(stage, root, r, foe_col, parties, [3.0, 9.0], held_col, at, foe)  # held_col: the block behind a breach; at: the town the storm torches; foe: whose standard goes up once it falls
	sieges[id]["assault"] = assault
	var loose := Timer.new()
	loose.wait_time = 2.6
	loose.autostart = true
	var starved := [false]  # hunger has reached the walls (the town's siege.hungry): once
	loose.timeout.connect(func():
		if not starved[0] and bool((Awareness.store().town(id).get_var(&"siege", {}, false) as Dictionary).get("hungry", false)):
			starved[0] = true
			_hungry_walls(archers, spears, r)
		var marks := []
		for men in parties:
			marks.append_array(men.filter(func(m): return m.get("out", false) and m["alive"]))
		if is_instance_valid(camp):
			marks.append_array(camp.marks())  # the engines' crews
		marks = marks.filter(func(m): return is_instance_valid(m["node"]))  # a man fallen and gone is no mark
		# A man on the walk where the wall has given way under him falls with it.
		for u in up_top:
			var f: Node3D = u[0]
			if is_instance_valid(f) and not f.has_meta("dead") and walls and is_instance_valid(walls) \
					and walls.walk_toward(f.global_position, 0.15) == Vector3.INF:
				if u[1] != null:
					u[1]["alive"] = false
				stage.die(f, "Death_Front", r)
		# Each lane's archers shoot down their own lane (the marks within garrison.lane.reach of it), or at any mark when
		# their lane is empty; its spearmen thrust at whoever is at the wall's foot below them, and at the tower's
		# bridge once it stands against their stretch.
		var lane_reach := float(lk.get("reach", 2.5))
		var tower_at: Vector3 = camp.tower_at_wall() if is_instance_valid(camp) else Vector3.INF
		for lane in lanes:
			var lp: Vector3 = lane["at"]
			var theirs := marks.filter(func(m): return stage._flat_gap(m["node"].global_position, lp) < lane_reach)
			if not (lane["archers"] as Array).is_empty() and not marks.is_empty():
				stage._arrows(root, lane["archers"], theirs if not theirs.is_empty() else marks, r)
			var docked: bool = tower_at != Vector3.INF and stage._flat_gap(tower_at, lp) < lane_reach
			for sp in lane["spears"]:
				if is_instance_valid(sp) and not sp.has_meta("dead") and (docked or theirs.any(func(m): return stage._flat_gap(m["node"].global_position, sp.global_position) < 0.6)):
					stage.people.play(sp, "Spear_Thrust" if r.randf() < 0.7 else stage.guard(r), r.randf_range(0.9, 1.15)))
	root.add_child(loose)
	_siege_watch(id)


## A town starved out (the King's siege, bridge campaigns.js starve; Total War's and Stronghold's starved garrison):
## hunger reaches the walls. Of the men up there, siege.json garrison.hungry.down sink down slumped and shoot no more
## (Defeated, then sat against the parapet); the rest stand on, hurting between volleys (Injured_Idle).
func _hungry_walls(archers: Array, spears: Array, r: RandomNumberGenerator) -> void:
	var k: Dictionary = (Data.value("siege", "garrison", {}) as Dictionary).get("hungry", {})
	var down := float(k.get("down", 0.45))
	var men := []
	for a in archers:
		men.append([a["node"], a])
	for sp in spears:
		men.append([sp, null])
	for i in men.size():
		var f: Node3D = men[i][0]
		if not is_instance_valid(f) or f.has_meta("dead"):
			continue
		if fmod(i * 0.618, 1.0) < down:  # spread along the wall, not one end of it
			if men[i][1] != null:
				men[i][1]["kit"] = ""  # no more volleys from him (scenes.gd _arrows looses only bows)
			spears.erase(f)
			stage.people.play(f, "Defeated", 1.0)
			stage.get_tree().create_timer(2.5).timeout.connect(func():
				if is_instance_valid(f) and not f.has_meta("dead"):
					stage.people.play(f, "Sitting_Ground", r.randf_range(0.8, 1.0)))
		else:
			stage.people.play(f, "Injured_Idle", r.randf_range(0.8, 1.0))


## The side a host camps on: open, dry, gentle ground, as near as possible to
## the way it came. Each direction is scored by how far it turns from that way
## and by the water and slope along its arc.
func _camp_side(at: Vector3, want: float, wall: float, camp_r: float) -> float:
	var best := want
	var best_score := INF
	for i in 24:
		var a := want + TAU * i / 24.0
		var score := absf(wrapf(a - want, -PI, PI)) * 0.6
		for k in 5:
			var aa := a + (k - 2) * 0.3
			var d := Vector3(cos(aa), 0, sin(aa))
			var p := at + d * camp_r
			if not Ground.on_land(p):
				score += 3.0
			score += absf(stage.terrain.height_at(p.x, p.z) - stage.terrain.height_at(at.x + d.x * wall, at.z + d.z * wall)) * 1.5
		if score < best_score:
			best_score = score
			best = a
	return best


## Six men leave the camp behind their raised shields, run the last stretch,
## fight at the foot of the walls and fall back, leaving a man or two there.
## The camp sends a fresh man in each one's place before the next rush.
## Between rushes they wait as one small block (assault.abreast men to a rank, at the army's one spacing, army.json
## spacing), facing the wall, not strung loose along the arc (Mac 2026-11-15: single men scattered between the
## regiments): at angle `a`, or the nearest step along the arc (assault.slide, radians, up to assault.slides steps
## either way) whose ground ground.gd says is free (no engine, camp piece or regiment). It holds no claim: its men
## are stood at their homes by scenes.stand (ground.gd nearest_clear), which a claim would push off them.
func _assault(arc: Callable, a: float, wall: float) -> Array:
	var men := []
	var home_r := wall + Data.num("siege", "assault.home_from_wall", 1.65)  # behind the engines' line, ahead of the host
	var abreast := int(Data.num("siege", "assault.abreast", 3))
	var file := Data.num("army", "spacing.file", 0.18)
	var rank := Data.num("army", "spacing.rank", 0.26)
	var ranks := ceili(6.0 / abreast)
	var hw := abreast * file * 0.5 + 0.05
	var hd := ranks * rank * 0.5 + 0.05
	var slide := Data.num("siege", "assault.slide", 0.04)
	var mid: Vector3 = arc.call(a, home_r)
	var at := a
	for k in int(Data.num("siege", "assault.slides", 8)) * 2 + 1:
		var aa := a + slide * ((k + 1) / 2) * (1.0 if k % 2 == 1 else -1.0)
		var c: Vector3 = arc.call(aa, home_r)
		var poly := _block(c, arc.call(aa, wall), hw, hd)
		if Ground.area_free(poly):
			mid = c
			at = aa
			break
	var inward: Vector3 = arc.call(at, wall) - mid
	inward.y = 0.0
	inward = inward.normalized()
	var across := Vector3(-inward.z, 0, inward.x)
	for i in 6:
		var off := (i - 2.5) * 0.06
		var home: Vector3 = stage.ground(mid + across * (float(i % abreast) - (abreast - 1) * 0.5) * file + inward * ((ranks - 1) * 0.5 - float(i / abreast)) * rank)
		men.append({"home": home, "foot": arc.call(at + off, wall + 0.12), "alive": true, "kit": "sword", "rank": 1})
	return men  # army_assault.gd raises the men and runs them


## A party's block round `c` (world XZ), `hw` across and `hd` deep, its front toward `toward`.
static func _block(c: Vector3, toward: Vector3, hw: float, hd: float) -> PackedVector2Array:
	var f := Vector2(toward.x - c.x, toward.z - c.z).normalized()
	var s := Vector2(-f.y, f.x)
	var m := Vector2(c.x, c.z)
	return PackedVector2Array([m - s * hw - f * hd, m + s * hw - f * hd, m + s * hw + f * hd, m - s * hw + f * hd])


## Breaks a camp up once the host has moved on.
## Freeciv's assault on the siege of town `id` (the storm scene; the shot harness's --siege=taken|held): its parties
## and massed host storm, and it ends as Freeciv decided (army_assault.gd storm). A siege still being pitched (its
## town not up yet) storms once it stands.
func storm(id: int, taken: bool) -> void:
	var s: Dictionary = sieges.get(id, {})
	if s.is_empty():
		return
	var a = s.get("assault")
	if a != null and is_instance_valid(a):
		a.storm(taken)
	else:
		stage.get_tree().create_timer(1.0).timeout.connect(storm.bind(id, taken))


func _siege_watch(id: int) -> void:
	var t := Timer.new()
	t.wait_time = 2.0
	t.autostart = true
	t.timeout.connect(func():
		if not sieges.has(id):
			return
		var s: Dictionary = sieges[id]
		if Time.get_ticks_msec() / 1000.0 > s["until"]:
			sieges.erase(id)
			if is_instance_valid(s["root"]):
				s["root"].queue_free())
	sieges[id]["root"].add_child(t)
