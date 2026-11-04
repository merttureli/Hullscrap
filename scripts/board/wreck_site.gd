extends RefCounted
## The wreck of a ship you beat, as a boarding site (docs/BOARDING.md, Beta 4.1): make() builds a Site (site.gd) from the enemy Ship as the fight left it, so the soldier
## walks the ship that was fought. Pure logic; the same Ship dict and seed always give the same site.
## - The grid is the ship's: floors, walls, doors and shapes. A wall or door that was shot away is a hole (open to space, no body walks out of it).
## - The rooms are the ship's rooms (the atmosphere's), each with the pressure it had at the end of the fight (site.air_of). A room's purpose comes from the parts in it
##   (data/boarding.json `ship`). The airlock is a room on the hull edge with a 2-wide hatch in its outer wall, on a long side of the ship nearest its middle.
## - The parts stand where they were as props (`part`, they block like walls; the ship draws their art); a part that was destroyed is a scrap heap. The crew who died
##   aboard, or lie down, are bodies where they fell; after a win the crew still on their feet are foes where they stood. A captured ship has no foes.
## - Containers fill each room from its purpose as on generated sites, on the cells along the walls, never in front of a door and never so as to cut a room in two.
## The airlock prefers a hull-edge room that still has air (so the sealed rooms can be looted without a suit); an airless one only when no edge room has air.
## Returns null when no hatch can be made (the caller falls back to a generated site).

const Site = preload("res://scripts/board/site.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Air = preload("res://scripts/board/air.gd")

const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const CANDIDATES := 12  ## hatches tried (best first) before the best of them is taken
const WINDOW := 4  ## cells round a new prop in which a split of the floor is looked for


## The Ship of a saved dict (Ship.to_dict), null when it will not load.
static func load_ship(d: Dictionary):
	if not d.get("size") is Array or d["size"].size() != 2:
		return null
	var defs := TileDefs.new()
	defs.load_file(Site.TILES_PATH)
	var ship = Ship.new("Ship", ShipGrid.new(Vector2i(int(d["size"][0]), int(d["size"][1])), defs))
	return ship if ship.load_dict(d) == "" else null


## The site of the beaten ship `ship_dict` for `p_seed`. `opts`: {name, parts (part ids her containers hold), fight ("won" or "captured")}.
static func make(p_seed: int, ship_dict: Dictionary, opts := {}):
	var ship = load_ship(ship_dict)
	if ship == null or ship.atmosphere.rooms.is_empty():
		return null
	var cfg: Dictionary = Site.config()["ship"]
	var s = Site.new()
	s.kind = "wreck"
	s.seed_value = p_seed
	s.faction = str(opts.get("faction", "clans"))
	if s.faction == "":
		s.faction = "clans"
	s.parts = opts.get("parts", []).duplicate()
	s.fight = str(opts.get("fight", "won"))
	s.region = str(opts.get("region", ""))
	var crew := []  # who was aboard: [{name, species, pos, hp, max_hp, down, sealed}]
	for m in ship.crew:
		crew.append({"name": m.name, "species": m.species, "pos": m.pos, "hp": m.hp, "max_hp": m.max_hp, "down": m.is_down(), "sealed": Air.sealed(m)})
	var dead: Dictionary = ship.dead_at.duplicate(true)
	ship.crew.clear()  # (the view draws the people itself)
	ship.power_state = {}  # dark: nothing is running
	var grid: ShipGrid = ship.grid
	grid.door_open.clear()
	grid.door_locked.clear()
	s.ship = ship
	s.grid = grid
	s.site_name = str(opts.get("name", "")) if str(opts.get("name", "")) != "" else "Wreck"
	_rooms(s, ship)
	_doors(s, ship)
	_bounds(s)
	var rng := RandomNumberGenerator.new()
	rng.seed = Site._mix(p_seed, "wreck", 0)
	_parts(s, ship)
	_make_walk(s)
	if not _hatch(s):
		return null
	_purposes(s, cfg)
	_heaps(s, ship)
	_place_props(s, rng)
	_clear_lanes(s)
	_bodies(s, crew, dead)
	_crew_foes(s, crew, cfg)
	s._fill_slots(Site.config()["kinds"]["wreck"], rng)
	_lights(s, cfg, rng)
	s.ok = true
	s._place_marks()
	return s


## Is the airlock of the beaten ship `ship_dict` airless (the soldier needs a sealed suit to board her)? False when the ship will not load (she is a generated site).
static func airless_airlock(ship_dict: Dictionary) -> bool:
	var ship = load_ship(ship_dict)
	if ship == null or ship.atmosphere.rooms.is_empty():
		return false
	var s = Site.new()
	s.grid = ship.grid
	ship.crew.clear()
	_rooms(s, ship)
	_doors(s, ship)
	_bounds(s)
	_parts(s, ship)
	_make_walk(s)
	return _hatch(s) and Air.bad(s.air_of(int(s.airlock["room"])))


# --- rooms and doors ----------------------------------------------------------------------------------------------------

static func _rooms(s, ship) -> void:
	var atm = ship.atmosphere
	for r in atm.rooms:
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := Vector2i(-(1 << 20), -(1 << 20))
		var cells := {}
		for c in r["cells"]:
			lo = lo.min(c)
			hi = hi.max(c)
			cells[c] = true
			s.room_of[c] = r["id"]
		s.rooms.append({"id": r["id"], "rect": Rect2i(lo, hi - lo + Vector2i.ONE), "purpose": "", "corridor": false, "band": 0, "locked": false, "doors": [],
			"cells": cells, "air": clampf(float(atm.pressure[r["id"]]), 0.0, 1.0)})


static func _doors(s, ship) -> void:
	var grid: ShipGrid = s.grid
	var seen := {}
	for rec in ship.atmosphere.doors:
		var piece: Array[Vector2i] = grid.door_piece(rec["cell"])
		if piece.is_empty() or seen.has(piece[0]):
			continue
		seen[piece[0]] = true
		var ends := []
		for c in piece:
			for r in ship.atmosphere.doors:
				if r["cell"] == c:
					for e in [r["a"], r["b"]]:
						if int(e) >= 0 and not ends.has(int(e)):
							ends.append(int(e))
		if ends.is_empty():  # a door between nothing and nothing: a wall
			for c in piece:
				grid.force_tile(c, "wall")
			continue
		var id: int = s.doors.size()
		s.doors.append({"id": id, "cells": [piece[0], piece[-1]], "rooms": [ends[0], ends[-1]], "lock": "", "card": ""})
		for c in piece:
			s.door_of[c] = id
		for r in ends:
			s.rooms[r]["doors"].append(id)


static func _bounds(s) -> void:
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in s.grid.tiles:
		lo = lo.min(c)
		hi = hi.max(c)
	s.bounds = Rect2i(lo, hi - lo + Vector2i.ONE)


# --- the parts ----------------------------------------------------------------------------------------------------------

static func _parts(s, ship) -> void:
	var comps = ship.components
	var uids: Array = comps.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = comps.instances[uid]
		var cells: Array = inst["cells"]
		var lo: Vector2i = cells[0]
		var hi: Vector2i = lo
		var room := -1
		for c in cells:
			lo = lo.min(c)
			hi = hi.max(c)
			if room < 0:
				room = int(s.room_of.get(c, -1))
		var id: int = s.props.size()
		s.props.append({"id": id, "prop": "part", "cell": lo, "size": hi - lo + Vector2i.ONE, "cells": cells.duplicate(), "room": room, "blocks": true, "loot": false,
			"rolls": [0, 0], "table": "", "slot": "", "key": "", "fixed": {}, "part": str(inst["id"]), "uid": uid})
		for c in cells:
			if not s.prop_of.has(c):
				s.prop_of[c] = id


static func _make_walk(s) -> void:
	s.walk = ShipGrid.new(s.grid.size, s.grid.defs)
	s.walk.hull = s.grid.hull
	s.walk.tiles = s.grid.tiles.duplicate()
	for p in s.props:
		if p["blocks"]:
			for c in s.cells_of(p):
				s.walk.tiles[c] = "wall"


# --- the airlock ----------------------------------------------------------------------------------------------------------

static func _solid_full(grid: ShipGrid, c: Vector2i) -> bool:
	var id := grid.get_tile(c)
	return id != "" and grid.tile_flag(id, "solid") and grid.shape_of(c).is_empty()


## Does the line of wall from `w` outward along `n` (at most `thick` cells) end in space?
static func _to_space(grid: ShipGrid, w: Vector2i, n: Vector2i, thick: int) -> bool:
	var c := w
	for i in thick:
		var id := grid.get_tile(c)
		if id == "":
			return i > 0
		if not grid.tile_flag(id, "solid"):
			return false
		c += n
	return grid.get_tile(c) == ""


static func _hatch(s) -> bool:
	var grid: ShipGrid = s.grid
	var thick := int(Site.config()["ship"]["hatch"]["thick"])
	var wide: bool = s.bounds.size.x >= s.bounds.size.y  # the long axis of the ship
	var mid := Vector2(s.bounds.position) + Vector2(s.bounds.size) / 2.0
	var found := {}
	for r in s.rooms:
		for c in r["cells"]:
			for n in SIDES:
				var t := Vector2i(n.y, n.x).abs()  # along the wall
				var c2: Vector2i = c + t
				if not r["cells"].has(c2):
					continue
				var w: Vector2i = c + n
				var w2: Vector2i = c2 + n
				if not (_solid_full(grid, w) and _solid_full(grid, w2) and _to_space(grid, w, n, thick) and _to_space(grid, w2, n, thick)):
					continue
				var back: Vector2i = c - n
				var back2: Vector2i = c2 - n
				if not (r["cells"].has(back) and r["cells"].has(back2)):
					continue
				var anchor: Vector2i = c.min(c2).min(back).min(back2)
				if not Pathfinder.body_ok(s.walk, anchor):
					continue
				var h: Array = [w.min(w2), w.max(w2)]
				var key := "%d,%d,%d,%d" % [h[0].x, h[0].y, n.x, n.y]
				if found.has(key):
					continue
				var centre := (Vector2(h[0]) + Vector2(h[1])) / 2.0 + Vector2(0.5, 0.5)
				var along: float = centre.y - mid.y if not wide else centre.x - mid.x
				var on_long: bool = (n.y != 0) if wide else (n.x != 0)
				found[key] = {"room": r["id"], "hatch": h, "normal": n, "anchor": anchor, "rank": [1 if Air.bad(s.air_of(r["id"])) else 0, 0 if on_long else 1, snappedf(absf(along), 0.01), h[0].y, h[0].x, n.x, n.y]}
	var list: Array = found.values()
	list.sort_custom(func(a, b): return _before(a["rank"], b["rank"]))
	if list.is_empty():
		return false
	var total := 0
	for y in range(s.bounds.position.y, s.bounds.end.y):
		for x in range(s.bounds.position.x, s.bounds.end.x):
			total += int(Pathfinder.body_ok(s.walk, Vector2i(x, y)))
	var best: Dictionary = {}
	var best_reach := -1
	var open := func(_c: Vector2i) -> bool: return true
	for i in mini(list.size(), CANDIDATES):
		var cand: Dictionary = list[i]
		var reach: int = s.reach(cand["anchor"], open).size()
		if reach > best_reach:
			best = cand
			best_reach = reach
		if float(reach) >= 0.5 * float(total):
			best = cand
			break
	var h: Array = best["hatch"]
	s.airlock = {"room": best["room"], "hatch": h, "spawn": Vector2(best["anchor"]) + Vector2.ONE, "normal": Vector2(best["normal"])}
	s.rooms[best["room"]]["purpose"] = "airlock"
	return true


static func _before(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


# --- purposes, props ----------------------------------------------------------------------------------------------------

static func _purposes(s, cfg: Dictionary) -> void:
	var fam: Dictionary = cfg["purpose"]
	var order: Array = cfg["order"]
	var counts := {}
	for p in s.props:
		if p.has("part") and p["room"] >= 0:
			var family := str(s.ship.components.def(str(p["part"])).get("family", ""))
			if fam.has(family):
				var by: Dictionary = counts.get(p["room"], {})
				by[fam[family]] = int(by.get(fam[family], 0)) + 1
				counts[p["room"]] = by
	for r in s.rooms:
		if r["purpose"] == "airlock":
			continue
		var by: Dictionary = counts.get(r["id"], {})
		if by.is_empty():
			var rect: Rect2i = r["rect"]
			r["corridor"] = mini(rect.size.x, rect.size.y) <= int(cfg["narrow"])
			r["purpose"] = "corridor" if r["corridor"] else str(cfg["bare"])
			continue
		var pick := ""
		for name in order:
			if by.has(name) and (pick == "" or int(by[name]) > int(by[pick])):
				pick = str(name)
		r["purpose"] = pick
	s.rooms[s.airlock["room"]]["corridor"] = false


## Scrap heaps where parts were shot to pieces.
static func _heaps(s, ship) -> void:
	var def: Dictionary = Site.config()["props"]["heap"]
	for w in ship.components.wrecks:
		for c in w["cells"]:
			if s.room_of.has(c) and s.rooms[s.room_of[c]]["purpose"] != "airlock" and not s.prop_of.has(c) and Pathfinder.walkable(s.walk, c) and not _splits(s, [c]):
				_add(s, "heap", def, c, Vector2i.ONE, true)
				break


static func _add(s, prop: String, def: Dictionary, c: Vector2i, size: Vector2i, block: bool) -> void:
	var id: int = s.props.size()
	var room: int = int(s.room_of.get(c, -1))
	s.props.append({"id": id, "prop": prop, "cell": c, "size": size, "room": room, "blocks": block, "loot": bool(def["loot"]), "rolls": def["rolls"].duplicate(), "table": str(def.get("table", "")),
		"slot": "", "key": "", "fixed": {}})
	for y in size.y:
		for x in size.x:
			s.prop_of[c + Vector2i(x, y)] = id
			if block:
				s.walk.tiles[c + Vector2i(x, y)] = "wall"


## The cells of room `r` a door or the arrival keeps clear.
static func _mouth(s, r: Dictionary) -> Dictionary:
	var out := {}
	for did in r["doors"]:
		for dc in s.doors[did]["cells"]:
			for d in SIDES:
				var f: Vector2i = dc + d
				if r["cells"].has(f):
					for oy in range(-1, 2):
						for ox in range(-1, 2):
							out[f + Vector2i(ox, oy)] = true
	if r["id"] == s.airlock["room"]:
		var a: Vector2i = s.spawn_anchor()
		for oy in range(-2, 4):
			for ox in range(-2, 4):
				out[a + Vector2i(ox, oy)] = true
	return out


static func _ring(r: Dictionary, c: Vector2i) -> bool:
	for d in SIDES:
		if not r["cells"].has(c + d):
			return true
	return false


static func _place_props(s, rng: RandomNumberGenerator) -> void:
	var pdefs: Dictionary = Site.config()["props"]
	var rdefs: Dictionary = Site.config()["rooms"]
	var mult := float(Site.config()["kinds"]["wreck"]["prop_mult"])
	for r in s.rooms:
		if not rdefs.has(r["purpose"]):
			continue
		var mouth := _mouth(s, r)
		for entry in rdefs[r["purpose"]]["props"]:
			var n := rng.randi_range(int(entry["n"][0]), int(entry["n"][1]))
			n = int(floor(float(n) * mult + rng.randf()))
			for i in n:
				_put(s, r, str(entry["prop"]), pdefs[entry["prop"]], mouth, rng)


static func _put(s, r: Dictionary, prop: String, def: Dictionary, mouth: Dictionary, rng: RandomNumberGenerator) -> void:
	var blocks: bool = def["blocks"]
	var cand: Array[Vector2i] = []
	for c in r["cells"]:
		if not mouth.has(c) and not s.prop_of.has(c) and s.grid.get_tile(c) == "floor" and (not blocks or _ring(r, c)):
			cand.append(c)
	cand.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	while not cand.is_empty():
		var i := rng.randi() % cand.size()
		var c: Vector2i = cand[i]
		cand.remove_at(i)
		var size := Vector2i(int(def["size"][0]), int(def["size"][1]))
		for turned in 2:
			var sz := size if turned == 0 else Vector2i(size.y, size.x)
			var cells: Array[Vector2i] = []
			var good := true
			for yy in sz.y:
				for xx in sz.x:
					var cc := c + Vector2i(xx, yy)
					cells.append(cc)
					if not r["cells"].has(cc) or mouth.has(cc) or s.prop_of.has(cc) or s.grid.get_tile(cc) != "floor" or (blocks and not _ring(r, cc)):
						good = false
			if good and (not blocks or not _splits(s, cells)):
				_add(s, prop, def, c, sz, blocks)
				return


## Would walls on `cells` cut the floor of the ship near them in two (2x2 bodies, within WINDOW cells)? Looks only at that window, so it can say yes when the
## floor is joined further off: that only costs a prop.
static func _splits(s, cells: Array) -> bool:
	var lo: Vector2i = cells[0]
	var hi: Vector2i = lo
	for c in cells:
		lo = lo.min(c)
		hi = hi.max(c)
	lo -= Vector2i(WINDOW, WINDOW)
	hi += Vector2i(WINDOW, WINDOW)
	var before := _comps(s.walk, lo, hi)
	var saved := {}
	for c in cells:
		saved[c] = s.walk.tiles.get(c, "")
		s.walk.tiles[c] = "wall"
	var after := _comps(s.walk, lo, hi)
	for c in cells:
		if saved[c] == "":
			s.walk.tiles.erase(c)
		else:
			s.walk.tiles[c] = saved[c]
	var map := {}
	for a in after:
		var was: int = int(before.get(a, -1))
		if map.has(was) and map[was] != after[a]:
			return true
		map[was] = after[a]
	return false


## Component id of every body anchor in [lo, hi] that a body stands on, joined 4-ways within the window.
static func _comps(walk: ShipGrid, lo: Vector2i, hi: Vector2i) -> Dictionary:
	var comp := {}
	var n := 0
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var a := Vector2i(x, y)
			if comp.has(a) or not Pathfinder.body_ok(walk, a):
				continue
			comp[a] = n
			var stack: Array[Vector2i] = [a]
			while not stack.is_empty():
				var cur: Vector2i = stack.pop_back()
				for d in SIDES:
					var nb: Vector2i = cur + d
					if nb.x >= lo.x and nb.x <= hi.x and nb.y >= lo.y and nb.y <= hi.y and not comp.has(nb) and Pathfinder.body_ok(walk, nb):
						comp[nb] = n
						stack.append(nb)
			n += 1
	return comp


## The rooms (ids) a body can walk to from the airlock with every door open.
static func _reached(s) -> Dictionary:
	var open := func(_c: Vector2i) -> bool: return true
	var seen: Dictionary = s.reach(s.spawn_anchor(), open)
	var out := {}
	for a in seen:
		var rid := int(s.room_of.get(a, -1))
		if rid >= 0 and s.room_of.get(a + Vector2i.ONE, -2) == rid:
			out[rid] = true
	return out


## Every room must be walked to from the airlock. When the blocking props stop that, all of them are lifted and put back one at a time (by id), each staying only
## if every room that can be reached at all is still reached; a room that cannot be reached even then is gone (its containers too).
static func _clear_lanes(s) -> void:
	var reached := _reached(s)
	var blockers: Array = s.props.filter(func(p): return p["blocks"])
	var need := func(r: Dictionary) -> bool: return r["purpose"] != "gone" and not reached.has(r["id"])
	if s.rooms.any(need):
		for p in blockers:
			for c in s.cells_of(p):
				s.walk.tiles[c] = s.grid.tiles.get(c, "")
		var best := _reached(s)
		for p in blockers:
			for c in s.cells_of(p):
				s.walk.tiles[c] = "wall"
			if _reached(s).size() >= best.size():
				continue
			for c in s.cells_of(p):
				s.walk.tiles[c] = s.grid.tiles.get(c, "")
			p["blocks"] = false
		reached = _reached(s)
	for r in s.rooms:
		if r["purpose"] != "gone" and not reached.has(r["id"]):
			r["purpose"] = "gone"
	for p in s.props:
		if p["room"] >= 0 and s.rooms[p["room"]]["purpose"] == "gone":
			p["loot"] = false


# --- the crew -----------------------------------------------------------------------------------------------------------

## The nearest free cell to `at` (a floor cell of a room that is not gone, no prop on it), within 6 cells; (-1, -1) when none.
static func _free_cell(s, at: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 1.0e9
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var c := at + Vector2i(dx, dy)
			var rid := int(s.room_of.get(c, -1))
			if rid < 0 or s.rooms[rid]["purpose"] == "gone" or s.prop_of.has(c) or s.grid.get_tile(c) != "floor":
				continue
			var d := float(dx * dx + dy * dy)
			if d < bd:
				best = c
				bd = d
	return best


static func _bodies(s, crew: Array, dead: Dictionary) -> void:
	var def: Dictionary = Site.config()["props"]["body"]
	var at := []  # Vector2 where each lies, dead first by name
	var names: Array = dead.keys()
	names.sort()
	for n in names:
		var p = dead[n].get("pos")
		if p is Array and p.size() == 2:
			at.append(Vector2(float(p[0]), float(p[1])))
	for e in crew:
		if e["down"] or s.fight == "captured":
			at.append(e["pos"])
	for p in at:
		var c := _free_cell(s, Vector2i(floori(p.x), floori(p.y)))
		if c != Vector2i(-1, -1):
			_add(s, "body", def, c, Vector2i.ONE, false)


static func _crew_foes(s, crew: Array, cfg: Dictionary) -> void:
	s.foe_crew = []
	if s.fight != "won":
		return
	var species: Dictionary = cfg["foe"]["species"]
	for e in crew:
		if e["down"]:
			continue
		var anchor := _nearest_anchor(s, Pathfinder.anchor_of(e["pos"]))
		if anchor == Vector2i(-1, -1):
			continue
		s.foe_crew.append({"name": e["name"], "species": e["species"], "kind": str(species.get(e["species"], cfg["foe"]["default"])), "pos": Pathfinder.centre_of(anchor),
			"hp": clampf(float(e["hp"]) / maxf(float(e["max_hp"]), 1.0), 0.05, 1.0), "sealed": bool(e["sealed"])})


static func _nearest_anchor(s, at: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 1.0e9
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var a := at + Vector2i(dx, dy)
			var rid := int(s.room_of.get(a, -1))
			if rid < 0 or s.rooms[rid]["purpose"] in ["gone", "airlock"] or not Pathfinder.body_ok(s.walk, a) or s.room_of.get(a + Vector2i.ONE, -2) != rid:
				continue
			var d := float(dx * dx + dy * dy)
			if d < bd:
				best = a
				bd = d
	return best


static func _lights(s, cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	for r in s.rooms:
		if r["purpose"] == "gone":
			continue
		var mid: Vector2 = s.centre_of_room(r["id"])
		if r["id"] == s.airlock["room"]:
			s.lights.append({"pos": mid, "color": "green", "room": r["id"]})
		elif rng.randf() < float(cfg["lights"]):
			s.lights.append({"pos": mid, "color": "red", "room": r["id"]})
