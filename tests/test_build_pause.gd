extends "res://tests/base_test.gd"
## Build mode pauses the world (ShipSim.set_paused, set by BuildMode): crew, jobs, fires, oxygen, heat,
## malfunctions, crafting, abilities and the ships' clock stand still; leaving it recomputes the rooms and the
## air and moves crew who stand in a wall or in a sealed pocket (ShipSim.relocate_crew).

const BuildMode = preload("res://scripts/build/build_mode.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Workshop = preload("res://scripts/craft/workshop.gd")

const KICKJET := "engine_scrap_mk1"  ## 16 scrap, level 1, 20 s


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## The test room with a reactor, a fabricator (crafting a Kickjet), an oxygen generator on one cable, a fire at
## (19, 14), half-empty air, a crew member at (12, 15) and a hand-me-down heat on the reactor.
func _world() -> Dictionary:
	var ship := Fixture.room_ship()
	var d := {"ship": ship}
	d["reactor"] = Fixture.put(ship, "reactor_mk1", 10, 10)
	d["fab"] = Fixture.put(ship, "fabricator", 15, 10)
	d["gen"] = Fixture.put(ship, "oxygen_gen", 15, 12)
	Fixture.wire(ship, [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11), Vector2i(15, 12)])
	ship.refresh()
	for i in ship.atmosphere.pressure.size():
		ship.atmosphere.pressure[i] = 0.5
	ship.fires[Vector2i(19, 14)] = 0.9
	ship.components.instances[d["reactor"]]["heat"] = 40.0
	var hand := CrewMember.new("Ada", Vector2(12.0, 15.0))
	ship.crew.append(hand)
	ship.crafting.enqueue(KICKJET, ship.inventory, Workshop.best(ship))
	var sim := ShipSim.new()
	sim.ships = [ship]
	d["sim"] = sim
	d["hand"] = hand
	return d


## Everything the sim moves, as one value to compare.
func _snap(ship: Ship) -> Dictionary:
	var parts := []
	for uid in ship.components.instances:
		var i: Dictionary = ship.components.instances[uid]
		parts.append([uid, i["heat"], i["hp"], i["status"]])
	return {
		"clock": ship.clock, "fires": ship.fires.duplicate(), "air": ship.atmosphere.pressure.duplicate(),
		"parts": parts, "crew": ship.crew.map(func(m): return [m.name, m.pos, m.hp, m.path.duplicate(), m.job.duplicate()]),
		"crafting": ship.crafting.to_dict(), "cargo": ship.inventory.to_dict(), "abilities": ship.ability_state.duplicate(true),
		"events": ship.events.size(),
	}


func _run(sim: ShipSim, seconds: float, step := 0.1) -> void:
	for i in roundi(seconds / step):
		sim.step(step)


func test_build_mode_stops_every_tick_of_the_sim() -> void:
	var d := _world()
	var ship: Ship = d["ship"]
	var sim: ShipSim = d["sim"]
	var build := BuildMode.new()
	build.sim = sim
	check(build.build_on and sim.paused, "build mode (the start) pauses the sim")
	eq(sim.pause_line(), "PAUSED: build mode", "and the HUD line says so")
	var before := _snap(ship)
	_run(sim, 10.0)
	var after := _snap(ship)
	for k in before:
		eq(after[k], before[k], "%s stands still over 10 s of build mode" % k)
	near(ship.clock, 0.0, "the game clock did not advance")
	build.build_on = false
	check(not sim.paused and sim.pause_line() == "", "play mode runs it")
	_run(sim, 10.0)
	var played := _snap(ship)
	near(ship.clock, 10.0, "the clock runs in play mode", 1e-6)
	check(played["fires"] != before["fires"], "the fire burns (%s)" % str(played["fires"]))
	check(played["air"] != before["air"], "the air moves (%s)" % str(played["air"]))
	check(played["parts"] != before["parts"], "the parts heat up")
	check(played["crew"] != before["crew"], "the crew walk and work")
	check(played["crafting"] != before["crafting"], "the fabricator crafts (%s)" % str(played["crafting"]))
	build.build_on = true
	var again := _snap(ship)
	_run(sim, 10.0)
	eq(_snap(ship), again, "back in build mode it stands still again")
	build.free()
	sim.free()


func test_abilities_wait_in_build_mode() -> void:
	var ship := Fixture.room_ship()
	var reactor := Fixture.put(ship, "reactor_mk1", 10, 10)
	var engine := Fixture.put(ship, KICKJET, 15, 10, 2)
	Fixture.wire(ship, [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.refresh()
	check(reactor > 0 and engine > 0, "the rig")
	eq(Abilities.trigger(ship, engine), "", "the engine ability is on")
	var left := Abilities.active_left(ship, engine, "sputter_boost")
	check(left > 3.0, "for a few seconds (%f)" % left)
	var sim := ShipSim.new()
	sim.ships = [ship]
	sim.set_paused(true, "build mode")
	_run(sim, 3.0)
	near(Abilities.active_left(ship, engine, "sputter_boost"), left, "it does not count down while paused")
	sim.set_paused(false)
	_run(sim, 1.0)
	near(Abilities.active_left(ship, engine, "sputter_boost"), left - 1.0, "and does once the world runs", 0.11)
	sim.free()


func test_a_paused_sim_still_keeps_the_rooms_and_the_power_up_to_date() -> void:
	var d := _world()
	var ship: Ship = d["ship"]
	var sim: ShipSim = d["sim"]
	sim.set_paused(true, "build mode")
	var rooms := ship.atmosphere.rooms.size()
	BuildSession.new(ship).apply(BuildSession.room_changes(Vector2i(17, 12), Vector2i(21, 16), "wall", "floor"))
	sim.step(0.1)
	check(ship.atmosphere.rooms.size() > rooms, "a wall built while paused makes its room (%d rooms)" % ship.atmosphere.rooms.size())
	ship.cables.cells.clear()
	ship.mark_dirty()
	sim.step(0.1)
	check(not ship.power_state["powered"][d["fab"]], "and cutting the cable shows in the power")
	sim.free()


func test_leaving_build_mode_moves_crew_out_of_walls_and_sealed_pockets() -> void:
	var ship := Fixture.room_ship()
	var sim := ShipSim.new()
	sim.ships = [ship]
	var build := BuildMode.new()
	build.sim = sim
	var walled := CrewMember.new("Walled", Vector2(12.0, 14.0))  # a wall goes up on top of them
	var sealed := CrewMember.new("Sealed", Vector2(19.0, 14.0))  # a room goes up round them
	var fine := CrewMember.new("Fine", Vector2(13.0, 10.0))
	ship.crew.append_array([walled, sealed, fine])
	var home := ship.atmosphere.rooms.size()
	var session := BuildSession.new(ship)
	session.apply(BuildSession.room_changes(Vector2i(17, 12), Vector2i(21, 16), "wall", "floor"))  # interior x 18..20, y 13..15
	session.apply([{"layer": "tile", "cell": Vector2i(12, 14), "to": "wall"}])
	check(not walled.fits(ship.grid, walled.pos, Callable(), CrewMember.RADIUS - 0.01), "(the wall is on top of Walled)")
	var was := [walled.pos, sealed.pos, fine.pos]
	_run(sim, 5.0)
	eq([walled.pos, sealed.pos, fine.pos], was, "nobody moves while the world is paused")
	build.build_on = false
	check(walled.fits(ship.grid, walled.pos, Callable(), CrewMember.RADIUS - 0.01), "Walled stands clear of the wall again")
	check(ship.grid.get_tile(Pathfinder.anchor_of(walled.pos)) == "floor", "on floor")
	check(walled.pos.distance_to(was[0]) < 4.0, "near where they were: %s" % str(walled.pos))
	var from_sealed := Pathfinder.find_path(ship.grid, Pathfinder.anchor_of(sealed.pos), Pathfinder.anchor_of(fine.pos))
	check(not from_sealed.is_empty(), "Sealed can walk to the rest of the ship")
	check(sealed.pos.distance_to(was[1]) < 8.0, "from the nearest floor outside their pocket: %s" % str(sealed.pos))
	eq(fine.pos, was[2], "Fine stays where they stood")
	check(ship.atmosphere.rooms.size() > home, "the rooms were recomputed (%d)" % ship.atmosphere.rooms.size())
	check(ship.events.any(func(e): return e["text"].begins_with("Crew moved clear of the rebuild") and "Walled" in e["text"] and "Sealed" in e["text"]), "the chronicle says who moved: %s" % str(ship.events))
	eq(ShipSim.relocate_crew(ship), 0, "a second pass moves nobody")
	build.free()
	sim.free()


func test_a_crew_member_with_nowhere_to_stand_goes_to_the_helm_room() -> void:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	var ship := Ship.new("Closet", g)
	for c in [Vector2i(10, 12), Vector2i(11, 12), Vector2i(10, 13), Vector2i(11, 13)]:
		g.force_tile(c, "floor")
	for x in range(12, 18):
		g.force_tile(Vector2i(x, 12), "floor")  # a corridor one cell wide: no body walks it
	var helm := Fixture.put(ship, "helm", 10, 12)
	check(helm > 0, "a helm at the end of the corridor")
	g.force_tile(Vector2i(11, 13), "wall")  # and a wall on a corner of the helm: no 2x2 floor anywhere
	ship.mark_dirty()
	ship.refresh()
	var m := CrewMember.new("Stuck", Vector2(16.5, 12.5))
	ship.crew.append(m)
	eq(ShipSim.relocate_crew(ship), 1, "the one crew member is moved")
	var room: int = ship.atmosphere.room_at(Vector2i(10, 12))
	check(room >= 0 and ship.atmosphere.room_at(m.cell()) == room and m.cell() == Vector2i(10, 12), "to the cell of the helm's room by the helm: %s" % str(m.pos))


func test_crew_stay_put_when_nothing_changed() -> void:
	var d := _world()
	var ship: Ship = d["ship"]
	var sim: ShipSim = d["sim"]
	var where: Vector2 = d["hand"].pos
	sim.set_paused(true, "build mode")
	sim.set_paused(false)
	eq(d["hand"].pos, where, "an untouched ship moves nobody")
	eq(ship.events.filter(func(e): return e["text"].begins_with("Crew moved")).size(), 0, "and says nothing")
	sim.free()
