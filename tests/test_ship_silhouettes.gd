extends "res://tests/base_test.gd"
## No premade ship is a rectangle (docs/CONTENT.md 4c): the three starters, the pirate raider and the
## Rustfang rammer each have a real silhouette of shaped cells (a starter's silhouette is its big hull
## frame, with shaped cells on the core built in it), every gun and engine is mounted through a flat wall
## run into open space, every floor cell can be reached by a crew body from the helm, and each ship keeps
## what it is: its parts and cargo, a mass and a hull integrity within 15% of the numbers pinned below,
## power that balances and rooms that hold air.
## tests/tool_make_starters.gd and tests/tool_make_rammer.gd rebuild the files.

const Ship = preload("res://scripts/ship/ship.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Shapes = preload("res://scripts/ship/shapes.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")

const MAX_FILL := 0.85  ## the area of a ship's built cells (a slope or a curve counts its solid part) over the area of their bounding box; for a starter, its hull frame over the box of the frame
const MIN_SHAPED := 4  ## cells that are slopes or curves
const TOLERANCE := 0.15  ## how far mass and hull integrity may drift from the numbers pinned below

## What each ship is: its flight mass and hull integrity, its parts and its cargo. The three starters
## ("frame": true) are big hull frames with only the essentials built (docs/CONTENT.md 4c, "Start with
## very little"); the pirate and the rammer are the ships they were.
const SHIPS := {
	"Rustbucket": {
		"path": "res://data/ships/starter_rustbucket.json", "mass": 733.0, "hull": 246.0, "frame": true,
		"parts": {"bed": 2, "engine_scrap_mk1": 2, "fabricator": 1, "helm": 1, "oxygen_scrap_mk1": 1, "radiator": 1, "rattle_burst_scrap": 1, "reactor_mk2": 1},
		"cargo": {"scrap": 500, "copper": 80, "polymer": 30, "shield_scrap_mk1": 1, "net_mouth_scrap": 1, "credits": 300, "fuel": 6},
	},
	"Courier": {
		"path": "res://data/ships/starter_courier.json", "mass": 574.0, "hull": 168.0, "frame": true,
		"parts": {"bed": 2, "engine_mk2": 2, "fabricator": 1, "helm": 1, "oxygen_gen": 1, "pulse_mk1": 1, "reactor_mk2": 1},
		"cargo": {"scrap": 400, "copper": 80, "titanium": 40, "polymer": 30, "afterburner": 1, "shield_mk1": 1, "credits": 500, "fuel": 6},
	},
	"Prism": {
		"path": "res://data/ships/starter_prism.json", "mass": 451.0, "hull": 152.0, "frame": true,
		"parts": {"bed": 2, "engine_neon_mk1": 1, "fabricator": 1, "heat_lance_neon": 1, "helm": 1, "oxygen_gen": 1, "radiator": 2, "reactor_neon_mk1": 1},
		"cargo": {"scrap": 400, "copper": 80, "polymer": 30, "silicon": 40, "crystal": 12, "plasma_cell": 3, "afterburner": 1, "shield_neon_mk1": 1, "credits": 400, "fuel": 6},
	},
	"Pirate Raider": {
		"path": "res://data/ships/pirate_raider.json", "mass": 732.0, "hull": 64.0,
		"parts": {"engine_mk1": 2, "helm": 1, "laser_mk1": 1, "oxygen_gen": 1, "rattle_burst_scrap": 1, "reactor_mk2": 1, "reactor_scrap_mk1": 1, "shield_mk1": 1},
		"cargo": {"scrap": 120, "copper": 10},
	},
	"Rustfang": {
		"path": "res://data/ships/rustfang_rammer.json", "mass": 570.0, "hull": 180.0,
		"parts": {"bolt_thrower_scrap": 1, "engine_scrap_mk1": 2, "helm": 1, "reactor_scrap_mk1": 2},
		"cargo": {"scrap": 200, "copper": 30},
	},
}


func _ship(key: String) -> Ship:
	var ship := Ship.from_design(SHIPS[key]["path"])
	check(ship != null, key + " loads")
	return ship


func _parts(ship: Ship) -> Dictionary:
	var out := {}
	for uid in ship.components.instances:
		var id: String = ship.components.instances[uid]["id"]
		out[id] = int(out.get(id, 0)) + 1
	return out


func _helm_of(ship: Ship) -> int:
	for uid in ship.components.instances:
		if ship.components.def(ship.components.instances[uid]["id"]).get("family", "") == "helm":
			return uid
	return -1


## The walkable cells no crew body can reach from the helm: bodies walk by 4-neighbour steps of their
## top-left cell wherever all four cells are walkable (pathfinder.gd), and a cell is reached when
## some reachable body covers it. A floor pocket (a corner or a sliver of floor next to a slope that
## no 2x2 body fits in) shows up here.
func _unreached(ship: Ship) -> Array:
	var helm := _helm_of(ship)
	if helm < 0:
		return ship.grid.tiles.keys()
	var start: Vector2i = ship.components.instances[helm]["anchor"]
	if not Pathfinder.body_ok(ship.grid, start):
		return ship.grid.tiles.keys()
	var seen := {start: true}
	var open := [start]
	while not open.is_empty():
		var a: Vector2i = open.pop_back()
		for d in ShipGrid.SIDES:
			if not seen.has(a + d) and Pathfinder.body_ok(ship.grid, a + d):
				seen[a + d] = true
				open.append(a + d)
	var covered := {}
	for a in seen:
		for c in Pathfinder.body_cells(a):
			covered[c] = true
	return ship.grid.tiles.keys().filter(func(c): return Pathfinder.walkable(ship.grid, c) and not covered.has(c))


func test_no_ship_is_a_rectangle() -> void:
	for key in SHIPS:
		var ship := _ship(key)
		var g = ship.grid
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := Vector2i(-(1 << 20), -(1 << 20))
		var area := 0.0
		for c in (g.hull if SHIPS[key].get("frame", false) else g.tiles):  # a starter's silhouette is its frame
			lo = lo.min(c)
			hi = hi.max(c)
			area += 1.0 if SHIPS[key].get("frame", false) else g.area_at(c)
		var box := float((hi.x - lo.x + 1) * (hi.y - lo.y + 1))
		check(area < MAX_FILL * box, "%s: its solid cells fill %.0f%% of their bounding box (under %.0f%%)" % [key, 100.0 * area / box, 100.0 * MAX_FILL])
		check(g.shapes.size() >= MIN_SHAPED, "%s: %d shaped cells (at least %d)" % [key, g.shapes.size(), MIN_SHAPED])
		for c in g.shapes:
			check(Shapes.has_shape(str(g.shapes[c]["shape"])) and g.tile_flag(g.get_tile(c), "solid"), "%s: the shaped cell %s is a wall of a known shape" % [key, str(c)])


func test_every_mount_sits_on_a_flat_wall_with_its_outside_half_in_space() -> void:
	for key in SHIPS:
		var ship := _ship(key)
		var g = ship.grid
		var comps = ship.components
		var mounts := []
		for uid in comps.instances:
			if Mounts.is_mount(comps.def(comps.instances[uid]["id"])):
				mounts.append(uid)
		mounts.sort()
		check(mounts.size() >= 2, "%s has its guns and engines mounted (%d)" % [key, mounts.size()])
		var rear := 0
		for uid in mounts:
			var inst: Dictionary = comps.instances[uid].duplicate(true)
			var def: Dictionary = comps.def(inst["id"])
			var name := "%s: %s at %s" % [key, inst["id"], str(inst["anchor"])]
			check(comps.has_outside(uid) and comps.link_intact(g, uid), name + " has both halves and a whole wall between them")
			for c in inst["link"]:
				check(Mounts.flat_wall(g, c), "%s: the link cell %s is a flat wall (full, no door, no shape)" % [name, str(c)])
			for c in inst["out_cells"]:
				check(g.get_tile(c) == "", "%s: the outside cell %s is open space" % [name, str(c)])
			for c in inst["cells"]:
				check(g.get_tile(c) == "floor", "%s: the inside cell %s is floor" % [name, str(c)])
			var osz := Mounts.turned(def["mount"]["outside"], inst["rot"])
			var out := Mounts.outward(inst["rot"])
			var across: int = osz.x if out.y != 0 else osz.y  # how wide the outside half is along the wall
			check(inst["link"].size() >= across and inst["link"].size() % across == 0, "%s: a run of flat wall %d wide, %d deep" % [name, across, inst["link"].size() / across])
			# the real placement rules, asked again with the part lifted out: they put it back exactly where it is
			comps.remove_uid(uid)
			var plan: Dictionary = comps.plan_mount(g, inst["id"], inst["out_anchor"], inst["rot"])
			eq(plan["why"], "", name + ": the placement rules accept it")
			eq([plan["anchor"], plan["link"]], [inst["anchor"], inst["link"]], name + ": and give the same inside half and link")
			if def["family"] == "weapon":
				eq(out, Vector2i.UP, name + ": guns face forward")
			else:
				check(out != Vector2i.UP, name + ": an engine never pushes backwards")
				rear += int(out == Vector2i.DOWN)
		check(rear >= 1, key + ": has an engine on its stern, facing aft")


func test_every_floor_cell_is_reachable_from_the_helm() -> void:
	for key in SHIPS:
		var ship := _ship(key)
		check(_helm_of(ship) >= 0, key + " has a helm")
		var lost := _unreached(ship)
		eq(lost.size(), 0, "%s: every floor, door and part cell is reachable from the helm by a 2x2 body (not reached: %s)" % [key, str(lost.slice(0, 8))])
		for d in ship.atmosphere.doors:
			eq(ship.grid.door_piece(d["cell"]).size(), 2, "%s: the door at %s is 2 cells wide" % [key, str(d["cell"])])


func test_the_ships_keep_their_parts_cargo_and_numbers() -> void:
	for key in SHIPS:
		var ship := _ship(key)
		eq(_parts(ship), SHIPS[key]["parts"], key + ": the same parts")
		eq(ship.inventory.to_dict(), SHIPS[key]["cargo"], key + ": the same cargo")
		var arena := Arena.new(1)
		arena.add_ship(ship)
		var co = arena.ships[0]
		var mass_was: float = SHIPS[key]["mass"]
		var hull_was: float = SHIPS[key]["hull"]
		check(absf(co.mass - mass_was) <= TOLERANCE * mass_was, "%s: mass %.0f is within 15%% of %.0f" % [key, co.mass, mass_was])
		check(absf(co.hull_max - hull_was) <= TOLERANCE * hull_was, "%s: hull integrity %.0f is within 15%% of %.0f" % [key, co.hull_max, hull_was])
		eq(co.flight.can_fly(ship.components, co.powered), "", key + " can fly")


func test_every_ship_is_powered_and_every_room_holds_air() -> void:
	for key in SHIPS:
		var ship := _ship(key)
		for uid in ship.components.instances:
			check(ship.power_state["powered"].get(uid, false), "%s: %s is powered" % [key, ship.components.instances[uid]["id"]])
		for n in ship.power_state["networks"]:
			check(n["supply"] + 0.0001 >= n["demand"], "%s: network %d supply %s covers demand %s" % [key, n["id"], str(n["supply"]), str(n["demand"])])
		check(ship.atmosphere.rooms.size() >= 2, "%s has rooms (%d)" % [key, ship.atmosphere.rooms.size()])
		for r in ship.atmosphere.rooms:
			check(r["sealed"], "%s: room %d is sealed" % [key, r["id"]])
