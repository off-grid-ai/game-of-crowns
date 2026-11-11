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


## A number by its dotted path, or the fallback.
static func num(name: String, path: String, fallback: float) -> float:
	var v: Variant = value(name, path, fallback)
	return float(v) if (v is float or v is int) else fallback
