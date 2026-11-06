extends "res://tests/base_test.gd"
## Sector hazards (scripts/combat/hazards.gd): the roll, the five effects in an arena, the map and HUD texts, and that a
## fight with no hazard is unchanged.

const Structure = preload("res://scripts/ship/structure.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Fire = preload("res://scripts/sim/fire.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Hazards = preload("res://scripts/combat/hazards.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Regions = preload("res://scripts/space/regions.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")

const NORTH := 270.0  ## a hazard's dir: degrees, 0 east, 90 south (toward the star, or upstream)
const SOUTH := 90.0
const EAST := 0.0


## A 31x31 ship with one walled room: walls on x = 8 and 22, y = 8 and 17, floor inside (x 9..21, y 9..16).
func _room() -> Ship:
	return Fixture.room_ship()


## Ship 0 at the origin and ship 1 above it, turned round (as in a fight), both room ships, with `hazard` in force.
func _arena(hazard := {}, angle0 := 0.0) -> Arena:
	var a := Arena.new(7)
	a.add_ship(_room(), Vector2.ZERO, angle0)
	a.add_ship(_room(), Vector2(0.0, -1200.0), PI)
	a.hazard = hazard
	return a


## A 31x31 all-floor ship with a reactor, a shield generator and the cable between them: its shield is up from the start.
func _shielded() -> Ship:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	for c in g.hull:
		g.force_tile(c, "floor")
	var s := Ship.new("t", g)
	check(s.components.place(g, "reactor_mk1", Vector2i(9, 19), 0) > 0, "reactor placed")
	check(s.components.place(g, "shield_mk1", Vector2i(13, 19), 0) > 0, "shield placed")
	for x in range(9, 17):
		s.cables.place(g, Vector2i(x, 20))
	return s


func _crew(ship: Ship, name: String, suited := false) -> CrewMember:
	var m := CrewMember.new(name, Vector2(15.0, 12.0))
	if suited:
		m.gear_traits = ["suit"]
	ship.crew.append(m)
	return m


func _events(a: Arena, type: String, kind := "") -> Array:
	return a.events.filter(func(e): return e["type"] == type and (kind == "" or e.get("kind", "") == kind))


# --- the data ----------------------------------------------------------------------------------------

func test_data_has_the_five_hazards_the_regions_name() -> void:
	var table: Dictionary = Hazards.config().get("hazards", {})
	var want: Array = Regions.HAZARDS.duplicate()
	want.sort()
	var have: Array = table.keys()
	have.sort()
	eq(have, want, "hazards.json has exactly the ids the region validator allows")
	for id in table:
		var d: Dictionary = table[id]
		for k in ["name", "hud", "glyph", "color"]:
			check(d.has(k) and str(d[k]) != "", "%s has a %s" % [id, k])
		check(str(d["hud"]).begins_with(str(d["name"]).to_upper()), "%s: the HUD line starts with the name in capitals" % id)
	for t in ["empty", "anomaly", "asteroid_field", "wreck_field", "default", "station", "exit"]:
		check(Hazards.config()["chances"].has(t), "a chance for " + t)
	eq(Hazards.chance_of("station"), 0.0, "no hazard at a station")
	eq(Hazards.chance_of("exit"), 0.0, "no hazard at the exit")
	eq(Hazards.chance_of("pirate"), 0.2, "other types use the default")
	eq(Hazards.chance_of("anomaly"), 0.6, "anomaly 0.6")


# --- the roll ----------------------------------------------------------------------------------------

func test_roll_is_deterministic_per_seed_and_node() -> void:
	var list := ["ion_storm", "gas_cloud", "radiation"]
	var same := true
	var any_diff := false
	var ids := {}
	var dirs := {}
	var hits := 0
	for i in 400:
		var node := {"id": "n%d" % i, "type": "empty"}
		var a := Hazards.roll(1234, node, list)
		same = same and a == Hazards.roll(1234, node, list)
		any_diff = any_diff or a != Hazards.roll(99, node, list)
		if not a.is_empty():
			hits += 1
			ids[a["id"]] = true
			dirs[a["dir"]] = true
			check(a["id"] in list, "it rolls one of the region's hazards: " + str(a))
			check(is_equal_approx(fposmod(float(a["dir"]), 45.0), 0.0) and float(a["dir"]) >= 0.0 and float(a["dir"]) < 360.0, "a direction in 45 degree steps: " + str(a["dir"]))
	check(same, "the same seed and node give the same hazard")
	check(any_diff, "another seed gives other hazards")
	check(hits > 160 and hits < 240, "about half of the empty nodes have one (0.5): %d of 400" % hits)
	eq(ids.size(), 3, "it picks among all the region's hazards")
	check(dirs.size() >= 6, "the directions vary: %d" % dirs.size())


func test_roll_never_at_a_station_or_the_exit_or_without_region_hazards() -> void:
	var all := ["ion_storm", "star_heat", "gas_cloud", "radiation", "debris_surge"]
	for i in 200:
		for t in ["station", "exit", "gate"]:
			check(Hazards.roll(5, {"id": "n%d" % i, "type": t}, all).is_empty(), "no hazard at a %s" % t)
		for t in ["empty", "anomaly", "pirate", "asteroid_field"]:
			check(Hazards.roll(5, {"id": "n%d" % i, "type": t}, []).is_empty(), "a region with no hazards has none (%s)" % t)
	eq(Hazards.roll(5, {"id": "x", "type": "empty"}, ["bogus"]), {}, "an unknown hazard id is never rolled")


func test_roll_chance_follows_the_node_type() -> void:
	var counts := {}
	for t in ["anomaly", "pirate"]:
		var n := 0
		for i in 500:
			if not Hazards.roll(77, {"id": "n%d" % i, "type": t}, ["ion_storm"]).is_empty():
				n += 1
		counts[t] = n
	check(counts["anomaly"] > 250 and counts["anomaly"] < 350, "anomalies: about 0.6 (%d of 500)" % counts["anomaly"])
	check(counts["pirate"] > 70 and counts["pirate"] < 130, "others: about 0.2 (%d of 500)" % counts["pirate"])


func test_the_campaign_caches_one_hazard_per_node_from_its_region() -> void:
	var seen := 0
	for s in [1, 2, 3, 4, 5, 6]:
		var c := Campaign.new(s)
		var region_hazards: Array = c.region_data.get("hazards", [])
		for id in c.drift.ids():
			var h := c.hazard_at(id)
			eq(h, Hazards.roll(c.region_seed, c.node(id), region_hazards), "hazard_at is the roll of the region seed and node (%s)" % id)
			check(is_same(h, c.hazard_at(id)), "it is cached")
			if not h.is_empty():
				seen += 1
				check(h["id"] in region_hazards, "a node has one of its region's hazards")
				check(c.node(id)["type"] != "station" and c.node(id)["type"] != "exit", "never at a station or the exit")
		eq(c.hazard_at("no_such_node"), {}, "no hazard at a node the map does not have")
	check(seen > 0, "some node of six runs has a hazard")
	var c2 := Campaign.new(1)
	c2.enter_region("lumen_space")  # its region lists ion_storm
	var ion := 0
	for id in c2.drift.ids():
		var h2 := c2.hazard_at(id)
		ion += 1 if h2.get("id", "") == "ion_storm" else 0
		check(h2.is_empty() or h2["id"] == "ion_storm", "Lumen space rolls only ion storms")
	check(ion > 0, "Lumen space has an ion storm somewhere")


# --- ion storm ---------------------------------------------------------------------------------------

## Seconds until the one layer a hit used comes back, in a fight with `hazard`.
func _recharge_seconds(hazard: Dictionary) -> float:
	var a := Arena.new(3)
	a.add_ship(_shielded(), Vector2.ZERO, 0.0)
	a.hazard = hazard
	var co = a.ships[0]
	var full: int = co.layers
	check(full > 0, "the shield is up")
	Shields.absorb(a, 0, {"damage_type": "energy", "damage": 99.0}, Vector2.ZERO, Vector2.UP, 0)
	check(co.layers < full, "the hit used a layer")
	var t := 0.0
	while float(co.sector_layers[0]) < Shields.cap_of(co, 0) - 1e-6 and t < 60.0:
		a.step(0.05)
		t += 0.05
	return t


func test_ion_storm_halves_the_shield_recharge() -> void:
	var normal := _recharge_seconds({})
	var storm := _recharge_seconds({"id": "ion_storm", "dir": 0.0})
	var row := Abilities.shield_row({})
	var base: float = float(row["break_delay"]) + float(row["layer_hp"]) / float(row["regen_rate"])  # knocked to 0: the break delay, then the layer's HP at the regen rate
	check(absf(normal - base) < 0.15, "a layer takes about %s s to come back (%s)" % [base, normal])
	check(absf(storm - 2.0 * normal) < 0.2, "in an ion storm twice as long (%s vs %s)" % [storm, normal])
	var a := _arena({"id": "ion_storm", "dir": 0.0})
	eq(Hazards.recharge_mult(a), 0.5, "the factor")
	eq(Hazards.accuracy_add(a), 0.0, "an ion storm leaves accuracy alone")
	eq(Hazards.aim_error_mult(a), 1.0, "and aim")


func test_ion_storm_does_not_slow_the_ion_lock() -> void:
	var a := Arena.new(3)
	a.add_ship(_shielded(), Vector2.ZERO, 0.0)
	a.hazard = {"id": "ion_storm", "dir": 0.0}
	a.ships[0].ion_lock = 3.0
	a.step(3.1)
	eq(a.ships[0].ion_lock, 0.0, "the lock ends after 3 s as always")


# --- star heat ---------------------------------------------------------------------------------------

func _fires(a: Arena, idx: int) -> Array:
	return Fire.sorted_cells(a.ships[idx].ship.fires.keys())


func test_a_flare_ignites_only_cells_beside_walls_facing_the_star() -> void:
	var a := _arena({"id": "star_heat", "dir": NORTH})
	var n := Hazards.flare(a)
	eq(n, 6, "three fires on each of the two ships")
	var f0 := _fires(a, 0)
	eq(f0.size(), 3, "at most 3 on ship 0")
	for c in f0:
		eq(c.y, 9, "ship 0: the fire is in the row just inside the north wall: " + str(c))
		check(c.x >= 9 and c.x <= 21, "ship 0: on the floor: " + str(c))
	var f1 := _fires(a, 1)  # ship 1 is turned round: its south wall faces north
	eq(f1.size(), 3, "at most 3 on ship 1")
	for c in f1:
		eq(c.y, 16, "ship 1: the row just inside its south wall: " + str(c))
	eq(_events(a, "hazard", "flare").size(), 2, "one flare event per ship")


func test_a_flare_follows_the_ships_turn() -> void:
	var a := _arena({"id": "star_heat", "dir": NORTH}, PI / 2.0)  # turned a quarter clockwise: its west wall faces north
	Hazards.flare(a)
	var f0 := _fires(a, 0)
	eq(f0.size(), 3, "three fires")
	for c in f0:
		eq(c.x, 9, "just inside the west wall: " + str(c))
	var b := _arena({"id": "star_heat", "dir": EAST})
	Hazards.flare(b)
	for c in _fires(b, 0):
		eq(c.x, 21, "a star to the east: the row inside the east wall: " + str(c))


func test_a_flare_with_few_floor_cells_lights_what_there_is() -> void:
	var s := _room()  # fill the row inside the north wall with walls but two floor cells
	for x in range(11, 22):
		s.grid.force_tile(Vector2i(x, 9), "wall")
	var a := Arena.new(7)
	a.add_ship(s)
	a.hazard = {"id": "star_heat", "dir": NORTH}
	var walls := Hazards.facing_walls(a, 0, Vector2(0.0, -1.0), 0.5)
	check(walls.size() > 0, "walls face north")
	Hazards.flare(a)
	var f := _fires(a, 0)
	eq(f, [Vector2i(9, 9), Vector2i(10, 9)], "only the two floor cells left beside the north wall burn")


func test_a_wall_inside_the_ship_is_not_an_outer_wall() -> void:
	var s := _room()
	for x in range(9, 22):
		s.grid.force_tile(Vector2i(x, 12), "wall")  # a partition across the room: floor on both sides
	var a := Arena.new(7)
	a.add_ship(s)
	for dir in [NORTH, SOUTH]:
		a.hazard = {"id": "star_heat", "dir": dir}
		for w in Hazards.facing_walls(a, 0, Hazards.dir_vec(a.hazard), 0.5):
			check(w["cell"].y != 12, "the partition faces nobody (%s): %s" % [dir, str(w["cell"])])
	a.hazard = {"id": "debris_surge", "dir": SOUTH}
	for i in 5:
		Hazards.surge(a)
	for e in _surge_hits(a, 0):
		check(e["cell"].y != 12, "no surge hit on the partition: " + str(e["cell"]))
	a.hazard = {"id": "star_heat", "dir": NORTH}
	for i in 5:
		Hazards.flare(a)
	for c in _fires(a, 0):
		eq(c.y, 9, "fires only beside the outer north wall: " + str(c))


func test_flares_come_every_25_seconds() -> void:
	var a := _arena({"id": "star_heat", "dir": NORTH})
	a.step(24.9)
	eq(_events(a, "hazard", "flare").size(), 0, "none before 25 s")
	eq(a.ships[0].ship.fires.size(), 0, "no fire yet")
	a.step(0.2)
	eq(_events(a, "hazard", "flare").size(), 2, "the first flare at 25 s (a flare event per ship)")
	eq(a.ships[0].ship.fires.size(), 3, "three fires")
	a.step(24.9)
	eq(_events(a, "hazard", "flare").size(), 4, "the second at 50 s")
	a.step(25.0)
	eq(_events(a, "hazard", "flare").size(), 6, "the third at 75 s")


func test_flare_warning_three_seconds_before() -> void:
	var a := _arena({"id": "star_heat", "dir": NORTH})
	check(Hazards.hud_line(a).begins_with("STAR HEAT: a flare every 25 s"), "the plain line: " + Hazards.hud_line(a))
	a.tick = 1500 - 4 * 60
	check(not "Flare in" in Hazards.hud_line(a), "no warning at 4 s")
	a.tick = 1500 - 3 * 60
	eq(Hazards.hud_line(a), "STAR HEAT: Flare in 3", "warning at 3 s")
	a.tick = 1500 - 2 * 60 - 30
	eq(Hazards.hud_line(a), "STAR HEAT: Flare in 3", "2.5 s rounds up")
	a.tick = 1500 - 1
	eq(Hazards.hud_line(a), "STAR HEAT: Flare in 1", "right before it")
	a.tick = 1500
	check(not "Flare in" in Hazards.hud_line(a), "and the line is plain again once it has gone off")


# --- gas cloud ---------------------------------------------------------------------------------------

func test_gas_cloud_lowers_turret_accuracy_and_widens_the_pilots_aim() -> void:
	var a := _arena()
	var uid := a.add_mount(0, "laser_turret_mk1", Vector2(15.5, 10.5))
	var base := a.weapons.hit_chance(a, 0, uid, 1)
	check(base > 0.3 and base < 0.99, "a hit chance that is not clamped: %s" % base)
	a.hazard = {"id": "gas_cloud", "dir": 0.0}
	check(absf(a.weapons.hit_chance(a, 0, uid, 1) - (base - 0.2)) < 1e-6, "0.2 less in a gas cloud")
	eq(Hazards.aim_error_mult(a), 1.5, "aim error x1.5")
	eq(Hazards.recharge_mult(a), 1.0, "shields as usual")
	var spread := func(arena: Arena) -> float:
		var ai := PilotAI.new(arena, 1, 0, {})
		ai.aim_skill = 0.4
		var worst := 0.0
		for i in 300:
			ai.think(0.5)  # re-rolls the aim error each time
			worst = maxf(worst, absf(ai.bias))
		return rad_to_deg(worst)
	var clear: float = spread.call(_arena())
	var cloud: float = spread.call(a)
	check(clear <= 5.1 + 1e-6 and clear > 4.3, "skill 0.4 is off by up to 5.1 degrees (8.5 x 0.6): %s" % clear)
	check(cloud <= 7.65 + 1e-6 and cloud > 5.6, "in a gas cloud by up to 7.65: %s" % cloud)


# --- radiation ---------------------------------------------------------------------------------------

func test_radiation_hurts_unsuited_crew_only_with_no_shield_layer() -> void:
	var a := Arena.new(5)
	var bare := _room()  # no shield at all
	var plain := _crew(bare, "Ann")
	var suited := _crew(bare, "Rex", true)
	var down := _crew(bare, "Dee")
	down.hp = 0.0
	a.add_ship(bare, Vector2.ZERO, 0.0)
	var guarded := _shielded()
	var safe := _crew(guarded, "Bo")
	a.add_ship(guarded, Vector2(0.0, -1200.0), PI)
	check(a.ships[1].layers > 0, "ship 1's shield is up")
	a.hazard = {"id": "radiation", "dir": 0.0}
	a.step(2.0)
	check(absf(plain.hp - (plain.max_hp - 1.0)) < 0.05, "no layers: 0.5 hp/s, 1 hp in 2 s (lost %s)" % (plain.max_hp - plain.hp))
	eq(suited.hp, suited.max_hp, "a suit keeps the radiation out")
	eq(down.hp, 0.0, "a downed member is left alone")
	eq(safe.hp, safe.max_hp, "a shield layer up: no harm")
	var co = a.ships[1]
	co.sector_layers[0] = 0.0  # the layers are gone
	co.sector_wait[0] = 999.0
	a.step(2.0)
	check(co.layers == 0, "the layer stayed down")
	check(absf(safe.hp - (safe.max_hp - 1.0)) < 0.05, "layers 0: the crew is hurt now")
	var plain_hp := plain.hp
	a.hazard = {}
	a.step(2.0)
	eq(plain.hp, plain_hp, "no hazard, no harm")


func test_radiation_counts_an_ion_locked_shield_as_down() -> void:
	var a := Arena.new(5)
	var s := _shielded()
	var m := _crew(s, "Cy")
	a.add_ship(s)
	a.hazard = {"id": "radiation", "dir": 0.0}
	a.step(1.0)
	eq(m.hp, m.max_hp, "shielded: fine")
	a.ships[0].ion_lock = 3.0
	check(a.ships[0].layers > 0, "the layers are still counted")
	a.step(1.0)
	check(m.hp < m.max_hp - 0.4, "but the ion lock opens the ship to radiation")
	check(Hazards.hud_line(a).begins_with("RADIATION: SHIELDS DOWN"), "and the HUD says so: " + Hazards.hud_line(a))


func test_radiation_can_put_a_crew_member_down() -> void:
	var a := Arena.new(5)
	var s := _room()
	var m := _crew(s, "Ed")
	m.hp = 0.2
	a.add_ship(s)
	a.hazard = {"id": "radiation", "dir": 0.0}
	a.step(1.0)
	check(m.is_down(), "down")
	eq(m.hp, 0.0, "not below 0")
	check(s.events.any(func(e): return e["text"] == "Ed is down"), "and the chronicle says so")


# --- debris surge ------------------------------------------------------------------------------------

func _surge_hits(a: Arena, idx: int) -> Array:
	return a.events.filter(func(e): return e["type"] == "hit" and e["ship"] == idx and e.get("hazard", false))


func test_a_surge_hits_only_outer_walls_facing_the_current() -> void:
	var a := _arena({"id": "debris_surge", "dir": SOUTH})
	eq(Hazards.surge(a), 8, "four hits on each ship")
	var h0 := _surge_hits(a, 0)
	eq(h0.size(), 4, "four hits on ship 0")
	for e in h0:
		eq(e["cell"].y, 17, "the south wall: " + str(e["cell"]))
		check(e["cell"].x >= 8 and e["cell"].x <= 22, "on the wall: " + str(e["cell"]))
		eq(e["dtype"], "kinetic", "kinetic")
		eq(e["kind"], "wall", "walls only")
	var h1 := _surge_hits(a, 1)
	eq(h1.size(), 4, "four hits on ship 1")
	for e in h1:
		eq(e["cell"].y, 8, "ship 1 is turned round: its north wall faces south: " + str(e["cell"]))
	eq(_events(a, "hazard", "surge").size(), 2, "a surge event per ship")


func test_surges_come_every_20_seconds() -> void:
	var a := _arena({"id": "debris_surge", "dir": SOUTH})
	a.step(19.9)
	eq(_surge_hits(a, 0).size(), 0, "none before 20 s")
	a.step(0.2)
	eq(_surge_hits(a, 0).size(), 4, "four at 20 s")
	eq(_surge_hits(a, 1).size(), 4, "on each ship")
	a.step(20.0)
	eq(_surge_hits(a, 0).size(), 8, "four more at 40 s")
	for e in _surge_hits(a, 0):
		eq(e["cell"].y, 17, "always the south wall")
	check(Hazards.hud_line(a).begins_with("DEBRIS SURGE"), "the line: " + Hazards.hud_line(a))


func test_a_surge_follows_the_normal_damage_rules() -> void:
	# resist: a heavy armour wall (kinetic x0.6) takes 0.6 per hit
	var s := _room()
	for x in range(8, 23):
		s.grid.force_tile(Vector2i(x, 17), "heavy_armor")
	var a := Arena.new(7)
	a.add_ship(s)
	a.hazard = {"id": "debris_surge", "dir": SOUTH}
	Hazards.surge(a)
	var dealt := 0.0
	for e in _surge_hits(a, 0):
		check(absf(float(e["dealt"]) - 0.6) < 1e-6, "heavy armour resists kinetic: %s" % e["dealt"])
		dealt += float(e["dealt"])
	var t0 := Structure.totals(a.ships[0].ship)
	check(absf(t0.y - t0.x - dealt) < 1e-3, "the blocks lose what was dealt")
	# slope: a face 45 degrees off the current takes cos(45) of the damage
	var t := _room()
	var b := Arena.new(7)
	b.add_ship(t, Vector2.ZERO, PI / 4.0)  # turned an eighth: a south star-ish current meets the faces at 45 degrees
	b.hazard = {"id": "debris_surge", "dir": SOUTH}
	Hazards.surge(b)
	var hits := _surge_hits(b, 0)
	check(hits.size() > 0, "walls face the current at 45 degrees")
	for e in hits:
		check(absf(float(e["dealt"]) - sqrt(0.5)) < 1e-4, "a 45 degree face takes 0.707: %s" % e["dealt"])
	# breaches: a wall on its last hp is shot open, and the hull is told
	var u := _room()
	for x in range(8, 23):
		u.grid.hp[Vector2i(x, 17)] = 0.5
	var c := Arena.new(7)
	c.add_ship(u)
	c.hazard = {"id": "debris_surge", "dir": SOUTH}
	Hazards.surge(c)
	check(_events(c, "breach").size() > 0, "a weak wall is breached")
	eq(u.grid.get_tile(_events(c, "breach")[0]["cell"]), "", "and the cell is open")
	eq(_events(c, "breach").size(), _surge_hits(c, 0).size(), "each hit that landed breached a different wall (a breached one takes no more)")


func test_a_surge_on_a_surrendering_enemy_is_no_refusal() -> void:
	var a := _arena({"id": "debris_surge", "dir": SOUTH})
	Hazards.surge(a)
	var Morale = preload("res://scripts/combat/morale.gd")
	var m = Morale.new(a, 1, 0)
	for e in _surge_hits(a, 1):
		check(not m._is_attack(e), "a surge hit is not the player's attack")
	var shot := {"type": "hit", "ship": 1, "cell": Vector2i(8, 8)}
	check(m._is_attack(shot), "a real hit still is")


# --- no hazard ---------------------------------------------------------------------------------------

func test_no_hazard_changes_nothing() -> void:
	var a := _arena()
	eq(Hazards.recharge_mult(a), 1.0, "recharge")
	eq(Hazards.accuracy_add(a), 0.0, "accuracy")
	eq(Hazards.aim_error_mult(a), 1.0, "aim")
	eq(Hazards.hud_line(a), "", "no HUD line")
	var before := a.rng.state
	a.step(60.0)
	eq(a.rng.state, before, "a hazard-free arena draws nothing from its rng")
	eq(_events(a, "hazard").size(), 0, "and logs no hazard event")
	eq(a.ships[0].ship.fires.size(), 0, "no fires")


# --- the map and the HUD texts -----------------------------------------------------------------------

func test_texts() -> void:
	eq(Hazards.compass({"dir": 0.0}), "E", "east")
	eq(Hazards.compass({"dir": 270.0}), "N", "north")
	eq(Hazards.compass({"dir": 315.0}, true), "north-east", "north-east")
	var lines := Hazards.map_lines({"id": "star_heat", "dir": 90.0})
	eq(lines[0], "Hazard: Star heat (star to the south)", "the map names it and where the star is")
	check("flare" in lines[1], "and says what it does: " + lines[1])
	lines = Hazards.map_lines({"id": "debris_surge", "dir": 180.0})
	eq(lines[0], "Hazard: Debris surge (current from the west)", "the current")
	lines = Hazards.map_lines({"id": "ion_storm", "dir": 45.0})
	eq(lines[0], "Hazard: Ion storm", "no direction for a storm")
	eq(lines[1], "shields recharge at half speed", "the effect")
	eq(Hazards.map_lines({}), [], "nothing for no hazard")
	eq(Hazards.hud_line(_arena({"id": "ion_storm", "dir": 0.0})), "ION STORM: shields recharge at half speed", "the HUD line")


# --- the map starts a fight in the node's hazard ---------------------------------------------------

## A stand-in for the combat view that builds the real session, so the map's hook has an arena to set the hazard on.
class FakeCombat extends Node:
	signal finished(result: Dictionary)
	var active := false
	var sim: Node
	var session = null

	func enter(path := "") -> String:
		var enemy = load("res://scripts/combat/combat_session.gd").load_ship(path)
		session = load("res://scripts/combat/combat_session.gd").new()
		session.start(sim.player_ship(), enemy, 1)
		active = true
		return ""


func test_the_map_starts_a_fight_in_the_nodes_hazard() -> void:
	var sim := ShipSim.new()
	check(sim.choose_ship("res://data/ships/starter_rustbucket.json") == "", "the starter loads")
	var fake := FakeCombat.new()
	fake.sim = sim
	var map := MapView.new()
	map.sim = sim
	map.combat = fake
	map.size = Vector2(1600.0, 900.0)
	map.new_seed = 5
	map.open()
	map.event_panel.close()
	var c: Campaign = map.campaign
	var with := ""
	var without := ""
	for id in c.drift.ids():
		if c.node(id)["type"] in ["station", "exit", "gate"]:
			continue
		if c.hazard_at(id).is_empty():
			without = id
		else:
			with = id
	check(with != "" and without != "", "the region has nodes with and without a hazard")
	c.current = with
	map._start_fight("tier", {})
	eq(fake.session.arena.hazard, c.hazard_at(with), "the fight at a hazard node has its hazard")
	check(not fake.session.arena.hazard.is_empty(), "and it is not empty")
	fake.active = false
	map._fighting = false
	c.current = without
	map._start_fight("tier", {})
	eq(fake.session.arena.hazard, {}, "a fight at a plain node has none")
	map.free()
	sim.free()
	fake.free()


# --- a fight in each hazard --------------------------------------------------------------------------

func test_every_hazard_runs_a_whole_fight() -> void:
	for id in Regions.HAZARDS:
		var sim := ShipSim.new()
		check(sim.choose_ship("res://data/ships/starter_courier.json") == "", "the starter loads")
		var player = sim.player_ship()
		var enemy = Session.load_ship(Session.PIRATE_PATH)
		sim.ships.append(enemy)
		var s := Session.new()
		s.start(player, enemy, 11)
		s.arena.hazard = {"id": id, "dir": 135.0}
		var pilot := PilotAI.new(s.arena, Session.PLAYER, Session.ENEMY, {})
		var n := 0
		while s.state() == "fighting" and n < 60 * 70:
			if n % 3 == 0:
				pilot.think(Session.STEP * 3.0)
			s.ai.think(Session.STEP)
			s.arena.step(Session.STEP)
			s.morale.tick(Session.STEP)
			n += 1
			if n % 12 == 0:
				sim.step(0.2)
		for i in 2:
			var co = s.arena.ships[i]
			check(is_finite(Structure.structure_fraction(co)), "%s: ship %d structure" % [id, i])
			check(is_finite(co.flight.pos.x) and is_finite(co.flight.pos.y), "%s: ship %d position" % [id, i])
			for m in co.ship.crew:
				check(m.hp >= 0.0 and m.hp <= m.max_hp + 1e-6, "%s: %s hp %s" % [id, m.name, str(m.hp)])
			for c in co.ship.fires:
				check(co.ship.fires[c] >= 0.0 and co.ship.fires[c] <= 1.0, "%s: fire intensity" % id)
		sim.ships.erase(enemy)
		if id == "star_heat" and n >= 60 * 26:
			check(s.arena.events.any(func(e): return e["type"] == "hazard" and e.get("kind") == "flare"), "star_heat: the fight saw a flare")
		if id == "debris_surge" and n >= 60 * 21:
			check(s.arena.events.any(func(e): return e["type"] == "hit" and e.get("hazard", false)), "debris_surge: the fight saw a surge")
