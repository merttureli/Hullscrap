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
