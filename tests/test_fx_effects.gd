extends "res://tests/base_test.gd"
## The racial weapon effects (scripts/combat/effects.gd, docs/CONTENT.md section 17), each fired through the real
## arena: acid, spores, shard, sonic, magnetic, frost and corrode on the target; self_room, needs_operator,
## needs_crew_in_room and ammo_mult on the shooter; and the validator that knows their keys.

const Arena = preload("res://scripts/combat/arena.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Wall = preload("res://tests/fixture_wall.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Content = preload("res://scripts/data/content.gd")
const EffectFx = preload("res://scripts/combat/effect_fx.gd")
const Art = preload("res://scripts/view/art.gd")

const DT := 1.0 / 60.0

var arena: Arena
var gun: int  ## the shooter's mount: a virtual "fx_gun" on the east side of ship 0
var target: Ship  ## ship 1, at (800, 0); row 15 of its grid is the line of fire
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


## Ship 0 (the shooter, floor everywhere) with a virtual "fx_gun" laser whose entry is `entry` on top of a plain
## 1-damage energy laser; ship 1 (`target`, at x 800) is the sealed room ship: walls round a floor x 9..21, y 9..16, full of air.
## A shot along the world row y = 0 hits its wall at (8, 15) and goes on into the room.
func _duel(entry: Dictionary, shooter: Ship = null, seed_value := 1) -> void:
	arena = Arena.new(seed_value)
	arena.add_ship(shooter if shooter != null else _floor_ship())
	target = Fixture.room_ship()
	arena.add_ship(target, Vector2(800.0, 0.0))
	gun = _mount(entry, Vector2(20.5, 15.5))


func _mount(entry: Dictionary, at: Vector2) -> int:
	var full := {"kind": "laser", "damage_type": "energy", "damage": 1, "gimbal": 180, "cooldown": 0.0, "range": 2000}
	full.merge(entry, true)
	arena.weapons.defs["fx_gun"] = full
	return arena.add_mount(0, "fx_gun", at)


## Fire `gun` (its cooldown cleared) at the world point `at`, by default the wall cell (8, 15) of the target.
func _shoot(at := Vector2.INF) -> bool:
	arena.ships[0].cooldowns.clear()
	return arena.fire(0, gun, arena.cell_to_world(1, Vector2i(8, 15)) if at == Vector2.INF else at)


func _hp(x: int, y: int, ship: Ship = null) -> float:
	return (ship if ship != null else target).grid.hp_of(Vector2i(x, y))


func _events(kind: String) -> Array:
	return arena.events.filter(func(e): return e["type"] == "effect" and e["kind"] == kind)


func _person(name: String, species: String, x: float, y: float) -> CrewMember:
	var m := CrewMember.new(name, Vector2(x, y), species)
	return m


func _pressure() -> float:
	return target.atmosphere.pressure_at(Vector2i(12, 12))


# --- acid ---------------------------------------------------------------------------------------------------

func test_acid_eats_the_hit_cell_over_time_and_does_not_stack() -> void:
	_duel({"effects": {"acid": {"dps": 2.0, "seconds": 2.0}}})
	target.grid.force_tile(Vector2i(8, 15), "heavy_armor")  # 10 hp, no energy resist
	check(_shoot(), "fires")
	near(_hp(8, 15), 9.0, "the shot itself does 1")
	eq(arena.fx["timed"].size(), 1, "one acid is running")
	eq(_events("acid").size(), 1, "and said so")
	arena.step(1.0)
	near(_hp(8, 15), 7.0, "2 damage a second", 0.05)
	_shoot()  # a second shot renews it instead of stacking
	eq(arena.fx["timed"].size(), 1, "still one acid")
	arena.step(2.5)
	near(_hp(8, 15), 7.0 - 1.0 - 4.0, "it ran its 2 seconds after the renewal and stopped (4 damage), not more", 0.05)
	eq(arena.fx["timed"].size(), 0, "and is gone")


func test_acid_breaches_a_wall_and_never_wrecks_a_part_that_is_already_out() -> void:
	_duel({"effects": {"acid": {"dps": 8.0, "seconds": 3.0}}})
	_shoot()  # the steel wall has 4 hp
	arena.step(1.0)
	check(not target.grid.tiles.has(Vector2i(8, 15)), "the wall is eaten through")
	check(arena.events.any(func(e): return e["type"] == "breach"), "and breached")
	eq(arena.fx["timed"].size(), 0, "the acid stops once nothing is left to eat")
	# a part: acid wears it down to disabled, but never wrecks it
	_duel({"effects": {"acid": {"dps": 6.0, "seconds": 4.0}}})
	var uid := Fixture.put(target, "radiator", 9, 15)  # 2x2 on row 15, behind the wall at (8, 15), which is opened
	check(uid >= 0, "(setup)")
	target.grid.force_tile(Vector2i(8, 15), "floor")
	_shoot()
	arena.step(4.5)
	eq(target.components.instances[uid]["status"], "disabled", "the radiator is out of action")
	check(target.components.instances.has(uid), "but still there, not wrecked")


# --- spores -----------------------------------------------------------------------------------------------------

func test_spores_drain_the_air_of_the_room_hit() -> void:
	_duel({"effects": {"spores": {"o2_drain": 0.1, "seconds": 3.0}}})
	near(_pressure(), 1.0, "(setup: a full room)")
	_shoot()
	var e: Array = _events("spores")
	eq(e.size(), 1, "logged")
	check(e[0]["room_size"] > 50.0, "(the room hit is the big one)")
	arena.step(1.0)
	near(_pressure(), 0.9, "0.1 of the air a second", 0.005)
	arena.step(3.0)
	near(_pressure(), 0.7, "for 3 seconds and no longer", 0.005)
	eq(arena.fx["timed"].size(), 0, "and it is over")


func test_spores_renew_instead_of_stacking() -> void:
	_duel({"effects": {"spores": {"o2_drain": 0.1, "seconds": 2.0}}})
	_shoot()
	_shoot()
	eq(arena.fx["timed"].size(), 1, "two hits on the same room are one cloud")
	arena.step(2.5)
	near(_pressure(), 0.8, "which drains 0.1 a second for 2 seconds", 0.005)


# --- shard ------------------------------------------------------------------------------------------------------

## A target of solid wall, x 8..16, y 12..18, in the line of fire (row 15): the shot lands on (8, 15), which has five solid neighbours.
func _slab() -> void:
	for y in range(12, 19):
		for x in range(8, 17):
			target.grid.force_tile(Vector2i(x, y), "wall")


func _damaged_around(cell: Vector2i) -> Array:
	var out := []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := cell + Vector2i(dx, dy)
			if (dx != 0 or dy != 0) and target.grid.get_tile(c) == "wall" and target.grid.hp_of(c) < 4.0:
				out.append(c)
	return out


func test_shard_splinters_hit_neighbouring_cells() -> void:
	_duel({"effects": {"shard": {"splinters": 3, "dmg": 0.5}}})
	_slab()
	_shoot()
	near(_hp(8, 15), 3.0, "the shot does 1 to the cell it hits")
	var hit := _damaged_around(Vector2i(8, 15))
	eq(hit.size(), 3, "three of its neighbours were splintered")
	for c in hit:
		near(_hp(c.x, c.y), 3.5, "each for 0.5")
	eq(_events("shard")[0]["targets"].size(), 3, "the event says where the splinters went")
	# the same seed splinters the same cells; another seed may not
	_duel({"effects": {"shard": {"splinters": 3, "dmg": 0.5}}})
	_slab()
	_shoot()
	eq(_damaged_around(Vector2i(8, 15)), hit, "deterministic")


func test_shard_has_no_more_splinters_than_neighbours_and_skips_the_part_it_hit() -> void:
	_duel({"effects": {"shard": {"splinters": 8, "dmg": 1.0}}})
	_shoot()  # the wall at (8, 15): its solid neighbours are (8, 14) and (8, 16) only
	var hit := _damaged_around(Vector2i(8, 15))
	eq(hit.size(), 2, "only the two wall cells beside it")
	# a part hit directly is not splintered by its own shot; a neighbouring part is, once
	_duel({"effects": {"shard": {"splinters": 8, "dmg": 1.0}}})
	target.grid.force_tile(Vector2i(8, 15), "floor")
	var a := Fixture.put(target, "radiator", 9, 15)  # the shot lands on it, at (9, 15)
	var b := Fixture.put(target, "helm", 9, 13)  # and this one sits above it
	check(a >= 0 and b >= 0, "(setup)")
	_shoot()
	near(float(target.components.instances[a]["hp"]), 3.0, "the part hit takes the shot only")
	near(float(target.components.instances[b]["hp"]), 3.0, "its neighbour takes one splinter, though two of its cells touch the impact")
	near(_hp(8, 14), 3.0, "and the wall beside it one")
	near(_hp(8, 16), 3.0, "and the other")
	eq(_events("shard")[0]["targets"].size(), 3, "three splinters in all")


# --- sonic -----------------------------------------------------------------------------------------------------

func test_sonic_stuns_the_crew_in_the_room_hit_and_pauses_their_work() -> void:
	_duel({"effects": {"sonic": {"stun_s": 3.0}}})
	var inside := _person("In", "human", 12.5, 12.5)
	var outside := _person("Out", "human", 3.5, 3.5)
	target.crew.append_array([inside, outside])
	_shoot()
	near(inside.stun, 3.0, "the crew in the room are stunned")
	near(outside.stun, 0.0, "the ones elsewhere are not")
	eq(_events("sonic")[0]["stunned"], 1, "one stunned")
	check(inside.is_stunned(), "stunned means no walking and no work")
	check(inside.go_to(target.grid, Vector2i(18, 12)), "(setup: a path to walk)")
	var start := inside.pos
	var jobs := Jobs.new()
	jobs.tick(target, 1.0, true)
	eq(inside.pos, start, "a stunned crew member does not walk")
	near(inside.stun, 2.0, "and the stun runs down", 0.01)
	jobs.tick(target, 2.5, true)
	check(not inside.is_stunned(), "then they recover")


# --- magnetic -----------------------------------------------------------------------------------------------------

func test_magnetic_pulls_the_target_toward_the_shooter_and_drags_debris() -> void:
	_duel({"effects": {"magnetic": {"pull": 40.0}}})
	var near_debris := Effects.add_debris(arena, arena.cell_to_world(1, Vector2i(8, 15)) + Vector2(60, 0), Vector2.ZERO, 20.0)
	var far_debris := Effects.add_debris(arena, Vector2(800, 2000), Vector2.ZERO, 20.0)
	var mass: float = arena.ships[1].mass
	_shoot()
	var v: Vector2 = arena.ships[1].flight.vel
	near(v.x, -40.0 * Effects.PULL_MASS / mass, "the target gains pull x 1000 / its mass toward the shooter", 0.01)
	near(v.y, 0.0, "straight along the line between them", 0.01)
	check(arena.fx["debris"][near_debris]["vel"].x < -1000.0, "debris close to the impact is dragged (a light piece fast)")
	eq(arena.fx["debris"][far_debris]["vel"], Vector2.ZERO, "debris far away is not")
	eq(_events("magnetic")[0]["dragged"], 1, "the event counts it")
	var before: Vector2 = arena.fx["debris"][near_debris]["pos"]
	arena.step(0.5)
	check(arena.fx["debris"][near_debris]["pos"].x < before.x - 100.0, "and it moves")


func test_a_heavier_ship_is_pulled_less() -> void:
	_duel({"effects": {"magnetic": {"pull": 40.0}}})
	_shoot()
	var light: float = arena.ships[1].flight.vel.x
	_duel({"effects": {"magnetic": {"pull": 40.0}}})
	arena.ships[1].mass *= 2.0
	_shoot()
	near(arena.ships[1].flight.vel.x, light / 2.0, "twice the mass, half the speed")


# --- frost ------------------------------------------------------------------------------------------------------------

## The wall ship (a Wall.wall_ship with a mounted laser and its reactor, as in test_aiming) turned to face the shooter,
## 800 px east of it: ship 1. Returns the uid of its laser.
func _frost_target() -> int:
	var ship := Wall.wall_ship(1, 0)
	var uid := ship.components.place_mount(ship.grid, "laser_mk1", Wall.out_anchor(0), 0)
	var reactor := ship.components.place(ship.grid, "reactor_mk1", Wall.corner(0, 2, 5, 1, 4), 0)
	for c in [Wall.at(0, 1, 1), Wall.at(0, 2, 1)]:
		ship.cables.place(ship.grid, c)
	ship.refresh()
	check(uid >= 0 and reactor >= 0, "(setup: the gun and its reactor)")
	arena.add_ship(ship, Vector2(800.0, 0.0), -PI / 2.0)  # its wall faces west now
	return uid


func test_frost_slows_the_cooldown_of_the_weapon_it_hits() -> void:
	var left := []
	for slow in [0.0, 0.5]:
		arena = Arena.new(1)
		arena.add_ship(_floor_ship())
		var uid := _frost_target()
		var entry := {"cooldown": 0.0, "range": 2000, "damage": 0.1}
		if slow > 0.0:
			entry["effects"] = {"frost": {"slow": slow, "seconds": 4.0}}
		gun = _mount(entry, Vector2(20.5, 15.5))
		arena.ships[1].cooldowns[uid] = arena.tick + 120  # the target's laser is 2 seconds from ready
		var wall_at := arena.cell_to_world(1, Wall.at(0, 5, 0))  # a wall cell away from the mount
		_shoot(wall_at)
		arena.step(1.0)
		left.append(arena.cooldown_left(1, uid))
	near(left[0], 1.0, "unfrozen: one second left after one second", 0.05)
	near(left[1], 1.5, "frozen by half: its charge ran at half speed", 0.05)


func test_frost_slows_the_shield_recharge() -> void:
	var timers := []
	for slow in [0.0, 0.5]:
		arena = Arena.new(1)
		arena.add_ship(_floor_ship())
		target = _floor_ship()
		for c in [Vector2i(1, 14), Vector2i(1, 16), Vector2i(29, 14), Vector2i(29, 16), Vector2i(14, 1), Vector2i(16, 1), Vector2i(14, 29), Vector2i(16, 29), Vector2i(3, 15)]:
			target.grid.force_tile(c, "wall")
		check(target.components.place(target.grid, "reactor_mk1", Vector2i(9, 19), 0) > 0 and target.components.place(target.grid, "shield_mk1", Vector2i(13, 19), 0) > 0, "(setup)")
		for x in range(9, 17):
			target.cables.place(target.grid, Vector2i(x, 20))
		arena.add_ship(target, Vector2(800.0, 0.0))
		gun = _mount({"cooldown": 0.0, "range": 2000}, Vector2(20.5, 15.5))
		_shoot()  # the bubble takes its only layer: it comes back after 7 seconds and the 3 of a broken sector
		check(arena.ships[1].sector_timers[0].size() == 1, "(a layer is coming back)")
		var entry := {"cooldown": 0.0, "range": 2000, "pass_shields": true, "damage": 0.1}
		if slow > 0.0:
			entry["effects"] = {"frost": {"slow": slow, "seconds": 4.0}}
		var frost := _mount(entry, Vector2(20.5, 15.5))
		arena.ships[0].cooldowns.clear()
		arena.fire(0, frost, aim)  # gets through the bubble to the wall at (3, 15), and the room's systems are chilled
		arena.step(1.0)
		timers.append(float(arena.ships[1].sector_timers[0][0].x))
	near(timers[0], 9.0, "unfrozen: the layer has 9 of its 10 seconds to go", 0.05)
	near(timers[1], 9.5, "frozen by half: half a second more", 0.05)


# --- corrode ------------------------------------------------------------------------------------------------------------

func test_corrode_makes_the_wall_take_more_damage_for_a_while() -> void:
	_duel({"damage": 0.5, "effects": {"corrode": {"resist_mult": 0.5, "seconds": 3.0}}})
	_shoot()
	near(_hp(8, 15), 3.5, "the first shot does its 0.5")
	eq(arena.fx["corroded"].size(), 1, "the wall is corroded")
	_shoot()
	near(_hp(8, 15), 3.5 - 1.0, "the second does twice that (resist x0.5)")
	arena.step(3.5)
	eq(arena.fx["corroded"].size(), 0, "it wears off")
	_shoot()
	near(_hp(8, 15), 2.5 - 0.5, "and the wall is sound again")


func test_corrode_works_with_the_materials_own_resist() -> void:
	_duel({"damage": 1.0, "damage_type": "kinetic", "effects": {"corrode": {"resist_mult": 0.5, "seconds": 9.0}}})
	target.grid.force_tile(Vector2i(8, 15), "heavy_armor")  # kinetic x0.6
	_shoot()
	near(_hp(8, 15), 10.0 - 0.6, "heavy armour takes 0.6 of a kinetic hit")
	_shoot()
	near(_hp(8, 15), 10.0 - 0.6 - 1.2, "corroded, it takes 0.6 / 0.5 = 1.2")


# --- the shield stops them -----------------------------------------------------------------------------------------------

func test_a_shield_that_stops_the_shot_stops_its_effect() -> void:
	arena = Arena.new(1)
	arena.add_ship(_floor_ship())
	target = _floor_ship()
	for c in [Vector2i(1, 14), Vector2i(1, 16), Vector2i(29, 14), Vector2i(29, 16), Vector2i(14, 1), Vector2i(16, 1), Vector2i(14, 29), Vector2i(16, 29), Vector2i(3, 15)]:
		target.grid.force_tile(c, "wall")
	check(target.components.place(target.grid, "reactor_mk1", Vector2i(9, 19), 0) > 0 and target.components.place(target.grid, "shield_mk1", Vector2i(13, 19), 0) > 0, "(setup)")
	for x in range(9, 17):
		target.cables.place(target.grid, Vector2i(x, 20))
	arena.add_ship(target, Vector2(800.0, 0.0))
	gun = _mount({"effects": {"acid": {"dps": 1.0, "seconds": 2.0}, "corrode": {"resist_mult": 0.5, "seconds": 2.0}}}, Vector2(20.5, 15.5))
	_shoot()
	check(arena.events.any(func(e): return e["type"] == "shield"), "(the bubble took the shot)")
	eq(arena.fx["timed"].size() + arena.fx["corroded"].size(), 0, "no acid and no corrosion got through")
	eq(_events("acid").size(), 0, "none logged")


# --- beams ---------------------------------------------------------------------------------------------------------------

func test_a_beam_renews_its_acid_every_tick_instead_of_stacking() -> void:
	_duel({"kind": "beam", "damage": 0.2, "duration": 1.0, "cooldown": 3.0, "effects": {"acid": {"dps": 1.0, "seconds": 1.0}}})
	target.grid.force_tile(Vector2i(8, 15), "heavy_armor")
	_shoot()
	arena.step(1.0)
	eq(arena.fx["timed"].size(), 1, "one acid for the whole beam")
	check(arena.events.filter(func(e): return e["type"] == "effect" and e["kind"] == "acid").size() >= 3, "renewed on every tick of the beam")


func test_a_beams_magnetic_pull_scales_with_its_tick() -> void:
	_duel({"kind": "beam", "damage": 0.1, "duration": 1.0, "tick": 0.25, "cooldown": 3.0, "effects": {"magnetic": {"pull": 40.0}}})
	var mass: float = arena.ships[1].mass
	_shoot()
	arena.step(1.2)
	var gained: float = absf(arena.ships[1].flight.vel.x)
	check(gained < 40.0 * Effects.PULL_MASS / mass * 1.5, "a beam pulls about one shot's worth over its whole second, not one per tick")
	check(gained > 0.0, "but it pulls")


# --- self_room ------------------------------------------------------------------------------------------------------------

## A shooter with a sealed room (Fixture.room_ship) and a virtual mount inside it at (12.5, 12.5); ship 1 is the target.
func _self_duel(entry: Dictionary) -> Ship:
	var shooter := Fixture.room_ship()
	arena = Arena.new(1)
	arena.add_ship(shooter)
	target = Fixture.room_ship()
	arena.add_ship(target, Vector2(800.0, 0.0))
	gun = _mount(entry, Vector2(12.5, 12.5))
	return shooter


func test_self_room_o2_drain_heat_and_fire() -> void:
	var shooter := _self_duel({"effects": {"self_room": {"o2_drain": 0.3, "heat": 40.0, "fire_chance": 1.0}}})
	BuildSession.new(shooter).apply(BuildSession.room_changes(Vector2i(8, 20), Vector2i(16, 26), "wall", "floor"))  # a second room
	var reactor := Fixture.put(shooter, "reactor_mk1", 12, 10)
	var elsewhere := Fixture.put(shooter, "reactor_mk1", 10, 21)
	check(reactor >= 0 and elsewhere >= 0, "(setup)")
	shooter.refresh()
	near(shooter.atmosphere.pressure_at(Vector2i(12, 12)), 1.0, "(a full room)")
	check(_shoot(Vector2(800.0, -300.0)), "fires")
	near(shooter.atmosphere.pressure_at(Vector2i(12, 12)), 0.7, "the shot cost 30 percent of the air in its room")
	near(float(shooter.components.instances[reactor]["heat"]), 40.0, "and 40 heat to the parts in it")
	near(float(shooter.components.instances[elsewhere]["heat"]), 0.0, "but not to parts in another room")
	check(not shooter.fires.is_empty(), "and started a fire (fire_chance 1)")
	check(not _events("self_room").is_empty(), "it is in the log")
	_shoot(Vector2(800.0, -300.0))
	near(shooter.atmosphere.pressure_at(Vector2i(12, 12)), 0.4, "each shot again")


func test_self_room_fire_chance_zero_never_burns_and_one_roll_per_shot() -> void:
	var shooter := _self_duel({"effects": {"self_room": {"fire_chance": 0.0, "o2_drain": 0.01}}})
	for i in 20:
		_shoot(Vector2(800.0, -300.0))
	check(shooter.fires.is_empty(), "no fire at chance 0")


func test_self_room_shock_hurts_organic_crew_only_while_firing() -> void:
	var shooter := _self_duel({"cooldown": 2.0, "effects": {"self_room": {"shock_dps": 2.0}}})
	var human := _person("Human", "human", 14.5, 12.5)
	var robot := _person("Robot", "gauntling", 15.5, 12.5)
	var outside := _person("Out", "human", 3.5, 3.5)
	shooter.crew.append_array([human, robot, outside])
	var hp0 := human.hp
	var robot0 := robot.hp
	_shoot(Vector2(800.0, -300.0))
	arena.step(1.0)
	near(hp0 - human.hp, 2.0, "2 hp a second to the organic crew in the room", 0.05)
	near(robot0 - robot.hp, 0.0, "none to the mechanical")
	near(outside.hp, outside.max_hp, "none outside the room")
	arena.step(3.0)
	near(hp0 - human.hp, 4.0, "and it stops when the weapon stops: one 2-second cooldown, 4 hp in all", 0.05)


# --- needs_operator and needs_crew_in_room --------------------------------------------------------------------------------

func test_needs_operator_gives_full_power_only_with_the_right_species() -> void:
	var dealt := []
	for who in ["", "Ada", "Pris"]:
		var shooter := _self_duel({"damage": 2.0, "effects": {"needs_operator": {"species": "prismatic", "else_mult": 0.5}}})
		shooter.crew.append_array([_person("Ada", "human", 14.5, 12.5), _person("Pris", "prismatic", 15.5, 12.5)])
		if who != "":
			shooter.manned[gun] = who
		_shoot()
		dealt.append(4.0 - _hp(8, 15))
	near(dealt[0], 1.0, "nobody at the station: half power")
	near(dealt[1], 1.0, "a human at it: half power")
	near(dealt[2], 2.0, "a Prismatic at it: full power")


func test_needs_operator_can_slow_the_rate_instead() -> void:
	var cd := []
	for who in ["Ada", "Pris"]:
		var shooter := _self_duel({"cooldown": 2.0, "effects": {"needs_operator": {"species": ["prismatic"], "else_mult": 0.5, "stat": "rate"}}})
		shooter.crew.append_array([_person("Ada", "human", 14.5, 12.5), _person("Pris", "prismatic", 15.5, 12.5)])
		shooter.manned[gun] = who
		_shoot()
		cd.append(arena.cooldown_left(0, gun))
	near(cd[0], 4.0, "without the right operator it fires at half rate", 0.02)
	near(cd[1], 2.0, "with them at full rate", 0.02)


func test_needs_crew_in_room_wants_enough_hands() -> void:
	var cd := []
	for n in [1, 2, 3]:
		var shooter := _self_duel({"cooldown": 1.0, "effects": {"needs_crew_in_room": {"count": 3, "else_mult": 0.4}}})
		for i in n:
			shooter.crew.append(_person("K%d" % i, "kett", 12.5 + i, 12.5))
		shooter.crew.append(_person("Outside", "kett", 3.5, 3.5))  # does not count: not in the room
		_shoot()
		cd.append(arena.cooldown_left(0, gun))
	near(cd[0], 2.5, "one crew member: x0.4 rate", 0.02)
	near(cd[1], 2.5, "two: still short", 0.02)
	near(cd[2], 1.0, "three: full rate", 0.02)


func test_stunned_or_downed_crew_do_not_count_as_hands() -> void:
	var shooter := _self_duel({"cooldown": 1.0, "effects": {"needs_crew_in_room": {"count": 2, "else_mult": 0.5}}})
	var a := _person("A", "kett", 12.5, 12.5)
	var b := _person("B", "kett", 13.5, 12.5)
	shooter.crew.append_array([a, b])
	b.stun = 5.0
	_shoot()
	near(arena.cooldown_left(0, gun), 2.0, "one stunned: short", 0.02)
	b.stun = 0.0
	b.hp = 0.0
	_shoot()
	near(arena.cooldown_left(0, gun), 2.0, "one down: short", 0.02)


# --- ammo_mult ----------------------------------------------------------------------------------------------------------------

func test_ammo_mult_spends_more_ammo_per_shot_with_the_fraction_carried() -> void:
	var shooter := _self_duel({"ammo": "scrap", "effects": {"ammo_mult": 1.5}})
	shooter.inventory.load_dict({"scrap": 20})
	var spent := []
	for i in 4:
		var before := shooter.inventory.count("scrap")
		check(_shoot(), "fires")
		spent.append(before - shooter.inventory.count("scrap"))
	eq(spent, [1, 2, 1, 2], "1.5 a shot is 1, 2, 1, 2")
	var heavy := _self_duel({"ammo": "scrap", "ammo_mult": 3.0})  # also accepted at the top level of the entry
	heavy.inventory.load_dict({"scrap": 7})
	_shoot()
	_shoot()
	eq(heavy.inventory.count("scrap"), 1, "ammo_mult 3: two shots take 6")
	check(not _shoot(), "and with one left there is no third")
	eq(arena.weapons.can_fire(arena, 0, gun, aim), "no ammo", "because it is out of ammo")


# --- the validator and the data ------------------------------------------------------------------------------------------------

func test_the_validator_knows_every_key_and_catches_typos() -> void:
	var good := {"effects": {"acid": {"dps": 1.5, "seconds": 4}, "spores": {"o2_drain": 0.05, "seconds": 5}, "shard": {"splinters": 3, "dmg": 0.5},
		"sonic": {"stun_s": 2}, "magnetic": {"pull": 30}, "frost": {"slow": 0.4, "seconds": 5}, "corrode": {"resist_mult": 0.7, "seconds": 10},
		"self_room": {"o2_drain": 0.3, "heat": 40, "fire_chance": 0.1, "shock_dps": 2}, "needs_operator": {"species": "prismatic", "else_mult": 0.5},
		"needs_crew_in_room": {"count": 3, "else_mult": 0.4, "stat": "rate"}, "ammo_mult": 1.5, "lock_doors": true}}
	eq(Effects.problems(good, ["prismatic"]), [], "everything at once is fine")
	eq(Effects.problems({"effects": ["lock_doors", "tether"]}), [], "the old list of tags is fine")
	eq(Effects.problems({"ammo": "scrap", "ammo_mult": 3}), [], "a top-level ammo_mult is fine")
	eq(Effects.problems({}), [], "no effects is fine")
	var bad := [
		[{"effects": {"acids": {"dps": 1, "seconds": 1}}}, "unknown effect"],
		[{"effects": {"acid": {"dps": 1}}}, "needs 'seconds'"],
		[{"effects": {"acid": {"dps": 1, "seconds": 1, "dsp": 3}}}, "unknown key"],
		[{"effects": {"acid": {"dps": -1, "seconds": 1}}}, "acid.dps"],
		[{"effects": {"acid": {"dps": 1, "seconds": 1, "type": "poison"}}}, "damage type"],
		[{"effects": {"shard": {"splinters": 2.5, "dmg": 1}}}, "whole number"],
		[{"effects": {"shard": {"splinters": 0, "dmg": 1}}}, "shard.splinters"],
		[{"effects": {"frost": {"slow": 1.5, "seconds": 1}}}, "frost.slow"],
		[{"effects": {"corrode": {"resist_mult": 0.0, "seconds": 1}}}, "corrode.resist_mult"],
		[{"effects": {"self_room": {"smoke": 1}}}, "unknown key"],
		[{"effects": {"self_room": {}}}, "self_room"],
		[{"effects": {"needs_operator": {"species": "nobody", "else_mult": 0.5}}}, "not a species"],
		[{"effects": {"needs_operator": {"else_mult": 0.5}}}, "needs a species"],
		[{"effects": {"needs_operator": {"species": "kett", "else_mult": 0.5, "stat": "luck"}}}, "stat"],
		[{"effects": {"needs_crew_in_room": {"count": 3}}}, "needs 'else_mult'"],
		[{"effects": {"ammo_mult": 0}}, "ammo_mult"],
		[{"effects": {}}, "empty"],
		[{"effects": []}, "empty list"],
		[{"effects": ["explode"]}, "not one of"],
		[{"effects": "acid"}, "list of tags or an object"],
	]
	for case in bad:
		var p := Effects.problems(case[0], ["prismatic", "kett"])
		check(p.size() >= 1 and p.any(func(s): return case[1] in s), "%s is caught as '%s' (got %s)" % [str(case[0]), case[1], str(p)])


func test_every_weapon_in_the_data_has_valid_effects() -> void:
	var species: Array = []
	for s in Content.list("species"):
		species.append(s["id"])
	var w := Weapons.new()
	for id in w.defs:
		for p in Effects.problems(w.defs[id], species):
			check(false, "%s: %s" % [id, p])


func test_the_old_tags_are_read_as_tags_and_change_nothing() -> void:
	eq(Effects.of({"effects": ["lock_doors"]}), {"lock_doors": true}, "a list of tags becomes a Dictionary")
	eq(Effects.of({}), {}, "no effects, none")
	_duel({})
	var siren := arena.add_mount(0, "siren_ion_neon", Vector2(20.5, 15.5))
	arena.ships[0].cooldowns.clear()
	check(arena.fire(0, siren, aim), "a weapon with list-style effects still fires")


func test_weapon_stats_carry_their_id_for_the_art() -> void:
	eq(Weapons.new().def("laser_mk1")["id"], "laser_mk1", "def() says which weapon it is")


# --- replay ---------------------------------------------------------------------------------------------------------------------

func test_a_fight_with_every_effect_replays_exactly() -> void:
	var snaps := []
	for run in 2:
		_duel({"cooldown": 0.2, "damage": 0.5, "effects": {"acid": {"dps": 1.0, "seconds": 2.0}, "spores": {"o2_drain": 0.05, "seconds": 3.0},
			"shard": {"splinters": 3, "dmg": 0.3}, "sonic": {"stun_s": 1.0}, "magnetic": {"pull": 10.0}, "corrode": {"resist_mult": 0.6, "seconds": 3.0},
			"self_room": {"o2_drain": 0.01}}}, null, 5)
		_slab()
		target.crew.append(_person("C", "human", 12.5, 12.5))
		for i in 12:
			arena.ships[0].cooldowns.clear()
			arena.fire(0, gun, aim)
			arena.step(0.25)
		snaps.append(arena.snapshot())
	eq(snaps[0], snaps[1], "the same seed and inputs give the same arena, effects included")
	check(snaps[0]["fx"]["timed"].size() > 0 or snaps[0]["fx"]["corroded"].size() > 0, "(and the effects were running)")


# --- what they look like ---------------------------------------------------------------------------------------------------------

func test_every_effect_event_has_pictures_in_the_views_format_and_they_replay() -> void:
	var entries := {}
	var again := {}
	for run in 2:
		_duel({"cooldown": 0.2, "damage": 0.5, "effects": {"acid": {"dps": 1.0, "seconds": 2.0}, "spores": {"o2_drain": 0.05, "seconds": 3.0},
			"shard": {"splinters": 3, "dmg": 0.3}, "sonic": {"stun_s": 1.0}, "magnetic": {"pull": 10.0}, "corrode": {"resist_mult": 0.6, "seconds": 3.0},
			"frost": {"slow": 0.3, "seconds": 3.0}}}, null, 5)
		_slab()
		for i in 6:
			_shoot()
			arena.step(0.3)
		for e in arena.events:
			if e["type"] == "effect":
				(entries if run == 0 else again)[e["kind"]] = EffectFx.of(arena, e)
			elif e["type"] == "hit" and e.has("dot") and run == 0:
				entries["dot"] = EffectFx.dot(e)
	for kind in ["acid", "spores", "shard", "sonic", "magnetic", "corrode", "dot"]:
		check(entries.has(kind) and not entries[kind].is_empty(), "%s has pictures" % kind)
		for f in entries.get(kind, []):
			check(f["k"] in ["flash", "ring", "spark", "puff", "streak"] and float(f["life"]) > 0.0 and f["pos"] is Vector2, "%s: an entry in the view's format (%s)" % [kind, str(f)])
	for kind in again:
		eq(again[kind], entries[kind], kind + " looks the same on a replay")
	_self_duel({"effects": {"self_room": {"o2_drain": 0.2, "heat": 20.0, "shock_dps": 1.0}}})
	_shoot()
	var ev: Array = _events("self_room")
	check(not ev.is_empty() and not EffectFx.of(arena, ev[0]).is_empty(), "the shooter's own side effects show too")


func test_the_art_looks_for_the_weapons_own_projectile_before_the_kinds() -> void:
	Art.root = "res://tests/fixtures/art"
	Art.clear_cache()
	check(Art.projectile_of("my_gun", "bolt") == Art.projectile("bolt") and Art.projectile("bolt") != null, "no art of its own: the kind's")
	check(Art.projectile_of("laser", "bolt") == Art.projectile("laser"), "art under the weapon's id wins")
	check(Art.projectile_of("my_gun", "bolt", "_impact") == null, "no impact art, none")
	check(Art.projectile_of("", "laser") == Art.projectile("laser"), "no id: the kind's")
	Art.root = Art.DEFAULT_ROOT
	Art.clear_cache()
