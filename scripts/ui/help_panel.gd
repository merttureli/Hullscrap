extends Control
## How to play: one screen in columns with the keys of the game (moving and crew, building, the map and
## events, combat, stations, shields, crafting) and a "First run" box. F1 opens and closes it anywhere
## (the main menu and the pause menu list it too); Esc, Enter or Space close it. While open it takes
## every key and click. The keys are the real ones of the input handlers: build_mode.gd, crew_view.gd,
## combat_view.gd, weapon_bar.gd, map_view.gd, event_panel.gd, station_panel.gd, shield_panel.gd and
## crafting_panel.gd; tests/test_front_door.gd checks that every one of them is on the screen.
## In the UI colours of station_panel.gd.

const Campaign = preload("res://scripts/space/campaign.gd")

## Emitted when the panel is closed.
signal closed

## Columns of sections; a section is [title, rows] and a row is [keys, what it does].
const COLUMNS: Array = [
	[
		["MOVING AND CREW", [
			["W A S D", "Walk your soldier (the legs turn the way you walk)"],
			["Mouse", "Play mode: the soldier aims at the cursor"],
			["E (hold)", "Work with your hands: stand by a fire, a breach, a broken system or a downed crewmate"],
			["E on a door", "Open / close the door"],
			["Middle click", "Send Ada there"],
			["B", "Build mode / play mode"],
			["O / P", "Oxygen / power overlay"],
			["Wheel", "Zoom"],
			["Ctrl+S / Ctrl+L", "Save / load the ship and the run"],
			["N", "Play mode: pick another ship"],
			["Esc", "Pause menu"],
			["F1", "This screen, anywhere"],
		]],
		["STATIONS", [
			["Click", "Buy or sell one"],
			["Right click", "Five fuel, or all of an item"],
			["Wheel", "Scroll a column"],
			["Esc / Enter / M", "Leave"],
		]],
	],
	[
		["BUILDING (B for build mode)", [
			["Tab", "Next palette: Tiles, Systems, Cables"],
			["1 2 3", "Tiles: floor, wall, door"],
			["1 - 9", "Systems: pick one you hold in cargo"],
			["Left mouse", "Place; drag to paint (a system goes down on release)"],
			["Shift+Left drag", "Straight line"],
			["Ctrl+Left drag", "Rectangle (a wall makes a room)"],
			["Right mouse", "Remove and get it back (Shift / Ctrl: line / rectangle)"],
			["T", "Wall shape: full, slope, round"],
			["R", "Turn the piece or system; flip a door"],
			["Shift+R", "Mirror a wall shape"],
			["F", "Send the nearest crew to repair the system under the mouse"],
			["Ctrl+Z / Ctrl+Y", "Undo / redo (Ctrl+Shift+Z also redoes)"],
			["Esc", "Cancel a drag"],
			["Mounts", "A weapon or engine goes outside the hull, against a wall; its inside half goes on the floor behind it"],
			["Cables", "Every system needs a cable to a reactor"],
		]],
	],
	[
		["THE MAP AND EVENTS (M in play mode)", [
			["Click a marker", "Set a course to that point of interest; crew at the helm fly there (click again: cancel)"],
			["E at the helm", "Fly the ship yourself (mouse, W/S, A/D); E again hands it back"],
			["M", "Open / close the map"],
			["Click a lit neighbour", "Spool the jump drive there (8 s, fuel when it fires; the same node again cancels)"],
			["Shift+click", "Drift jump with no fuel (costs hull)"],
			["T", "Wait for a passing trader (no fuel)"],
			["Y", "Ma tows you home to Rusthold (no fuel, debt +150)"],
			["Enter", "Close to a station's beacon its menu opens; Enter on the map says so"],
			["Esc", "Close the map"],
			["1 - 9 or click", "Pick a choice in an event"],
			["Enter / Space", "Continue"],
		]],
		["COMBAT (a fight, or K in play mode)", [
			["K", "Play mode: meet the test pirate (Shift+K: the Rustfang rammer)"],
			["Mouse", "Steer; fixed guns aim where the ship points"],
			["W / S", "Throttle forward / back"],
			["A / D", "Strafe"],
			["Left / Right mouse", "Fire group 1 (lasers, bolts, beams) / group 2 (missiles, flak)"],
			["1 - 9", "Fire that weapon"],
			["T", "Turrets: autofire on / off"],
			["Shift / Space / Q", "Engine / shield / utility ability"],
			["Arrows / End", "Shift the shield toward a side / back to even"],
			["Esc", "Leave, once the enemy is wrecked or far away"],
			["J", "Open the map to spool the jump drive (held while the enemy is within 2,000 px)"],
			["R", "After your ship is wrecked"],
		]],
	],
	[
		["SHIELDS (H)", [
			["H", "Shields tab: click a sector's + or -, or pick a preset or a custom slot"],
			["H / Esc", "Close it"],
		]],
		["CRAFTING (C)", [
			["C", "Crafting panel, in build or play mode"],
			["Click, or Up / Down + Enter", "Queue a recipe"],
			["PgUp / PgDn", "Scroll fast"],
			["Click a queued job", "Cancel it"],
			["U", "Debug: unlock a random blueprint"],
			["C / Esc", "Close it"],
		]],
	],
]

const KEY_W := 128.0  ## width of the keys column of a row
const COL_GAP := 20.0
const PAD := 18.0
const MARGIN := 24.0
const TITLE_H := 56.0
const FONT := 14
const ROW_GAP := 5.0
const DIM := Color(0.0, 0.0, 0.0, 0.8)
const PANEL_BG := Color("#1f2630")
const ROW_BG := Color("#2a3340")
const EDGE := Color("#cfd6df")
const EDGE_DIM := Color("#59667a")
const HIGHLIGHT := Color(1.0, 1.0, 1.0, 0.1)
const TEXT := Color("#eef2f7")
const DIM_TEXT := Color("#97a3b3")
const GOOD := Color("#6bd34a")
const AMBER := Color("#e1a136")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


## The first-run steps. The debt figures come from data/drift.json.
static func first_run() -> Array[String]:
	var d: Dictionary = Campaign.config()["debt"]
	return [
		"Click a marker to fly there; M opens the map to jump on.",
		"Read the event and pick a choice.",
		"Keep fuel up: buy it at stations.",
		"Pay %s %d credits every %d jumps." % [str(d["creditor"]).get_slice(" ", 0), int(d["payment"]), int(d["every"])],
		"Win fights for credits and scrap.",
		"Build better guns with C.",
	]


## The text of the keys column of every row, joined: what tests look the keys up in.
static func keys_text() -> String:
	var out: Array[String] = []
	for col in COLUMNS:
		for sec in col:
			for row in sec[1]:
				out.append(str(row[0]))
	return "\n".join(out)


## Everything the screen says, as plain text.
static func all_text() -> String:
	var out: Array[String] = []
	for col in COLUMNS:
		for sec in col:
			out.append(str(sec[0]))
			for row in sec[1]:
				out.append("%s %s" % [row[0], row[1]])
	out.append_array(first_run())
	return "\n".join(out)


func open() -> void:
	if visible:
		return
	visible = true
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


# --- input ------------------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if not (e is InputEventKey):
		return
	if not visible:
		if e.pressed and not e.echo and e.keycode == KEY_F1:
			open()
			_handled()
		return
	_handled()
	if e.pressed and not e.echo and e.keycode in [KEY_F1, KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		close()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		close()
	accept_event()


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


# --- layout and drawing ------------------------------------------------------------------------------------

func panel_rect() -> Rect2:
	return Rect2(Vector2(MARGIN, MARGIN), size - Vector2(MARGIN, MARGIN) * 2.0)


func column_width() -> float:
	return (panel_rect().size.x - 2.0 * PAD - (COLUMNS.size() - 1) * COL_GAP) / COLUMNS.size()


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	var p := panel_rect()
	_panel(p)
	_text("HOW TO PLAY", p.position + Vector2(PAD, 38.0), 26, TEXT)
	_text("Everything flies on salvage. Keep the ship alive, keep Ma paid.", p.position + Vector2(PAD + 220.0, 36.0), 15, DIM_TEXT)
	var cw := column_width()
	for c in COLUMNS.size():
		var x := p.position.x + PAD + c * (cw + COL_GAP)
		var y := p.position.y + TITLE_H + 12.0
		if c == COLUMNS.size() - 1:
			y = _first_run_box(Vector2(x, y), cw) + 18.0  # the box first: it is what a new player reads
		for sec in COLUMNS[c]:
			y = _section(sec, Vector2(x, y), cw) + 14.0
	_text("F1 / Esc / Enter: close", Vector2(p.position.x + PAD, p.end.y - 12.0), 13, DIM_TEXT)


## Draw a section at `at` in a column `w` wide; returns the y under it.
func _section(sec: Array, at: Vector2, w: float) -> float:
	_text(str(sec[0]), at + Vector2(0.0, 14.0), 14, AMBER)
	draw_line(at + Vector2(0.0, 20.0), at + Vector2(w, 20.0), EDGE_DIM, 1.0)
	var y := at.y + 36.0
	for row in sec[1]:
		var h := _row(row, Vector2(at.x, y), w)
		y += h + ROW_GAP
	return y


## One row: the keys (amber, wrapped in their own column) and what they do (wrapped). Returns its height.
func _row(row: Array, at: Vector2, w: float) -> float:
	var keys := str(row[0])
	var font := ThemeDB.fallback_font
	var kh := font.get_multiline_string_size(keys, HORIZONTAL_ALIGNMENT_LEFT, KEY_W - 8.0, FONT).y
	var dh := font.get_multiline_string_size(str(row[1]), HORIZONTAL_ALIGNMENT_LEFT, w - KEY_W, FONT).y
	draw_multiline_string(font, at + Vector2(0.0, FONT), keys, HORIZONTAL_ALIGNMENT_LEFT, KEY_W - 8.0, FONT, -1, AMBER)
	draw_multiline_string(font, at + Vector2(KEY_W, FONT), str(row[1]), HORIZONTAL_ALIGNMENT_LEFT, w - KEY_W, FONT, -1, TEXT)
	return maxf(kh, dh)


## The First run box at `at`, `w` wide. Returns the y under it.
func _first_run_box(at: Vector2, w: float) -> float:
	var steps := first_run()
	var font := ThemeDB.fallback_font
	var h := 40.0
	for s in steps:
		h += font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, w - 48.0, 16).y + 9.0
	var box := Rect2(at, Vector2(w, h + 8.0))
	draw_rect(box, ROW_BG)
	draw_rect(box, AMBER, false, 2.0)
	_text("FIRST RUN", box.position + Vector2(12.0, 24.0), 15, AMBER)
	var y := box.position.y + 40.0
	for i in steps.size():
		_text("%d." % (i + 1), Vector2(box.position.x + 12.0, y + 16.0), 16, AMBER)
		draw_multiline_string(font, Vector2(box.position.x + 34.0, y + 16.0), steps[i], HORIZONTAL_ALIGNMENT_LEFT, w - 48.0, 16, -1, TEXT)
		y += font.get_multiline_string_size(steps[i], HORIZONTAL_ALIGNMENT_LEFT, w - 48.0, 16).y + 9.0
	return box.end.y


## A chunky panel: a slate fill, a 2 px light border and a 1 px inner highlight.
func _panel(r: Rect2, fill := PANEL_BG) -> void:
	draw_rect(r, fill)
	draw_rect(r, EDGE, false, 2.0)
	draw_rect(r.grow(-3.0), HIGHLIGHT, false, 1.0)


func _text(text: String, at: Vector2, font_size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
