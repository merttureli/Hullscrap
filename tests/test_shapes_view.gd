extends "res://tests/base_test.gd"
## Shaped walls on screen (scripts/view/tile_art.gd): the sheet row of every orientation, the 60% rule
## for a neighbour that joins, the shaped and ram sheets a wall is drawn from, floor under a slope that
## looks into the ship, and the exterior hull skin (which sides face space, shaped cells, ram plating,
## the tint by dominant line, panel variants and decals). Art from the shipped art/ folder.

const TileArt = preload("res://scripts/view/tile_art.gd")
const Art = preload("res://scripts/view/art.gd")
const Shapes = preload("res://scripts/ship/shapes.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const CELL := Rect2(10, 20, 32, 32)
const TRI_TL := {"shape": "tri", "rot": 1, "mirror": false}  ## the top-left half: solid against the north and west walls


class FakeCanvas extends RefCounted:
	var calls: Array = []

	func draw_texture_rect_region(tex, rect, src, modulate := Color.WHITE, transpose := false, clip_uv := true) -> void:
		calls.append({"op": "texture", "tex": tex, "rect": rect, "src": src, "modulate": modulate})

	func draw_set_transform_matrix(xf) -> void:
		pass

	func draw_rect(rect, color, filled := true, width := -1.0) -> void:
		calls.append({"op": "rect", "rect": rect, "color": color})

	func draw_colored_polygon(points, color) -> void:
		calls.append({"op": "polygon", "points": points, "color": color})

	func textures() -> Array:
		return calls.filter(func(c): return c["op"] == "texture")


func _art() -> void:
	Art.root = Art.DEFAULT_ROOT
	Art.tier_fallback = true
	Art.clear_cache()


func _grid(n := 24) -> ShipGrid:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(n, n), defs)
	g.fill_circle_hull(n / 2.0)
	return g


## A ring of `wall` from (3, 3) to (3 + w - 1, 3 + h - 1) round floor.
func _ring(g: ShipGrid, w: int, h: int, wall := "wall") -> void:
	for y in range(3, 3 + h):
		for x in range(3, 3 + w):
			var edge: bool = x == 3 or y == 3 or x == 3 + w - 1 or y == 3 + h - 1
			g.force_tile(Vector2i(x, y), wall if edge else "floor")


func _entry(plan: Dictionary, c: Vector2i) -> Dictionary:
	for e in plan["cells"]:
		if e["c"] == c:
			return e
	return {}


func test_the_sheet_row_of_every_orientation() -> void:
	for mirror in [false, true]:
		for rot in 4:
			for i in TileArt.SHAPE_CELLS.size():
				var orient := (4 if mirror else 0) + rot
				eq(TileArt.shape_row({"shape": TileArt.SHAPE_CELLS[i], "rot": rot, "mirror": mirror}), orient * 7 + i, "orient %d cell %d" % [orient, i])
	eq(TileArt.shape_row({}), -1, "a full square has no row")
	eq(TileArt.shape_row({"shape": "mystery", "rot": 0, "mirror": false}), -1, "nor has a shape with no art")
	eq(TileArt.shape_row({"shape": "tri", "rot": 5, "mirror": false}), 7, "turns wrap round")
	for id in Shapes.shape_ids():
		check(id == Shapes.FULL or TileArt.shape_row({"shape": id, "rot": 0, "mirror": false}) >= 0, "%s has a row in the sheets" % id)


func test_every_row_of_the_wall_sheet_matches_its_polygon() -> void:
	_art()
	var s = Art.tiles("walls_shapes")
	check(s != null and s.count == 16 * 56, "the sheet is 16 x 56 frames")
	if s == null:
		return
	for mirror in [false, true]:
		for rot in 4:
			for i in TileArt.SHAPE_CELLS.size():
				var sd := {"shape": TileArt.SHAPE_CELLS[i], "rot": rot, "mirror": mirror}
				var at: Vector2 = s.region(TileArt.shape_row(sd) * 16 + 15).position  # all four neighbours solid
				var poly := Shapes.cell_polygon(sd["shape"], rot, mirror)
				var off := 0
				for y in 16:
					for x in 16:
						var drawn: bool = s.image.get_pixel(int(at.x) + x, int(at.y) + y).a > 0.0
						if drawn != Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5) / 16.0, poly):
							off += 1
				check(off <= 12, "%s rot %d mirror %s: %d pixels off its polygon" % [sd["shape"], rot, mirror, off])


func test_a_neighbour_joins_when_it_covers_sixty_percent_of_the_edge() -> void:
	var g := _grid()
	var here := Vector2i(5, 5)
	g.force_tile(here, "wall")
	var east := here + Vector2i.RIGHT
	var cases := [
		["tri", 0, false, 1.0, true],  # its left edge is whole
		["tri2_low", 0, false, 0.0, false],  # only touches the corner
		["tri2_high", 0, false, 0.5, false],  # half the edge
		["tri2_high", 0, true, 1.0, true],  # mirrored: the tall side faces us
		["round2_tr", 0, false, 0.722, true],
		["round2_tl", 0, false, 0.0, false],
		["round2_br", 0, false, 1.0, true],
	]
	for k in cases:
		g.force_tile(east, "wall", {"shape": k[0], "rot": k[1], "mirror": k[2]})
		var got: float = TileArt.cover(g, east, Vector2i.LEFT)
		check(absf(got - k[3]) < 0.01, "%s %s covers %s of the shared edge, got %s" % [k[0], k[2], k[3], got])
		eq(TileArt.wall_mask(g, here) & 2 != 0, k[4], "%s %s joins: %s" % [k[0], k[2], k[4]])
	var poly := PackedVector2Array([Vector2(0, 0.4), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	check(absf(TileArt.edge_cover(poly, Vector2i.LEFT) - 0.6) < 1e-6, "a polygon that covers 0.6")
	check(TileArt.edge_cover(poly, Vector2i.LEFT) >= TileArt.JOIN_COVER - TileArt.EDGE_EPS, "which is just enough")
	check(TileArt.edge_cover(poly, Vector2i.UP) < TileArt.JOIN_COVER, "its top edge is a single corner")


func test_every_side_of_a_shaped_neighbour_is_measured_on_the_shared_edge() -> void:
	var g := _grid()
	var here := Vector2i(5, 5)
	g.force_tile(here, "wall")
	g.force_tile(here + Vector2i.UP, "wall", {"shape": "tri", "rot": 0, "mirror": false})  # bottom-left half: its bottom edge is whole
	g.force_tile(here + Vector2i.DOWN, "wall", {"shape": "tri", "rot": 0, "mirror": false})  # its top edge is a corner
	g.force_tile(here + Vector2i.LEFT, "wall", TRI_TL)  # top-left half: its right edge is a corner
	g.force_tile(here + Vector2i.RIGHT, "door")  # a door always joins
	eq(TileArt.wall_mask(g, here), 1 + 2, "N and E join, S and W do not")
	g.force_tile(here + Vector2i.DOWN, "floor")
	eq(TileArt.wall_mask(g, here) & 4, 0, "floor does not")


func test_a_wall_is_drawn_from_the_shaped_sheet() -> void:
	_art()
	var g := _grid()
	var c := Vector2i(5, 5)
	g.force_tile(c, "wall", {"shape": "tri2_low", "rot": 1, "mirror": true})  # orient 5, cell 1
	var canvas := FakeCanvas.new()
	check(TileArt.wall_tile(canvas, CELL, g, c, "wall", Color("#9aa3b5")), "drawn with art")
	var t: Dictionary = canvas.textures()[0]
	eq(t["tex"], Art.tiles("walls_shapes").texture, "from walls_shapes")
	eq(t["src"], Rect2(0, (5 * 7 + 1) * 16, 16, 16), "row 36, mask 0")
	eq(t["modulate"], Color.WHITE, "the plain wall is not tinted")
	g.force_tile(c + Vector2i.LEFT, "wall")
	g.force_tile(c + Vector2i.DOWN, "wall")
	canvas = FakeCanvas.new()
	TileArt.wall_tile(canvas, CELL, g, c, "wall", Color.WHITE)
	eq(canvas.textures()[0]["src"], Rect2((4 + 8) * 16, 36 * 16, 16, 16), "the mask column follows the joining neighbours (W and S)")
	var armour := FakeCanvas.new()
	TileArt.wall_tile(armour, CELL, g, c, "heavy_armor", Color("#5b6577"))
	t = armour.textures()[0]
	eq(t["tex"], Art.tiles("walls_armor_shapes").texture, "armour materials use the armour shapes")
	eq(t["modulate"], Color("#5b6577"), "multiplied by the material colour")
	g.shapes[c] = {"shape": "mystery", "rot": 0, "mirror": false}
	check(not TileArt.wall_tile(FakeCanvas.new(), CELL, g, c, "wall", Color.WHITE), "a shape with no art falls back to the placeholder")


func test_ram_plating_is_drawn_from_the_ram_sheets_with_no_tint() -> void:
	_art()
	var g := _grid()
	g.force_tile(Vector2i(5, 5), "ram_plating")
	g.force_tile(Vector2i(8, 5), "ram_plating", {"shape": "tri2_high", "rot": 0, "mirror": false})
	var canvas := FakeCanvas.new()
	check(TileArt.wall_tile(canvas, CELL, g, Vector2i(5, 5), "ram_plating", Color("#b9875a")), "full cell")
	var t: Dictionary = canvas.textures()[0]
	eq(t["tex"], Art.tiles("walls_ram").texture, "walls_ram")
	eq(t["modulate"], Color.WHITE, "no tint, whatever the tile colour")
	canvas = FakeCanvas.new()
	TileArt.wall_tile(canvas, CELL, g, Vector2i(8, 5), "ram_plating", Color("#b9875a"))
	t = canvas.textures()[0]
	eq(t["tex"], Art.tiles("walls_ram_shapes").texture, "walls_ram_shapes")
	eq(t["modulate"], Color.WHITE, "no tint")
	eq(t["src"], Rect2(0, 2 * 16, 16, 16), "tri2_high is cell 2 of orientation 0")


func test_the_open_part_of_a_slope_shows_floor_inside_and_space_outside() -> void:
	_art()
	var g := _grid()
	_ring(g, 12, 8)
	var corner := Vector2i(4, 4)  # inside the room, next to the north and west walls
	g.force_tile(corner, "wall", TRI_TL)
	check(TileArt.open_over_floor(g, corner), "its open half looks onto the floor")
	var canvas := FakeCanvas.new()
	TileArt.solid_cell(canvas, CELL, g, corner, "wall", Color("#9aa3b5"))
	var t := canvas.textures()
	eq(t.size(), 2, "floor, then the wall")
	eq(t[0]["tex"], Art.tiles("floor").texture, "floor under it")
	eq(t[1]["tex"], Art.tiles("walls_shapes").texture, "the slope over it")
	var out := Vector2i(14, 3)  # a hull corner: the slope's open half faces empty space
	g.force_tile(out, "wall", {"shape": "tri", "rot": 0, "mirror": false})
	check(not TileArt.open_over_floor(g, out), "no floor beside the open half")
	canvas = FakeCanvas.new()
	TileArt.solid_cell(canvas, CELL, g, out, "wall", Color("#9aa3b5"))
	eq(canvas.textures().size(), 1, "just the slope, space shows through the rest")
	check(not TileArt.open_over_floor(g, Vector2i(3, 3)), "a full wall has no open part")


func test_with_no_art_a_slope_is_a_flat_polygon() -> void:
	Art.root = "res://tests/fixtures/no_such_folder"
	Art.clear_cache()
	var g := _grid()
	g.force_tile(Vector2i(5, 5), "wall", {"shape": "tri", "rot": 0, "mirror": false})
	g.force_tile(Vector2i(8, 5), "wall")
	var canvas := FakeCanvas.new()
	TileArt.solid_cell(canvas, CELL, g, Vector2i(5, 5), "wall", Color("#9aa3b5"))
	eq(canvas.calls.size(), 1, "one call")
	eq(canvas.calls[0]["op"], "polygon", "a polygon")
	eq(canvas.calls[0]["points"].size(), 3, "of the triangle")
	eq(canvas.calls[0]["points"][2], CELL.position + Vector2(0, 32), "in the cell's own pixels")
	canvas = FakeCanvas.new()
	TileArt.solid_cell(canvas, CELL, g, Vector2i(8, 5), "wall", Color("#9aa3b5"))
	eq(canvas.calls[0]["op"], "rect", "a full wall stays the flat square")
	_art()


func test_the_skin_mask_is_the_sides_that_face_space() -> void:
	var g := _grid()
	_ring(g, 12, 8)
	var plan := TileArt.skin_plan(g)
	eq(_entry(plan, Vector2i(3, 3))["mask"], 1 + 8, "the corner: north and west")
	eq(_entry(plan, Vector2i(6, 3))["mask"], 1, "the top: north")
	eq(_entry(plan, Vector2i(14, 6))["mask"], 2, "the east side")
	eq(_entry(plan, Vector2i(14, 10))["mask"], 2 + 4, "the corner: east and south")
	eq(_entry(plan, Vector2i(6, 10))["mask"], 4, "the bottom")
	eq(_entry(plan, Vector2i(5, 5)), {}, "floor has no skin")
	eq(plan["cells"].size(), 2 * 12 + 2 * 6, "every wall of the ring")
	g.force_tile(Vector2i(8, 3), "door")  # a door in the north wall
	eq(TileArt.skin_mask(g, Vector2i(7, 3)), 1, "a door beside a wall is not space")
	check(_entry(TileArt.skin_plan(g), Vector2i(8, 3)).is_empty(), "and has no skin itself")
	g.breach(Vector2i(6, 3))
	var hole := TileArt.skin_plan(g)
	eq(_entry(hole, Vector2i(5, 3))["mask"], 1 + 2, "a breach opens the side beside it to space")
	eq(_entry(hole, Vector2i(7, 3))["mask"], 1 + 8, "from both sides")


func test_the_skin_follows_the_cut_edge_of_shaped_cells() -> void:
	var g := _grid()
	_ring(g, 12, 8)
	var out := Vector2i(14, 3)  # the top-right corner, cut: solid bottom-left, the open half faces space
	g.force_tile(out, "wall", {"shape": "tri", "rot": 0, "mirror": false})
	var inside := Vector2i(4, 4)  # a chamfer in a room's corner: the open half faces the floor
	g.force_tile(inside, "wall", TRI_TL)
	var plan := TileArt.skin_plan(g)
	var e := _entry(plan, out)
	check(not e.is_empty(), "the cut corner is skinned")
	eq(e["row"], TileArt.shape_row({"shape": "tri", "rot": 0, "mirror": false}), "from the shaped sheet's row")
	eq(e["mask"] & (4 + 8), 0, "its flat sides (south, west) touch walls")
	eq(e["mask"] & (1 + 2), 1 + 2, "the sides of the cut face space (the sheet ignores those bits)")
	check(_entry(plan, inside).is_empty(), "a slope that looks into the ship has no skin")
	eq(_entry(plan, Vector2i(13, 3))["mask"], 1, "the wall beside the cut corner joins its whole left edge")
	eq(_entry(plan, Vector2i(14, 4))["mask"], 2, "and so does the cell below it")
	g.force_tile(Vector2i(8, 3), "ram_plating")
	plan = TileArt.skin_plan(g)
	check(_entry(plan, Vector2i(8, 3)).is_empty(), "ram plating keeps its hazard tape: no skin")
	eq(_entry(plan, Vector2i(7, 3))["mask"], 1, "and it is a wall beside it, not space")
	g.force_tile(Vector2i(10, 3), "wall", {"shape": "tri2_low", "rot": 0, "mirror": false})  # a low ramp: it touches the wall on its left only at a corner
	plan = TileArt.skin_plan(g)
	eq(_entry(plan, Vector2i(10, 3))["row"], TileArt.shape_row({"shape": "tri2_low", "rot": 0, "mirror": false}), "every shape finds its row")
	eq(_entry(plan, Vector2i(9, 3))["mask"], 1 + 2, "the wall beside it faces the ramp's open half, which is space")


func test_the_skin_tint_follows_the_dominant_line() -> void:
	_art()
	var sheet = Art.tiles("hull_skin")
	check(sheet != null, "the skin sheet")
	var g := _grid()
	_ring(g, 10, 8, "scrap_plate")
	eq(TileArt.skin_plan(g)["line"], "scrap", "scrap plates all round")
	eq(TileArt.skin_tint(sheet, "scrap"), Color8(255, 184, 133), "scrap rust")
	eq(TileArt.skin_tint(sheet, "standard"), Color8(237, 250, 255), "standard clean")
	eq(TileArt.skin_tint(sheet, "neon"), Color8(92, 112, 189), "neon navy")
	eq(TileArt.skin_tint(sheet, "mystery"), Color8(237, 250, 255), "an unknown line gets the standard tint")
	_ring(g, 10, 8, "reflective_coating")
	eq(TileArt.skin_plan(g)["line"], "neon", "a neon shell")
	eq(TileArt.skin_glow(sheet, "neon"), Color8(64, 242, 255), "which glows")
	eq(TileArt.skin_glow(sheet, "scrap"), null, "the others do not")
	_ring(g, 10, 8, "wall")
	eq(TileArt.skin_plan(g)["line"], "standard", "steel")
	for x in range(3, 7):  # half of the north side turns scrap: the most is still standard
		g.force_tile(Vector2i(x, 3), "scrap_plate")
	eq(TileArt.skin_plan(g)["line"], "standard", "the most cells win")
	for x in range(7, 13):
		g.force_tile(Vector2i(x, 3), "scrap_plate")
	eq(TileArt.skin_plan(g)["line"], "standard", "10 scrap of 32 is not the most")
	eq(TileArt.dominant_line({"scrap": 3, "standard": 3}), "standard", "a tie goes to standard")
	eq(TileArt.dominant_line({"scrap": 4, "neon": 3}), "scrap", "")
	eq(TileArt.dominant_line({}), "standard", "an empty ship is standard")


func test_panel_variants_and_decals_come_from_the_position() -> void:
	var g := _grid(48)
	for y in range(2, 30):
		for x in range(2, 44):
			g.force_tile(Vector2i(x, y), "wall" if x in [2, 43] or y in [2, 29] else "floor")
	var a := TileArt.skin_plan(g)
	var b := TileArt.skin_plan(g)
	eq(a, b, "the same ship, the same skin")
	var variants := {}
	var decals := 0
	var vents := 0
	for e in a["cells"]:
		check(e["variant"] >= 0 and e["variant"] < 4, "a variant of the four")
		variants[e["variant"]] = true
		eq(e["variant"], posmod(hash(e["c"]), 4), "by the cell's position")
		if e["decal"] != "":
			decals += 1
			check(e["decal"] in TileArt.DECALS, "a known decal")
			check(e["mask"] in [1, 2, 4, 8], "only on a flat run")
			eq(_entry(a, e["c"] + Vector2i.LEFT).get("decal", ""), "", "never on the cell after a decal")
		if e["decal"] == "vent":
			vents += 1
			eq(_entry(a, e["c"] + Vector2i.RIGHT)["mask"], e["mask"], "a vent has skin of the same face beside it")
			check(e["mask"] in [1, 4], "and lies along a horizontal run")
	eq(variants.size(), 4, "all four panels turn up")
	var n: int = a["cells"].size()
	check(decals > n / 25 and decals < n / 4, "decals are sparse: %d of %d" % [decals, n])
	check(vents > 0, "and some are vents")


func test_a_skin_plan_draws_the_skin_the_glow_and_the_decals() -> void:
	_art()
	var g := _grid(48)
	for y in range(2, 22):
		for x in range(2, 30):
			g.force_tile(Vector2i(x, y), "reflective_coating" if x in [2, 29] or y in [2, 21] else "floor")
	g.force_tile(Vector2i(12, 2), "wall", {"shape": "tri", "rot": 0, "mirror": false})
	var plan := TileArt.skin_plan(g)
	eq(plan["line"], "neon", "a neon ship")
	var canvas := FakeCanvas.new()
	var glow := []
	check(TileArt.draw_skin(canvas, plan, Vector2(100, 200), 32.0, 0.0, glow), "drawn")
	var skin = Art.tiles("hull_skin")
	var tint := TileArt.skin_tint(skin, "neon")
	var first: Dictionary = plan["cells"][0]
	var t: Dictionary = canvas.textures()[0]
	eq(t["tex"], skin.texture, "the first cell from the skin sheet")
	eq(t["src"], Rect2(first["mask"] * 16, first["variant"] * 16, 16, 16), "its mask column, its panel variant row")
	eq(t["rect"], Rect2(Vector2(100, 200) + Vector2(first["c"]) * 32.0, Vector2(32, 32)), "in its cell")
	eq(t["modulate"], tint, "multiplied by the line's tint")
	var shaped: Dictionary = _entry(plan, Vector2i(12, 2))
	var hit := canvas.textures().filter(func(c): return c["tex"] == Art.tiles("hull_skin_shapes").texture)
	eq(hit.size(), 1, "the slope comes from the shapes sheet")
	eq(hit[0]["src"], Rect2(shaped["mask"] * 16, shaped["row"] * 16, 16, 16), "by its row")
	check(glow.size() >= plan["cells"].size(), "neon adds an edge glow to every skin cell")
	eq(glow[0]["mod"], Color8(64, 242, 255), "in the neon cyan")
	eq(glow[0]["rect"].size, Vector2(22, 22) * 2.0, "22 px frames at the cell's scale")
	var decals: int = plan["cells"].filter(func(e): return e["decal"] != "").size()
	check(decals > 0, "the long walls take decals")
	eq(canvas.textures().size(), plan["cells"].size() + decals, "one more draw per decal")
	# a scrap ship: no edge glow
	for c in g.tiles.keys():
		if g.tiles[c] == "reflective_coating":
			g.force_tile(c, "scrap_plate")
	var plain := []
	TileArt.draw_skin(FakeCanvas.new(), TileArt.skin_plan(g), Vector2.ZERO, 32.0, 0.0, plain)
	check(plain.size() <= decals + 1, "a scrap skin glows only at the lamps and the antennas (%d quads)" % plain.size())


func test_the_skin_draws_nothing_without_art() -> void:
	Art.root = "res://tests/fixtures/no_such_folder"
	Art.clear_cache()
	var g := _grid()
	_ring(g, 8, 6)
	check(not TileArt.draw_skin(FakeCanvas.new(), TileArt.skin_plan(g), Vector2.ZERO, 32.0, 0.0), "no sheet, no skin")
	_art()
