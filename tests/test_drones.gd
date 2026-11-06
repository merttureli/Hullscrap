extends "res://tests/base_test.gd"
## The drone bay and the drones (docs/DRONES.md): placing a bay by the mount rules, one drone per bay, the part cost and the re-arm, the orbit staying
## in its band, point defence and flak shooting drones, a recall on no power, the saved kit, the enemy bay and its launch, and the same seed giving
## the same fight.

const Arena = preload("res://scripts/combat/arena.gd")
const Drones = preload("res://scripts/combat/drones.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Projectiles = preload("res://scripts/combat/projectiles.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const WeaponBar = preload("res://scripts/ui/weapon_bar.gd")
const GunBadges = preload("res://scripts/ui/gun_badges.gd")


func _ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	for c in g.hull:
		var edge := false
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			edge = edge or not g.hull.has(c + d)
		g.force_tile(c, "wall" if edge else "floor")
	return Ship.new("t", g)


## Two ships 1200 px apart, ship 0 with a virtual bay holding `kit`, with parts.
func _duel(kit: String, bay := "drone_bay_mk3", parts := 10) -> Array:
	var a := Arena.new(7)
	var p := _ship()
	p.inventory.add(PART, parts)
	p.inventory.add(kit, 1)
	a.add_ship(p, Vector2.ZERO, 0.0)
	a.add_ship(_ship(), Vector2(0.0, -1200.0), PI)
	var uid := Drones.add_bay(a, 0, bay, kit, Vector2(15.5, 4.5))
	return [a, uid]


const PART := "drone_part"


func test_kits_and_bays_are_data() -> void:
	eq(Drones.kit_ids().filter(func(id): return Drones.kit(id)["drone"]["role"] in ["combat", "defence"]).size(), 7, "seven combat and defence kits")
	for id in Drones.kit_ids():
		var k := Drones.kit(id)
		if k["drone"]["role"] in ["combat", "defence"]:
			check(k["drone"]["hp"] == [0, 3, 5, 8][int(k["drone"]["tier"])], "%s hp by tier" % id)
	var s := _ship()
	for id in ["drone_bay_mk1", "drone_bay_mk2", "drone_bay_mk3"]:
		var d := s.components.def(id)
		eq(d["size"], [3, 3], id + " inside")
		eq(d["mount"]["outside"], [3, 1], id + " outside")
	eq([s.components.def("drone_bay_mk1")["bay"]["rearm_s"], s.components.def("drone_bay_mk2")["bay"]["rearm_s"], s.components.def("drone_bay_mk3")["bay"]["rearm_s"]], [12.0, 9.0, 6.0], "re-arm")


func test_launch_costs_parts_and_one_drone_per_bay() -> void:
	var r := _duel("laser_drone_mk2")
	var a: Arena = r[0]
	var uid: int = r[1]
	eq(a.launch_drone(0, uid), "", "launches")
	eq(a.ships[0].ship.inventory.count(PART), 8, "tier 2 costs 2 parts")
	eq(a.launch_drone(0, uid), "drone out", "one drone per bay")
	eq(a.drones.size(), 1, "one drone")
	var r2 := _duel("pulse_drone_mk1", "drone_bay_mk1", 0)
	eq(r2[0].launch_drone(0, r2[1]), "no parts", "refused with no parts")
	var r3 := _duel("beam_drone_mk3", "drone_bay_mk2")
	eq(r3[0].launch_drone(0, r3[1]), "bay too small", "a Mk II bay does not launch tier 3")
	var r4 := _duel("pulse_drone_mk1")
	eq(r4[0].launch_drone(0, r4[1]), "", "pulse")
	eq(r4[0].ships[0].ship.inventory.count(PART), 9, "tier 1 costs 1")
	var r5 := Drones.add_bay(r4[0], 0, "drone_bay_mk1", "", Vector2(5, 5))
	eq(r4[0].launch_drone(0, r5), "no kit", "an empty bay")


func test_rearm_after_a_loss() -> void:
	var r := _duel("pulse_drone_mk1", "drone_bay_mk1")
	var a: Arena = r[0]
	a.launch_drone(0, r[1])
	Drones.damage(a, a.drones[0], 99.0)
	check(a.drones.is_empty(), "the drone is gone")
	eq(a.launch_drone(0, r[1]), "re-arming", "a Mk I bay waits")
	check(absf(Drones.ready_in(a, 0, r[1]) - 12.0) < 0.05, "12 s")
	a.step(11.9)
	eq(a.launch_drone(0, r[1]), "re-arming", "still waiting")
	a.step(0.2)
	eq(a.launch_drone(0, r[1]), "", "ready after 12 s")


func test_orbit_stays_in_its_band() -> void:
	var r := _duel("laser_drone_mk2")
	var a: Arena = r[0]
	a.launch_drone(0, r[1])
	var d: Dictionary = a.drones[0]
	var o: Dictionary = d["orbit"]
	var ring := Drones.ring_radius(a, 1)
	var lo := INF
	var hi := 0.0
	var moved := 0.0
	var last: Vector2 = d["pos"]
	for i in 600:
		a.step(1.0 / 20.0)
		if a.drones.is_empty():
			break
		if i > 80:
			var dist: float = Vector2(d["pos"]).distance_to(a.ships[1].flight.pos)
			lo = minf(lo, dist)
			hi = maxf(hi, dist)
			moved += Vector2(d["pos"]).distance_to(last) / 20.0 * 20.0
		last = d["pos"]
	var gap := float(o["gap"])
	var wv := float(o["weave"])
	check(lo >= ring + gap - 1.5 * wv - 40.0, "never inside its band: %.0f of %.0f" % [lo, ring + gap - 1.5 * wv])
	check(hi <= ring + gap + 1.5 * wv + 40.0, "never outside its band: %.0f of %.0f" % [hi, ring + gap + 1.5 * wv])
	check(moved > 600.0, "always moving: %.0f px" % moved)


func test_the_bay_is_a_hull_mount_placed_by_the_mount_rules() -> void:
	var ship = Shipgen.build("concord", "medium", 41, 120.0)
	var bay := "drone_bay_mk2"
	var def: Dictionary = ship.components.def(bay)
	check(Mounts.is_mount(def) and Mounts.is_low(def), "a mount, and a low hatch (3x1 sticks out one cell)")
	eq(Mounts.turned(def["mount"]["outside"], 0), Vector2i(3, 1), "outside 3x1")
	# open floor with no wall: refused by the mount rules
	var open := _ship()
	check(open.components.can_place_mount(open.grid, bay, Vector2i(14, 14), 0) != "", "no wall, no mount")
	var uid := -1
	for t in 6:
		ship = Shipgen.build("concord", "medium", 41 + t, 120.0)
		uid = Shipgen.add_bay(ship, bay, "pulse_drone_mk1")
		if uid >= 0:
			break
	check(uid >= 0, "a bay mounts through a wall of a generated ship")
	if uid >= 0:
		check(ship.components.has_outside(uid) and ship.components.link_intact(ship.grid, uid), "its two halves and the link are whole")
		check(ship.power_state["powered"].get(uid, false), "and it is powered")
		eq(ship.components.instances[uid]["kit"], "pulse_drone_mk1", "the kit is loaded")
		eq(Shipgen.validate(ship), [], "the ship is still valid")


func test_the_kit_is_chosen_checked_and_saved() -> void:
	var ship = Shipgen.build("concord", "large", 5, 300.0)
	var uid := Shipgen.add_bay(ship, "drone_bay_mk2", "")
	for t in 8:
		if uid >= 0:
			break
		ship = Shipgen.build("concord", "large", 6 + t, 300.0)
		uid = Shipgen.add_bay(ship, "drone_bay_mk2", "")
	check(uid >= 0, "a bay")
	eq(Drones.set_kit(ship, uid, "laser_drone_mk2"), "none in the hold", "a kit the hold lacks is refused")
	ship.inventory.add("laser_drone_mk2", 1)
	ship.inventory.add("beam_drone_mk3", 1)
	eq(Drones.set_kit(ship, uid, "beam_drone_mk3"), "needs a Mk III bay", "a Mk II bay refuses tier 3")
	eq(Drones.set_kit(ship, uid, "laser_drone_mk2"), "", "loads")
	var back = Ship.new("b", ShipGrid.new(Vector2i(ship.grid.size), ship.grid.defs))
	eq(back.load_dict(ship.to_dict()), "", "the ship loads again")
	eq(back.components.instances[uid].get("kit", ""), "laser_drone_mk2", "the loaded kit survives the save")
	eq(Drones.set_kit(ship, uid, ""), "", "unloads")
	check(not ship.components.instances[uid].has("kit"), "empty")


func test_point_defence_and_flak_shoot_drones() -> void:
	var r := _duel("flak_drone_mk3")  # the player's drone circles the enemy
	var a: Arena = r[0]
	a.launch_drone(0, r[1])
	var d: Dictionary = a.drones[0]
	# the enemy has a point-defence turret (human_flak_screen) and a flak turret that can reach the drone
	for at in [Vector2(15.5, 1.0), Vector2(15.5, 30.0), Vector2(1.0, 15.5), Vector2(30.0, 15.5)]:  # on the hull's edge all round, pointing out
		a.add_mount(1, "human_flak_screen", at, true)
		a.add_mount(1, "grundl_barge_flak", at, true)
	var hp0 := float(d["hp"])
	var min_hp := hp0
	for i in 900:
		a.step(1.0 / 20.0)
		if a.drones.is_empty():
			break
		min_hp = minf(min_hp, float(d["hp"]))
	check(a.drones.is_empty() or min_hp < hp0, "the enemy's PD and flak hurt the drone: %.1f of %.1f" % [min_hp, hp0])
	check(a.events.any(func(e): return e["type"] == "drone_hit"), "drone_hit events were logged")


func test_defence_drones_shoot_missiles_and_enemy_drones() -> void:
	var a := Arena.new(3)
	var p := _ship()
	p.inventory.add(PART, 10)
	p.inventory.add("defence_drone_mk2", 1)
	a.add_ship(p, Vector2.ZERO, 0.0)
	var e := _ship()
	e.inventory.add(PART, 10)
	e.inventory.add("pulse_drone_mk1", 1)
	a.add_ship(e, Vector2(0.0, -900.0), PI)
	var mine := Drones.add_bay(a, 0, "drone_bay_mk2", "defence_drone_mk2", Vector2(15.5, 4.5))
	var theirs := Drones.add_bay(a, 1, "drone_bay_mk1", "pulse_drone_mk1", Vector2(15.5, 4.5))
	eq(a.launch_drone(0, mine), "", "defence drone out")
	eq(a.launch_drone(1, theirs), "", "enemy drone out")
	var ring := Drones.ring_radius(a, 0)
	var shot := false
	for i in 400:
		a.step(1.0 / 20.0)
		if a.drones.size() == 2 and not shot:
			var md = Drones.out_of(a, 0, mine)
			check(Vector2(md["pos"]).distance_to(a.ships[0].flight.pos) < ring + 260.0, "a defence drone stays by its own ship")
		if a.events.any(func(ev): return ev["type"] == "drone_shot" and ev["kind"] == "pd"):
			shot = true
	check(shot, "the defence drone shot at the enemy's drone")
	# and a missile
	var m := Arena.new(4)
	var p2 := _ship()
	p2.inventory.add(PART, 5)
	p2.inventory.add("defence_drone_mk1", 1)
	m.add_ship(p2, Vector2.ZERO, 0.0)
	m.add_ship(_ship(), Vector2(0.0, -900.0), PI)
	var b2 := Drones.add_bay(m, 0, "drone_bay_mk1", "defence_drone_mk1", Vector2(15.5, 4.5))
	m.launch_drone(0, b2)
	m.step(1.5)
	var killed := 0
	for k in 12:
		var w: Dictionary = m.weapons.def("test_missile")
		var dpos: Vector2 = m.drones[0]["pos"]
		var pos: Vector2 = dpos + (m.ships[0].flight.pos - dpos).normalized().rotated(1.0) * 110.0
		m.projectiles.append({"owner": 1, "w": w, "pos": pos, "vel": Vector2(0.0, 20.0), "left": 500.0, "target": -1, "bounces": 0, "skip": {}})
		var before := m.projectiles.size()
		for i in 60:
			m.step(1.0 / 20.0)
			if not m.projectiles.has(m.projectiles.back()) if not m.projectiles.is_empty() else true:
				break
		killed += 1 if m.projectiles.size() < before else 0
		m.projectiles.clear()
		m.step(1.6)
	check(killed >= 3, "the defence drone shot down missiles: %d of 12" % killed)


func test_no_power_recalls_the_drone_and_the_fight_end_does() -> void:
	var r := _duel("pulse_drone_mk1", "drone_bay_mk1")
	var a: Arena = r[0]
	a.launch_drone(0, r[1])
	a.step(1.0)
	a.ships[0].bays[r[1]]["powered"] = false
	a.step(0.1)
	eq(a.drones[0]["state"], "home", "no power: the drone is recalled")
	a.ships[0].bays[r[1]]["powered"] = true
	a.step(14.0)
	check(a.drones.is_empty(), "it docked")
	eq(a.ships[0].bays[r[1]]["drone"], null, "the bay is free")
	eq(a.ships[0].ship.inventory.count(PART), 9, "the part is spent")
	eq(a.launch_drone(0, r[1]), "", "and it can launch again at once")
	a.step(0.5)
	Drones.recall_all(a)
	check(a.drones[0]["state"] == "home", "the end of a fight recalls it")


func test_the_enemy_bay_and_its_launch() -> void:
	var found = null
	for k in 60:
		var ship = Shipgen.from_spec(Shipgen.spec("kett", "large", 100 + k, 300.0, false, 3))
		if ship != null and not Drones.bays_of(ship).is_empty():
			found = ship
			break
	check(found != null, "some generated enemies carry a bay")
	if found == null:
		return
	check(found.inventory.count(PART) >= 4, "with parts")
	var uid: int = Drones.bays_of(found).keys()[0]
	check(Drones.kit(str(found.components.instances[uid]["kit"])).size() > 0, "and a kit")
	var a := Arena.new(9)
	a.add_ship(_ship(), Vector2.ZERO, 0.0)
	a.add_ship(found, Vector2(0.0, -1100.0), PI)
	var ai := PilotAI.new(a, 1, 0, found.get_meta("ai", {}))
	for i in 600:
		ai.think(1.0 / 60.0)
		a.step(1.0 / 60.0)
	check(not Drones.of_ship(a, 1).is_empty() or a.events.any(func(e): return e["type"] == "drone_launch"), "the enemy AI launched")
	# a late fight still names the stage 1 enemies without a bay
	var none := 0
	for k in 20:
		var s1 = Shipgen.from_spec(Shipgen.spec("kett", "large", 200 + k, 300.0, false, 1))
		none += 1 if s1 != null and Drones.bays_of(s1).is_empty() else 0
	eq(none, 20, "stage 1 enemies have no bay")


func _fight(seed_value: int) -> Dictionary:
	var a := Arena.new(seed_value)
	var p := _ship()
	p.inventory.add(PART, 10)
	p.inventory.add("laser_drone_mk2", 1)
	a.add_ship(p, Vector2.ZERO, 0.0)
	a.add_ship(_ship(), Vector2(0.0, -1000.0), PI)
	var u := Drones.add_bay(a, 0, "drone_bay_mk3", "laser_drone_mk2", Vector2(15.5, 4.5))
	a.add_mount(1, "human_flak_screen", Vector2(15.5, 15.5), true)
	a.launch_drone(0, u)
	for i in 600:
		a.step(1.0 / 20.0)
	return a.snapshot()


func test_the_same_seed_gives_the_same_fight() -> void:
	eq(str(_fight(11)), str(_fight(11)), "the same seed, the same fight")
	check(str(_fight(11)) != str(_fight(12)), "another seed differs")


func test_a_drone_shoots_the_ship_and_loses_hp_to_a_shot_that_crosses_it() -> void:
	var r := _duel("pulse_drone_mk1", "drone_bay_mk1")
	var a: Arena = r[0]
	a.launch_drone(0, r[1])
	a.step(12.0)
	check(a.events.any(func(e): return e["type"] == "drone_shot"), "the drone fires")
	for i in 20:
		if a.events.any(func(e): return e["type"] == "hit" and e["ship"] == 1):
			break
		a.step(5.0)
	check(a.events.any(func(e): return e["type"] == "hit" and e["ship"] == 1), "and its shot hits the enemy ship")
	var d: Dictionary = a.drones[0]
	var hp := float(d["hp"])
	var dir: Vector2 = Vector2(1.0, 0.3).normalized()
	Projectiles.spawn(a, 1, a.weapons.def("test_bolt"), Vector2(d["pos"]) - dir * 60.0, dir)
	a.step(0.2)
	check(float(d["hp"]) < hp or a.drones.is_empty(), "a shot that crosses a drone hurts it")


func test_the_bay_is_a_slot_with_its_key_and_a_group_on_the_weapon_bar() -> void:
	var player = null
	var uid := -1
	for t in 10:
		player = Shipgen.build("concord", "large", 70 + t, 300.0)
		uid = Shipgen.add_bay(player, "drone_bay_mk2", "laser_drone_mk2")
		if uid >= 0:
			break
	check(uid >= 0, "a player ship with a bay")
	if uid < 0:
		return
	player.inventory.add("laser_drone_mk2", 1)
	player.inventory.add(PART, 5)
	var s := Session.new()
	s.start(player, Shipgen.build("rustfangs", "medium", 3, 100.0), 5)
	var guns: int = s.weapons().size()
	eq(s.bays().size(), 1, "one bay slot")
	eq(s.bay_state(uid)["status"], "ready", "ready")
	eq(s.bay_state(uid)["cost"], 2, "tier 2 costs 2 parts")
	var bar := WeaponBar.new()
	bar.bind(s, func() -> Vector2: return Vector2.ZERO)
	var lay := bar.layout()
	check(lay.has("bay_head") and lay["bay_slots"].any(func(sl): return sl["number"] == guns + 1), "a DRONES header with the bay at the key after the guns")
	check(not lay["slots"].any(func(sl): return sl.has("bay")) and not lay["zones"].any(func(z): return z["group"] == 4), "the bay is in no fire group and has no drop zone")
	check(s.fire_slot(guns + 1, Vector2.ZERO), "its key launches")
	eq(s.bay_state(uid)["status"], "drone out", "now out")
	check(not s.fire_slot(guns + 1, Vector2.ZERO), "and a second press does nothing")
	eq(s.bay_state(uid)["parts"], 3, "the parts were spent")
	bar.free()


func test_a_launched_drone_waits_hidden_in_the_bay_then_shows_in_the_open_hatch() -> void:
	var r := _duel("laser_drone_mk2")
	var a: Arena = r[0]
	a.launch_drone(0, r[1])
	var d: Dictionary = a.drones[0]
	var hatch: Vector2 = a.local_to_world(0, a.ships[0].bays[r[1]]["pos"])
	a.step(0.25)
	check(Vector2(d["pos"]).distance_to(hatch) < 1.0, "held at the hatch mouth, no motion while hidden")
	var before := float(d["hp"])
	check(Drones.contact(a, 1, hatch + Vector2(-30, 0), hatch + Vector2(30, 0)).is_empty(), "nothing hits a drone that is still inside")
	check(not a.events.any(func(e): return e["type"] == "drone_emerge"), "no puff before it shows")
	a.step(0.1)
	check(a.events.filter(func(e): return e["type"] == "drone_emerge").size() == 1, "it shows at 0.3 s with one puff")
	eq(before, float(d["hp"]), "unhurt")
	check(absf(Drones.scale_of(a, d) - Drones.DOCKED_SCALE) < 0.1, "it leaves at the size it had on the cradle")
	a.step(0.5)
	check(Drones.scale_of(a, d) > 0.99, "and grows to full size")


func test_a_drone_bay_cannot_be_put_in_a_fire_group() -> void:
	var player = null
	var uid := -1
	for t in 10:
		player = Shipgen.build("concord", "large", 70 + t, 300.0)
		uid = Shipgen.add_bay(player, "drone_bay_mk2", "laser_drone_mk2")
		if uid >= 0:
			break
	check(uid >= 0, "a ship with a bay")
	if uid < 0:
		return
	player.inventory.add("laser_drone_mk2", 1)
	player.inventory.add(PART, 5)
	var s := Session.new()
	s.start(player, Shipgen.build("rustfangs", "medium", 3, 100.0), 5)
	var ws = s.arena.weapons
	for g in [0, 1, 2, 3]:
		eq(GunBadges.assign(player.components, ws, uid, g), -1, "assign to group %d is refused" % g)
	eq(GunBadges.cycle(player.components, ws, uid), -1, "a right-click cycle is refused")
	player.components.set_group_choice(uid, 2)
	eq(player.components.group_choice(uid), -1, "and the component takes no group at all")
	var bar := WeaponBar.new()
	bar.bind(s, func() -> Vector2: return Vector2.ZERO)
	var lay := bar.layout()
	var b: Dictionary = lay["bay_slots"][0]
	var over: Vector2 = b["rect"].get_center() + bar._base(lay)
	eq(bar.group_at(over), -1, "dropping a gun on the DRONES header is refused like any invalid drop")
	check(bar.slot_at(over).is_empty(), "a bay slot cannot be picked up to drag")
	bar.free()
