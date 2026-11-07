extends Control
## The event panel of the Drift: the FTL-style text box that opens on arrival. A scene text and a list of
## choices (keys 1-9 or a click). A blue choice (cyan, its reason in brackets) is open to a species,
## a trait or an installed part; a greyed one shows what it needs; the rest are hidden. A chosen choice
## shows its outcome, the changes in words and any derelict log found; Continue (Enter, Space or a
## click) goes on to the next page (goto), starts a fight, opens the ending screen (an outcome with the `ending`
## effect) or ends. open_notice() shows a plain page.
## A choice whose outcomes include a fight ends with the name line of the enemy it would send, "[Kett lancer]" ("[may fight: Kett lancer]" when only
## some of its outcomes fight), in her livery's colour, and a card beside the panel shows her real ship next to yours: no skulls, no numbers (the
## player learns to judge a ship by her look). The campaign rolls that enemy when the page opens and keeps it (Campaign.foe_for), so the fight is the one shown.
## While open it takes every key and click, over the map. The rules are in events.gd and campaign.gd; this
## node only reads input and draws, in the UI colours of docs/ART_STYLE.md.

## Emitted when the chain of pages is over.
signal finished
## Emitted when an outcome asked for a fight: `value` is "tier" or a design id, `after_win` {text, effects}.
signal fight_requested(value: String, after_win: Dictionary)
## Emitted when an outcome ended the run (the `ending` effect): `id` is the ending. The map turns it into the ending screen.
signal ending_reached(id: String)
## Emitted when an outcome sent the soldier aboard another vessel (the `board` effect): `spec` is the effect ({kind, ...}) and `ev` the page the
## choice was on, which the map opens again when he is back (the vessel stays boardable until it is cleared).
signal board_requested(spec: Dictionary, ev: Dictionary)
## Emitted when a talk aboard another vessel (a person's, or a discovery's: `talk` is set) is over instead of `finished`: `ops` is everything the outcomes asked
## of the boarding session (events.gd result "npc"), `acted` whether any outcome did something.
signal talk_done(ops: Array, acted: bool)

const BreachPrompt = preload("res://scripts/ui/breach_prompt.gd")
const FoeInfo = preload("res://scripts/space/foe_info.gd")
const FoePic = preload("res://scripts/ui/foe_pic.gd")
const Audio = preload("res://scripts/audio/audio.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const WIDTH := 940.0
const PAD := 26.0
const TITLE_H := 52.0
const GAP := 14.0
const ROW_PAD := 11.0
const ROW_GAP := 8.0
const ROW_TEXT_W := 90.0  ## px kept free at the right of a row's text
const TEXT_SIZE := 18
const ROW_SIZE := 17
const DIM := Color(0.0, 0.0, 0.0, 0.55)
const ROW_BG := Color("#2a3340")
const EDGE := Color("#cfd6df")
const EDGE_DIM := Color("#59667a")
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
var talk := {}  ## aboard another vessel: the node of the person or the spot the event is about ({type: boarding_npc ..., npc: {id, name, species, role}}), else {}. Set by the map before open_event
var talk_ops: Array = []  ## the ops the outcomes taken in this talk asked for
var talk_acted := false

var foe_pic: Control  ## the card of the enemy the hovered (else the first) fight choice may send: her ship next to yours
var _pic_for := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _process(_dt: float) -> void:
	if visible:
		_update_pic()
		queue_redraw()


## The enemy card beside the panel: the fight choice under the mouse, else the first one that may fight.
func _update_pic() -> void:
	if foe_pic == null:
		foe_pic = FoePic.new()
		add_child(foe_pic)
		foe_pic.visible = false
	var design := ""
	if page == "choices":
		if hover >= 0 and hover < view.size() and view[hover].has("foe"):
			design = str(view[hover]["foe"])
		else:
			for v in view:
				if v.has("foe"):
					design = str(v["foe"])
					break
	if design == "":
		foe_pic.visible = false
		_pic_for = ""
		return
	if design != _pic_for:
		_pic_for = design
		var info := FoeInfo.of(design)
		foe_pic.show_foe(info.get("ship"), map.ship(), str(info.get("line", "")), info.get("boss", {}))
	var p: Rect2 = layout()["panel"]
	if p.end.x + 12.0 + FoePic.BOX.x + 8.0 <= size.x:  # beside the panel when there is room, else under it (or over it)
		foe_pic.position = Vector2(p.end.x + 12.0, p.position.y)
	elif p.end.y + 12.0 + foe_pic.size.y + 8.0 <= size.y:
		foe_pic.position = Vector2(p.position.x, p.end.y + 12.0)
	else:
		foe_pic.position = Vector2(p.position.x, maxf(p.position.y - foe_pic.size.y - 12.0, 4.0))
	foe_pic.visible = true


func _campaign():
	return map.campaign


func _node() -> Dictionary:
	var n: Dictionary = map.campaign.node(map.campaign.current)
	return n if talk.is_empty() else n.merged(talk, true)


# --- actions --------------------------------------------------------------------------------------------------

## Show event `ev` (a dictionary from events.gd) at the current node.
func open_event(ev: Dictionary) -> void:
	var c = _campaign()
	if not talk.is_empty():
		ev = c.events.personalize(ev, str(talk.get("npc", {}).get("name", "")))
	event = ev
	var place: String = map.poi_title() if map.has_method("poi_title") else ""  # at a POI: its name, not the node's
	title = str(ev.get("title", place if place != "" else c.label(c.current)))  # an event built in code (salvage) may name its own title
	if not talk.is_empty() and not ev.has("title"):
		var who: Dictionary = talk.get("npc", {})
		title = "%s, %s" % [who["name"], str(who.get("label", who.get("role", ""))).to_lower()] if not who.is_empty() else "Aboard"
	view = c.events.choice_view(ev, c, map.ship(), _node())
	var leave := {"index": -1, "text": "Leave.", "blue": false, "grey": false, "need": ""}
	if view.is_empty():
		view = [leave]
	elif view.all(func(v): return v["grey"]):
		view.append(leave)  # every choice needs something you lack: never leave the panel without a way out
	for v in view:
		_tag_threat(v)
		_tag_risk(v)
	page = "choices"
	message = ""
	hover = -1
	visible = true
	Audio.fx(self, "event_open")


## Show a page with only a text and Continue.
func open_notice(p_title: String, text: String, lines: Array) -> void:
	event = {}
	view = []
	title = p_title
	result = {"text": text, "lines": lines, "logs": [], "goto": "", "fight": "", "ending": "", "after_win": {}}
	page = "result"
	message = ""
	visible = true
	Audio.fx(self, "open")


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
		message = str(v["locked"]) if str(v.get("locked", "")) != "" else "You need " + v["need"]
		Audio.fx(self, "error")
		return message
	Audio.fx(self, "confirm")
	if v["index"] < 0:
		close()
		_end()
		return ""
	var c = _campaign()
	var r: Dictionary = c.events.choose(event, v["index"], c, map.ship(), _node())
	if not r["ok"]:
		message = r["why"]
		return message
	result = r
	page = "result"
	message = ""
	if not talk.is_empty():
		talk_ops.append_array(r.get("npc", []))
		talk_acted = talk_acted or bool(r.get("acted", false))
	map.refresh()
	if str(r["text"]) == "" and r["lines"].is_empty() and r["logs"].is_empty():
		proceed()  # nothing to read: straight on
	return ""


## Leave the result page: the next page, a fight, the ending screen, or the end.
func proceed() -> void:
	if page != "result":
		return
	var c = _campaign()
	var r := result
	if str(r.get("fight", "")) != "":
		close()
		fight_requested.emit(str(r["fight"]), r.get("after_win", {}))
	elif str(r.get("ending", "")) != "":
		close()
		ending_reached.emit(str(r["ending"]))
	elif not r.get("board", {}).is_empty():
		var back := event
		close()
		board_requested.emit(r["board"], back)
	elif str(r.get("goto", "")) != "" and c.events.has(str(r["goto"])):
		open_event(c.events.get_event(str(r["goto"])))
	else:
		close()
		_end()


## The chain of pages is over: `finished`, or for a talk aboard another vessel `talk_done` with what it asked for.
func _end() -> void:
	if talk.is_empty():
		finished.emit()
		return
	var ops := talk_ops
	var acted := talk_acted
	talk = {}
	talk_ops = []
	talk_acted = false
	talk_done.emit(ops, acted)


# --- input ------------------------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey):
		return
	if BreachPrompt.claims(e):
		return  # R and V answer the breach card, whatever window is open
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
			var h := maxf((v["lines"].size() * _font().get_height(ROW_SIZE) if v.has("lines") else _wrapped(_row_label(v), inner - ROW_TEXT_W, ROW_SIZE)) + 2.0 * ROW_PAD, 40.0)
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
	return "%s%s" % [v["text"], (("   (%s)" if str(v.get("locked", "")) != "" else "   (needs %s)") % v["need"]) if v["grey"] else ""]


# --- threat tags ----------------------------------------------------------------------------------------------------

## Mark choice `v` (an entry of `view`) with the enemy the fight it may start would send: `tag` ("[Kett lancer]" or "[may fight: Kett lancer]", the
## name line of her real ship: no skulls, no numbers), `foe` (the design, for the picture) and `lines` (its label wrapped with the tag at the end of
## the last line). Nothing for a choice with no fight.
func _tag_threat(v: Dictionary) -> void:
	if int(v["index"]) < 0:
		return
	var outcomes: Array = event["choices"][v["index"]].get("outcomes", [])
	var fights := 0
	var design := ""
	for o in outcomes:
		var eff = o.get("effects") if o is Dictionary else null
		if eff is Dictionary and str(eff.get("fight", "")) != "":
			fights += 1
			if design == "":
				design = map.fight_design(str(eff["fight"]))
	if fights == 0 or design == "":
		return
	var info := FoeInfo.of(design)
	if info.is_empty():
		return
	v["foe"] = design
	_set_tag(v, "[%s%s]" % ["may fight: " if fights < outcomes.size() else "", info["line"]], info["palette"]["mark"] if not info["palette"].is_empty() else AMBER)


## An expedition choice's odds (events.gd choice_view `risk`) as the same kind of tag at the end of its line: red for a crew loss, amber for lost gear, else by risk.
func _tag_risk(v: Dictionary) -> void:
	if not v.has("risk"):
		return
	var tone := str(v["risk"]["tone"])
	_set_tag(v, str(v["risk"]["text"]), BAD if tone == "loss" else (AMBER if tone == "gear" else (GOOD if str(v["risk"]["text"]).contains("low") else AMBER)))


func _set_tag(v: Dictionary, tag: String, color: Color) -> void:
	v["tag"] = tag
	v["tag_color"] = color
	var para := TextParagraph.new()  # the tag's spaces do not break, so it never splits over two lines
	para.width = WIDTH - 2.0 * PAD - ROW_TEXT_W
	var text := "%s %s" % [_row_label(v), str(v["tag"]).replace(" ", "\u00a0")]
	para.add_string(text, _font(), ROW_SIZE)
	var lines := []
	for k in para.get_line_count():
		var span := para.get_line_range(k)
		lines.append(text.substr(span.x, span.y - span.x).replace("\u00a0", " ").strip_edges(false, true))
	v["lines"] = lines


# --- drawing -------------------------------------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	var lay := layout()
	var p: Rect2 = lay["panel"]
	UiKit.frame(self, p)
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
	if not v.has("lines"):
		draw_multiline_string(_font(), r.position + Vector2(44.0, ROW_PAD + 14.0), _row_label(v), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - ROW_TEXT_W, ROW_SIZE, -1, col)
		return
	var lines: Array = v["lines"]  # the text wrapped with its threat tag at the end, which has a colour of its own
	for k in lines.size():
		var at := r.position + Vector2(44.0, ROW_PAD + 14.0 + k * _font().get_height(ROW_SIZE))
		var line := str(lines[k])
		if k < lines.size() - 1:
			_text(line, at, ROW_SIZE, col)
			continue
		var head := line.substr(0, line.length() - str(v["tag"]).length())
		_text(head, at, ROW_SIZE, col)
		_text(str(v["tag"]), at + Vector2(_font().get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_SIZE).x, 0.0), ROW_SIZE, v["tag_color"])


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
	var ended := str(result.get("ending", "")) != "" and not fighting
	var boards: bool = not result.get("board", {}).is_empty() and not fighting and not ended
	draw_rect(b, ROW_BG)
	draw_rect(b, BAD if fighting else (AMBER if ended or boards else EDGE), false, 2.0)
	_text("To battle (Enter)" if fighting else ("The end (Enter)" if ended else ("Go aboard (Enter)" if boards else "Continue (Enter)")), b.position + Vector2(24.0, 28.0), 17, BAD if fighting else (AMBER if ended or boards else TEXT))


## How a change line reads: 1 good (a gain, a debt paid), -1 bad (a loss, a debt grown), 0 neither.
static func tone_of(line: String) -> int:
	if line.contains("is lost"):
		return -1
	if line.contains("joins") or line.contains("rejoins") or line.contains("learned") or line.begins_with("Blueprint:") or line.begins_with("Log ") or line.begins_with("On the map") or line.begins_with("Unlocked") or line.begins_with("Landmark"):
		return 1
	var re := RegEx.new()
	re.compile("[+-][0-9]+")
	var m := re.search(line)
	if m == null:
		return 0
	var sign := 1 if m.get_string().begins_with("+") else -1
	return -sign if line.begins_with("Debt") else sign


func _text(text: String, at: Vector2, font_size: int, col: Color) -> void:
	draw_string(_font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
