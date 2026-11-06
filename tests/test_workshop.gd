extends "res://tests/base_test.gd"

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Components = preload("res://scripts/ship/components.gd")
const Cables = preload("res://scripts/ship/cables.gd")
const Power = preload("res://scripts/sim/power.gd")
const Rooms = preload("res://scripts/sim/rooms.gd")
const Workshop = preload("res://scripts/craft/workshop.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const Damage = preload("res://scripts/combat/damage.gd")
const Arena = preload("res://scripts/combat/arena.gd")

## The fabricator's level is its own (upgraded in build mode); the workshop modules in its room give tools and crafting speed.
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


func _set_level(fab: int, level: int) -> void:
	comps.instances[fab]["fab_level"] = level


func test_robot_arm_and_rig_make_crafting_faster_not_higher() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	var arm := _put("robot_arm", 7, 2)
	var r := _level(fab, _on())
	eq(r["level"], 1, "an arm no longer sets the level")
	eq(r["modules"], [arm], "the arm is listed")
	eq(r["tools"], [], "an arm is no tool")
	eq(r["speed"], 1.25, "one arm: +25%")
	_put("robot_arm", 9, 2)
	eq(_level(fab, _on())["speed"], 1.5, "two: +50%")
	_put("assembly_rig", 2, 5)
	r = _level(fab, _on())
	eq(r["speed"], 1.5, "a rig adds to the same pool, capped at +50%")
	eq(r["level"], 1, "and sets no level")
	_put("nanoforge", 7, 5)
	eq(_level(fab, _on())["level"], 1, "a nanoforge sets no level either")


func test_the_rig_counts_for_speed_like_an_arm() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	_put("assembly_rig", 2, 5)
	eq(_level(fab, _on())["speed"], 1.25, "a rig alone: +25%")


func test_level_is_the_fabricators_own() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	for lv in [1, 2, 3, 4]:
		_set_level(fab, lv)
		eq(_level(fab, _on())["level"], lv, "level %d as saved on the instance" % lv)
	eq(_level(fab, _on([fab]))["level"], 0, "unpowered: 0 whatever the level")


func test_a_module_in_another_room_does_not_count() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	_put("robot_arm", 24, 2)
	_put("laser_cutter", 28, 2)
	var r := _level(fab, _on())
	eq(r["speed"], 1.0, "arm next door: no speed")
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
	eq(r["speed"], 1.0, "unpowered arm: no speed")
	eq(r["tools"], [], "unpowered cutter: no tool")
	eq(r["modules"], [], "none counted")
	r = _level(fab, _on([cutter]))
	eq(r["speed"], 1.25, "powered arm counts again")
	var p := _on()
	p.erase(arm)
	eq(_level(fab, p)["speed"], 1.0, "a uid missing from the powered map is unpowered")


func test_the_tools_come_from_the_modules() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	var cutter := _put("laser_cutter", 12, 2)
	var r := _level(fab, _on())
	eq(r["tools"], ["laser_cutter"], "the cutter tool")
	eq(r["level"], 1, "but no level")
	eq(r["modules"], [cutter], "listed")
	_put("nanoforge", 7, 5)
	eq(_level(fab, _on())["tools"], ["laser_cutter", "nanoforge"], "tools come in a fixed order")


func test_unpowered_fabricator_is_level_zero() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	_set_level(fab, 3)
	_put("robot_arm", 7, 2)
	_put("laser_cutter", 12, 2)
	var r := _level(fab, _on([fab]))
	eq(r["level"], 0, "offline")
	eq(r["tools"], [], "no tools")
	eq(r["modules"], [], "no modules")
	eq(_level(fab, {})["level"], 0, "not in the powered map: offline")
	eq(_level(99, _on())["level"], 0, "no such fabricator: offline")


func test_fabricator_outside_any_room_keeps_its_level_without_tools() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	_set_level(fab, 2)
	_put("robot_arm", 7, 2)
	_put("laser_cutter", 12, 2)
	var r := Workshop.level_of(comps, {"room_of": {}, "rooms": [], "doors": []}, fab, _on())
	eq(r["level"], 2, "no room: its own level")
	eq(r["tools"], [], "no tools")
	eq(r["speed"], 1.0, "no speed")
	eq(r["modules"], [], "no modules")


func test_modules_in_the_fabricators_room_when_it_is_the_right_one() -> void:
	_setup()
	var fab := _put("fabricator", 24, 2)
	_put("laser_cutter", 7, 2)
	var cutter := _put("laser_cutter", 29, 2)
	var r := _level(fab, _on())
	eq(r["tools"], ["laser_cutter"], "the cutter in the fabricator's own room counts")
	eq(r["modules"], [cutter], "only that one")


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
	eq(r["speed"], 1.25, "one powered arm: +25%")
	eq(r["tools"], ["laser_cutter"], "powered cutter")
	eq(r["modules"], [arm, cutter], "the loose arm is not counted")
	comps.remove_at(Vector2i(15, 2))
	res = Power.solve(comps, cables)
	r = Workshop.level_of(comps, Rooms.compute(grid), fab, res["powered"])
	eq(r["level"], 0, "no reactor: the fabricator is offline")
	eq(r["tools"], [], "and has no tools")


# --- the upgrade path, one per ship, never wrecked, old saves --------------------------------------------------------

## A test-room ship with the fabricator placed and a stock of every upgrade material.
func _ship(stock := true) -> Dictionary:
	var ship := Fixture.room_ship()
	var fab := Fixture.put(ship, "fabricator", 15, 10)
	if stock:
		ship.inventory.load_dict({"scrap": 1000, "copper": 100, "titanium": 100, "silicon": 50, "conductor": 50, "polymer": 50, "alloy": 100, "crystal": 50})
	return {"ship": ship, "fab": fab}


func test_the_upgrade_costs_are_data_and_the_path_runs_one_to_four() -> void:
	var d := _ship()
	var ship: Ship = d["ship"]
	eq(Workshop.upgrade_cost(ship, 2), {"scrap": 80, "copper": 30, "titanium": 8}, "level 2 costs")
	eq(Workshop.upgrade_cost(ship, 3), {"scrap": 150, "titanium": 30, "silicon": 15, "polymer": 20}, "level 3 costs")
	eq(Workshop.upgrade_cost(ship, 4), {"scrap": 250, "alloy": 40, "conductor": 20, "crystal": 10}, "level 4 costs")
	eq(Workshop.upgrade_cost(ship, 5), {}, "nothing beyond 4")
	eq(Workshop.upgrade_cost(ship, 1), {}, "nothing for 1")
	eq(int(ship.components.instances[d["fab"]]["fab_level"]), 1, "it starts at level 1")
	for lv in [2, 3, 4]:
		var before: int = ship.inventory.count("scrap")
		var cost := Workshop.upgrade_cost(ship, lv)
		eq(Workshop.upgrade(ship, d["fab"]), "", "upgrade to %d" % lv)
		eq(int(ship.components.instances[d["fab"]]["fab_level"]), lv, "level %d" % lv)
		eq(ship.inventory.count("scrap"), before - int(cost["scrap"]), "the scrap was paid")
	eq(Workshop.upgrade(ship, d["fab"]), "Fully upgraded", "no level 5")
	eq(Workshop.upgrade_info(ship, d["fab"])["text"], "Fully upgraded", "the card says so")
	eq(Workshop.upgrade_info(ship, d["fab"])["next"], 0, "no next level")


func test_an_upgrade_when_short_is_refused_and_pays_nothing() -> void:
	var d := _ship(false)
	var ship: Ship = d["ship"]
	ship.inventory.load_dict({"scrap": 80, "copper": 30, "titanium": 7})
	var inf := Workshop.upgrade_info(ship, d["fab"])
	eq(inf["short"], {"titanium": 1}, "one titanium short")
	check(not inf["can"], "cannot")
	check(Workshop.upgrade(ship, d["fab"]) != "", "refused")
	eq(int(ship.components.instances[d["fab"]]["fab_level"]), 1, "still level 1")
	eq(ship.inventory.count("scrap"), 80, "nothing was paid")
	ship.inventory.add("titanium", 1)
	eq(Workshop.upgrade(ship, d["fab"]), "", "with the titanium it goes")
	eq(ship.inventory.count("scrap"), 0, "and the scrap is gone")


func test_the_card_counts_the_known_blueprints_the_next_level_opens() -> void:
	var d := _ship()
	var ship: Ship = d["ship"]
	var known_l2 := 0
	var known_all := 0
	for id in ship.crafting.known:
		var r: Dictionary = ship.crafting.def(id)
		if r["station"] == "fabricator" and int(r["fab_level"]) <= 2:
			known_all += 1
			if int(r["fab_level"]) == 2:
				known_l2 += 1
	var inf := Workshop.upgrade_info(ship, d["fab"])
	eq([inf["new"], inf["total"]], [known_l2, known_all], "counted from the known recipes")
	check(str(inf["text"]).begins_with("Level 2: %d more blueprint" % known_l2), "the card text: " + str(inf["text"]))


func test_one_fabricator_per_ship() -> void:
	var d := _ship()
	var ship: Ship = d["ship"]
	eq(ship.components.can_place(ship.grid, "fabricator", Vector2i(10, 14), 0), "One fabricator per ship: click yours to upgrade it", "can_place says why")
	eq(Fixture.put(ship, "fabricator", 10, 14), -1, "refused")
	ship.inventory.add("fabricator", 1)  # from the cargo, in build mode
	var s := BuildSession.new(ship)
	var r := s.apply(s.plan_component("fabricator", Vector2i(10, 14), 0)["changes"])
	eq(r["applied"], 0, "build mode: not placed")
	check("One fabricator per ship" in str(r["reason"]), "with the reason: " + str(r["reason"]))
	eq(ship.inventory.count("fabricator"), 1, "and it stays in the cargo")
	ship.components.remove_uid(d["fab"])
	check(Fixture.put(ship, "fabricator", 10, 14) > 0, "with none aboard it goes")


func test_the_fabricator_recipe_is_refused_on_a_ship_that_has_one() -> void:
	var d := _ship()
	var ship: Ship = d["ship"]
	ship.crafting.known["fabricator"] = true
	var fab := {"level": 4, "tools": [], "count": 1}
	check("one fabricator per ship" in ship.crafting.can_craft("fabricator", ship.inventory, fab), "refused when the ship has one")


func test_a_saved_set_with_two_fabricators_keeps_one() -> void:
	var d := _ship()
	var ship: Ship = d["ship"]
	var saved: Dictionary = ship.components.to_dict()
	var extra: Dictionary = saved["instances"][0].duplicate(true)
	extra["uid"] = 99
	extra["anchor"] = [10, 14]
	saved["instances"].append(extra)
	var c := Components.new()
	c.load_defs("res://data/components.json")
	eq(c.load_dict(saved, ship.grid), "", "loads")
	var n := 0
	for uid in c.instances:
		if c.instances[uid]["id"] == "fabricator":
			n += 1
	eq(n, 1, "one fabricator")
	eq(c.returned.size(), 1, "the other went back to the cargo")
	eq(c.returned[0]["id"], "fabricator", "it is a fabricator")


func test_every_shipped_design_has_at_most_one_fabricator() -> void:
	var dirs: Array[String] = ["res://data/ships/"]
	for p in DirAccess.get_directories_at("res://data/packs"):
		dirs.append("res://data/packs/%s/ships/" % p)
	var n := 0
	for dir in dirs:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".json"):
				continue
			var ship = Ship.from_design(dir + f)
			var k := 0
			for uid in ship.components.instances:
				if ship.components.instances[uid]["id"] == "fabricator":
					k += 1
			check(k <= 1 and ship.components.returned.is_empty(), "%s%s: %d fabricators" % [dir, f, k])
			n += 1
	check(n >= 40, "looked at the designs (%d)" % n)


func test_the_blank_frame_kit_has_a_fabricator_to_place() -> void:
	var ship = Ship.from_design("res://data/ships/starter_blank.json")
	eq(ship.inventory.count("fabricator"), 1, "the kit carries one")
	eq(Workshop.fab_uid(ship), -1, "none placed yet")


func test_the_fabricator_is_never_wrecked() -> void:
	var d := _ship()
	var ship: Ship = d["ship"]
	check(not ship.components.can_wreck("fabricator"), "no_wreck in the data")
	check(ship.components.can_wreck("robot_arm"), "other parts can be")
	var arena := Arena.new(1)
	arena.add_ship(ship)
	var uid: int = d["fab"]
	var obj := {"kind": "component", "uid": uid, "def": ship.components.def("fabricator")}
	var cell: Vector2i = ship.components.instances[uid]["cells"][0]
	for i in 6:
		arena.tick += 2
		Damage.apply(arena, 0, cell, obj, 50.0, "kinetic")
	check(ship.components.instances.has(uid), "still aboard after six big hits")
	eq(ship.components.instances[uid]["status"], "disabled", "only disabled")
	eq(ship.components.wrecks.size(), 0, "no debris")


func test_an_old_saved_fabricator_takes_the_level_its_modules_gave_it() -> void:
	_setup()
	var fab := _put("fabricator", 2, 2)
	eq(Workshop.legacy_level(comps, Rooms.compute(grid), fab), 1, "alone: 1")
	_put("robot_arm", 7, 2)
	eq(Workshop.legacy_level(comps, Rooms.compute(grid), fab), 2, "an arm: 2")
	_put("assembly_rig", 2, 5)
	eq(Workshop.legacy_level(comps, Rooms.compute(grid), fab), 2, "a rig with one arm: still 2")
	_put("robot_arm", 9, 2)
	eq(Workshop.legacy_level(comps, Rooms.compute(grid), fab), 3, "a rig and two arms: 3")
	_put("nanoforge", 7, 5)
	eq(Workshop.legacy_level(comps, Rooms.compute(grid), fab), 4, "and a nanoforge: 4")


func test_loading_a_save_with_no_level_migrates_it_and_saving_keeps_it() -> void:
	var d := _ship()
	var ship: Ship = d["ship"]
	Fixture.put(ship, "robot_arm", 19, 10)
	Fixture.put(ship, "assembly_rig", 10, 13)
	Fixture.put(ship, "robot_arm", 19, 12)
	var saved: Dictionary = ship.to_dict()
	for i in saved["components"]["instances"]:
		i.erase("fab_level")  # a save from before the fabricator had a level of its own
	saved["components"]["version"] = 7
	var loaded := Fixture.room_ship()
	eq(loaded.load_dict(saved), "", "an old save loads")
	var fab := Workshop.fab_uid(loaded)
	check(fab > 0, "the fabricator is back")
	var lv := int(loaded.components.instances[fab].get("fab_level", 0))
	check(lv >= 2, "it did not lose the level its modules gave it (%d)" % lv)
	var again: Dictionary = loaded.to_dict()
	var rec: Dictionary = {}
	for i in again["components"]["instances"]:
		if i["id"] == "fabricator":
			rec = i
	eq(int(rec.get("fab_level", 0)), lv, "saved from then on")
	eq(int(again["components"]["version"]), Components.VERSION, "on the current version")
	var back := Fixture.room_ship()
	eq(back.load_dict(again), "", "and loads again")
	eq(int(back.components.instances[Workshop.fab_uid(back)]["fab_level"]), lv, "with the same level")
	eq(back.components.legacy_fabs.size(), 0, "nothing left to migrate")
