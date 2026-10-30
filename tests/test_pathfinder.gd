extends "res://tests/base_test.gd"

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")


## A grid from text rows: '#' wall, '.' floor, 'D' door, anything else is empty space.
## Tiles are written directly, so doors skip the "walls on both sides" placement rule.
static func grid_from(rows: Array) -> ShipGrid:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(str(rows[0]).length(), rows.size()), defs)
	var ids := {"#": "wall", ".": "floor", "D": "door"}
	for y in rows.size():
		for x in str(rows[y]).length():
			var id: String = ids.get(str(rows[y])[x], "")
			if id != "":
				g.tiles[Vector2i(x, y)] = id
	return g


## Cells on the shortest route by plain breadth-first search, 0 when unreachable.
func _bfs(g: ShipGrid, a: Vector2i, b: Vector2i, dp: Callable = Callable()) -> int:
	if not Pathfinder.walkable(g, a, dp) or not Pathfinder.walkable(g, b, dp):
		return 0
	var dist := {a: 1}
	var queue: Array[Vector2i] = [a]
	var i := 0
	while i < queue.size():
		var c := queue[i]
		i += 1
		if c == b:
			return dist[c]
		for d in ShipGrid.SIDES:
			if not dist.has(c + d) and Pathfinder.walkable(g, c + d, dp):
				dist[c + d] = dist[c] + 1
				queue.append(c + d)
	return 0


func _is_route(g: ShipGrid, p: Array[Vector2i], a: Vector2i, b: Vector2i) -> bool:
	if p.is_empty() or p[0] != a or p[p.size() - 1] != b:
		return false
	for i in p.size():
		if not Pathfinder.walkable(g, p[i]):
			return false
		if i > 0 and absi(p[i].x - p[i - 1].x) + absi(p[i].y - p[i - 1].y) != 1:
			return false
	return true


func test_walkable_cells() -> void:
	var g := grid_from(["#.D "])
	check(not Pathfinder.walkable(g, Vector2i(0, 0)), "wall blocks")
	check(Pathfinder.walkable(g, Vector2i(1, 0)), "floor is walkable")
	check(Pathfinder.walkable(g, Vector2i(2, 0)), "door passes by default")
	check(not Pathfinder.walkable(g, Vector2i(2, 0), func(_c): return false), "shut door blocks")
	check(Pathfinder.walkable(g, Vector2i(2, 0), func(_c): return true), "open door passes")
	check(not Pathfinder.walkable(g, Vector2i(3, 0)), "empty space blocks")
	check(not Pathfinder.walkable(g, Vector2i(-4, 9)), "far outside blocks")
	var bare := ShipGrid.new(Vector2i(3, 3))
	bare.tiles[Vector2i(1, 1)] = "anything"
	check(Pathfinder.walkable(bare, Vector2i(1, 1)), "a grid without rules walks every tile")


func test_straight_corridor() -> void:
	var g := grid_from(["#######", "......."  , "#######"])
	var p := Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(6, 1))
	eq(p.size(), 7, "corridor length")
	eq(p[0], Vector2i(0, 1), "starts at from")
	eq(p[6], Vector2i(6, 1), "ends at to")
	check(_is_route(g, p, Vector2i(0, 1), Vector2i(6, 1)), "valid route")
	eq(Pathfinder.find_path(g, Vector2i(3, 1), Vector2i(3, 1)), [Vector2i(3, 1)] as Array[Vector2i], "same cell is a one-cell path")
	var back := Pathfinder.find_path(g, Vector2i(6, 1), Vector2i(0, 1))
	eq(back.size(), 7, "works in reverse")


func test_around_a_wall() -> void:
	var g := grid_from([
		".....",
		".###.",
		".....",
	])
	var p := Pathfinder.find_path(g, Vector2i(2, 0), Vector2i(2, 2))
	eq(p.size(), 7, "must go round the wall block")
	check(_is_route(g, p, Vector2i(2, 0), Vector2i(2, 2)), "valid route")
	check(not p.has(Vector2i(2, 1)), "never through the wall")


func test_through_a_door() -> void:
	var g := grid_from([
		"#####",
		"..D..",
		"#####",
	])
	var p := Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(4, 1))
	eq(p.size(), 5, "door is part of the route")
	check(p.has(Vector2i(2, 1)), "goes through the door")
	var open := func(_c): return true
	eq(Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(4, 1), open).size(), 5, "explicitly passable door")
	var to_door := Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(2, 1))
	eq(to_door.size(), 3, "a door cell can be the destination")


func test_no_path_through_a_shut_door() -> void:
	var g := grid_from([
		"#####",
		"..D..",
		"#####",
	])
	var shut := func(_c): return false
	eq(Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(4, 1), shut).size(), 0, "shut door blocks the corridor")
	eq(Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(2, 1), shut).size(), 0, "nor can you stand in it")
	eq(Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(1, 1), shut).size(), 2, "same side still works")
	var closed := {Vector2i(2, 1): true}
	var by_cell := func(c): return not closed.has(c)
	eq(Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(4, 1), by_cell).size(), 0, "the callable gets the door cell")
	closed.clear()
	eq(Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(4, 1), by_cell).size(), 5, "opens again")


func test_no_path_into_wall_or_space() -> void:
	var g := grid_from([
		"#...",
		".#. ",
		"....",
	])
	eq(Pathfinder.find_path(g, Vector2i(1, 0), Vector2i(0, 0)).size(), 0, "to a wall")
	eq(Pathfinder.find_path(g, Vector2i(1, 1), Vector2i(1, 0)).size(), 0, "from a wall")
	eq(Pathfinder.find_path(g, Vector2i(1, 0), Vector2i(3, 1)).size(), 0, "to space inside the grid")
	eq(Pathfinder.find_path(g, Vector2i(1, 0), Vector2i(9, 9)).size(), 0, "to a cell off the grid")
	eq(Pathfinder.find_path(g, Vector2i(3, 1), Vector2i(1, 0)).size(), 0, "from space")
	var split := grid_from([".#."])
	eq(Pathfinder.find_path(split, Vector2i(0, 0), Vector2i(2, 0)).size(), 0, "walled off")


func test_same_path_twice() -> void:
	var g := grid_from([
		"........",
		"........",
		"..####..",
		"........",
		"........",
	])
	var a := Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(7, 4))
	var b := Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(7, 4))
	eq(a, b, "identical on repeat")
	eq(a.size(), 12, "still shortest")
	# Pinned tie-break: in an open room, equal f prefers lower h, then lower (y, x).
	var room := grid_from(["...", "...", "..."])
	var want: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)]
	eq(Pathfinder.find_path(room, Vector2i(0, 0), Vector2i(2, 2)), want, "tie-break order")


func test_optimal_on_a_small_maze() -> void:
	var g := grid_from([
		".#...",
		".#.#.",
		".#.#.",
		"...#.",
	])
	var p := Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(4, 0))
	eq(p.size(), 11, "the only way round the maze")
	check(_is_route(g, p, Vector2i(0, 0), Vector2i(4, 0)), "valid route")
	# Every pair of cells in a bigger maze agrees with breadth-first search.
	var maze := grid_from([
		"..#......",
		".##.####.",
		"....#....",
		"####.#.##",
		"....#.#..",
		".####.#.#",
		"......#..",
	])
	var cells: Array[Vector2i] = []
	for c in maze.tiles:
		if maze.tiles[c] != "wall":
			cells.append(c)
	var bad := 0
	for a in cells:
		for b in cells:
			var path := Pathfinder.find_path(maze, a, b)
			if path.size() != _bfs(maze, a, b) or (not path.is_empty() and not _is_route(maze, path, a, b)):
				bad += 1
	eq(bad, 0, "pairs where A* differs from breadth-first search")


func test_optimal_with_doors() -> void:
	var g := grid_from([
		"#D###",
		".....",
		"#D#D#",
		".....",
	])
	var closed := {Vector2i(1, 2): true}
	var dp := func(c): return not closed.has(c)
	for a in g.tiles:
		for b in g.tiles:
			if g.tiles[a] == "wall" or g.tiles[b] == "wall":
				continue
			var n := Pathfinder.find_path(g, a, b, dp).size()
			if n != _bfs(g, a, b, dp):
				failures.append("door maze %s -> %s: A* %d, BFS %d" % [a, b, n, _bfs(g, a, b, dp)])


func test_big_open_ship_is_fast_enough() -> void:
	var row := ".".repeat(64)
	var rows := []
	for i in 64:
		rows.append(row)
	var g := grid_from(rows)
	var t := Time.get_ticks_msec()
	var p := Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(63, 63))
	eq(p.size(), 127, "corner to corner on 64x64")
	check(Time.get_ticks_msec() - t < 1000, "64x64 search under a second")


func test_nearest_walkable() -> void:
	var g := grid_from([
		"#.#",
		"#..",
		"###",
	])
	eq(Pathfinder.nearest_walkable(g, Vector2(1.5, 1.5)), Vector2i(1, 1), "centre of the cell wins")
	eq(Pathfinder.nearest_walkable(g, Vector2(1.5, 1.5), Callable(), Vector2i(1, 1)), Vector2i(1, 0), "tie goes to lower y")
	eq(Pathfinder.nearest_walkable(g, Vector2(0.2, 2.9)), Vector2i(1, 1), "from outside the room")
	eq(Pathfinder.nearest_walkable(grid_from(["###"]), Vector2(1, 0)), Pathfinder.NO_CELL, "none at all")
