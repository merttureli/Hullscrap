extends "res://tests/base_test.gd"
## A sectored bubble in a fight (shields.gd): layers per sector at `layers x weight`, a hit spending the
## sector it enters, recharge per sector, shifting (the loser drops at once, the gainer fills at the
## recharge rate), firing opening only the exit sector, overcharge, a changed sector count, what a ship
## saves, and the pilot shifting toward its foe.

const Arena = preload("res://scripts/combat/arena.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Balance = preload("res://scripts/combat/shield_balance.gd")
const CombatView = preload("res://scripts/combat/combat_view.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")

const DT := 1.0 / 60.0

var arena: Arena
var target: Ship
var big := 0  ## uid of the second generator of _duel_two()


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## A 31x31 ship (centre 15.5, 15.5) with a ring of wall cells x 5..25, y 5..25 round a floor, so the bubble is
## the same all round: the hull of the ring (5..26) inflated by 1.5.
func _ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	for c in g.hull:
		g.force_tile(c, "floor")
	for i in range(5, 26):
		for c in [Vector2i(i, 5), Vector2i(i, 25), Vector2i(5, i), Vector2i(25, i)]:
			g.force_tile(c, "wall")
	return Ship.new("t", g)


## The target (ship 1, at the origin): a reactor and a Mk1 generator patched to `layers` and `sectors`, wired.
## Ship 0 is a plain shooter, put where each test wants it, with a laser (uid `gun`) at its centre.
var gun := 0


func _duel(sectors: int, layers := 2) -> void:
	arena = Arena.new(7)
	arena.add_ship(_ship(), Vector2(0.0, -800.0))
	target = _ship()
	target.components.by_id["shield_mk1"]["stats"]["sectors"] = sectors
	target.components.by_id["shield_mk1"]["stats"]["layers"] = layers
	check(target.components.place(target.grid, "reactor_mk1", Vector2i(9, 19), 0) > 0, "reactor")
	check(target.components.place(target.grid, "shield_mk1", Vector2i(13, 19), 0) > 0, "generator")
	for x in range(9, 17):
		target.cables.place(target.grid, Vector2i(x, 20))
	arena.add_ship(target, Vector2.ZERO)
	arena.weapons.defs["zap"] = {"kind": "laser", "damage_type": "energy", "damage": 1, "arc": 360, "gimbal": 180.0, "cooldown": 0.0, "range": 3000}
	gun = arena.add_mount(0, "zap", Vector2(15.5, 15.5))


## The shooter fires one laser at the target's centre from `from` (a world point).
func _shot(from: Vector2) -> void:
	arena.ships[0].flight.pos = from
	arena.ships[0].cooldowns.clear()
	check(arena.fire(0, gun, Vector2.ZERO), "fired from %s" % str(from))


func _count(type: String) -> int:
	var n := 0
	for e in arena.events:
		if e["type"] == type:
			n += 1
	return n


func test_the_sector_count_comes_from_the_generator_and_every_sector_starts_full() -> void:
	for n in [1, 2, 4, 8]:
		_duel(n)
		var co = arena.ships[1]
		eq(co.sectors, n, "%d sectors" % n)
		eq(co.weights, Balance.even(n), "%d sectors: even weights" % n)
		eq(co.layers_cap, 2, "%d sectors: two layers a weight-1 sector holds" % n)
		var full := []
		for k in n:
			full.append(2.0)
		eq(co.sector_layers, full, "%d sectors: every one full" % n)
		eq(co.layers, 2 * n, "%d sectors: %d whole layers up in all" % [n, 2 * n])
	_duel(3)
	eq(arena.ships[1].sectors, 2, "a generator that says 3 gives 2 (only 1, 2, 4 and 8 exist)")
	_duel(1, 0)
	eq([arena.ships[1].layers_cap, arena.ships[1].layers], [0, 0], "no layers, nothing up")


func test_a_sector_holds_the_layers_times_its_weight() -> void:
	_duel(4)
	var co = arena.ships[1]
	check(Shields.set_weights(co, [1.5, 0.5, 1.0, 1.0]), "valid weights are taken")
	eq([Shields.cap_of(co, 0), Shields.cap_of(co, 1), Shields.cap_of(co, 2), Shields.cap_of(co, 3)], [3.0, 1.0, 2.0, 2.0], "capacity is the layers (2) x the weight")
	check(not Shields.set_weights(co, [2.0, 1.0, 1.0, 1.0]), "weights that do not add up are refused")
	check(not Shields.set_weights(co, [1.0, 1.0]), "so are weights for another count")
	eq(co.weights, [1.5, 0.5, 1.0, 1.0], "and nothing changed")
	_duel(2, 3)
	co = arena.ships[1]
	Shields.set_weights(co, [0.5, 1.5])
	eq([Shields.cap_of(co, 0), Shields.cap_of(co, 1)], [1.5, 4.5], "three layers at half a weight: a layer and a half")
	eq(co.sector_layers, [1.5, 3.0], "the sector that lost drops at once, to what it can hold")
	arena.step(2.1)
	eq(co.sector_layers, [1.5, 4.5], "the one that gained fills in")
	eq(co.layers, 5, "a half layer is not a layer a shot can use: 1 + 4 whole layers")
	_shot(Vector2(0.0, -800.0))  # from the bow
	eq(_count("shield"), 1, "a bow of 1.5 layers: the first shot is stopped")
	eq(co.sector_layers[0], 0.5, "leaving half a layer")
	_shot(Vector2(0.0, -800.0))
	eq(_count("shield"), 1, "which stops nothing: the second shot is not stopped")


func test_a_hit_spends_a_layer_of_the_sector_it_enters_and_only_that_one_recharges() -> void:
	_duel(4)
	var co = arena.ships[1]
	var froms := {0: Vector2(0.0, -800.0), 1: Vector2(800.0, 0.0), 2: Vector2(0.0, 800.0), 3: Vector2(-800.0, 0.0)}
	for k in 4:
		_duel(4)
		co = arena.ships[1]
		_shot(froms[k])
		eq(_count("shield"), 1, "sector %d: the bubble took it" % k)
		var want := [2.0, 2.0, 2.0, 2.0]
		want[k] = 1.0
		eq(co.sector_layers, want, "sector %d: only its layer is used" % k)
		eq(arena.events.filter(func(e): return e["type"] == "shield")[0]["sector"], k, "sector %d: and the event says which" % k)
	_duel(4)
	co = arena.ships[1]
	_shot(froms[0])
	_shot(froms[0])
	arena.step(1.0)
	_shot(froms[2])
	eq(co.sector_layers, [0.0, 2.0, 1.0, 2.0], "two layers off the bow and one off the stern")
	arena.step(1.05)  # 2.05 s after the first two
	eq(co.sector_layers, [2.0, 2.0, 1.0, 2.0], "the bow's layers are back after 2 s; the stern's one is not yet")
	arena.step(1.0)
	eq(co.sector_layers, [2.0, 2.0, 2.0, 2.0], "and the stern's a second later")
	arena.step(5.0)
	eq(co.sector_layers, [2.0, 2.0, 2.0, 2.0], "never above the capacity")


func test_a_sector_with_no_layer_lets_the_shot_through_to_the_hull() -> void:
	_duel(2)
	var co = arena.ships[1]
	Shields.set_weights(co, [2.0, 0.0])
	eq(co.sector_layers, [2.0, 0.0], "the stern's layers are gone at once")
	arena.step(2.1)
	eq(co.sector_layers, [4.0, 0.0], "and the bow's arrive: all the layers are in the bow")
	_shot(Vector2(0.0, 800.0))  # at the stern
	eq(_count("shield"), 0, "the stern has nothing to stop it")
	eq(_count("hit"), 1, "so the wall is hit")
	_shot(Vector2(0.0, -800.0))
	eq(_count("shield"), 1, "the bow does stop one")
	eq(co.sector_layers, [3.0, 0.0], "and has four layers to start with")


func test_shifting_drops_the_loser_at_once_and_fills_the_gainer_at_the_recharge_rate() -> void:
	_duel(2)
	var co = arena.ships[1]
	eq(Shields.shift(co, "up"), "", "a step toward the bow")
	eq(co.weights, [1.5, 0.5], "half a weight moved")
	eq(co.sector_layers, [2.0, 1.0], "the stern lost a layer on the spot; the bow has not got it yet")
	arena.step(1.9)
	eq(co.sector_layers, [2.0, 1.0], "1.9 s on: still not")
	arena.step(0.2)
	eq(co.sector_layers, [3.0, 1.0], "2 s on: the layer is there")
	eq(Shields.shift(co, "up"), "", "another step")
	eq([co.weights, co.sector_layers], [[2.0, 0.0], [3.0, 0.0]], "the stern is bare at once; the bow's layer is on its way")
	eq(Shields.shift(co, "up"), "Bow is at the most (2)", "a step past 2 is refused, and says why")
	eq(co.weights, [2.0, 0.0], "with nothing changed")
	arena.step(2.1)
	eq(co.sector_layers, [4.0, 0.0], "all four layers in the bow")
	Shields.reset_even(co)
	eq([co.weights, co.sector_layers], [[1.0, 1.0], [2.0, 0.0]], "End: the bow drops to its new capacity at once, the stern starts filling")
	arena.step(1.9)
	eq(co.sector_layers[1], 0.0, "slowly")
	arena.step(0.2)
	eq(co.sector_layers, [2.0, 2.0], "even again, full")
	eq(Shields.shift(co, "left"), "port and starboard need 4 sectors", "two sectors have no port")
	_duel(1)
	eq(Shields.shift(arena.ships[1], "up"), "one piece: no balance to set", "one sector: nothing to shift")


func test_a_shot_that_lands_while_a_layer_is_still_on_its_way_finds_it_missing() -> void:
	_duel(2)
	var co = arena.ships[1]
	Shields.shift(co, "up")
	Shields.shift(co, "up")  # stern bare, the bow's two new layers on their way
	_shot(Vector2(0.0, 800.0))
	eq(_count("shield"), 0, "a volley at the stern lands on an empty sector")
	eq(_count("hit"), 1, "and hits the hull")
	arena.step(2.1)
	_shot(Vector2(0.0, 800.0))
	eq(_count("shield"), 0, "and the stern stays empty: nothing was moved back")
	eq(co.sector_layers[0], 4.0, "while the bow has them all")


func test_the_exit_sector_opens_and_not_the_aim() -> void:
	_duel(4)
	var co = arena.ships[1]
	var up := arena.add_mount(1, "zap", Vector2(24.5, 6.5))  # near the north-east corner, inside the bubble
	var from := arena.tick + 1
	arena.fire(1, up, Vector2(0.0, -2000.0))  # north: out through the top, a bow sector shot
	eq(Shields.open_sectors(co, from), [true, false, false, false], "north from the north-east corner leaves through the bow sector")
	co.cooldowns.clear()
	co.sector_open = {}
	arena.fire(1, up, Vector2(2000.0, 0.0))  # east from the same spot: out through the side
	eq(Shields.open_sectors(co, arena.tick + 1), [false, true, false, false], "east leaves through the starboard sector")
	co.cooldowns.clear()
	co.sector_open = {}
	var west := arena.add_mount(1, "zap", Vector2(6.5, 24.5))  # the south-west corner
	arena.fire(1, west, Vector2(0.0, 2000.0))
	eq(Shields.open_sectors(co, arena.tick + 1), [false, false, true, false], "south from the south-west leaves through the stern sector")
	co.cooldowns.clear()
	co.sector_open = {}
	arena.fire(1, west, Vector2(-2000.0, 0.0))
	eq(Shields.open_sectors(co, arena.tick + 1), [false, false, false, true], "west leaves through the port sector")
	_duel(2)
	co = arena.ships[1]
	var side := arena.add_mount(1, "zap", Vector2(24.5, 6.5))
	arena.fire(1, side, Vector2(2000.0, 0.0))
	eq(Shields.open_sectors(co, arena.tick + 1), [true, false], "two sectors: that corner is on the bow side")
	# a shot through the open sector uses no layer; one through another is stopped
	_duel(4)
	co = arena.ships[1]
	var gun1 := arena.add_mount(1, "zap", Vector2(15.5, 10.5))
	arena.fire(1, gun1, Vector2(0.0, -2000.0))
	arena.step(DT)
	arena.ships[0].flight.pos = Vector2(0.0, -800.0)
	arena.ships[0].cooldowns.clear()
	arena.fire(0, gun, Vector2.ZERO)
	eq(_count("shield"), 0, "a shot into the bow while it is open uses no layer")
	arena.ships[0].flight.pos = Vector2(800.0, 0.0)
	arena.ships[0].cooldowns.clear()
	arena.fire(0, gun, Vector2.ZERO)
	eq(_count("shield"), 1, "but one into the starboard is stopped")


func test_overcharge_adds_layers_spread_by_the_weights() -> void:
	_duel(2)
	var co = arena.ships[1]
	Shields.set_weights(co, [1.5, 0.5])
	arena.step(2.1)
	eq(co.sector_layers, [3.0, 1.0], "settled at 3 and 1")
	eq(arena.overcharge(1), "", "overcharged")
	eq(co.layers_cap, 3, "one more layer in all")
	eq(co.sector_layers, [4.5, 1.5], "it arrives full, split 1.5 and 0.5")
	arena.step(6.1)
	eq(co.layers_cap, 2, "gone after 6 s")
	eq(co.sector_layers, [3.0, 1.0], "back to the weights' share")


func test_a_changed_sector_count_starts_again_from_even() -> void:
	arena = Arena.new(3)
	target = _ship()
	target.components.by_id["shield_mk1"]["stats"]["sectors"] = 2
	var bigdef: Dictionary = target.components.by_id["shield_mk1"].duplicate(true)
	bigdef["id"] = "shield_big"
	bigdef["stats"]["sectors"] = 4
	target.components.by_id["shield_big"] = bigdef
	check(target.components.place(target.grid, "reactor_mk1", Vector2i(9, 19), 0) > 0, "reactor")
	check(target.components.place(target.grid, "shield_mk1", Vector2i(13, 19), 0) > 0, "the two-sector generator")
	big = target.components.place(target.grid, "shield_big", Vector2i(17, 19), 0)
	check(big > 0, "the four-sector generator")
	for x in range(9, 21):
		target.cables.place(target.grid, Vector2i(x, 20))
	var i := arena.add_ship(target)
	var co = arena.ships[i]
	eq([co.sectors, co.layers_cap], [4, 2], "the better generator sets the count (the layers add: the big one says 1 too, so 2)")
	target.components.by_id["shield_big"]["stats"]["layers"] = 1
	Shields.set_weights(co, [2.0, 1.0, 0.0, 1.0])
	arena.step(2.1)
	target.components.instances[big]["status"] = "disabled"
	co.dirty = true
	arena.sync(i)
	eq([co.sectors, co.weights], [2, [1.0, 1.0]], "the four-sector generator is lost: two sectors, even weights again")
	eq(co.sector_layers.size(), 2, "and two sectors of layers")
	target.components.instances[big]["status"] = "ok"
	co.dirty = true
	arena.sync(i)
	eq([co.sectors, co.weights], [4, [1.0, 1.0, 1.0, 1.0]], "repaired: four sectors, even")
	for k in 4:
		check(co.sector_layers[k] <= Shields.cap_of(co, k) + 1e-9, "sector %d does not hold more than it can" % k)


func test_the_sectors_keep_their_fill_when_the_count_changes() -> void:
	_duel(2)
	var co = arena.ships[1]
	_shot(Vector2(0.0, -800.0))
	_shot(Vector2(0.0, -800.0))  # the bow is bare, the stern full: 2 of 4 layers up
	eq(co.sector_layers, [0.0, 2.0], "half the layers are up")
	target.components.by_id["shield_mk1"]["stats"]["sectors"] = 4
	co.dirty = true
	arena.sync(1)
	eq([co.sectors, co.layers], [4, 4], "four sectors, each with half its layers: no free refill")
	arena.step(2.1)
	eq(co.sector_layers, [2.0, 2.0, 2.0, 2.0], "the rest recharges")


func test_a_saved_balance_comes_back_and_starts_every_fight() -> void:
	var ship := _ship()
	check(ship.components.place(ship.grid, "reactor_mk1", Vector2i(9, 19), 0) > 0, "reactor")
	check(ship.components.place(ship.grid, "shield_mk2", Vector2i(13, 19), 0) > 0, "a Mk2 generator: 2 layers, 2 sectors")
	for x in range(9, 17):
		ship.cables.place(ship.grid, Vector2i(x, 20))
	ship.refresh()
	var plain := ship.to_dict()
	check(not plain.has("shield_balance"), "nothing chosen: nothing saved")
	eq(plain["version"], 5, "ship save version 5")
	ship.shield_balance["weights"] = [2.0, 0.0]
	ship.shield_balance["presets"][1] = [1.5, 0.5]
	var d := ship.to_dict()
	eq(d["shield_balance"], {"weights": [2.0, 0.0], "presets": [[], [1.5, 0.5]]}, "the balance is saved")
	var again := Ship.new("b", _ship().grid)
	eq(again.load_dict(JSON.parse_string(JSON.stringify(d))), "", "it loads")
	eq(again.shield_balance, ship.shield_balance, "with the weights and the custom slots")
	var a := Arena.new()
	var co = a.ships[a.add_ship(again)]
	eq([co.sectors, co.weights, co.sector_layers], [2, [2.0, 0.0], [4.0, 0.0]], "the fight starts with those weights, full")
	var other := Arena.new()
	var plain_co = other.ships[other.add_ship(ship)]
	eq(plain_co.weights, [2.0, 0.0], "the same ship object does too")
	ship.shield_balance["weights"] = [1.0, 1.0, 1.0, 1.0]
	var wrong := Arena.new()
	eq(wrong.ships[wrong.add_ship(ship)].weights, [1.0, 1.0], "weights for another sector count are ignored: even")
	# an old save: no balance at all, an older version
	var old := ship.to_dict()
	old.erase("shield_balance")
	old["version"] = 3
	var loaded := Ship.new("c", _ship().grid)
	loaded.shield_balance = {"weights": [0.0, 2.0], "presets": [[1.0, 1.0], []]}
	eq(loaded.load_dict(old), "", "a version 3 save loads")
	eq(loaded.shield_balance, Balance.fresh(), "its balance starts fresh: even, empty slots")
	var o := Arena.new()
	eq(o.ships[o.add_ship(loaded)].weights, [1.0, 1.0], "and fights even")
	var junk := ship.to_dict()
	junk["shield_balance"] = {"weights": "x", "presets": [7]}
	eq(loaded.load_dict(junk), "", "a damaged balance does not stop the ship loading")
	eq(loaded.shield_balance, Balance.fresh(), "it is just dropped")


func test_the_pilot_shifts_its_balance_toward_its_foe_every_interval() -> void:
	arena = Arena.new(7)
	var pilot_ship := _ship()
	pilot_ship.components.by_id["shield_mk1"]["stats"]["sectors"] = 4
	check(pilot_ship.components.place(pilot_ship.grid, "reactor_mk1", Vector2i(9, 19), 0) > 0, "reactor")
	check(pilot_ship.components.place(pilot_ship.grid, "shield_mk1", Vector2i(13, 19), 0) > 0, "generator")
	for x in range(9, 17):
		pilot_ship.cables.place(pilot_ship.grid, Vector2i(x, 20))
	arena.add_ship(pilot_ship, Vector2.ZERO)
	arena.add_ship(_ship(), Vector2(900.0, 0.0))  # the foe is to the east: the starboard side
	var co = arena.ships[0]
	var ai := PilotAI.new(arena, 0, 1)
	near(ai.aim_skill, 0.6, "the default skill is 0.6")
	near(ai.shift_interval(), 0.9, "so a step every 0.9 s")
	for i in 50:
		ai.think(DT)
		arena.step(DT)
	eq(co.weights, [1.0, 1.0, 1.0, 1.0], "0.83 s in: nothing yet")
	for i in 10:
		ai.think(DT)
		arena.step(DT)
	eq(co.weights, [1.0, 1.5, 1.0, 0.5], "0.9 s in: half a weight from the port to the starboard, which faces the foe")
	for i in 54:
		ai.think(DT)
		arena.step(DT)
	eq(co.weights, [1.0, 2.0, 1.0, 0.0], "another 0.9 s: and again")
	for i in 120:
		ai.think(DT)
		arena.step(DT)
	eq(co.weights, [1.0, 2.0, 1.0, 0.0], "past 2 it stops (the foe has not moved: still the starboard)")
	var skilled := PilotAI.new(arena, 0, 1, {"aim_skill": 0.9})
	near(skilled.shift_interval(), 0.6, "a better pilot shifts quicker")
	var rookie := PilotAI.new(arena, 0, 1, {"aim_skill": 0.0})
	near(rookie.shift_interval(), 1.5, "a worse one slower")
	# a pilot with one sector has nothing to shift
	var solo := Arena.new(1)
	solo.add_ship(_ship(), Vector2.ZERO)
	solo.add_ship(_ship(), Vector2(900.0, 0.0))
	var ai2 := PilotAI.new(solo, 0, 1)
	for i in 120:
		ai2.think(DT)
		solo.step(DT)
	eq(solo.ships[0].weights, [1.0], "no shield: no shifting")


func test_the_bow_is_sector_zero_at_any_heading_for_every_count() -> void:
	for n in [2, 4, 8]:
		_duel(n)
		var co = arena.ships[1]
		for deg in [0.0, 90.0, 37.0, -120.0]:
			co.flight.angle = deg_to_rad(deg)
			var bow := Vector2.UP.rotated(co.flight.angle)
			for k in n:
				eq(Shields.sector_of_world_dir(co, bow.rotated(TAU * k / n)), k, "%d sectors at %d degrees: %d steps round from the bow" % [n, deg, k])
			eq(Shields.sector_of_world_dir(co, bow.rotated(deg_to_rad(180.0 / n - 3.0))), 0, "%d sectors at %d degrees: just inside the bow's edge" % [n, deg])
			eq(Shields.sector_of_world_dir(co, bow.rotated(deg_to_rad(-180.0 / n + 3.0))), 0, "and on the other side")


func test_a_shot_enters_the_sector_it_meets_when_the_ship_is_turned() -> void:
	_duel(4)
	var co = arena.ships[1]
	co.flight.angle = deg_to_rad(90.0)  # turned right: its bow points east
	_shot(Vector2(800.0, 0.0))  # the shooter is to the east: the ship's bow
	eq(co.sector_layers, [1.0, 2.0, 2.0, 2.0], "a shot from the east hits the turned ship's bow sector")
	_shot(Vector2(0.0, -800.0))  # from the north: its port side
	eq(co.sector_layers, [1.0, 2.0, 2.0, 1.0], "and one from the north its port sector")


func test_the_player_balances_the_shield_from_the_session() -> void:
	var ship := _ship()
	check(ship.components.place(ship.grid, "reactor_mk1", Vector2i(9, 19), 0) > 0, "reactor")
	check(ship.components.place(ship.grid, "shield_neon_mk1", Vector2i(13, 19), 0) > 0, "the Neon Lattice: 4 sectors, 2 layers")
	for x in range(9, 17):
		ship.cables.place(ship.grid, Vector2i(x, 20))
	var s := Session.new()
	s.start(ship, Session.load_ship(Session.PIRATE_PATH), 1)
	var co = s.arena.ships[Session.PLAYER]
	eq(s.shield_sectors().map(func(x): return x["layers"]), [2.0, 2.0, 2.0, 2.0], "the diagram's numbers")
	eq(s.shift_shield("right"), "", "right: a step toward the starboard")
	eq(co.weights, [1.0, 1.5, 1.0, 0.5], "from the port")
	var parts: Array = s.shield_sectors()
	eq([parts[1]["weight"], parts[1]["cap"], parts[3]["layers"], parts[1]["filling"]], [1.5, 3.0, 1.0, true], "the diagram: the starboard fills, the port dropped at once")
	eq(s.shift_shield("up"), "", "up")
	eq(co.weights, [1.5, 1.5, 0.5, 0.5], "the stern gives")
	s.reset_shield()
	eq(co.weights, [1.0, 1.0, 1.0, 1.0], "End: even")
	var view := CombatView.new()
	view.session = s
	view.active = true
	view._unhandled_input(_key(KEY_LEFT))
	eq(co.weights, [1.0, 0.5, 1.0, 1.5], "the left arrow in the view: toward the port")
	view._unhandled_input(_key(KEY_DOWN))
	eq(co.weights, [0.5, 0.5, 1.5, 1.5], "down: the stern")
	view._unhandled_input(_key(KEY_END))
	eq(co.weights, [1.0, 1.0, 1.0, 1.0], "End in the view")
	view._unhandled_input(_key(KEY_UP))
	view._unhandled_input(_key(KEY_UP))
	view._unhandled_input(_key(KEY_UP))
	eq(co.weights, [2.0, 1.0, 0.0, 1.0], "up, up and up: the third is refused at 2")
	check(view._note.begins_with("Shield balance: "), "and the view says why: " + view._note)
	view.free()
	var plain := Session.new()
	plain.start(_ship(), Session.load_ship(Session.PIRATE_PATH), 1)
	eq(plain.shield_sectors(), [], "no generator: no diagram")
	eq(plain.shift_shield("up"), "no shield", "and nothing to shift")


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e
