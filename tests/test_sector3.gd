extends "res://tests/base_test.gd"
## Sector space step 3, the Raft content (docs/CONTENT.md section 11): the Salvage Intake Mk2 and Mk3, the Radar Mk1 to Mk3 and
## the Tractor Beam Mk1 and Mk2 in the data (stats, recipes, Meridian's stock), the radar rules for them (ranges, naming, Mk3 seeing
## hidden contacts, a shot-off dish blinding the console, threat skulls from Mk2 up), the intake pull radii, the tractor
## hauling debris to the nearest intake while Q is held, the income per minute (Mk1 idle, Mk3 chasing), and the quest sites that
## put each homeland's tech quest on the map.

const Campaign = preload("res://scripts/space/campaign.gd")
const Content = preload("res://scripts/data/content.gd")
const DebrisView = preload("res://scripts/view/debris_view.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const DriftDebris = preload("res://scripts/space/drift_debris.gd")
const Helm = preload("res://scripts/space/helm.gd")
const HelpPanel = preload("res://scripts/ui/help_panel.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Radar = preload("res://scripts/space/radar.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Tractor = preload("res://scripts/space/tractor.gd")
const Wall = preload("res://tests/fixture_wall.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const HERE := Vector2(10000.0, 10000.0)
const RAFT_IDS: Array[String] = ["intake_mk2", "intake_mk3", "radar_mk1", "radar_mk2", "radar_mk3", "tractor_mk1", "tractor_mk2"]


func near(got: float, want: float, msg: String, eps := 1e-3) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


# --- the rig -------------------------------------------------------------------------------------------------------

## A ship with a 21-wide flat wall (u -10..10; the starter is 20 wide) facing up, floor behind it, a helm at u 8..9, a reactor
## with power to spare and a cable row behind the wall that every part sits on. `parts`: [[id, u]] hull mounts through the wall,
## the outside half's left edge at cell u (an inside half starts at the same u). Returns {ship, uid: {id: uid}}.
func _rig(parts: Array) -> Dictionary:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(31, 31), defs)
	g.fill_circle_hull(15.0)
	var ship := Ship.new("Rig", g)
	ship.inventory.load_dict({"scrap": 800, "copper": 40})
	for u in range(-10, 11):
		g.force_tile(Wall.at(0, u, 0), "wall")
		for d in range(1, 7):
			g.force_tile(Wall.at(0, u, d), "floor")
	var uids := {}
	var order := []
	for p in parts:
		var def: Dictionary = ship.components.def(str(p[0]))
		var out: Array = def["mount"]["outside"]
		var uid := ship.components.place_mount(g, str(p[0]), Wall.corner(0, int(p[1]), int(p[1]) + int(out[0]) - 1, -int(out[1]), -1), 0)
		check(uid >= 0, "%s goes in at u %d" % [p[0], int(p[1])])
		uids[str(p[0])] = uid
		order.append(uid)
	check(ship.components.place(g, "helm", Wall.corner(0, 8, 9, 1, 2), 0) >= 0, "the helm goes in")
	check(ship.components.place(g, "reactor_mk1", Wall.corner(0, 6, 9, 3, 6), 0) >= 0, "the reactor goes in")
	ship.components.by_id["reactor_mk1"]["power"] = 30
	for u in range(-10, 10):
		ship.cables.place(g, Wall.at(0, u, 1))
	ship.cables.place(g, Wall.at(0, 6, 2))
	ship.cables.place(g, Wall.at(0, 6, 3))
	ship.mark_dirty()
	ship.refresh()
	return {"ship": ship, "uid": uids, "order": order}


## A DriftDebris whose current runs due south with no wobble, so the rig (facing up) meets it head on.
func _dd(seed_value := 1, speed := 40.0) -> DriftDebris:
	var cfg: Dictionary = Content.read(DriftDebris.PATH).duplicate(true)
	cfg["current"]["angle"] = 90
	cfg["current"]["wobble_deg"] = 0
	cfg["current"]["speed_wobble"] = 0
	cfg["current"]["speed"] = speed
	return DriftDebris.new(seed_value, cfg)


func _run(d: DriftDebris, ship, seconds: float) -> void:
	for i in roundi(seconds / 0.05):
		d.step(ship, 0.05)


## The ship's px of the middle of the outside half of mount `uid` (the rig is upright at the build view's px).
func _mouth(ship, uid: int) -> Vector2:
	var cells: Array = ship.components.instances[uid]["out_cells"]
	var sum := Vector2.ZERO
	for c in cells:
		sum += Vector2(c) * 32.0 + Vector2(16.0, 16.0)
	return DriftDebris._origin(ship) + sum / float(cells.size())


func _poi(id: String, vis: String, d: float, type := "wreck") -> Dictionary:
	return {"id": id, "type": type, "name": type, "pos": HERE + Vector2.RIGHT * d, "visibility": vis, "event_type": "wreck_field", "state": "new", "enemy": "", "main": false}


func _sector(pois: Array):
	var s = Campaign.new(1).sector_at("n01")
	s.pois = pois
	s.ambient = []
	s.cfg = s.cfg.duplicate()
	s.cfg.erase("far")  # exactly these POIs: no far ones
	s.ship_pos = HERE
	return s


func _ids(list: Array) -> Array:
	return list.map(func(c): return c["poi"]["id"])


# --- the data ------------------------------------------------------------------------------------------------------

func test_the_raft_parts_have_the_numbers_of_the_spec() -> void:
	var c = Ship.new_starter().components
	for id in RAFT_IDS:
		check(c.has(id), id + " exists")
		check(c.is_mount(id), id + " is a hull mount")
	# pull radius 3 / 4 / 5 cells, power -1 / -1 / -2, a 4x2 mouth out and in
	for row in [["intake_mk1", 3, -1, 1], ["intake_mk2", 4, -1, 2], ["intake_mk3", 5, -2, 3]]:
		var d: Dictionary = c.def(row[0])
		eq([d["family"], d["size"], d["mount"]["outside"], int(d["stats"]["pull_radius"]), d["power"], d["tier"], d["line"]], ["intake", [4, 2], [4, 2], row[1], row[2], row[3], "standard"], row[0])
	# radar: range 6,000 / 10,000 / 16,000 px, identify from Mk2, see_hidden on the Mk3; an inside console and an outside dish
	for row in [["radar_mk1", 6000, 0, 0, [2, 2]], ["radar_mk2", 10000, 1, 0, [4, 2]], ["radar_mk3", 16000, 1, 1, [4, 2]]]:
		var d: Dictionary = c.def(row[0])
		eq([d["family"], d["size"], d["mount"]["outside"], int(d["stats"]["radar_range"]), int(d["stats"].get("identify", 0)), int(d["stats"].get("see_hidden", 0))],
			["radar", row[4], [2, 2], row[1], row[2], row[3]], row[0])
	# the tractor: a turret mount, 300 / 450 px
	for row in [["tractor_mk1", 300, 1], ["tractor_mk2", 450, 2]]:
		var d: Dictionary = c.def(row[0])
		eq([d["family"], d["size"], d["mount"]["outside"], int(d["stats"]["tractor_range"]), d["tier"]], ["tractor", [4, 2], [4, 2], row[1], row[2]], row[0])
		check(float(d["stats"]["tractor_pull"]) > 90.0, row[0] + " hauls faster than an intake pulls (90 px/s)")
	check(float(c.def("tractor_mk2")["stats"]["tractor_pull"]) > float(c.def("tractor_mk1")["stats"]["tractor_pull"]), "the Mk2 hauls faster")
	for id in ["radar_mk2", "radar_mk3", "tractor_mk1", "tractor_mk2", "intake_mk2", "intake_mk3"]:
		check(c.def(id)["power"] < 0, id + " draws power")


func test_the_recipes_are_blueprints_and_meridian_sells_them_at_the_price_rule() -> void:
	var ship := Ship.new_starter()
	var recipes := {}
	for r in Content.list("recipes"):
		recipes[r["id"]] = r
	for id in RAFT_IDS:
		check(recipes.has(id), id + " has a recipe")
		check(not ship.crafting.is_known(id), id + " is a blueprint to find or buy, not known at the start")
		for m in recipes[id]["materials"]:
			check(Content.has("materials", m), "%s: %s is a material" % [id, m])
			check(not m in ["military_circuit", "gate_alloy", "void_crystal"], "%s: Mk1-Mk3 use common and regional materials only" % id)
	var c := Campaign.new(1)
	var values: Dictionary = c.cfg["values"]["tier"]
	var mk1 := {"intake": 120.0, "radar": 130.0, "tractor": 160.0}
	for id in RAFT_IDS:
		var d: Dictionary = ship.components.def(id)
		var raw: float = mk1[d["family"]] * float(values[str(d["tier"])]) / float(values["1"])
		eq(c.stock_price("meridian", id), roundi(raw / 10.0) * 10, "Meridian sells %s at the price rule (%s)" % [id, raw])
	for st in c.cfg["stations"]:
		for id in c.cfg["stations"][st]["stock"]:
			if id.begins_with("radar_") or id.begins_with("tractor_") or id.begins_with("intake_"):
				check(int(ship.components.def(id)["tier"]) <= 3, "%s sells %s: nothing above tier 3 is sold" % [st, id])
	check(c.stock_price("rusthold", "radar_mk1") == 0, "Rusthold sells no Concord radar")


# --- radar ---------------------------------------------------------------------------------------------------------

## The rig with radar `id` through the wall, its outside half at u -9 (a console wider than its dish pokes out of it by the centring rule).
func _radar_rig(id: String) -> Dictionary:
	return _rig([[id, -9]])


func test_the_radar_parts_set_the_ranges_and_what_they_identify() -> void:
	for row in [["radar_mk1", 6000.0, 0.0, 0.0], ["radar_mk2", 10000.0, 10000.0, 0.0], ["radar_mk3", 16000.0, 16000.0, 16000.0]]:
		var rig := _radar_rig(row[0])
		eq(Radar.ranges(rig["ship"]), {"range": row[1], "identify_range": row[2], "hidden_range": row[3]}, row[0])
	var none := _rig([])
	eq(Radar.ranges(none["ship"]), {"range": 3000.0, "identify_range": 0.0, "hidden_range": 0.0}, "no radar part: only the helm's Mk0")
	var s = _sector([_poi("a", "signal", 5900.0), _poi("b", "signal", 6100.0), _poi("c", "signal", 9900.0), _poi("d", "signal", 10100.0), _poi("e", "signal", 15900.0), _poi("f", "signal", 16100.0)])
	eq(_ids(Radar.contacts(s, _radar_rig("radar_mk1")["ship"])), ["a"], "Mk1 sees 6,000 px")
	eq(_ids(Radar.contacts(s, _radar_rig("radar_mk2")["ship"])), ["a", "b", "c"], "Mk2 sees 10,000 px")
	eq(_ids(Radar.contacts(s, _radar_rig("radar_mk3")["ship"])), ["a", "b", "c", "d", "e"], "Mk3 sees 16,000 px")
	var m1 := Radar.contacts(s, _radar_rig("radar_mk1")["ship"])
	eq(m1[0]["known_type"], Radar.CONTACT, "Mk1 shows 'contact' and the bearing, not what it is")
	near(float(m1[0]["bearing"]), PI / 2.0, "the bearing")
	check(not m1[0]["scanned"], "and does not scan")
	var m2 := Radar.contacts(s, _radar_rig("radar_mk2")["ship"])
	eq([m2[0]["known_type"], m2[2]["known_type"], m2[2]["scanned"]], ["wreck", "wreck", true], "Mk2 names what it sees, out to its whole range")


func test_mk3_sees_hidden_contacts_within_its_range_and_the_others_only_up_close() -> void:
	var s = _sector([_poi("near", "hidden", 1400.0), _poi("mid", "hidden", 9000.0), _poi("far", "hidden", 15000.0), _poi("out", "hidden", 17000.0)])
	for id in ["radar_mk1", "radar_mk2"]:
		eq(_ids(Radar.contacts(s, _radar_rig(id)["ship"])), ["near"], "%s: a hidden contact shows only within 1,500 px" % id)
	var list := Radar.contacts(s, _radar_rig("radar_mk3")["ship"])
	eq(_ids(list), ["near", "mid", "far"], "Mk3 sees hidden contacts to 16,000 px, and not beyond")
	eq([list[0]["via"], list[1]["via"], list[1]["known_type"]], ["visual", "radar", "wreck"], "by radar, and named: it identifies")
	eq(_ids(Radar.contacts(s, _rig([])["ship"])), ["near"], "the helm's Mk0: up close only")
	# a see_hidden radar that does not identify shows just a contact
	eq(Radar.contacts_for(s, 16000.0, 0.0, false, 16000.0)[1]["known_type"], Radar.CONTACT, "seeing hidden is not naming")


func test_a_shot_off_dish_a_cut_link_or_no_power_blinds_the_radar() -> void:
	var rig := _radar_rig("radar_mk3")
	var ship: Ship = rig["ship"]
	var uid: int = rig["uid"]["radar_mk3"]
	var s = _sector([_poi("w", "signal", 12000.0), _poi("h", "hidden", 9000.0)])
	eq(_ids(Radar.contacts(s, ship)), ["h", "w"], "the Mk3 sees both")
	ship.components.instances[uid]["out_hp"] = 0  # the dish, the outside half
	eq(Radar.ranges(ship), {"range": 3000.0, "identify_range": 0.0, "hidden_range": 0.0}, "a shot-off dish blinds the console: only the helm's Mk0 is left")
	eq(_ids(Radar.contacts(s, ship)), [], "and the markers follow it")
	ship.repair(uid)
	near(Radar.ranges(ship)["range"], 16000.0, "repaired, it sees again")
	var link: Vector2i = ship.components.instances[uid]["link"][0]
	ship.grid.force_tile(link, "")  # the wall between the halves is breached
	near(Radar.ranges(ship)["range"], 3000.0, "a breached link cuts the console off")
	ship.grid.force_tile(link, "wall")
	near(Radar.ranges(ship)["range"], 16000.0, "patched")
	for u in range(-10, -6):  # the cells under the console
		ship.cables.remove(Wall.at(0, u, 1))
	ship.mark_dirty()
	near(Radar.ranges(ship)["range"], 3000.0, "and an unwired console has no power")


func test_a_radar_that_identifies_names_a_passing_ship_and_rates_a_fighter_in_skulls() -> void:
	var c := Campaign.new(1)
	var s = c.current_sector()
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	ship.components.by_id["helm"]["stats"] = {"radar_range": 10000, "identify": 1}  # a Mk2-like radar on the starter
	s.pois = []
	s.ship_pos = HERE
	var kinds := {"pirate": 3000.0, "patrol": 4000.0, "trader": 5000.0}
	var contacts := []
	for k in kinds:
		contacts.append({"id": "a_" + k, "type": "unknown", "name": "Unknown ship", "pos": HERE + Vector2(kinds[k], 0.0), "visibility": "signal", "event_type": k,
			"state": "new", "enemy": "", "main": false, "ambient": true, "vel": Vector2.ZERO, "ttl": 100.0})
	s.ambient = contacts
	var seen := {}
	for ct in Radar.contacts(s, ship):
		seen[ct["poi"]["event_type"]] = ct
	check(seen["pirate"]["scanned"], "an identifying radar scans what it sees")
	eq([Radar.title(seen["pirate"]), Radar.title(seen["patrol"]), Radar.title(seen["trader"])], ["Pirate ship", "Patrol ship", "Trader"], "a passing ship is named by its kind")
	var st = c.rng.state
	var n := Radar.threat(c, ship, seen["pirate"])
	check(n >= 1 and n <= 5, "a pirate is rated 1 to 5 skulls: %d" % n)
	eq(c.rng.state, st, "looking at a contact moves no rng")
	var at = c.rng.state
	var design: String = c.fight_path("tier", "pirate")
	c.rng.state = at
	eq(n, int(Shipgen.threat_of(design, ship)["skulls"]), "it is the rating of the ship a fight here would send (Shipgen.threat_of)")
	check(Radar.threat(c, ship, seen["patrol"]) >= 1, "so is a patrol")
	eq(Radar.threat(c, ship, seen["trader"]), 0, "a trader shows no skulls")
	var nest := _poi("nest", "signal", 2000.0, "pirate_nest")
	s.pois = [nest]
	var nests: Array = Radar.contacts(s, ship).filter(func(ct): return ct["poi"]["id"] == "nest")
	check(Radar.threat(c, ship, nests[0]) >= 1, "a pirate nest is rated too")
	var odd := _poi("odd", "signal", 2000.0, "unknown")
	s.pois = [odd]
	eq(Radar.threat(c, ship, Radar.contacts(s, ship)[0]), 0, "an unknown ship could be anything: no skulls")
	# a radar that does not identify rates nothing
	var plain := Ship.from_design(RUSTBUCKET)
	var blind := {}
	for ct in Radar.contacts(_with_ambient(s, contacts), plain):
		if ct["poi"]["event_type"] == "pirate":
			blind = ct
	check(not blind.is_empty() and not blind["scanned"], "the helm's Mk0 does not scan")
	eq(Radar.threat(c, plain, blind), 0, "and rates nothing")
	eq(Radar.title(blind), "Contact", "nor names it")


func _with_ambient(s, contacts: Array):
	s.pois = []
	s.ambient = contacts
	return s


# --- intakes -------------------------------------------------------------------------------------------------------

func test_intake_pull_radii_are_three_four_and_five_cells() -> void:
	for row in [["intake_mk1", 3], ["intake_mk2", 4], ["intake_mk3", 5]]:
		var rig := _rig([[row[0], -2]])
		var ship: Ship = rig["ship"]
		var m: Rect2 = _dd().intakes(ship)[0]["rect"]
		eq(_dd().intakes(ship)[0]["pull"], float(row[1]) * 32.0, row[0] + ": the pull radius in px")
		var reach: float = float(row[1]) * 32.0
		var r := 12.0  # a scrap chunk (24 px) is 12 px in radius
		var d := _dd()
		d.add_piece("scrap_chunk_s", Vector2(m.end.x + reach - 6.0, m.position.y - 120.0), Vector2(0, 40))  # just inside the radius, beside the mouth
		_run(d, ship, 6.0)
		eq(d.picked, 1, "%s draws in a piece passing %d cells (less a bit) from the side of its mouth" % [row[0], row[1]])
		d = _dd()
		d.add_piece("scrap_chunk_s", Vector2(m.end.x + reach + r + 20.0, m.position.y - 120.0), Vector2(0, 40))  # just outside
		_run(d, ship, 6.0)
		eq(d.picked, 0, "but not one a bit beyond it")


# --- the tractor ---------------------------------------------------------------------------------------------------

## Two Mk1 intakes at u -10 and u 4 and a tractor `id` between them at u -3: [rig, left mouth uid, right mouth uid, tractor uid].
func _tractor_rig(id := "tractor_mk2") -> Array:
	var rig := _rig([["intake_mk1", -10], [id, -3], ["intake_mk1", 4]])
	return [rig, rig["order"][0], rig["order"][2], rig["order"][1]]


## A spawner with no natural spawning (the flow floor of data/debris.json would put a stray piece in the mouth): only the pieces a test adds.
func _lone_dd() -> DriftDebris:
	var d := _dd()
	d.cfg["spawn"]["max_alive"] = 0
	return d


func test_q_hauls_debris_toward_the_nearest_intake() -> void:
	var t := _tractor_rig()
	var ship: Ship = t[0]["ship"]
	var emitter: Vector2 = Tractor.beams(ship, DriftDebris._origin(ship))[0]["at"]
	var left := _mouth(ship, t[1])
	var right := _mouth(ship, t[2])
	# two pieces 200 px out from the tractor, one nearer the left mouth, one nearer the right, both beyond an intake's own pull;
	# the current (south) alone would drop them on the wall between the mouths
	for case in [[-30.0, left, t[1]], [30.0, right, t[2]]]:
		var d := _lone_dd()
		d.tractor_on = true
		var p := d.add_piece("scrap_chunk_s", emitter + Vector2(case[0], -200.0), Vector2.ZERO)
		_run(d, ship, 8.0)
		check(not d.pieces.has(p), "the piece is hauled in")
		var e := d.take_events()
		check(e.size() == 1 and e[0]["uid"] == case[2], "into the nearest intake (uid %d): %s" % [case[2], str(e)])
	var off := _lone_dd()
	var q := off.add_piece("scrap_chunk_s", emitter + Vector2(-30.0, -200.0), Vector2.ZERO)
	_run(off, ship, 8.0)
	check(off.picked == 0, "with Q up the same piece is not drawn in")
	check(off.beam_lines.is_empty() and off.beams_on.is_empty(), "no beam shows")
	var on := _lone_dd()
	on.tractor_on = true
	on.add_piece("scrap_chunk_s", emitter + Vector2(-30.0, -200.0), Vector2.ZERO)
	on.step(ship, 0.05)
	eq(on.beams_on, [t[3]], "the beam that works is on")
	check(on.beam_lines.size() == 1 and on.beam_lines[0]["uid"] == t[3], "and is drawn to the piece it holds")
	near(on.beam_lines[0]["from"].distance_to(emitter), 0.0, "from its emitter", 1e-3)
	check(on.beam_aims()[t[3]].dot((Vector2(-30.0, -200.0)).normalized()) > 0.99, "the head turns toward the piece")


func test_the_beam_reaches_300_px_for_the_mk1_and_450_for_the_mk2() -> void:
	for row in [["tractor_mk1", 300.0], ["tractor_mk2", 450.0]]:
		var t := _tractor_rig(row[0])
		var ship: Ship = t[0]["ship"]
		var origin := DriftDebris._origin(ship)
		var beams := Tractor.beams(ship, origin)
		eq(beams.size(), 1, row[0] + ": one beam")
		eq(float(beams[0]["range"]), row[1], row[0] + ": its range")
		var mouths := _dd().intakes(ship)
		var r := 12.0
		var at: Vector2 = beams[0]["at"]
		check(not Tractor.pull(beams, mouths, at + Vector2(0.0, -(row[1] - 5.0)), r).is_empty(), "%s hauls a piece 5 px inside its range" % row[0])
		check(not Tractor.pull(beams, mouths, at + Vector2(0.0, -(row[1] + r - 2.0)), r).is_empty(), "the edge of the piece counts")
		check(Tractor.pull(beams, mouths, at + Vector2(0.0, -(row[1] + r + 10.0)), r).is_empty(), "%s leaves one beyond it alone" % row[0])
		var d := _dd()
		d.tractor_on = true
		var far := d.add_piece("scrap_chunk_s", at + Vector2(0.0, -(row[1] + 60.0)), Vector2.ZERO)
		d.step(ship, 0.5)
		check(far["vel"].length() < 45.0, "%s: a piece beyond the range only drifts with the current: %s" % [row[0], str(far["vel"])])
	var mk1 := _tractor_rig("tractor_mk1")
	var mk2 := _tractor_rig("tractor_mk2")
	var s1: Ship = mk1[0]["ship"]
	var s2: Ship = mk2[0]["ship"]
	var piece_at := Vector2(0.0, -380.0)  # 380 px out: the Mk2 reaches it, the Mk1 does not
	var d1 := _dd()
	d1.tractor_on = true
	var p1 := d1.add_piece("scrap_chunk_s", Tractor.beams(s1, DriftDebris._origin(s1))[0]["at"] + piece_at, Vector2.ZERO)
	d1.step(s1, 0.5)
	var d2 := _dd()
	d2.tractor_on = true
	var p2 := d2.add_piece("scrap_chunk_s", Tractor.beams(s2, DriftDebris._origin(s2))[0]["at"] + piece_at, Vector2.ZERO)
	d2.step(s2, 0.5)
	check(p1["vel"].length() < 45.0 and p2["vel"].length() > 60.0, "at 380 px only the Mk2 hauls: %s and %s" % [str(p1["vel"]), str(p2["vel"])])


func test_a_tractor_that_cannot_work_or_has_no_intake_hauls_nothing() -> void:
	var t := _tractor_rig()
	var ship: Ship = t[0]["ship"]
	var origin := DriftDebris._origin(ship)
	var emitter: Vector2 = Tractor.beams(ship, origin)[0]["at"]
	ship.components.instances[t[3]]["out_hp"] = 0  # the emitter is shot off
	eq(Tractor.beams(ship, origin), [], "a shot-off emitter: no beam")
	ship.repair(t[3])
	check(not Tractor.beams(ship, origin).is_empty(), "repaired")
	ship.components.instances[t[3]]["status"] = "overheated"
	eq(Tractor.beams(ship, origin), [], "an overheated tractor: no beam")
	ship.components.instances[t[3]]["status"] = "ok"
	for u in range(-3, 1):  # the cells under the tractor's inside half
		ship.cables.remove(Wall.at(0, u, 1))
	ship.mark_dirty()
	ship.refresh()
	eq(Tractor.beams(ship, origin), [], "an unpowered tractor: no beam")
	# no intake works: there is nowhere to haul to
	var lone := _rig([["tractor_mk2", -3]])
	var d := _dd()
	d.tractor_on = true
	var p := d.add_piece("scrap_chunk_s", Tractor.beams(lone["ship"], DriftDebris._origin(lone["ship"]))[0]["at"] + Vector2(0.0, -150.0), Vector2.ZERO)
	d.step(lone["ship"], 0.5)
	check(p["vel"].length() < 45.0 and d.beam_lines.is_empty(), "a tractor with no intake leaves the debris to the current")


func test_q_runs_the_tractor_in_play_mode_and_not_in_build_mode_or_a_fight() -> void:
	var sim := ShipSim.new()
	var build := BuildMode.new()
	build.sim = sim
	var view := DebrisView.new()
	view.sim = sim
	view.build = build
	view.q_held = true
	build.build_on = true
	view.frame(0.1)
	check(view.debris == null or not view.debris.tractor_on, "build mode: Q does nothing")
	build.build_on = false
	view.q_held = false
	view.frame(0.1)
	check(view.debris != null and not view.debris.tractor_on, "play mode, Q up: the beams are off")
	view.q_held = true
	view.frame(0.1)
	check(view.debris.tractor_on, "play mode, Q held: they are on")
	build.combat = true
	view.frame(0.1)
	check(not view.debris.tractor_on, "in a fight Q is the utility ability: the tractor is off")
	build.combat = false
	view.frame(0.1)
	check(view.debris.tractor_on, "and back on after it")
	view.q_held = false
	view.frame(0.1)
	check(not view.debris.tractor_on and build.mount_fx.is_empty(), "Q up again")
	view.free()
	build.free()
	sim.free()


func test_the_help_screen_lists_the_tractor_key() -> void:
	check(HelpPanel.keys_text().contains("Q (hold)"), "How to play lists Q (hold)")
	check(HelpPanel.all_text().to_lower().contains("tractor"), "and says what it does")


# --- income --------------------------------------------------------------------------------------------------------

## Scrap, copper and polymer a minute that `rig` collects in `minutes` simulated minutes over `seeds` seeds. `chase`: fly with the
## mouth leading toward the nearest piece beyond 420 px ahead (else upstream), at 160 px/s, turning 120 degrees a second, with
## Q held when `tractor`; else the ship drifts, still, with the mouth facing the stream.
func _income(rig: Dictionary, chase: bool, tractor: bool, seeds: int, minutes: float, first_seed := 1) -> Dictionary:
	var ship: Ship = rig["ship"]
	var pivot := Helm.pivot_of(ship.grid)
	var out := Vector2(Mounts.outward(0))
	var got := {"scrap": 0.0, "copper": 0.0, "polymer": 0.0}
	for s in seeds:
		var d := _dd(first_seed + s)
		var pos := Vector2(12000.0, 12000.0)
		var vel := Vector2.ZERO
		var angle := (-d.current_dir()).angle() - out.angle()  # the mouth faces upstream
		d.frame = Helm.frame_of(ship, pos, angle, pivot)
		d.view_centre = d.frame * ship.world_pos
		d.prewarm(ship)
		d.tractor_on = tractor
		var before := {}
		for k in got:
			before[k] = ship.inventory.count(k)
		var target := -1
		for i in roundi(1200.0 * minutes):
			if chase:
				var face := out.rotated(angle)
				var found = null
				for p in d.pieces:
					if int(p["uid"]) == target:
						found = p
				if found != null and (found["pos"].distance_to(pos) < 420.0 or absf(face.angle_to(found["pos"] - pos)) > deg_to_rad(80.0)):
					found = null
				if found == null:
					target = -1
					var best := 1100.0
					for p in d.pieces:
						var off: Vector2 = p["pos"] - pos
						if off.length() < best and off.length() > 420.0 and absf(face.angle_to(off)) < deg_to_rad(70.0):
							best = off.length()
							found = p
					if found != null:
						target = int(found["uid"])
				var want: Vector2 = -d.current_dir() if found == null else (found["pos"] - pos).normalized()
				var step := deg_to_rad(120.0) * 0.05
				angle += clampf(face.angle_to(want), -step, step)
				vel = out.rotated(angle) * (160.0 if found != null else 60.0)
				pos += vel * 0.05
			d.frame = Helm.frame_of(ship, pos, angle, pivot)
			d.frame_vel = vel
			d.view_centre = d.frame * ship.world_pos
			d.step(ship, 0.05)
		for k in got:
			got[k] += float(ship.inventory.count(k) - int(before[k]))
	for k in got:
		got[k] = got[k] / float(seeds) / minutes
	return got


func test_one_mk1_intake_drifting_idle_brings_twenty_to_thirty_five_scrap_a_minute_and_mk3_chasing_about_triple() -> void:
	var idle := _income(_rig([["intake_mk1", -2]]), false, false, 8, 1.5)
	var chase := _income(_rig([["intake_mk3", -2]]), true, false, 8, 1.5)
	var both := _income(_rig([["intake_mk3", -6], ["tractor_mk2", 0]]), true, true, 8, 1.5)
	print("sector3: scrap a minute: Mk1 idle %.1f (copper %.1f, polymer %.1f), Mk3 chasing %.1f, Mk3 chasing with the Mk2 tractor %.1f" % [idle["scrap"], idle["copper"], idle["polymer"], chase["scrap"], both["scrap"]])
	check(idle["scrap"] >= 18.0 and idle["scrap"] <= 50.0, "an idle Mk1 earns about 20-50 scrap a minute (the steady flow of Beta 3: spawn every 1.1 s, 70 pieces; the floor of the flow, data/debris.json spawn.flow_min, lifted the top from 35): %.1f" % idle["scrap"])
	check(idle["copper"] + idle["polymer"] >= 2.0, "and a bit of copper and polymer: %.1f and %.1f" % [idle["copper"], idle["polymer"]])
	check(chase["scrap"] >= 1.5 * idle["scrap"] and chase["scrap"] <= 3.5 * idle["scrap"], "Mk3 chasing is about triple (a fast ship meets more pieces): %.1f against %.1f" % [chase["scrap"], idle["scrap"]])
	check(both["scrap"] >= 1.1 * chase["scrap"], "and the tractor adds to it: %.1f against %.1f" % [both["scrap"], chase["scrap"]])


# --- quest sites ---------------------------------------------------------------------------------------------------

## The homeland regions and the id of the quest each one has: {region id: quest event id}.
func _homeland_quests() -> Dictionary:
	var out := {}
	for ev in Content.events():
		if str(ev.get("type", "")) != "quest":
			continue
		var req: Dictionary = ev.get("requires", {})
		for f in (req.get("flag", []) if req.get("flag") is Array else [req.get("flag", "")]):
			if str(f).begins_with("in_"):
				out[str(f).trim_prefix("in_")] = str(ev["id"])
	return out


func test_quest_sites_are_made_only_where_there_is_a_quest_and_often_enough_there() -> void:
	var quests := _homeland_quests()
	eq(quests.size(), 10, "ten homeland tech quests")
	for id in quests:
		var r: Dictionary = {}
		for reg in Content.regions():
			if reg["id"] == id:
				r = reg
		check(not r.is_empty() and str(r.get("home_species", "")) != "", id + " is a homeland region")
		check(Sector.has_quest(id, str(r.get("events", ""))), id + " has a quest, so it gets quest sites")
	check(Sector.has_quest("clan_space", "clan_space") and Sector.has_quest("concord_space"), "the main-line regions have quest sites too: the story's quests (data/packs/story_1) ask for no region")
	var most := 0.0
	for id in quests:
		var with := 0
		var total := 0
		for seed in range(1, 5):
			var c := Campaign.new(seed)
			c.enter_region(id)
			for n in c.drift.nodes:
				total += 1
				if c.sector_at(n["id"]).pois.any(func(p): return p["type"] == "quest"):
					with += 1
		var rate := float(with) / float(total)
		print("sector3: %s: a quest site in %d of %d sectors" % [id, with, total])
		check(rate >= 0.25, "%s: a quest site in at least a quarter of its sectors (%d of %d)" % [id, with, total])
		most = maxf(most, rate)
	check(most < 0.85, "but not in all of them (one quest, once, a region; sectors hold one POI more since Beta 3): %.2f" % most)
	var c := Campaign.new(7)  # Clan space
	var sites := 0
	for n in c.drift.nodes:
		for p in c.sector_at(n["id"]).pois:
			sites += int(p["type"] == "quest")
	check(sites > 0, "Clan space has quest sites now (%d)" % sites)


func test_each_homelands_tech_quest_can_come_up_at_its_quest_site() -> void:
	var quests := _homeland_quests()
	var ids: Array = quests.keys()
	ids.sort()
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	for id in ids:
		var c := Campaign.new(11)
		c.enter_region(id)
		var found := {}
		for n in c.drift.nodes:
			var s = c.sector_at(n["id"])
			for p in s.pois:
				if p["type"] == "quest" and found.is_empty():
					found = {"sector": s, "poi": p}
		check(not found.is_empty(), id + ": a quest site exists in its region")
		if found.is_empty():
			continue
		var s = found["sector"]
		eq([found["poi"]["visibility"], found["poi"]["event_type"]], ["beacon", "quest"], id + ": a quest site is a beacon and runs a quest event")
		check(Radar.contacts_for(s, 0.0, 0.0).any(func(ct): return ct["poi"]["id"] == found["poi"]["id"]), id + ": the site broadcasts, so it is on any ship's radar")
		s.ship_pos = found["poi"]["pos"]
		var res: Dictionary = s.trigger(c, ship)
		check(not res.is_empty() and not res["event"].is_empty(), id + ": flying to the site runs an event")
		if not res.is_empty() and not res["event"].is_empty():
			eq(res["event"]["id"], quests[id], id + ": the homeland's own tech quest")
	# the pick itself: the quest of another homeland never comes up here
	var c := Campaign.new(11)
	c.enter_region("human_core")
	var other := {"id": "n01", "type": "quest", "place": ""}
	for k in 30:
		var ev: Dictionary = c.events.pick(c, other, ship)
		check(ev.is_empty() or ev["id"] == quests["human_core"], "the Human Core never rolls another homeland's quest: %s" % str(ev.get("id")))
