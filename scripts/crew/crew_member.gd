extends RefCounted
## One person walking inside the ship. Plain data and rules: no nodes, no drawing.
## `pos` is the centre of the body in cell units. The body is 2x2 cells (see Pathfinder.BODY): it
## sits on the four cells round `pos`, and collides as a circle of RADIUS (a little under a cell,
## so a 2-wide opening lets it through). NPCs follow a `path` of body anchors (go_to + step), whose
## body centre is the anchor plus (1, 1); the player's soldier moves directly (move_input).

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const RADIUS := 0.9  ## body radius in cells, used for wall collision (a body is 2 cells wide)
const MAX_SUBSTEP := 0.2  ## longest single move in cells, so a long frame cannot skip over a wall

var name := ""
var pos := Vector2.ZERO
var speed := 3.0  ## cells per second
var facing := Vector2.DOWN
var path: Array[Vector2i] = []


func _init(p_name := "", p_pos := Vector2.ZERO) -> void:
	name = p_name
	pos = p_pos


## The cell under the centre of the body (the room whose air this person breathes).
func cell() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


## The top-left cell of the 2x2 cells the body covers.
func anchor() -> Vector2i:
	return Pathfinder.anchor_of(pos)


## The 2x2 cells the body covers.
func body_cells() -> Array[Vector2i]:
	return Pathfinder.body_cells(anchor())


## Walk until the body sits on anchor `target` (see Pathfinder), along the shortest path from the
## nearest usable anchor. Returns false (and keeps the current path) when there is no route.
func go_to(grid: ShipGrid, target: Vector2i, door_passable: Callable = Callable()) -> bool:
	var from := Pathfinder.nearest_walkable(grid, pos, door_passable)
	var p := Pathfinder.find_path(grid, from, target, door_passable)
	if p.is_empty():
		return false
	path = p
	return true


## Advance along the path, centre to centre. Ends exactly on the last anchor's body centre.
func step(dt: float) -> void:
	var left := speed * dt
	while left > 0.0 and not path.is_empty():
		var to := Pathfinder.centre_of(path[0])
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
## Doorway assist: walking straight at an opening a little off line, the body drifts sideways onto
## the line that lets it through (a 2-wide door leaves only 0.2 cells to spare).
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
		elif d.y == 0.0:
			_slide_to_lane(grid, Vector2(d.x, 0.0), door_passable)
		if fits(grid, pos + Vector2(0.0, d.y), door_passable):
			pos.y += d.y
		elif d.x == 0.0:
			_slide_to_lane(grid, Vector2(0.0, d.y), door_passable)


## Blocked head-on while moving by `step` (along one axis): nudge sideways, at most `step` long,
## toward the nearest whole-number line from which the step would fit.
func _slide_to_lane(grid: ShipGrid, step: Vector2, door_passable: Callable) -> void:
	var a := 0 if step.x != 0.0 else 1  # the axis we move along; 1 - a is the sideways one
	var side := 1 - a
	var lanes := [floorf(pos[side]), ceilf(pos[side])]
	if lanes[0] == lanes[1]:
		return  # already on a line: a real wall
	if pos[side] - lanes[0] > lanes[1] - pos[side]:
		lanes.reverse()  # nearest first
	for lane: float in lanes:
		var ahead := pos + step
		ahead[side] = lane
		if not fits(grid, ahead, door_passable):
			continue
		var to := pos
		to[side] += clampf(lane - pos[side], -absf(step[a]), absf(step[a]))
		if fits(grid, to, door_passable):
			pos = to
		return


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


## Fix up after the ship changed under us (a wall built on the body, a door shut): when the body
## overlaps a non-walkable cell, move it onto the nearest usable anchor, then re-plan or drop a
## path that now crosses an anchor the body can't stand on.
func resolve(grid: ShipGrid, door_passable: Callable = Callable()) -> void:
	if not fits(grid, pos, door_passable, RADIUS - 0.01):
		var n := Pathfinder.nearest_walkable(grid, pos, door_passable)
		if n == Pathfinder.NO_CELL:
			return
		pos = Pathfinder.centre_of(n)
	for c in path:
		if not Pathfinder.body_ok(grid, c, door_passable):
			if not go_to(grid, path.back(), door_passable):
				path.clear()
			break
