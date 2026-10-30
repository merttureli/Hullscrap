extends SceneTree
## Not a test (the runner only loads test_*.gd). Rebuilds the three starter ships and the pirate raider of data/ships/:
##   godot --headless --path . --script res://tests/tool_make_starters.gd [-- rustbucket courier prism pirate]
## (the names after -- pick the ships to rebuild; none means all four).
## No ship is a rectangle (docs/CONTENT.md 4c). Each is described below by its OUTLINE, a polygon on the
## cell lattice that hull_outline.gd turns into the skin with exact shaped cells (slope45, slope2, round2
## arcs: never stair-steps), the bulkheads that cut the inside into rooms, doors, parts and plating
## (local coordinates, the top-left corner of the outline's bounding box is 0,0). It is built through
## BuildSession.apply, wired by a cheap router, then exported with Ship.to_dict(). The hull is the
## bounding box plus MARGIN cells, and the ship sits in the middle of the 63x63 grid. Prints a map
## (shaped cells as triangles, arcs as o) and the stats of every ship, and fails when a floor cell
## cannot be reached by a crew body from the helm.
## A weapon or engine is a hull mount (docs/CONTENT.md 4f): its entry is [id, x, y, rot] with x, y the
## top-left cell of its OUTSIDE half (in space, against a flat stretch of the outer wall face; outward
## is up at rot 0, so rear engines use rot 2); the inside half goes on the floor behind the wall by the
## placement rule, so the part has to be placed where the real mount rules (mounts.gd) allow it.

const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const HullOutline = preload("res://tests/hull_outline.gd")

const GRID := Vector2i(63, 63)
const MARGIN := 2
const OUT_DIR := "res://data/ships/"
const SIDES: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const STOCK := {"scrap": 5000, "copper": 600, "titanium": 400, "silicon": 400, "crystal": 200, "plasma_cell": 100, "polymer": 100}
## Cost of crossing a cell when routing a cable: walls, doors and parts are cheap (the wire hides there).
const WIRE_COST := {"solid": 2, "part": 2, "floor": 5, "none": 14}

var _bad := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var skin_only: bool = "skin" in args
	var makers := {"rustbucket": _rustbucket, "courier": _courier, "prism": _prism, "pirate": _pirate}
	for key in makers:
		if args.size() - int(skin_only) == 0 or key in args:
			_make(makers[key].call(), skin_only)
	quit(1 if _bad else 0)


# --- the designs ---------------------------------------------------------------------------------------
# outline: see hull_outline.gd. plate: the tile of the plated skin cells, plated: which skin cells (local
# cell -> bool) are plated, the others are steel; thick (optional): which cells behind a plated one are
# plated too (else steel). walls: bulkheads [x0, y0, x1, y1] (inclusive cells of floor turned into wall,
# also used to square off a corner no crew body would fit in); doors [x, y, "h" | "v"]; parts [id, x, y,
# rot] (mounts: the outside half). Each ship keeps the parts, crew and cargo of the rectangle it replaced,
# and its mass and hull integrity stay within 15% of it (tests/test_ship_silhouettes.gd).

## Scrap line: a lumpy freighter, a hold full of junk, unreliable parts. Three reactors, because scrap
## parts draw 20% more and make 10% less.
## Lumpy and lopsided: a blunt bow cut by 45 degree slopes (short on the port side, long on the starboard),
## one fat cargo sponson on the port side, a scrap-plate patch sticking out of the starboard side, and a
## wide engine block at the stern with round2 corners.
func _rustbucket() -> Dictionary:
	return {
		"file": "starter_rustbucket", "name": "Rustbucket",
		"crew": [{"name": "Soldier", "species": "human"}, {"name": "Ada", "species": "human"}, {"name": "Rook", "species": "basalt"}, {"name": "Juno", "species": "fenn"}],
		"blurb": "Welded together from scrap: cheap, thick-skinned, a hold full of junk. Parts rattle and quit, but it hits back.",
		"outline": [[8, 0], [21, 0], [26, 5], [26, 7], [30, 11], [30, 15], [26, 15], [26, 16], [28, 18], [28, 22], ["arc", 26, 22, 0, 90], [4, 24], ["arc", 4, 22, 90, 180], [2, 19], [0, 17], [0, 12], [5, 7], [5, 3]],
		"plate": "scrap_plate", "plated": func(c): return true, "thick": func(c): return c.y <= 1,
		"walls": [
			[7, 6, 23, 6], [11, 7, 11, 18], [6, 7, 10, 7], [3, 10, 3, 10], [2, 11, 10, 11],  # the weapons deck's floor, the workshop, the cargo hold's wall
			[18, 7, 18, 12], [12, 13, 25, 13], [24, 14, 24, 14], [25, 17, 25, 17], [3, 18, 25, 18],  # the bridge, the engineering hall (its corners squared off), the engine deck's ceiling
		],
		"doors": [[13, 6, "h"], [21, 6, "h"], [18, 9, "v"], [11, 8, "v"], [11, 14, "v"], [14, 13, "h"], [12, 18, "h"], [20, 18, "h"]],
		"parts": [
			["shrapnel_cannon_scrap", 9, -3], ["rattle_burst_scrap", 13, -2], ["bolt_thrower_scrap", 17, -2],
			["fabricator", 7, 8], ["bed", 12, 8], ["bed", 14, 8], ["oxygen_scrap_mk1", 16, 8], ["helm", 21, 7], ["shield_scrap_mk1", 20, 9],
			["reactor_scrap_mk1", 12, 14], ["reactor_mk2", 16, 14], ["reactor_scrap_mk1", 20, 14],
			["radiator", 14, 20], ["engine_scrap_mk1", 5, 24, 2], ["engine_scrap_mk1", 21, 24, 2],
		],
		"cargo": {"scrap": 900, "copper": 60, "polymer": 12, "engine_scrap_mk1": 1, "radiator": 1, "bed": 1, "credits": 300, "fuel": 6},
	}


## Standard line: small and quick. Two Mk2 reactors because one cannot feed the guns, the shield, both rear
## engines and the strafe pair on the side walls.
## A sleek arrowhead: a long slope2 taper to a flat tip that carries the pulse gun, a narrow neck, a laser
## on each shoulder step, and swept-back wings (45 degree leading edges) whose tips carry the strafe
## engines, with a notch between the rear engines. Symmetric about x = 12.
func _courier() -> Dictionary:
	return {
		"file": "starter_courier", "name": "Courier",
		"crew": [{"name": "Soldier", "species": "human"}, {"name": "Ada", "species": "human"}, {"name": "Bram", "species": "basalt"}],
		"blurb": "Small, quick and reliable: standard parts, a titanium nose and a light shield. Stays out of trouble or shoots its way out.",
		"outline": [[9, 0], [15, 0], [18, 6], [22, 6], [24, 8], [24, 19], [19, 19], [15, 17], [9, 17], [5, 19], [0, 19], [0, 8], [2, 6], [6, 6]],
		"plate": "titanium_alloy", "plated": func(c): return c.y <= 6,
		"walls": [
			[7, 6, 7, 6], [16, 6, 16, 6], [6, 7, 7, 7], [16, 7, 17, 7], [7, 8, 16, 8], [7, 8, 7, 16], [16, 8, 16, 16], [8, 11, 15, 11], [8, 16, 8, 16], [15, 16, 15, 16],  # the bridge's floor, the wings' inner walls, the workshop's floor
			[17, 14, 22, 14],  # the right wing's engine room
		],
		"doors": [[10, 8, "h"], [10, 11, "h"], [7, 9, "v"], [7, 13, "v"], [16, 9, "v"], [16, 12, "v"], [19, 14, "h"]],
		"parts": [
			["laser_mk1", 2, 4], ["pulse_mk1", 10, -2], ["laser_mk1", 18, 4],
			["shield_mk1", 10, 4], ["helm", 8, 6], ["fabricator", 10, 9],
			["bed", 3, 10, 1], ["bed", 3, 12, 1], ["oxygen_gen", 3, 14, 1],
			["reactor_mk2", 8, 12], ["reactor_mk2", 12, 12], ["radiator", 17, 10],
			["engine_mk2", 1, 19, 2], ["engine_mk2", 19, 19, 2],
			["engine_mk1", -2, 10, 3], ["engine_mk1", 24, 10, 1],  # the strafe pair on the wing tips (push right and left)
		],
		"cargo": {"scrap": 220, "copper": 80, "titanium": 40, "polymer": 10, "engine_mk1": 1, "laser_mk1": 1, "afterburner": 1, "radiator": 1, "credits": 500, "fuel": 6},
	}


## Neon line: a glass cannon with a lot of power. A third radiator keeps the Heat Lance from cooking.
## A faceted crystal: only 45 degree facets, symmetric about x = 11, a coated spire on the bow with a gun on
## each step beside it, a pointed stern and a spine down the middle (shield, reactor, radiators, engine).
func _prism() -> Dictionary:
	return {
		"file": "starter_prism", "name": "Prism",
		"crew": [{"name": "Soldier", "species": "human"}, {"name": "Tess", "species": "emberkin"}, {"name": "Quill", "species": "fenn"}, {"name": "Wren", "species": "basalt"}],
		"blurb": "A neon glass cannon: huge power, a snappy four-sector shield, thin skin, and everything runs hot.",
		"outline": [[10, 0], [12, 0], [14, 2], [18, 2], [22, 6], [22, 10], [14, 18], [8, 18], [0, 10], [0, 6], [4, 2], [8, 2]],
		"plate": "reflective_coating", "plated": func(c): return c.y <= 2 and (c.x in range(9, 13) or c.x in range(4, 8) or c.x in range(14, 18) or c.y < 2),
		"walls": [
			[3, 3, 3, 3], [18, 3, 18, 3], [1, 5, 1, 5], [20, 5, 20, 5], [1, 6, 20, 6], [8, 3, 8, 6], [13, 3, 13, 6],  # the nose deck's floor and corners, the walls round the shield room
			[8, 7, 8, 14], [13, 7, 13, 14], [5, 14, 8, 14], [13, 14, 16, 14], [6, 15, 6, 15], [15, 15, 15, 15],  # the spine's walls, the wings' floor, the engine room's corners
		],
		"doors": [[4, 6, "h"], [10, 6, "h"], [16, 6, "h"], [8, 8, "v"], [13, 8, "v"]],
		"parts": [
			["heat_lance_neon", 4, 0], ["siren_ion_neon", 14, 0], ["radiator", 2, 4], ["helm", 18, 4], ["shield_neon_mk1", 9, 2],
			["bed", 2, 7], ["bed", 4, 7], ["oxygen_gen", 6, 7], ["fabricator", 16, 7],
			["reactor_neon_mk1", 9, 7], ["radiator", 9, 11], ["radiator", 11, 11], ["engine_neon_mk1", 9, 18, 2],
		],
		"cargo": {"scrap": 120, "copper": 60, "polymer": 10, "silicon": 40, "crystal": 12, "plasma_cell": 3, "afterburner": 1, "radiator": 1, "bed": 1, "credits": 400, "fuel": 6},
	}


## The test pirate (combat_session.gd PIRATE_PATH): a small scrap-plated raider with one fixed laser and
## one Rattle Burst turret on the nose, two rear engines, a shield and the aim of a pilot of skill 0.5.
## A scrap reactor joins the Mk2 because the turret's scrap line draws 20% more than the laser it replaced.
## A jagged wedge: a notched prow of two horns with the laser in the notch, the starboard flank raked and cut
## into saw teeth, a big sponson on the port side set well back with the turret on it. Two rooms and one door.
func _pirate() -> Dictionary:
	return {
		"file": "pirate_raider", "name": "Pirate Raider",
		"crew": [{"name": "Grub", "species": "human"}, {"name": "Skab", "species": "human"}, {"name": "Vex", "species": "basalt"}],
		"ai": {"aim_skill": 0.5},
		"blurb": "A Rustfang raider: a laser to aim with the whole ship, a rattling turret that fires whether it is aimed or not.",
		"outline": [[7, 0], [9, 0], [9, 2], [13, 2], [13, 0], [15, 0], [22, 7], [22, 9], [20, 11], [22, 13], [18, 17], [8, 17], [4, 13], [0, 13], [0, 6], [5, 6], [5, 2]],
		"plate": "scrap_plate", "plated": func(c): return c.y <= 3 or (c.y == 6 and c.x in range(1, 5)),
		"walls": [[7, 2, 7, 2], [20, 12, 20, 12], [5, 13, 20, 13], [6, 14, 6, 14], [19, 14, 19, 14]],  # the engine deck's ceiling and the corners squared off
		"doors": [[12, 13, "h"]],
		"parts": [
			["laser_mk1", 9, 0], ["rattle_burst_scrap", 1, 4], ["helm", 14, 4], ["oxygen_gen", 6, 4],
			["reactor_mk2", 6, 8], ["reactor_scrap_mk1", 10, 8], ["shield_mk1", 14, 8],
			["engine_mk1", 8, 17, 2], ["engine_mk1", 14, 17, 2],
		],
		"cargo": {"scrap": 120, "copper": 10},
	}


# --- building ------------------------------------------------------------------------------------------

func _make(spec: Dictionary, skin_only := false) -> void:
	var name: String = spec["name"]
	var ras := HullOutline.rasterize(spec["outline"])
	for e in ras["errors"]:
		_fail("%s: %s" % [name, e])
	var plate: String = spec["plate"]
	var skin := HullOutline.layers(ras["cells"], func(c): return plate if spec["plated"].call(c) else "", func(c): return plate if spec.has("thick") and spec["thick"].call(c) else "")
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in skin:
		lo = lo.min(c)
		hi = hi.max(c)
	if lo != Vector2i.ZERO:
		_fail("%s: the outline starts at %s, not 0,0" % [name, str(lo)])
	for w in spec["walls"]:
		for y in range(w[1], w[3] + 1):
			for x in range(w[0], w[2] + 1):
				var c := Vector2i(x, y)
				if not skin.has(c):
					_fail("%s: the bulkhead %s leaves the hull at %s" % [name, str(w), str(c)])
				elif skin[c]["tile"] == "floor":
					skin[c]["tile"] = "wall"
	if skin_only:
		print("==== %s (skin only)" % name)
		_print_skin(skin, lo, hi)
		return

	var defs := TileDefs.new()
	defs.load_file(Ship.TILES_PATH)
	var ship := Ship.new(name, ShipGrid.new(GRID, defs))
	var g: ShipGrid = ship.grid
	for y in GRID.y:
		for x in GRID.x:
			g.hull[Vector2i(x, y)] = true  # the real hull is set at the end
	ship.inventory.load_dict(STOCK)
	for p in spec["parts"]:
		ship.inventory.add(p[0], 1)
	var off: Vector2i = (GRID - (hi - lo + Vector2i.ONE)) / 2
	var session := BuildSession.new(ship)

	var cells: Array = skin.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var changes := []
	for c in cells:
		var e := {"layer": "tile", "cell": c + off, "to": skin[c]["tile"]}
		e.merge(skin[c]["shape"])
		changes.append(e)
	_apply(session, changes, name + " hull")

	changes = []
	for d in spec["doors"]:
		changes.append({"layer": "tile", "cell": Vector2i(d[0], d[1]) + off, "to": "door", "axis": Vector2i.RIGHT if d[2] == "h" else Vector2i.DOWN})
	_apply(session, changes, name + " doors")

	for p in spec["parts"]:  # one at a time, so a refusal names its part
		_apply(session, [{"layer": "component", "id": p[0], "anchor": Vector2i(p[1], p[2]) + off, "rot": p[3] if p.size() > 3 else 0}], "%s: %s at %d,%d" % [name, p[0], p[1], p[2]])

	_wire(ship, session, spec)

	var blo := Vector2i(GRID)
	var bhi := Vector2i.ZERO
	var all: Array = g.tiles.keys() + ship.cables.cells.keys()
	for uid in ship.components.instances:
		all.append_array(ship.components.instances[uid]["cells"])
		all.append_array(ship.components.instances[uid]["out_cells"])
	for c in all:
		blo = blo.min(c)
		bhi = bhi.max(c)
	blo -= Vector2i(MARGIN, MARGIN)
	bhi += Vector2i(MARGIN, MARGIN)
	if blo.x < 0 or blo.y < 0 or bhi.x >= GRID.x or bhi.y >= GRID.y:
		_fail(name + ": the hull does not fit the grid")
	g.hull.clear()
	for y in range(blo.y, bhi.y + 1):
		for x in range(blo.x, bhi.x + 1):
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
	_report(spec, path, off)


func _apply(session: BuildSession, changes: Array, what: String) -> void:
	var r := session.apply(changes)
	if r["skipped"] > 0:
		_fail("%s: %d of %d changes refused: %s" % [what, r["skipped"], changes.size(), r["reason"]])


func _fail(text: String) -> void:
	printerr("FAIL " + text)
	_bad = true


## The skin map of a hull before anything is built in it: P plate, # steel, . floor, triangles and o for shaped cells.
func _print_skin(skin: Dictionary, lo: Vector2i, hi: Vector2i) -> void:
	print(HullOutline.ruler(lo, hi))
	for y in range(lo.y, hi.y + 1):
		var row := "%3d " % y
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			if not skin.has(c):
				row += " "
				continue
			var sd: Dictionary = skin[c]["shape"]
			row += HullOutline.shape_glyph(sd) if not sd.is_empty() else {"wall": "#", "floor": "."}.get(skin[c]["tile"], "P")
		var floors := range(lo.x, hi.x + 1).filter(func(x): return skin.has(Vector2i(x, y)) and skin[Vector2i(x, y)]["tile"] == "floor")
		print(row + ("   floor %d..%d (%d)" % [floors.min(), floors.max(), floors.size()] if not floors.is_empty() else ""))




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



func _report(spec: Dictionary, path: String, off: Vector2i) -> void:
	var ship := Ship.from_design(path)
	print("==== %s  (%s)" % [spec["name"], path])
	if ship == null:
		_fail(spec["name"] + ": the exported file does not load")
		return
	var g: ShipGrid = ship.grid
	var glyph := {"reactor": "R", "engine": "E", "oxygen": "O", "shield": "S", "weapon": "W", "helm": "H", "bed": "B", "fabricator": "F", "radiator": "i"}
	var tile_glyph := {"floor": ".", "wall": "#", "door": "D", "scrap_plate": "s", "titanium_alloy": "T", "reflective_coating": "x", "ram_plating": "r"}
	var lo := Vector2i(GRID)
	var hi := Vector2i.ZERO
	var cells: Array = g.tiles.keys()
	for uid in ship.components.instances:
		cells.append_array(ship.components.instances[uid]["out_cells"])
	for c in cells:
		lo = lo.min(c)
		hi = hi.max(c)
	for pass_no in (2 if OS.get_environment("CABLES") != "" else 1):
		print(HullOutline.ruler(lo - off, hi - off))
		for y in range(lo.y, hi.y + 1):
			var row := "%3d " % (y - off.y)
			for x in range(lo.x, hi.x + 1):
				var c := Vector2i(x, y)
				var ch := " "
				var t: String = g.get_tile(c)
				if t != "":
					ch = tile_glyph.get(t, "?")
					if g.shapes.has(c):
						ch = HullOutline.shape_glyph(g.shapes[c])
				var uid: int = ship.components.at(c)
				if uid >= 0:
					ch = glyph.get(ship.components.def(ship.components.instances[uid]["id"])["family"], "?")
				var out_uid: int = ship.components.at_out(c)
				if out_uid >= 0:  # the outside half of a mount, in lower case
					ch = glyph.get(ship.components.def(ship.components.instances[out_uid]["id"])["family"], "?").to_lower()
				if pass_no == 1 and ship.cables.has(c):
					ch = "+"
				row += ch
			print(row)
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
	var tlo := Vector2i(GRID)
	var thi := Vector2i.ZERO
	var area := 0.0
	for c in g.tiles:
		tlo = tlo.min(c)
		thi = thi.max(c)
		area += g.area_at(c)
	var box := thi - tlo + Vector2i.ONE
	print("%s: tiles %dx%d, solid %.0f%% of its box, %d shaped  supply %.1f demand %.1f  unpowered %s  rooms %d sealed %s  can_fly '%s'" % [
		ship.name, box.x, box.y, 100.0 * area / (box.x * box.y), g.shapes.size(),
		supply, demand, str(unpowered), ship.atmosphere.rooms.size(), str(sealed), co.flight.can_fly(ship.components, co.powered)])
	print("   mass %.0f  thrust %.1f  accel %.1f px/s2  turn %.2f rad/s2  hull %d  shield %d layers x %d sectors  weapons %d  cables %d  tiles %d  cargo %s" % [
		co.mass, co.thrust, co.thrust * co.flight.thrust_to_accel / co.mass, co.thrust * co.flight.turn_factor / co.mass,
		co.hull_max, co.layers_cap, co.sectors, co.mounts.size(), ship.cables.cells.size(), g.tiles.size(), str(ship.inventory.to_dict())])
	var pockets := HullOutline.pockets(ship)
	if not pockets.is_empty():
		_fail("%s: %d floor cells no crew body reaches from the helm: %s" % [spec["name"], pockets.size(), str(pockets.map(func(c): return c - off))])
