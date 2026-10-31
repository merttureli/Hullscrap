extends "res://tests/base_test.gd"
## Aiming and flying with hull mounts (docs/CONTENT.md 4 and 4f): fixed guns point where the mount points
## (a few degrees of gimbal toward the cursor), turrets track and shoot by themselves with a hit roll,
## engines push along their nozzle, the ship turns toward the mouse, and the pilot AI leads with its nose.

const Wall = preload("res://tests/fixture_wall.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Flight = preload("res://scripts/sim/flight.gd")
const Components = preload("res://scripts/ship/components.gd")
const Collisions = preload("res://scripts/combat/collisions.gd")

const PIRATE := "res://data/ships/pirate_raider.json"
const DT := 1.0 / 60.0


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## A powered mount `id` on a wall `thick` deep, facing `rot`, at the world origin. Returns {arena, ship, uid}.
func _gun(id: String, rot := 0, thick := 1) -> Dictionary:
	var ship := Wall.wall_ship(thick, rot)
	var uid := ship.components.place_mount(ship.grid, id, Wall.out_anchor(rot), rot)
	var reactor := ship.components.place(ship.grid, "reactor_mk1", Wall.corner(rot, 2, 5, thick, thick + 3), 0)
	for c in [Wall.at(rot, 1, thick), Wall.at(rot, 2, thick)]:
		ship.cables.place(ship.grid, c)
	ship.refresh()
	var a := Arena.new(7)
	a.add_ship(ship, Vector2.ZERO)
	check(uid >= 0 and reactor >= 0, "(setup: the gun and its reactor)")
	return {"arena": a, "ship": ship, "uid": uid}


## A solid block of wall for a target, `size` cells square, at `pos` in the world, facing as it is.
func _target(a: Arena, pos: Vector2, size := 9) -> int:
	var s := Wall.wall_ship(1)
	for y in size:
		for x in size:
			s.grid.force_tile(Vector2i(11 + x, 11 + y), "wall")
	return a.add_ship(s, pos)


func _shots(a: Arena, ship := 0) -> Array:
	return a.events.filter(func(e): return e["type"] == "shot" and e["ship"] == ship)


# --- fixed guns ---------------------------------------------------------------------------------------

func test_a_placed_gun_shoots_from_the_muzzle_of_its_barrel_along_the_mount() -> void:
	for rot in 4:
		var g := _gun("laser_mk1", rot)
		var a: Arena = g["arena"]
		var m: Dictionary = a.ships[0].mounts[g["uid"]]
		eq(m["dir"], Vector2(Mounts.outward(rot)), "rot %d: the mount points outward" % rot)
		eq(m["aim"], m["dir"], "and starts at rest along it")
		near(m["reach"], 35.0 / 16.0, "the muzzle is 35 art pixels along the barrel from its pivot", 1e-6)
		var far: Vector2 = a.local_to_world(0, m["pos"]) + Vector2(m["dir"]) * 2000.0
		check(a.fire(0, g["uid"], far), "fires")
		var e: Dictionary = _shots(a)[0]
		near((e["origin"] - a.local_to_world(0, m["pos"])).length(), m["reach"] * 32.0, "the shot leaves a muzzle's length from the pivot", 1e-3)
		near(Vector2(e["dir"]).angle_to(Vector2(m["dir"])), 0.0, "along the mount", 1e-5)
		var outside: Vector2 = a.cell_to_world(0, g["ship"].components.instances[g["uid"]]["out_cells"][0])
		check(e["origin"].distance_to(a.ships[0].flight.pos) > outside.distance_to(a.ships[0].flight.pos) - 64.0, "and well out in front of the hull")


func test_the_barrel_turns_toward_the_cursor_only_as_far_as_its_gimbal() -> void:
	var g := _gun("laser_mk1")  # standard: 5 degrees
	var a: Arena = g["arena"]
	var m: Dictionary = a.ships[0].mounts[g["uid"]]
	var pivot: Vector2 = a.local_to_world(0, m["pos"])
	for deg in [0.0, 2.0, 4.9, 5.0, 12.0, 90.0, 170.0, -3.0, -30.0]:
		a.weapons.point_barrel(a, 0, g["uid"], pivot + Vector2.from_angle(deg_to_rad(deg) - PI / 2.0) * 800.0)
		var off := rad_to_deg(Vector2(m["dir"]).angle_to(m["aim"]))
		near(off, clampf(deg, -5.0, 5.0), "the cursor %d degrees off: the barrel %.1f" % [deg, off], 1e-3)
	for case in [["rattle_burst_scrap", 0.0], ["shrapnel_cannon_scrap", 3.0], ["laser_mk1", 5.0], ["heat_lance_neon", 8.0]]:
		eq(float(a.weapons.def(case[0])["gimbal"]), float(case[1]), "%s: scrap 3, standard 5, neon 8, turrets none" % case[0])
	for id in a.weapons.defs:
		if not id.begins_with("test_"):
			eq(float(a.weapons.def(id)["gimbal"]) == 0.0, bool(a.weapons.def(id)["turret"]), id + ": only turrets have no gimbal")


func test_the_player_barrels_follow_the_cursor_each_substep() -> void:
	var g := _gun("laser_mk1")
	var a: Arena = g["arena"]
	var m: Dictionary = a.ships[0].mounts[g["uid"]]
	a.aim_points[0] = a.local_to_world(0, m["pos"]) + Vector2.from_angle(deg_to_rad(3.0) - PI / 2.0) * 800.0
	a.step(DT)
	near(rad_to_deg(Vector2(m["dir"]).angle_to(m["aim"])), 3.0, "the barrel follows", 1e-3)
	a.ships[0].flight.angle = deg_to_rad(10.0)
	a.ships[0].flight.ang_vel = 0.0
	a.step(DT)
	near(rad_to_deg(Vector2(m["dir"]).angle_to(m["aim"])), -5.0, "and keeps the cone about the mount when the ship turns away", 0.05)


# --- turrets --------------------------------------------------------------------------------------------

func test_a_turret_deals_sixty_percent_of_its_fixed_equivalent() -> void:
	var w := Weapons.new()
	eq(w.turret_damage, 0.6, "the data says 60 percent")
	var turrets := []
	for id in w.defs:
		if w.defs[id].get("turret", false):
			turrets.append(id)
			near(w.def(id)["damage"], 0.6 * float(w.defs[id]["damage"]), id + ": 60 percent of the entry", 1e-9)
			for k in ["arc", "track", "accuracy"]:
				check(w.defs[id].has(k), "%s has %s" % [id, k])
			check(float(w.defs[id]["accuracy"]) >= 0.6 and float(w.defs[id]["accuracy"]) <= 0.85, id + ": accuracy 0.6 to 0.85")
		elif not id.begins_with("test_"):
			eq(w.def(id)["damage"], float(w.defs[id]["damage"]), id + ": a fixed gun deals its whole damage")
	turrets.sort()
	for id in ["laser_turret_mk1", "leech_laser", "rattle_burst_scrap", "siren_ion_neon"]:  # the four of the first set; racial packs add more
		check(turrets.has(id), id + " is a turret")
	near(w.def("laser_turret_mk1")["damage"], 0.6 * w.def("laser_mk1")["damage"], "the Concord Point Turret against Laser Mk1", 1e-9)
	eq([float(w.defs["laser_turret_mk1"]["arc"]), float(w.defs["laser_turret_mk1"]["track"]), float(w.defs["laser_turret_mk1"]["accuracy"]), float(w.defs["laser_turret_mk1"]["cooldown"])], [270.0, 120.0, 0.8, 4.0], "arc 270, 120 degrees a second, accuracy 0.8, cooldown 4")


func test_a_turret_turns_at_its_track_rate_and_stops_at_the_edge_of_its_arc() -> void:
	var g := _gun("laser_turret_mk1")  # arc 270, 120 deg/s
	var a: Arena = g["arena"]
	var m: Dictionary = a.ships[0].mounts[g["uid"]]
	a.autofire[0] = false
	var t := _target(a, Vector2(900.0, 0.0))  # 90 degrees to the right of the muzzle's way
	for i in 30:  # half a second
		a.step(DT)
	near(rad_to_deg(Vector2(m["dir"]).angle_to(m["aim"])), 60.0, "half a second at 120 degrees a second", 0.6)
	for i in 60:
		a.step(DT)
	near(rad_to_deg(Vector2(m["dir"]).angle_to(m["aim"])), 90.0, "then it is on the target", 6.0)
	a.ships[t].flight.pos = Vector2(-900.0, 900.0)  # behind and to the left: 225 degrees round, outside the 270 degree arc
	for i in 240:
		a.step(DT)
	near(rad_to_deg(Vector2(m["dir"]).angle_to(m["aim"])), -135.0, "it stops at the edge of its arc, 135 degrees either way", 0.6)
	a.ships[t].flight.pos = Vector2(0.0, 1500.0)  # straight behind: outside the arc
	a.step(DT)
	eq(a.weapons.can_fire(a, 0, g["uid"], Vector2.ZERO), "out of arc", "an enemy outside the arc cannot be shot at")


func test_a_turret_fires_by_itself_when_loaded_and_on_target_and_t_stops_it() -> void:
	var g := _gun("laser_turret_mk1")
	var a: Arena = g["arena"]
	_target(a, Vector2(0.0, -700.0))
	for i in 120:
		a.step(DT)
	check(_shots(a).size() >= 1, "it opens fire with nobody touching anything (%d shots)" % _shots(a).size())
	var n := _shots(a).size()
	a.autofire[0] = false
	for i in 600:
		a.step(DT)
	eq(_shots(a).size(), n, "with autofire off it holds fire")
	a.autofire[0] = true
	for i in 300:
		a.step(DT)
	check(_shots(a).size() > n, "and fires again when it is back on")
	var s := Session.new()
	s.start(Session.load_ship(PIRATE), Session.load_ship(PIRATE), 1)
	eq(s.arena.autofire.get(Session.PLAYER, true), true, "autofire starts on")
	eq(s.toggle_autofire(), false, "T turns it off")
	eq(s.toggle_autofire(), true, "and on again")


func test_the_hit_roll_goes_by_accuracy_less_evasion_and_replays_for_a_seed() -> void:
	var results := []
	for run in 2:
		var g := _gun("laser_turret_mk1")
		var a: Arena = g["arena"]
		a.rng.seed = 99
		var t := _target(a, Vector2(0.0, -700.0))
		var weapons: Weapons = a.weapons
		near(weapons.hit_chance(a, 0, g["uid"], t), 0.8, "a target at rest is hit 80 percent of the time", 1e-9)
		var top: float = a.ships[t].flight.max_speed
		a.ships[t].flight.vel = Vector2(0.0, -top)
		near(weapons.hit_chance(a, 0, g["uid"], t), 0.8 - 0.25, "at full speed its evasion is 0.25", 1e-9)
		a.ships[t].flight.vel = Vector2(0.0, -top / 2.0)
		a.ships[t].ship.manned[1] = "Ada"  # nobody at a helm: no bonus
		near(weapons.hit_chance(a, 0, g["uid"], t), 0.8 - 0.125, "half speed, half the evasion", 1e-9)
		a.ships[t].flight.vel = Vector2.ZERO
		var m: Dictionary = a.ships[0].mounts[g["uid"]]
		var pivot: Vector2 = a.local_to_world(0, m["pos"])
		var points := []
		var hits := 0
		var radius: float = Collisions.hit_cells(a, t)["radius"]
		for k in 400:
			var w: Dictionary = weapons.def(m["id"])
			var p: Vector2 = weapons._turret_point(a, 0, g["uid"], m, w, t)
			points.append(p)
			hits += int(p.distance_to(a.ships[t].flight.pos) < radius)
		near(float(hits) / 400.0, 0.8, "400 shots: about 80 percent aimed at the hull", 0.06)
		results.append(points)
	eq(results[0], results[1], "the same seed gives the same shots, cell for cell")


func test_a_hit_aims_at_an_outer_cell_facing_the_turret_and_a_miss_just_off_the_hull() -> void:
	var g := _gun("laser_turret_mk1")
	var a: Arena = g["arena"]
	var t := _target(a, Vector2(0.0, -700.0))
	var m: Dictionary = a.ships[0].mounts[g["uid"]]
	var pivot: Vector2 = a.local_to_world(0, m["pos"])
	var facing: Array = a.weapons.facing_cells(a, t, pivot)
	check(facing.size() >= 9, "the near face of the block (%d cells)" % facing.size())
	for c in facing:
		check(a.cell_to_world(t, c).y > a.ships[t].flight.pos.y - 5.0, "%s is on the side toward the turret" % str(c))
	var w: Dictionary = a.weapons.def(m["id"])
	var outside := 0
	for k in 300:
		var p: Vector2 = a.weapons._turret_point(a, 0, g["uid"], m, w, t)
		var cell: Vector2i = a.world_to_cell(t, p)
		var on_face := facing.has(cell)
		var radius: float = Collisions.hit_cells(a, t)["radius"]
		if not on_face:
			outside += 1
			check(p.distance_to(a.ships[t].flight.pos) >= radius + 20.0, "a miss is past the hull's edge, %d px from its middle" % p.distance_to(a.ships[t].flight.pos))
	check(outside > 30 and outside < 90, "about one shot in five misses (%d of 300)" % outside)


# --- engines and steering -------------------------------------------------------------------------------

## Engine Mk1s turned `rots` (bare: no wall needed) in a row on the floor of a wall ship, with a reactor and
## a helm and one cable bus along the floor's top row, all powered.
func _engine_ship(rots: Array) -> Arena:
	var a := Arena.new(1)
	a.add_ship(_engine_ship_ship(rots))
	return a


## The ship of _engine_ship().
func _engine_ship_ship(rots: Array) -> Ship:
	var ship := Wall.wall_ship(1)  # floor x 8..22, y 16..21
	ship.components.place(ship.grid, "reactor_mk1", Vector2i(8, 17), 0)
	ship.components.place(ship.grid, "helm", Vector2i(12, 17), 0)
	var x := 14
	var tops := [Vector2i(8, 17), Vector2i(12, 17)]
	for rot in rots:
		check(ship.components.place(ship.grid, "engine_mk1", Vector2i(x, 17), rot) >= 0, "(setup: engine at %d turned %d)" % [x, rot])
		tops.append(Vector2i(x, 17))
		x += 4 if rot % 2 == 0 else 2
	for cell in Mounts.rect_cells(Rect2i(Vector2i(8, 16), Vector2i(x - 8, 1))):
		ship.cables.place(ship.grid, cell)
	for cell in tops:
		ship.cables.place(ship.grid, cell)
	ship.refresh()
	return ship


func test_thrust_follows_the_nozzle_rear_engines_all_forward_side_engines_only_sideways() -> void:
	var one := 10.0  # engine_mk1
	var rear := _engine_ship([2])
	near(rear.ships[0].thrusts["fwd"], one, "rear: all forward", 1e-6)
	eq([rear.ships[0].thrusts["left"], rear.ships[0].thrusts["right"]], [0.0, 0.0], "and nothing sideways")
	var right_wall := _engine_ship([1])  # nozzle to the right: pushes the ship left
	near(right_wall.ships[0].thrusts["fwd"], 0.0, "an engine on a side wall gives no forward thrust", 1e-6)
	near(right_wall.ships[0].thrusts["left"], one, "a nozzle pointing right pushes the ship left", 1e-6)
	near(right_wall.ships[0].thrusts["right"], 0.0, "and not right", 1e-6)
	var left_wall := _engine_ship([3])
	near(left_wall.ships[0].thrusts["right"], one, "a nozzle pointing left pushes the ship right", 1e-6)
	var pair := _engine_ship([1, 3])
	eq([pair.ships[0].thrusts["fwd"], pair.ships[0].thrusts["left"], pair.ships[0].thrusts["right"]], [0.0, one, one], "a side pair: strafe both ways, no forward")
	near(pair.ships[0].thrust, 2.0 * one, "though all of it turns the ship", 1e-6)
	var front := _engine_ship([2, 0])
	near(front.ships[0].thrusts["fwd"], 0.0, "a front-facing engine cancels a rear one", 1e-6)


func test_an_angled_engine_gives_cos_forward_and_sin_sideways() -> void:
	var half := Flight.split(10.0, Vector2(sin(deg_to_rad(30.0)), -cos(deg_to_rad(30.0))))  # pushing 30 degrees right of forward
	near(half.y, 10.0 * cos(deg_to_rad(30.0)), "forward is thrust x cos", 1e-5)
	near(half.x, 10.0 * sin(deg_to_rad(30.0)), "sideways is thrust x sin", 1e-5)
	eq(Flight.split(10.0, Vector2.UP), Vector2(0.0, 10.0), "straight forward")
	near(Flight.split(10.0, Vector2.DOWN).y, -10.0, "straight back", 1e-9)
	near(Flight.split(10.0, Vector2.LEFT).x, -10.0, "straight left", 1e-9)


func test_the_ship_moves_the_way_the_engines_push() -> void:
	var a := _engine_ship([2, 1, 3])
	a.set_input(0, 1.0, 0.0)
	a.step(1.0)
	check(a.ships[0].flight.vel.y < -1.0 and absf(a.ships[0].flight.vel.x) < 1e-6, "W: forward along the nose")
	a = _engine_ship([2, 1, 3])
	a.set_input(0, 0.0, 0.0, 1.0)
	a.step(1.0)
	check(a.ships[0].flight.vel.x > 1.0 and absf(a.ships[0].flight.vel.y) < 1e-6, "D: strafe to the right, the nose does not turn")
	near(a.ships[0].flight.angle, 0.0, "and the heading is the same", 1e-9)
	a = _engine_ship([2, 1, 3])
	a.set_input(0, 0.0, 0.0, -1.0)
	a.step(1.0)
	check(a.ships[0].flight.vel.x < -1.0, "A: strafe to the left")
	a = _engine_ship([2])
	a.set_input(0, 0.0, 0.0, 1.0)
	a.step(1.0)
	eq(a.ships[0].flight.vel, Vector2.ZERO, "no side engines, no strafe")
	a = _engine_ship([2, 1, 3])
	a.ships[0].flight.angle = PI / 2.0
	a.set_input(0, 0.0, 0.0, 1.0)
	a.step(1.0)
	check(a.ships[0].flight.vel.y > 1.0, "strafing is the ship's own right: turned a quarter it is the world's down")


func test_the_ship_turns_toward_the_mouse_and_the_keys_mode_still_turns_with_a_and_d() -> void:
	var s := Session.new()
	s.start(_engine_ship_ship([2, 1, 3]), _engine_ship_ship([2]), 3)  # a rear engine and a strafe pair against an unarmed ship (the Courier starts without a pair, and a pirate would shoot the bare engines off)
	var co = s.arena.ships[Session.PLAYER]
	eq(co.flight.steer, "mouse", "data/flight.json: the mouse steers")
	s.cursor = Vector2(1000.0, 0.0)  # due east
	for i in 240:
		s.tick(DT)
	near(co.flight.angle, PI / 2.0, "the nose comes round to the cursor and stops there", 0.06)
	s.cursor = Vector2(-1000.0, 0.0)
	for i in 480:
		s.tick(DT)
	near(absf(co.flight.angle), PI / 2.0, "and goes round the other way when the cursor does: now due west (-90 degrees)", 0.08)
	check(co.flight.angle < 0.0, "counter-clockwise")
	s.input = {"throttle": 0.0, "turn": 1.0, "strafe": 1.0}
	var angle: float = co.flight.angle
	var x: float = co.flight.pos.x
	for i in 30:
		s.tick(DT)
	check(absf(co.flight.angle - angle) < 0.02, "with the mouse steering A/D do not turn")
	check(co.flight.pos.x != x or co.flight.vel.length() > 1.0, "they strafe")
	co.flight.steer = "keys"
	s.input = {"throttle": 0.0, "turn": 1.0, "strafe": 1.0}
	var before: float = co.flight.angle
	co.flight.ang_vel = 0.0
	for i in 20:  # a light ship turns fast: a longer wait would wrap past half a turn
		s.tick(DT)
	check(co.flight.angle - before > 0.1, "keys steering: D turns clockwise")
	s.cursor = null
	co.flight.steer = "mouse"
	s.input = {"throttle": 0.0, "turn": 1.0, "strafe": 0.0}
	co.flight.ang_vel = 0.0
	before = co.flight.angle
	for i in 20:  # a light ship turns fast: a longer wait would wrap past half a turn
		s.tick(DT)
	check(co.flight.angle - before > 0.1, "and with no cursor yet the keys work too")


func test_the_helm_input_of_a_session_is_pure_data() -> void:
	var s := Session.new()
	s.start(Session.load_ship(PIRATE), Session.load_ship(PIRATE), 1)
	s.input = {"throttle": 0.5, "turn": 0.7, "strafe": -1.0}
	eq(s.helm_input(), {"throttle": 0.5, "turn": 0.7, "strafe": 0.0}, "no cursor: the keys turn, nothing strafes")
	s.cursor = s.arena.ships[Session.PLAYER].flight.pos + Vector2(0.0, -500.0)
	eq(s.helm_input()["strafe"], -1.0, "a cursor: A strafes")
	near(s.helm_input()["turn"], 0.0, "and straight ahead needs no turn", 1e-2)
	s.cursor = s.arena.ships[Session.PLAYER].flight.pos + Vector2(10.0, 0.0)
	near(s.helm_input()["turn"], 0.0, "a cursor on top of the ship does not spin it", 1e-9)


# --- the pilot ------------------------------------------------------------------------------------------

func test_the_pilot_aims_with_an_error_that_shrinks_with_its_skill() -> void:
	for skill in [0.0, 0.4, 0.5, 0.6, 0.85, 1.0]:
		var a := Arena.new(11)
		a.add_ship(Session.load_ship(PIRATE), Vector2.ZERO)
		a.add_ship(Session.load_ship(PIRATE), Vector2(0.0, -1200.0), PI)
		var ai := PilotAI.new(a, 0, 1, {"aim_skill": skill})
		var limit := deg_to_rad((1.0 - skill) * PilotAI.AIM_ERROR_DEG)
		var worst := 0.0
		var m: Dictionary = a.ships[0].mounts[1]
		var origin: Vector2 = a.local_to_world(0, m["pos"])
		for k in 200:
			ai.think(0.6)  # a retarget each time: a new error
			var perfect: Vector2 = ai.aim_for(m, false) - origin
			var got: Vector2 = ai.aim_for(m, true) - origin
			worst = maxf(worst, absf(perfect.angle_to(got)))
		check(worst <= limit + 1e-6, "skill %.2f: never off by more than %.2f degrees (worst %.2f)" % [skill, rad_to_deg(limit), rad_to_deg(worst)])
		if skill < 0.9:
			check(worst > limit * 0.5, "skill %.2f: it does err (worst %.2f of %.2f)" % [skill, rad_to_deg(worst), rad_to_deg(limit)])
	eq(PilotAI.DEFAULT_AIM_SKILL, 0.6, "the default skill is 0.6")
	var a := Arena.new(1)
	a.add_ship(Session.load_ship(PIRATE))
	a.add_ship(Session.load_ship(PIRATE))
	eq(PilotAI.new(a, 0, 1).aim_skill, 0.6, "a design with no ai entry")
	eq(PilotAI.new(a, 0, 1, Session.load_ship(PIRATE).get_meta("ai")).aim_skill, 0.5, "the pirate: 0.5")
	eq(PilotAI.new(a, 0, 1, Session.spawn_rammer().get_meta("ai")).aim_skill, 0.4, "the rammer: 0.4")


func test_the_pilot_points_its_nose_at_you_and_hits_with_its_fixed_gun() -> void:
	var s := Session.new()
	s.start(Session.load_ship("res://data/ships/starter_rustbucket.json"), Session.load_ship(PIRATE), 4)
	var laser_hits := 0
	for i in 60 * 30:
		s.tick(DT)
	for e in s.arena.events:
		laser_hits += int(e["type"] == "hit" and e["ship"] == Session.PLAYER and not e.get("ram", false))
	var shots := s.arena.events.filter(func(e): return e["type"] == "shot" and e["ship"] == Session.ENEMY and e["weapon"] == "laser_mk1")
	check(shots.size() >= 5, "its fixed laser fires (%d shots)" % shots.size())
	check(laser_hits >= 3, "and some of it lands (%d hits on the player)" % laser_hits)


func test_the_pilot_never_clips_your_hull_in_a_minute() -> void:
	for key in ["starter_rustbucket", "starter_courier", "starter_prism"]:
		var s := Session.new()
		s.start(Session.load_ship("res://data/ships/%s.json" % key), Session.load_ship(PIRATE), 6)
		var closest := INF
		for i in 60 * 60:
			s.tick(DT)
			closest = minf(closest, s.distance())
		var rams := s.arena.events.filter(func(e): return e["type"] == "ram")
		eq(rams.size(), 0, "%s: not one collision in a minute (the centres came as close as %d px, the hulls reach %d and %d)" % [key, closest, Collisions.hit_cells(s.arena, 0)["radius"], Collisions.hit_cells(s.arena, 1)["radius"]])
		check(s.arena.contact_tick.is_empty(), "%s: the hulls never touched" % key)
