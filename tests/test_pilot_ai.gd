extends "res://tests/base_test.gd"
## The enemy pilot: its lead against a moving target, target priority, range keeping, determinism and
## stopping when wrecked.

const Structure = preload("res://scripts/ship/structure.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Collisions = preload("res://scripts/combat/collisions.gd")
const PIRATE := "res://data/ships/pirate_raider.json"
const COURIER := "res://data/ships/starter_courier.json"
const LARGE := "gen:concord:large:7:30000"  ## a large Concord ship (radius 600+ px): a row of 3 bow guns and 4 flank turrets
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


## Shots logged by ship `ship` with weapon `weapon`.
func _shots_of(a: Arena, ship: int, weapon: String) -> int:
	var n := 0
	for e in a.events:
		n += int(e["type"] == "shot" and e["ship"] == ship and e["weapon"] == weapon)
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
	var ai: PilotAI = d[1][0]
	a.autofire[1] = false  # the sitting foe holds fire
	_run(a, d[1], 20.0)
	var dist: float = a.ships[0].flight.pos.distance_to(a.ships[1].flight.pos)
	var u: Vector2 = (a.ships[1].flight.pos - a.ships[0].flight.pos) / dist
	var want := ai.hold_distance(u, ai._intact())
	var gap := dist - ai.extent(0, u) - ai.extent(1, -u)
	check(absf(dist - want) < 0.2 * want, "it holds %d between the centres, it holds %d" % [want, dist])
	check(gap > 0.5 * PilotAI.HULL_MARGIN, "so the hulls never clip (a gap of %d px)" % gap)
	check(_count(a, "shot", 0) >= 8, "it fires: %d shots" % _count(a, "shot", 0))
	check(_count(a, "hit", 1) + _count(a, "shield", 1) > 0, "and hits")
	check(Structure.structure_fraction(a.ships[1]) < 1.0, "the foe's hull is hurt")
	eq(_count(a, "shot", 1), 0, "(the sitting foe fired nothing)")
	for e in a.events:  # the strafing pirate's wide hull may clip the foe's: that is the only way it can be hurt
		if e["type"] == "hit" and e["ship"] == 0:
			check(e.get("ram", false), "(and the only damage it took was from a collision)")
	check(_shots_of(a, 0, "laser_mk1") >= 4 and _shots_of(a, 0, "rattle_burst_scrap") >= 2, "the laser and the turret both fire (%d, %d)" % [_shots_of(a, 0, "laser_mk1"), _shots_of(a, 0, "rattle_burst_scrap")])
	var arcs := 0
	for uid in a.ships[0].mounts:
		arcs += int(a.weapons.in_arc(a, 0, a.ships[0].mounts[uid], a.ships[1].flight.pos))
	check(arcs >= 1, "it keeps the foe where one of its guns can bear")


## The gap it keeps is RANGE_FRACTION of a bow gun's range between the hulls (each hull's reach along the line between the
## centres, not a bounding circle), and a flank turret far behind the bow asks for a closer one.
func test_the_hold_distance_counts_each_hull_and_each_gun() -> void:
	var a := Arena.new(1)
	a.add_ship(Ship.from_design(COURIER), Vector2.ZERO)
	a.add_ship(Session.load_ship(LARGE), Vector2(0.0, -2000.0), PI)
	var ai := PilotAI.new(a, 0, 1)
	var u := Vector2.UP
	var ext: float = ai.extent(0, u)
	var pulse := 0.7 * float(a.weapons.def("pulse_mk1")["range"])
	near(ai.hold_distance(u, ai._intact()) - ext - ai.extent(1, -u), pulse, "one bow gun: a gap of 70% of its range", 40.0)
	var big := PilotAI.new(a, 1, 0)
	var gap: float = big.hold_distance(-u, big._intact()) - big.extent(1, -u) - big.extent(0, u)
	check(gap < 0.7 * 900.0 - 50.0 and gap >= PilotAI.HULL_MARGIN - 1e-3, "the large ship's flank turrets ask for a closer gap than its bow guns would (%d)" % gap)


## One short gun among long ones does not pull the ship in: it holds the gap that the guns with 60% of the dps reach (docs/GUNS.md 13).
func test_one_short_gun_does_not_set_the_hold_distance() -> void:
	var a := Arena.new(1)
	a.add_ship(Ship.from_design(COURIER), Vector2.ZERO)
	a.add_ship(Session.load_ship(PIRATE), Vector2(0.0, -2000.0), PI)
	var ai := PilotAI.new(a, 0, 1)
	var armed: Dictionary = ai._intact()
	check(not armed.is_empty(), "the courier has a gun")
	var m: Dictionary = armed[armed.keys()[0]].duplicate()
	m["id"] = "pulse_mk1"
	var short: Dictionary = m.duplicate()
	short["id"] = "flak_turret"
	var d_long: float = ai.hold_distance(Vector2.UP, {1: m})
	var d_short: float = ai.hold_distance(Vector2.UP, {1: short})
	check(d_short < d_long - 100.0, "a flak gun alone holds a closer gap than a pulse gun (%d, %d)" % [d_short, d_long])
	var w: Dictionary = a.weapons.def("pulse_mk1")
	var mixed: Dictionary = {1: m, 2: short, 3: m.duplicate(), 4: m.duplicate()}
	near(ai.hold_distance(Vector2.UP, mixed), d_long, "three pulse guns with a flak gun: the pulse range is held", 1.0)
	check(float(w["range"]) > 1000.0, "and the gun ranges are the longer ones")


## A starter flown by the AI reaches a large generated enemy (radius 600+ px, more than the starter's gun range between
## the bounding circles) and hits it.
func test_a_starter_reaches_a_large_enemy_and_hits_it() -> void:
	var s := Session.new()
	s.start(Ship.from_design(COURIER), Session.load_ship(LARGE), 3)
	var a: Arena = s.arena
	check(float(Collisions.hit_cells(a, 1)["radius"]) + float(Collisions.hit_cells(a, 0)["radius"]) > float(a.weapons.def("pulse_mk1")["range"]), "(the two bounding circles are wider than the pulse's range)")
	a.autofire[1] = false
	var pilot := PilotAI.new(a, 0, 1, {"aim_skill": 0.75})
	for k in 25 * 60:
		pilot.think(DT)
		a.step(DT)
	check(_shots_of(a, 0, "pulse_mk1") >= 8, "it fires its pulse (%d shots)" % _shots_of(a, 0, "pulse_mk1"))
	check(_count(a, "hit", 1) + _count(a, "shield", 1) >= 5, "and its shots land (%d)" % (_count(a, "hit", 1) + _count(a, "shield", 1)))


## A large enemy's pilot fires every gun of its bow row (a row of fixed guns cannot all point at one part, but each lines up
## on the hull) and its flank turrets, at a starter that sits still.
func test_a_large_enemy_brings_its_guns_to_bear() -> void:
	var s := Session.new()
	s.start(Ship.from_design(COURIER), Session.load_ship(LARGE), 3)
	var a: Arena = s.arena
	for k in 30 * 60:
		s.ai.think(DT)
		a.step(DT)
	var fixed := 0
	var turrets := 0
	for uid in a.ships[1].mounts:
		var id: String = a.ships[1].mounts[uid]["id"]
		var n := 0
		for e in a.events:
			n += int(e["type"] == "shot" and e["ship"] == 1 and e["uid"] == uid)
		if a.weapons.def(id)["turret"]:
			turrets += int(n > 0)
		elif Vector2(a.ships[1].mounts[uid]["dir"]).y < -0.5:  # (a broadside on a flank fires only when its side is presented, docs/GUNS.md 6)
			check(n >= 3, "the bow gun %s (%d) fires (%d shots)" % [id, uid, n])
			fixed += 1
	check(fixed >= 2, "(it has a row of bow guns: %d)" % fixed)
	check(turrets >= 1, "and a flank turret fires too")


func test_a_shot_lines_up_on_the_hull_or_not() -> void:
	var d := _duel()
	var a: Arena = d[0]
	var ai: PilotAI = d[1][0]
	var from: Vector2 = a.ships[0].flight.pos + Vector2(0.0, -400.0)
	var to_foe: Vector2 = (a.ships[1].flight.pos - from).normalized()
	check(ai.on_hull(from, to_foe, 2000.0), "straight at the foe")
	check(not ai.on_hull(from, -to_foe, 2000.0), "not away from it")
	check(not ai.on_hull(from, to_foe.rotated(PI / 2.0), 2000.0), "not sideways")
	check(not ai.on_hull(from, to_foe, 200.0), "not beyond the gun's range")


## A pilot of SNIPE_SKILL or better aims at the foe's weapons, then its hull; a worse one at its hull from the start, at a
## wall clear of the guns' outside halves; a fleeing foe's engines come first.
func test_who_aims_at_what() -> void:
	var d := _duel()
	var a: Arena = d[0]
	var ai: PilotAI = d[1][0]
	var foe: Ship = a.ships[1].ship
	var family := func(uid: int) -> String: return foe.components.def(foe.components.instances[uid]["id"])["family"]
	ai.aim_skill = 0.9
	eq(family.call(ai.pick_target()), "weapon", "a sniper aims at the weapons first")
	ai.aim_skill = 0.5
	eq(ai.pick_target(), -1, "a brute aims at the hull")
	var p: Vector2 = ai.hull_point()
	var t: String = foe.grid.get_tile(Vector2i(floori(p.x), floori(p.y)))
	check(foe.grid.tile_flag(t, "solid") or foe.grid.tile_flag(t, "door"), "at a wall (%s)" % t)
	var pc := Vector2i(floori(p.x), floori(p.y))
	check(PilotAI.SIDES.any(func(dd): return foe.grid.get_tile(pc + dd) == "" and foe.components.any_at(pc + dd) < 0), "on the outside of the hull, not a bulkhead inside")
	check((p - a.ships[1].com).dot(ai.arena.world_to_local(1, a.ships[0].flight.pos) - a.ships[1].com) > 0.0, "on the side that faces it")
	for uid in foe.components.instances:
		for c in foe.components.instances[uid]["out_cells"]:
			if family.call(uid) == "weapon":
				check(maxi(absi(c.x - floori(p.x)), absi(c.y - floori(p.y))) > PilotAI.GUN_CLEARANCE, "clear of the guns' outside halves")
	ai.foe_morale = {"state": "fleeing"}  # morale.gd's state is all the pilot reads
	eq(family.call(ai.pick_target()), "engine", "a fleeing foe's engines first")
	ai.foe_morale = null
	ai.aim_skill = 0.9
	for uid in foe.components.instances:
		if family.call(uid) == "weapon":
			foe.components.instances[uid]["status"] = "disabled"
	eq(ai.pick_target(), -1, "with the guns out the sniper aims at the hull too")


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
	eq(a.ships[0].input, {"throttle": 0.0, "turn": 0.0, "strafe": 0.0}, "no helm input")
	eq(_count(a, "shot", 0), shots, "no more shots")
	eq(a.ships[1].input, {"throttle": 0.0, "turn": 0.0, "strafe": 0.0}, "the other pilot stops when its foe is wrecked")


func test_with_a_sectored_shield_it_holds_weapons_aimed_into_the_sector_the_foe_is_about_to_hit() -> void:
	var d := _duel()
	var a: Arena = d[0]
	var ai: PilotAI = d[1][0]
	a.ships[0].ship.components.by_id["shield_mk1"]["stats"]["sectors"] = 4  # a test-only sectored shield
	a.ships[0].dirty = true
	a.sync(0)
	eq(a.ships[0].sectors, 4, "four sectors")
	a.ships[1].flight.pos = Vector2(0.0, -1300.0)  # nose to nose with room between (the hulls are 450 px across the corner)
	for uid in a.ships[0].mounts:
		a.ships[0].cooldowns[uid] = 0
	for uid in a.ships[1].mounts:
		a.ships[1].cooldowns[uid] = 0
	a.autofire[1] = false  # its turret stays loaded
	eq(ai._exposed_sectors(), [0], "the foe's loaded guns point at my bow")
	for k in 30:
		ai.think(DT)
		a.step(DT)
	eq(_shots_of(a, 0, "laser_mk1"), 0, "so it holds its fixed bow gun for now")
	for k in 120:
		ai.think(DT)
		a.step(DT)
	check(_shots_of(a, 0, "laser_mk1") > 0, "but not for ever")
