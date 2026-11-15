extends Node
## What the King can do about a piece of news: the one owner of that, and of "a threat to the King's town".
## Copied from Crusader Kings 3's alerts (each one carries its answers) and Warcraft III's "our town is under
## attack" (a horn, a line, the arrow, a key that answers it). Every answer is an order the King already has:
## a host order (host_command.gd's public select and order: POST /host/order), a decree (ui.decree_at: the
## bridge's /decree; each decree verb placed by its data row), the court (ui.open_matter, or ui.counsel_act's court),
## the tithe (ui.counsel_act), or the camera's jump-and-back (news.gd go_to). Nothing new is
## decided here; the bridge decides and says so.
##   verbs(entry) -> rows   what can be done about a news entry (a chronicle line, or a threat seen here), as the
##                          place stands now: [{verb, label, cost, enabled, why, tip, call}], best first; label carries the price
##                          ("Raise the levy · 20,000 crowns") or why it can't be done ("· the treasury can't pay");
##                          call() does it. The ticker and the drawer (chronicle_panel.gd) ask here.
##   buttons(entry)         the same rows as one row of buttons, ready to place.
##   threats                the King's towns a foe's host marches on, besieges or raids now (from the mirror:
##                          awareness war_hosts, cities' besieged, raids); a new one is news with its answers
##                          open, the horn, and the edge arrow on the town until the threat ends.
##   defend key             answers the latest threat (keys.gd "defend").
## Verbs per kind, their words and the threats' lines: realm/data/news_actions.json.

const Data := preload("res://scripts/data.gd")
const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")  # its CROWNS and crowns(): a price written one way
const FILE := "news_actions"

static var one: Node  # the realm's (for the ticker, which holds no realm of its own)

var main: Node
var threats := {}  # town id -> {kind: march|siege|raid, by, text, since (ms)}
var _latest := -1  # the town of the latest threat, for the defend key


## How long a caption with answers stays up (news_actions.json caption_seconds).
static func caption_seconds() -> float:
	return Data.num(FILE, "caption_seconds", 10.0)


static func apply(m: Node) -> void:
	var n := new()
	n.name = "NewsActions"
	n.main = m
	m.add_child(n)


func _ready() -> void:
	one = self
	while main.get("awareness") == null:
		await get_tree().process_frame  # main.gd makes the mirror a few startup steps after this is added
	main.awareness.synced.connect(_watch)
	main.awareness.cleared.connect(func():
		threats.clear()
		_latest = -1)


func _exit_tree() -> void:
	if one == self:
		one = null


# --- threats to the King's towns ---------------------------------------------------------------

## Each /world: which of the King's towns a foe's host is on now. A new one (or a march become a siege) is news.
func _watch() -> void:
	var aw: Node = main.awareness
	var crown := int(aw.rec("crownId", -1))
	if crown < 0:
		return
	var now := {}
	for wh in aw.war_hosts():
		var c: Dictionary = aw.city(int(wh.get("city", -1)))
		if not c.is_empty() and int(c.get("owner", -2)) == crown and not wh.get("home", false) and int(wh.get("owner", -1)) != crown:
			now[int(c["id"])] = {"kind": "march", "by": int(wh.get("owner", -1))}
	for c in aw.rec("cities", []):
		if int(c.get("owner", -2)) == crown and bool(c.get("besieged", false)):
			var by := int((aw.siege_of(int(c["id"])) as Dictionary).get("by", (now.get(int(c["id"]), {}) as Dictionary).get("by", -1)))
			now[int(c["id"])] = {"kind": "siege", "by": by}
	for r in aw.raids():
		var goal := int(r.get("goal", r.get("town", -1)))
		var c: Dictionary = aw.city(goal)
		if not c.is_empty() and _realm_town(c, crown) and not now.has(goal):
			now[goal] = {"kind": "raid", "by": -1}
	for id in now:
		var was: Dictionary = threats.get(id, {})
		if was.is_empty() or (String(was["kind"]) != "siege" and String(now[id]["kind"]) == "siege"):
			now[id]["text"] = _threat_words(now[id], aw.city(id))
			now[id]["since"] = Time.get_ticks_msec()
			threats[id] = now[id]
			_raise(id)
		else:
			now[id] = was
	threats = now
	if not threats.has(_latest):
		_latest = -1
		for id in threats:
			if _latest < 0 or int(threats[id]["since"]) > int(threats[_latest]["since"]):
				_latest = id
	# Newer news took the arrow and has gone stale: the threat still standing has it again, quietly.
	if _latest >= 0 and main.news.idle():
		var id := _latest
		main.news.point_at(_at(aw.city(id)), String(threats[id]["text"]), _go_call(id), func() -> bool: return threats.has(id))


func _threat_words(t: Dictionary, c: Dictionary) -> String:
	var house := String((main.awareness.houses_by_id().get(int(t.get("by", -1)), {}) as Dictionary).get("name", "A foe"))
	return String(Data.value(FILE, "threat_words." + String(t["kind"]), "{house} marches on {town}")).format({"house": house, "town": _town_name(c)})


## A town the crown answers for against raiders (Mac: "defend yourself? or does it auto defend?"; CK3's liege
## defends his vassals): the King's own, or a house's that isn't at war with the crown and isn't men without banners.
func _realm_town(c: Dictionary, crown: int) -> bool:
	var owner := int(c.get("owner", -2))
	if owner == crown:
		return true
	var pl := _player(owner)
	if pl.is_empty() or (pl.get("house", {}) is Dictionary and bool((pl["house"] as Dictionary).get("wild", false))):
		return false
	return not (pl.get("wars", []) as Array).has(String(Data.value(FILE, "crown_word", "the Crown")))


## A threat is news: its line in the corner with its answers open, the horn, and the arrow on the town (news.gd)
## until the threat ends. The camera stays where the King put it.
func _raise(id: int) -> void:
	_latest = id
	var t: Dictionary = threats[id]
	var e := {"kind": "attack", "text": String(t["text"]), "city": id, "crown": true, "open": true, "hold": Data.num(FILE, "attack_hold", 40.0), "turn": int(main.awareness.rec("turn", 0))}  # dated now: its season on the card, and its age
	main.ui.chronicle.show_news(e, true)
	main.sound.event("horn")
	var c: Dictionary = main.awareness.city(id)
	main.news.point_at(_at(c), String(t["text"]), _go_call(id), func() -> bool: return threats.has(id))


# --- what can be done about a piece of news ----------------------------------------------------

## The answers to a news entry ({kind, text, city?, thread?, ...}, as the chronicle has it): rows of
## {verb, label, cost (crowns, 0 for none), enabled, why, tip, call}, best first. Only what fits NOW is there:
##   the Hand's advised decree; a matter waiting at court, its own answers straight on the card (court_panel's options,
##   answered the one way: ui.petition_answered); what the place's state asks now (the mirror: a threat, a siege,
##   hunger, sickness, unrest, war with the crown, a cold lord; news_actions.json states); the story's title theme only
##   when the place says nothing; then the kind's own verbs. A verb whose condition no longer holds (news_actions.json
##   verbs.needs) is dropped: no Defend when nothing threatens, no Send relief once the plague has passed.
func verbs(entry: Dictionary) -> Array:
	var kinds: Dictionary = Data.value(FILE, "kinds", {})
	var kind := String(entry.get("kind", ""))
	var list: Array = (kinds.get(kind, kinds.get("other", ["go"])) as Array).duplicate()
	var first := []
	# The Hand's counsel names the decree it advises (bridge next.js act): that answer first.
	var act = entry.get("act")
	if act is Dictionary:
		var by_act: Dictionary = Data.value(FILE, "acts", {})
		if by_act.has(String(act.get("action", ""))):
			first.append(String(by_act[String(act["action"])]))
		if act.get("city") != null and entry.get("city") == null:
			entry = entry.duplicate()
			entry["city"] = act["city"]
	var c: Dictionary = main.awareness.city(int(entry["city"])) if entry.get("city") != null else {}
	var now := _now(c)
	# Fresh news of a foe at a town of the realm is a threat there, whoever's riders they are (a rival king's raiders
	# over the border, rivals.js, aren't Freeciv's raids the mirror sees): Defend and the levy answer it.
	var turn := int(main.awareness.rec("turn", 0))
	if kind in (Data.value(FILE, "threat_kinds", []) as Array) and not c.is_empty() and _realm_town(c, int(main.awareness.rec("crownId", -1))) and turn - int(entry.get("turn", turn)) <= int(Data.num(FILE, "fresh_seasons", 1.0)):
		now["threat"] = true
		now["war"] = true
	var stated := []
	if not kind in (Data.value(FILE, "no_state", []) as Array):
		for s in Data.value(FILE, "states", []):
			if s is Dictionary and now.has(String(s.get("when", ""))) and not kind in ((s as Dictionary).get("skip", []) as Array):
				stated.append_array(s.get("verbs", []))
	# The title's theme ("The Pestilence of Thunderhold") only where the place itself says nothing now.
	if stated.is_empty() and (kind in (Data.value(FILE, "theme_kinds", []) as Array) or not kinds.has(kind)):
		first.append_array(_themed(entry))
	var answers := _answers(entry)
	var rows := answers.duplicate()
	var seen := {}
	# A threat's own answers (defend, the levy, the banners) come before what else the place asks (Mac: a rising
	# offered a feast first); a cold lord's gifts are no answer to raiders (states' skip).
	var order: Array = first + list + stated if kind in (Data.value(FILE, "threat_kinds", []) as Array) else first + stated + list
	for v in order:
		if seen.has(v):
			continue
		seen[v] = true
		var r := _row(String(v), entry, now)
		if r.is_empty() or (r.has("key") and seen.has(r["key"])):
			continue  # one decree once (Send grain and Send relief are both the relief)
		if r.has("key"):
			seen[r["key"]] = true
		rows.append(r)
	# The matter's answers on the card stand in for "Rule on it" (kept only when they didn't all fit) and "To court".
	if not answers.is_empty():
		var whole: bool = answers.size() >= int((main.ui.court.matter(String(answers[0]["matter"])).get("options", []) as Array).size())
		rows = rows.filter(func(x): return not (String(x["verb"]) == "court" or String(x["verb"]) == "rule" and whole))
	elif rows.any(func(x): return String(x["verb"]) == "rule"):
		rows = rows.filter(func(x): return String(x["verb"]) != "court")
	return rows


## A story's beat speaks of what it is about ("The Pestilence of Thunderhold"): its theme's verbs (news_actions.json
## themes), matched in its name and its line. The fallback when the place's state says nothing.
func _themed(entry: Dictionary) -> Array:
	var said := ("%s %s %s" % [entry.get("thread", ""), entry.get("text", ""), entry.get("label", "")]).to_lower()
	var out := []
	var themes: Dictionary = Data.value(FILE, "themes", {})
	for k in themes:
		var t = themes[k]
		if not t is Dictionary:
			continue
		for w in (t as Dictionary).get("words", []):
			if said.contains(String(w)):
				out.append_array((t as Dictionary).get("verbs", []))
				break
	return out


## The place's state now, from the mirror: the keys news_actions.json states and verbs.needs ask after. war: the crown
## at war with anyone, or a foe's host on one of its towns (realm-wide); threat (a foe's host on this town of his:
## threats), besieged, hungry (starved this season, its granary low, or its siege biting), plague, unrest (disorder),
## crown_war (the town's house at war with the crown) and cold (its house's favour under cold_below).
func _now(c: Dictionary) -> Dictionary:
	var aw: Node = main.awareness
	var crown := int(aw.rec("crownId", -1))
	var out := {}
	if not threats.is_empty() or not (_player(crown).get("wars", []) as Array).is_empty():
		out["war"] = true
	if int(main.ui.court.waiting()) > 0:
		out["court_waits"] = true  # To court only when a matter waits there (Mac: "why would that even come up")
	if c.is_empty():
		return out
	if threats.has(int(c["id"])):
		out["threat"] = true
	if bool(c.get("besieged", false)):
		out["besieged"] = true
	var siege: Dictionary = c.get("siege") if c.get("siege") is Dictionary else {}
	if bool(c.get("famine", false)) or bool(c.get("granaryLow", false)) or bool(siege.get("hungry", false)):
		out["hungry"] = true
	if bool(c.get("plague", false)):
		out["plague"] = true
	if bool(c.get("disorder", false)):
		out["unrest"] = true
	var owner := int(c.get("owner", -2))
	if owner != crown:
		var pl := _player(owner)
		if (pl.get("wars", []) as Array).has(String(Data.value(FILE, "crown_word", "the Crown"))):
			out["crown_war"] = true
		if pl.get("favour") != null and float(pl["favour"]) < Data.num(FILE, "cold_below", 35.0):
			out["cold"] = true
	return out


## The court matter this news waits on: a matter's own card by its id, a story's by its name (ui.story_matter), or the lord come to court for it (the
## court line "<name> of <house> comes to court: <thread>"), or "".
func _matter(e: Dictionary) -> String:
	if e.get("matter") != null:
		return String(e["matter"])  # a court matter's own card (court_panel.gd _as_card)
	var id: String = main.ui.story_matter(e) if e.get("thread") else ""
	if id != "" or String(e.get("kind", "")) != "court":
		return id
	var said := String(e.get("text", ""))
	for p in main.ui.court._petitions:
		var th := String(p.get("thread", ""))
		if String(p.get("name", "")) != "" and said.contains(String(p["name"])) and (th == "" or said.contains(th)):
			return String(p["id"])
	return ""


static var _PRICE_RE := RegEx.create_from_string("\\s*\\([\\d,]+ crowns\\)\\s*$")  # "(50,000 crowns)" closing a court answer


## A matter's own answers as the card's buttons (at most answers_most, in the court's order: its first is the one we'd
## have him give), each answered as the court card answers it (ui.petition_answered: the bridge rules, the court
## refreshes); one the purse can't pay greyed with why.
func _answers(e: Dictionary) -> Array:
	var id := _matter(e)
	if id == "":
		return []
	var out := []
	for o in main.ui.court.matter(id).get("options", []):
		if out.size() >= int(Data.num(FILE, "answers_most", 3)):
			break
		var opt := String(o.get("id", ""))
		var short := String(o.get("short", ""))
		# Its price is on the button already (the cost below): "(50,000 crowns)" in the court's own label goes.
		var label := _PRICE_RE.sub(String(o.get("label", o.get("text", opt))), "").strip_edges()
		out.append({"verb": "answer", "matter": id, "label": label, "cost": int(o.get("cost", 0)) * UI.CROWNS,
			"enabled": short == "", "why": short, "tip": String(o.get("hint", "")), "call": func(): main.ui.petition_answered.emit(id, opt)})
	return out


## The rows as one row of buttons (the ticker's line, a caption): the label says the price, or why not.
func buttons(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.GAP)
	for r in verbs(entry):
		var b: Button = main.ui.btn(String(r["label"]), r["call"])
		b.disabled = not bool(r["enabled"])
		b.tooltip_text = String(r["why"]) if String(r["why"]) != "" else String(r["tip"])
		b.add_theme_font_size_override("font_size", T.SIZE_DESC)
		row.add_child(b)
	return row


## One verb's row, or {} where it doesn't fit: its condition (verbs.needs: any of the keys of _now) no longer holds,
## or its place or order is wanting.
func _row(verb: String, e: Dictionary, now: Dictionary) -> Dictionary:
	var city := int(e["city"]) if e.get("city") != null else -1
	var c: Dictionary = main.awareness.city(city) if city >= 0 else {}
	var mine := not c.is_empty() and int(c.get("owner", -2)) == int(main.awareness.rec("crownId", -1))
	var words: Dictionary = Data.value(FILE, "verbs." + verb, {})
	var needs: Array = words.get("needs", [])
	if not needs.is_empty() and not needs.any(func(k): return now.has(String(k))):
		return {}
	var fill := {"town": _town_name(c), "house": _house_name(c)}
	var r := {"verb": verb, "label": String(words.get("label", verb)), "cost": 0, "enabled": true, "why": "", "tip": String(words.get("tip", "")).format(fill)}
	match verb:
		"defend":
			var h := _free_host(city)
			var on_way := _host_bound(city)
			if not on_way.is_empty():
				var at_town: bool = on_way.get("at") is Dictionary and int((on_way["at"] as Dictionary).get("id", -1)) == city
				r["label"] = String(words.get("holds" if at_town else "going", "")).format(fill)
				r["enabled"] = false
			elif h.is_empty():
				return {}  # no host free: the levy answers instead
			else:
				var from: String = String((h["at"] as Dictionary).get("name", "")) if h.get("at") is Dictionary else "the field"
				r["tip"] = String(words.get("tip", "")).format({"from": from, "men": UI.heads(int(h.get("men", 0))), "town": fill["town"]})
				r["call"] = _defend.bind(city)
		"rule":
			var id := _matter(e)
			if id == "":
				return {}
			r["call"] = main.ui.open_matter.bind(id)
		"go":
			if c.is_empty():
				return {}
			r["call"] = func(): main.news.go_to(_at(c), String(e.get("text", "")), _go_call(city))
		_:
			if words.has("ui"):
				return _ui_row(r, words)
			if not words.has("decree"):
				return {}
			return _decree_row(r, words, verb, c, mine)
	if not r.has("call"):
		r["call"] = func(): pass
	return r


## A decree verb, as its data row says (news_actions.json verbs: decree, at, town, not_seat, building, built_as,
## unsworn): at the news's town, or at the King's seat (at: seat); only at his own towns (town: mine), only at a
## lord's (town: theirs); a building only where the town hasn't one and no royal works rise. Priced as the bridge has it.
func _decree_row(r: Dictionary, words: Dictionary, verb: String, c: Dictionary, mine: bool) -> Dictionary:
	var action := String(words["decree"])
	var seat := String(words.get("at", "town")) == "seat"
	var want := String(words.get("town", "any"))
	if want == "mine" and not mine or want == "theirs" and (c.is_empty() or mine) or not seat and c.is_empty():
		return {}
	if bool(words.get("not_seat", false)) and mine and bool(c.get("capital", false)):
		return {}  # the King's seat feeds itself (but its sick still need physicians)
	var owner := int(c.get("owner", -1))
	var pl := _player(owner)
	if bool(words.get("unsworn", false)) and (pl.is_empty() or pl.get("sworn") != null):
		return {}
	var building := String(words.get("building", ""))
	if building != "":
		var built := String(words.get("built_as", building))
		if bool(c.get("royal", false)) or (c.get("buildings", []) as Array).any(func(x): return String(x).begins_with(built)):
			return {}
	var at := int(main.awareness.rec("seatId", -1)) if seat else int(c.get("id", -1))
	_priced(r, words, action, -1 if mine or seat else owner)
	r["key"] = "%s:%s" % [action, building]
	r["call"] = _decree.bind(action, at, verb, building)
	return r


## A verb the King's own controls already answer (ui.counsel_act: the court, the tithe up or down), as its data row
## says (news_actions.json verbs: ui); the tithe greyed with its wait while the year's rate stands.
func _ui_row(r: Dictionary, words: Dictionary) -> Dictionary:
	var on := String(words["ui"])
	var ui: Node = main.ui
	if on == "tithe_down" and float(ui.tithe) <= 0.0 or on == "tithe_up" and float(ui.tithe) >= 0.4:
		return {}
	if on.begins_with("tithe") and int(ui.tithe_wait) > 0:
		r["label"] = "%s  ·  %s" % [r["label"], String(Data.value(FILE, "again_in", "again in {n} seasons")).format({"n": ui.tithe_wait, "s": "" if int(ui.tithe_wait) == 1 else "s"})]
		r["enabled"] = false
		r["why"] = r["label"]
	r["call"] = ui.counsel_act.bind({"ui": on})
	return r


## A house's record from the mirror (its sworn oath, its war), or {}.
func _player(id: int) -> Dictionary:
	for pl in main.awareness.rec("players", []):
		if int(pl.get("id", -2)) == id:
			return pl
	return {}


## A decree's price as the bridge has it (/world crown.decrees, in its gold), on the label; greyed with the
## reason when the purse can't pay, it waits its year, or the house had its favour of the King this year.
func _priced(r: Dictionary, words: Dictionary, action: String, house: int) -> void:
	var crown: Dictionary = main.awareness.rec("crown", {})
	var d: Dictionary = (crown.get("decrees", {}) as Dictionary).get(action, {})
	if bool(d.get("off", false)):
		r["enabled"] = false
	var gold := int(d.get("cost", 0))
	r["cost"] = gold * UI.CROWNS
	var wait := int(d.get("wait", 0)) if house < 0 else int((crown.get("favourWait", {}) as Dictionary).get(str(house), 0))
	var label := String(words.get("label", action))
	if wait > 0:
		r["label"] = "%s  ·  %s" % [label, String(Data.value(FILE, "again_in", "again in {n} seasons")).format({"n": wait, "s": "" if wait == 1 else "s"})]
		r["enabled"] = false
		r["why"] = r["label"]
	elif int(crown.get("treasury", 0)) < gold:
		r["label"] = "%s  ·  %s" % [label, String(Data.value(FILE, "no_purse", "the treasury can't pay"))]
		r["enabled"] = false
		r["why"] = String(d.get("short", r["label"]))
	else:
		r["label"] = "%s  ·  %s" % [label, UI.crowns(gold)]


# --- the answers -------------------------------------------------------------------------------

## The nearest royal host free to go (standing at ease, holding or in a town; an order left this season; not at
## sea; not already there), or {}.
func _free_host(city: int) -> Dictionary:
	var c: Dictionary = main.awareness.city(city)
	var free: Array = Data.value(FILE, "free_orders", ["hold", "garrison"])
	var best := {}
	var near := INF
	for h in main.awareness.hosts():
		var o = h.get("order")
		if o is Dictionary and not (String(o.get("kind", "")) in free):
			continue
		if int(h.get("ordersLeft", 1)) == 0 or bool(h.get("aboard", false)):
			continue
		if h.get("at") is Dictionary and int((h["at"] as Dictionary).get("id", -1)) == city:
			continue
		var d := maxf(absf(float(h["x"]) - float(c.get("x", 0))), absf(float(h["y"]) - float(c.get("y", 0))))
		if d < near:
			near = d
			best = h
	return best


## A royal host already bound for the town, or standing in it, or {}.
func _host_bound(city: int) -> Dictionary:
	for h in main.awareness.hosts():
		var o = h.get("order")
		if o is Dictionary and o.get("city") != null and int(o["city"]) == city:
			return h
		if h.get("at") is Dictionary and int((h["at"] as Dictionary).get("id", -1)) == city and not (o is Dictionary):
			return h
	return {}


## Defend: the nearest free host is chosen and told to garrison the town, the one way a host is ordered
## (host_command.gd select + order: POST /host/order, its captain's answer, the horn, the men's cry).
## With none free, the levy is raised in its place; with no purse for it, the King is told so.
func _defend(city: int) -> void:
	var cmd: Node = main.get_node_or_null("HostCommand")
	var h := _free_host(city)
	if cmd and not h.is_empty():
		cmd.select(int(h["id"]))
		# His own town he garrisons; a house's he can't enter, so the host advances on it and falls on the raiders
		# it meets there (Warcraft III's attack-move, bridge hosts.js advance).
		var mine := int(main.awareness.city(city).get("owner", -2)) == int(main.awareness.rec("crownId", -1))
		cmd.order("garrison" if mine else "advance", {"city": city})
		return
	var levy := _row("levy", {"kind": "attack", "city": city}, _now(main.awareness.city(city)))
	if not levy.is_empty() and bool(levy["enabled"]):
		(levy["call"] as Callable).call()
	else:
		main.ui.toast(String(Data.value(FILE, "no_answer", "No royal host is free, and the treasury can't pay for a levy.")))


## The defend key: the latest threat still standing, answered.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"defend") and not event.is_echo():
		if _latest >= 0 and threats.has(_latest):
			_defend(_latest)
			get_viewport().set_input_as_handled()


## A decree from the news, as the town card gives it (ui.decree_at -> bridge /decree); the steward says so.
func _decree(action: String, city: int, verb: String, building := "") -> void:
	main.ui.decree_at.emit(action, city, -1, building, "")
	if main.barks and main.barks.has_method("steward"):
		main.barks.steward(verb)


func _go_call(city: int) -> Callable:
	return func(): main.ui.look_city.emit(city)


func _at(c: Dictionary) -> Vector3:
	return main.terrain.world_pos(float(c.get("x", 0)), float(c.get("y", 0)))


func _town_name(c: Dictionary) -> String:
	return String(c.get("title", c.get("name", "the town")))


func _house_name(c: Dictionary) -> String:
	return String((main.awareness.houses_by_id().get(int(c.get("owner", -1)), {}) as Dictionary).get("name", "the house"))
