extends "res://tests/base_test.gd"

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")


func _grid() -> ShipGrid:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(11, 11), defs)
	g.fill_circle_hull(5.0)
	return g


func test_hull_is_a_circle() -> void:
	var g := _grid()
	check(g.in_hull(Vector2i(5, 5)), "centre is hull")
	check(not g.in_hull(Vector2i(0, 0)), "corner is outside")
	eq(g.can_place("floor", Vector2i(0, 0)), "outside the hull", "no building outside")


func test_place_replace_remove() -> void:
	var g := _grid()
	var c := Vector2i(5, 5)
	check(g.place("floor", c), "floor placed")
	eq(g.can_place("floor", c), "already there", "same tile twice")
	check(g.place("wall", c), "wall replaces floor")
	eq(g.get_tile(c), "wall", "tile is now a wall")
	check(g.remove(c), "removed")
	eq(g.can_remove(c), "nothing to remove", "cell is empty")
	eq(g.can_place("teleporter", c), "unknown tile", "unknown ids refused")


func test_door_needs_walls_at_both_ends() -> void:
	var g := _grid()
	var c := Vector2i(5, 5)  # a door piece here takes (5,5) and (6,5)
	var why := "doors need walls at both ends"
	eq(g.can_place("door", c), why, "bare door refused")
	g.place("wall", c + Vector2i.LEFT)
	eq(g.can_place("door", c), why, "one wall is not enough")
	g.place("wall", c + Vector2i.UP)
	eq(g.can_place("door", c), why, "a wall beside it is not an end")
	g.place("wall", c + Vector2i(2, 0))
	check(g.place("door", c), "door piece between the left and right walls")
	eq(g.get_tile(c), "door", "first cell")
	eq(g.get_tile(c + Vector2i.RIGHT), "door", "second cell")
	eq(g.can_place("door", c), "already there", "same piece twice")


func test_door_piece_is_two_cells_either_way_round() -> void:
	var g := _grid()
	var c := Vector2i(5, 5)
	eq(g.door_piece(c), [] as Array[Vector2i], "no door, no piece")
	g.place("wall", Vector2i(4, 5))
	g.place("wall", Vector2i(7, 5))
	check(g.place("door", c), "horizontal piece in a horizontal wall")
	var want: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5)]
	eq(g.door_piece(Vector2i(5, 5)), want, "from the first cell")
	eq(g.door_piece(Vector2i(6, 5)), want, "from the second cell")
	var h := _grid()
	h.place("wall", Vector2i(5, 3))
	h.place("wall", Vector2i(5, 6))
	eq(h.door_axis_at(Vector2i(5, 4)), Vector2i.DOWN, "walls above and below: a vertical piece")
	check(h.place("door", Vector2i(5, 4)), "vertical piece in a vertical wall")
	var up: Array[Vector2i] = [Vector2i(5, 4), Vector2i(5, 5)]
	eq(h.door_piece(Vector2i(5, 5)), up, "both cells, from the lower one")
	eq(g.door_axis_at(c), Vector2i.RIGHT, "walls left and right: a horizontal piece")


func test_a_door_run_is_exactly_two() -> void:
	var g := _grid()
	for x in [3, 4, 7, 8]:
		g.place("wall", Vector2i(x, 5))
	check(g.place_door("door", Vector2i(5, 5), Vector2i.RIGHT), "a piece between two walls")
	# A second piece in the same row would need its own wall at both ends.
	eq(g.can_place_door("door", Vector2i(7, 5), Vector2i.RIGHT), "doors need walls at both ends", "no second piece right after it")
	eq(g.can_place_door("door", Vector2i(3, 5), Vector2i.RIGHT), "doors need walls at both ends", "nor right before it")
	# Hand-written data (an old save) can hold a longer run, but it is no piece.
	var t := _grid()
	for x in [4, 5, 6]:
		t.tiles[Vector2i(x, 5)] = "door"
	t.tiles[Vector2i(3, 5)] = "wall"
	t.tiles[Vector2i(7, 5)] = "wall"
	eq(t.door_piece(Vector2i(5, 5)), [Vector2i(5, 5)] as Array[Vector2i], "a run of three: each cell stands alone")
	# A lone cell between walls is not a piece either, and cannot be built.
	var u := _grid()
	u.place("wall", Vector2i(4, 5))
	u.place("wall", Vector2i(6, 5))
	eq(u.can_place_door("door", Vector2i(5, 5), Vector2i.RIGHT), "doors need walls at both ends", "a one-cell gap is too narrow")


func test_door_pieces_do_not_touch_sideways() -> void:
	var g := _grid()
	for p in [Vector2i(4, 5), Vector2i(7, 5), Vector2i(4, 6), Vector2i(7, 6)]:
		g.place("wall", p)
	check(g.place("door", Vector2i(5, 5)), "first piece")
	eq(g.can_place_door("door", Vector2i(5, 6), Vector2i.RIGHT), "no door beside a door", "no second piece right behind it")
	eq(g.can_place_door("door", Vector2i(5, 5), Vector2i.UP), "bad door direction", "only RIGHT and DOWN")
	eq(g.can_place_door("door", Vector2i(0, 0), Vector2i.RIGHT), "outside the hull", "needs the hull")
	eq(g.can_place_door("floor", Vector2i(5, 5), Vector2i.RIGHT), "not a door", "only door tiles")
	eq(g.can_place_door("teleporter", Vector2i(5, 5), Vector2i.RIGHT), "unknown tile", "unknown tile")


func test_wall_holding_a_door_stays() -> void:
	var g := _grid()
	var c := Vector2i(5, 5)
	g.place("wall", c + Vector2i.LEFT)
	g.place("wall", c + Vector2i(2, 0))
	g.place("wall", c + Vector2i.UP)
	g.place("door", c)
	eq(g.can_remove(c + Vector2i.LEFT), "a door needs this wall", "the wall at one end cannot go")
	eq(g.can_place("floor", c + Vector2i.LEFT), "a door needs this wall", "nor be replaced by floor")
	eq(g.can_remove(c + Vector2i(2, 0)), "a door needs this wall", "the other end neither")
	check(g.remove(c + Vector2i.UP), "a wall beside the door holds nothing")
	check(g.remove(c), "the door goes first")
	check(g.remove(c + Vector2i.LEFT), "then its wall is free")


func test_removing_either_cell_removes_the_door_piece() -> void:
	var g := _door_grid()
	check(g.remove(Vector2i(6, 5)), "removed by its second cell")
	eq(g.get_tile(Vector2i(5, 5)), "", "first cell gone")
	eq(g.get_tile(Vector2i(6, 5)), "", "second cell gone")
	check(g.place("door", Vector2i(5, 5)), "built again")
	check(g.remove(Vector2i(5, 5)), "removed by its first cell")
	eq(g.tiles.has(Vector2i(6, 5)), false, "both gone")
	g.place("door", Vector2i(5, 5))
	check(g.place("floor", Vector2i(6, 5)), "floor over one door cell")
	eq(g.get_tile(Vector2i(5, 5)), "floor", "replaces the whole piece")
	eq(g.get_tile(Vector2i(6, 5)), "floor", "both cells")


func test_save_load_round_trip() -> void:
	var g := _grid()
	g.place("wall", Vector2i(4, 5))
	g.place("wall", Vector2i(7, 5))
	g.place("door", Vector2i(5, 5))
	g.place("floor", Vector2i(5, 6))
	var d: Dictionary = JSON.parse_string(JSON.stringify(g.to_dict()))
	var h := ShipGrid.new(Vector2i.ZERO, g.defs)
	eq(h.load_dict(d), "", "loads")
	eq(h.tiles, g.tiles, "same tiles")
	eq(h.hull, g.hull, "same hull")
	eq(h.load_dict({"version": 99}), "unsupported ship version", "future saves refused")


func test_a_tile_cost_is_a_dict_of_materials() -> void:
	var g := _grid()
	eq(g.cost_of("door"), {"scrap": 3, "copper": 1}, "door cost is a dict")
	eq(g.cost_of("teleporter"), {}, "unknown tiles are free")


func _door_grid() -> ShipGrid:  # a door piece on (5,5) and (6,5)
	var g := _grid()
	g.place("wall", Vector2i(4, 5))
	g.place("wall", Vector2i(7, 5))
	g.place("door", Vector2i(5, 5))
	return g


func test_doors_start_closed_and_toggle() -> void:
	var g := _door_grid()
	var c := Vector2i(5, 5)
	check(not g.is_door_open(c), "doors start closed")
	check(g.set_door_open(c, true), "door opens")
	check(g.is_door_open(c), "now open")
	check(g.is_door_open(Vector2i(6, 5)), "the whole piece opens, both cells")
	check(g.set_door_open(Vector2i(6, 5), false), "closed from the other cell")
	check(not g.is_door_open(c) and not g.is_door_open(Vector2i(6, 5)), "both cells closed")
	check(not g.set_door_open(Vector2i(4, 5), true), "a wall is not a door")
	check(not g.is_door_open(Vector2i(4, 5)), "walls never open")


func test_removing_a_door_clears_its_state() -> void:
	var g := _door_grid()
	var c := Vector2i(5, 5)
	g.set_door_open(c, true)
	check(g.remove(c), "door removed")
	check(g.door_open.is_empty(), "state cleared with the piece")
	check(g.place("door", c), "new door placed")
	check(not g.is_door_open(c), "a new door starts closed")
	g.set_door_open(c, true)
	check(g.place("floor", c), "floor replaces the door")
	check(g.door_open.is_empty(), "replacing a door clears its state too")


func test_door_states_save_and_load() -> void:
	var g := _door_grid()
	g.set_door_open(Vector2i(5, 5), true)
	var d: Dictionary = JSON.parse_string(JSON.stringify(g.to_dict()))
	var h := ShipGrid.new(Vector2i.ZERO, g.defs)
	eq(h.load_dict(d), "", "loads")
	check(h.is_door_open(Vector2i(5, 5)) and h.is_door_open(Vector2i(6, 5)), "open door stays open, both cells")
	d["version"] = 1
	d.erase("doors_open")
	eq(h.load_dict(d), "", "version 1 saves still load")
	check(not h.is_door_open(Vector2i(5, 5)), "version 1 has all doors closed")


func test_bad_save_changes_nothing() -> void:
	var g := _door_grid()
	var before := g.to_dict()
	eq(g.load_dict({"version": 2, "size": [3, 3], "hull": [], "tiles": [[0, 0, "teleporter"]]}),
		"unknown tile teleporter", "unknown tile refused")
	eq(g.load_dict({"version": 2}), "bad ship data", "missing fields refused")
	eq(g.to_dict(), before, "grid untouched by failed loads")
