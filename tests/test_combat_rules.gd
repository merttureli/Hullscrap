extends "res://tests/base_test.gd"
## Combat rules added for the playable fight: flight from helm input, open doors, ammo, jams and heat
## per shot, firing opening the shooter's shield (sectors), and the overcharge.

const Structure = preload("res://scripts/ship/structure.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const PIRATE := "res://data/ships/pirate_raider.json"


func _pirate() -> Ship:
	var s := Session.load_ship(PIRATE)
	check(s != null, "the pirate loads")
	return s


## A 31x31 ship (hull cells 0..30, centre at 15.5, 15.5) with floor everywhere.
func _ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	for c in g.hull:
		g.force_tile(c, "floor")
	return Ship.new("t", g)


## Eight wall cells near the edge of `s`, beside its middle row and column (which the shots travel along):
## the bubble hugs the solid cells, so this makes it span the whole 31x31 hull.
func _edged(s: Ship) -> Ship:
	for c in [Vector2i(1, 14), Vector2i(1, 16), Vector2i(29, 14), Vector2i(29, 16), Vector2i(14, 1), Vector2i(16, 1), Vector2i(14, 29), Vector2i(16, 29)]:
		s.grid.force_tile(c, "wall")
	return s


func _count(a: Arena, type: String, ship := -1) -> int:
	var n := 0
	for e in a.events:
		if e["type"] == type and (ship < 0 or e["ship"] == ship):
			n += 1
	return n


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## Define weapon `id` for the arena (a laser unless `d` says otherwise, any arc, no cooldown).
func _def(a: Arena, id: String, d := {}) -> void:
	var full := {"kind": "laser", "damage_type": "energy", "damage": 1, "gimbal": 180, "cooldown": 0.0, "range": 2000}
	full.merge(d, true)
	a.weapons.defs[id] = full


# --- flight and the pirate -----------------------------------------------------------------------

func test_the_pirate_is_a_flyable_armed_ship_with_two_rooms() -> void:
	var s := _pirate()
	eq(s.grid.hull.size(), 26 * 23, "26 x 23 hull cells: the 22 x 19 of its hull and mounts, and two more all round")
	eq(s.atmosphere.rooms.size(), 2, "two rooms")
	var count := {}
	for uid in s.components.instances:
		var id: String = s.components.instances[uid]["id"]
		count[id] = int(count.get(id, 0)) + 1
		check(s.power_state["powered"][uid], id + " is powered")
	eq([count.get("laser_mk1"), count.get("rattle_burst_scrap"), count.get("engine_mk1"), count.get("shield_mk1"), count.get("helm"), count.get("oxygen_gen"), count.get("reactor_mk2"), count.get("reactor_scrap_mk1")], [1, 1, 2, 1, 1, 1, 1, 1], "the parts: a fixed laser and a turret on the nose")
	var plates := 0
	var doors := 0
	for c in s.grid.tiles:
		plates += int(s.grid.tiles[c] == "scrap_plate")
		doors += int(s.grid.tiles[c] == "door")
	eq([plates, doors], [22, 2], "a scrap plate layer across the front and one 2-wide door")
	check(s.inventory.count("scrap") > 0, "cargo with scrap")
	var a := Arena.new()
	var i := a.add_ship(s)
	eq(a.ships[i].mounts.size(), 2, "a laser and a turret")
	for uid in a.ships[i].mounts:
		check(a.ships[i].mounts[uid]["pos"].y < a.ships[i].pivot.y - 2.0, "near the bow edge")
	eq(a.ships[i].layers, 1, "one shield layer")


func test_helm_input_flies_the_ship() -> void:
	var a := Arena.new()
	var i := a.add_ship(_pirate(), Vector2.ZERO)
	a.step(1.0)
	eq(a.ships[i].flight.pos, Vector2.ZERO, "no input, no motion")
	a.set_input(i, 1.0, 0.0)
	a.step(2.0)
	check(a.ships[i].flight.pos.y < -20.0, "throttle moves it toward the bow (up): %s" % str(a.ships[i].flight.pos))
	near(a.ships[i].flight.pos.x, 0.0, "straight", 1e-3)
	var v: Vector2 = a.ships[i].flight.vel
	a.set_input(i, 0.0, 1.0)
	a.step(1.5)
	check(a.ships[i].flight.angle > 0.05, "D turns clockwise")
	a.set_input(i, -1.0, 0.0)
	a.step(0.5)
	check(a.ships[i].flight.vel.length() < v.length() + 1.0, "reverse slows it")
	var dead := a.add_ship(_pirate(), Vector2(1500.0, 0.0))  # clear of the first ship: hulls that touch push each other
	a.ships[dead].ship.components.instances[a.ships[dead].ship.components.instances.keys()[0]]["status"] = "ok"
	for uid in a.ships[dead].ship.components.instances:
		if a.ships[dead].ship.components.def(a.ships[dead].ship.components.instances[uid]["id"])["family"] == "helm":
			a.ships[dead].ship.components.instances[uid]["status"] = "disabled"
	a.set_input(dead, 1.0, 0.0)
	a.step(1.0)
	eq(a.ships[dead].flight.pos, Vector2(1500.0, 0.0), "no powered helm, no flight")


# --- doors -------------------------------------------------------------------------------------------

func test_open_doors_let_shots_pass_and_closed_ones_block() -> void:
	var a := Arena.new()
	var gun_ship := a.add_ship(_ship())
	var s := _ship()
	for y in range(13, 19):
		s.grid.force_tile(Vector2i(3, y), "wall")
	check(s.grid.place_door("door", Vector2i(3, 15), Vector2i.DOWN), "a door piece in the wall")
	s.grid.force_tile(Vector2i(8, 15), "wall")
	var t := a.add_ship(s, Vector2(800.0, 0.0))
	var gun := a.add_mount(gun_ship, "laser_mk1", Vector2(20.5, 15.5))
	a.weapons.defs["laser_mk1"]["damage"] = 2  # pinned at 2: these tests are about the damage rules, not the balance numbers
	var aim := Vector2(2000.0, 0.0)
	a.ships[gun_ship].cooldowns.clear()
	check(a.fire(gun_ship, gun, aim), "fired")
	eq(s.grid.hp_of(Vector2i(3, 15)), 1.0, "the closed door took the 2 damage (3 hp)")
	eq(s.grid.hp_of(Vector2i(8, 15)), 4.0, "the wall behind it is untouched")
	s.grid.hp[Vector2i(3, 15)] = 3.0
	s.grid.set_door_open(Vector2i(3, 15), true)
	a.ships[gun_ship].cooldowns.clear()
	check(a.fire(gun_ship, gun, aim), "fired again")
	eq(s.grid.hp_of(Vector2i(3, 15)), 3.0, "the open door took nothing")
	eq(s.grid.hp_of(Vector2i(8, 15)), 2.0, "the shot flew through to the wall behind")
	check(Structure.structure_fraction(a.ships[t]) < 1.0, "and the hull took it")


# --- ammo, jams, heat ------------------------------------------------------------------------------

func test_ammo_is_consumed_and_a_gun_without_it_does_not_fire() -> void:
	var a := Arena.new()
	var i := a.add_ship(_ship())
	_def(a, "slugger", {"ammo": "slug"})
	var gun := a.add_mount(i, "slugger", Vector2(20.5, 15.5))
	var aim := Vector2(1000.0, 0.0)
	eq(a.weapons.can_fire(a, i, gun, aim), "no ammo", "none in the cargo")
	check(not a.fire(i, gun, aim), "refused")
	eq(_count(a, "shot"), 0, "and nothing was shot")
	a.ships[i].ship.inventory.add("slug", 2)
	check(a.fire(i, gun, aim), "first slug")
	eq(a.ships[i].ship.inventory.count("slug"), 1, "one used")
	check(a.fire(i, gun, aim), "second slug")
	eq(a.ships[i].ship.inventory.count("slug"), 0, "all used")
	eq(a.weapons.can_fire(a, i, gun, aim), "no ammo", "empty")
	_def(a, "plain")
	var free := a.add_mount(i, "plain", Vector2(20.5, 15.5))
	check(a.fire(i, free, aim), "a gun without ammo needs none")


func test_jam_chance_one_jams_after_one_shot_until_repaired() -> void:
	var a := Arena.new()
	var i := a.add_ship(_ship())
	_def(a, "jammer", {"jam_chance": 1.0})
	var gun := a.add_mount(i, "jammer", Vector2(20.5, 15.5))
	var aim := Vector2(1000.0, 0.0)
	check(a.fire(i, gun, aim), "the shot goes off")
	eq(_count(a, "shot"), 1, "one shot")
	eq(_count(a, "jam"), 1, "then it jams")
	eq(a.weapons.can_fire(a, i, gun, aim), "malfunction", "it stops")
	check(not a.fire(i, gun, aim), "refused")
	a.weapons.repair(a, i, gun)
	eq(a.weapons.can_fire(a, i, gun, aim), "", "a repair frees it")
	_def(a, "never", {"jam_chance": 0.0})
	var ok := a.add_mount(i, "never", Vector2(20.5, 15.5))
	for k in 20:
		check(a.fire(i, ok, aim), "no jam at 0")


func test_a_placed_weapon_jams_as_a_malfunction_and_a_repair_frees_it() -> void:
	var a := Arena.new()
	var s := _pirate()
	a.weapons.defs["laser_mk1"]["jam_chance"] = 1.0
	a.weapons.defs["laser_mk1"]["heat_per_shot"] = 12.0
	var i := a.add_ship(s)
	var uid: int = a.ships[i].mounts.keys()[0]
	var aim := Vector2(0.0, -800.0)
	eq(a.weapons.can_fire(a, i, uid, aim), "", "ready")
	check(a.fire(i, uid, aim), "fired")
	eq(s.components.instances[uid]["status"], "malfunction", "the part malfunctions")
	near(s.components.instances[uid]["heat"], 12.0, "heat per shot goes into the part")
	a.ships[i].cooldowns.clear()
	eq(a.weapons.can_fire(a, i, uid, aim), "malfunction", "it stays stopped")
	check(not a.ships[i].powered.get(uid, true), "and counts as off")
	s.repair(uid)
	eq(a.weapons.can_fire(a, i, uid, aim), "", "crew repair brings it back")
	s.components.instances[uid]["status"] = "overheated"
	eq(a.weapons.can_fire(a, i, uid, aim), "overheated", "an overheated part is refused too")


func test_the_arena_follows_changes_the_ship_sim_makes() -> void:
	var a := Arena.new()
	var s := _pirate()
	var i := a.add_ship(s)
	var thrust: float = a.ships[i].thrust
	check(thrust > 0.0, "engines give thrust")
	for uid in s.components.instances:
		if s.components.instances[uid]["id"] == "engine_mk1":
			s.components.instances[uid]["status"] = "malfunction"  # as Reliability would
	s.refresh()  # ShipSim refreshes the ship itself: the arena must still notice
	a.sync(i)
	near(a.ships[i].thrust, 0.0, "both engines out")
	a.set_input(i, 1.0, 0.0)
	a.step(0.5)
	eq(a.ships[i].flight.pos, Vector2.ZERO, "so it cannot move")


# --- shields: sectors and the drop on firing --------------------------------------------------

## Ship 1 at the origin (reactor, `shields` shield parts wired, `sectors` per generator), with a wall
## at (15, 3) near its bow; ship 0 north and ship 2 south of it, `gap` px away, each with a bolt.
## Returns the arena. Mounts: the bow laser of ship 1 is uid `laser`, the shooters' bolts `north`, `south`.
var laser := 0
var north := 0
var south := 0
var gap := 620.0


func _duel(sectors: int, shields := 1) -> Arena:
	var a := Arena.new(3)
	var t := _edged(_ship())
	t.grid.force_tile(Vector2i(15, 3), "wall")
	check(t.components.place(t.grid, "reactor_mk1", Vector2i(9, 19), 0) > 0, "reactor")
	for k in shields:
		check(t.components.place(t.grid, "shield_mk1", Vector2i(13 + 4 * k, 19), 0) > 0, "shield")
		t.components.by_id["shield_mk1"]["stats"]["sectors"] = sectors
		for k2 in {"layer_hp": 2.0, "regen_delay": 0.0, "regen_rate": 2.0 / 7.0, "break_delay": 3.0}:  # a layer is 2 HP: one test_bolt; 7 s a layer
			t.components.by_id["shield_mk1"]["stats"][k2] = {"layer_hp": 2.0, "regen_delay": 0.0, "regen_rate": 2.0 / 7.0, "break_delay": 3.0}[k2]
	for x in range(9, 13 + 4 * shields):
		t.cables.place(t.grid, Vector2i(x, 20))
	a.add_ship(_ship(), Vector2(0.0, -gap))
	a.add_ship(t, Vector2.ZERO)
	a.add_ship(_ship(), Vector2(0.0, gap))
	north = a.add_mount(0, "test_bolt", Vector2(15.5, 15.5))
	south = a.add_mount(2, "test_bolt", Vector2(15.5, 15.5))
	laser = a.add_mount(1, "laser_mk1", Vector2(15.5, 10.5))  # 5 cells toward the bow
	return a


func test_sector_maths_at_any_heading() -> void:
	var a := _duel(4)
	var co = a.ships[1]
	eq(co.sectors, 4, "four sectors")
	eq([Shields.sector_of(co, Vector2(0, -1)), Shields.sector_of(co, Vector2(1, 0)), Shields.sector_of(co, Vector2(0, 1)), Shields.sector_of(co, Vector2(-1, 0))], [0, 1, 2, 3], "bow, then clockwise")
	eq([Shields.sector_of(co, Vector2(0.9, -1)), Shields.sector_of(co, Vector2(-0.9, -1)), Shields.sector_of(co, Vector2(1, -0.9))], [0, 0, 1], "sector 0 spans 45 degrees either side of the bow")
	eq(Shields.sector_of(co, Vector2.ZERO), 0, "no direction, sector 0")
	for deg in [0.0, 90.0, 37.0]:
		co.flight.angle = deg_to_rad(deg)
		var bow := Vector2.UP.rotated(co.flight.angle)
		for k in 4:
			eq(Shields.sector_of_world_dir(co, bow.rotated(deg_to_rad(90.0 * k))), k, "%d degrees: %d quarter turns off the bow" % [deg, k])
		eq(Shields.sector_of_world_dir(co, bow.rotated(deg_to_rad(44.0))), 0, "%d degrees: 44 degrees is still the bow" % deg)
		eq(Shields.sector_of_world_dir(co, bow.rotated(deg_to_rad(-46.0))), 3, "%d degrees: 46 degrees to port" % deg)
	var eight := _duel(8)
	eq(Shields.sector_of(eight.ships[1], Vector2(1, -1)), 1, "eight sectors: 45 degrees is sector 1")
	eq(Shields.sector_of(eight.ships[1], Vector2(1, -0.5)), 1, "and 63 degrees too")
	eq(Shields.sector_of(eight.ships[1], Vector2(1, 0.3)), 2, "107 degrees is sector 2")


func test_the_best_powered_generator_sets_the_sector_count() -> void:
	eq(_duel(4, 2).ships[1].sectors, 4, "two powered generators of 4 sectors")
	var ship := _ship()
	var big: Dictionary = ship.components.by_id["shield_mk1"].duplicate(true)  # a test-only Mk3
	big["id"] = "shield_big"
	big["stats"]["sectors"] = 8
	ship.components.by_id["shield_big"] = big
	ship.components.by_id["shield_mk1"]["stats"]["sectors"] = 4
	check(ship.components.place(ship.grid, "reactor_mk1", Vector2i(9, 19), 0) > 0, "reactor")
	check(ship.components.place(ship.grid, "shield_mk1", Vector2i(13, 19), 0) > 0, "Mk1 shield")
	var mk3 := ship.components.place(ship.grid, "shield_big", Vector2i(17, 19), 0)
	check(mk3 > 0, "Mk3 shield")
	for x in range(9, 17):
		ship.cables.place(ship.grid, Vector2i(x, 20))  # reaches the Mk1 only
	var a := Arena.new()
	var i := a.add_ship(ship)
	eq(a.ships[i].sectors, 4, "the unpowered 8-sector generator does not count")
	for x in range(17, 21):
		ship.cables.place(ship.grid, Vector2i(x, 20))
	a.ships[i].dirty = true
	a.sync(i)
	eq(a.ships[i].sectors, 8, "wired, it does")
	ship.components.instances[mk3]["status"] = "disabled"
	a.sync(i)
	eq(a.ships[i].sectors, 4, "and a disabled one stops counting")
	var plain := Arena.new()
	eq(plain.ships[plain.add_ship(_ship())].sectors, 1, "a ship with no shield has one sector")


func _fire_all_north_south(a: Arena) -> void:
	a.fire(0, north, Vector2(0.0, 0.0))  # the northern bolt flies south at the bow
	a.fire(2, south, Vector2(0.0, 0.0))  # the southern one flies north at the stern


func test_firing_a_bow_laser_opens_only_the_bow_sector() -> void:
	var a := _duel(4)
	check(a.fire(1, laser, Vector2(0.0, -2000.0)), "the bow laser fires")
	check(Shields.sector_open(a.ships[1], 0, a.tick + 1), "sector 0 opens on the next tick")
	for s in [1, 2, 3]:
		check(not Shields.sector_open(a.ships[1], s, a.tick + 1), "sector %d stays closed" % s)
	check(not Shields.sector_open(a.ships[1], 0, a.tick), "not on the tick of the shot: what is in contact now is resolved first")
	_fire_all_north_south(a)
	a.step(1.0)
	eq(_count(a, "shield", 1), 1, "the stern bolt met a closed sector and used a layer")
	check(_count(a, "hit", 1) >= 1, "the bow bolt passed the open sector and hit the hull")
	eq(a.ships[1].sector_layers, [1.0, 1.0, 0.0, 1.0], "the stern's one layer is used and not back yet; the other sectors keep theirs")
	eq(a.ships[1].layers, 3, "three whole layers up")


func test_with_one_sector_the_whole_bubble_opens() -> void:
	var a := _duel(1)
	check(a.fire(1, laser, Vector2(0.0, -2000.0)), "fired")
	check(Shields.sector_open(a.ships[1], 0, a.tick + 1), "the bubble is open")
	_fire_all_north_south(a)
	a.step(1.0)
	eq(_count(a, "shield", 1), 0, "no layer used, from either side")
	eq(a.ships[1].layers, 1, "the layer stayed")


func test_the_bubble_closes_when_the_window_ends() -> void:
	var a := _duel(1)
	a.fire(1, laser, Vector2(0.0, -2000.0))
	a.step(0.4)  # a laser opens it for 0.3 s
	check(not Shields.sector_open(a.ships[1], 0, a.tick), "closed again")
	a.fire(2, south, Vector2(0.0, 0.0))
	a.step(1.0)
	eq(_count(a, "shield", 1), 1, "a bolt after the window is stopped")
	eq(a.ships[1].layers, 0, "and used the layer")


func test_a_bolt_in_flight_passes_while_open_and_not_before_or_after() -> void:
	var a := _duel(1)
	a.fire(2, south, Vector2(0.0, 0.0))  # contact after about 6 ticks
	a.fire(1, laser, Vector2(0.0, -2000.0))  # opens ticks 1..18
	a.step(0.5)
	eq(_count(a, "shield", 1), 0, "the bolt reached the bubble inside the window")
	var b := _duel(1)
	b.fire(1, laser, Vector2(0.0, -2000.0))
	b.step(0.5)
	b.fire(0, north, Vector2(0.0, 0.0))
	b.step(1.0)
	eq(_count(b, "shield", 1), 1, "the same bolt after the window is blocked")


func test_missiles_never_drop_the_shield_and_data_overrides_the_default() -> void:
	var a := _duel(1)
	var rocket := a.add_mount(1, "test_missile", Vector2(15.5, 10.5))
	check(a.fire(1, rocket, Vector2(0.0, -2000.0)), "a missile is launched")
	check(not Shields.sector_open(a.ships[1], 0, a.tick + 1), "and the bubble stays shut")
	var secs := {}
	for k in ["laser", "bolt", "flak", "missile"]:
		secs[k] = Shields.drop_seconds({"kind": k, "damage_type": "kinetic"})
	eq(secs, {"laser": 0.3, "bolt": 0.4, "flak": 0.6, "missile": 0.0}, "defaults by kind")
	eq(Shields.drop_seconds({"kind": "bolt", "damage_type": "ion"}), 0.3, "ion damage is 0.3")
	eq(Shields.drop_seconds({"kind": "beam", "duration": 2.5}), 2.5, "a beam: its whole duration")
	eq(Shields.drop_seconds({"kind": "laser", "drops_shield_s": 1.0}), 1.0, "the entry wins")
	eq(Shields.drop_seconds({"kind": "missile", "drops_shield_s": 1.0}), 0.0, "missiles never")
	_def(a, "long_laser", {"drops_shield_s": 1.0})
	var gun := a.add_mount(1, "long_laser", Vector2(15.5, 10.5))
	a.fire(1, gun, Vector2(0.0, -2000.0))
	var from: int = a.tick + 1
	check(Shields.sector_open(a.ships[1], 0, from + 59), "open for the 1 s of the entry")
	check(not Shields.sector_open(a.ships[1], 0, from + 60), "and not a tick longer")


func test_overlapping_windows_run_to_the_latest_end() -> void:
	var a := _duel(1)
	_def(a, "flak_like", {"kind": "flak", "damage_type": "kinetic", "speed": 600.0, "shots": 1})
	var flak := a.add_mount(1, "flak_like", Vector2(15.5, 10.5))
	a.fire(1, laser, Vector2(0.0, -2000.0))  # 0.3 s from tick 1: ticks 1..18
	a.step(0.1)
	a.fire(1, flak, Vector2(0.0, -2000.0))  # 0.6 s from tick 7: until tick 6 + 36 = 42
	var co = a.ships[1]
	check(Shields.sector_open(co, 0, 42), "open to the later end")
	check(not Shields.sector_open(co, 0, 43), "and no longer")
	a.step(0.15)
	a.ships[1].cooldowns.clear()
	a.fire(1, laser, Vector2(0.0, -2000.0))  # would end at 15 + 18 = 33: the later end stays
	check(Shields.sector_open(co, 0, 42) and not Shields.sector_open(co, 0, 43), "a shorter window does not shorten it")


func test_a_beam_holds_its_sector_open_for_its_duration() -> void:
	var a := _duel(4)
	_def(a, "burner", {"kind": "beam", "duration": 2.0, "tick": 0.25, "damage": 1})
	var gun := a.add_mount(1, "burner", Vector2(15.5, 10.5))
	a.fire(1, gun, Vector2(0.0, -2000.0))
	var from: int = a.tick + 1
	check(Shields.sector_open(a.ships[1], 0, from + 119), "open for 2 s")
	check(not Shields.sector_open(a.ships[1], 0, from + 120), "then closed")
	check(not Shields.sector_open(a.ships[1], 2, from + 10), "the stern stays shut")


func test_overcharge_adds_a_layer_for_six_seconds_then_a_cooldown() -> void:
	var a := _duel(1)
	eq(a.ships[1].layers, 1, "one layer to begin with")
	eq(a.overcharge(1), "", "overcharged")
	eq([a.ships[1].layers, a.ships[1].layers_cap], [2, 2], "one extra layer")
	eq(a.overcharge(1), "already overcharged", "not twice")
	a.step(5.9)
	eq(a.ships[1].layers, 2, "still there after 5.9 s")
	a.step(0.2)
	eq([a.ships[1].layers, a.ships[1].layers_cap], [1, 1], "gone after 6 s")
	eq(a.overcharge(1), "cooling down", "the cooldown is respected")
	var rest := float(a.ships[1].ship.components.def("shield_mk1")["abilities"][0]["cooldown"])  # the Overcharge ability's data
	a.step(rest - 0.5)
	eq(a.overcharge(1), "cooling down", "still resting")
	a.step(0.6)
	eq(a.overcharge(1), "", "ready again")
	eq(a.ships[1].layers, 2, "and the layer is back")
	var plain := Arena.new()
	var i := plain.add_ship(_ship())
	eq(plain.overcharge(i), "no shield", "nothing to overcharge without a generator")
	var b := _duel(1)
	b.overcharge(1)
	b.fire(2, b.add_mount(2, "test_bolt", Vector2(15.5, 15.5)), Vector2(0.0, 0.0))
	b.step(0.6)  # the extra layer takes the bolt
	eq(_count(b, "shield", 1), 1, "the overcharge layer absorbs a hit")
	check(float(b.ships[1].sector_layers[0]) < 1.2, "and a layer's HP is gone from the pool (%s layers left)" % b.ships[1].sector_layers[0])
	b.step(6.0)
	check(b.ships[1].layers <= b.ships[1].layers_cap, "and nothing is left over when it ends")
