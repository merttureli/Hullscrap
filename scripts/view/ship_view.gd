extends Node2D
## One ship drawn at its place in the arena: the node sits on the ship's flight body (position and
## heading), so everything below is drawn in the ship's own frame, in pixels from its pivot. Tiles
## (materials by colour, shaped cells as slopes and curves), the exterior hull skin over the cells
## that face space (a ship in an arena only), breached cells as dark holes, damage, doors, systems
## through visuals.gd, crew, and the shield bubble. Drawing only; bind() it to an arena ship and it
## follows it. Reusable: with no arena it draws a plain Ship at the node's own transform (pivot = the
## hull's centre), with no skin.

const Visuals = preload("res://scripts/view/visuals.gd")
const TileArt = preload("res://scripts/view/tile_art.gd")
const GlowLayer = preload("res://scripts/view/glow_layer.gd")
const PersonDrawer = preload("res://scripts/crew/person_drawer.gd")
const Art = preload("res://scripts/view/art.gd")
const Shields = preload("res://scripts/combat/shields.gd")

const CELL := 32.0
const HOLE := Color("#06080c")
const HOLE_RIM := Color("#9a5428")
const BUBBLE := Color("#5fd4ff")
const ION := Color("#a07bff")
const OVERCHARGE := Color("#ffd24a")
const WRECK_TINT := Color(0.5, 0.48, 0.5)
const LOOKS := {
	"Soldier": {"suit": "#33c6d6", "hair": "#2b2320", "tool": "#d7dce4"},
	"Ada": {"suit": "#e8913a", "hair": "#c2331f", "tool": "#f1d36b"},
}
const OTHER_LOOK := {"suit": "#b8382c", "hair": "#1b1b1b", "tool": "#d7dce4"}
const BUBBLE_STEPS := 48  ## points round a whole bubble

var arena  ## arena.gd, or null
var index := 0  ## the ship's index in the arena
var ship  ## ship.gd
var pivot := Vector2.ZERO  ## the ship's centre in cell coordinates: the node's origin
var _clock := 0.0
var _glow: Node2D  # additive layer for the glow art of the parts
var _weapons := {}  # uid -> {left, peak, shot}: a weapon's cooldown as last seen, the longest it has been, when it last fired (_clock)
var _crew_anim := {}  # CrewMember -> PersonDrawer state, for drawing only
var _doors := {}  # a door piece's first cell -> TileArt.door_progress() state, for the opening animation
var _glow_quads: Array = []  # the glow art of this frame, handed to _glow at the end of _draw
var _skin := {}  # TileArt.skin_plan() of the grid, remade when _skin_sig changes
var _skin_sig := []


## Follow ship `idx` of `p_arena`.
func bind(p_arena, idx: int) -> void:
	arena = p_arena
	index = idx
	ship = arena.ships[idx].ship
	pivot = arena.ships[idx].pivot
	_follow()


## Draw a loose ship (no arena) with its hull centre at the node's origin.
func show_ship(p_ship) -> void:
	arena = null
	ship = p_ship
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in ship.grid.hull:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x + 1.0), maxf(hi.y, c.y + 1.0))
	pivot = (lo + hi) / 2.0 if not ship.grid.hull.is_empty() else Vector2(ship.grid.size) / 2.0


func _follow() -> void:
	if arena != null:
		var co = arena.ships[index]
		position = co.flight.pos
		rotation = co.flight.angle
		modulate = WRECK_TINT if co.wrecked else Color.WHITE


func _ready() -> void:
	_glow = GlowLayer.new()
	add_child(_glow)


func _process(dt: float) -> void:
	_clock += dt
	_follow()
	if ship != null:
		for m in ship.crew:
			var a: Dictionary = _crew_anim.get(m, PersonDrawer.new_state(m))
			PersonDrawer.animate(a, m, dt, PersonDrawer.job_aim(m))
			_crew_anim[m] = a
	queue_redraw()


## The pixel position of cell coordinates `c` relative to the pivot.
func px(c: Vector2) -> Vector2:
	return (c - pivot) * CELL


func _draw() -> void:
	if ship == null:
		return
	_glow_quads = []
	var grid = ship.grid
	for c in grid.tiles:
		_draw_tile(grid, c, grid.tiles[c])
	if arena != null:
		_draw_skin(grid)
	for c in grid.breached:
		_draw_hole(c)
	for c in grid.hp:
		_draw_damage(grid, c)
	var powered: Dictionary = ship.power_state.get("powered", {})
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		var lo: Vector2i = inst["cells"][0]
		var hi: Vector2i = lo
		for c in inst["cells"]:
			lo = lo.min(c)
			hi = hi.max(c)
		var r := Rect2(px(Vector2(lo)), Vector2(hi - lo + Vector2i.ONE) * CELL)
		var opts := _weapon_opts(uid)
		opts.merge({"powered": powered.get(uid, false), "time": _clock, "glow_out": _glow_quads})
		Visuals.draw_component(self, r, ship.components.def(inst["id"]), inst, CELL, opts)
	draw_fire(self, ship.fires, px(Vector2.ZERO), CELL, _clock, _glow_quads)
	for m in ship.crew:
		var a: Dictionary = _crew_anim.get(m, PersonDrawer.new_state(m))
		var look: Dictionary = m.look if not m.look.is_empty() else LOOKS.get(m.name, OTHER_LOOK)
		var pose := {"species": Art.crew_rig(m.rig()), "move": a["angle"], "aim": a["aim"], "phase": a["phase"], "moving": a["moving"],
			"item": PersonDrawer.item_for(m, ship.clock, arena != null), "down": m.is_down(), "work": PersonDrawer.is_working(m, ship.clock), "t": _clock}
		PersonDrawer.draw(self, px(m.pos), pose, look, CELL)
		draw_health(self, px(m.pos), m.hp / m.max_hp, m.is_down(), CELL)
	if _glow != null:
		_glow.show_quads(_glow_quads)
	if arena != null:
		_draw_bubble(arena.ships[index])


## What the art of weapon `uid` needs from the arena: {charge (0..1, how far the cooldown has run),
## fired_ago (seconds since the cooldown last restarted)}. A cooldown that jumps up means a shot was
## fired (the arena is only read, through cooldown_left); the longest cooldown seen since then is the
## full bar. Empty for a part that is not a weapon, or with no arena.
func _weapon_opts(uid: int) -> Dictionary:
	if arena == null or not arena.ships[index].mounts.has(uid):
		return {}
	var left: float = arena.cooldown_left(index, uid)
	var w: Dictionary = _weapons.get(uid, {"left": left, "peak": left, "shot": -1.0e9})
	if left > float(w["left"]) + 0.001:
		w["shot"] = _clock
		w["peak"] = left
	w["left"] = left
	_weapons[uid] = w
	return {"charge": 1.0 if left <= 0.0 or w["peak"] <= 0.0 else 1.0 - left / w["peak"], "fired_ago": _clock - w["shot"]}


func _draw_tile(grid, c: Vector2i, id: String) -> void:
	var r := Rect2(px(Vector2(c)), Vector2(CELL, CELL))
	var col: Color = grid.defs.color(id)
	var def: Dictionary = grid.defs.get_def(id)
	if def.get("door", false):
		var piece: Array[Vector2i] = grid.door_piece(c)
		if piece[0] == c:
			_draw_door(grid, piece, col, grid.is_door_open(c))
	elif def.get("solid", false):
		TileArt.solid_cell(self, r, grid, c, id, col)
	elif not TileArt.floor_tile(self, r, c):
		draw_rect(r, col)
		draw_rect(r.grow(-1), col.lightened(0.05), false, 1.0)


## The exterior skin over the walls that face space. The plan is remade when walls come or go (a breach, a repair).
func _draw_skin(grid) -> void:
	var sig := [grid.tiles.size(), grid.shapes.size(), grid.breached.size(), ship.components.instances.size()]
	if sig != _skin_sig:
		_skin = TileArt.skin_plan(grid, _part_lines())
		_skin_sig = sig
	TileArt.draw_skin(self, _skin, px(Vector2.ZERO), CELL, _clock, _glow_quads)


## Line -> cells of the ship's parts, so a ship full of neon parts wears the neon skin even on standard plates.
func _part_lines() -> Dictionary:
	var out := {}
	for uid in ship.components.instances:
		var inst: Dictionary = ship.components.instances[uid]
		var line := str(ship.components.def(inst["id"]).get("line", ""))
		if line != "":
			out[line] = int(out.get(line, 0)) + inst["cells"].size()
	return out


## A door piece: floor under it, two leaves that meet in the middle when closed and slide back into
## the walls at both ends when open (an open door lets shots through).
func _draw_door(grid, piece: Array[Vector2i], col: Color, open: bool) -> void:
	var floor_col: Color = grid.defs.color("floor") if grid.defs.has("floor") else col.darkened(0.5)
	var rects := []
	for p in piece:
		var cell_rect := Rect2(px(Vector2(p)), Vector2(CELL, CELL))
		rects.append(cell_rect)
		if not TileArt.floor_tile(self, cell_rect, p):
			draw_rect(cell_rect, floor_col)
	var horizontal: bool = piece[1].x != piece[0].x if piece.size() > 1 else true
	if TileArt.door_piece(self, rects, horizontal, TileArt.door_fraction(_doors, piece[0], open, _clock), _glow_quads):
		return
	var along := Vector2.RIGHT if horizontal else Vector2.DOWN
	var across := Vector2(along.y, along.x)
	var base := px(Vector2(piece[0]))
	var n := float(piece.size())
	var leaves := [[0.0, n * 0.25], [n * 0.75, n]] if open else [[0.0, n * 0.5], [n * 0.5, n]]
	for l in leaves:
		draw_rect(Rect2(base + along * (l[0] * CELL) + across * (CELL * 0.4), along * ((l[1] - l[0]) * CELL) + across * (CELL * 0.2)), col)
	if not open:
		draw_rect(Rect2(base + along * (n * 0.5 * CELL - 1.0) + across * (CELL * 0.4), along * 2.0 + across * (CELL * 0.2)), col.darkened(0.55))


## A shot-out cell: a dark ragged hole into space with a scorched rim.
func _draw_hole(c: Vector2i) -> void:
	var o := px(Vector2(c))
	if TileArt.breach(self, Rect2(o, Vector2(CELL, CELL)), c):
		return
	var h := hash(c)
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0
		var r := CELL * (0.42 + 0.1 * float((h >> (i * 2)) & 3) / 3.0)
		pts.append(o + Vector2(CELL, CELL) / 2.0 + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, HOLE)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, HOLE_RIM, 2.0)


## A damaged wall or door darkens and cracks with the hp it has lost.
func _draw_damage(grid, c: Vector2i) -> void:
	if not grid.tiles.has(c):
		return
	var lost: float = 1.0 - grid.hp_of(c) / maxf(grid.max_hp_of(c), 0.01)
	if lost <= 0.0:
		return
	var o := px(Vector2(c))
	var shade := Color(0.05, 0.02, 0.0, 0.55 * lost)
	if grid.shapes.has(c):  # only the solid part of a slope or a curve darkens
		var pts := PackedVector2Array()
		for p in grid.polygon_at(c):
			pts.append(o + p * CELL)
		draw_colored_polygon(pts, shade)
	else:
		draw_rect(Rect2(o, Vector2(CELL, CELL)), shade)
	draw_line(o + Vector2(4, 6), o + Vector2(CELL * 0.55, CELL * 0.5), Color(0, 0, 0, 0.8), 1.5)
	if lost > 0.4:
		draw_line(o + Vector2(CELL * 0.55, CELL * 0.5), o + Vector2(CELL - 5, CELL - 8), Color(0, 0, 0, 0.8), 1.5)


# --- fire and health (placeholder art: swap these two helpers for real art) -----------------------

## Fires as flickering blobs: a red base, an orange body and a yellow core per burning cell, bigger
## with the intensity. `fires`: cell -> intensity (0..1); `origin`: where cell (0, 0) starts, in the
## canvas' pixels; `t`: seconds, for the flicker. Static, so the interior view uses it too.
static func draw_fire(canvas: CanvasItem, fires: Dictionary, origin: Vector2, cell_px: float, t: float, glow_out = null) -> void:
	for c in fires:
		var i: float = clampf(fires[c], 0.0, 1.0)
		if TileArt.fire_cell(canvas, Rect2(origin + Vector2(c) * cell_px, Vector2(cell_px, cell_px)), i, t, c, glow_out):
			continue
		var h := hash(c)
		var phase := float(h & 255) / 40.0
		var flick := 0.88 + 0.12 * sin(t * 11.0 + phase) + 0.05 * sin(t * 23.0 + phase * 2.0)
		var mid := origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell_px
		var r := cell_px * (0.35 + 0.5 * i) * flick
		canvas.draw_circle(mid, r * 1.5, Color(1.0, 0.25, 0.05, 0.14 + 0.1 * i))
		canvas.draw_circle(mid + Vector2(sin(t * 7.0 + phase), 0.0) * cell_px * 0.06, r, Color(0.95, 0.2, 0.06, 0.55 + 0.3 * i))
		canvas.draw_circle(mid + Vector2(0.0, -0.08) * cell_px, r * 0.68, Color(1.0, 0.55, 0.1, 0.75))
		canvas.draw_circle(mid + Vector2(0.0, -0.14) * cell_px, r * 0.36 * flick, Color(1.0, 0.9, 0.4, 0.9))


## A small health bar over the head of a person at `centre` (pixels), only when hurt or down.
static func draw_health(canvas: CanvasItem, centre: Vector2, frac: float, down: bool, cell_px: float) -> void:
	if frac >= 1.0 and not down:
		return
	var w := cell_px * 1.8
	var r := Rect2(centre + Vector2(-w / 2.0, -cell_px * 1.9), Vector2(w, cell_px * 0.22))
	canvas.draw_rect(r.grow(1.5), Color(0, 0, 0, 0.7))
	canvas.draw_rect(r, Color("#5a1d1d"))
	canvas.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), Color("#7bd88f") if frac > 0.4 else Color("#ff5a4a"))
	if down:  # a red cross over them
		var k := cell_px * 0.7
		canvas.draw_line(centre + Vector2(-k, -k), centre + Vector2(k, k), Color(1, 0.2, 0.2, 0.8), 3.0)
		canvas.draw_line(centre + Vector2(-k, k), centre + Vector2(k, -k), Color(1, 0.2, 0.2, 0.8), 3.0)


# --- shield bubble ----------------------------------------------------------------------------

## The point of the bubble ellipse (semi-axes `ax` px) in direction `phi`, clockwise from the bow.
static func bubble_point(ax: Vector2, phi: float) -> Vector2:
	var d := Vector2(sin(phi), -cos(phi))
	return d / sqrt(pow(d.x / ax.x, 2.0) + pow(d.y / ax.y, 2.0))


## The bubble: a faint ellipse, brighter for every layer up, split into sectors when there are several.
## An open sector (it just fired) is dim and broken; an ion-locked bubble flickers violet.
func _draw_bubble(co) -> void:
	if co.wrecked or co.layers_cap <= 0:
		return
	var ax := Shields.axes(co) * CELL
	var n: int = co.sectors
	var open := Shields.open_sectors(co, arena.tick)
	var ion: bool = co.ion_lock > 0.0
	var tint := ION if ion else (OVERCHARGE if co.overcharge_left > 0.0 else BUBBLE)
	var up: float = 0.0 if ion else float(co.layers)
	var fill := 0.025 + 0.035 * up
	var line := 0.10 + 0.17 * up if up > 0.0 else 0.07
	if ion:
		line = 0.2 + 0.3 * absf(sin(_clock * 25.0))
	var steps := maxi(6, BUBBLE_STEPS / n)
	for k in n:
		var a0 := (float(k) - 0.5) * TAU / n if n > 1 else -PI
		var a1 := (float(k) + 0.5) * TAU / n if n > 1 else PI
		var pts := PackedVector2Array()
		for i in steps + 1:
			pts.append(bubble_point(ax, lerpf(a0, a1, float(i) / steps)))
		var flick := 0.0
		if open[k]:
			flick = 0.35 + 0.25 * sin(_clock * 38.0 + k)
		draw_colored_polygon(PackedVector2Array([Vector2.ZERO]) + pts if n > 1 else pts, Color(tint, fill * (flick if open[k] else 1.0)))
		if not open[k]:
			draw_polyline(pts, Color(tint, minf(line, 0.9)), 2.0, true)
		else:  # broken: some of the arc is missing, and what is left flickers
			var shift := int(_clock * 24.0)
			for i in steps:
				if (i + shift) % 3 != 0:
					draw_line(pts[i], pts[i + 1], Color(tint, 0.35 * flick), 1.5)
	if n > 1:
		for k in n:
			var edge := bubble_point(ax, (float(k) - 0.5) * TAU / n)
			draw_line(Vector2.ZERO, edge, Color(tint, 0.10), 1.0)
	if co.overcharge_left > 0.0:
		var outer := PackedVector2Array()
		for i in BUBBLE_STEPS + 1:
			outer.append(bubble_point(ax + Vector2(10.0, 10.0), TAU * i / BUBBLE_STEPS))
		draw_polyline(outer, Color(OVERCHARGE, 0.35 + 0.2 * sin(_clock * 6.0)), 2.0, true)
