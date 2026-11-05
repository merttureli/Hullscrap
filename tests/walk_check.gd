extends RefCounted
## Test helper (and the sweep tests/tool_walkable.gd): can the soldier walk every ship he boards? audit() builds the boarding site of a ship (wreck_site.gd) and asks
## two things of it, with every door open and a 2x2 body (a place is "standable" when one fits):
##   shipped: the rooms a body can stand in that the walk from the airlock does not reach, in the site as it is played (what wreck_site.gd makes). Must be 0.
##   strict:  the same with every part a solid wall, the parts the site made walk-through put back (`lifted` of them). A ship that needs a lift is one whose
##            parts block its corridors; the site keeps it walkable by letting the soldier through them.

const WreckSite = preload("res://scripts/board/wreck_site.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")


## {site: false when no hatch can be made, shipped: rooms cut as played, strict: rooms cut with solid parts, lifted: parts made walk-through, blockers: part ids by them}.
static func audit(ship_dict: Dictionary, p_seed := 7) -> Dictionary:
	var s = WreckSite.make(p_seed, ship_dict, {"fight": "captured"})
	var out := {"site": s != null, "shipped": 0, "strict": 0, "lifted": 0, "blockers": []}
	if s == null:
		return out
	out["shipped"] = rooms_cut(s)
	var walls := ShipGrid.new(s.grid.size, s.grid.defs)  # the ship with every part a wall and nothing else
	walls.hull = s.grid.hull
	walls.tiles = s.grid.tiles.duplicate()
	var blockers := {}
	for p in s.props:
		if p["prop"] == "part":
			if not p["blocks"]:
				out["lifted"] += 1
				blockers[str(p["part"])] = true
			for c in s.cells_of(p):
				walls.tiles[c] = "wall"
	s.walk = walls
	out["strict"] = rooms_cut(s)
	out["blockers"] = blockers.keys()
	return out


## How many rooms of `s` a body can stand in (on s.walk, doors open) without the walk from the airlock reaching them.
static func rooms_cut(s) -> int:
	var open := func(_c: Vector2i) -> bool: return true
	var walked: Dictionary = s.reach(s.spawn_anchor(), open)
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in s.grid.tiles:
		lo = lo.min(c)
		hi = hi.max(c)
	var standable := {}
	var got := {}
	for y in range(lo.y - 1, hi.y + 1):
		for x in range(lo.x - 1, hi.x + 1):
			var a := Vector2i(x, y)
			var rid := int(s.room_of.get(a, -1))
			if rid >= 0 and s.room_of.get(a + Vector2i.ONE, -2) == rid and Pathfinder.body_ok(s.walk, a, open):
				standable[rid] = true
				if walked.has(a):
					got[rid] = true
	return standable.size() - got.size()
