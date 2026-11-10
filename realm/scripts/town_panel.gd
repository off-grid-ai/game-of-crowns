extends RefCounted
## The town card: the town the King opened, who holds it and what it holds, and the
## royal decrees he can make there (grain, crowns, a feast, the levy and banners, an
## oath, a march, a grant, a marriage, a work to fund). Owned by ui.gd, which forwards
## its public calls here (ui.show_town and the rest).

const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")
const Heraldry = preload("res://scripts/heraldry.gd")

var ui: UI  # the interface that owns this card: its signals, its building blocks, its other cards

var _town_panel: PanelContainer
var _town_title: Label
var _town_sigil: TextureRect
var _town_info: Label
var _town_family: HBoxContainer  # the lesser family holding the town, under its arms
var _grant_menu: MenuButton
var _marriage_menu: MenuButton  # wed this town's house to another
var _marry_ids: Array = []  # the houses it can be wed to, by menu item
var _house_ids: Array = []
var _decree_btns := {}  # decree -> its button on the town card, named for whose town it is


func _init(owner: UI) -> void:
	ui = owner


func _build_town_panel() -> void:
	_town_panel = ui.glass_panel()
	_town_panel.anchor_left = 0.5
	_town_panel.anchor_right = 0.5
	_town_panel.anchor_top = 1.0
	_town_panel.anchor_bottom = 1.0
	_town_panel.offset_left = -290
	_town_panel.offset_right = 290
	_town_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_town_panel.offset_bottom = -12
	_town_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_town_panel.add_child(v)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	v.add_child(title_row)
	_town_sigil = ui.sigil_icon({}, 24)
	title_row.add_child(_town_sigil)
	_town_title = T.title("", 16)
	title_row.add_child(_town_title)
	_town_family = HBoxContainer.new()
	_town_family.add_theme_constant_override("separation", 10)
	_town_family.add_child(ui.sigil_icon({}, 22))
	_town_family.add_child(T.datum("", T.SIZE_DESC + 1, T.TEXT_2))
	v.add_child(_town_family)
	_town_info = Label.new()
	_town_info.add_theme_color_override("font_color", T.TEXT_2)
	_town_info.add_theme_font_size_override("font_size", T.SIZE_DESC + 1)
	_town_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_town_info.custom_minimum_size = Vector2(240, 0)
	v.add_child(_town_info)
	v.add_child(T.label("Royal decrees"))
	var row := HFlowContainer.new()
	v.add_child(row)
	for a in ["relief", "gift", "feast", "levy", "banners", "alliance", "march"]:
		var act: String = a
		_decree_btns[act] = ui.btn("", func():
			if act == "banners":
				ui.guide_mark(2)
			_order(act, "", -1))
		row.add_child(_decree_btns[act])
	_grant_menu = MenuButton.new()
	_grant_menu.get_popup().id_pressed.connect(func(i): _order("grant", "", int(_house_ids[i])))
	row.add_child(_grant_menu)
	# A royal match: bind this house to another by marriage.
	_marriage_menu = MenuButton.new()
	_marriage_menu.text = "Arrange a marriage with…"  # its price is set with the town's other decrees
	_marriage_menu.tooltip_text = "Bind this house to another by blood: both warm to the crown, and neither raids or plots against the other while the bond holds."
	_marriage_menu.get_popup().id_pressed.connect(func(i): _order("marriage", "", int(_marry_ids[i])))
	row.add_child(_marriage_menu)
	var build := HFlowContainer.new()
	v.add_child(build)
	_fund_label = T.label("Fund  18k cr")
	build.add_child(_fund_label)
	for pair in [["Sept", "temple"], ["Granary", "granary"], ["Walls", "walls"], ["Market", "market"], ["Barracks", "barracks"], ["Aqueduct", "aqueduct"]]:
		var bld: String = pair[1]
		_build_btns[bld] = ui.btn(pair[0], func(): _order("build", bld, -1))
		build.add_child(_build_btns[bld])


## An order given from the card: it goes, and the card closes on its own (the
## toast says what the order did); nothing stays open the King didn't ask for.
func _order(action: String, building: String, to: int) -> void:
	ui.decree.emit(action, building, to)
	_put_town_away()


## The town card put away for good: the realm's next update refreshes nothing,
## so it never comes back over whatever the King opened instead.
func _put_town_away() -> void:
	_town_id = -1
	if _town_panel and _town_panel.visible:
		_town_panel.visible = false
		ui.town_closed.emit()


## The decrees a town card offers, named for whose town it is: the King's own
## seat (a feast at court, the royal levy), another of his towns (grain from the
## royal stores, granting it away), or a house's (grain and gold sent to them, a
## feast in their honour, taking the town for another house).
var _decrees := {}  # the bridge's own decree list: action -> {cost (in gold), label}
var _favour_wait := {}  # house id -> seasons until it may have another royal favour


## A decree's price as the bridge has it, in crowns: "12k cr".
func _price(action: String, fallback: int) -> String:
	var gold := int(_decrees.get(action, {}).get("cost", fallback / ui.CROWNS))
	return "%dk cr" % int(round(gold * ui.CROWNS / 1000.0))


var _build_btns := {}  # build key -> its button on the town card
var _fund_label: Label
# The engine's name for each building the King can fund (an aqueduct may be "Aqueduct, Lake").
const BUILT_AS := {"temple": "Temple", "granary": "Granary", "walls": "City Walls", "market": "Marketplace", "aqueduct": "Aqueduct", "barracks": "Barracks"}


## The royal host's chances against a town, as a captain would put them.
func _forecast(odds: float) -> String:
	if odds >= 0.75:
		return "they'd break before us"
	if odds >= 0.58:
		return "we'd likely take it"
	if odds >= 0.42:
		return "about even"
	if odds >= 0.25:
		return "they'd likely hold"
	return "we'd be thrown back"


func _name_decrees(c: Dictionary, house: Dictionary) -> void:
	# Only what the town hasn't built is offered; with nothing left, no "Fund" at all.
	var has: Array = c.get("buildings", [])
	var any_left := false
	for k in _build_btns:
		var name: String = BUILT_AS[k]
		_build_btns[k].visible = not has.any(func(x): return String(x).begins_with(name))
		any_left = any_left or _build_btns[k].visible
	if _fund_label:
		_fund_label.visible = any_left
		_fund_label.text = "Fund  %s" % _price("build", 18000)
	# The King's own works under way: the site rising, nothing else funded here till it stands.
	if c.get("royal", false):
		for k in _build_btns:
			_build_btns[k].visible = false
		if _fund_label:
			_fund_label.visible = true
			_fund_label.text = "The King's %s rising  ·  %d%%" % [String(c.get("building", "work")).to_lower(), int(float(c.get("progress", 0)) * 100)]
	var town := String(c.get("title", c["name"]))
	var lord := String(house.get("name", "")).replace("House ", "")
	var mine: bool = house.get("crown", false)
	var seat: bool = mine and c.get("capital", false)
	# What each decree does, in a few words: the bridge's decrees.json (via /world), never written here.
	var says := func(a: String, at_court: bool) -> String:
		var d: Dictionary = _decrees.get(a, {})
		var w := String(d.get("courtEffect" if at_court else "effect", ""))
		return ("  ·  " + w) if w != "" else ""
	var names := {
		"relief": "" if seat else (("Grain from the royal stores  " if mine else "Send grain to %s  " % town) + _price("relief", 12000)),
		"gift": "" if mine else "Gift crowns to %s  %s" % [lord, _price("gift", 15000)],
		# On the King's own seat these are the realm's decrees: each says what it does.
		"feast": ("Hold a feast at court  " + _price("feast", 10000) + says.call("feast", true)) if seat else ("" if mine else "Feast in %s's honour  %s%s" % [lord, _price("feast", 10000), says.call("feast", false)]),
		"levy": ("Raise the royal levy  " + _price("levy", 20000) + says.call("levy", true)) if seat else "",
		"banners": ("Call the banners  " + _price("banners", 5000) + says.call("banners", true)) if seat else "",
		# Politics with teeth: an oath that binds a house to the crown's wars, and the royal host.
		"alliance": "" if mine or _town_player.get("sworn") != null else "Swear an alliance with %s  %s" % [lord, _price("alliance", 20000)],
		"march": "" if mine or (_town_player.get("besieged", []) as Array).has(int(c["id"])) else ("March on %s  %s  ·  %s" % [town, _price("march", 25000), _forecast(float(c["odds"]))] if c.get("odds") != null else "March on %s  %s" % [town, _price("march", 25000)]),
	}
	_marriage_menu.text = "Arrange a marriage with…  " + _price("marriage", 40000)
	# A decree the purse can't pay is greyed, and says why and what to do.
	var COST := {}
	for a in ["relief", "gift", "feast", "levy", "banners", "alliance", "march"]:
		COST[a] = int(_decrees.get(a, {}).get("cost", 0)) * ui.CROWNS
	for a in names:
		_decree_btns[a].text = names[a]
		_decree_btns[a].visible = names[a] != ""
		var short: bool = ui.purse * 100 < int(COST.get(a, 0))
		# The crown's great occasions come once a year: the levy, the banners, a
		# feast at court (a feast in a lord's honour is another matter).
		var wait := int(_decrees.get(a, {}).get("wait", 0)) if (seat or a in ["levy", "banners"]) else 0
		# One royal favour to a house a year: grain, crowns or a feast in their honour.
		if not seat and not mine and a in ["relief", "gift", "feast"]:
			wait = int(_favour_wait.get(str(int(c.get("owner", -1))), 0))
		if wait > 0 and names[a] != "":
			_decree_btns[a].text = "%s  ·  again in %d season%s" % [names[a].get_slice("  ", 0), wait, "" if wait == 1 else "s"]
		elif short and names[a] != "":
			# Can't be paid: the order says so on its face, not only on hover.
			_decree_btns[a].text = "%s  ·  the treasury can't pay" % names[a].get_slice("  ", 0)
		_decree_btns[a].disabled = short or wait > 0
		_decree_btns[a].tooltip_text = ("Once a year. Again in %d season%s." % [wait, "" if wait == 1 else "s"]) if wait > 0 else (("%s. Raise the tithe (the %% in the top bar) to fill it." % String(_decrees.get(a, {}).get("short", "The treasury holds %s crowns" % ui.heads(ui.purse * 100)))) if short else "")
	_grant_menu.visible = not c.get("capital", false)  # a house's seat is never granted away
	_marriage_menu.visible = not mine  # a match is made between two great houses
	# The other great houses, not this one: the names as the houses table has them.
	var mp := _marriage_menu.get_popup()
	mp.clear()
	_marry_ids.clear()
	var popup := _grant_menu.get_popup()
	for i in _house_ids.size():
		if int(_house_ids[i]) != int(c.get("owner", -1)):
			mp.add_item(popup.get_item_text(i), _marry_ids.size())
			_marry_ids.append(int(_house_ids[i]))
	_grant_menu.text = "Grant this town to…" if mine else "Take it and grant it to…"


const PINNED_WIDTH := 400.0  # the town card standing by its town: narrow, its orders wrapping
var _town_player := {}  # the house holding the town on the card, as the realm reports it
var _town_id := -1  # the town on the card; -1 once it is put away


func show_town(c: Dictionary, house: Dictionary, _player: Dictionary) -> void:
	_town_player = _player
	if c.is_empty():
		_town_id = -1
		_town_panel.visible = false
		ui._ticker.visible = false  # as before: the chronicle down the right carries the news
		return
	# The realm's update for a town whose card is already down refreshes its
	# words only: it never brings the card back over what the King opened since.
	var fresh := int(c["id"]) != _town_id
	_town_id = int(c["id"])
	# While the King watches a scene the card waits, and returns with the panels.
	if ui.cinema_on:
		if fresh:
			ui.cinema_was["_town_panel"] = true
	elif fresh or _town_panel.visible:
		_town_panel.visible = true
		# The King opened a town: a petitioner on screen steps back and waits on
		# the court's badge, and comes back in when the town's card is put away.
		if ui._court_panel.visible:
			ui._court_panel.visible = false
			ui._held_court = true
	ui._ticker.visible = false
	_town_title.text = "%s  ·  %s" % [c.get("title", c["name"]), house.get("name", "")]
	# The town's orders stand by the town itself, following it as the camera moves
	# (Civilization's unit actions), not in a strip at the bottom of the screen.
	var at: Vector3 = ui.town_point.call(c)
	if at != Vector3.INF:
		_town_panel.custom_minimum_size = Vector2(PINNED_WIDTH, 0)
		_town_panel.size = Vector2(PINNED_WIDTH, 0)
		ui.anchor.pin(_town_panel, at)
	_name_decrees(c, house)
	ui.set_sigil(_town_sigil, house)
	# A town held by a bannerman flies his family's arms.
	var family := Heraldry.family(String(c["family"])) if c.get("family") is String else {}
	_town_family.visible = not family.is_empty()
	if _town_family.visible:
		ui.set_arms(_town_family.get_child(0), family)
		(_town_family.get_child(1) as Label).text = "Held by the %s family, sworn to %s" % [c["family"], String(house.get("name", "")).replace("House ", "")]
	var b: Array = c.get("buildings", [])
	var parts := []
	# What has befallen the town, first (the bridge's situation.js: stormed, rebuilding, starving…).
	if String(c.get("situation", "")) != "":
		parts.append(String(c["situation"]))
	if c.get("capital", false):
		parts.append("Seat of the house")
	if (_town_player.get("besieged", []) as Array).has(int(c["id"])):
		parts.append("the royal host at its walls")
	if _town_player.get("sworn") != null:
		parts.append("sworn to the crown")
	parts.append("%s souls" % ui.heads(250 * int(c["size"]) * (int(c["size"]) + 1)))
	if String(c.get("building", "")) == "Coinage":
		parts.append("filling the coffers")
	elif c.get("building"):
		parts.append(preload("res://scripts/town_life.gd").doing_line(String(c.get("buildingKind", "")), String(c["building"]), float(c.get("progress", 0))).to_lower())
	if c.get("granary"):
		# How full the granary is, as a steward would say it, not tonnes of a capacity.
		var full := clampf(float(c.get("food", 0)) / maxf(float(c["granary"]), 1.0), 0.0, 1.0)
		parts.append("starving" if c.get("famine", false) else ("granary empty" if full < 0.05 else ("granary %s" % ("low" if full < 0.34 else ("half full" if full < 0.67 else "full")))))
	if b.size() > 0:
		parts.append(", ".join(b.map(_realm_word)))
	_town_info.text = "  ·  ".join(parts)


## Freeciv's names for what a town builds, in the realm's own words.
const REALM_WORDS := {"Colosseum": "Tiltyard", "Diplomat": "Envoys", "Workers": "Labourers", "Trireme": "Galley", "Bank": "Counting house", "Marketplace": "Market", "City Walls": "Walls"}
static func _realm_word(name: String) -> String:
	return String(REALM_WORDS.get(name, name))
