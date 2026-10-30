extends "res://tests/base_test.gd"

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Components = preload("res://scripts/ship/components.gd")
const Cables = preload("res://scripts/ship/cables.gd")
const Power = preload("res://scripts/sim/power.gd")
const Rooms = preload("res://scripts/sim/rooms.gd")
const Workshop = preload("res://scripts/craft/workshop.gd")

var grid: ShipGrid
var comps: Components


## Two walled rooms side by side on an all-hull grid: the left room is x 1..20, the right x 23..42
## (both y 1..12). Room 0 is the left one. No components yet.
func _setup() -> void:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	grid = ShipGrid.new(Vector2i(44, 14), defs)
	for y in 14:
		for x in 44:
			grid.hull[Vector2i(x, y)] = true
	_box(Rect2i(0, 0, 22, 14))
	_box(Rect2i(22, 0, 22, 14))
	comps = Components.new()
	comps.load_defs("res://data/components.json")


func _box(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			grid.place("wall" if edge else "floor", Vector2i(x, y))


func _put(id: String, x: int, y: int) -> int:
	var uid := comps.place(grid, id, Vector2i(x, y), 0)
	check(uid > 0, "%s placed at %d,%d" % [id, x, y])
	return uid


## Everything powered, except the uids in `off`.
func _on(off := []) -> Dictionary:
	var p := {}
	for uid in comps.instances:
		p[uid] = not off.has(uid)
	return p


func _level(fab: int, powered: Dictionary) -> Dictionary:
	return Workshop.level_of(comps, Rooms.compute(grid), fab, powered)


func test_base_level_is_one() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	var r := _level(fab, _on())
	eq(r["level"], 1, "a lone fabricator is level 1")
	eq(r["tools"], [], "no tools")
	eq(r["modules"], [], "no modules")


func test_robot_arm_in_the_same_room_makes_level_two() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	var arm := _put("robot_arm", 7, 2)
	var r := _level(fab, _on())
	eq(r["level"], 2, "one arm: level 2")
	eq(r["modules"], [arm], "the arm is listed")
	eq(r["tools"], [], "an arm is no tool")
	_put("robot_arm", 9, 2)
	eq(_level(fab, _on())["level"], 2, "a second arm alone changes nothing")


func test_a_module_in_another_room_does_not_count() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	_put("robot_arm", 24, 2)
	_put("laser_cutter", 28, 2)
	var r := _level(fab, _on())
	eq(r["level"], 1, "arm next door: still level 1")
	eq(r["tools"], [], "cutter next door: no tool")
	eq(r["modules"], [], "no modules")
	var res := Rooms.compute(grid)
	check(res["room_of"][Vector2i(2, 2)] != res["room_of"][Vector2i(24, 2)], "they really are in different rooms")


func test_an_unpowered_module_does_not_count() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	var arm := _put("robot_arm", 7, 2)
	var cutter := _put("laser_cutter", 12, 2)
	var r := _level(fab, _on([arm, cutter]))
	eq(r["level"], 1, "unpowered arm: level 1")
	eq(r["tools"], [], "unpowered cutter: no tool")
	eq(r["modules"], [], "none counted")
	r = _level(fab, _on([cutter]))
	eq(r["level"], 2, "powered arm counts again")
	var p := _on()
	p.erase(arm)
	eq(_level(fab, p)["level"], 1, "a uid missing from the powered map is unpowered")


func test_rig_and_two_arms_make_level_three() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	var a := _put("robot_arm", 7, 2)
	var rig := _put("assembly_rig", 2, 5)
	eq(_level(fab, _on())["level"], 2, "rig with one arm: still 2")
	var b := _put("robot_arm", 9, 2)
	var r := _level(fab, _on())
	eq(r["level"], 3, "rig and two arms: 3")
	eq(r["modules"], [a, rig, b], "modules sorted by uid")
	eq(_level(fab, _on([b]))["level"], 2, "an unpowered arm drops it to 2")
	eq(_level(fab, _on([rig]))["level"], 2, "an unpowered rig drops it to 2")


func test_rig_without_arms_stays_level_one() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	_put("assembly_rig", 2, 5)
	eq(_level(fab, _on())["level"], 1, "a rig alone does nothing")


func test_nanoforge_makes_level_four_on_top_of_level_three() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	_put("robot_arm", 7, 2)
	_put("robot_arm", 9, 2)
	_put("assembly_rig", 2, 5)
	var forge := _put("nanoforge", 7, 5)
	var r := _level(fab, _on())
	eq(r["level"], 4, "level 4")
	eq(r["tools"], ["nanoforge"], "and the nanoforge tool")
	eq(_level(fab, _on([forge]))["level"], 3, "without power for the forge: 3")
	eq(_level(fab, _on([forge]))["tools"], [], "and no tool")


func test_nanoforge_without_the_level_three_set_up() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	_put("robot_arm", 7, 2)
	_put("nanoforge", 7, 5)
	var r := _level(fab, _on())
	eq(r["level"], 2, "no rig: the forge adds no level")
	eq(r["tools"], ["nanoforge"], "but it is a tool")


func test_laser_cutter_adds_its_tool() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	var cutter := _put("laser_cutter", 12, 2)
	var r := _level(fab, _on())
	eq(r["tools"], ["laser_cutter"], "the cutter tool")
	eq(r["level"], 1, "but no level")
	eq(r["modules"], [cutter], "listed")
	_put("robot_arm", 7, 2)
	_put("assembly_rig", 2, 5)
	_put("robot_arm", 9, 2)
	_put("nanoforge", 7, 5)
	eq(_level(fab, _on())["tools"], ["laser_cutter", "nanoforge"], "tools come in a fixed order")


func test_unpowered_fabricator_is_level_zero() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	_put("robot_arm", 7, 2)
	_put("laser_cutter", 12, 2)
	var r := _level(fab, _on([fab]))
	eq(r["level"], 0, "offline")
	eq(r["tools"], [], "no tools")
	eq(r["modules"], [], "no modules")
	eq(_level(fab, {})["level"], 0, "not in the powered map: offline")
	eq(_level(99, _on())["level"], 0, "no such fabricator: offline")


func test_fabricator_outside_any_room_is_level_one_without_tools() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	_put("robot_arm", 7, 2)
	_put("laser_cutter", 12, 2)
	var r := Workshop.level_of(comps, {"room_of": {}, "rooms": [], "doors": []}, fab, _on())
	eq(r["level"], 1, "no room: level 1")
	eq(r["tools"], [], "no tools")
	eq(r["modules"], [], "no modules")


func test_modules_in_the_fabricators_room_when_it_is_the_right_one() -> void:
	_setup()
	var fab := _put("fabricator", 24, 2)
	_put("robot_arm", 7, 2)
	var arm := _put("robot_arm", 29, 2)
	var r := _level(fab, _on())
	eq(r["level"], 2, "the arm in the fabricator's own room counts")
	eq(r["modules"], [arm], "only that one")


func test_with_the_real_power_solver() -> void:
	_setup()
	var cables := Cables.new()
	var fab := _put("fabricator", 2, 2)
	var arm := _put("robot_arm", 7, 2)
	var cutter := _put("laser_cutter", 12, 2)
	_put("reactor_mk1", 15, 2)
	var loose := _put("robot_arm", 15, 8)  # no cable: never powered
	for x in range(2, 16):
		check(cables.place(grid, Vector2i(x, 2)), "cable at %d,2" % x)
	var res := Power.solve(comps, cables)
	check(res["powered"][fab] and res["powered"][arm] and res["powered"][cutter], "the cabled parts are on")
	check(not res["powered"][loose], "the loose arm is off")
	var r := Workshop.level_of(comps, Rooms.compute(grid), fab, res["powered"])
	eq(r["level"], 2, "one powered arm: level 2")
	eq(r["tools"], ["laser_cutter"], "powered cutter")
	eq(r["modules"], [arm, cutter], "the loose arm is not counted")
	comps.remove_at(Vector2i(15, 2))
	res = Power.solve(comps, cables)
	r = Workshop.level_of(comps, Rooms.compute(grid), fab, res["powered"])
	eq(r["level"], 0, "no reactor: the fabricator is offline")
	eq(r["tools"], [], "and has no tools")
