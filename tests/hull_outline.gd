extends RefCounted
## Not a test (the runner only loads test_*.gd). The silhouette helper of tests/tool_make_starters.gd and
## tests/tool_make_rammer.gd: turns a hull OUTLINE into the cells of a hull, with the exact shaped cells
## (data/shapes.json, docs/CONTENT.md 4d) wherever the outline cuts a cell. No stair-step fakes.
##
## An outline is a closed polygon on the cell lattice (local cell coordinates, x right, y down), a list of
## points [x, y] and arcs ["arc", cx, cy, from_deg, to_deg]: a round2 corner, radius 2 round (cx, cy), the
## angles in screen degrees (0 = +x, 90 = down) and drawn in 8 segments exactly like the round2 piece.
## Every edge must be axis-aligned, 45 degrees (slope45) or 2:1 (slope2), and start and end on lattice
## points, so each cut cell is one of the shapes of shapes.json; anything else is reported as an error.
##
## rasterize() gives the cells; layers() sorts them into the skin and the wall behind it. A skin cell
## is a cell next to space or a shaped one: plating where the caller says so, steel where it does not.
## Behind a plated cell comes a full cell of steel (or of more plating where the caller says so: the
## plate is thin, and slopes need something solid behind them), and what is left inside is floor for
## the caller to partition with bulkheads.

const Shapes = preload("res://scripts/ship/shapes.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")

const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const ARC_R := 2.0
const ARC_STEPS := 8
const EPS := 1e-6
const TOL := 2e-5  ## shape match: the shape library keeps six digits


## The outline as a polygon.
static func polygon(outline: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in outline:
		if p.size() == 5 and p[0] is String:
			var a0: float = deg_to_rad(float(p[3]))
			var a1: float = deg_to_rad(float(p[4]))
			for k in ARC_STEPS + 1:
				var a: float = a0 + (a1 - a0) * k / ARC_STEPS
				out.append(Vector2(float(p[1]) + ARC_R * cos(a), float(p[2]) + ARC_R * sin(a)))
		else:
			out.append(Vector2(float(p[0]), float(p[1])))
	return out


## The cells of the outline: {"cells": {Vector2i: shape dict ({} = a full cell, else {shape, rot, mirror})},
## "errors": [text]}. A cell the outline cuts in a way no shape of shapes.json fits is an error.
static func rasterize(outline: Array) -> Dictionary:
	var poly := polygon(outline)
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	var cells := {}
	var errors := []
	for y in range(floori(lo.y), ceili(hi.y)):
		for x in range(floori(lo.x), ceili(hi.x)):
			var cut := _clip(poly, Vector2(x, y))
			var area := absf(Shapes.polygon_area(cut))
			if area < EPS:
				continue
			var c := Vector2i(x, y)
			if area > 1.0 - EPS:
				cells[c] = {}
				continue
			var sd := _match(cut, area)
			if sd.is_empty():
				errors.append("cell %s: the outline cuts it into %s, which is no shape of shapes.json" % [str(c), str(cut)])
			else:
				cells[c] = sd
	return {"cells": cells, "errors": errors}


## Sort the cells of rasterize() into {Vector2i: {"tile": tile id, "shape": {}}}: the tile is "floor", "wall"
## (steel) or a plating tile. `skin_of` is a Callable(cell) -> the plating tile id of a skin cell, "" for steel;
## `behind_of` (optional) the same for a cell behind a plated skin cell ("" or no Callable: steel).
static func layers(cells: Dictionary, skin_of: Callable, behind_of := Callable()) -> Dictionary:
	var out := {}
	for c in cells:
		var skin: bool = not cells[c].is_empty()
		for d in SIDES:
			skin = skin or not cells.has(c + d)
		if skin:
			var id: String = skin_of.call(c)
			out[c] = {"tile": id if id != "" else "wall", "shape": cells[c]}
	var behind := {}
	for c in out:
		if out[c]["tile"] != "wall":
			for d in SIDES:
				if cells.has(c + d) and not out.has(c + d):
					behind[c + d] = true
	for c in behind:
		var id: String = behind_of.call(c) if behind_of.is_valid() else ""
		out[c] = {"tile": id if id != "" else "wall", "shape": {}}
	for c in cells:
		if not out.has(c):
			out[c] = {"tile": "floor", "shape": {}}
	return out


## The shape (rot and mirror included) whose polygon is `cut` (clockwise or not), or {}.
static func _match(cut: PackedVector2Array, area: float) -> Dictionary:
	var poly := cut
	if Shapes.polygon_area(poly) < 0.0:
		poly.reverse()
	for id in Shapes.shape_ids():
		if id == Shapes.FULL:
			continue
		for mirror in [false, true]:
			for rot in 4:
				var cand := Shapes.cell_polygon(id, rot, mirror)
				if absf(Shapes.polygon_area(cand) - area) > TOL:
					continue
				if cand.size() <= 6 and _inside_all(poly, cand) and _inside_all(cand, poly):
					return {"shape": id, "rot": rot, "mirror": mirror}
	return {}


## Is every vertex of `pts` inside (or on) the convex polygon `shape` (clockwise on screen)?
static func _inside_all(shape: PackedVector2Array, pts: PackedVector2Array) -> bool:
	for p in pts:
		for i in shape.size():
			var a: Vector2 = shape[i]
			var b: Vector2 = shape[(i + 1) % shape.size()]
			if (b - a).cross(p - a) < -TOL:
				return false
	return true


## `poly` clipped to the unit square whose top-left corner is `at`.
static func _clip(poly: PackedVector2Array, at: Vector2) -> PackedVector2Array:
	var out := poly
	out = _half(out, Vector2(-1, 0), -at.x)
	out = _half(out, Vector2(1, 0), at.x + 1.0)
	out = _half(out, Vector2(0, -1), -at.y)
	out = _half(out, Vector2(0, 1), at.y + 1.0)
	for i in out.size():
		out[i] -= at
	return out


## Sutherland-Hodgman: `poly` cut to the half plane n . p <= d.
static func _half(poly: PackedVector2Array, n: Vector2, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var da := n.dot(a) - d
		var db := n.dot(b) - d
		if da <= EPS:
			out.append(a)
		if (da < -EPS and db > EPS) or (da > EPS and db < -EPS):
			out.append(a + (b - a) * (da / (da - db)))
	return out


## The ruler line(s) over a map from cell x `lo` to `hi`.
static func ruler(lo: Vector2i, hi: Vector2i) -> String:
	var tens := "    "
	var ones := "    "
	for x in range(lo.x, hi.x + 1):
		tens += str((x / 10) % 10) if x % 10 == 0 else " "
		ones += str(posmod(x, 10))
	return tens + "\n" + ones


## One glyph for a shaped cell: a triangle pointing at the solid corner of a slope45, / or \ for the cut of
## a slope2, o for a curve.
static func shape_glyph(sd: Dictionary) -> String:
	if str(sd["shape"]).begins_with("round2"):
		return "o"
	var poly := Shapes.cell_polygon(str(sd["shape"]), int(sd["rot"]), bool(sd["mirror"]))
	var cen := Shapes.centroid(str(sd["shape"]), int(sd["rot"]), bool(sd["mirror"]))
	if str(sd["shape"]) == "tri":
		return "◤◥◢◣"[(0 if cen.x < 0.5 and cen.y < 0.5 else (1 if cen.x >= 0.5 and cen.y < 0.5 else (2 if cen.x >= 0.5 else 3)))]
	# slope2: the cut is the one edge that is neither across nor up and down; '/' when it climbs to the right
	for i in poly.size():
		var e: Vector2 = poly[(i + 1) % poly.size()] - poly[i]
		if absf(e.x) > 1e-6 and absf(e.y) > 1e-6:
			return "/" if e.x * e.y < 0.0 else "\\"
	return "?"


## The walkable cells that no crew body can reach from the helm (by body_ok, the way crew path).
static func pockets(ship) -> Array:
	var helm := -1
	for uid in ship.components.instances:
		if ship.components.def(ship.components.instances[uid]["id"])["family"] == "helm":
			helm = uid
	if helm < 0:
		return ship.grid.tiles.keys().filter(func(c): return Pathfinder.walkable(ship.grid, c))  # nobody can get anywhere
	var start: Vector2i = ship.components.instances[helm]["anchor"]
	var seen := {start: true}
	var open := [start]
	while not open.is_empty():
		var a: Vector2i = open.pop_back()
		for d in SIDES:
			if not seen.has(a + d) and Pathfinder.body_ok(ship.grid, a + d):
				seen[a + d] = true
				open.append(a + d)
	var covered := {}
	for a in seen:
		for c in Pathfinder.body_cells(a):
			covered[c] = true
	return ship.grid.tiles.keys().filter(func(c): return Pathfinder.walkable(ship.grid, c) and not covered.has(c))
