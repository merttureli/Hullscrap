extends "res://tests/base_test.gd"
## The weights of a sectored bubble (shield_balance.gd): steps of 0.5 from 0 to 2 that always add up to the
## sector count, taken from the opposite sector first, the presets, and what a ship saves.

const Balance = preload("res://scripts/combat/shield_balance.gd")


func _step(w: Array, s: int, delta: int) -> Array:
	return Balance.step(w, s, delta)["weights"]


func test_even_and_valid_weights() -> void:
	eq(Balance.even(4), [1.0, 1.0, 1.0, 1.0], "even is all ones")
	check(Balance.valid([1.0, 1.0], 2) and Balance.valid([2.0, 0.0], 2) and Balance.valid([0.5, 1.5, 1.0, 1.0], 4), "good lists")
	check(not Balance.valid([1.0, 1.0], 4), "the wrong count")
	check(not Balance.valid([2.5, -0.5], 2), "out of 0..2")
	check(not Balance.valid([1.2, 0.8], 2), "not a step of 0.5")
	check(not Balance.valid([1.0, 0.5], 2), "not adding up to the count")
	check(not Balance.valid("x", 2) and not Balance.valid([1.0, "a"], 2), "junk")
	eq(Balance.normalized([2.0, 0.0], 2), [2.0, 0.0], "a good list stays")
	eq(Balance.normalized([2.0, 0.0], 4), [1.0, 1.0, 1.0, 1.0], "one for another count becomes even")
	eq([Balance.legal(0), Balance.legal(1), Balance.legal(2), Balance.legal(3), Balance.legal(4), Balance.legal(7), Balance.legal(8), Balance.legal(99)], [1, 1, 2, 2, 4, 4, 8, 8], "only 1, 2, 4 and 8 sectors exist")


func test_the_arrow_keys_point_at_sectors() -> void:
	eq([Balance.dir_sector(1, "up"), Balance.dir_sector(1, "left")], [-1, -1], "one piece: nothing to point at")
	eq([Balance.dir_sector(2, "up"), Balance.dir_sector(2, "down"), Balance.dir_sector(2, "left"), Balance.dir_sector(2, "right")], [0, 1, -1, -1], "two: bow and stern, no port or starboard")
	eq([Balance.dir_sector(4, "up"), Balance.dir_sector(4, "right"), Balance.dir_sector(4, "down"), Balance.dir_sector(4, "left")], [0, 1, 2, 3], "four: bow, starboard, stern, port")
	eq([Balance.dir_sector(8, "up"), Balance.dir_sector(8, "right"), Balance.dir_sector(8, "down"), Balance.dir_sector(8, "left")], [0, 2, 4, 6], "eight: the four sides, the diagonals are set in the Shields tab")
	eq([Balance.opposite(2, 0), Balance.opposite(4, 1), Balance.opposite(8, 5), Balance.opposite(8, 0)], [1, 3, 1, 4], "the opposite sector")
	eq([Balance.name_of(2, 1), Balance.name_of(4, 1), Balance.name_of(4, 3), Balance.name_of(8, 4)], ["Stern", "Starboard", "Port", "Stern"], "names")


func test_a_step_takes_from_the_opposite_sector_first_and_stops_at_two_and_zero() -> void:
	var w := Balance.even(4)
	w = _step(w, 0, 1)
	eq(w, [1.5, 1.0, 0.5, 1.0], "bow up: half a weight from the stern")
	w = _step(w, 0, 1)
	eq(w, [2.0, 1.0, 0.0, 1.0], "again: the stern is empty")
	var r := Balance.step(w, 0, 1)
	eq(r["weights"], [2.0, 1.0, 0.0, 1.0], "a step past 2 changes nothing")
	check(str(r["why"]).contains("most"), "and says why: " + str(r["why"]))
	w = _step(w, 2, 1)
	eq(w, [1.5, 1.0, 0.5, 1.0], "stern up takes from the bow")
	r = Balance.step([1.0, 1.0], 0, -1)
	eq(r["weights"], [0.5, 1.5], "a minus gives to the opposite")
	r = Balance.step([0.0, 2.0], 0, -1)
	eq(r["weights"], [0.0, 2.0], "a minus past 0 changes nothing")
	check(str(r["why"]).contains("0"), "and says why: " + str(r["why"]))
	r = Balance.step([2.0, 0.0], 1, 1)
	eq(r["weights"], [1.5, 0.5], "two sectors: the only other one gives")
	check(Balance.step([1.0], 0, 1)["why"] != "", "one piece: refused")


func test_with_nothing_to_take_opposite_a_step_takes_evenly_from_the_others() -> void:
	var w := [1.0, 1.5, 0.0, 1.5]
	w = _step(w, 0, 1)
	eq(w, [1.5, 1.5, 0.0, 1.0], "the opposite stern has none: the port gives first (it is next to the stern)")
	w = _step(w, 0, 1)
	eq(w, [2.0, 1.0, 0.0, 1.0], "then the one with the most, the starboard")
	var eight := [1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0, 2.0]
	var r := _step(eight, 0, 1)
	eq(r, [1.5, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.5], "eight sectors: the bow-port, with the most, gives")
	eq(Balance.step([1.0, 0.5, 2.0, 0.5], 0, -1)["weights"], [0.5, 0.5, 2.0, 1.0], "a minus with the opposite sector full goes to one of the others holding the least")
	eq(Balance.step([1.0, 2.0, 0.0, 1.0], 0, -1)["weights"], [0.5, 2.0, 0.5, 1.0], "a minus: the opposite stern has room")


func test_weights_always_add_up_to_the_count_whatever_is_pressed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for n in [2, 4, 8]:
		var w := Balance.even(n)
		var moved := 0
		for i in 400:
			var r := Balance.step(w, rng.randi() % n, 1 if rng.randf() < 0.5 else -1)
			if r["why"] == "":
				moved += 1
			w = r["weights"]
			check(Balance.valid(w, n), "%d sectors, press %d: %s" % [n, i, str(w)])
		check(moved > 100, "%d sectors: the steps did move things (%d)" % [n, moved])


func test_the_presets_lean_toward_a_side_and_add_up() -> void:
	eq(Balance.preset(4, "Even"), [1.0, 1.0, 1.0, 1.0], "even")
	eq(Balance.preset(2, "Bow"), [2.0, 0.0], "two sectors: bow")
	eq(Balance.preset(2, "Stern"), [0.0, 2.0], "and stern")
	eq(Balance.preset(4, "Bow"), [2.0, 1.0, 0.0, 1.0], "four: bow")
	eq(Balance.preset(4, "Starboard"), [1.0, 2.0, 1.0, 0.0], "starboard")
	eq(Balance.preset(4, "Stern"), [0.0, 1.0, 2.0, 1.0], "stern")
	eq(Balance.preset(4, "Port"), [1.0, 0.0, 1.0, 2.0], "port")
	eq(Balance.preset(8, "Bow"), [2.0, 1.5, 1.0, 0.5, 0.0, 0.5, 1.0, 1.5], "eight: bow fades away round both sides")
	eq(Balance.preset(2, "Port"), [], "two sectors have no port")
	eq(Balance.preset(2, "Starboard"), [], "or starboard")
	eq(Balance.preset(1, "Even"), [], "one piece: no presets")
	eq(Balance.preset(4, "Sideways"), [], "an unknown name")
	for n in [2, 4, 8]:
		for name in Balance.PRESETS:
			var w := Balance.preset(n, name)
			if w.is_empty():
				check(n < 4 and name in ["Port", "Starboard"], "%d sectors, %s: only port and starboard are missing" % [n, name])
			else:
				check(Balance.valid(w, n), "%d sectors, %s: %s is valid" % [n, name, str(w)])


func test_a_ships_saved_balance_survives_json_and_drops_junk() -> void:
	var fresh := Balance.fresh()
	check(Balance.is_fresh(fresh), "a new balance is fresh")
	eq(fresh, {"weights": [], "presets": [[], []]}, "no weights, two empty slots")
	var set := {"weights": [2.0, 0.0], "presets": [[1.5, 0.5], []]}
	check(not Balance.is_fresh(set), "something set")
	var back := Balance.sanitize(JSON.parse_string(JSON.stringify(set)))
	eq(back, set, "a JSON round trip gives the same lists")
	eq(Balance.sanitize(null), fresh, "nothing: fresh")
	eq(Balance.sanitize({"weights": "x", "presets": 5}), fresh, "junk: fresh")
	eq(Balance.sanitize({"weights": [1, 1], "presets": [[1, "a"], [0.5, 1.5], [1.0, 1.0]]}), {"weights": [1.0, 1.0], "presets": [[], [0.5, 1.5]]}, "ints become floats, bad slots are emptied, a third slot is ignored")
