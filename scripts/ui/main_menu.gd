extends Control
## The main menu shown at launch, and the small pause menu Esc opens in the game (same node, two modes).
## Main: Continue (only when a run is saved), New run (the ship picker), How to play, Quit; a starfield
## behind the title, the last five runs and the version in the corner. Pause: Resume, How to play, Save and
## quit to menu, Quit. Each entry has a letter key; Up/Down and Enter, a click and the number keys work too.
## The menu only says which entry was chosen (`chosen`); front_door.gd does what it means. entries() is the
## state machine (Continue is left out without a save). In the UI colours of station_panel.gd.
## Both menus carry a small Sound row: four sliders (Master, Music, SFX, Ambience) that a click or a drag sets and the wheel nudges; `sound`
## holds them (front_door.gd sets it from the profile), `sound_changed` says which moved (final = the mouse was let go: save it).
## Under them a Ledger row (the guidance program of scripts/sim/advisor.gd): three buttons, Full, Warnings only and Off; `ledger` holds the
## setting (front_door.gd sets it from the profile) and `ledger_changed` says which was clicked.

## Emitted with the id of the entry chosen: continue, new, help, quit, resume, save_menu.
signal chosen(id: String)

## A volume slider moved: its kind (master, music, sfx or ambience), the new value (0 to 1) and whether this is the last of the drag.
signal sound_changed(kind: String, value: float, final: bool)

## The Ledger's setting was clicked: "full", "warn" or "off".
signal ledger_changed(mode: String)

const Profile = preload("res://scripts/ui/profile.gd")
const Audio = preload("res://scripts/audio/audio.gd")

enum Mode { MAIN, PAUSE }

const MAIN_ENTRIES: Array = [
	{"id": "continue", "label": "Continue", "key": KEY_C},
	{"id": "new", "label": "New run", "key": KEY_N},
	{"id": "help", "label": "How to play", "key": KEY_H},
	{"id": "quit", "label": "Quit", "key": KEY_Q},
]
const PAUSE_ENTRIES: Array = [
	{"id": "resume", "label": "Resume", "key": KEY_R},
	{"id": "help", "label": "How to play", "key": KEY_H},
	{"id": "save_menu", "label": "Save and quit to menu", "key": KEY_S},
	{"id": "quit", "label": "Quit", "key": KEY_Q},
]
const SOUND_KINDS: Array = [["master", "Master"], ["music", "Music"], ["sfx", "SFX"], ["ambience", "Ambience"]]
const SLIDER_W := 88.0
const SLIDER_H := 12.0
const SOUND_STEP := 0.05  ## a wheel notch
const SOUND_H := 70.0  ## the room the sound row takes under the buttons
const LEDGER_H := 50.0  ## and the Ledger row under it
const LEDGER_GAP := 8.0  ## between its buttons
const TAGLINE := "Everything flies on salvage."
const BTN := Vector2(380.0, 48.0)
const GAP := 12.0
const DIM := Color(0.0, 0.0, 0.0, 0.7)
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

var mode: int = Mode.MAIN
var has_save := false  ## a saved run exists: Continue is listed
var selected := 0  ## the entry Enter presses
var recent: Array = []  ## profile.last_runs(): the records listed on the main menu
var version := ""  ## the label in the corner
var note := ""  ## a line under the buttons (a refused Continue, "Run saved")
var sound := Profile.SOUND_DEFAULTS.duplicate()  ## the volume sliders, 0 to 1
var ledger := "full"  ## the Ledger's setting (Profile.LEDGER_MODES)
var _drag := -1  # the slider being dragged
var _stars: Node2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


## The entries of `p_mode`, in order. The main menu lists Continue only when `p_has_save`.
static func entries(p_mode: int, p_has_save: bool) -> Array:
	if p_mode == Mode.PAUSE:
		return PAUSE_ENTRIES
	return MAIN_ENTRIES.filter(func(e): return e["id"] != "continue" or p_has_save)


## The entries as listed now.
func list() -> Array:
	return entries(mode, has_save)


func ids() -> Array:
	return list().map(func(e): return e["id"])


## Show the menu in `p_mode`, the first entry selected.
func open(p_mode: int, p_has_save := false, p_note := "") -> void:
	mode = p_mode
	has_save = p_has_save
	note = p_note
	selected = 0  # Continue when there is a save, else New run (pause: Resume)
	if _stars != null:
		_stars.visible = mode == Mode.MAIN
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


## The starfield behind the main menu (starfield.gd), made by front_door.gd; shown only in the main mode.
func set_stars(node: Node2D) -> void:
	_stars = node
	_stars.show_behind_parent = true
	add_child(_stars)
	_stars.visible = mode == Mode.MAIN


func move(d: int) -> void:
	var n := list().size()
	selected = (selected + d + n) % n
	Audio.fx(self, "hover")


## Choose entry `i`: hides nothing (the owner decides), just says which.
func press(i: int) -> void:
	var l := list()
	if i >= 0 and i < l.size():
		Audio.fx(self, "cancel" if l[i]["id"] in ["resume", "quit"] else "confirm")
		chosen.emit(l[i]["id"])


## What a key does: returns the id of the entry it chose, "" for none. Up/Down move, Enter presses,
## a letter or a number presses its entry, Esc resumes the pause menu.
func key(code: int) -> String:
	var l := list()
	match code:
		KEY_UP:
			move(-1)
		KEY_DOWN, KEY_TAB:
			move(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			press(selected)
			return l[selected]["id"]
		KEY_ESCAPE:
			if mode == Mode.PAUSE:
				press(0)
				return "resume"
		_:
			for i in l.size():
				if l[i]["key"] == code or code == KEY_1 + i:
					selected = i
					press(i)
					return l[i]["id"]
	return ""


# --- input ---------------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey):
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()
	if e.pressed and not e.echo:
		key(e.keycode)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		if _drag >= 0:
			set_slider(_drag, e.position.x, false)
		else:
			var i := button_at(e.position)
			if i >= 0 and i != selected:
				selected = i
				Audio.fx(self, "hover")
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			var l := ledger_at(e.position)
			var s := slider_at(e.position)
			if l >= 0:
				set_ledger(Profile.LEDGER_MODES[l])
			elif s >= 0:
				_drag = s
				set_slider(s, e.position.x, false)
			else:
				var i := button_at(e.position)
				if i >= 0:
					selected = i
					press(i)
		elif _drag >= 0:
			set_slider(_drag, e.position.x, true)
			_drag = -1
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var s := slider_at(e.position)
		if s >= 0:
			nudge(s, 1.0 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
	accept_event()


# --- the sound row -----------------------------------------------------------------------------------------------

## Where the Sound row starts (its heading's baseline): under the buttons and their note.
func _sound_top() -> float:
	return button_rect(list().size() - 1).end.y + (64.0 if note != "" else 44.0)


func slider_rect(i: int) -> Rect2:
	var n := SOUND_KINDS.size()
	return Rect2(Vector2((size.x - BTN.x) / 2.0 + i * (SLIDER_W + (BTN.x - n * SLIDER_W) / (n - 1.0)), _sound_top() + 28.0), Vector2(SLIDER_W, SLIDER_H))


## The slider under `p` (its bar, a little taller to hit), or -1.
func slider_at(p: Vector2) -> int:
	for i in SOUND_KINDS.size():
		if slider_rect(i).grow_individual(4.0, 10.0, 4.0, 10.0).has_point(p):
			return i
	return -1


## Put slider `i` at the screen x `x` and say so. `final`: the drag is over.
func set_slider(i: int, x: float, final: bool) -> void:
	var r := slider_rect(i)
	set_sound(SOUND_KINDS[i][0], roundf(clampf((x - r.position.x) / r.size.x, 0.0, 1.0) * 100.0) / 100.0, final)


## Move slider `i` one wheel notch (`dir` +1 or -1).
func nudge(i: int, dir: float) -> void:
	var kind: String = SOUND_KINDS[i][0]
	set_sound(kind, roundf(clampf(float(sound[kind]) + dir * SOUND_STEP, 0.0, 1.0) * 100.0) / 100.0, true)


func set_sound(kind: String, v: float, final: bool) -> void:
	if sound.get(kind) == v and not final:
		return
	if roundi(v * 20.0) != roundi(float(sound.get(kind, 0.0)) * 20.0):
		Audio.fx(self, "slider_tick")  # a tick at every 5%
	sound[kind] = v
	sound_changed.emit(kind, v, final)


# --- the Ledger row ---------------------------------------------------------------------------------------------

## The button of setting `i` (Profile.LEDGER_MODES order: Full, Warnings only, Off), under the Sound row.
func ledger_rect(i: int) -> Rect2:
	var n := Profile.LEDGER_MODES.size()
	var w := (BTN.x - (n - 1.0) * LEDGER_GAP) / n
	return Rect2(Vector2((size.x - BTN.x) / 2.0 + i * (w + LEDGER_GAP), _sound_top() + 68.0), Vector2(w, 24.0))


## The Ledger button under `p`, or -1.
func ledger_at(p: Vector2) -> int:
	for i in Profile.LEDGER_MODES.size():
		if ledger_rect(i).has_point(p):
			return i
	return -1


## Choose the Ledger's setting and say so (unless it is the one already on).
func set_ledger(mode: String) -> void:
	if not Profile.LEDGER_MODES.has(mode) or mode == ledger:
		return
	ledger = mode
	Audio.fx(self, "click")
	ledger_changed.emit(mode)


# --- layout and drawing ----------------------------------------------------------------------------------

## Where the buttons start: under the title on the main menu, in a small panel on the pause menu.
func _top() -> float:
	return size.y * 0.35 if mode == Mode.MAIN else size.y * 0.5 - (list().size() * (BTN.y + GAP)) / 2.0 + 16.0


func button_rect(i: int) -> Rect2:
	return Rect2(Vector2((size.x - BTN.x) / 2.0, _top() + i * (BTN.y + GAP)), BTN)


## The entry at `p`, or -1.
func button_at(p: Vector2) -> int:
	for i in list().size():
		if button_rect(i).has_point(p):
			return i
	return -1


func _draw() -> void:
	if mode == Mode.MAIN:
		_draw_main()
	else:
		_draw_pause()
	var l := list()
	for i in l.size():
		var b := button_rect(i)
		var hot := i == selected
		draw_rect(b, ROW_BG)
		draw_rect(b, AMBER if hot else EDGE_DIM, false, 3.0 if hot else 1.0)
		_text(str(l[i]["label"]), b.position + Vector2(18.0, 31.0), 20, TEXT)
		var k := OS.get_keycode_string(l[i]["key"])
		var w := ThemeDB.fallback_font.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		_text(k, Vector2(b.end.x - w - 18.0, b.position.y + 30.0), 15, AMBER if hot else DIM_TEXT)
	if note != "":
		_centered(note, button_rect(l.size() - 1).end.y + 32.0, 16, GOOD)
	_draw_sound()
	_draw_ledger()


func _draw_sound() -> void:
	var a = Audio.of(self)
	var off: bool = a != null and a.muted
	var x0 := (size.x - BTN.x) / 2.0
	var top := _sound_top()
	_text("SOUND", Vector2(x0, top + 8.0), 13, AMBER)
	var hint := "MUTED  (Ctrl+M)" if off else "Ctrl+M mutes"
	_text(hint, Vector2(x0 + BTN.x - ThemeDB.fallback_font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, top + 8.0), 13, BAD if off else DIM_TEXT)
	for i in SOUND_KINDS.size():
		var r := slider_rect(i)
		var v: float = float(sound[SOUND_KINDS[i][0]])
		_text("%s %d%%" % [SOUND_KINDS[i][1], roundi(v * 100.0)], r.position + Vector2(0.0, -5.0), 13, DIM_TEXT if off else TEXT)
		draw_rect(r, ROW_BG)
		draw_rect(Rect2(r.position, Vector2(r.size.x * v, r.size.y)), DIM_TEXT if off else AMBER)
		draw_rect(r, AMBER if i == _drag else EDGE_DIM, false, 1.0)


func _draw_ledger() -> void:
	var x0 := (size.x - BTN.x) / 2.0
	var top := _sound_top()
	_text("THE LEDGER", Vector2(x0, top + 62.0), 13, AMBER)
	var hint := "Ma Gantry's goals, tips and warnings"
	_text(hint, Vector2(x0 + BTN.x - ThemeDB.fallback_font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, top + 62.0), 13, DIM_TEXT)
	for i in Profile.LEDGER_MODES.size():
		var r := ledger_rect(i)
		var on: bool = Profile.LEDGER_MODES[i] == ledger
		draw_rect(r, Color("#3a3020") if on else ROW_BG)
		draw_rect(r, AMBER if on else EDGE_DIM, false, 2.0 if on else 1.0)
		var label: String = {"full": "Full", "warn": "Warnings only", "off": "Off"}[Profile.LEDGER_MODES[i]]
		var w := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		_text(label, r.position + Vector2((r.size.x - w) / 2.0, 17.0), 13, TEXT if on else DIM_TEXT)


func _draw_main() -> void:
	_centered("HULLSCRAP", size.y * 0.2, 96, TEXT)
	_centered(TAGLINE, size.y * 0.2 + 44.0, 22, AMBER)
	_text(version, Vector2(size.x - 16.0 - ThemeDB.fallback_font.get_string_size(version, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, size.y - 14.0), 14, DIM_TEXT)
	if recent.is_empty():
		return
	var r := Rect2(24.0, size.y - 24.0 - (28.0 + 22.0 * recent.size()), 760.0, 28.0 + 22.0 * recent.size())
	draw_rect(r, Color(PANEL_BG, 0.85))
	draw_rect(r, EDGE_DIM, false, 1.0)
	_text("LAST RUNS", r.position + Vector2(12.0, 20.0), 13, AMBER)
	for i in recent.size():
		_text(Profile.run_line(recent[i]), r.position + Vector2(12.0, 42.0 + 22.0 * i), 14, TEXT if i == 0 else DIM_TEXT)


func _draw_pause() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	var top := _top()
	var p := Rect2(Vector2((size.x - BTN.x) / 2.0 - 28.0, top - 78.0), Vector2(BTN.x + 56.0, 78.0 + list().size() * (BTN.y + GAP) + 28.0 + (28.0 if note != "" else 0.0) + SOUND_H + LEDGER_H))
	_panel(p)
	_centered("PAUSED", top - 32.0, 26, TEXT)


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
