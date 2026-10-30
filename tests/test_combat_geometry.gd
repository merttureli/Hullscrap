extends "res://tests/base_test.gd"
## Shots against the real geometry of shaped cells: a ray that only crosses the empty half passes, the
## incidence angle and face normal, sloped armour, the ricochet and deflect curves, reflected
## directions, bounces (half damage; lasers once, projectiles twice; the shooter's own ship included)
## and the events. Shots are traced directly between ship-local points of the target (ship 1, at
## x = 1500, not turned), so the geometry is exact.

const Arena = preload("res://scripts/combat/arena.gd")
const Damage = preload("res://scripts/combat/damage.gd")
const Projectiles = preload("res://scripts/combat/projectiles.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")

var arena: Arena
var target: Ship


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## A 31x31 ship (hull cells 0..30, centre at 15.5, 15.5) with floor everywhere; walls are tough (hp 1000).
func _ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	defs.by_id["wall"]["hp"] = 1000
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	for c in g.hull:
		g.force_tile(c, "floor")
	return Ship.new("t", g)


## Ship 0 (the shooter, at the origin) and ship 1 (`target`, at x 1500). The cells set in `tiles`
## (cell -> tile id or [tile id, shape dict]) are built on the target before it joins.
func _duel(tiles := {}, seed_value := 1) -> void:
	arena = Arena.new(seed_value)
	arena.add_ship(_ship())
	target = _ship()
	for c in tiles:
		var t = tiles[c]
		if t is Array:
			target.grid.force_tile(c, t[0], t[1])
		else:
			target.grid.force_tile(c, t)
	arena.add_ship(target, Vector2(1500.0, 0.0))


func _w(type: String, dmg := 1.0, kind := "bolt") -> Dictionary:
	return {"kind": kind, "damage_type": type, "damage": dmg, "pierce": 0, "speed": 700.0, "range": 4000.0, "arc": 360, "cooldown": 0.0}


## Trace weapon `w` between two points of the target's grid (cell coordinates). Returns the out dict.
func _trace(w: Dictionary, a: Vector2, b: Vector2, ctx := {}) -> Dictionary:
	var out := {}
	out["spent"] = Projectiles.trace(arena, 0, w, arena.local_to_world(1, a), arena.local_to_world(1, b), out, ctx)
	return out


func _events(type: String, ship := -1) -> Array:
	return arena.events.filter(func(e): return e["type"] == type and (ship < 0 or e["ship"] == ship))


## A shot at the west face of the wall column at x = 10, `deg` degrees off its normal, ending 1 cell inside.
func _at_wall(w: Dictionary, deg: float) -> Dictionary:
	var d := Vector2.from_angle(deg_to_rad(deg))
	var face := Vector2(10.0, 15.5)
	return _trace(w, face - d * 3.0, face + d)


func _wall_column() -> Dictionary:
	var t := {}
	for y in range(5, 26):
		t[Vector2i(10, y)] = "wall"
	return t


# --- passing and hitting the polygon ----------------------------------------------------------------

func test_a_ray_crossing_only_the_empty_half_of_a_tri_passes() -> void:
	# tri at (10,15), solid below the diagonal; the ray runs along x - y = -4.5, through the empty top-right half only.
	_duel({Vector2i(10, 15): ["wall", {"shape": "tri"}], Vector2i(11, 16): "wall"})
	var out := _trace(_w("energy", 1.0, "laser"), Vector2(9.0, 13.5), Vector2(13.0, 17.5))
	check(out["spent"], "the laser is stopped")
	var hits := _events("hit", 1)
	eq(hits.size(), 1, "one hit")
	eq(hits[0]["cell"], Vector2i(11, 16), "on the wall behind: it went through the empty half of the tri")
	_duel({Vector2i(10, 15): "wall", Vector2i(11, 16): "wall"})
	_trace(_w("energy", 1.0, "laser"), Vector2(9.0, 13.5), Vector2(13.0, 17.5))
	eq(_events("hit", 1)[0]["cell"], Vector2i(10, 15), "the same ray meets a whole square at the cell")
	_duel({Vector2i(10, 15): ["wall", {"shape": "tri"}]})
	check(not _trace(_w("energy", 1.0, "laser"), Vector2(9.0, 13.5), Vector2(13.0, 17.5))["spent"], "and with nothing behind it, the ray passes clean")


func test_the_solid_half_is_hit_at_the_polygon_not_the_square() -> void:
	# tri rot 3: solid where x + y >= 1 (local); a horizontal ray at local y 0.75 enters the empty part first and meets the diagonal at x = 0.25.
	_duel({Vector2i(10, 15): ["wall", {"shape": "tri", "rot": 3}]})
	var out := _trace(_w("energy", 1.0, "laser"), Vector2(8.0, 15.75), Vector2(13.0, 15.75))
	check(out["spent"], "hit")
	var hit: Dictionary = _events("hit", 1)[0]
	near(arena.world_to_local(1, out["end"]).x, 10.25, "at the diagonal, a quarter of the way into the cell")
	near(hit["n"].x, -sqrt(0.5), "the face normal is the diagonal's (up and back)", 1e-4)
	near(hit["n"].y, -sqrt(0.5), "", 1e-4)


func test_a_ramp_is_met_where_the_slope_is() -> void:
	# slope2 at (10,15) and (11,15): low cell first, rising to the right. y = 1 - x/2 across the two cells.
	_duel({Vector2i(10, 15): ["wall", {"shape": "tri2_low"}], Vector2i(11, 15): ["wall", {"shape": "tri2_high"}]})
	_trace(_w("explosive", 1.0), Vector2(8.0, 15.8), Vector2(13.0, 15.8))
	var hits := _events("hit", 1)
	eq(hits[0]["cell"], Vector2i(10, 15), "low on the ramp the first cell is hit (at x = 0.4)")
	_duel({Vector2i(10, 15): ["wall", {"shape": "tri2_low"}], Vector2i(11, 15): ["wall", {"shape": "tri2_high"}]})
	_trace(_w("explosive", 1.0), Vector2(8.0, 15.3), Vector2(13.0, 15.3))
	hits = _events("hit", 1)
	eq(hits[0]["cell"], Vector2i(11, 15), "higher up it flies over the low cell and meets the second")
	near(hits[0]["n"].dot(Vector2(-1, -2).normalized()), 1.0, "the ramp's normal is up and back", 1e-4)


func test_a_skipped_cell_is_not_hit() -> void:
	_duel({Vector2i(10, 15): "wall"})
	var out := _trace(_w("energy", 1.0, "laser"), Vector2(8.0, 15.5), Vector2(12.0, 15.5), {"skip": {"ship": 1, "cell": Vector2i(10, 15)}})
	check(not out["spent"], "a shot told to skip the cell flies through it")
	out = _trace(_w("energy", 1.0, "laser"), Vector2(8.0, 15.5), Vector2(12.0, 15.5))
	check(out["spent"], "and meets it otherwise")


# --- sloped armour ----------------------------------------------------------------------------------

func test_sloped_armour_cuts_kinetic_and_explosive_damage_by_the_angle() -> void:
	for type in ["explosive", "kinetic"]:
		var want := {0.0: 1.0, 45.0: cos(deg_to_rad(45.0)), 70.0: 0.5}  # cos 70 = 0.342 is clamped to 0.5
		for deg in want:
			var seen := 0.0
			for seed_value in range(1, 25):  # a kinetic shot at a shallow angle may glance off: use the first that hits
				_duel(_wall_column(), seed_value)
				_at_wall(_w(type, 1.0), deg)
				var hits := _events("hit", 1)
				if not hits.is_empty():
					seen = hits[0]["dealt"]
					break
			near(seen, want[deg], "%s at %d degrees does %.3f of its damage" % [type, int(deg), want[deg]])
	_duel(_wall_column())
	_at_wall(_w("energy", 1.0, "laser"), 70.0)
	near(_events("hit", 1)[0]["dealt"], 1.0, "energy is not cut by the angle")
	check(Damage.slope_factor("kinetic", 0.9) == 0.9 and Damage.slope_factor("explosive", 0.2) == 0.5 and Damage.slope_factor("ion", 0.2) == 1.0, "the rule itself")


func test_a_slope_cuts_a_head_on_shot_by_the_slopes_own_angle() -> void:
	# tri rot 3 again: a horizontal shot meets the 45 degree diagonal, so explosive damage is cos 45.
	_duel({Vector2i(10, 15): ["wall", {"shape": "tri", "rot": 3}]})
	_trace(_w("explosive", 1.0), Vector2(8.0, 15.75), Vector2(13.0, 15.75))
	near(_events("hit", 1)[0]["dealt"], sqrt(0.5), "head on, a 45 degree slope takes 0.707 of it")
	# slope2 is steeper to the shot: its normal is 63.4 degrees off a horizontal path, cos = 0.447, held at 0.5.
	_duel({Vector2i(10, 15): ["wall", {"shape": "tri2_low"}], Vector2i(11, 15): ["wall", {"shape": "tri2_high"}]})
	_trace(_w("explosive", 1.0), Vector2(8.0, 15.8), Vector2(13.0, 15.8))
	near(_events("hit", 1)[0]["dealt"], 0.5, "slope2 takes half")


# --- ricochet and deflect ---------------------------------------------------------------------------

func test_the_ricochet_curve() -> void:
	near(Damage.ricochet_chance(0.0), 0.0, "straight on")
	near(Damage.ricochet_chance(40.0), 0.0, "40 degrees")
	near(Damage.ricochet_chance(57.5), 0.4, "halfway up the ramp is 0.4")
	near(Damage.ricochet_chance(75.0), 0.8, "75 degrees")
	near(Damage.ricochet_chance(89.0), 0.8, "and beyond")
	for deg in [30.0, 50.0, 65.0, 80.0]:
		_duel(_wall_column(), 11)
		var n := 400
		for i in n:
			_at_wall(_w("kinetic", 0.001), deg)
		var want := Damage.ricochet_chance(deg) * n
		var got := _events("ricochet", 1).size()
		var sigma := sqrt(maxf(want * (1.0 - want / n), 1.0))
		check(absf(got - want) <= 4.5 * sigma, "%d degrees: about %d of %d glance off, got %d" % [int(deg), int(want), n, got])
		eq(got + _events("hit", 1).size(), n, "every shot glanced off or hit")


func test_reflective_deflect_grows_with_the_angle() -> void:
	var counts := {}
	for deg in [0.0, 80.0]:
		_duel({Vector2i(10, 15): "reflective_coating"}, 4)
		for i in 500:
			var d := Vector2.from_angle(deg_to_rad(deg))
			_trace(_w("energy", 0.001, "laser"), Vector2(10.0, 15.5) - d * 3.0, Vector2(10.0, 15.5) + d)
		counts[deg] = _events("deflect", 1).size()
	check(absf(counts[0.0] - 200.0) <= 50.0, "0.4 straight on, about 200 of 500: %d" % counts[0.0])
	var want := 500.0 * 0.4 * (1.0 + 0.5 * sin(deg_to_rad(80.0)))
	check(absf(counts[80.0] - want) <= 55.0, "x (1 + 0.5 sin 80) at 80 degrees, about %d: %d" % [int(want), counts[80.0]])
	check(counts[80.0] > counts[0.0] + 50, "so it deflects clearly more")


func test_a_ricochet_reflects_the_shot_at_half_damage_and_says_where() -> void:
	var found := false
	for seed_value in range(1, 40):
		_duel(_wall_column(), seed_value)
		# a bolt coming in at 80 degrees from the normal, 3 cells off the face
		var d := Vector2.from_angle(deg_to_rad(80.0))
		Projectiles.spawn(arena, 0, _w("kinetic", 2.0), arena.local_to_world(1, Vector2(10.0, 15.5) - d * 3.0), d)
		arena.step(0.2)
		if _events("ricochet", 1).is_empty():
			continue
		found = true
		var e: Dictionary = _events("ricochet", 1)[0]
		near(e["pos"].x, 1500.0 + (10.0 - 15.5) * 32.0, "the event is at the face of the wall", 0.01)
		near(e["dir"].dot(d), 1.0, "it records the way the shot flew", 1e-4)
		near(e["new_dir"].x, -d.x, "and leaves mirrored about the face: x reversed", 1e-4)
		near(e["new_dir"].y, d.y, "y kept", 1e-4)
		eq(arena.projectiles.size(), 1, "the shot lives on")
		var p: Dictionary = arena.projectiles[0]
		eq(p["bounces"], 1, "one bounce")
		near(p["w"]["damage"], 1.0, "at half the damage")
		near(p["vel"].normalized().dot(e["new_dir"]), 1.0, "flying the new way", 1e-4)
		near(p["vel"].length(), 700.0, "at the same speed", 1e-3)
		eq(p["skip"], {}, "(the skipped cell lasts one step)")
		break
	check(found, "some seed glances the bolt off")


func test_a_deflect_off_a_slope_goes_off_at_the_slopes_angle() -> void:
	_duel({Vector2i(10, 15): ["reflective_coating", {"shape": "tri", "rot": 3}]})
	target.grid.defs.by_id["reflective_coating"]["deflect"] = {"energy": 1.0}
	arena.ships[1].dirty = true
	_trace(_w("energy", 1.0, "laser"), Vector2(8.0, 15.75), Vector2(13.0, 15.75))
	var e: Dictionary = _events("deflect", 1)[0]
	near(e["new_dir"].x, 0.0, "a level beam off a 45 degree slope goes straight up: no x", 1e-4)
	near(e["new_dir"].y, -1.0, "north", 1e-4)
	near(arena.world_to_local(1, e["pos"]).x, 10.25, "from the diagonal", 1e-3)


# --- bounces ----------------------------------------------------------------------------------------

## Ship 1's west face (x = 3 cells) and ship 0's east face (x = 28) both reflect energy straight back.
func _mirrors() -> void:
	arena = Arena.new(2)
	var shooter := _ship()
	shooter.grid.force_tile(Vector2i(28, 15), "reflective_coating")
	shooter.grid.defs.by_id["reflective_coating"]["deflect"] = {"energy": 1.0}
	arena.add_ship(shooter)
	target = _ship()
	target.grid.force_tile(Vector2i(3, 15), "reflective_coating")
	target.grid.defs.by_id["reflective_coating"]["deflect"] = {"energy": 1.0}
	arena.add_ship(target, Vector2(1500.0, 0.0))


func test_a_laser_bounces_once_and_can_hit_its_own_ship() -> void:
	_mirrors()
	var uid := arena.add_mount(0, "laser_mk1", Vector2(20.5, 15.5))
	arena.weapons.defs["laser_mk1"]["range"] = 4000
	check(arena.fire(0, uid, Vector2(3000.0, 0.0)), "fires")
	eq(_events("deflect", 1).size(), 1, "reflected off the target's face")
	eq(_events("deflect", 0).size(), 1, "and met the shooter's own plate: its roll is made")
	var beams := _events("beam")
	eq(beams.size(), 2, "the beam has two parts, not three: lasers bounce once")
	check(not beams[0]["bounce"] and beams[1]["bounce"], "the second is the bounced part")
	near(beams[1]["from"].y, 0.0, "back along the line it came", 0.01)
	check(beams[1]["to"].x < 500.0, "to the shooter's own ship (x %f)" % beams[1]["to"].x)
	eq(arena.projectiles.size(), 0, "nothing in flight")


func test_a_laser_that_bounces_into_its_own_wall_hurts_it_for_half() -> void:
	arena = Arena.new(2)
	var shooter := _ship()
	shooter.grid.force_tile(Vector2i(28, 15), "scrap_plate")  # hp 3
	arena.add_ship(shooter)
	target = _ship()
	target.grid.force_tile(Vector2i(3, 15), "reflective_coating")
	target.grid.defs.by_id["reflective_coating"]["deflect"] = {"energy": 1.0}
	arena.add_ship(target, Vector2(1500.0, 0.0))
	var uid := arena.add_mount(0, "laser_mk1", Vector2(20.5, 15.5))
	arena.weapons.defs["laser_mk1"]["range"] = 4000
	check(arena.fire(0, uid, Vector2(3000.0, 0.0)), "fires")
	var hits := _events("hit", 0)
	eq(hits.size(), 1, "the bounced beam hits the shooter")
	eq(hits[0]["cell"], Vector2i(28, 15), "on its east plate")
	near(hits[0]["dealt"], 1.0, "for half the laser's 2 damage")
	near(shooter.grid.hp_of(Vector2i(28, 15)), 2.0, "scrap plate 3 - 1")
	eq(_events("hit", 1).size(), 0, "and the target's mirror took nothing")


func test_a_projectile_bounces_twice_then_dies() -> void:
	_mirrors()
	Projectiles.spawn(arena, 0, _w("energy", 1.0), arena.local_to_world(0, Vector2(22.5, 15.5)), Vector2.RIGHT)
	arena.step(6.0)
	eq(_events("deflect", 1).size() + _events("deflect", 0).size(), 3, "off the target, off the shooter, off the target: three rolls")
	eq(_events("deflect", 1).size(), 2, "twice on the target")
	eq(_events("deflect", 0).size(), 1, "once on its own ship")
	eq(arena.projectiles.size(), 0, "and the third one ended it")


func test_a_projectile_that_comes_back_hits_its_own_ship_for_half() -> void:
	arena = Arena.new(2)
	var shooter := _ship()
	shooter.grid.force_tile(Vector2i(28, 15), "scrap_plate")
	arena.add_ship(shooter)
	target = _ship()
	target.grid.force_tile(Vector2i(3, 15), "reflective_coating")
	target.grid.defs.by_id["reflective_coating"]["deflect"] = {"energy": 1.0}
	arena.add_ship(target, Vector2(1500.0, 0.0))
	Projectiles.spawn(arena, 0, _w("energy", 2.0), arena.local_to_world(0, Vector2(22.5, 15.5)), Vector2.RIGHT)
	arena.step(6.0)
	var hits := _events("hit", 0)
	eq(hits.size(), 1, "it came back and hit")
	near(hits[0]["dealt"], 1.0, "at half damage")
	eq(arena.projectiles.size(), 0, "and is spent")


func test_a_bounced_shot_is_aimed_by_the_slope_it_left() -> void:
	# A kinetic bolt off a 45 degree slope at p > 0 leaves along the reflection; check by many tries that one does.
	var found := false
	for seed_value in range(1, 60):
		_duel({Vector2i(10, 15): ["wall", {"shape": "tri", "rot": 3}]}, seed_value)
		Projectiles.spawn(arena, 0, _w("kinetic", 2.0), arena.local_to_world(1, Vector2(6.0, 15.75)), Vector2.RIGHT)
		arena.step(0.5)
		var rico := _events("ricochet", 1)
		if rico.is_empty():
			continue
		found = true
		near(rico[0]["new_dir"].y, -1.0, "straight up off a 45 degree slope", 1e-4)
		check(arena.projectiles.size() == 1 and arena.projectiles[0]["vel"].y < 0.0, "and flying that way")
		break
	check(found, "a 45 degree face glances a bolt off for some seed (p = 0.11)")
