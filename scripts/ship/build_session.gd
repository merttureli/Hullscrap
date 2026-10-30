extends RefCounted
## One place for build edits: wraps a ShipGrid and the ship's Inventory so that every user action
## pays or refunds materials and is recorded as one undo step. No nodes, so it is testable headless.
## A step is [{cell, from, to}] (a tile id, "" = empty; "from_open" is set when a removed door was open).

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const Inventory = preload("res://scripts/ship/inventory.gd")
const VERSION := 2  # save format; version 1 is a bare ShipGrid save
const MAX_HISTORY := 200
const START_PATH := "res://data/start.json"

## How a drag turns into cells: freehand path, straight line, or filled rectangle.
enum Mode { PAINT, LINE, RECT }

var grid: ShipGrid
var inventory: Inventory
var undo_stack: Array = []
var redo_stack: Array = []


func _init(p_grid: ShipGrid, p_inventory: Inventory) -> void:
	grid = p_grid
	inventory = p_inventory


## The cargo a new ship starts with (data/start.json).
static func start_cargo(path := START_PATH) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data is Dictionary and data.get("cargo") is Dictionary, "bad start data: " + path)
	return data["cargo"]


## One user action. `changes` is [{"cell": Vector2i, "to": tile id or ""}] (""= remove), applied in order.
## A change that breaks a placement rule or can't be paid for is skipped. Returns
## {"applied": n, "skipped": n, "reason": the first skip reason or ""}.
func apply(changes: Array) -> Dictionary:
	var run := _run(changes)
	var step: Array = run["step"]
	var skipped := 0
	var reason := ""
	for why in run["reasons"]:
		if why != "":
			skipped += 1
			if reason == "":
				reason = why
	if not step.is_empty():
		undo_stack.append(step)
		if undo_stack.size() > MAX_HISTORY:
			undo_stack.pop_front()
		redo_stack.clear()
	return {"applied": step.size(), "skipped": skipped, "reason": reason}


## What apply() would do, without keeping it: [{"cell", "to", "reason"}], reason "" = it would apply.
func preview(changes: Array) -> Array:
	var run := _run(changes)
	_revert(run["step"])
	var out := []
	for i in changes.size():
		out.append({"cell": changes[i]["cell"], "to": changes[i]["to"], "reason": run["reasons"][i]})
	return out


func undo() -> bool:
	if undo_stack.is_empty():
		return false
	var step: Array = undo_stack.pop_back()
	_revert(step)
	redo_stack.append(step)
	return true


func redo() -> bool:
	if redo_stack.is_empty():
		return false
	var step: Array = redo_stack.pop_back()
	for e in step:
		_shift(grid.cost_of(e["from"]), 1)
		_shift(grid.cost_of(e["to"]), -1)
		grid.force_tile(e["cell"], e["to"])
	undo_stack.append(step)
	return true


## Turn one drag into changes: {"changes": Array, "error": String}. `a` and `b` are the drag start
## and end cells, `path` the cells a PAINT stroke went over. `remove` clears instead of placing `tile`.
## A wall (any solid tile) dragged as a RECT makes a room: walls round the edge, floor inside.
## Cells outside the grid are dropped. When `error` is set the drag is refused and `changes` is empty.
func plan(mode: int, tile: String, remove: bool, a: Vector2i, b: Vector2i, path: Array = []) -> Dictionary:
	var to := "" if remove else tile
	var changes := []
	if mode == Mode.RECT and to != "" and grid.tile_flag(to, "door"):
		return {"changes": [], "error": "drag doors one at a time"}
	if mode == Mode.RECT and to != "" and grid.tile_flag(to, "solid"):
		changes = room_changes(a, b, to, floor_tile())
	else:
		var cells: Array = path
		if mode == Mode.LINE:
			cells = line_cells(a, b)
		elif mode == Mode.RECT:
			cells = rect_cells(a, b, false)
		var seen := {}
		for c in cells:
			if not seen.has(c):
				seen[c] = true
				changes.append({"cell": c, "to": to})
	var kept := []
	for ch in changes:
		if grid.in_bounds(ch["cell"]):
			kept.append(ch)
	if kept.is_empty() and not changes.is_empty():
		return {"changes": [], "error": "outside the hull"}
	return {"changes": _doors_first(kept), "error": ""}


## The tile that fills a room: the first one that is neither solid nor a door ("" if none).
func floor_tile() -> String:
	if grid.defs == null:
		return ""
	for id in grid.defs.ids():
		if not grid.tile_flag(id, "solid") and not grid.tile_flag(id, "door"):
			return id
	return ""


## Cells of a straight line from `a`, locked to the axis (horizontal on a tie) with the larger delta.
static func line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := b - a
	var horizontal := absi(d.x) >= absi(d.y)
	var n := d.x if horizontal else d.y
	var dir := 1 if n >= 0 else -1
	for i in range(0, n + dir, dir):
		out.append(a + (Vector2i(i, 0) if horizontal else Vector2i(0, i)))
	return out


## Cells of the rectangle with corners `a` and `b` (any order), row by row; only its edge if `outline_only`.
static func rect_cells(a: Vector2i, b: Vector2i, outline_only := false) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if not outline_only or x == lo.x or x == hi.x or y == lo.y or y == hi.y:
				out.append(Vector2i(x, y))
	return out


## Changes for a room: `wall_id` on the edge of the rectangle, then `floor_id` inside (skipped if "").
static func room_changes(a: Vector2i, b: Vector2i, wall_id: String, floor_id: String) -> Array:
	var out := []
	for c in rect_cells(a, b, true):
		out.append({"cell": c, "to": wall_id})
	if floor_id != "":
		var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
		var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
		for c in rect_cells(a, b, false):
			if c.x > lo.x and c.x < hi.x and c.y > lo.y and c.y < hi.y:
				out.append({"cell": c, "to": floor_id})
	return out


## Every cell on the way from `a` to `b` (Bresenham), both ends included. Keeps a fast mouse stroke unbroken.
static func trace_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := (b - a).abs()
	var step := Vector2i(1 if b.x >= a.x else -1, 1 if b.y >= a.y else -1)
	var err := d.x - d.y
	var c := a
	while true:
		out.append(c)
		if c == b:
			break
		var e2 := 2 * err
		if e2 > -d.y:
			err -= d.y
			c.x += step.x
		if e2 < d.x:
			err += d.x
			c.y += step.y
	return out


func to_dict() -> Dictionary:
	var d := grid.to_dict()
	d["version"] = VERSION
	d["cargo"] = inventory.to_dict()
	return d


## Replace grid, cargo and door states with a saved ship and clear the undo history.
## Version 1 (grid only) loads with the starting cargo. Returns "" on success, else the reason.
func load_dict(d: Dictionary) -> String:
	var version := int(d.get("version", 0))
	var cargo := Inventory.new()
	if version == 1:
		cargo.load_dict(start_cargo())
	elif version == VERSION:
		if not (d.get("cargo") is Dictionary):
			return "bad ship data"
		var why: String = cargo.load_dict(d["cargo"])
		if why != "":
			return why
	else:
		return "unsupported ship version"
	var err: String = grid.load_dict(d)
	if err != "":
		return err
	inventory.counts = cargo.counts
	undo_stack.clear()
	redo_stack.clear()
	return ""


## Try each change in order, changing grid and cargo for the ones that pass.
## Returns {"step": the recorded changes, "reasons": one entry per change, "" = applied}.
func _run(changes: Array) -> Dictionary:
	var step := []
	var reasons := []
	for ch in changes:
		reasons.append(_try(ch["cell"], ch["to"], step))
	return {"step": step, "reasons": reasons}


func _try(c: Vector2i, to: String, step: Array) -> String:
	var from: String = grid.get_tile(c)
	var was_open: bool = grid.is_door_open(c)
	var old_cost := grid.cost_of(from)
	if to == "":
		var why: String = grid.can_remove(c)
		if why != "":
			return why
		inventory.refund(old_cost)
		grid.remove(c)
	else:
		var why: String = grid.can_place(to, c)
		if why != "":
			return why
		inventory.refund(old_cost)
		var short: Dictionary = inventory.missing(grid.cost_of(to))
		if not short.is_empty():
			inventory.spend(old_cost)
			return "not enough " + str(short.keys()[0])
		inventory.spend(grid.cost_of(to))
		grid.place(to, c)
	var e := {"cell": c, "from": from, "to": to}
	if was_open:
		e["from_open"] = true
	step.append(e)
	return ""


## Undo a step's tiles and cargo, newest change first. Skips the placement rules.
func _revert(step: Array) -> void:
	for i in range(step.size() - 1, -1, -1):
		var e: Dictionary = step[i]
		_shift(grid.cost_of(e["to"]), 1)
		_shift(grid.cost_of(e["from"]), -1)
		grid.force_tile(e["cell"], e["from"])
		if e.get("from_open", false):
			grid.set_door_open(e["cell"], true)


## Add (`sign` 1) or take (-1) `cost` to or from the cargo.
func _shift(cost: Dictionary, sign: int) -> void:
	for id in cost:
		inventory.add(id, sign * int(cost[id]))


## Cells that hold a door go first: a door has to go before the wall that holds it can be changed.
func _doors_first(changes: Array) -> Array:
	var doors := []
	var rest := []
	for ch in changes:
		if grid.tile_flag(grid.get_tile(ch["cell"]), "door"):
			doors.append(ch)
		else:
			rest.append(ch)
	return doors + rest
