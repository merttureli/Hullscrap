extends Control
## The end of a run: "YOUR SHIP IS SCRAP" with the ship's name and what the run came to (jumps made,
## credits, debt left, crew alive, events seen, fights won), then New run (the ship picker) or Main menu.
## front_door.gd opens it when the map reports a lost campaign fight, writes the run record to the profile
## and wipes the saves; this node only shows the numbers and reads input (N, M, Up/Down, Enter, click).
## stats_of() is the logic: the numbers from a campaign and the ship. In the UI colours of station_panel.gd.

## Emitted with the id of the button pressed: "new" or "menu".
signal chosen(id: String)

const BUTTONS: Array = [{"id": "new", "label": "New run", "key": KEY_N}, {"id": "menu", "label": "Main menu", "key": KEY_M}]
const ROWS: Array = [["Jumps made", "jumps"], ["Credits", "credits"], ["Debt left", "debt"], ["Crew alive", "crew"], ["Events seen", "events"], ["Fights won", "fights"]]
const PANEL := Vector2(560.0, 520.0)
const BTN := Vector2(240.0, 48.0)
const DIM := Color(0.0, 0.0, 0.0, 0.8)
const PANEL_BG := Color("#1f2630")
const ROW_BG := Color("#2a3340")
const EDGE := Color("#cfd6df")
const EDGE_DIM := Color("#59667a")
const HIGHLIGHT := Color(1.0, 1.0, 1.0, 0.1)
const TEXT := Color("#eef2f7")
const DIM_TEXT := Color("#97a3b3")
const BAD := Color("#e0413b")
const AMBER := Color("#e1a136")

var stats := {}  ## stats_of() of the run that ended
var selected := 0  ## the button Enter presses


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


## The numbers of a run: {ship, jumps, credits, debt, crew, events, fights}. `ship` is the player's Ship;
## crew alive is everyone aboard above 0 hp.
static func stats_of(campaign, ship) -> Dictionary:
	var alive := 0
	if ship != null:
		for m in ship.crew:
			if m.hp > 0.0 and not m.is_drone():  # (a repair drone is no crew)
				alive += 1
	return {"ship": ship.name if ship != null else "?", "jumps": campaign.jumps,
		"credits": ship.inventory.count("credits") if ship != null else 0, "debt": campaign.debt,
		"crew": alive, "events": campaign.events_seen, "fights": campaign.fights_won}


## Show the end screen for `p_stats` (stats_of).
func open(p_stats: Dictionary) -> void:
	stats = p_stats
	selected = 0
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


## Press button `i`: hides the screen and says which.
func press(i: int) -> void:
	if i < 0 or i >= BUTTONS.size():
		return
	close()
	chosen.emit(BUTTONS[i]["id"])


# --- input --------------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey):
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()
	if not e.pressed or e.echo or e.ctrl_pressed:  # (Ctrl+M is the mute, audio.gd)
		return
	match e.keycode:
		KEY_UP, KEY_LEFT:
			selected = (selected + BUTTONS.size() - 1) % BUTTONS.size()
		KEY_DOWN, KEY_RIGHT, KEY_TAB:
			selected = (selected + 1) % BUTTONS.size()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			press(selected)
		_:
			for i in BUTTONS.size():
				if BUTTONS[i]["key"] == e.keycode:
					press(i)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var i := button_at(e.position)
		if i >= 0:
			selected = i
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		press(button_at(e.position))
	accept_event()


# --- layout and drawing ---------------------------------------------------------------------------------

func panel_rect() -> Rect2:
	return Rect2((size - PANEL) / 2.0, PANEL)


func button_rect(i: int) -> Rect2:
	var p := panel_rect()
	var gap := 24.0
	var total := BUTTONS.size() * BTN.x + (BUTTONS.size() - 1) * gap
	return Rect2(Vector2(p.position.x + (p.size.x - total) / 2.0 + i * (BTN.x + gap), p.end.y - 40.0 - BTN.y), BTN)


## The button at `p`, or -1.
func button_at(p: Vector2) -> int:
	for i in BUTTONS.size():
		if button_rect(i).has_point(p):
			return i
	return -1


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	var p := panel_rect()
	_panel(p)
	_centered("YOUR SHIP IS SCRAP", p.position.y + 74.0, 38, BAD)
	_centered(str(stats.get("ship", "")), p.position.y + 112.0, 22, AMBER)
	var y := p.position.y + 150.0
	for row in ROWS:
		var r := Rect2(p.position.x + 60.0, y, p.size.x - 120.0, 36.0)
		draw_rect(r, ROW_BG)
		draw_rect(r, EDGE_DIM, false, 1.0)
		_text(row[0], r.position + Vector2(14.0, 25.0), 18, DIM_TEXT)
		var v := str(int(stats.get(row[1], 0)))
		var w := ThemeDB.fallback_font.get_string_size(v, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_text(v, Vector2(r.end.x - w - 14.0, r.position.y + 25.0), 20, TEXT)
		y += 42.0
	for i in BUTTONS.size():
		var b := button_rect(i)
		var hot := i == selected
		draw_rect(b, ROW_BG)
		draw_rect(b, AMBER if hot else EDGE_DIM, false, 3.0 if hot else 1.0)
		var label: String = BUTTONS[i]["label"]
		var w2 := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_text(label, b.position + Vector2((b.size.x - w2) / 2.0 - 8.0, 31.0), 20, TEXT)
		var k := OS.get_keycode_string(BUTTONS[i]["key"])
		_text(k, b.position + Vector2(b.size.x - 28.0, 30.0), 15, AMBER if hot else DIM_TEXT)
	_centered("The save is gone: death is final.", p.end.y - 16.0, 14, DIM_TEXT)


## A chunky panel: a slate fill, a 2 px light border and a 1 px inner highlight.
func _panel(r: Rect2, fill := PANEL_BG) -> void:
	draw_rect(r, fill)
	draw_rect(r, EDGE, false, 2.0)
	draw_rect(r.grow(-3.0), HIGHLIGHT, false, 1.0)


func _centered(text: String, y: float, font_size: int, col: Color) -> void:
	var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(text, Vector2((size.x - w) / 2.0, y), font_size, col)


func _text(text: String, at: Vector2, font_size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
