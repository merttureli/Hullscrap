extends "res://tests/base_test.gd"

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Atmosphere = preload("res://scripts/sim/atmosphere.gd")
const Rooms = preload("res://scripts/sim/rooms.gd")

const DOOR := Vector2i(4, 3)


## A 12x10 grid that is hull everywhere, so cells outside the buildings are empty hull (space).
func _grid() -> ShipGrid:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(12, 10), defs)
	for y in 10:
		for x in 12:
			g.hull[Vector2i(x, y)] = true
	return g


## A wall ring around `r` with floor inside.
func _box(g: ShipGrid, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			g.place("wall" if edge else "floor", Vector2i(x, y))


## A wall across column `x` of a box whose interior rows are 2..4, with a 2-cell door piece at (x, 3) and (x, 4).
func _divide(g: ShipGrid, x: int) -> void:
	for y in range(2, 5):
		g.place("wall", Vector2i(x, y))
	check(g.place("door", Vector2i(x, 3)), "door at x=%d" % x)


## One sealed 3x3 room (cells 2..4 x 2..4), room 0.
func _single() -> ShipGrid:
	var g := _grid()
	_box(g, Rect2i(1, 1, 5, 5))
	return g


## Two sealed rooms joined by a door at DOOR: room 0 has 6 cells, room 1 has 9.
func _pair() -> ShipGrid:
	var g := _grid()
	_box(g, Rect2i(1, 1, 8, 5))
	_divide(g, 4)
	return g


## Three rooms of 6 cells in a row, doors at (4,3) and (7,3).
func _row() -> ShipGrid:
	var g := _grid()
	_box(g, Rect2i(1, 1, 10, 5))
	_divide(g, 4)
	_divide(g, 7)
	return g


## An atmosphere with the documented default rates, ignoring the tuning file.
func _atm() -> Atmosphere:
	return Atmosphere.new("")


func _near(got: float, want: float, eps: float, msg: String) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func test_config_file_loads() -> void:
	var a := Atmosphere.new()
	check(a.vent_rate > 0.0 and a.door_rate > 0.0, "rates come from data/atmosphere.json")
	check(not a.load_config("res://data/no_such_file.json"), "missing file is refused")
	check(a.vent_rate > 0.0, "and the rates are kept")
	eq(_atm().vent_rate, 1.5, "built-in vent_rate")
	eq(_atm().door_rate, 2.0, "built-in door_rate")


func test_fresh_atmosphere_starts_sealed_full_and_open_empty() -> void:
	var g := _pair()
	g.remove(Vector2i(7, 1))  # breach in the right room's top wall
	var a := _atm()
	a.rebuild(g)
	eq(a.pressure_of(0), 1.0, "sealed room starts full")
	eq(a.pressure_of(1), 0.0, "breached room starts empty")
	eq(a.pressure_at(Vector2i(3, 3)), 1.0, "pressure_at inside the sealed room")
	eq(a.pressure_at(Vector2i(2, 1)), 0.0, "a wall cell has no pressure")
	eq(a.pressure_at(Vector2i(0, 0)), 0.0, "nor does empty hull")
	eq(a.room_at(Vector2i(6, 3)), 1, "room_at")
	eq(a.room_at(DOOR), -1, "a door cell is in no room")


func test_sealed_room_keeps_its_air() -> void:
	var a := _atm()
	a.rebuild(_single())
	for i in 100:
		a.tick(0.1, {})
	eq(a.pressure_at(Vector2i(3, 3)), 1.0, "sealed room still full after 100 ticks")


func test_breached_room_vents() -> void:
	var g := _single()
	var a := _atm()
	a.rebuild(g)
	g.remove(Vector2i(3, 1))
	a.rebuild(g)
	check(not a.rooms[0]["sealed"], "now unsealed")
	_near(a.pressure_at(Vector2i(3, 3)), 1.0, 1e-9, "air carried over the breach")
	for i in 50:
		a.tick(0.1, {})
	check(a.pressure_at(Vector2i(3, 3)) < 0.01, "almost empty after 5 s")
	for i in 50:
		a.tick(0.1, {})
	eq(a.pressure_at(Vector2i(3, 3)), 0.0, "below the floor it becomes exactly 0")


func test_venting_is_exponential() -> void:
	var g := _single()
	var a := _atm()
	a.rebuild(g)
	g.remove(Vector2i(3, 1))
	a.rebuild(g)
	a.tick(0.2, {})
	_near(a.pressure_of(0), exp(-1.5 * 0.2), 1e-9, "p *= exp(-vent_rate * dt)")


func test_open_door_equalises_and_conserves_oxygen() -> void:
	var a := _atm()
	a.rebuild(_pair())
	a.consume(1, 100.0)
	eq(a.pressure_of(1), 0.0, "right room emptied")
	var total := a.total_oxygen()
	_near(total, 6.0, 1e-9, "left room holds 6 cells of gas")
	var worst := 0.0
	for i in 200:
		a.tick(0.1, {DOOR: true})
		worst = maxf(worst, absf(a.total_oxygen() - total))
	_near(worst, 0.0, 1e-6, "total oxygen conserved on every tick")
	var want := total / 15.0  # size-weighted average
	_near(a.pressure_of(0), want, 1e-3, "left room settles at the average")
	_near(a.pressure_of(1), want, 1e-3, "right room settles at the average")


func test_a_two_cell_door_passes_gas_through_both_cells() -> void:
	var one := _atm()
	one.rebuild(_pair())
	one.consume(1, 100.0)
	var two := _atm()
	two.rebuild(_pair())
	two.consume(1, 100.0)
	one.tick(0.01, {DOOR: true})
	two.tick(0.01, {DOOR: true, DOOR + Vector2i.DOWN: true})
	var moved_one := 1.0 - one.pressure_of(0)
	var moved_two := 1.0 - two.pressure_of(0)
	check(moved_one > 0.0, "gas moves through one open cell")
	check(moved_two > 1.9 * moved_one and moved_two <= 2.0 * moved_one, "an open 2-wide door passes about twice as much, got %f vs %f" % [moved_two, moved_one])


func test_gas_flows_from_high_to_low_only() -> void:
	var a := _atm()
	a.rebuild(_pair())
	a.consume(1, 100.0)
	a.tick(0.1, {DOOR: true})
	check(a.pressure_of(0) < 1.0 and a.pressure_of(1) > 0.0, "gas moved from the full room to the empty one")
	check(a.pressure_of(0) > a.pressure_of(1), "one tick does not overshoot")


func test_big_time_step_does_not_overshoot() -> void:
	var a := _atm()
	a.rebuild(_pair())
	a.consume(1, 100.0)
	a.tick(100.0, {DOOR: true})
	_near(a.pressure_of(0), 0.4, 1e-9, "left lands on the average")
	_near(a.pressure_of(1), 0.4, 1e-9, "right lands on the average")


func test_closed_door_does_not_leak() -> void:
	for open_doors in [{}, {DOOR: false}]:
		var a := _atm()
		a.rebuild(_pair())
		a.consume(1, 100.0)
		for i in 100:
			a.tick(0.1, open_doors)
		eq(a.pressure_of(0), 1.0, "full room stays full (%s)" % str(open_doors))
		eq(a.pressure_of(1), 0.0, "empty room stays empty (%s)" % str(open_doors))


func test_door_to_space_vents_only_while_open() -> void:
	var g := _single()
	check(g.place("door", Vector2i(3, 1)), "door in the outer wall")
	var closed := _atm()
	closed.rebuild(g)
	check(closed.rooms[0]["sealed"], "a door does not unseal the room")
	for i in 50:
		closed.tick(0.1, {})
	eq(closed.pressure_of(0), 1.0, "closed outer door holds the air")
	var open := _atm()
	open.rebuild(g)
	for i in 50:
		open.tick(0.1, {Vector2i(3, 1): true})
	check(open.pressure_of(0) < 0.01, "open outer door vents like a breach")


func test_door_into_a_breached_room_drains_both() -> void:
	var g := _pair()
	var a := _atm()
	a.rebuild(g)
	g.remove(Vector2i(7, 1))
	a.rebuild(g)
	for i in 200:
		a.tick(0.1, {DOOR: true})
	check(a.pressure_of(0) < 0.01 and a.pressure_of(1) < 0.01, "everything leaks out through the breach")


func test_rebuild_after_a_split_keeps_both_halves() -> void:
	var g := _grid()
	_box(g, Rect2i(1, 1, 7, 5))  # interior 5x3 = 15 cells
	var a := _atm()
	a.rebuild(g)
	a.consume(0, 6.0)
	_near(a.pressure_of(0), 0.6, 1e-9, "room at 0.6")
	for y in range(2, 5):
		g.place("wall", Vector2i(4, y))
	a.rebuild(g)
	eq(a.rooms.size(), 2, "split in two")
	_near(a.pressure_of(0), 0.6, 1e-9, "left half keeps the pressure")
	_near(a.pressure_of(1), 0.6, 1e-9, "right half keeps the pressure")
	# knocking the wall down again: the three new floor cells hold no air yet
	for y in range(2, 5):
		g.place("floor", Vector2i(4, y))
	a.rebuild(g)
	eq(a.rooms.size(), 1, "merged again")
	_near(a.pressure_of(0), 12.0 * 0.6 / 15.0, 1e-9, "size-weighted average, new cells at 0")


func test_add_oxygen_and_consume_clamp() -> void:
	var a := _atm()
	a.rebuild(_single())  # 9 cells
	_near(a.consume(0, 3.0), 3.0, 1e-9, "consume reports what it took")
	_near(a.pressure_of(0), 2.0 / 3.0, 1e-9, "3 of 9 cells gone")
	_near(a.add_oxygen(0, 100.0), 3.0, 1e-9, "add only fills to the top")
	eq(a.pressure_of(0), 1.0, "clamped to 1")
	_near(a.consume(0, 100.0), 9.0, 1e-9, "consume only takes what is there")
	eq(a.pressure_of(0), 0.0, "clamped to 0")
	eq(a.consume(0, 1.0), 0.0, "nothing left to take")
	_near(a.add_oxygen(0, 4.5), 4.5, 1e-9, "half the room")
	_near(a.pressure_of(0), 0.5, 1e-9, "add_oxygen in cell units")
	eq(a.add_oxygen(7, 1.0), 0.0, "unknown room ignored")
	eq(a.consume(-1, 1.0), 0.0, "unknown room ignored")
	_near(a.total_oxygen(), 4.5, 1e-9, "total_oxygen")


func _run(order: Array) -> Array[float]:
	var g := _row()
	var a := _atm()
	a.rebuild(g)
	g.remove(Vector2i(9, 1))  # breach in the right room
	a.rebuild(g)
	a.consume(0, 3.0)
	var open_doors := {}
	for c in order:
		open_doors[c] = true
	for i in 100:
		a.tick(0.1, open_doors)
		if i == 30:
			a.add_oxygen(1, 2.0)
	return a.pressure.duplicate()


func test_same_inputs_give_the_same_result() -> void:
	var first := _run([Vector2i(4, 3), Vector2i(7, 3)])
	check(first[0] > 0.0 and first[0] < 1.0, "the scenario actually moves gas")
	eq(_run([Vector2i(4, 3), Vector2i(7, 3)]), first, "same run twice")
	eq(_run([Vector2i(7, 3), Vector2i(4, 3)]), first, "door dictionary order does not matter")


# --- air from the generators (playtest 2, economy): supply() fills the air network, evenly; breached rooms take none ---

## Three rooms of 6 cells in a row (rooms 0, 1, 2), doors at DOOR and (7,3), all closed unless a test opens them.
func _empty_row() -> Atmosphere:
	var a := _atm()
	a.rebuild(_row())
	for r in 3:
		a.consume(r, 100.0)
	return a


func test_a_generator_fills_a_room_two_closed_doors_away() -> void:
	var a := _empty_row()
	_near(a.add_oxygen(0, 0.0), 0.0, 1e-9, "nothing added")
	var added := a.supply(0, 18.0, {})
	_near(added, 18.0, 1e-9, "all of it went into the network")
	for r in 3:
		_near(a.pressure_of(r), 1.0, 1e-9, "room %d is full, closed doors or not" % r)
	check(a.rooms[2]["sealed"], "the far room is sealed")
	a.consume(0, 100.0)
	a.consume(1, 100.0)
	a.consume(2, 100.0)
	a.supply(0, 6.0, {})
	for r in 3:
		_near(a.pressure_of(r), 1.0 / 3.0, 1e-9, "6 cells of air over 18 cells of room: the same pressure everywhere (room %d)" % r)
	a.supply(1, 6.0, {})  # a generator in the middle room reaches the same network
	for r in 3:
		_near(a.pressure_of(r), 2.0 / 3.0, 1e-9, "and a second generator adds the same again (room %d)" % r)


func test_supply_fills_the_emptiest_first_and_never_overfills() -> void:
	var a := _empty_row()
	a.add_oxygen(1, 6.0)  # room 1 full, 0 and 2 empty
	var added := a.supply(1, 3.0, {})
	_near(added, 3.0, 1e-9, "taken")
	_near(a.pressure_of(0), 0.25, 1e-9, "the two empty rooms share it evenly")
	_near(a.pressure_of(2), 0.25, 1e-9, "the other one the same")
	eq(a.pressure_of(1), 1.0, "the full room stays full")
	_near(a.supply(1, 1000.0, {}), 9.0, 1e-9, "only what fits is taken")
	for r in 3:
		eq(a.pressure_of(r), 1.0, "all full")
	eq(a.supply(1, 5.0, {}), 0.0, "a full ship takes nothing")


func test_a_breached_room_gets_no_supply_and_its_closed_door_neighbour_keeps_its_air() -> void:
	var g := _row()
	var a := _atm()
	a.rebuild(g)
	g.remove(Vector2i(9, 1))  # breach in the right room (2)
	a.rebuild(g)
	check(not a.rooms[2]["sealed"], "room 2 is breached")
	for i in 100:
		a.tick(0.1, {})
	eq(a.pressure_of(2), 0.0, "the breached room is empty")
	eq(a.pressure_of(1), 1.0, "its closed-door neighbour keeps all of its air")
	a.consume(0, 3.0)
	a.consume(1, 3.0)
	var before := a.pressure_of(2)
	a.supply(0, 1.0, {})
	eq(a.pressure_of(2), before, "the breached room took none")
	check(a.pressure_of(0) > 0.5 and a.pressure_of(1) > 0.5, "the sealed rooms did")
	_near(a.pressure_of(0), a.pressure_of(1), 1e-9, "evenly")
	var gen_in_breach := a.supply(2, 1.0, {})
	eq(gen_in_breach, 0.0, "a generator in the breached room supplies nothing")
	# a breach in the middle cuts the network: the room beyond it gets nothing from a generator on the other side
	var g2 := _row()
	var b := _atm()
	b.rebuild(g2)
	g2.remove(Vector2i(5, 1))  # breach in the middle room's top wall
	b.rebuild(g2)
	b.consume(0, 100.0)
	b.consume(2, 100.0)
	b.supply(0, 6.0, {})
	eq(b.pressure_of(0), 1.0, "the generator's own room fills")
	eq(b.pressure_of(2), 0.0, "the room past the breached one is cut off")


func test_an_open_door_to_a_breached_room_still_drains_its_neighbour() -> void:
	var g := _pair()
	var a := _atm()
	a.rebuild(g)
	g.remove(Vector2i(7, 1))  # breach in room 1
	a.rebuild(g)
	for i in 300:
		a.tick(0.1, {DOOR: true})
	check(a.pressure_of(0) < 0.01, "the open door lets the neighbour's air out")
	var healthy := _atm()
	healthy.rebuild(_pair())
	for i in 100:
		healthy.tick(0.1, {DOOR: true})
	eq(healthy.pressure_of(0), 1.0, "no breach, no drain")


func test_a_door_open_to_space_stops_the_supply_to_that_room() -> void:
	var g := _single()
	g.place("door", Vector2i(3, 1))
	var a := _atm()
	a.rebuild(g)
	a.consume(0, 100.0)
	eq(a.supply(0, 1.0, {Vector2i(3, 1): true}), 0.0, "an outer door standing open vents the room: no supply")
	_near(a.supply(0, 1.0, {}), 1.0, 1e-9, "closed again, it takes air")


func test_a_powered_generator_raises_the_air_of_the_ship_and_an_unpowered_one_does_nothing() -> void:
	const ShipSim = preload("res://scripts/sim/ship_sim.gd")
	var sim := ShipSim.new()
	check(sim.choose_ship("res://data/ships/starter_rustbucket.json") == "", "a starter")
	var ship = sim.player_ship()
	var gens := []
	var reactors := []
	for uid in ship.components.instances:
		var id: String = ship.components.instances[uid]["id"]
		if float(ship.effective(id)["stats"].get("o2_rate", 0.0)) > 0.0:
			gens.append(uid)
		if str(ship.components.def(id).get("family", "")) == "reactor":
			reactors.append(uid)
	check(not gens.is_empty() and not reactors.is_empty(), "the starter has a generator and a reactor")
	for i in ship.atmosphere.pressure.size():
		ship.atmosphere.pressure[i] = 0.5
	var total: float = ship.atmosphere.total_oxygen()
	sim.step(5.0)
	check(float(ship.atmosphere.total_oxygen()) > total, "a working generator raises the air of a thin ship")
	for uid in reactors:
		ship.components.remove_uid(uid)
	ship.refresh()
	check(not ship.power_state.get("powered", {}).get(gens[0], false), "with the reactors gone the generator is dark")
	for i in ship.atmosphere.pressure.size():
		ship.atmosphere.pressure[i] = 0.5
	var before: float = ship.atmosphere.total_oxygen()
	sim.step(5.0)
	check(float(ship.atmosphere.total_oxygen()) <= before + 1.0e-9, "an unpowered generator supplies nothing: the air does not rise (crew only use it)")


func test_a_door_locked_by_evacuate_stays_shut_and_the_supply_still_crosses_it() -> void:
	var g := _pair()
	g.door_locked[DOOR] = true  # (Evacuate.sync locks the doors of an abandoned room)
	var a := _atm()
	a.rebuild(g)
	a.consume(1, 100.0)
	a.supply(0, 4.5, {})  # nobody opened it: the open-door map is empty
	check(a.pressure_of(1) > 0.0, "the closed, locked door still lets the generator's air through")
	for i in 100:
		a.tick(0.1, {})
	eq(a.pressure_of(0), 1.0, "and equalises nothing: the full room stays full")
	_near(a.pressure_of(1), 4.5 / 9.0 + 0.0, 0.2, "the supplied air stayed where it went")
