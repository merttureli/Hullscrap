extends "res://tests/base_test.gd"

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Rooms = preload("res://scripts/sim/rooms.gd")


## A 10x10 grid that is hull everywhere, so cells outside the buildings are empty hull (space).
func _grid() -> ShipGrid:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(10, 10), defs)
	for y in 10:
		for x in 10:
			g.hull[Vector2i(x, y)] = true
	return g


## A wall ring around `r` with floor inside.
func _box(g: ShipGrid, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			g.place("wall" if edge else "floor", Vector2i(x, y))


func test_closed_room_is_one_sealed_room() -> void:
	var g := _grid()
	_box(g, Rect2i(1, 1, 5, 5))
	var res := Rooms.compute(g)
	eq(res["rooms"].size(), 1, "one room")
	var r: Dictionary = res["rooms"][0]
	eq(r["id"], 0, "numbered 0")
	eq(r["size"], 9, "3x3 cells")
	eq(r["cells"].size(), 9, "cell list matches size")
	eq(r["cells"][0], Vector2i(2, 2), "cells sorted by y then x")
	check(r["sealed"], "walls all round: sealed")
	eq(res["room_of"].size(), 9, "only air cells are in a room")
	eq(res["room_of"][Vector2i(3, 3)], 0, "centre belongs to room 0")
	check(not res["room_of"].has(Vector2i(1, 1)), "walls are not air")
	eq(res["doors"].size(), 0, "no doors")


func test_gap_in_the_wall_unseals() -> void:
	var g := _grid()
	_box(g, Rect2i(1, 1, 5, 5))
	check(g.remove(Vector2i(3, 1)), "wall removed")
	var res := Rooms.compute(g)
	eq(res["rooms"].size(), 1, "still one room")
	check(not res["rooms"][0]["sealed"], "gap opens onto empty hull")
	# a floor tile in the gap joins the room and still faces space
	g.place("floor", Vector2i(3, 1))
	res = Rooms.compute(g)
	eq(res["rooms"][0]["size"], 10, "floor in the gap is part of the room")
	check(not res["rooms"][0]["sealed"], "and it is still open to space")


func test_floor_at_the_grid_edge_faces_space() -> void:
	var g := _grid()
	g.place("floor", Vector2i(0, 0))
	check(not Rooms.compute(g)["rooms"][0]["sealed"], "neighbours outside the grid count as space")


func test_door_splits_two_rooms_and_links_them() -> void:
	var g := _grid()
	_box(g, Rect2i(1, 1, 7, 5))
	for y in range(2, 5):
		check(g.place("wall", Vector2i(4, y)), "divider wall")
	check(g.place("door", Vector2i(4, 3)), "door in the divider")
	var res := Rooms.compute(g)
	eq(res["rooms"].size(), 2, "two rooms")
	eq(res["rooms"][0]["size"], 6, "left room")
	eq(res["rooms"][1]["size"], 6, "right room")
	check(res["rooms"][0]["sealed"] and res["rooms"][1]["sealed"], "both sealed")
	eq(res["doors"].size(), 1, "one door")
	eq(res["doors"][0]["cell"], Vector2i(4, 3), "door cell")
	eq(res["doors"][0]["a"], 0, "left end is room 0")
	eq(res["doors"][0]["b"], 1, "right end is room 1")
	check(not res["room_of"].has(Vector2i(4, 3)), "the door itself is no room cell")
	# without the door the rooms are still split by the wall
	g.place("wall", Vector2i(4, 3))
	eq(Rooms.compute(g)["rooms"].size(), 2, "a wall splits them too")
	eq(Rooms.compute(g)["doors"].size(), 0, "and there is no door")


func test_door_in_outer_wall_links_to_space() -> void:
	var g := _grid()
	_box(g, Rect2i(1, 1, 5, 5))
	check(g.place("door", Vector2i(3, 1)), "door in the top wall")
	check(g.place("door", Vector2i(1, 3)), "door in the left wall")
	var res := Rooms.compute(g)
	eq(res["rooms"].size(), 1, "one room")
	check(res["rooms"][0]["sealed"], "doors seal")
	eq(res["doors"].size(), 2, "two doors")
	eq(res["doors"][0]["cell"], Vector2i(3, 1), "sorted by y then x")
	eq(res["doors"][0]["a"], Rooms.SPACE, "top door: space above")
	eq(res["doors"][0]["b"], 0, "top door: room below")
	eq(res["doors"][1]["cell"], Vector2i(1, 3), "left door")
	eq(res["doors"][1]["a"], Rooms.SPACE, "left door: space to the left")
	eq(res["doors"][1]["b"], 0, "left door: room to the right")
	eq(Rooms.SPACE, -1, "space is -1")


func test_door_ends_that_are_solid() -> void:
	var g := _grid()
	var c := Vector2i(5, 5)
	for d in ShipGrid.SIDES:
		g.tiles[c + d] = "wall"
	g.tiles[c] = "door"
	var res := Rooms.compute(g)
	eq(res["doors"][0]["a"], -2, "walls on both axes: solid")
	eq(res["doors"][0]["b"], -2, "walls on both axes: solid")
	# floor on one open end only: that end is the room, the other is solid
	g.tiles[c + Vector2i.RIGHT] = "floor"
	res = Rooms.compute(g)
	eq(res["doors"][0]["a"], Rooms.SOLID, "wall end")
	eq(res["doors"][0]["b"], 0, "room end")


func test_numbering_is_deterministic() -> void:
	var boxes := [Rect2i(1, 5, 3, 3), Rect2i(7, 1, 3, 3), Rect2i(3, 1, 3, 3)]
	var g1 := _grid()
	for r in boxes:
		_box(g1, r)
	var g2 := _grid()
	for i in range(boxes.size() - 1, -1, -1):
		_box(g2, boxes[i])
	var res := Rooms.compute(g1)
	eq(res["rooms"].size(), 3, "three rooms")
	eq(res["room_of"][Vector2i(4, 2)], 0, "smallest y first")
	eq(res["room_of"][Vector2i(8, 2)], 1, "then larger x on the same row")
	eq(res["room_of"][Vector2i(2, 6)], 2, "then the lower room")
	eq(Rooms.compute(g2), res, "build order does not matter")
	eq(Rooms.compute(g1), res, "same grid, same result")


func test_grid_without_rules_has_only_air() -> void:
	var g := ShipGrid.new(Vector2i(4, 4))
	for c in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]:
		g.hull[c] = true
		g.place("floor", c)
	var res := Rooms.compute(g)
	eq(res["rooms"].size(), 1, "one room")
	eq(res["rooms"][0]["size"], 4, "four cells")
	check(not res["rooms"][0]["sealed"], "no walls: open to space")
