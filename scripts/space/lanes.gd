extends RefCounted
## Walk lanes of a ship's rooms: can a 2x2 crew body walk between every door of a room? Parts count as solid here (they
## stand in the way of a body on the boarding site, scripts/board/wreck_site.gd). Used by the generator to keep corridors
## clear (shipgen.gd) and by the tests to measure it. Everything is static; no nodes.

const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


static func _open(grid, comps, c: Vector2i) -> bool:
	return Pathfinder.walkable(grid, c) and comps.at(c) < 0 and comps.wreck_at(c) < 0


## The anchors (top-left cells of a body) that sit square against door piece `piece`, one on each side.
static func _ports(piece: Array) -> Array[Vector2i]:
	var m: Vector2i = piece[0]
	for c in piece:
		m = m.min(c)
	if piece.size() > 1 and piece[0].x == piece[1].x:  # a door in a vertical wall: the way through is sideways
		return [m + Vector2i(-2, 0), m + Vector2i(1, 0)]
	return [m + Vector2i(0, -2), m + Vector2i(0, 1)]


## Is the room made of floor `cells` (a set) cut off: a door a body cannot stand at, or two doors it cannot walk between?
## (A room with one door that a part fills is not: nobody walks there.)
## `doors` are the door pieces (arrays of cells) on the room's wall.
static func room_blocked(grid, comps, cells: Dictionary, doors: Array) -> bool:
	var ports: Array[Vector2i] = []
	for piece in doors:
		var mine: Array[Vector2i] = []
		for a in _ports(piece):
			if cells.has(a) and cells.has(a + Vector2i.ONE) and cells.has(a + Vector2i(1, 0)) and cells.has(a + Vector2i(0, 1)):
				mine.append(a)
		ports.append_array(mine)
	if ports.is_empty():
		return false
	var seen := {ports[0]: true}
	var todo: Array[Vector2i] = [ports[0]]
	var open := {}  # cell -> _open, asked once per cell
	if not _body(grid, comps, cells, ports[0], open):
		if ports.size() == 1:  # one door into a room a part fills (a turret): there is no walk to cut, unless a body fits somewhere else
			for a in cells:
				if _body(grid, comps, cells, a, open):
					return true
			return false
		return true
	while not todo.is_empty():
		var a: Vector2i = todo.pop_back()
		for d in SIDES:
			var n := a + d
			if not seen.has(n) and _body(grid, comps, cells, n, open):
				seen[n] = true
				todo.append(n)
	for p in ports:
		if not seen.has(p):
			return true
	return false


static func _body(grid, comps, cells: Dictionary, a: Vector2i, open: Dictionary) -> bool:
	for y in 2:
		for x in 2:
			var c := a + Vector2i(x, y)
			if not cells.has(c):
				return false
			if not open.has(c):
				open[c] = _open(grid, comps, c)
			if not open[c]:
				return false
	return true


## The door pieces on the wall of the rectangle `r` (its ring of cells just outside).
static func doors_round(grid, r: Rect2i) -> Array:
	var out: Array = []
	var seen := {}
	var ring: Array[Vector2i] = []
	for x in range(r.position.x, r.end.x):
		ring.append(Vector2i(x, r.position.y - 1))
		ring.append(Vector2i(x, r.end.y))
	for y in range(r.position.y, r.end.y):
		ring.append(Vector2i(r.position.x - 1, y))
		ring.append(Vector2i(r.end.x, y))
	for c in ring:
		if not seen.has(c):
			var piece: Array[Vector2i] = grid.door_piece(c)
			if not piece.is_empty():
				for p in piece:
					seen[p] = true
				out.append(piece)
	return out


## The cells (a set) and the door pieces of the rectangle `r`: what rect_blocked reads. Only tiles change them, not parts.
static func rect_room(grid, r: Rect2i) -> Array:
	var cells := {}
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			cells[Vector2i(x, y)] = true
	return [cells, doors_round(grid, r)]


## Is the room `r` (a rectangle of floor) cut off? `room`: its rect_room(), when the caller has it and no tile changed since.
static func rect_blocked(grid, comps, r: Rect2i, room := []) -> bool:
	if room.is_empty():
		room = rect_room(grid, r)
	return room_blocked(grid, comps, room[0], room[1])


## How many rooms of `ship` (floor regions between walls and doors) are cut off.
static func blocked(ship) -> int:
	var grid = ship.grid
	var comps = ship.components
	var seen := {}
	var n := 0
	var keys: Array = grid.tiles.keys()
	keys.sort()
	for c in keys:
		if seen.has(c) or not Pathfinder.walkable(grid, c) or grid.tile_flag(grid.get_tile(c), "door"):
			continue
		var cells := {c: true}
		var todo: Array[Vector2i] = [c]
		var doors := {}
		while not todo.is_empty():
			var a: Vector2i = todo.pop_back()
			for d in SIDES:
				var b := a + d
				if cells.has(b):
					continue
				var id: String = grid.get_tile(b)
				if id == "":
					continue
				if grid.tile_flag(id, "door"):
					doors[grid.door_piece(b)[0]] = grid.door_piece(b)
				elif Pathfinder.walkable(grid, b):
					cells[b] = true
					todo.append(b)
		seen.merge(cells)
		if cells.size() >= 4 and room_blocked(grid, comps, cells, doors.values()):
			n += 1
	return n
