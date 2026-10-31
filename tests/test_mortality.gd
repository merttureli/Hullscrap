extends "res://tests/base_test.gd"
## Bleeding out (scripts/crew/mortality.gd): a downed crew member dies after crew.json bleed_out_s (45 s) unless a
## crewmate is working a revive on them or a powered, working medbay is in their room; the player's soldier never dies.

const Fixture = preload("res://tests/fixture_ship.gd")
const Mortality = preload("res://scripts/crew/mortality.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const RAIDER := "res://data/ships/pirate_raider.json"


## A person whose 2x2 body has its top-left cell on (x, y).
func _npc(p_name: String, x: int, y: int) -> CrewMember:
	return CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y)))


func _down(m: CrewMember) -> CrewMember:
	m.hurt(1000.0)
	return m


## Tick `seconds` in steps of 1 s; returns the chronicle lines of the whole span.
func _run(ship: Ship, seconds: int) -> Array:
	var lines := []
	for i in seconds:
		lines.append_array(Mortality.tick(ship, 1.0))
	return lines


## A room ship with a medbay at x 10..13, y 10..13; powered by a reactor next to it when `power`.
func _medbay_ship(power: bool) -> Ship:
	var ship := Fixture.room_ship()
	Fixture.put(ship, "medbay", 10, 10)
	if power:
		Fixture.put(ship, "reactor_mk1", 15, 10)
		Fixture.wire(ship, [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.refresh()
	return ship


func near(got: float, want: float, msg: String, eps := 1e-6) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, want, got])


func test_the_bleed_out_time_is_45_seconds_in_the_data() -> void:
	near(Mortality.bleed_out_s(), 45.0, "data/crew.json bleed_out_s")
	check(str(CrewMember.config()["_doc"]).contains("bleed_out_s"), "and the _doc says what it is")


func test_a_downed_member_dies_at_45_seconds() -> void:
	var ship := Fixture.room_ship()
	var rook := _down(_npc("Rook", 18, 12))
	ship.crew.append(rook)
	eq(_run(ship, 44), [], "nothing for 44 s")
	near(rook.down_t, 44.0, "the timer counted")
	check(ship.crew.has(rook), "still aboard")
	var lines := _run(ship, 1)
	eq(lines, ["Rook has died."], "at 45 s the chronicle line")
	check(not ship.crew.has(rook), "and Rook is off the ship")
	eq(ship.dead_crew, ["Rook"], "the ship remembers")


func test_back_above_zero_hp_the_timer_starts_over() -> void:
	var ship := Fixture.room_ship()
	var rook := _down(_npc("Rook", 18, 12))
	ship.crew.append(rook)
	_run(ship, 30)
	near(rook.down_t, 30.0, "30 s down")
	rook.heal(20.0)
	_run(ship, 1)
	near(rook.down_t, 0.0, "up: back to 0")
	rook.hurt(1000.0)
	_run(ship, 40)
	check(ship.crew.has(rook), "down again, 40 s is not 45")


func test_a_revive_in_progress_pauses_the_timer() -> void:
	var ship := Fixture.room_ship()
	var rook := _down(_npc("Rook", 18, 12))
	var ada := _npc("Ada", 20, 12)  # right beside him
	ada.job = {"key": "revive:Rook", "type": "revive", "who": "Rook", "cells": rook.body_cells(), "label": "reviving Rook"}
	ship.crew.append_array([rook, ada])
	rook.down_t = 10.0
	_run(ship, 100)
	near(rook.down_t, 10.0, "100 s with Ada at work on him: the timer stood still")
	check(ship.crew.has(rook), "alive")
	ada.job = {}
	_run(ship, 34)
	check(ship.crew.has(rook), "34 s more is 44 in all")
	eq(_run(ship, 1), ["Rook has died."], "and the next second takes him")


func test_a_rescuer_who_is_still_walking_or_down_does_not_pause_it() -> void:
	var ship := Fixture.room_ship()
	var rook := _down(_npc("Rook", 18, 12))
	var ada := _npc("Ada", 10, 12)
	ada.job = {"key": "revive:Rook", "type": "revive", "who": "Rook", "cells": rook.body_cells()}
	ada.path = [Vector2i(16, 12)]  # on her way
	ship.crew.append_array([rook, ada])
	_run(ship, 10)
	near(rook.down_t, 10.0, "still walking: the clock runs")
	ada.path.clear()  # no path left but still far from him: not working on him yet
	_run(ship, 5)
	near(rook.down_t, 15.0, "too far to touch: the clock runs")
	ada.pos = Pathfinder.centre_of(Vector2i(20, 12))
	_run(ship, 5)
	near(rook.down_t, 15.0, "beside him: it stops")
	ada.hurt(1000.0)  # the rescuer goes down herself
	_run(ship, 5)
	near(rook.down_t, 20.0, "a downed rescuer saves nobody")


func test_a_revive_job_run_by_the_real_board_stops_the_clock_until_he_is_up() -> void:
	var ship := Fixture.room_ship()
	var rook := _down(_npc("Rook", 12, 12))
	var ada := _npc("Ada", 14, 12)  # right beside him: in reach
	ship.crew.append_array([rook, ada])
	rook.down_t = 20.0
	var jobs := Jobs.new()
	jobs.tick(ship, 0.1)  # the board is built, Ada takes the revive and starts the work
	eq(ada.job.get("key"), "revive:Rook", "Ada took the revive")
	check(ada.path.is_empty(), "and she is at his side")
	Mortality.tick(ship, 1.0)
	near(rook.down_t, 20.0, "the work is in progress: no bleeding")
	for i in 60:
		jobs.tick(ship, 0.1)
		Mortality.tick(ship, 0.1)
	check(not rook.is_down(), "she got him up (3 s of work)")
	near(rook.down_t, 0.0, "and the timer is cleared")


func test_a_powered_medbay_in_the_room_pauses_the_timer() -> void:
	var ship := _medbay_ship(true)
	var rook := _down(_npc("Rook", 18, 12))  # in the room, not on the medbay itself
	ship.crew.append(rook)
	rook.down_t = 7.0
	_run(ship, 200)
	near(rook.down_t, 7.0, "a medbay that is on: the timer stood still")
	check(ship.crew.has(rook), "alive")


func test_an_unpowered_or_broken_medbay_does_not() -> void:
	var cold := _medbay_ship(false)
	var rook := _down(_npc("Rook", 18, 12))
	cold.crew.append(rook)
	eq(_run(cold, 45), ["Rook has died."], "no power: he dies")
	var ship := _medbay_ship(true)
	for inst in ship.components.instances.values():
		if inst["id"] == "medbay":
			inst["status"] = "disabled"
	var juno := _down(_npc("Juno", 18, 12))
	ship.crew.append(juno)
	eq(_run(ship, 45), ["Juno has died."], "a disabled medbay: he dies")


func test_the_soldier_never_dies() -> void:
	var ship := Fixture.room_ship()
	var soldier := _down(_npc("Soldier", 18, 12))
	soldier.is_player = true
	ship.crew.append(soldier)
	eq(_run(ship, 300), [], "no lines")
	check(ship.crew.has(soldier) and soldier.is_down(), "he just stays down")
	near(Mortality.bleed_frac(soldier), 0.0, "and no ring is drawn for him")


func test_the_ring_fraction_grows_with_the_time_down() -> void:
	var ship := Fixture.room_ship()
	var rook := _npc("Rook", 18, 12)
	ship.crew.append(rook)
	near(Mortality.bleed_frac(rook), 0.0, "standing: 0")
	rook.hurt(1000.0)
	_run(ship, 9)
	near(Mortality.bleed_frac(rook), 0.2, "9 of 45 s")
	_run(ship, 18)
	near(Mortality.bleed_frac(rook), 0.6, "27 of 45 s")


func test_an_enemy_crew_dies_the_same_way_through_the_ship_sim() -> void:
	var sim := ShipSim.new()
	sim.choose_ship(RUSTBUCKET)
	Jobs.spawn_crew(sim.player_ship())
	var enemy: Ship = Ship.from_design(RAIDER)
	sim.ships.append(enemy)
	sim.step(0.1)  # the enemy's crew is spawned on its first tick
	eq(enemy.crew.size(), 3, "three aboard")
	for m in enemy.crew:
		m.hurt(1000.0)  # all down, so nobody can revive anyone
	for i in 47:
		sim.step(1.0)
	eq(enemy.crew.size(), 0, "all three bled out")
	eq(enemy.dead_crew.size(), 3, "and are on the list")
	check(enemy.events.any(func(e): return e["text"] == "Grub has died."), "the enemy's chronicle says so")
	check(sim.player_ship().crew.size() >= 2, "the player's crew is untouched")
	sim.free()


func test_a_death_leaves_the_crew_the_stations_and_the_jobs_and_stays_dead() -> void:
	var sim := ShipSim.new()
	sim.choose_ship(RUSTBUCKET)
	var ship: Ship = sim.player_ship()
	Jobs.spawn_crew(ship)
	var names: Array = ship.crew.map(func(m): return m.name)
	check(names.has("Rook") and names.has("Ada"), "the Rustbucket carries Rook and Ada")
	var rook: CrewMember = ship.crew.filter(func(m): return m.name == "Rook")[0]
	var ada: CrewMember = ship.crew.filter(func(m): return m.name == "Ada")[0]
	ship.manned[3] = "Rook"
	ship.manned[4] = "Ada"
	ada.job = {"key": "revive:Rook", "type": "revive", "who": "Rook", "cells": rook.body_cells()}
	ada.path = [Vector2i(40, 40)]  # far off
	rook.job = {"key": "man_station:3", "type": "man_station", "uid": 3}
	rook.hurt(1000.0)
	rook.down_t = 44.5
	var lines := Mortality.tick(ship, 1.0)
	eq(lines, ["Rook has died."], "he dies")
	check(not ship.crew.has(rook), "off the crew")
	check(not ship.manned.has(3) and ship.manned.get(4) == "Ada", "off his station, Ada's stays")
	check(ada.job.is_empty() and ada.path.is_empty(), "Ada is no longer sent to save him")
	check(rook.job.is_empty(), "and his own job is gone")
	var jobs := Jobs.new()
	jobs.build_board(ship)
	check(not jobs.board.has("revive:Rook"), "the board has no revive for him")
	eq(Jobs.spawn_crew(ship).map(func(m): return m.name), [], "the starting-crew spawn does not bring him back")
	check(not ship.crew.any(func(m): return m.name == "Rook"), "still dead")
	sim.free()


func test_a_dead_ada_is_not_respawned_either() -> void:
	var ship: Ship = Ship.from_design("res://data/ships/starter_courier.json")
	Jobs.spawn_crew(ship)
	var ada: CrewMember = ship.crew.filter(func(m): return m.name == "Ada")[0]
	_down(ada).down_t = 44.5
	Mortality.tick(ship, 1.0)
	eq(Jobs.spawn_crew(ship), [], "nothing spawns")
	check(not ship.crew.any(func(m): return m.name == "Ada"), "Ada stays dead")
	var plain := Fixture.room_ship()  # no crew list: the default crew of the soldier, Ada and two more
	var made := Jobs.spawn_crew(plain)
	var extras: int = made.filter(func(m): return not m.is_player and m.name != "Ada").size()
	var first_extra: CrewMember = made.filter(func(m): return not m.is_player and m.name != "Ada")[0]
	_down(first_extra).down_t = 99.0
	Mortality.tick(plain, 1.0)
	eq(Jobs.spawn_crew(plain), [], "the default crew does not refill either (%d extras)" % extras)


func test_nobody_bleeds_while_the_world_is_paused() -> void:
	var sim := ShipSim.new()
	var ship := Fixture.room_ship()
	sim.ships = [ship]
	var rook := _down(_npc("Rook", 18, 12))
	var juno := _down(_npc("Juno", 12, 12))  # all down, so nobody can revive anyone
	ship.crew.append_array([rook, juno])
	sim.set_paused(true, "build mode")
	for i in 60:
		sim.step(1.0)
	near(rook.down_t, 0.0, "a minute in build mode: no bleeding")
	check(ship.crew.has(rook), "nobody died")
	sim.set_paused(false)
	for i in 46:
		sim.step(1.0)
	check(not ship.crew.has(rook) and not ship.crew.has(juno), "unpaused, the clock runs and they die")
	sim.free()
