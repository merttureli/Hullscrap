extends "res://tests/base_test.gd"

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const GridTests = preload("res://tests/test_pathfinder.gd")


func _corridor() -> ShipGrid:  # 2 cells wide, 12 long: body spots (anchors) x 0..10 on y = 1
	return GridTests.grid_from(["############", "............", "............", "############"])


func _room() -> ShipGrid:  # floor x 1..8, y 1..6
	return GridTests.grid_from([
		"##########",
		"#........#",
		"#........#",
		"#........#",
		"#........#",
		"#........#",
		"#........#",
		"##########",
	])


## A person whose body (2x2) has its top-left cell on `anchor`.
func _at(anchor: Vector2i) -> CrewMember:
	return CrewMember.new("T", Pathfinder.centre_of(anchor))


func test_cell_is_floor_of_pos() -> void:
	var m := CrewMember.new("T", Vector2(2.99, 4.0))
	eq(m.cell(), Vector2i(2, 4), "floor of pos: the cell under the centre of the body")
	eq(_at(Vector2i(3, 1)).pos, Vector2(4, 2), "a body centre is its anchor plus (1, 1)")


func test_the_body_covers_the_four_cells_round_the_centre() -> void:
	var m := _at(Vector2i(3, 1))
	eq(m.anchor(), Vector2i(3, 1), "anchor is the top-left cell")
	eq(m.body_cells(), [Vector2i(3, 1), Vector2i(4, 1), Vector2i(3, 2), Vector2i(4, 2)] as Array[Vector2i], "2x2 cells")
	m.pos = Vector2(4.4, 2.4)
	eq(m.anchor(), Vector2i(3, 1), "still the nearest whole-cell spot")
	m.pos = Vector2(4.6, 2.4)
	eq(m.anchor(), Vector2i(4, 1), "the next spot along x")
	eq(m.cell(), Vector2i(4, 2), "the room it breathes is the one under its centre")


func test_step_reaches_target_and_snaps() -> void:
	var g := _corridor()
	var m := _at(Vector2i(1, 1))
	check(m.go_to(g, Vector2i(8, 1)), "route found")
	m.step(0.5)
	check(m.pos.is_equal_approx(Vector2(3.5, 2.0)), "1.5 cells in half a second at speed 3, got %s" % m.pos)
	check(not m.path.is_empty(), "still walking")
	for i in 100:
		m.step(0.1)
	eq(m.pos, Vector2(9, 2), "snapped to the final body centre")
	eq(m.anchor(), Vector2i(8, 1), "standing on the target")
	check(m.path.is_empty(), "path cleared")
	m.step(1.0)
	eq(m.pos, Vector2(9, 2), "stays put once arrived")


func test_one_long_step_walks_the_whole_path() -> void:
	var g := _corridor()
	var m := _at(Vector2i(0, 1))
	m.go_to(g, Vector2i(10, 1))
	m.step(60.0)
	eq(m.pos, Vector2(11, 2), "overshoot is clamped to the end")
	check(m.path.is_empty(), "path cleared")


func test_go_to_unreachable_keeps_the_path() -> void:
	var g := _corridor()
	var m := _at(Vector2i(1, 1))
	check(m.go_to(g, Vector2i(5, 1)), "reachable")
	var before := m.path.duplicate()
	check(not m.go_to(g, Vector2i(5, 0)), "a body spot over a wall is not a destination")
	eq(m.path, before, "failed go_to leaves the path alone")
	var narrow := GridTests.grid_from(["#######", ".......", "#######"])
	check(not _at(Vector2i(1, 1)).go_to(narrow, Vector2i(4, 1)), "no route down a 1-wide corridor")


func test_go_to_starts_from_the_nearest_spot() -> void:
	var g := _corridor()
	var m := CrewMember.new("T", Vector2(3.3, 2.0))  # between spots, not on one
	check(m.go_to(g, Vector2i(8, 1)), "route found")
	eq(m.path[0], Vector2i(2, 1), "first walks to the nearest spot")
	m.step(60.0)
	eq(m.anchor(), Vector2i(8, 1), "and arrives")


func test_walks_around_walls_and_through_doors() -> void:
	var g := GridTests.grid_from([
		"#########",
		"....D....",
		"....D....",
		"#########",
	])
	var m := _at(Vector2i(0, 1))
	check(m.go_to(g, Vector2i(7, 1)), "through the open door")
	m.step(60.0)
	eq(m.anchor(), Vector2i(7, 1), "arrived")
	var m2 := _at(Vector2i(0, 1))
	check(not m2.go_to(g, Vector2i(7, 1), func(_c): return false), "shut door means no route")


func test_move_input_along_a_corridor() -> void:
	var g := _corridor()
	var m := _at(Vector2i(1, 1))
	for i in 30:
		m.move_input(g, Vector2.RIGHT, 1.0 / 60.0)
	check(is_equal_approx(m.pos.x, 2.0 + 30 * 3.0 / 60.0), "3 cells/s, got x=%s" % m.pos.x)
	eq(m.pos.y, 2.0, "no drift sideways")
	eq(m.facing, Vector2.RIGHT, "faces the way it moves")
	m.move_input(g, Vector2.LEFT * 5.0, 1.0 / 60.0)
	check(is_equal_approx(m.pos.x, 3.5 - 0.05), "input length does not change speed")


func test_move_input_diagonal_is_not_faster() -> void:
	var g := _room()
	var m := _at(Vector2i(3, 2))
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
			for c in m.body_cells():
				if g.get_tile(c) != "floor":
					failures.append("body over %s at %s going %s" % [g.get_tile(c), m.pos, dir])
					return
	check(true, "never left the floor")


func test_radius_keeps_the_body_off_the_walls() -> void:
	eq(CrewMember.RADIUS, 0.9, "a body is a little under 2 cells wide")
	var g := _room()  # floor x 1..8, y 1..6
	var m := _at(Vector2i(3, 2))
	for i in 200:
		m.move_input(g, Vector2.RIGHT, 1.0 / 60.0)
	check(m.pos.x <= 9.0 - CrewMember.RADIUS + 0.0001, "stops a body radius short of the east wall, x=%s" % m.pos.x)
	check(m.pos.x > 9.0 - CrewMember.RADIUS - 0.1, "but gets close to it, x=%s" % m.pos.x)
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


func test_two_wide_openings_leave_a_little_room() -> void:
	var g := _corridor()  # floor y 1..2: a body centre must stay within 0.1 of y = 2
	var m := _at(Vector2i(2, 1))
	check(m.fits(g, Vector2(4, 2.09)), "a hair off the middle still fits")
	check(not m.fits(g, Vector2(4, 2.2)), "further off clips the wall")
	check(not m.fits(GridTests.grid_from(["#######", ".......", "#######"]), Vector2(4, 1.5)), "nothing fits a 1-wide corridor")


func test_corner_is_rounded_not_boxed() -> void:
	# A wall pillar at (3,1): its lower-left corner is at (3,2).
	var g := GridTests.grid_from([
		".....",
		"...#.",
		".....",
		".....",
		".....",
	])
	var m := CrewMember.new("T", Vector2(2.0, 3.0))
	check(m.fits(g, Vector2(2.3, 2.7)), "a box would clip the corner cell here; the round body does not")
	check(not m.fits(g, Vector2(2.4, 2.5)), "touching the wall cell")
	check(m.fits(g, Vector2(1.5, 3.0)), "open floor")


func test_cannot_walk_through_a_shut_door_or_into_space() -> void:
	var g := GridTests.grid_from([
		"##########",
		"....D...  ",
		"....D...  ",
		"##########",
	])
	var m := _at(Vector2i(0, 1))
	for i in 120:
		m.move_input(g, Vector2.RIGHT, 1.0 / 60.0, func(_c): return false)
	check(m.pos.x <= 4.0 - CrewMember.RADIUS + 0.0001, "stopped by the shut door, x=%s" % m.pos.x)
	for i in 120:
		m.move_input(g, Vector2.RIGHT, 1.0 / 60.0)
	check(m.pos.x > 5.0, "through once it is passable, x=%s" % m.pos.x)
	for i in 240:
		m.move_input(g, Vector2.RIGHT, 1.0 / 60.0)
	check(m.pos.x <= 8.0 - CrewMember.RADIUS + 0.0001, "empty space beyond the floor stops it, x=%s" % m.pos.x)


func test_walking_at_a_door_a_little_off_line_still_gets_through() -> void:
	# A horizontal wall with a 2-wide door piece in it: cells (4,3) and (5,3) are the door.
	var g := GridTests.grid_from([
		"##########",
		"..........",
		"..........",
		"....DD....",
		"..........",
		"..........",
	])
	for x in 4:
		g.tiles[Vector2i(x, 3)] = "wall"
		g.tiles[Vector2i(6 + x, 3)] = "wall"
	for off in [-0.6, -0.45, -0.2, 0.2, 0.45, 0.6]:
		var m := CrewMember.new("T", Vector2(5.0 + off, 2.0))  # above the door, a little off its middle line (x = 5)
		for i in 120:
			m.move_input(g, Vector2.DOWN, 1.0 / 60.0)
		check(m.pos.y > 4.0, "off by %s: through the door, y=%s" % [off, m.pos.y])
		check(absf(m.pos.x - 5.0) < 0.11, "and lined up on it, x=%s" % m.pos.x)
	var wall := CrewMember.new("T", Vector2(2.0, 2.0))  # nowhere near the door: a wall is a wall
	for i in 120:
		wall.move_input(g, Vector2.DOWN, 1.0 / 60.0)
	check(wall.pos.y <= 3.0 - CrewMember.RADIUS + 0.0001, "walks into a plain wall and stops, y=%s" % wall.pos.y)
	eq(wall.pos.x, 2.0, "without being nudged sideways")


func _door_row() -> ShipGrid:
	# A horizontal wall with a 2-wide door piece in it: cells (4,3) and (5,3) are the door, (3,3) and (6,3) its frame.
	var g := GridTests.grid_from([
		"##########",
		"..........",
		"..........",
		"....DD....",
		"..........",
		"..........",
	])
	for x in 4:
		g.tiles[Vector2i(x, 3)] = "wall"
		g.tiles[Vector2i(6 + x, 3)] = "wall"
	return g


func test_a_door_frame_is_rounded_so_a_body_off_the_line_fits() -> void:
	var g := _door_row()
	var m := CrewMember.new("T", Vector2(5.0, 2.0))
	check(m.fits(g, Vector2(5.4, 3.0)), "0.4 off the door's line, in the doorway: the frame's corner lets it by")
	check(not m.fits(g, Vector2(5.5, 3.0)), "0.5 off: the frame still stops it")
	check(not m.fits(g, Vector2(2.0, 2.4)), "a plain wall keeps the whole radius")
	check(not m.fits(g, Vector2(5.0, 3.0), func(_c): return false), "a shut door is not a frame: it stops the body")


func test_walking_slantwise_at_a_door_gets_through() -> void:
	for dir in [Vector2(1, 1), Vector2(1, 2), Vector2(-1, 2), Vector2(0.3, 1)]:
		var g := _door_row()
		var m := CrewMember.new("T", Vector2(2.5 if dir.x > 0.0 else 7.5, 2.0))
		var through := false
		for i in 360:
			m.move_input(g, dir, 1.0 / 60.0)
			through = through or m.pos.y > 4.2
		check(through, "heading %s: through the door, at %s" % [dir, m.pos])
	var wall := CrewMember.new("T", Vector2(1.0, 2.0))  # slanting into a plain wall far from the door: no way through
	var g2 := _door_row()
	for i in 30:
		wall.move_input(g2, Vector2(0.3, 1), 1.0 / 60.0)
	check(wall.pos.y <= 3.0 - CrewMember.RADIUS + 0.0001, "a plain wall stops it, y=%s" % wall.pos.y)


func test_a_body_in_a_doorway_walks_out_lined_up() -> void:
	var g := _door_row()
	var m := CrewMember.new("T", Vector2(5.35, 2.0))
	for i in 90:
		m.move_input(g, Vector2.DOWN, 1.0 / 60.0)
	check(m.pos.y > 4.0, "through, y=%s" % m.pos.y)
	check(absf(m.pos.x - 5.0) < 0.05, "pulled onto the door's line on the way, x=%s" % m.pos.x)


func test_a_long_frame_cannot_tunnel() -> void:
	var g := _room()
	var m := _at(Vector2i(3, 2))
	m.move_input(g, Vector2.RIGHT, 2.0)  # 6 cells in one frame
	check(m.pos.x <= 9.0 - CrewMember.RADIUS + 0.0001, "still inside, x=%s" % m.pos.x)


func test_resolve_pushes_out_of_a_new_wall() -> void:
	var g := _room()
	var m := _at(Vector2i(3, 2))
	g.tiles[Vector2i(4, 3)] = "wall"  # on one of the four cells of the body
	m.resolve(g)
	check(Pathfinder.body_ok(g, m.anchor()), "moved to a spot where a body fits")
	eq(m.pos, Pathfinder.centre_of(m.anchor()), "on a whole-cell body centre")
	check(not m.body_cells().has(Vector2i(4, 3)), "left the wall cell")
	# A wall built next to us, overlapping the round body but not its four cells.
	var g2 := _room()
	var m2 := CrewMember.new("T", Vector2(4.3, 3.0))
	g2.tiles[Vector2i(5, 3)] = "wall"
	check(not m2.fits(g2, m2.pos), "the wall clips the body")
	m2.resolve(g2)
	check(m2.fits(g2, m2.pos), "body clear of the wall again")
	eq(m2.anchor(), Vector2i(3, 2), "same spot")
	var m3 := _at(Vector2i(3, 2))
	m3.resolve(_room())
	eq(m3.pos, Vector2(4, 3), "nothing in the way: left alone")


func test_resolve_replans_a_blocked_path() -> void:
	var g := GridTests.grid_from([
		".......",
		".......",
		".......",
		".......",
	])
	var m := _at(Vector2i(0, 0))
	m.go_to(g, Vector2i(5, 0))
	g.tiles[Vector2i(3, 0)] = "wall"
	m.resolve(g)
	for a in m.path:
		check(not Pathfinder.body_cells(a).has(Vector2i(3, 0)), "new route avoids the wall: %s" % a)
	eq(m.path.back(), Vector2i(5, 0), "same destination")
	m.step(60.0)
	eq(m.anchor(), Vector2i(5, 0), "arrives")
	var n := _at(Vector2i(0, 0))
	n.go_to(g, Vector2i(1, 0))
	g.tiles[Vector2i(1, 0)] = "wall"
	n.resolve(g)
	check(n.path.is_empty(), "destination walled in: path dropped")
