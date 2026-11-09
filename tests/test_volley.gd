extends "res://tests/base_test.gd"
## Volley and Ripple fire modes (volley.gd): a Volley group waits for its slowest gun (at most 3 s), fires together within 0.15 s and
## opens the sector once; Ripple is unchanged; point defence and piercing shots never open the shield; the mode is saved with the ship
## and an old save loads as Ripple.

const Arena = preload("res://scripts/combat/arena.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Volley = preload("res://scripts/combat/volley.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")

var arena: Arena
var guns := []


func _ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	for c in g.hull:
		g.force_tile(c, "floor")
	return Ship.new("t", g)


## Ship 0 with three lasers (cooldowns `cds`) in the fire group LMB, Volley when `volley`; ship 1 a shielded target 800 px to the east.
func _duel(cds: Array, volley: bool) -> void:
	arena = Arena.new(1)
	arena.add_ship(_ship())
	var t := _ship()
	check(t.components.place(t.grid, "reactor_mk1", Vector2i(9, 19), 0) > 0, "reactor")
	check(t.components.place(t.grid, "shield_mk1", Vector2i(13, 19), 0) > 0, "shield")
	for x in range(9, 17):
		t.cables.place(t.grid, Vector2i(x, 20))
	arena.add_ship(t, Vector2(800.0, 0.0))
	guns = []
	for i in cds.size():
		arena.weapons.defs["vg%d" % i] = {"kind": "laser", "damage_type": "energy", "damage": 0.1, "gimbal": 180, "cooldown": cds[i], "range": 2000}
		guns.append(arena.add_mount(0, "vg%d" % i, Vector2(20.5, 15.5 + 0.2 * i)))
	if volley:
		arena.ships[0].volley[1] = true


## The player's button held: every gun of the group is asked to fire each substep.
func _hold(seconds: float) -> void:
	for i in int(seconds * 60.0):
		for g in guns:
			arena.fire(0, g, Vector2(800.0, 0.0))
		arena.step(1.0 / 60.0)


func _shot_ticks() -> Array:
	return arena.events.filter(func(e): return e["type"] == "shot" and e["ship"] == 0).map(func(e): return e["tick"])


func test_a_volley_of_three_guns_fires_together_and_opens_the_sector_once() -> void:
	_duel([1.0, 1.0, 1.0], true)
	check(not arena.fire(0, guns[0], Vector2(800.0, 0.0)), "a Volley gun does not fire on the spot: the order waits for its group")
	eq(_shot_ticks().size(), 0, "nothing yet")
	_hold(0.5)
	var ticks := _shot_ticks()
	eq(ticks.size(), 3, "all three fired")
	check(ticks[2] - ticks[0] <= 9, "inside 0.15 s (%s)" % str(ticks))
	var co = arena.ships[0]
	eq(co.sector_open.size(), 1, "one sector opened")
	var win: Vector2i = co.sector_open.values()[0]
	check(win.y - win.x + 1 <= 18 + 9, "once for the volley: the laser's 0.3 s plus the stagger, not three windows end to end (%s)" % str(win))


func test_a_volley_waits_for_its_slowest_gun() -> void:
	_duel([1.0, 1.0, 2.0], true)
	_hold(0.5)
	eq(_shot_ticks().size(), 3, "the first volley")
	_hold(1.3)  # 1.8 s: the two quick guns are ready at 1 s, the slow one at 2 s
	eq(_shot_ticks().size(), 3, "the quick guns hold their fire for the slow one")
	_hold(0.5)
	eq(_shot_ticks().size(), 6, "and all three go together once it is ready")


func test_a_volley_waits_at_most_three_seconds() -> void:
	_duel([1.0, 1.0, 9.0], true)
	_hold(0.5)
	eq(_shot_ticks().size(), 3, "the first volley")
	_hold(3.3)  # the quick guns are ready at 1 s; they wait until 4 s
	eq(_shot_ticks().size(), 3, "still waiting")
	_hold(0.6)
	eq(_shot_ticks().size(), 5, "after 3 s the ready guns go without the slow one")


func test_a_volley_does_not_wait_for_a_gun_that_cannot_bear() -> void:  # (fights-end 2026-11: a flagship's pulses waited on its railgun)
	_duel([1.0], true)
	arena.weapons.defs["vg_back"] = {"kind": "laser", "damage_type": "energy", "damage": 0.1, "gimbal": 5, "cooldown": 2.5, "range": 2000}
	var back: int = arena.add_mount(0, "vg_back", Vector2(10.5, 15.5), true, Vector2.LEFT)  # it looks west, the target is east
	arena.ships[0].volley[1] = true
	check(arena.fire(0, back, Vector2(800.0, 0.0), true), "the stern gun fires once (forced) and cools for 2.5 s")
	check(not arena.weapons.can_bear(arena, 0, back, Vector2(800.0, 0.0)), "it cannot bear on the target east of it")
	check(arena.weapons.can_bear(arena, 0, guns[0], Vector2(800.0, 0.0)), "the gun that faces it can")
	for i in 12:  # the pilot asks only the gun that bears
		arena.fire(0, guns[0], Vector2(800.0, 0.0))
		arena.step(1.0 / 60.0)
	eq(_shot_ticks().size(), 2, "it fires at once, not after the stern gun's 2.5 s (%s)" % str(_shot_ticks()))


func test_ripple_is_unchanged() -> void:
	_duel([1.0, 2.0, 3.0], false)
	check(arena.fire(0, guns[0], Vector2(800.0, 0.0)), "a Ripple gun fires at once")
	check(arena.fire(0, guns[1], Vector2(800.0, 0.0)), "each as it is ready")
	eq(_shot_ticks().size(), 2, "two shots, same tick")
	arena.step(1.01)
	check(arena.fire(0, guns[0], Vector2(800.0, 0.0)) and not arena.fire(0, guns[1], Vector2(800.0, 0.0)), "the quick gun fires again, the slow one is cooling")


func test_a_gun_picked_by_its_number_key_fires_alone_even_in_volley() -> void:
	_duel([1.0, 1.0, 1.0], true)
	check(arena.fire(0, guns[0], Vector2(800.0, 0.0), true), "forced: a number key fires that gun")
	eq(_shot_ticks().size(), 1, "just the one")


func test_point_defence_and_piercing_shots_never_open_the_shield() -> void:
	var pd := {"kind": "bolt", "damage_type": "kinetic", "damage": 1, "effects": {"intercept": {"range": 500}}}
	eq(Shields.drop_seconds(pd), 0.0, "an intercept gun's shots drop nothing")
	eq(Shields.drop_seconds({"kind": "bolt", "ap": true}), 0.0, "nor does a piercing round")
	check(Shields.drop_seconds({"kind": "bolt"}) > 0.0, "a plain bolt does")
	_duel([1.0], false)
	arena.weapons.defs["vgpd"] = {"kind": "bolt", "damage_type": "kinetic", "damage": 1, "turret": true, "arc": 360, "cooldown": 0.0, "range": 2000, "effects": {"intercept": {"range": 500}}}
	var uid := arena.add_mount(0, "vgpd", Vector2(20.5, 15.5))
	arena.ships[0].volley[0] = true
	check(not Volley.mode(arena, 0, uid), "point defence never joins a volley")
	arena.fire(0, uid, Vector2(800.0, 0.0))
	eq(arena.ships[0].sector_open.size(), 0, "and opened no sector")


func test_the_mode_is_saved_with_the_ship_and_an_old_save_is_ripple() -> void:
	var s := Ship.new_starter()
	s.volley_groups[1] = true
	s.volley_groups[0] = true
	s.ap_guns[7] = true
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var b := Ship.new_starter()
	eq(b.load_dict(d), "", "loads")
	eq(b.volley_groups, {0: true, 1: true}, "the Volley groups come back")
	eq(b.ap_guns, {7: true}, "and the Piercing guns")
	d.erase("fire_opts")
	var c := Ship.new_starter()
	c.volley_groups[2] = true
	eq(c.load_dict(d), "", "an old save loads")
	eq([c.volley_groups, c.ap_guns], [{}, {}], "as Ripple and Standard")


func test_a_rapid_gun_never_joins_a_volley() -> void:
	_duel([1.0], true)
	arena.weapons.defs["vgr"] = {"kind": "bolt", "damage_type": "kinetic", "damage": 1, "rapid": true, "gimbal": 180, "cooldown": 0.5, "range": 2000}
	var uid := arena.add_mount(0, "vgr", Vector2(20.5, 15.5))
	check(not Volley.mode(arena, 0, uid), "a rapid gun in a Volley group still ripples")
	check(arena.fire(0, uid, Vector2(800.0, 0.0)), "it fires at once")
	arena.ships[0].ai_volley = true
	check(not Volley.mode(arena, 0, uid), "and so does an enemy's")
