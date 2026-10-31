extends "res://tests/base_test.gd"
## Sector space, the core logic (scripts/space/sector.gd, the sector and jump parts of campaign.gd, docs/CONTENT.md
## section 11): generation from a node (deterministic; the POI counts, mix, distances and visibility follow
## data/sectors.json; a station node has its beacon), the region, the current feeding drift_debris.gd, flying as a point
## mass, triggers (a POI fires once and stays done through a save), fights spawned near a POI, the 8 s jump spool
## (the hostile block, fuel spent when it fires, arrival), the ambient encounters, saves and the data file.

const Campaign = preload("res://scripts/space/campaign.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const DriftDebris = preload("res://scripts/space/drift_debris.gd")
const Events = preload("res://scripts/space/events.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Content = preload("res://scripts/data/content.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const TYPES: Array = ["station", "gate", "pirate", "wreck_field", "distress", "trader", "anomaly", "patrol", "asteroid_field", "empty"]


func near(got: float, want: float, msg: String, eps := 1e-3) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	return s


## A campaign on the new light-speed flow (the instant jump off). Its cfg is its own copy.
func _camp(seed_value := 1, instant := false) -> Campaign:
	var cfg: Dictionary = Campaign.config().duplicate(true)
	cfg["instant_jump"] = instant
	return Campaign.new(seed_value, cfg)


## A node dictionary of type `type` that no map has (for generating sectors of every type).
func _node(type: String, i := 0) -> Dictionary:
	return {"id": "t%d" % i, "name": "", "type": type, "place": ""}


## The id of the first node of the map that has type `type`.
func _of_type(c: Campaign, type: String) -> String:
	for n in c.drift.nodes:
		if n["type"] == type and str(n["place"]) == "":
			return n["id"]
	check(false, "this map has a %s node" % type)
	return ""


## Put the campaign on node `id` as if the ship had come in (no jump counted).
func _go(c: Campaign, id: String, ship = null) -> void:
	c.current = id
	c.visited[id] = true
	c.current_sector().enter()
	if ship != null:
		c.current_sector().set_flight(ship)


func _next(c: Campaign) -> String:
	for o in c.neighbours(c.current):
		if c.node(o)["type"] != "gate":
			return o
	return ""


## Everything a sector is made of, to compare two.
func _sig(s) -> Array:
	return [s.arrival, s.current_angle, s.current_speed, s.density, s.debris_mult, s.region, s.pois.map(func(p): return [p["id"], p["type"], p["pos"], p["visibility"], p["event_type"], p["state"], p["main"]])]


func _fuel_to(ship: Ship, n: int) -> void:
	ship.inventory.add("fuel", n - ship.inventory.count("fuel"))


# --- generation ----------------------------------------------------------------------------------------------

func test_the_same_seed_and_node_make_the_same_sector() -> void:
	var c := Campaign.new(5)
	var node := c.node("n03")
	var a = Sector.generate(5, node, "clans")
	var b = Sector.generate(5, node, "clans")
	eq(_sig(a), _sig(b), "the same sector twice")
	check(_sig(Sector.generate(5, c.node("n04"), "clans")) != _sig(a), "another node, another sector")
	check(_sig(Sector.generate(6, node, "clans")) != _sig(a), "another seed, another sector")
	eq(a.seed_value, Sector.seed_for(5, "n03"), "its seed is seed_for")


func test_a_sector_does_not_depend_on_when_it_is_made_and_leaves_the_campaigns_rng_alone() -> void:
	var c1 := Campaign.new(9)
	var c2 := Campaign.new(9)
	var state := c1.rng.state
	var ids: Array = c1.drift.ids()
	for id in ids:
		c1.sector_at(id)
	eq(c1.rng.state, state, "making sectors does not move the campaign's rng")
	ids.reverse()
	c2.jumps = 17  # nor does the jump counter matter
	for id in ids:
		c2.sector_at(id)
	for id in ids:
		eq(_sig(c1.sectors[id]), _sig(c2.sectors[id]), "%s: the same made first or last" % id)
	check(c1.sector_at("nope") == null, "no sector for a node the map does not have")
	check(c1.sector_at("n03") == c1.sector_at("n03"), "it is made once and kept")


func test_size_arrival_current_and_poi_distances_are_in_range() -> void:
	var n := 0
	for seed_value in [1, 2, 3, 4, 5, 6]:
		var c := Campaign.new(seed_value)
		for id in c.drift.ids():
			var s = c.sector_at(id)
			n += 1
			var tag := "seed %d node %s" % [seed_value, id]
			eq(s.size, 24000.0, tag + ": 24,000 px square")
			near(minf(minf(s.arrival.x, s.arrival.y), minf(s.size - s.arrival.x, s.size - s.arrival.y)), 1200.0, tag + ": the arrival point is near one edge")
			check(s.contains(s.arrival), tag + ": and inside")
			check(s.current_speed >= 20.0 and s.current_speed <= 60.0, tag + ": the current runs 20 to 60 px/s (%s)" % str(s.current_speed))
			check(s.current_angle >= 0.0 and s.current_angle < 360.0, tag + ": in degrees")
			check(s.pois.size() >= 2 and s.pois.size() <= 6, tag + ": 2 to 6 POIs (%d)" % s.pois.size())
			var seen := {}
			for p in s.pois:
				var d: float = p["pos"].distance_to(s.arrival)
				check(d >= 3000.0 - 0.01 and d <= 12000.0 + 0.01, "%s %s: %d px from the arrival point" % [tag, p["id"], d])
				check(s.contains(p["pos"]), tag + ": POI inside the sector")
				check(Sector.VISIBILITIES.has(p["visibility"]), tag + ": a known visibility")
				eq(p["state"], "new", tag + ": POIs start new")
				check(not seen.has(p["id"]), tag + ": ids are unique")
				seen[p["id"]] = true
				check(p["pos"] is Vector2 and p["enemy"] is String and p["event_type"] is String, tag + ": the fields")
			eq(s.pois[0]["main"], true, tag + ": the first is the main POI")
			eq(s.ship_pos, s.arrival, tag + ": the ship starts at the arrival point")
	check(n == 6 * 28, "all sectors were checked (%d)" % n)


func test_the_poi_mix_follows_sectors_json() -> void:
	var cfg: Dictionary = Sector.config()
	var share := {}  # node type -> {poi type: sectors that have one}
	var wrecks_of_pirates := 0
	for type in TYPES:
		var nc: Dictionary = cfg["nodes"][type]
		var allowed := {str(nc["main"]): true}
		for t in nc["weights"]:
			if float(nc["weights"][t]) > 0.0:
				allowed[t] = true
		var lo := maxi(int(nc["count"][0]), int(cfg["poi"]["count"][0]))
		var hi := mini(int(nc["count"][1]), int(cfg["poi"]["count"][1]))
		share[type] = {}
		for i in 40:
			var s = Sector.generate(i, _node(type, i), "boneyard")
			var tag := "%s #%d" % [type, i]
			eq(s.pois[0]["type"], nc["main"], tag + ": the main POI is the node type's")
			eq(s.pois[0]["event_type"], type, tag + ": and runs the node's own event type")
			check(s.pois.size() >= lo and s.pois.size() <= hi, "%s: %d POIs, wanted %d to %d" % [tag, s.pois.size(), lo, hi])
			var count := {}
			if type == "pirate":
				wrecks_of_pirates += s.pois.filter(func(p): return p["type"] == "wreck").size()
			for k in s.pois.size():
				var p: Dictionary = s.pois[k]
				var t: Dictionary = cfg["poi_types"][p["type"]]
				check(allowed.has(p["type"]), "%s: %s is not in the mix" % [tag, p["type"]])
				count[p["type"]] = int(count.get(p["type"], 0)) + 1
				if k > 0:
					var ev = t["event"]
					check(ev == p["event_type"] if ev is String else ev.has(p["event_type"]), "%s: %s runs a %s event" % [tag, p["type"], p["event_type"]])
				var vis = t["visibility"]
				check(vis == p["visibility"] if vis is String else vis.has(p["visibility"]), "%s: %s is %s" % [tag, p["type"], p["visibility"]])
			for t in count:
				check(int(count[t]) <= int(cfg["poi_types"][t]["max"]), "%s: at most %d %s" % [tag, cfg["poi_types"][t]["max"], t])
				share[type][t] = int(share[type].get(t, 0)) + 1
	eq(share["pirate"].get("pirate_nest", 0), 40, "a pirate node always has its nest")
	eq(share["pirate"].get("wreck", 0), 40, "and a wreck")
	check(wrecks_of_pirates >= 40 + 8, "and often a second (%d wrecks in 40 pirate sectors)" % wrecks_of_pirates)
	eq(share["trader"].get("store", 0), 40, "a trader node always has its store")
	eq(share["trader"].get("mining_field", 0), 40, "and a mining field")
	eq(share["patrol"].get("concord_checkpoint", 0), 40, "a patrol node has its checkpoint")
	eq(share["asteroid_field"].get("mining_field", 0), 40, "an asteroid field has its mining")
	eq(share["wreck_field"].get("wreck", 0), 40, "a wreck field has wrecks")


func test_every_poi_type_turns_up_somewhere() -> void:
	var cfg: Dictionary = Sector.config()
	var met := {}
	for type in TYPES:
		for i in 60:
			for p in Sector.generate(i, _node(type, i), "boneyard").pois:
				met[p["type"]] = true
	for t in cfg["poi_types"]:
		check(met.has(t), "%s turns up in some sector" % t)
	var vis := {}
	for i in 200:
		for p in Sector.generate(i, _node("pirate", i), "boneyard").pois:
			vis[p["visibility"]] = true
	for v in Sector.VISIBILITIES:
		check(vis.has(v), "%s POIs exist" % v)


func test_a_station_node_always_has_its_station_beacon() -> void:
	for place in ["rusthold", "meridian", "prism"]:
		for seed_value in range(1, 11):
			var c := Campaign.new(seed_value)
			var s = c.sector_at(place)
			var stations: Array = s.pois.filter(func(p): return p["type"] == "station")
			eq(stations.size(), 1, "%s/%d: exactly one station" % [place, seed_value])
			eq(s.pois[0]["type"], "station", "%s/%d: it is the main POI" % [place, seed_value])
			eq(s.pois[0]["visibility"], "beacon", "%s/%d: a beacon" % [place, seed_value])
			eq(s.pois[0]["name"], c.node(place)["name"], "%s/%d: it carries the station's name" % [place, seed_value])
			eq(s.pois[0]["event_type"], "station", "%s/%d: its event type" % [place, seed_value])
	var hidden: Dictionary = Sector.config().duplicate(true)
	hidden["poi_types"]["station"]["visibility"] = "hidden"
	for i in 5:
		eq(Sector.generate(i, {"id": "x", "name": "Somewhere", "type": "station", "place": "x"}, "clans", hidden).pois[0]["visibility"], "beacon", "a station is a beacon whatever the table says")


func test_the_region_is_the_nearest_landmark() -> void:
	var c := Campaign.new(3)
	eq(c.region_of("rusthold"), "clans", "Rusthold")
	eq(c.region_of("meridian"), "concord", "Meridian")
	eq(c.region_of("prism"), "lumen", "the Prism")
	for g in ["gate_1", "gate_2", "gate_3"]:
		eq(c.region_of(g), "boneyard", "%s: a gate is not a landmark of any region" % g)
	var places: Array = c.drift.nodes.filter(func(n): return str(n["place"]) != "")
	var names := {"rusthold": "clans", "meridian": "concord", "prism": "lumen"}
	var seen := {}
	for n in c.drift.nodes:
		var best := ""
		var best_d := INF
		for p in places:
			var d: float = n["pos"].distance_to(p["pos"])
			if d < best_d:
				best = p["id"]
				best_d = d
		eq(c.region_of(n["id"]), names.get(best, "boneyard"), "%s: the region of its nearest landmark %s" % [n["id"], best])
		seen[c.region_of(n["id"])] = true
		eq(c.sector_at(n["id"]).region, c.region_of(n["id"]), "%s: its sector knows" % n["id"])
	check(seen.size() >= 3, "the map has several regions (%s)" % str(seen.keys()))


# --- the current feeds the debris ----------------------------------------------------------------------------

func test_the_current_and_density_drive_drift_debris() -> void:
	var wreck = Sector.generate(4, _node("wreck_field", 1), "clans")
	var empty = Sector.generate(4, _node("empty", 2), "clans")
	var base: Dictionary = Content.read(DriftDebris.PATH)
	var d: DriftDebris = DriftDebris.for_sector(wreck, 1)
	near(float(d.cfg["current"]["angle"]), wreck.current_angle, "the spawner runs on the sector's current direction")
	near(float(d.cfg["current"]["speed"]), wreck.current_speed, "and speed")
	var swing := absf(rad_to_deg(angle_difference(d.current_dir().angle(), deg_to_rad(wreck.current_angle))))
	check(swing <= float(base["current"]["wobble_deg"]) + 0.01, "the direction wobbles only a little around it (%s deg)" % str(swing))
	var speed := d.current_speed()
	check(speed >= wreck.current_speed * 0.85 - 0.01 and speed <= wreck.current_speed * 1.15 + 0.01, "the speed stays near it (%s)" % str(speed))
	var dd: DriftDebris = DriftDebris.for_sector(empty, 1)
	check(float(d.cfg["spawn"]["every"]) < float(base["spawn"]["every"]) and float(dd.cfg["spawn"]["every"]) > float(base["spawn"]["every"]), "a wreck field spawns faster than the base, an empty sector slower")
	check(int(d.cfg["spawn"]["max_alive"]) > int(dd.cfg["spawn"]["max_alive"]), "and holds more")
	var weights := {}
	for t in d.cfg["types"]:
		weights[t["id"]] = float(t["weight"])
	check(weights["sealed_crate"] > 2.0 * 5.0, "the wreck theme: more crates than the base 5 (%s)" % str(weights["sealed_crate"]))
	var ship := _ship()
	d.prewarm(ship)
	dd.prewarm(ship)
	check(d.pieces.size() > 2 * dd.pieces.size(), "a wreck field starts with far more debris than empty space (%d and %d)" % [d.pieces.size(), dd.pieces.size()])
	var base_run := DriftDebris.new(1)
	eq(float(base_run.cfg["current"]["angle"]), float(base["current"]["angle"]), "with no sector the numbers of debris.json run as they did")
	var other = Sector.generate(4, _node("pirate", 3), "clans")
	check(other.current_angle != wreck.current_angle or other.current_speed != wreck.current_speed, "sectors have their own currents")
	d.step(ship, 1.0)
	for p in d.pieces:
		check(p["vel"].length() < 200.0, "the pieces drift at the current's pace")


# --- flying ----------------------------------------------------------------------------------------------------

func test_the_flight_numbers_are_the_arenas() -> void:
	var ship := _ship()
	var n := Sector.flight_numbers(ship)
	var arena := Arena.new(1)
	arena.add_ship(ship)
	var co = arena.ships[0]
	check(float(n["accel"]) > 0.0, "the starter can fly (%s px/s2)" % str(n["accel"]))
	near(float(n["accel"]), float(co.thrusts["fwd"]) * co.flight.thrust_to_accel / co.mass, "accel is the forward thrust x thrust_to_accel / mass, as the arena has it", 1e-6)
	eq(n["max_speed"], co.flight.max_speed, "the arena's top speed")
	eq(n["damping"], co.flight.linear_damping, "and damping")
	var s = Campaign.new(1).sector_at("n01")
	s.set_flight(ship)
	near(s.accel, float(n["accel"]), "the sector takes them", 1e-6)


func test_fly_is_a_point_mass() -> void:
	var s = Campaign.new(1).sector_at("n01")
	s.ship_pos = Vector2(12000.0, 12000.0)
	s.accel = 100.0
	s.max_speed = 600.0
	s.damping = 0.25
	s.fly(1.0, Vector2.RIGHT)
	near(s.ship_vel.x, 100.0 * exp(-0.25), "full thrust east for a second: 100 px/s, less the damping (as flight.gd orders them)", 1e-3)
	eq(s.ship_vel.y, 0.0, "and nothing sideways")
	check(s.ship_pos.x > 12000.0, "and the ship moved")
	var v: float = s.ship_vel.length()
	s.fly(2.0)
	check(s.ship_vel.length() < v and s.ship_vel.length() > 0.0, "with no thrust it slows, never at once")
	var a = Campaign.new(1).sector_at("n01")
	var b = Campaign.new(1).sector_at("n01")
	for t in [a, b]:
		t.accel = 100.0
	a.fly(1.0, Vector2(5.0, 0.0))
	b.fly(1.0, Vector2(1.0, 0.0))
	eq(a.ship_vel, b.ship_vel, "a thrust longer than 1 is cut to full thrust")
	var half = Campaign.new(1).sector_at("n01")
	half.accel = 100.0
	half.fly(1.0, Vector2(0.5, 0.0))
	near(half.ship_vel.x, b.ship_vel.x / 2.0, "half thrust, half the speed", 1e-6)
	s.accel = 1.0e6
	for i in 100:
		s.fly(0.1, Vector2.RIGHT)
	near(s.ship_vel.length(), 600.0, "the speed is capped at max_speed")
	var wall = Campaign.new(1).sector_at("n01")
	wall.accel = 500.0
	wall.ship_pos = Vector2(wall.size - 100.0, 500.0)
	for i in 100:
		wall.fly(0.1, Vector2.RIGHT)
	eq(wall.ship_pos.x, wall.size, "the sector's wall stops the ship")
	eq(wall.ship_vel.x, 0.0, "and its speed into the wall")
	var still = Campaign.new(1).sector_at("n01")
	still.fly(5.0, Vector2.RIGHT)
	eq(still.ship_pos, still.arrival, "a ship with no acceleration (no engine) goes nowhere; the current only moves the debris")
	still.fly(0.0, Vector2.RIGHT)
	eq(still.ship_vel, Vector2.ZERO, "a zero step does nothing")


func test_hostile_near() -> void:
	var s = Campaign.new(1).sector_at("n01")
	check(not s.hostile_near(2000.0), "no hostiles, none near")
	s.hostiles = [s.ship_pos + Vector2(2001.0, 0.0)]
	check(not s.hostile_near(2000.0), "2,001 px away is not near")
	s.hostiles.append(s.ship_pos + Vector2(0.0, -1999.0))
	check(s.hostile_near(2000.0), "1,999 px away is")
	s.enter()
	check(not s.hostile_near(2000.0), "arriving clears them")


# --- triggers --------------------------------------------------------------------------------------------------

func test_a_poi_within_800_px_fires_once_and_stays_done_through_a_save() -> void:
	var c := _camp(1)
	var ship := _ship()
	var id := _of_type(c, "wreck_field")
	_go(c, id, ship)
	var s = c.current_sector()
	var poi: Dictionary = s.pois[0]
	check(s.trigger(c, ship).is_empty(), "at the arrival point, 3,000 px from everything, nothing fires")
	s.ship_pos = poi["pos"] + Vector2(801.0, 0.0)
	var r: Dictionary = s.trigger(c, ship)
	check(r.is_empty() or r["poi"]["id"] != "p0", "at 801 px it does not fire")
	s.ship_pos = poi["pos"] + Vector2(799.0, 0.0)
	r = s.trigger(c, ship)
	check(not r.is_empty(), "at 799 px it fires")
	eq(r["poi"]["id"], "p0", "the POI")
	eq(r["refused"], "", "nobody refuses a wreck field")
	check(not r["event"].is_empty(), "with the node's arrival event")
	eq(r["event"]["type"], "wreck_field", "an event of the POI's type")
	check(not r["dock"], "nothing to dock at")
	eq(c.events_seen, 1, "it counts as an event met")
	check(s.trigger(c, ship).is_empty(), "it does not fire again while it is open")
	s.ship_pos = poi["pos"] + Vector2(2000.0, 0.0)
	check(s.trigger(c, ship).is_empty(), "the ship is away")
	s.ship_pos = poi["pos"] + Vector2(500.0, 0.0)
	check(not s.trigger(c, ship).is_empty(), "an event left unresolved fires again when the ship comes back")
	eq(poi["state"], "new", "it is still new")
	s.resolve("p0")
	eq(poi["state"], "done", "resolved, the POI is done")
	check(s.trigger(c, ship).is_empty(), "and it fires no more")
	s.ship_pos = poi["pos"] + Vector2(100.0, 0.0)
	check(s.trigger(c, ship).is_empty(), "not even right on top of it")
	s.ship_vel = Vector2(3.0, 4.0)
	var d = JSON.parse_string(JSON.stringify(c.to_dict()))
	var c2 := _camp(77)
	eq(c2.load_dict(d), "", "the save loads")
	var s2 = c2.current_sector()
	eq(c2.current, id, "on the same node")
	eq(s2.pois[0]["state"], "done", "the POI is still done after the save")
	eq(s2.ship_pos, poi["pos"] + Vector2(100.0, 0.0), "the ship is where it was")
	eq(s2.ship_vel, Vector2(3.0, 4.0), "with its speed")
	check(s2.trigger(c2, ship).is_empty(), "and it does not fire again")
	eq(_sig(s2), _sig(s), "the sector is the same: its layout comes from the seed")


func test_other_pois_run_an_event_of_their_own_type() -> void:
	var ship := _ship()
	var found := false
	for seed_value in range(1, 40):
		var c := _camp(seed_value)
		for n in c.drift.nodes:
			if n["type"] == "pirate":
				var s = c.sector_at(n["id"])
				for p in s.pois:
					if p["type"] == "wreck":
						found = true
						_go(c, n["id"], ship)
						s.ship_pos = p["pos"] + Vector2(0.0, 300.0)
						var r: Dictionary = s.trigger(c, ship)
						eq(r["poi"]["id"], p["id"], "the wreck fires")
						check(not r["event"].is_empty(), "with an event")
						eq(r["event"]["type"], "wreck_field", "of its own type, not the pirate node's")
						eq(r["refused"], "", "no refusal")
						s.resolve(p["id"])
						eq(p["state"], "done", "done")
						s.pois.append({"id": "px", "type": "concord_checkpoint", "name": "Checkpoint", "pos": p["pos"], "visibility": "signal", "event_type": "patrol", "state": "new", "enemy": "", "main": false})
						c.rep["concord"] = -10
						eq(s.trigger(c, ship)["event"]["id"], "patrol_hostile", "a Concord checkpoint that has you on its list opens fire, wherever it is")
						break
			if found:
				break
		if found:
			break
	check(found, "a pirate sector with a wreck turned up")


func test_the_main_poi_runs_the_nodes_arrival_event_with_its_rules() -> void:
	var c := _camp(1)
	var ship := _ship()
	_go(c, "rusthold", ship)
	var s = c.current_sector()
	eq(c.drift.node("rusthold")["type"], "station", "Rusthold is a station")
	s.ship_pos = s.pois[0]["pos"] + Vector2(300.0, 0.0)
	var r: Dictionary = s.trigger(c, ship)
	eq(r["poi"]["id"], "p0", "the station fires")
	check(r["dock"], "and opens the menu")
	check(c.flags.has("at_rusthold"), "the dock flag is set, as arrive() does")
	check(not r["event"].is_empty(), "with a greeting")
	check(s.trigger(c, ship).is_empty(), "once")
	s.resolve("p0")
	eq(s.pois[0]["state"], "new", "a station never becomes done")
	s.ship_pos = s.pois[0]["pos"] + Vector2(1000.0, 0.0)
	check(s.trigger(c, ship).is_empty(), "still inside 1.5 x 800 px: not yet re-armed")
	s.ship_pos = s.pois[0]["pos"] + Vector2(1500.0, 0.0)
	check(s.trigger(c, ship).is_empty(), "out of range")
	s.ship_pos = s.pois[0]["pos"] + Vector2(400.0, 0.0)
	r = s.trigger(c, ship)
	check(not r.is_empty() and r["dock"], "back again, it docks")
	check(r["event"].is_empty(), "with no second greeting")
	check(not s.cleared(), "a sector with other POIs to do is not cleared")
	for p in s.pois:
		p["state"] = "done"
	check(s.cleared(), "all done: cleared")
	s.pois[0]["state"] = "new"
	check(s.cleared(), "a station or store is never left to do")
	c.rep["clans"] = -10
	s.enter()  # a new arrival: it greets again
	s.ship_pos = s.pois[0]["pos"] + Vector2(100.0, 0.0)
	r = s.trigger(c, ship)
	eq(r["refused"], Campaign.REFUSED_TEXT, "below the refusal line the dock master turns you away")
	check(not r["dock"], "and no menu opens")


func test_a_fight_spawns_an_enemy_design_near_the_poi() -> void:
	var c := _camp(3)
	var ship := _ship()
	var id := _of_type(c, "pirate")
	_go(c, id, ship)
	var s = c.current_sector()
	var poi: Dictionary = s.pois[0]
	var f: Dictionary = s.fight_spawn(c, "p0", "tier")
	eq(f["poi"], "p0", "the POI")
	check(Shipgen.from_spec(str(f["design"])) != null, "a generated ship that builds (%s)" % str(f["design"]))
	var d: float = f["pos"].distance_to(poi["pos"])
	check(d >= 250.0 - 0.01 and d <= 600.0 + 0.01, "250 to 600 px from the POI (%s)" % str(d))
	eq(s.fight_spawn(c, "p0", "pirate_raider")["design"], "res://data/ships/pirate_raider.json", "a named design is that design")
	poi["enemy"] = "rustfang_rammer"
	eq(s.fight_spawn(c, "p0", "tier")["design"], "res://data/ships/rustfang_rammer.json", "a POI with its own enemy uses it for a tier fight")
	eq(s.fight_spawn(c, "p0", "pirate_raider")["design"], "res://data/ships/pirate_raider.json", "but an event that names a design wins")
	check(s.fight_spawn(c, "nope", "tier").is_empty(), "an unknown POI spawns nothing")
	var again: Dictionary = s.fight_spawn(c, "p0", "tier")
	check(again["pos"] != f["pos"], "each spawn point is its own roll")


# --- the jump ------------------------------------------------------------------------------------------------

func test_the_old_instant_jump_is_on_by_default() -> void:
	eq(Campaign.config()["instant_jump"], true, "data/drift.json: instant_jump is true for now")
	var c := Campaign.new(1)
	check(c.instant_jump(), "so the campaign jumps at once")
	var ship := _ship()
	var to := _next(c)
	var r := c.jump(to, ship)
	check(r["ok"], "jump() works as it did")
	eq(c.current, to, "and arrives")
	check(c.sectors.has(to), "the sector of the node is there when it is wanted")
	var off := _camp(1)
	var why: Dictionary = off.jump(_next(off), ship)
	check(not why["ok"] and why["why"] == Campaign.SPOOL_TEXT, "with the flag off jump() asks for the spool")
	eq(off.current, off.drift.start_id(), "and does not move")


func test_the_jump_drive_spools_for_8_seconds_and_spends_fuel_when_it_fires() -> void:
	var c := _camp(1)
	var ship := _ship()
	_fuel_to(ship, 5)
	var to := _next(c)
	var from := c.current
	var cost := c.jump_fuel(ship)
	var part_after := (c.fuel_part + c.jump_cost(ship)) % Campaign.FUEL_PARTS
	eq(c.tick_jump(1.0, false, ship), "", "nothing to tick with no spool")
	var r: Dictionary = c.start_jump(to, ship)
	check(r["ok"], "the spool starts: " + str(r["why"]))
	eq(c.spool_time(), 8.0, "it takes 8 seconds")
	check(c.jump_status()["active"], "active")
	check(not c.start_jump(to, ship)["ok"], "one spool at a time")
	eq(ship.inventory.count("fuel"), 5, "nothing is spent when it starts")
	eq(c.tick_jump(3.0, false, ship), "spooling", "3 s")
	eq(c.tick_jump(4.9, false, ship), "spooling", "7.9 s")
	near(float(c.jump_status()["frac"]), 7.9 / 8.0, "the charge is nearly full", 1e-6)
	eq(c.current, from, "still here")
	eq(ship.inventory.count("fuel"), 5, "still no fuel spent")
	eq(c.jumps, 0, "no jump counted")
	eq(c.tick_jump(0.2, false, ship), "jumped", "8.1 s: it fires")
	eq(c.current, to, "the ship is at the new node")
	eq(ship.inventory.count("fuel"), 5 - cost, "the fuel is spent now (jump_fuel: %d)" % cost)
	eq(c.fuel_part, part_after, "with the engines' fuel_mult, as the old jump took it")
	eq(c.jumps, 1, "the jump counter moved")
	check(c.visited.has(to), "visited")
	check(c.last_jump["ok"] and c.last_jump["node"] == to, "last_jump says so")
	check(not c.jump_status()["active"], "the spool is over")
	check(c.sectors.has(to), "the new sector exists")
	eq(c.current_sector().ship_pos, c.current_sector().arrival, "the ship is at its arrival point")
	check(c.current_sector().accel > 0.0, "flying with the ship's numbers")
	eq(c.tick_jump(1.0, false, ship), "", "nothing more to tick")


func test_a_spool_can_be_ticked_in_any_steps() -> void:
	var ship := _ship()
	for step in [0.016, 0.5, 2.0, 8.0, 100.0]:
		var c := _camp(1)
		c.start_jump(_next(c), ship)
		var t := 0.0
		var result := ""
		while result != "jumped" and t < 20.0:
			result = c.tick_jump(step, false, ship)
			t += step
		eq(result, "jumped", "steps of %s s" % str(step))
		check(t >= 8.0 and t < 8.0 + step + 0.1, "it fired as the 8 s ran out (%s)" % str(t))


func test_hostiles_within_2000_px_block_the_jump() -> void:
	var c := _camp(1)
	var ship := _ship()
	_fuel_to(ship, 5)
	var to := _next(c)
	eq(c.hostile_range(), 2000.0, "the block range is 2,000 px")
	var r: Dictionary = c.start_jump(to, ship, true)
	check(not r["ok"], "it does not start with a hostile near")
	eq(r["why"], "hostiles too close to jump", "and says why")
	check(not c.jump_status()["active"], "no spool")
	check(c.start_jump(to, ship)["ok"], "it starts clear")
	eq(c.tick_jump(5.0, false, ship), "spooling", "5 s charged")
	eq(c.tick_jump(10.0, true, ship), "blocked", "a hostile comes within range: blocked")
	check(c.jump_status()["blocked"], "the HUD is told")
	near(float(c.jump_status()["t"]), 5.0, "the charge holds where it was")
	eq(c.current, c.drift.start_id(), "no jump")
	eq(ship.inventory.count("fuel"), 5, "and no fuel spent")
	eq(c.tick_jump(2.0, false, ship), "spooling", "the hostile is gone: it goes on (7 s)")
	check(not c.jump_status()["blocked"], "no longer blocked")
	eq(c.tick_jump(1.0, true, ship), "blocked", "a hostile at the last moment blocks the firing too")
	eq(c.current, c.drift.start_id(), "still here")
	eq(c.tick_jump(1.0, false, ship), "jumped", "clear, it fires")
	var s = c.sector_at(c.drift.start_id())
	s.hostiles = [s.ship_pos + Vector2(1900.0, 0.0)]
	check(s.hostile_near(c.hostile_range()), "the sector's hostile list feeds the block")


func test_a_jump_that_cannot_be_paid_does_not_start_or_fires_nothing() -> void:
	var c := _camp(1)
	var ship := _ship()
	_fuel_to(ship, 0)
	var to := _next(c)
	var r: Dictionary = c.start_jump(to, ship)
	eq(r["why"], Campaign.NO_FUEL, "no fuel, no spool")
	_fuel_to(ship, 3)
	check(c.start_jump(to, ship)["ok"], "with fuel it starts")
	c.tick_jump(4.0, false, ship)
	_fuel_to(ship, 0)  # the fuel is gone before it fires
	eq(c.tick_jump(5.0, false, ship), "failed", "it fires into an empty tank: refused")
	eq(c.last_jump["why"], Campaign.NO_FUEL, "for want of fuel")
	eq(c.current, c.drift.start_id(), "no jump")
	check(not c.jump_status()["active"], "the spool is over")
	check(not c.start_jump("nowhere", ship)["ok"], "no lane, no spool")
	var gate := ""
	for n in c.drift.nodes:
		if n["type"] == "gate" and c.drift.linked(c.current, n["id"]):
			gate = n["id"]
	if gate != "":
		eq(c.start_jump(gate, ship)["why"], Campaign.DARK_TEXT, "a dark gate")
	_fuel_to(ship, 3)
	c.start_jump(to, ship)
	c.cancel_jump()
	check(not c.jump_status()["active"], "cancelled")
	eq(ship.inventory.count("fuel"), 3, "nothing spent")


func test_arriving_loads_the_sector_as_it_was_left() -> void:
	var c := _camp(1)
	var ship := _ship()
	_fuel_to(ship, 10)
	var home := c.current
	var to := _next(c)
	c.start_jump(to, ship)
	eq(c.tick_jump(8.0, false, ship), "jumped", "there")
	var s = c.current_sector()
	s.pois[0]["state"] = "done"
	s.ship_pos = s.arrival + Vector2(500.0, 500.0)
	var layout := _sig(s)
	c.start_jump(home, ship)
	eq(c.tick_jump(8.0, false, ship), "jumped", "home")
	eq(c.current, home, "the way back")
	c.start_jump(to, ship)
	eq(c.tick_jump(8.0, false, ship), "jumped", "and there again")
	var again = c.current_sector()
	check(again == s, "the same sector")
	eq(again.pois[0]["state"], "done", "its POIs remember what is done")
	eq(again.ship_pos, again.arrival, "the ship arrives at the arrival point again")
	eq(_sig(again), layout, "the layout is unchanged")


func test_a_tow_cancels_the_spool_and_arrives_home() -> void:
	var c := _camp(1)
	var ship := _ship()
	c.start_jump(_next(c), ship)
	c.tick_jump(2.0, false, ship)
	_fuel_to(ship, 0)
	var r: Dictionary = c.tow(ship)
	check(r["ok"], "towed")
	check(not c.jump_status()["active"], "the spool is gone")
	eq(c.current_sector().ship_pos, c.current_sector().arrival, "home, at the arrival point")


# --- ambient encounters --------------------------------------------------------------------------------------

func _busy(chance := 1.0) -> Dictionary:
	var cfg: Dictionary = Sector.config().duplicate(true)
	cfg["ambient"]["chance"] = chance
	return cfg


func test_ambient_contacts_come_every_90_seconds_by_a_seeded_roll() -> void:
	var node := _node("empty", 1)
	var a = Sector.generate(5, node, "clans", _busy())
	var b = Sector.generate(5, node, "clans", _busy())
	eq(a.tick(89.0, null), [], "nothing before 90 s")
	check(a.ambient.is_empty(), "no contact yet")
	var made: Array = a.tick(1.0, null)
	eq(made.size(), 1, "at 90 s a roll adds a contact (the chance is 1 here)")
	eq(a.ambient.size(), 1, "it is about")
	var c: Dictionary = a.ambient[0]
	eq(c["type"], "unknown", "an unknown contact")
	eq(c["visibility"], "signal", "that needs a radar")
	check(["trader", "patrol", "pirate"].has(c["event_type"]), "a trader, a patrol or a pirate (%s)" % c["event_type"])
	near(c["pos"].distance_to(a.ship_pos), 1500.0 * 0.9, "at the radar's edge: with no radar the visual range x 0.9", 0.5)
	check(a.contains(c["pos"]), "inside the sector")
	check(a.all_pois().has(c), "it is one of the sector's contacts")
	b.tick(90.0, null)
	eq(b.ambient.size(), 1, "the twin sector")
	eq([b.ambient[0]["pos"], b.ambient[0]["event_type"], b.ambient[0]["vel"]], [c["pos"], c["event_type"], c["vel"]], "rolls the same contact: they are seeded")
	var other = Sector.generate(5, _node("empty", 2), "clans", _busy())
	other.tick(90.0, null)
	check(other.ambient[0]["pos"] != c["pos"], "another node, another roll")
	var x = Sector.generate(5, node, "clans", _busy())
	for i in 90:
		x.tick(1.0, null)
	eq([x.ambient[0]["pos"], x.ambient[0]["event_type"]], [c["pos"], c["event_type"]], "a second at a time gives the same contact")


func test_ambient_kind_follows_the_regions_weights_and_the_cap_and_time_to_leave() -> void:
	var cfg := _busy()
	var cap := int(cfg["ambient"]["max"])
	for region in ["clans", "concord", "lumen", "boneyard"]:
		var s = Sector.generate(2, _node("empty", 3), region, cfg)
		var kinds := {}
		for i in 40:
			s.ambient.clear()
			for c in s.tick(90.0, null):
				kinds[c["event_type"]] = int(kinds.get(c["event_type"], 0)) + 1
		var weights: Dictionary = cfg["regions"][region]["ambient"]
		for k in kinds:
			check(float(weights.get(k, 0.0)) > 0.0, "%s: %s is in the region's weights" % [region, k])
		var top := "pirate" if region in ["clans", "boneyard"] else ("patrol" if region == "concord" else "trader")
		var best := ""
		for k in kinds:
			if best == "" or kinds[k] > kinds[best]:
				best = k
		eq(best, top, "%s: mostly %s (%s)" % [region, top, str(kinds)])
	var s = Sector.generate(2, _node("empty", 3), "boneyard", cfg)
	for i in 8:
		s.tick(90.0, null)
	check(s.ambient.size() <= cap, "at most %d about at once (%d)" % [cap, s.ambient.size()])
	var quiet = Sector.generate(2, _node("empty", 3), "boneyard", _busy(0.0))
	for i in 20:
		quiet.tick(90.0, null)
	check(quiet.ambient.is_empty(), "chance 0: nobody comes")
	var some = Sector.generate(2, _node("empty", 3), "boneyard", _busy(0.5))
	var count := 0
	for i in 100:
		some.ambient.clear()
		count += some.tick(90.0, null).size()
	check(count > 30 and count < 70, "chance 0.5: about half the rolls bring someone (%d of 100)" % count)


func test_an_ambient_contact_moves_leaves_and_fires_its_event() -> void:
	var c := _camp(1)
	var ship := _ship()
	var cfg := _busy()
	var s = Sector.generate(1, c.node("n01"), "clans", cfg)
	_go(c, "n01", ship)
	c.sectors["n01"] = s
	s.set_flight(ship)
	s.ship_pos = Vector2(12000.0, 12000.0)
	s.tick(90.0, ship)
	var a: Dictionary = s.ambient[0]
	near(a["pos"].distance_to(s.ship_pos), 3000.0 * 0.9, "the helm's radar reach x 0.9", 0.5)
	var p0: Vector2 = a["pos"]
	s.tick(10.0, ship)
	check(a["pos"] != p0 and a["pos"].distance_to(p0) > 100.0, "it flies")
	near(float(a["ttl"]), 300.0 - 10.0, "and its time runs out")
	s.ambient.clear()
	s.tick(90.0, ship)
	a = s.ambient[0]
	s.ship_pos = a["pos"] + Vector2(300.0, 0.0)
	var r: Dictionary = s.trigger(c, ship)
	check(not r.is_empty(), "within 800 px it fires")
	eq(r["poi"]["id"], a["id"], "that contact")
	if not r["event"].is_empty():
		eq(r["event"]["type"], a["event_type"], "an event of the kind it is")
	s.resolve(a["id"])
	check(s.find(a["id"]).is_empty(), "resolved, it is gone")
	s.ambient.clear()
	s.tick(90.0, ship)
	a = s.ambient[0]
	a["ttl"] = 5.0
	s.tick(6.0, ship)
	check(not s.ambient.any(func(x): return x["id"] == a["id"]), "it leaves when its time is up")


# --- saving and loading --------------------------------------------------------------------------------------

func test_saves_are_version_3_and_old_ones_arrive_at_the_arrival_point() -> void:
	eq(Campaign.VERSION, 3, "the campaign save version")
	var c := _camp(1)
	var ship := _ship()
	_go(c, _next(c), ship)
	var d: Dictionary = c.to_dict()
	eq(d["version"], 3, "saved as version 3")
	check(d["sectors"] is Dictionary and d["sectors"].has(c.current), "with the sectors visited")
	check(d["spool"] is Dictionary, "and the spool")
	for old in [2, 1]:
		var e = JSON.parse_string(JSON.stringify(d))
		e.erase("sectors")
		e.erase("spool")
		e["version"] = old
		if old == 1:
			e.erase("fuel_part")
		var c2 := _camp(9)
		eq(c2.load_dict(e), "", "version %d loads" % old)
		eq(c2.current, c.current, "%d: on the same node" % old)
		eq(c2.sectors.size(), 0, "%d: no sector saved" % old)
		var s = c2.current_sector()
		eq(s.ship_pos, s.arrival, "%d: the ship is at the sector's arrival point" % old)
		eq(_sig(s), _sig(c.current_sector()), "%d: the same sector, made from the seed" % old)
		check(c2.spool.is_empty(), "%d: no spool" % old)
	var future = JSON.parse_string(JSON.stringify(d))
	future["version"] = 4
	eq(_camp(1).load_dict(future), "unsupported campaign version", "a newer save is refused")


func test_the_sectors_and_the_spool_survive_a_save() -> void:
	var c := _camp(2)
	var ship := _ship()
	_fuel_to(ship, 9)
	var a := c.current
	var b := _next(c)
	var sa = c.current_sector()
	sa.pois[0]["state"] = "done"
	sa.ship_pos = Vector2(5000.0, 6000.0)
	sa.ship_vel = Vector2(10.0, -4.0)
	c.start_jump(b, ship)
	c.tick_jump(3.0, false, ship)
	var d = JSON.parse_string(JSON.stringify(c.to_dict()))
	var c2 := _camp(55)
	eq(c2.load_dict(d), "", "loads")
	eq(c2.spool["to"], b, "the spool is still aimed at the same node")
	near(float(c2.spool["t"]), 3.0, "3 s charged")
	eq(c2.tick_jump(4.9, false, ship), "spooling", "7.9 s")
	eq(c2.tick_jump(0.2, false, ship), "jumped", "it fires after the load")
	eq(c2.current, b, "there")
	var back = c2.sector_at(a)
	eq(back.pois[0]["state"], "done", "the sector left behind kept its POI states")
	eq(back.ship_pos, Vector2(5000.0, 6000.0), "and where the ship was")
	eq(back.ship_vel, Vector2(10.0, -4.0), "and its speed")
	var ids: Array = c2.sectors.keys()
	ids.sort()
	var want: Array = [a, b]
	want.sort()
	eq(ids, want, "the visited sectors")


func test_ambient_state_survives_a_save() -> void:
	var c := _camp(1)
	var ship := _ship()
	var s = Sector.generate(1, c.node("n01"), "clans", _busy())
	s.tick(100.0, ship)
	c.sectors["n01"] = s
	var d = JSON.parse_string(JSON.stringify(c.to_dict()))
	var c2 := _camp(1)
	eq(c2.load_dict(d), "", "loads")
	var t = c2.sector_at("n01")
	eq(t.ambient.size(), 1, "the ship about is saved")
	near(t.ambient[0]["pos"].x, s.ambient[0]["pos"].x, "its place", 1e-3)
	eq(t.ambient[0]["event_type"], s.ambient[0]["event_type"], "its kind")
	# the loaded sector uses the default data (no forced chance), so compare the rng stream instead
	eq(t.rng.state, s.rng.state, "and the ambient rng goes on where it was")
	near(t.clock, s.clock, "the clock")


func test_a_malformed_save_is_refused_and_changes_nothing() -> void:
	var c := _camp(1)
	var ship := _ship()
	_go(c, _next(c), ship)
	var good = JSON.parse_string(JSON.stringify(c.to_dict()))
	var bad_cases := {
		"sectors": [[], "bad campaign sectors", "sectors a list"],
		"sectors_node": [{"nowhere": {}}, "bad campaign sectors", "a sector for a node that is not on the map"],
		"sectors_body": [{"n01": {"pois": 1}}, "bad campaign sectors", "a sector with no body"],
		"spool": [{"to": "nowhere", "t": 1.0}, "bad campaign jump drive", "a spool aimed at nothing"],
		"spool_list": [[1], "bad campaign jump drive", "a spool that is a list"],
	}
	for k in bad_cases:
		var e = JSON.parse_string(JSON.stringify(good))
		e["sectors" if k.begins_with("sectors") else "spool"] = bad_cases[k][0]
		var c2 := _camp(3)
		var before := c2.current
		eq(c2.load_dict(e), bad_cases[k][1], bad_cases[k][2])
		eq(c2.current, before, bad_cases[k][2] + ": nothing changed")
		eq(c2.sectors.size(), 0, bad_cases[k][2] + ": no sector kept")
	var e = JSON.parse_string(JSON.stringify(good))
	e["sectors"][c.current]["pois"] = {"p0": "maybe"}
	eq(_camp(3).load_dict(e), "bad campaign sectors", "a POI state that is neither new nor done")
	var f = JSON.parse_string(JSON.stringify(good))
	f["sectors"][c.current]["pois"]["p99"] = "done"
	eq(_camp(3).load_dict(f), "", "a POI this layout does not have is ignored")


# --- the data ------------------------------------------------------------------------------------------------

func test_sectors_json_is_sound() -> void:
	var cfg: Dictionary = Sector.config()
	var types: Dictionary = cfg["poi_types"]
	var want := ["station", "store", "trader", "distress", "wreck", "abandoned_station", "mining_field", "unknown", "pirate_nest", "concord_checkpoint", "anomaly", "quest"]
	for t in want:
		check(types.has(t), "POI type %s exists" % t)
	eq(types.size(), want.size(), "and no others")
	for t in types:
		var d: Dictionary = types[t]
		var vis = d["visibility"]
		for v in ([vis] if vis is String else vis.keys()):
			check(Sector.VISIBILITIES.has(v), "%s: visibility %s" % [t, v])
		var ev = d["event"]
		for e in ([ev] if ev is String else ev.keys()):
			check(Events.EVENT_TYPES.has(e), "%s: event type %s is one events.gd knows" % [t, e])
		check(d.has("label") and int(d["max"]) >= 1, "%s: a label and a max" % t)
	var map_types: Dictionary = Campaign.config()["types"]
	for t in map_types:
		check(cfg["nodes"].has(t), "node type %s has a mix" % t)
	for t in cfg["nodes"]:
		var n: Dictionary = cfg["nodes"][t]
		check(types.has(n["main"]), "%s: main %s is a POI type" % [t, n["main"]])
		for w in n["weights"]:
			check(types.has(w), "%s: weight for %s, a POI type" % [t, w])
		check(int(n["count"][0]) >= 2 and int(n["count"][1]) <= 6 and int(n["count"][0]) <= int(n["count"][1]), "%s: a count within 2 to 6" % t)
		check(float(n["density"]) > 0.0, "%s: a density" % t)
		var debris: Array = Content.read(DriftDebris.PATH)["types"].map(func(x): return x["id"])
		for k in n["debris"]:
			check(debris.has(k), "%s: debris theme names a real debris type, %s" % [t, k])
	var landmarks := {}
	for p in Campaign.config()["places"]:
		landmarks[str(p["id"])] = true
	for r in cfg["regions"]:
		var lm := str(cfg["regions"][r]["landmark"])
		check(lm == "" or landmarks.has(lm), "region %s: landmark %s is a place" % [r, lm])
		for k in cfg["regions"][r]["ambient"]:
			check(["trader", "patrol", "pirate"].has(k), "region %s: ambient kind %s" % [r, k])
	eq(cfg["size"], 24000, "24,000 px")
	eq(cfg["poi"]["trigger"], 800, "the trigger distance")
	eq(cfg["poi"]["dist"], [3000.0, 12000.0], "the POI distances")
	eq(cfg["radar"]["visual"], 1500, "the visual range")
	eq(cfg["radar"]["helm"], 3000, "the helm's radar")
	eq(cfg["ambient"]["every"], 90, "the ambient period")
	eq(cfg["current"]["speed"], [20.0, 60.0], "the current")
	eq(Campaign.config()["jump"]["spool"], 8.0, "the spool")
	eq(Campaign.config()["jump"]["hostile_range"], 2000.0, "the hostile range")
