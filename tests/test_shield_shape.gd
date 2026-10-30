extends "res://tests/base_test.gd"
## The outline of a shield bubble: the convex hull of the solid cells inflated 1.5 cells with rounded
## corners (shield_shape.gd), its point and segment tests and its sectors.

const Shape = preload("res://scripts/combat/shield_shape.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func _rect(x0: int, y0: int, w: int, h: int) -> Array:
	var out := []
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			out.append(Vector2i(x, y))
	return out


## The four test ships: a rectangle, an L, a wedge (a right triangle with a long slope) and a long thin ship.
func _shapes() -> Dictionary:
	var l := _rect(0, 0, 4, 12)
	l.append_array(_rect(4, 8, 8, 4))
	var wedge := []
	for y in 14:
		for x in range(0, 2 + y):
			wedge.append(Vector2i(x, y))
	return {"rectangle": _rect(3, 2, 12, 6), "L": l, "wedge": wedge, "thin": _rect(0, 0, 60, 2)}


func _tile_ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	return Ship.new("t", g)


func test_the_hull_of_points_is_convex_and_has_no_spare_points() -> void:
	var h := Shape.hull_of(PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(4, 0), Vector2(4, 3), Vector2(2, 3), Vector2(0, 3), Vector2(2, 1), Vector2(0, 0)]))
	eq(h.size(), 4, "a rectangle has four corners: the points on its sides and inside are dropped")
	for i in h.size():
		check((h[(i + 1) % 4] - h[i]).cross(h[(i + 2) % 4] - h[(i + 1) % 4]) > 0.0, "all turns the same way")


func test_the_shape_holds_every_solid_cell_with_a_margin_of_one_and_a_half_cells() -> void:
	var all := _shapes()
	for key in all:
		var cells: Array = all[key]
		var s = Shape.from_cells(cells)
		for c in cells:
			var m: float = s.margin(Vector2(c) + Vector2(0.5, 0.5))
			check(m >= Shape.INFLATE - 1e-6, "%s: cell %s centre has margin %.3f" % [key, str(c), m])
			check(s.contains(Vector2(c) + Vector2(0.5, 0.5)), "%s: cell %s is inside" % [key, str(c)])
		for c in cells:  # and the corners of the cells too: the whole cell counts
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
				check(s.margin(Vector2(c) + corner) >= Shape.INFLATE - 1e-6, "%s: a corner of %s is 1.5 inside" % [key, str(c)])


func test_the_outline_is_convex_and_is_the_hull_pushed_out_by_one_and_a_half() -> void:
	var all := _shapes()
	for key in all:
		var s = Shape.from_cells(all[key])
		var o: PackedVector2Array = s.outline()
		var n := o.size()
		check(n >= 4 * (Shape.ARC_STEPS + 1) / 2, key + ": rounded corners have points")
		for i in n:
			var cr := (o[(i + 1) % n] - o[i]).cross(o[(i + 2) % n] - o[(i + 1) % n])
			check(cr >= -1e-6, "%s: the outline never turns back (%f)" % [key, cr])
		for p in o:
			near(s.margin(p), 0.0, key + ": every outline point is on the outline", 1e-4)
			near(s.hull_distance(p), Shape.INFLATE, key + ": 1.5 cells from the hull", 1e-4)
		# a rounded corner: straight out of a hull corner, between its two side normals, is 1.5 away and no more
		var vn: int = s.verts.size()
		for i in vn:
			var dir: Vector2 = (s._normals[i] + s._normals[(i + vn - 1) % vn]).normalized()
			near(s.hull_distance(s.verts[i] + dir * 1.5), 1.5, "%s: corner %d is a piece of a circle" % [key, i], 1e-4)


func test_a_segment_meets_the_outline_on_it() -> void:
	var all := _shapes()
	for key in all:
		var s = Shape.from_cells(all[key])
		var ctr: Vector2 = s.centre
		for deg in range(0, 360, 15):
			var d := Vector2.from_angle(deg_to_rad(deg))
			var a: Vector2 = ctr + d * (s.radius + 20.0)
			var t: float = s.entry_t(a, ctr)
			check(t > 0.0 and t < 1.0, "%s %d deg: it enters" % [key, deg])
			var p: Vector2 = a.lerp(ctr, t)
			near(s.margin(p), 0.0, "%s %d deg: the hit point is on the outline" % [key, deg], 1e-3)
			check(not s.contains(a.lerp(ctr, maxf(t - 0.002, 0.0))) and s.contains(a.lerp(ctr, minf(t + 0.002, 1.0))), "%s %d deg: outside before, inside after" % [key, deg])
			var out: float = s.exit_t(ctr, a)
			near(s.margin(ctr.lerp(a, out)), 0.0, "%s %d deg: and it leaves on the outline" % [key, deg], 1e-3)
			near(float(ctr.distance_to(ctr.lerp(a, out))), float(ctr.distance_to(p)), "%s %d deg: through the same point" % [key, deg], 1e-3)


func test_segments_that_start_inside_stop_short_or_pass_by_do_not_enter() -> void:
	var s = Shape.from_cells(_rect(0, 0, 10, 6))
	eq(s.entry_t(Vector2(5, 3), Vector2(40, 3)), -1.0, "starting inside: it is in already")
	eq(s.entry_t(Vector2(-10, 3), Vector2(-3, 3)), -1.0, "stopping short of the bubble")
	eq(s.entry_t(Vector2(-10, -4), Vector2(40, -4)), -1.0, "passing above it (1.5 cells out is y = -1.5)")
	eq(s.entry_t(Vector2(-10, 10), Vector2(40, 10)), -1.0, "passing below it")
	near(s.entry_t(Vector2(-10, 3), Vector2(5, 3)), 8.5 / 15.0, "a segment along the middle row enters at x = -1.5", 1e-6)
	near(s.entry_t(Vector2(5, -10), Vector2(5, 3)), 8.5 / 13.0, "and one down the middle column at y = -1.5", 1e-6)
	var corner: float = s.entry_t(Vector2(-6, -6), Vector2(5, 3))
	check(corner > 0.0, "a slanting segment through the rounded corner enters")
	near(s.margin(Vector2(-6, -6).lerp(Vector2(5, 3), corner)), 0.0, "on the outline", 1e-3)
	# the corner is rounded: the square's corner point (-1.5, -1.5) is outside the bubble
	check(not s.contains(Vector2(-1.4, -1.4)), "the bubble cuts the corner")
	check(s.contains(Vector2(-1.0, -1.0)), "but holds the point a cell in")


func test_a_segment_ending_just_inside_still_enters() -> void:
	var s = Shape.from_cells(_rect(0, 0, 10, 6))
	var t: float = s.entry_t(Vector2(5, -10), Vector2(5, -1.49))
	check(t > 0.99 and t <= 1.0, "it ends a hair inside: entered at the very end (%f)" % t)


func test_sector_of_a_vector_for_one_two_four_and_eight_sectors() -> void:
	eq([Shape.sector_at(Vector2(0, -1), 1), Shape.sector_at(Vector2(3, 5), 1), Shape.sector_at(Vector2.ZERO, 4)], [0, 0, 0], "one sector, or no direction: sector 0")
	eq([Shape.sector_at(Vector2(0, -1), 2), Shape.sector_at(Vector2(1, -0.1), 2), Shape.sector_at(Vector2(1, 0.1), 2), Shape.sector_at(Vector2(0, 1), 2), Shape.sector_at(Vector2(-1, 0.1), 2), Shape.sector_at(Vector2(-1, -0.1), 2)], [0, 0, 1, 1, 1, 0], "two: bow and stern, the split across the beam")
	eq([Shape.sector_at(Vector2(0, -1), 4), Shape.sector_at(Vector2(1, 0), 4), Shape.sector_at(Vector2(0, 1), 4), Shape.sector_at(Vector2(-1, 0), 4)], [0, 1, 2, 3], "four: bow, starboard, stern, port")
	eq([Shape.sector_at(Vector2(0.9, -1), 4), Shape.sector_at(Vector2(-0.9, -1), 4), Shape.sector_at(Vector2(1, -0.9), 4)], [0, 0, 1], "four: the bow spans 45 degrees either side")
	var eight := []
	for k in 8:
		eight.append(Shape.sector_at(Vector2.from_angle(-PI / 2.0 + TAU * k / 8.0), 8))
	eq(eight, [0, 1, 2, 3, 4, 5, 6, 7], "eight: every 45 degrees, clockwise from the bow")
	eq([Shape.sector_at(Vector2.from_angle(-PI / 2.0 + deg_to_rad(20.0)), 8), Shape.sector_at(Vector2.from_angle(-PI / 2.0 + deg_to_rad(25.0)), 8), Shape.sector_at(Vector2.from_angle(-PI / 2.0 - deg_to_rad(25.0)), 8)], [0, 1, 7], "eight: the split is 22.5 degrees off the centre")


func test_the_sector_lines_cover_the_outline() -> void:
	var all := _shapes()
	for key in all:
		var s = Shape.from_cells(all[key])
		for n in [1, 2, 4, 8]:
			var lines: Array = s.sector_lines(n)
			eq(lines.size(), n, "%s %d: one line per sector" % [key, n])
			for k in n:
				var line: PackedVector2Array = lines[k]
				check(line.size() >= 2, "%s %d/%d: a line" % [key, n, k])
				for p in line:
					near(s.margin(p), 0.0, "%s %d/%d: on the outline" % [key, n, k], 1e-3)
				if n > 1:
					near(float(line[-1].distance_to(lines[(k + 1) % n][0])), 0.0, "%s %d/%d: ends where the next sector starts" % [key, n, k], 1e-6)
					for i in range(1, line.size() - 1):
						eq(Shape.sector_at(line[i] - s.centre, n), k, "%s %d/%d: the points between its ends are in it" % [key, n, k])


func test_the_shape_of_a_ship_is_its_solid_cells_and_parts_and_ignores_breaches() -> void:
	var ship := _tile_ship()
	for c in ship.grid.hull:
		ship.grid.force_tile(c, "floor")
	eq(Shape.cells_of(ship).size(), ship.grid.hull.size(), "no walls: the hull's cells")
	for c in _rect(5, 5, 20, 1):
		ship.grid.force_tile(c, "wall")
	for c in _rect(5, 25, 20, 1):
		ship.grid.force_tile(c, "wall")
	var door_cells := [Vector2i(5, 14), Vector2i(5, 15)]
	for c in door_cells:
		ship.grid.force_tile(c, "door")
	var walls := Shape.cells_of(ship)
	eq(walls.size(), 42, "40 wall cells and 2 door cells")
	var before: Array = Shape.signature(ship)
	var shape = Shape.from_cells(walls, Shape.centre_of(ship))
	var verts_before: PackedVector2Array = shape.verts.duplicate()
	ship.grid.breach(Vector2i(10, 5))
	check(Shape.signature(ship) != before, "a breach changes the signature")
	var after = Shape.from_cells(Shape.cells_of(ship), Shape.centre_of(ship))
	eq(after.verts, verts_before, "but not the shape: a shot-open wall is still part of the hull")
	eq(Shape.cells_of(ship).size(), 42, "the breached cell still counts")
	check(ship.components.place(ship.grid, "reactor_mk1", Vector2i(9, 19), 0) > 0, "a part")
	var with_part: Array = Shape.cells_of(ship)
	check(with_part.size() > 42, "its cells count")
	var wide = Shape.from_cells(with_part, Shape.centre_of(ship))
	check(wide.contains(Vector2(10.5, 20.5)), "and it is inside")
	near(Shape.centre_of(ship).x, 15.5, "the centre is the hull's middle")


func test_a_wider_copy_of_the_shape_is_cached_and_bigger() -> void:
	var s = Shape.from_cells(_rect(0, 0, 10, 6))
	var g = s.grown(0.5)
	check(g == s.grown(0.5), "cached")
	near(g.margin(Vector2(5, 3)), s.margin(Vector2(5, 3)) + 0.5, "half a cell more all round")
	check(g.contains(Vector2(-1.9, 3.0)) and not s.contains(Vector2(-1.9, 3.0)), "it holds a point the plain one does not")
