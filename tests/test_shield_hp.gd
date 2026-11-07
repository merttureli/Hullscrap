extends "res://tests/base_test.gd"
## Shield HP (shields.gd): a layer is `layer_hp` HP by the part's tier, a hit takes its damage off the sector's pool, what the pool
## cannot take passes to the hull, a hit delays the regen, a sector knocked to 0 waits the break delay, ion takes double and locks the regen.

const Abilities = preload("res://scripts/sim/abilities.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")

var arena: Arena
var target: Ship
var gun: int
var aim := Vector2(2000.0, 0.0)


func near(got: float, want: float, msg: String, eps := 1e-3) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func _ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	for c in g.hull:
		g.force_tile(c, "floor")
	return Ship.new("t", g)


## Ship 1: a wall at (3, 15) in the line of fire and one Mk1 generator (1 layer, tier 1: 4 HP, 3 s delay, 1 HP/s, 5 s break).
## Ship 0 shoots a laser of `damage`.
func _duel(damage: float, dtype := "energy") -> void:
	arena = Arena.new(1)
	arena.add_ship(_ship())
	target = _ship()
	for c in [Vector2i(1, 14), Vector2i(1, 16), Vector2i(29, 14), Vector2i(29, 16), Vector2i(14, 1), Vector2i(16, 1), Vector2i(14, 29), Vector2i(16, 29), Vector2i(3, 15)]:
		target.grid.force_tile(c, "wall")
	check(target.components.place(target.grid, "reactor_mk1", Vector2i(9, 19), 0) > 0, "reactor")
	check(target.components.place(target.grid, "shield_mk1", Vector2i(13, 19), 0) > 0, "shield")
	for x in range(9, 17):
		target.cables.place(target.grid, Vector2i(x, 20))
	target.components.by_id["shield_mk1"]["stats"].erase("recharge")  # (the base speed: the numbers below are the tier row's)
	arena.add_ship(target, Vector2(800.0, 0.0))
	arena.weapons.defs["hp_gun"] = {"kind": "laser", "damage_type": dtype, "damage": damage, "gimbal": 180, "cooldown": 0.0, "range": 2000}
	gun = arena.add_mount(0, "hp_gun", Vector2(20.5, 15.5))


func _shoot() -> void:
	arena.ships[0].cooldowns.clear()
	check(arena.fire(0, gun, aim), "fired")


func _shield_events() -> Array:
	return arena.events.filter(func(e): return e["type"] == "shield")


func test_the_tier_rows_give_the_hp_numbers() -> void:
	_duel(1.0)
	var co = arena.ships[1]
	var row := Abilities.shield_row({"tier": 1})
	eq([row["layer_hp"], row["regen_delay"], row["regen_rate"], row["break_delay"]], [4.0, 3.0, 1.0, 5.0], "tier 1: 4 HP a layer, 3 s delay, 1 HP/s, 5 s broken")
	eq(co.shield_hp, row, "the ship reads its generator's row")
	eq(Shields.hp_cap_of(co, 0), 4.0, "one layer is 4 HP")
	var t3 := Abilities.shield_row({"tier": 3})
	check(float(t3["layer_hp"]) > float(row["layer_hp"]) and float(t3["break_delay"]) < float(row["break_delay"]) and float(t3["regen_rate"]) > float(row["regen_rate"]), "a higher tier has more HP, a faster regen and a shorter break")
	eq(Abilities.shield_row({"tier": 1, "stats": {"layer_hp": 9.0}})["layer_hp"], 9.0, "a part's own stat wins")


func test_a_hit_takes_its_damage_off_the_pool_and_a_covered_shot_is_stopped() -> void:
	_duel(1.5)
	_shoot()
	near(Shields.hp_of(arena.ships[1], 0), 2.5, "1.5 of the 4 HP gone")
	near(float(_shield_events()[0]["passed"]), 0.0, "nothing passed")
	eq(target.grid.hp_of(Vector2i(3, 15)), 4.0, "the wall is untouched")


func test_the_excess_of_a_heavy_shot_passes_to_the_hull() -> void:
	_duel(6.0)
	_shoot()
	near(float(_shield_events()[0]["passed"]), 2.0, "6 against a pool of 4: 2 passed")
	eq(arena.ships[1].sector_layers[0], 0.0, "the pool is empty")
	near(target.grid.hp_of(Vector2i(3, 15)), 2.0, "and the wall took the 2")


func test_a_weak_shield_breaks_on_one_hit_and_waits_its_break_delay() -> void:
	_duel(4.0)
	_shoot()
	eq(arena.ships[1].sector_layers[0], 0.0, "one hit of 4 knocked the tier 1 layer down")
	near(arena.ships[1].sector_wait[0], 5.0, "it waits the break delay")
	arena.step(4.9)
	eq(arena.ships[1].sector_layers[0], 0.0, "still down at 4.9 s")
	arena.step(1.1)  # 6 s: 1 s of regen
	near(arena.ships[1].sector_layers[0], 0.25, "regen began after the 5 s: 1 HP of 4", 0.02)
	_shoot()
	eq(_shield_events().size(), 2, "(a sector with HP stops a shot again)")


func test_regen_starts_after_the_delay() -> void:
	_duel(1.0)
	_shoot()
	near(arena.ships[1].sector_layers[0], 0.75, "3 of 4 HP left")
	arena.step(2.9)
	near(arena.ships[1].sector_layers[0], 0.75, "no regen inside the 3 s delay")
	arena.step(1.1)  # 4 s: 1 s of regen at 1 HP/s
	near(arena.ships[1].sector_layers[0], 1.0, "then 1 HP/s fills it", 0.02)
	_shoot()
	arena.step(1.0)
	_shoot()
	near(arena.ships[1].sector_wait[0], 3.0, "a second hit starts the delay again")


func test_ion_takes_double_and_locks_the_regen() -> void:
	_duel(1.0, "ion")
	_shoot()
	near(Shields.hp_of(arena.ships[1], 0), 2.0, "1 ion damage took 2 HP")
	near(arena.ships[1].ion_lock, 5.0, "and locked the bubble")
	arena.step(4.0)
	near(Shields.hp_of(arena.ships[1], 0), 2.0, "no regen while locked")
	arena.step(1.1)  # the lock ended at 5 s; the 3 s delay was still running underneath
	near(Shields.hp_of(arena.ships[1], 0), 2.0, "the delay starts to run once the lock is over")


func test_a_shot_that_leaves_through_an_open_sector_or_passes_uses_no_hp() -> void:
	_duel(1.0)
	arena.weapons.defs["hp_gun"]["pass_shields"] = true
	_shoot()
	eq(_shield_events().size(), 0, "a piercing shot never meets the pool")
	near(Shields.hp_of(arena.ships[1], 0), 4.0, "so it takes nothing")


func test_overcharge_adds_layers_of_hp() -> void:
	_duel(1.0)
	var co = arena.ships[1]
	eq(arena.overcharge(1), "", "overcharged")
	near(Shields.hp_cap_of(co, 0), 8.0, "a second layer: 4 more HP while it runs")
