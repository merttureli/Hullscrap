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


func test_door_needs_opposite_walls() -> void:
	var g := _grid()
	var c := Vector2i(5, 5)
	eq(g.can_place("door", c), "doors need walls on two opposite sides", "bare door refused")
	g.place("wall", c + Vector2i.LEFT)
	eq(g.can_place("door", c), "doors need walls on two opposite sides", "one wall is not enough")
	g.place("wall", c + Vector2i.UP)
	eq(g.can_place("door", c), "doors need walls on two opposite sides", "corner walls are not enough")
	g.place("wall", c + Vector2i.RIGHT)
	check(g.place("door", c), "door between left and right walls")


func test_wall_holding_a_door_stays() -> void:
	var g := _grid()
	var c := Vector2i(5, 5)
	g.place("wall", c + Vector2i.LEFT)
	g.place("wall", c + Vector2i.RIGHT)
	g.place("door", c)
	eq(g.can_remove(c + Vector2i.LEFT), "a door needs this wall", "supporting wall cannot go")
	eq(g.can_place("floor", c + Vector2i.LEFT), "a door needs this wall", "nor be replaced by floor")
	g.place("wall", c + Vector2i.UP)
	g.place("wall", c + Vector2i.DOWN)
	check(g.remove(c + Vector2i.LEFT), "free once up/down walls also hold the door")


func test_save_load_round_trip() -> void:
	var g := _grid()
	g.place("wall", Vector2i(4, 5))
	g.place("wall", Vector2i(6, 5))
	g.place("door", Vector2i(5, 5))
	g.place("floor", Vector2i(5, 6))
	var d: Dictionary = JSON.parse_string(JSON.stringify(g.to_dict()))
	var h := ShipGrid.new(Vector2i.ZERO, g.defs)
	eq(h.load_dict(d), "", "loads")
	eq(h.tiles, g.tiles, "same tiles")
	eq(h.hull, g.hull, "same hull")
	eq(h.total_cost(), g.total_cost(), "same cost")
	eq(h.load_dict({"version": 99}), "unsupported ship version", "future saves refused")


func test_total_cost_sums_materials() -> void:
	var g := _grid()
	eq(g.total_cost(), {}, "empty ship costs nothing")
	g.place("wall", Vector2i(4, 5))
	g.place("wall", Vector2i(6, 5))
	g.place("door", Vector2i(5, 5))
	g.place("floor", Vector2i(5, 6))
	eq(g.total_cost(), {"scrap": 2 + 2 + 3 + 1, "copper": 1}, "summed per material")
	eq(g.cost_of("door"), {"scrap": 3, "copper": 1}, "door cost is a dict")
	eq(g.cost_of("teleporter"), {}, "unknown tiles are free")


func _door_grid() -> ShipGrid:
	var g := _grid()
	g.place("wall", Vector2i(4, 5))
	g.place("wall", Vector2i(6, 5))
	g.place("door", Vector2i(5, 5))
	return g


func test_doors_start_closed_and_toggle() -> void:
	var g := _door_grid()
	var c := Vector2i(5, 5)
	check(not g.is_door_open(c), "doors start closed")
	check(g.set_door_open(c, true), "door opens")
	check(g.is_door_open(c), "now open")
	check(g.set_door_open(c, false), "door closes")
	check(not g.is_door_open(c), "now closed")
	check(not g.set_door_open(Vector2i(4, 5), true), "a wall is not a door")
	check(not g.is_door_open(Vector2i(4, 5)), "walls never open")


func test_removing_a_door_clears_its_state() -> void:
	var g := _door_grid()
	var c := Vector2i(5, 5)
	g.set_door_open(c, true)
	check(g.remove(c), "door removed")
	check(not g.is_door_open(c), "state cleared with the door")
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
	check(h.is_door_open(Vector2i(5, 5)), "open door stays open")
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
