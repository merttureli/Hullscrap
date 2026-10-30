extends SceneTree
## Not a test (the runner only loads test_*.gd). Rebuilds the three starter ships and the pirate raider of data/ships/:
##   godot --headless --path . --script res://tests/tool_make_starters.gd
## Each ship is described by room rectangles, doors, parts and plating below (local coordinates, the
## ship's top-left bounding-box cell is 0,0), built through BuildSession.apply, wired by a cheap
## router, then exported with Ship.to_dict(). The hull is the bounding box plus MARGIN cells, and
## the ship sits in the middle of the 63x63 grid. Prints a map and the stats of every ship.
## A weapon or engine is a hull mount (docs/CONTENT.md 4f): its entry is [id, x, y, rot] with x, y the
## top-left cell of its OUTSIDE half (in space, against the outer wall face; outward is up at rot 0,
## so rear engines use rot 2); the inside half goes on the floor behind the wall by the placement rule.

const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const Arena = preload("res://scripts/combat/arena.gd")

const GRID := Vector2i(63, 63)
const MARGIN := 2
const OUT_DIR := "res://data/ships/"
const SIDES: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const STOCK := {"scrap": 5000, "copper": 600, "titanium": 400, "silicon": 400, "crystal": 200, "plasma_cell": 100, "polymer": 100}
## Cost of crossing a cell when routing a cable: walls, doors and parts are cheap (the wire hides there).
const WIRE_COST := {"solid": 2, "part": 2, "floor": 5, "none": 14}

var _bad := false


func _init() -> void:
	for spec in [_rustbucket(), _courier(), _prism(), _pirate()]:
		_make(spec)
	quit(1 if _bad else 0)


# --- the three designs ---------------------------------------------------------------------------------

## Scrap line: a brick of a ship, a hold full of junk, unreliable parts. Three reactors, because scrap
## parts draw 20% more and make 10% less.
func _rustbucket() -> Dictionary:
	return {
		"file": "starter_rustbucket", "name": "Rustbucket", "size": Vector2i(30, 24),
		"crew": [{"name": "Soldier", "species": "human"}, {"name": "Ada", "species": "human"}, {"name": "Rook", "species": "basalt"}, {"name": "Juno", "species": "fenn"}],
		"blurb": "Welded together from scrap: cheap, thick-skinned, a hold full of junk. Parts rattle and quit, but it hits back.",
		"rooms": [
			[1, 1, 7, 6], [7, 1, 22, 6], [22, 1, 28, 6],  # workshop, weapons deck, bridge
			[1, 6, 16, 13], [16, 6, 28, 13],  # cargo hold, quarters
			[1, 13, 8, 18], [8, 13, 28, 18],  # shield room, engineering
			[1, 18, 28, 22],  # engine deck
		],
		"doors": [
			[7, 3, "v"], [22, 3, "v"], [3, 6, "h"], [14, 6, "h"], [17, 6, "h"], [25, 6, "h"], [16, 8, "v"],
			[6, 13, "h"], [14, 13, "h"], [20, 13, "h"], [8, 15, "v"], [14, 18, "h"], [20, 18, "h"],
		],
		"parts": [
			["fabricator", 2, 2], ["shrapnel_cannon_scrap", 9, -3], ["rattle_burst_scrap", 13, -2], ["bolt_thrower_scrap", 17, -2],
			["helm", 24, 3], ["bed", 19, 7], ["bed", 21, 7], ["oxygen_scrap_mk1", 23, 7], ["shield_scrap_mk1", 2, 14],
			["reactor_scrap_mk1", 10, 14], ["reactor_mk2", 16, 14], ["reactor_scrap_mk1", 22, 14],
			["engine_scrap_mk1", 4, 24, 2], ["engine_scrap_mk1", 22, 24, 2], ["radiator", 14, 20],
		],
		"plates": [["scrap_plate", func(_c): return true]],
		"cargo": {"scrap": 900, "copper": 60, "polymer": 12, "engine_scrap_mk1": 1, "radiator": 1, "bed": 1, "credits": 300, "fuel": 6},
	}


## Standard line: small and quick. Two Mk2 reactors because one cannot feed the guns, the shield, both rear
## engines and the strafe pair on the side walls.
func _courier() -> Dictionary:
	return {
		"file": "starter_courier", "name": "Courier", "size": Vector2i(24, 19),
		"crew": [{"name": "Soldier", "species": "human"}, {"name": "Ada", "species": "human"}, {"name": "Bram", "species": "basalt"}],
		"blurb": "Small, quick and reliable: standard parts, a titanium nose and a light shield. Stays out of trouble or shoots its way out.",
		"rooms": [
			[0, 1, 23, 6],  # weapons bay
			[0, 6, 8, 13], [8, 6, 14, 13], [14, 6, 23, 13],  # quarters, workshop, bridge
			[0, 13, 5, 18], [5, 13, 18, 18], [18, 13, 23, 18],  # engine room, reactors, engine room
		],
		"doors": [
			[1, 6, "h"], [10, 6, "h"], [17, 6, "h"], [8, 8, "v"], [14, 8, "v"],
			[2, 13, "h"], [10, 13, "h"], [19, 13, "h"],
		],
		"parts": [
			["laser_mk1", 5, -2], ["pulse_mk1", 10, -2], ["laser_mk1", 15, -2],
			["bed", 3, 7], ["bed", 5, 7], ["oxygen_gen", 3, 11, 1],
			["fabricator", 9, 10], ["helm", 17, 7], ["shield_mk1", 17, 9],
			["reactor_mk2", 6, 14], ["reactor_mk2", 12, 14], ["radiator", 16, 14],
			["engine_mk2", 1, 19, 2], ["engine_mk2", 19, 19, 2],
			["engine_mk1", -2, 9, 3], ["engine_mk1", 24, 7, 1],  # the strafe pair: stand-ins on the side walls (push right and left)
		],
		"plates": [["titanium_alloy", func(c): return c.y == 0 and c.x >= 0 and c.x <= 23]],
		"cargo": {"scrap": 220, "copper": 80, "titanium": 40, "polymer": 10, "engine_mk1": 1, "laser_mk1": 1, "afterburner": 1, "radiator": 1, "credits": 500, "fuel": 6},
	}


## Neon line: a glass cannon with a lot of power. A third radiator keeps the Heat Lance from cooking.
func _prism() -> Dictionary:
	return {
		"file": "starter_prism", "name": "Prism", "size": Vector2i(22, 18),
		"crew": [{"name": "Soldier", "species": "human"}, {"name": "Tess", "species": "emberkin"}, {"name": "Quill", "species": "fenn"}, {"name": "Wren", "species": "basalt"}],
		"blurb": "A neon glass cannon: huge power, a snappy four-sector shield, thin skin, and everything runs hot.",
		"rooms": [
			[5, 1, 16, 6],  # weapons nose
			[0, 6, 8, 12], [8, 6, 15, 12], [15, 6, 21, 12],  # quarters, bridge, workshop
			[0, 12, 4, 17], [4, 12, 17, 17], [17, 12, 21, 17],  # cargo, engine room, cargo
		],
		"doors": [
			[13, 6, "h"], [8, 8, "v"], [15, 10, "v"], [2, 12, "h"], [13, 12, "h"], [18, 12, "h"],
		],
		"parts": [
			["heat_lance_neon", 6, -2], ["radiator", 10, 2], ["siren_ion_neon", 12, -2],
			["bed", 1, 7], ["bed", 3, 7], ["oxygen_gen", 5, 7],
			["shield_neon_mk1", 9, 7], ["helm", 13, 8], ["fabricator", 16, 7],
			["reactor_neon_mk1", 5, 13], ["radiator", 9, 13], ["radiator", 11, 13], ["engine_neon_mk1", 13, 18, 2],
		],
		"plates": [["reflective_coating", func(c): return c.y == 0]],
		"cargo": {"scrap": 120, "copper": 60, "polymer": 10, "silicon": 40, "crystal": 12, "plasma_cell": 3, "afterburner": 1, "radiator": 1, "bed": 1, "credits": 400, "fuel": 6},
	}


## The test pirate (combat_session.gd PIRATE_PATH): a small scrap-plated raider with one fixed laser and
## one Rattle Burst turret on the nose, two rear engines, a shield and the aim of a pilot of skill 0.5.
## A scrap reactor joins the Mk2 because the turret's scrap line draws 20% more than the laser it replaced.
func _pirate() -> Dictionary:
	return {
		"file": "pirate_raider", "name": "Pirate Raider", "size": Vector2i(20, 15),
		"crew": [{"name": "Grub", "species": "human"}, {"name": "Skab", "species": "human"}, {"name": "Vex", "species": "basalt"}],
		"ai": {"aim_skill": 0.5},
		"blurb": "A Rustfang raider: a laser to aim with the whole ship, a rattling turret that fires whether it is aimed or not.",
		"rooms": [
			[0, 1, 19, 8],  # nose deck
			[0, 8, 19, 14],  # engine deck
		],
		"doors": [[8, 8, "h"]],
		"parts": [
			["laser_mk1", 5, -2], ["rattle_burst_scrap", 10, -2], ["shield_mk1", 15, 3], ["helm", 2, 3],
			["reactor_mk2", 8, 9], ["reactor_scrap_mk1", 6, 4], ["oxygen_gen", 2, 9],
			["engine_mk1", 4, 15, 2], ["engine_mk1", 13, 15, 2],
		],
		"plates": [["scrap_plate", func(c): return c.y == 0]],
		"cargo": {"scrap": 120, "copper": 10},
	}


# --- building ------------------------------------------------------------------------------------------

func _make(spec: Dictionary) -> void:
	var defs := TileDefs.new()
	defs.load_file(Ship.TILES_PATH)
	var ship := Ship.new(spec["name"], ShipGrid.new(GRID, defs))
	var g: ShipGrid = ship.grid
	for y in GRID.y:
		for x in GRID.x:
			g.hull[Vector2i(x, y)] = true  # the real hull is set at the end
	ship.inventory.load_dict(STOCK)
	for p in spec["parts"]:
		ship.inventory.add(p[0], 1)
	var off: Vector2i = (GRID - spec["size"]) / 2
	var session := BuildSession.new(ship)

	var walls := {}
	var floors := {}
	for r in spec["rooms"]:
		var rect := Rect2i(r[0] + off.x, r[1] + off.y, r[2] - r[0] + 1, r[3] - r[1] + 1)
		for y in rect.size.y:
			for x in rect.size.x:
				var c := rect.position + Vector2i(x, y)
				if x == 0 or y == 0 or x == rect.size.x - 1 or y == rect.size.y - 1:
					walls[c] = true
				else:
					floors[c] = true
	for c in floors:
		if walls.has(c):
			_fail("%s: cell %s is a wall of one room and the floor of another" % [spec["name"], c - off])
	var changes := []
	for c in walls:
		changes.append({"layer": "tile", "cell": c, "to": "wall"})
	for c in floors:
		changes.append({"layer": "tile", "cell": c, "to": "floor"})
	_apply(session, changes, spec["name"] + " rooms")

	changes = []
	for d in spec["doors"]:
		changes.append({"layer": "tile", "cell": Vector2i(d[0], d[1]) + off, "to": "door", "axis": Vector2i.RIGHT if d[2] == "h" else Vector2i.DOWN})
	_apply(session, changes, spec["name"] + " doors")

	for pl in spec["plates"]:  # one layer round the outside, corners included
		var ring := {}
		for c in g.tiles:
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var n: Vector2i = c + Vector2i(dx, dy)
					if not g.tiles.has(n) and pl[1].call(n - off):
						ring[n] = true
		changes = []
		for c in ring:
			changes.append({"layer": "tile", "cell": c, "to": pl[0]})
		_apply(session, changes, spec["name"] + " plating")

	changes = []
	for p in spec["parts"]:
		changes.append({"layer": "component", "id": p[0], "anchor": Vector2i(p[1], p[2]) + off, "rot": p[3] if p.size() > 3 else 0})
	_apply(session, changes, spec["name"] + " parts")

	_wire(ship, session, spec)

	var lo := Vector2i(GRID)
	var hi := Vector2i.ZERO
	var cells: Array = g.tiles.keys() + ship.cables.cells.keys()
	for uid in ship.components.instances:
		cells.append_array(ship.components.instances[uid]["cells"])
		cells.append_array(ship.components.instances[uid]["out_cells"])
	for c in cells:
		lo = lo.min(c)
		hi = hi.max(c)
	lo -= Vector2i(MARGIN, MARGIN)
	hi += Vector2i(MARGIN, MARGIN)
	if lo.x < 0 or lo.y < 0 or hi.x >= GRID.x or hi.y >= GRID.y:
		_fail(spec["name"] + ": the hull does not fit the grid")
	g.hull.clear()
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			g.hull[Vector2i(x, y)] = true
	ship.inventory.load_dict(spec["cargo"])
	ship.refresh()

	var saved := ship.to_dict()
	saved["blurb"] = spec["blurb"]
	saved["crew"] = spec["crew"]  # who starts aboard and their species (Jobs.spawn_crew)
	if spec.has("ai"):
		saved["ai"] = spec["ai"]  # the pilot's style and aim skill (pilot_ai.gd)
	var path: String = OUT_DIR + spec["file"] + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(_format(saved))
	f.close()
	_report(spec, path)


func _apply(session: BuildSession, changes: Array, what: String) -> void:
	var r := session.apply(changes)
	if r["skipped"] > 0:
		_fail("%s: %d of %d changes refused: %s" % [what, r["skipped"], changes.size(), r["reason"]])


func _fail(text: String) -> void:
	printerr("FAIL " + text)
	_bad = true


# --- wiring --------------------------------------------------------------------------------------------

## Join every part to the first reactor with cables: part by part, the one with the cheapest route
## to the network goes next. A cable goes under a cell of the part, so beds are wired too.
func _wire(ship: Ship, session: BuildSession, spec: Dictionary) -> void:
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	var net := {}
	var rest: Array = []
	for uid in uids:
		if ship.components.def(ship.components.instances[uid]["id"])["family"] == "reactor" and net.is_empty():
			var inst: Dictionary = ship.components.instances[uid]
			net[inst["cells"][5]] = true  # a cell inside the reactor
			continue
		rest.append(uid)
	var cables := [{"layer": "cable", "cell": net.keys()[0]}]
	while not rest.is_empty():
		var best := {}
		var best_uid := -1
		for uid in rest:
			var r := _route(ship, ship.components.instances[uid]["cells"], net)
			if not r.is_empty() and (best.is_empty() or r["cost"] < best["cost"]):
				best = r
				best_uid = uid
		if best.is_empty():
			_fail(spec["name"] + ": no route to a part")
			return
		for c in best["path"]:
			net[c] = true
			cables.append({"layer": "cable", "cell": c})
		rest.erase(best_uid)
	_apply(session, cables, spec["name"] + " cables")


## The cheapest cable path from any cell of `starts` to a cell of `targets`: {path, cost}, or {}.
func _route(ship: Ship, starts: Array, targets: Dictionary) -> Dictionary:
	var dist := {}
	var prev := {}
	var buckets := {}
	for s in starts:
		dist[s] = _wire_cost(ship, s)
		_push(buckets, dist[s], s)
	var d := 0
	while d < 4000:
		if buckets.has(d):
			var i := 0
			while i < buckets[d].size():
				var c: Vector2i = buckets[d][i]
				i += 1
				if dist[c] != d:
					continue
				if targets.has(c):
					var path: Array = []
					var at := c
					path.append(at)
					while prev.has(at):
						at = prev[at]
						path.append(at)
					return {"path": path.filter(func(p): return not targets.has(p)), "cost": d}
				for s in SIDES:
					var n: Vector2i = c + s
					if not ship.grid.in_bounds(n) or (not ship.grid.tiles.has(n) and _outside(ship, n)):
						continue
					var nd: int = d + _wire_cost(ship, n)
					if not dist.has(n) or nd < dist[n]:
						dist[n] = nd
						prev[n] = c
						_push(buckets, nd, n)
		d += 1
	return {}


func _push(buckets: Dictionary, d: int, c: Vector2i) -> void:
	if not buckets.has(d):
		buckets[d] = []
	buckets[d].append(c)


## Cells far from any tile are never worth wiring through.
func _outside(ship: Ship, c: Vector2i) -> bool:
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if ship.grid.tiles.has(c + Vector2i(dx, dy)):
				return false
	return true


func _wire_cost(ship: Ship, c: Vector2i) -> int:
	var t: String = ship.grid.get_tile(c)
	if t == "":
		return WIRE_COST["none"]
	if ship.grid.tile_flag(t, "solid") or ship.grid.tile_flag(t, "door"):
		return WIRE_COST["solid"]
	return WIRE_COST["part"] if ship.components.at(c) >= 0 else WIRE_COST["floor"]


# --- output --------------------------------------------------------------------------------------------

## The saved ship, one top-level key per line and the long lists on one line each, so a diff stays readable.
func _format(d: Dictionary) -> String:
	var keys := d.keys()
	keys.sort()
	var lines := []
	for k in keys:
		var v = d[k]
		if k == "tiles":
			var rows := []
			for t in v:
				rows.append("\t" + JSON.stringify(t))
			lines.append("\"tiles\": [\n" + ",\n".join(rows) + "\n]")
		else:
			lines.append("%s: %s" % [JSON.stringify(k), JSON.stringify(v, "", true)])
	return "{\n" + ",\n".join(lines) + "\n}\n"


func _report(spec: Dictionary, path: String) -> void:
	var ship := Ship.from_design(path)
	print("==== %s  (%s)" % [spec["name"], path])
	if ship == null:
		_fail(spec["name"] + ": the exported file does not load")
		return
	var g: ShipGrid = ship.grid
	var glyph := {"reactor": "R", "engine": "E", "oxygen": "O", "shield": "S", "weapon": "W", "helm": "H", "bed": "B", "fabricator": "F", "radiator": "i"}
	var lo := Vector2i(GRID)
	var hi := Vector2i.ZERO
	for c in g.hull:
		lo = lo.min(c)
		hi = hi.max(c)
	for pass_no in 2:
		var rows := []
		for y in range(lo.y, hi.y + 1):
			var row := ""
			for x in range(lo.x, hi.x + 1):
				var c := Vector2i(x, y)
				var ch := " "
				var t: String = g.get_tile(c)
				if t != "":
					ch = {"floor": ".", "wall": "#", "door": "D", "scrap_plate": "s", "titanium_alloy": "T", "reflective_coating": "x"}.get(t, "?")
				var uid: int = ship.components.at(c)
				if uid >= 0:
					ch = glyph.get(ship.components.def(ship.components.instances[uid]["id"])["family"], "?")
				var out_uid: int = ship.components.at_out(c)
				if out_uid >= 0:  # the outside half of a mount, in lower case
					ch = glyph.get(ship.components.def(ship.components.instances[out_uid]["id"])["family"], "?").to_lower()
				if pass_no == 1 and ship.cables.has(c):
					ch = "+"
				row += ch
			rows.append(row)
		print("\n".join(rows))
		print("")
	var supply := 0.0
	var demand := 0.0
	for n in ship.power_state["networks"]:
		supply += n["supply"]
		demand += n["demand"]
	var unpowered := []
	for uid in ship.components.instances:
		if not ship.power_state["powered"].get(uid, false):
			unpowered.append(ship.components.def(ship.components.instances[uid]["id"])["name"])
	var arena := Arena.new(1)
	arena.add_ship(ship)
	var co = arena.ships[0]
	var sealed: bool = ship.atmosphere.rooms.all(func(r): return r["sealed"])
	print("%s: %dx%d cells (hull %dx%d)  supply %.1f demand %.1f  unpowered %s  rooms %d sealed %s  can_fly '%s'" % [
		ship.name, hi.x - lo.x + 1 - 2 * MARGIN, hi.y - lo.y + 1 - 2 * MARGIN, hi.x - lo.x + 1, hi.y - lo.y + 1,
		supply, demand, str(unpowered), ship.atmosphere.rooms.size(), str(sealed), co.flight.can_fly(ship.components, co.powered)])
	print("   mass %.0f  thrust %.1f  accel %.1f px/s2  turn %.2f rad/s2  hull %d  shield %d layers x %d sectors  weapons %d  cables %d  tiles %d  cargo %s" % [
		co.mass, co.thrust, co.thrust * co.flight.thrust_to_accel / co.mass, co.thrust * co.flight.turn_factor / co.mass,
		co.hull_max, co.layers_cap, co.sectors, co.mounts.size(), ship.cables.cells.size(), g.tiles.size(), str(ship.inventory.to_dict())])
