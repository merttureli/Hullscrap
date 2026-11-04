extends SceneTree
## Not a test (the runner only loads test_*.gd). Rebuilds the three starter ships and the pirate raider of data/ships/:
##   godot --headless --path . --script res://tests/tool_make_starters.gd [-- rustbucket courier prism pirate]
## (the names after -- pick the ships to rebuild; none means all four).
## No ship is a rectangle (docs/CONTENT.md 4c). Each is described below by its OUTLINE, a polygon on the
## cell lattice that hull_outline.gd turns into the skin with exact shaped cells (slope45, slope2, round2
## arcs: never stair-steps), the bulkheads that cut the inside into rooms, doors, parts and plating
## (local coordinates, the top-left corner of the outline's bounding box is 0,0). It is built through
## BuildSession.apply, wired by a cheap router, then exported with Ship.to_dict(). The hull is the
## bounding box plus MARGIN cells, and the ship sits in the middle of its grid (63x63, a starter's 83x83). Prints a map
## (shaped cells as triangles, arcs as o) and the stats of every ship, and fails when a floor cell
## cannot be reached by a crew body from the helm.
## A weapon or engine is a hull mount (docs/CONTENT.md 4f): its entry is [id, x, y, rot] with x, y the
## top-left cell of its OUTSIDE half (in space, against a flat stretch of the outer wall face; outward
## is up at rot 0, so rear engines use rot 2); the inside half goes on the floor behind the wall by the
## placement rule, so the part has to be placed where the real mount rules (mounts.gd) allow it.
## A STARTER (docs/CONTENT.md 4c, "Start with very little") has a "frame" outline too: a big silhouette in the
## same local coordinates as everything else (its bounding box starts at 0,0, the ship sits in the middle of the
## grid). The "outline" of such a ship is only its built core, somewhere inside the frame: the essentials and the
## walls of their rooms. Everything built has to stay inside that silhouette (the tool fails if not), which also
## places the core in the grid. The hull a starter is saved with is the big round build area (playtest 2, B1): a
## disc of DISC_R cells round the middle of the grid, joined with every cell the ship uses, the rest empty hull
## for the player to build in. The pirate has no frame: its hull stays the bounding box plus MARGIN.

const Structure = preload("res://scripts/ship/structure.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const HullOutline = preload("res://scripts/ship/hull_outline.gd")

const GRID := Vector2i(63, 63)  ## the grid of the pirate, and the limit a starter's authored frame outline is grown within
const START_GRID := Vector2i(83, 83)  ## the grid of a starter: its round build area (DISC_R) plus 3 cells at the edge for the outside half of a mount
const MARGIN := 2
const MAX_FILL := 0.84  ## a grown frame stays a silhouette: its cells over its box (tests/test_starter_ships.gd wants under 85%)
const FRAME_GROWTH := 0.15  ## P4: a starter's frame is grown by about this share of its area (the built core stays as it is)
const DISC_R := 38.0  ## B1: the build area of a starter is a disc of this radius in cells, centred on its grid (START_GRID)
const OUT_DIR := "res://data/ships/"
const SIDES: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
## Who starts aboard: the soldier alone (playtest 2, A1). Ada is found in a distress pod (data/packs/start_alone), the rest are hired or met.
const SOLDIER := [{"name": "Soldier", "species": "human"}]
const START_AMMO := 10  ## rounds of hand_ammo in every starter's hold
const STOCK := {"scrap": 5000, "copper": 600, "titanium": 400, "silicon": 400, "crystal": 200, "plasma_cell": 100, "polymer": 600}
## Cost of crossing a cell when routing a cable: walls, doors and parts are cheap (the wire hides there).
const WIRE_COST := {"solid": 2, "part": 2, "floor": 5, "none": 14}

var _bad := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var skin_only: bool = "skin" in args
	var makers := _makers()
	for key in makers:
		if args.size() - int(skin_only) == 0 or key in args:
			_make(makers[key].call(), skin_only)
	quit(1 if _bad else 0)


## The designs this tool builds: name -> Callable returning a spec. tests/tool_make_starters2.gd overrides it.
func _makers() -> Dictionary:
	return {"rustbucket": _rustbucket, "courier": _courier, "prism": _prism, "pirate": _pirate}


# --- the designs ---------------------------------------------------------------------------------------
# outline: see hull_outline.gd. plate: the tile of the plated skin cells, plated: which skin cells (local
# cell -> bool) are plated, the others are steel; thick (optional): which cells behind a plated one are
# plated too (else steel). walls: bulkheads [x0, y0, x1, y1] (inclusive cells of floor turned into wall,
# also used to square off a corner no crew body would fit in); doors [x, y, "h" | "v"]; parts [id, x, y,
# rot] (mounts: the outside half). Each ship keeps the parts, crew and cargo of the rectangle it replaced,
# and its mass and hull integrity stay within 15% of it (tests/test_ship_silhouettes.gd).

## Scrap line: a lumpy freighter, scrap-plated all round, unreliable parts. One Mk2 reactor, because scrap
## parts draw 20% more and make 10% less, and the Wheezer, both Kickjets and the Rattle Burst add up to more
## than a scrap reactor gives.
## The frame is lumpy and lopsided: a blunt bow cut by 45 degree slopes (short on the port side, long on the
## starboard), a fat cargo sponson on the port side, a patch sticking out of the starboard side and a
## rounded stern. Only the core is built: a plated bow with the Rattle Burst and the bridge, a workshop under
## the bridge's port half (the starboard half hangs over a notch), the engine room with a wide stern block
## and round2 corners, and the quarters in the port sponson. A Net Mouth waits in the hold.
func _rustbucket() -> Dictionary:
	return {
		"file": "starter_rustbucket", "name": "Rustbucket", "was_hull": 1122, "at": [6, 5],
		"crew": SOLDIER, "kit": "shield",
		"blurb": "Ma Gantry's first loan and her worst: three owners, two fires and a clan wedding went into this scrap hull. Thick-skinned, a bolt thrower, a patched bubble, lots of empty frame. Now it's yours, and so is the bill.",
		"frame": [[12, 0], [38, 0], [46, 8], [46, 14], [52, 20], [52, 28], [46, 34], ["arc", 44, 42, 0, 90], [12, 44], ["arc", 12, 42, 90, 180], [10, 36], [0, 26], [0, 18], [6, 12], [6, 8], [12, 2]],
		"outline": [[20, 6], [20, 4], [22, 4], [22, 7], [26, 7], [26, 4], [28, 4], [30, 6], [30, 13], [24, 13], [24, 17], [30, 17], [30, 25], ["arc", 28, 25, 0, 90], [19, 27], ["arc", 19, 25, 90, 180], [17, 22], [11, 22], [10, 21], [10, 15], [11, 14], [17, 14], [17, 9]],
		"plate": "scrap_plate", "plated": func(c): return true, "backed": func(c): return c.y <= 9 or c.x >= 29 or c.y >= 25, "thick": func(c): return true,
		"walls": [
			[18, 12, 23, 12], [18, 16, 23, 16], [17, 14, 17, 21], [20, 7, 20, 7], [27, 7, 27, 7],  # the bridge's floor, the workshop's floor, the quarters' wall, the corners behind the horns
		],
		"doors": [[19, 12, "h"], [19, 16, "h"], [17, 18, "v"]],
		"parts": [
			["bolt_thrower_scrap", 22, 5], ["helm", 26, 10], ["fabricator", 18, 13],
			["bed", 11, 15], ["oxygen_scrap_mk1", 15, 15],
			["reactor_mk2", 21, 18], ["engine_scrap_mk1", 19, 27, 2], ["engine_scrap_mk1", 24, 27, 2],
			["shield_scrap_mk1", 13, 17, 0],  # in place of the Rattle Burst turret (fights5): the nose gun got shot out in 12 of 12 fights, a Courier's shield absorbs a quarter of the shots
		],
		"cargo": {"scrap": 250, "copper": 80, "polymer": 30, "net_mouth_scrap": 1, "reactor_mk1": 1, "credits": 300, "fuel": 6},
	}


## Standard line: small and quick. One Mk2 reactor feeds the pulse gun, both rear engines, the O2 and the workshop.
## The frame is an arrowhead (a long slope2 taper to a flat tip, swept-back wings with 45 degree edges, a tail
## block), symmetric about x = 24. Only the fuselage is built: a titanium nose with the pulse gun on its tip,
## the bridge, the quarters, the workshop and the engine room with the two Mk2 engines. The wings and the
## rest of the frame are empty hull; the strafe pair waits in the hold.
func _courier() -> Dictionary:
	return {
		"file": "starter_courier", "name": "Courier", "was_hull": 864,
		"crew": SOLDIER, "kit": "shield",
		"blurb": "Thirty years a Concord mail boat, never late until the Snap. Her courier retired and left her to whoever signed first. A titanium nose, a pulse gun, a light shield, a roomy frame and strafe jets in the hold.",
		"frame": [[20, 0], [28, 0], [34, 12], [36, 12], [48, 24], [48, 34], [42, 40], [34, 40], [34, 44], [14, 44], [14, 40], [6, 40], [0, 34], [0, 24], [12, 12], [14, 12]],
		"outline": [[20, 9], [28, 9], [30, 13], [30, 29], [29, 30], [19, 30], [18, 29], [18, 13]],
		"plate": "titanium_alloy", "plated": func(c): return true, "backed": func(c): return c.y <= 13, "thick": func(c): return c.y <= 13,
		"walls": [
			[19, 14, 28, 14], [24, 15, 24, 20], [19, 21, 28, 21],  # the bridge's floor, the quarters' wall, the engine room's ceiling
		],
		"doors": [[21, 14, "h"], [26, 14, "h"], [21, 21, "h"], [26, 21, "h"]],
		"parts": [
			["pulse_mk1", 22, 7], ["helm", 26, 12],
			["bed", 19, 15, 1], ["shield_mk1", 19, 17, 1], ["oxygen_gen", 19, 19, 1], ["fabricator", 25, 17],
			["reactor_mk2", 22, 22], ["engine_mk1", 20, 30, 2], ["engine_mk1", 24, 30, 2],
		],
		"cargo": {"scrap": 250, "copper": 80, "titanium": 40, "polymer": 30, "afterburner": 1, "reactor_mk1": 1, "credits": 500, "fuel": 6},
	}


## Neon line: a glass cannon with a lot of power. One Prism Core gives more than the whole ship draws.
## The frame is a faceted crystal: only 45 degree facets (a long hexagon with a pointed bow and stern),
## symmetric about x = 19. Only the spine is built: a coated spire with the Heat Lance on its tip, the
## bridge, the quarters and the workshop side by side, and the engine room with the Ion Drive at the pointed
## stern, and the Neon Lattice Shield in the quarters.
func _prism() -> Dictionary:
	return {
		"file": "starter_prism", "name": "Prism", "was_hull": 624, "at": [7, 9],
		"crew": SOLDIER, "kit": "shield",
		"blurb": "Built by a Lumen apprentice who wanted a lamp and got a gun. Huge power, thin skin, a lattice shield, a big empty crystal frame to grow in, and everything runs hot. The apprentice left in a hurry. You were nearby.",
		"frame": [[15, 0], [23, 0], [38, 15], [38, 25], [23, 40], [15, 40], [0, 25], [0, 15]],
		"outline": [[9, 0], [15, 0], [18, 3], [18, 19], [15, 22], [9, 22], [6, 19], [6, 3]],
		"plate": "reflective_coating", "plated": func(c): return true, "backed": func(c): return c.y <= 2, "thick": func(c): return c.y <= 2,
		"walls": [
			[7, 6, 16, 6], [12, 7, 12, 12], [7, 13, 16, 13],  # the bridge's floor, the quarters' wall, the engine room's ceiling
		],
		"doors": [[9, 6, "h"], [14, 6, "h"], [9, 13, "h"], [14, 13, "h"]],
		"parts": [
			["heat_lance_neon", 10, -2], ["helm", 11, 4],
			["bed", 7, 7, 1], ["shield_neon_mk1", 7, 9, 1], ["oxygen_gen", 7, 11, 1], ["fabricator", 13, 8],
			["reactor_neon_mk1", 10, 14], ["radiator", 7, 15], ["radiator", 14, 15], ["engine_neon_mk1", 10, 22, 2],
		],
		"cargo": {"scrap": 250, "copper": 80, "polymer": 30, "silicon": 40, "crystal": 12, "plasma_cell": 3, "afterburner": 1, "reactor_mk1": 1, "credits": 400, "fuel": 6},
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

## The frame `cells` (Vector2i -> true) grown by about FRAME_GROWTH of its area, without changing its look: up to three dilations, each
## one cell wide, sideways (x), lengthways (y), all four ways (r4) or all eight (r8), the mix whose area is nearest the goal and
## that still fits the grid. The grown frame may start at negative coordinates: the core keeps its own.
func _grow_frame(cells: Dictionary, who: String) -> Dictionary:
	var goal := float(cells.size()) * (1.0 + FRAME_GROWTH)
	var best: Dictionary = cells
	var best_err := INF
	var best_ops := []
	var ops: Array[String] = ["x", "y", "r4", "r8"]
	var plans := [[]]
	for a in ops:
		plans.append([a])
		for b in ops:
			if ops.find(b) >= ops.find(a):
				plans.append([a, b])
				for d in ops:
					if ops.find(d) >= ops.find(b):
						plans.append([a, b, d])
	for plan in plans:
		if plan.is_empty():
			continue
		var grown := cells
		for op in plan:
			grown = _dilate(grown, op)
			if grown.size() > goal * 1.25:
				break
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := Vector2i(-(1 << 20), -(1 << 20))
		for c in grown:
			lo = lo.min(c)
			hi = hi.max(c)
		var err: float = absf(float(grown.size()) - goal) + 0.5 * plan.size()
		var fill := float(grown.size()) / float((hi.x - lo.x + 1) * (hi.y - lo.y + 1))
		if hi.x - lo.x + 1 <= GRID.x and hi.y - lo.y + 1 <= GRID.y and fill <= MAX_FILL and err < best_err:
			best = grown
			best_err = err
			best_ops = plan
	if best == cells:
		_fail(who + ": the frame cannot grow and still fit the grid")
	print("%s: frame %d -> %d cells (+%.0f%%) by %s" % [who, cells.size(), best.size(), 100.0 * (float(best.size()) / cells.size() - 1.0), str(best_ops)])
	return best


## `cells` with every cell's neighbours added: "x" left and right, "y" up and down, "r4" both, "r8" the eight round it.
func _dilate(cells: Dictionary, op: String) -> Dictionary:
	var steps: Array[Vector2i] = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var diag: bool = dx != 0 and dy != 0
			if (dx == 0 and dy == 0) or (op == "x" and dy != 0) or (op == "y" and dx != 0) or (op == "r4" and diag):
				continue
			steps.append(Vector2i(dx, dy))
	var out := cells.duplicate()
	for c in cells:
		for st in steps:
			out[c + st] = true
	return out


## A starter is authored in the local coordinates of its built core and carries "at": [x, y], where the core
## sits in the frame. Returns the spec with the outline, bulkheads, doors and parts moved there.
func _placed(spec: Dictionary) -> Dictionary:
	if not spec.has("at"):
		return spec
	var d := Vector2i(spec["at"][0], spec["at"][1])
	var out := spec.duplicate()
	out["outline"] = spec["outline"].map(func(p): return [p[0], p[1] + d.x, p[2] + d.y, p[3], p[4]] if p[0] is String else [p[0] + d.x, p[1] + d.y])
	out["walls"] = spec["walls"].map(func(w): return [w[0] + d.x, w[1] + d.y, w[2] + d.x, w[3] + d.y])
	out["doors"] = spec["doors"].map(func(w): return [w[0] + d.x, w[1] + d.y, w[2]])
	if spec.has("rooms"):
		out["rooms"] = spec["rooms"].map(func(w): return [w[0] + d.x, w[1] + d.y, w[2] + d.x, w[3] + d.y])
	out["parts"] = spec["parts"].map(func(p): return p if p[1] is String else [p[0], p[1] + d.x, p[2] + d.y] + p.slice(3))
	var plated: Callable = spec["plated"]
	out["plated"] = func(c): return plated.call(c - d)
	for key in ["thick", "backed", "plate"]:
		if spec.has(key) and spec[key] is Callable:
			var fn: Callable = spec[key]
			out[key] = func(c): return fn.call(c - d)
	out.erase("at")
	return out


func _make(spec: Dictionary, skin_only := false) -> void:
	spec = _placed(spec)
	var name: String = spec["name"]
	var ras := HullOutline.rasterize(spec["outline"])
	for e in ras["errors"]:
		_fail("%s: %s" % [name, e])
	var frame := {}  # Vector2i -> true: the hull frame (starters), else empty
	var flo := Vector2i.ZERO
	var fhi := Vector2i.ZERO
	if spec.has("frame"):
		var fr := HullOutline.rasterize(spec["frame"])
		for e in fr["errors"]:
			_fail("%s frame: %s" % [name, e])
		flo = Vector2i(1 << 20, 1 << 20)
		fhi = Vector2i(-(1 << 20), -(1 << 20))
		for c in fr["cells"]:
			frame[c] = true
			flo = flo.min(c)
			fhi = fhi.max(c)
		if flo != Vector2i.ZERO:
			_fail("%s: the frame starts at %s, not 0,0" % [name, str(flo)])
		spec["frame_was"] = frame.size()
		frame = _grow_frame(frame, name)  # P4: a little more empty hull to build in
		flo = Vector2i(1 << 20, 1 << 20)
		fhi = Vector2i(-(1 << 20), -(1 << 20))
		for c in frame:
			flo = flo.min(c)
			fhi = fhi.max(c)
	var plate_of: Callable = spec["plate"] if spec["plate"] is Callable else func(_c): return spec["plate"]  # a tile id, or a Callable(cell) -> the tile id of that cell
	var skin := HullOutline.layers(ras["cells"], func(c): return plate_of.call(c) if spec["plated"].call(c) else "", func(c): return plate_of.call(c) if spec.has("thick") and spec["thick"].call(c) else "", spec.get("backed", Callable()))
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in skin:
		lo = lo.min(c)
		hi = hi.max(c)
	if lo != Vector2i.ZERO and frame.is_empty():
		_fail("%s: the outline starts at %s, not 0,0" % [name, str(lo)])
	if not frame.is_empty():
		lo = flo  # the grid position comes from the frame
		hi = fhi
	for w in spec["walls"]:
		for y in range(w[1], w[3] + 1):
			for x in range(w[0], w[2] + 1):
				var c := Vector2i(x, y)
				if not skin.has(c):
					_fail("%s: the bulkhead %s leaves the hull at %s" % [name, str(w), str(c)])
				elif skin[c]["tile"] == "floor":
					skin[c]["tile"] = "wall"
	if spec.has("rooms"):  # "rooms" [x0, y0, x1, y1] (inclusive cells): the floor of the ship. Every other cell inside the outline is wall.
		var room_cells := {}
		for r in spec["rooms"]:
			for y in range(r[1], r[3] + 1):
				for x in range(r[0], r[2] + 1):
					room_cells[Vector2i(x, y)] = true
		for c in room_cells:
			if not skin.has(c) or skin[c]["tile"] != "floor":
				_fail("%s: the room cell %s is not floor (%s)" % [name, str(c), skin[c]["tile"] if skin.has(c) else "outside the hull"])
		for c in skin:
			if skin[c]["tile"] == "floor" and not room_cells.has(c):
				skin[c]["tile"] = "wall"
	if skin_only:
		print("==== %s (skin only)" % name)
		_print_skin(skin, lo, hi, frame)
		return

	var defs := TileDefs.new()
	defs.load_file(Ship.TILES_PATH)
	var grid_size := START_GRID if spec.has("frame") else GRID
	var ship := Ship.new(name, ShipGrid.new(grid_size, defs))
	var g: ShipGrid = ship.grid
	for y in grid_size.y:
		for x in grid_size.x:
			g.hull[Vector2i(x, y)] = true  # the real hull is set at the end
	ship.inventory.load_dict(STOCK)
	for p in spec["parts"]:
		ship.inventory.add(p[0], 1)
	var off: Vector2i = (grid_size - (hi - lo + Vector2i.ONE)) / 2 - lo
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
		if p[1] is String:  # [id, "flank"]: a second gun on the first flat stretch of a flank the mount rules accept
			_flank(session, p[0], skin, off, name)
			continue
		_apply(session, [{"layer": "component", "id": p[0], "anchor": Vector2i(p[1], p[2]) + off, "rot": p[3] if p.size() > 3 else 0}], "%s: %s at %d,%d" % [name, p[0], p[1], p[2]])

	_wire(ship, session, spec)

	var blo := Vector2i(grid_size)
	var bhi := Vector2i.ZERO
	var all: Array = g.tiles.keys() + ship.cables.cells.keys()
	for uid in ship.components.instances:
		all.append_array(ship.components.instances[uid]["cells"])
		all.append_array(ship.components.instances[uid]["out_cells"])
	for c in all:
		blo = blo.min(c)
		bhi = bhi.max(c)
	g.hull.clear()
	if frame.is_empty():
		blo -= Vector2i(MARGIN, MARGIN)
		bhi += Vector2i(MARGIN, MARGIN)
		if blo.x < 0 or blo.y < 0 or bhi.x >= grid_size.x or bhi.y >= grid_size.y:
			_fail(name + ": the hull does not fit the grid")
		for y in range(blo.y, bhi.y + 1):
			for x in range(blo.x, bhi.x + 1):
				g.hull[Vector2i(x, y)] = true
	else:
		var outside := all.filter(func(c): return not frame.has(c - off))
		if not outside.is_empty():
			_fail("%s: %d built cells leave the frame, first %s" % [name, outside.size(), str(outside.slice(0, 6).map(func(c): return c - off))])
		g.fill_circle_hull(DISC_R)  # B1: the build area is a big disc (whole cells, so the rim is a stair), joined with everything built
		for c in all:
			g.hull[c] = true
	ship.inventory.load_dict(spec["cargo"])
	if ship.inventory.count("hand_ammo") == 0:
		ship.inventory.add("hand_ammo", START_AMMO)  # (Beta 4.1) every run starts with some rounds for the hand weapons
	ship.refresh()

	var saved := ship.to_dict()
	saved["blurb"] = spec["blurb"]
	saved["crew"] = spec["crew"]  # who starts aboard and their species (Jobs.spawn_crew)
	if spec.has("ai"):
		saved["ai"] = spec["ai"]  # the pilot's style and aim skill (pilot_ai.gd)
	if spec.has("hangar"):
		saved["hangar"] = spec["hangar"]  # {group, layout, unlock}: the hangar tab, the layout A/B/C and the unlock that opens it (space/hangar.gd)
	var path: String = spec.get("dir", OUT_DIR) + spec["file"] + ".json"
	if FileAccess.file_exists(path):  # the blueprints a design knows stay as they were: a regenerated one must not need a pack the old one did not
		var was = JSON.parse_string(FileAccess.get_file_as_string(path))
		if was is Dictionary and was.has("crafting"):
			saved["crafting"] = was["crafting"]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(_format(saved))
	f.close()
	_report(spec, path, off)


## Mount part `id` on a flank: the first anchor, scanning down the hull, the left-hand wall (rot 3, the quarters) before the right (rot 1,
## the workshop stays the fabricator's alone), that the real mount rules accept.
func _flank(session: BuildSession, id: String, skin: Dictionary, off: Vector2i, what: String) -> void:
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in skin:
		lo = lo.min(c)
		hi = hi.max(c)
	for rot in [3, 1]:
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x - 4, hi.x + 4):
				var r := session.apply([{"layer": "component", "id": id, "anchor": Vector2i(x, y) + off, "rot": rot}])
				if r["skipped"] == 0:
					print("%s: %s on the flank at %d,%d rot %d" % [what, id, x, y, rot])
					return
	_fail("%s: no flank spot for %s" % [what, id])


func _apply(session: BuildSession, changes: Array, what: String) -> void:
	var r := session.apply(changes)
	if r["skipped"] > 0:
		_fail("%s: %d of %d changes refused: %s" % [what, r["skipped"], changes.size(), r["reason"]])


func _fail(text: String) -> void:
	printerr("FAIL " + text)
	_bad = true


## The skin map of a hull before anything is built in it: P plate, # steel, . floor, triangles and o for shaped cells,
## : for a cell of the empty frame.
func _print_skin(skin: Dictionary, lo: Vector2i, hi: Vector2i, frame := {}) -> void:
	print(HullOutline.ruler(lo, hi))
	for y in range(lo.y, hi.y + 1):
		var row := "%3d " % y
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			if not skin.has(c):
				row += ":" if frame.has(c) else " "  # empty hull frame
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
	var tile_glyph := {"floor": ".", "wall": "#", "door": "D", "scrap_plate": "s", "titanium_alloy": "T", "reflective_coating": "x", "ram_plating": "r", "whipple_spacer": "p", "neon_lattice": "n", "heavy_armor": "h", "ablative_plating": "a"}
	var lo := Vector2i(g.size)
	var hi := Vector2i.ZERO
	var cells: Array = g.tiles.keys()
	for uid in ship.components.instances:
		cells.append_array(ship.components.instances[uid]["out_cells"])
	if spec.has("frame"):
		cells.append_array(g.hull.keys())  # the map shows the whole frame
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
				if spec.has("frame") and g.hull.has(c):
					ch = ":"  # empty hull to build on
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
	var tlo := Vector2i(g.size)
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
		Structure.totals(ship).y, co.layers_cap, co.sectors, co.mounts.size(), ship.cables.cells.size(), g.tiles.size(), str(ship.inventory.to_dict())])
	if spec.has("frame"):
		var empty := 0
		for c in g.hull:
			empty += int(g.get_tile(c) == "" and ship.components.at_out(c) < 0)
		print("   frame %d cells%s, %d tiles, %d components, empty %d = %.0f%%" % [
			g.hull.size(), " (%.2fx the old hull of %d)" % [float(g.hull.size()) / spec["was_hull"], spec["was_hull"]] if spec.has("was_hull") else "", g.tiles.size(), ship.components.instances.size(), empty, 100.0 * empty / g.hull.size()])
		print("ROW %s|%s|%d|%d|%d|%.0f|%d" % [spec["file"], str(spec.get("hangar", {}).get("group", "")) + " " + str(spec.get("hangar", {}).get("layout", "")), int(Structure.totals(ship).y), ship.components.instances.size(), g.hull.size(), 100.0 * empty / g.hull.size(), int(spec.get("frame_was", 0))])
	if spec.has("frame"):
		_check_loadout(spec, ship)
	var pockets := HullOutline.pockets(ship)
	if not pockets.is_empty():
		_fail("%s: %d floor cells no crew body reaches from the helm: %s" % [spec["name"], pockets.size(), str(pockets.map(func(c): return c - off))])


## The loadout rules of a starter (playtest 2, P3): a helm, one reactor, one bed, air and the fabricator; 1-2 engines; 1-2 guns; then
## exactly one of a shield (one gun) and a medbay (1-2 guns), or neither (two guns); no spare shield or medbay in the hold; 250 scrap.
func _check_loadout(spec: Dictionary, ship: Ship) -> void:
	var fam := {}
	for uid in ship.components.instances:
		var f := str(ship.components.def(ship.components.instances[uid]["id"]).get("family", ""))
		fam[f] = int(fam.get(f, 0)) + 1
	var who: String = spec["name"]
	for f in ["helm", "reactor", "oxygen", "bed", "fabricator"]:
		if int(fam.get(f, 0)) != 1:
			_fail("%s: %d parts of family %s, wants exactly 1" % [who, int(fam.get(f, 0)), f])
	var guns := int(fam.get("weapon", 0))
	var shields := int(fam.get("shield", 0))
	var medbays := int(fam.get("medbay", 0))
	if not int(fam.get("engine", 0)) in [1, 2]:
		_fail("%s: %d engines, wants 1 or 2" % [who, int(fam.get("engine", 0))])
	if not guns in [1, 2]:
		_fail("%s: %d guns, wants 1 or 2" % [who, guns])
	if shields + medbays > 1:
		_fail("%s: a shield and a medbay both built" % who)
	if shields + medbays == 0 and guns != 2:
		_fail("%s: neither a shield nor a medbay, so it wants two guns (has %d)" % [who, guns])
	if shields == 1 and guns != 1:
		_fail("%s: a shield ship wants one gun (has %d)" % [who, guns])
	for id in ship.inventory.to_dict():
		if str(ship.components.def(str(id)).get("family", "")) in ["shield", "medbay"]:
			_fail("%s: a spare %s in the hold" % [who, id])
	if ship.inventory.count("scrap") != 250:
		_fail("%s: %d scrap in the hold, wants 250" % [who, ship.inventory.count("scrap")])
