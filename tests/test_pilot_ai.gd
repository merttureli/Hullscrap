extends "res://tests/base_test.gd"
## The enemy pilot: its lead against a moving target, target priority, range keeping, determinism and
## stopping when wrecked.

const Arena = preload("res://scripts/combat/arena.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const PIRATE := "res://data/ships/pirate_raider.json"
const DT := 1.0 / 60.0


func _ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	for c in g.hull:
		g.force_tile(c, "floor")
	return Ship.new("t", g)


func _count(a: Arena, type: String, ship := -1) -> int:
	var n := 0
	for e in a.events:
		if e["type"] == type and (ship < 0 or e["ship"] == ship):
			n += 1
	return n


func near(got: float, want: float, msg: String, eps := 1e-3) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func test_lead_point_meets_a_moving_target() -> void:
	var o := Vector2(10.0, 20.0)
	eq(PilotAI.lead_point(o, Vector2(500.0, 20.0), Vector2(0.0, 80.0), 0.0), Vector2(500.0, 20.0), "hitscan: where it is")
	eq(PilotAI.lead_point(o, Vector2(500.0, 20.0), Vector2.ZERO, 700.0), Vector2(500.0, 20.0), "a target at rest")
	for v: Vector2 in [Vector2(0.0, 100.0), Vector2(-60.0, 40.0), Vector2(30.0, -90.0)]:
		var p := Vector2(600.0, -100.0)
		var aim := PilotAI.lead_point(o, p, v, 700.0)
		var t := (aim - p).length() / v.length()
		near(o.distance_to(aim), 700.0 * t, "the shot arrives as the target does (%s)" % str(v), 0.05)
		check((aim - p).normalized().dot(v.normalized()) > 0.99, "ahead of the target, along its path")


## One shot at a block of walls that drifts across the line of fire; true when it hit.
func _trial(seed_value: int, lead: bool) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var a := Arena.new(seed_value)
	a.add_ship(_ship(), Vector2.ZERO)
	var s := _ship()
	for y in range(13, 18):
		for x in range(13, 18):
			s.grid.force_tile(Vector2i(x, y), "wall")  # 5 x 5 cells: 160 px
	var dir := Vector2.from_angle(rng.randf() * TAU)
	var speed := rng.randf_range(60.0, 120.0)  # a slow drift, across the line of fire
	var foe := a.add_ship(s, dir * rng.randf_range(450.0, 800.0))
	a.ships[foe].flight.linear_damping = 0.0
	a.ships[foe].flight.vel = dir.rotated(PI / 2.0 * (1.0 if rng.randf() < 0.5 else -1.0)) * speed
	var gun := a.add_mount(0, "test_bolt", Vector2(15.5, 15.5))
	var ai := PilotAI.new(a, 0, foe)
	var aim: Vector2 = ai.aim_for(a.ships[0].mounts[gun]) if lead else a.ships[foe].flight.pos
	check(a.fire(0, gun, aim), "fired")
	a.step(3.0)
	return _count(a, "hit", foe) > 0


func test_the_ai_lead_hits_a_slowly_moving_target_more_often_than_aiming_at_it() -> void:
	var led := 0
	var naive := 0
	var trials := 40
	for k in trials:
		led += int(_trial(100 + k, true))
		naive += int(_trial(100 + k, false))
	check(led >= trials * 9 / 10, "the lead hits nearly always (%d of %d)" % [led, trials])
	check(led >= naive + trials / 4, "and clearly more than aiming at the current position (%d against %d)" % [led, naive])


## The pirate (ship 0, flown by the AI) against a second pirate that sits still and ships a shield.
func _duel(seed_value := 5, foe_ai := false) -> Array:
	var a := Arena.new(seed_value)
	a.add_ship(Session.load_ship(PIRATE), Vector2.ZERO)
	a.add_ship(Session.load_ship(PIRATE), Vector2(0.0, -1200.0), PI)
	var ais := [PilotAI.new(a, 0, 1)]
	if foe_ai:
		ais.append(PilotAI.new(a, 1, 0))
	return [a, ais]


func _run(a: Arena, ais: Array, seconds: float) -> void:
	for k in int(seconds / DT):
		for ai in ais:
			ai.think(DT)
		a.step(DT)


func test_the_ai_closes_to_its_preferred_range_and_shoots() -> void:
	var d := _duel()
	var a: Arena = d[0]
	_run(a, d[1], 20.0)
	var dist: float = a.ships[0].flight.pos.distance_to(a.ships[1].flight.pos)
	var want := PilotAI.RANGE_FRACTION * float(a.weapons.def("laser_mk1")["range"])
	check(absf(dist - want) < 0.2 * want, "70%% of the laser range (%d), it holds %d" % [want, dist])
	check(_count(a, "shot", 0) >= 8, "it fires: %d shots" % _count(a, "shot", 0))
	check(_count(a, "hit", 1) + _count(a, "shield", 1) > 0, "and hits")
	check(a.ships[1].hull < a.ships[1].hull_max, "the foe's hull is hurt")
	near(a.ships[0].hull, a.ships[0].hull_max, "(the sitting foe did nothing)", 1e-6)
	var arcs := 0
	for uid in a.ships[0].mounts:
		arcs += int(a.weapons.in_arc(a, 0, a.ships[0].mounts[uid], a.ships[1].flight.pos))
	check(arcs >= 1, "it keeps the foe inside an arc of its guns")


func test_the_ai_aims_at_weapons_then_engines_then_the_reactor() -> void:
	var d := _duel()
	var a: Arena = d[0]
	var ai: PilotAI = d[1][0]
	var foe: Ship = a.ships[1].ship
	var family := func(uid: int) -> String: return foe.components.def(foe.components.instances[uid]["id"])["family"]
	eq(family.call(ai.pick_target()), "weapon", "weapons first")
	for uid in foe.components.instances:
		if family.call(uid) == "weapon":
			foe.components.instances[uid]["status"] = "disabled"
	eq(family.call(ai.pick_target()), "engine", "then engines")
	for uid in foe.components.instances:
		if family.call(uid) == "engine":
			foe.components.instances[uid]["status"] = "disabled"
	eq(family.call(ai.pick_target()), "reactor", "then the reactor")
	for uid in foe.components.instances:
		foe.components.instances[uid]["status"] = "disabled"
	eq(ai.pick_target(), -1, "with everything out it aims at the hull")


func test_the_same_seed_replays_the_same_fight() -> void:
	var one := _duel(9, true)
	var two := _duel(9, true)
	_run(one[0], one[1], 12.0)
	_run(two[0], two[1], 12.0)
	eq(JSON.stringify(one[0].snapshot()), JSON.stringify(two[0].snapshot()), "same state")
	var other := _duel(10, true)
	_run(other[0], other[1], 12.0)
	check(JSON.stringify(one[0].snapshot()) != JSON.stringify(other[0].snapshot()), "another seed plays out differently")


func test_a_wrecked_pilot_stops() -> void:
	var d := _duel(5, true)
	var a: Arena = d[0]
	_run(a, d[1], 6.0)
	check(a.ships[0].input["throttle"] != 0.0 or a.ships[0].input["turn"] != 0.0, "it was flying")
	a.wreck(0)
	var shots := _count(a, "shot", 0)
	_run(a, d[1], 3.0)
	eq(a.ships[0].input, {"throttle": 0.0, "turn": 0.0}, "no helm input")
	eq(_count(a, "shot", 0), shots, "no more shots")
	eq(a.ships[1].input, {"throttle": 0.0, "turn": 0.0}, "the other pilot stops when its foe is wrecked")


func test_with_a_sectored_shield_it_holds_weapons_aimed_into_the_sector_the_foe_is_about_to_hit() -> void:
	var d := _duel()
	var a: Arena = d[0]
	var ai: PilotAI = d[1][0]
	a.ships[0].ship.components.by_id["shield_mk1"]["stats"]["sectors"] = 4  # a test-only sectored shield
	a.ships[0].dirty = true
	a.sync(0)
	eq(a.ships[0].sectors, 4, "four sectors")
	a.ships[1].flight.pos = Vector2(0.0, -600.0)
	for uid in a.ships[0].mounts:
		a.ships[0].cooldowns[uid] = 0
	for uid in a.ships[1].mounts:
		a.ships[1].cooldowns[uid] = 0
	eq(ai._exposed_sectors(), [0], "the foe's loaded lasers point at my bow")
	for k in 30:
		ai.think(DT)
		a.step(DT)
	eq(_count(a, "shot", 0), 0, "so it holds its bow guns for now")
	for k in 120:
		ai.think(DT)
		a.step(DT)
	check(_count(a, "shot", 0) > 0, "but not for ever")
