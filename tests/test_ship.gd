extends "res://tests/base_test.gd"

const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const CrewView = preload("res://scripts/crew/crew_view.gd")
const GridTests = preload("res://tests/test_pathfinder.gd")
const REACTOR := Vector2i(10, 10)  # 4x4: x 10..13, y 10..13
const GEN := Vector2i(15, 10)  # 2x4: x 15..16, y 10..13
const ROOM_CELLS := 104.0  # the room below: floor x 9..21, y 9..16


## A 31x31 ship with a sealed room (walls round (8,8)-(22,17), floor inside: 13x8 = 104 cells) and a few parts in the cargo.
func _room_ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	var ship := Ship.new("Test", g)
	ship.inventory.load_dict({"scrap": 400, "copper": 40, "reactor_mk1": 1, "oxygen_gen": 1, "helm": 1})
	BuildSession.new(ship).apply(BuildSession.room_changes(Vector2i(8, 8), Vector2i(22, 17), "wall", "floor"))
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
	s.apply(_cables([Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)]))
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
	return ship.atmosphere.pressure_at(Vector2i(12, 15))


# --- The ship ---

func test_starter_ship_has_hull_and_cargo() -> void:
	var s := Ship.new_starter()
	eq(s.grid.size, Vector2i(63, 63), "a 63x63 grid for the 2x2 crew")
	check(s.grid.in_hull(Vector2i(31, 31)) and s.grid.in_hull(Vector2i(31, 4)) and not s.grid.in_hull(Vector2i(31, 2)), "a circular hull of radius 28")
	check(s.grid.hull.size() > 2400, "a circular hull")
	eq(s.grid.tiles.size(), 0, "nothing built yet")
	check(s.inventory.count("scrap") > 0 and s.inventory.count("copper") > 0, "starts with materials")
	for id in ["reactor_mk1", "oxygen_gen", "helm", "fabricator"]:
		check(s.inventory.count(id) > 0, "starts with a " + id)
	var mats: Array = []
	for m in JSON.parse_string(FileAccess.get_file_as_string("res://data/materials.json"))["materials"]:
		mats.append(m["id"])
	var items: Array = []
	for it in JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))["items"]:
		items.append(it["id"])
	for id in s.inventory.counts:
		check(id in mats or id in items or s.components.has(id), "%s is a material, an item or a known system" % id)
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
	s.cables.place(s.grid, Vector2i(11, 11))
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
	s.apply([{"layer": "tile", "cell": Vector2i(12, 17), "to": "door"}])  # a 2-cell door in the bottom wall
	a.grid.set_door_open(Vector2i(12, 17), true)
	a.refresh()
	a.atmosphere.pressure[0] = 0.5
	var d: Dictionary = JSON.parse_string(JSON.stringify(a.to_dict()))
	eq(d["version"], 3, "version 3")
	var b := Ship.new_starter()
	eq(b.load_dict(d), "", "loads")
	eq(b.grid.size, a.grid.size, "size")
	eq(b.grid.hull, a.grid.hull, "hull")
	eq(b.grid.tiles, a.grid.tiles, "tiles")
	check(b.grid.is_door_open(Vector2i(12, 17)) and b.grid.is_door_open(Vector2i(13, 17)), "the open door, both cells")
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
	check(a.grid.get_tile(Vector2i(8, 8)) == "wall", "tiles from the save")
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
	check(is_equal_approx(_room_pressure(ship), 0.5 + rate * 2.0 / ROOM_CELLS), "0.6 cell units a second into 104 cells, got %f" % _room_pressure(ship))
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
	ship.crew.append(CrewMember.new("A", Vector2(12.0, 14.0)))
	ship.crew.append(CrewMember.new("B", Vector2(16.0, 14.0)))
	var sim := _sim_of([ship])
	_run(sim, 10.0)
	check(is_equal_approx(_room_pressure(ship), 1.0 - 2.0 * 0.02 * 10.0 / ROOM_CELLS), "two people use 0.4 cell units in 10 s, got %f" % _room_pressure(ship))
	sim.free()


func test_a_door_is_open_while_someone_stands_in_it() -> void:
	var g := GridTests.grid_from([
		"##########",
		"#...D....#",
		"#...D....#",
		"##########",
	])
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
	ship.crew.append(CrewMember.new("Walker", Vector2(4.0, 2.0)))  # the body covers the door
	_run(sim, 1.0)
	check(ship.atmosphere.pressure[right] > 0.1, "air flows through the door while someone is in it")
	var total: float = ship.atmosphere.total_oxygen()
	ship.crew[0].pos = Vector2(2.0, 2.0)
	var after := ship.atmosphere.pressure[right]
	_run(sim, 1.0)
	eq(ship.atmosphere.pressure[right], after, "and stops when they step out")
	check(ship.atmosphere.total_oxygen() <= total, "nothing was made out of nothing")
	sim.free()


func test_a_body_over_one_cell_opens_the_whole_door_piece() -> void:
	var g := GridTests.grid_from([
		"#######",
		"#.....#",
		"#.....#",
		"##DD###",
		"#.....#",
		"#.....#",
		"#######",
	])
	var ship := Ship.new("Doors", g)
	ship.refresh()
	var above := ship.atmosphere.room_at(Vector2i(1, 1))
	var below := ship.atmosphere.room_at(Vector2i(1, 4))
	ship.atmosphere.pressure[above] = 1.0
	ship.atmosphere.pressure[below] = 0.0
	var sim := _sim_of([ship])
	var walker := CrewMember.new("Walker", Vector2(4.0, 2.6))  # body on x 3..4, y 2..3: only door cell (3,3) is under it
	eq(walker.body_cells(), [Vector2i(3, 2), Vector2i(4, 2), Vector2i(3, 3), Vector2i(4, 3)] as Array[Vector2i], "the body covers one door cell")
	ship.crew.append(walker)
	sim.step(0.01)
	# Both door cells pass gas: 2 cells x 1.0 diff x door_rate 2.0 x 0.01 s into a room of 10 cells.
	check(absf(ship.atmosphere.pressure[below] - 2.0 * 2.0 * 0.01 / 10.0) < 0.0001, "the other cell of the piece opened too, got %f" % ship.atmosphere.pressure[below])
	walker.pos = Vector2(3.0, 1.0)
	sim.step(0.01)
	var held: float = ship.atmosphere.pressure[below]
	sim.step(0.01)
	eq(ship.atmosphere.pressure[below], held, "shut again once the body is clear")
	sim.free()


func test_open_door_cells_are_the_opened_doors_and_the_pieces_with_a_body_in_them() -> void:
	var g := GridTests.grid_from([
		"#########",
		"#...D...#",
		"#...D...#",
		"#########",
	])
	var ship := Ship.new("Doors", g)
	eq(ShipSim.open_door_cells(ship), {}, "all shut, nobody about")
	ship.crew.append(CrewMember.new("A", Vector2(2.0, 2.0)))
	eq(ShipSim.open_door_cells(ship), {}, "a body next to the door does not open it")
	ship.crew[0].pos = Vector2(3.6, 2.0)  # covers x 3..4: overlaps both door cells
	eq(ShipSim.open_door_cells(ship), {Vector2i(4, 1): true, Vector2i(4, 2): true}, "both cells of the piece")
	ship.crew.clear()
	g.set_door_open(Vector2i(4, 2), true)
	eq(ShipSim.open_door_cells(ship), {Vector2i(4, 1): true, Vector2i(4, 2): true}, "an opened door counts, both cells")


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
