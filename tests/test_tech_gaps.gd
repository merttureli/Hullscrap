extends "res://tests/base_test.gd"
## The racial tech gaps, each through the real arena: ion vulnerability of a part's line (layers stripped, seconds shut down),
## acid spread, a shot that splits on a shield, scorch from a weapon's breech, turn_mult, missile interception, and
## the Sporeling aura against the air their parts eat.

const Arena = preload("res://scripts/combat/arena.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")

var arena: Arena
var target: Ship  ## ship 1, at (800, 0); row 15 of its grid is the line of fire
var gun: int  ## the shooter's mount on ship 0
var aim := Vector2(2000.0, 0.0)


func near(got: float, want: float, msg: String, eps := 1e-3) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## A 31x31 ship (hull cells 0..30, centre at 15.5, 15.5) with floor everywhere.
func _floor_ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	for c in g.hull:
		g.force_tile(c, "floor")
	return Ship.new("t", g)


## Ship 0 (floor everywhere) with a virtual "tg_gun" of entry `entry` (over a 1-damage energy laser that fires anywhere) at its east side,
## and ship 1 (`target`, x 800): `target_ship` or the sealed room ship (walls round a floor x 9..21, y 9..16).
func _duel(entry: Dictionary, target_ship: Ship = null, seed_value := 1) -> void:
	arena = Arena.new(seed_value)
	arena.add_ship(_floor_ship())
	target = target_ship if target_ship != null else Fixture.room_ship()
	arena.add_ship(target, Vector2(800.0, 0.0))
	var full := {"kind": "laser", "damage_type": "energy", "damage": 1, "gimbal": 180, "cooldown": 0.0, "range": 2000}
	full.merge(entry, true)
	arena.weapons.defs["tg_gun"] = full
	gun = arena.add_mount(0, "tg_gun", Vector2(20.5, 15.5))


## Fire `gun` (its cooldown cleared) at the world point `at`, by default cell (8, 15) of the target.
func _shoot(at := Vector2.INF) -> bool:
	arena.ships[0].cooldowns.clear()
	return arena.fire(0, gun, arena.cell_to_world(1, Vector2i(8, 15)) if at == Vector2.INF else at)


func _events(type: String) -> Array:
	return arena.events.filter(func(e): return e["type"] == type)


# --- 1. ion vulnerability ------------------------------------------------------------------------------------

## A ship with a reactor and one shield part `shield_id` wired up, a wall at (3, 15) in the line of fire.
func _shielded(shield_id: String) -> Ship:
	var s := _floor_ship()
	for c in [Vector2i(1, 14), Vector2i(1, 16), Vector2i(29, 14), Vector2i(29, 16), Vector2i(14, 1), Vector2i(16, 1), Vector2i(14, 29), Vector2i(16, 29)]:
		s.grid.force_tile(c, "wall")
	s.grid.force_tile(Vector2i(3, 15), "wall")
	check(Fixture.put(s, "reactor_mk1", 9, 19) > 0, "(reactor placed)")
	check(Fixture.put(s, shield_id, 13, 19) > 0, "(shield placed)")
	Fixture.wire(s, range(9, 17).map(func(x): return Vector2i(x, 20)))
	return s


func test_ion_strips_layers_and_locks_the_bubble_times_the_shields_line_vulnerability() -> void:
	var rows := {}
	for id in ["shield_mk2", "shield_neon_mk1"]:
		_duel({"damage_type": "ion", "damage": 1}, _shielded(id))
		var co = arena.ships[1]
		var before := 0.0
		for x in co.sector_layers:
			before += float(x)
		check(_shoot(), "%s: fires" % id)
		var after := 0.0
		for x in co.sector_layers:
			after += float(x)
		rows[id] = [before - after, co.ion_lock]
	near(rows["shield_mk2"][0], 1.0, "a plain shield loses one layer to an ion hit")
	near(rows["shield_mk2"][1], 3.0, "and is locked for 3 s")
	near(rows["shield_neon_mk1"][0], 2.0, "a neon shield (ion_vulnerability 2) loses two layers")
	near(rows["shield_neon_mk1"][1], 6.0, "and is locked for 6 s")
	# the lost layers come back, no more
	_duel({"damage_type": "ion", "damage": 1}, _shielded("shield_neon_mk1"))
	var co = arena.ships[1]
	var full := float(co.layers_cap)
	_shoot()
	arena.step(6.0 + 1.4 + 0.1)  # the lock, then the neon recharge (1.4 s a layer, all at once)
	var sum := 0.0
	for x in co.sector_layers:
		sum += float(x)
	near(sum, full * co.sectors, "every stripped layer is back after the lock and the recharge, never more", 1e-3)


func test_ion_with_one_layer_in_the_sector_strips_only_that_layer() -> void:
	_duel({"damage_type": "ion", "damage": 1}, _shielded("shield_neon_mk1"))
	var co = arena.ships[1]
	_shoot()
	var lost := 0
	for s in co.sectors:
		if float(co.sector_layers[s]) < 2.0 - 1e-6:
			lost += 1
			check(float(co.sector_layers[s]) >= 0.0, "a sector never goes below 0")
	eq(lost, 1, "only the sector hit was stripped")


## The wall at (8, 15) of the room ship opened, `id` placed behind it so row 15 hits it first.
func _exposed(id: String) -> int:
	var t := Fixture.room_ship()
	t.grid.force_tile(Vector2i(8, 15), "floor")
	var uid := Fixture.put(t, id, 9, 13)
	check(uid >= 0, "(%s placed)" % id)
	Fixture.wire(t, [Vector2i(10, 14)])  # a part on a cable is "powered" when it works
	_duel({"damage_type": "ion", "damage": 1}, t)
	return uid


func test_ion_shuts_a_part_down_for_the_lock_time_times_its_vulnerability() -> void:
	var seconds := {}
	for id in ["reactor_mk1", "reactor_neon_mk1"]:
		var uid := _exposed(id)
		check(target.power_state.get("powered", {}).get(uid, false), "%s works before the hit" % id)
		check(_shoot(), "%s: fires" % id)
		var ev := _events("ion_part")
		eq(ev.size(), 1, "%s: the hit is reported" % id)
		seconds[id] = float(ev[0]["seconds"])
		arena.step(0.1)
		check(not target.power_state.get("powered", {}).get(uid, true), "%s is shut down" % id)
		check(target.disabled_uids().has(uid), "%s counts as out of action" % id)
		eq(target.components.instances[uid]["status"], "ok", "%s is not broken, ion only shuts it down" % id)
		var lock: float = seconds[id]
		arena.step(lock - 0.3)
		check(Abilities.ion_left(target, uid) > 0.0, "%s is still down just before the end" % id)
		arena.step(0.4)
		check(target.power_state.get("powered", {}).get(uid, false), "%s works again after %s s" % [id, str(lock)])
		eq(Abilities.ion_left(target, uid), 0.0, "%s: nothing left" % id)
	near(seconds["reactor_mk1"], 3.0, "a plain part is down for 3 s")
	near(seconds["reactor_neon_mk1"], 6.0, "a neon part (ion_vulnerability 2) for twice as long: the Song Reactor's rule")


func test_a_second_ion_hit_does_not_stack_and_a_wall_is_not_locked() -> void:
	var uid := _exposed("reactor_mk1")
	_shoot()
	arena.step(1.0)
	_shoot()
	near(Abilities.ion_left(target, uid), 3.0, "the second hit renews to 3 s, it does not add up", 0.05)
	_duel({"damage_type": "ion", "damage": 1})
	_shoot()
	eq(_events("ion_part").size(), 0, "an ion hit on a plain wall shuts nothing down")
