extends RefCounted
## Walking rules and pathfinding on the ship grid: A* on 4-neighbours with a Manhattan heuristic.
## Walkable = a non-empty tile that is not solid, or a door that `door_passable` lets through.
## Ties on f break on lower h, then lower (y, x), so the same grid always gives the same path.
## Everything is static: call it as `Pathfinder.find_path(...)`. No nodes, testable headless.

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const NO_CELL := Vector2i(-1, -1)  ## "none found"; real cells are never negative
const FAR := 1 << 30


## Can a crew member stand on `c`? `door_passable` is a Callable(cell) -> bool for door cells;
## an invalid (default) Callable means every door is passable.
static func walkable(grid: ShipGrid, c: Vector2i, door_passable: Callable = Callable()) -> bool:
	var id := grid.get_tile(c)
	if id == "":
		return false
	var def: Dictionary = grid.defs.get_def(id) if grid.defs != null else {}
	if def.get("door", false):
		return not door_passable.is_valid() or bool(door_passable.call(c))
	return not def.get("solid", false)


## Shortest path from `from` to `to`, both ends included. Empty when either end is not
## walkable or no route exists.
static func find_path(grid: ShipGrid, from: Vector2i, to: Vector2i, door_passable: Callable = Callable()) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not walkable(grid, from, door_passable) or not walkable(grid, to, door_passable):
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
			if closed.has(n) or g >= g_cost.get(n, FAR) or not walkable(grid, n, door_passable):
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


## The walkable cell whose centre is nearest to `p` (cell units), skipping `exclude`.
## Ties go to the lower (y, x). NO_CELL when there is none.
static func nearest_walkable(grid: ShipGrid, p: Vector2, door_passable: Callable = Callable(), exclude := NO_CELL) -> Vector2i:
	var best := NO_CELL
	var best_d := INF
	for c: Vector2i in grid.tiles:
		if c == exclude or not walkable(grid, c, door_passable):
			continue
		var d := (Vector2(c) + Vector2(0.5, 0.5) - p).length_squared()
		if d < best_d or (d == best_d and (c.y < best.y or (c.y == best.y and c.x < best.x))):
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
