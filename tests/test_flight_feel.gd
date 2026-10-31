extends "res://tests/base_test.gd"
## The owner's Beta 1 playtest ("ships are a little slow"): the flight numbers are 1.5x what Beta 1 had, the
## turn in proportion, the safe docking speed is unchanged, a bump does not one-shot, and an AI fight still resolves.

const Arena = preload("res://scripts/combat/arena.gd")
const Collisions = preload("res://scripts/combat/collisions.gd")
const Flight = preload("res://scripts/sim/flight.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Ship = preload("res://scripts/ship/ship.gd")

## The Beta 1 numbers (data/flight.json and data/collision.json before this change).
const BETA1 := {"thrust_to_accel": 2000.0, "turn_factor": 48.0, "max_speed": 600.0, "damage_k": 6e-7}
const COURIER := "res://data/ships/starter_courier.json"
const PRISM := "res://data/ships/starter_prism.json"
const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const PIRATE := "res://data/ships/pirate_raider.json"


func near(got: float, want: float, msg: String, eps := 1e-6) -> void:
	check(absf(got - want) <= eps * maxf(1.0, absf(want)), "%s: expected %s, got %s" % [msg, str(want), str(got)])


func test_the_flight_numbers_are_one_and_a_half_times_beta_1() -> void:
	var f := Flight.new()
	for k in ["thrust_to_accel", "turn_factor", "max_speed"]:
		near(f.get(k), 1.5 * float(BETA1[k]), "%s is 1.5x" % k)
	near(f.linear_damping, 0.25, "the damping is the same, so the top speed follows the acceleration")
	near(f.angular_damping, 1.5, "and so does the spin")


func test_the_same_ship_accelerates_and_turns_one_and_a_half_times_as_fast() -> void:
	var old := Flight.new()
	old.thrust_to_accel = BETA1["thrust_to_accel"]
	old.turn_factor = BETA1["turn_factor"]
	old.max_speed = BETA1["max_speed"]
	var now := Flight.new()
	for f in [old, now]:
		for i in 30:
			f.step(0.1, {"throttle": 1.0}, 600.0, 20.0)
	near(now.vel.length(), 1.5 * old.vel.length(), "3 s at full throttle: 1.5x the speed", 1e-4)
	near(now.pos.length(), 1.5 * old.pos.length(), "and 1.5x the way covered", 1e-4)
	var spin_old := Flight.new()
	spin_old.turn_factor = BETA1["turn_factor"]
	var spin_now := Flight.new()
	for f in [spin_old, spin_now]:
		for i in 10:
			f.step(0.1, {"turn": 1.0}, 600.0, 20.0)
	near(spin_now.ang_vel, 1.5 * spin_old.ang_vel, "1 s of full turn: 1.5x the spin, so the turning circle stays the same", 1e-4)


func test_a_real_ship_has_a_higher_top_speed() -> void:
	var a := Arena.new(1)
	var i := a.add_ship(Ship.from_design(COURIER))
	var co = a.ships[i]
	var accel: float = co.thrusts["fwd"] * co.flight.thrust_to_accel / co.mass
	var old_accel: float = co.thrusts["fwd"] * BETA1["thrust_to_accel"] / co.mass
	near(accel, 1.5 * old_accel, "the Courier accelerates 1.5x")
	check(accel / co.flight.linear_damping > 1.4 * old_accel / co.flight.linear_damping and accel / co.flight.linear_damping <= co.flight.max_speed, "its coasting top speed is 1.5x and under the cap")


func test_the_safe_docking_speed_is_unchanged_and_a_bump_does_not_one_shot() -> void:
	var c := Collisions.load_config()
	near(c["min_speed"], 40.0, "ram.min_speed stays 40 px/s")
	near(c["damage_k"], 0.6 * BETA1["damage_k"], "damage_k is x0.6, so 1.5x the speed (2.25x the energy) hurts 1.35x")
	var a := Arena.new(1)
	var i := a.add_ship(Ship.from_design(COURIER))
	var hull: float = a.ships[i].hull_max
	# A glancing 150 px/s bump between two Couriers of 76 hull (Beta 1 top speed was 600; this is a quarter of the new one).
	var energy: float = 0.5 * (a.ships[i].mass / 2.0) * 150.0 * 150.0
	check(energy * c["damage_k"] < 0.2 * hull, "a bump at 150 px/s costs under a fifth of the hull (%f of %f)" % [energy * c["damage_k"], hull])


func test_an_ai_fight_still_resolves() -> void:
	var s := Session.new()
	s.start(Ship.from_design(PRISM), Session.load_ship(PIRATE), 5)
	s.arena.ships[Session.ENEMY].hull = 14.0  # a pirate already hurt: the fight has to end
	var pilot := PilotAI.new(s.arena, Session.PLAYER, Session.ENEMY, {})
	var n := 0
	var fastest := 0.0
	while s.state() == "fighting" and n < 90 * 60:
		if n % 3 == 0:
			pilot.think(Session.STEP * 3)
		s.ai.think(Session.STEP)
		s.arena.step(Session.STEP)
		n += 1
		fastest = maxf(fastest, maxf(s.arena.ships[Session.PLAYER].flight.vel.length(), s.arena.ships[Session.ENEMY].flight.vel.length()))
	eq(s.state(), "won", "the hurt pirate is wrecked within 90 s (took %.1f s)" % (n / 60.0))
	check(fastest <= s.arena.ships[Session.PLAYER].flight.max_speed + 1e-3, "nobody went over the speed cap")


func test_the_pilot_closes_faster_than_it_used_to() -> void:
	# From the 1200 px spawn gap the pirate closed to 1000 px in 4.2 s against the slow Rustbucket in Beta 1 (3.5 s now).
	var s := Session.new()
	s.start(Ship.from_design(RUSTBUCKET), Session.load_ship(PIRATE), 1)
	var t := -1.0
	for i in 60 * 30:
		s.arena.set_input(Session.PLAYER, 0.0, 0.0, 0.0)
		s.ai.think(Session.STEP)
		s.arena.step(Session.STEP)
		if s.distance() < 1000.0:
			t = i / 60.0
			break
	check(t > 0.0 and t < 4.0, "the pirate closed from 1200 to 1000 px in %.1f s" % t)
	check(PilotAI.CLOSE_MAX >= 1.5 * 260.0 - 1.0 and PilotAI.LATERAL_MAX >= 1.5 * 150.0 - 1.0, "its speed caps are Beta 1's x1.5")
