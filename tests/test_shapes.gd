extends "res://tests/base_test.gd"
## Cell shapes (data/shapes.json, scripts/ship/shapes.gd): the polygons, rotation and mirror, pieces,
## the shape a grid stores per cell and saves, area-scaled hp, mass and cost, and building a piece
## as one undo step. Also the mass distribution helpers of flight.gd (centre of mass, inertia).

const Shapes = preload("res://scripts/ship/shapes.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Flight = preload("res://scripts/sim/flight.gd")
const Components = preload("res://scripts/ship/components.gd")
const Cables = preload("res://scripts/ship/cables.gd")


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func _has_point(poly: PackedVector2Array, p: Vector2) -> bool:
	for v in poly:
		if v.distance_to(p) < 1e-5:
			return true
	return false


func _same_points(poly: PackedVector2Array, pts: Array) -> bool:
	if poly.size() != pts.size():
		return false
	for p in pts:
		if not _has_point(poly, p):
			return false
	return true


func _grid() -> ShipGrid:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(15, 15), defs)
	g.fill_circle_hull(7.0)
	return g


func _session(scrap := 100) -> BuildSession:
	var ship := Ship.new("Test", _grid())
	ship.inventory.load_dict({"scrap": scrap, "titanium": 20})
	return BuildSession.new(ship)


# --- the polygons ---------------------------------------------------------------------------------

func test_cell_polygons_and_areas() -> void:
	near(Shapes.area("full"), 1.0, "full")
	near(Shapes.area("tri"), 0.5, "tri")
	near(Shapes.area("tri2_low"), 0.25, "the small triangle of slope2")
	near(Shapes.area("tri2_high"), 0.75, "the trapezoid of slope2")
	check(_same_points(Shapes.cell_polygon("full"), [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), "full is the unit square")
	check(_same_points(Shapes.cell_polygon("tri"), [Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]), "tri at rotation 0 is the bottom-left half")
	check(_same_points(Shapes.cell_polygon("tri2_low"), [Vector2(0, 1), Vector2(1, 0.5), Vector2(1, 1)]), "slope2 starts low at (0,1)")
	check(_same_points(Shapes.cell_polygon("tri2_high"), [Vector2(0, 0.5), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), "and reaches (2,0): the second cell")
	for id in Shapes.shape_ids():
		for rot in 4:
			for mirror in [false, true]:
				var p := Shapes.cell_polygon(id, rot, mirror)
				near(Shapes.polygon_area(p), Shapes.area(id), "%s rot %d mirror %s keeps its area" % [id, rot, str(mirror)], 1e-6)
				check(Shapes.polygon_area(p) > 0.0, id + " is wound the same way")
				var n := Shapes.edge_normals(id, rot, mirror)
				var c := Shapes.centroid(id, rot, mirror)
				for k in p.size():
					check(n[k].dot(c - p[k]) < 1e-9, "%s normal %d points outward" % [id, k])
					near(n[k].length(), 1.0, "unit normal", 1e-6)
					check(p[k].x >= -1e-6 and p[k].x <= 1.000001 and p[k].y >= -1e-6 and p[k].y <= 1.000001, id + " stays in its cell")


func test_round2_is_an_eight_segment_quarter_disk() -> void:
	# Centred on the piece's bottom-right corner (2,2), radius 2: the four cells' polygons together.
	var total := 0.0
	var on_arc := 0
	for k in 4:
		var id: String = ["round2_tl", "round2_tr", "round2_bl", "round2_br"][k]
		var off := Vector2(k % 2, k / 2)
		total += Shapes.area(id)
		for v in Shapes.cell_polygon(id):
			var d := (v + off).distance_to(Vector2(2, 2))
			check(d <= 2.0 + 1e-5, "%s lies inside the disk (%f)" % [id, d])
			on_arc += int(absf(d - 2.0) < 1e-5)
	near(total, 8.0 * 0.5 * 4.0 * sin(PI / 16.0), "the area of the 8-gon", 1e-4)
	eq(Shapes.polygon_area(Shapes.cell_polygon("round2_br")), 1.0, "the bottom-right cell is whole")
	check(on_arc >= 9, "the arc's nine corners are on the circle (%d seen)" % on_arc)
	var tl := Shapes.cell_polygon("round2_tl")
	check(_has_point(tl, Vector2(1, 1)), "the top-left cell keeps the corner next to the middle")
	check(not _has_point(tl, Vector2(0, 0)) and not _has_point(tl, Vector2(1, 0)) and not _has_point(tl, Vector2(0, 1)), "and loses the other three")
	check(Shapes.has_piece("round2") and Shapes.has_piece("slope2") and Shapes.has_piece("slope45") and Shapes.has_piece("full"), "the four v1 pieces exist")


func test_rotation_turns_clockwise_and_mirror_flips_x_first() -> void:
	# tri: bottom-left half, then top-left, top-right, bottom-right as it turns clockwise.
	check(_same_points(Shapes.cell_polygon("tri", 1), [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]), "tri turned once is the top-left half")
	check(_same_points(Shapes.cell_polygon("tri", 2), [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]), "twice, the top-right half")
	check(_same_points(Shapes.cell_polygon("tri", 3), [Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), "three times, the bottom-right half")
	check(_same_points(Shapes.cell_polygon("tri", 4), Shapes.cell_polygon("tri", 0)), "four turns are none")
	check(_same_points(Shapes.cell_polygon("tri", -1), Shapes.cell_polygon("tri", 3)), "-1 is 3")
	check(_same_points(Shapes.cell_polygon("tri", 0, true), [Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]), "mirrored, the bottom-right half")
	# mirror first, then turn: tri2_low mirrored is (1,1),(0,0.5),(0,1); turned once (x,y) -> (1-y,x).
	check(_same_points(Shapes.cell_polygon("tri2_low", 1, true), [Vector2(0, 1), Vector2(0.5, 0), Vector2(0, 0)]), "mirror, then turn")
	check(not _same_points(Shapes.cell_polygon("tri2_low", 1, true), Shapes.cell_polygon("tri2_low", 1, false)), "the order matters")
	near(Shapes.polygon_area(Shapes.cell_polygon("tri2_low", 1, true)), 0.25, "still wound the same way", 1e-6)


func test_pieces_place_their_cells_with_the_offsets_turned_too() -> void:
	var a := Vector2i(5, 5)
	var cells := Shapes.piece_cells("slope2", a, 0)
	eq([cells[0]["cell"], cells[0]["shape"], cells[1]["cell"], cells[1]["shape"]], [Vector2i(5, 5), "tri2_low", Vector2i(6, 5), "tri2_high"], "slope2 rises to the right")
	cells = Shapes.piece_cells("slope2", a, 1)
	eq([cells[0]["cell"], cells[1]["cell"], cells[0]["rot"]], [Vector2i(5, 5), Vector2i(5, 6), 1], "turned once it runs down; the low end is on top")
	cells = Shapes.piece_cells("slope2", a, 2)
	eq([cells[0]["cell"], cells[1]["cell"]], [Vector2i(6, 5), Vector2i(5, 5)], "turned twice the low end is on the right")
	cells = Shapes.piece_cells("slope2", a, 0, true)
	eq([cells[0]["cell"], cells[1]["cell"], cells[0]["mirror"]], [Vector2i(6, 5), Vector2i(5, 5), true], "mirrored the low end is on the right")
	eq(Shapes.piece_size("slope2"), Vector2i(2, 1), "2x1")
	eq(Shapes.piece_size("slope2", 1), Vector2i(1, 2), "1x2 when turned")
	eq(Shapes.piece_cells("slope45", a, 3).size(), 1, "slope45 is one cell")
	eq(Shapes.piece_cells("nothing", a, 0), [], "an unknown piece has no cells")
	# The ramp is one straight line across both cells: the end of the first cell's edge is the start of the second's.
	var lo := Shapes.cell_polygon("tri2_low")
	var hi := Shapes.cell_polygon("tri2_high")
	check(_has_point(lo, Vector2(1, 0.5)) and _has_point(hi, Vector2(0, 0.5)), "slope2's cells meet at the same height")


func test_a_turned_round2_is_still_a_quarter_disk_round_the_right_corner() -> void:
	# The disk's centre is the piece's bottom-right corner turning clockwise with it; mirroring flips x first.
	var centres_plain := [Vector2(2, 2), Vector2(0, 2), Vector2(0, 0), Vector2(2, 0)]
	var centres_mirror := [Vector2(0, 2), Vector2(0, 0), Vector2(2, 0), Vector2(2, 2)]
	for mirror in [false, true]:
		for rot in 4:
			var centre: Vector2 = (centres_mirror if mirror else centres_plain)[rot]
			var total := 0.0
			for pc in Shapes.piece_cells("round2", Vector2i.ZERO, rot, mirror):
				total += Shapes.area(pc["shape"])
				for v in Shapes.cell_polygon(pc["shape"], pc["rot"], pc["mirror"]):
					var d: float = (v + Vector2(pc["cell"])).distance_to(centre)
					check(d <= 2.0 + 1e-5, "rot %d mirror %s: %s corner inside the disk at %s (%f)" % [rot, str(mirror), pc["shape"], str(centre), d])
			near(total, Shapes.area("round2_tl") + Shapes.area("round2_tr") + Shapes.area("round2_bl") + 1.0, "the same area turned", 1e-5)


func test_a_ray_meets_the_solid_half_of_a_shape_only() -> void:
	var tri := {"shape": "tri", "rot": 0, "mirror": false}  # solid where y >= x: below the diagonal from (0,0) to (1,1)
	var h := Shapes.segment_hit(tri, Vector2(-1, 0.75), Vector2(2, 0.75))
	check(not h.is_empty(), "a ray along y = 0.75 meets the solid half")
	near(h["t"], 1.0 / 3.0, "at the cell's left face")
	eq(h["n"], Vector2(-1, 0), "whose normal faces the shooter")
	h = Shapes.segment_hit(tri, Vector2(0.75, -1), Vector2(0.75, 2))  # straight down at x = 0.75: meets the diagonal at y = 0.75
	near(h["t"], 1.75 / 3.0, "a ray from above meets the slope")
	near(h["n"].x, sqrt(0.5), "its normal is the slope's: up and to the right", 1e-6)
	near(h["n"].y, -sqrt(0.5), "(outward, toward the shooter)", 1e-6)
	check(Shapes.segment_hit(tri, Vector2(0.2, -0.3), Vector2(1.4, 0.9)).is_empty(), "a ray along x - y = 0.5 crosses only the empty half and misses")
	check(Shapes.segment_hit(tri, Vector2(1.5, 0.5), Vector2(0.8, 0.5)).is_empty(), "so does one that stops in the empty corner")
	check(Shapes.segment_hit(tri, Vector2(2, 0.75), Vector2(3, 0.75)).is_empty(), "a segment that stops short misses")
	h = Shapes.segment_hit(tri, Vector2(0.2, 0.9), Vector2(0.4, 0.9))
	eq([h["t"], h["n"]], [0.0, Vector2.ZERO], "a segment that starts inside is a hit at 0 with no normal")
	check(Shapes.segment_hit(tri, Vector2(0.0, 0.5), Vector2(-1.0, 0.5)).is_empty(), "one leaving from the face it starts on misses")


# --- the grid ---------------------------------------------------------------------------------------

func test_the_grid_stores_a_shape_per_cell_and_saves_it_only_when_not_full() -> void:
	var g := _grid()
	var c := Vector2i(7, 7)
	g.force_tile(c, "wall")
	eq(g.shape_of(c), {}, "a wall is a full square")
	near(g.area_at(c), 1.0, "area 1")
	eq(g.polygon_at(c), Shapes.cell_polygon("full"), "its polygon is the unit square")
	check(not g.to_dict().has("shapes"), "no shapes key when every cell is full")
	g.set_shape(c, "tri", 3, true)
	eq(g.shape_of(c), {"shape": "tri", "rot": 3, "mirror": true}, "the shape, turn and mirror are kept")
	near(g.area_at(c), 0.5, "area 0.5")
	eq(g.polygon_at(c), Shapes.cell_polygon("tri", 3, true), "the polygon follows")
	g.set_shape(c, "full")
	eq(g.shape_of(c), {}, "setting full clears it")
	g.set_shape(c, "tri2_high", 6)
	eq(g.shape_of(c)["rot"], 2, "turns wrap")
	var d: Dictionary = JSON.parse_string(JSON.stringify(g.to_dict()))
	var saved: Array = d["shapes"][0]
	eq([d["shapes"].size(), int(saved[0]), int(saved[1]), saved[2], int(saved[3]), saved[4]], [1, 7, 7, "tri2_high", 2, false], "saved as [x, y, shape, rot, mirror]")
	var h := _grid()
	h.force_tile(c, "wall")
	eq(h.load_dict(d), "", "loads")
	eq(h.shape_of(c), {"shape": "tri2_high", "rot": 2, "mirror": false}, "and comes back")
	g.force_tile(c, "wall")
	eq(g.shape_of(c), {}, "force_tile without a shape makes it whole again")
	g.force_tile(c, "wall", {"shape": "tri", "rot": 1})
	eq(g.shape_of(c), {"shape": "tri", "rot": 1, "mirror": false}, "or gives it the shape asked for")
	g.force_tile(c, "")
	eq(g.shape_of(c), {}, "removing the tile removes the shape")


func test_old_saves_without_shapes_load_and_bad_ones_are_refused() -> void:
	var g := _grid()
	g.force_tile(Vector2i(7, 7), "wall")
	var d: Dictionary = JSON.parse_string(JSON.stringify(g.to_dict()))
	check(not d.has("shapes"), "an old-style save has no shapes")
	var h := _grid()
	h.set_shape(Vector2i(3, 3), "tri")
	eq(h.load_dict(d), "", "it loads")
	eq(h.shapes, {}, "with every cell full")
	var bad: Dictionary = d.duplicate(true)
	bad["shapes"] = [[7, 7, "teardrop", 0, false]]
	g.set_shape(Vector2i(7, 7), "tri")
	eq(g.load_dict(bad), "bad ship data", "an unknown shape is refused")
	eq(g.shape_of(Vector2i(7, 7)), {"shape": "tri", "rot": 0, "mirror": false}, "and nothing changed")
	bad["shapes"] = [[7, 7, "tri"]]
	eq(g.load_dict(bad), "bad ship data", "so is a short entry")
	var whole := Ship.new("t", _grid())
	whole.grid.force_tile(Vector2i(6, 6), "wall", {"shape": "tri", "rot": 2})
	var back := Ship.new("t", _grid())
	eq(back.load_dict(JSON.parse_string(JSON.stringify(whole.to_dict()))), "", "a whole ship with a shaped cell loads")
	eq(back.grid.shape_of(Vector2i(6, 6)), {"shape": "tri", "rot": 2, "mirror": false}, "keeping the shape")


func test_hp_scales_with_the_area_and_a_breach_remembers_the_shape() -> void:
	var g := _grid()
	var c := Vector2i(7, 7)
	g.force_tile(c, "wall", {"shape": "tri"})  # wall hp 4
	near(g.max_hp_of(c), 2.0, "half the area, half the hp")
	g.force_tile(c, "wall", {"shape": "tri2_low"})
	near(g.max_hp_of(c), 1.0, "a quarter would be 1.0 anyway; never below 1")
	g.force_tile(c, "scrap_plate", {"shape": "tri2_low"})  # hp 3 x 0.25 = 0.75
	near(g.max_hp_of(c), 1.0, "least 1 hp")
	g.force_tile(c, "heavy_armor", {"shape": "tri"})
	near(g.max_hp_of(c), 5.0, "heavy armour 10 x 0.5")
	near(g.hp_of(c), 5.0, "starts whole")
	eq(g.breach(c), "heavy_armor", "breached")
	eq(g.get_tile(c), "", "now a hole")
	eq(g.shape_of(c), {}, "with no shape")
	check(g.repair(c), "repaired")
	eq(g.get_tile(c), "heavy_armor", "the tile is back")
	eq(g.shape_of(c), {"shape": "tri", "rot": 0, "mirror": false}, "in the same shape")
	g.breach(c)
	var d: Dictionary = JSON.parse_string(JSON.stringify(g.to_dict()))
	var kept: Array = d["breached_shapes"][0]
	eq([d["breached_shapes"].size(), int(kept[0]), int(kept[1]), kept[2], int(kept[3]), kept[4]], [1, 7, 7, "tri", 0, false], "a breached cell's shape is saved too")
	var h := _grid()
	eq(h.load_dict(d), "", "loads")
	check(h.repair(c), "repair after loading")
	eq(h.shape_of(c)["shape"], "tri", "the shape returns")


func test_only_walls_take_a_shape() -> void:
	var g := _grid()
	eq(g.can_place("floor", Vector2i(7, 7), {"shape": "tri"}), "only walls take a shape", "floor")
	eq(g.can_place("wall", Vector2i(7, 7), {"shape": "tri"}), "", "wall")
	g.force_tile(Vector2i(7, 7), "wall", {"shape": "tri"})
	eq(g.can_place("wall", Vector2i(7, 7), {"shape": "tri"}), "already there", "the same wall in the same shape")
	eq(g.can_place("wall", Vector2i(7, 7), {"shape": "tri", "rot": 1}), "", "another turn is a change")
	eq(g.can_place("wall", Vector2i(7, 7)), "", "and so is a whole one")
	check(g.place("wall", Vector2i(7, 7)), "placing a plain wall over it")
	eq(g.shape_of(Vector2i(7, 7)), {}, "makes it whole")


func test_cost_is_rounded_up_per_cell() -> void:
	var g := _grid()
	eq(g.cost_of("wall"), {"scrap": 2}, "a whole wall")
	eq(g.cost_of("wall", 0.5), {"scrap": 1}, "half")
	eq(g.cost_of("wall", 0.25), {"scrap": 1}, "a quarter rounds up to 1")
	eq(g.cost_of("heavy_armor", 0.5), {"scrap": 3, "titanium": 1}, "heavy armour 6 and 2 halved")
	eq(g.cost_of("heavy_armor", 0.75), {"scrap": 5, "titanium": 2}, "three quarters rounds up")


# --- building --------------------------------------------------------------------------------------

func test_a_piece_is_one_change_and_one_undo_step() -> void:
	var s := _session()
	var before: Dictionary = s.inventory.to_dict().duplicate()
	var pl := s.plan_piece("slope2", "wall", Vector2i(6, 6), 0)
	eq(pl["error"], "", "planned")
	eq(pl["changes"].size(), 1, "one change")
	var r := s.apply(pl["changes"])
	eq([r["applied"], r["skipped"]], [2, 0], "two cells built")
	eq(s.undo_stack.size(), 1, "one undo step")
	eq(s.grid.shape_of(Vector2i(6, 6)).get("shape"), "tri2_low", "the low end")
	eq(s.grid.shape_of(Vector2i(7, 6)).get("shape"), "tri2_high", "and the high end")
	eq(s.inventory.count("scrap"), 100 - 1 - 2, "wall scrap 2: the quarter costs 1 and the three quarters 2")
	check(s.undo(), "undo")
	eq([s.grid.get_tile(Vector2i(6, 6)), s.grid.get_tile(Vector2i(7, 6))], ["", ""], "both cells gone")
	eq(s.grid.shapes, {}, "and their shapes")
	eq(s.inventory.to_dict(), before, "the cargo is back")
	check(s.redo(), "redo")
	eq(s.grid.shape_of(Vector2i(7, 6)).get("shape"), "tri2_high", "shapes come back with it")
	eq(s.inventory.count("scrap"), 97, "and the cost is paid again")
	check(s.undo(), "undo once more")
	eq(s.inventory.to_dict(), before, "still exact")


func test_round2_costs_by_area_and_a_failed_piece_builds_nothing() -> void:
	var s := _session()
	var r := s.apply(s.plan_piece("round2", "wall", Vector2i(5, 5), 0)["changes"])
	eq([r["applied"], r["skipped"]], [4, 0], "four cells")
	# wall scrap 2 per cell: 0.309 -> 1, 0.906 -> 2, 0.906 -> 2, 1.0 -> 2
	eq(s.inventory.count("scrap"), 100 - 7, "round2 in walls costs 7 scrap")
	eq(s.undo_stack.size(), 1, "one step")
	s.undo()
	eq(s.inventory.count("scrap"), 100, "refunded")
	var poor := _session(4)  # 4 scrap: the first two cells fit (1 + 2 = 3), the third does not
	r = poor.apply(poor.plan_piece("round2", "wall", Vector2i(5, 5), 0)["changes"])
	eq([r["applied"], r["skipped"]], [0, 1], "not enough for all of it: none of it")
	eq(r["reason"], "not enough scrap", "and says why")
	eq(poor.grid.tiles.size(), 0, "no cell was built")
	eq(poor.inventory.count("scrap"), 4, "and nothing was spent")
	eq(poor.undo_stack.size(), 0, "and no step recorded")
	var s2 := _session()
	var out := s2.plan_piece("slope2", "wall", Vector2i(14, 14), 0)
	eq(out["error"], "outside the hull", "a piece off the grid is refused at the plan")
	var edge := s2.apply(s2.plan_piece("slope2", "wall", Vector2i(12, 3), 0)["changes"])  # (12, 3) is in the round hull, (13, 3) is not
	eq(edge["applied"], 0, "one cell outside the hull refuses the whole piece")
	eq(s2.grid.tiles.size(), 0, "nothing built")
	eq(s2.plan_piece("slope2", "floor", Vector2i(6, 6))["error"], "only walls take a shape", "a floor cannot be sloped")
	eq(s2.plan_piece("teardrop", "wall", Vector2i(6, 6))["error"], "unknown piece", "unknown piece")


func test_pieces_turn_mirror_and_replace_cells() -> void:
	var s := _session()
	s.apply(s.plan_piece("slope45", "wall", Vector2i(6, 6), 1, true)["changes"])
	eq(s.grid.shape_of(Vector2i(6, 6)), {"shape": "tri", "rot": 1, "mirror": true}, "turn and mirror are stored")
	var r := s.apply(s.plan_piece("slope45", "wall", Vector2i(6, 6), 1, true)["changes"])
	eq([r["applied"], r["skipped"], r["reason"]], [0, 1, "already there"], "the same piece again does nothing")
	var scrap: int = s.inventory.count("scrap")
	r = s.apply(s.plan_piece("slope45", "heavy_armor", Vector2i(6, 6), 0)["changes"])
	eq(r["applied"], 1, "another material and shape replaces it")
	eq(s.grid.get_tile(Vector2i(6, 6)), "heavy_armor", "heavy armour now")
	eq(s.inventory.count("scrap"), scrap + 1 - 3, "the old half-wall is refunded (1), the new half-armour paid (3)")
	s.undo()
	eq(s.grid.get_tile(Vector2i(6, 6)), "wall", "undo brings the wall back")
	eq(s.grid.shape_of(Vector2i(6, 6)), {"shape": "tri", "rot": 1, "mirror": true}, "in its old shape")
	eq(s.inventory.count("scrap"), scrap, "and the cargo")
	# A plain tile change may carry a shape too.
	var t := s.apply([{"cell": Vector2i(8, 8), "to": "wall", "shape": "tri", "rot": 2}])
	eq(t["applied"], 1, "a tile change with a shape")
	eq(s.grid.shape_of(Vector2i(8, 8)), {"shape": "tri", "rot": 2, "mirror": false}, "builds it")
	var p := s.preview([{"layer": "piece", "piece": "slope2", "tile": "wall", "anchor": Vector2i(3, 6), "rot": 0, "mirror": false}])
	eq(p[0]["reason"], "", "a preview says it would build")
	eq(s.grid.get_tile(Vector2i(3, 6)), "", "without building it")
	eq(s.inventory.count("scrap"), scrap - 1, "or paying (the half wall at (8,8) cost 1)")


# --- mass ------------------------------------------------------------------------------------------

func test_mass_follows_the_solid_area() -> void:
	var g := _grid()
	var f := Flight.new()
	var comps := Components.new()
	comps.load_defs("res://data/components.json")
	var cables := Cables.new()
	g.force_tile(Vector2i(5, 5), "wall")
	near(f.mass_of(g, comps, cables), 2.0, "a whole wall (mass 2)")
	g.force_tile(Vector2i(5, 5), "wall", {"shape": "tri"})
	near(f.mass_of(g, comps, cables), 1.0, "a half wall")
	g.force_tile(Vector2i(6, 5), "heavy_armor", {"shape": "tri2_low"})
	near(f.mass_of(g, comps, cables), 1.0 + 5.0 * 0.25, "plus a quarter of heavy armour (mass 5)")
	eq(g.area_at(Vector2i(0, 0)), 1.0, "(an empty cell reads as whole)")


func test_centre_of_mass_and_moment_of_inertia() -> void:
	var g := _grid()
	var f := Flight.new()
	var comps := Components.new()
	comps.load_defs("res://data/components.json")
	var cables := Cables.new()
	g.force_tile(Vector2i(5, 5), "wall")
	g.force_tile(Vector2i(6, 5), "wall")
	var props := f.mass_props(g, comps, cables)
	near(props["mass"], 4.0, "two walls")
	near(props["com"].x, 6.0, "centre of mass between them")
	near(props["com"].y, 5.5, "and mid-height")
	# each wall: mass 2 at 0.5 cells from the centre plus a plate's own m/6 -> 2 x 2 x (0.25 + 1/6) cells^2, 32 px a cell
	near(props["inertia"], 4.0 * (0.25 + 1.0 / 6.0) * 1024.0, "inertia about the centre of mass", 1e-3)
	var g2 := _grid()  # the same pair moved: the same inertia about the new centre
	g2.force_tile(Vector2i(2, 8), "wall")
	g2.force_tile(Vector2i(3, 8), "wall")
	near(f.mass_props(g2, comps, cables)["inertia"], props["inertia"], "does not depend on where it is", 1e-3)
	g2.force_tile(Vector2i(12, 8), "wall")
	var far := f.mass_props(g2, comps, cables)
	check(float(far["inertia"]) > 50.0 * props["inertia"], "a far outlier makes a flywheel")
	check(far["com"].x > 5.0, "and drags the centre of mass")
	var g3 := _grid()  # a triangle's mass sits at its own centre (the slope side is lighter)
	g3.force_tile(Vector2i(5, 5), "wall", {"shape": "tri"})  # bottom-left half: centroid (1/3, 2/3)
	var p3 := f.mass_props(g3, comps, cables)
	near(p3["com"].x, 5.0 + 1.0 / 3.0, "the centroid of a triangle in x")
	near(p3["com"].y, 5.0 + 2.0 / 3.0, "and y")
	var g4 := _grid()  # a part's mass is spread over its cells
	var ship := Ship.new("t", g4)
	for y in range(4, 8):
		for x in range(4, 6):
			g4.force_tile(Vector2i(x, y), "floor")
	ship.components.place(g4, "reactor_mk1", Vector2i(4, 4), 0)  # 2x4
	var p4 := f.mass_props(g4, ship.components, ship.cables)
	near(p4["mass"], 8.0 + 14.0, "8 floors and the reactor's 14")
	near(p4["com"].x, 5.0, "centred on the reactor and the floor under it")
