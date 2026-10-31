extends "res://scripts/ui/ship_picker.gd"
## The hangar (docs/CONTENT.md section 19): the run-start screen that replaces the three-card ship picker. Every starter
## ship (space/hangar.gd: the designs with a `hangar` field, and the first three) sits under a tab of its race or faction,
## with A / B / C tabs for the layouts of that ship type. A ship the player has not unlocked (profile.gd) is dimmed and says
## how to earn it; the selected ship shows its plan, its pitch, its power / mass / hull / shield / weapons and its crew.
## Left / Right change the tab, Up / Down or A / B / C the layout, Enter or a click on "Fly this ship" loads it into the
## player's ship (ShipPicker.choose does that, with the same API: open, ask, close, `chosen`, `on_escape`), Esc goes back.
## While it is open it swallows every key and click. Rules are in space/hangar.gd; this node only draws and reads input.

const Hangar = preload("res://scripts/space/hangar.gd")

const SIZE := Vector2(1320.0, 760.0)
const MAP := Vector2(600.0, 470.0)  ## the plan of the selected ship
const TAB_H := 36.0
const AMBER := Color("#e1a136")
const LAYOUT_NOTE := {"A": "The signature ship", "B": "A different strategy", "C": "The odd one"}

var profile = null  ## the Profile (profile.gd) whose unlocks decide what is open; null = nothing earned
var sel := 0  ## the selected ship: an index into `cards`
var tab_first := 0  ## the first group tab shown (the row scrolls when there are many)
var hot := {}  ## (the parent keeps `hover` for its cards) what the mouse is over: {kind: "group" | "layout" | "button", index}
var message := ""  ## why the last choice was refused
var _prev_path := ""  # the ship the preview below was made for
var _prev := {}  # {ship, arena, co, stats} of that ship


## Every starter of the hangar, in order (space/hangar.gd), as the cards: {id, name, path, pack, group, layout, unlock, blurb, crew}.
func load_cards() -> void:
	cards = Hangar.starters()
	sel = clampi(sel, 0, maxi(cards.size() - 1, 0))
	_prev_path = ""


func _layout() -> void:
	pass  # the plan is drawn by this node: no per-card children to place


func _show_cards(_on: bool) -> void:
	pass


## Show the hangar, fresh (the profile may have earned something), on the first ship that is open.
func open() -> void:
	load_cards()
	var first := 0
	for i in cards.size():
		if not is_locked(i):
			first = i
			break
	select(first)
	message = ""
	super.open()


func is_locked(i: int) -> bool:
	return i >= 0 and i < cards.size() and Hangar.locked(cards[i], profile)


## Select card `i`.
func select(i: int) -> void:
	if cards.is_empty():
		return
	sel = clampi(i, 0, cards.size() - 1)
	message = ""
	var gs := groups()
	var at := gs.find(cards[sel]["group"])
	tab_first = clampi(tab_first, 0, maxi(at, 0))
	while at >= tab_first + visible_tabs(gs).size() and tab_first < at:
		tab_first += 1
	queue_redraw()


func groups() -> Array:
	return Hangar.groups(cards)


## Select the ship of `group`: the layout `prefer` if the group has it, else its first open ship, else its first.
func select_group(group: String, prefer := "") -> void:
	var at := Hangar.find(cards, group, prefer)
	if at < 0:
		for i in cards.size():
			if cards[i]["group"] == group and (at < 0 or (is_locked(at) and not is_locked(i))):
				at = i
	if at >= 0:
		select(at)


## Select the layout `layout` (A, B, C) of the selected ship's group, when there is one.
func select_layout(layout: String) -> void:
	if cards.is_empty():
		return
	var at := Hangar.find(cards, cards[sel]["group"], layout)
	if at >= 0:
		select(at)


## Go `step` groups on (wrapping), keeping the layout when the new group has it.
func step_group(step: int) -> void:
	var gs := groups()
	if gs.is_empty():
		return
	select_group(gs[posmod(gs.find(cards[sel]["group"]) + step, gs.size())], cards[sel]["layout"])


## Go `step` layouts on within the group (wrapping), over the layouts the group has.
func step_layout(step: int) -> void:
	if cards.is_empty():
		return
	var have: Array = []
	for l in Hangar.LAYOUTS:
		if Hangar.find(cards, cards[sel]["group"], l) >= 0:
			have.append(l)
	select_layout(have[posmod(have.find(cards[sel]["layout"]) + step, have.size())])


## Load the selected ship (or `i`, the index of a card). A locked one is refused and says how it is earned.
func choose(i: int) -> String:
	if i < 0 or i >= cards.size():
		return "no such ship"
	if is_locked(i):
		message = "Locked: " + Hangar.hint(cards[i])
		queue_redraw()
		return message
	message = ""
	return super.choose(i)


## The selected ship made ready to show: {ship, arena, co (its arena ship), stats (ShipPicker.stats_of)}; {} when it cannot be
## loaded. Made again only when the selection changes.
func preview() -> Dictionary:
	if cards.is_empty():
		return {}
	var path: String = cards[sel]["path"]
	if path != _prev_path:
		_prev_path = path
		_prev = {}
		var s = Ship.from_design(path)
		if s != null:
			var arena := Arena.new(1)
			arena.add_ship(s)
			_prev = {"ship": s, "arena": arena, "co": arena.ships[0], "stats": stats_of(arena.ships[0])}
	return _prev


# --- input ---------------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if mode == Mode.CONFIRM or not visible or not (e is InputEventKey) or not e.pressed or e.keycode == KEY_ESCAPE:
		super._input(e)  # the Y / N question, and Esc: back
		return
	_handled()
	if e.echo:
		return
	match e.keycode:
		KEY_LEFT:
			step_group(-1)
		KEY_RIGHT, KEY_TAB:
			step_group(1)
		KEY_UP:
			step_layout(-1)
		KEY_DOWN:
			step_layout(1)
		KEY_A, KEY_B, KEY_C:
			select_layout(OS.get_keycode_string(e.keycode))
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			choose(sel)


func _gui_input(e: InputEvent) -> void:
	if mode != Mode.CHOOSE:
		return
	if e is InputEventMouseMotion:
		hot = zone_at(e.position)
		queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		click(e.position)


## A click at `p`: a group tab, a layout tab or the button.
func click(p: Vector2) -> void:
	var z := zone_at(p)
	match z.get("kind", ""):
		"group":
			select_group(visible_tabs(groups())[z["index"]], cards[sel]["layout"] if not cards.is_empty() else "")
		"layout":
			select_layout(Hangar.LAYOUTS[z["index"]])
		"button":
			choose(sel)


## What is at `p`: {kind: "group", index (into the tabs shown)}, {kind: "layout", index (0..2)}, {kind: "button"} or {}.
func zone_at(p: Vector2) -> Dictionary:
	var lay := layout()
	for i in lay["groups"].size():
		if lay["groups"][i].has_point(p):
			return {"kind": "group", "index": i}
	for i in lay["layouts"].size():
		if lay["layouts"][i].has_point(p) and Hangar.find(cards, cards[sel]["group"], Hangar.LAYOUTS[i]) >= 0:
			return {"kind": "layout", "index": i}
	if lay["button"].has_point(p):
		return {"kind": "button"}
	return {}


# --- layout ----------------------------------------------------------------------------------------------

func panel_rect() -> Rect2:
	return Rect2(((size - SIZE) / 2.0).round(), SIZE)


## The group tabs that fit, from `tab_first`.
func visible_tabs(gs: Array) -> Array:
	var out := []
	var x := 0.0
	var room := SIZE.x - 2.0 * PAD
	for i in range(tab_first, gs.size()):
		var w := _tab_w(gs[i])
		if x + w > room and not out.is_empty():
			break
		out.append(gs[i])
		x += w + 6.0
	return out


func _tab_w(group: String) -> float:
	return ThemeDB.fallback_font.get_string_size(_tab_label(group), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 36.0


func _tab_label(group: String) -> String:
	var n := Hangar.open_count(cards, group, profile)
	return group if n[0] == n[1] else "%s %d/%d" % [group, n[0], n[1]]


## Where everything goes, in screen px: {panel, groups (the tabs shown), layouts (A, B, C), map, info, button}.
func layout() -> Dictionary:
	var p := panel_rect()
	var tabs := []
	var x := p.position.x + PAD
	for g in visible_tabs(groups()):
		var w := _tab_w(g)
		tabs.append(Rect2(x, p.position.y + 96.0, w, TAB_H))
		x += w + 6.0
	var layouts := []
	for i in Hangar.LAYOUTS.size():
		layouts.append(Rect2(p.position.x + PAD + i * 74.0, p.position.y + 144.0, 68.0, TAB_H))
	var map := Rect2(p.position + Vector2(PAD, 196.0), MAP)
	var info := Rect2(map.end.x + 30.0, map.position.y, p.end.x - PAD - map.end.x - 30.0, MAP.y)
	return {"panel": p, "groups": tabs, "layouts": layouts, "map": map, "info": info,
		"button": Rect2(info.position.x, info.end.y - 50.0, info.size.x, 50.0)}


# --- drawing ---------------------------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	if mode == Mode.CONFIRM:
		_draw_confirm()
		return
	var lay := layout()
	var p: Rect2 = lay["panel"]
	draw_rect(p, PANEL_BG)
	draw_rect(p, EDGE, false, 2.0)
	_text("Hangar", p.position + Vector2(PAD, 44.0), 30, TEXT)
	_text("Choose the ship this run starts with. Locked ships open as you reach endings and landmarks.", p.position + Vector2(PAD, 72.0), 14, DIM_TEXT)
	if cards.is_empty():
		_text("No ships in the hangar.", p.position + Vector2(PAD, 140.0), 20, BAD)
		return
	var cur: Dictionary = cards[sel]
	var gs := visible_tabs(groups())
	for i in gs.size():
		var r: Rect2 = lay["groups"][i]
		var here: bool = gs[i] == cur["group"]
		var all_locked: bool = Hangar.open_count(cards, gs[i], profile)[0] == 0
		draw_rect(r, CARD_BG if not here else EDGE)
		draw_rect(r, AMBER if here else (EDGE_HOT if hot.get("kind") == "group" and hot.get("index") == i else EDGE), false, 2.0 if here else 1.0)
		_text(_tab_label(gs[i]), r.position + Vector2(18.0, 24.0), 17, TEXT if here else (DIM_TEXT if all_locked else Color("#c8dcf0")))
	if tab_first > 0:
		_text("<", Vector2(p.position.x + 8.0, p.position.y + 120.0), 20, AMBER)
	if tab_first + gs.size() < groups().size():
		_text(">", Vector2(p.end.x - 22.0, p.position.y + 120.0), 20, AMBER)
	for i in Hangar.LAYOUTS.size():
		_draw_layout_tab(i, lay["layouts"][i], cur)
	_text(LAYOUT_NOTE.get(cur["layout"], ""), Vector2(lay["layouts"][2].end.x + 16.0, lay["layouts"][2].position.y + 24.0), 15, DIM_TEXT)
	_draw_plan(lay["map"], cur)
	_draw_info(lay, cur)
	_text("Left / Right: tab      Up / Down or A B C: layout      Enter: fly this ship      Esc: back",
		p.position + Vector2(PAD, p.size.y - 22.0), 14, DIM_TEXT)


func _draw_layout_tab(i: int, r: Rect2, cur: Dictionary) -> void:
	var l: String = Hangar.LAYOUTS[i]
	var at := Hangar.find(cards, cur["group"], l)
	var here: bool = l == cur["layout"]
	draw_rect(r, CARD_BG if not here else EDGE)
	draw_rect(r, AMBER if here else (EDGE_HOT if hot.get("kind") == "layout" and hot.get("index") == i else EDGE), false, 2.0 if here else 1.0)
	var col := TEXT if here else DIM_TEXT
	if at < 0:
		col = Color(DIM_TEXT, 0.35)
	_text(l, r.position + Vector2(14.0, 25.0), 20, col)
	if at >= 0 and is_locked(at):
		_lock(r.position + Vector2(r.size.x - 24.0, 11.0), col)


## A little padlock at `at`.
func _lock(at: Vector2, col: Color) -> void:
	draw_arc(at + Vector2(6.0, 3.0), 4.0, PI, TAU, 8, col, 1.5)
	draw_rect(Rect2(at + Vector2(0.0, 3.0), Vector2(12.0, 9.0)), col)


func _draw_plan(r: Rect2, cur: Dictionary) -> void:
	draw_rect(r, Color("#05080d"))
	var pv := preview()
	if not pv.is_empty():
		Schematic.draw_map(self, pv["ship"], pv["co"].powered, r.grow(-14.0))
	else:
		_text("This design cannot be loaded.", r.position + Vector2(20.0, 40.0), 16, BAD)
	if is_locked(sel):
		draw_rect(r, Color(0.0, 0.0, 0.0, 0.6))
		var note := Rect2(r.get_center() - Vector2(220.0, 62.0), Vector2(440.0, 124.0))
		draw_rect(note, Color("#0b0f16"))
		draw_rect(note, AMBER, false, 2.0)
		_lock(note.position + Vector2(note.size.x / 2.0 - 6.0, 14.0), AMBER)
		_centered_in(note, "LOCKED", note.position.y + 56.0, 24, AMBER)
		draw_multiline_string(ThemeDB.fallback_font, Vector2(note.position.x + 16.0, note.position.y + 82.0), Hangar.hint(cur), HORIZONTAL_ALIGNMENT_CENTER, note.size.x - 32.0, 16, 2, TEXT)
	draw_rect(r, EDGE, false, 2.0)


func _draw_info(lay: Dictionary, cur: Dictionary) -> void:
	var r: Rect2 = lay["info"]
	var locked := is_locked(sel)
	var x := r.position.x
	var y := r.position.y + 30.0
	_text(str(cur["name"]), Vector2(x, y), 30, DIM_TEXT if locked else TEXT)
	_text("%s, layout %s" % [cur["group"], cur["layout"]], Vector2(x, y + 24.0), 15, DIM_TEXT)
	y += 52.0
	draw_multiline_string(ThemeDB.fallback_font, Vector2(x, y), str(cur["blurb"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 16, 4, DIM_TEXT if locked else TEXT)
	y += 86.0
	var pv := preview()
	if not pv.is_empty():
		var st: Dictionary = pv["stats"]
		var ok: bool = st["supply"] + 0.0001 >= st["demand"]
		_stat(x, y, "Power", "%s supply / %s demand" % [_num(st["supply"]), _num(st["demand"])], GOOD if ok else BAD)
		_stat(x, y + 22.0, "Mass", "%d" % roundi(st["mass"]))
		_stat(x + 200.0, y + 22.0, "Hull", "%d" % roundi(st["hull"]))
		var layers: int = st["layers"]
		_stat(x, y + 44.0, "Shield", "none" if layers == 0 else "%d layer%s%s" % [layers, "" if layers == 1 else "s", ", %d sectors" % st["sectors"] if st["sectors"] > 1 else ""])
		_text("Weapons", Vector2(x, y + 66.0), 14, DIM_TEXT)
		draw_multiline_string(ThemeDB.fallback_font, Vector2(x + 70.0, y + 66.0), ", ".join(st["weapons"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 70.0, 14, 2, TEXT)
	y += 116.0
	_text("Crew", Vector2(x, y), 14, DIM_TEXT)
	var names: Array[String] = []
	for m in cur["crew"]:
		names.append("%s (%s)" % [m["name"], str(m["species"]).capitalize()])
	draw_multiline_string(ThemeDB.fallback_font, Vector2(x + 70.0, y), ", ".join(names) if not names.is_empty() else "none", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 70.0, 14, 3, TEXT)
	if message != "":
		_text(message, Vector2(x, lay["button"].position.y - 12.0), 14, BAD)
	var b: Rect2 = lay["button"]
	draw_rect(b, CARD_BG)
	draw_rect(b, EDGE_HOT if hot.get("kind") == "button" and not locked else (EDGE if locked else GOOD), false, 2.0)
	_centered_in(b, "Locked" if locked else "Fly this ship (Enter)", b.position.y + 32.0, 20, DIM_TEXT if locked else TEXT)


func _centered_in(r: Rect2, text: String, y: float, font_size: int, col: Color) -> void:
	var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(text, Vector2(r.position.x + (r.size.x - w) / 2.0, y), font_size, col)
