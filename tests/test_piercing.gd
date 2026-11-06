extends "res://tests/base_test.gd"
## Piercing rounds (weapons.gd): only rapid kinetic bolt guns can load them; a piercing shot passes a full shield, spends a round, deals
## 60% of its damage and opens no sector; with no rounds left the gun falls back to Standard and says so once.

const Arena = preload("res://scripts/combat/arena.gd")
const Content = preload("res://scripts/data/content.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")

var arena: Arena
var gun: int
var target: Ship


func _ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	for c in g.hull:
		g.force_tile(c, "floor")
	return Ship.new("t", g)


## Ship 0 has a rapid kinetic gun (damage 5) and `rounds` piercing rounds; ship 1 has a full shield and a wall at (3, 15).
func _duel(rounds: int) -> void:
	arena = Arena.new(1)
	var s0 := _ship()
	s0.inventory.add("piercing_rounds", rounds)
	arena.add_ship(s0)
	target = _ship()
	for c in [Vector2i(1, 14), Vector2i(1, 16), Vector2i(29, 14), Vector2i(29, 16), Vector2i(14, 1), Vector2i(16, 1), Vector2i(14, 29), Vector2i(16, 29), Vector2i(3, 15)]:
		target.grid.force_tile(c, "wall")
	check(target.components.place(target.grid, "reactor_mk1", Vector2i(9, 19), 0) > 0, "reactor")
	check(target.components.place(target.grid, "shield_mk1", Vector2i(13, 19), 0) > 0, "shield")
	for x in range(9, 17):
		target.cables.place(target.grid, Vector2i(x, 20))
	arena.add_ship(target, Vector2(800.0, 0.0))
	arena.weapons.defs["rg"] = {"kind": "bolt", "damage_type": "kinetic", "damage": 5, "rapid": true, "speed": 1500.0, "gimbal": 180, "cooldown": 0.0, "range": 2000}
	gun = arena.add_mount(0, "rg", Vector2(20.5, 15.5))


func _shoot() -> void:
	arena.ships[0].cooldowns.clear()
	check(arena.fire(0, gun, Vector2(2000.0, 0.0)), "fired")
	arena.step(1.0)


func _count(type: String) -> int:
	return arena.events.filter(func(e): return e["type"] == type).size()


func test_only_rapid_kinetic_bolt_guns_can_load_them() -> void:
	var ids := []
	for id in Content.list("weapons").map(func(e): return str(e["id"])):
		if arena_can(id):
			ids.append(id)
	ids.sort()
	check("rattle_burst_scrap" in ids, "the rapid kinetic bolt guns: " + str(ids))
	check(not ("kett_drone_picket" in ids) and not ("laser_turret_mk1" in ids) and not ("pd_mk2" in ids) and not ("artemis_mk1" in ids) and not ("pulse_light" in ids), "lasers, point defence, missiles and energy bolts cannot: " + str(ids))


func arena_can(id: String) -> bool:
	var a := Arena.new(1)
	return a.weapons.can_pierce(a.weapons.def(id))


func test_a_piercing_shot_passes_a_full_shield_spends_a_round_and_deals_60_percent() -> void:
	_duel(3)
	check(arena.weapons.set_ap(arena, 0, gun, true), "switched to piercing")
	_shoot()
	eq(_count("shield"), 0, "the full shield did not stop it")
	eq(arena.ships[1].sector_layers[0], 1.0, "and lost nothing")
	eq(arena.ships[0].ship.inventory.count("piercing_rounds"), 2, "one round spent")
	var wall: float = target.grid.hp_of(Vector2i(3, 15))
	check(absf(wall - (4.0 - 3.0)) < 0.01 or not target.grid.hp.has(Vector2i(3, 15)) or wall <= 1.01, "the wall took 3 of the shot's 5 (60%%): %s left" % str(wall))
	eq(arena.ships[0].sector_open.size(), 0, "a piercing shot opens no sector")


func test_a_standard_shot_is_stopped_by_the_same_shield() -> void:
	_duel(3)
	_shoot()
	eq(_count("shield"), 1, "the shield stopped the standard shot")
	eq(arena.ships[0].ship.inventory.count("piercing_rounds"), 3, "no round spent")


func test_the_gun_falls_back_to_standard_when_the_rounds_run_out() -> void:
	_duel(1)
	arena.weapons.set_ap(arena, 0, gun, true)
	_shoot()
	eq(arena.ships[0].ship.inventory.count("piercing_rounds"), 0, "the last round")
	eq(_count("shield"), 0, "it passed")
	_shoot()
	eq(_count("shield"), 1, "the next shot is standard and meets the shield")
	check(not arena.weapons.ap_on(arena, 0, gun, arena.ships[0].mounts[gun]), "the gun is back on Standard")
	eq(_count("ap_out"), 1, "logged once")
	_shoot()
	eq(_count("ap_out"), 1, "and not again")


func test_a_gun_that_cannot_load_them_refuses_the_switch() -> void:
	_duel(3)
	arena.weapons.defs["lz"] = {"kind": "laser", "damage_type": "energy", "damage": 1, "rapid": true, "gimbal": 180, "cooldown": 0.0, "range": 2000}
	var lz := arena.add_mount(0, "lz", Vector2(20.5, 15.5))
	check(not arena.weapons.set_ap(arena, 0, lz, true), "a laser cannot")


func test_the_item_is_crafted_known_and_sold() -> void:
	check(Content.list("items").any(func(e): return e["id"] == "piercing_rounds" and e["kind"] == "ammo"), "an ammo item")
	var rec: Dictionary = {}
	for r in Content.list("recipes"):
		if r["id"] == "piercing_rounds":
			rec = r
	eq([int(rec["output"]["count"]), rec["materials"].keys()], [10, ["scrap", "titanium"]], "10 a craft from scrap and titanium")
	check("piercing_rounds" in Content.read("res://data/recipes.json")["start_known"], "known from the start")
	var drift: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/drift.json"))
	check(drift["stations"].values().any(func(s): return s.get("stock", {}).has("piercing_rounds")), "sold in a store")


func test_a_few_late_enemies_carry_piercing_rounds() -> void:
	var Shipgen = load("res://scripts/space/shipgen.gd")
	var late := 0
	var early := 0
	var rounds_ok := true
	for seed_value in range(1, 41):
		for faction in ["rustfangs", "clans"]:
			var big = Shipgen.build(faction, "medium", seed_value, 130.0)
			var small = Shipgen.build(faction, "medium", seed_value, 40.0)
			if big != null and not big.ap_guns.is_empty():
				late += 1
				rounds_ok = rounds_ok and big.inventory.count("piercing_rounds") > 0
			if small != null and not small.ap_guns.is_empty():
				early += 1
	check(late > 0 and late < 40, "some late ships load piercing rounds, not most of them (%d of 80)" % late)
	check(rounds_ok, "and carry the rounds")
	eq(early, 0, "an early ship never does")
