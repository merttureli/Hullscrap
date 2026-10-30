extends "res://tests/base_test.gd"

const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const CrewView = preload("res://scripts/crew/crew_view.gd")
const GridTests = preload("res://tests/test_pathfinder.gd")
const REACTOR := Vector2i(4, 4)  # 2x2: (4,4) (5,4) (4,5) (5,5)
const GEN := Vector2i(7, 5)  # 1x2: (7,5) (7,6)


## A 15x15 ship with a sealed room (walls round (3,3)-(9,8), floor inside: 20 cells) and a few parts in the cargo.
func _room_ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(15, 15), defs)
	g.fill_circle_hull(7.0)
	var ship := Ship.new("Test", g)
	ship.inventory.load_dict({"scrap": 200, "copper": 20, "reactor_mk1": 1, "oxygen_gen": 1, "helm": 1})
	BuildSession.new(ship).apply(BuildSession.room_changes(Vector2i(3, 3), Vector2i(9, 8), "wall", "floor"))
	ship.refresh()
	return ship


func _place(id: String, anchor: Vector2i) -> Dictionary:
	return {"layer": "component", "id": id, "anchor": anchor, "rot": 0}


func _cables(cells: Array) -> Array:
	var out := []
	for c in cells:
		out.append({"layer": "cable", "cell": c})
	return out


## The room ship with a reactor and an oxygen generator joined by a cable: the generator is powered.
func _powered_room() -> Ship:
	var ship := _room_ship()
	var s := BuildSession.new(ship)
	s.apply([_place("reactor_mk1", REACTOR), _place("oxygen_gen", GEN)])
	s.apply(_cables([Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)]))
	ship.refresh()
	return ship


func _sim_of(ships: Array) -> ShipSim:
	var sim := ShipSim.new()
	sim.ships = ships
	return sim


func _run(sim: ShipSim, seconds: float) -> void:
	for i in roundi(seconds * 10.0):
		sim.step(0.1)


func _room_pressure(ship: Ship) -> float:
	return ship.atmosphere.pressure_at(Vector2i(5, 6))


# --- The ship ---

func test_starter_ship_has_hull_and_cargo() -> void:
	var s := Ship.new_starter()
	check(s.grid.hull.size() > 300, "a circular hull")
	eq(s.grid.tiles.size(), 0, "nothing built yet")
	check(s.inventory.count("scrap") > 0 and s.inventory.count("copper") > 0, "starts with materials")
	for id in ["reactor_mk1", "oxygen_gen", "helm", "fabricator"]:
		check(s.inventory.count(id) > 0, "starts with a " + id)
	for id in s.inventory.counts:
		check(id in ["scrap", "copper"] or s.components.has(id), "%s is a material or a known system" % id)
	eq(s.world_pos, Vector2.ZERO, "world position starts at 0")
	eq(s.rot_quarters, 0, "and rotation too")
	check(s.crew.is_empty(), "no crew yet")


func test_refresh_follows_structure_and_parts() -> void:
	var s := _room_ship()
	check(not s.refresh(), "clean after a refresh")
	s.mark_dirty()
	check(s.refresh(), "a structure change is rebuilt")
	check(not s.refresh(), "once")
	var uid := s.components.place(s.grid, "reactor_mk1", REACTOR, 0)
	check(s.refresh(), "a part added behind our back is noticed")
	s.cables.place(s.grid, Vector2i(5, 5))
	check(s.refresh(), "so is a cable")
	check(s.power_state["powered"][uid], "the reactor is in the power result")
	s.components.remove_at(REACTOR)
	check(s.refresh(), "a part removed too")
	check(not s.power_state["powered"].has(uid), "and it is gone from the result")


func test_round_trip_covers_everything() -> void:
	var a := _powered_room()
	a.name = "Round"
	a.world_pos = Vector2(120.5, -40)
	a.rot_quarters = 3
	var s := BuildSession.new(a)
	s.apply([{"layer": "tile", "cell": Vector2i(6, 8), "to": "door"}])
	a.grid.set_door_open(Vector2i(6, 8), true)
	a.refresh()
	a.atmosphere.pressure[0] = 0.5
	var d: Dictionary = JSON.parse_string(JSON.stringify(a.to_dict()))
	eq(d["version"], 3, "version 3")
	var b := Ship.new_starter()
	eq(b.load_dict(d), "", "loads")
	eq(b.grid.size, a.grid.size, "size")
	eq(b.grid.hull, a.grid.hull, "hull")
	eq(b.grid.tiles, a.grid.tiles, "tiles")
	check(b.grid.is_door_open(Vector2i(6, 8)), "the open door")
	eq(b.components.to_dict(), a.components.to_dict(), "components, uids included")
	eq(b.cables.cells, a.cables.cells, "cables")
	eq(b.inventory.to_dict(), a.inventory.to_dict(), "cargo")
	eq([b.name, b.world_pos, b.rot_quarters], ["Round", Vector2(120.5, -40), 3], "name and world transform")
	check(is_equal_approx(b.atmosphere.pressure[0], 0.5), "oxygen")
	check(b.power_state["powered"].size() == 2 and b.power_state["powered"].values().all(func(p): return p), "power solved after loading")
	eq(JSON.stringify(b.to_dict()), JSON.stringify(a.to_dict()), "and it saves back the same")


func test_version_2_save_loads_without_parts_or_cables() -> void:
	var a := _powered_room()
	var old := a.grid.to_dict()  # grid version 2: tiles and doors
	old["cargo"] = {"scrap": 7, "copper": 3}
	eq(old["version"], 2, "a version 2 save")
	eq(a.load_dict(JSON.parse_string(JSON.stringify(old))), "", "loads into a ship that has parts")
	eq(a.components.instances.size(), 0, "no components")
	eq(a.cables.cells.size(), 0, "no cables")
	eq(a.inventory.to_dict(), {"scrap": 7, "copper": 3}, "cargo from the save")
	check(a.grid.get_tile(Vector2i(3, 3)) == "wall", "tiles from the save")
	check(a.power_state["powered"].is_empty(), "nothing to power")
	eq(a.load_dict({"version": 4}), "unsupported ship version", "a newer version is refused")


func test_bad_saves_change_nothing() -> void:
	var a := _powered_room()
	var before := JSON.stringify(a.to_dict())
	var bad := a.to_dict()
	bad["components"]["instances"].append({"uid": 99, "id": "teleporter", "anchor": [1, 1], "rot": 0})
	eq(a.load_dict(bad), "unknown component teleporter", "unknown part refused")
	bad = a.to_dict()
	bad.erase("cables")
	eq(a.load_dict(bad), "bad ship data", "missing cables refused")
	bad = a.to_dict()
	bad["cables"]["version"] = 9
	eq(a.load_dict(bad), "unsupported cables version", "wrong cables version refused")
	bad = a.to_dict()
	bad["components"]["instances"] = [{"uid": 1}]
	eq(a.load_dict(bad), "bad ship data", "a half-written part refused")
	bad = a.to_dict()
	bad["cargo"] = {"scrap": -1}
	check(a.load_dict(bad) != "", "bad cargo refused")
	bad = a.to_dict()
	bad["tiles"] = [[1, 1, "teleporter"]]
	check(a.load_dict(bad) != "", "bad tiles refused")
	eq(JSON.stringify(a.to_dict()), before, "the ship is as it was")


# --- The simulation, headless ---

func test_a_powered_generator_raises_the_pressure() -> void:
	var ship := _powered_room()
	check(ship.power_state["powered"][ship.components.at(GEN)], "the generator is powered")
	ship.atmosphere.pressure[ship.atmosphere.room_at(GEN)] = 0.5
	var sim := _sim_of([ship])
	_run(sim, 2.0)
	var rate: float = ship.components.def("oxygen_gen")["stats"]["o2_rate"]
	check(is_equal_approx(_room_pressure(ship), 0.5 + rate * 2.0 / 20.0), "0.6 cell units a second into 20 cells, got %f" % _room_pressure(ship))
	sim.free()


func test_no_reactor_no_oxygen() -> void:
	var ship := _powered_room()
	BuildSession.new(ship).apply([{"layer": "component", "cell": REACTOR}])
	ship.refresh()
	ship.atmosphere.pressure[ship.atmosphere.room_at(GEN)] = 0.5
	var sim := _sim_of([ship])
	_run(sim, 2.0)
	eq(_room_pressure(ship), 0.5, "an unpowered generator adds nothing")
	check(not ship.power_state["powered"][ship.components.at(GEN)], "and the sim saw it unpowered")
	sim.free()


func test_power_follows_a_part_removed_behind_the_sims_back() -> void:
	var ship := _powered_room()
	var sim := _sim_of([ship])
	_run(sim, 0.5)
	ship.components.remove_at(REACTOR)  # no BuildSession, no mark_dirty
	ship.atmosphere.pressure[ship.atmosphere.room_at(GEN)] = 0.5
	_run(sim, 1.0)
	eq(_room_pressure(ship), 0.5, "power was re-solved")
	sim.free()


func test_crew_breathe() -> void:
	var ship := _room_ship()
	ship.crew.append(CrewMember.new("A", Vector2(5.5, 5.5)))
	ship.crew.append(CrewMember.new("B", Vector2(6.5, 5.5)))
	var sim := _sim_of([ship])
	_run(sim, 10.0)
	check(is_equal_approx(_room_pressure(ship), 1.0 - 2.0 * 0.02 * 10.0 / 20.0), "two people use 0.4 cell units in 10 s, got %f" % _room_pressure(ship))
	sim.free()


func test_a_door_is_open_while_someone_stands_in_it() -> void:
	var g := GridTests.grid_from(["#######", "#..D..#", "#######"])
	var ship := Ship.new("Doors", g)
	ship.refresh()
	var left := ship.atmosphere.room_at(Vector2i(1, 1))
	var right := ship.atmosphere.room_at(Vector2i(5, 1))
	check(left >= 0 and right >= 0 and left != right, "two rooms")
	ship.atmosphere.pressure[left] = 1.0
	ship.atmosphere.pressure[right] = 0.0
	var sim := _sim_of([ship])
	_run(sim, 1.0)
	eq(ship.atmosphere.pressure[right], 0.0, "a shut door holds the air")
	ship.crew.append(CrewMember.new("Walker", Vector2(3.5, 1.5)))
	_run(sim, 1.0)
	check(ship.atmosphere.pressure[right] > 0.1, "air flows through the door while someone is in it")
	var total: float = ship.atmosphere.total_oxygen()
	ship.crew[0].pos = Vector2(1.5, 1.5)
	var after := ship.atmosphere.pressure[right]
	_run(sim, 1.0)
	eq(ship.atmosphere.pressure[right], after, "and stops when they step out")
	check(ship.atmosphere.total_oxygen() <= total, "nothing was made out of nothing")
	sim.free()


func test_the_sim_runs_every_ship() -> void:
	var a := _powered_room()
	var b := _powered_room()
	b.name = "Other"
	for ship in [a, b]:
		ship.atmosphere.pressure[ship.atmosphere.room_at(GEN)] = 0.5
	var sim := _sim_of([a, b])
	eq(sim.player_ship(), a, "the first ship is the player's")
	_run(sim, 1.0)
	check(_room_pressure(a) > 0.5 and _room_pressure(b) > 0.5, "both ships got oxygen")
	sim.free()
	var fresh := ShipSim.new()
	eq(fresh.ships.size(), 1, "one ship to start with")
	check(fresh.player_ship().grid.hull.size() > 0, "the starter")
	fresh.free()


func test_crew_walk_through_every_door() -> void:
	var view := CrewView.new()
	check(view.door_passable.call(Vector2i(3, 3)), "auto doors: no locks")
	view.free()
