extends RefCounted
## Room detection: groups the air cells of a ship grid into rooms and finds the doors between them.
## Pure logic over a ShipGrid (reads `tiles` and `defs`), deterministic, no nodes.

const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const SPACE := -1  ## a door end that opens to space (no tile there)
const SOLID := -2  ## a door end that is a wall, another door, or otherwise closed


## Returns {"room_of": {cell: id}, "rooms": [{id, cells, size, sealed}], "doors": [{cell, a, b}]}.
## Air cells are tiles that are neither solid nor door. Rooms are 4-connected groups of them,
## numbered 0..n-1 by their smallest cell (y, then x). A room is sealed unless one of its cells
## touches a cell with no tile (empty hull or outside the grid). Doors are boundaries: `a` is the
## left/up end and `b` the right/down end, each a room id, SPACE or SOLID; sorted by cell.
static func compute(grid) -> Dictionary:
	var air: Array[Vector2i] = []
	var door_cells: Array[Vector2i] = []
	for c in grid.tiles:
		var id: String = grid.tiles[c]
		if _flag(grid, id, "door"):
			door_cells.append(c)
		elif not _flag(grid, id, "solid"):
			air.append(c)
	_sort(air)
	_sort(door_cells)
	var is_air := {}
	for c in air:
		is_air[c] = true

	var room_of := {}
	var rooms: Array = []
	for start in air:
		if room_of.has(start):
			continue
		var id := rooms.size()
		var cells: Array[Vector2i] = []
		var sealed := true
		var stack: Array[Vector2i] = [start]
		room_of[start] = id
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			cells.append(c)
			for d in SIDES:
				var n: Vector2i = c + d
				if is_air.has(n):
					if not room_of.has(n):
						room_of[n] = id
						stack.append(n)
				elif grid.get_tile(n) == "":
					sealed = false
		_sort(cells)
		rooms.append({"id": id, "cells": cells, "size": cells.size(), "sealed": sealed})

	var doors: Array = []
	for c in door_cells:
		var h := [_end(grid, room_of, c + Vector2i.LEFT), _end(grid, room_of, c + Vector2i.RIGHT)]
		var v := [_end(grid, room_of, c + Vector2i.UP), _end(grid, room_of, c + Vector2i.DOWN)]
		var ends: Array = h if _open_ends(h) >= _open_ends(v) else v
		doors.append({"cell": c, "a": ends[0], "b": ends[1]})
	return {"room_of": room_of, "rooms": rooms, "doors": doors}


## What lies at `n` as seen from a door: a room id, SPACE (no tile) or SOLID.
static func _end(grid, room_of: Dictionary, n: Vector2i) -> int:
	if room_of.has(n):
		return room_of[n]
	return SPACE if grid.get_tile(n) == "" else SOLID


static func _open_ends(ends: Array) -> int:
	return int(ends[0] >= SPACE) + int(ends[1] >= SPACE)


static func _flag(grid, id: String, key: String) -> bool:
	return grid.defs != null and bool(grid.defs.get_def(id).get(key, false))


static func _sort(cells: Array[Vector2i]) -> void:
	cells.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
