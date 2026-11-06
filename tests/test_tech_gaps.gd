extends "res://tests/base_test.gd"
## The racial tech gaps, each through the real arena: ion vulnerability of a part's line (layers stripped, seconds shut down),
## acid spread, a shot that splits on a shield, scorch from a weapon's breech, turn_mult, missile interception, and
## the Sporeling aura against the air their parts eat.

const Arena = preload("res://scripts/combat/arena.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const Flight = preload("res://scripts/sim/flight.gd")
const PartEffects = preload("res://scripts/sim/part_effects.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")

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


## Step the arena until an event of `type` is logged (at most `max_s` seconds).
func _until(type: String, max_s := 3.0) -> void:
	var t := 0.0
	while t < max_s and _events(type).is_empty():
		arena.step(1.0 / 60.0)
		t += 1.0 / 60.0


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
	near(rows["shield_mk2"][1], 5.0, "and is locked for 5 s (Shields.ION_LOCK)")
	near(rows["shield_neon_mk1"][0], 2.0, "a neon shield (ion_vulnerability 2) loses two layers")
	near(rows["shield_neon_mk1"][1], 10.0, "and is locked for 10 s")
	# the lost layers come back, no more
	_duel({"damage_type": "ion", "damage": 1}, _shielded("shield_neon_mk1"))
	var co = arena.ships[1]
	var full := float(co.layers_cap)
	_shoot()
	arena.step(10.0 + (2.0 * 7.0 + 3.0) / 1.75 + 0.1)  # the lock (10 s), then the neon recharge: two layers one after the other (7 + 7 s of base time, 3 more for the emptied sector) at x1.75
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


# --- 3. split on a shield --------------------------------------------------------------------------------------

func _splitter(count := 3, mult := 0.5) -> Dictionary:
	return {"kind": "bolt", "speed": 800.0, "damage": 4.0, "effects": {"split_on_shield": {"count": count, "damage_mult": mult}}}


func _hits() -> Array:
	return _events("hit").filter(func(e): return e["ship"] == 1)


func test_a_shot_a_shield_stops_splits_into_weaker_shots_that_meet_the_bubble_again() -> void:
	_duel(_splitter(), _shielded("prismatic_lattice_shield"))  # 4 layers in each of 4 sectors
	var sector_before := 0.0
	for x in arena.ships[1].sector_layers:
		sector_before += float(x)
	check(_shoot(), "fires")
	_until("shield")
	eq(_events("shield").size(), 1, "the shot itself is stopped first")
	eq(_events("effect").filter(func(e): return e["kind"] == "split").size(), 1, "and it splits (reported for the picture)")
	eq(arena.projectiles.size(), 3, "into three")
	arena.step(0.6)
	eq(_events("shield").size(), 4, "each fragment is stopped by the bubble in its turn: 1 + 3 layers used")
	var sector_after := 0.0
	for x in arena.ships[1].sector_layers:
		sector_after += float(x)
	near(sector_before - sector_after, 4.0, "four layers of the sector are gone")
	eq(_hits().size(), 0, "and nothing reached the hull")
	eq(arena.projectiles.size(), 0, "no fragment splits again")


func test_fragments_reach_the_hull_past_a_broken_layer_with_their_weaker_damage() -> void:
	_duel(_splitter(3, 0.5), _shielded("shield_mk1"))  # one sector, one layer
	var wall_hp := target.grid.hp_of(Vector2i(3, 15))
	check(_shoot(), "fires")
	arena.step(1.0)
	eq(_events("shield").size(), 1, "the one layer stops the shot")
	var hits := _hits()
	check(hits.size() >= 1, "and the fragments, with the bubble down, hit the hull (%d hits)" % hits.size())
	for h in hits:
		check(float(h["dealt"]) <= 2.0 + 1e-6, "a fragment does 4 x 0.5 at most (dealt %s)" % str(h["dealt"]))
	check(target.grid.hp_of(Vector2i(3, 15)) >= wall_hp - 2.0 * 3.0 - 1e-6, "(it is the hull they hit)")


func test_a_shot_with_no_shield_in_the_way_does_not_split() -> void:
	_duel(_splitter(), _shielded("shield_mk1"))
	arena.ships[1].ion_lock = 100.0  # the bubble is offline: nothing stops the shot
	_shoot()
	arena.step(0.6)
	eq(_events("shield").size(), 0, "(no shield event)")
	eq(_events("effect").filter(func(e): return e["kind"] == "split").size(), 0, "no split")
	eq(_hits().size(), 1, "one hit, the shot itself")


func test_a_split_keeps_the_other_effects_scaled_and_one_fragment_is_one_shot() -> void:
	var e := _splitter(1, 0.5)
	e["effects"]["shard"] = {"splinters": 2, "dmg": 1.0}
	_duel(e, _shielded("shield_mk1"))
	_shoot()
	_until("shield")
	eq(arena.projectiles.size(), 1, "count 1 is one fragment")
	var w: Dictionary = arena.projectiles[0]["w"]
	near(float(w["damage"]), 2.0, "with half the damage")
	near(float(w["fx_k"]), 0.5, "and half the shard splinter damage")
	check(not Effects.of(w).has("split_on_shield") and Effects.of(w).has("shard"), "it keeps its shard and cannot split again")


func test_the_validator_knows_split_on_shield() -> void:
	eq(Effects.problems({"kind": "bolt", "effects": {"split_on_shield": {"count": 3, "damage_mult": 0.35}}}), [], "a good one")
	var cases := [
		[{"kind": "bolt", "effects": {"split_on_shield": {"count": 3}}}, "needs 'damage_mult'"],
		[{"kind": "bolt", "effects": {"split_on_shield": {"count": 2.5, "damage_mult": 0.5}}}, "whole number"],
		[{"kind": "bolt", "effects": {"split_on_shield": {"count": 0, "damage_mult": 0.5}}}, "split_on_shield.count"],
		[{"kind": "bolt", "effects": {"split_on_shield": {"count": 3, "damage_mult": 1.5}}}, "damage_mult"],
		[{"kind": "bolt", "effects": {"split_on_shield": {"count": 3, "damage_mult": 0.5, "angle": 3}}}, "unknown key"],
		[{"kind": "laser", "effects": {"split_on_shield": {"count": 3, "damage_mult": 0.5}}}, "not a laser"],
		[{"kind": "beam", "effects": {"split_on_shield": {"count": 3, "damage_mult": 0.5}}}, "not a beam"],
	]
	for case in cases:
		var p := Effects.problems(case[0])
		check(p.any(func(s): return case[1] in s), "%s is caught as '%s' (got %s)" % [str(case[0]), case[1], str(p)])


func test_the_refractor_splits_into_three() -> void:
	var w = Weapons.new()
	var spec: Dictionary = w.defs["prismatic_refractor"]["effects"]["split_on_shield"]
	eq(int(spec["count"]), 3, "the Refractor splits 1 into 3")
	check(float(spec["damage_mult"]) < 1.0, "weaker")


# --- 4. the Sporeling aura against the air their parts eat -----------------------------------------------------

const REFERENCE_ROOM := 40.0  ## cells: about the median room of the starter ships (rooms of 15 to 76 cells, median 37)


func _drain_per_s(component_id: String) -> float:
	var c := Ship.new("c").components
	for a in c.def(component_id)["abilities"]:
		for se in a["side_effects"]:
			if se["type"] == "drain_o2":
				return float(se["rate"])
	return 0.0


func test_two_sporelings_cancel_a_spore_cannon_and_a_bloom_reactor_in_a_typical_room() -> void:
	var cannon: Dictionary = Weapons.new().defs["sporeling_spore_cannon"]
	var per_shot := float(cannon["effects"]["self_room"]["o2_drain"])  # a fraction of the room's air
	var cannon_per_s := per_shot / float(cannon["cooldown"])
	var bloom_per_s := _drain_per_s("sporeling_bloom_reactor")  # a fraction of the air left, a full room to begin with
	var eaten := (cannon_per_s + bloom_per_s) * REFERENCE_ROOM  # cell units of air a second at full pressure
	var given := 2.0 * float(TraitSet.of(CrewMember.new("Sp", Vector2.ZERO, "sporeling"))["aura"]["o2_per_s"])
	var ratio := given / eaten
	print("tech_gaps: in a %d-cell room a firing Spore Cannon and a Bloom Reactor eat %.2f air a second, two Sporelings give %.2f (%.0f%%)" % [int(REFERENCE_ROOM), eaten, given, ratio * 100.0])
	check(ratio >= 0.85 and ratio <= 1.25, "two Sporelings give back about what they eat (%.0f%%)" % (ratio * 100.0))


func _bloom_room(species: String) -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	var s := Ship.new("Bloom", g)
	s.inventory.load_dict({"scrap": 800, "copper": 40})
	BuildSession.new(s).apply(BuildSession.room_changes(Vector2i(8, 8), Vector2i(15, 15), "wall", "floor"))  # a sealed room of 6 x 6 = 36 cells
	var uid := Fixture.put(s, "sporeling_bloom_reactor", 9, 9)
	check(uid >= 0, "(bloom placed)")
	Fixture.wire(s, [Vector2i(10, 10)])
	s.crew.append(CrewMember.new("A", Vector2(13.5, 13.5), species))
	s.crew.append(CrewMember.new("B", Vector2(13.5, 12.5), species))
	s.refresh()
	return s


func test_a_bloom_reactor_empties_a_room_of_humans_but_not_one_of_sporelings() -> void:
	var left := {}
	for species in ["human", "sporeling"]:
		var s := _bloom_room(species)
		var room := s.atmosphere.room_at(Vector2i(13, 13))
		eq(int(s.atmosphere.rooms[room]["size"]), 36, "(the room is 36 cells)")
		var sim := ShipSim.new()
		sim.ships = [s]
		for i in 600:
			sim._step_ship(s, 0.1)
		left[species] = s.atmosphere.pressure_of(room)
		check(s.atmosphere.room_at(s.crew[0].cell()) == room, "(the crew stayed in the room)")
	print("tech_gaps: a Bloom Reactor in a 36-cell room, air after a minute: two humans %.2f, two Sporelings %.2f" % [left["human"], left["sporeling"]])
	check(left["human"] < 0.7, "with humans the Bloom Reactor eats the room's air (%.2f after a minute)" % left["human"])
	check(left["sporeling"] > 0.97, "with two Sporelings the air stays (%.2f)" % left["sporeling"])


# --- 5. scorch from a weapon's breech --------------------------------------------------------------------------

## Ship 0 is the room ship, with the virtual gun inside its room (12.5, 12.5); ship 1 is the target. Returns ship 0.
func _breech_duel(entry: Dictionary) -> Ship:
	var shooter := Fixture.room_ship()
	arena = Arena.new(1)
	arena.add_ship(shooter)
	target = Fixture.room_ship()
	arena.add_ship(target, Vector2(800.0, 0.0))
	var full := {"kind": "laser", "damage_type": "energy", "damage": 1, "gimbal": 180, "cooldown": 0.0, "range": 2000}
	full.merge(entry, true)
	arena.weapons.defs["tg_gun"] = full
	gun = arena.add_mount(0, "tg_gun", Vector2(12.5, 12.5))
	return shooter


func test_scorch_dps_burns_the_crew_who_do_not_shrug_heat_off_for_the_cooldown() -> void:
	var shooter := _breech_duel({"cooldown": 2.0, "effects": {"self_room": {"scorch_dps": 2.0}}})
	var human := CrewMember.new("Human", Vector2(14.5, 12.5), "human")
	var ember := CrewMember.new("Ember", Vector2(15.5, 12.5), "emberkin")
	var outside := CrewMember.new("Out", Vector2(3.5, 3.5), "human")
	shooter.crew.append_array([human, ember, outside])
	var hp0 := human.hp
	var ember0 := ember.hp
	_shoot(Vector2(800.0, -300.0))
	arena.step(1.0)
	near(hp0 - human.hp, 2.0, "2 hp a second to the crew in the breech room", 0.05)
	near(ember0 - ember.hp, 0.0, "none to an Emberkin (heat_resistant)")
	near(outside.hp, outside.max_hp, "none outside the room")
	arena.step(3.0)
	near(hp0 - human.hp, 4.0, "and it stops with the cooldown: 2 s at 2 hp/s", 0.05)
	_shoot(Vector2(800.0, -300.0))
	arena.step(1.0)
	near(hp0 - human.hp, 6.0, "the next shot burns again", 0.05)


func test_scorch_and_shock_are_separate() -> void:
	var shooter := _breech_duel({"cooldown": 2.0, "effects": {"self_room": {"scorch_dps": 1.0, "shock_dps": 3.0}}})
	var robot := CrewMember.new("Robot", Vector2(14.5, 12.5), "gauntling")
	var ember := CrewMember.new("Ember", Vector2(15.5, 12.5), "emberkin")
	shooter.crew.append_array([robot, ember])
	_shoot(Vector2(800.0, -300.0))
	arena.step(1.0)
	near(robot.max_hp - robot.hp, 1.0, "a mechanical crew member takes the scorch but not the shock", 0.05)
	near(ember.max_hp - ember.hp, 3.0, "an Emberkin takes the shock but not the scorch", 0.05)


func test_the_validator_knows_scorch_dps_and_the_emberkin_weapons_use_it() -> void:
	eq(Effects.problems({"effects": {"self_room": {"heat": 40, "scorch_dps": 1.5}}}), [], "scorch_dps is a self_room key")
	for bad in [-1.0, 80.0, "hot"]:
		var p := Effects.problems({"effects": {"self_room": {"scorch_dps": bad}}})
		check(p.any(func(s): return "self_room.scorch_dps" in s), "%s is caught (%s)" % [str(bad), str(p)])
	var w = Weapons.new()
	for id in ["emberkin_pyre_lance", "emberkin_flare_turret"]:
		check(float(w.defs[id]["effects"]["self_room"].get("scorch_dps", 0.0)) > 0.0, "%s scorches its breech" % id)


# --- 6. turn_mult -----------------------------------------------------------------------------------------------

func _anchored() -> Ship:
	var s := _floor_ship()
	check(Fixture.put(s, "reactor_mk1", 10, 10) > 0, "(reactor placed)")
	var uid := Fixture.put(s, "basalt_gravity_anchor", 14, 10)
	check(uid > 0, "(anchor placed)")
	Fixture.wire(s, range(10, 16).map(func(x): return Vector2i(x, 10)))
	return s


func test_a_gravity_anchor_turns_the_ship_faster_while_it_works() -> void:
	var s := _anchored()
	var uid: int = s.components.instances.keys().filter(func(u): return s.components.instances[u]["id"] == "basalt_gravity_anchor")[0]
	arena = Arena.new(1)
	arena.add_ship(s)
	near(Abilities.turn_mult(s), 1.5, "the anchor's turn_mult counts while it is powered")
	near(arena.ships[0].flight.turn_mult, 1.5, "and the arena hands it to the flight body")
	s.components.instances[uid]["status"] = "disabled"
	arena.step(0.1)
	near(arena.ships[0].flight.turn_mult, 1.0, "a disabled anchor turns nothing")
	s.components.instances[uid]["status"] = "ok"
	arena.step(0.1)
	near(arena.ships[0].flight.turn_mult, 1.5, "repaired, it does again")
	Abilities.ion_lock(s, uid)
	arena.step(0.1)
	near(arena.ships[0].flight.turn_mult, 1.0, "and an ion hit shuts it down for a while")


func test_turn_mult_scales_the_spin_and_the_steering() -> void:
	var plain := Flight.new()
	var heavy := Flight.new()
	heavy.turn_mult = 1.5
	for f in [plain, heavy]:
		for i in 10:
			f.step(0.1, {"turn": 1.0}, 600.0, 20.0)
	near(heavy.ang_vel, 1.5 * plain.ang_vel, "1 s of full turn: 1.5x the spin", 1e-6)
	var p := Flight.new()
	var h := Flight.new()
	h.turn_mult = 1.5
	var want := PI / 2.0
	for f in [p, h]:
		for i in 600:
			f.step(0.01, {"turn": f.steer_toward(want, 600.0, 20.0)}, 600.0, 20.0)
	check(absf(wrapf(h.angle - want, -PI, PI)) < 0.05 and absf(wrapf(p.angle - want, -PI, PI)) < 0.05, "steer_toward still settles on the heading with the faster turn")


func test_the_validator_knows_turn_mult() -> void:
	eq(PartEffects.problems({"id": "a", "type": "passive", "effects": {"turn_mult": 1.5}}), [], "turn_mult 1.5 is fine")
	for bad in [0, -1.0, "fast"]:
		var p := PartEffects.problems({"id": "a", "type": "passive", "effects": {"turn_mult": bad}})
		check(p.any(func(s): return "turn_mult" in s), "%s is caught (%s)" % [str(bad), str(p)])


# --- 7. missile interception ---------------------------------------------------------------------------------------

const VOLLEY := {"kind": "missile", "shots": 3, "spread": 16.0, "damage": 4.0, "cooldown": 0.0, "range": 1400}


## Ship 0 fires a volley of three missiles at ship 1 (the room ship), which has a point-defence turret on its west side
## with `intercept` {range} and the given accuracy; `with_turret` false leaves it out.
func _volley_duel(with_turret: bool, accuracy := 1.0, range_px := 300.0, seed_value := 1, cooldown := 0.15) -> void:
	_duel(VOLLEY, null, seed_value)
	arena.weapons.defs["tg_pd"] = {"kind": "bolt", "damage_type": "kinetic", "damage": 1.0, "cooldown": cooldown, "range": 900.0, "speed": 900.0,
		"turret": true, "arc": 300.0, "track": 720.0, "accuracy": accuracy, "effects": {"intercept": {"range": range_px}}}
	if with_turret:
		arena.add_mount(1, "tg_pd", Vector2(10.5, 15.5), true, Vector2.LEFT)


func _fly_volley(seconds := 5.0) -> void:
	check(_shoot(aim), "(the volley fires)")
	eq(arena.projectiles.size(), 3, "(three missiles)")
	arena.step(seconds)


func test_a_point_defence_turret_shoots_a_missile_volley_down() -> void:
	_volley_duel(false)
	_fly_volley()
	var undefended := _hits().size()
	check(undefended >= 2, "without the turret the missiles hit the hull (%d hits)" % undefended)
	_volley_duel(true)
	_fly_volley()
	var shot := _events("effect").filter(func(e): return e["kind"] == "intercept" and e["hit"])
	eq(shot.size(), 3, "with it every missile is shot down (accuracy 1)")
	eq(_hits().size(), 0, "and none reaches the hull")
	eq(arena.projectiles.size(), 0, "nothing is left flying")
	eq(arena.projectiles.filter(func(p): return p["owner"] == 1).size(), 0, "(the turret fired no real shots: its intercepts are instant)")
	check(_events("beam").size() >= 3, "each shot shows a tracer")


func test_the_real_flak_screen_and_drone_picket_lose_a_volley_missiles() -> void:
	_volley_duel(false)
	_fly_volley()
	var undefended := _hits().size()
	for id in ["human_flak_screen", "kett_drone_picket"]:
		_volley_duel(false)
		var uid := arena.add_mount(1, id, Vector2(10.5, 15.5), true, Vector2.LEFT)
		check(uid < 0, "(%s mounted)" % id)
		_fly_volley()
		var shot := _events("effect").filter(func(e): return e["kind"] == "intercept" and e["hit"]).size()
		print("tech_gaps: %s shot down %d of 3 missiles, %d hull hits (undefended: %d)" % [id, shot, _hits().size(), undefended])
		check(shot >= 1, "%s shoots down at least one of three missiles (%d)" % [id, shot])
		check(_hits().size() < undefended, "so fewer reach the hull than undefended (%d against %d)" % [_hits().size(), undefended])


func test_a_miss_leaves_the_missile_flying() -> void:
	_volley_duel(true, 0.0)
	_fly_volley()
	var shots := _events("effect").filter(func(e): return e["kind"] == "intercept")
	check(shots.size() >= 1 and shots.all(func(e): return not e["hit"]), "accuracy 0: it fires and misses (%d shots)" % shots.size())
	check(_hits().size() >= 2, "so the missiles still arrive")


func test_it_only_looks_at_missiles_inside_its_range() -> void:
	_volley_duel(true, 1.0, 40.0)  # a range of 40 px: the missiles are never that close to the turret before they hit
	var w: Dictionary = arena.weapons.def("tg_pd")
	var m: Dictionary = arena.ships[1].mounts.keys().filter(func(u): return arena.ships[1].mounts[u]["id"] == "tg_pd").map(func(u): return arena.ships[1].mounts[u])[0]
	var at: Vector2 = arena.local_to_world(1, m["pos"])
	arena.projectiles.append({"owner": 0, "w": arena.weapons.def("tg_gun"), "pos": at + Vector2(-200.0, 0.0), "vel": Vector2(300.0, 0.0), "left": 1000.0, "target": 1, "bounces": 0, "skip": {}})
	check(arena.weapons.missile_target(arena, 1, m, w) == null, "a missile 200 px away is outside a range of 40")
	arena.weapons.defs["tg_pd"]["effects"]["intercept"]["range"] = 300.0
	check(arena.weapons.missile_target(arena, 1, m, arena.weapons.def("tg_pd")) != null, "and inside a range of 300")
	arena.projectiles.append({"owner": 0, "w": arena.weapons.def("tg_gun"), "pos": at + Vector2(-100.0, 0.0), "vel": Vector2(300.0, 0.0), "left": 1000.0, "target": 1, "bounces": 0, "skip": {}})
	var near_one = arena.weapons.missile_target(arena, 1, m, arena.weapons.def("tg_pd"))
	near(near_one["pos"].distance_to(at), 100.0, "the nearest one is the target")
	arena.projectiles.append({"owner": 1, "w": arena.weapons.def("tg_gun"), "pos": at + Vector2(-20.0, 0.0), "vel": Vector2(-300.0, 0.0), "left": 1000.0, "target": 0, "bounces": 0, "skip": {}})
	near(arena.weapons.missile_target(arena, 1, m, arena.weapons.def("tg_pd"))["pos"].distance_to(at), 100.0, "its own ship's missiles are not shot at")


func test_a_turret_without_intercept_ignores_missiles_and_a_missile_comes_before_a_ship() -> void:
	_volley_duel(false)
	arena.weapons.defs["tg_plain"] = arena.weapons.defs["tg_pd"].duplicate(true)
	arena.weapons.defs["tg_plain"].erase("effects")
	arena.add_mount(1, "tg_plain", Vector2(10.5, 15.5), true, Vector2.LEFT)
	_fly_volley()
	eq(_events("effect").filter(func(e): return e["kind"] == "intercept").size(), 0, "a plain turret never intercepts")
	# with intercept, a missile in range comes before the ship in range: the turret shoots the missile, not a real shot at the ship
	_volley_duel(true)
	_shoot(aim)
	arena.step(1.4)
	check(not _events("effect").filter(func(e): return e["kind"] == "intercept").is_empty(), "it shot at a missile while the enemy ship was in range of its normal fire too")
	eq(arena.projectiles.filter(func(p): return p["owner"] == 1).size(), 0, "and fired no shot at the ship in that time")


func test_point_defence_fights_replay_exactly() -> void:
	var snaps := []
	for run in 2:
		_volley_duel(true, 0.6, 300.0, 7)
		_fly_volley()
		snaps.append(arena.snapshot())
	eq(snaps[0], snaps[1], "the same seed gives the same interceptions")


func test_the_validator_knows_intercept() -> void:
	eq(Effects.problems({"turret": true, "effects": {"intercept": {"range": 300}}}), [], "a turret may intercept")
	var cases := [
		[{"turret": true, "effects": {"intercept": {}}}, "needs 'range'"],
		[{"turret": true, "effects": {"intercept": {"range": 5}}}, "intercept.range"],
		[{"turret": true, "effects": {"intercept": {"range": 300, "arc": 3}}}, "unknown key"],
		[{"turret": false, "effects": {"intercept": {"range": 300}}}, "needs a turret"],
		[{"effects": {"intercept": {"range": 300}}}, "needs a turret"],
	]
	for case in cases:
		var p := Effects.problems(case[0])
		check(p.any(func(s): return case[1] in s), "%s is caught as '%s' (got %s)" % [str(case[0]), case[1], str(p)])


func test_the_flak_screen_and_the_drone_picket_intercept_at_300_px() -> void:
	var w = Weapons.new()
	for id in ["human_flak_screen", "kett_drone_picket"]:
		near(float(w.defs[id]["effects"]["intercept"]["range"]), 340.0, "%s intercepts missiles within 340 px" % id)
		check(bool(w.defs[id]["turret"]), "%s is a turret" % id)
