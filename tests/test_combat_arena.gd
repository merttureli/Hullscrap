extends "res://tests/base_test.gd"
## The arena: transforms, substeps, weapon arcs and cooldowns, projectiles that need leading,
## hull integrity and wrecks, and determinism.

const Arena = preload("res://scripts/combat/arena.gd")
const Damage = preload("res://scripts/combat/damage.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")


## A 31x31 ship (hull cells 0..30, centre at cell coordinates 15.5, 15.5) with floor everywhere.
func _ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	for c in g.hull:
		g.force_tile(c, "floor")
	return Ship.new("t", g)


func _tile(s: Ship, x: int, y: int, id: String) -> void:
	s.grid.force_tile(Vector2i(x, y), id)


func _block(s: Ship, x0: int, y0: int, x1: int, y1: int, id: String) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_tile(s, x, y, id)


func _count(a: Arena, type: String, ship := -1) -> int:
	var n := 0
	for e in a.events:
		if e["type"] == type and (ship < 0 or e["ship"] == ship):
			n += 1
	return n


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func test_cells_and_world_round_trip_at_any_angle() -> void:
	for angle in [0.0, PI / 2.0, deg_to_rad(37.0), -2.4]:
		var a := Arena.new()
		var i := a.add_ship(_ship(), Vector2(123.0, -45.0), angle)
		for c in [Vector2i(0, 15), Vector2i(15, 15), Vector2i(30, 7), Vector2i(3, 28), Vector2i(22, 9)]:
			var w := a.cell_to_world(i, c)
			eq(a.world_to_cell(i, w), c, "cell %s at %.2f rad" % [str(c), angle])
			for off in [Vector2(0.4, 0.4), Vector2(-0.4, 0.4), Vector2(0.4, -0.4), Vector2(-0.4, -0.4)]:
				eq(a.world_to_cell(i, w + (off * Arena.CELL).rotated(angle)), c, "inside cell %s at %.2f rad" % [str(c), angle])
			var l := a.world_to_local(i, w)
			near(a.local_to_world(i, l).distance_to(w), 0.0, "local round trip")
	var a := Arena.new()
	var i := a.add_ship(_ship(), Vector2(100.0, 100.0), 0.0)
	eq(a.cell_to_world(i, Vector2i(15, 15)), Vector2(100.0, 100.0), "the centre cell sits on the body position")
	eq(a.cell_to_world(i, Vector2i(20, 15)), Vector2(260.0, 100.0), "5 cells right of the centre, unrotated")
	a.ships[i].flight.angle = PI / 2.0
	check(a.cell_to_world(i, Vector2i(20, 15)).distance_to(Vector2(100.0, 260.0)) < 1e-3, "a quarter turn clockwise puts it below")
	a.ships[i].flight.angle = deg_to_rad(37.0)
	near(a.cell_to_world(i, Vector2i(20, 15)).distance_to(Vector2(100.0, 100.0)), 160.0, "rotation keeps distances")


func test_the_pivot_is_the_centre_of_the_hull_box() -> void:
	var s := _ship()
	s.grid.hull.clear()
	for y in range(4, 10):  # a lopsided hull: cells 10..19 x 4..9
		for x in range(10, 20):
			s.grid.hull[Vector2i(x, y)] = true
	var a := Arena.new()
	var i := a.add_ship(s, Vector2(50.0, 50.0))
	eq(a.ships[i].pivot, Vector2(15.0, 7.0), "centre of the box")
	eq(a.ships[i].half, Vector2(5.0, 3.0), "half extents")
	eq(a.cell_to_world(i, Vector2i(15, 7)), Vector2(66.0, 66.0), "the cell just right of and below the pivot")


func test_step_runs_whole_substeps_and_moves_ships() -> void:
	var a := Arena.new()
	var i := a.add_ship(_ship())
	a.ships[i].flight.linear_damping = 0.0
	a.ships[i].flight.vel = Vector2(100.0, 0.0)
	a.step(0.01)
	eq(a.tick, 0, "less than a substep waits")
	a.step(0.01)
	eq(a.tick, 1, "two halves make a substep")
	a.step(1.0)
	eq(a.tick, 61, "a second is 60 substeps")
	near(a.time(), 61.0 / 60.0, "time")
	near(a.ships[i].flight.pos.x, 100.0 * 61.0 / 60.0, "moved by its velocity", 1e-3)


## The direction (world) of the newest "shot" event.
func _last_shot_dir(a: Arena) -> Vector2:
	for k in range(a.events.size() - 1, -1, -1):
		if a.events[k]["type"] == "shot":
			return a.events[k]["dir"]
	return Vector2.ZERO


func test_a_fixed_gun_fires_along_its_mount_within_its_gimbal() -> void:
	var a := Arena.new()
	var i := a.add_ship(_ship())
	var east := a.add_mount(i, "laser_mk1", Vector2(20.5, 15.5))  # 5 cells right of the centre: it points east
	var far := 1000.0
	var at := a.local_to_world(i, Vector2(20.5, 15.5))
	check(a.fire(i, east, at + Vector2(far, 0.0)), "fires straight out")
	near(_last_shot_dir(a).angle(), 0.0, "along its mount", 1e-6)
	a.ships[i].cooldowns.clear()
	check(a.fire(i, east, at + Vector2.from_angle(deg_to_rad(3.0)) * far), "3 degrees off")
	near(rad_to_deg(_last_shot_dir(a).angle()), 3.0, "inside the 5 degree gimbal the barrel follows the aim", 1e-4)
	a.ships[i].cooldowns.clear()
	check(a.fire(i, east, at + Vector2.from_angle(deg_to_rad(55.0)) * far), "55 degrees off still fires")
	near(rad_to_deg(_last_shot_dir(a).angle()), 5.0, "but only 5 degrees round: the ship is aimed, not the gun", 1e-4)
	a.ships[i].cooldowns.clear()
	check(a.fire(i, east, at + Vector2.from_angle(deg_to_rad(-20.0)) * far), "20 degrees the other way")
	near(rad_to_deg(_last_shot_dir(a).angle()), -5.0, "clamped on that side too", 1e-4)
	a.ships[i].cooldowns.clear()
	check(a.fire(i, east, at + Vector2(-far, 0.0)), "aimed behind it fires too")
	near(absf(rad_to_deg(_last_shot_dir(a).angle())), 5.0, "along the edge of the cone", 1e-4)
	check(a.weapons.in_arc(a, i, a.ships[i].mounts[east], at + Vector2.from_angle(deg_to_rad(4.0)) * far), "in_arc: the aim point is inside the cone")
	check(not a.weapons.in_arc(a, i, a.ships[i].mounts[east], at + Vector2.from_angle(deg_to_rad(6.0)) * far), "and 6 degrees is outside it")
	a.ships[i].cooldowns.clear()
	a.ships[i].flight.angle = PI / 2.0  # the east mount now faces south
	at = a.local_to_world(i, Vector2(20.5, 15.5))
	a.fire(i, east, at + Vector2(far, 0.0))
	near(_last_shot_dir(a).angle(), PI / 2.0 - deg_to_rad(5.0), "after the ship turned the gun points south: east is 90 degrees off, so the cone's edge", 1e-4)
	a.ships[i].cooldowns.clear()
	a.fire(i, east, at + Vector2(0.0, far))
	near(_last_shot_dir(a).angle(), PI / 2.0, "and south is straight on", 1e-4)
	var gun := a.add_mount(i, "test_bolt", Vector2(20.5, 15.5))
	eq(a.weapons.can_fire(a, i, gun, Vector2(-far, 0.0)), "", "a test gun has a 180 degree gimbal: it fires anywhere")
	eq(a.weapons.can_fire(a, i, 99, Vector2(far, 0.0)), "no such weapon", "unknown mount")


func test_a_mount_added_with_a_direction_points_that_way() -> void:
	var a := Arena.new()
	var i := a.add_ship(_ship())
	var up := a.add_mount(i, "laser_mk1", Vector2(15.5, 10.5), true, Vector2.UP)
	a.fire(i, up, a.local_to_world(i, Vector2(15.5, 10.5)) + Vector2(1000.0, 0.0))
	near(rad_to_deg(_last_shot_dir(a).angle()), -90.0 + 5.0, "a gun that points up, aimed east, goes 5 degrees clockwise of up", 1e-4)
	var centre := a.add_mount(i, "laser_mk1", Vector2(15.5, 15.5))
	eq(a.ships[i].mounts[centre]["dir"], Vector2.UP, "a mount in the middle of the ship points up")


func test_cooldown_is_respected() -> void:
	var a := Arena.new()
	var i := a.add_ship(_ship())
	var uid := a.add_mount(i, "laser_mk1", Vector2(20.5, 15.5))  # cooldown 2.1 s
	var aim := Vector2(1000.0, 0.0)
	check(a.fire(i, uid, aim), "first shot")
	eq(a.weapons.can_fire(a, i, uid, aim), "cooling down", "right away")
	near(a.cooldown_left(i, uid), 2.1, "full cooldown", 1e-3)
	a.step(1.9)
	check(not a.fire(i, uid, aim), "still cooling after 1.9 s")
	a.step(0.1)
	check(not a.fire(i, uid, aim), "still cooling after 2.0 s")
	a.step(0.11)
	check(a.fire(i, uid, aim), "ready after 2.1 s")
	eq(_count(a, "shot"), 2, "two shots logged")


func test_wrecked_and_unpowered_weapons_refuse() -> void:
	var a := Arena.new()
	var i := a.add_ship(_ship())
	var off := a.add_mount(i, "laser_mk1", Vector2(20.5, 15.5), false)
	var on := a.add_mount(i, "laser_mk1", Vector2(20.5, 15.5))
	eq(a.weapons.can_fire(a, i, off, Vector2(1000.0, 0.0)), "unpowered", "an unpowered mount")
	a.wreck(i)
	eq(a.weapons.can_fire(a, i, on, Vector2(1000.0, 0.0)), "wrecked", "a wreck")


## A placed laser fires only with power: reactor and laser joined by a cable.
func test_a_placed_laser_needs_power() -> void:
	var s := _ship()
	var laser := s.components.place(s.grid, "laser_mk1", Vector2i(20, 14), 0)
	var reactor := s.components.place(s.grid, "reactor_mk1", Vector2i(20, 16), 0)
	check(laser > 0 and reactor > 0, "parts placed")
	var a := Arena.new()
	var i := a.add_ship(s)
	eq(a.ships[i].mounts.keys(), [laser], "the laser is a mount, the reactor is not")
	near((a.ships[i].mounts[laser]["pos"] as Vector2).distance_to(Vector2(21.0, 15.0)), 0.0, "mount at the centre of its (2x2) footprint")
	eq(a.weapons.can_fire(a, i, laser, Vector2(1000.0, 0.0)), "unpowered", "no cable yet")
	s.cables.place(s.grid, Vector2i(20, 15))
	s.cables.place(s.grid, Vector2i(20, 16))
	a.ships[i].dirty = true
	eq(a.weapons.can_fire(a, i, laser, Vector2(1000.0, 0.0)), "", "powered")
	eq(a.weapons.can_fire(a, i, laser, Vector2(-1000.0, 0.0)), "", "a fixed gun is never out of arc: it fires along its own direction")
	check(not a.weapons.in_arc(a, i, a.ships[i].mounts[laser], Vector2(-1000.0, 0.0)), "though the aim point is far outside its cone")


## The shot that must be led: the speed of the bolt against a target on the move.
func _lead(m: Vector2, p: Vector2, v: Vector2, speed: float) -> Vector2:
	var r := p - m
	var qa := v.dot(v) - speed * speed
	var qb := 2.0 * r.dot(v)
	var qc := r.dot(r)
	var s := sqrt(qb * qb - 4.0 * qa * qc)
	var t := maxf((-qb + s) / (2.0 * qa), (-qb - s) / (2.0 * qa))
	return p + v * t


func _chase(aim_at_lead: bool) -> Arena:
	var a := Arena.new()
	var shooter := a.add_ship(_ship(), Vector2.ZERO)
	var s := _ship()
	_block(s, 13, 13, 17, 17, "wall")  # 5x5 cells = 160 px of solid ship around the centre
	var target := a.add_ship(s, Vector2(700.0, 0.0))
	a.ships[target].flight.linear_damping = 0.0
	a.ships[target].flight.vel = Vector2(0.0, 300.0)
	var gun := a.add_mount(shooter, "test_bolt", Vector2(15.5, 15.5))
	var aim: Vector2 = a.ships[target].flight.pos
	if aim_at_lead:
		aim = _lead(a.local_to_world(shooter, Vector2(15.5, 15.5)), aim, a.ships[target].flight.vel, 700.0)
	check(a.fire(shooter, gun, aim), "the bolt is fired")
	a.step(2.0)
	return a


func test_a_bolt_aimed_where_the_ship_is_misses_a_moving_ship() -> void:
	var a := _chase(false)
	eq(_count(a, "hit"), 0, "no hit")
	eq(Structure.structure_fraction(a.ships[1]), 1.0, "structure untouched")
	eq(a.projectiles.size(), 0, "the bolt flew on and expired")


func test_a_bolt_aimed_at_the_lead_point_hits() -> void:
	var a := _chase(true)
	check(_count(a, "hit", 1) >= 1, "hit the moving ship")
	check(Structure.structure_fraction(a.ships[1]) < 1.0, "and hurt it")
	for e in a.events:
		if e["type"] == "hit":
			check(e["cell"].x >= 13 and e["cell"].x <= 17 and e["cell"].y >= 13 and e["cell"].y <= 17, "inside the block: " + str(e["cell"]))
			break


func test_structure_is_the_block_hp_and_wrecks_the_ship_under_the_line() -> void:
	var s := _ship()
	_block(s, 5, 5, 7, 5, "titanium_alloy")
	_tile(s, 5, 7, "heavy_armor")
	var a := Arena.new()
	var i := a.add_ship(s)
	eq(Structure.structure_fraction(a.ships[i]), 1.0, "a fresh ship is whole")
	eq(Structure.totals(s), Vector2(28.0, 28.0), "3 titanium (6 hp) and 1 heavy armour (10 hp): the hp of its blocks, no matter the armour")
	# A row of walls, and a laser that goes through all of them.
	var b := Arena.new()
	var shooter := b.add_ship(_ship())
	var t := _ship()
	_block(t, 3, 15, 12, 15, "wall")  # 10 walls of 4 hp
	var target := b.add_ship(t, Vector2(800.0, 0.0))
	b.weapons.defs["lance"] = {"kind": "laser", "damage": 100, "pierce": 50, "gimbal": 180, "range": 2000, "cooldown": 0.1}
	var lance := b.add_mount(shooter, "lance", Vector2(20.5, 15.5))
	var small := b.add_mount(shooter, "laser_mk1", Vector2(20.5, 15.5))
	eq(Structure.totals(t).y, 40.0, "ten walls of 4 hp")
	check(b.fire(shooter, small, Vector2(2000.0, 0.0)), "a small laser first")
	b.step(0.1)
	eq(Structure.totals(t).x, 37.0, "3 damage dealt to a wall")
	check(Structure.structure_fraction(b.ships[target]) > 0.9 and not b.ships[target].wrecked, "still flying")
	b.ships[shooter].cooldowns.clear()
	check(b.fire(shooter, lance, Vector2(2000.0, 0.0)), "then the lance")
	b.step(0.1)
	eq(Structure.structure_fraction(b.ships[target]), 0.0, "every wall is breached")
	check(b.ships[target].wrecked, "wrecked")
	eq(_count(b, "wreck", target), 1, "reported once")
	eq(b.ships.size(), 2, "it stays in the arena")
	var gun := b.add_mount(target, "laser_mk1", Vector2(20.5, 15.5))
	eq(b.weapons.can_fire(b, target, gun, Vector2(-1000.0, 0.0)), "wrecked", "a wreck does not fire")


func test_a_ship_is_wrecked_when_its_structure_falls_under_the_line() -> void:
	var a := Arena.new()
	var t := _ship()
	_block(t, 3, 15, 12, 15, "wall")  # 10 walls of 4 hp
	var i := a.add_ship(t)
	var gone := int((1.0 - Structure.defeat_below()) * 10.0 + 1e-6)  # walls at 0 hp that leave exactly the defeat line
	for x in gone:
		t.grid.hp[Vector2i(3 + x, 15)] = 0.0
	a.step(0.2)
	check(not a.ships[i].wrecked and absf(Structure.structure_fraction(a.ships[i]) - Structure.defeat_below()) < 1e-6, "exactly on the line: not yet")
	Damage.apply(a, i, Vector2i(12, 15), {"kind": "wall", "def": t.grid.defs.get_def("wall")}, 1.0, "kinetic")
	a.step(0.1)
	check(a.ships[i].wrecked, "a little under the line: wrecked")
	eq(_count(a, "wreck", i), 1, "reported once")


func _scripted_battle(seed_value: int) -> Arena:
	var a := Arena.new(seed_value)
	var red := a.add_ship(_ship(), Vector2.ZERO)
	var s := _ship()
	_block(s, 8, 8, 22, 22, "wall")
	_block(s, 9, 9, 21, 21, "floor")
	_block(s, 12, 12, 18, 18, "scrap_plate")
	var blue := a.add_ship(s, Vector2(600.0, 40.0), deg_to_rad(20.0))
	a.ships[blue].flight.vel = Vector2(-20.0, 10.0)
	var gun := a.add_mount(red, "laser_mk1", Vector2(20.5, 15.5))
	var flak := a.add_mount(red, "test_flak", Vector2(15.5, 15.5))
	var rocket := a.add_mount(red, "test_missile", Vector2(15.5, 15.5))
	var bolt := a.add_mount(red, "test_bolt", Vector2(15.5, 15.5))
	for k in 20:
		var aim: Vector2 = a.ships[blue].flight.pos + Vector2(0.0, (k % 5 - 2) * 30.0)
		a.fire(red, gun, aim)
		a.fire(red, flak, aim)
		a.fire(red, rocket, aim)
		a.fire(red, bolt, aim)
		a.set_input(red, 0.0, 0.0)
		a.step(0.25)
	return a


func test_the_same_seed_and_inputs_replay_exactly() -> void:
	var a := _scripted_battle(7)
	var b := _scripted_battle(7)
	check(_count(a, "hit") > 5, "the scripted battle hits things (%d)" % _count(a, "hit"))
	eq(a.tick, 300, "five seconds")
	eq(JSON.stringify(a.snapshot()), JSON.stringify(b.snapshot()), "same state after 5 s")
	eq(Structure.structure_fraction(a.ships[1]), Structure.structure_fraction(b.ships[1]), "same structure")
	eq(a.ships[1].ship.grid.hp, b.ships[1].ship.grid.hp, "same cell hp")
	var c := _scripted_battle(8)
	check(JSON.stringify(a.snapshot()) != JSON.stringify(c.snapshot()), "another seed spreads the flak differently")
