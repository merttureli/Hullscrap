extends Control
## The crafting panel (C, in build or play mode): a fabricator screen over the game. Left: a grid of picture cards (pic_card.gd: the
## output's sprite, its figures, its materials with the missing ones in red, no name), grouped by family (every blueprint you know, once;
## one you cannot make yet stays, dimmed, and its details say why; locked ones are hidden, the box at the right says how many you found). Hovering a card shows its name, description and full stats (part_card.gd). Middle: what the selected recipe
## makes, described (describe.gd), or how crafting works (? toggles it). Right: the fabricator (level, tools, workshop modules counted, the Upgrade button)
## and the queue with progress bars; a click on a queued job cancels it (the materials come back). Bottom: the
## cargo's materials. Tab (or a click on the tabs at the top) switches to the smelter (docs/CONTENT.md
## section 12): its recipes, its level, speed and tools, its own queue. Click a card, or select it with the arrows and press Enter, to
## queue it. U unlocks a random locked blueprint (debug, until salvage gives real ones).
## While open it takes every key and click; the game keeps running behind it. It stays shut during a
## fight and while the ship picker is up. Rules are in crafting.gd and workshop.gd; this node reads
## input and draws, in the UI colours of docs/ART_STYLE.md.

const Crafting = preload("res://scripts/craft/crafting.gd")
const BreachPrompt = preload("res://scripts/ui/breach_prompt.gd")
const Workshop = preload("res://scripts/craft/workshop.gd")
const Processing = preload("res://scripts/craft/processing.gd")
const Describe = preload("res://scripts/ui/describe.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Audio = preload("res://scripts/audio/audio.gd")
const Mods = preload("res://scripts/board/mods.gd")
const PartCard = preload("res://scripts/ui/part_card.gd")
const PicCard = preload("res://scripts/ui/pic_card.gd")
const Thumbs = preload("res://scripts/ui/thumbs.gd")

const STATION_IDS: Array[String] = ["fabricator", "smelter"]  ## the tabs, in order (Tab cycles them)
const TAB_NAMES := {"fabricator": "Fabricator", "smelter": "Smelter"}
const TAB_W: Array[float] = [176.0, 120.0]
## The Fabricator tab's groups: part families first (in this order, the families not named after them), then the rest.
const FAMILY_ORDER: Array[String] = ["weapon", "drone_bay", "shield", "engine", "reactor", "smelter", "oxygen", "helm", "medbay", "bed", "fabricator", "workshop", "radiator", "utility", "intake", "ammo_rack", "belt_drive", "radar", "tractor"]
const FAMILY_NAMES := {"weapon": "Weapons", "drone_bay": "Drone bays", "shield": "Shields", "engine": "Engines", "reactor": "Reactors", "smelter": "Smelters", "oxygen": "Life support", "helm": "Helms", "medbay": "Medbays",
	"bed": "Beds", "fabricator": "Fabricators", "workshop": "Workshop modules", "radiator": "Radiators", "utility": "Utility", "intake": "Intakes", "ammo_rack": "Ammo racks", "belt_drive": "Belt drives",
	"radar": "Radars", "tractor": "Tractor beams"}
const G_MATERIALS := "Materials"
const G_GEAR := "Hand weapons and gear"
const G_ITEMS := "Items"
const HOVER_W := 330.0  ## the hover card
const CATEGORIES: Array[String] = ["system", "gear", "material", "module"]
const CATEGORY_NAMES := {"system": "Systems", "gear": "Gear", "material": "Materials", "module": "Modules"}
const BLUEPRINT_HELP := "Needs a blueprint"
const MARGIN := 40.0
const TITLE_H := 56.0
const CARGO_H := 96.0
const HEAD_H := 30.0  ## a category header row
const CARD_H := 124.0  ## a recipe card
const COLS := 4  ## cards across the list
const CARD_GAP := 6.0
const JOB_H := 52.0
const FAB_H := 160.0  ## the smelter's box
const FAB_BOX_H := 262.0  ## the fabricator's box: its level, modules and the Upgrade button
const GAP := 14.0
const PAD := 14.0
const DIM := Color(0.0, 0.0, 0.0, 0.62)
const PANEL_BG := Color("#1f2630")
const ROW_BG := Color("#2a3340")
const EDGE := Color("#cfd6df")
const EDGE_DIM := Color("#59667a")
const HIGHLIGHT := Color(1.0, 1.0, 1.0, 0.1)
const TEXT := Color("#eef2f7")
const DIM_TEXT := Color("#97a3b3")
const GOOD := Color("#6bd34a")
const BAD := Color("#e0413b")
const AMBER := Color("#e1a136")
const BLUE := Color("#4fa3ff")

var sim: Node  ## the ShipSim whose player ship is worked on
var station := "fabricator"  ## the tab shown: the station whose recipes and queue are on screen
var selected := ""  ## the recipe id under the cursor
var top := 0  ## the first row of rows() shown
var debug_keys := OS.is_debug_build()  ## U (free blueprint) and M (all mods) work only in a debug build; a release export has neither
var message := ""
var flash := 0.0  ## seconds left of the green flash after an upgrade
var message_bad := false
var hover_row := -1  ## index into rows()
var hover_job := -1
var help_open := false  ## the middle column shows how crafting works, not the selected recipe
var fresh_now := {}  ## the NEW blueprints shown on the Fabricator tab this visit (they count as seen once it was opened)
var hover_kw := {}  ## the keyword chip under the mouse in the description ({} for none), and its rect
var hover_rect := Rect2()
var chips_at := []  # the description's chips as drawn: [[Rect2, keyword]]
var _ids_cache: Array[String] = []  # recipe_ids() for _ids_key: it is asked for many times a frame
var _ids_key := ""


func _ready() -> void:
	sim = get_node_or_null("../../ShipSim")
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _process(dt: float) -> void:
	flash = maxf(0.0, flash - dt)
	if visible:
		queue_redraw()


# --- the data the screen shows ------------------------------------------------------------------

## The player's ship (null before the scene is wired).
func ship():
	return sim.player_ship() if sim != null else null


## The ids of the recipes of the shown station in screen order: by category, as listed in data/recipes.json, only the ones whose
## blueprint is known (the Fabricator tab: every known one, grouped by family).
func recipe_ids() -> Array[String]:
	var s = ship()
	if s == null:
		return []
	var has_fab: bool = s.components.has_fabricator()  # (one per ship: its own recipe is not offered while it has one)
	var key := "%s|%d|%d|%d|%s" % [station, s.crafting.known.size(), s.crafting.order.size(), s.get_instance_id(), has_fab]
	if key == _ids_key:
		return _ids_cache
	var out: Array[String] = []
	if station == Crafting.FABRICATOR:
		var groups := {}
		var ranks := []
		for id in s.crafting.ids():
			if s.crafting.is_known(id) and s.crafting.station_of(id) == station and not (has_fab and id == "fabricator"):  # (the smelter's own are on its tab)
				var g := group_of(s, id)
				if not groups.has(g[1]):
					groups[g[1]] = []
					ranks.append(g)
				groups[g[1]].append(id)
		ranks.sort_custom(func(a, b): return a[0] < b[0])
		for g in ranks:
			out.append_array(groups[g[1]])
		_ids_key = key
		_ids_cache = out
		return out
	for cat in CATEGORIES:
		for id in s.crafting.ids():
			if s.crafting.def(id)["category"] == cat and s.crafting.station_of(id) == station and s.crafting.is_known(id) and not (has_fab and id == "fabricator"):
				out.append(id)
	_ids_key = key
	_ids_cache = out
	return out


## The Fabricator tab's group of recipe `id`: [rank, name]. A part goes by its family, a material, hand gear and the rest by their own groups.
func group_of(s, id: String) -> Array:
	var out: String = str(s.crafting.def(id)["output"]["item"])
	if s.components.has(out):
		var fam := str(s.components.def(out).get("family", ""))
		var at := FAMILY_ORDER.find(fam)
		return [at if at >= 0 else FAMILY_ORDER.size(), FAMILY_NAMES.get(fam, fam.capitalize())]
	if s.crafting.def(id)["category"] == "material":
		return [100, G_MATERIALS]
	var item: Dictionary = s.crafting.item_def(out)
	if str(item.get("kind", "")) == "gear" and not item.has("does"):
		return [101, G_GEAR]
	return [102, G_ITEMS]


## The rows of the left column: {"header": text} for a category (a group on the Fabricator tab), {"id": recipe id} for a recipe.
func rows() -> Array:
	var out := []
	var s = ship()
	if s == null:
		return out
	var last := ""
	for id in recipe_ids():
		var cat: String = group_of(s, id)[1] if station == Crafting.FABRICATOR else str(s.crafting.def(id)["category"])
		if cat != last:
			out.append({"header": cat if station == Crafting.FABRICATOR else CATEGORY_NAMES.get(cat, cat)})
			last = cat
		out.append({"id": id})
	return out


## The shown station's level, tools and speed (workshop.gd's or processing.gd's best result) for `s`.
func station_info(s, st := "") -> Dictionary:
	if st == "":
		st = station
	return Processing.best(s, st) if st != Crafting.FABRICATOR else Workshop.best(s)


## Why recipe `id` cannot be queued now ("" when it can): crafting.gd's reason, or a full queue.
func reason(id: String) -> String:
	var s = ship()
	if s == null:
		return "no ship"
	var why: String = s.crafting.can_craft(id, s.inventory, station_info(s, s.crafting.station_of(id)))
	if why == "" and s.crafting.queue_of(s.crafting.station_of(id)).size() >= Crafting.QUEUE_MAX:
		return "queue full"
	return why


# --- actions (the keys and clicks call these) -----------------------------------------------------

func open() -> void:
	if not visible:
		Audio.fx(self, "open")
	visible = true
	_enter_tab()
	if not recipe_ids().has(selected):
		selected = recipe_ids()[0] if not recipe_ids().is_empty() else ""
	message = ""
	_show_selection()
	queue_redraw()


func close() -> void:
	if visible:
		Audio.fx(self, "close")
	visible = false
	fresh_now = {}


## The Fabricator tab is on screen: the blueprints learned since it was last looked at are NEW for this visit, and count as seen from now on.
func _enter_tab() -> void:
	fresh_now = {}
	var s = ship()
	if station == Crafting.FABRICATOR and s != null:
		for id in s.crafting.fresh():
			fresh_now[id] = true
		s.crafting.mark_seen()


## How many blueprints are NEW: this visit's on the Fabricator tab, else the ones not looked at yet.
func new_count() -> int:
	var s = ship()
	if s == null:
		return 0
	return fresh_now.size() if station == Crafting.FABRICATOR else s.crafting.fresh().size()


## The Fabricator tab's title: "Fabricator (2 new)".
func tab_label(id: String) -> String:
	var n := new_count() if id == Crafting.FABRICATOR else 0
	return str(TAB_NAMES[id]) + (" (%d new)" % n if n > 0 else "")


## Open recipe `id` on the tab of its station, selected and ready to queue (a click on a Blueprints row). False when it is not a recipe.
func open_recipe(id: String) -> bool:
	var s = ship()
	if s == null or not s.crafting.has(id):
		return false
	set_station(s.crafting.station_of(id))
	selected = id
	_show_selection()
	return true


## Show the tab of `id` ("fabricator", "smelter" or "blueprints"): its recipes and its queue. False for anything else.
func set_station(id: String) -> bool:
	if not STATION_IDS.has(id):
		return false
	station = id
	top = 0
	_enter_tab()
	selected = recipe_ids()[0] if not recipe_ids().is_empty() else ""
	message = ""
	_show_selection()
	Audio.fx(self, "tab_switch")
	return true


## The next tab.
func next_station() -> void:
	set_station(STATION_IDS[(STATION_IDS.find(station) + 1) % STATION_IDS.size()])


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Move the cursor `delta` recipes down (up when negative), keeping it on screen.
func move(delta: int) -> void:
	var ids := recipe_ids()
	if ids.is_empty():
		return
	selected = ids[clampi(maxi(ids.find(selected), 0) + delta, 0, ids.size() - 1)]
	_show_selection()


## Move the cursor a line down (up when negative) in the grid, to the same column or the last card of that line.
func move_line(dir: int) -> void:
	var all := rows()
	var starts := line_starts()
	var idx := -1
	for i in all.size():
		if all[i].get("id", "") == selected:
			idx = i
	if idx < 0 or starts.is_empty():
		return
	var li := 0
	for k in starts.size():
		if starts[k] <= idx:
			li = k
	var col := idx - starts[li]
	var t := li + dir
	while t >= 0 and t < starts.size() and all[starts[t]].has("header"):
		t += dir
	if t < 0 or t >= starts.size():
		return
	var last := (starts[t + 1] if t + 1 < starts.size() else all.size()) - 1
	selected = all[mini(starts[t] + col, last)]["id"]
	_show_selection()


## The row indices where a line of the grid starts: a header is a line of its own, a group's cards run COLS to a line.
func line_starts() -> Array[int]:
	var out: Array[int] = []
	var all := rows()
	var col := 0
	for i in all.size():
		if all[i].has("header"):
			out.append(i)
			col = 0
		else:
			if col == 0:
				out.append(i)
			col = (col + 1) % COLS
	return out


## Queue recipe `id`. Returns "" or the reason it was refused; either way it is the message on screen.
func craft(id: String) -> String:
	var s = ship()
	if s == null:
		return "no ship"
	var why: String = s.crafting.enqueue(id, s.inventory, station_info(s, s.crafting.station_of(id)))
	if why == "":
		_say("Queued " + _name(id), false)
	elif not s.crafting.is_known(id):
		_say("%s: %s" % [_name(id), BLUEPRINT_HELP], true)
	else:
		_say("%s: %s" % [_name(id), why], true)
	return why


## Enter or a double-click on recipe `id`: queue it.
func activate(id: String) -> String:
	return craft(id) if id != "" else "nothing selected"


func craft_selected() -> String:
	return craft(selected) if selected != "" else "nothing selected"


## Cancel queued job `index` of the shown station (its materials come back). False when there is no such job.
func cancel_job(index: int) -> bool:
	var s = ship()
	if s == null or index < 0 or index >= s.crafting.queue_of(station).size():
		return false
	var id: String = s.crafting.queue_of(station)[index]["recipe"]
	s.crafting.cancel(index, s.inventory, station)
	_say("Cancelled %s, materials back" % _name(id), false)
	return true


## Debug: learn a random blueprint that is still locked (drawn from the ship's seeded rng). Returns
## "" or why nothing happened.
func debug_unlock() -> String:
	var s = ship()
	if s == null:
		return "no ship"
	var locked: Array[String] = []
	for id in s.crafting.ids():
		if not s.crafting.is_known(id):
			locked.append(id)
	if locked.is_empty():
		_say("Every blueprint is known", true)
		return "none locked"
	var id: String = locked[sim.rng_of(s).randi() % locked.size()]
	s.crafting.unlock(id)
	open_recipe(id)
	_say("Unlocked blueprint: %s (debug)" % _name(id), false)
	return ""


## Debug: one of every boarding mod, every tier (nine items), into the hold. Returns "" or why nothing happened.
func debug_mods() -> String:
	var s = ship()
	if s == null:
		return "no ship"
	for id in Mods.ids():
		for tier in [1, 2, 3]:
			s.inventory.add(Mods.item_id(str(id), int(tier)), 1)
	_say("The nine boarding mods are in the hold (debug)", false)
	return ""


func _say(text: String, bad: bool) -> void:
	message = text
	message_bad = bad


func _name(recipe_id: String) -> String:
	var s = ship()
	return s.crafting.name_of(s.crafting.def(recipe_id)["output"]["item"], s.components)


# --- input ----------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if not (e is InputEventKey):
		return
	if not visible:
		if e.pressed and not e.echo and e.keycode == KEY_C and not e.ctrl_pressed and not e.alt_pressed and not e.meta_pressed and _can_open():
			open()
			_handled()
		return
	if BreachPrompt.claims(e):
		return  # R and V answer the breach card, whatever window is open
	_handled()
	if not e.pressed:
		return
	match e.keycode:
		KEY_UP:
			move_line(-1)
		KEY_DOWN:
			move_line(1)
		KEY_LEFT:
			move(-1)
		KEY_RIGHT:
			move(1)
		KEY_PAGEUP:
			move(-6)
		KEY_PAGEDOWN:
			move(6)
		_:
			if e.echo:
				return
			match e.keycode:
				KEY_C, KEY_ESCAPE:
					close()
				KEY_TAB:
					next_station()
				KEY_ENTER, KEY_KP_ENTER:
					activate(selected)
				KEY_U:
					if debug_keys:
						debug_unlock()
				KEY_M:
					if debug_keys:
						debug_mods()
				KEY_SLASH, KEY_QUESTION:
					help_open = not help_open


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hover_row = row_at(e.position)
		hover_job = job_at(e.position)
		hover_kw = {}
		for c in chips_at:
			if c[0].has_point(e.position):
				hover_kw = c[1]
				hover_rect = c[0]
	elif e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				var job := job_at(e.position)
				var row := row_at(e.position)
				var tab := tab_at(e.position)
				if help_rect().has_point(e.position):
					help_open = not help_open
				elif tab >= 0:
					set_station(STATION_IDS[tab])
				elif job >= 0:
					cancel_job(job)
				elif station == "smelter" and hint_button_rect().has_point(e.position) and no_smelter_recipe() != "":
					open_recipe(no_smelter_recipe())
				elif station == Crafting.FABRICATOR and upgrade_rect().has_point(e.position) and fab_upgrade()["next"] != 0:
					upgrade_fab()
				elif queue_rect_btn().has_point(e.position) and not help_open:
					craft_selected()
				elif row >= 0 and rows()[row].has("id"):
					selected = rows()[row]["id"]
					if e.double_click:
						craft_selected()  # one click selects and pins the card; two queue
			MOUSE_BUTTON_WHEEL_UP:
				_scroll(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_scroll(1)
	accept_event()


## May the panel open now? Not in a fight, not while the soldier is aboard another vessel, and not over the ship picker.
func _can_open() -> bool:
	var combat := get_node_or_null("../../Combat")
	if combat != null and combat.get("active"):
		return false
	var board := get_node_or_null("../../Board")
	if board != null and board.get("active"):
		return false
	var kit_panel := get_node_or_null("../CrewKitPanel")
	if kit_panel != null and kit_panel.visible:
		return false
	var picker := get_node_or_null("../../PickerLayer/ShipPicker")
	return picker == null or not picker.visible


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


# --- layout ---------------------------------------------------------------------------------------

func panel_rect() -> Rect2:
	return Rect2(Vector2(MARGIN, MARGIN), size - Vector2(MARGIN, MARGIN) * 2.0)


func list_rect() -> Rect2:
	var p := panel_rect()
	return Rect2(p.position + Vector2(PAD, TITLE_H), Vector2(p.size.x * 0.5 - PAD, p.size.y - TITLE_H - CARGO_H - PAD))


## The middle column: the selected recipe described, or how crafting works.
func details_rect() -> Rect2:
	var p := panel_rect()
	var l := list_rect()
	return Rect2(Vector2(l.end.x + GAP, l.position.y), Vector2(p.size.x * 0.26, l.size.y))


## The right column: the station and its queue.
func side_rect() -> Rect2:
	var p := panel_rect()
	var d := details_rect()
	return Rect2(Vector2(d.end.x + GAP, d.position.y), Vector2(p.end.x - PAD - d.end.x - GAP, d.size.y))


func cargo_rect() -> Rect2:
	var p := panel_rect()
	return Rect2(Vector2(p.position.x + PAD, p.end.y - CARGO_H), Vector2(p.size.x - 2.0 * PAD, CARGO_H - PAD))


## The Queue button at the foot of the pinned card (the details column).
func queue_rect_btn() -> Rect2:
	var r := details_rect()
	return Rect2(r.end.x - 12.0 - 150.0, r.end.y - 44.0, 150.0, 32.0)


func queue_rect() -> Rect2:
	var r := side_rect()
	var h := FAB_BOX_H if station == Crafting.FABRICATOR else FAB_H
	return Rect2(r.position + Vector2(0.0, h + GAP), Vector2(r.size.x, r.size.y - h - GAP))


## The tab button of station `i` of STATION_IDS, in the title row after the title (the top right is under the HUD's tide box).
func tab_rect(i: int) -> Rect2:
	var p := panel_rect()
	var x := p.position.x + 250.0
	for k in i:
		x += TAB_W[k] + 4.0
	return Rect2(x, p.position.y + 12.0, TAB_W[i], 32.0)


## The "?" button after the tabs: how crafting works.
func help_rect() -> Rect2:
	var t := tab_rect(STATION_IDS.size() - 1)
	return Rect2(t.end.x + 8.0, t.position.y, 32.0, t.size.y)


## The tab at `p`, or -1.
func tab_at(p: Vector2) -> int:
	for i in STATION_IDS.size():
		if tab_rect(i).has_point(p):
			return i
	return -1


func job_rect(i: int) -> Rect2:
	var q := queue_rect()
	return Rect2(q.position + Vector2(8.0, 40.0 + i * (JOB_H + 6.0)), Vector2(q.size.x - 16.0, JOB_H))


## The width of a card of the grid.
func card_w() -> float:
	return (list_rect().size.x - (COLS - 1) * CARD_GAP) / COLS


## The rect of row `i` of rows() as drawn: a header across the list, a card in its column (rows before `top`, and cards that do not
## fit under the list's foot, are not on screen: an empty rect).
func row_rect(i: int) -> Rect2:
	var l := list_rect()
	var all := rows()
	if i < top or i >= all.size():
		return Rect2()
	var y := l.position.y
	var col := 0
	for k in range(top, i + 1):
		if all[k].has("header"):
			if col > 0:
				y += CARD_H + CARD_GAP
				col = 0
			if k == i:
				var h := Rect2(Vector2(l.position.x, y), Vector2(l.size.x, HEAD_H))
				return h if h.end.y + CARD_H <= l.end.y else Rect2()  # a header is shown only with a line of cards under it
			y += HEAD_H
			continue
		if k == i:
			var c := Rect2(Vector2(l.position.x + col * (card_w() + CARD_GAP), y), Vector2(card_w(), CARD_H))
			return c if c.end.y <= l.end.y else Rect2()
		col += 1
		if col == COLS:
			col = 0
			y += CARD_H + CARD_GAP
	return Rect2()


## The row at `p`, or -1.
func row_at(p: Vector2) -> int:
	var all := rows()
	for i in range(top, all.size()):
		if row_rect(i).has_point(p):
			return i
	return -1


## The queued job at `p`, or -1.
func job_at(p: Vector2) -> int:
	var s = ship()
	if s == null:
		return -1
	for i in s.crafting.queue_of(station).size():
		if job_rect(i).has_point(p):
			return i
	return -1


## The wheel: `dir` lines down (up when negative).
func _scroll(dir: int) -> void:
	var starts := line_starts()
	var at := 0
	for k in starts.size():
		if starts[k] <= top:
			at = k
	top = starts[clampi(at + dir, 0, starts.size() - 1)] if not starts.is_empty() else 0


## Scroll so the selected recipe (and its category header) is on screen.
func _show_selection() -> void:
	var all := rows()
	var idx := -1
	for i in all.size():
		if all[i].get("id", "") == selected:
			idx = i
	if idx < 0:
		top = 0
		return
	var starts := line_starts()
	var li := 0
	for k in starts.size():
		if starts[k] <= idx:
			li = k
	var first: int = starts[li - 1] if li > 0 and all[starts[li - 1]].has("header") and starts[li - 1] == starts[li] - 1 else starts[li]
	if first < top:
		top = first
	while top < idx and row_rect(idx).size == Vector2.ZERO:
		var nxt := 0
		for k in starts.size():
			if starts[k] > top:
				nxt = starts[k]
				break
		if nxt <= top:
			break
		top = nxt


# --- drawing --------------------------------------------------------------------------------------

func _draw() -> void:
	var s = ship()
	if s == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	var p := panel_rect()
	_panel(p)
	_text(str(TAB_NAMES[station]).to_upper(), p.position + Vector2(PAD, 36.0), 26, TEXT)
	_text(message, Vector2(help_rect().end.x + 16.0, p.position.y + 34.0), 16, BAD if message_bad else GOOD)
	_draw_tabs()
	var fab := station_info(s)
	_draw_list(s, fab)
	_draw_details()
	if station == Crafting.FABRICATOR:
		_draw_fabricator(s, fab)
		_draw_queue(s)
	else:
		_draw_smelter(s, fab)
		_draw_queue(s)
	_draw_cargo(s)
	_draw_hover_card(s)


func _draw_tabs() -> void:
	var h := help_rect()
	draw_rect(h, ROW_BG if help_open else PANEL_BG)
	draw_rect(h, EDGE if help_open else EDGE_DIM, false, 2.0 if help_open else 1.0)
	_text("?", h.position + Vector2(0.0, 22.0), 18, TEXT if help_open else DIM_TEXT, h.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	for i in STATION_IDS.size():
		var r := tab_rect(i)
		var on := STATION_IDS[i] == station
		draw_rect(r, ROW_BG if on else PANEL_BG)
		draw_rect(r, EDGE if on else EDGE_DIM, false, 2.0 if on else 1.0)
		_text(tab_label(STATION_IDS[i]), r.position + Vector2(0.0, 22.0), 16, TEXT if on else DIM_TEXT, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)


## The recipe under the cursor, described (describe.gd): what its output does, its keywords, its stats, one line of lore.
func described() -> Dictionary:
	var s = ship()
	if s == null or selected == "":
		return {}
	return Describe.of(s.crafting.def(selected)["output"]["item"], s)


## How crafting works, a paragraph each (the "?" box).
func help_lines() -> Array[String]:
	return [
		"Click a recipe (or Up/Down, Enter) to queue it. Its materials leave the cargo.",
		"Fabricator: every blueprint you know, grouped. Needs power. The Upgrade button in its box raises its level and pays at once. Arms and rigs in its room make it 25% faster each (up to +50%); a laser cutter or nanoforge there gives it that tool.",
		"Smelter (Tab): scrap and ore into refined materials. A crew member at it adds %d%% speed." % roundi(Processing.manned_speed() * 100.0),
		"Finished parts land in the hold: place them from the build palette (B). Click a queued job to cancel it.",
		"Hover a card for its name and stats; click to select it; Enter, a double-click or the Queue button queues it. A dimmed card is a blueprint you know but cannot make yet: select it to see why (fabricator level, a tool, materials).",
		"Only recipes whose blueprint you know are listed (the box at the right says how many you found): scan salvage, or find one in events and stores.",
	]


func _draw_details() -> void:
	chips_at = []
	var r := details_rect()
	_panel(r, ROW_BG)
	var x := r.position.x + 12.0
	var w := r.size.x - 24.0
	if help_open:
		_text("HOW CRAFTING WORKS", r.position + Vector2(12.0, 24.0), 15, AMBER)
		var yy := r.position.y + 38.0
		for line in help_lines():
			yy += _para(line, Vector2(x, yy), w, 14, TEXT) + 10.0
		return
	var d := described()
	if d.is_empty():
		_text("Nothing selected", r.position + Vector2(12.0, 24.0), 15, DIM_TEXT)
		return
	_text(_name(selected).to_upper(), r.position + Vector2(12.0, 24.0), 15, AMBER)
	var y := r.position.y + 38.0
	var limit := r.end.y - 56.0
	_draw_pinned_foot(r)
	if d["what"] != "":
		y += _para(d["what"], Vector2(x, y), w, 14, TEXT) + 8.0
	if not d["keywords"].is_empty():
		var lay := UiKit.chip_layout(d["keywords"], Vector2(x, y), w, 11)
		for c in lay:
			UiKit.keyword_chip(self, c[0], c[1], 11, c[1] == hover_kw)
		chips_at = lay
		y += lay[lay.size() - 1][0].end.y - y + 10.0
	for row in d["stats"]:
		if y > limit:
			return
		_text(str(row[0]), Vector2(x, y + 13.0), 13, DIM_TEXT)
		y += _para(str(row[1]), Vector2(x + 84.0, y), w - 84.0, 13, TEXT) + 1.0
	if y <= limit and d["lore"] != "":
		_para(d["lore"], Vector2(x, y + 8.0), w, 13, DIM_TEXT)
	if not hover_kw.is_empty():
		var lines := UiKit.wrap(hover_kw["hover"], w - 16.0, 12)
		var tw := 16.0
		for l in lines:
			tw = maxf(tw, UiKit.text_width(l, 12) + 16.0)
		UiKit.note(self, lines, Vector2(minf(hover_rect.position.x, r.end.x - 8.0 - tw), hover_rect.end.y + 4.0), hover_kw["color"])


## The foot of the pinned card: the Queue button (a click queues the selected recipe), or why it cannot be queued.
func _draw_pinned_foot(r: Rect2) -> void:
	var why := reason(selected)
	var b := queue_rect_btn()
	var ok := why == ""
	UiKit.button(self, b, false, ok and b.has_point(get_local_mouse_position()))
	_text("Queue" if ok else "Can't queue", b.position + Vector2(0.0, 22.0), 16, GOOD if ok else DIM_TEXT, b.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if not ok:
		var f := ThemeDB.fallback_font
		draw_multiline_string(f, Vector2(r.position.x + 12.0, r.end.y - 40.0), why.substr(0, 1).to_upper() + why.substr(1), HORIZONTAL_ALIGNMENT_LEFT, b.position.x - r.position.x - 20.0, 13, 2, AMBER)


## The hover card: the row under the mouse (not the pinned one), as PartCard shows it, to the right of the row.
func _draw_hover_card(s) -> void:
	var rows_all := rows()
	if hover_row < 0 or hover_row >= rows_all.size() or not rows_all[hover_row].has("id") or rows_all[hover_row]["id"] == selected or help_open:
		return
	var id: String = rows_all[hover_row]["id"]
	var card := hover_card(id)
	var row := row_rect(hover_row)
	var h := PartCard.height(card, HOVER_W)
	var p := panel_rect()
	var x := row.end.x + 10.0
	if x + HOVER_W > p.end.x - 6.0:
		x = row.position.x - 10.0 - HOVER_W  # no room on the right: on the left of the card
	PartCard.draw(self, Vector2(maxf(x, p.position.x + 6.0), clampf(row.position.y, p.position.y + TITLE_H, p.end.y - CARGO_H - h)), HOVER_W, card)


## The words of the hover card of recipe `id` (part_card.gd): name, what it does, key stats, materials, and why it cannot be queued.
func hover_card(id: String) -> Dictionary:
	var s = ship()
	if s == null or not s.crafting.has(id):
		return {}
	return PartCard.data(id, s, reason(id))


## Draw `text` wrapped to `width` with its top at `at`; returns its height.
func _para(text: String, at: Vector2, width: float, font_size: int, col: Color) -> float:
	var font := ThemeDB.fallback_font
	draw_multiline_string(font, at + Vector2(0.0, font_size), text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, -1, col)
	return font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y


func _draw_list(s, fab: Dictionary) -> void:
	var l := list_rect()
	var all := rows()
	if all.is_empty():
		_para(empty_text(), l.position + Vector2(8.0, 10.0), l.size.x - 16.0, 16, DIM_TEXT)
		return
	var last := top - 1
	for i in range(top, all.size()):
		var r := row_rect(i)
		if r.size == Vector2.ZERO:
			break
		last = i
		var row: Dictionary = all[i]
		if row.has("header"):
			_text(str(row["header"]).to_upper(), r.position + Vector2(4.0, 21.0), 15, AMBER)
			draw_line(r.position + Vector2(0.0, HEAD_H - 4.0), r.position + Vector2(r.size.x, HEAD_H - 4.0), EDGE_DIM, 1.0)
		else:
			PicCard.draw(self, r, s, card_spec(row["id"]), row["id"] == selected, i == hover_row, Time.get_ticks_msec() / 1000.0)
	if top > 0:
		_text("^ more", Vector2(l.end.x - 70.0, l.position.y - 6.0), 13, DIM_TEXT)
	if last < all.size() - 1:
		_text("v more", Vector2(l.end.x - 70.0, l.end.y + 14.0), 13, DIM_TEXT)


## What the list says when it has no card: no blueprint is known for the station.
func empty_text() -> String:
	return "No blueprints known here yet. Learn them from scans, events, stores and boarding."


## The picture card of recipe `id` (pic_card.gd's spec): the output's sprite and figures, its materials (red when short), NEW on the
## the Fabricator tab, x3 for a batch, the fabricator level it needs (red when the station is too low). No name.
func card_spec(id: String) -> Dictionary:
	var s = ship()
	var rec: Dictionary = s.crafting.def(id)
	var out: String = str(rec["output"]["item"])
	var entry := {"kind": "item", "id": "item"}
	var stats := []
	var aim := ""
	var line := "standard"
	if s.components.has(out):
		entry = {"kind": "part", "id": out}
		var g := Describe.glance(out, s)
		stats = g["stats"]
		aim = g["aim"]
		line = "unique" if s.components.def(out).get("unique", false) else str(s.components.def(out).get("line", "standard"))
	elif s.crafting.materials.has(out) or UiKit.icon_art(out) != null or not Thumbs.item_art(out).is_empty():
		entry = {"kind": "item", "id": out}
	var tags := []
	if fresh_now.has(id):
		tags.append("NEW")
	if int(rec["output"]["count"]) > 1:
		tags.append("x%d" % int(rec["output"]["count"]))
	var meta := "L%d" % int(rec["fab_level"])
	var level_low: bool = int(station_info(s)["level"]) < int(rec["fab_level"])
	var can: bool = s.crafting.can_craft(id, s.inventory, station_info(s)) == ""
	return {"entry": entry, "line": line, "stats": stats, "aim": aim, "cost": rec["materials"], "short": s.inventory.missing(rec["materials"]),
		"held": -1, "tags": tags, "key": 0, "meta": meta, "meta_bad": level_low, "dim": not can}


## "34 of 120 found": the blueprints you know out of every recipe in the game.
func found_text() -> String:
	var s = ship()
	return "%d of %d found" % [s.crafting.known.size(), s.crafting.ids().size()] if s != null else ""


## What to do about having no smelter: {text, recipe}, from the cheapest smelter recipe you know (its name and costs are read from the data).
func no_smelter_hint(s) -> Dictionary:
	var best := ""
	for id in s.crafting.ids():
		var rec: Dictionary = s.crafting.def(id)
		var item := str(rec["output"]["item"])
		if not s.crafting.is_known(id) or rec["station"] != Crafting.FABRICATOR or not s.components.has(item) or str(s.components.def(item).get("family", "")) != "smelter":
			continue
		if best == "" or _cost_key(s, id) < _cost_key(s, best):
			best = id
	if best == "":
		return {"text": "No smelter aboard. Build one in build mode (B).", "recipe": ""}
	var costs := []
	for m in s.crafting.def(best)["materials"]:
		costs.append("%d %s" % [s.crafting.def(best)["materials"][m], s.crafting.name_of(m).to_lower()])
	return {"text": "No smelter aboard. Craft a %s at the fabricator (%s), then place it in build mode (B)." % [_name(best), ", ".join(costs)], "recipe": best}


func _cost_key(s, id: String) -> Array:
	var total := 0
	for m in s.crafting.def(id)["materials"]:
		total += int(s.crafting.def(id)["materials"][m])
	return [int(s.components.def(str(s.crafting.def(id)["output"]["item"])).get("tier", 0)), total]


## The recipe the no-smelter button opens ("" when there is no smelter missing or no recipe to show).
func no_smelter_recipe() -> String:
	var s = ship()
	if s == null or int(station_info(s, "smelter")["count"]) > 0:
		return ""
	return str(no_smelter_hint(s)["recipe"])


## The button under the no-smelter text: open that recipe at the fabricator.
func hint_button_rect() -> Rect2:
	var r := side_rect()
	return Rect2(r.position.x + 10.0, r.position.y + FAB_H - 38.0, 190.0, 28.0)


## The fabricator box's line: "Level 2 · Tools: laser cutter · Speed +25%" (`with_level` false: without the "Level 2 · ").
static func fab_line(fab: Dictionary, with_level := true) -> String:
	var tools: Array = fab["tools"]
	var out := "Tools: " + (", ".join(tools).replace("_", " ") if not tools.is_empty() else "none")
	out += " \u00b7 Speed +%d%%" % roundi((float(fab.get("speed", 1.0)) - 1.0) * 100.0)
	return ("Level %d \u00b7 " % int(fab["level"]) + out) if with_level else out


## The fabricator's upgrade card (workshop.gd upgrade_info) for the ship's fabricator; "next" is 0 at the top level or with no fabricator.
func fab_upgrade() -> Dictionary:
	var s = ship()
	var uid: int = Workshop.fab_uid(s) if s != null else -1
	if uid < 0:
		return {"level": 0, "next": 0, "cost": {}, "short": {}, "new": 0, "total": 0, "text": "", "can": false}
	return Workshop.upgrade_info(s, uid)


## The Upgrade button's words: what is missing when short, else "Upgrade to level N".
func upgrade_label() -> String:
	var s = ship()
	var inf := fab_upgrade()
	if s == null or int(inf["next"]) == 0:
		return ""
	if inf["can"]:
		return "Upgrade to level %d" % int(inf["next"])
	var parts := PackedStringArray()
	for m in inf["short"]:
		parts.append("%d %s" % [inf["short"][m], s.crafting.name_of(m).to_lower()])
	return "Need " + ", ".join(parts)


## Pay for and raise the fabricator one level (workshop.gd's upgrade, as the build-mode card does). Returns "" or why not.
func upgrade_fab() -> String:
	var s = ship()
	if s == null:
		return "no ship"
	var uid: int = Workshop.fab_uid(s)
	if uid < 0:
		_say("No fabricator on this ship", true)
		return "No fabricator on this ship"
	var why := Workshop.upgrade(s, uid)
	if why != "":
		_say(why, true)
		Audio.fx(self, "invalid")
		return why
	_say("Fabricator upgraded to level %d" % int(s.components.instances[uid]["fab_level"]), false)
	flash = 0.7
	Audio.fx(self, "unlock")
	s.mark_dirty()
	_ids_key = ""
	return ""


## The Upgrade button, at the foot of the fabricator's box.
func upgrade_rect() -> Rect2:
	var r := side_rect()
	return Rect2(r.position.x + 10.0, r.position.y + FAB_BOX_H - 42.0, r.size.x - 20.0, 32.0)


func _draw_fabricator(s, fab: Dictionary) -> void:
	var r := side_rect()
	var box := Rect2(r.position, Vector2(r.size.x, FAB_BOX_H))
	_panel(box, ROW_BG)
	_text("FABRICATOR", box.position + Vector2(10.0, 24.0), 15, AMBER)
	_text(found_text(), box.position + Vector2(0.0, 24.0), 13, DIM_TEXT, box.size.x - 10.0, HORIZONTAL_ALIGNMENT_RIGHT)
	var status := "Level %d" % fab["level"]
	var col := GOOD
	if int(fab["count"]) == 0:
		status = "No fabricator on this ship"
		col = BAD
	elif int(fab["level"]) == 0:
		status = "Offline: no power"
		col = BAD
	_text(status, box.position + Vector2(10.0, 54.0), 22, col)
	_text(fab_line(fab, false), box.position + Vector2(10.0, 80.0), 14, TEXT)
	var counts := {}
	for uid in fab["modules"]:
		var nm: String = s.components.def(s.components.instances[uid]["id"]).get("name", "?")
		counts[nm] = int(counts.get(nm, 0)) + 1
	var names: Array = counts.keys()
	names.sort()
	var parts := PackedStringArray()
	for nm in names:
		parts.append("%s x%d" % [nm, counts[nm]])
	draw_multiline_string(ThemeDB.fallback_font, box.position + Vector2(10.0, 102.0),
		"Modules: " + (", ".join(parts) if not parts.is_empty() else "none counted"), HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 20.0, 14, 3, TEXT)
	if int(fab["count"]) == 0:
		return
	var inf := fab_upgrade()
	var y := box.position.y + 150.0
	draw_line(Vector2(box.position.x + 10.0, y), Vector2(box.end.x - 10.0, y), EDGE_DIM, 1.0)
	if int(inf["next"]) == 0:
		_text("Fully upgraded", Vector2(box.position.x + 10.0, y + 30.0), 18, GOOD)
		return
	var h := _para(str(inf["text"]), Vector2(box.position.x + 10.0, y + 6.0), box.size.x - 20.0, 14, TEXT)
	var cx := box.position.x + 10.0
	var cy := y + 12.0 + h
	for m in inf["cost"]:
		var t := str(inf["cost"][m])
		UiKit.icon(self, str(m), Rect2(cx, cy, 16.0, 16.0))
		_text(t, Vector2(cx + 19.0, cy + 13.0), 14, BAD.lightened(0.2) if inf["short"].has(m) else TEXT)
		cx += 19.0 + UiKit.text_width(t, 14) + 12.0
	var b := upgrade_rect()
	var ok: bool = inf["can"]
	UiKit.button(self, b, false, ok and b.has_point(get_local_mouse_position()))
	_text(upgrade_label(), b.position + Vector2(0.0, 22.0), 15, GOOD if ok else AMBER, b.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if flash > 0.0:
		var a := flash / 0.7
		draw_rect(box.grow(2.0 + 8.0 * (1.0 - a)), Color(0.55, 1.0, 0.8, a), false, 2.0)


## The smelter's box: its level, speed (manned or not), tools, count and heat.
func _draw_smelter(s, st: Dictionary) -> void:
	var r := side_rect()
	var box := Rect2(r.position, Vector2(r.size.x, FAB_H))
	_panel(box, ROW_BG)
	_text("SMELTER", box.position + Vector2(10.0, 24.0), 15, AMBER)
	var status := "Level %d" % st["level"]
	var col := GOOD
	if int(st["count"]) == 0:
		var hint := no_smelter_hint(s)
		_para(hint["text"], box.position + Vector2(10.0, 34.0), box.size.x - 20.0, 14, BAD)
		if hint["recipe"] != "":
			var b := hint_button_rect()
			UiKit.button(self, b, false, b.has_point(get_local_mouse_position()))
			_text("Show the recipe", b.position + Vector2(0.0, 20.0), 15, GOOD, b.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		return
	elif int(st["level"]) == 0:
		status = "Offline: no power"
		col = BAD
	_text(status, box.position + Vector2(10.0, 54.0), 22, col)
	var tools: Array = st["tools"]
	if int(st["level"]) > 0:
		var speed := "Speed x%s, %s" % [str(snappedf(float(st["speed"]), 0.01)), "manned" if st["manned"] else "unmanned (+%d%% with crew)" % roundi(Processing.manned_speed() * 100.0)]
		_text(speed, box.position + Vector2(10.0, 78.0), 14, TEXT)
		var heat := ""
		var lead := int(st["uid"])
		if lead >= 0:
			var inst: Dictionary = s.components.instances[lead]
			heat = "   Heat %d%%" % roundi(float(inst["heat"]) / maxf(1.0, float(s.effective(inst["id"])["heat_limit"])) * 100.0)
		_text("Tools: %s   Smelters: %d%s" % [", ".join(tools) if not tools.is_empty() else "none", st["count"], heat], box.position + Vector2(10.0, 100.0), 14, TEXT)
	else:
		draw_multiline_string(ThemeDB.fallback_font, box.position + Vector2(10.0, 78.0), "No smelter. Build one (Utility tab) with a radiator beside it.", HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 20.0, 14, 3, DIM_TEXT)


func _draw_queue(s) -> void:
	var q := queue_rect()
	_panel(q, ROW_BG)
	var c = s.crafting
	var jobs: Array = c.queue_of(station)
	_text("QUEUE  %d/%d" % [jobs.size(), Crafting.QUEUE_MAX], q.position + Vector2(10.0, 24.0), 15, AMBER)
	if c.is_paused(station):
		_text("PAUSED", Vector2(q.position.x, q.position.y + 24.0), 15, BAD, q.size.x - 10.0, HORIZONTAL_ALIGNMENT_RIGHT)
	if jobs.is_empty():
		_text("Nothing queued", q.position + Vector2(10.0, 62.0), 15, DIM_TEXT)
		return
	for i in jobs.size():
		var job: Dictionary = jobs[i]
		var rec: Dictionary = c.def(job["recipe"])
		var jr := job_rect(i)
		draw_rect(jr, PANEL_BG)
		draw_rect(jr, BAD if i == hover_job else EDGE_DIM, false, 2.0 if i == hover_job else 1.0)
		_text(_name(job["recipe"]), jr.position + Vector2(8.0, 19.0), 15, TEXT)
		var note := "click to cancel" if i == hover_job else "%s / %s s" % [_num(job["progress"]), _num(rec["time"])]
		_text(note, Vector2(jr.position.x, jr.position.y + 19.0), 13, BAD if i == hover_job else DIM_TEXT, jr.size.x - 8.0, HORIZONTAL_ALIGNMENT_RIGHT)
		var bar := Rect2(jr.position + Vector2(8.0, 30.0), Vector2(jr.size.x - 16.0, 12.0))
		draw_rect(bar, Color("#0f141a"))
		var frac := clampf(job["progress"] / rec["time"], 0.0, 1.0)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), AMBER if (i == 0 and c.is_paused(station)) else GOOD)
		draw_rect(bar, EDGE_DIM, false, 1.0)


func _draw_cargo(s) -> void:
	var r := cargo_rect()
	_panel(r, ROW_BG)
	_text("CARGO", r.position + Vector2(10.0, 24.0), 15, AMBER)
	_text("C/Esc close   ?: help   Tab: next tab   Click: select   Enter / double-click / Queue: queue   Upgrade button: raise the fabricator   Click a job: cancel",
		r.position + Vector2(10.0, r.size.y - 10.0), 13, DIM_TEXT)
	var x := r.position.x + 90.0
	var y := r.position.y + 24.0
	for id in s.crafting.materials:
		var m: Dictionary = s.crafting.materials[id]
		var seg := "%s %d" % [m["name"], s.inventory.count(id)]
		var w := ThemeDB.fallback_font.get_string_size(seg, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 34.0
		if x + w > r.end.x - 8.0:
			x = r.position.x + 90.0
			y += 26.0
		draw_rect(Rect2(Vector2(x, y - 12.0), Vector2(12.0, 12.0)), Color(m["color"]))
		draw_rect(Rect2(Vector2(x, y - 12.0), Vector2(12.0, 12.0)), Color(0, 0, 0, 0.5), false, 1.0)
		_text(seg, Vector2(x + 18.0, y), 15, TEXT if s.inventory.count(id) > 0 else DIM_TEXT)
		x += w


## A chunky panel: a slate fill, a 2 px light border and a 1 px inner highlight.
func _panel(r: Rect2, fill := PANEL_BG) -> void:
	draw_rect(r, fill)
	draw_rect(r, EDGE, false, 2.0)
	draw_rect(r.grow(-3.0), HIGHLIGHT, false, 1.0)


## A figure: whole numbers plain, others with one decimal.
static func _num(v: float) -> String:
	return "%d" % roundi(v) if is_equal_approx(v, roundf(v)) else "%.1f" % v


func _text(text: String, at: Vector2, font_size: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(ThemeDB.fallback_font, at, text, align, width, font_size, col)
