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
