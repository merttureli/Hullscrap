extends "res://tests/base_test.gd"
## Ships as rigid bodies (scripts/combat/collisions.gd, docs/CONTENT.md 4e): contacts on the cells'
## real polygons, the impulse with restitution and spin, the ram damage and its quirks, the
## dampener, crew knocks, the battering bow's tether, wrecks, determinism; and the rammer pilot.
## Test ships are hollow frames of wall (hp 1000, so nothing breaks unless a test wants it), with no
## drag, A at x = -300 flying right and B at x = 300 flying left.

const Arena = preload("res://scripts/combat/arena.gd")
const Collisions = preload("res://scripts/combat/collisions.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")

const DT := 1.0 / 60.0
const K := 1e-4  ## damage_k for the tests that count damage: big enough to read, small enough for the 1000 hp walls

var arena: Arena


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## A hollow frame w x h cells: a ring of `wall` round floor, in a 41x41 grid. The hull is exactly the
## frame, so the ship's pivot is its middle. Its east column cells are `nose` where that is not "".
func _frame(w: int, h: int, nose := "") -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	for id in ["wall", "ram_plating", "scrap_plate"]:
		defs.by_id[id]["hp"] = 1000
	var g := ShipGrid.new(Vector2i(41, 41), defs)
	var x0 := (41 - w) / 2
	var y0 := (41 - h) / 2
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			var c := Vector2i(x, y)
			g.hull[c] = true
			var edge: bool = x == x0 or y == y0 or x == x0 + w - 1 or y == y0 + h - 1
			g.force_tile(c, "wall" if edge else "floor")
			if nose != "" and x == x0 + w - 1:
				g.force_tile(c, nose)
	return Ship.new("t", g)


## A frame ship each side of the origin, at x = -away and +away, flying at each other at `va` and `vb` px/s.
func _pair(a: Ship, b: Ship, va := 150.0, vb := 150.0, k := K, away := 300.0) -> void:
	arena = Arena.new(1)
	arena.collision["damage_k"] = k
	arena.add_ship(a, Vector2(-away, 0.0))
	arena.add_ship(b, Vector2(away, 0.0), 0.0)
	for i in 2:
		arena.ships[i].flight.linear_damping = 0.0
		arena.ships[i].flight.angular_damping = 0.0
	arena.ships[0].flight.vel = Vector2(va, 0.0)
	arena.ships[1].flight.vel = Vector2(-vb, 0.0)


func _run(seconds: float) -> void:
	for i in int(round(seconds / DT)):
		arena.step(DT)


func _events(type: String) -> Array:
	return arena.events.filter(func(e): return e["type"] == type)


## The hp ship `idx` lost to collisions (the "dealt" of its ram hits).
func _dealt(idx: int) -> float:
	var total := 0.0
	for e in arena.events:
		if e["type"] == "hit" and e["ship"] == idx and e.get("ram", false):
			total += e["dealt"]
	return total


func _momentum() -> Vector2:
	var p := Vector2.ZERO
	for co in arena.ships:
		p += co.mass * co.flight.vel
	return p


# --- response --------------------------------------------------------------------------------------

func test_a_head_on_collision_separates_and_exchanges_momentum() -> void:
	_pair(_frame(12, 8), _frame(12, 8))
	var p0 := _momentum()
	_run(0.7)
	eq(_events("ram").size(), 0, "(not touching yet)")
	_run(1.5)
	var a = arena.ships[0]
	var b = arena.ships[1]
	check(_momentum().distance_to(p0) < 0.002 * (a.mass + b.mass) * 150.0, "momentum is conserved: %s -> %s" % [str(p0), str(_momentum())])
	near(a.flight.vel.x, -30.0, "A is sent back at e x 150 = 30", 0.5)
	near(b.flight.vel.x, 30.0, "and B forward", 0.5)
	check(b.flight.pos.x - a.flight.pos.x > 12.0 * 32.0, "they have parted: %f apart" % (b.flight.pos.x - a.flight.pos.x))
	near(a.flight.ang_vel, 0.0, "a centred hit spins nobody", 1e-3)
	eq(_events("ram").size(), 1, "one collision, one event")
	var e: Dictionary = _events("ram")[0]
	eq([e["a"], e["b"]], [0, 1], "between ships 0 and 1")
	near(e["speed"], 300.0, "at 300 px/s closing", 0.01)
	near(e["energy"], 0.5 * (a.mass / 2.0) * 300.0 * 300.0, "E = 1/2 mu v^2, mu = m/2", 1.0)
	near(e["pos"].y, 0.0, "at the middle of the faces", 1.0)
	near(e["pos"].x, 0.0, "half way between them", 3.0)


func test_unequal_masses_conserve_momentum_and_bounce_by_the_restitution() -> void:
	_pair(_frame(14, 10), _frame(6, 4), 120.0, 60.0)
	var p0 := _momentum()
	var closing := 180.0
	_run(3.0)
	var a = arena.ships[0]
	var b = arena.ships[1]
	check(_momentum().distance_to(p0) < 0.003 * p0.length(), "momentum before %s after %s" % [str(p0), str(_momentum())])
	near(b.flight.vel.x - a.flight.vel.x, 0.2 * closing, "they part at 0.2 x the closing speed", 0.5)
	check(a.flight.vel.x < 120.0 and b.flight.vel.x > -60.0, "the light one turned round, the heavy one was slowed")
	near(a.flight.ang_vel, 0.0, "no spin from a centred hit", 1e-3)


func test_an_off_centre_hit_spins_both_ships() -> void:
	_pair(_frame(12, 8), _frame(12, 8))
	arena.ships[1].flight.pos.y = -100.0  # B sits 100 px higher: A hits its lower half, B hits A's upper half
	_run(2.0)
	check(arena.ships[1].flight.ang_vel < -0.01, "B, pushed on its low side, turns counter-clockwise: %f" % arena.ships[1].flight.ang_vel)
	check(arena.ships[0].flight.ang_vel < -0.01, "A, pushed back on its high side, does too: %f" % arena.ships[0].flight.ang_vel)
	_pair(_frame(12, 8), _frame(12, 8))
	_run(2.0)
	near(arena.ships[1].flight.ang_vel, 0.0, "while a centred hit does not", 1e-3)


func test_a_heavy_ship_spins_less_than_a_light_one_for_the_same_blow() -> void:
	_pair(_frame(12, 8), _frame(12, 8))
	arena.ships[1].flight.pos.y = -100.0
	_run(2.0)
	var light: float = absf(arena.ships[1].flight.ang_vel)
	_pair(_frame(12, 8), _frame(24, 16))
	arena.ships[1].flight.pos.y = -100.0
	_run(2.0)
	check(absf(arena.ships[1].flight.ang_vel) < light * 0.5, "the larger ship's inertia resists (%f vs %f)" % [absf(arena.ships[1].flight.ang_vel), light])


func test_polygons_not_squares_decide_a_touch() -> void:
	# One cell each, 25.6 px right and 19.2 px up from the other: the squares overlap at A's top-right corner.
	for shape in [{"shape": "tri", "rot": 0}, {}]:
		var a := _frame(1, 1)
		a.grid.force_tile(Vector2i(20, 20), "wall", shape)  # tri rot 0: solid below the diagonal; its top-right half is empty
		var b := _frame(1, 1)
		arena = Arena.new(1)
		arena.add_ship(a, Vector2.ZERO)
		arena.add_ship(b, Vector2(25.6, -19.2))
		Collisions.step(arena, DT)
		eq(arena.contact_tick.has(0), shape.is_empty(), "%s: the whole square touches, the slope's empty corner does not" % str(shape))


func test_below_the_minimum_speed_it_is_a_bump_not_a_blow() -> void:
	_pair(_frame(12, 8), _frame(12, 8), 15.0, 15.0, K, 204.0)  # 30 px/s closing, the minimum is 40; the faces start 24 px apart
	_run(3.0)
	eq(_events("ram").size(), 0, "no ram event")
	near(_dealt(0) + _dealt(1), 0.0, "no damage")
	check(arena.ships[0].flight.vel.x < 0.0 and arena.ships[1].flight.vel.x > 0.0, "but they still bounce apart")
	_pair(_frame(12, 8), _frame(12, 8), 25.0, 25.0, K, 204.0)
	_run(3.0)
	eq(_events("ram").size(), 1, "50 px/s closing is a ram")
	check(_dealt(0) > 0.0 and _dealt(1) > 0.0, "and both take damage")


func test_damage_goes_with_the_square_of_the_speed() -> void:
	var dealt := []
	for v in [75.0, 150.0, 300.0]:
		_pair(_frame(12, 8), _frame(12, 8), v, v)
		_run(2.5)
		dealt.append(_dealt(0))
	near(dealt[1] / dealt[0], 4.0, "twice the speed, four times the damage", 0.01)
	near(dealt[2] / dealt[1], 4.0, "and again", 0.01)
	near(_dealt(1), _dealt(0), "both ships take the same from equal plain frames", 1e-6)
	var e: Dictionary = _events("ram")[0]
	near(dealt[2], e["energy"] * K, "which is E x damage_k", 1e-6)


func test_two_couriers_head_on_at_150_each_lose_2_to_12_hull() -> void:  # was 8 to 12 before the guns stuck out (rams hit the outside halves first and those are not hull), then 4 to 8 with three guns on a flat nose, then 4 to 12 for the arrowhead with one gun on its tip; the Courier is now a light fuselage in a big empty frame (574 against 1009 mass), so the reduced mass and the hit are smaller
	arena = Arena.new(1)  # the real damage_k
	var a := Ship.from_design("res://data/ships/starter_courier.json")
	var b := Ship.from_design("res://data/ships/starter_courier.json")
	arena.add_ship(a, Vector2(0.0, 0.0), 0.0)
	arena.add_ship(b, Vector2(0.0, -700.0), PI)
	arena.ships[0].flight.vel = Vector2(0.0, -150.0)
	arena.ships[1].flight.vel = Vector2(0.0, 150.0)
	for co in arena.ships:
		co.flight.linear_damping = 0.0
	var h0: float = arena.ships[0].hull
	_run(4.0)
	var lost0: float = h0 - arena.ships[0].hull
	var lost1: float = h0 - arena.ships[1].hull
	check(lost0 >= 2.0 and lost0 <= 12.0, "courier A lost %f hull" % lost0)
	check(lost1 >= 2.0 and lost1 <= 12.0, "courier B lost %f hull" % lost1)
	var guns_hit := 0
	for e in arena.events:
		guns_hit += int(e["type"] == "hit" and e.get("half", "") == "out")
	check(guns_hit > 0, "and the gun housings on the noses took part of it (%d hits)" % guns_hit)
	check(not arena.ships[0].wrecked and not arena.ships[1].wrecked, "neither is wrecked")


func test_a_glancing_blow_does_less_by_the_slope_rule() -> void:
	_pair(_frame(12, 8), _frame(12, 8))
	arena.ships[0].flight.vel = Vector2(150.0, 150.0)  # in at 45 degrees to B's face; only the part along the face's normal counts as closing
	arena.ships[1].flight.vel = Vector2(-150.0, 0.0)
	_run(3.0)
	var e: Dictionary = _events("ram")[0]
	near(e["speed"], 300.0, "the closing speed is the normal part", 0.5)
	var share: float = _dealt(1) / (e["energy"] * K)
	check(share > 0.8 and share < 0.95, "relative velocity is (300, 150): cos to the face normal is 0.89, the damage share %f" % share)
	_pair(_frame(12, 8), _frame(12, 8))
	_run(3.0)
	near(_dealt(1) / (_events("ram")[0]["energy"] * K), 1.0, "head on it is whole", 1e-6)


# --- the ram quirks --------------------------------------------------------------------------------

func test_ram_plating_deals_double_and_takes_half() -> void:
	_pair(_frame(12, 8), _frame(12, 8))
	_run(2.5)
	var base: float = K * float(_events("ram")[0]["energy"])
	near(_dealt(0), base, "plain steel takes E k", 1e-6)
	near(_dealt(1), base, "and deals the same", 1e-6)
	_pair(_frame(12, 8, "ram_plating"), _frame(12, 8))
	_run(2.5)
	var e: float = K * float(_events("ram")[0]["energy"])
	near(_dealt(1), 2.0 * e, "a ram plated nose deals twice", 1e-6)
	near(_dealt(0), e * 0.5 * 0.4, "and takes half, less the plating's 0.4 kinetic resist", 1e-6)
	_pair(_frame(12, 8), _frame(12, 8, "ram_plating"))
	arena.ships[1].flight.angle = PI  # turned about, its plated east face meets A
	_run(2.5)
	near(_dealt(0), 2.0 * float(_events("ram")[0]["energy"]) * K, "the same the other way round", 1e-2)


func test_a_powered_dampener_halves_the_damage_to_plain_cells() -> void:
	var b := _frame(12, 8)
	var uid := _dampener_set(b)
	_pair(_frame(12, 8), b)
	check(arena.ships[1].powered.get(uid, false), "the dampener is powered")
	_run(2.5)
	var e: float = K * float(_events("ram")[0]["energy"])
	near(_dealt(1), 0.5 * e, "B's walls take half", 1e-6)
	near(_dealt(0), e, "A, with none, takes the lot", 1e-6)
	var c := _frame(12, 8)
	var dead := _dampener_set(c, false)  # no cable: it is not powered
	_pair(_frame(12, 8), c)
	check(not arena.ships[1].powered.get(dead, false), "an unwired dampener has no power")
	_run(2.5)
	near(_dealt(1), K * float(_events("ram")[0]["energy"]), "and does nothing", 1e-6)


## A reactor and a dampener on the floor of frame ship `s` (the west half, away from the nose), wired together when `wired`. Returns the dampener's uid.
func _dampener_set(s: Ship, wired := true) -> int:
	s.components.place(s.grid, "reactor_mk1", Vector2i(16, 18), 0)
	var uid: int = s.components.place(s.grid, "inertial_dampener", Vector2i(20, 18), 0)
	if wired:
		for x in range(17, 21):  # from the reactor's right-hand column (x 16..17) to the dampener
			s.cables.place(s.grid, Vector2i(x, 18))
	return uid


func test_crew_get_knocked_in_the_rooms_that_touch_the_impact() -> void:
	var b := _frame(12, 8)
	for y in range(17, 23):
		b.grid.force_tile(Vector2i(20, y), "wall")  # a fin from wall to wall: a west room (x 15..19) and an east room (x 21..24)
	_pair(_frame(12, 8), b)
	var west := CrewMember.new("w", Vector2(17.0, 20.0))  # in the room against B's west wall, the one that is hit
	var east := CrewMember.new("e", Vector2(23.0, 20.0))  # in the room behind the fin
	arena.ships[1].ship.crew.append(west)
	arena.ships[1].ship.crew.append(east)
	_run(2.5)
	near(west.hp, 100.0 - 5.0 * 300.0 / 100.0, "5 hp per 100 px/s of impact: 15 at 300", 1e-6)
	near(east.hp, 100.0, "the room that does not touch the impact is unhurt", 1e-6)


func test_a_dampener_stops_crew_knocks() -> void:
	var b := _frame(12, 8)
	_dampener_set(b)
	_pair(_frame(12, 8), b)
	var crew := CrewMember.new("c", Vector2(17.0, 22.0))
	arena.ships[1].ship.crew.append(crew)
	var other := CrewMember.new("o", Vector2(17.0, 22.0))
	arena.ships[0].ship.crew.append(other)
	_run(2.5)
	near(crew.hp, 100.0, "the dampened ship's crew keep their feet", 1e-6)
	check(other.hp < 100.0, "the other ship's crew do not")


func test_the_battering_bow_deals_triple_and_latches_for_three_seconds() -> void:
	var a := _frame(8, 4)  # cells x 16..23, y 18..21
	for y in [19, 20]:  # the bow at A's nose rows: 4x2 cells on floor, reaching the east edge
		a.grid.force_tile(Vector2i(23, y), "floor")
	check(a.components.place(a.grid, "battering_bow", Vector2i(20, 19), 0) > 0, "the bow is placed")
	var b := _frame(6, 2)  # as tall as the bow: only the bow meets it
	var k := 1e-6  # small, so the bow's 14 hp are not the limit
	_pair(a, b, 150.0, 150.0, k)
	_run(1.4)
	var e: float = k * float(_events("ram")[0]["energy"])
	near(_dealt(1), 3.0 * e, "B's cells that met the bow take triple", 1e-6)
	near(_dealt(0), e, "and the bow takes the plain share", 1e-6)
	eq(arena.tethers.size(), 1, "a tether is set")
	var t: Dictionary = arena.tethers[0]
	check(t["left"] > 2.4 and t["left"] <= 3.0, "which runs for 3 seconds from the hit (%f left)" % t["left"])
	# Pull B away at 120 px/s^2 and see whether the latch holds, then lets go.
	var gap0: float = arena.ships[1].flight.pos.x - arena.ships[0].flight.pos.x
	var seen_max := 0.0
	var released := -1.0
	for i in 360:
		arena.ships[1].flight.vel.x += 120.0 * DT
		arena.step(DT)
		if arena.tethers.is_empty() and released < 0.0:
			released = i * DT
		var held: float = arena.local_to_world(0, arena.tethers[0]["la"]).distance_to(arena.local_to_world(1, arena.tethers[0]["lb"])) if not arena.tethers.is_empty() else 0.0
		seen_max = maxf(seen_max, held)
		if not arena.tethers.is_empty():
			check(arena.ships[1].flight.pos.x - arena.ships[0].flight.pos.x < gap0 + 30.0, "still stuck at %.2f s: gap %f vs %f" % [i * DT, arena.ships[1].flight.pos.x - arena.ships[0].flight.pos.x, gap0])
	check(seen_max < 8.0, "the anchors never drifted more than a few px: %f" % seen_max)
	check(released > 2.3 and released < 3.2, "it let go after about 3 s (at %f)" % released)
	check(arena.ships[1].flight.pos.x - arena.ships[0].flight.pos.x > gap0 + 100.0, "and then B pulled away")
	# The same blow with plain frames: nothing holds.
	_pair(_frame(8, 4), _frame(6, 2), 150.0, 150.0, k)
	_run(1.4)
	eq(_events("ram").size(), 1, "(the same blow with plain frames)")
	eq(arena.tethers.size(), 0, "no bow, no tether")


func test_a_wreck_stays_solid_and_gets_pushed() -> void:
	_pair(_frame(12, 8), _frame(12, 8), 150.0, 0.0)
	arena.ships[1].flight.vel = Vector2.ZERO
	arena.wreck(1)
	check(arena.ships[1].wrecked, "B is a wreck")
	var x0: float = arena.ships[1].flight.pos.x
	_run(3.0)
	eq(_events("ram").size(), 1, "A rams it")
	check(arena.ships[1].flight.vel.x > 20.0, "the wreck is shoved on: %f" % arena.ships[1].flight.vel.x)
	check(arena.ships[1].flight.pos.x > x0 + 20.0, "and has moved")
	check(arena.ships[0].flight.vel.x < 150.0 * 0.7, "A was slowed by it, and did not pass through")
	check(arena.ships[0].flight.pos.x < arena.ships[1].flight.pos.x - 12.0 * 32.0 + 10.0, "A is still on its own side")


func test_collisions_are_deterministic() -> void:
	var snaps := []
	for run in 2:
		_pair(_frame(12, 8), _frame(14, 6, "ram_plating"), 170.0, 110.0)
		arena.ships[1].flight.pos.y = -90.0
		arena.ships[0].flight.angle = 0.1
		_run(3.0)
		snaps.append(arena.snapshot())
	eq(snaps[0], snaps[1], "the same start, the same state to the last bit")
	check(absf(snaps[0]["ships"][0]["ang_vel"]) > 0.0, "(and it was an interesting run)")


# --- the rammer ------------------------------------------------------------------------------------

func test_the_bow_is_the_side_with_the_most_ram_plating() -> void:
	var s := _frame(12, 8)
	arena = Arena.new(1)
	var i := arena.add_ship(s)
	eq(PilotAI.bow_of(arena.ships[i]), Vector2.UP, "no ram plating: forward")
	var west := _frame(12, 8)
	for y in range(18, 23):
		west.grid.force_tile(Vector2i(15, y), "ram_plating")
	for x in range(16, 19):
		west.grid.force_tile(Vector2i(x, 17), "ram_plating")
	eq(PilotAI.bow_of(arena.ships[arena.add_ship(west)]), Vector2.LEFT, "the west wall has the most")
	var tie := _frame(12, 8)
	tie.grid.force_tile(Vector2i(14, 20), "ram_plating")
	tie.grid.force_tile(Vector2i(20, 16), "ram_plating")
	eq(PilotAI.bow_of(arena.ships[arena.add_ship(tie)]), Vector2.UP, "a tie that includes forward keeps forward")
	var south := _frame(12, 8)
	south.grid.force_tile(Vector2i(20, 24), "ram_plating")
	eq(PilotAI.bow_of(arena.ships[arena.add_ship(south)]), Vector2.DOWN, "or one plate on the south side")


func test_the_rustfang_rammer_design() -> void:
	var ship := Session.spawn_rammer()
	check(ship != null, "the design loads")
	eq(ship.get_meta("ai"), {"style": "rammer", "aim_skill": 0.4, "morale": "ram"}, "and carries its pilot style, its poor aim and its morale")
	var plates := 0
	var slopes := 0
	for c in ship.grid.tiles:
		plates += int(ship.grid.tiles[c] == "ram_plating")
		slopes += int(ship.grid.shapes.has(c) and ship.grid.shapes[c]["shape"] == "tri")
	check(plates >= 20, "ram plating makes the bow (%d cells)" % plates)
	check(slopes >= 10, "its edges are slope45 cells (%d)" % slopes)
	var kick := 0
	var guns := 0
	for uid in ship.components.instances:
		var id: String = ship.components.instances[uid]["id"]
		kick += int(id == "engine_scrap_mk1")
		guns += int(ship.components.def(id)["family"] == "weapon")
	eq([kick, guns], [2, 1], "two Kickjets and a bow gun")
	arena = Arena.new(1)
	var i := arena.add_ship(ship)
	eq(PilotAI.bow_of(arena.ships[i]), Vector2.UP, "the bow is forward")
	eq(arena.ships[i].flight.can_fly(ship.components, arena.ships[i].powered), "", "it can fly")
	check(arena.ships[i].thrust * arena.ships[i].flight.thrust_to_accel / arena.ships[i].mass > 30.0, "and is not a brick")
	var pirate := Session.load_ship(Session.PIRATE_PATH)
	eq(pirate.get_meta("ai"), {"aim_skill": 0.5, "morale": "rustfang"}, "the pirate has no pilot style, only a middling aim and a Rustfang morale")


func _rammer_fight(target_path := "res://data/ships/starter_courier.json", seed_value := 3) -> Session:
	var s := Session.new()
	s.start(Ship.from_design(target_path), Session.spawn_rammer(), seed_value)
	return s


func test_the_rammer_closes_and_hits_a_stationary_target_within_10_seconds() -> void:
	var s := _rammer_fight()
	eq(s.ai.style, "rammer", "the enemy pilot is a rammer")
	var first := -1.0
	for i in 600:
		s.tick(DT)
		if first < 0.0 and s.arena.events.any(func(e): return e["type"] == "ram"):
			first = i * DT
	check(first > 0.0 and first < 10.0, "it rammed within 10 s (at %f)" % first)
	var tgt = s.arena.ships[Session.PLAYER]
	var hurt: bool = tgt.hull < tgt.hull_max or s.arena.events.any(func(e): return e["type"] == "hit" and e["ship"] == Session.PLAYER)  # the ram may only get as far as the gun housings on the nose
	check(hurt, "and hurt the target: %f of %f" % [tgt.hull, tgt.hull_max])
	check(s.arena.ships[Session.ENEMY].hull > 0.0 and not s.arena.ships[Session.ENEMY].wrecked, "the rammer is fine")


func test_the_rammer_uses_its_engine_ability_in_range_backs_off_and_comes_round() -> void:
	var s := _rammer_fight()
	var boost_at := -1.0
	var boost_dist := 0.0
	var rams: Array = []
	var min_throttle := 0.0
	for i in 60 * 16:
		s.tick(DT)
		min_throttle = minf(min_throttle, s.arena.ships[Session.ENEMY].input["throttle"])
		if boost_at < 0.0 and s.arena.events.any(func(e): return e["type"] == "ability" and e["ship"] == Session.ENEMY):
			boost_at = i * DT
			boost_dist = s.distance()
	check(boost_at > 0.0, "it fired its engine ability")
	var courier_reach: float = Collisions.hit_cells(s.arena, Session.PLAYER)["radius"]
	check(boost_dist - courier_reach < 620.0, "inside 600 px of the target's hull (centres %f apart, its reach %f)" % [boost_dist, courier_reach])
	for e in s.arena.events:
		if e["type"] == "ram":
			rams.append(e["tick"])
	check(rams.size() >= 2, "it came round and hit again (%d collisions)" % rams.size())
	check(rams.size() < 2 or rams[rams.size() - 1] - rams[0] > 2.0 / DT, "with the backing off in between")
	check(min_throttle < 0.0, "which was a reverse (%f)" % min_throttle)


func test_the_rammer_aims_its_bow_at_the_target() -> void:
	var s := _rammer_fight()
	for i in 90:
		s.tick(DT)
	var rammer = s.arena.ships[Session.ENEMY]
	var heading := Vector2.UP.rotated(rammer.flight.angle)
	var to_target: Vector2 = (s.arena.ships[Session.PLAYER].flight.pos - rammer.flight.pos).normalized()
	check(heading.dot(to_target) > 0.98, "the bow points at the target (cos %f)" % heading.dot(to_target))
	check(s.arena.ships[Session.ENEMY].input["throttle"] > 0.99, "at full throttle")
