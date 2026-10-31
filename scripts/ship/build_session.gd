extends RefCounted
## One place for build edits: wraps a Ship so that every user action pays or refunds and is
## recorded as one undo step, across all three layers. No nodes, so it is testable headless.
## A change says which layer it edits (a change without "layer" is a tile change):
##   tile      {"layer": "tile", "cell", "to": tile id, "" = remove}
##             A door is a piece of two cells: "to" a door tile builds one starting at "cell", going
##             along "axis" (Vector2i.RIGHT or DOWN; left out = the grid's automatic choice). Removing
##             or replacing either cell of a door piece takes the whole piece (it is one step).
##             A solid tile may carry "shape" (a cell shape of shapes.gd), "rot" and "mirror": the cell
##             takes that shape (left out = a full square). Its cost, hp and mass scale with the area.
##   piece     {"layer": "piece", "piece": id of shapes.gd, "tile": solid tile id, "anchor", "rot", "mirror"}
##             builds all the cells of a shaped piece (slope45, slope2, round2...) or none of them.
##   component {"layer": "component", "id", "anchor", "rot"} places; {"layer": "component", "cell"} removes.
##             A hull mount (a weapon or engine) is placed by its OUTSIDE half: "anchor" is that half's
##             top-left cell, and the inside half goes on the floor behind the wall (components.gd
##             plan_mount). Removing it by a cell of either half takes both.
##   cable     {"layer": "cable", "cell"} places; add "remove": true to remove
##   belt      {"layer": "belt", "cell"} lays a conveyor-belt cell (docs/CONTENT.md 4f; floor and doors, once the belt blueprint
##             is known: Ammo.belts_unlocked); add "remove": true to remove. A belt cell costs build.json's belt_cost.
## Placing a component takes one item with its id from the cargo; removing it gives the item back.
## A cable costs build.json's cable_cost per cell, refunded in full. A tile costs per cell, so a door
## piece costs twice. A step is the list of what was really done: tiles {layer, cell, from, to}
## (+ "from_open" for a removed open door, "from_shape" / "to_shape" for a shaped cell; a door piece
## and a shaped piece are one entry per cell),
## components {layer, uid, id, anchor (the inside half), rot, added, + out (the outside half's top-left) for a mount},
## cables {layer, cell, added}, belts {layer, cell, added}; a component removal also has "stock" (the ammo it held, now in the cargo).

const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const Shapes = preload("res://scripts/ship/shapes.gd")
const Inventory = preload("res://scripts/ship/inventory.gd")
const Ammo = preload("res://scripts/sim/ammo.gd")
const Belts = preload("res://scripts/sim/belts.gd")
const MAX_HISTORY := 200
const BUILD_PATH := "res://data/build.json"

## How a drag turns into cells: freehand path, straight line, or filled rectangle.
enum Mode { PAINT, LINE, RECT }

var ship: Ship
var cable_cost := {}  ## material id -> count per cable cell
var belt_cost := {}  ## material id -> count per belt cell
var last_preview_cost := {}  ## what the last preview() would take from the cargo: id -> count (negative = given back)
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
	belt_cost = Belts.cost()


## The cargo a new ship starts with (data/start.json).
static func start_cargo(path := Ship.START_PATH) -> Dictionary:
	return Ship.start_cargo(path)


## One user action: `changes` (see the top) applied in order. A change that breaks a rule or
## can't be paid for is skipped. Returns {"applied": n, "skipped": n, "reason": the first skip
## reason or ""}: `applied` counts what was really done (a door piece is two cells), `skipped`
## the changes refused.
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


## What apply() would do, without keeping it: each change plus "reason" ("" = it would apply). Also sets last_preview_cost.
func preview(changes: Array) -> Array:
	var has_parts := changes.any(func(ch): return ch.get("layer", "") == "component")
	var parts_before: Dictionary = ship.components.to_dict() if has_parts else {}  # placing hands out a uid
	var cargo_before: Dictionary = inventory.counts.duplicate()
	var run := _run(changes)
	last_preview_cost = {}
	for id in cargo_before.keys() + inventory.counts.keys():
		var d := int(cargo_before.get(id, 0)) - inventory.count(id)
		if d != 0:
			last_preview_cost[id] = d
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


## One door piece of tile `id` starting at `c`, going along `axis` (Vector2i.RIGHT or DOWN; the
## default Vector2i.ZERO lets the grid choose by the walls round it).
func plan_door(id: String, c: Vector2i, axis := Vector2i.ZERO) -> Dictionary:
	var pl := _clip([{"layer": "tile", "cell": c, "to": id}])
	if axis != Vector2i.ZERO and not pl["changes"].is_empty():
		pl["changes"][0]["axis"] = axis
	return pl


## Turn one cable drag into changes, with the same drag modes as tiles (a RECT is filled).
func plan_cables(mode: int, remove: bool, a: Vector2i, b: Vector2i, path: Array = []) -> Dictionary:
	var changes := []
	for c in _unique(drag_cells(mode, a, b, path)):
		changes.append({"layer": "cable", "cell": c, "remove": remove})
	return _clip(changes)


## Turn one belt drag into changes, with the same drag modes as tiles (a RECT is filled).
func plan_belts(mode: int, remove: bool, a: Vector2i, b: Vector2i, path: Array = []) -> Dictionary:
	var changes := []
	for c in _unique(drag_cells(mode, a, b, path)):
		changes.append({"layer": "belt", "cell": c, "remove": remove})
	return _clip(changes)


## Build piece `piece` (shapes.gd: slope45, slope2, round2...) of the solid tile `tile` with its
## top-left cell on `anchor`, turned `rot` quarter turns and optionally mirrored: one change, one undo step.
func plan_piece(piece: String, tile: String, anchor: Vector2i, rot := 0, mirror := false) -> Dictionary:
	if not Shapes.has_piece(piece):
		return {"changes": [], "error": "unknown piece"}
	if not grid.tile_flag(tile, "solid"):
		return {"changes": [], "error": "only walls take a shape"}
	for pc in Shapes.piece_cells(piece, anchor, rot, mirror):
		if not grid.in_bounds(pc["cell"]):
			return {"changes": [], "error": "outside the hull"}
	return {"changes": [{"layer": "piece", "piece": piece, "tile": tile, "anchor": anchor, "rot": posmod(rot, 4), "mirror": mirror}], "error": ""}


## Place component `id` with its top-left cell on `anchor`, turned `rot` quarter turns. For a hull
## mount `anchor` is the top-left cell of its outside half.
func plan_component(id: String, anchor: Vector2i, rot: int) -> Dictionary:
	if not grid.in_bounds(anchor):
		return {"changes": [], "error": "outside the hull"}
	return {"changes": [{"layer": "component", "id": id, "anchor": anchor, "rot": posmod(rot, 4)}], "error": ""}


## Remove the component covering `cell`.
func plan_component_removal(cell: Vector2i) -> Dictionary:
	if ship.components.any_at(cell) < 0:
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
				reasons.append(_try_tile(ch["cell"], ch["to"], step, ch.get("axis", Vector2i.ZERO), Shapes.norm({"shape": ch.get("shape", Shapes.FULL), "rot": ch.get("rot", 0), "mirror": ch.get("mirror", false)})))
			"piece":
				reasons.append(_try_piece(ch, step))
			"component":
				reasons.append(_try_component(ch, step))
			"cable":
				reasons.append(_try_cable(ch["cell"], bool(ch.get("remove", false)), step))
			"belt":
				reasons.append(_try_belt(ch["cell"], bool(ch.get("remove", false)), step))
			_:
				reasons.append("unknown layer")
	return {"step": step, "reasons": reasons}


## Build all the cells of a piece, or none: a cell that cannot be built undoes the cells before it.
func _try_piece(ch: Dictionary, step: Array) -> String:
	if not Shapes.has_piece(str(ch.get("piece", ""))):
		return "unknown piece"
	var tile := str(ch.get("tile", ""))
	if not grid.tile_flag(tile, "solid"):
		return "only walls take a shape"
	var done := []
	for pc in Shapes.piece_cells(ch["piece"], ch["anchor"], int(ch.get("rot", 0)), bool(ch.get("mirror", false))):
		var why := _try_tile(pc["cell"], tile, done, Vector2i.ZERO, Shapes.norm(pc))
		if why != "":
			_revert(done)
			return why
	step.append_array(done)
	return ""


## Build `to` on `c` ("" removes). A door is a piece of two cells and so is any change to a door cell.
## `shape` ({shape, rot, mirror} or {} for a full square) is the shape the new cell takes.
func _try_tile(c: Vector2i, to: String, step: Array, axis := Vector2i.ZERO, shape := {}) -> String:
	var placing_door := to != "" and grid.tile_flag(to, "door")
	var axis_used := (axis if axis != Vector2i.ZERO else grid.door_axis_at(c)) if placing_door else Vector2i.ZERO
	var why: String
	var cells: Array[Vector2i] = [c]
	if placing_door:
		why = grid.can_place_door(to, c, axis_used) if shape.is_empty() else "only walls take a shape"
		cells.append(c + axis_used)
	else:
		why = grid.can_remove(c) if to == "" else grid.can_place(to, c, shape)
		if grid.tile_flag(grid.get_tile(c), "door"):
			cells = grid.door_piece(c)
	if why == "":
		for p in cells:
			why = _stands_on(p, to, shape)
			if why != "":
				break
	if why != "":
		return why
	var edits := []
	var old_cost := {}
	for p in cells:
		var from: String = grid.get_tile(p)
		var e := {"layer": "tile", "cell": p, "from": from, "to": to}
		if grid.is_door_open(p):
			e["from_open"] = true
		if not grid.shape_of(p).is_empty():
			e["from_shape"] = grid.shape_of(p).duplicate()
		if not shape.is_empty() and to != "":
			e["to_shape"] = shape
		edits.append(e)
		_add_cost(old_cost, grid.cost_of(from, grid.area_at(p)))
	var new_cost := {}
	if to != "":
		for p in cells:
			_add_cost(new_cost, grid.cost_of(to, Shapes.area_of(shape)))
	inventory.refund(old_cost)
	var short: Dictionary = inventory.missing(new_cost)
	if not short.is_empty():
		inventory.spend(old_cost)
		return "not enough " + str(short.keys()[0])
	inventory.spend(new_cost)
	if placing_door:
		grid.place_door(to, c, axis_used)
	elif to == "":
		grid.remove(c)
	else:
		grid.place(to, c, shape)
	step.append_array(edits)
	return ""


func _add_cost(sum: Dictionary, cost: Dictionary) -> void:
	for m in cost:
		sum[m] = int(sum.get(m, 0)) + int(cost[m])


## A system can't be left without floor: a reason when `c` holds one and `to` is not a floor tile. A
## hull mount's barrel needs open space, and the wall it is mounted through must stay a full wall
## (any material): a reason for any other change there.
func _stands_on(c: Vector2i, to: String, shape := {}) -> String:
	var parts = ship.components
	var out_uid: int = parts.at_out(c)
	if out_uid >= 0 and to != "":
		return "a %s sticks out here" % parts.def(parts.instances[out_uid]["id"]).get("name", "system")
	var link_uid: int = parts.link_at(c)
	if link_uid >= 0 and (to == "" or not grid.tile_flag(to, "solid") or grid.tile_flag(to, "door") or not shape.is_empty()):
		return "a %s is mounted through this wall" % parts.def(parts.instances[link_uid]["id"]).get("name", "system")
	if ship.belts.has(c) and (to == "" or grid.tile_flag(to, "solid")):
		return "a belt runs here"
	var uid: int = parts.at(c)
	if uid < 0 or (to != "" and not grid.tile_flag(to, "solid") and not grid.tile_flag(to, "door")):
		return ""
	return "a %s stands here" % parts.def(parts.instances[uid]["id"]).get("name", "system")


func _try_component(ch: Dictionary, step: Array) -> String:
	var parts = ship.components
	if ch.has("id"):
		var id: String = ch["id"]
		var anchor: Vector2i = ch["anchor"]
		var rot := int(ch.get("rot", 0))
		var mount: bool = parts.is_mount(id)
		var why: String = parts.can_place_mount(grid, id, anchor, rot) if mount else parts.can_place(grid, id, anchor, rot)
		if why != "":
			return why
		for c in (parts.plan_mount(grid, id, anchor, rot)["cells"] if mount else parts.footprint(id, anchor, rot)):
			if ship.belts.has(c):
				return "a belt runs here"
		if inventory.count(id) < 1:
			return "no %s in cargo" % parts.def(id).get("name", id)
		var new_uid: int = parts.place_mount(grid, id, anchor, rot) if mount else parts.place(grid, id, anchor, rot)
		inventory.add(id, -1)
		var e := {"layer": "component", "uid": new_uid, "id": id, "anchor": parts.instances[new_uid]["anchor"], "rot": posmod(rot, 4), "added": true}
		if mount:
			e["out"] = anchor
		step.append(e)
		return ""
	var uid: int = parts.any_at(ch["cell"])
	if uid < 0:
		return "nothing to remove"
	var inst: Dictionary = parts.instances[uid]
	var e := {"layer": "component", "uid": uid, "id": inst["id"], "anchor": inst["anchor"], "rot": inst["rot"], "added": false}
	if parts.has_outside(uid):
		e["out"] = inst["out_anchor"]
	var held := Ammo.unload(ship, uid)  # a rack's ammo (and a gun's loaded units) go back to the cargo
	if not held.is_empty():
		e["stock"] = held
	parts.remove_uid(uid)
	inventory.add(inst["id"], 1)
	step.append(e)
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


func _try_belt(c: Vector2i, remove: bool, step: Array) -> String:
	if remove:
		if not ship.belts.has(c):
			return "nothing to remove"
		ship.belts.remove(c)
		inventory.refund(belt_cost)
	else:
		if not Ammo.belts_unlocked(ship):
			return "needs a belt drive (found or traded) first"
		var why: String = ship.belts.can_place(grid, ship.components, c)
		if why != "":
			return why
		var short: Dictionary = inventory.missing(belt_cost)
		if not short.is_empty():
			return "not enough " + str(short.keys()[0])
		inventory.spend(belt_cost)
		ship.belts.place(grid, ship.components, c)
		Ammo.learn(ship)
	step.append({"layer": "belt", "cell": c, "added": not remove})
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
		"belt":
			_set_belt(e["cell"], e["added"] == forward)
		_:
			var from: String = e["from"] if forward else e["to"]
			var to: String = e["to"] if forward else e["from"]
			var from_shape: Dictionary = e.get("from_shape", {}) if forward else e.get("to_shape", {})
			var to_shape: Dictionary = e.get("to_shape", {}) if forward else e.get("from_shape", {})
			_shift(grid.cost_of(from, Shapes.area_of(from_shape)), 1)
			_shift(grid.cost_of(to, Shapes.area_of(to_shape)), -1)
			grid.force_tile(e["cell"], to, to_shape)
			if not forward and e.get("from_open", false):
				grid.set_door_open(e["cell"], true)


## Put a recorded component back with its old uid (taking its item), or take it away (returning the item).
func _set_component(e: Dictionary, present: bool) -> void:
	var parts = ship.components
	if present:
		var d: Dictionary = parts.to_dict()
		var rec := {"uid": e["uid"], "id": e["id"], "anchor": [e["anchor"].x, e["anchor"].y], "rot": e["rot"]}
		if e.has("out"):
			rec["out"] = [e["out"].x, e["out"].y]
		if e.has("stock"):  # it takes back what it held
			var st: Dictionary = e["stock"]
			Ammo.stock_into(rec, st)
			if int(st.get("n", 0)) > 0:
				inventory.add(str(st["ammo"]), -int(st["n"]))
			if int(st.get("loaded", 0)) > 0:
				inventory.add(Ammo.ammo_item(e["id"]), -int(st["loaded"]))
		d["instances"].append(rec)
		parts.load_dict(d)
	else:
		var held := Ammo.unload(ship, e["uid"])
		if not held.is_empty():
			e["stock"] = held
		parts.remove_uid(e["uid"])
	inventory.add(e["id"], -1 if present else 1)


func _set_cable(c: Vector2i, present: bool) -> void:
	if present:
		ship.cables.cells[c] = true
	else:
		ship.cables.cells.erase(c)
	_shift(cable_cost, -1 if present else 1)


func _set_belt(c: Vector2i, present: bool) -> void:
	if present:
		ship.belts.cells[c] = true
	else:
		ship.belts.cells.erase(c)
		ship.belts.cut.erase(c)
	ship.belts.rev += 1
	_shift(belt_cost, -1 if present else 1)


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
