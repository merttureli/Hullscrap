extends "res://tests/base_test.gd"
## Fires (scripts/sim/fire.gd): growth, spreading, oxygen, parts, how they start, saving.

const Fixture = preload("res://tests/fixture_ship.gd")
const Fire = preload("res://scripts/sim/fire.gd")
const Heat = preload("res://scripts/sim/heat.gd")
const Reliability = preload("res://scripts/sim/reliability.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Ship = preload("res://scripts/ship/ship.gd")

const MID := Vector2i(15, 12)  # a floor cell in the middle of the room (floor x 9..21, y 9..16)


func _rng(seed_value := 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _room(ship: Ship) -> int:
	return ship.atmosphere.room_at(MID)


func _log(ship: Ship, text: String) -> bool:
	return ship.events.any(func(e): return e["text"] == text)


func near(got: float, want: float, msg: String, eps := 1e-6) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, want, got])


func test_a_fire_grows_while_the_air_is_good() -> void:
	var ship := Fixture.room_ship()
	check(Fire.ignite(ship, MID), "lit on floor")
	near(ship.fires[MID], Fire.START, "a new fire")
	Fire.tick(ship, 1.0)
	near(ship.fires[MID], Fire.START + 0.15, "+0.15 a second")
	Fire.tick(ship, 2.0)
	near(ship.fires[MID], Fire.START + 0.45, "and by the time passed")
	for i in 20:
		Fire.tick(ship, 1.0)
	near(ship.fires[MID], 1.0, "it tops out at 1")


func test_only_floor_burns() -> void:
	var ship := Fixture.room_ship()
	check(not Fire.ignite(ship, Vector2i(8, 12)), "not a wall")
	check(not Fire.ignite(ship, Vector2i(2, 2)), "not an empty cell")
	check(ship.fires.is_empty(), "nothing burns")
	check(Fire.ignite_near(ship, Vector2i(15, 8)), "a hit on the wall lights the floor beside it")
	eq(ship.fires.keys(), [Vector2i(15, 9)], "the cell inside")
	var uid := Fixture.put(ship, "reactor_mk1", 10, 10)
	check(Fire.ignite(ship, Vector2i(11, 11)), "a cell under a part burns")
	check(uid > 0, "(part placed)")


func test_a_fire_spreads_to_neighbouring_floor_only() -> void:
	var ship := Fixture.room_ship()
	var rng := _rng(5)
	Fire.ignite(ship, Vector2i(9, 9))  # the corner of the room
	for i in 150:
		ship.atmosphere.pressure[_room(ship)] = 1.0  # keep the air good
		Fire.tick(ship, 1.0, rng)
	check(ship.fires.size() > 5, "it spread: %d cells" % ship.fires.size())
	for c in ship.fires:
		check(c.x >= 9 and c.x <= 21 and c.y >= 9 and c.y <= 16, "%s is inside the room" % str(c))
		var linked := false
		for d in Fire.SIDES:
			linked = linked or ship.fires.has(c + d)
		check(linked, "%s touches another burning cell" % str(c))


func test_a_fire_does_not_spread_without_an_rng() -> void:
	var ship := Fixture.room_ship()
	Fire.ignite(ship, MID)
	for i in 100:
		Fire.tick(ship, 1.0)
	eq(ship.fires.size(), 1, "still one cell")


func test_the_spread_chance_is_about_ten_percent_a_second() -> void:
	var ship := Fixture.room_ship()
	var born := 0
	var rng := _rng(3)
	for t in 400:
		ship.fires.clear()
		ship.atmosphere.pressure[_room(ship)] = 1.0
		Fire.ignite(ship, MID)
		Fire.tick(ship, 1.0, rng)
		if ship.fires.size() > 1:
			born += 1
	check(born >= 20 and born <= 65, "%d of 400 seconds spread (about 40)" % born)


func test_a_fire_eats_the_rooms_oxygen() -> void:
	var ship := Fixture.room_ship()
	var room := _room(ship)
	for c in [MID, MID + Vector2i.RIGHT, MID + Vector2i.DOWN]:
		Fire.ignite(ship, c)
	var before: float = ship.atmosphere.oxygen_of(room)
	Fire.tick(ship, 1.0)
	near(before - ship.atmosphere.oxygen_of(room), 3.0 * Fire.AIR_USE, "0.05 a burning cell a second")


func test_a_fire_dies_in_thin_air() -> void:
	var ship := Fixture.room_ship()
	ship.atmosphere.pressure[_room(ship)] = 0.19
	Fire.ignite(ship, MID, 0.5)
	Fire.tick(ship, 1.0)
	near(ship.fires[MID], 0.2, "decays by 0.3 a second")
	check(not _log(ship, "Fire out"), "(still burning)")
	Fire.tick(ship, 1.0)
	check(ship.fires.is_empty(), "and goes out at 0")
	check(_log(ship, "Fire out"), "the chronicle says so")


func test_the_air_limit_is_twenty_percent() -> void:
	var ship := Fixture.room_ship()
	ship.atmosphere.pressure[_room(ship)] = 0.21
	Fire.ignite(ship, MID, 0.5)
	Fire.tick(ship, 1.0)
	near(ship.fires[MID], 0.65, "just above 20%: it grows")
	ship.atmosphere.pressure[_room(ship)] = 0.2
	Fire.tick(ship, 1.0)
	near(ship.fires[MID], 0.65, "at 20% it neither grows nor dies")


func test_a_fire_burns_itself_out_in_a_small_sealed_room() -> void:
	var ship := Fixture.room_ship()
	var rng := _rng(2)
	Fire.ignite(ship, MID)
	var peak := 0
	for i in 3000:
		Fire.tick(ship, 1.0, rng)
		peak = maxi(peak, ship.fires.size())
		if ship.fires.is_empty():
			break
	check(ship.fires.is_empty(), "the oxygen ran out and the fire with it")
	check(peak > 3, "after it had spread (%d cells)" % peak)
	check(ship.atmosphere.pressure[_room(ship)] <= Fire.MIN_AIR + 0.02, "the room is left thin")


func test_parts_in_a_fire_lose_hp_and_are_disabled_at_zero() -> void:
	var ship := Fixture.room_ship()
	var uid := Fixture.put(ship, "reactor_mk1", 10, 10)
	var inst: Dictionary = ship.components.instances[uid]
	Fire.ignite(ship, Vector2i(11, 11))
	Fire.ignite(ship, Vector2i(12, 12))  # two burning cells under one part: it loses 0.5 a second, not 1
	for i in 4:
		Fire.tick(ship, 1.0)
	near(float(inst["hp"]), 6.0, "8 hp - 4 s x 0.5")
	eq(inst["status"], "ok", "still works")
	for i in 12:
		Fire.tick(ship, 1.0)
	near(float(inst["hp"]), 0.0, "burnt to 0")
	eq(inst["status"], "disabled", "disabled, not destroyed")
	check(_log(ship, "Reactor Mk1 is disabled"), "the chronicle says so")
	check(ship.components.instances.has(uid), "and it is still there")
	ship.refresh()
	check(not ship.power_state.get("powered", {}).get(uid, false), "it makes no power")


func test_a_part_off_the_fire_is_left_alone() -> void:
	var ship := Fixture.room_ship()
	var uid := Fixture.put(ship, "reactor_mk1", 10, 10)
	Fire.ignite(ship, Vector2i(14, 10))  # beside it, not under it
	for i in 10:
		Fire.tick(ship, 1.0)
	eq(ship.components.instances[uid]["hp"], 8, "untouched")


func test_the_chronicle_names_the_room() -> void:
	var ship := Fixture.room_ship()
	Fire.ignite(ship, MID)
	check(_log(ship, "Fire in corridor"), "a room with no system in it")
	var other := Fixture.room_ship()
	Fixture.put(other, "engine_mk1", 15, 10)
	Fire.ignite(other, Vector2i(16, 10))
	check(_log(other, "Fire in engine room"), "an engine room")
	Fire.ignite(other, Vector2i(17, 10))
	eq(other.events.size(), 1, "a second fire in the same room is not news")
	var third := Fixture.room_ship()
	Fixture.put(third, "reactor_mk1", 10, 10)
	Fixture.put(third, "engine_mk1", 15, 10)
	eq(Fire.room_name(third, _room(third)), "reactor room", "the reactor names a room that has both")


func test_fire_out_is_logged_once_for_the_last_fire_in_a_room() -> void:
	var ship := Fixture.room_ship()
	Fire.ignite(ship, MID)
	Fire.ignite(ship, MID + Vector2i.RIGHT)
	Fire.extinguish(ship, MID)
	check(not _log(ship, "Fire out"), "one still burns")
	Fire.extinguish(ship, MID + Vector2i.RIGHT)
	check(_log(ship, "Fire out"), "now it is out")


func test_a_burning_cell_that_is_no_longer_floor_goes_out() -> void:
	var ship := Fixture.room_ship()
	Fire.ignite(ship, MID)
	ship.grid.force_tile(MID, "")
	ship.mark_dirty()
	Fire.tick(ship, 0.1)
	check(ship.fires.is_empty(), "nothing to burn on")


func test_overheating_can_start_a_real_fire() -> void:
	var lit := 0
	for seed_value in range(1, 41):
		var ship := Fixture.room_ship()
		var uid := Fixture.put(ship, "reactor_neon_mk1", 10, 10)
		Fixture.wire(ship, [Vector2i(11, 11)])
		ship.refresh()
		var rng := _rng(seed_value)
		for s in 30:
			Heat.tick(ship, 1.0, rng)
		check(ship.components.instances[uid]["status"] == "overheated" or _log(ship, "Prism Core cooled down"), "it overheated")
		var said := _log(ship, "Prism Core started a fire")
		eq(not ship.fires.is_empty(), said, "a fire burns exactly when the chronicle says one started")
		if said:
			lit += 1
			var cell: Vector2i = ship.fires.keys()[0]
			check(cell in ship.components.instances[uid]["cells"], "on the part")
			check(_log(ship, "Fire in reactor room"), "and the room is named")
	check(lit >= 2 and lit <= 20, "%d of 40 trips started a fire (20 percent each)" % lit)


func test_a_malfunction_can_start_a_real_fire() -> void:
	var found := false
	for seed_value in range(1, 6):
		var ship := Fixture.room_ship()
		var uid := Fixture.put(ship, "reactor_scrap_mk1", 10, 10)
		Fixture.wire(ship, [Vector2i(11, 11)])
		ship.refresh()
		var rng := _rng(seed_value)
		for s in 40000:
			Reliability.tick(ship, 1.0, rng)
			if ship.components.instances[uid]["status"] != "ok":
				ship.repair(uid)
				ship.refresh()
			if _log(ship, "Rustbucket Reactor started a fire"):
				break
		if _log(ship, "Rustbucket Reactor started a fire"):
			found = true
			check(not ship.fires.is_empty() and ship.fires.keys()[0] in ship.components.instances[uid]["cells"], "a fire on the part")
			break
	check(found, "a scrap reactor sets itself alight now and then")


func test_a_hit_that_ignites_starts_a_real_fire() -> void:
	var ship := Fixture.room_ship()
	var a := Arena.new()
	var i := a.add_ship(ship)
	a.log_event("ignite", i, Vector2i(16, 12))
	eq(ship.fires.keys(), [Vector2i(16, 12)], "on the cell that was hit")
	a.log_event("ignite", i, Vector2i(8, 12))  # the wall of the room
	check(ship.fires.has(Vector2i(9, 12)), "a wall was hit: the floor behind it burns")
	check(_log(ship, "Fire in corridor"), "and the chronicle has it")


func test_fires_are_saved_and_loaded() -> void:
	var a := Fixture.room_ship()
	Fire.ignite(a, MID, 0.6)
	Fire.ignite(a, MID + Vector2i.DOWN, 0.3)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(a.to_dict()))
	var b := Ship.new_starter()
	eq(b.load_dict(saved), "", "loads")
	eq(b.fires, {MID: 0.6, MID + Vector2i.DOWN: 0.3}, "the same fires")
	var calm := Fixture.room_ship()
	check(not calm.to_dict().has("fires"), "a ship with no fire writes no list")
	eq(calm.load_dict(saved), "", "load over a calm ship")
	eq(calm.fires.size(), 2, "now it burns")
	var old: Dictionary = JSON.parse_string(JSON.stringify(Fixture.room_ship().to_dict()))
	eq(b.load_dict(old), "", "an older save loads")
	check(b.fires.is_empty(), "and burns nothing")
	var bad: Dictionary = saved.duplicate(true)
	bad["fires"] = [[1, 2]]
	eq(b.load_dict(bad), "bad ship data", "a malformed list is refused")
	check(b.fires.is_empty(), "and changes nothing")


func test_the_same_seed_burns_the_same_way() -> void:
	var runs: Array = []
	for seed_value in [4, 4, 9]:
		var ship := Fixture.room_ship()
		Fixture.put(ship, "engine_mk1", 15, 10)
		var rng := _rng(seed_value)
		Fire.ignite(ship, MID)
		for i in 100:
			ship.atmosphere.pressure[_room(ship)] = 1.0
			Fire.tick(ship, 0.5, rng)
		runs.append([ship.fires.duplicate(), float(ship.components.instances[1]["hp"])])
	eq(runs[0], runs[1], "the same seed, the same fire")
	check(runs[0][0] != runs[2][0], "another seed, another fire")
