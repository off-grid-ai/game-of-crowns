extends RefCounted
## The view's tunables, read from realm/data/<name>.json (docs/TUNING.md): the one
## loader, so no script opens and parses its own file. The shape is Paradox's
## common/defines and RimWorld's Defs: the designer changes a number in a data
## file between sessions; the code reads it and never retypes it.
## A missing file or key keeps the caller's fallback (today's value), so a
## half-filled file never breaks the game.

static var _files := {}  # name -> its parsed Dictionary, read once


## The whole file, parsed once ({} when it's missing or malformed).
static func read(name: String) -> Dictionary:
	if not _files.has(name):
		var f := FileAccess.open("res://data/%s.json" % name, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f else null
		_files[name] = d if d is Dictionary else {}
	return _files[name]


## A value by its dotted path in a file ("hit.victors"), or the fallback.
static func value(name: String, path: String, fallback: Variant) -> Variant:
	var v: Variant = read(name)
	for k in path.split("."):
		v = (v as Dictionary).get(k) if v is Dictionary else null
	return fallback if v == null else v


## A colour as data writes it: [r, g, b] or [r, g, b, a] (0-1), or a string Godot reads ("#c8a050", "gold"); else the fallback.
## The one place a data colour becomes a Color (integration audit #18).
static func colour(v: Variant, fallback: Color) -> Color:
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if (v as Array).size() > 3 else 1.0)
	if v is String and v != "":
		return Color.from_string(v, fallback)
	return fallback


## A number by its dotted path, or the fallback.
static func num(name: String, path: String, fallback: float) -> float:
	var v: Variant = value(name, path, fallback)
	return float(v) if (v is float or v is int) else fallback
