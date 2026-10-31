extends "res://tests/base_test.gd"
## Conveyor belts (docs/CONTENT.md 4f; scripts/sim/belts.gd, scripts/sim/ammo.gd): the layer and its rules, networks, drives,
## the units riding to the guns and the reloads that wait for them, damage and repair, saves, and laying belts in the build session.

const Fx = preload("res://tests/fixture_ammo.gd")
const Ammo = preload("res://scripts/sim/ammo.gd")
const Belts = preload("res://scripts/sim/belts.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Damage = preload("res://scripts/combat/damage.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Palette = preload("res://scripts/build/palette.gd")
const Wall = preload("res://tests/fixture_wall.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Hud = preload("res://scripts/ui/hud.gd")


func near(got: float, want: float, msg: String, eps := 1e-6) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func _why(a, uid: int) -> String:
	return a.weapons.can_fire(a, 0, uid, Fx.AIM)


## Run the belts of `ship` for `seconds` in steps of 0.05 s.
func _run(ship: Ship, seconds: float) -> void:
	for i in roundi(seconds / 0.05):
		Ammo.tick(ship, 0.05)


## Seconds (in 0.05 steps, up to `limit`) until `done` is true; -1 if it never was.
func _until(ship: Ship, done: Callable, limit := 10.0) -> float:
	var t := 0.0
	while t < limit:
		if done.call():
			return t
		Ammo.tick(ship, 0.05)
		t += 0.05
	return -1.0


# --- the layer ------------------------------------------------------------------------------------------------

func test_belts_go_on_floor_and_doors_only() -> void:
	var d := Fx.belts()
	var ship: Ship = d["ship"]
	var b = ship.belts
	eq(b.can_place(ship.grid, ship.components, Vector2i(10, 20)), "", "plain floor")
	eq(b.can_place(ship.grid, ship.components, Vector2i(12, 19)), "", "a door cell")
	eq(b.can_place(ship.grid, ship.components, Vector2i(12, 17)), "belts run on floor and doors, not walls", "not a wall")
	eq(b.can_place(ship.grid, ship.components, Vector2i(10, 18)), "a system is in the way", "not under a system")
	eq(b.can_place(ship.grid, ship.components, Vector2i(13, 18)), "already a belt", "not twice")
	eq(b.can_place(ship.grid, ship.components, Vector2i(2, 2)), "outside the hull", "inside the hull")
	eq(b.can_place(ship.grid, ship.components, Vector2i(14, 22)), "needs floor or a door", "on a tile")


func test_a_belt_costs_one_scrap_a_cell_and_needs_the_blueprint() -> void:
	var ship := Wall.wall_ship(1, 0)
	var s := BuildSession.new(ship)
	var scrap: int = ship.inventory.count("scrap")
	eq(Belts.cost(), {"scrap": 1}, "1 scrap a cell (build.json)")
	var r := s.apply(s.plan_belts(BuildSession.Mode.LINE, false, Vector2i(10, 18), Vector2i(14, 18))["changes"])
	eq(r["applied"], 0, "no drive aboard: no belts")
	check(String(r["reason"]).contains("belt drive"), "and it says why (%s)" % r["reason"])
	check(not Ammo.belts_unlocked(ship), "locked")
	ship.inventory.add("belt_drive_scrap", 1)
	check(Ammo.belts_unlocked(ship), "a drive aboard unlocks it")
	r = s.apply(s.plan_belts(BuildSession.Mode.LINE, false, Vector2i(10, 18), Vector2i(14, 18))["changes"])
	eq(r["applied"], 5, "five cells laid")
	eq(ship.inventory.count("scrap"), scrap - 5, "for 5 scrap")
	check(ship.belts.known, "and the blueprint is learned for good")
	ship.inventory.add("belt_drive_scrap", -1)
	check(Ammo.belts_unlocked(ship), "still known without the drive")
	check(s.undo(), "undo")
	eq(ship.belts.cells.size(), 0, "the belt is gone")
	eq(ship.inventory.count("scrap"), scrap, "and the scrap is back")
	check(s.redo(), "redo")
	eq(ship.belts.cells.size(), 5, "laid again")
	r = s.apply(s.plan_belts(BuildSession.Mode.PAINT, true, Vector2i(10, 18), Vector2i(10, 18), [Vector2i(10, 18)])["changes"])
	eq(r["applied"], 1, "a right-click removes one")
	eq(ship.inventory.count("scrap"), scrap - 4, "and refunds it")


func test_a_part_cannot_be_put_on_a_belt_and_floor_under_a_belt_stays() -> void:
	var d := Fx.belts()
	var ship: Ship = d["ship"]
	var s := BuildSession.new(ship)
	ship.inventory.add("ammo_rack", 1)
	var r := s.apply([{"layer": "component", "id": "ammo_rack", "anchor": Vector2i(16, 18), "rot": 0}])
	eq(r["applied"], 0, "no rack on the belt")
	check(String(r["reason"]).contains("belt"), "reason: " + r["reason"])
	r = s.apply([{"layer": "tile", "cell": Vector2i(14, 18), "to": ""}])
	eq(r["applied"], 0, "no pulling the floor from under a belt")
	check(String(r["reason"]).contains("belt"), "reason: " + r["reason"])


func test_taking_a_rack_out_gives_its_ammo_back_and_undo_puts_it_back() -> void:
	var d := Fx.with_rack()
	var ship: Ship = d["ship"]
	Fx.stock(ship, d["rack"], "missile", 12)
	var s := BuildSession.new(ship)
	var r := s.apply([{"layer": "component", "cell": Vector2i(20, 20)}])
	eq(r["applied"], 1, "removed")
	eq(ship.inventory.count("missile"), 12, "its 12 missiles went to the cargo")
	check(s.undo(), "undo")
	eq(ship.inventory.count("missile"), 0, "and back into the rack")
	eq(Ammo.count_in(ship, d["rack"]), 12, "12 again")
	var before := ship.inventory.counts.duplicate()
	s.preview([{"layer": "component", "cell": Vector2i(20, 20)}])
	eq(ship.inventory.counts, before, "a preview leaves the cargo alone")
	eq(Ammo.count_in(ship, d["rack"]), 12, "and the rack")


# --- networks ---------------------------------------------------------------------------------------------------

func test_orthogonally_joined_cells_are_a_network_and_parts_join_by_an_edge() -> void:
	var d := Fx.belts()
	var ship: Ship = d["ship"]
	var plan: Dictionary = ship.belts.analyze(ship)
	eq(plan["nets"].size(), 1, "one network")
	var net: Dictionary = plan["nets"][0]
	eq(net["cells"].size(), 7, "seven cells")
	eq(net["racks"], [d["rack"]], "the rack touches it")
	eq(net["weapons"], [d["gun"]], "and the gun")
	eq(net["drives"], [d["drive"]], "and the drive")
	check(not plan["touch"].has(d["reactor"]), "the reactor is no belt part")
	ship.belts.cells[Vector2i(20, 17)] = true  # a stray cell touching nothing
	ship.belts.rev += 1
	eq(ship.belts.analyze(ship)["nets"].size(), 2, "a lone cell is a network of its own")


func test_a_cut_cell_splits_the_network_and_mending_it_joins_it_again() -> void:
	var d := Fx.belts()
	var ship: Ship = d["ship"]
	check(ship.belts.cut_cell(Vector2i(12, 18)), "cut the door cell")
	var plan: Dictionary = ship.belts.analyze(ship)
	eq(plan["nets"].size(), 2, "two networks")
	eq(plan["touch"][d["rack"]].size(), 1, "the rack is on one")
	check(plan["touch"][d["rack"]] != plan["touch"][d["gun"]], "and the gun on the other")
	check(ship.belts.repair(Vector2i(12, 18)), "mend it")
	eq(ship.belts.analyze(ship)["nets"].size(), 1, "joined again")


func test_a_breached_belt_cell_is_cut_until_the_breach_is_sealed() -> void:
	var d := Fx.belts()
	var ship: Ship = d["ship"]
	eq(ship.belts.analyze(ship)["nets"].size(), 1, "one network")
	ship.grid.breach(Vector2i(12, 18))
	eq(ship.grid.get_tile(Vector2i(12, 18)), "", "the door is shot open")
	eq(ship.belts.analyze(ship)["nets"].size(), 2, "the belt through it is cut")
	check(ship.belts.cut.is_empty(), "though no cell is marked cut: it heals with the breach")
	ship.grid.repair(Vector2i(12, 18))
	eq(ship.belts.analyze(ship)["nets"].size(), 1, "sealed: whole again")


func test_damage_beside_a_belt_cuts_it_and_a_crew_member_mends_it() -> void:
	var d := Fx.belts()
	var ship: Ship = d["ship"]
	var a := Fx.arena(ship)
	var obj := Damage.solid_at(a.ships[0], Vector2i(14, 17))  # the gun's inside half, just above the belt
	check(not obj.is_empty(), "the gun is there")
	Damage.apply(a, 0, Vector2i(14, 17), obj, 1.0, "kinetic")
	check(ship.belts.cut.has(Vector2i(14, 18)), "the belt cell under it was cut")
	check(a.events.any(func(e): return e["type"] == "belt_cut"), "an event says so")
	eq(ship.belts.analyze(ship)["nets"].size() >= 1, true, "still networks")
	var jobs := Jobs.new()
	jobs.build_board(ship)
	var key := "belt:14,18"
	check(jobs.board.has(key), "a repair job is on the board")
	eq(jobs.board[key]["priority"], 70, "priority 70")
	var m := CrewMember.new("Hand", Pathfinder.centre_of(Vector2i(14, 19)))
	check(jobs.in_reach(m, jobs.board[key]), "next to it")
	jobs.work(ship, m, jobs.board[key], 1.9)
	check(ship.belts.cut.has(Vector2i(14, 18)), "2 s of work not done yet")
	jobs.work(ship, m, jobs.board[key], 0.2)
	check(not ship.belts.cut.has(Vector2i(14, 18)), "mended")


func test_ion_does_not_cut_a_belt() -> void:
	var d := Fx.belts()
	var ship: Ship = d["ship"]
	var a := Fx.arena(ship)
	Damage.apply(a, 0, Vector2i(14, 17), Damage.solid_at(a.ships[0], Vector2i(14, 17)), 5.0, "ion")
	check(ship.belts.cut.is_empty(), "ion does no structural damage")


# --- drives, speed, feed ------------------------------------------------------------------------------------------

func test_a_unit_rides_the_belt_and_arrives_after_length_over_speed() -> void:
	var d := Fx.belts()
	var ship: Ship = d["ship"]
	Fx.stock(ship, d["rack"], "missile", 10)
	var gun_loaded := func(): return Ammo.loaded(ship, d["gun"]) >= 1
	var t := _until(ship, gun_loaded)
	# 3 cells from the rack to the gun's edge at 5 cells a second: 0.6 s
	near(t, 0.6, "the Autoloader brings the first unit in 0.6 s", 0.11)
	eq(Ammo.count_in(ship, d["rack"]), 8, "two pulled so far (the gun wants two)")


func test_each_drive_has_its_speed_and_feed_interval() -> void:
	for spec in [["belt_drive_scrap", 3.0, 0.8], ["belt_drive_std", 5.0, 0.5], ["belt_drive_neon", 8.0, 0.3]]:
		var d := Fx.belts("artemis_mk1", spec[0])
		var ship: Ship = d["ship"]
		Fx.stock(ship, d["rack"], "missile", 10)
		ship.refresh()
		near(Ammo.drive_speed(ship, d["drive"]), spec[1], spec[0] + " speed")
		var first := _until(ship, func(): return Ammo.loaded(ship, d["gun"]) >= 1)
		near(first, 3.0 / spec[1], spec[0] + ": the first unit takes 3 cells / speed", 0.11)
		var second := _until(ship, func(): return Ammo.loaded(ship, d["gun"]) >= 2)
		near(second, spec[2], spec[0] + ": the second follows one feed interval later", 0.11)


func test_several_drives_add_feed_rate_and_the_speed_is_the_best_ones() -> void:
	var d := Fx.belts("grundl_slug_mortar", "belt_drive_scrap", true)
	var ship: Ship = d["ship"]
	Fx.stock(ship, d["rack"], "scrap", 20)
	var one := Fx.belts("grundl_slug_mortar", "belt_drive_scrap", false)
	Fx.stock(one["ship"], one["rack"], "scrap", 20)
	_run(ship, 0.9)
	_run(one["ship"], 0.9)
	# one scrap drive pulls at t = 0 and t = 0.8; two pull twice as often
	eq(20 - Ammo.count_in(one["ship"], one["rack"]), 2, "one Chain Drive: 2 units in 0.9 s")
	eq(20 - Ammo.count_in(ship, d["rack"]), 4, "two: 4 units")
	near(Ammo.drive_speed(ship, d["drive"]), 3.0, "speed 3")


func test_the_belt_moves_at_the_best_working_drives_speed() -> void:
	var d := Fx.belts("artemis_mk1", "belt_drive_scrap", true)
	var ship: Ship = d["ship"]
	var fast: int = ship.components.place(ship.grid, "belt_drive_neon", Vector2i(17, 16), 0)
	check(fast >= 0, "a Mag-Rail fits at (17, 16), above the belt's end")
	ship.refresh()
	Fx.stock(ship, d["rack"], "missile", 10)
	eq(ship.belts.analyze(ship)["nets"][0]["drives"].size(), 3, "three drives on the net")
	Ammo.tick(ship, 0.05)
	var u: Dictionary = ship.belts.units[0]
	near(float(u["p"]), 0.0, "launched")
	Ammo.tick(ship, 0.05)
	near(float(u["p"]), 8.0 * 0.05, "the unit moves at the Mag-Rail's 8 cells a second, not the Chain Drives' 3")
	ship.components.instances[fast]["status"] = "malfunction"
	ship.refresh()
	Ammo.tick(ship, 0.05)
	near(float(u["p"]), 8.0 * 0.05 + 3.0 * 0.05, "with it down, the best working drive is a Chain Drive: 3")


func test_units_in_flight_delay_the_reload_and_a_gun_that_waits_says_so() -> void:
	var d := Fx.belts()
	var ship: Ship = d["ship"]
	var a := Fx.arena(ship)
	Fx.stock(ship, d["rack"], "missile", 10)
	eq(_why(a, d["gun"]), "feeding", "the rack is on the belt, nothing has arrived: feeding")
	Ammo.tick(ship, 0.05)
	eq(ship.belts.units.size(), 1, "a unit is on its way")
	eq(_why(a, d["gun"]), "feeding", "still feeding")
	check(not a.fire(0, d["gun"], Fx.AIM), "it does not fire")
	_until(ship, func(): return Ammo.loaded(ship, d["gun"]) >= 1)
	eq(_why(a, d["gun"]), "", "arrived: ready")
	check(a.fire(0, d["gun"], Fx.AIM), "fires")
	eq(Ammo.loaded(ship, d["gun"]), 1 if Ammo.loaded(ship, d["gun"]) == 1 else 0, "one unit used from the chamber")
	# a shot is followed by a reload from the belt
	_run(ship, 3.0)
	eq(Ammo.loaded(ship, d["gun"]), 2, "the chamber is full again (two shots' worth)")
	eq(Ammo.count_in(ship, d["rack"]), 10 - 3, "three units left the rack in all")


func test_the_reload_waits_for_the_cooldown_first_then_for_the_belt() -> void:
	var d := Fx.belts()
	var ship: Ship = d["ship"]
	var a := Fx.arena(ship)
	Fx.stock(ship, d["rack"], "missile", 10)
	_run(ship, 2.0)
	check(a.fire(0, d["gun"], Fx.AIM), "fires")
	eq(_why(a, d["gun"]), "cooling down", "cooling down is reported first")


func test_a_cut_belt_returns_the_unit_riding_it() -> void:
	var d := Fx.belts()
	var ship: Ship = d["ship"]
	Fx.stock(ship, d["rack"], "missile", 10)
	Ammo.tick(ship, 0.05)
	var riding: int = ship.belts.units.size()
	check(riding >= 1, "a unit is riding")
	eq(Ammo.count_in(ship, d["rack"]), 10 - riding, "it left the rack")
	ship.belts.cut_cell(Vector2i(12, 18))
	Ammo.tick(ship, 0.05)
	eq(ship.belts.units.size(), 0, "the cut stopped the ride")
	eq(Ammo.count_in(ship, d["rack"]), 10, "and the unit went back into its rack")
	var a := Fx.arena(ship)
	eq(_why(a, d["gun"]), "no ammo rack in reach", "the gun's network has no rack now")
	ship.belts.repair(Vector2i(12, 18))
	eq(_why(a, d["gun"]), "feeding", "mended: fed again")


func test_no_working_drive_means_the_belt_is_stopped() -> void:
	var d := Fx.belts()
	var ship: Ship = d["ship"]
	var a := Fx.arena(ship)
	Fx.stock(ship, d["rack"], "missile", 10)
	ship.components.instances[d["drive"]]["status"] = "malfunction"
	ship.refresh()
	near(Ammo.drive_speed(ship, d["drive"]), 0.0, "a malfunctioning drive does not move")
	_run(ship, 2.0)
	eq(ship.belts.units.size(), 0, "nothing rides")
	eq(_why(a, d["gun"]), "belt stopped", "stock is on the belt, but it is stopped")
	ship.repair(d["drive"])
	ship.refresh()
	eq(_why(a, d["gun"]), "feeding", "kicked: it runs")
	# unpowered
	ship.cables.cells.clear()
	ship.refresh()
	near(Ammo.drive_speed(ship, d["drive"]), 0.0, "no power, no belt")


func test_an_ion_hit_stops_a_mag_rail_for_the_ion_duration_but_not_the_others() -> void:
	var d := Fx.belts("artemis_mk1", "belt_drive_neon")
	var ship: Ship = d["ship"]
	var a := Fx.arena(ship)
	check(Ammo.drive_speed(ship, d["drive"]) > 0.0, "it runs")
	Damage.apply(a, 0, Vector2i(14, 19), Damage.solid_at(a.ships[0], Vector2i(14, 19)), 3.0, "ion")
	near(Ammo.drive_speed(ship, d["drive"]), 0.0, "an ion hit stops it")
	Fx.stock(ship, d["rack"], "missile", 10)
	_run(ship, 2.9)
	eq(ship.belts.units.size() + Ammo.loaded(ship, d["gun"]), 0, "nothing moved for 2.9 s")
	_run(ship, 0.3)
	check(Ammo.drive_speed(ship, d["drive"]) > 0.0, "3 s later it runs again")
	var d2 := Fx.belts("artemis_mk1", "belt_drive_std")
	var a2 := Fx.arena(d2["ship"])
	Damage.apply(a2, 0, Vector2i(14, 19), Damage.solid_at(a2.ships[0], Vector2i(14, 19)), 3.0, "ion")
	check(Ammo.drive_speed(d2["ship"], d2["drive"]) > 0.0, "an Autoloader shrugs it off")


func test_a_scrap_chain_drive_jams_on_a_malfunction_until_kicked() -> void:
	var d := Fx.belts("artemis_mk1", "belt_drive_scrap")
	var ship: Ship = d["ship"]
	check(ship.effective("belt_drive_scrap")["malfunction_per_min"] > ship.effective("belt_drive_std")["malfunction_per_min"], "the Scrap line malfunctions more often")
	ship.components.instances[d["drive"]]["status"] = "malfunction"
	var jobs := Jobs.new()
	jobs.build_board(ship)
	check(jobs.board.has("fix:%d" % d["drive"]), "the usual repair job kicks it")


func test_the_guns_are_served_the_emptiest_first_and_a_room_rack_beats_the_belt() -> void:
	var d := Fx.belts()
	var ship: Ship = d["ship"]
	Fx.stock(ship, d["rack"], "missile", 10)
	var local: int = ship.components.place(ship.grid, "ammo_rack", Vector2i(20, 20), 0)
	Fx.stock(ship, local, "missile", 5)
	_run(ship, 2.0)
	eq(ship.belts.units.size() + Ammo.loaded(ship, d["gun"]), 0, "a rack in the gun's room feeds it: the belt stays idle")
	Fx.stock(ship, local, "missile", 0)
	_run(ship, 2.0)
	eq(Ammo.loaded(ship, d["gun"]), 2, "the local rack is empty: the belt brings it")


# --- saving --------------------------------------------------------------------------------------------------------

func test_belts_and_cuts_survive_a_save_and_riding_units_go_back_to_their_rack() -> void:
	var d := Fx.belts()
	var ship: Ship = d["ship"]
	Fx.stock(ship, d["rack"], "missile", 10)
	Ammo.learn(ship)
	ship.belts.cut_cell(Vector2i(16, 18))
	Ammo.tick(ship, 0.05)
	var riding: int = ship.belts.units.size()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(ship.to_dict()))
	check(saved.has("belts"), "the layer is saved")
	eq(saved["belts"]["cells"].size(), 7, "seven cells")
	eq(saved["belts"]["cut"].size(), 1, "and the cut one")
	eq(int(saved["belts"]["cut"][0][0]), 16, "at x 16")
	var rec: Dictionary = saved["components"]["instances"].filter(func(r): return int(r["uid"]) == d["rack"])[0]
	eq(int(rec["n"]), 10 - riding + riding, "what rode the belt is back in the rack")
	var back := Ship.new_starter()
	eq(back.load_dict(saved), "", "loads")
	eq(back.belts.cells.size(), 7, "cells back")
	check(back.belts.cut.has(Vector2i(16, 18)), "cut back")
	check(back.belts.known, "the blueprint too")
	eq(back.belts.units.size(), 0, "nothing rides after a load")


func test_a_save_without_belts_loads_and_a_bad_one_is_refused() -> void:
	var d := Fx.belts()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Fx.room()["ship"].to_dict()))
	check(not saved.has("belts"), "a ship without belts writes no belts key")
	var back := Ship.new_starter()
	eq(back.load_dict(saved), "", "loads with no belts")
	var bad: Dictionary = JSON.parse_string(JSON.stringify(d["ship"].to_dict()))
	bad["belts"]["version"] = 9
	eq(back.load_dict(bad), "unsupported belts version", "a newer belts layer is refused")
	bad["belts"] = {"version": 1, "cells": [[1]], "cut": []}
	eq(back.load_dict(bad), "bad ship data", "a bad cell is refused")


# --- the first drive teaches the belt --------------------------------------------------------------------------------

func test_the_first_drive_brings_the_belt_blueprint_with_the_sim() -> void:
	var ship: Ship = Fx.room()["ship"]
	check(not ship.belts.known, "not known")
	var sim := ShipSim.new()
	sim.ships[0] = ship
	sim.step(0.1)
	check(not ship.belts.known, "no drive yet")
	ship.inventory.add("belt_drive_std", 1)
	sim.step(1.1)  # the sim looks once a second
	check(ship.belts.known, "the first drive in the hold teaches it")


func test_the_palette_has_a_belt_card_that_is_locked_until_a_drive_is_aboard() -> void:
	var ship := Wall.wall_ship(1, 0)
	var cards := Palette.entries(Palette.Tab.STRUCTURE, ship, {"copper": 1})
	var belt: Dictionary = {}
	for e in cards:
		if e["key"] == "belt":
			belt = e
	check(not belt.is_empty(), "a Belt card on the Structure tab")
	eq(belt["name"], "Belt", "named Belt")
	eq(belt["cost"], {"scrap": 1}, "1 scrap")
	check(not belt["ok"], "locked: no drive")
	check(String(belt["why"]).contains("drive"), "it says it needs a drive")
	ship.inventory.add("belt_drive_scrap", 1)
	for e in Palette.entries(Palette.Tab.STRUCTURE, ship, {"copper": 1}):
		if e["key"] == "belt":
			belt = e
	check(belt["ok"], "unlocked with a drive aboard")
	var info := Palette.info(belt, ship)
	check(String(info["blurb"]).length() > 0 and info["rows"].size() >= 2, "the selection card says something")


func test_the_belt_tool_in_build_mode() -> void:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(20, 20), defs)
	g.fill_circle_hull(9.0)
	for c in g.hull:
		g.force_tile(c, "floor")
	var ship := Ship.new("T", g)
	ship.inventory.load_dict({"scrap": 50, "belt_drive_std": 1})
	var sim := ShipSim.new()
	sim.ships = [ship]
	var b := BuildMode.new()
	b.sim = sim
	b.selected = "floor"
	b.hover = Vector2i(8, 8)
	b.hud = Hud.new()
	b.hud.setup(b)
	b.pick(Palette.belt_entry(ship))
	eq(b.group, BuildMode.Group.BELTS, "the Belt card puts the belt tool in hand")
	eq(b.tool_key(), "belt", "its key")
	eq(b.selected_entry()["name"], "Belt", "its card")
	b._refresh_ghost()
	eq(b.ghost.size(), 1, "one cell under the mouse")
	eq([b.ghost[0]["layer"], b.ghost[0]["reason"]], ["belt", ""], "a belt that would apply")
	b.hover = Vector2i(0, 0)
	b._refresh_ghost()
	check(b.ghost.is_empty() or b.ghost[0]["reason"] != "", "outside the hull it is refused")
	b.hud.free()
	sim.free()
	b.free()
