extends "res://tests/base_test.gd"
## Heat, overheating and radiators (scripts/sim/heat.gd).

const Fixture = preload("res://tests/fixture_ship.gd")
const Heat = preload("res://scripts/sim/heat.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const REACTOR_CABLE: Array[Vector2i] = [Vector2i(11, 11)]
const RADIATOR_CABLES: Array[Vector2i] = [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11), Vector2i(15, 12)]


## A room with a Prism Core (x 10..13, y 10..13) and `radiators` radiators (2x2 at x 15..16), all on one cable.
func _prism(radiators: int) -> Dictionary:
	var ship := Fixture.room_ship()
	var out := {"ship": ship, "reactor": Fixture.put(ship, "reactor_neon_mk1", 10, 10), "radiators": []}
	check(out["reactor"] > 0, "reactor placed")
	Fixture.wire(ship, REACTOR_CABLE)
	if radiators > 0:
		out["radiators"].append(Fixture.put(ship, "radiator", 15, 10))
		Fixture.wire(ship, RADIATOR_CABLES)
	if radiators > 1:
		out["radiators"].append(Fixture.put(ship, "radiator", 15, 12))
	ship.refresh()
	return out


## Tick once a second until the reactor overheats; the second it happened, or -1 after `limit` seconds.
func _seconds_to_overheat(d: Dictionary, limit: int) -> int:
	var ship = d["ship"]
	for s in range(1, limit + 1):
		Heat.tick(ship, 1.0)
		if ship.components.instances[d["reactor"]]["status"] == "overheated":
			return s
	return -1


func test_a_neon_reactor_without_a_radiator_overheats_within_20_seconds() -> void:
	var d := _prism(0)
	var t := _seconds_to_overheat(d, 20)
	check(t > 0 and t <= 20, "overheated after %d s" % t)
	var inst: Dictionary = d["ship"].components.instances[d["reactor"]]
	eq(inst["heat"], 100.0, "heat stops at the limit")
	check(d["ship"].events.any(func(e): return e["text"] == "Prism Core overheated"), "the chronicle says so")


func test_two_radiators_keep_it_cool() -> void:
	var d := _prism(2)
	eq(_seconds_to_overheat(d, 120), -1, "never overheats")
	var inst: Dictionary = d["ship"].components.instances[d["reactor"]]
	eq(inst["status"], "ok", "still running")
	eq(inst["heat"], 0.0, "15 heat/s against 5 + 6 + 6 cooling: stays cold")


func test_one_radiator_only_delays_it() -> void:
	var d := _prism(1)
	eq(_seconds_to_overheat(d, 20), -1, "fine for 20 s: +4 heat/s")
	var t := _seconds_to_overheat(d, 20)
	check(t > 0, "but it gets there")


func test_it_recovers_below_half_the_limit() -> void:
	var d := _prism(0)
	_seconds_to_overheat(d, 20)
	var ship = d["ship"]
	var inst: Dictionary = ship.components.instances[d["reactor"]]
	var back := -1
	for s in range(1, 40):
		var before: float = inst["heat"]
		Heat.tick(ship, 1.0)
		if inst["status"] == "ok":
			back = s
			check(before >= 50.0 and inst["heat"] < 50.0, "recovered once below 50 (from %s to %s)" % [before, inst["heat"]])
			break
		check(inst["heat"] >= 50.0, "still too hot at %s" % inst["heat"])
	check(back > 0, "it recovers")
	check(ship.events.any(func(e): return e["text"] == "Prism Core cooled down"), "and says so")


func test_an_overheated_part_is_unpowered_and_stops_heating() -> void:
	var d := _prism(0)
	_seconds_to_overheat(d, 20)
	var ship = d["ship"]
	ship.refresh()
	check(not ship.power_state["powered"][d["reactor"]], "an overheated reactor is not powered")
	var hot: float = ship.components.instances[d["reactor"]]["heat"]
	Heat.tick(ship, 1.0)
	check(ship.components.instances[d["reactor"]]["heat"] < hot, "it cools while out of action")


func test_standard_parts_do_not_overheat_at_normal_load() -> void:
	var ship := Fixture.room_ship()
	var r := Fixture.put(ship, "reactor_mk1", 10, 10)
	var e := Fixture.put(ship, "engine_mk1", 15, 10)  # x 15..18, y 10..11
	check(r > 0 and e > 0, "placed")
	Fixture.wire(ship, [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.refresh()
	for i in 300:
		Heat.tick(ship, 1.0)
	for uid in ship.components.instances:
		eq(ship.components.instances[uid]["status"], "ok", "part %d" % uid)
	eq(ship.components.instances[r]["heat"], 0.0, "reactor: 4 heat/s against 5 cooling")
	eq(ship.components.instances[e]["heat"], 0.0, "engine: 3 against 3")


func test_a_scrap_engine_creeps_up() -> void:
	var ship := Fixture.room_ship()
	Fixture.put(ship, "reactor_mk1", 10, 10)
	var e := Fixture.put(ship, "engine_scrap_mk1", 15, 10)
	Fixture.wire(ship, [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.refresh()
	for i in 60:
		Heat.tick(ship, 1.0)
	var h: float = ship.components.instances[e]["heat"]
	check(absf(h - 60 * (3.3 - 3.0)) < 0.001, "3 x 1.1 heat against 3 cooling: +0.3/s, got %s" % h)


func test_an_unpowered_part_gains_no_heat() -> void:
	var ship := Fixture.room_ship()
	var e := Fixture.put(ship, "engine_neon_mk1", 15, 10)  # no cable, no power
	ship.refresh()
	ship.components.instances[e]["heat"] = 40.0
	Heat.tick(ship, 2.0)
	eq(ship.components.instances[e]["heat"], 34.0, "cools by 3 a second, nothing added")
	Heat.tick(ship, 100.0)
	eq(ship.components.instances[e]["heat"], 0.0, "never below zero")


func test_a_radiator_only_cools_its_own_room() -> void:
	var ship := Fixture.room_ship()
	BuildSession.new(ship).apply(BuildSession.room_changes(Vector2i(8, 19), Vector2i(22, 25), "wall", "floor"))
	var e := Fixture.put(ship, "engine_neon_mk1", 10, 21)  # in the second room, no power
	Fixture.put(ship, "reactor_mk1", 10, 10)
	Fixture.put(ship, "radiator", 15, 10)
	Fixture.wire(ship, [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	ship.refresh()
	var room: int = ship.atmosphere.room_at(Vector2i(15, 10))
	check(room >= 0 and room != ship.atmosphere.room_at(Vector2i(10, 21)), "two rooms")
	eq(Heat.room_bonus(ship), {room: 6.0}, "one running radiator: +6 in its room")
	ship.components.instances[e]["heat"] = 30.0
	Heat.tick(ship, 1.0)
	eq(ship.components.instances[e]["heat"], 27.0, "the other room only has its own 3 cooling")


func test_a_radiator_that_is_out_of_action_does_not_cool() -> void:
	var d := _prism(1)
	var ship = d["ship"]
	ship.components.instances[d["radiators"][0]]["status"] = "malfunction"
	ship.refresh()
	eq(Heat.room_bonus(ship), {}, "a malfunctioning radiator adds nothing")


func test_fire_roll_on_overheating_is_logged() -> void:
	var fires := 0
	for seed_value in 40:
		var d := _prism(0)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for s in 12:
			Heat.tick(d["ship"], 1.0, rng)
		if d["ship"].events.any(func(e): return e["text"] == "Prism Core started a fire"):
			fires += 1
	check(fires >= 2 and fires <= 16, "about 20%% of 40 trips start a fire, got %d" % fires)
