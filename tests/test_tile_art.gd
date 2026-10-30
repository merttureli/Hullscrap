extends "res://tests/base_test.gd"
## The structure art (scripts/view/tile_art.gd): mask4 autotiles for walls and cables, floor variants,
## armour walls, doors that open over time, breaches and fire, and the fall back to placeholders when
## the art is missing. Art from tests/fixtures/art (16 px tiles are 2x2 there).

const TileArt = preload("res://scripts/view/tile_art.gd")
const Art = preload("res://scripts/view/art.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const CombatView = preload("res://scripts/combat/combat_view.gd")
const FIXTURES := "res://tests/fixtures/art"
const EMPTY := "res://tests/fixtures/no_such_folder"
const TMP := "user://art_tile_test"
const CELL := Rect2(10, 20, 32, 32)


class FakeCanvas extends RefCounted:
	var calls: Array = []

	func draw_texture_rect_region(tex, rect, src, modulate := Color.WHITE, transpose := false, clip_uv := true) -> void:
		calls.append({"op": "texture", "tex": tex, "rect": rect, "src": src, "modulate": modulate})

	func draw_set_transform_matrix(xf) -> void:
		calls.append({"op": "matrix", "xf": xf})

	func textures() -> Array:
		return calls.filter(func(c): return c["op"] == "texture")


func _use(root: String) -> void:
	Art.root = root
	Art.tier_fallback = true
	Art.clear_cache()


func _done() -> void:
	_use(Art.DEFAULT_ROOT)


func _grid() -> ShipGrid:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(11, 11), defs)
	g.fill_circle_hull(5.0)
	return g


func test_wall_mask_follows_the_solid_neighbours() -> void:
	var g := _grid()
	for c in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6)]:
		g.force_tile(c, "wall")
	eq(TileArt.wall_mask(g, Vector2i(5, 5)), 2 + 4, "E and S")
	eq(TileArt.wall_mask(g, Vector2i(6, 5)), 8, "W")
	eq(TileArt.wall_mask(g, Vector2i(5, 6)), 1, "N")
	eq(TileArt.wall_mask(g, Vector2i(3, 3)), 0, "alone")
	g.force_tile(Vector2i(4, 5), "door")
	eq(TileArt.wall_mask(g, Vector2i(5, 5)), 2 + 4 + 8, "a door joins the wall")
	g.force_tile(Vector2i(5, 4), "floor")
	eq(TileArt.wall_mask(g, Vector2i(5, 5)) & 1, 0, "a floor does not")


func test_a_wall_is_drawn_from_its_mask_frame() -> void:
	_use(FIXTURES)
	var g := _grid()
	g.force_tile(Vector2i(5, 5), "wall")
	g.force_tile(Vector2i(6, 5), "wall")
	var canvas := FakeCanvas.new()
	check(TileArt.wall_tile(canvas, CELL, g, Vector2i(5, 5), "wall", Color("#9aa3b5")), "drawn with art")
	var t: Dictionary = canvas.textures()[0]
	eq(t["src"], Rect2(2 * 2, 0, 2, 2), "frame 2 (E) of the strip")
	eq(t["rect"], CELL, "into the cell")
	eq(t["modulate"], Color.WHITE, "the plain steel wall is not tinted")
	var armour := FakeCanvas.new()
	TileArt.wall_tile(armour, CELL, g, Vector2i(5, 5), "heavy_armor", Color("#5b6577"))
	t = armour.textures()[0]
	eq(t["tex"], Art.tiles("walls_armor").texture, "armour materials use the armour sheet")
	eq(t["modulate"], Color("#5b6577"), "multiplied by the material colour")
	_done()


func test_armour_falls_back_to_tinting_the_plain_walls() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP + "/tiles"))
	var img := Image.create(32, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5))
	img.save_png(TMP + "/tiles/walls.png")
	var f := FileAccess.open(TMP + "/tiles/walls.json", FileAccess.WRITE)
	f.store_string('{"frame": [2, 2]}')
	f.close()
	_use(TMP)
	var g := _grid()
	g.force_tile(Vector2i(5, 5), "scrap_plate")
	var canvas := FakeCanvas.new()
	check(TileArt.wall_tile(canvas, CELL, g, Vector2i(5, 5), "scrap_plate", Color("#7d6f5e")), "drawn")
	var m: Color = canvas.textures()[0]["modulate"]
	check(m != Color.WHITE and m.r < 1.0, "no armour sheet and no mask: the whole sprite is pulled toward the colour (%s)" % m)
	eq(canvas.textures()[0]["src"], Rect2(0, 0, 2, 2), "a 16-frame sheet autotiles without saying so (mask 0 here)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP + "/tiles/walls.png"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP + "/tiles/walls.json"))
	_done()


func test_floor_variants_favour_the_plain_one() -> void:
	_use(FIXTURES)
	var s = Art.tiles("floor")
	eq(s.count, 3, "three variants")
	var counts := [0, 0, 0]
	for x in 32:
		for y in 32:
			counts[TileArt.floor_variant(s, Vector2i(x, y))] += 1
	check(counts[0] > 512 and counts[0] < 768, "the plain floor is about 10 in 16 (%d of 1024)" % counts[0])
	check(counts[1] > 50 and counts[2] > 50, "the others both turn up (%s)" % [counts])
	eq(TileArt.floor_variant(s, Vector2i(7, 9)), TileArt.floor_variant(s, Vector2i(7, 9)), "the same cell always draws the same")
	var canvas := FakeCanvas.new()
	check(TileArt.floor_tile(canvas, CELL, Vector2i(1, 1), 0.5), "floor drawn")
	eq(canvas.textures()[0]["modulate"].a, 0.5, "with the alpha (ghosts)")
	_done()


func test_door_progress_moves_over_time_and_can_turn_round() -> void:
	var st := {}
	eq(TileArt.door_progress(st, "d", true, 0.0, 0.5), 1.0, "first seen open: already open")
	eq(TileArt.door_progress(st, "d", false, 1.0, 0.5), 1.0, "starts to close")
	eq(TileArt.door_progress(st, "d", false, 1.25, 0.5), 0.5, "half way after half the time")
	eq(TileArt.door_progress(st, "d", true, 1.25, 0.5), 0.5, "turns round where it is")
	eq(TileArt.door_progress(st, "d", true, 1.5, 0.5), 1.0, "and finishes opening")
	eq(TileArt.door_progress(st, "other", false, 9.0, 0.5), 0.0, "first seen closed: closed")
	_use(FIXTURES)
	var s = Art.tiles("door")
	eq([TileArt.door_frame(s, 0.0), TileArt.door_frame(s, 0.5), TileArt.door_frame(s, 1.0)], [0, 2, 4], "along the open animation")
	eq(TileArt.door_seconds(s), 0.5, "5 frames at 10 fps")
	eq(TileArt.door_fraction({}, 1, true, 0.0), 1.0, "door_fraction uses the art's timing")
	_done()


func test_a_door_piece_is_turned_for_a_vertical_wall_and_has_its_glow() -> void:
	_use(FIXTURES)
	var rects := [Rect2(0, 0, 32, 32), Rect2(32, 0, 32, 32)]
	var quads := []
	var h := FakeCanvas.new()
	check(TileArt.door_piece(h, rects, true, 1.0, quads), "drawn")
	eq(h.textures().size(), 1, "the door only: the glow goes to the layer")
	eq(h.textures()[0]["rect"], Rect2(-32, -16, 64, 32), "the 2-cell piece about its middle")
	eq(h.textures()[0]["src"], Rect2(16, 0, 4, 2), "the open frame")
	eq(quads.size(), 1, "one glow quad")
	eq(quads[0]["src"], Rect2(24, 0, 6, 4), "the glow frame that goes with it")
	eq(quads[0]["rect"], Rect2(-48, -32, 96, 64), "placed by its offset, scaled with the door (16 px per source px here)")
	var v := FakeCanvas.new()
	TileArt.door_piece(v, [Rect2(0, 0, 32, 32), Rect2(0, 32, 32, 32)], false, 0.0, null)
	check(is_equal_approx(v.calls[0]["xf"].get_rotation(), PI / 2.0), "a vertical piece is turned a quarter")
	eq(v.textures().size(), 2, "with no layer the glow is drawn over the door")
	eq(v.textures()[0]["src"], Rect2(0, 0, 4, 2), "closed frame")
	_done()


func test_cables_autotile_and_light_up_when_powered() -> void:
	_use(FIXTURES)
	var cells := {Vector2i(2, 2): true, Vector2i(3, 2): true, Vector2i(2, 3): true}
	var has := func(c: Vector2i) -> bool: return cells.has(c)
	var dull := FakeCanvas.new()
	check(TileArt.cable(dull, CELL, has, Vector2i(2, 2)), "drawn")
	eq(dull.textures()[0]["src"], Rect2(6 * 2, 0, 2, 2), "E and S neighbours: frame 6")
	eq(dull.textures()[0]["tex"], Art.tiles("cable").texture, "the dull sheet")
	eq(dull.textures().size(), 1, "no glow when unpowered")
	var lit := FakeCanvas.new()
	TileArt.cable(lit, CELL, has, Vector2i(3, 2), true)
	eq(lit.textures()[0]["tex"], Art.tiles("cable_on").texture, "powered: the cable_on sheet")
	eq(lit.textures()[0]["src"], Rect2(8 * 2, 0, 2, 2), "W neighbour: frame 8")
	eq(lit.textures().size(), 2, "and its glow")
	_done()


func test_breach_and_fire() -> void:
	_use(FIXTURES)
	var canvas := FakeCanvas.new()
	check(TileArt.breach(canvas, CELL, Vector2i(3, 4)), "breach drawn")
	check(canvas.textures()[0]["src"].position.x in [0.0, 2.0, 4.0, 6.0], "one of its frames")
	var quads := []
	var fire := FakeCanvas.new()
	check(TileArt.fire_cell(fire, CELL, 1.0, 0.0, Vector2i(1, 1), quads), "fire drawn")
	var t: Dictionary = fire.textures()[0]
	eq(t["rect"].end.y, CELL.end.y, "the flames stand on the bottom edge of the cell")
	eq(t["rect"].size, Vector2(2, 2) * 2.0, "full size at full intensity: 2x2 source px at 2 px each")
	eq(quads.size(), 1, "with its glow")
	var small := FakeCanvas.new()
	TileArt.fire_cell(small, CELL, 0.0, 0.0, Vector2i(1, 1))
	check(small.textures()[0]["rect"].size.x < t["rect"].size.x, "a weak fire is smaller")
	check(small.textures()[0]["modulate"].a < t["modulate"].a, "and dimmer")
	var phases := {}
	for x in 20:
		var c := FakeCanvas.new()
		TileArt.fire_cell(c, CELL, 1.0, 0.0, Vector2i(x, 0))
		phases[c.textures()[0]["src"].position.x] = true
	check(phases.size() > 1, "neighbouring fires start on different frames")
	_done()


func test_without_art_every_tile_path_says_so() -> void:
	_use(EMPTY)
	var g := _grid()
	var canvas := FakeCanvas.new()
	var has := func(c: Vector2i) -> bool: return false
	check(not TileArt.floor_tile(canvas, CELL, Vector2i(1, 1)), "floor")
	check(not TileArt.wall_tile(canvas, CELL, g, Vector2i(1, 1), "wall", Color.GRAY), "wall")
	check(not TileArt.door_piece(canvas, [CELL], true, 0.0), "door")
	check(not TileArt.breach(canvas, CELL, Vector2i(1, 1)), "breach")
	check(not TileArt.cable(canvas, CELL, has, Vector2i(1, 1)), "cable")
	check(not TileArt.fire_cell(canvas, CELL, 1.0, 0.0, Vector2i(1, 1)), "fire")
	eq(canvas.calls.size(), 0, "and nothing was drawn")
	_done()


func test_beams_are_tiled_from_whole_pieces() -> void:
	var pieces := CombatView.beam_pieces(100.0, 32.0)
	eq(pieces.size(), 4, "three whole tiles and a cut one")
	eq(pieces.map(func(p): return p["len"]), [32.0, 32.0, 32.0, 4.0], "lengths")
	eq(pieces.map(func(p): return p["from"]), [0.0, 32.0, 64.0, 96.0], "each starts where the last ended")
	eq(CombatView.beam_pieces(10.0, 32.0).size(), 1, "a short beam is one cut piece")
	eq(CombatView.beam_pieces(0.0, 32.0).size(), 0, "no length, no pieces")
	eq(CombatView.beam_pieces(64.0, 32.0).size(), 2, "an exact fit has no stub")
