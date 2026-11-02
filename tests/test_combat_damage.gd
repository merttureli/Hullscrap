extends "res://tests/base_test.gd"
## What shots do to cells: the ray march, pierce, wall materials (resist, deflect, ricochet,
## ablative, lattice), splash and spacing, breaches and rooms, parts that get disabled.

const Structure = preload("res://scripts/ship/structure.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Rooms = preload("res://scripts/sim/rooms.gd")

var arena: Arena
var gun: int  ## the shooter's mount: the east side of ship 0, laser_mk1
var target: Ship  ## ship 1, at (800, 0); row 15 of its grid is the line of fire
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


## Ship 0 (the shooter, at the origin) and ship 1 (`target`, at x 800). A laser from ship 0's east
## mount flies along the world row y = 0, which is row 15 of the target.
func _duel(seed_value := 1) -> void:
	arena = Arena.new(seed_value)
	arena.add_ship(_ship())
	target = _ship()
	gun = arena.add_mount(0, "laser_mk1", Vector2(20.5, 15.5))
	arena.weapons.defs["laser_mk1"]["damage"] = 2  # pinned at 2: these tests are about the damage rules, not the balance numbers


func _join() -> void:
	arena.add_ship(target, Vector2(800.0, 0.0))


func _tile(x: int, y: int, id: String) -> void:
	target.grid.force_tile(Vector2i(x, y), id)


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


func _hp(x: int, y: int) -> float:
	return target.grid.hp_of(Vector2i(x, y))


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func test_the_new_materials_are_in_the_tile_data() -> void:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	for id in ["scrap_plate", "titanium_alloy", "heavy_armor", "reflective_coating", "ablative_plating", "whipple_spacer", "neon_lattice"]:
		var d := defs.get_def(id)
		check(d.get("solid", false) == true, id + " is solid")
		for k in ["hp", "mass", "cost", "line", "resist", "deflect", "quirk"]:
			check(d.has(k), id + " has " + k)
		check(not (d["cost"] as Dictionary).is_empty(), id + " costs material")
	eq([defs.get_def("wall")["hp"], defs.get_def("wall")["mass"], defs.get_def("door")["hp"]], [4.0, 2.0, 3.0], "steel wall 4 hp mass 2, door 3 hp")
	eq(defs.get_def("heavy_armor")["resist"], {"kinetic": 0.6, "explosive": 0.7}, "heavy armour resists")
	eq(defs.get_def("reflective_coating")["deflect"], {"energy": 0.4}, "reflective deflects energy")
	eq([defs.get_def("ablative_plating")["quirk"], defs.get_def("neon_lattice")["quirk"]], ["ablative", "lattice_power"], "quirks")
	var s := _ship()
	eq(s.grid.can_place("heavy_armor", Vector2i(5, 5)), "", "a new material can be built")


func test_arena_flight_uses_the_tile_masses_of_the_data() -> void:
	_duel()
	target.grid.force_tile(Vector2i(5, 5), "heavy_armor")
	target.grid.force_tile(Vector2i(6, 5), "wall")
	_join()
	var s := _ship()
	s.grid.force_tile(Vector2i(5, 5), "wall")
	s.grid.force_tile(Vector2i(6, 5), "wall")
	var plain := arena.add_ship(s)
	var floors := float(target.grid.hull.size() - 2)
	near(arena.ships[1].mass, floors + 5.0 + 2.0, "heavy armour weighs 5")
	near(arena.ships[plain].mass, floors + 4.0, "two steel walls weigh 2 each")


func test_a_laser_hits_the_first_wall_and_not_the_floor_behind_it() -> void:
	_duel()
	_tile(3, 15, "wall")
	_tile(6, 15, "wall")  # floor between the two walls
	_join()
	check(_shoot(gun), "fired")
	eq(_hp(3, 15), 2.0, "first wall took the 2 damage")
	eq(_hp(6, 15), 4.0, "second wall untouched")
	eq(target.grid.hp.keys(), [Vector2i(3, 15)], "floor cells took nothing")
	eq(_count("hit"), 1, "one hit")
	_shoot(gun)
	eq(target.grid.get_tile(Vector2i(3, 15)), "", "second hit breaches it")
	_shoot(gun)
	eq(_hp(6, 15), 2.0, "the next shot flies over the floor and the hole into the next wall")


func test_pierce_carries_the_leftover_damage_into_the_next_wall() -> void:
	_duel()
	_tile(3, 15, "wall")
	_tile(6, 15, "wall")
	_tile(8, 15, "wall")
	_join()
	var spear := _def("spear", {"damage": 6, "pierce": 1})
	_shoot(spear)
	eq(target.grid.get_tile(Vector2i(3, 15)), "", "first wall destroyed (4 of 6)")
	eq(_hp(6, 15), 2.0, "leftover 2 into the second wall")
	eq(_hp(8, 15), 4.0, "pierce 1 stops after one more cell")
	var plain := _def("plain", {"damage": 6, "pierce": 0})
	_shoot(plain)
	eq(target.grid.get_tile(Vector2i(6, 15)), "", "no pierce: the shot ends in the wall it hits, even with damage to spare")
	eq(_hp(8, 15), 4.0, "so the third wall is safe")
	var rake := _def("rake", {"damage": 100, "pierce": 5})
	_shoot(rake)
	eq(target.grid.get_tile(Vector2i(8, 15)), "", "plenty of damage and pierce reaches the last wall")


func test_reflective_coating_deflects_about_40_percent_of_energy() -> void:
	_duel(5)
	_tile(3, 15, "reflective_coating")
	_join()
	var tiny := _def("tiny", {"damage": 0.001})
	for i in 1000:
		_shoot(tiny)
	var n := _count("deflect")
	check(n >= 340 and n <= 460, "about 400 of 1000 deflected, got %d" % n)
	eq(_count("deflect") + _count("hit"), 1000, "every shot was deflected or hit")
	var again := _count("deflect")
	_duel(5)
	_tile(3, 15, "reflective_coating")
	_join()
	tiny = _def("tiny", {"damage": 0.001})
	for i in 1000:
		_shoot(tiny)
	eq(_count("deflect"), again, "same seed, same count")
	# Kinetic is not deflected, and the coating takes 1.5x from it.
	_duel(5)
	_tile(3, 15, "reflective_coating")
	_join()
	var pebble := _def("pebble", {"kind": "bolt", "damage_type": "kinetic", "damage": 1, "speed": 700})
	_shoot(pebble)
	arena.step(2.0)
	eq(_count("deflect"), 0, "kinetic shots are not deflected")
	near(_hp(3, 15), 2.0 - 1.0 * 1.5, "a 1 damage bolt does 1.5 to the coating")


func test_heavy_armour_and_titanium_take_less_kinetic_damage() -> void:
	_duel()
	_tile(3, 15, "heavy_armor")
	_join()
	var bolt := arena.add_mount(0, "test_bolt", Vector2(20.5, 15.5))  # kinetic, 2 damage
	_shoot(bolt)
	arena.step(2.0)
	near(_hp(3, 15), 10.0 - 2.0 * 0.6, "heavy armour takes 0.6x kinetic")
	_duel()
	_tile(3, 15, "titanium_alloy")
	_join()
	bolt = arena.add_mount(0, "test_bolt", Vector2(20.5, 15.5))
	_shoot(bolt)
	arena.step(2.0)
	near(_hp(3, 15), 6.0 - 2.0 * 0.8, "titanium takes 0.8x kinetic")
	_duel()
	_tile(3, 15, "heavy_armor")
	_join()
	_shoot(gun)
	near(_hp(3, 15), 10.0 - 2.0, "energy hits heavy armour for full damage")


## Move ship 0 so that its east mount is 300 px before the middle of the west face of `cell` of
## ship 1, on the line along `d`. Returns the mount's world position.
func _muzzle_for(d: Vector2, cell: Vector2i) -> Vector2:
	var face := arena.cell_to_world(1, cell) - Vector2(16.0, 0.0)
	var mount := arena.local_to_world(0, Vector2(20.5, 15.5))
	arena.ships[0].flight.pos += face - d * 300.0 - mount
	return arena.local_to_world(0, Vector2(20.5, 15.5))


## 300 tiny kinetic bolts at one wall cell, coming at `deg` degrees off the wall's face normal.
## Returns [ricochets, hits on the target]; a ricochet is reflected and flies on into space.
func _ricochets(deg: float) -> Array:
	_duel(3)
	for y in range(5, 26):
		_tile(10, y, "wall")  # a wall column; the shots enter it through its west face
	_join()
	var tiny := _def("pebble", {"kind": "bolt", "damage_type": "kinetic", "damage": 0.001, "speed": 700})
	var d := Vector2.from_angle(deg_to_rad(deg))
	var muzzle := _muzzle_for(d, Vector2i(10, 15))
	for i in 300:
		_shoot(tiny, muzzle + d * 100.0)
	arena.step(1.5)
	var hits := 0
	for e in arena.events:
		hits += int(e["type"] == "hit" and e["ship"] == 1)
	return [_count("ricochet"), hits]


func test_kinetic_shots_ricochet_on_a_curve_of_the_angle() -> void:
	# 0 below 40 degrees off the normal, rising linearly to 0.8 at 75 degrees and beyond.
	var shallow := _ricochets(75.0)
	check(shallow[0] >= 215 and shallow[0] <= 265, "80%% of 300 shots at 75 degrees glance off, got %d" % shallow[0])
	eq(shallow[0] + shallow[1], 300, "every shot glanced off or hit")
	var steep := _ricochets(40.0)
	eq(steep[0], 0, "40 degrees off the normal is steep enough")
	var straight := _ricochets(0.0)
	eq(straight, [0, 300], "head-on shots never ricochet")
	var edge := _ricochets(58.0)
	check(edge[0] >= 95 and edge[0] <= 150, "41%% at 58 degrees (about 123 of 300), got %d" % edge[0])
	var mid := _ricochets(50.0)
	check(mid[0] >= 45 and mid[0] <= 95, "23%% at 50 degrees (about 69 of 300), got %d" % mid[0])
	var grazing := _ricochets(85.0)
	check(grazing[0] >= 215 and grazing[0] <= 265, "past 75 degrees it stays at 80%%, got %d" % grazing[0])


func test_energy_does_not_ricochet() -> void:
	_duel()
	for y in range(5, 26):
		_tile(10, y, "wall")
	_join()
	var tiny := _def("beamlet", {"damage": 0.001})
	var d := Vector2.from_angle(deg_to_rad(80.0))
	var muzzle := _muzzle_for(d, Vector2i(10, 15))
	for i in 100:
		_shoot(tiny, muzzle + d * 100.0)
	eq(_count("ricochet"), 0, "lasers are not kinetic")
	eq(_count("hit"), 100, "all hit")


func test_ablative_plating_loses_max_hp_on_energy_hits() -> void:
	_duel()
	_tile(3, 15, "ablative_plating")
	_join()
	_shoot(gun)  # 2 energy x 0.5 resist = 1
	eq([_hp(3, 15), target.grid.max_hp_of(Vector2i(3, 15))], [4.0, 4.0], "hp 5 -> 4, max 5 -> 4")
	_shoot(gun)
	eq([_hp(3, 15), target.grid.max_hp_of(Vector2i(3, 15))], [3.0, 3.0], "then 3 and 3")
	var bolt := arena.add_mount(0, "test_bolt", Vector2(20.5, 15.5))
	_shoot(bolt)
	arena.step(2.0)
	eq([_hp(3, 15), target.grid.max_hp_of(Vector2i(3, 15))], [1.0, 3.0], "kinetic hurts it (2 x 1.0) but does not burn it: max stays 3")
	for i in 5:
		_shoot(gun)
	eq(target.grid.get_tile(Vector2i(3, 15)), "", "worn away")


func test_neon_lattice_counts_the_energy_it_absorbs() -> void:
	_duel()
	_tile(3, 15, "neon_lattice")
	_tile(5, 15, "wall")
	_join()
	_shoot(gun)  # 2 x 0.7 = 1.4 absorbed
	near(float(arena.power_bonus.get(1, 0.0)), 1.4 * 0.2, "20% of the absorbed energy")
	near(_hp(3, 15), 3.0 - 1.4, "lattice hp")
	_shoot(gun)
	_shoot(gun)  # lattice (1.6 left) takes 1.4 then 0.2, the wall is not reached
	near(float(arena.power_bonus.get(1, 0.0)), (1.4 + 1.4 + 0.2) * 0.2, "only what it really absorbed")
	_shoot(gun)  # now the wall
	near(float(arena.power_bonus.get(1, 0.0)), 3.0 * 0.2, "a plain wall adds nothing")


func test_ion_does_no_structural_damage() -> void:
	_duel()
	_tile(3, 15, "wall")
	_join()
	var ion := _def("ion", {"damage_type": "ion", "damage": 5})
	_shoot(ion)
	eq(_hp(3, 15), 4.0, "wall unharmed")
	eq(target.grid.hp.size(), 0, "no damage recorded")
	eq(Structure.structure_fraction(arena.ships[1]), 1.0, "structure unharmed")
	eq(_count("hit"), 1, "but it did hit")


func test_missile_splash_spreads_half_the_damage_to_nearby_cells() -> void:
	_duel()
	_tile(3, 15, "wall")  # the impact cell
	_tile(3, 14, "wall")  # beside it
	_tile(3, 17, "wall")  # 2 away, wall between? no: (3,16) is floor
	_tile(5, 15, "wall")  # 2 away
	_tile(3, 12, "wall")  # 3 away
	_join()
	var rocket := arena.add_mount(0, "test_missile", Vector2(20.5, 15.5))  # 4 explosive, splash 2 cells
	_shoot(rocket)
	arena.step(3.0)
	eq(target.grid.get_tile(Vector2i(3, 15)), "", "the impact cell took 4 and is gone")
	near(_hp(3, 14), 4.0 - 2.0, "next to the impact: 50% of 4")
	near(_hp(3, 17), 4.0 - 0.6, "2 away with a floor gap between: 30% of the splash")
	near(_hp(5, 15), 4.0 - 0.6, "2 away with a floor gap between: 30% of the splash")
	eq(_hp(3, 12), 4.0, "outside the radius")


func test_the_whipple_spacing_rule_cuts_splash_on_the_inner_layer() -> void:
	_duel()
	_tile(3, 15, "whipple_spacer")
	_tile(4, 15, "wall")  # touching: no gap
	_join()
	var rocket := arena.add_mount(0, "test_missile", Vector2(20.5, 15.5))
	_shoot(rocket)
	arena.step(3.0)
	var touching := _hp(4, 15)
	near(touching, 4.0 - 2.0, "an inner layer right behind the spacer gets the full splash")
	_duel()
	_tile(3, 15, "whipple_spacer")
	_tile(5, 15, "wall")  # one floor cell of gap
	_join()
	rocket = arena.add_mount(0, "test_missile", Vector2(20.5, 15.5))
	_shoot(rocket)
	arena.step(3.0)
	near(_hp(5, 15), 4.0 - 0.6, "behind a gap it gets 30% of that")
	check(_hp(5, 15) > touching, "so the spaced layer is better off")
	eq(target.grid.get_tile(Vector2i(3, 15)), "", "the spacer itself is sacrificed")


func test_splash_hits_a_part_once_and_resists_apply() -> void:
	_duel()
	_tile(3, 15, "scrap_plate")
	_tile(4, 14, "heavy_armor")
	var uid := target.components.place(target.grid, "reactor_mk1", Vector2i(3, 16), 0)
	check(uid > 0, "reactor placed")
	target.components.instances[uid]["hp"] = 10
	_join()
	var rocket := arena.add_mount(0, "test_missile", Vector2(20.5, 15.5))
	_shoot(rocket)
	arena.step(3.0)
	eq(target.grid.get_tile(Vector2i(3, 15)), "", "scrap plate (3 hp, x1.5 explosive) is gone")
	near(_hp(4, 14), 10.0 - 2.0 * 0.7, "heavy armour: 0.7x explosive on the splash")
	near(float(target.components.instances[uid]["hp"]), 8.0, "the reactor took 50% of 4 once, though 8 of its cells are in range")


func test_flak_throws_a_fan_of_pellets() -> void:
	_duel(2)
	_join()
	var flak := arena.add_mount(0, "test_flak", Vector2(15.5, 15.5))
	check(_shoot(flak), "fired")
	eq(arena.projectiles.size(), 5, "5 pellets")
	var angles := []
	for p in arena.projectiles:
		var a: float = absf(rad_to_deg((p["vel"] as Vector2).angle()))
		angles.append(a)
		check(a <= 6.0 + 1e-3, "within the 12 degree spread: %f" % a)
		near((p["vel"] as Vector2).length(), 600.0, "flak speed")
	check(angles.min() != angles.max(), "pellets differ")


func test_a_missile_homes_and_a_bolt_does_not() -> void:
	_duel()
	for y in range(13, 18):
		for x in range(13, 18):
			_tile(x, y, "wall")
	_join()
	var rocket := arena.add_mount(0, "test_missile", Vector2(15.5, 15.5))
	var bolt := arena.add_mount(0, "test_bolt", Vector2(15.5, 15.5))
	var off := Vector2(800.0, 0.0).rotated(deg_to_rad(20.0))  # 20 degrees off the target
	_shoot(bolt, off)
	arena.step(2.0)
	eq(_count("hit"), 0, "the bolt flies by")
	_shoot(rocket, off)
	arena.step(4.0)
	check(_count("hit") >= 1, "the missile turned onto the ship")


func test_a_beam_burns_for_its_duration() -> void:
	_duel()
	_tile(3, 15, "wall")
	_tile(6, 15, "wall")
	_join()
	var lance := _def("lance", {"kind": "beam", "damage": 4, "duration": 1.0, "tick": 0.25})
	_shoot(lance)
	arena.step(0.55)
	near(_hp(3, 15), 4.0 - 3.0, "3 ticks of 1 damage in 0.55 s")
	arena.step(2.0)
	eq(arena.beams.size(), 0, "the beam ended")
	eq(target.grid.get_tile(Vector2i(3, 15)), "", "4 ticks in the 1 s duration burned the wall through")
	eq(_hp(6, 15), 4.0, "and no more")


func test_walls_and_doors_stop_shots_and_breach_at_zero_hp() -> void:
	_duel()
	_tile(3, 15, "wall")
	_tile(4, 15, "door")
	_tile(5, 15, "door")
	_join()
	var hull: float = Structure.totals(target).x
	_shoot(gun)
	_shoot(gun)
	eq(target.grid.get_tile(Vector2i(3, 15)), "", "wall breached")
	eq(target.grid.breached, {Vector2i(3, 15): "wall"}, "remembered for repair")
	eq(hull - Structure.totals(target).x, 4.0, "structure lost the 4 dealt to the wall")
	_shoot(gun)
	eq(_hp(4, 15), 1.0, "a door has 3 hp and stops shots")
	_shoot(gun)
	eq(target.grid.get_tile(Vector2i(4, 15)), "", "door cell breached")
	eq(target.grid.breached[Vector2i(4, 15)], "door", "as a door")
	eq(hull - Structure.totals(target).x, 7.0, "structure lost 3 more for the door")
	eq(_count("breach"), 2, "two breaches reported")


func test_a_breached_wall_unseals_its_room() -> void:
	_duel()
	for i in range(8, 13):  # a ring of walls: x 8..12, y 10..14, with a 3x3 room inside
		_tile(i, 10, "wall")
		_tile(i, 14, "wall")
	for y in range(10, 15):
		_tile(8, y, "wall")
		_tile(12, y, "wall")
	_join()
	var inside := Vector2i(10, 12)
	var res := Rooms.compute(target.grid)
	check(res["rooms"][res["room_of"][inside]]["sealed"], "the walled room is sealed")
	target.refresh()
	check(target.atmosphere.rooms[target.atmosphere.room_of[inside]]["sealed"], "and so is its atmosphere")
	arena.ships[0].flight.pos = Vector2(0.0, -96.0)  # row 12 of the target is the world row y = -96
	_shoot(gun, Vector2(2000.0, -96.0))
	_shoot(gun, Vector2(2000.0, -96.0))
	eq(target.grid.get_tile(Vector2i(8, 12)), "", "the wall in the line of fire is breached")
	res = Rooms.compute(target.grid)
	check(not res["rooms"][res["room_of"][inside]]["sealed"], "the room is open to space")
	check(target.refresh(), "the ship was marked for a refresh")
	check(not target.atmosphere.rooms[target.atmosphere.room_of[inside]]["sealed"], "so its atmosphere vents now")
	check(target.grid.repair(Vector2i(8, 12)), "repair puts the wall back")
	eq(target.grid.get_tile(Vector2i(8, 12)), "wall", "the original material")
	eq(_hp(8, 12), 4.0, "at full hp")
	check(Rooms.compute(target.grid)["rooms"][Rooms.compute(target.grid)["room_of"][inside]]["sealed"], "sealed again")


func test_damage_and_breaches_survive_a_save() -> void:
	_duel()
	_tile(3, 15, "ablative_plating")
	_tile(6, 15, "wall")
	_join()
	_shoot(gun)
	for i in 3:
		_shoot(gun)
	var g: ShipGrid = target.grid
	check(g.breached.has(Vector2i(3, 15)) or g.hp.has(Vector2i(3, 15)), "something happened")
	g.hp[Vector2i(6, 15)] = 1.5
	g.hp_max[Vector2i(6, 15)] = 3.0
	g.breached[Vector2i(7, 7)] = "heavy_armor"
	var d: Dictionary = JSON.parse_string(JSON.stringify(g.to_dict()))
	var h := ShipGrid.new(Vector2i.ZERO, g.defs)
	eq(h.load_dict(d), "", "loads")
	eq(h.hp, g.hp, "hp")
	eq(h.hp_max, g.hp_max, "burnt max hp")
	eq(h.breached, g.breached, "breaches")
	eq(h.hp_of(Vector2i(6, 15)), 1.5, "hp_of")
	eq(h.max_hp_of(Vector2i(6, 15)), 3.0, "max_hp_of")
	var clean := ShipGrid.new(Vector2i(5, 5), g.defs)
	check(not clean.to_dict().has("hp") and not clean.to_dict().has("breached"), "an undamaged grid saves exactly as before")
	var before := g.to_dict()
	for bad in [{"hp": [[1, 2]]}, {"hp": 5}, {"hp_max": [[1, 2, "x"]]}, {"breached": [[1, 2, 3]]}, {"breached": [[1, 2, "teleporter"]]}]:
		var e := d.duplicate()
		e.merge(bad, true)
		check(h.load_dict(e) != "", "bad damage data refused: " + str(bad))
	eq(h.to_dict(), g.to_dict(), "a refused load changes nothing")
	eq(g.to_dict(), before, "and the source is untouched")
	g.force_tile(Vector2i(6, 15), "wall")
	check(not g.hp.has(Vector2i(6, 15)) and not g.hp_max.has(Vector2i(6, 15)), "a rebuilt tile starts fresh")


func test_a_part_at_zero_hp_is_disabled_and_loses_power() -> void:
	_duel()
	var reactor := target.components.place(target.grid, "reactor_mk1", Vector2i(13, 13), 0)
	var laser := target.components.place(target.grid, "laser_mk1", Vector2i(13, 17), 0)
	check(reactor > 0 and laser > 0, "parts placed")
	target.cables.place(target.grid, Vector2i(14, 16))
	target.cables.place(target.grid, Vector2i(14, 17))
	target.components.instances[reactor]["hp"] = 3
	_join()
	eq(arena.weapons.can_fire(arena, 1, laser, arena.ships[1].flight.pos + Vector2(0.0, 1000.0)), "", "its laser works while the reactor does")
	var hull: float = Structure.totals(target).x
	_shoot(gun)  # the line of fire crosses the reactor first
	eq(target.components.instances[reactor]["hp"], 1.0, "3 - 2")
	check(target.components.instances[reactor].get("status", "") != "disabled", "still working")
	_shoot(gun)
	eq(target.components.instances[reactor]["hp"], 0.0, "0 hp")
	eq(target.components.instances[reactor]["status"], "disabled", "disabled, not destroyed")
	check(target.components.instances.has(reactor), "still there")
	_shoot(gun)
	eq(_count("disable"), 1, "reported once")
	eq(Structure.totals(target).x, hull - 3.0, "part damage counts: the reactor lost its 3 hp, nothing else")
	eq(arena.weapons.can_fire(arena, 1, laser, arena.ships[1].flight.pos + Vector2(0.0, 1000.0)), "unpowered", "no power, no laser")


func test_a_part_hit_uses_its_definition_hp_when_the_instance_has_none() -> void:
	_duel()
	var reactor := target.components.place(target.grid, "reactor_mk1", Vector2i(13, 13), 0)
	_join()
	_shoot(gun)
	var hp: float = target.components.instances[reactor]["hp"]
	var full: float = float(target.components.def("reactor_mk1").get("hp", 4.0))
	near(hp, full - 2.0, "starts from the definition's hp (or the default 4)")


func test_a_laser_through_a_pierced_part_counts_it_once() -> void:
	_duel()
	var reactor := target.components.place(target.grid, "reactor_mk1", Vector2i(13, 13), 0)
	target.components.instances[reactor]["hp"] = 1
	_tile(20, 15, "wall")
	_join()
	var spear := _def("spear", {"damage": 5, "pierce": 3})
	_shoot(spear)
	eq(target.components.instances[reactor]["status"], "disabled", "the reactor is out")
	eq(_count("hit"), 2, "one hit on the reactor (4 cells deep), one on the wall")
	near(_hp(20, 15), 4.0 - 4.0, "5 damage, 1 spent on the reactor, 4 left for the wall")
