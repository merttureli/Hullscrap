extends "res://tests/base_test.gd"
## The door-piece handling of the build mode node, driven without a scene tree: the ghost, R, a
## placement and a removal by mouse, and E.

const BuildMode = preload("res://scripts/build/build_mode.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const AT := Vector2i(8, 10)  # the first cell of a piece in the wall


## A build mode on a ship of its own, Door selected, with a wall along row 10 (x 5..12), or along
## column 10 (y 5..12) when `vertical`.
func _build(vertical := false) -> BuildMode:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(20, 20), defs)
	g.fill_circle_hull(9.0)
	var ship := Ship.new("T", g)
	ship.inventory.load_dict({"scrap": 200, "copper": 20})
	var sim := ShipSim.new()
	sim.ships = [ship]
	var b := BuildMode.new()
	b.sim = sim
	b.selected = "door"
	var cells := []
	for i in range(5, 13):
		cells.append(Vector2i(10, i) if vertical else Vector2i(i, 10))
	b.session.apply(b.session.plan(BuildSession.Mode.PAINT, "wall", false, cells[0], cells[-1], cells)["changes"])
	b.hover = Vector2i(10, 8) if vertical else AT
	return b


func _done(b: BuildMode) -> void:
	b.sim.free()
	b.free()


## A click on the cell under the mouse: press and release of `button`.
func _click(b: BuildMode, button: int) -> void:
	b.dragging = true
	b.drag_button = button
	b.drag_mode = BuildSession.Mode.PAINT
	b.drag_start = b.hover
	b.drag_path = [b.hover]
	b._end_drag()


func _key(b: BuildMode, code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	b._on_key(e)


func test_the_ghost_is_a_two_cell_piece_turned_to_fit_the_wall() -> void:
	var b := _build()
	b._refresh_ghost()
	eq(b.ghost.size(), 1, "one ghost for the piece")
	eq(b.ghost[0]["reason"], "", "it fits: green")
	eq(b._ghost_cells(b.ghost[0]), [AT, AT + Vector2i.RIGHT] as Array[Vector2i], "2x1 along the horizontal wall")
	_done(b)
	var v := _build(true)
	v._refresh_ghost()
	eq(v.ghost[0]["reason"], "", "fits the vertical wall too")
	eq(v._ghost_cells(v.ghost[0]), [Vector2i(10, 8), Vector2i(10, 9)] as Array[Vector2i], "1x2 along the vertical wall")
	_done(v)


func test_r_flips_the_door_piece_and_a_bad_fit_shows_red() -> void:
	var b := _build()
	_key(b, KEY_R)
	b._refresh_ghost()
	eq(b._ghost_cells(b.ghost[0]), [AT, AT + Vector2i.DOWN] as Array[Vector2i], "flipped across the wall")
	eq(b.ghost[0]["reason"], "doors need walls at both ends", "and it does not fit: red, with the reason")
	_key(b, KEY_R)
	b._refresh_ghost()
	eq(b._ghost_cells(b.ghost[0]), [AT, AT + Vector2i.RIGHT] as Array[Vector2i], "R again turns it back")
	b.group = BuildMode.Group.SYSTEMS
	_key(b, KEY_R)
	eq(b.rot, 1, "with a system selected R rotates the system instead")
	check(not b.door_flip, "and leaves the door alone")
	_done(b)


func test_a_click_places_both_cells_as_one_undo_step() -> void:
	var b := _build()
	var steps: int = b.session.undo_stack.size()
	_click(b, MOUSE_BUTTON_LEFT)
	eq(b.grid.door_piece(AT), [AT, AT + Vector2i.RIGHT] as Array[Vector2i], "the piece stands")
	eq(b.session.undo_stack.size(), steps + 1, "one undo step")
	eq(b.message, "", "no complaint")
	check(b.session.undo(), "undo")
	eq([b.grid.get_tile(AT), b.grid.get_tile(AT + Vector2i.RIGHT)], ["wall", "wall"], "both cells are wall again")
	_done(b)


func test_a_bad_click_says_why_and_builds_nothing() -> void:
	var b := _build()
	b.hover = Vector2i(5, 10)  # (4,10) is empty: no wall at that end
	_click(b, MOUSE_BUTTON_LEFT)
	eq(b.message, "doors need walls at both ends", "the reason")
	eq(b.grid.get_tile(Vector2i(5, 10)), "wall", "nothing changed")
	_done(b)


func test_right_click_on_either_cell_removes_the_whole_piece() -> void:
	var b := _build()
	_click(b, MOUSE_BUTTON_LEFT)
	b.hover = AT + Vector2i.RIGHT  # the second cell
	_click(b, MOUSE_BUTTON_RIGHT)
	eq([b.grid.get_tile(AT), b.grid.get_tile(AT + Vector2i.RIGHT)], ["", ""], "both cells removed")
	b.session.undo()
	eq(b.grid.door_piece(AT).size(), 2, "one undo brings the piece back")
	b.hover = AT
	_click(b, MOUSE_BUTTON_RIGHT)
	eq(b.grid.tiles.has(AT + Vector2i.RIGHT), false, "removed by the first cell as well")
	_done(b)


func test_e_opens_and_closes_the_whole_piece() -> void:
	var b := _build()
	_key(b, KEY_E)
	eq(b.message, "no door under the mouse", "E on a wall does nothing")
	_click(b, MOUSE_BUTTON_LEFT)
	b.hover = AT + Vector2i.RIGHT  # either cell will do
	_key(b, KEY_E)
	check(b.grid.is_door_open(AT) and b.grid.is_door_open(AT + Vector2i.RIGHT), "both cells open")
	eq(b.message, "door opened", "said so")
	b.hover = AT
	_key(b, KEY_E)
	check(not b.grid.is_door_open(AT) and not b.grid.is_door_open(AT + Vector2i.RIGHT), "both cells closed")
	_done(b)
