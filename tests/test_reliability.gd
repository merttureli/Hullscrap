extends "res://tests/base_test.gd"
## Malfunctions and repair (scripts/sim/reliability.gd, Ship.repair, ShipSim's rng).

const Fixture = preload("res://tests/fixture_ship.gd")
const Reliability = preload("res://scripts/sim/reliability.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Heat = preload("res://scripts/sim/heat.gd")


## A room with one reactor of line `id` on a cable; returns {ship, uid}.
func _one(id: String) -> Dictionary:
	var ship := Fixture.room_ship()
	var uid := Fixture.put(ship, id, 10, 10)
	check(uid > 0, id + " placed")
	Fixture.wire(ship, [Vector2i(11, 11)])
	ship.refresh()
	return {"ship": ship, "uid": uid}


## Over `trials` runs of `minutes` minutes, ticking once a second and repairing at once, how many
## malfunctions the part had. Each trial has its own seed.
func _malfunctions(d: Dictionary, trials: int, minutes: int) -> int:
	var ship = d["ship"]
	var count := 0
	for t in trials:
		var rng := RandomNumberGenerator.new()
		rng.seed = t + 1
		for s in minutes * 60:
			Reliability.tick(ship, 1.0, rng)
			if ship.components.instances[d["uid"]]["status"] != "ok":
				count += 1
				ship.repair(d["uid"])
	return count


func test_a_scrap_part_malfunctions_about_15_percent_a_minute() -> void:
	var n := _malfunctions(_one("reactor_scrap_mk1"), 30, 10)  # 300 minutes: 45 expected
	check(n >= 28 and n <= 65, "scrap malfunctions in 300 minutes: %d (about 45)" % n)


func test_a_standard_part_rarely_does() -> void:
	var n := _malfunctions(_one("reactor_mk1"), 30, 10)  # 300 minutes at 1%: 3 expected
	check(n <= 12, "standard malfunctions in 300 minutes: %d (about 3)" % n)


func test_a_neon_part_is_in_between() -> void:
	var n := _malfunctions(_one("reactor_neon_mk1"), 30, 10)  # 9 expected
	check(n >= 2 and n <= 22, "neon malfunctions in 300 minutes: %d (about 9)" % n)


func test_the_same_seed_gives_the_same_story() -> void:
	var a := _one("engine_scrap_mk1")
	var b := _one("engine_scrap_mk1")
	# the engine needs power: a reactor beside it
	for d in [a, b]:
		Fixture.put(d["ship"], "reactor_mk1", 15, 10)
		Fixture.wire(d["ship"], [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
		d["ship"].refresh()
	var ra := RandomNumberGenerator.new()
	var rb := RandomNumberGenerator.new()
	ra.seed = 7
	rb.seed = 7
	for s in 3000:
		Reliability.tick(a["ship"], 1.0, ra)
		Reliability.tick(b["ship"], 1.0, rb)
		for d in [a, b]:
			for uid in d["ship"].components.instances:
				if d["ship"].components.instances[uid]["status"] != "ok" and s % 50 == 0:
					d["ship"].repair(uid)
	check(a["ship"].events.size() > 0, "something happened")
	eq(a["ship"].events, b["ship"].events, "same seed, same chronicle")
	eq(a["ship"].components.to_dict(), b["ship"].components.to_dict(), "same parts")
	var rc := RandomNumberGenerator.new()
	rc.seed = 8
	var c := _one("engine_scrap_mk1")
	Fixture.put(c["ship"], "reactor_mk1", 15, 10)
	Fixture.wire(c["ship"], [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)])
	c["ship"].refresh()
	for s in 3000:
		Reliability.tick(c["ship"], 1.0, rc)
		for uid in c["ship"].components.instances:
			if c["ship"].components.instances[uid]["status"] != "ok" and s % 50 == 0:
				c["ship"].repair(uid)
	check(JSON.stringify(c["ship"].events) != JSON.stringify(a["ship"].events), "another seed tells another story")


func test_a_malfunction_takes_the_part_out_of_action_and_repair_fixes_it() -> void:
	var d := _one("reactor_scrap_mk1")
	var ship = d["ship"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var s := 0
	while ship.components.instances[d["uid"]]["status"] == "ok" and s < 5000:
		Reliability.tick(ship, 1.0, rng)
		s += 1
	var inst: Dictionary = ship.components.instances[d["uid"]]
	check(inst["status"] != "ok", "it malfunctioned after %d s" % s)
	ship.refresh()
	check(not ship.power_state["powered"][d["uid"]], "and is no longer powered")
	check(ship.events.any(func(e): return e["text"] == "Rustbucket Reactor malfunctioned"), "the chronicle says so")
	var t0: int = ship.events.size()
	Reliability.tick(ship, 1.0, rng)
	eq(ship.events.size(), t0, "a part that is out of action does not roll again")
	inst["hp"] = 2
	check(ship.repair(d["uid"]), "repair works")
	eq([inst["status"], inst["hp"]], ["ok", 8], "status ok, hp back to the maximum")
	ship.refresh()
	check(ship.power_state["powered"][d["uid"]], "powered again")
	check(not ship.repair(9999), "an unknown uid cannot be repaired")


func test_some_malfunctions_cost_hp_and_the_last_hp_disables() -> void:
	var d := _one("reactor_scrap_mk1")
	var ship = d["ship"]
	var inst: Dictionary = ship.components.instances[d["uid"]]
	var hurt := 0
	var disabled := 0
	var plain := 0
	for t in 300:
		ship.repair(d["uid"])
		inst["hp"] = 1
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + t
		for s in 600:
			Reliability.tick(ship, 1.0, rng)
			if inst["status"] != "ok":
				break
		match inst["status"]:
			"disabled":
				disabled += 1
				eq(inst["hp"], 0, "disabled means 0 hp")
			"malfunction":
				plain += 1
				eq(inst["hp"], 1, "a plain malfunction costs nothing")
	hurt = disabled
	check(plain > 0 and disabled > 0, "both outcomes happen (%d plain, %d disabled)" % [plain, disabled])
	var share := float(hurt) / float(hurt + plain)
	check(share > 0.15 and share < 0.35, "about a quarter cost hp: %.2f" % share)


func test_some_malfunctions_start_a_fire() -> void:
	var d := _one("reactor_scrap_mk1")
	var ship = d["ship"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var malfunctions := 0
	var fires := 0
	for s in 60 * 600:
		Reliability.tick(ship, 1.0, rng)
		if ship.components.instances[d["uid"]]["status"] != "ok":
			ship.repair(d["uid"])
	for e in ship.events:
		malfunctions += 1 if e["text"].ends_with("malfunctioned") else 0
		fires += 1 if e["text"].ends_with("started a fire") else 0
	check(malfunctions > 20, "plenty of malfunctions: %d" % malfunctions)
	check(fires > 0 and float(fires) / malfunctions < 0.5, "about 30%% start a fire: %d of %d" % [fires, malfunctions])
	check(ship.events.size() <= 50, "the chronicle is capped")


func test_the_sim_owns_a_seeded_rng_per_ship() -> void:
	var sim := ShipSim.new()
	var ship := Fixture.room_ship()
	sim.ships = [ship]
	var a := sim.rng_of(ship)
	eq(sim.rng_of(ship), a, "one rng per ship")
	var fresh := RandomNumberGenerator.new()
	fresh.seed = 1
	eq(a.randi(), fresh.randi(), "seeded from the ship's seed, 1 by default")
	ship.rng_seed = 42
	var other := Fixture.room_ship()
	other.rng_seed = 42
	var b := sim.rng_of(other)
	fresh.seed = 42
	eq(b.randi(), fresh.randi(), "another seed")
	sim.free()


func test_the_sim_ticks_heat_and_reliability() -> void:
	var sim := ShipSim.new()
	var ship := Fixture.room_ship()
	var uid := Fixture.put(ship, "reactor_neon_mk1", 10, 10)
	Fixture.wire(ship, [Vector2i(11, 11)])
	sim.ships = [ship]
	for i in 200:
		sim.step(0.1)
	check(ship.clock > 19.9 and ship.clock < 20.1, "the ship's clock runs: %s" % ship.clock)
	check(ship.events.any(func(e): return e["text"] == "Prism Core overheated"), "the Prism Core overheated by itself")
	check(ship.components.instances[uid]["status"] != "ok" or ship.components.instances[uid]["heat"] > 0.0, "and has state")
	sim.free()
	var again := ShipSim.new()
	var twin := Fixture.room_ship()
	Fixture.put(twin, "reactor_neon_mk1", 10, 10)
	Fixture.wire(twin, [Vector2i(11, 11)])
	again.ships = [twin]
	for i in 200:
		again.step(0.1)
	eq(twin.events, ship.events, "the same ship gives the same chronicle")
	again.free()
