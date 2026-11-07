extends RefCounted
## The ship's build grid: which cells are inside the hull and what is built on each cell.
## Pure data (no nodes, no drawing) so every rule can be tested headless.
## A door is a piece of exactly two door cells in a row (2x1 or 1x2) with a solid cell at each end;
## walls stay one cell thick, so a crew body (2x2) needs a 2-wide opening.

const VERSION := 2  # 2 adds door states; version 1 saves still load (all doors closed)
# Combat damage (hp, hp_max, breached) is saved as optional keys, written only when there is damage.
# Cell shapes (shapes, breached_shapes) are optional keys too, written only for cells that are not a full square.
const Shapes = preload("res://scripts/ship/shapes.gd")
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const NO_DEF := {}  ## the def of a tile id the defs do not know (read only)

var size: Vector2i
var defs  # tile_defs.gd instance, or null for a rule-less grid
var hull := {}   # Vector2i -> true: cells where building is allowed
var tiles := {}  # Vector2i -> tile id
var door_open := {}  # Vector2i -> true for doors that are open; closed doors are absent
var door_locked := {}  # Vector2i -> true for the doors of an abandoned room (Evacuate.sync sets them, K2): crew's paths avoid them unless the caller passes its own door_passable; not saved
var hp := {}  # Vector2i -> float: current hp of damaged cells (a cell not listed has full hp)
var hp_max := {}  # Vector2i -> float: max hp of cells burnt below their tile's hp (ablative); others are absent
var hp_mult := {}  # Vector2i -> float: factor on a wall's max hp from a part in the room it bounds (Stonehide bay), set when a fight starts; not saved
var breached := {}  # Vector2i -> tile id: cells shot open (now empty), with the tile to restore on repair
var shapes := {}  # Vector2i -> {shape, rot, mirror}: solid cells that are not a full square (see shapes.gd); a cell not listed is full
var breached_shapes := {}  # Vector2i -> {shape, rot, mirror}: the shape of a breached cell, restored on repair


func _init(p_size := Vector2i(63, 63), p_defs = null) -> void:
	size = p_size
	defs = p_defs


## Mark every cell whose centre lies within `radius` cells of the grid centre as hull.
func fill_circle_hull(radius: float) -> void:
	hull.clear()
	var centre := Vector2(size) / 2.0
	for y in size.y:
		for x in size.x:
			if (Vector2(x + 0.5, y + 0.5) - centre).length() <= radius:
				hull[Vector2i(x, y)] = true


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


func in_hull(c: Vector2i) -> bool:
	return hull.has(c)


func get_tile(c: Vector2i) -> String:
	return tiles.get(c, "")


## Why `id` cannot go on `c`, or "" when it can. Placing over a different tile replaces it. `shape`
## ({shape, rot, mirror}, default a full square) is the shape the cell takes; only solid tiles take one.
func can_place(id: String, c: Vector2i, shape := {}) -> String:
	if not in_hull(c):
		return "outside the hull"
	if defs != null and not defs.has(id):
		return "unknown tile"
	var sh := Shapes.norm(shape)
	if not sh.is_empty() and not _flag(id, "solid"):
		return "only walls take a shape"
	var cur := get_tile(c)
	if cur == id and shape_of(c) == sh:
		return "already there"
	if cur != "" and not _flag(id, "solid") and _supports_door(c):
		return "a door needs this wall"
	if _flag(id, "door"):
		return can_place_door(id, c, door_axis_at(c))
	return ""


## Place tile `id` on `c`. A door goes in as a piece of two cells starting at `c` (door_axis_at
## picks the direction; place_door() chooses it). Replacing a door cell replaces its whole piece.
func place(id: String, c: Vector2i, shape := {}) -> bool:
	if can_place(id, c, shape) != "":
		return false
	if _flag(id, "door"):
		return place_door(id, c, door_axis_at(c))
	for p in door_piece(c) if _flag(get_tile(c), "door") else [c]:
		force_tile(p, id, shape)
	return true


## The direction an automatic door piece starting at `c` takes: RIGHT (a 2x1 piece in a horizontal
## wall) when the cells left of `c` and right of `c + 1` are solid, else DOWN (a 1x2 piece).
func door_axis_at(c: Vector2i) -> Vector2i:
	if _is_solid(c + Vector2i.LEFT) and _is_solid(c + Vector2i(2, 0)):
		return Vector2i.RIGHT
	return Vector2i.DOWN


## Why door piece `id` cannot start at `c` and run along `axis` (RIGHT = 2x1, DOWN = 1x2), or ""
## when it can: `c` and the next cell along `axis` become doors. Both cells need the hull, the cells
## past both ends must be solid (so the run is exactly 2 long) and no door may touch the piece from
## the side (so a door cell never belongs to two pieces).
func can_place_door(id: String, c: Vector2i, axis: Vector2i) -> String:
	if axis != Vector2i.RIGHT and axis != Vector2i.DOWN:
		return "bad door direction"
	var cells := _piece_at(c, axis)
	for p in cells:
		if not in_hull(p):
			return "outside the hull"
	if defs != null and not _flag(id, "door"):
		return "unknown tile" if not defs.has(id) else "not a door"
	if cells.all(func(p): return get_tile(p) == id) and door_piece(c) == cells:
		return "already there"
	if not (_is_solid(c - axis) and _is_solid(c + axis * 2)):
		return "doors need walls at both ends"
	var side := Vector2i(axis.y, axis.x)
	for p in cells:
		if _flag(get_tile(p + side), "door") or _flag(get_tile(p - side), "door"):
			return "no door beside a door"
	return ""


## Build door piece `id` (see can_place_door), replacing whatever stood on its two cells.
## Returns false when it cannot go there.
func place_door(id: String, c: Vector2i, axis: Vector2i) -> bool:
	if can_place_door(id, c, axis) != "":
		return false
	for p in _piece_at(c, axis):
		force_tile(p, id)
	return true


## The cells of the door piece holding door cell `c`, in (y, x) order; [] when `c` is no door.
## A door cell that is part of no valid piece (an old save, hand-written test data) is a piece of one.
func door_piece(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not _flag(tiles.get(c, ""), "door"):
		return out
	for axis in [Vector2i.RIGHT, Vector2i.DOWN]:
		var run := _door_run(c, axis)
		if _run_fits(run, axis):
			return run
	out.append(c)
	return out


## Set the tile on `c` ("" clears it) without checking any rule, close any door there and forget
## any damage on the cell. `shape` ({shape, rot, mirror}) is the cell's new shape, a full square when
## left out. Only for replaying recorded edits; use place() and remove() for user actions.
func force_tile(c: Vector2i, id: String, shape := {}) -> void:
	if id == "":
		tiles.erase(c)
	else:
		tiles[c] = id
	door_open.erase(c)
	door_locked.erase(c)
	hp.erase(c)
	hp_max.erase(c)
	breached.erase(c)
	breached_shapes.erase(c)
	var sh := Shapes.norm(shape) if id != "" else {}
	if sh.is_empty():
		shapes.erase(c)
	else:
		shapes[c] = sh


## Give the tile on `c` a shape (a full square erases it). Rotation is in quarter turns clockwise.
func set_shape(c: Vector2i, shape: String, rot := 0, mirror := false) -> void:
	var sh := Shapes.norm({"shape": shape, "rot": rot, "mirror": mirror})
	if sh.is_empty():
		shapes.erase(c)
	else:
		shapes[c] = sh


## The stored shape of the cell on `c`: {shape, rot, mirror}, or {} for a full square.
func shape_of(c: Vector2i) -> Dictionary:
	return shapes.get(c, {})


## Solid area of the cell on `c` in cells: 1 for a full square, less for a slope or a curve.
func area_at(c: Vector2i) -> float:
	return Shapes.area_of(shapes[c]) if shapes.has(c) else 1.0


## The solid polygon of the cell on `c` in cell-local coordinates (the unit square when it is full).
func polygon_at(c: Vector2i) -> PackedVector2Array:
	var sh := shape_of(c)
	return Shapes.cell_polygon(str(sh["shape"]), int(sh["rot"]), bool(sh["mirror"])) if not sh.is_empty() else Shapes.cell_polygon(Shapes.FULL)


## Max hp of the tile on `c`: what ablative burn left of it, else its tile's `hp` (1 when the tile
## has none, or the grid has no rules) times the cell's solid area, at least 1; 0 where there is no tile.
func max_hp_of(c: Vector2i) -> float:
	var id := get_tile(c)
	if id == "":
		return 0.0
	if hp_max.has(c):
		return hp_max[c]
	var base := (float(defs.get_def(id).get("hp", 1.0)) if defs != null else 1.0) * float(hp_mult.get(c, 1.0))
	return maxf(base * area_at(c), 1.0) if shapes.has(c) else base


## Current hp of the tile on `c`; 0 where there is no tile.
func hp_of(c: Vector2i) -> float:
	return hp[c] if hp.has(c) else max_hp_of(c)


## Shoot the tile on `c` open: the cell becomes empty (so rooms see a hole there) and `breached`
## remembers the tile for repair. Returns the tile id, "" when there was nothing to breach.
func breach(c: Vector2i) -> String:
	var id := get_tile(c)
	if id == "":
		return ""
	var sh := shape_of(c)
	force_tile(c, "")
	breached[c] = id
	if not sh.is_empty():
		breached_shapes[c] = sh
	return id


## Put a breached cell's tile back at full hp. Returns false when `c` is not breached.
func repair(c: Vector2i) -> bool:
	if not breached.has(c):
		return false
	force_tile(c, breached[c], breached_shapes.get(c, {}))
	return true


func can_remove(c: Vector2i) -> String:
	if get_tile(c) == "":
		return "nothing to remove"
	if _supports_door(c):
		return "a door needs this wall"
	return ""


## Remove the tile on `c`; removing either cell of a door piece removes the whole piece.
func remove(c: Vector2i) -> bool:
	if can_remove(c) != "":
		return false
	for p in door_piece(c) if _flag(get_tile(c), "door") else [c]:
		force_tile(p, "")
	return true


## Materials needed to build tile `id` (material id -> count); {} when it is free or unknown. A
## cell that is only part of a square (`area` < 1) costs that part of each count, rounded up.
func cost_of(id: String, area := 1.0) -> Dictionary:
	if defs == null:
		return {}
	var raw = defs.get_def(id).get("cost", {})
	var cost := {}
	if raw is Dictionary:
		for m in raw:  # JSON numbers are floats
			cost[str(m)] = int(raw[m]) if area >= 1.0 else ceili(float(raw[m]) * area - 1e-9)
	return cost


## Everything built so far, summed per material.
func total_cost() -> Dictionary:
	var sum := {}
	for c in tiles:
		var cost := cost_of(tiles[c], area_at(c))
		for m in cost:
			sum[m] = int(sum.get(m, 0)) + int(cost[m])
	return sum


## True when tile `id` has the data flag `key` ("solid", "door").
func tile_flag(id: String, key: String) -> bool:
	return _flag(id, key)


## Open or close the door on `c`: the whole piece moves together. Returns false when there is no door there.
func set_door_open(c: Vector2i, open: bool) -> bool:
	if not _flag(get_tile(c), "door"):
		return false
	for p in door_piece(c):
		if open:
			door_open[p] = true
		else:
			door_open.erase(p)
	return true


func is_door_open(c: Vector2i) -> bool:
	return door_open.has(c)


func to_dict() -> Dictionary:
	var h := []
	for c in _sorted(hull.keys()):
		h.append([c.x, c.y])
	var t := []
	for c in _sorted(tiles.keys()):
		t.append([c.x, c.y, tiles[c]])
	var o := []
	for c in _sorted(door_open.keys()):
		o.append([c.x, c.y])
	var d := {"version": VERSION, "size": [size.x, size.y], "hull": h, "tiles": t, "doors_open": o}
	for pair in [["hp", hp], ["hp_max", hp_max], ["breached", breached]]:
		if not pair[1].is_empty():
			var list := []
			for c in _sorted(pair[1].keys()):
				list.append([c.x, c.y, pair[1][c]])
			d[pair[0]] = list
	for pair in [["shapes", shapes], ["breached_shapes", breached_shapes]]:
		if not pair[1].is_empty():
			var list := []
			for c in _sorted(pair[1].keys()):
				list.append([c.x, c.y, pair[1][c]["shape"], pair[1][c]["rot"], pair[1][c]["mirror"]])
			d[pair[0]] = list
	return d


## Replace this grid with a saved one (version 1 or 2). Returns "" on success, else the reason;
## nothing changes when it fails.
func load_dict(d: Dictionary) -> String:
	var version := int(d.get("version", 0))
	if version < 1 or version > VERSION:
		return "unsupported ship version"
	if not (d.get("size") is Array and d["size"].size() == 2 and d.get("hull") is Array and d.get("tiles") is Array):
		return "bad ship data"
	var new_size := Vector2i(int(d["size"][0]), int(d["size"][1]))
	var new_hull := {}
	for p in d["hull"]:
		if not (p is Array and p.size() == 2):
			return "bad ship data"
		new_hull[Vector2i(int(p[0]), int(p[1]))] = true
	var new_tiles := {}
	for p in d["tiles"]:
		if not (p is Array and p.size() == 3):
			return "bad ship data"
		if defs != null and not defs.has(str(p[2])):
			return "unknown tile " + str(p[2])
		new_tiles[Vector2i(int(p[0]), int(p[1]))] = str(p[2])
	var new_hp = _cell_values(d, "hp", false)
	var new_hp_max = _cell_values(d, "hp_max", false)
	var new_breached = _cell_values(d, "breached", true)
	var new_shapes = _shape_values(d, "shapes")
	var new_breached_shapes = _shape_values(d, "breached_shapes")
	if new_hp == null or new_hp_max == null or new_breached == null or new_shapes == null or new_breached_shapes == null:
		return "bad ship data"
	for c in new_breached:
		if defs != null and not defs.has(new_breached[c]):
			return "unknown tile " + new_breached[c]
	size = new_size
	hull = new_hull
	tiles = new_tiles
	hp = new_hp
	hp_max = new_hp_max
	breached = new_breached
	shapes = new_shapes
	breached_shapes = new_breached_shapes
	door_open.clear()
	for p in d.get("doors_open", []):
		if p is Array and p.size() == 2 and _flag(get_tile(Vector2i(int(p[0]), int(p[1]))), "door"):
			door_open[Vector2i(int(p[0]), int(p[1]))] = true
	return ""


## The optional save list `key` ([[x, y, value], ...]) as cell -> value (a string when `text`, else
## a float); {} when absent, null when malformed.
static func _cell_values(d: Dictionary, key: String, text: bool):
	var list = d.get(key, [])
	if not list is Array:
		return null
	var out := {}
	for p in list:
		if not (p is Array and p.size() == 3 and (p[2] is String if text else (p[2] is float or p[2] is int))):
			return null
		out[Vector2i(int(p[0]), int(p[1]))] = p[2] if text else float(p[2])
	return out


## The optional save list `key` ([[x, y, shape, rot, mirror], ...]) as cell -> {shape, rot, mirror}; {}
## when absent, null when malformed or naming an unknown shape. Full squares are dropped.
static func _shape_values(d: Dictionary, key: String):
	var list = d.get(key, [])
	if not list is Array:
		return null
	var out := {}
	for p in list:
		if not (p is Array and p.size() == 5 and p[2] is String and Shapes.has_shape(p[2]) and (p[3] is float or p[3] is int) and p[4] is bool):
			return null
		var sh := Shapes.norm({"shape": p[2], "rot": int(p[3]), "mirror": p[4]})
		if not sh.is_empty():
			out[Vector2i(int(p[0]), int(p[1]))] = sh
	return out


func _flag(id: String, key: String) -> bool:
	return defs != null and bool(defs.by_id.get(id, NO_DEF).get(key, false))  # (defs.get_def in place: the door rules ask this a lot)


func _is_solid(c: Vector2i) -> bool:
	return _flag(tiles.get(c, ""), "solid")


## The two cells a piece starting at `c` takes along `axis`.
static func _piece_at(c: Vector2i, axis: Vector2i) -> Array[Vector2i]:
	return [c, c + axis]


## The contiguous door cells through `c` along `axis`, lowest first.
func _door_run(c: Vector2i, axis: Vector2i) -> Array[Vector2i]:
	var first := c
	while _flag(tiles.get(first - axis, ""), "door"):
		first -= axis
	var run: Array[Vector2i] = []
	var p := first
	while _flag(tiles.get(p, ""), "door"):
		run.append(p)
		p += axis
	return run


## A run is a valid door piece when it is exactly 2 cells long with a solid cell past both ends.
func _run_fits(run: Array[Vector2i], axis: Vector2i) -> bool:
	return run.size() == 2 and _is_solid(run[0] - axis) and _is_solid(run[1] + axis)


## Does the door cell `c` belong to a valid door piece?
func _door_fits(c: Vector2i) -> bool:
	return door_piece(c).size() == 2


## True when `c` is a solid tile that a neighbouring door would no longer fit without.
func _supports_door(c: Vector2i) -> bool:
	if not _is_solid(c):
		return false
	var saved: String = tiles[c]
	var held: Array[Vector2i] = []  # door cells beside `c` that are in a valid piece now
	for d in SIDES:
		if _door_fits(c + d):
			held.append(c + d)
	tiles.erase(c)
	var needed := held.any(func(p): return not _door_fits(p))
	tiles[c] = saved
	return needed


static func _sorted(keys: Array) -> Array:
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return keys
