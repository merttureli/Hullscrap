extends RefCounted
## One place for build edits: wraps a Ship so that every user action pays or refunds and is
## recorded as one undo step, across all three layers. No nodes, so it is testable headless.
## A change says which layer it edits (a change without "layer" is a tile change):
##   tile      {"layer": "tile", "cell", "to": tile id, "" = remove}
##   component {"layer": "component", "id", "anchor", "rot"} places; {"layer": "component", "cell"} removes
##   cable     {"layer": "cable", "cell"} places; add "remove": true to remove
## Placing a component takes one item with its id from the cargo; removing it gives the item back.
## A cable costs build.json's cable_cost per cell, refunded in full. A step is the list of what was
## really done: tiles {layer, cell, from, to} (+ "from_open" for a removed open door),
## components {layer, uid, id, anchor, rot, added}, cables {layer, cell, added}.

const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const Inventory = preload("res://scripts/ship/inventory.gd")
const MAX_HISTORY := 200
const BUILD_PATH := "res://data/build.json"

## How a drag turns into cells: freehand path, straight line, or filled rectangle.
enum Mode { PAINT, LINE, RECT }

var ship: Ship
var cable_cost := {}  ## material id -> count per cable cell
var undo_stack: Array = []
var redo_stack: Array = []
var grid: ShipGrid:
	get:
		return ship.grid
var inventory: Inventory:
	get:
		return ship.inventory


func _init(p_ship: Ship, build_path := BUILD_PATH) -> void:
	ship = p_ship
	var data = JSON.parse_string(FileAccess.get_file_as_string(build_path))
	assert(data is Dictionary and data.get("cable_cost") is Dictionary, "bad build data: " + build_path)
	for m in data["cable_cost"]:
		cable_cost[str(m)] = int(data["cable_cost"][m])


## The cargo a new ship starts with (data/start.json).
static func start_cargo(path := Ship.START_PATH) -> Dictionary:
	return Ship.start_cargo(path)


## One user action: `changes` (see the top) applied in order. A change that breaks a rule or
## can't be paid for is skipped. Returns {"applied": n, "skipped": n, "reason": the first skip
## reason or ""}.
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
		ship.mark_dirty()
	return {"applied": step.size(), "skipped": skipped, "reason": reason}


## What apply() would do, without keeping it: each change plus "reason" ("" = it would apply).
func preview(changes: Array) -> Array:
	var has_parts := changes.any(func(ch): return ch.get("layer", "") == "component")
	var parts_before: Dictionary = ship.components.to_dict() if has_parts else {}  # placing hands out a uid
	var run := _run(changes)
	_revert(run["step"])
	if has_parts:
		ship.components.load_dict(parts_before)  # give the uid back
	var out := []
	for i in changes.size():
		var e: Dictionary = changes[i].duplicate()
		e["reason"] = run["reasons"][i]
		out.append(e)
	return out


func undo() -> bool:
	if undo_stack.is_empty():
		return false
	var step: Array = undo_stack.pop_back()
	_revert(step)
	redo_stack.append(step)
	ship.mark_dirty()
	return true


func redo() -> bool:
	if redo_stack.is_empty():
		return false
	var step: Array = redo_stack.pop_back()
	for e in step:
		_replay(e, true)
	undo_stack.append(step)
	ship.mark_dirty()
	return true


## Turn one tile drag into changes: {"changes": Array, "error": String}. `a` and `b` are the drag
## start and end cells, `path` the cells a PAINT stroke went over. `remove` clears instead of placing `tile`.
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
		for c in _unique(drag_cells(mode, a, b, path)):
			changes.append({"layer": "tile", "cell": c, "to": to})
	var pl := _clip(changes)
	pl["changes"] = _doors_first(pl["changes"])
	return pl


## Turn one cable drag into changes, with the same drag modes as tiles (a RECT is filled).
func plan_cables(mode: int, remove: bool, a: Vector2i, b: Vector2i, path: Array = []) -> Dictionary:
	var changes := []
	for c in _unique(drag_cells(mode, a, b, path)):
		changes.append({"layer": "cable", "cell": c, "remove": remove})
	return _clip(changes)


## Place component `id` with its top-left cell on `anchor`, turned `rot` quarter turns.
func plan_component(id: String, anchor: Vector2i, rot: int) -> Dictionary:
	if not grid.in_bounds(anchor):
		return {"changes": [], "error": "outside the hull"}
	return {"changes": [{"layer": "component", "id": id, "anchor": anchor, "rot": posmod(rot, 4)}], "error": ""}


## Remove the component covering `cell`.
func plan_component_removal(cell: Vector2i) -> Dictionary:
	if ship.components.at(cell) < 0:
		return {"changes": [], "error": "nothing to remove"}
	return {"changes": [{"layer": "component", "cell": cell}], "error": ""}


## The tile that fills a room: the first one that is neither solid nor a door ("" if none).
func floor_tile() -> String:
	if grid.defs == null:
		return ""
	for id in grid.defs.ids():
		if not grid.tile_flag(id, "solid") and not grid.tile_flag(id, "door"):
			return id
	return ""


## The cells a drag covers: its freehand `path`, a straight line, or a filled rectangle.
static func drag_cells(mode: int, a: Vector2i, b: Vector2i, path: Array) -> Array:
	if mode == Mode.LINE:
		return line_cells(a, b)
	if mode == Mode.RECT:
		return rect_cells(a, b, false)
	return path


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
		out.append({"layer": "tile", "cell": c, "to": wall_id})
	if floor_id != "":
		var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
		var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
		for c in rect_cells(a, b, false):
			if c.x > lo.x and c.x < hi.x and c.y > lo.y and c.y < hi.y:
				out.append({"layer": "tile", "cell": c, "to": floor_id})
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
	return ship.to_dict()


## Replace the whole ship with a saved one and clear the undo history (see Ship.load_dict).
## Returns "" on success, else the reason.
func load_dict(d: Dictionary) -> String:
	var err := ship.load_dict(d)
	if err == "":
		undo_stack.clear()
		redo_stack.clear()
	return err


## Try each change in order, changing the ship for the ones that pass.
## Returns {"step": the recorded changes, "reasons": one entry per change, "" = applied}.
func _run(changes: Array) -> Dictionary:
	var step := []
	var reasons := []
	for ch in changes:
		match ch.get("layer", "tile"):
			"tile":
				reasons.append(_try_tile(ch["cell"], ch["to"], step))
			"component":
				reasons.append(_try_component(ch, step))
			"cable":
				reasons.append(_try_cable(ch["cell"], bool(ch.get("remove", false)), step))
			_:
				reasons.append("unknown layer")
	return {"step": step, "reasons": reasons}


func _try_tile(c: Vector2i, to: String, step: Array) -> String:
	var from: String = grid.get_tile(c)
	var was_open: bool = grid.is_door_open(c)
	var old_cost: Dictionary = grid.cost_of(from)
	var why: String = grid.can_remove(c) if to == "" else grid.can_place(to, c)
	if why == "":
		why = _stands_on(c, to)
	if why != "":
		return why
	inventory.refund(old_cost)
	if to == "":
		grid.remove(c)
	else:
		var short: Dictionary = inventory.missing(grid.cost_of(to))
		if not short.is_empty():
			inventory.spend(old_cost)
			return "not enough " + str(short.keys()[0])
		inventory.spend(grid.cost_of(to))
		grid.place(to, c)
	var e := {"layer": "tile", "cell": c, "from": from, "to": to}
	if was_open:
		e["from_open"] = true
	step.append(e)
	return ""


## A system can't be left without floor: a reason when `c` holds one and `to` is not a floor tile.
func _stands_on(c: Vector2i, to: String) -> String:
	var uid: int = ship.components.at(c)
	if uid < 0 or (to != "" and not grid.tile_flag(to, "solid") and not grid.tile_flag(to, "door")):
		return ""
	return "a %s stands here" % ship.components.def(ship.components.instances[uid]["id"]).get("name", "system")


func _try_component(ch: Dictionary, step: Array) -> String:
	var parts = ship.components
	if ch.has("id"):
		var id: String = ch["id"]
		var anchor: Vector2i = ch["anchor"]
		var rot := int(ch.get("rot", 0))
		var why: String = parts.can_place(grid, id, anchor, rot)
		if why != "":
			return why
		if inventory.count(id) < 1:
			return "no %s in cargo" % parts.def(id).get("name", id)
		var new_uid: int = parts.place(grid, id, anchor, rot)
		inventory.add(id, -1)
		step.append({"layer": "component", "uid": new_uid, "id": id, "anchor": anchor, "rot": posmod(rot, 4), "added": true})
		return ""
	var uid: int = parts.at(ch["cell"])
	if uid < 0:
		return "nothing to remove"
	var inst: Dictionary = parts.instances[uid]
	parts.remove_at(ch["cell"])
	inventory.add(inst["id"], 1)
	step.append({"layer": "component", "uid": uid, "id": inst["id"], "anchor": inst["anchor"], "rot": inst["rot"], "added": false})
	return ""


func _try_cable(c: Vector2i, remove: bool, step: Array) -> String:
	if remove:
		if not ship.cables.has(c):
			return "nothing to remove"
		ship.cables.remove(c)
		inventory.refund(cable_cost)
	else:
		var why: String = ship.cables.can_place(grid, c)
		if why != "":
			return why
		var short: Dictionary = inventory.missing(cable_cost)
		if not short.is_empty():
			return "not enough " + str(short.keys()[0])
		inventory.spend(cable_cost)
		ship.cables.place(grid, c)
	step.append({"layer": "cable", "cell": c, "added": not remove})
	return ""


## Undo a step, newest change first. Skips the placement rules.
func _revert(step: Array) -> void:
	for i in range(step.size() - 1, -1, -1):
		_replay(step[i], false)


## Do (`forward`) or undo one recorded change of any layer, cargo included. Skips the placement rules.
func _replay(e: Dictionary, forward: bool) -> void:
	match e.get("layer", "tile"):
		"component":
			_set_component(e, e["added"] == forward)
		"cable":
			_set_cable(e["cell"], e["added"] == forward)
		_:
			var from: String = e["from"] if forward else e["to"]
			var to: String = e["to"] if forward else e["from"]
			_shift(grid.cost_of(from), 1)
			_shift(grid.cost_of(to), -1)
			grid.force_tile(e["cell"], to)
			if not forward and e.get("from_open", false):
				grid.set_door_open(e["cell"], true)


## Put a recorded component back with its old uid (taking its item), or take it away (returning the item).
func _set_component(e: Dictionary, present: bool) -> void:
	var parts = ship.components
	if present:
		var d: Dictionary = parts.to_dict()
		d["instances"].append({"uid": e["uid"], "id": e["id"], "anchor": [e["anchor"].x, e["anchor"].y], "rot": e["rot"]})
		parts.load_dict(d)
	else:
		parts.remove_at(e["anchor"])
	inventory.add(e["id"], -1 if present else 1)


func _set_cable(c: Vector2i, present: bool) -> void:
	if present:
		ship.cables.cells[c] = true
	else:
		ship.cables.cells.erase(c)
	_shift(cable_cost, -1 if present else 1)


## Add (`sign` 1) or take (-1) `cost` to or from the cargo.
func _shift(cost: Dictionary, sign: int) -> void:
	for id in cost:
		inventory.add(id, sign * int(cost[id]))


## `cells` without repeats, first occurrence kept.
func _unique(cells: Array) -> Array:
	var seen := {}
	var out := []
	for c in cells:
		if not seen.has(c):
			seen[c] = true
			out.append(c)
	return out


## Drop changes outside the grid; refuse the whole drag when nothing is left inside it.
func _clip(changes: Array) -> Dictionary:
	var kept := []
	for ch in changes:
		if grid.in_bounds(ch["cell"]):
			kept.append(ch)
	if kept.is_empty() and not changes.is_empty():
		return {"changes": [], "error": "outside the hull"}
	return {"changes": kept, "error": ""}


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
