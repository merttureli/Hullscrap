extends "res://tests/base_test.gd"
## The wall tool's shapes in build mode (scripts/build/build_mode.gd), driven without a scene tree: T cycles
## full, slope45, slope2 and round2, R turns the piece and Shift+R mirrors it, the ghost is the piece's
## real outline (red with the reason when it is refused), a click builds it as one undo step, and the
## hint line shows the keys.

const BuildMode = preload("res://scripts/build/build_mode.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const Shapes = preload("res://scripts/ship/shapes.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const AT := Vector2i(8, 8)


## A build mode on a ship of its own with the Steel Wall selected and the mouse on AT.
func _build(cargo := {"scrap": 200, "titanium": 20}) -> BuildMode:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(20, 20), defs)
	g.fill_circle_hull(9.0)
	var ship := Ship.new("T", g)
	ship.inventory.load_dict(cargo)
	var sim := ShipSim.new()
	sim.ships = [ship]
	var b := BuildMode.new()
	b.sim = sim
	b.selected = "wall"
	b.hover = AT
	return b


func _done(b: BuildMode) -> void:
	b.sim.free()
	b.free()


func _key(b: BuildMode, code: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	b._on_key(e)


func _click(b: BuildMode, button: int) -> void:
	b.dragging = true
	b.drag_button = button
	b.drag_mode = BuildSession.Mode.PAINT
	b.drag_start = b.hover
	b.drag_path = [b.hover]
	b._end_drag()


func _pick(b: BuildMode, piece: String) -> void:
	while b.wall_piece != piece:
		_key(b, KEY_T)


func test_t_cycles_the_wall_tool_through_the_pieces() -> void:
	var b := _build()
	eq(b.wall_piece, "full", "walls start full")
	var seen: Array[String] = []
	for i in 4:
		_key(b, KEY_T)
		seen.append(b.wall_piece)
	eq(seen, ["slope45", "slope2", "round2", "full"] as Array[String], "full > slope45 > slope2 > round2 > full")
	_key(b, KEY_T)
	eq(b.message, "wall shape: slope45", "it says which")
	b.selected = "floor"
	_key(b, KEY_T)
	check(b.message.contains("pick a wall"), "with a floor selected it says the shape is for walls (%s)" % b.message)
	check(not b._shaped_wall(), "and the floor tool stays square")
	_done(b)


func test_r_turns_the_piece_and_shift_r_mirrors_it() -> void:
	var b := _build()
	_pick(b, "slope2")
	for i in 4:
		_key(b, KEY_R)
	eq(b.shape_rot, 0, "four turns come back round")
	_key(b, KEY_R)
	_key(b, KEY_R)
	eq(b.shape_rot, 2, "R turns a quarter at a time")
	check(not b.shape_mirror, "no mirror yet")
	_key(b, KEY_R, true)
	check(b.shape_mirror, "Shift+R mirrors")
	eq(b.shape_rot, 2, "and keeps the turn")
	_key(b, KEY_R, true)
	check(not b.shape_mirror, "again mirrors back")
	eq(b.rot, 0, "the rotation of systems is its own")
	b.group = BuildMode.Group.SYSTEMS
	_key(b, KEY_R)
	eq(b.rot, 1, "with a system selected R turns the system")
	eq(b.shape_rot, 2, "and leaves the shape alone")
	_done(b)


func test_the_ghost_is_the_real_outline_of_the_piece() -> void:
	var b := _build()
	_pick(b, "slope2")
	_key(b, KEY_R)  # turned a quarter: 1 wide, 2 tall
	_key(b, KEY_R, true)
	b._refresh_ghost()
	eq(b.ghost.size(), 1, "one ghost for the piece")
	var g: Dictionary = b.ghost[0]
	eq(g["layer"], "piece", "a piece")
	eq(g["reason"], "", "it fits: green")
	eq([g["piece"], g["tile"], g["anchor"], g["rot"], g["mirror"]], ["slope2", "wall", AT, 1, true], "the tool's state")
	var cells := Shapes.piece_cells(g["piece"], g["anchor"], g["rot"], g["mirror"])
	eq(cells.size(), 2, "two cells")
	eq(Shapes.piece_size("slope2", 1), Vector2i(1, 2), "1x2 when turned")
	var area := 0.0
	for pc in cells:
		area += Shapes.area(pc["shape"])
	check(absf(area - 1.0) < 1e-6, "the polygons are the slope's: a small triangle and a trapezoid")
	_done(b)


func test_a_refused_piece_shows_red_with_the_reason() -> void:
	var b := _build()
	_pick(b, "round2")
	b.hover = Vector2i(0, 0)  # in the grid, outside the hull
	b._refresh_ghost()
	eq(b.ghost[0]["reason"], "outside the hull", "the reason")
	check(b.hud_text().contains("can't: outside the hull"), "it is in the HUD")
	b.hover = Vector2i(19, 19)  # the piece would leave the grid: plan_piece itself refuses
	b._refresh_ghost()
	eq(b.ghost.size(), 1, "there is still a ghost to draw red")
	eq(b.ghost[0]["layer"], "piece", "of the piece")
	eq(b.ghost[0]["anchor"], Vector2i(19, 19), "where the mouse is")
	eq(b.ghost[0]["reason"], "outside the hull", "with plan_piece's reason")
	b.hover = AT
	b._refresh_ghost()
	eq(b.ghost[0]["reason"], "", "back in the hull it is green")
	_done(b)
	var poor := _build({"scrap": 1})
	_pick(poor, "round2")
	poor._refresh_ghost()
	eq(poor.ghost[0]["reason"], "not enough scrap", "a piece you cannot pay for is red")
	_done(poor)


func test_a_click_builds_the_piece_as_one_undo_step_and_redo_brings_it_back() -> void:
	var b := _build()
	_pick(b, "slope2")
	var steps: int = b.session.undo_stack.size()
	var cargo: int = b.ship.inventory.count("scrap")
	_click(b, MOUSE_BUTTON_LEFT)
	eq(b.message, "", "no complaint")
	eq(b.session.undo_stack.size(), steps + 1, "one undo step")
	eq(b.grid.shape_of(AT), {"shape": "tri2_low", "rot": 0, "mirror": false}, "the low half")
	eq(b.grid.shape_of(AT + Vector2i.RIGHT), {"shape": "tri2_high", "rot": 0, "mirror": false}, "and the high half")
	eq(b.ship.inventory.count("scrap"), cargo - 3, "paid by area: a quarter of 2 scrap rounds up to 1, three quarters to 2")
	b._undo()
	check(b.grid.get_tile(AT) == "" and b.grid.get_tile(AT + Vector2i.RIGHT) == "", "undo takes both away")
	eq(b.ship.inventory.count("scrap"), cargo, "and refunds them")
	b._redo()
	eq(b.grid.shape_of(AT + Vector2i.RIGHT), {"shape": "tri2_high", "rot": 0, "mirror": false}, "redo builds them again")
	_done(b)


func test_a_rotated_and_mirrored_piece_goes_down_the_way_the_ghost_shows() -> void:
	var b := _build()
	_pick(b, "round2")
	_key(b, KEY_R)
	_key(b, KEY_R, true)
	_click(b, MOUSE_BUTTON_LEFT)
	for pc in Shapes.piece_cells("round2", AT, 1, true):
		eq(b.grid.shape_of(pc["cell"]), {"shape": pc["shape"], "rot": 1, "mirror": true}, "cell %s" % [pc["cell"]])
	eq(b.grid.shapes.size(), 4, "four cells")
	_done(b)


func test_a_drag_with_a_piece_places_one_piece_and_the_right_button_removes_cells() -> void:
	var b := _build()
	_pick(b, "slope45")
	b.dragging = true
	b.drag_button = MOUSE_BUTTON_LEFT
	b.drag_mode = BuildSession.Mode.RECT
	b.drag_start = Vector2i(4, 4)
	b.hover = Vector2i(9, 9)
	b._end_drag()
	eq(b.grid.tiles.size(), 1, "a rectangle drag still builds the one piece, at the mouse")
	eq(b.grid.get_tile(Vector2i(9, 9)), "wall", "at the release cell")
	_click(b, MOUSE_BUTTON_RIGHT)
	eq(b.grid.tiles.size(), 0, "right click removes the cell under the mouse")
	_done(b)


func test_the_hint_line_shows_the_shape_keys() -> void:
	var b := _build()
	check(b.hud_text().contains("T shape"), "a wall: T is offered")
	_pick(b, "slope45")
	var hud := b.hud_text()
	for k in ["T shape", "R rotate", "Shift+R mirror", "slope45"]:
		check(hud.contains(k), "the hint line has %s" % k)
	b.selected = "floor"
	check(not b.hud_text().contains("T shape"), "the floor tool has no shapes")
	b.selected = "door"
	check(b.hud_text().contains("R flip"), "the door keeps R flip")
	_done(b)
