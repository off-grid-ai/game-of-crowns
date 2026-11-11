extends RefCounted
## The court's painted faces (realm/assets/portraits/painted, made by
## tools/portraits/build.py from public-domain museum portraits; references CK2
## and King of Dragon Pass's painted faces). The one owner of who wears which
## face: a person gets the same face every time, drawn from the faces of their
## sex and time of life by their id: a child from children's faces (and only a
## child), the old from old faces, the rest from young and grown faces.

const DIR := "res://assets/portraits/painted/"
const OLD := 55
const CHILD := 16

static var _pool: Array = []  # sources.json's portraits


static func _load() -> void:
	if not _pool.is_empty():
		return
	var f := FileAccess.open(DIR + "sources.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	_pool = (d.get("portraits", []) if d is Dictionary else []) as Array


## A person's painted face (person: the bridge's sitter, with id, gender, age), or null.
static func face(person: Dictionary) -> Texture2D:
	_load()
	if _pool.is_empty():
		return null
	var sex := "f" if String(person.get("gender", "")) == "female" else "m"
	var years := int(person.get("age", 30))
	var child := years < CHILD
	var old := years >= OLD
	# Theirs first (sex and time of life), then their sex at any grown age: never a man's face on a woman,
	# never a child's face on a grown person.
	var picks: Array = _pool.filter(func(p): return p["sex"] == sex and bool(p.get("child", false)) == child \
		and (child or (p["age"] == "old") == old))
	if picks.size() < 3:
		picks = _pool.filter(func(p): return p["sex"] == sex and bool(p.get("child", false)) == child)
	if picks.is_empty():
		picks = _pool.filter(func(p): return not bool(p.get("child", false)))
	var p: Dictionary = picks[absi(hash(String(person.get("id", person.get("name", ""))))) % picks.size()]
	return load(DIR + String(p["file"])) as Texture2D
