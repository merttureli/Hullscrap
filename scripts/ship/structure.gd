extends RefCounted
## A ship's structure: the current hp of all its blocks over their maximum hp, read from the grid and the
## components as they are now (data/structure.json). There is no hull-health pool: the blocks are the health,
## and the number is never shown. Blocks are every wall and door tile (a breached one counts at 0 hp), every
## component with the outside half of a hull mount, and the wrecks (0 hp) until a crew member clears them.
## Floor has no hp and is not a block. Also what hurts and mends blocks outside a fight (events, drift jumps,
## the station) and which blocks are damaged (the wrench in the top bar). Static functions, no nodes.

const Stats = preload("res://scripts/sim/stats.gd")
const Shapes = preload("res://scripts/ship/shapes.gd")

const PATH := "res://data/structure.json"
const EPS := 1e-6
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

static var _cfg := {}


## data/structure.json as a Dictionary (read once; empty when the file is missing or unusable).
static func config() -> Dictionary:
	if _cfg.is_empty() and FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			_cfg = d
	return _cfg


## The structure fraction under which a ship in a fight is wrecked.
static func defeat_below() -> float:
	return float(config().get("defeat_below", 0.5))


## The ship of an arena combatant, or the ship itself.
static func ship_of(co_or_ship):
	var s = co_or_ship.get("ship")
	return s if s != null else co_or_ship


## The structure of an arena combatant or a ship, 0..1 (1 for a ship with no blocks). The one place that
## reads it: the fight's defeat rule, morale, the threat rating and the hull creak all call this.
static func structure_fraction(co_or_ship) -> float:
	var t := totals(ship_of(co_or_ship))
	return 1.0 if t.y <= 0.0 else clampf(t.x / t.y, 0.0, 1.0)


## Is the structure of `co_or_ship` under the defeat line?
static func defeated(co_or_ship) -> bool:
	return structure_fraction(co_or_ship) < defeat_below() - EPS


## (hp now, hp at most) summed over all the blocks of `ship`.
static func totals(ship) -> Vector2:
	var grid = ship.grid
	var cur := 0.0
	var top := 0.0
	if grid.defs != null:
		var has_hp := {}  # tile id -> does it have hp (floor has none)
		for c in grid.tiles:
			var id: String = grid.tiles[c]
			if not has_hp.has(id):
				has_hp[id] = grid.defs.get_def(id).has("hp")
			if has_hp[id]:
				var m: float = grid.max_hp_of(c)
				top += m
				cur += clampf(grid.hp_of(c), 0.0, m)
		for c in grid.breached:
			top += breached_max(grid, c)
	var comps = ship.components
	for uid in comps.instances:
		var inst: Dictionary = comps.instances[uid]
		var m := float(Stats.max_hp(comps.def(inst["id"])))
		top += m
		cur += clampf(float(inst["hp"]), 0.0, m)
		if comps.has_outside(uid):
			var o := float(comps.outside_hp_max(inst["id"]))
			top += o
			cur += clampf(float(inst["out_hp"]), 0.0, o)
	for w in comps.wrecks:
		top += _wreck_max(comps, w)
	return Vector2(cur, top)


## Max hp the tile of the breached cell `c` has once it is put back.
static func breached_max(grid, c: Vector2i) -> float:
	var base := float(grid.defs.get_def(str(grid.breached[c])).get("hp", 1.0)) * float(grid.hp_mult.get(c, 1.0)) if grid.defs != null else 1.0
	if grid.breached_shapes.has(c):
		return maxf(base * Shapes.area_of(grid.breached_shapes[c]), 1.0)
	return base


static func _wreck_max(comps, w: Dictionary) -> float:
	var id := str(w["id"])
	return float(Stats.max_hp(comps.def(id)) + comps.outside_hp_max(id))


## The damaged blocks of `ship`: [{cell, kind ("tile", "breach", "part" or "wreck"), missing (hp)}], by row then column.
## A tile below its hp, a breach, a component or mount half below its hp (one entry for the part: its first cell),
## and the debris of a wrecked part (nothing a station mends; the crew clear it).
static func damaged(ship) -> Array:
	var out := []
	var grid = ship.grid
	for c in grid.hp:
		if grid.tiles.has(c):
			var gap: float = grid.max_hp_of(c) - grid.hp_of(c)
			if gap > EPS:
				out.append({"cell": c, "kind": "tile", "missing": gap})
	for c in grid.breached:
		out.append({"cell": c, "kind": "breach", "missing": breached_max(grid, c)})
	var comps = ship.components
	for uid in comps.instances:
		var inst: Dictionary = comps.instances[uid]
		var gap := _part_gap(comps, inst)
		if gap > EPS:
			out.append({"cell": inst["cells"][0], "kind": "part", "missing": gap})
	for w in comps.wrecks:
		out.append({"cell": w["cells"][0], "kind": "wreck", "missing": 0.0})
	out.sort_custom(func(a, b): return a["cell"].y < b["cell"].y or (a["cell"].y == b["cell"].y and a["cell"].x < b["cell"].x))
	return out


static func _part_gap(comps, inst: Dictionary) -> float:
	var gap := maxf(float(Stats.max_hp(comps.def(inst["id"]))) - float(inst["hp"]), 0.0)
	if not inst["out_cells"].is_empty():
		gap += maxf(float(comps.outside_hp_max(inst["id"])) - float(inst["out_hp"]), 0.0)
	return gap


## hp of block damage a station can mend (wrecks are not: the crew clear them).
static func missing_hp(ship) -> float:
	var sum := 0.0
	for d in damaged(ship):
		sum += float(d["missing"])
	return sum


## Mend every damaged tile, breach and component (not wrecks). Returns the hp restored.
static func repair_all(ship) -> float:
	var got := missing_hp(ship)
	var grid = ship.grid
	for c in grid.hp.keys():
		grid.hp.erase(c)  # a cell that is not listed has full hp
	for c in grid.breached.keys():
		grid.repair(c)
	var comps = ship.components
	for uid in comps.instances:
		var inst: Dictionary = comps.instances[uid]
		inst["hp"] = Stats.max_hp(comps.def(inst["id"]))
		if not inst["out_cells"].is_empty():
			inst["out_hp"] = comps.outside_hp_max(inst["id"])
		if inst["status"] == "disabled":
			inst["status"] = "ok"
	ship.mark_dirty()
	return got


## Deal `n` hp of damage to random outer blocks of `ship`, 1 to 3 hp at a time, from `rng` (so the same seed hurts the
## same blocks). Walls and doors that face open space are hit first; a block at 0 hp is breached, as in a fight. The
## structure is never taken under `floor_fraction` of its maximum. Returns the hp dealt.
static func hurt(ship, n: float, rng: RandomNumberGenerator, floor_fraction := 0.0) -> float:
	var t := totals(ship)
	var left := minf(n, maxf(t.x - floor_fraction * t.y, 0.0))
	var grid = ship.grid
	var dealt := 0.0
	var pool := _hittable(ship, true)
	if pool.is_empty():
		pool = _hittable(ship, false)
	while left > EPS and not pool.is_empty():
		var i := rng.randi() % pool.size()
		var c: Vector2i = pool[i]
		var take := minf(minf(left, float(1 + rng.randi() % 3)), grid.hp_of(c))
		grid.hp[c] = grid.hp_of(c) - take
		left -= take
		dealt += take
		if grid.hp[c] <= EPS:
			grid.breach(c)
			pool.remove_at(i)
	if dealt > 0.0:
		ship.mark_dirty()
	return dealt


## The cells of solid blocks with hp left; `outer`: only those with open space beside them (no tile, no part).
static func _hittable(ship, outer: bool) -> Array:
	var grid = ship.grid
	var out := []
	if grid.defs == null:
		return out
	for c in grid.tiles:
		var d: Dictionary = grid.defs.get_def(grid.tiles[c])
		if not (bool(d.get("solid", false)) or bool(d.get("door", false))) or grid.hp_of(c) <= EPS:
			continue
		if outer:
			var open := false
			for s in SIDES:
				if grid.get_tile(c + s) == "" and ship.components.any_at(c + s) < 0:
					open = true
					break
			if not open:
				continue
		out.append(c)
	out.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


## Mend `n` hp of damaged blocks, the smallest gaps first (a breach is only sealed when all its hp is paid). Returns the hp mended.
static func mend(ship, n: float) -> float:
	var list := damaged(ship).filter(func(d): return d["kind"] != "wreck")
	list.sort_custom(func(a, b): return float(a["missing"]) < float(b["missing"]))
	var grid = ship.grid
	var comps = ship.components
	var left := n
	for d in list:
		if left <= EPS:
			break
		var c: Vector2i = d["cell"]
		var gap := float(d["missing"])
		match d["kind"]:
			"breach":
				if left >= gap - EPS:
					grid.repair(c)
					left -= gap
			"tile":
				var add := minf(left, gap)
				grid.hp[c] = grid.hp_of(c) + add
				if grid.hp[c] >= grid.max_hp_of(c) - EPS:
					grid.hp.erase(c)
				left -= add
			"part":
				var inst: Dictionary = comps.instances[comps.at(c)]
				var in_gap := maxf(float(Stats.max_hp(comps.def(inst["id"]))) - float(inst["hp"]), 0.0)
				var add := minf(left, in_gap)
				inst["hp"] = float(inst["hp"]) + add
				left -= add
				if inst["status"] == "disabled" and float(inst["hp"]) > 0.0:
					inst["status"] = "ok"
				if left > EPS and not inst["out_cells"].is_empty():
					var more := minf(left, maxf(float(comps.outside_hp_max(inst["id"])) - float(inst["out_hp"]), 0.0))
					inst["out_hp"] = float(inst["out_hp"]) + more
					left -= more
	ship.mark_dirty()
	return n - left
