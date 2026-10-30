extends RefCounted
## The ship's build grid: which cells are inside the hull and what is built on each cell.
## Pure data (no nodes, no drawing) so every rule can be tested headless.

const VERSION := 1
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var size: Vector2i
var defs  # tile_defs.gd instance, or null for a rule-less grid
var hull := {}   # Vector2i -> true: cells where building is allowed
var tiles := {}  # Vector2i -> tile id


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
	tiles[c] = id
	return true


func can_remove(c: Vector2i) -> String:
	if get_tile(c) == "":
		return "nothing to remove"
	if _supports_door(c):
		return "a door needs this wall"
	return ""


func remove(c: Vector2i) -> bool:
	if can_remove(c) != "":
		return false
	tiles.erase(c)
	return true


func total_cost() -> int:
	var sum := 0
	for c in tiles:
		sum += defs.cost(tiles[c]) if defs != null else 0
	return sum


func to_dict() -> Dictionary:
	var h := []
	for c in _sorted(hull.keys()):
		h.append([c.x, c.y])
	var t := []
	for c in _sorted(tiles.keys()):
		t.append([c.x, c.y, tiles[c]])
	return {"version": VERSION, "size": [size.x, size.y], "hull": h, "tiles": t}


## Replace this grid with a saved one. Returns "" on success, else the reason.
func load_dict(d: Dictionary) -> String:
	if int(d.get("version", 0)) != VERSION:
		return "unsupported ship version"
	size = Vector2i(int(d["size"][0]), int(d["size"][1]))
	hull.clear()
	tiles.clear()
	for p in d["hull"]:
		hull[Vector2i(int(p[0]), int(p[1]))] = true
	for p in d["tiles"]:
		tiles[Vector2i(int(p[0]), int(p[1]))] = str(p[2])
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
