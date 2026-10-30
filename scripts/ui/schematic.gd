extends Control
## An FTL-style ship panel (about 280 x 200 px): a small top-down map of one arena ship's grid with
## its rooms, walls, doors and systems coloured by state, breaches in red, a hull integrity bar and
## shield pips with a ring that shows which sector of the bubble is open. Bow is up. Placeholder shapes.
## bind() it to an arena ship; it redraws every frame. Drawing only.

const Visuals = preload("res://scripts/view/visuals.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Stats = preload("res://scripts/sim/stats.gd")

const PANEL := Vector2(280.0, 200.0)
const MAP := Rect2(8.0, 26.0, 264.0, 132.0)
const BG := Color(0.04, 0.07, 0.11, 0.82)
const EDGE := Color("#3b5a78")
const ROOM_TINTS: Array[Color] = [Color("#22404f"), Color("#27384f")]
const WALL_DAMAGE := Color("#ff9a3c")
const BREACH := Color("#ff2a2a")
const TEXT := Color("#cfe6ff")
const STATE_COLORS := {
	"ok": Color("#4fd08a"), "damaged": Color("#f1c40f"), "disabled": Color("#e0453a"),
	"overheated": Color("#ff8a1f"), "malfunction": Color("#b07cff"), "unpowered": Color("#5d6e86"),
}
const PIP := Color("#5fd4ff")
const GOLD := Color("#ffd24a")
const ION := Color("#a07bff")

var arena
var index := 0
var title := ""


func _init() -> void:
	custom_minimum_size = PANEL
	size = PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(p_arena, idx: int, p_title: String) -> void:
	arena = p_arena
	index = idx
	title = p_title


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


## The state a system shows: disabled / overheated / malfunction (out of action), damaged (hurt but
## working), unpowered (a consumer with no power), else ok.
static func component_state(def: Dictionary, inst: Dictionary, powered: bool) -> String:
	var status := str(inst.get("status", "ok"))
	if status != "ok":
		return status
	if int(inst.get("hp", Stats.max_hp(def))) < Stats.max_hp(def):
		return "damaged"
	if not powered and int(def.get("power", 0)) < 0:
		return "unpowered"
	return "ok"


## Draw `ship`'s map on the canvas `cv`: rooms, walls, doors, breaches and systems coloured by state
## (`powered`: uid -> bool), bow up, fitted into `map` (px). The cells of `bounds` (cell coordinates; the
## hull's bounding box when empty) are scaled to fit. Returns {origin: the px of cell (0, 0), s: px per cell}.
static func draw_map(cv: CanvasItem, ship, powered: Dictionary, map: Rect2, bounds := Rect2()) -> Dictionary:
	var grid = ship.grid
	if grid.hull.is_empty():
		return {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for cell in grid.hull:
		lo = Vector2(minf(lo.x, cell.x), minf(lo.y, cell.y))
		hi = Vector2(maxf(hi.x, cell.x + 1.0), maxf(hi.y, cell.y + 1.0))
	if bounds.size != Vector2.ZERO:
		lo = bounds.position
		hi = bounds.end
	var s := minf(map.size.x / (hi.x - lo.x), map.size.y / (hi.y - lo.y))
	var origin := map.position + (map.size - (hi - lo) * s) / 2.0 - lo * s
	var atmo = ship.atmosphere
	for c in grid.tiles:
		var id: String = grid.tiles[c]
		var def: Dictionary = grid.defs.get_def(id)
		var r := Rect2(origin + Vector2(c) * s, Vector2(s, s) + Vector2(0.4, 0.4))
		if def.get("solid", false):
			var lost: float = 1.0 - grid.hp_of(c) / maxf(grid.max_hp_of(c), 0.01)
			cv.draw_rect(r, grid.defs.color(id).darkened(0.25).lerp(WALL_DAMAGE, lost * 0.8))
		elif def.get("door", false):
			var open: bool = grid.is_door_open(c)
			cv.draw_rect(r, ROOM_TINTS[0])
			cv.draw_rect(r.grow(-s * 0.2) if open else r.grow(-s * 0.05), grid.defs.color(id), not open)
		else:
			var room: int = atmo.room_of.get(c, -1)
			var col := ROOM_TINTS[room % 2] if room >= 0 else ROOM_TINTS[0]
			if room >= 0:
				col = col.lerp(Color("#7a2020"), (1.0 - atmo.pressure_of(room)) * 0.7)  # thin air reddens a room
			cv.draw_rect(r, col)
	var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.008)
	for c in grid.breached:
		var r := Rect2(origin + Vector2(c) * s, Vector2(s, s) + Vector2(0.4, 0.4))
		cv.draw_rect(r, Color(BREACH, pulse))
		if s >= 6.0:
			cv.draw_line(r.position, r.end, Color(0.2, 0, 0), 1.0)
			cv.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), Color(0.2, 0, 0), 1.0)
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		var def: Dictionary = ship.components.def(inst["id"])
		var clo: Vector2i = inst["cells"][0]
		var chi: Vector2i = clo
		for c in inst["cells"]:
			clo = clo.min(c)
			chi = chi.max(c)
		var r := Rect2(origin + Vector2(clo) * s, Vector2(chi - clo + Vector2i.ONE) * s).grow(-0.6)
		var state := component_state(def, inst, powered.get(uid, false))
		var col: Color = STATE_COLORS[state]
		cv.draw_rect(r, col.darkened(0.45) if state in ["ok", "damaged"] else col.darkened(0.2))
		cv.draw_rect(r, col, false, 1.5)
		if state in ["disabled", "overheated", "malfunction"] and r.size.x >= 8.0:
			cv.draw_line(r.position + Vector2(2, 2), r.end - Vector2(2, 2), col, 1.5)
		if r.size.y >= 12.0 and r.size.x >= 18.0:
			_label(cv, Visuals.label_of(def), r.get_center() + Vector2(-6, 4), 10, Color(1, 1, 1, 0.9))
	return {"origin": origin, "s": s}


func _draw() -> void:
	if arena == null:
		return
	var co = arena.ships[index]
	var grid = co.ship.grid
	draw_rect(Rect2(Vector2.ZERO, PANEL), BG)
	draw_rect(Rect2(Vector2.ZERO, PANEL), EDGE, false, 2.0)
	draw_rect(Rect2(2, 2, PANEL.x - 4, 20), Color(0.12, 0.2, 0.3, 0.7))
	_text(title.to_upper(), Vector2(10, 17), 13, TEXT)
	if grid.hull.is_empty():
		return
	draw_map(self, co.ship, co.powered, MAP)
	# Hull integrity bar and the shield pips.
	var frac := clampf(co.hull / maxf(co.hull_max, 0.01), 0.0, 1.0)
	_text("HULL", Vector2(10, 172), 11, TEXT)
	var bar := Rect2(44, 163, 150, 10)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color("#e0453a").lerp(Color("#4fd08a"), frac))
	draw_rect(bar, EDGE, false, 1.0)
	_text("%d/%d" % [ceili(co.hull), ceili(co.hull_max)], Vector2(200, 172), 11, TEXT)
	_draw_shield(co, Vector2(10, 180))
	if co.wrecked:
		draw_rect(Rect2(Vector2.ZERO, PANEL), Color(0.25, 0.0, 0.0, 0.45))
		_text("WRECKED", Vector2(70, 100), 26, Color("#ff5a4a"))


## Shield pips (a filled one per layer up, the overcharge layer in gold; with several sectors the layers up
## over all of them), "OPEN" while a sector is open, "ION" when locked, and a ring split into the bubble's
## sectors: each as bright as it is full, dark while open.
func _draw_shield(co, at: Vector2) -> void:
	_text("SHLD", at + Vector2(0, 12), 11, TEXT)
	if co.layers_cap <= 0:
		_text("none", at + Vector2(34, 12), 11, Color(TEXT, 0.5))
		return
	var ion: bool = co.ion_lock > 0.0
	var open := Shields.open_sectors(co, arena.tick)
	var any_open := open.has(true)
	var x := 44.0
	if co.sectors > 1:
		var line := "%d / %d" % [co.layers, co.layers_cap * co.sectors]
		_text(line, at + Vector2(x, 12), 12, ION if ion else PIP)
		x += ThemeDB.fallback_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 8.0
	else:
		for i in co.layers_cap:
			var c := at + Vector2(44.0 + i * 15.0, 7.0)
			var extra: bool = co.overcharge_left > 0.0 and i == co.layers_cap - 1
			var col := GOLD if extra else (ION if ion else PIP)
			if i < co.layers and not ion:
				draw_circle(c, 5.5, col if not any_open else col.darkened(0.5))
			else:
				draw_arc(c, 5.0, 0.0, TAU, 14, Color(col, 0.55), 1.5)
		x += minf(co.layers_cap, 6) * 15.0 + 4.0
	if ion:
		_text("ION", at + Vector2(x, 12), 12, ION)
	elif any_open:
		_text("OPEN", at + Vector2(x, 12), 12, Color("#ffb347"))
	var ring := Vector2(PANEL.x - 20.0, at.y + 7.0)
	var n := open.size()
	for k in n:
		var a0 := -PI / 2.0 + (float(k) - 0.5) * TAU / n + (0.28 if n > 1 else 0.0)
		var a1 := -PI / 2.0 + (float(k) + 0.5) * TAU / n - (0.28 if n > 1 else 0.0)
		if n == 1:
			a0 = -PI / 2.0
			a1 = a0 + TAU
		var full := clampf(float(co.sector_layers[k]) / maxf(Shields.cap_of(co, k), 1.0), 0.0, 1.0)
		draw_arc(ring, 8.0, a0, a1, 10, Color("#243242") if open[k] else Color(ION if ion else PIP, 0.25 + 0.7 * full), 3.5, true)


func _text(text: String, at: Vector2, size: int, col: Color) -> void:
	_label(self, text, at, size, col)


static func _label(cv: CanvasItem, text: String, at: Vector2, size: int, col: Color) -> void:
	cv.draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
