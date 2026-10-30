extends Node2D
## One ship drawn at its place in the arena: the node sits on the ship's flight body (position and
## heading), so everything below is drawn in the ship's own frame, in pixels from its pivot. Tiles
## (materials by colour), breached cells as dark holes, damage, doors, systems through visuals.gd,
## crew, and the shield bubble. Drawing only; bind() it to an arena ship and it follows it.
## Reusable: with no arena it draws a plain Ship at the node's own transform (pivot = the hull's centre).

const Visuals = preload("res://scripts/view/visuals.gd")
const PersonDrawer = preload("res://scripts/crew/person_drawer.gd")
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


func _process(dt: float) -> void:
	_clock += dt
	_follow()
	queue_redraw()


## The pixel position of cell coordinates `c` relative to the pivot.
func px(c: Vector2) -> Vector2:
	return (c - pivot) * CELL


func _draw() -> void:
	if ship == null:
		return
	var grid = ship.grid
	for c in grid.tiles:
		_draw_tile(grid, c, grid.tiles[c])
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
		Visuals.draw_component(self, r, ship.components.def(inst["id"]), inst, CELL, {"powered": powered.get(uid, false)})
	for m in ship.crew:
		var look: Dictionary = LOOKS.get(m.name, OTHER_LOOK)
		PersonDrawer.draw_person(self, px(m.pos), m.facing.angle(), _clock * 2.2, false, look, CELL)
	if arena != null:
		_draw_bubble(arena.ships[index])


func _draw_tile(grid, c: Vector2i, id: String) -> void:
	var r := Rect2(px(Vector2(c)), Vector2(CELL, CELL))
	var col: Color = grid.defs.color(id)
	var def: Dictionary = grid.defs.get_def(id)
	if def.get("door", false):
		var piece: Array[Vector2i] = grid.door_piece(c)
		if piece[0] == c:
			_draw_door(grid, piece, col, grid.is_door_open(c))
	elif def.get("solid", false):
		draw_rect(r, col)
		draw_rect(r.grow(-3), col.lightened(0.12))
	else:
		draw_rect(r, col)
		draw_rect(r.grow(-1), col.lightened(0.05), false, 1.0)


## A door piece: floor under it, two leaves that meet in the middle when closed and slide back into
## the walls at both ends when open (an open door lets shots through).
func _draw_door(grid, piece: Array[Vector2i], col: Color, open: bool) -> void:
	var floor_col: Color = grid.defs.color("floor") if grid.defs.has("floor") else col.darkened(0.5)
	for p in piece:
		draw_rect(Rect2(px(Vector2(p)), Vector2(CELL, CELL)), floor_col)
	var horizontal: bool = piece[1].x != piece[0].x if piece.size() > 1 else true
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
	draw_rect(Rect2(o, Vector2(CELL, CELL)), Color(0.05, 0.02, 0.0, 0.55 * lost))
	draw_line(o + Vector2(4, 6), o + Vector2(CELL * 0.55, CELL * 0.5), Color(0, 0, 0, 0.8), 1.5)
	if lost > 0.4:
		draw_line(o + Vector2(CELL * 0.55, CELL * 0.5), o + Vector2(CELL - 5, CELL - 8), Color(0, 0, 0, 0.8), 1.5)


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
