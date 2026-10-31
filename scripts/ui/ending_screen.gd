extends "res://scripts/ui/game_over.gd"
## The ending screen (docs/CONTENT.md section 13): a run that reached an ending (an event's `ending` effect) is a win,
## and this is its page. The ending's art (art/endings/<id>.png; a framed placeholder until it lands) with the title and
## the epilogue under it; your ship in a "hall of ships" frame; the score breakdown; the unlocks earned; the run log
## (regions, crew alive, landmarks and unlocks in order); then New run or Main menu. Same buttons and keys as the game
## over screen it extends (N, M, Up/Down, Enter, click); front_door.gd opens it with open_ending() and keeps the rest
## (the profile record, the hall of ships file, wiping the saves). Endings.report (endings.gd) makes the report.
## Placeholder shapes, in the UI colours of station_panel.gd.

const Art = preload("res://scripts/view/art.gd")
const Schematic = preload("res://scripts/ui/schematic.gd")
const Unlocks = preload("res://scripts/space/unlocks.gd")

const GOOD := Color("#6bd34a")
const BACKDROP := Color(0.02, 0.03, 0.05, 0.96)  ## nearly opaque: the HUD of the ship behind it must not show through
const SIZE := Vector2(1440.0, 820.0)
const PAD := 30.0
const ART_PX := Vector2(320.0, 180.0)  ## the illustration's size in source px
const LEFT_W := 656.0  ## the art frame's width: the illustration at 2x and an 8 px frame
const LIST_LINES := 6  ## log lines shown
const UNLOCK_LINES := 3
const GAP := 14.0

var report := {}  ## Endings.report of the run that ended
var ship = null  ## the player's Ship, drawn small in the hall of ships frame
var _sheet = null  ## the art (a SpriteSheet) or null: the placeholder
var _glow: Control
var _t := 0.0  # seconds since it opened: the art's ambient animation
var _stars: Array = []  # the placeholder's stars: [Vector2 (0..1), brightness]


func _ready() -> void:
	super._ready()
	_glow = Control.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	_glow.draw.connect(_draw_glow)
	add_child(_glow)


func _process(dt: float) -> void:
	if visible:
		_t += dt
		_glow.queue_redraw()
	super._process(dt)


## Show the ending page for `p_report` (Endings.report) with the player's `p_ship` in the hall of ships frame.
func open_ending(p_report: Dictionary, p_ship) -> void:
	report = p_report
	ship = p_ship
	_t = 0.0
	_sheet = Art.ending(str(report.get("ending", {}).get("id", "")))
	_stars = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(report.get("ending", {}).get("id", "")))  # visual only: the same stars for the same ending
	for i in 70:
		_stars.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(0.25, 1.0)])
	open({})


# --- layout ---------------------------------------------------------------------------------------------------

func panel_rect() -> Rect2:
	return Rect2(((size - SIZE) / 2.0).round(), SIZE)


func button_rect(i: int) -> Rect2:
	var p := panel_rect()
	var gap := 24.0
	var x := p.end.x - PAD - (BUTTONS.size() * BTN.x + (BUTTONS.size() - 1) * gap)
	return Rect2(Vector2(x + i * (BTN.x + gap), p.end.y - PAD - BTN.y), BTN)


## Where everything goes, in screen px: {panel, frame (the art's frame), art, epilogue, hall (the frame), ship (where the ship
## is drawn), score, unlocks, log}. Computed from `size` only, so drawing and tests agree.
func layout() -> Dictionary:
	var p := panel_rect()
	var o := p.position
	var right := o.x + PAD + LEFT_W + PAD
	var wide := p.end.x - PAD - right
	var hall := Rect2(right, o.y + 100.0, 290.0, 340.0)
	return {"panel": p, "frame": Rect2(o + Vector2(PAD, 100.0), Vector2(LEFT_W, 376.0)), "art": Rect2(o + Vector2(PAD + 8.0, 108.0), ART_PX * 2.0),
		"epilogue": Rect2(o + Vector2(PAD, 500.0), Vector2(LEFT_W, 226.0)),
		"hall": hall, "ship": Rect2(hall.position + Vector2(14.0, 14.0), Vector2(hall.size.x - 28.0, hall.size.y - 80.0)),
		"score": Rect2(hall.end.x + GAP + 6.0, hall.position.y, wide - hall.size.x - GAP - 6.0, hall.size.y),
		"unlocks": Rect2(right, o.y + 460.0, wide, 100.0), "log": Rect2(right, o.y + 572.0, wide, 154.0)}


## The run log's lines (regions, crew, then the log in order), the last ones folded into "... and N more".
func log_lines() -> Array[String]:
	var out: Array[String] = []
	var regions: Array = report.get("regions", [])
	out.append("Regions: " + (", ".join(PackedStringArray(regions)) if not regions.is_empty() else "none"))
	var crew: Array = report.get("crew", [])
	out.append("Crew alive (%d): %s" % [crew.size(), ", ".join(PackedStringArray(crew)) if not crew.is_empty() else "none"])
	var entries: Array = report.get("log", [])
	var room := LIST_LINES - out.size()
	for i in entries.size():
		if i == room - 1 and entries.size() > room:
			out.append("... and %d more" % (entries.size() - i))
			break
		out.append(entry_line(entries[i]))
	return out


## One run log entry as a line: "Jump 12  Landmark: Meet Ma In Person".
static func entry_line(e: Dictionary) -> String:
	var label: String = {"landmark": "Landmark", "unlock": "Unlocked", "ending": "Ending"}.get(str(e.get("kind", "")), "Event")
	return "Jump %d  %s: %s" % [int(e.get("jumps", 0)), label, str(e.get("text", ""))]


## The unlocks box's lines: each earned unlock with its kind, the last ones folded into "... and N more".
func unlock_lines() -> Array[String]:
	var out: Array[String] = []
	var list: Array = report.get("unlocks", [])
	if list.is_empty():
		return ["Nothing new this run."]
	for i in list.size():
		if i == UNLOCK_LINES - 1 and list.size() > UNLOCK_LINES:
			out.append("... and %d more" % (list.size() - i))
			break
		out.append("%s  (%s)" % [list[i]["name"], Unlocks.LABELS.get(list[i]["kind"], "Unlock")])
	return out


# --- drawing --------------------------------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)
	var lay := layout()
	var p: Rect2 = lay["panel"]
	_panel(p)
	var e: Dictionary = report.get("ending", {})
	_text("ENDING", p.position + Vector2(PAD, 36.0), 14, DIM_TEXT)
	_text(str(e.get("title", "The End")).to_upper(), p.position + Vector2(PAD, 80.0), 40, AMBER)
	_draw_art(lay)
	var ep: Rect2 = lay["epilogue"]
	draw_multiline_string(ThemeDB.fallback_font, ep.position + Vector2(0.0, 16.0), str(e.get("epilogue", "")), HORIZONTAL_ALIGNMENT_LEFT, ep.size.x, 17, 10, TEXT)
	_draw_hall(lay)
	_draw_score(lay["score"])
	var ul: Array[String] = unlock_lines()
	_box("UNLOCKS EARNED", lay["unlocks"], ul, GOOD if not (report.get("unlocks", []) as Array).is_empty() else DIM_TEXT)
	_box("RUN LOG", lay["log"], log_lines(), TEXT)
	_text("Jumps %d (par %d)    Fights won %d    Credits %d" % [int(report.get("jumps", 0)), int(report.get("par", 0)), int(report.get("fights", 0)),
		int(report.get("credits", 0))], p.position + Vector2(PAD, p.size.y - PAD - 14.0), 15, DIM_TEXT)
	for i in BUTTONS.size():
		var b := button_rect(i)
		var hot := i == selected
		draw_rect(b, ROW_BG)
		draw_rect(b, AMBER if hot else EDGE_DIM, false, 3.0 if hot else 1.0)
		var label: String = BUTTONS[i]["label"]
		var w := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_text(label, b.position + Vector2((b.size.x - w) / 2.0 - 8.0, 31.0), 20, TEXT)
		_text(OS.get_keycode_string(BUTTONS[i]["key"]), b.position + Vector2(b.size.x - 28.0, 30.0), 15, AMBER if hot else DIM_TEXT)


## The illustration (its frame of the ambient strip) in its frame, or the placeholder.
func _draw_art(lay: Dictionary) -> void:
	var fr: Rect2 = lay["frame"]
	var r: Rect2 = lay["art"]
	draw_rect(fr, Color("#0b0f16"))
	if _sheet != null:
		draw_texture_rect_region(_sheet.texture, _art_dest(r), _sheet.region(_sheet.loop_frame(_t)))
	else:
		draw_rect(r, Color("#121a26"))
		draw_rect(Rect2(r.position + Vector2(0.0, r.size.y * 0.62), Vector2(r.size.x, r.size.y * 0.38)), Color("#18222f"))
		for s in _stars:
			draw_rect(Rect2(r.position + s[0] * (r.size - Vector2(2.0, 2.0)), Vector2(2.0, 2.0)), Color(TEXT, s[1] * 0.8))
		var id := str(report.get("ending", {}).get("id", ""))
		_centered_in(r, str(report.get("ending", {}).get("title", "")), r.position.y + r.size.y / 2.0 - 4.0, 26, Color(AMBER, 0.55))
		_centered_in(r, "art/endings/%s.png" % id, r.position.y + r.size.y / 2.0 + 24.0, 14, DIM_TEXT)
	draw_rect(fr, EDGE, false, 2.0)
	draw_rect(fr.grow(-4.0), EDGE_DIM, false, 1.0)


## The rectangle the art is drawn in: whole multiples of its source size, centred in `r`.
func _art_dest(r: Rect2) -> Rect2:
	var f: Vector2 = _sheet.frame
	var k := maxf(floorf(minf(r.size.x / f.x, r.size.y / f.y)), 1.0)
	return Rect2(r.position + (r.size - f * k) / 2.0, f * k)


## The glow layer, added over the art (this control's material is additive).
func _draw_glow() -> void:
	if not visible or _sheet == null or _sheet.glow == null:
		return
	var g = _sheet.glow
	_glow.draw_texture_rect_region(g.texture, _art_dest(layout()["art"]), g.region(g.loop_frame(_t)))


## The hall of ships frame with the ship drawn small in it, its name and the ending under it.
func _draw_hall(lay: Dictionary) -> void:
	var h: Rect2 = lay["hall"]
	draw_rect(h, Color("#0b0f16"))
	draw_rect(h, EDGE, false, 2.0)
	draw_rect(h.grow(-5.0), AMBER, false, 1.0)
	for c in [h.position, Vector2(h.end.x, h.position.y), Vector2(h.position.x, h.end.y), h.end]:  # corner studs
		draw_rect(Rect2(c - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), AMBER)
	var inner: Rect2 = lay["ship"]
	draw_rect(inner, Color("#05080d"))
	if ship != null:
		ship.refresh()
		Schematic.draw_map(self, ship, ship.power_state.get("powered", {}), inner)
	_centered_in(h, "HALL OF SHIPS", h.end.y - 44.0, 13, DIM_TEXT)
	_centered_in(h, str(report.get("ship", "")), h.end.y - 18.0, 20, TEXT)


func _draw_score(r: Rect2) -> void:
	_panel(r, ROW_BG)
	_text("SCORE", r.position + Vector2(16.0, 28.0), 18, AMBER)
	var y := r.position.y + 62.0
	for row in report.get("score", {}).get("rows", []):
		_text(str(row["label"]), Vector2(r.position.x + 16.0, y), 17, TEXT)
		_text(str(row["detail"]), Vector2(r.position.x + 16.0, y + 15.0), 12, DIM_TEXT)
		var pts := int(row["points"])
		var v := "%+d" % pts if pts != 0 else "0"
		var w := ThemeDB.fallback_font.get_string_size(v, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_text(v, Vector2(r.end.x - w - 16.0, y + 4.0), 20, GOOD if pts > 0 else (BAD if pts < 0 else DIM_TEXT))
		y += 40.0
	draw_line(Vector2(r.position.x + 12.0, r.end.y - 52.0), Vector2(r.end.x - 12.0, r.end.y - 52.0), EDGE_DIM, 1.0)
	_text("TOTAL", Vector2(r.position.x + 16.0, r.end.y - 18.0), 20, TEXT)
	var t := str(int(report.get("score", {}).get("total", 0)))
	var tw := ThemeDB.fallback_font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	_text(t, Vector2(r.end.x - tw - 16.0, r.end.y - 14.0), 32, AMBER)


## A titled box of text lines.
func _box(title: String, r: Rect2, lines: Array, col: Color) -> void:
	_panel(r, ROW_BG)
	_text(title, r.position + Vector2(16.0, 24.0), 15, AMBER)
	var y := r.position.y + 44.0
	for l in lines:
		draw_string(ThemeDB.fallback_font, Vector2(r.position.x + 16.0, y), str(l), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 32.0, 16, col)
		y += 21.0


func _centered_in(r: Rect2, text: String, y: float, font_size: int, col: Color) -> void:
	var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(text, Vector2(r.position.x + (r.size.x - w) / 2.0, y), font_size, col)
