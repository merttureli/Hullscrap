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


## Every row and column of `rows` made `k` times as many: a one-cell corridor becomes k cells wide.
static func scaled(rows: Array, k := 2) -> Array:
	var out := []
	for row in rows:
		var wide := ""
		for ch in str(row):
			wide += ch.repeat(k)
		for i in k:
			out.append(wide)
	return out


## Body anchors on the shortest route by plain breadth-first search, 0 when unreachable.
func _bfs(g: ShipGrid, a: Vector2i, b: Vector2i, dp: Callable = Callable()) -> int:
	if not Pathfinder.body_ok(g, a, dp) or not Pathfinder.body_ok(g, b, dp):
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
			if not dist.has(c + d) and Pathfinder.body_ok(g, c + d, dp):
				dist[c + d] = dist[c] + 1
				queue.append(c + d)
	return 0


func _is_route(g: ShipGrid, p: Array[Vector2i], a: Vector2i, b: Vector2i) -> bool:
	if p.is_empty() or p[0] != a or p[p.size() - 1] != b:
		return false
	for i in p.size():
		if not Pathfinder.body_ok(g, p[i]):
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


func test_a_body_needs_all_four_cells() -> void:
	var g := grid_from([
		"#####",
		"#...#",
		"#..##",
		"#####",
	])
	check(Pathfinder.body_ok(g, Vector2i(1, 1)), "2x2 of floor")
	check(not Pathfinder.body_ok(g, Vector2i(2, 1)), "a wall under one corner")
	check(not Pathfinder.body_ok(g, Vector2i(0, 0)), "a wall all round")
	check(not Pathfinder.body_ok(g, Vector2i(9, 9)), "far outside")
	eq(Pathfinder.body_cells(Vector2i(1, 1)), [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)] as Array[Vector2i], "the four cells")
	eq(Pathfinder.centre_of(Vector2i(1, 1)), Vector2(2, 2), "centre is the anchor plus (1, 1)")
	eq(Pathfinder.anchor_of(Vector2(2.2, 1.9)), Vector2i(1, 1), "anchor of the body round a point")
	var shut := func(_c): return false
	var d := grid_from(["..", ".D"])
	check(Pathfinder.body_ok(d, Vector2i.ZERO), "a door passes by default")
	check(not Pathfinder.body_ok(d, Vector2i.ZERO, shut), "one shut door cell blocks the body")


func test_a_one_wide_corridor_blocks_a_body() -> void:
	var g := grid_from(["#######", ".......", "#######"])
	check(Pathfinder.walkable(g, Vector2i(3, 1)), "a single cell could walk it")
	eq(Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(4, 1)).size(), 0, "no body spot in it")
	eq(Pathfinder.nearest_walkable(g, Vector2(3, 1.5)), Pathfinder.NO_CELL, "none to stand on")


func test_a_two_wide_corridor_passes() -> void:
	var g := grid_from(["############", "............", "............", "############"])
	var p := Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(10, 1))
	eq(p.size(), 11, "corridor of 12 cells: 11 body spots")
	check(_is_route(g, p, Vector2i(0, 1), Vector2i(10, 1)), "valid route")
	eq(Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(10, 1)).size(), 0, "a spot in the wall is no start")
	# A 2-wide corridor that narrows to 1 closes behind the bend.
	var t := grid_from(["#########", "........#", "........#", "#######.#", "#######.#"])
	eq(Pathfinder.find_path(t, Vector2i(0, 1), Vector2i(6, 1)).size(), 7, "the room part is open")
	eq(Pathfinder.find_path(t, Vector2i(0, 1), Vector2i(6, 3)).size(), 0, "but the 1-wide tail is not")


func test_a_two_wide_door_passes() -> void:
	var g := grid_from([
		"#########",
		"....D....",
		"....D....",
		"#########",
	])
	var p := Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(7, 1))
	eq(p.size(), 8, "door is part of the route")
	check(p.has(Vector2i(3, 1)) and p.has(Vector2i(4, 1)), "bodies overlap the door cells on the way")
	var gap := grid_from([
		"#########",
		"....D....",
		"####.####",
		"#########",
	])
	eq(Pathfinder.find_path(gap, Vector2i(0, 0), Vector2i(7, 0)).size(), 0, "a 1-wide door is too narrow")
	check(not Pathfinder.body_ok(gap, Vector2i(3, 1)), "no body spot in it")


func test_straight_corridor() -> void:
	var g := grid_from(["############", "............", "............", "############"])
	var p := Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(10, 1))
	eq(p[0], Vector2i(0, 1), "starts at from")
	eq(p[10], Vector2i(10, 1), "ends at to")
	eq(Pathfinder.find_path(g, Vector2i(3, 1), Vector2i(3, 1)), [Vector2i(3, 1)] as Array[Vector2i], "same spot is a one-spot path")
	var back := Pathfinder.find_path(g, Vector2i(10, 1), Vector2i(0, 1))
	eq(back.size(), 11, "works in reverse")


func test_around_a_wall() -> void:
	var g := grid_from([
		"........",
		"........",
		"..####..",
		"........",
		"........",
	])
	var p := Pathfinder.find_path(g, Vector2i(3, 0), Vector2i(3, 3))
	eq(p.size(), 10, "must go round the wall block")
	check(_is_route(g, p, Vector2i(3, 0), Vector2i(3, 3)), "valid route")
	for a in p:
		check(not Pathfinder.body_cells(a).has(Vector2i(3, 2)), "never over the wall at %s" % a)


func test_through_a_door() -> void:
	var g := grid_from([
		"#########",
		"....D....",
		"....D....",
		"#########",
	])
	var open := func(_c): return true
	eq(Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(7, 1), open).size(), 8, "explicitly passable door")
	var to_door := Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(3, 1))
	eq(to_door.size(), 4, "a body standing on a door can be the destination")


func test_no_path_through_a_shut_door() -> void:
	var g := grid_from([
		"#########",
		"....D....",
		"....D....",
		"#########",
	])
	var shut := func(_c): return false
	eq(Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(7, 1), shut).size(), 0, "shut door blocks the corridor")
	eq(Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(3, 1), shut).size(), 0, "nor can you stand in it")
	eq(Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(2, 1), shut).size(), 3, "same side still works")
	var closed := {Vector2i(4, 2): true}  # one cell of the piece is enough to block
	var by_cell := func(c): return not closed.has(c)
	eq(Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(7, 1), by_cell).size(), 0, "the callable gets the door cell")
	closed.clear()
	eq(Pathfinder.find_path(g, Vector2i(0, 1), Vector2i(7, 1), by_cell).size(), 8, "opens again")


func test_no_path_into_wall_or_space() -> void:
	var g := grid_from([
		"#......",
		".......",
		"..#....",
		".......",
		".....  ",
	])
	eq(Pathfinder.find_path(g, Vector2i(3, 0), Vector2i(0, 0)).size(), 0, "to a wall")
	eq(Pathfinder.find_path(g, Vector2i(1, 1), Vector2i(3, 0)).size(), 0, "from a body spot with a wall under it")
	eq(Pathfinder.find_path(g, Vector2i(3, 0), Vector2i(4, 3)).size(), 0, "to space inside the grid")
	eq(Pathfinder.find_path(g, Vector2i(3, 0), Vector2i(9, 9)).size(), 0, "to a cell off the grid")
	eq(Pathfinder.find_path(g, Vector2i(4, 3), Vector2i(3, 0)).size(), 0, "from space")
	var split := grid_from(["..#..", "..#.."])
	eq(Pathfinder.find_path(split, Vector2i(0, 0), Vector2i(3, 0)).size(), 0, "walled off")


func test_same_path_twice() -> void:
	var g := grid_from([
		"........",
		"........",
		"..####..",
		"........",
		"........",
	])
	var a := Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(6, 3))
	var b := Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(6, 3))
	eq(a, b, "identical on repeat")
	eq(a.size(), 10, "still shortest")
	# Pinned tie-break: in an open room, equal f prefers lower h, then lower (y, x).
	var room := grid_from(["....", "....", "....", "...."])
	var want: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)]
	eq(Pathfinder.find_path(room, Vector2i(0, 0), Vector2i(2, 2)), want, "tie-break order")


func test_optimal_on_a_small_maze() -> void:
	var g := grid_from(scaled([
		".#...",
		".#.#.",
		".#.#.",
		"...#.",
	]))
	var a := Vector2i(0, 0)
	var b := Vector2i(8, 0)
	var p := Pathfinder.find_path(g, a, b)
	eq(p.size(), _bfs(g, a, b), "the only way round the maze, as short as breadth-first search finds it")
	check(_is_route(g, p, a, b), "valid route")
	# Every pair of body spots in a bigger maze agrees with breadth-first search.
	var maze := grid_from(scaled([
		"..#......",
		".##.####.",
		"....#....",
		"####.#.##",
		"....#.#..",
		".####.#.#",
		"......#..",
	]))
	var spots: Array[Vector2i] = []
	for c in maze.tiles:
		if Pathfinder.body_ok(maze, c):
			spots.append(c)
	var bad := 0
	var reachable := 0
	for i in range(0, spots.size(), 3):  # every third spot as a start, every spot as a goal
		for q in spots:
			var path := Pathfinder.find_path(maze, spots[i], q)
			var want := _bfs(maze, spots[i], q)
			reachable += int(want > 0)
			if path.size() != want or (not path.is_empty() and not _is_route(maze, path, spots[i], q)):
				bad += 1
	check(reachable > 100, "the maze has routes to compare (%d)" % reachable)
	eq(bad, 0, "pairs where A* differs from breadth-first search")


func test_optimal_with_doors() -> void:
	var g := grid_from(scaled([
		"#D###",
		".....",
		"#D#D#",
		".....",
	]))
	var closed := {}  # the shut door: every cell of the one at (1, 2) in the unscaled map
	for c in [Vector2i(2, 4), Vector2i(3, 4), Vector2i(2, 5), Vector2i(3, 5)]:
		closed[c] = true
	var dp := func(c): return not closed.has(c)
	var spots: Array[Vector2i] = []
	for c in g.tiles:
		if Pathfinder.body_ok(g, c):
			spots.append(c)
	for a in spots:
		for b in spots:
			var n := Pathfinder.find_path(g, a, b, dp).size()
			if n != _bfs(g, a, b, dp):
				failures.append("door maze %s -> %s: A* %d, BFS %d" % [a, b, n, _bfs(g, a, b, dp)])
	check(Pathfinder.find_path(g, Vector2i(0, 2), Vector2i(8, 6)).size() > 0, "all doors open: a way through")


func test_big_open_ship_is_fast_enough() -> void:
	var row := ".".repeat(64)
	var rows := []
	for i in 64:
		rows.append(row)
	var g := grid_from(rows)
	var t := Time.get_ticks_msec()
	var p := Pathfinder.find_path(g, Vector2i(0, 0), Vector2i(62, 62))
	eq(p.size(), 125, "corner to corner on 64x64")
	check(Time.get_ticks_msec() - t < 1000, "64x64 search under a second")


func test_nearest_walkable() -> void:
	var g := grid_from([
		"#####",
		"#...#",
		"#...#",
		"#####",
	])
	eq(Pathfinder.nearest_walkable(g, Vector2(2.4, 2.0)), Vector2i(1, 1), "the body centre nearest the point wins")
	eq(Pathfinder.nearest_walkable(g, Vector2(2.5, 2.0)), Vector2i(1, 1), "a tie goes to the lower x")
	eq(Pathfinder.nearest_walkable(g, Vector2(3.4, 2.0)), Vector2i(2, 1), "the other spot")
	eq(Pathfinder.nearest_walkable(g, Vector2(2.5, 2.0), Callable(), Vector2i(1, 1)), Pathfinder.NO_CELL, "both spots overlap a body on (1,1)")
	var wide := grid_from(["#######", "#.....#", "#.....#", "#######"])
	eq(Pathfinder.nearest_walkable(wide, Vector2(2.0, 2.0), Callable(), Vector2i(1, 1)), Vector2i(3, 1), "the nearest spot clear of that body")
	eq(Pathfinder.nearest_walkable(g, Vector2(0.2, 2.9)), Vector2i(1, 1), "from outside the room")
	eq(Pathfinder.nearest_walkable(grid_from(["###"]), Vector2(1, 0)), Pathfinder.NO_CELL, "none at all")
