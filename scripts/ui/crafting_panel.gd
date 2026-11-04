extends Control
## The crafting panel (C, in build or play mode): a fabricator screen over the game. Left: every recipe,
## grouped by category, the known ones first with what each needs (missing materials in red) and why it
## cannot be made yet, then the ones whose blueprint is missing, dimmed (not those of a unique or relic part, or of a
## people not met yet: racial tech stays hidden until learned). Middle: what the selected recipe makes, described
## (describe.gd), or how crafting works (? toggles it). Right: the fabricator (level, tools, workshop modules counted)
## and the queue with progress bars; a click on a queued job cancels it (the materials come back). Bottom: the
## cargo's materials. Tab (or a click on the tabs at the top) switches to the smelter (docs/CONTENT.md
## section 12): its recipes, its level, speed and tools, its own queue. Click a recipe, or select it with Up/Down and press Enter, to queue it. U
## unlocks a random locked blueprint (debug, until salvage gives real ones).
## While open it takes every key and click; the game keeps running behind it. It stays shut during a
## fight and while the ship picker is up. Rules are in crafting.gd and workshop.gd; this node reads
## input and draws, in the UI colours of docs/ART_STYLE.md.

const Crafting = preload("res://scripts/craft/crafting.gd")
const BreachPrompt = preload("res://scripts/ui/breach_prompt.gd")
const Workshop = preload("res://scripts/craft/workshop.gd")
const Processing = preload("res://scripts/craft/processing.gd")
const Describe = preload("res://scripts/ui/describe.gd")
const Content = preload("res://scripts/data/content.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Audio = preload("res://scripts/audio/audio.gd")
const Mods = preload("res://scripts/board/mods.gd")

const STATION_IDS: Array[String] = ["fabricator", "smelter"]  ## the tabs, in order
const CATEGORIES: Array[String] = ["system", "gear", "material", "module"]
const CATEGORY_NAMES := {"system": "Systems", "gear": "Gear", "material": "Materials", "module": "Modules"}
const BLUEPRINT_HELP := "Needs a blueprint"
const MARGIN := 40.0
const TITLE_H := 56.0
const CARGO_H := 96.0
const HEAD_H := 30.0  ## a category header row
const ROW_H := 62.0  ## a recipe row
const JOB_H := 52.0
const FAB_H := 140.0
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
var message_bad := false
var hover_row := -1  ## index into rows()
var hover_job := -1
var help_open := false  ## the middle column shows how crafting works, not the selected recipe
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


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


# --- the data the screen shows ------------------------------------------------------------------

## The player's ship (null before the scene is wired).
func ship():
	return sim.player_ship() if sim != null else null


## The ids of the recipes of the shown station in screen order: by category, the known ones first, then the ones
## whose blueprint is missing (as listed in data/recipes.json), minus the ones kept hidden (_hidden).
func recipe_ids() -> Array[String]:
	var s = ship()
	if s == null:
		return []
	var key := "%s|%d|%d|%d" % [station, s.crafting.known.size(), s.crafting.order.size(), s.get_instance_id()]
	if key == _ids_key:
		return _ids_cache
	var out: Array[String] = []
	for cat in CATEGORIES:
		for known in [true, false]:
			for id in s.crafting.ids():
				if s.crafting.def(id)["category"] == cat and s.crafting.station_of(id) == station and s.crafting.is_known(id) == known and (known or not _hidden(s, id)):
					out.append(id)
	_ids_key = key
	_ids_cache = out
	return out


## Is the unknown recipe `id` kept off the list: the part it makes is unique or a relic (found, never built), or it is
## racial tech of a people you have not met (a tech_* pack)? Learning the blueprint shows it.
func _hidden(s, id: String) -> bool:
	var d: Dictionary = s.components.def(s.crafting.def(id)["output"]["item"])
	return d.get("unique", false) or d.get("relic", false) or Content.origin("recipes", id).begins_with("tech_")


## The rows of the left column: {"header": text} for a category, {"id": recipe id} for a recipe.
func rows() -> Array:
	var out := []
	var s = ship()
	if s == null:
		return out
	var last := ""
	for id in recipe_ids():
		var cat: String = s.crafting.def(id)["category"]
		if cat != last:
			out.append({"header": CATEGORY_NAMES.get(cat, cat)})
			last = cat
		out.append({"id": id})
	return out


## The shown station's level, tools and speed (workshop.gd's or processing.gd's best result) for `s`.
func station_info(s) -> Dictionary:
	return Processing.best(s, station) if station != Crafting.FABRICATOR else Workshop.best(s)


## Why recipe `id` cannot be queued now ("" when it can): crafting.gd's reason, or a full queue.
func reason(id: String) -> String:
	var s = ship()
	if s == null:
		return "no ship"
	var why: String = s.crafting.can_craft(id, s.inventory, station_info(s))
	if why == "" and s.crafting.queue_of(s.crafting.station_of(id)).size() >= Crafting.QUEUE_MAX:
		return "queue full"
	return why


# --- actions (the keys and clicks call these) -----------------------------------------------------

func open() -> void:
	if not visible:
		Audio.fx(self, "open")
	visible = true
	if not recipe_ids().has(selected):
		selected = recipe_ids()[0] if not recipe_ids().is_empty() else ""
	message = ""
	_show_selection()
	queue_redraw()


func close() -> void:
	if visible:
		Audio.fx(self, "close")
	visible = false


## Show the tab of `id` ("fabricator" or "smelter"): its recipes and its queue. False for anything else.
func set_station(id: String) -> bool:
	if not STATION_IDS.has(id):
		return false
	station = id
	top = 0
	selected = recipe_ids()[0] if not recipe_ids().is_empty() else ""
	message = ""
	_show_selection()
	Audio.fx(self, "tab_switch")
	return true


## The other tab.
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


## Queue recipe `id`. Returns "" or the reason it was refused; either way it is the message on screen.
func craft(id: String) -> String:
	var s = ship()
	if s == null:
		return "no ship"
	var why: String = s.crafting.enqueue(id, s.inventory, station_info(s))
	if why == "":
		_say("Queued " + _name(id), false)
	elif not s.crafting.is_known(id):
		_say("%s: %s" % [_name(id), BLUEPRINT_HELP], true)
	else:
		_say("%s: %s" % [_name(id), why], true)
	return why


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
	station = s.crafting.station_of(id)
	selected = id
	_show_selection()
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
			move(-1)
		KEY_DOWN:
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
					craft_selected()
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
				elif row >= 0 and rows()[row].has("id"):
					selected = rows()[row]["id"]
					craft_selected()
			MOUSE_BUTTON_WHEEL_UP:
				top = maxi(top - 1, 0)
			MOUSE_BUTTON_WHEEL_DOWN:
				top = mini(top + 1, maxi(rows().size() - 1, 0))
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
	return Rect2(p.position + Vector2(PAD, TITLE_H), Vector2(p.size.x * 0.42 - PAD, p.size.y - TITLE_H - CARGO_H - PAD))


## The middle column: the selected recipe described, or how crafting works.
func details_rect() -> Rect2:
	var p := panel_rect()
	var l := list_rect()
	return Rect2(Vector2(l.end.x + GAP, l.position.y), Vector2(p.size.x * 0.3, l.size.y))


## The right column: the station and its queue.
func side_rect() -> Rect2:
	var p := panel_rect()
	var d := details_rect()
	return Rect2(Vector2(d.end.x + GAP, d.position.y), Vector2(p.end.x - PAD - d.end.x - GAP, d.size.y))


func cargo_rect() -> Rect2:
	var p := panel_rect()
	return Rect2(Vector2(p.position.x + PAD, p.end.y - CARGO_H), Vector2(p.size.x - 2.0 * PAD, CARGO_H - PAD))


func queue_rect() -> Rect2:
	var r := side_rect()
	return Rect2(r.position + Vector2(0.0, FAB_H + GAP), Vector2(r.size.x, r.size.y - FAB_H - GAP))


## The tab button of station `i` of STATION_IDS, in the title row after the title (the top right is under the HUD's tide box).
func tab_rect(i: int) -> Rect2:
	var p := panel_rect()
	return Rect2(p.position.x + 250.0 + i * 124.0, p.position.y + 12.0, 120.0, 32.0)


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


func _row_h(row: Dictionary) -> float:
	return HEAD_H if row.has("header") else ROW_H


## The rect of row `i` of rows() as drawn (rows before `top` are not on screen: an empty rect).
func row_rect(i: int) -> Rect2:
	var l := list_rect()
	var all := rows()
	if i < top or i >= all.size():
		return Rect2()
	var y := l.position.y
	for k in range(top, i):
		y += _row_h(all[k])
	var r := Rect2(Vector2(l.position.x, y), Vector2(l.size.x, _row_h(all[i])))
	return r if r.end.y <= l.end.y else Rect2()


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
	if idx < top or (idx == top + 1 and top > 0 and all[top].has("header")):
		top = idx - 1 if idx > 0 and all[idx - 1].has("header") else idx
	var l := list_rect()
	while top < idx and _span(all, top, idx) > l.size.y:
		top += 1


## The height of rows first..last, both included.
func _span(all: Array, first: int, last: int) -> float:
	var h := 0.0
	for k in range(first, last + 1):
		h += _row_h(all[k])
	return h


# --- drawing --------------------------------------------------------------------------------------

func _draw() -> void:
	var s = ship()
	if s == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	var p := panel_rect()
	_panel(p)
	_text(str(Crafting.STATIONS[station]).to_upper(), p.position + Vector2(PAD, 36.0), 26, TEXT)
	_text(message, p.position + Vector2(560.0, 34.0), 16, BAD if message_bad else GOOD)
	_draw_tabs()
	var fab := station_info(s)
	_draw_list(s, fab)
	_draw_details()
	if station == Crafting.FABRICATOR:
		_draw_fabricator(s, fab)
	else:
		_draw_smelter(s, fab)
	_draw_queue(s)
	_draw_cargo(s)


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
		_text(str(Crafting.STATIONS[STATION_IDS[i]]), r.position + Vector2(0.0, 22.0), 16, TEXT if on else DIM_TEXT, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)


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
		"Fabricator: parts, gear, modules. Needs power. Workshop modules in its room raise its level.",
		"Smelter (Tab): scrap and ore into refined materials. A crew member at it adds %d%% speed." % roundi(Processing.manned_speed() * 100.0),
		"Finished parts land in the hold: place them from the build palette (B). Click a queued job to cancel it.",
		"Dimmed recipes need a blueprint: scan salvage, or find one in events and stores.",
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
	var limit := r.end.y - 10.0
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


## Draw `text` wrapped to `width` with its top at `at`; returns its height.
func _para(text: String, at: Vector2, width: float, font_size: int, col: Color) -> float:
	var font := ThemeDB.fallback_font
	draw_multiline_string(font, at + Vector2(0.0, font_size), text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, -1, col)
	return font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y


func _draw_list(s, fab: Dictionary) -> void:
	var l := list_rect()
	var all := rows()
	if all.is_empty():
		_text("No recipes here", l.position + Vector2(8.0, 24.0), 16, DIM_TEXT)
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
			_draw_recipe(s, fab, row["id"], r, i == hover_row)
	if top > 0:
		_text("^ more", Vector2(l.end.x - 70.0, l.position.y - 6.0), 13, DIM_TEXT)
	if last < all.size() - 1:
		_text("v more", Vector2(l.end.x - 70.0, l.end.y + 14.0), 13, DIM_TEXT)


func _draw_recipe(s, fab: Dictionary, id: String, r: Rect2, hot: bool) -> void:
	var rec: Dictionary = s.crafting.def(id)
	var why := reason(id)
	var known: bool = s.crafting.is_known(id)
	if not known:
		why = BLUEPRINT_HELP
	var picked := id == selected
	draw_rect(r.grow(-2.0), ROW_BG if known else PANEL_BG)
	if not known:
		draw_rect(r.grow(-2.0), Color(0.0, 0.0, 0.0, 0.2))  # dimmed: its blueprint is missing
	draw_rect(r.grow(-2.0), EDGE if picked else (AMBER if hot else EDGE_DIM), false, 3.0 if picked else 1.0)
	var out: Dictionary = rec["output"]
	var title := _name(id) + (" x%d" % out["count"] if out["count"] > 1 else "")
	_text(title, r.position + Vector2(12.0, 21.0), 16, TEXT if why == "" else DIM_TEXT)
	var meta := "L%d   %s s" % [rec["fab_level"], _num(rec["time"])]
	if not rec["tools"].is_empty():
		meta += "   " + ", ".join(rec["tools"])
	var level_ok: bool = int(fab["level"]) >= rec["fab_level"]
	_text(meta, Vector2(r.position.x, r.position.y + 21.0), 13, DIM_TEXT if level_ok or not known else BAD, r.size.x - 12.0, HORIZONTAL_ALIGNMENT_RIGHT)
	var x := r.position.x + 12.0
	var short: Dictionary = s.inventory.missing(rec["materials"])
	for m in rec["materials"]:
		var have: int = s.inventory.count(m)
		var seg := "%s %d" % [s.crafting.name_of(m), rec["materials"][m]] if not short.has(m) else "%s %d/%d" % [s.crafting.name_of(m), have, rec["materials"][m]]
		_text(seg, Vector2(x, r.position.y + 39.0), 13, BAD if short.has(m) and known else DIM_TEXT)
		x += ThemeDB.fallback_font.get_string_size(seg, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14.0
	_text("Enter / click to craft" if why == "" else why, r.position + Vector2(12.0, 56.0), 12, GOOD if why == "" else (DIM_TEXT if not known else AMBER))


func _draw_fabricator(s, fab: Dictionary) -> void:
	var r := side_rect()
	var box := Rect2(r.position, Vector2(r.size.x, FAB_H))
	_panel(box, ROW_BG)
	_text("FABRICATOR", box.position + Vector2(10.0, 24.0), 15, AMBER)
	var status := "Level %d" % fab["level"]
	var col := GOOD
	if int(fab["count"]) == 0:
		status = "No fabricator on this ship"
		col = BAD
	elif int(fab["level"]) == 0:
		status = "Offline: no power"
		col = BAD
	_text(status, box.position + Vector2(10.0, 54.0), 22, col)
	var tools: Array = fab["tools"]
	_text("Tools: " + (", ".join(tools) if not tools.is_empty() else "none"), box.position + Vector2(10.0, 80.0), 14, TEXT)
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


## The smelter's box: its level, speed (manned or not), tools, count and heat.
func _draw_smelter(s, st: Dictionary) -> void:
	var r := side_rect()
	var box := Rect2(r.position, Vector2(r.size.x, FAB_H))
	_panel(box, ROW_BG)
	_text("SMELTER", box.position + Vector2(10.0, 24.0), 15, AMBER)
	var status := "Level %d" % st["level"]
	var col := GOOD
	if int(st["count"]) == 0:
		status = "No smelter on this ship"
		col = BAD
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
	_text("C/Esc close   ?: help   Tab: station   Up/Down, Enter: craft   Click a job: cancel   Wheel: scroll",
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
