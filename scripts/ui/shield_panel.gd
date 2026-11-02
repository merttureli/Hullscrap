extends Control
## The Shields tab (H, in build or play mode): a screen over the game where the shield balance of the
## player's ship is set. Left: the ship's silhouette (the combat schematic's map) with its real bubble, the
## convex outline round the hull, cut into the generator's sectors; each sector has a - and a + button and
## shows its weight and layers. Right: what the generators give, the weight of every sector, the presets
## (Even, Bow, Stern, Port, Starboard) and two custom slots to save and load. The weights stay summed to the
## sector count (shield_balance.gd). A generator with one sector is one piece: nothing to set.
## The choice is kept in `ship.shield_balance` (saved with the ship) and is how every fight starts.
## While open it takes every key and click (Esc or H closes); the game keeps running behind it. The rules
## are in shield_balance.gd and shields.gd; this node reads input and draws, in the UI colours of
## docs/ART_STYLE.md like the crafting and station screens. build_mode.gd makes it and opens it on H.

const Schematic = preload("res://scripts/ui/schematic.gd")
const ShipView = preload("res://scripts/view/ship_view.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Shape = preload("res://scripts/combat/shield_shape.gd")
const Balance = preload("res://scripts/combat/shield_balance.gd")
const Audio = preload("res://scripts/audio/audio.gd")

const MARGIN := 40.0
const PAD := 18.0
const TITLE_H := 56.0
const FOOT_H := 46.0
const MAP_SHARE := 0.6  ## of the panel's width
const BTN := Vector2(30.0, 30.0)  ## a sector's - and + buttons
const PRESET_BTN := Vector2(104.0, 32.0)
const SLOT_BTN := Vector2(72.0, 30.0)
const ROW_H := 28.0
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
const BUBBLE := Color("#5fd4ff")
const ONE_PIECE := "This generator is one piece: no balance to set."

var sim: Node  ## the ShipSim whose player ship is set up
var message := ""
var message_bad := false
var hover_id := ""  ## the button under the mouse
var _shape: RefCounted
var _shape_sig: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


# --- the data the screen shows --------------------------------------------------------------------

## The player's ship (null before the scene is wired).
func ship():
	return sim.player_ship() if sim != null else null


## uid -> powered for the ship's parts, after a fresh power solve.
func powered() -> Dictionary:
	var s = ship()
	if s == null:
		return {}
	s.refresh()
	return s.power_state.get("powered", {})


## Sectors of the ship's bubble: the best powered generator's.
func sector_count() -> int:
	var s = ship()
	return Shields.sectors_of_ship(s, powered()) if s != null else 1


## The layers of a weight-1 sector: what the powered generators give.
func layers() -> int:
	var s = ship()
	return Shields.layers_of_ship(s, powered()) if s != null else 0


## The weights in force: the ship's saved ones when they suit the sector count, else even.
func weights() -> Array:
	var s = ship()
	var n := sector_count()
	return Balance.normalized(s.shield_balance.get("weights", []), n) if s != null else Balance.even(n)


## The layers each sector holds at those weights.
func caps() -> Array:
	var out := []
	for w in weights():
		out.append(layers() * float(w))
	return out


## The names of the powered shield generators on the ship.
func generators() -> Array:
	var s = ship()
	var out := []
	if s == null:
		return out
	var pw := powered()
	var uids: Array = s.components.instances.keys()
	uids.sort()
	for uid in uids:
		var d: Dictionary = s.components.def(s.components.instances[uid]["id"])
		if d.get("family", "") == "shield" and pw.get(uid, false):
			out.append(str(d.get("name", d["id"])))
	return out


## The bubble's outline round the ship's cells (cached until they change).
func shape() -> RefCounted:
	var s = ship()
	var sig: Array = Shape.signature(s)
	if _shape == null or _shape_sig != sig:
		_shape = Shape.from_cells(Shape.cells_of(s), Shape.centre_of(s))
		_shape_sig = sig
	return _shape


# --- actions (the buttons and keys call these) ---------------------------------------------------------

func open() -> void:
	if ship() == null:
		return
	message = ""
	hover_id = ""
	visible = true
	Audio.fx(self, "open")
	queue_redraw()


func close() -> void:
	if visible:
		Audio.fx(self, "close")
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Keep weights `w` on the ship (an even list is kept as "none chosen"). Returns "".
func _store(w: Array, text: String) -> String:
	var s = ship()
	s.shield_balance["weights"] = [] if w == Balance.even(w.size()) else w.duplicate()
	_say(text, false)
	Audio.fx(self, "shield_shift")
	return ""


func _say(text: String, bad: bool) -> void:
	message = text
	message_bad = bad


## The + (delta 1) or - (delta -1) of sector `sector`. A + takes half a weight from the opposite
## sector first, then evenly from the others; a - gives it to the opposite one. "" or why it was refused.
func adjust(sector: int, delta: int) -> String:
	var n := sector_count()
	if ship() == null:
		return "no ship"
	if n < 2:
		_say(ONE_PIECE, true)
		return ONE_PIECE
	var r := Balance.step(weights(), sector, delta)
	if r["why"] != "":
		_say(r["why"], true)
		return r["why"]
	var w: Array = r["weights"]
	return _store(w, "%s %.1f" % [Balance.name_of(n, sector), w[sector]])


## Set a preset: "Even", "Bow", "Stern", "Port" or "Starboard". "" or why it was refused.
func apply_preset(preset_name: String) -> String:
	var n := sector_count()
	if ship() == null:
		return "no ship"
	if n < 2:
		_say(ONE_PIECE, true)
		return ONE_PIECE
	var w := Balance.preset(n, preset_name)
	if w.is_empty():
		var why := "%s needs 4 sectors" % preset_name
		_say(why, true)
		return why
	return _store(w, "Preset: " + preset_name)


## Save the weights in force in custom slot `i` (0 or 1). "" or why not.
func save_slot(i: int) -> String:
	var n := sector_count()
	if ship() == null or i < 0 or i >= Balance.SLOTS:
		return "no such slot"
	if n < 2:
		_say(ONE_PIECE, true)
		return ONE_PIECE
	ship().shield_balance["presets"][i] = weights().duplicate()
	_say("Saved in slot %d" % (i + 1), false)
	return ""


## Load custom slot `i`. "" or why not (empty, or saved for another sector count).
func load_slot(i: int) -> String:
	var n := sector_count()
	if ship() == null or i < 0 or i >= Balance.SLOTS:
		return "no such slot"
	if n < 2:
		_say(ONE_PIECE, true)
		return ONE_PIECE
	var saved: Array = ship().shield_balance["presets"][i]
	var why := ""
	if saved.is_empty():
		why = "Slot %d is empty" % (i + 1)
	elif not Balance.valid(saved, n):
		why = "Slot %d was saved for %d sectors; this bubble has %d" % [i + 1, saved.size(), n]
	if why != "":
		_say(why, true)
		return why
	return _store(saved, "Loaded slot %d" % (i + 1))


# --- buttons ---------------------------------------------------------------------------------------

## Every button on screen: {id, rect, label, enabled}. Ids: "minus:K" and "plus:K" for sector K,
## "preset:NAME", "save:I" and "load:I".
func buttons() -> Array:
	var out := []
	var n := sector_count()
	if ship() == null or n < 2:
		return out
	for k in n:
		var r := sector_buttons(k)
		out.append({"id": "minus:%d" % k, "rect": r[0], "label": "-", "enabled": true})
		out.append({"id": "plus:%d" % k, "rect": r[1], "label": "+", "enabled": true})
	var side := side_rect()
	var y := _presets_y(n)
	var x := side.position.x + 10.0
	for preset_name in Balance.PRESETS:
		var ok := not (n < 4 and preset_name in ["Port", "Starboard"])
		out.append({"id": "preset:" + preset_name, "rect": Rect2(Vector2(x, y + 34.0), PRESET_BTN), "label": preset_name, "enabled": ok})
		x += PRESET_BTN.x + 8.0
	for i in Balance.SLOTS:
		var sy := y + 112.0 + i * 40.0
		out.append({"id": "save:%d" % i, "rect": Rect2(Vector2(side.position.x + 100.0, sy), SLOT_BTN), "label": "Save", "enabled": true})
		out.append({"id": "load:%d" % i, "rect": Rect2(Vector2(side.position.x + 100.0 + SLOT_BTN.x + 8.0, sy), SLOT_BTN), "label": "Load", "enabled": true})
	return out


## The button with `id`, or {}.
func button(id: String) -> Dictionary:
	for b in buttons():
		if b["id"] == id:
			return b
	return {}


func button_at(p: Vector2) -> String:
	for b in buttons():
		if b["rect"].has_point(p):
			return b["id"]
	return ""


## Do what button `id` says ("minus:1", "preset:Bow", "save:0" ...). "" or why it was refused.
func press(id: String) -> String:
	var parts := id.split(":")
	if parts.size() != 2:
		return "no such button"
	match parts[0]:
		"plus":
			return adjust(int(parts[1]), 1)
		"minus":
			return adjust(int(parts[1]), -1)
		"preset":
			return apply_preset(parts[1])
		"save":
			return save_slot(int(parts[1]))
		"load":
			return load_slot(int(parts[1]))
	return "no such button"


# --- layout ----------------------------------------------------------------------------------------

func panel_rect() -> Rect2:
	return Rect2(Vector2(MARGIN, MARGIN), size - Vector2(MARGIN, MARGIN) * 2.0)


## Where the silhouette and its bubble are drawn.
func map_rect() -> Rect2:
	var p := panel_rect()
	return Rect2(p.position + Vector2(PAD, TITLE_H), Vector2(p.size.x * MAP_SHARE - PAD, p.size.y - TITLE_H - FOOT_H))


func side_rect() -> Rect2:
	var p := panel_rect()
	var m := map_rect()
	return Rect2(Vector2(m.end.x + PAD, m.position.y), Vector2(p.end.x - PAD - m.end.x - PAD, m.size.y))


## The cells (cell coordinates) the map shows: the bubble's outline with room round it for the buttons.
func map_bounds() -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for q in shape().outline():
		lo = lo.min(q)
		hi = hi.max(q)
	return Rect2(lo - Vector2(4.5, 4.5), hi - lo + Vector2(9.0, 9.0))


## px per cell and the px of cell (0, 0) on this screen.
func map_transform() -> Dictionary:
	var b := map_bounds()
	var m := map_rect()
	var s := minf(m.size.x / b.size.x, m.size.y / b.size.y)
	return {"s": s, "origin": m.position + (m.size - b.size * s) / 2.0 - b.position * s}


## The screen point of cell coordinates `c`.
func to_screen(c: Vector2) -> Vector2:
	var t := map_transform()
	return t["origin"] + c * float(t["s"])


## The screen direction of the middle of sector `k` of `n` (bow up, clockwise).
static func sector_dir(k: int, n: int) -> Vector2:
	return Vector2.from_angle(-PI / 2.0 + TAU * k / n)


## The Rect2s of sector `k`'s [- button, + button]: outside the bubble on the line from the centre through
## the middle of the sector, side by side across that line.
func sector_buttons(k: int) -> Array:
	var n := sector_count()
	var d := sector_dir(k, n)
	var edge := to_screen(shape().boundary_toward(d))
	var at := edge + d * (BTN.y * 1.1)
	var across := d.rotated(PI / 2.0)
	var half := (BTN.x + 4.0) / maxf(absf(across.x), absf(across.y)) / 2.0  # far enough apart that the squares never touch
	var out := []
	for sign in [-1, 1]:
		var c: Vector2 = at + across * half * sign
		out.append(Rect2(c - BTN / 2.0, BTN))
	return out


func _presets_y(n: int) -> float:
	return side_rect().position.y + 104.0 + n * ROW_H + 52.0 + 4.0


# --- input -----------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey):
		return
	_handled()
	if not e.pressed or e.echo:
		return
	if e.keycode == KEY_ESCAPE or e.keycode == KEY_H:
		close()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hover_id = button_at(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var id := button_at(e.position)
		if id != "":
			press(id)
	accept_event()


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


# --- drawing ---------------------------------------------------------------------------------------

func _draw() -> void:
	var s = ship()
	if s == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	var p := panel_rect()
	_panel(p)
	_text("SHIELDS", p.position + Vector2(PAD, 36.0), 26, TEXT)
	_text(message, p.position + Vector2(180.0, 34.0), 16, BAD if message_bad else GOOD)
	var pw := powered()
	var n := sector_count()
	Schematic.draw_map(self, s, pw, map_rect(), map_bounds())
	_draw_bubble(n, layers())
	_draw_side(n)
	_text("H/Esc close   Click + or - on a sector   Presets and slots on the right   Saved with the ship",
		p.position + Vector2(PAD, p.size.y - 16.0), 13, DIM_TEXT)


## The real bubble over the silhouette: each sector as bright and thick as the layers it holds at these
## weights, a dashed line at 0, with the - and + buttons and the sector's name, weight and layers.
func _draw_bubble(n: int, total: int) -> void:
	var sh := shape()
	var w := weights()
	var lines: Array = sh.sector_lines(n)
	var centre := to_screen(sh.centre)
	for k in n:
		var pts := PackedVector2Array()
		for q in lines[k]:
			pts.append(to_screen(q))
		var cap := total * float(w[k])
		var hot := hover_id.ends_with(":%d" % k) and (hover_id.begins_with("plus") or hover_id.begins_with("minus"))
		draw_colored_polygon(PackedVector2Array([centre]) + pts if n > 1 else pts, Color(BUBBLE, 0.04 + 0.025 * minf(cap, 4.0) + (0.1 if hot else 0.0)))
		if cap >= 1.0:
			draw_polyline(pts, Color(BUBBLE, minf(0.3 + 0.15 * cap, 0.95)), 2.0 + 1.2 * minf(cap, 4.0), true)
		else:
			ShipView.dashed(self, pts, Color(BUBBLE, 0.5), 2.5, 14.0, 10.0)
		if n > 1:
			var d := sector_dir(k, n)
			var sector_name := Balance.name_of(n, k)
			var info := "%.1f   %s" % [w[k], _layers_text(cap)]
			var a := to_screen(sh.boundary_toward(d)) + d * (BTN.y * 1.6 + 12.0)  # beyond the buttons
			var top := a.y - 16.0 + d.y * 16.0
			_text_aligned(sector_name, Vector2(a.x, top + 13.0), 15, TEXT, d.x)
			_text_aligned(info, Vector2(a.x, top + 31.0), 13, AMBER if hot else DIM_TEXT, d.x)
			var edge := to_screen(sh.boundary_toward(Vector2.from_angle(-PI / 2.0 + (float(k) - 0.5) * TAU / n)))
			draw_line(centre, edge, Color(BUBBLE, 0.18), 1.0)
	for b in buttons():
		if str(b["id"]).begins_with("plus") or str(b["id"]).begins_with("minus"):
			_button(b)


func _draw_side(n: int) -> void:
	var side := side_rect()
	var box := Rect2(side.position, Vector2(side.size.x, 92.0))
	_panel(box, ROW_BG)
	_text("GENERATORS", box.position + Vector2(10.0, 24.0), 15, AMBER)
	var gens := generators()
	if gens.is_empty():
		_text("No powered shield generator", box.position + Vector2(10.0, 54.0), 20, BAD)
		_text("No shield generator. Build one and wire it to a reactor.", box.position + Vector2(10.0, 78.0), 13, DIM_TEXT)
		return
	_text("%d layers, %d sector%s" % [layers(), n, "" if n == 1 else "s"], box.position + Vector2(10.0, 54.0), 20, TEXT)
	_text(", ".join(PackedStringArray(gens)), box.position + Vector2(10.0, 78.0), 13, DIM_TEXT)
	if n < 2:
		var one := Rect2(side.position + Vector2(0.0, 104.0), Vector2(side.size.x, 70.0))
		_panel(one, ROW_BG)
		draw_multiline_string(ThemeDB.fallback_font, one.position + Vector2(12.0, 30.0), ONE_PIECE, HORIZONTAL_ALIGNMENT_LEFT, one.size.x - 24.0, 18, 3, TEXT)
		return
	var w := weights()
	var rows := Rect2(side.position + Vector2(0.0, 104.0), Vector2(side.size.x, n * ROW_H + 44.0))
	_panel(rows, ROW_BG)
	_text("BALANCE  (weights add up to %d)" % n, rows.position + Vector2(10.0, 24.0), 15, AMBER)
	for k in n:
		var y := rows.position.y + 36.0 + k * ROW_H
		_text(Balance.name_of(n, k), Vector2(rows.position.x + 12.0, y + 16.0), 14, TEXT)
		var bar := Rect2(Vector2(rows.position.x + 150.0, y + 4.0), Vector2(150.0, 14.0))
		draw_rect(bar, Color("#0f141a"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(w[k]) / Balance.MAX_W, bar.size.y)), Color(BUBBLE, 0.8))
		for tick in 5:
			draw_line(bar.position + Vector2(bar.size.x * tick / 4.0, 0.0), bar.position + Vector2(bar.size.x * tick / 4.0, bar.size.y), Color(0, 0, 0, 0.5), 1.0)
		draw_rect(bar, EDGE_DIM, false, 1.0)
		_text("%.1f" % w[k], Vector2(bar.end.x + 12.0, y + 16.0), 14, TEXT)
		_text(_layers_text(layers() * float(w[k])), Vector2(bar.end.x + 56.0, y + 16.0), 14, DIM_TEXT)
	var py := _presets_y(n)
	var presets := Rect2(Vector2(side.position.x, py - 4.0), Vector2(side.size.x, 196.0))
	_panel(presets, ROW_BG)
	_text("PRESETS", Vector2(presets.position.x + 10.0, py + 20.0), 15, AMBER)
	_text("CUSTOM SLOTS", Vector2(presets.position.x + 10.0, py + 100.0), 15, AMBER)
	for i in Balance.SLOTS:
		var saved: Array = ship().shield_balance["presets"][i]
		var sy := py + 112.0 + i * 40.0
		_text("Slot %d" % (i + 1), Vector2(presets.position.x + 10.0, sy + 21.0), 14, TEXT)
		_text(" ".join(PackedStringArray(saved.map(func(x): return "%.1f" % x))) if not saved.is_empty() else "empty", Vector2(presets.position.x + 100.0 + 2.0 * (SLOT_BTN.x + 8.0) + 10.0, sy + 21.0), 13, DIM_TEXT)
	for b in buttons():
		if not (str(b["id"]).begins_with("plus") or str(b["id"]).begins_with("minus")):
			_button(b)


func _button(b: Dictionary) -> void:
	var r: Rect2 = b["rect"]
	var hot: bool = b["id"] == hover_id and b["enabled"]
	draw_rect(r, PANEL_BG if b["enabled"] else Color("#171c23"))
	draw_rect(r, AMBER if hot else (EDGE if b["enabled"] else EDGE_DIM), false, 2.0 if hot else 1.0)
	var size_px := 22 if b["label"].length() == 1 else 14
	var col: Color = TEXT if b["enabled"] else Color(DIM_TEXT, 0.5)
	var wide := ThemeDB.fallback_font.get_string_size(b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	_text(b["label"], r.position + Vector2((r.size.x - wide) / 2.0, r.size.y / 2.0 + size_px * 0.35), size_px, col)


## A chunky panel: a slate fill, a 2 px light border and a 1 px inner highlight.
func _panel(r: Rect2, fill := PANEL_BG) -> void:
	draw_rect(r, fill)
	draw_rect(r, EDGE, false, 2.0)
	draw_rect(r.grow(-3.0), HIGHLIGHT, false, 1.0)


## A figure: whole numbers plain, others with one decimal.
static func _num(v: float) -> String:
	return "%d" % roundi(v) if is_equal_approx(v, roundf(v)) else "%.1f" % v


func _text(text: String, at: Vector2, font_size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


## Text at `at`, left-aligned when `side` is positive (the sector is on the right), right-aligned when
## negative, else centred.
func _text_aligned(text: String, at: Vector2, font_size: int, col: Color, side: float) -> void:
	var wide := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(text, at - Vector2(0.0 if side > 0.35 else (wide if side < -0.35 else wide / 2.0), 0.0), font_size, col)


## "1 layer", "1.5 layers".
static func _layers_text(v: float) -> String:
	return "%s layer%s" % [_num(v), "" if is_equal_approx(v, 1.0) else "s"]
