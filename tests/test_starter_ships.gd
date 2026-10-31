extends "res://tests/base_test.gd"
## Every starter ship of the hangar (docs/CONTENT.md 19): the three first ones (data/ships/starter_*.json) and the
## ships of the packs (the seven event starters and the two ships of each race of data/packs/starters_2/). Each
## loads, sits in the middle of the 63x63 grid on a big hull frame (docs/CONTENT.md 4c, "Start with very little")
## with only the essentials built (at most 10 parts) and most of the frame empty to build in, is wired, sealed,
## connected, can fly, has its gun and engines mounted through its walls, a shield in the hold and the rest of a
## working ship, and runs for minutes without overheating. The pack's ships also have their unlock, a crew of
## their race and a silhouette of their own.
## tests/tool_make_starters.gd and tests/tool_make_starters2.gd rebuild the files.

const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Flight = preload("res://scripts/sim/flight.gd")
const Rooms = preload("res://scripts/sim/rooms.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Hangar = preload("res://scripts/space/hangar.gd")
const Unlocks = preload("res://scripts/space/unlocks.gd")
const Content = preload("res://scripts/data/content.gd")
const Shapes = preload("res://scripts/ship/shapes.gd")
const HullOutline = preload("res://tests/hull_outline.gd")

const PATHS := {
	"Rustbucket": "res://data/ships/starter_rustbucket.json",
	"Courier": "res://data/ships/starter_courier.json",
	"Prism": "res://data/ships/starter_prism.json",
}
const PIRATE := "res://data/ships/pirate_raider.json"
const MAX_COVER := 3  ## tiles between a gun and open space: a wall, a plate, one more at most
const OLD_HULL := {"Rustbucket": 1122, "Courier": 864, "Prism": 624}  ## cells of the hull of the starters before the big frames (the bounding box plus 2)
const MIN_GROWTH := 1.6  ## the frame is about 1.6 to 2 times as big as that
const MAX_GROWTH := 2.0
const MAX_FILL := 0.85  ## the frame's cells over the cells of its box: a silhouette, not a rectangle (test_ship_silhouettes.gd)
const MIN_SHAPED := 4  ## slopes or curves on the built hull
const MIN_FRAME := 1000  ## cells of the hull frame: a lot of room (the first three have 1100 to 1850)
const MAX_FRAME := 2300
const MAX_PARTS := 10  ## placed components: the essentials only
const MIN_EMPTY := 0.5  ## at least this share of the frame is empty hull (no tile, no outside half of a mount)
const MIN_HULL_INTEGRITY := 150.0  ## every starter has real armour on its outer hull (arena.gd: 20 + 2 per plated cell)
const BOW_ROWS := 6  ## the Courier is an arrowhead: its titanium skin covers the nose, shoulders included (docs/CONTENT.md 4c)


## Every starter of the hangar, name -> design path (the first three, then the packs' ships).
func _all() -> Dictionary:
	var out := {}
	for e in Hangar.starters():
		out[e["name"]] = e["path"]
	return out


## The hangar entries of the packs' starters (not the first three), id -> entry.
func _packed() -> Dictionary:
	var out := {}
	for e in Hangar.starters():
		if e["pack"] == "starters_2" or e["pack"] == "endings_1":
			out[e["id"]] = e
	return out


func _ship(key: String) -> Ship:
	return Ship.from_design(_all()[key])


## The rooms that hold a part which lets air out or starts fires on purpose (a Vacuum Forge, Ma's Kettle, a Bloom Reactor, a Garden Bay):
## the air of such a room is not asked to stay (a fire eats it, and nobody is aboard to put it out).
func _leaky_rooms(ship: Ship) -> Dictionary:
	var out := {}
	for uid in ship.components.instances:
		var inst: Dictionary = ship.components.instances[uid]
		for a in ship.components.def(inst["id"]).get("abilities", []):
			for se in a.get("side_effects", []):
				if str(se.get("type", "")) in ["drain_o2", "fire_risk"]:
					out[ship.atmosphere.room_at(inst["anchor"])] = true
	return out


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


## The bounding box (lo, hi) of everything built: tiles, parts and cables, and with `mounts` the outside
## halves of the hull mounts too (they stick out of the hull into space).
func _bounds(ship: Ship, mounts := false) -> Array:
	var cells: Array = ship.grid.tiles.keys() + ship.cables.cells.keys()
	for uid in ship.components.instances:
		cells.append_array(ship.components.instances[uid]["cells"])
		if mounts:
			cells.append_array(ship.components.instances[uid]["out_cells"])
	var lo: Vector2i = cells[0]
	var hi: Vector2i = cells[0]
	for c in cells:
		lo = lo.min(c)
		hi = hi.max(c)
	return [lo, hi]


func test_each_starter_loads() -> void:
	for key in _all():
		var ship := _ship(key)
		check(ship != null, key + " loads")
		if ship == null:
			continue
		eq(ship.name, key, key + " keeps its name")
		eq(ship.grid.size, Vector2i(63, 63), key + " sits in a 63x63 grid")
		check(ship.grid.tiles.size() > 200 and ship.components.instances.size() >= 8, key + " is a built ship")
		var d = JSON.parse_string(FileAccess.get_file_as_string(_all()[key]))
		check(str(d.get("blurb", "")).length() > 30, key + " has a one-line character")
	check(Ship.from_design("res://data/ships/nothing_here.json") == null, "a missing design is null, not a crash")
	check(Ship.new_starter().grid.tiles.is_empty(), "the empty starter hull is unchanged")


func test_the_hull_is_a_big_frame_in_the_middle_that_holds_everything_built() -> void:  # the box of the hull, parts, cables and the outside halves of the mounts
	for key in _all():
		var ship := _ship(key)
		var b := _bounds(ship, true)
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := Vector2i(-(1 << 20), -(1 << 20))
		for c in ship.grid.hull:
			lo = lo.min(c)
			hi = hi.max(c)
		if OLD_HULL.has(key):  # the first three have a frame that holds the whole box of the core; the packs' ships only need every built cell on it (below)
			check(ship.grid.hull.has(b[0]) and ship.grid.hull.has(b[1]), key + ": the frame holds the built ship, outside halves of the mounts included")
		var built: Array = ship.grid.tiles.keys() + ship.cables.cells.keys()
		for uid in ship.components.instances:
			built.append_array(ship.components.instances[uid]["cells"])
			built.append_array(ship.components.instances[uid]["out_cells"])
		check(built.all(func(c): return ship.grid.hull.has(c)), key + ": every tile, cable and part is on the frame")
		var centre := Vector2(lo + hi + Vector2i.ONE) / 2.0
		check((centre - Vector2(31.5, 31.5)).length() <= 1.0, "%s: the frame is centred in the grid (%s)" % [key, str(centre)])
		var box := (hi - lo + Vector2i.ONE)
		check(ship.grid.hull.size() < 0.9 * box.x * box.y, "%s: the frame is a silhouette, not a rectangle (%d of %d cells)" % [key, ship.grid.hull.size(), box.x * box.y])
		if OLD_HULL.has(key):
			var growth := float(ship.grid.hull.size()) / float(OLD_HULL[key])
			check(growth >= MIN_GROWTH and growth <= MAX_GROWTH, "%s: the frame is %.2fx today's old hull (%d cells), 1.6 to 2 wanted" % [key, growth, ship.grid.hull.size()])
		check(ship.grid.hull.size() >= MIN_FRAME and ship.grid.hull.size() <= MAX_FRAME, "%s: a frame of %d cells (%d to %d wanted)" % [key, ship.grid.hull.size(), MIN_FRAME, MAX_FRAME])


func test_each_starter_has_at_most_ten_parts_and_at_least_half_of_its_frame_empty() -> void:
	for key in _all():
		var ship := _ship(key)
		var empty := 0
		for c in ship.grid.hull:
			empty += int(ship.grid.get_tile(c) == "" and ship.components.at_out(c) < 0)
		var share := float(empty) / float(ship.grid.hull.size())
		check(share >= MIN_EMPTY, "%s: %.0f%% of the frame is empty hull (%d of %d cells), at least 50%% wanted" % [key, 100.0 * share, empty, ship.grid.hull.size()])
		check(ship.components.instances.size() <= MAX_PARTS, "%s: %d placed parts, at most %d" % [key, ship.components.instances.size(), MAX_PARTS])


func test_each_starter_has_real_armour_on_its_outer_hull() -> void:
	for key in _all():
		var a := Arena.new(1)
		a.add_ship(_ship(key))
		check(a.ships[0].hull_max >= MIN_HULL_INTEGRITY, "%s: hull integrity %.0f, at least %.0f wanted" % [key, a.ships[0].hull_max, MIN_HULL_INTEGRITY])


func test_every_component_is_powered_and_supply_covers_demand() -> void:
	for key in _all():
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
	for key in _all():
		var ship := _ship(key)
		eq(Flight.new().can_fly(ship.components, ship.power_state["powered"]), "", key + " can fly")
		check(not _family(ship, "helm").is_empty() and not _family(ship, "engine").is_empty(), key + " has a helm and engines")


func test_rooms_are_sealed_doors_are_two_wide_and_everything_is_connected() -> void:
	for key in _all():
		var ship := _ship(key)
		var atmo = ship.atmosphere
		check(atmo.rooms.size() >= 4, "%s has rooms (%d)" % [key, atmo.rooms.size()])
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
	for key in _all():
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


func test_each_has_a_gun_the_essentials_and_a_shield_in_the_hold() -> void:
	for key in _all():
		var ship := _ship(key)
		check(_family(ship, "weapon").size() >= 1, key + " has a gun")
		for family in ["reactor", "engine", "oxygen", "helm", "fabricator", "bed"]:
			check(not _family(ship, family).is_empty(), "%s has a %s" % [key, family])
		check(_family(ship, "bed").size() >= 2, key + " has crew beds")
		check(_family(ship, "shield").is_empty(), key + ": the shield is not built yet")
		var shields := 0
		for id in ship.inventory.counts:
			if ship.components.has(id) and ship.components.def(id).get("family", "") == "shield":
				shields += ship.inventory.count(id)
		eq(shields, 1, key + ": one shield waits in the hold")
		var fab: int = _family(ship, "fabricator")[0]
		var room: int = ship.atmosphere.room_at(ship.components.instances[fab]["anchor"])
		var mates := 0
		for uid in ship.components.instances:
			if uid != fab and ship.atmosphere.room_at(ship.components.instances[uid]["anchor"]) == room:
				mates += 1
		check(room >= 0 and ship.atmosphere.rooms[room]["sealed"], key + ": the fabricator is in a sealed room")
		eq(mates, 0, key + ": the workshop holds the fabricator alone")


func test_every_gun_and_engine_is_mounted_through_the_wall() -> void:
	for key in _all():
		var ship := _ship(key)
		for fam in ["weapon", "engine"]:
			for uid in _family(ship, fam):
				var inst: Dictionary = ship.components.instances[uid]
				var name := "%s: %s at %s" % [key, inst["id"], str(inst["anchor"])]
				check(ship.components.has_outside(uid), name + " has an outside half")
				check(ship.components.link_intact(ship.grid, uid), name + ": its wall is whole")
				for c in inst["out_cells"]:
					check(ship.grid.get_tile(c) == "" and ship.components.at(c) < 0, "%s: the barrel at %s is in space" % [name, str(c)])
				for c in inst["link"]:
					check(ship.grid.tile_flag(ship.grid.get_tile(c), "solid"), "%s: %s is a wall" % [name, str(c)])
				for c in inst["cells"]:
					check(ship.grid.get_tile(c) == "floor", "%s: the breech at %s is on the floor" % [name, str(c)])
				var layers := Mounts.depth_of(ship.components.def(inst["id"]), inst["anchor"], inst["rot"], inst["out_anchor"])
				check(layers >= 1 and layers <= MAX_COVER, "%s: %d layers of wall between the halves" % [name, layers])
				check(inst["out_hp"] == ship.components.outside_hp_max(inst["id"]), name + ": the outside half is whole")


func test_nose_guns_point_forward_and_rear_engines_push_forward() -> void:
	for key in _all():
		var ship := _ship(key)
		var arena := Arena.new(1)
		arena.add_ship(ship)
		var co = arena.ships[0]
		check(co.thrusts["fwd"] > 0.0, "%s: the engines push forward (%s)" % [key, str(co.thrusts)])
		for uid in co.mounts:
			eq(co.mounts[uid]["dir"], Vector2.UP, "%s: %s is on the bow" % [key, co.mounts[uid]["id"]])


func test_rustbucket_is_the_scrap_ship() -> void:
	var ship := _ship("Rustbucket")
	var b := _bounds(ship)
	eq(b[1] - b[0] + Vector2i.ONE, Vector2i(20, 21), "20x21 cells built")
	eq([_count(ship, "reactor_mk2"), _count(ship, "radiator")], [1, 1], "one standard Reactor Mk2 (scrap parts draw 20% more) and a radiator (the Kickjets run hot)")
	eq([_count(ship, "engine_scrap_mk1"), _count(ship, "oxygen_scrap_mk1"), _count(ship, "rattle_burst_scrap")], [2, 1, 1], "2 Kickjets, Wheezer O2, Rattle Burst")
	eq([ship.inventory.count("shield_scrap_mk1"), ship.inventory.count("net_mouth_scrap")], [1, 1], "the Bubble Rig and a Net Mouth in the hold")
	check(_tiles(ship, "scrap_plate") > 100, "a scrap-plate outer layer all round")
	check(ship.inventory.count("scrap") >= 400, "a lot of scrap in the hold")
	eq(ship.inventory.count("credits"), 300, "300 credits")


func test_courier_is_the_standard_ship() -> void:
	var ship := _ship("Courier")
	var b := _bounds(ship)
	eq(b[1] - b[0] + Vector2i.ONE, Vector2i(12, 21), "12x21 cells built: the fuselage of the arrowhead")
	eq([_count(ship, "engine_mk2"), _count(ship, "pulse_mk1"), _count(ship, "reactor_mk2")], [2, 1, 1], "2 Engine Mk2 (the fast ship), Pulse Mk1, one Reactor Mk2")
	eq([ship.inventory.count("shield_mk1"), ship.inventory.count("afterburner")], [1, 1], "a Shield Mk1 and an Afterburner in the hold")
	check(_tiles(ship, "titanium_alloy") >= 60, "a titanium skin all round")
	var nose := 0
	for c in ship.grid.tiles:
		nose += int(ship.grid.tiles[c] == "titanium_alloy" and c.y <= b[0].y + BOW_ROWS)
	check(nose >= 20, "and the pointed bow is titanium over titanium (%d cells in its first %d rows)" % [nose, BOW_ROWS + 1])
	eq(ship.inventory.count("credits"), 500, "500 credits")


func test_courier_has_room_for_a_strafe_pair_on_its_flanks() -> void:
	var ship := _ship("Courier")
	var arena := Arena.new(1)
	arena.add_ship(ship)
	var t: Dictionary = arena.ships[0].thrusts
	check(t["fwd"] > 0.0 and t["left"] == 0.0 and t["right"] == 0.0, "it starts with rear engines only: %s" % str(t))
	var found := {}
	for rot in [1, 3]:  # nozzle to the right (on the right wall), nozzle to the left (on the left wall)
		for y in ship.grid.size.y:
			for x in ship.grid.size.x:
				if not found.has(rot) and ship.components.can_place_mount(ship.grid, "engine_mk1", Vector2i(x, y), rot) == "":
					found[rot] = Vector2i(x, y)
	eq(found.keys().size(), 2, "an Engine Mk1 fits on each side wall: %s" % str(found))
	for uid in _family(ship, "weapon"):
		var inst: Dictionary = ship.components.instances[uid]
		eq(Mounts.depth_of(ship.components.def(inst["id"]), inst["anchor"], inst["rot"], inst["out_anchor"]), 2, "%s: its link is the whole 2-cell bow" % inst["id"])


func test_prism_is_the_neon_ship() -> void:
	var ship := _ship("Prism")
	var b := _bounds(ship)
	eq(b[1] - b[0] + Vector2i.ONE, Vector2i(12, 22), "12x22 cells built: the spine of the crystal")
	eq([_count(ship, "reactor_neon_mk1"), _count(ship, "engine_neon_mk1"), _count(ship, "heat_lance_neon")], [1, 1, 1], "Prism Core, Ion Drive, Heat Lance")
	eq([ship.inventory.count("shield_neon_mk1"), ship.inventory.count("afterburner")], [1, 1], "the Neon Lattice Shield and an Afterburner in the hold")
	var core: int = _family(ship, "reactor")[0]
	var hot: int = ship.atmosphere.room_at(ship.components.instances[core]["anchor"])
	var radiators := 0
	for uid in _family(ship, "radiator"):
		if ship.atmosphere.room_at(ship.components.instances[uid]["anchor"]) == hot:
			radiators += 1
	check(radiators >= 2, "2 radiators in the Prism Core's room")
	eq(ship.components.def("shield_neon_mk1")["stats"]["sectors"], 4, "a 4-sector shield")
	check(_tiles(ship, "reflective_coating") >= 60 and _tiles(ship, "wall") > 0, "a reflective coating all round over steel")
	eq(ship.inventory.count("credits"), 400, "400 credits")


func test_cargo_is_known_ids_and_credits() -> void:
	var known := {"credits": true}
	for kind in ["materials", "items"]:
		for e in Content.list(kind):  # the core files and the packs'
			known[e["id"]] = true
	for key in _all():
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
	for key in _all():
		var a := Arena.new(1)
		a.add_ship(_ship(key))
		var co = a.ships[0]
		hull[key] = co.hull_max
		accel[key] = co.thrust * co.flight.thrust_to_accel / co.mass
	check(hull["Rustbucket"] > hull["Courier"] and hull["Courier"] > hull["Prism"], "armour: Rustbucket > Courier > Prism: " + str(hull))
	check(accel["Rustbucket"] < accel["Courier"] and accel["Rustbucket"] < accel["Prism"], "the Rustbucket is the slow one: " + str(accel))
	var stats: Dictionary = _ship("Prism").components.def("shield_neon_mk1")["stats"]
	eq([int(stats["layers"]), int(stats["sectors"])], [2, 4], "the Prism's shield, in its hold: 2 layers, 4 sectors")


func test_every_weapon_is_ready_against_an_enemy_ahead() -> void:
	for key in _all():
		var s := Session.new()
		s.start(_ship(key), Session.load_ship(PIRATE), 3)
		var aim: Vector2 = s.arena.ships[Session.ENEMY].flight.pos
		var list := s.weapons()
		check(list.size() >= 1, key + " has a weapon in the arena")
		for w in list:
			eq(s.slot_state(w["uid"], aim)["status"], "ready", "%s: %s is ready, in arc, powered" % [key, w["name"]])
		eq(s.fire_group(1, aim) + s.fire_group(2, aim), list.size(), key + ": every weapon fires on the first volley")


func test_the_starters_run_for_five_minutes() -> void:
	for key in _all():
		var sim := ShipSim.new()
		eq(sim.choose_ship(_all()[key]), "", key + " is chosen")
		var ship: Ship = sim.player_ship()
		var overheated := 0
		for i in 3000:
			sim.step(0.1)
			if i % 10 == 0:
				for uid in ship.components.instances:
					if ship.components.instances[uid]["status"] == "overheated":
						overheated += 1
		eq(overheated, 0, key + ": nothing overheats while it idles")
		var leaky := _leaky_rooms(ship)
		for i in ship.atmosphere.rooms.size():
			var burning: bool = ship.fires.keys().any(func(c): return ship.atmosphere.room_at(c) == i)  # a scrap part set it alight, and nobody is aboard to put it out
			check(burning or leaky.has(i) or ship.atmosphere.pressure_of(i) >= 0.99, "%s: room %d keeps its air" % [key, i])
		sim.free()


# --- the packs' starters: the event starters and the two ships of each race -----------------------------------------

const EVENT_STARTERS := ["halcyon_tender", "kettle_tug", "concord_frigate", "door_prize", "lumen_skiff", "hollow_touched", "patience_sister"]
const RACES := ["human", "basalt", "emberkin", "fenn", "kett", "mire", "sporeling", "gauntling", "prismatic", "grundl"]


## Every effects object of the events, with the id of its event.
func _effects_of_events() -> Array:
	var out := []
	for ev in Content.events():
		for ch in ev.get("choices", []):
			for o in ch.get("outcomes", []):
				if o.get("effects") is Dictionary:
					out.append([ev["id"], o["effects"]])
	return out


func test_the_hangar_holds_the_seven_event_starters_and_twenty_race_starters() -> void:
	var packed := _packed()
	for id in EVENT_STARTERS:
		check(packed.has(id), id + " is in the hangar")
	var by_group := {}
	for e in Hangar.starters():
		by_group[e["group"]] = by_group.get(e["group"], []) + [e["layout"]]
	for race in RACES:
		var group: String = race.capitalize()
		eq(by_group.get(group, []), ["A", "B"], group + ": a layout A and a layout B")
	eq(Hangar.validate(), [], "the hangar is sound (every ship has its group, layout and a known unlock)")
	for id in Content.ids("unlocks"):
		check(not Content.entry("unlocks", id).has("pending"), id + ": no unlock is pending any more")


func test_each_pack_starter_has_its_unlock_and_sits_where_the_unlock_says() -> void:
	var packed := _packed()
	for id in packed:
		var e: Dictionary = packed[id]
		var u := Unlocks.for_ship(id)
		check(u != "", id + " has a starter_ship unlock")
		if u == "":
			continue
		var entry := Unlocks.entry(u)
		eq(e["unlock"], u, id + ": the hangar entry carries it")
		eq(str(entry["payload"].get("layout", "")), e["layout"], id + ": its layout is the unlock's")
		eq(str(entry["payload"].get("group", "")).to_lower(), e["group"].to_lower(), id + ": its group is the unlock's")
		check(str(entry.get("how", "")).length() > 12, id + ": the unlock says how to earn it")
		check(e["crew"].size() >= 2, id + ": it has a crew")


func test_every_pack_starter_can_be_earned_in_an_event() -> void:
	var effects := _effects_of_events()
	for id in _packed():
		var u := Unlocks.for_ship(id)
		var found := effects.filter(func(x): return str(x[1].get("unlock", "")) == u or (x[1].get("unlock") is Array and x[1]["unlock"].has(u)))
		check(not found.is_empty(), "%s: an event grants %s" % [id, u])
	for race in RACES:  # layout A is reached in a homeland's dock, layout B won in its quest (the outcomes that win the tech)
		var group: String = race.capitalize()
		for l in ["A", "B"]:
			for e in Hangar.starters():
				if e["group"] != group or e["layout"] != l:
					continue
				var hits := effects.filter(func(x): return str(x[1].get("unlock", "")) == e["unlock"])
				check(hits.all(func(x): return str(x[0]).length() > 0), e["id"] + ": its events are named")
				if l == "B":
					check(hits.all(func(x): return str(x[1].get("flag", "")).begins_with("tech_")), e["id"] + ": layout B is earned only where the race's tech is won")
				check(not hits.is_empty() and hits.all(func(x): return x[0] == hits[0][0]), e["id"] + ": and in one event only")


func test_each_race_starter_is_crewed_by_its_race_and_fits_its_tech() -> void:
	for race in RACES:
		var group: String = race.capitalize()
		var racial := Content.ids("components").filter(func(id): return id.begins_with(race + "_"))
		for e in Hangar.starters():
			if e["group"] != group:
				continue
			var crew: Array = e["crew"]
			eq(crew[0], {"name": "Soldier", "species": "human"}, e["id"] + ": the Soldier first")
			var kin := crew.filter(func(m): return m["species"] == race)
			check(kin.size() >= 2 or (race == "human" and crew.size() >= 3), "%s: at least two of the race aboard (%s)" % [e["id"], str(crew)])
			if race != "human":
				check(crew.slice(1).all(func(m): return m["species"] == race), e["id"] + ": a crew of that race (and the Soldier)")
			var ship := Ship.from_design(e["path"])
			var mine := 0
			var parts := {}
			for uid in ship.components.instances:
				parts[ship.components.instances[uid]["id"]] = true
			for id in ship.inventory.counts:
				if ship.components.has(id):
					parts[id] = true
			for id in parts:
				mine += int(racial.has(id))
			if not racial.is_empty():
				check(mine >= 1, "%s: fits a part of the %s tech pack, built or in the hold (%s)" % [e["id"], race, str(parts.keys())])


func test_the_pack_starters_are_no_rectangles_and_mount_on_flat_walls() -> void:
	for id in _packed():
		var e: Dictionary = _packed()[id]
		var ship := Ship.from_design(e["path"])
		var g = ship.grid
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := Vector2i(-(1 << 20), -(1 << 20))
		for c in g.hull:
			lo = lo.min(c)
			hi = hi.max(c)
		var box := float((hi.x - lo.x + 1) * (hi.y - lo.y + 1))
		check(float(g.hull.size()) < MAX_FILL * box, "%s: the frame fills %.0f%% of its box (under %.0f%%)" % [id, 100.0 * g.hull.size() / box, 100.0 * MAX_FILL])
		check(g.shapes.size() >= MIN_SHAPED, "%s: %d shaped cells (at least %d)" % [id, g.shapes.size(), MIN_SHAPED])
		for c in g.shapes:
			check(Shapes.has_shape(str(g.shapes[c]["shape"])) and g.tile_flag(g.get_tile(c), "solid"), "%s: the shaped cell %s is a wall of a known shape" % [id, str(c)])
		var comps = ship.components
		for uid in comps.instances:
			var inst: Dictionary = comps.instances[uid]
			if not Mounts.is_mount(comps.def(inst["id"])):
				continue
			for c in inst["link"]:
				check(Mounts.flat_wall(g, c), "%s: %s: the link cell %s is a flat wall" % [id, inst["id"], str(c)])
			for c in inst["out_cells"]:
				check(g.get_tile(c) == "" and g.hull.has(c), "%s: %s: the outside cell %s is open space on the frame" % [id, inst["id"], str(c)])
		var lost := HullOutline.pockets(ship)
		eq(lost.size(), 0, "%s: every floor cell is reachable from the helm by a 2x2 body (%s)" % [id, str(lost.slice(0, 6))])


## A signature of a ship's look: the cells of its frame and of its walls, from the top left of the frame.
func _look(ship: Ship) -> Array:
	var lo := Vector2i(1 << 20, 1 << 20)
	for c in ship.grid.hull:
		lo = lo.min(c)
	var frame := ship.grid.hull.keys().map(func(c): return [c.x - lo.x, c.y - lo.y])
	var walls := ship.grid.tiles.keys().filter(func(c): return ship.grid.tile_flag(ship.grid.tiles[c], "solid")).map(func(c): return [c.x - lo.x, c.y - lo.y])
	frame.sort()
	walls.sort()
	return [hash(str(frame)), hash(str(walls))]


func test_every_starter_has_a_silhouette_of_its_own() -> void:
	var frames := {}
	var cores := {}
	for key in _all():
		var look := _look(_ship(key))
		check(not frames.has(look[0]), "%s: its frame is not the frame of %s" % [key, frames.get(look[0], "")])
		check(not cores.has(look[1]), "%s: its hull is not the hull of %s" % [key, cores.get(look[1], "")])
		frames[look[0]] = key
		cores[look[1]] = key
