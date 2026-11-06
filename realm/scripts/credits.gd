extends RefCounted
## Who made what the realm is built from, read from the licence files that ship
## beside each asset (Sketchfab's license.txt, the audio and blood records), so
## the Credits page stays true as assets come and go.

const ROOT := "res://assets"

## The works and tools the realm stands on that carry no licence file of their own.
const FOUNDATIONS := [
	["Freeciv", "the Freeciv project", "GPL 2.0", "runs the realm's turns, armies and towns"],
	["Azgaar's Fantasy Map Generator", "Azgaar", "MIT", "drew the land of Aldmere"],
	["Godot Engine", "Juan Linietsky, Ariel Manzur and contributors", "MIT", ""],
	["Terrain3D", "Cory Petkovsek, Roope Palmroos and contributors", "MIT", "the ground"],
	["Sky3D", "TokisanGames and contributors", "MIT", "the sky, sun and weather"],
	["Mixamo", "Adobe", "Mixamo licence", "people's movements and several characters"],
	["Boujie Water Shader", "Zach Bernal and contributors", "MIT", "the sea and lakes"],
	["Waterways", "Kasper Arnklit Frandsen", "MIT", "the rivers"],
	["Off Grid AI", "Off Grid AI", "", "the voices and words of the realm's people"],
	["Universal Base Characters, Fantasy Outfits, MegaKits", "Quaternius", "CC0", "townsfolk, their clothes, village and nature pieces"],
	["Castle Kit, Fantasy Town Kit, UI Pack", "Kenney", "CC0", "castle and town pieces"],
	["Ground textures", "Poly Haven", "CC0", "the earth, fields and roads"],
	["The Milky Way panorama", "ESO/S. Brunier", "CC BY 4.0", "the night sky"],
	["Phosphor Icons", "Phosphor Icons", "MIT", "the interface's icons"],
	["Geist, Geist Mono", "The Geist Project Authors", "OFL 1.1", "the interface's letters"],
	["EB Garamond", "The EB Garamond Project Authors", "OFL 1.1", "people's spoken words"],
	["Cinzel", "The Cinzel Project Authors", "OFL 1.1", ""],
	["Inter", "The Inter Project Authors", "OFL 1.1", ""],
]


## [{section, title, by, licence}] sorted by section, then title.
static func entries() -> Array:
	var out: Array = []
	for f in FOUNDATIONS:
		out.append({"section": "Built on", "title": f[0], "by": f[1], "licence": f[2], "note": f[3]})
	_walk(ROOT, out)
	_audio(out)
	out.sort_custom(func(a, b): return _key(a) < _key(b))
	# A work whose licence ships in two places (beside the model and its copy) is credited once.
	var seen := {}
	return out.filter(func(e):
		var k := "%s|%s|%s" % [e["section"], e["title"], e["by"]]
		if seen.has(k):
			return false
		seen[k] = true
		return true)


## The order the page reads in: what the realm runs on first, then its things.
const ORDER := ["Built on", "Buildings, trees and goods", "People", "Horses", "Arms", "Rooms", "Effects", "Music", "Sound", "Other"]
static func _key(e: Dictionary) -> String:
	return "%02d %s" % [ORDER.find(e["section"]), String(e["title"]).to_lower()]


static func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_walk(dir.path_join(sub), out)
	for file in d.get_files():
		var path := dir.path_join(file)
		if file == "license.txt":
			_sketchfab(path, out)
		elif file.begins_with("LICENSE_"):
			_record(path, out)


## Sketchfab's own licence file: "* title:", "* author:", "* license type:".
static func _sketchfab(path: String, out: Array) -> void:
	var f := {}
	for line in FileAccess.get_file_as_string(path).split("\n"):
		for key in ["title", "author", "license type"]:
			if line.begins_with("* %s:" % key):
				f[key] = _bare(line.substr(line.find(":") + 1))
	if f.has("title"):
		out.append({"section": _section_of(path), "title": String(f["title"]).trim_prefix("."), "by": f.get("author", ""), "licence": _licence(f.get("license type", "")), "note": ""})


## A source record: "Asset:", "Author:" and "Licence:" lines, or "Blood Splatter
## by ExileGL" with a "Source licence field: CC0" line.
static func _record(path: String, out: Array) -> void:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var f := {}
	for l in lines:
		for key in ["Asset", "Author", "Licence"]:
			if l.begins_with(key + ":"):
				f[key] = l.substr(key.length() + 1).strip_edges().get_slice(" — ", 0)
	if f.has("Asset"):
		out.append({"section": "Effects", "title": f["Asset"], "by": f.get("Author", ""), "licence": _licence(f.get("Licence", "")), "note": ""})
		return
	for i in lines.size():
		if " by " in lines[i] and not lines[i].begins_with("http"):
			var parts := lines[i].strip_edges().trim_prefix("# ").split(" by ", true, 1)
			var lic := ""
			for l in lines:
				if "licence" in l.to_lower() and ":" in l:
					lic = _licence(l.substr(l.find(":") + 1))
			out.append({"section": "Effects", "title": parts[0], "by": parts[1], "licence": lic, "note": ""})
			return


## The music and sounds, from the table in assets/audio/CREDITS.md.
static func _audio(out: Array) -> void:
	var path := ROOT.path_join("audio/CREDITS.md")
	if not FileAccess.file_exists(path):
		return
	var section := "Music"
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("## "):
			section = "Music" if "music" in line.to_lower() else "Sound"
		if not line.begins_with("| `"):
			continue
		var cells := line.split("|")
		if cells.size() < 7:
			continue
		out.append({"section": section, "title": cells[3].strip_edges(), "by": cells[4].strip_edges(), "licence": _licence(cells[5]), "note": ""})


static func _section_of(path: String) -> String:
	for pair in [["/interiors/", "Rooms"], ["/hero/", "People"], ["/people/", "People"], ["/cavalry/", "Horses"], ["/weapons/", "Arms"], ["/realistic/", "Buildings, trees and goods"]]:
		if pair[0] in path:
			return pair[1]
	return "Other"


## "Pixel Life (https://sketchfab.com/pixellife)" reads "Pixel Life".
static func _bare(s: String) -> String:
	s = s.strip_edges()
	var paren := s.find(" (http")
	return s.left(paren) if paren > 0 else s


## "CC-BY-4.0 (http://…)" reads "CC BY 4.0".
static func _licence(s: String) -> String:
	s = _bare(s).replace("CC-BY", "CC BY").replace("-SA", " SA").replace("-4.0", " 4.0").replace("-3.0", " 3.0")
	return "Sketchfab Standard" if s.to_upper().begins_with("SKETCHFAB") else s
