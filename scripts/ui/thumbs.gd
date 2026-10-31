extends RefCounted
## The picture of a palette card (scripts/build/palette.gd entries), drawn from the real art: a part's sprite
## (a hull mount as its outside half above a strip of wall and its inside half under it, as it sits on the hull),
## a little patch of a tile autotiled on a scratch grid, a shaped piece, a cable run, a cargo icon. Centred in
## the rect it is given, at a whole number of screen px per cell. Drawing only.

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const Shapes = preload("res://scripts/ship/shapes.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Visuals = preload("res://scripts/view/visuals.gd")
const TileArt = preload("res://scripts/view/tile_art.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const BeltArt = preload("res://scripts/view/belt_art.gd")
const Ammo = preload("res://scripts/sim/ammo.gd")
const WALL := Color("#3b3f45")
const WALL_TOP := Color("#5a6068")
const CABLE := Color("#d98a4e")
const MAX_CELL := 32.0

static var _grids := {}  # entry key -> the scratch grid its tiles are drawn from


## Draw card `e` of `ship` into `r`. `t`: seconds, for the art's loops.
static func draw(cv: CanvasItem, e: Dictionary, ship, r: Rect2, t := 0.0) -> void:
	match e["kind"]:
		"part":
			_part(cv, ship.components.def(e["id"]), r, t)
		"item":
			var s := minf(r.size.x, r.size.y) * 0.8
			UiKit.icon(cv, e["id"], Rect2(r.get_center() - Vector2(s, s) / 2.0, Vector2(s, s)))
		"cable":
			_cable(cv, r)
		"belt":
			_belt(cv, r, t)
		_:
			_tiles(cv, e, ship, r)


## A part at rotation 0. A mount: [barrel room] outside half, wall, inside half, top to bottom.
static func _part(cv: CanvasItem, def: Dictionary, r: Rect2, t: float) -> void:
	var size := Vector2(float(def["size"][0]), float(def["size"][1]))
	if not Mounts.is_mount(def):
		var k := _cell(r, size)
		var rect := Rect2(r.get_center() - size * k / 2.0, size * k)
		Visuals.draw_component(cv, rect, def, {"rot": 0}, k, {"time": t})
		return
	var out := Vector2(float(def["mount"]["outside"][0]), float(def["mount"]["outside"][1]))
	var head := 1.0 if str(def.get("family", "")) in Visuals.BARRELS else 0.0  # the barrel (a gun, a dish, an emitter) sticks out above
	var wall := 0.5
	var k := _cell(r, Vector2(maxf(size.x, out.x), head + out.y + wall + size.y))
	var top := r.get_center().y - (head + out.y + wall + size.y) * k / 2.0 + head * k
	var out_rect := Rect2(Vector2(r.get_center().x - out.x * k / 2.0, top), out * k)
	var wall_rect := Rect2(Vector2(r.get_center().x - maxf(size.x, out.x) * k / 2.0, out_rect.end.y), Vector2(maxf(size.x, out.x) * k, wall * k))
	var in_rect := Rect2(Vector2(r.get_center().x - size.x * k / 2.0, wall_rect.end.y), size * k)
	cv.draw_rect(wall_rect, WALL)
	cv.draw_rect(Rect2(wall_rect.position, Vector2(wall_rect.size.x, maxf(1.0, k / 8.0))), WALL_TOP)
	Visuals.draw_component(cv, in_rect, def, {"rot": 0}, k, {"time": t})
	var pivot: Vector2 = out_rect.position + Mounts.barrel(def, Vector2i.ZERO, 0)["pivot"] * k
	Visuals.draw_mount_out(cv, def, {"rot": 0}, out_rect, pivot, k, Vector2.ZERO, {"time": t})


## Screen px per cell to fit `cells` in `r`: whole px, at most MAX_CELL.
static func _cell(r: Rect2, cells: Vector2) -> float:
	return clampf(floorf(minf(r.size.x / cells.x, r.size.y / cells.y)), 2.0, MAX_CELL)


## A tile, door or shaped piece from a scratch grid: floor 3x2, a wall 3x2 block, a door between two walls, a piece as it is.
static func _tiles(cv: CanvasItem, e: Dictionary, ship, r: Rect2) -> void:
	var g := _grid(e, ship)
	var lo := Vector2i(99, 99)
	var hi := Vector2i(-99, -99)
	for c in g.tiles:
		lo = lo.min(c)
		hi = hi.max(c)
	var cells := Vector2(hi - lo + Vector2i.ONE)
	var k := _cell(r, cells)
	var at := r.get_center() - cells * k / 2.0
	var col: Color = g.defs.color(e["id"])
	var door := []
	for c in g.tiles:
		var q := Rect2(at + Vector2(c - lo) * k, Vector2(k, k))
		var id: String = g.tiles[c]
		if g.tile_flag(id, "door"):
			door.append(q)
		elif g.tile_flag(id, "solid"):
			TileArt.solid_cell(cv, q, g, c, id, g.defs.color(id))
		elif not TileArt.floor_tile(cv, q, c):
			cv.draw_rect(q, col)
			cv.draw_rect(q.grow(-1), col.lightened(0.05), false, 1.0)
	if not door.is_empty() and not TileArt.door_piece(cv, door, true, 0.0):
		for q in door:
			cv.draw_rect(q, col)
		cv.draw_rect(Rect2(door[0].position + Vector2(0, k * 0.4), Vector2(k * door.size(), k * 0.2)), col.darkened(0.4))


## The scratch grid of card `e`, made once.
static func _grid(e: Dictionary, ship) -> ShipGrid:
	if _grids.has(e["key"]):
		return _grids[e["key"]]
	var g := ShipGrid.new(Vector2i(6, 4), ship.grid.defs)
	var id: String = e["id"]
	if e["kind"] == "piece":
		for pc in Shapes.piece_cells(e["piece"], Vector2i.ZERO):
			g.force_tile(pc["cell"], id, {"shape": pc["shape"], "rot": pc["rot"], "mirror": pc["mirror"]})
	elif g.tile_flag(id, "door"):
		var wall := "wall" if g.defs.has("wall") else id
		for x in 4:
			g.force_tile(Vector2i(x, 0), id if x in [1, 2] else wall)
	else:
		for y in 2:
			for x in 3:
				g.force_tile(Vector2i(x, y), id)
	_grids[e["key"]] = g
	return g


## Three cells of lit cable in a row.
static func _cable(cv: CanvasItem, r: Rect2) -> void:
	var k := _cell(r, Vector2(3, 1))
	var at := r.get_center() - Vector2(3, 1) * k / 2.0
	var has := func(c: Vector2i) -> bool: return c.y == 0 and c.x >= 0 and c.x < 3
	for x in 3:
		var q := Rect2(at + Vector2(x * k, 0), Vector2(k, k))
		if not TileArt.cable(cv, q, has, Vector2i(x, 0), true):
			cv.draw_line(q.get_center() - Vector2(k / 2.0, 0), q.get_center() + Vector2(k / 2.0, 0), CABLE, 2.0)
			cv.draw_circle(q.get_center(), 3.0, CABLE)


## Three cells of conveyor belt in a row, the treads running.
static func _belt(cv: CanvasItem, r: Rect2, t: float) -> void:
	var k := _cell(r, Vector2(3, 1))
	var at := r.get_center() - Vector2(3, 1) * k / 2.0
	for x in 3:
		BeltArt.tile(cv, Rect2(at + Vector2(x * k, 0), Vector2(k, k)), [2, 10, 8][x], t)
	BeltArt.unit(cv, at + Vector2((fposmod(t * 1.2, 1.0) * 2.0 + 0.5) * k, k / 2.0), k, "missile")
