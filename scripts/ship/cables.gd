extends RefCounted
## The cable layer: a separate set of hull cells that carry power. Cables may run under floors,
## walls, doors and components. Pure data, no nodes.

const VERSION := 1

var cells := {}  # Vector2i -> true


func has(c: Vector2i) -> bool:
	return cells.has(c)


## Why a cable cannot go on `c`, or "" when it can.
func can_place(grid, c: Vector2i) -> String:
	if not grid.in_hull(c):
		return "outside the hull"
	if cells.has(c):
		return "already a cable"
	return ""


func place(grid, c: Vector2i) -> bool:
	if can_place(grid, c) != "":
		return false
	cells[c] = true
	return true


func remove(c: Vector2i) -> bool:
	return cells.erase(c)


func to_dict() -> Dictionary:
	var keys := cells.keys()
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var list := []
	for c in keys:
		list.append([c.x, c.y])
	return {"version": VERSION, "cells": list}


## Replace the cables with a saved set. Returns "" on success, else the reason.
func load_dict(d: Dictionary) -> String:
	if int(d.get("version", 0)) != VERSION:
		return "unsupported cables version"
	cells.clear()
	for p in d["cells"]:
		cells[Vector2i(int(p[0]), int(p[1]))] = true
	return ""
