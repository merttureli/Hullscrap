extends "res://tests/base_test.gd"

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const GridTests = preload("res://tests/test_pathfinder.gd")


func _corridor() -> ShipGrid:
	return GridTests.grid_from(["##########", "..........", "##########"])


func _room() -> ShipGrid:
	return GridTests.grid_from([
		"#######",
		"#.....#",
		"#.....#",
		"#.....#",
		"#######",
	])


func _at(c: Vector2i) -> CrewMember:
	return CrewMember.new("T", Vector2(c) + Vector2(0.5, 0.5))


func test_cell_is_floor_of_pos() -> void:
	var m := CrewMember.new("T", Vector2(2.99, 4.0))
	eq(m.cell(), Vector2i(2, 4), "floor of pos")
	eq(_at(Vector2i(3, 1)).pos, Vector2(3.5, 1.5), "cell centre is c + 0.5")


func test_step_reaches_target_and_snaps() -> void:
	var g := _corridor()
	var m := _at(Vector2i(1, 1))
	check(m.go_to(g, Vector2i(8, 1)), "route found")
	m.step(0.5)
	check(m.pos.is_equal_approx(Vector2(3.0, 1.5)), "1.5 cells in half a second at speed 3, got %s" % m.pos)
	check(not m.path.is_empty(), "still walking")
	for i in 100:
		m.step(0.1)
	eq(m.pos, Vector2(8.5, 1.5), "snapped to the final centre")
	eq(m.cell(), Vector2i(8, 1), "standing on the target")
	check(m.path.is_empty(), "path cleared")
	m.step(1.0)
	eq(m.pos, Vector2(8.5, 1.5), "stays put once arrived")


func test_one_long_step_walks_the_whole_path() -> void:
	var g := _corridor()
	var m := _at(Vector2i(0, 1))
	m.go_to(g, Vector2i(9, 1))
	m.step(60.0)
	eq(m.pos, Vector2(9.5, 1.5), "overshoot is clamped to the end")
	check(m.path.is_empty(), "path cleared")


func test_go_to_unreachable_keeps_the_path() -> void:
	var g := _corridor()
	var m := _at(Vector2i(1, 1))
	check(m.go_to(g, Vector2i(5, 1)), "reachable")
	var before := m.path.duplicate()
	check(not m.go_to(g, Vector2i(5, 0)), "a wall is not a destination")
	eq(m.path, before, "failed go_to leaves the path alone")


func test_walks_around_walls_and_through_doors() -> void:
	var g := GridTests.grid_from([
		"#####",
		"..D..",
		"#####",
	])
	var m := _at(Vector2i(0, 1))
	check(m.go_to(g, Vector2i(4, 1)), "through the open door")
	m.step(60.0)
	eq(m.cell(), Vector2i(4, 1), "arrived")
	var m2 := _at(Vector2i(0, 1))
	check(not m2.go_to(g, Vector2i(4, 1), func(_c): return false), "shut door means no route")


func test_move_input_along_a_corridor() -> void:
	var g := _corridor()
	var m := _at(Vector2i(1, 1))
	for i in 30:
		m.move_input(g, Vector2.RIGHT, 1.0 / 60.0)
	check(is_equal_approx(m.pos.x, 1.5 + 30 * 3.0 / 60.0), "3 cells/s, got x=%s" % m.pos.x)
	eq(m.pos.y, 1.5, "no drift sideways")
	eq(m.facing, Vector2.RIGHT, "faces the way it moves")
	m.move_input(g, Vector2.LEFT * 5.0, 1.0 / 60.0)
	check(is_equal_approx(m.pos.x, 3.0 - 0.05), "input length does not change speed")


func test_move_input_diagonal_is_not_faster() -> void:
	var g := _room()
	var m := _at(Vector2i(2, 1))
	var start := m.pos
	m.move_input(g, Vector2(1, 1), 0.2)
	check(is_equal_approx((m.pos - start).length(), 0.6), "0.6 cells in 0.2s, got %s" % (m.pos - start).length())
	var still := m.pos
	m.move_input(g, Vector2.ZERO, 1.0)
	eq(m.pos, still, "no input, no move")


func test_move_input_into_a_wall_does_not_enter() -> void:
	var g := _room()
	var m := _at(Vector2i(3, 2))
	for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, 1), Vector2(-1, -1)]:
		for i in 120:
			m.move_input(g, dir, 1.0 / 60.0)
			if g.get_tile(m.cell()) != "floor":
				failures.append("walked into %s at %s going %s" % [g.get_tile(m.cell()), m.pos, dir])
				return
	check(true, "never left the floor")


func test_radius_keeps_the_body_off_the_walls() -> void:
	var g := _room()  # floor x 1..5, y 1..3
	var m := _at(Vector2i(3, 2))
	for i in 200:
		m.move_input(g, Vector2.RIGHT, 1.0 / 60.0)
	check(m.pos.x <= 6.0 - CrewMember.RADIUS + 0.0001, "stops a body radius short of the east wall, x=%s" % m.pos.x)
	check(m.pos.x > 6.0 - CrewMember.RADIUS - 0.1, "but gets close to it, x=%s" % m.pos.x)
	for i in 200:
		m.move_input(g, Vector2.UP, 1.0 / 60.0)
	check(m.pos.y >= 1.0 + CrewMember.RADIUS - 0.0001, "and the north wall, y=%s" % m.pos.y)
	check(m.pos.y < 1.0 + CrewMember.RADIUS + 0.1, "close to it, y=%s" % m.pos.y)
	# Sliding: pushing diagonally into the wall still moves along it.
	var slide_from := m.pos.x
	for i in 30:
		m.move_input(g, Vector2(-1, -1), 1.0 / 60.0)
	check(m.pos.x < slide_from - 0.5, "slides along the wall")
	check(m.pos.y >= 1.0 + CrewMember.RADIUS - 0.0001, "without sinking into it")


func test_corner_is_rounded_not_boxed() -> void:
	# An inner corner: the wall cell at (2,0) is diagonal to a body at the cell (1,1) edge.
	var g := GridTests.grid_from([
		"..#",
		"...",
	])
	var m := CrewMember.new("T", Vector2(1.5, 1.5))
	check(m.fits(g, Vector2(1.8, 1.25)), "a box would clip the corner cell here; the round body does not")
	check(not m.fits(g, Vector2(1.95, 1.2)), "touching the wall cell")
	check(m.fits(g, Vector2(1.5, 0.5)), "open floor")


func test_cannot_walk_through_a_shut_door_or_into_space() -> void:
	var g := GridTests.grid_from([
		"#####",
		"..D. ",
		"#####",
	])
	var m := _at(Vector2i(0, 1))
	for i in 120:
		m.move_input(g, Vector2.RIGHT, 1.0 / 60.0, func(_c): return false)
	check(m.pos.x <= 2.0 - CrewMember.RADIUS + 0.0001, "stopped by the shut door, x=%s" % m.pos.x)
	for i in 120:
		m.move_input(g, Vector2.RIGHT, 1.0 / 60.0)
	check(m.pos.x > 3.0, "through once it is passable, x=%s" % m.pos.x)
	for i in 240:
		m.move_input(g, Vector2.RIGHT, 1.0 / 60.0)
	check(m.pos.x <= 4.0 - CrewMember.RADIUS + 0.0001, "empty space beyond the floor stops it, x=%s" % m.pos.x)


func test_a_long_frame_cannot_tunnel() -> void:
	var g := _room()
	var m := _at(Vector2i(3, 2))
	m.move_input(g, Vector2.RIGHT, 2.0)  # 6 cells in one frame
	check(m.pos.x <= 6.0 - CrewMember.RADIUS + 0.0001, "still inside, x=%s" % m.pos.x)


func test_resolve_pushes_out_of_a_new_wall() -> void:
	var g := _room()
	var m := _at(Vector2i(3, 2))
	g.tiles[Vector2i(3, 2)] = "wall"
	m.resolve(g)
	check(Pathfinder.walkable(g, m.cell()), "moved to a walkable cell")
	eq(m.pos, Vector2(m.cell()) + Vector2(0.5, 0.5), "on a cell centre")
	check(m.cell() != Vector2i(3, 2), "left the wall cell")
	# A wall built next to us, overlapping the body but not our cell.
	var g2 := _room()
	var m2 := CrewMember.new("T", Vector2(3.9, 2.5))
	g2.tiles[Vector2i(4, 2)] = "wall"
	m2.resolve(g2)
	check(m2.fits(g2, m2.pos), "body clear of the wall again")
	eq(m2.cell(), Vector2i(3, 2), "same cell")


func test_resolve_replans_a_blocked_path() -> void:
	var g := GridTests.grid_from([
		".....",
		".....",
	])
	var m := _at(Vector2i(0, 0))
	m.go_to(g, Vector2i(4, 0))
	g.tiles[Vector2i(2, 0)] = "wall"
	m.resolve(g)
	check(not m.path.has(Vector2i(2, 0)), "new route avoids the wall")
	eq(m.path.back(), Vector2i(4, 0), "same destination")
	m.step(60.0)
	eq(m.cell(), Vector2i(4, 0), "arrives")
	var n := _at(Vector2i(0, 0))
	n.go_to(g, Vector2i(1, 0))
	g.tiles[Vector2i(1, 0)] = "wall"
	n.resolve(g)
	check(n.path.is_empty(), "destination walled in: path dropped")
