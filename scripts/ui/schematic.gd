extends Control
## An FTL-style ship panel (about 280 x 200 px): a small top-down map of one arena ship's grid with
## its rooms, walls, doors and systems coloured by state, breaches in red, and the
## shield pips with a ring that shows which sector of the bubble is open. Bow is up. Placeholder shapes.
## bind() it to an arena ship; it redraws every frame. Drawing only.
## The player's panel can show the enemy's intent (`intent`, intent.gd): a pulsing red reticle on the part the pilot
## aims at, and under the panel "Targeting: Weapons" and a row per heavy enemy weapon about to fire.
## The enemy's panel shows its crew as dots (`reveal`) while a crew member of yours with reveal_enemy is up (traits.gd).

const Visuals = preload("res://scripts/view/visuals.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Stats = preload("res://scripts/sim/stats.gd")
const Intent = preload("res://scripts/combat/intent.gd")
const Skulls = preload("res://scripts/ui/skulls.gd")

const PANEL := Vector2(280.0, 200.0)
const MAP := Rect2(8.0, 26.0, 264.0, 132.0)
const BG := Color(0.04, 0.07, 0.11, 0.82)
const EDGE := Color("#3b5a78")
const ROOM_TINTS: Array[Color] = [Color("#22404f"), Color("#27384f")]
const WALL_DAMAGE := Color("#ff9a3c")
const BREACH := Color("#ff2a2a")
const LOST := Color("#c0271f")  ## the tint of a lost room (jobs.gd, lost_rooms)
const TEXT := Color("#cfe6ff")
const STATE_COLORS := {
	"ok": Color("#4fd08a"), "damaged": Color("#f1c40f"), "disabled": Color("#e0453a"),
	"overheated": Color("#ff8a1f"), "malfunction": Color("#b07cff"), "unpowered": Color("#5d6e86"),
}
const PIP := Color("#5fd4ff")
const GOLD := Color("#ffd24a")
const ION := Color("#a07bff")
const THREAT := Color("#ff3a3a")  ## the intent reticle and its rows
const ROW_H := 16.0  ## px per line of the intent strip under the panel
const SKULL_K := 0.6  ## the size of the threat skulls in the title bar
const CREW_DOT := Color("#e9f6ff")  ## a revealed crew member; the down ones are CREW_DOWN
const CREW_DOWN := Color("#ff5a4a")
const FLASH_FOR := 0.7  ## seconds a clicked room is lit

var arena
var index := 0
var title := ""
var intent: Dictionary = {}  ## Intent.of(...), set each frame on the player's panel; {} draws nothing
var threat := 0  ## the enemy's panel: its threat in skulls (1-5), drawn small at the right of the title bar; 0 draws none
var flash_cells: Array = []  ## the cells of the room just clicked (flash_room), lit while flash_left > 0
var flash_left := 0.0
var reveal := false  ## draw the ship's crew on the map (set each frame on the enemy's panel from TraitSet.reveals_enemy)


func _init() -> void:
	custom_minimum_size = PANEL
	size = PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(p_arena, idx: int, p_title: String) -> void:
	arena = p_arena
	index = idx
	title = p_title


func _process(dt: float) -> void:
	flash_left = maxf(flash_left - dt / maxf(Engine.time_scale, 0.01), 0.0)  # real time, so the slow-down does not stretch it
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


## The cells a ship's map is fitted to by default: what is built (tiles, parts, the outside halves of mounts) with two cells
## round it, as the hull of a generated ship is. Not the whole hull: a starter's round frame (59 cells across) would shrink
## the ship to a speck. The hull's own box when nothing is built.
static func fit_box(ship) -> Rect2:
	var grid = ship.grid
	var cells: Array = grid.tiles.keys()
	for uid in ship.components.instances:
		cells.append_array(ship.components.instances[uid]["cells"])
		cells.append_array(ship.components.instances[uid].get("out_cells", []))
	var pad := Vector2(2.0, 2.0)
	if cells.is_empty():
		cells = grid.hull.keys()
		pad = Vector2.ZERO
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for cell in cells:
		lo = Vector2(minf(lo.x, cell.x), minf(lo.y, cell.y))
		hi = Vector2(maxf(hi.x, cell.x + 1.0), maxf(hi.y, cell.y + 1.0))
	return Rect2(lo - pad, hi - lo + pad * 2.0)


## Where draw_map puts `ship`'s cells in `map` (px): {origin: the px of cell (0, 0), s: px per cell}.
static func map_layout(ship, map: Rect2, bounds := Rect2()) -> Dictionary:
	var box := fit_box(ship) if bounds.size == Vector2.ZERO else bounds
	var lo := box.position
	var hi := box.end
	var s := minf(map.size.x / (hi.x - lo.x), map.size.y / (hi.y - lo.y))
	return {"origin": map.position + (map.size - (hi - lo) * s) / 2.0 - lo * s, "s": s}


## The point of the ship's grid (cell units) under `p` (this panel's px), or null when `p` is off the map or on no built cell.
static func cell_under(ship, p: Vector2, map := MAP) -> Variant:
	if ship.grid.hull.is_empty() or not map.has_point(p):
		return null
	var lay := map_layout(ship, map)
	var at: Vector2 = (p - lay["origin"]) / float(lay["s"])
	return at if ship.grid.tiles.has(Vector2i(floori(at.x), floori(at.y))) else null


## Flash the cells `cells` for a moment (the room a middle-click order went to).
func flash_room(cells: Array) -> void:
	flash_cells = cells
	flash_left = FLASH_FOR


## Draw `ship`'s map on the canvas `cv`: rooms, walls, doors, breaches and systems coloured by state
## (`powered`: uid -> bool), bow up, fitted into `map` (px). The cells of `bounds` (cell coordinates; the
## built cells' box, fit_box, when empty) are scaled to fit. Returns {origin: the px of cell (0, 0), s: px per cell}.
static func draw_map(cv: CanvasItem, ship, powered: Dictionary, map: Rect2, bounds := Rect2()) -> Dictionary:
	var grid = ship.grid
	if grid.hull.is_empty():
		return {}
	var lay := map_layout(ship, map, bounds)
	var s: float = lay["s"]
	var origin: Vector2 = lay["origin"]
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
				if ship.lost_rooms.has(room):
					col = col.lerp(LOST, 0.45)  # a lost room (a fight, jobs.gd): the crew have given it up
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
	for id in ship.lost_rooms:  # the LOST marker on each room given up
		if id >= atmo.rooms.size() or atmo.rooms[id]["cells"].is_empty():
			continue
		var cells: Array = atmo.rooms[id]["cells"]
		var sum := Vector2.ZERO
		for c in cells:
			sum += Vector2(c) + Vector2(0.5, 0.5)
		var at: Vector2 = origin + sum / float(cells.size()) * s + Vector2(-13.0, 4.0)
		cv.draw_rect(Rect2(at + Vector2(-3.0, -11.0), Vector2(32.0, 14.0)), Color(0.1, 0.0, 0.0, 0.8))
		_label(cv, "LOST", at, 11, Color("#ff7a6a"))
	return {"origin": origin, "s": s}


func _draw() -> void:
	if arena == null:
		return
	var co = arena.ships[index]
	var grid = co.ship.grid
	draw_rect(Rect2(Vector2.ZERO, PANEL), BG)
	draw_rect(Rect2(Vector2.ZERO, PANEL), EDGE, false, 2.0)
	draw_rect(Rect2(2, 2, PANEL.x - 4, 20), Color(0.12, 0.2, 0.3, 0.7))
	var skulls_w := Skulls.width(SKULL_K) + 8.0 if threat > 0 else 0.0
	draw_string(ThemeDB.fallback_font, Vector2(10, 17), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 20.0 - skulls_w, 13, TEXT)
	if threat > 0:
		Skulls.draw(self, Vector2(PANEL.x - 8.0 - Skulls.width(SKULL_K), 12.0), threat, Skulls.color(threat), SKULL_K)
	if grid.hull.is_empty():
		return
	var map := draw_map(self, co.ship, co.powered, MAP)
	if flash_left > 0.0 and not map.is_empty():
		for c in flash_cells:
			draw_rect(Rect2(map["origin"] + Vector2(c) * float(map["s"]), Vector2.ONE * float(map["s"])), Color(GOLD, 0.85 * flash_left / FLASH_FOR))
	if reveal:
		_draw_crew(co.ship, map)
	# The shield pips. (No hull bar: the damage is on the blocks of the map.)
	_draw_shield(co, Vector2(10, 180))
	_draw_intent(co, map)
	if co.wrecked:
		draw_rect(Rect2(Vector2.ZERO, PANEL), Color(0.25, 0.0, 0.0, 0.45))
		_text("WRECKED", Vector2(70, 100), 26, Color("#ff5a4a"))


## Where the crew of `ship` stand on its map (`map`: what draw_map returned): [{at: px, down: bool}], one per crew member.
static func crew_marks(ship, map: Dictionary) -> Array:
	var out := []
	if map.is_empty():
		return out
	for m in ship.crew:
		out.append({"at": map["origin"] + m.pos * float(map["s"]), "down": m.is_down()})
	return out


## A dot for each crew member (a red one with a cross for the down).
func _draw_crew(ship, map: Dictionary) -> void:
	var r := clampf(float(map.get("s", 8.0)) * 0.45, 2.5, 6.0)
	for mark in crew_marks(ship, map):
		var at: Vector2 = mark["at"]
		draw_circle(at, r + 1.5, Color(0, 0, 0, 0.75))
		draw_circle(at, r, CREW_DOWN if mark["down"] else CREW_DOT)
		if mark["down"]:
			draw_line(at + Vector2(-r, -r) * 0.7, at + Vector2(r, r) * 0.7, Color(0.2, 0, 0), 1.5)
			draw_line(at + Vector2(-r, r) * 0.7, at + Vector2(r, -r) * 0.7, Color(0.2, 0, 0), 1.5)


## Where the intent marks go on `ship`'s map (`map`: what draw_map returned): {ring: the reticle's centre (px), radius,
## line: "Targeting: Weapons" ("" with no target), rows: [{text, hot}] (the heavy weapons: "Artemis in 1.2 s", hot under
## red_under_s; at most max_rows, then "+N more")}. `ring` is absent with no target. Empty for an empty `intent`.
static func intent_layout(ship, p_intent: Dictionary, map: Dictionary) -> Dictionary:
	var out := {"line": "", "rows": []}
	var cfg := Intent.config()
	var uid := int(p_intent.get("target_uid", -1))
	var inst = ship.components.instances.get(uid)
	if uid >= 0 and inst != null and not map.is_empty():
		var lo: Vector2i = inst["cells"][0]
		var hi := lo
		for c in inst["cells"]:
			lo = lo.min(c)
			hi = hi.max(c)
		var r := Rect2(map["origin"] + Vector2(lo) * map["s"], Vector2(hi - lo + Vector2i.ONE) * map["s"])
		out["ring"] = r.get_center()
		out["radius"] = maxf(r.size.x, r.size.y) * 0.5 + 3.0
		out["line"] = "Targeting: " + Intent.family_label(str(p_intent.get("target_family", "")))
	var heavy: Array = p_intent.get("heavy", [])
	var cap := int(cfg.get("max_rows", 4))
	for i in mini(heavy.size(), cap):
		var h: Dictionary = heavy[i]
		var eta := float(h["eta"])
		var weapon := Intent.short_name(str(h["name"]))
		out["rows"].append({"text": "%s ready" % weapon if eta < 0.05 else "%s in %.1f s" % [weapon, eta], "hot": eta < float(cfg.get("red_under_s", 0.5))})
	if heavy.size() > cap:
		out["rows"].append({"text": "+%d more" % (heavy.size() - cap), "hot": false})
	return out


## The reticle (a ring and four ticks, pulsing) on the targeted part, and under the panel the strip with the
## "Targeting" line and a row for each heavy weapon about to fire.
func _draw_intent(co, map: Dictionary) -> void:
	if intent.is_empty():
		return
	var lay := intent_layout(co.ship, intent, map)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	if lay.has("ring"):
		var at: Vector2 = lay["ring"]
		var rad: float = lay["radius"] + 1.5 * pulse
		draw_arc(at, rad, 0.0, TAU, 24, Color(THREAT, 0.6 + 0.4 * pulse), 2.0, true)
		for d in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
			draw_line(at + d * (rad - 3.0), at + d * (rad + 4.0), Color(THREAT, 0.6 + 0.4 * pulse), 2.0)
	var lines: Array = ([lay["line"]] if lay["line"] != "" else []) + lay["rows"]
	if lines.is_empty():
		return
	var box := Rect2(0.0, PANEL.y + 4.0, PANEL.x, 8.0 + ROW_H * lines.size())
	draw_rect(box, BG)
	draw_rect(box, Color(THREAT, 0.55), false, 2.0)
	var y := box.position.y + 6.0 + 11.0
	if lay["line"] != "":
		_text(lay["line"], Vector2(10.0, y), 13, THREAT.lerp(TEXT, 0.35))
		y += ROW_H
	for row in lay["rows"]:
		var hot: bool = row["hot"]
		var col := Color(THREAT, 0.7 + 0.3 * pulse) if hot else TEXT
		draw_rect(Rect2(10.0, y - 8.0, 7.0, 7.0), col, hot)  # a flat marker, solid when hot
		_text(row["text"], Vector2(24.0, y), 13, col)
		y += ROW_H


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
