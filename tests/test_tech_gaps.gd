extends "res://tests/base_test.gd"
## The racial tech gaps, each through the real arena: ion vulnerability of a part's line (layers stripped, seconds shut down),
## acid spread, a shot that splits on a shield, scorch from a weapon's breech, turn_mult, missile interception, and
## the Sporeling aura against the air their parts eat.

const Arena = preload("res://scripts/combat/arena.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
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


# --- 2. acid spread ------------------------------------------------------------------------------------------

## A target of solid wall, x 8..16, y 12..18, in the line of fire (row 15): the shot lands on (8, 15).
func _slab() -> void:
	for y in range(12, 19):
		for x in range(8, 17):
			target.grid.force_tile(Vector2i(x, y), "wall")


func _cloud() -> Dictionary:
	var acids: Array = arena.fx["timed"].filter(func(e): return e["k"] == "acid")
	return acids[0] if not acids.is_empty() else {}


func test_a_spreading_acid_creeps_to_neighbouring_cells_and_eats_them() -> void:
	_duel({"effects": {"acid": {"dps": 1.0, "seconds": 3.0, "spread": 1.0}}})
	_slab()
	_shoot()
	eq(_cloud()["cells"].size(), 1, "it starts on the cell hit")
	arena.step(1.0)
	var cells: Array = _cloud()["cells"]
	check(cells.size() >= 4, "at spread 1.0 it gained about a cell a tick (%d cells after 1 s)" % cells.size())
	for c in cells.slice(0, cells.size() - 1):  # (the newest cell is first hit by the next tick)
		check(target.grid.hp_of(c) < 4.0, "cell %s is being eaten" % str(c))
		check(c == Vector2i(8, 15) or cells.any(func(o): return o != c and (o - c).length_squared() == 1), "cell %s touches another of the cloud" % str(c))
	var spread := arena.events.filter(func(e): return e["type"] == "effect" and e["kind"] == "acid" and e.get("spread", false))
	eq(spread.size(), cells.size() - 1, "every creep is reported (for the picture)")
	arena.step(3.0)
	eq(arena.fx["timed"].size(), 0, "the whole cloud ends with the acid's seconds")


func test_an_acid_without_spread_stays_on_one_cell() -> void:
	_duel({"effects": {"acid": {"dps": 1.0, "seconds": 3.0}}})
	_slab()
	_shoot()
	arena.step(2.0)
	eq(_cloud()["cells"].size(), 1, "no spread key, one cell")
	var hurt := 0
	for c in target.grid.hp:
		hurt += 1
	eq(hurt, 1, "and only that cell was damaged")


func test_acid_creeps_into_a_part_once_and_never_past_the_cell_cap() -> void:
	_duel({"effects": {"acid": {"dps": 0.1, "seconds": 20.0, "spread": 1.0}}})
	var uid := Fixture.put(target, "radiator", 9, 15)  # a 2x2 part just inside the wall hit: only one of its cells may join
	check(uid >= 0, "(setup)")
	_shoot()
	arena.step(10.0)
	var cells: Array = _cloud()["cells"]
	var mine := cells.filter(func(c): return target.components.at(c) == uid)
	eq(mine.size(), 1, "a part joins the cloud once, not once a cell")
	eq(cells.size(), Effects.ACID_MAX_CELLS, "and the cloud stops at ACID_MAX_CELLS")


func test_a_hit_on_a_cell_the_cloud_eats_renews_that_cloud() -> void:
	_duel({"effects": {"acid": {"dps": 0.1, "seconds": 3.0, "spread": 1.0}}})
	_slab()
	_shoot()
	arena.step(1.0)
	var inside: Vector2i = _cloud()["cells"][1]
	_shoot(arena.cell_to_world(1, inside))
	eq(arena.fx["timed"].size(), 1, "still one cloud: the second shot renewed it")
	check(_cloud()["left"] > 2.9, "with its time back")


func test_a_spreading_acid_replays_exactly() -> void:
	var snaps := []
	for run in 2:
		_duel({"cooldown": 0.2, "effects": {"acid": {"dps": 0.5, "seconds": 3.0, "spread": 0.5}}}, null, 9)
		_slab()
		for i in 6:
			arena.ships[0].cooldowns.clear()
			arena.fire(0, gun, arena.cell_to_world(1, Vector2i(8, 15)))
			arena.step(0.5)
		snaps.append(arena.snapshot())
	eq(snaps[0], snaps[1], "the same seed gives the same cloud")
	check(snaps[0]["fx"]["timed"].any(func(t): return t[2] > 1), "(and it did spread)")


func test_the_validator_checks_spread() -> void:
	eq(Effects.problems({"effects": {"acid": {"dps": 1, "seconds": 4, "spread": 0.3}}}), [], "spread 0.3 is fine")
	for bad in [1.5, -0.1, "lots"]:
		var p := Effects.problems({"effects": {"acid": {"dps": 1, "seconds": 4, "spread": bad}}})
		check(p.any(func(s): return "acid.spread" in s), "spread %s is caught (%s)" % [str(bad), str(p)])
	var p2 := Effects.problems({"effects": {"spores": {"o2_drain": 0.1, "seconds": 4, "spread": 0.3}}})
	check(p2.any(func(s): return "unknown key" in s), "and spread belongs to acid only")


func test_the_magma_spitter_and_the_rot_pod_spread() -> void:
	var w = Weapons.new()
	for id in ["basalt_magma_spitter", "sporeling_rot_pod"]:
		check(float(w.defs[id]["effects"]["acid"].get("spread", 0.0)) > 0.0, "%s has an acid spread" % id)
