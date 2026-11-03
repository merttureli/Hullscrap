extends "res://tests/base_test.gd"
## Shield bubbles: layers from powered shield parts, stopping shots, recharge, missiles passing,
## ion strips and locks, and the shape of the bubble.

const Arena = preload("res://scripts/combat/arena.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Projectiles = preload("res://scripts/combat/projectiles.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")

var arena: Arena
var target: Ship
var gun: int
var aim := Vector2(2000.0, 0.0)


## A 31x31 ship (hull cells 0..30, centre at 15.5, 15.5) with floor everywhere.
func _ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	for c in g.hull:
		g.force_tile(c, "floor")
	return Ship.new("t", g)


## Eight wall cells near the edge of `s`, beside its middle row and column (which the shots travel along):
## the bubble hugs the solid cells, so this makes it span the whole 31x31 hull.
func _edged(s: Ship) -> Ship:
	for c in [Vector2i(1, 14), Vector2i(1, 16), Vector2i(29, 14), Vector2i(29, 16), Vector2i(14, 1), Vector2i(16, 1), Vector2i(14, 29), Vector2i(16, 29)]:
		s.grid.force_tile(c, "wall")
	return s


## Ship 0 shoots (laser_mk1 on its east side); ship 1 has a wall at (3, 15), in the line of fire,
## a reactor and `shields` Mk1 shield generators wired up (`wired` false leaves out the cable).
func _duel(shields: int, wired := true, seed_value := 1, reactor := "reactor_mk1") -> void:
	arena = Arena.new(seed_value)
	arena.add_ship(_ship())
	target = _edged(_ship())
	target.grid.force_tile(Vector2i(3, 15), "wall")
	check(target.components.place(target.grid, reactor, Vector2i(9, 19), 0) > 0, "reactor placed")
	for i in shields:
		check(target.components.place(target.grid, "shield_mk1", Vector2i(13 + 4 * i, 19), 0) > 0, "shield placed")
	if wired:
		for x in range(9, 13 + 4 * shields):
			target.cables.place(target.grid, Vector2i(x, 20))
	arena.add_ship(target, Vector2(800.0, 0.0))
	gun = arena.add_mount(0, "laser_mk1", Vector2(20.5, 15.5))
	arena.weapons.defs["laser_mk1"]["damage"] = 2  # pinned at 2: these tests are about the damage rules, not the balance numbers


func _def(id: String, d: Dictionary) -> int:
	var full := {"kind": "laser", "damage_type": "energy", "damage": 1, "gimbal": 180, "cooldown": 0.0, "range": 2000}
	full.merge(d, true)
	arena.weapons.defs[id] = full
	return arena.add_mount(0, id, Vector2(20.5, 15.5))


func _shoot(uid: int, at := aim) -> bool:
	arena.ships[0].cooldowns.clear()
	return arena.fire(0, uid, at)


func _count(type: String) -> int:
	var n := 0
	for e in arena.events:
		if e["type"] == type:
			n += 1
	return n


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func test_layers_come_from_powered_shield_parts() -> void:
	_duel(2)
	eq(arena.ships[1].layers, 2, "two Mk1 shields, one layer each, start full")
	eq(arena.ships[1].layers_cap, 2, "cap")
	_duel(2, false)
	eq(arena.ships[1].layers, 0, "no cable, no power, no shield")
	_duel(2)
	var uid: int = target.components.at(Vector2i(13, 19))
	target.components.instances[uid]["status"] = "disabled"
	arena.ships[1].dirty = true
	arena.sync(1)
	eq([arena.ships[1].layers, arena.ships[1].layers_cap], [1, 1], "a disabled generator takes its layer away")
	_duel(0)
	eq(arena.ships[1].layers, 0, "no generator")


func test_a_layer_stops_a_shot_and_recharges() -> void:
	_duel(2)
	check(_shoot(gun), "fired")
	eq(_count("shield"), 1, "the bubble took it")
	eq(_count("hit"), 0, "the wall behind did not")
	eq(target.grid.hp.size(), 0, "no cell damage")
	eq(arena.ships[1].layers, 1, "one layer used")
	arena.step(1.0)
	_shoot(gun)
	eq(arena.ships[1].layers, 0, "the second layer used a second later")
	_shoot(gun)
	eq(_count("hit"), 1, "with no layers left the third shot reaches the wall")
	eq(target.grid.hp_of(Vector2i(3, 15)), 2.0, "and damages it")
	arena.step(8.0)  # 9 s after the first shot: the bubble was emptied at 1 s, so the first layer waits 3 s more (7 s from the hit, 10 s in all)
	eq(arena.ships[1].layers, 0, "the first layer is not back yet")
	arena.step(1.05)  # 10.05 s
	eq(arena.ships[1].layers, 1, "the first layer is back after 7 s + 3 s")
	arena.step(6.5)  # 16.55 s
	eq(arena.ships[1].layers, 1, "the second comes 7 s after the first, not with it")
	arena.step(0.6)  # 17.15 s
	eq(arena.ships[1].layers, 2, "and is back at 17 s")
	arena.step(5.0)
	eq(arena.ships[1].layers, 2, "never above the cap")


func test_a_mk1_bubble_hit_once_is_down_for_7_s_and_3_s() -> void:
	_duel(1)
	check(_shoot(gun), "fired")
	eq(arena.ships[1].layers, 0, "the one layer is used: the sector is empty")
	arena.step(9.9)
	eq(arena.ships[1].layers, 0, "still down at 9.9 s")
	arena.step(0.2)
	eq(arena.ships[1].layers, 1, "back after 7 s + the 3 s of a broken sector")


func test_two_layers_used_come_back_one_at_a_time_at_t_and_2t() -> void:
	_duel(3, true, 1, "reactor_mk2")  # a Mk1 reactor powers only two generators
	_shoot(gun)
	_shoot(gun)
	eq(arena.ships[1].layers, 1, "two of three layers used (the sector is not emptied: no extra wait)")
	arena.step(6.9)
	eq(arena.ships[1].layers, 1, "nothing back at 6.9 s")
	arena.step(0.2)
	eq(arena.ships[1].layers, 2, "one back at 7 s")
	arena.step(6.5)  # 13.6 s
	eq(arena.ships[1].layers, 2, "the next one starts its timer only now: not back at 13.6 s")
	arena.step(0.5)  # 14.1 s
	eq(arena.ships[1].layers, 3, "and the second is back at 14 s")


## Seconds until the one used layer of a bubble of `count` generators of `part` is back (60 at most).
func _seconds_back(part: String, count: int) -> float:
	var a := Arena.new(1)
	a.add_ship(_ship())
	var t := _edged(_ship())
	check(t.components.place(t.grid, "reactor_mk1", Vector2i(9, 19), 0) > 0, "reactor placed")
	for i in count:
		check(t.components.place(t.grid, part, Vector2i(13 + 4 * i, 19), 0) > 0, "shield placed")
	for x in range(9, 13 + 4 * count):
		t.cables.place(t.grid, Vector2i(x, 20))
	a.add_ship(t, Vector2(800.0, 0.0))
	var before: int = a.ships[1].layers
	Shields.absorb(a, 1, {"damage_type": "energy"}, Vector2.ZERO, Vector2.ZERO, 0)
	var secs := 0.0
	while a.ships[1].layers < before and secs < 60.0:
		a.step(0.05)
		secs += 0.05
	return secs


func test_the_neon_shield_comes_back_faster_than_the_mk1() -> void:
	var mk1 := _seconds_back("shield_mk1", 2)
	var neon := _seconds_back("shield_neon_mk1", 1)
	near(mk1, 7.0, "a Mk1 layer: 7 s", 0.1)
	near(neon, 4.0, "a Neon Lattice layer: 4 s", 0.1)
	check(neon < mk1, "the neon shield is the faster")


func test_a_layer_takes_one_shot_whatever_its_damage() -> void:
	_duel(1)
	var big := _def("big", {"damage": 50, "pierce": 9})
	_shoot(big)
	eq(arena.ships[1].layers, 0, "used up")
	eq(target.grid.get_tile(Vector2i(3, 15)), "wall", "a huge shot is still absorbed whole")


func test_missiles_pass_through_shields() -> void:
	_duel(2)
	var rocket := arena.add_mount(0, "test_missile", Vector2(20.5, 15.5))
	_shoot(rocket)
	arena.step(3.0)
	eq(arena.ships[1].layers, 2, "no layer used")
	eq(_count("shield"), 0, "the bubble never reacted")
	eq(target.grid.get_tile(Vector2i(3, 15)), "", "the missile took the wall out (4 explosive damage on 4 hp)")


func test_flak_wears_down_the_bubble_pellet_by_pellet() -> void:
	_duel(2)
	for y in range(13, 18):
		for x in range(13, 18):
			target.grid.force_tile(Vector2i(x, y), "wall")
	var flak := arena.add_mount(0, "test_flak", Vector2(15.5, 15.5))
	_shoot(flak)
	arena.step(2.0)
	eq(_count("shield"), 2, "the first two pellets used the two layers")
	eq(arena.ships[1].layers, 0, "bubble down")
	check(_count("hit") >= 1, "the rest got through to the hull (%d)" % _count("hit"))


func test_ion_strips_a_layer_and_locks_the_shields() -> void:
	_duel(2)
	var ion := _def("ion", {"damage_type": "ion", "damage": 3})
	_shoot(ion)
	eq(arena.ships[1].layers, 1, "ion removes a layer")
	near(arena.ships[1].ion_lock, 5.0, "and locks the shields for 5 s (Shields.ION_LOCK; 3 before the Beta 4 audit)")
	eq(_count("ion_lock"), 1, "reported")
	_shoot(gun)
	eq(_count("shield"), 1, "the locked bubble stops nothing more")
	eq(target.grid.hp_of(Vector2i(3, 15)), 2.0, "so the laser burns the wall")
	arena.step(2.4)
	eq(arena.ships[1].layers, 1, "no recharge while locked")
	arena.step(2.4)  # 4.8 s: still locked, the lock ends at 5.0 s and the recharge needs 7 s more
	eq(arena.ships[1].layers, 1, "still locked")
	arena.step(5.0)  # 9.8 s
	eq(arena.ships[1].layers, 1, "still recharging 4.8 s after the lock")
	arena.step(2.4)  # 12.2 s
	eq(arena.ships[1].layers, 2, "back 7 s after the lock ended")
	eq(arena.ships[1].ion_lock, 0.0, "unlocked")


func test_a_wreck_has_no_shields() -> void:
	_duel(2)
	arena.wreck(1)
	eq(arena.ships[1].layers, 0, "bubble gone")
	_shoot(gun)
	eq(_count("shield"), 0, "nothing absorbed")
	eq(_count("hit"), 1, "the derelict still takes hits")


func test_a_shot_already_inside_the_bubble_is_not_stopped() -> void:
	_duel(2)
	var p0 := arena.cell_to_world(1, Vector2i(0, 15))  # inside the bubble, outside the wall
	var w := arena.weapons.def("laser_mk1")
	check(Projectiles.trace(arena, 0, w, p0, p0 + Vector2(300.0, 0.0)), "it reached the wall")
	eq(_count("shield"), 0, "and passed no bubble")
	eq(arena.ships[1].layers, 2, "layers untouched")
	eq(_count("hit"), 1, "wall hit")
