extends RefCounted
## The ship's build grid: which cells are inside the hull and what is built on each cell.
## Pure data (no nodes, no drawing) so every rule can be tested headless.

const VERSION := 2  # 2 adds door states; version 1 saves still load (all doors closed)
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var size: Vector2i
var defs  # tile_defs.gd instance, or null for a rule-less grid
var hull := {}   # Vector2i -> true: cells where building is allowed
var tiles := {}  # Vector2i -> tile id
var door_open := {}  # Vector2i -> true for doors that are open; closed doors are absent


func _init(p_size := Vector2i(31, 31), p_defs = null) -> void:
	size = p_size
	defs = p_defs


## Mark every cell whose centre lies within `radius` cells of the grid centre as hull.
func fill_circle_hull(radius: float) -> void:
	hull.clear()
	var centre := Vector2(size) / 2.0
	for y in size.y:
		for x in size.x:
			if (Vector2(x + 0.5, y + 0.5) - centre).length() <= radius:
				hull[Vector2i(x, y)] = true


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


func in_hull(c: Vector2i) -> bool:
	return hull.has(c)


func get_tile(c: Vector2i) -> String:
	return tiles.get(c, "")


## Why `id` cannot go on `c`, or "" when it can. Placing over a different tile replaces it.
func can_place(id: String, c: Vector2i) -> String:
	if not in_hull(c):
		return "outside the hull"
	if defs != null and not defs.has(id):
		return "unknown tile"
	var cur := get_tile(c)
	if cur == id:
		return "already there"
	if cur != "" and not _flag(id, "solid") and _supports_door(c):
		return "a door needs this wall"
	if _flag(id, "door") and not _door_fits(c):
		return "doors need walls on two opposite sides"
	return ""


func place(id: String, c: Vector2i) -> bool:
	if can_place(id, c) != "":
		return false
	force_tile(c, id)
	return true


## Set the tile on `c` ("" clears it) without checking any rule, and close any door there.
## Only for replaying recorded edits; use place() and remove() for user actions.
func force_tile(c: Vector2i, id: String) -> void:
	if id == "":
		tiles.erase(c)
	else:
		tiles[c] = id
	door_open.erase(c)


func can_remove(c: Vector2i) -> String:
	if get_tile(c) == "":
		return "nothing to remove"
	if _supports_door(c):
		return "a door needs this wall"
	return ""


func remove(c: Vector2i) -> bool:
	if can_remove(c) != "":
		return false
	force_tile(c, "")
	return true


## Materials needed to build tile `id` (material id -> count); {} when it is free or unknown.
func cost_of(id: String) -> Dictionary:
	if defs == null:
		return {}
	var raw = defs.get_def(id).get("cost", {})
	var cost := {}
	if raw is Dictionary:
		for m in raw:  # JSON numbers are floats
			cost[str(m)] = int(raw[m])
	return cost


## Everything built so far, summed per material.
func total_cost() -> Dictionary:
	var sum := {}
	for c in tiles:
		var cost := cost_of(tiles[c])
		for m in cost:
			sum[m] = int(sum.get(m, 0)) + int(cost[m])
	return sum


## True when tile `id` has the data flag `key` ("solid", "door").
func tile_flag(id: String, key: String) -> bool:
	return _flag(id, key)


## Open or close the door on `c`. Returns false when there is no door there.
func set_door_open(c: Vector2i, open: bool) -> bool:
	if not _flag(get_tile(c), "door"):
		return false
	if open:
		door_open[c] = true
	else:
		door_open.erase(c)
	return true


func is_door_open(c: Vector2i) -> bool:
	return door_open.has(c)


func to_dict() -> Dictionary:
	var h := []
	for c in _sorted(hull.keys()):
		h.append([c.x, c.y])
	var t := []
	for c in _sorted(tiles.keys()):
		t.append([c.x, c.y, tiles[c]])
	var o := []
	for c in _sorted(door_open.keys()):
		o.append([c.x, c.y])
	return {"version": VERSION, "size": [size.x, size.y], "hull": h, "tiles": t, "doors_open": o}


## Replace this grid with a saved one (version 1 or 2). Returns "" on success, else the reason;
## nothing changes when it fails.
func load_dict(d: Dictionary) -> String:
	var version := int(d.get("version", 0))
	if version < 1 or version > VERSION:
		return "unsupported ship version"
	if not (d.get("size") is Array and d["size"].size() == 2 and d.get("hull") is Array and d.get("tiles") is Array):
		return "bad ship data"
	var new_size := Vector2i(int(d["size"][0]), int(d["size"][1]))
	var new_hull := {}
	for p in d["hull"]:
		if not (p is Array and p.size() == 2):
			return "bad ship data"
		new_hull[Vector2i(int(p[0]), int(p[1]))] = true
	var new_tiles := {}
	for p in d["tiles"]:
		if not (p is Array and p.size() == 3):
			return "bad ship data"
		if defs != null and not defs.has(str(p[2])):
			return "unknown tile " + str(p[2])
		new_tiles[Vector2i(int(p[0]), int(p[1]))] = str(p[2])
	size = new_size
	hull = new_hull
	tiles = new_tiles
	door_open.clear()
	for p in d.get("doors_open", []):
		if p is Array and p.size() == 2 and _flag(get_tile(Vector2i(int(p[0]), int(p[1]))), "door"):
			door_open[Vector2i(int(p[0]), int(p[1]))] = true
	return ""


func _flag(id: String, key: String) -> bool:
	return defs != null and bool(defs.get_def(id).get(key, false))


func _is_solid(c: Vector2i) -> bool:
	return _flag(get_tile(c), "solid")


func _door_fits(c: Vector2i) -> bool:
	var left_right := _is_solid(c + Vector2i.LEFT) and _is_solid(c + Vector2i.RIGHT)
	var up_down := _is_solid(c + Vector2i.UP) and _is_solid(c + Vector2i.DOWN)
	return left_right or up_down


## True when `c` is a solid tile that a neighbouring door would no longer fit without.
func _supports_door(c: Vector2i) -> bool:
	if not _is_solid(c):
		return false
	var saved: String = tiles[c]
	tiles.erase(c)
	var needed := false
	for d in SIDES:
		if _flag(get_tile(c + d), "door") and not _door_fits(c + d):
			needed = true
			break
	tiles[c] = saved
	return needed


static func _sorted(keys: Array) -> Array:
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return keys
