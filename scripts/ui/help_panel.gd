extends Control
## How to play: one screen in columns with the keys of the game (moving and crew, building, the map and
## events, combat, stations, shields, crafting) and a "First run" box. F1 opens and closes it anywhere
## (the main menu and the pause menu list it too); Esc, Enter or Space close it. While open it takes
## every key and click. The keys are the real ones of the input handlers: build_mode.gd, crew_view.gd,
## combat_view.gd, weapon_bar.gd, map_view.gd, event_panel.gd, station_panel.gd, shield_panel.gd, ledger_card.gd and
## crafting_panel.gd and crew_kit_panel.gd; tests/test_front_door.gd checks that every one of them is on the screen.
## In the UI colours of station_panel.gd.

const Campaign = preload("res://scripts/space/campaign.gd")
const BreachPrompt = preload("res://scripts/ui/breach_prompt.gd")
const Audio = preload("res://scripts/audio/audio.gd")

## Emitted when the panel is closed.
signal closed

## Columns of sections; a section is [title, rows] and a row is [keys, what it does].
const COLUMNS: Array = [
	[
		["MOVING AND CREW", [
			["W A S D", "Walk your soldier (the legs turn the way you walk)"],
			["Mouse", "Play mode: the soldier aims at the cursor"],
			["E (hold)", "Hold to repair, patch, extinguish or revive nearby."],
			["E on a door", "Open / close the door"],
			["Middle click", "Send a crewmate or a group (in a fight: your ship or schematic)"],
			["Left click", "Select; Shift or drag adds; X spreads"],
			["Station bar", "Post the selected crew member"],
			["R / V", "Breach alert: repair / evacuate"],
			["G", "Use the selected crew member's special ability (in a fight too)"],
			["I", "Crew kit (play or build mode)"],
			["B", "Build mode / play mode"],
			["O / P", "Oxygen / power overlay"],
			["Wheel", "Zoom (build: MMB drag, arrows pan)"],
			["Ctrl+S / Ctrl+L", "Save / load the ship and the run"],
			["Ctrl+M", "Mute / unmute all sound"],
			["N / Esc / F1", "New ship / pause menu / this help"],
		]],
	],
	[
		["BUILDING (B for build mode)", [
			["Tab / Shift+Tab", "Palette tab: Structure, Shapes, Systems, Weapons, Engines, Utility, Cargo"],
			["1 - 9", "Pick a card. Grey: none held or can't pay."],
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
			["Mounts", "Weapons and engines go on an outer wall or a slope; the inside half sits on the floor behind."],
			["Cables", "Every system needs a cable to a reactor (Cable is on Structure)"],
			["Belts", "Ammo racks feed guns in their room; a belt drive and belts (Belt on Structure) carry ammo to the rest"],
			["Mode bar", "Click Build, Play, Map, Shields, Crafting or Help"],
		]],
		["SHIELDS (H)", [
			["H", "Shields tab: click a sector's + or -, or pick a preset or a custom slot"],
			["H / Esc", "Close it"],
		]],
		["THE LEDGER (L)", [
			["L", "Fold or unfold the Ledger's goal list (a click on its card does too)"],
		]],
	],
	[
		["THE MAP AND EVENTS (M in play mode)", [
			["Click a marker", "Set a course to that point of interest; crew at the helm fly there (click again: cancel)"],
			["E at the helm", "Fly the ship yourself (mouse, W/S, A/D); E again hands it back"],
			["M", "Open / close the map"],
			["J", "Journal: the logs found this run"],
			["Click a lit neighbour", "Spool the jump drive there (8 s, fuel when it fires; the same node again cancels)"],
			["Shift+click", "Drift jump with no fuel (costs hull)"],
			["T", "Wait for a passing trader (no fuel)"],
			["Y", "No fuel: Ma tows you to the region start (debt +150)."],
			["Enter", "Close to a station's beacon its menu opens; at the exit beacon, choose the next region (1 - 3) once its warden is dealt with"],
			["Exit warden", "A warden holds each exit: pay, show standing, or break through."],
			["Esc", "Close the map"],
			["1 - 9 or click", "Pick a choice in an event"],
			["Enter / Space", "Continue"],
		]],
		["RAFT LOOP (flying)", [
			["Q (hold)", "Not in a fight: tractor beams haul nearby debris to the nearest intake"],
		]],
		["STATIONS", [
			["Click", "Buy or sell one"],
			["Right click", "Five fuel, or all of an item"],
			["Wheel", "Scroll a column"],
			["Esc / Enter / M", "Leave"],
		]],
	],
	[
		["COMBAT (a fight, or K in play mode)", [
			["K", "Play mode: meet the test pirate"],
			["Mouse", "Steer; fixed guns aim where the ship points"],
			["W / S", "Throttle forward / back"],
			["A / D", "Strafe"],
			["Left / Right mouse", "Fire amber / cyan guns, Q pink; drag a slot to move one"],
			["1 - 9", "Fire that weapon"],
			["T", "Auto guns: fire on their own on / off"],
			["Shift / Space / E", "Engine / shield / utility ability"],
			["Arrows / End", "Shift the shield toward a side / back to even"],
			["Esc / Tab", "Leave when over; Tab slows time"],
			["Y", "Accept a surrender"],
			["J", "Spool the jump drive (10 s); engines or helm down hold it"],
			["R", "After your ship is wrecked"],
		]],
		["CRAFTING (C)", [
			["C", "Crafting panel, in build or play mode"],
			["Tab", "Fabricator / smelter (steel, alloy, conductor, glass)"],
			["?", "How crafting works"],
			["Click, or Up / Down + Enter", "Queue a recipe, then place the part from the palette (B)."],
			["Dimmed recipe", "Needs a blueprint: salvage scans, events, stores"],
			["PgUp / PgDn", "Scroll fast"],
			["Click a queued job", "Cancel it"],
			["U", "Debug: unlock a random blueprint", "debug"],
			["C / Esc", "Close it"],
		]],
		["BOARDING (an event's Board her)", [
			["Mouse R Q F", "Aboard: fire, reload, swap, flashlight"],
			["E (hold), L", "Hold: open, hack, revive. Tap: talk. Airlock or L: leave"],
			["Mouse R", "Send the squad to a room: they fight, loot, hold"],
			["B, 1 2", "Call the squad back; select follower 1 / 2 (or click a card)"],
		]],
	],
]

const KEY_W := 128.0  ## width of the keys column of a row
const COL_GAP := 20.0
const PAD := 18.0
const MARGIN := 24.0
const TITLE_H := 56.0
const FONT := 13
const ROW_GAP := 2.0
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


## The rows of a section: a row marked "debug" (a third item) shows only in a debug build.
static func rows_of(sec: Array) -> Array:
	return sec[1].filter(func(r): return r.size() < 3 or OS.is_debug_build())


## The text of the keys column of every row, joined: what tests look the keys up in.
static func keys_text() -> String:
	var out: Array[String] = []
	for col in COLUMNS:
		for sec in col:
			for row in rows_of(sec):
				out.append(str(row[0]))
	return "\n".join(out)


## Everything the screen says, as plain text.
static func all_text() -> String:
	var out: Array[String] = []
	for col in COLUMNS:
		for sec in col:
			out.append(str(sec[0]))
			for row in rows_of(sec):
				out.append("%s %s" % [row[0], row[1]])
	out.append_array(first_run())
	return "\n".join(out)


func open() -> void:
	if visible:
		return
	visible = true
	Audio.fx(self, "open")
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	Audio.fx(self, "close")
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
	if BreachPrompt.claims(e):
		return  # R and V answer the breach card, whatever window is open
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


## The y of the bottom of column `c`'s last row, as _draw lays it out (the tests keep it above the footer line).
func column_end(c: int) -> float:
	var w := column_width()
	var y := panel_rect().position.y + TITLE_H + 12.0
	if c == 0:
		y += _first_run_h(w) + 18.0
	for sec in COLUMNS[c]:
		y += 32.0
		for row in rows_of(sec):
			y += _row_h(row, w) + ROW_GAP
		y += 14.0
	return y - 14.0 - ROW_GAP


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
		if c == 0:
			y = _first_run_box(Vector2(x, y), cw) + 18.0  # the box first: it is what a new player reads
		for sec in COLUMNS[c]:
			y = _section(sec, Vector2(x, y), cw) + 14.0
	_text("F1 / Esc / Enter: close", Vector2(p.position.x + PAD, p.end.y - 12.0), 13, DIM_TEXT)


## Draw a section at `at` in a column `w` wide; returns the y under it.
func _section(sec: Array, at: Vector2, w: float) -> float:
	_text(str(sec[0]), at + Vector2(0.0, 14.0), 14, AMBER)
	draw_line(at + Vector2(0.0, 20.0), at + Vector2(w, 20.0), EDGE_DIM, 1.0)
	var y := at.y + 32.0
	for row in rows_of(sec):
		var h := _row(row, Vector2(at.x, y), w)
		y += h + ROW_GAP
	return y


## The height of a row `w` wide: the taller of its keys and its text once wrapped.
static func _row_h(row: Array, w: float) -> float:
	var font := ThemeDB.fallback_font
	return maxf(font.get_multiline_string_size(str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, KEY_W - 8.0, FONT).y,
		font.get_multiline_string_size(str(row[1]), HORIZONTAL_ALIGNMENT_LEFT, w - KEY_W, FONT).y)


## One row: the keys (amber, wrapped in their own column) and what they do (wrapped). Returns its height.
func _row(row: Array, at: Vector2, w: float) -> float:
	var font := ThemeDB.fallback_font
	draw_multiline_string(font, at + Vector2(0.0, FONT), str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, KEY_W - 8.0, FONT, -1, AMBER)
	draw_multiline_string(font, at + Vector2(KEY_W, FONT), str(row[1]), HORIZONTAL_ALIGNMENT_LEFT, w - KEY_W, FONT, -1, TEXT)
	return _row_h(row, w)


## The height of the First run box `w` wide.
static func _first_run_h(w: float) -> float:
	var h := 48.0
	for s in first_run():
		h += ThemeDB.fallback_font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, w - 48.0, 16).y + 9.0
	return h


## The First run box at `at`, `w` wide. Returns the y under it.
func _first_run_box(at: Vector2, w: float) -> float:
	var steps := first_run()
	var font := ThemeDB.fallback_font
	var box := Rect2(at, Vector2(w, _first_run_h(w)))
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
