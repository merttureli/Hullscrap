extends "res://tests/base_test.gd"
## The three starter ships (data/ships/starter_*.json): each loads, sits in the middle of the 63x63
## grid with a hull of its bounding box plus 2 cells, is wired, sealed, connected, can fly, has guns on
## the outer edge, a shield and the rest of a working ship, and runs for minutes without overheating.
## tests/tool_make_starters.gd rebuilds the files.

const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Flight = preload("res://scripts/sim/flight.gd")
const Rooms = preload("res://scripts/sim/rooms.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Arena = preload("res://scripts/combat/arena.gd")

const PATHS := {
	"Rustbucket": "res://data/ships/starter_rustbucket.json",
	"Courier": "res://data/ships/starter_courier.json",
	"Prism": "res://data/ships/starter_prism.json",
}
const PIRATE := "res://data/ships/pirate_raider.json"
const MAX_COVER := 3  ## tiles between a gun and open space: a wall, a plate, one more at most


func _ship(key: String) -> Ship:
	return Ship.from_design(PATHS[key])


func _count(ship: Ship, id: String) -> int:
	var n := 0
	for uid in ship.components.instances:
		if ship.components.instances[uid]["id"] == id:
			n += 1
	return n


func _family(ship: Ship, family: String) -> Array:
	var out := []
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		if ship.components.def(ship.components.instances[uid]["id"]).get("family", "") == family:
			out.append(uid)
	return out


func _tiles(ship: Ship, id: String) -> int:
	var n := 0
	for c in ship.grid.tiles:
		if ship.grid.tiles[c] == id:
			n += 1
	return n


## The bounding box (lo, hi) of everything built: tiles, parts and cables.
func _bounds(ship: Ship) -> Array:
	var cells: Array = ship.grid.tiles.keys() + ship.cables.cells.keys()
	for uid in ship.components.instances:
		cells.append_array(ship.components.instances[uid]["cells"])
	var lo: Vector2i = cells[0]
	var hi: Vector2i = cells[0]
	for c in cells:
		lo = lo.min(c)
		hi = hi.max(c)
	return [lo, hi]


func test_each_starter_loads() -> void:
	for key in PATHS:
		var ship := _ship(key)
		check(ship != null, key + " loads")
		if ship == null:
			continue
		eq(ship.name, key, key + " keeps its name")
		eq(ship.grid.size, Vector2i(63, 63), key + " sits in a 63x63 grid")
		check(ship.grid.tiles.size() > 200 and ship.components.instances.size() >= 10, key + " is a built ship")
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATHS[key]))
		check(str(d.get("blurb", "")).length() > 30, key + " has a one-line character")
	check(Ship.from_design("res://data/ships/nothing_here.json") == null, "a missing design is null, not a crash")
	check(Ship.new_starter().grid.tiles.is_empty(), "the empty starter hull is unchanged")


func test_the_hull_is_the_bounding_box_plus_two_cells_in_the_middle() -> void:
	for key in PATHS:
		var ship := _ship(key)
		var b := _bounds(ship)
		var lo: Vector2i = b[0] - Vector2i(2, 2)
		var hi: Vector2i = b[1] + Vector2i(2, 2)
		var want := {}
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				want[Vector2i(x, y)] = true
		check(ship.grid.hull == want, key + ": the hull is the bounding box grown by 2")
		var centre := Vector2(lo + hi + Vector2i.ONE) / 2.0
		check((centre - Vector2(31.5, 31.5)).length() <= 1.0, "%s: centred in the grid (%s)" % [key, str(centre)])


func test_every_component_is_powered_and_supply_covers_demand() -> void:
	for key in PATHS:
		var ship := _ship(key)
		var powered: Dictionary = ship.power_state["powered"]
		for uid in ship.components.instances:
			check(powered.get(uid, false), "%s: %s (uid %d) is powered" % [key, ship.components.instances[uid]["id"], uid])
		var supply := 0.0
		var demand := 0.0
		for n in ship.power_state["networks"]:
			supply += n["supply"]
			demand += n["demand"]
			check(n["supply"] + 0.0001 >= n["demand"], "%s: network %d supply %s covers demand %s" % [key, n["id"], str(n["supply"]), str(n["demand"])])
		check(supply + 0.0001 >= demand and demand > 0.0, "%s: supply %s >= demand %s" % [key, str(supply), str(demand)])


func test_the_starters_can_fly() -> void:
	for key in PATHS:
		var ship := _ship(key)
		eq(Flight.new().can_fly(ship.components, ship.power_state["powered"]), "", key + " can fly")
		check(not _family(ship, "helm").is_empty() and not _family(ship, "engine").is_empty(), key + " has a helm and engines")


func test_rooms_are_sealed_doors_are_two_wide_and_everything_is_connected() -> void:
	for key in PATHS:
		var ship := _ship(key)
		var atmo = ship.atmosphere
		check(atmo.rooms.size() >= 6, "%s has rooms (%d)" % [key, atmo.rooms.size()])
		for r in atmo.rooms:
			check(r["sealed"], "%s: room %d is sealed" % [key, r["id"]])
		for i in atmo.rooms.size():
			check(atmo.pressure_of(i) >= 0.999, "%s: room %d starts full of air" % [key, i])
		var seen := {0: true}
		var open := [0]
		while not open.is_empty():
			var r: int = open.pop_back()
			for d in atmo.doors:
				var other: int = d["b"] if d["a"] == r else (d["a"] if d["b"] == r else -9)
				if other >= 0 and not seen.has(other):
					seen[other] = true
					open.append(other)
		eq(seen.size(), atmo.rooms.size(), key + ": every room can be reached through doors")
		for d in atmo.doors:
			check(d["a"] >= 0 and d["b"] >= 0 and d["a"] != d["b"], "%s: the door cell %s joins two rooms" % [key, str(d["cell"])])
			eq(ship.grid.door_piece(d["cell"]).size(), 2, "%s: the door at %s is a 2-cell piece" % [key, str(d["cell"])])


func test_the_crew_can_walk_to_every_room() -> void:
	for key in PATHS:
		var ship := _ship(key)
		var grid = ship.grid
		var spawn := Pathfinder.nearest_walkable(grid, Vector2(grid.size) / 2.0)
		check(spawn != Pathfinder.NO_CELL, key + ": the soldier has a place to start")
		check(ship.atmosphere.room_at(spawn + Vector2i.ONE) >= 0, key + ": and it is inside a room")
		var reached := {}
		for r in ship.atmosphere.rooms:
			var spot := Pathfinder.NO_CELL
			for c in r["cells"]:
				if Pathfinder.body_ok(grid, c) and ship.atmosphere.room_at(c) == r["id"]:
					spot = c
					break
			check(spot != Pathfinder.NO_CELL, "%s: room %d has space for a 2x2 body" % [key, r["id"]])
			if spot != Pathfinder.NO_CELL:
				check(not Pathfinder.find_path(grid, spawn, spot).is_empty(), "%s: a path from the start to room %d" % [key, r["id"]])
				reached[r["id"]] = true
		eq(reached.size(), ship.atmosphere.rooms.size(), key + ": every room is reachable on foot")


func test_each_has_guns_a_shield_and_the_rest_of_a_ship() -> void:
	for key in PATHS:
		var ship := _ship(key)
		var powered: Dictionary = ship.power_state["powered"]
		check(_family(ship, "weapon").size() >= 2, key + " has at least 2 weapons")
		var shields := _family(ship, "shield")
		check(shields.size() >= 1 and powered[shields[0]], key + " has a powered shield")
		for family in ["reactor", "engine", "oxygen", "helm", "fabricator", "bed", "radiator"]:
			check(not _family(ship, family).is_empty(), "%s has a %s" % [key, family])
		check(_family(ship, "bed").size() >= 2, key + " has crew beds")
		var fab: int = _family(ship, "fabricator")[0]
		var room: int = ship.atmosphere.room_at(ship.components.instances[fab]["anchor"])
		var mates := 0
		for uid in ship.components.instances:
			if uid != fab and ship.atmosphere.room_at(ship.components.instances[uid]["anchor"]) == room:
				mates += 1
		check(room >= 0 and ship.atmosphere.rooms[room]["sealed"], key + ": the fabricator is in a sealed room")
		eq(mates, 0, key + ": the workshop holds the fabricator alone")


func test_guns_sit_on_the_outer_edge_facing_out() -> void:
	for key in PATHS:
		var ship := _ship(key)
		var b := _bounds(ship)
		var pivot := Vector2(b[0] + b[1] + Vector2i.ONE) / 2.0
		for uid in _family(ship, "weapon"):
			var cells: Array = ship.components.instances[uid]["cells"]
			var sum := Vector2.ZERO
			for c in cells:
				sum += Vector2(c) + Vector2(0.5, 0.5)
			var off: Vector2 = sum / cells.size() - pivot  # the way the gun points
			var dir := Vector2i(signi(roundi(off.x)), 0) if absf(off.x) > absf(off.y) else Vector2i(0, signi(roundi(off.y)))
			var worst := 0
			for c in cells:
				if cells.has(c + dir):
					continue  # not on the outer face of the gun
				var n: Vector2i = c + dir
				var cover := 0
				while ship.grid.tiles.has(n) or ship.components.at(n) >= 0:
					check(ship.components.at(n) < 0, "%s: another part is in front of the gun at %s" % [key, str(c)])
					cover += 1
					n += dir
					if cover > 8:
						break
				worst = maxi(worst, cover)
			check(worst >= 1 and worst <= MAX_COVER, "%s: the gun at %s has %d tiles in front of it" % [key, str(cells[0]), worst])


func test_rustbucket_is_the_scrap_ship() -> void:
	var ship := _ship("Rustbucket")
	var b := _bounds(ship)
	eq(b[1] - b[0] + Vector2i.ONE, Vector2i(30, 24), "30x24 cells in use")
	eq([_count(ship, "reactor_scrap_mk1") >= 1, _count(ship, "reactor_mk2") + _count(ship, "reactor_mk1") >= 1], [true, true], "a Rustbucket Reactor and a standard one")
	eq([_count(ship, "engine_scrap_mk1"), _count(ship, "oxygen_scrap_mk1"), _count(ship, "shield_scrap_mk1")], [2, 1, 1], "2 Kickjets, Wheezer O2, Bubble Rig")
	eq([_count(ship, "rattle_burst_scrap"), _count(ship, "shrapnel_cannon_scrap"), _count(ship, "bolt_thrower_scrap")], [1, 1, 1], "Rattle Burst, Shrapnel Cannon, Bolt Thrower")
	check(_tiles(ship, "scrap_plate") > 80, "a scrap-plate outer layer all round")
	check(ship.inventory.count("scrap") >= 500, "a lot of scrap in the hold (and the Bolt Thrower eats it)")
	eq(ship.inventory.count("credits"), 300, "300 credits")


func test_courier_is_the_standard_ship() -> void:
	var ship := _ship("Courier")
	var b := _bounds(ship)
	check(b[1].x - b[0].x + 1 == 24 and b[1].y - b[0].y + 1 <= 19, "about 24x18 cells in use")
	eq([_count(ship, "engine_mk1"), _count(ship, "shield_mk1"), _count(ship, "laser_mk1"), _count(ship, "pulse_mk1")], [2, 1, 2, 1], "2 Engine Mk1, Shield Mk1, 2 Laser Mk1, Pulse Mk1")
	check(_count(ship, "reactor_mk1") >= 1 and _count(ship, "radiator") >= 1, "Reactor Mk1 and a radiator")
	check(_tiles(ship, "titanium_alloy") >= 20, "a titanium front layer")
	for c in ship.grid.tiles:
		if ship.grid.tiles[c] == "titanium_alloy":
			eq(c.y, b[0].y, "titanium only on the front row")
			break
	eq(ship.inventory.count("credits"), 500, "500 credits")


func test_prism_is_the_neon_ship() -> void:
	var ship := _ship("Prism")
	var b := _bounds(ship)
	eq(b[1] - b[0] + Vector2i.ONE, Vector2i(22, 18), "22x18 cells in use")
	eq([_count(ship, "reactor_neon_mk1"), _count(ship, "engine_neon_mk1"), _count(ship, "shield_neon_mk1")], [1, 1, 1], "Prism Core, Ion Drive, Neon Lattice Shield")
	eq([_count(ship, "heat_lance_neon"), _count(ship, "siren_ion_neon")], [1, 1], "Heat Lance and Siren Ion")
	var core: int = _family(ship, "reactor")[0]
	var hot: int = ship.atmosphere.room_at(ship.components.instances[core]["anchor"])
	var radiators := 0
	for uid in _family(ship, "radiator"):
		if ship.atmosphere.room_at(ship.components.instances[uid]["anchor"]) == hot:
			radiators += 1
	check(radiators >= 2, "2 radiators in the Prism Core's room")
	eq(ship.components.def("shield_neon_mk1")["stats"]["sectors"], 4, "a 4-sector shield")
	check(_tiles(ship, "reflective_coating") >= 8 and _tiles(ship, "wall") > 0, "a reflective coating over steel")
	check(_tiles(ship, "reflective_coating") <= 20, "little armour: a thin coat on the nose only")
	eq(ship.inventory.count("credits"), 400, "400 credits")


func test_cargo_is_known_ids_and_credits() -> void:
	var known := {"credits": true}
	for f in ["materials", "items"]:
		for e in JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % f))[f]:
			known[e["id"]] = true
	for key in PATHS:
		var ship := _ship(key)
		for id in ship.inventory.counts:
			check(known.has(id) or ship.components.has(id), "%s: cargo %s is a material, an item, a system or credits" % [key, id])
		check(ship.inventory.count("copper") >= 40, key + " has copper for cables and doors")
		check(ship.inventory.count("scrap") >= 100, key + " has scrap to build with")
		var spares := 0
		for id in ship.inventory.counts:
			if ship.components.has(id):
				spares += ship.inventory.count(id)
		check(spares >= 2, key + " carries a few spare parts")


func test_starters_are_ordered_by_hull_and_speed() -> void:
	var hull := {}
	var accel := {}
	for key in PATHS:
		var a := Arena.new(1)
		a.add_ship(_ship(key))
		var co = a.ships[0]
		hull[key] = co.hull_max
		accel[key] = co.thrust * co.flight.thrust_to_accel / co.mass
	check(hull["Rustbucket"] > hull["Courier"] and hull["Courier"] > hull["Prism"], "armour: Rustbucket > Courier > Prism: " + str(hull))
	check(accel["Rustbucket"] < accel["Courier"] and accel["Rustbucket"] < accel["Prism"], "the Rustbucket is the slow one: " + str(accel))
	var prism := Arena.new(1)
	prism.add_ship(_ship("Prism"))
	eq([prism.ships[0].layers_cap, prism.ships[0].sectors], [2, 4], "the Prism's shield: 2 layers, 4 sectors")


func test_every_weapon_is_ready_against_an_enemy_ahead() -> void:
	for key in PATHS:
		var s := Session.new()
		s.start(_ship(key), Session.load_ship(PIRATE), 3)
		var aim: Vector2 = s.arena.ships[Session.ENEMY].flight.pos
		var list := s.weapons()
		check(list.size() >= 2, key + " has weapons in the arena")
		for w in list:
			eq(s.slot_state(w["uid"], aim)["status"], "ready", "%s: %s is ready, in arc, powered" % [key, w["name"]])
		eq(s.fire_group(1, aim) + s.fire_group(2, aim), list.size(), key + ": every weapon fires on the first volley")


func test_the_starters_run_for_five_minutes() -> void:
	for key in PATHS:
		var sim := ShipSim.new()
		eq(sim.choose_ship(PATHS[key]), "", key + " is chosen")
		var ship: Ship = sim.player_ship()
		var overheated := 0
		for i in 3000:
			sim.step(0.1)
			if i % 10 == 0:
				for uid in ship.components.instances:
					if ship.components.instances[uid]["status"] == "overheated":
						overheated += 1
		eq(overheated, 0, key + ": nothing overheats while it idles")
		for i in ship.atmosphere.rooms.size():
			check(ship.atmosphere.pressure_of(i) >= 0.99, "%s: room %d keeps its air" % [key, i])
		sim.free()
