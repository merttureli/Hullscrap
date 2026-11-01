extends "res://tests/base_test.gd"
## What the big round build area (playtest 2, B1: every starter's frame is a disc of radius 29) touches besides the
## ships' files (tests/test_starter_ships.gd checks those): the build-mode art of the empty frame, which is drawn every
## frame of build mode, and the map of a ship, which must fit the built ship and not the whole frame.

const BuildMode = preload("res://scripts/build/build_mode.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Schematic = preload("res://scripts/ui/schematic.gd")

const COURIER := "res://data/ships/starter_courier.json"
const PIRATE := "res://data/ships/pirate_raider.json"


func test_the_frame_art_covers_exactly_the_hull_and_draws_each_edge_once() -> void:
	var ship := Ship.from_design(COURIER)
	var b := BuildMode.new()
	b.sim = ShipSim.new()
	b.sim.ships = [ship]
	b._make_frame_art()
	var cell := float(BuildMode.CELL)
	var covered := {}
	for r in b._frame_rects:
		check(r.size.y == cell, "a frame rect is one row high")
		for i in int(r.size.x / cell):
			var c := Vector2i(int(r.position.x / cell) + i, int(r.position.y / cell))
			check(not covered.has(c), "no cell is in two frame rects (%s)" % str(c))
			covered[c] = true
	eq(covered.size(), ship.grid.hull.size(), "the frame rects cover the whole hull")
	check(ship.grid.hull.keys().all(func(c): return covered.has(c)), "and only the hull")
	check(b._frame_rects.size() <= 2 * ship.grid.size.y, "a few long runs, not a rect for each of %d cells (%d)" % [ship.grid.hull.size(), b._frame_rects.size()])
	var edges := {}  # [horizontal?, x, y] of the unit edges the lines cover
	for i in range(0, b._frame_lines.size(), 2):
		var a: Vector2 = b._frame_lines[i] / cell
		var z: Vector2 = b._frame_lines[i + 1] / cell
		check(a.x == z.x or a.y == z.y, "a frame line runs along the grid")
		for k in int(maxf(z.x - a.x, z.y - a.y)):
			var e := [a.y == z.y, int(a.x) + (k if a.y == z.y else 0), int(a.y) + (k if a.y != z.y else 0)]
			check(not edges.has(e), "no edge is drawn twice (%s)" % str(e))
			edges[e] = true
	var want := {}
	for c in ship.grid.hull:
		for e in [[true, c.x, c.y], [true, c.x, c.y + 1], [false, c.x, c.y], [false, c.x + 1, c.y]]:
			want[e] = true
	eq(edges.size(), want.size(), "the lines cover every edge of every hull cell")
	check(want.keys().all(func(e): return edges.has(e)), "and no other")
	check(b._frame_lines.size() <= 400, "joined into long lines, not %d points" % b._frame_lines.size())
	b.sim.free()
	b.free()


func test_the_map_fits_what_is_built_not_the_empty_frame() -> void:
	for path in [COURIER, "res://data/ships/starter_rustbucket.json", "res://data/ships/starter_prism.json"]:
		var ship := Ship.from_design(path)
		var box := Schematic.fit_box(ship)
		check(box.size.x < 40.0 and box.size.y < 40.0, "%s: the map box is %s, well under the 59 cells of the frame" % [path, str(box.size)])
		var cells: Array = ship.grid.tiles.keys()
		for uid in ship.components.instances:
			cells.append_array(ship.components.instances[uid]["out_cells"])
		check(cells.all(func(c): return box.has_point(Vector2(c) + Vector2(0.5, 0.5))), "%s: the box holds every tile and every outside half" % path)
	var pirate := Ship.from_design(PIRATE)  # an enemy's hull is its built box plus two cells: the same box as before
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in pirate.grid.hull:
		lo = lo.min(Vector2(c))
		hi = hi.max(Vector2(c) + Vector2.ONE)
	eq(Schematic.fit_box(pirate), Rect2(lo, hi - lo), "a ship with a snug hull is fitted as it was")
