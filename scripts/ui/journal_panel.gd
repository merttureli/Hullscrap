extends Control
## The journal: the derelict logs found this run (campaign.logs_found), each with its title, where it came from and its
## text. J opens it from the map; Esc, J or Enter close it, Up / Down / PgUp / PgDn / the wheel scroll it by a log.
## While open it takes every key and click. In the style of the help panel (help_panel.gd).

## Emitted when the panel is closed.
const Audio = preload("res://scripts/audio/audio.gd")

signal closed

const WIDTH := 980.0
const MARGIN := 40.0
const PAD := 22.0
const HEAD_H := 78.0
const FOOT_H := 38.0
const GAP := 14.0
const TITLE_SIZE := 17
const TEXT_SIZE := 15
const DIM := Color(0.0, 0.0, 0.0, 0.8)
const PANEL_BG := Color("#1f2630")
const ROW_BG := Color("#2a3340")
const EDGE := Color("#cfd6df")
const EDGE_DIM := Color("#59667a")
const HIGHLIGHT := Color(1.0, 1.0, 1.0, 0.1)
const TEXT := Color("#eef2f7")
const DIM_TEXT := Color("#97a3b3")
const AMBER := Color("#e1a136")

var map: Control  ## the MapView: its campaign (logs_found) and events (the logs)
var top := 0  ## the first log shown


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


## The logs found this run, in the order they were found: [{id, title, ship, text}].
func entries() -> Array:
	var out := []
	var c = map.campaign if map != null else null
	if c == null:
		return out
	for id in c.logs_found:
		var l = c.events.logs.get(str(id))
		if l is Dictionary:
			out.append({"id": str(id), "title": str(l.get("title", id)), "ship": str(l.get("ship", "")), "text": str(l.get("text", ""))})
	return out


func open() -> void:
	if visible:
		return
	top = 0
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
	if not visible or not (e is InputEventKey):
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()
	if not e.pressed:
		return
	match e.keycode:
		KEY_ESCAPE, KEY_J, KEY_ENTER, KEY_KP_ENTER:
			if not e.echo:
				close()
		KEY_DOWN:
			scroll(1)
		KEY_UP:
			scroll(-1)
		KEY_PAGEDOWN:
			scroll(3)
		KEY_PAGEUP:
			scroll(-3)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_WHEEL_DOWN:
				scroll(1)
			MOUSE_BUTTON_WHEEL_UP:
				scroll(-1)
	accept_event()


## Move the list `n` logs down (negative: up), within the list.
func scroll(n: int) -> void:
	top = clampi(top + n, 0, maxi(entries().size() - 1, 0))


# --- layout and drawing ------------------------------------------------------------------------------------

func panel_rect() -> Rect2:
	var w := minf(WIDTH, size.x - 2.0 * MARGIN)
	return Rect2(Vector2((size.x - w) / 2.0, MARGIN), Vector2(w, size.y - 2.0 * MARGIN))


## The height of the card of log `e` in a panel `w` wide: its title, its source line and its text wrapped.
static func card_h(e: Dictionary, w: float) -> float:
	var font := ThemeDB.fallback_font
	return font.get_multiline_string_size(str(e["text"]), HORIZONTAL_ALIGNMENT_LEFT, w - 2.0 * PAD - 20.0, TEXT_SIZE).y + 46.0


## The cards that fit from `top`, as [{entry, rect}].
func visible_cards() -> Array:
	var p := panel_rect()
	var out := []
	var y := p.position.y + HEAD_H
	var limit := p.end.y - FOOT_H
	var all := entries()
	for i in range(top, all.size()):
		var h := card_h(all[i], p.size.x)
		if y + h > limit and not out.is_empty():
			break
		out.append({"entry": all[i], "rect": Rect2(Vector2(p.position.x + PAD, y), Vector2(p.size.x - 2.0 * PAD, h))})
		y += h + GAP
	return out


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	var p := panel_rect()
	_panel(p)
	var all := entries()
	_text("JOURNAL", p.position + Vector2(PAD, 40.0), 26, TEXT)
	_text("%d log%s found this run" % [all.size(), "" if all.size() == 1 else "s"], p.position + Vector2(PAD + 160.0, 38.0), 15, DIM_TEXT)
	if all.is_empty():
		_text("Nothing yet. Logs turn up in derelicts, wrecks and the odd radio ghost.", p.position + Vector2(PAD, HEAD_H + 30.0), TEXT_SIZE, DIM_TEXT)
	var font := ThemeDB.fallback_font
	var shown := visible_cards()
	for c in shown:
		var r: Rect2 = c["rect"]
		var e: Dictionary = c["entry"]
		draw_rect(r, ROW_BG)
		draw_rect(r, EDGE_DIM, false, 1.0)
		_text(str(e["title"]), r.position + Vector2(10.0, 22.0), TITLE_SIZE, AMBER)
		if str(e["ship"]) != "":
			_text(str(e["ship"]), Vector2(r.end.x - 10.0 - font.get_string_size(str(e["ship"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, r.position.y + 20.0), 13, DIM_TEXT)
		draw_multiline_string(font, r.position + Vector2(10.0, 30.0 + font.get_ascent(TEXT_SIZE)), str(e["text"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20.0, TEXT_SIZE, -1, TEXT)
	if top + shown.size() < all.size():
		_text("v more (Down / wheel)", Vector2(p.end.x - PAD - 150.0, p.end.y - 12.0), 13, DIM_TEXT)
	_text("J / Esc / Enter: close    Up / Down / wheel: scroll", Vector2(p.position.x + PAD, p.end.y - 12.0), 13, DIM_TEXT)


## A chunky panel: a slate fill, a 2 px light border and a 1 px inner highlight.
func _panel(r: Rect2, fill := PANEL_BG) -> void:
	draw_rect(r, fill)
	draw_rect(r, EDGE, false, 2.0)
	draw_rect(r.grow(-3.0), HIGHLIGHT, false, 1.0)


func _text(text: String, at: Vector2, font_size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
