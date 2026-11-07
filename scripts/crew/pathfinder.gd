extends RefCounted
## Walking rules and pathfinding on the ship grid: A* on 4-neighbours with a Manhattan heuristic.
## Walkable = a non-empty tile that is not solid, or a door that `door_passable` lets through.
## A crew body is BODY x BODY cells (2x2), so paths run over body anchors: the top-left cell of the
## body. An anchor is usable when all its cells are walkable (clearance), and the body centre is
## the anchor plus (1, 1) in cell units. A 1-wide corridor is closed to bodies; a 2-wide one is open.
## A small body (the trait `body` 1, CrewMember.body_size) is 1x1: every function takes its `body`
## size last (default BODY), its anchor is the cell it stands on and its centre the anchor plus (0.5, 0.5),
## so it also walks the 1-wide corridors (crawlspaces) that 2x2 bodies cannot.
## Ties on f break on lower h, then lower (y, x), so the same grid always gives the same path.
## A climber (a repair drone, CrewMember.climbs) also walks over solid wall and hull cells (any tile, not the empty space); each function
## takes `climb` last (default false).
## Everything is static: call it as `Pathfinder.find_path(...)`. No nodes, testable headless.

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const NO_CELL := Vector2i(-1, -1)  ## "none found"; real cells and anchors are never negative
const BODY := 2  ## a crew body covers BODY x BODY cells
const FAR := 1 << 30
const NO_DEF := {}  # (the def of a tile id the grid's defs do not know)


## Can a crew member stand on `c`? `door_passable` is a Callable(cell) -> bool for door cells;
## an invalid (default) Callable means every door is passable but a locked one (grid.door_locked: the doors of an
## abandoned room), which only a valid Callable that says yes lets through (the player's soldier walks in).
static func walkable(grid: ShipGrid, c: Vector2i, door_passable: Callable = Callable(), climb := false) -> bool:
	var id: String = grid.tiles.get(c, "")  # (grid.get_tile and defs.get_def read in place: every cell of every path comes here)
	if id == "":
		return false
	if climb and grid.tile_flag(id, "solid"):
		return true
	var def: Dictionary = grid.defs.by_id.get(id, NO_DEF) if grid.defs != null else NO_DEF
	if def.get("door", false):
		if grid.door_locked.has(c):
			return door_passable.is_valid() and bool(door_passable.call(c))
		return not door_passable.is_valid() or bool(door_passable.call(c))
	return not def.get("solid", false)


## Can a body stand with its top-left cell on `anchor`? All body x body cells must be walkable.
static func body_ok(grid: ShipGrid, anchor: Vector2i, door_passable: Callable = Callable(), body := BODY, climb := false) -> bool:
	for y in body:
		for x in body:
			if not walkable(grid, anchor + Vector2i(x, y), door_passable, climb):
				return false
	return true


## The anchor of the body whose centre is nearest to `p` (cell units), whether or not it is usable.
static func anchor_of(p: Vector2, body := BODY) -> Vector2i:
	if body == BODY:
		return Vector2i(roundi(p.x), roundi(p.y)) - Vector2i.ONE
	var h := body * 0.5
	return Vector2i(roundi(p.x - h), roundi(p.y - h))


## The centre (cell units) of a body on `anchor`.
static func centre_of(anchor: Vector2i, body := BODY) -> Vector2:
	return Vector2(anchor) + Vector2.ONE * (body * 0.5)


## The cells a body on `anchor` covers, row by row.
static func body_cells(anchor: Vector2i, body := BODY) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in body:
		for x in body:
			out.append(anchor + Vector2i(x, y))
	return out


## Shortest path of body anchors from `from` to `to`, both ends included. Empty when either end
## is not usable (see body_ok) or no route exists.
static func find_path(grid: ShipGrid, from: Vector2i, to: Vector2i, door_passable: Callable = Callable(), body := BODY, climb := false) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not body_ok(grid, from, door_passable, body, climb) or not body_ok(grid, to, door_passable, body, climb):
		return path
	var g_cost := {from: 0}
	var came_from := {}
	var closed := {}
	# Heap entries are Vector4i(f, h, y, x), compared in that order.
	var heap: Array[Vector4i] = []
	var h0 := _dist(from, to)
	_push(heap, Vector4i(h0, h0, from.y, from.x))
	while not heap.is_empty():
		var top := _pop(heap)
		var cur := Vector2i(top.w, top.z)
		if closed.has(cur):
			continue  # stale duplicate from an earlier, worse push
		closed[cur] = true
		if cur == to:
			break
		var g: int = g_cost[cur] + 1
		for d in ShipGrid.SIDES:
			var n := cur + d
			if closed.has(n) or g >= g_cost.get(n, FAR) or not body_ok(grid, n, door_passable, body, climb):
				continue
			g_cost[n] = g
			came_from[n] = cur
			var h := _dist(n, to)
			_push(heap, Vector4i(g + h, h, n.y, n.x))
	if not closed.has(to):
		return path
	var c := to
	while c != from:
		path.append(c)
		c = came_from[c]
	path.append(from)
	path.reverse()
	return path


## The usable body anchor whose body centre is nearest to `p` (cell units). Anchors whose body
## would overlap a body on `exclude` are skipped. Ties go to the lower (y, x). NO_CELL when none.
static func nearest_walkable(grid: ShipGrid, p: Vector2, door_passable: Callable = Callable(), exclude := NO_CELL, body := BODY, climb := false) -> Vector2i:
	var best := NO_CELL
	var best_d := INF
	for c: Vector2i in grid.tiles:  # an anchor is itself a walkable tile
		if exclude != NO_CELL and absi(c.x - exclude.x) < BODY and absi(c.y - exclude.y) < BODY:
			continue
		var d := (centre_of(c, body) - p).length_squared()
		if d > best_d or (d == best_d and (c.y > best.y or (c.y == best.y and c.x > best.x))):
			continue
		if body_ok(grid, c, door_passable, body, climb):
			best = c
			best_d = d
	return best


static func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func _less(a: Vector4i, b: Vector4i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	if a.z != b.z:
		return a.z < b.z
	return a.w < b.w


static func _push(heap: Array[Vector4i], v: Vector4i) -> void:
	heap.append(v)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if not _less(heap[i], heap[p]):
			break
		var t := heap[p]
		heap[p] = heap[i]
		heap[i] = t
		i = p


static func _pop(heap: Array[Vector4i]) -> Vector4i:
	var top := heap[0]
	var last: Vector4i = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	var n := heap.size()
	while true:
		var l := 2 * i + 1
		if l >= n:
			break
		var m := l + 1 if l + 1 < n and _less(heap[l + 1], heap[l]) else l
		if not _less(heap[m], heap[i]):
			break
		var t := heap[m]
		heap[m] = heap[i]
		heap[i] = t
		i = m
	return top
