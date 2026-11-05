extends "res://tests/base_test.gd"
## The drone bay and the drones (docs/DRONES.md): placing a bay by the mount rules, one drone per bay, the part cost and the re-arm, the orbit staying
## in its band, point defence and flak shooting drones, a recall on no power, the saved kit, the enemy bay and its launch, and the same seed giving
## the same fight.

const Arena = preload("res://scripts/combat/arena.gd")
const Drones = preload("res://scripts/combat/drones.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")


func _ship() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	for c in g.hull:
		g.force_tile(c, "floor")
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
	eq(Drones.kit_ids().size(), 7, "seven kits")
	for id in Drones.kit_ids():
		var k := Drones.kit(id)
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
