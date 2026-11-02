extends RefCounted
## Test helpers for structure (scripts/ship/structure.gd): put a ship at a structure fraction, or make it too tough to wreck.

const Structure = preload("res://scripts/ship/structure.gd")


## Lower the hp of the blocks of `co_or_ship` (wall and door tiles, in row order) until its structure is `fraction`.
static func set_structure(co_or_ship, fraction: float) -> void:
	var ship = Structure.ship_of(co_or_ship)
	var grid = ship.grid
	var t := Structure.totals(ship)
	var loss := (1.0 - fraction) * t.y - (t.y - t.x)  # more to take off than already is
	var cells: Array = []
	for c in grid.tiles:
		if grid.defs.get_def(grid.tiles[c]).has("hp"):
			cells.append(c)
	cells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for c in cells:
		if loss <= 1e-9:
			break
		var take := minf(loss, grid.hp_of(c))
		grid.hp[c] = grid.hp_of(c) - take
		loss -= take
	ship.mark_dirty()


## Make every wall and door of `co_or_ship` `k` times as strong, so the fire of a scenario never wrecks it.
static func tough(co_or_ship, k := 1000.0) -> void:
	var grid = Structure.ship_of(co_or_ship).grid
	for c in grid.tiles:
		if grid.defs.get_def(grid.tiles[c]).has("hp"):
			grid.hp_mult[c] = k
