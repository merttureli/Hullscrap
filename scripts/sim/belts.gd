extends RefCounted
## The conveyor-belt layer of a ship (docs/CONTENT.md 4f): a floor overlay laid cell by cell in build mode,
## an autotile like the cables, on floor and door cells (never walls, never under a system). Orthogonally
## connected live cells are a network; a rack, weapon or belt drive is on a network when a live cell touches
## its edge. A cell is cut when damage lands beside it (`cut`) until a crew member repairs it, and counts as
## cut while the cell is breached (no tile). What moves along the belts (feed rates, the units riding) is
## scripts/sim/ammo.gd; this is the layer, its networks and the paths along them. Pure data, no nodes.

const VERSION := 1
const SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]  ## N E S W: the autotile's mask bits 1 2 4 8
const BUILD_PATH := "res://data/build.json"
const ROLES := {"ammo_rack": "racks", "belt_drive": "drives", "weapon": "weapons"}  ## component family -> the list of a network it joins

static var _cost := {}

var cells := {}  ## Vector2i -> true
var cut := {}  ## Vector2i -> true: cells damage cut, until repaired
var known := false  ## the belt blueprint is learned (with the first belt drive aboard); saved
var units: Array = []  ## ammo riding the belts: {item, from (rack uid), to (weapon uid), path (cells, rack side first), p (cells travelled), plan}; not saved
var clock := 0.0  ## seconds the belts have run
var drive_free := {}  ## drive uid -> clock at which it may feed its next unit
var ion := {}  ## drive uid -> seconds an ion hit still stops it
var rev := 0  ## bumped by every change to the cells or the cuts
var plan_id := 0  ## bumped when analyze() builds a new plan
var _plan := {}
var _plan_sig := []


## What one belt cell costs (build.json belt_cost): material id -> count.
static func cost() -> Dictionary:
	if _cost.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(BUILD_PATH))
		var bc: Dictionary = d.get("belt_cost", {"scrap": 1})
		for m in bc:
			_cost[str(m)] = int(bc[m])
	return _cost.duplicate()


func has(c: Vector2i) -> bool:
	return cells.has(c)


## Is there a working belt cell on `c`: laid, not cut, and not shot open?
func live(grid, c: Vector2i) -> bool:
	return cells.has(c) and not cut.has(c) and grid.get_tile(c) != ""


## Why a belt cannot go on `c`, or "" when it can.
func can_place(grid, components, c: Vector2i) -> String:
	if not grid.in_hull(c):
		return "outside the hull"
	if cells.has(c):
		return "already a belt"
	var id: String = grid.get_tile(c)
	if id == "":
		return "needs floor or a door"
	if grid.tile_flag(id, "solid"):
		return "belts run on floor and doors, not walls"
	if components.at(c) >= 0:
		return "a system is in the way"
	if components.wreck_at(c) >= 0:
		return "wreckage in the way"
	return ""


func place(grid, components, c: Vector2i) -> bool:
	if can_place(grid, components, c) != "":
		return false
	cells[c] = true
	rev += 1
	return true


func remove(c: Vector2i) -> bool:
	if not cells.erase(c):
		return false
	cut.erase(c)
	rev += 1
	return true


## Damage cuts the belt on `c`. False when there is none or it is cut already.
func cut_cell(c: Vector2i) -> bool:
	if not cells.has(c) or cut.has(c):
		return false
	cut[c] = true
	rev += 1
	return true


## A crew member mends the cut cell `c`.
func repair(c: Vector2i) -> bool:
	if not cut.erase(c):
		return false
	rev += 1
	return true


## The cut cells in (y, x) order.
func cut_cells() -> Array:
	return sorted(cut.keys())


static func sorted(list: Array) -> Array:
	var out := list.duplicate()
	out.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


## The autotile mask of the belt on `c` (N*1 + E*2 + S*4 + W*8) over the neighbours that `has` says are belts.
static func mask_of(c: Vector2i, has: Callable) -> int:
	var m := 0
	for i in 4:
		if has.call(c + SIDES[i]):
			m |= 1 << i
	return m


# --- networks -------------------------------------------------------------------------------------

## The networks of `ship`'s live belt cells and what touches them (cached until the cells, the breaches or the
## parts change): {net_of: cell -> net id, nets: [{id, cells, racks, weapons, drives}] (uids of the parts on it, in
## uid order), touch: uid -> net ids, edge: uid -> the live belt cells beside the part}.
func analyze(ship) -> Dictionary:
	var grid = ship.grid
	var comps = ship.components
	var sig_parts := 0
	for uid in comps.instances:
		var a: Vector2i = comps.instances[uid]["anchor"]
		sig_parts += uid * 131 + a.x * 17 + a.y * 3 + int(comps.instances[uid]["rot"])
	var sig := [rev, grid.breached.size(), comps.instances.size(), sig_parts]
	if sig == _plan_sig:
		return _plan
	_plan_sig = sig
	plan_id += 1
	var net_of := {}
	var nets: Array = []
	for c in sorted(cells.keys()):
		if net_of.has(c) or not live(grid, c):
			continue
		var id := nets.size()
		var list: Array[Vector2i] = []
		var stack: Array[Vector2i] = [c]
		net_of[c] = id
		while not stack.is_empty():
			var q: Vector2i = stack.pop_back()
			list.append(q)
			for d in SIDES:
				var n: Vector2i = q + d
				if not net_of.has(n) and live(grid, n):
					net_of[n] = id
					stack.append(n)
		nets.append({"id": id, "cells": sorted(list), "racks": [], "weapons": [], "drives": []})
	var touch := {}
	var edge := {}
	var uids: Array = comps.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = comps.instances[uid]
		var role: String = ROLES.get(str(comps.def(inst["id"]).get("family", "")), "")
		if role == "" or net_of.is_empty():
			continue
		var found: Array[Vector2i] = []
		var ids: Array = []
		for cell in inst["cells"]:
			for d in SIDES:
				var n: Vector2i = cell + d
				if net_of.has(n) and not found.has(n):
					found.append(n)
					if not ids.has(net_of[n]):
						ids.append(net_of[n])
		if found.is_empty():
			continue
		ids.sort()
		touch[uid] = ids
		edge[uid] = sorted(found)
		for id in ids:
			nets[id][role].append(uid)
	_plan = {"net_of": net_of, "nets": nets, "touch": touch, "edge": edge}
	return _plan


## The shortest belt path from any of `starts` (live cells) to a cell that is a key of `goal` (cell -> uid of the
## part to reach): {uid, path} with the path's cells from the goal's end to the start, or {} when there is none.
## `net_of` is the plan's: only live cells are walked.
static func route(net_of: Dictionary, starts: Array, goal: Dictionary) -> Dictionary:
	var parent := {}
	var queue: Array = []
	for s in starts:
		parent[s] = Vector2i(-99999, -99999)
		queue.append(s)
	var i := 0
	while i < queue.size():
		var c: Vector2i = queue[i]
		i += 1
		if goal.has(c):
			var path: Array[Vector2i] = []
			var q := c
			while q != Vector2i(-99999, -99999):
				path.append(q)
				q = parent[q]
			return {"uid": goal[c], "path": path}  # c first, the start last: from the rack to the gun
		for d in SIDES:
			var n: Vector2i = c + d
			if net_of.has(n) and not parent.has(n):
				parent[n] = c
				queue.append(n)
	return {}


## Where unit `u` is, in cell coordinates: along its path's cell centres (the first at 0.5 cells travelled).
static func unit_pos(u: Dictionary) -> Vector2:
	var path: Array = u["path"]
	var q := clampf(float(u["p"]) - 0.5, 0.0, float(path.size() - 1))
	var k := int(q)
	var a := Vector2(path[k]) + Vector2(0.5, 0.5)
	var b := Vector2(path[mini(k + 1, path.size() - 1)]) + Vector2(0.5, 0.5)
	return a.lerp(b, q - k)


# --- saving -----------------------------------------------------------------------------------------

func is_blank() -> bool:
	return cells.is_empty() and not known


func to_dict() -> Dictionary:
	var list := []
	for c in sorted(cells.keys()):
		list.append([c.x, c.y])
	var cuts := []
	for c in sorted(cut.keys()):
		cuts.append([c.x, c.y])
	return {"version": VERSION, "cells": list, "cut": cuts, "known": known}


## Is `d` a saved layer load_dict would take? "" or the reason.
static func check_dict(d: Dictionary) -> String:
	if int(d.get("version", 0)) != VERSION:
		return "unsupported belts version"
	for key in ["cells", "cut"]:
		if not d.get(key, []) is Array:
			return "bad ship data"
		for p in d.get(key, []):
			if not (p is Array and p.size() == 2):
				return "bad ship data"
	return ""


## Replace the layer with a saved one. Returns "" on success, else the reason (nothing changes then). What was
## riding the belts is gone: the ship puts it back in its racks first (Ammo.stow_units).
func load_dict(d: Dictionary) -> String:
	var why := check_dict(d)
	if why != "":
		return why
	cells.clear()
	cut.clear()
	for p in d.get("cells", []):
		cells[Vector2i(int(p[0]), int(p[1]))] = true
	for p in d.get("cut", []):
		var c := Vector2i(int(p[0]), int(p[1]))
		if cells.has(c):
			cut[c] = true
	known = bool(d.get("known", false))
	reset_run()
	return ""


## Forget the running state (units, feed clocks, ion stops); the layer itself stays.
func reset_run() -> void:
	units = []
	clock = 0.0
	drive_free = {}
	ion = {}
	rev += 1
