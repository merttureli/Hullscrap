extends "res://tests/base_test.gd"

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Components = preload("res://scripts/ship/components.gd")
const Cables = preload("res://scripts/ship/cables.gd")
const Power = preload("res://scripts/sim/power.gd")
const Flight = preload("res://scripts/sim/flight.gd")

var grid: ShipGrid
var comps: Components
var cables: Cables


## A 15x15 circular hull with no tiles, no components and no cables.
func _setup() -> void:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	grid = ShipGrid.new(Vector2i(15, 15), defs)
	grid.fill_circle_hull(7.0)
	comps = Components.new()
	comps.load_defs("res://data/components.json")
	cables = Cables.new()


## Floor on the w x h rectangle at x0, y0.
func _floor(x0: int, y0: int, w: int, h: int) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			check(grid.place("floor", Vector2i(x, y)), "floor at %d,%d" % [x, y])


func _put(id: String, x: int, y: int) -> int:
	var uid := comps.place(grid, id, Vector2i(x, y), 0)
	check(uid > 0, "%s placed at %d,%d" % [id, x, y])
	return uid


func near(got: float, want: float, msg: String, eps := 1e-6) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func test_config_matches_the_data_file() -> void:
	var f := Flight.new()
	eq(f.tile_mass, {"floor": 1.0, "wall": 2.0, "door": 2.0}, "tile masses")
	eq(f.component_mass, {"reactor_mk1": 14.0, "reactor_mk2": 16.0}, "component masses")
	eq([f.component_mass_per_cell, f.cable_mass_per_cell], [3.0, 0.1], "per-cell masses")
	eq([f.linear_damping, f.angular_damping], [0.25, 1.5], "damping")
	eq([f.thrust_to_accel, f.turn_factor, f.max_speed], [40.0, 0.6, 600.0], "thrust_to_accel, turn_factor, max_speed")
	var d := Flight.new("")
	eq(d.max_speed, 600.0, "no file keeps the defaults")
	check(not d.load_config("res://data/nope.json"), "a missing file is refused")


func test_empty_ship_has_mass_one() -> void:
	_setup()
	near(Flight.new().mass_of(grid, comps, cables), 1.0, "empty ship")


func test_mass_counts_tiles() -> void:
	_setup()
	var f := Flight.new()
	_floor(5, 5, 3, 1)
	grid.force_tile(Vector2i(5, 4), "wall")
	grid.force_tile(Vector2i(6, 4), "wall")
	grid.force_tile(Vector2i(7, 4), "door")
	near(f.mass_of(grid, comps, cables), 3.0 + 4.0 + 2.0, "3 floors, 2 walls, 1 door")
	grid.force_tile(Vector2i(8, 4), "mystery")
	near(f.mass_of(grid, comps, cables), 10.0, "an unknown tile adds 1.0")


func test_mass_counts_components() -> void:
	_setup()
	var f := Flight.new()
	_floor(4, 6, 8, 2)  # 16 floors
	_put("reactor_mk1", 4, 6)
	near(f.mass_of(grid, comps, cables), 16.0 + 14.0, "a listed component uses its own mass")
	_put("reactor_mk2", 6, 6)
	near(f.mass_of(grid, comps, cables), 16.0 + 14.0 + 16.0, "the second listed component")
	_put("engine_mk1", 8, 6)  # 2x1 = 2 cells
	near(f.mass_of(grid, comps, cables), 16.0 + 14.0 + 16.0 + 6.0, "an unlisted 2x1 weighs 3 per cell")
	_put("helm", 10, 6)
	near(f.mass_of(grid, comps, cables), 16.0 + 14.0 + 16.0 + 6.0 + 3.0, "an unlisted 1x1")
	comps.remove_at(Vector2i(4, 6))
	near(f.mass_of(grid, comps, cables), 16.0 + 16.0 + 6.0 + 3.0, "removing a component lightens the ship")


func test_mass_counts_cables() -> void:
	_setup()
	var f := Flight.new()
	_floor(4, 6, 10, 1)
	for x in range(4, 14):
		check(cables.place(grid, Vector2i(x, 6)), "cable at %d" % x)
	near(f.mass_of(grid, comps, cables), 10.0 + 10 * 0.1, "10 floors and 10 cables")
	f.cable_mass_per_cell = 0.5
	near(f.mass_of(grid, comps, cables), 15.0, "cable mass comes from the config")


## A reactor, a helm and three engines (mk1, mk2, mk1 off the cable); returns the uids by name.
func _engine_ship() -> Dictionary:
	_setup()
	_floor(2, 5, 9, 3)
	var s := {}
	s["reactor"] = _put("reactor_mk1", 2, 5)
	s["helm"] = _put("helm", 4, 5)
	s["e1"] = _put("engine_mk1", 5, 5)
	s["e2"] = _put("engine_mk2", 7, 5)
	s["off"] = _put("engine_mk1", 5, 7)
	for x in range(3, 9):
		check(cables.place(grid, Vector2i(x, 5)), "cable at %d" % x)
	return s


func test_thrust_counts_only_powered_engines() -> void:
	var s := _engine_ship()
	var f := Flight.new()
	var powered: Dictionary = Power.solve(comps, cables)["powered"]
	check(not powered[s["off"]], "the third engine has no cable")
	near(f.thrust_of(comps, powered), 28.0, "mk1 10 + mk2 18")
	near(f.thrust_of(comps, {s["e1"]: true}), 10.0, "one powered engine")
	near(f.thrust_of(comps, {}), 0.0, "nothing powered")
	near(f.thrust_of(comps, {s["reactor"]: true, s["helm"]: true}), 0.0, "powered non-engines add nothing")
	near(f.thrust_of(comps, {s["e1"]: false, s["e2"]: true}), 18.0, "false means unpowered")


func test_boost_multiplies_thrust() -> void:
	var s := _engine_ship()
	var f := Flight.new()
	var powered: Dictionary = Power.solve(comps, cables)["powered"]
	near(f.thrust_of(comps, powered, {s["e1"]: 1.4}), 14.0 + 18.0, "boost one engine")
	near(f.thrust_of(comps, powered, {s["e1"]: 1.4, s["e2"]: 2.0}), 14.0 + 36.0, "boost both")
	near(f.thrust_of(comps, powered, {s["off"]: 3.0}), 28.0, "boosting an unpowered engine does nothing")
	near(f.thrust_of(comps, powered, {s["helm"]: 5.0}), 28.0, "boosting a non-engine does nothing")
	near(f.thrust_of(comps, powered, {s["e1"]: -1.0}), 18.0, "a negative boost counts as zero")


func test_throttle_accelerates_up() -> void:
	var f := Flight.new()
	f.step(0.1, {"throttle": 1.0}, 100.0, 20.0)  # accel = 20 * 40 / 100 = 8 px/s^2
	near(f.vel.y, -0.8 * exp(-f.linear_damping * 0.1), "velocity points up", 1e-5)
	near(f.vel.x, 0.0, "and not sideways")
	check(f.pos.y < 0.0, "moved up the screen")
	near(f.pos.y, f.vel.y * 0.1, "position integrates the new velocity", 1e-5)
	near(f.angle, 0.0, "heading unchanged")
	f.step(0.1, {"throttle": 1.0}, 100.0, 20.0)
	check(f.vel.y < -1.4, "keeps speeding up")


func test_acceleration_follows_the_heading() -> void:
	var f := Flight.new()
	f.angle = PI / 2.0
	f.step(0.1, {"throttle": 1.0}, 100.0, 20.0)
	check(f.vel.x > 0.7, "a quarter turn clockwise points right")
	near(f.vel.y, 0.0, "no vertical push", 1e-5)


func test_reverse_is_half() -> void:
	var fwd := Flight.new()
	var back := Flight.new()
	fwd.step(0.1, {"throttle": 1.0}, 100.0, 20.0)
	back.step(0.1, {"throttle": -1.0}, 100.0, 20.0)
	check(back.vel.y > 0.0, "reverse pushes down the screen")
	near(back.vel.y, -fwd.vel.y / 2.0, "half the forward speed")
	var half := Flight.new()
	half.step(0.1, {"throttle": 0.5}, 100.0, 20.0)
	near(half.vel.y, fwd.vel.y / 2.0, "half throttle is half speed")
	var over := Flight.new()
	over.step(0.1, {"throttle": 7.0}, 100.0, 20.0)
	near(over.vel.y, fwd.vel.y, "throttle is clamped to 1")


func test_damping_slows_a_coasting_ship() -> void:
	var f := Flight.new()
	f.vel = Vector2(30.0, -100.0)
	var last := f.vel.length()
	for i in 400:  # 20 s at 0.05
		f.step(0.05, {"throttle": 0.0}, 100.0, 20.0)
		check(f.vel.length() < last, "slower every step")
		last = f.vel.length()
	check(f.vel.length() < 1.0, "near zero after 20 s, got %s" % str(f.vel.length()))
	var g := Flight.new()
	g.vel = Vector2(0.0, -100.0)
	g.step(1.0, {}, 100.0, 20.0)
	near(g.vel.y, -100.0 * exp(-0.25), "one second decays by exp(-damping)", 1e-4)


func test_damping_does_not_depend_on_the_step_size() -> void:
	var a := Flight.new()
	var b := Flight.new()
	a.vel = Vector2(0.0, -100.0)
	b.vel = Vector2(0.0, -100.0)
	a.step(2.0, {}, 100.0, 0.0)
	for i in 20:
		b.step(0.1, {}, 100.0, 0.0)
	near(a.vel.y, b.vel.y, "one 2 s step equals twenty 0.1 s steps", 1e-4)


func test_speed_is_clamped() -> void:
	var f := Flight.new()
	f.vel = Vector2(0.0, -5000.0)
	f.step(0.1, {}, 100.0, 20.0)
	near(f.vel.length(), 600.0, "a huge speed is cut to max_speed", 1e-3)
	var g := Flight.new()
	for i in 200:
		g.step(0.1, {"throttle": 1.0}, 1.0, 1000000.0)
		check(g.vel.length() <= 600.0 + 1e-3, "never above max_speed")
	near(g.vel.length(), 600.0, "and it reaches it", 1e-3)
	g.step(0.1, {"throttle": -1.0}, 1.0, 1000000.0)
	near(g.vel.length(), 600.0, "reverse is clamped too", 1e-3)


func test_a_heavier_ship_accelerates_slower() -> void:
	var light := Flight.new()
	var heavy := Flight.new()
	light.step(0.1, {"throttle": 1.0, "turn": 1.0}, 50.0, 20.0)
	heavy.step(0.1, {"throttle": 1.0, "turn": 1.0}, 100.0, 20.0)
	near(heavy.vel.length() * 2.0, light.vel.length(), "twice the mass, half the acceleration")
	near(heavy.ang_vel * 2.0, light.ang_vel, "and half the angular acceleration")
	var strong := Flight.new()
	strong.step(0.1, {"throttle": 1.0}, 100.0, 40.0)
	near(strong.vel.length(), light.vel.length(), "twice the thrust cancels twice the mass")


func test_no_thrust_means_no_push() -> void:
	var f := Flight.new()
	f.step(0.1, {"throttle": 1.0, "turn": 1.0}, 100.0, 0.0)
	eq(f.vel, Vector2.ZERO, "no thrust, no speed")
	eq(f.ang_vel, 0.0, "and no turning")
	eq(f.pos, Vector2.ZERO, "so it stays put")


func test_turning_changes_the_angle_and_damping_stops_the_spin() -> void:
	var f := Flight.new()
	for i in 10:
		f.step(0.1, {"turn": 1.0}, 50.0, 20.0)  # 0.6 * 20 / 50 = 0.24 rad/s^2
	check(f.angle > 0.0, "positive turn is clockwise")
	check(f.ang_vel > 0.0, "and it spins")
	near(f.vel.length(), 0.0, "turning alone does not move the ship")
	var spun := f.angle
	for i in 400:
		f.step(0.05, {}, 50.0, 20.0)
	near(f.ang_vel, 0.0, "damping stops the spin after 20 s", 1e-9)
	check(f.angle > spun, "it drifted on a little while stopping")
	near(f.angle, spun + 0.0, "but not far", 0.5)
	var g := Flight.new()
	g.step(0.5, {"turn": -1.0}, 50.0, 20.0)
	check(g.angle < 0.0 and g.ang_vel < 0.0, "negative turn is counter-clockwise")


func test_the_angle_stays_in_range() -> void:
	var f := Flight.new()
	f.angle = PI - 0.01
	f.ang_vel = 1.0
	f.step(0.1, {}, 50.0, 0.0)
	check(f.angle < 0.0 and f.angle >= -PI, "wrapped past PI to the negative side, got %s" % str(f.angle))
	f.angle = -PI + 0.01
	f.ang_vel = -1.0
	f.step(0.1, {}, 50.0, 0.0)
	check(f.angle > 0.0 and f.angle <= PI, "wrapped the other way, got %s" % str(f.angle))


func test_a_non_positive_dt_changes_nothing() -> void:
	var f := Flight.new()
	f.vel = Vector2(1.0, 2.0)
	var before := f.to_dict()
	f.step(0.0, {"throttle": 1.0, "turn": 1.0}, 50.0, 20.0)
	f.step(-1.0, {"throttle": 1.0, "turn": 1.0}, 50.0, 20.0)
	eq(f.to_dict(), before, "no state change")


## A fixed mixed input sequence of 300 steps.
func _drive(f: Flight, from: int, to: int) -> void:
	for i in range(from, to):
		var input := {"throttle": sin(i * 0.1), "turn": cos(i * 0.07)}
		f.step(1.0 / 60.0, input, 80.0, 28.0)


func test_same_inputs_give_the_same_state() -> void:
	var a := Flight.new()
	var b := Flight.new()
	_drive(a, 0, 300)
	_drive(b, 0, 300)
	eq(a.to_dict(), b.to_dict(), "identical state")
	check(a.pos.length() > 1.0 and absf(a.angle) > 1e-3, "and it really moved")
	var c := Flight.new()
	_drive(c, 0, 150)
	var saved := c.to_dict()
	var d := Flight.new()
	eq(d.load_dict(saved), "", "resumes from a save")
	_drive(d, 150, 300)
	eq(d.to_dict(), a.to_dict(), "a save and resume changes nothing")


func test_save_and_load() -> void:
	var f := Flight.new()
	_drive(f, 0, 100)
	var g := Flight.new()
	eq(g.load_dict(f.to_dict()), "", "loads")
	eq(g.to_dict(), f.to_dict(), "same state")
	var h := Flight.new()
	eq(h.load_dict(JSON.parse_string(JSON.stringify(f.to_dict()))), "", "loads from JSON text")
	near(h.pos.x, f.pos.x, "pos.x through JSON", 1e-3)
	near(h.pos.y, f.pos.y, "pos.y through JSON", 1e-3)
	near(h.vel.x, f.vel.x, "vel.x through JSON", 1e-3)
	near(h.angle, f.angle, "angle through JSON", 1e-9)
	near(h.ang_vel, f.ang_vel, "ang_vel through JSON", 1e-9)
	var before := g.to_dict()
	check(g.load_dict({"version": 99}) != "", "wrong version refused")
	check(g.load_dict({"version": 1, "pos": [1.0], "vel": [0.0, 0.0], "angle": 0.0, "ang_vel": 0.0}) != "", "short pos refused")
	check(g.load_dict({"version": 1, "pos": [1.0, 2.0], "vel": [0.0, 0.0], "angle": "x", "ang_vel": 0.0}) != "", "text angle refused")
	eq(g.to_dict(), before, "a refused load changes nothing")


func test_can_fly_reasons() -> void:
	var s := _engine_ship()
	var f := Flight.new()
	var powered: Dictionary = Power.solve(comps, cables)["powered"]
	eq(f.can_fly(comps, powered), "", "helm and engine powered")
	eq(f.can_fly(comps, {}), "no powered helm", "nothing powered")
	eq(f.can_fly(comps, {s["e1"]: true, s["e2"]: true}), "no powered helm", "engines but no helm")
	eq(f.can_fly(comps, {s["helm"]: true}), "no powered engine", "a helm but no engine")
	eq(f.can_fly(comps, {s["helm"]: true, s["off"]: false}), "no powered engine", "an unpowered engine does not count")
	eq(f.can_fly(comps, {s["helm"]: true, s["reactor"]: true}), "no powered engine", "a reactor is not an engine")
	eq(f.can_fly(comps, {s["helm"]: true, s["off"]: true}), "", "any one powered engine is enough")
	var bare := Components.new()
	bare.load_defs("res://data/components.json")
	eq(f.can_fly(bare, {}), "no powered helm", "an empty ship")
	var cut := Cables.new()
	eq(f.can_fly(comps, Power.solve(comps, cut)["powered"]), "no powered helm", "no cables, no power")
