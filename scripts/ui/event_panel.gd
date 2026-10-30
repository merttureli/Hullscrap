extends Control
## The event panel of the Drift: the FTL-style text box that opens on arrival. A scene text and a list of
## choices (keys 1-9 or a click). A blue choice (cyan, its reason in brackets) is open to a species,
## a trait or an installed part; a greyed one shows what it needs; the rest are hidden. A chosen choice
## shows its outcome, the changes in words and any derelict log found; Continue (Enter, Space or a
## click) goes on to the next page (goto), starts a fight, or ends. open_notice() shows a plain page.
## While open it takes every key and click, over the map. The rules are in events.gd and campaign.gd; this
## node only reads input and draws, in the UI colours of docs/ART_STYLE.md.

## Emitted when the chain of pages is over.
signal finished
## Emitted when an outcome asked for a fight: `value` is "tier" or a design id, `after_win` {text, effects}.
signal fight_requested(value: String, after_win: Dictionary)

const WIDTH := 940.0
const PAD := 26.0
const TITLE_H := 52.0
const GAP := 14.0
const ROW_PAD := 11.0
const ROW_GAP := 8.0
const TEXT_SIZE := 18
const ROW_SIZE := 17
const DIM := Color(0.0, 0.0, 0.0, 0.55)
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
const CYAN := Color("#43e6ff")

var map: Control  ## the MapView: its campaign and ship
var event := {}  ## the event shown ({} for a notice)
var view: Array = []  ## the choices on offer: events.choice_view() plus a Leave when there are none
var page := "choices"  ## "choices", or "result" (an outcome or a notice)
var result := {}  ## the outcome shown: {text, lines, logs, goto, fight, after_win}
var title := ""
var message := ""  ## why a choice was refused
var hover := -1  ## the choice under the mouse


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func _campaign():
	return map.campaign


func _node() -> Dictionary:
	return map.campaign.node(map.campaign.current)


# --- actions --------------------------------------------------------------------------------------------------

## Show event `ev` (a dictionary from events.gd) at the current node.
func open_event(ev: Dictionary) -> void:
	var c = _campaign()
	event = ev
	title = c.label(c.current)
	view = c.events.choice_view(ev, c, map.ship(), _node())
	if view.is_empty():
		view = [{"index": -1, "text": "Leave.", "blue": false, "grey": false, "need": ""}]
	page = "choices"
	message = ""
	hover = -1
	visible = true


## Show a page with only a text and Continue.
func open_notice(p_title: String, text: String, lines: Array) -> void:
	event = {}
	view = []
	title = p_title
	result = {"text": text, "lines": lines, "logs": [], "goto": "", "fight": "", "after_win": {}}
	page = "result"
	message = ""
	visible = true


func close() -> void:
	visible = false
	event = {}
	view = []
	result = {}


## Take choice `i` of `view`. Returns "" or why it was refused.
func choose(i: int) -> String:
	if page != "choices" or i < 0 or i >= view.size():
		return "no such choice"
	var v: Dictionary = view[i]
	if v["grey"]:
		message = "You need " + v["need"]
		return message
	if v["index"] < 0:
		close()
		finished.emit()
		return ""
	var c = _campaign()
	var r: Dictionary = c.events.choose(event, v["index"], c, map.ship(), _node())
	if not r["ok"]:
		message = r["why"]
		return message
	result = r
	page = "result"
	message = ""
	map.refresh()
	if str(r["text"]) == "" and r["lines"].is_empty() and r["logs"].is_empty():
		proceed()  # nothing to read: straight on
	return ""


## Leave the result page: the next page, a fight, or the end.
func proceed() -> void:
	if page != "result":
		return
	var c = _campaign()
	var r := result
	if str(r.get("fight", "")) != "":
		close()
		fight_requested.emit(str(r["fight"]), r.get("after_win", {}))
	elif str(r.get("goto", "")) != "" and c.events.has(str(r["goto"])):
		open_event(c.events.enter(c.events.get_event(str(r["goto"])), c))
	else:
		close()
		finished.emit()


# --- input ------------------------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey):
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()
	if not e.pressed or e.echo:
		return
	if page == "result":
		if e.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
			proceed()
	elif e.keycode >= KEY_1 and e.keycode <= KEY_9:
		choose(e.keycode - KEY_1)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hover = choice_at(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if page == "result":
			if layout()["button"].has_point(e.position):
				proceed()
		else:
			var i := choice_at(e.position)
			if i >= 0:
				choose(i)
	accept_event()


## The choice at `p`, or -1.
func choice_at(p: Vector2) -> int:
	if page != "choices":
		return -1
	var rows: Array = layout()["rows"]
	for i in rows.size():
		if rows[i].has_point(p):
			return i
	return -1


## The rectangle of choice `i` on screen.
func choice_rect(i: int) -> Rect2:
	return layout()["rows"][i]


# --- layout -------------------------------------------------------------------------------------------------------

func _font() -> Font:
	return ThemeDB.fallback_font


func _wrapped(text: String, width: float, font_size: int) -> float:
	return _font().get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y if text != "" else 0.0


## Where everything goes for the page now: {panel, text (Rect2), rows (the choices), lines (y of each
## change), log (Rect2), button (Rect2)}. Computed from `size` and the content, so drawing and clicking agree.
func layout() -> Dictionary:
	var inner := WIDTH - 2.0 * PAD
	var y := PAD + TITLE_H
	var out := {"rows": [], "lines": [], "log": Rect2(), "button": Rect2()}
	var body := str(event.get("text", "")) if page == "choices" else str(result.get("text", ""))
	var text_h := _wrapped(body, inner, TEXT_SIZE)
	out["text"] = Rect2(Vector2(PAD, y), Vector2(inner, text_h))
	y += text_h + GAP * 1.5
	if page == "choices":
		for v in view:
			var h := maxf(_wrapped(_row_label(v), inner - 90.0, ROW_SIZE) + 2.0 * ROW_PAD, 40.0)
			out["rows"].append(Rect2(Vector2(PAD, y), Vector2(inner, h)))
			y += h + ROW_GAP
		if message != "":
			y += 6.0
			out["message_y"] = y + 14.0
			y += 26.0
	else:
		for l in result.get("lines", []):
			out["lines"].append(y + 18.0)
			y += 24.0
		for l in result.get("logs", []):
			var h := 44.0 + _wrapped(str(l.get("text", "")), inner - 24.0, 15)
			out["log"] = Rect2(Vector2(PAD, y + 8.0), Vector2(inner, h))
			y += h + 14.0
		y += GAP
		out["button"] = Rect2(Vector2(PAD + inner - 220.0, y), Vector2(220.0, 42.0))
		y += 42.0
	y += PAD
	var panel := Rect2((size - Vector2(WIDTH, y)) / 2.0, Vector2(WIDTH, y))
	panel.position = panel.position.round()
	for k in ["text", "log", "button"]:
		out[k] = Rect2(out[k].position + panel.position, out[k].size)
	out["rows"] = out["rows"].map(func(r): return Rect2(r.position + panel.position, r.size))
	out["lines"] = out["lines"].map(func(ly): return ly + panel.position.y)
	if out.has("message_y"):
		out["message_y"] += panel.position.y
	out["panel"] = panel
	return out


func _row_label(v: Dictionary) -> String:
	return "%s%s" % [v["text"], ("   (needs %s)" % v["need"]) if v["grey"] else ""]


# --- drawing -------------------------------------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	var lay := layout()
	var p: Rect2 = lay["panel"]
	_panel(p)
	_text(title.to_upper(), p.position + Vector2(PAD, 36.0), 22, AMBER)
	draw_line(p.position + Vector2(PAD, TITLE_H - 6.0), p.position + Vector2(p.size.x - PAD, TITLE_H - 6.0), EDGE_DIM, 1.0)
	var t: Rect2 = lay["text"]
	if t.size.y > 0.0:
		draw_multiline_string(_font(), t.position + Vector2(0.0, 16.0), str(event.get("text", "")) if page == "choices" else str(result.get("text", "")),
			HORIZONTAL_ALIGNMENT_LEFT, t.size.x, TEXT_SIZE, -1, TEXT)
	if page == "choices":
		for i in view.size():
			_draw_row(i, lay["rows"][i])
		if message != "":
			_text(message, Vector2(p.position.x + PAD, lay["message_y"]), 15, BAD)
	else:
		_draw_result(lay)


func _draw_row(i: int, r: Rect2) -> void:
	var v: Dictionary = view[i]
	var hot: bool = i == hover and not v["grey"]
	var edge := CYAN if v["blue"] else EDGE_DIM
	draw_rect(r, ROW_BG)
	draw_rect(r, AMBER if hot else edge, false, 3.0 if hot else (2.0 if v["blue"] else 1.0))
	var col := DIM_TEXT if v["grey"] else (CYAN if v["blue"] else TEXT)
	_text("%d" % (i + 1), r.position + Vector2(14.0, ROW_PAD + 15.0), ROW_SIZE, AMBER if not v["grey"] else EDGE_DIM)
	draw_multiline_string(_font(), r.position + Vector2(44.0, ROW_PAD + 14.0), _row_label(v), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 90.0, ROW_SIZE, -1, col)


func _draw_result(lay: Dictionary) -> void:
	var p: Rect2 = lay["panel"]
	var ls: Array = result.get("lines", [])
	for i in ls.size():
		var line := str(ls[i])
		var tone := tone_of(line)
		var col := GOOD if tone > 0 else (BAD if tone < 0 else TEXT)
		_text(line, Vector2(p.position.x + PAD + 6.0, lay["lines"][i]), 17, col)
	var logs: Array = result.get("logs", [])
	if not logs.is_empty():
		var lr: Rect2 = lay["log"]
		var l: Dictionary = logs[0]
		draw_rect(lr, Color("#10151c"))
		draw_rect(lr, EDGE_DIM, false, 1.0)
		_text("DATA PAD: %s" % l.get("title", ""), lr.position + Vector2(12.0, 24.0), 15, AMBER)
		draw_multiline_string(_font(), lr.position + Vector2(12.0, 46.0), str(l.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, lr.size.x - 24.0, 15, -1, DIM_TEXT)
	var b: Rect2 = lay["button"]
	var fighting := str(result.get("fight", "")) != ""
	draw_rect(b, ROW_BG)
	draw_rect(b, BAD if fighting else EDGE, false, 2.0)
	_text("To battle (Enter)" if fighting else "Continue (Enter)", b.position + Vector2(24.0, 28.0), 17, BAD if fighting else TEXT)


## How a change line reads: 1 good (a gain, a debt paid), -1 bad (a loss, a debt grown), 0 neither.
static func tone_of(line: String) -> int:
	if line.contains("is lost"):
		return -1
	if line.contains("joins") or line.contains("learned") or line.begins_with("Log found") or line.begins_with("On the map"):
		return 1
	var re := RegEx.new()
	re.compile("[+-][0-9]+")
	var m := re.search(line)
	if m == null:
		return 0
	var sign := 1 if m.get_string().begins_with("+") else -1
	return -sign if line.begins_with("Debt") else sign


## A chunky panel: a slate fill, a 2 px light border and a 1 px inner highlight.
func _panel(r: Rect2, fill := PANEL_BG) -> void:
	draw_rect(r, fill)
	draw_rect(r, EDGE, false, 2.0)
	draw_rect(r.grow(-3.0), HIGHLIGHT, false, 1.0)


func _text(text: String, at: Vector2, font_size: int, col: Color) -> void:
	draw_string(_font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
