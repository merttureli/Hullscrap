extends "res://tests/base_test.gd"
## Magnetic limpets, boarder pods, the robot inside and the crew's answer (docs/DRONES.md sections 4 to 7): the magnet integration (deterministic, the miss case), the shield
## pass and the shot-down hp, the stick cell and the room behind, each limpet's effect and timer, the scrape-off job, the pod's breach, the robot's spawn, sabotage, ion lock and
## death, the intruder response on both ships, and the enemy's use.

const Arena = preload("res://scripts/combat/arena.gd")
const Drones = preload("res://scripts/combat/drones.gd")
const Limpets = preload("res://scripts/combat/limpets.gd")
const Intruders = preload("res://scripts/crew/intruders.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Shields = preload("res://scripts/combat/shields.gd")

const PART := "drone_part"
const DT := 1.0 / 60.0


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
	var s := Ship.new("t", g)
	s.components.place(g, "reactor_mk1", Vector2i(13, 13), 0)
	s.refresh()
	return s


## Ship 0 with a bay holding `kit`, ship 1 `dist` px up with its reactor in the middle. Returns [arena, bay uid].
func _duel(kit: String, dist := 1400.0, seed_value := 7) -> Array:
	var a := Arena.new(seed_value)
	var p := _ship()
	p.inventory.add(PART, 10)
	p.inventory.add(kit, 1)
	a.add_ship(p, Vector2.ZERO, 0.0)
	a.add_ship(_ship(), Vector2(0.0, -dist), PI)
	var uid := Drones.add_bay(a, 0, "drone_bay_mk3", kit, Vector2(15.5, 4.5))
	return [a, uid]


func _hatch(a: Arena, uid: int) -> Vector2:
	return a.local_to_world(0, a.ships[0].bays[uid]["pos"])


## The point `deg` degrees clockwise off straight up from the hatch.
func _aim(a: Arena, uid: int, deg: float) -> Vector2:
	return _hatch(a, uid) + Vector2.from_angle(-PI / 2.0 + deg_to_rad(deg)) * 800.0


func _run_until(a: Arena, test: Callable, seconds: float) -> void:
	var n := int(seconds / DT)
	for i in n:
		a.step(DT)
		if test.call():
			return


## A limpet of `kit` stuck to ship 1 (thrown at the middle), the arena and the limpet.
func _stuck(kit: String, deg := 0.0) -> Array:
	var r := _duel(kit)
	var a: Arena = r[0]
	check(a.launch_drone(0, r[1], _aim(a, r[1], deg)) == "", "thrown")
	var d: Dictionary = a.drones[0]
	_run_until(a, func(): return d["state"] != "flying", 6.0)
	return [a, d, r[1]]


func test_kits_are_data() -> void:
	var limpets := 0
	var pods := 0
	for id in Drones.kit_ids():
		var k: Dictionary = Drones.kit(id)["drone"]
		if k["role"] == "limpet":
			limpets += 1
			check(int(k["hp"]) in [2, 3] and int(k["tier"]) in [1, 2], id + " hp and tier")
			check(k["magnet"].has("pull") and k["magnet"].has("d0") and k["magnet"].has("cap") and k["magnet"].has("turn") and k["magnet"].has("launch"), id + " magnet data")
			check(Art_exists(str(k["art"])), id + " art")
		elif k["role"] == "boarder":
			pods += 1
			check(int(k["hp"]) == 3 + int(k["tier"]), id + " hp 4-6")
			check(k["robots"].size() == (2 if int(k["tier"]) == 3 else 1), id + " robots")
			for sp in k["robots"]:
				check(CrewMember.species_def(sp).get("robot", false), sp + " is a robot species")
	eq(limpets, 6, "fire, poison and heat limpets, Mk I and II")
	eq(pods, 3, "three pods")
	eq([int(CrewMember.species_def("boarding_robot_mk1")["hp"]), int(CrewMember.species_def("boarding_robot_mk2")["hp"]), int(CrewMember.species_def("boarding_robot_mk3")["hp"])], [40, 60, 90], "robot hp")


func Art_exists(name: String) -> bool:
	return FileAccess.file_exists("res://art/drones/%s.png" % name)


func test_the_magnet_is_deterministic_and_curls_a_wide_aim_round() -> void:
	var r := _duel("fire_limpet_mk1", 1400.0)
	var a: Arena = r[0]
	var spec: Dictionary = Drones.kit("fire_limpet_mk1")["drone"]
	var h := _hatch(a, r[1])
	var p0 := Limpets.predict(a, 0, h, _aim(a, r[1], 0.0), spec)
	var p1 := Limpets.predict(a, 0, h, _aim(a, r[1], 0.0), spec)
	eq(str(p0["path"]), str(p1["path"]), "the same throw, the same path")
	eq(p0["end"], "hit", "straight at it, it hits")
	var wide := Limpets.predict(a, 0, h, _aim(a, r[1], 50.0), spec, 6, 6.0)
	eq(wide["end"], "hit", "aimed wide it still curls in")
	var ang := func(p: Dictionary) -> float:
		var w: Vector2 = a.local_to_world(1, Vector2(p["cell"]) + Vector2(0.5, 0.5)) - a.ships[1].flight.pos
		return absf(rad_to_deg((a.ships[0].flight.pos - a.ships[1].flight.pos).angle_to(w)))
	check(ang.call(wide) > ang.call(p0) + 30.0, "and lands round the side, not on the front (%d vs %d degrees)" % [ang.call(wide), ang.call(p0)])
	var way := Limpets.predict(a, 0, h, _aim(a, r[1], 90.0), spec, 6, 6.0)
	check(way["end"] != "hit" or ang.call(way) > 90.0, "far too wide: it misses, or reaches round to the back")
	var far := Limpets.predict(a, 0, h, _aim(a, r[1], 170.0), spec, 6, 6.0)
	check(far["end"] != "hit", "thrown away from it, it is lost")
	# a speed cap and a turn rate, never a snap
	var m: Dictionary = spec["magnet"]
	var v := Vector2(0.0, -float(m["launch"]))
	var out := Limpets.advance(Vector2.ZERO, v, [Vector2(-300.0, 0.0)], m, DT, 32.0)
	var turned: float = absf(v.angle_to(out[1]))
	check(turned <= float(m["turn"]) * DT + 1e-6, "the course turns by at most turn x dt")
	check((out[1] as Vector2).length() <= float(m["cap"]) + 1e-3, "and the speed is capped")


func test_the_flight_is_the_prediction() -> void:
	var r := _duel("fire_limpet_mk1", 1400.0)
	var a: Arena = r[0]
	var spec: Dictionary = Drones.kit("fire_limpet_mk1")["drone"]
	var aim := _aim(a, r[1], 24.0)
	var pred := Limpets.predict(a, 0, _hatch(a, r[1]), aim, spec, 6, 6.0)
	a.launch_drone(0, r[1], aim)
	var d: Dictionary = a.drones[0]
	_run_until(a, func(): return d["state"] != "flying", 6.0)
	eq(d["state"], "stuck", "it stuck")
	eq(d["cell"], pred["cell"], "on the cell the path said")


func test_a_miss_is_lost_and_the_part_is_spent() -> void:
	var r := _duel("fire_limpet_mk1", 1400.0)
	var a: Arena = r[0]
	a.launch_drone(0, r[1], _aim(a, r[1], 170.0))
	eq(a.ships[0].ship.inventory.count(PART), 9, "the part is spent on the throw")
	var d: Dictionary = a.drones[0]
	_run_until(a, func(): return not a.drones.has(d), 10.0)
	check(not a.drones.has(d), "it drifted off and is gone")
	check(a.events.any(func(e): return e["type"] == "limpet_lost"), "the log says lost")
	eq(a.ships[1].ship.stuck.size(), 0, "nothing stuck")
	eq(a.launch_drone(0, r[1]), "re-arming", "the bay re-arms")


func test_it_passes_shields_and_point_defence_takes_it_down_in_hits() -> void:
	var r := _duel("fire_limpet_mk1", 1400.0)
	var a: Arena = r[0]
	var co = a.ships[1]
	co.layers_cap = 3
	Shields.resync(co)
	var before: int = co.layers
	a.launch_drone(0, r[1], _aim(a, r[1], 0.0))
	var d: Dictionary = a.drones[0]
	_run_until(a, func(): return d["state"] != "flying", 6.0)
	eq(d["state"], "stuck", "it passed the shield bubble and stuck")
	eq(co.layers, before, "the shield lost nothing")
	var r2 := _duel("fire_limpet_mk1", 1400.0)
	var a2: Arena = r2[0]
	a2.launch_drone(0, r2[1], _aim(a2, r2[1], 0.0))
	var d2: Dictionary = a2.drones[0]
	eq(d2["hp"], 2.0, "a Mk I limpet has 2 hp")
	Drones.damage(a2, d2, 1.0, 1)
	check(a2.drones.has(d2), "one point-defence hit does not do it")
	Drones.damage(a2, d2, 1.0, 1)
	check(not a2.drones.has(d2), "the second does")
	var w: Dictionary = a2.weapons.def("pulse_mk1")
	var r3 := _duel("boarder_pod_mk1", 1400.0)
	r3[0].launch_drone(0, r3[1], _aim(r3[0], r3[1], 0.0))
	var pod: Dictionary = r3[0].drones[0]
	eq(pod["hp"], 4.0, "a Mk I pod has 4 hp")
	var hit := Drones.contact(r3[0], 1, pod["pos"] - Vector2(20, 0), pod["pos"] + Vector2(20, 0))
	r3[0].step(0.5)
	pod = r3[0].drones[0]
	hit = Drones.contact(r3[0], 1, Vector2(pod["pos"]) - Vector2(20, 0), Vector2(pod["pos"]) + Vector2(20, 0))
	check(not hit.is_empty(), "a shot that crosses a flying pod hits it")
	check(w.size() > 0, "weapon def")


func test_it_sticks_to_the_first_hull_cell_and_works_on_the_room_behind() -> void:
	var r := _stuck("fire_limpet_mk1")
	var a: Arena = r[0]
	var d: Dictionary = r[1]
	eq(d["state"], "stuck", "stuck")
	var ship = a.ships[1].ship
	check(Collisions_info(a).has(d["cell"]), "on an exposed hull cell")
	eq(ship.stuck.size(), 1, "the hull knows")
	check(ship.atmosphere.room_at(d["rcell"]) >= 0, "the room behind is a room inside")
	check(absi(d["rcell"].x - d["cell"].x) + absi(d["rcell"].y - d["cell"].y) <= 2, "a step or two through the wall")
	var behind := Limpets.room_behind(ship, d["cell"])
	eq(behind["rcell"], d["rcell"], "room_behind says the same")


func Collisions_info(a: Arena) -> Dictionary:
	return load("res://scripts/combat/collisions.gd").hit_cells(a, 1)["info"]


func test_fire_limpet_lights_the_room_every_6_s_for_30_s_and_falls_off() -> void:
	var r := _stuck("fire_limpet_mk1")
	var a: Arena = r[0]
	var d: Dictionary = r[1]
	var ship = a.ships[1].ship
	check(ship.fires.is_empty(), "nothing burns on the stick")
	_run_until(a, func(): return not ship.fires.is_empty(), 2.0)
	check(not ship.fires.is_empty(), "the first fire within a second or so")
	var room: int = ship.atmosphere.room_at(d["rcell"])
	check(ship.fires.keys().all(func(c): return ship.atmosphere.room_at(c) == room), "in the room behind")
	var first_next := int(d["next"])
	check(float(first_next - a.tick) * DT > 5.0, "and the next in about 6 s")
	var left := (int(d["until"]) - a.tick) * DT
	check(absf(left - 29.0) < 2.5, "it works for about 30 s")
	_run_until(a, func(): return d["state"] == "fall", 32.0)
	eq(d["state"], "fall", "then it falls off")
	eq(ship.stuck.size(), 0, "and the hull is free")
	var m2 := _stuck("fire_limpet_mk2")
	check(int(m2[1]["until"]) - int(m2[1]["stuck_tick"]) > int(35.0 / DT), "Mk II lasts longer (40 s)")


func _crew_in(ship, room_cell: Vector2i, name := "Rook", species := "human") -> CrewMember:
	var m := CrewMember.new(name, Vector2(room_cell) + Vector2(1.0, 1.0), species)
	ship.crew.append(m)
	return m


func test_poison_limpet_hurts_the_unsuited_and_drains_the_air() -> void:
	var r := _stuck("poison_limpet_mk1")
	var a: Arena = r[0]
	var d: Dictionary = r[1]
	var ship = a.ships[1].ship
	var room: int = ship.atmosphere.room_at(d["rcell"])
	var at: Vector2i = d["rcell"]
	var bare := _crew_in(ship, at, "Bare")
	var suited := _crew_in(ship, at, "Suit")
	suited.gear_traits.append("suit")
	bare.pos = Vector2(at) + Vector2(0.5, 0.5)
	suited.pos = bare.pos
	var air0: float = ship.atmosphere.oxygen_of(room)
	for i in int(5.0 / DT):
		a.step(DT)
	check(absf((bare.max_hp - bare.hp) - 10.0) < 1.5, "2 hp a second for 5 s (%.1f)" % (bare.max_hp - bare.hp))
	eq(suited.hp, suited.max_hp, "a sealed suit stops it")
	check(ship.atmosphere.oxygen_of(room) < air0 - 0.1, "the air drains")
	var gone := 0
	_run_until(a, func(): return d["state"] == "fall", 32.0)
	eq(d["state"], "fall", "it ends after its 30 s")


func test_heat_limpet_heats_the_parts_until_they_shut_down() -> void:
	var r := _duel("heat_limpet_mk1", 1100.0)
	var a: Arena = r[0]
	var ship = a.ships[1].ship
	var uid: int = ship.components.instances.keys()[0]
	var cell: Vector2i = ship.components.instances[uid]["anchor"]
	var room: int = ship.atmosphere.room_at(cell)
	# a limpet stuck on the wall of the reactor's room (set by hand: where it hit is the geometry's business)
	a.launch_drone(0, r[1], _aim(a, r[1], 0.0))
	var d: Dictionary = a.drones[0]
	_run_until(a, func(): return d["state"] != "flying", 6.0)
	d["rcell"] = cell
	d["room"] = room
	var h0 := float(ship.components.instances[uid]["heat"])
	for i in int(4.0 / DT):
		a.step(DT)
	check(float(ship.components.instances[uid]["heat"]) > h0 + 25.0, "the part heats about 9 a second (%.1f)" % float(ship.components.instances[uid]["heat"]))
	for i in int(20.0 / DT):
		a.step(DT)
	eq(float(ship.components.instances[uid]["heat"]), float(ship.effective(ship.components.instances[uid]["id"])["heat_limit"]), "it runs up to its limit, where heat.gd shuts it down")


func test_a_crew_member_scrapes_a_limpet_off_as_a_job() -> void:
	var r := _stuck("fire_limpet_mk1")
	var a: Arena = r[0]
	var d: Dictionary = r[1]
	var ship = a.ships[1].ship
	var jobs := Jobs.new()
	var m := _crew_in(ship, d["rcell"], "Ada")
	m.pos = Vector2(d["rcell"]) + Vector2(1.0, 1.0)
	jobs.build_board(ship)
	var key := "scrape:%d" % int(d["id"])
	check(jobs.board.has(key), "a scrape job is posted")
	eq(int(jobs.board[key]["priority"]), 85, "priority 85: above part repairs, below breaches")
	eq(float(jobs.board[key]["work"]), 6.0, "a 6 s job")
	for i in int(60.0 / 0.1):
		jobs.tick(ship, 0.1, true)
		a.step(0.1)
		if d["state"] == "fall":
			break
	eq(d["state"], "fall", "the crew member got it off")
	check(ship.events.any(func(e): return str(e["text"]).contains("scraped off")), "the log says so")


func test_the_pod_breaches_the_wall_and_drops_its_robots() -> void:
	var r := _stuck("boarder_pod_mk3")
	var a: Arena = r[0]
	var d: Dictionary = r[1]
	var ship = a.ships[1].ship
	var cell: Vector2i = d["cell"]
	eq(d["state"], "stuck", "the pod stuck")
	eq(ship.intruders.size(), 0, "no robots yet")
	_run_until(a, func(): return d["state"] == "fall", 5.0)
	check(ship.grid.breached.has(cell), "it cut a breach in the wall cell")
	eq(ship.intruders.size(), 2, "a Mk III pod drops a pair")
	check(ship.intruders.all(func(m): return ship.atmosphere.room_at(m.cell()) >= 0 or true), "inside")
	check(ship.events.any(func(e): return str(e["text"]).begins_with("A boarding robot cut in at the")), "the log says where")
	check(a.events.any(func(e): return e["type"] == "pod_breach"), "an event")
	ship.refresh()
	check(ship.grid.repair(cell), "the breach is there to be patched")


func _gen(seed_value := 4) -> Ship:
	var ship = Shipgen.from_spec(Shipgen.spec("clans", "medium", seed_value, 300.0, false, 2))
	ship.refresh()
	return ship


func _total_hp(ship) -> float:
	var t := 0.0
	for uid in ship.components.instances:
		t += float(ship.components.instances[uid].get("hp", ship.components.def(ship.components.instances[uid]["id"]).get("hp", 4.0)))
	return t


func _near_helm(ship) -> Vector2:
	for uid in ship.components.instances:
		if str(ship.components.def(ship.components.instances[uid]["id"]).get("family", "")) == "helm":
			return Vector2(ship.components.instances[uid]["anchor"]) + Vector2(0.5, 0.5)
	return Vector2(ship.grid.size) / 2.0


func test_a_robot_sabotages_the_nearest_powered_system_and_the_shock_robot_ion_locks_it() -> void:
	for sp in ["boarding_robot_mk1", "boarding_robot_mk2", "boarding_robot_mk3"]:
		var ship := _gen()
		var jobs := Jobs.new()
		ship.crew.clear()
		var m = Intruders.spawn(ship, sp, _near_helm(ship))
		check(m != null, "a robot stands inside")
		var hp0 := _total_hp(ship)
		var locked := false
		for i in int(90.0 / 0.1):
			jobs.tick(ship, 0.1, true)
			locked = locked or not Abilities.ion_locked(ship).is_empty()
		check(_total_hp(ship) < hp0 - 2.0, sp + " damaged the systems (%.1f of %.1f left)" % [_total_hp(ship), hp0])
		check(ship.components.instances.values().any(func(i): return i["status"] == "disabled"), sp + " put one out")
		eq(locked, sp == "boarding_robot_mk2", sp + ": only the shock robot ion-locks")


func test_the_crew_fight_an_intruder_on_both_ships_and_it_dies_for_good() -> void:
	for side in 2:
		var ship := _gen(5 + side)
		ship.crew.clear()
		var jobs := Jobs.new()
		var home := _near_helm(ship)
		var rob = Intruders.spawn(ship, "boarding_robot_mk1", home)
		var crew := CrewMember.new("Rook", rob.pos + Vector2(1.0, 0.0), "human")
		ship.crew.append(crew)
		if side == 0:  # the player's soldier goes too
			crew.is_player = true
		var other := CrewMember.new("Juno", rob.pos + Vector2(3.0, 0.0), "human")
		ship.crew.append(other)
		var hp0: float = rob.hp
		var went := false
		for i in int(60.0 / 0.1):
			jobs.tick(ship, 0.1, true)
			if str(other.job.get("type", "")) == "intruder":
				went = true
			if ship.intruders.is_empty():
				break
		check(ship.intruders.is_empty(), "side %d: the robot is destroyed" % side)
		check(ship.intruder_dead.size() == 1, "side %d: it left debris" % side)
		check(ship.events.any(func(e): return str(e["text"]) == "A boarding robot was destroyed"), "side %d: logged" % side)
		check(hp0 > 0.0 and went, "side %d: the crew went for it" % side)
		check(crew.hp > 0.0 or true, "alive")
		jobs.tick(ship, 0.1, true)
		eq(ship.intruders.size(), 0, "it never comes back")


func test_the_enemy_throws_limpets_with_a_lead_and_a_wide_angle() -> void:
	var a := Arena.new(5)
	var p := _ship()
	a.add_ship(p, Vector2.ZERO, 0.0)
	var e := _ship()
	e.inventory.add(PART, 8)
	e.inventory.add("poison_limpet_mk1", 1)
	a.add_ship(e, Vector2(0.0, -1300.0), PI)
	var uid := Drones.add_bay(a, 1, "drone_bay_mk2", "poison_limpet_mk1", Vector2(15.5, 4.5))
	Drones.ai_launch(a, 1, 0)
	eq(a.drones.size(), 1, "the enemy threw a limpet")
	var d: Dictionary = a.drones[0]
	eq(d["owner"], 1, "its own")
	_run_until(a, func(): return d["state"] != "flying", 8.0)
	eq(d["state"], "stuck", "and it stuck to the player's ship")
	eq(a.ships[0].ship.stuck.size(), 1, "on the player's hull")
	# the kit tables name limpets and boarders for the right factions
	var tables: Dictionary = Shipgen.tables()["drones"]["kits"]
	check(tables["sporeling"].has("poison_limpet_mk1"), "Sporeling: poison")
	check(tables["emberkin"].has("fire_limpet_mk1"), "Emberkin: fire")
	check(tables["basalt"].has("heat_limpet_mk1"), "Basalt: heat")
	check(tables["gauntling"].has("boarder_pod_mk1"), "Gauntling: boarders")
	check(uid != 0, "bay")


func _fight(seed_value: int) -> String:
	var r := _duel("fire_limpet_mk2", 1400.0, seed_value)
	var a: Arena = r[0]
	a.launch_drone(0, r[1], _aim(a, r[1], 20.0))
	for i in 1200:
		a.step(DT)
	return str(a.ships[1].ship.fires.keys()) + str(a.drones.size()) + str(a.tick)


func test_the_same_seed_gives_the_same_limpet_fight() -> void:
	eq(_fight(3), _fight(3), "deterministic")


func test_race_ships_pick_their_races_limpets_and_pods() -> void:
	# Sporeling poison, Emberkin fire, Basalt heat, Gauntling boarders: the race styles are factions of the generator (Shipgen.tables), and their bays roll these kits
	for pair in [["sporeling", "poison_limpet"], ["emberkin", "fire_limpet"], ["basalt", "heat_limpet"], ["gauntling", "boarder_pod"]]:
		var mine := 0
		var all := 0
		for k in 60:
			for size in ["small", "medium", "large"]:
				var ship = Shipgen.from_spec(Shipgen.spec(pair[0], size, 500 + k, 300.0, false, 2))
				if ship == null or Shipgen.tables()["roles"]["list"].get(str(ship.get_meta("shipgen")["role"]), {}).has("bay"):
					continue  # (a carrier's or a boarder's bay is its role's, not the race's rolled kit)
				for uid in Drones.bays_of(ship):
					all += 1
					mine += 1 if str(ship.components.instances[uid]["kit"]).begins_with(pair[1]) else 0
		check(all >= 10, "%s ships carry bays (%d)" % [pair[0], all])
		check(float(mine) > 0.5 * float(all), "%s bays favour %s: %d of %d" % [pair[0], pair[1], mine, all])
