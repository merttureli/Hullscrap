extends RefCounted
## One person walking inside the ship. Plain data and rules: no nodes, no drawing.
## `pos` is in cell units, so the centre of cell c is c + (0.5, 0.5).
## NPCs follow a `path` (go_to + step); the player's soldier moves directly (move_input).

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const RADIUS := 0.3  ## body radius in cells, used for wall collision
const MAX_SUBSTEP := 0.2  ## longest single move in cells, so a long frame cannot skip over a wall

var name := ""
var pos := Vector2.ZERO
var speed := 3.0  ## cells per second
var facing := Vector2.DOWN
var path: Array[Vector2i] = []


func _init(p_name := "", p_pos := Vector2.ZERO) -> void:
	name = p_name
	pos = p_pos


func cell() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


## Walk to `target` along the shortest path from the current cell. Returns false (and keeps
## the current path) when there is no route.
func go_to(grid: ShipGrid, target: Vector2i, door_passable: Callable = Callable()) -> bool:
	var p := Pathfinder.find_path(grid, cell(), target, door_passable)
	if p.is_empty():
		return false
	path = p
	return true


## Advance along the path, centre to centre. Ends exactly on the last cell's centre.
func step(dt: float) -> void:
	var left := speed * dt
	while left > 0.0 and not path.is_empty():
		var to := Vector2(path[0]) + Vector2(0.5, 0.5)
		var d := to - pos
		var dist := d.length()
		if dist > 0.0:
			facing = d / dist
		if dist <= left:
			pos = to
			left -= dist
			path.remove_at(0)
		else:
			pos += facing * left
			left = 0.0


## The player's direct movement: `dir` (any length) x speed x dt, one axis at a time so the
## body slides along walls. A move that would put the body into a non-walkable cell is dropped.
func move_input(grid: ShipGrid, dir: Vector2, dt: float, door_passable: Callable = Callable()) -> void:
	if dir.length_squared() < 0.0001 or dt <= 0.0:
		return
	facing = dir.normalized()
	var dist := speed * dt
	var n := maxi(1, ceili(dist / MAX_SUBSTEP))
	var d := facing * (dist / n)
	for i in n:
		if fits(grid, pos + Vector2(d.x, 0.0), door_passable):
			pos.x += d.x
		if fits(grid, pos + Vector2(0.0, d.y), door_passable):
			pos.y += d.y


## Would a body of `radius` centred on `p` stay clear of every non-walkable cell?
func fits(grid: ShipGrid, p: Vector2, door_passable: Callable = Callable(), radius := RADIUS) -> bool:
	for cy in range(floori(p.y - radius), floori(p.y + radius) + 1):
		for cx in range(floori(p.x - radius), floori(p.x + radius) + 1):
			if Pathfinder.walkable(grid, Vector2i(cx, cy), door_passable):
				continue
			var near := Vector2(clampf(p.x, cx, cx + 1), clampf(p.y, cy, cy + 1))
			if (p - near).length_squared() < radius * radius:
				return false
	return true


## Fix up after the ship changed under us (a wall built on this cell, a door shut):
## step out of a non-walkable cell to the nearest walkable one, centre in the cell if the body
## overlaps a wall, and re-plan or drop a path that now crosses a non-walkable cell.
func resolve(grid: ShipGrid, door_passable: Callable = Callable()) -> void:
	if not Pathfinder.walkable(grid, cell(), door_passable):
		var n := Pathfinder.nearest_walkable(grid, pos, door_passable)
		if n == Pathfinder.NO_CELL:
			return
		pos = Vector2(n) + Vector2(0.5, 0.5)
	elif not fits(grid, pos, door_passable, RADIUS - 0.01):
		pos = Vector2(cell()) + Vector2(0.5, 0.5)
	for c in path:
		if not Pathfinder.walkable(grid, c, door_passable):
			if not go_to(grid, path.back(), door_passable):
				path.clear()
			break
