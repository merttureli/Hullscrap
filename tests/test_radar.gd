extends "res://tests/base_test.gd"
## What the ship sees of a sector (scripts/space/radar.gd): beacons from anywhere, signals within the best radar's range,
## hidden contacts only within the visual range, the identification rules, the helm's built-in Mk0 radar of 3,000 px,
## radar parts read from stats.radar_range and stats.identify, and the bearing and the order of the list.

const Campaign = preload("res://scripts/space/campaign.gd")
const Radar = preload("res://scripts/space/radar.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Wall = preload("res://tests/fixture_wall.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const HERE := Vector2(10000.0, 10000.0)


func near(got: float, want: float, msg: String, eps := 1e-3) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## A sector whose POIs are exactly `pois`, with the ship at HERE.
func _sector(pois: Array):
	var s = Campaign.new(1).sector_at("n01")
	s.pois = pois
	s.ambient = []
	s.ship_pos = HERE
	return s


## A POI `d` px east of the ship (or at `dir` x d).
func _poi(id: String, vis: String, d: float, dir := Vector2.RIGHT, type := "wreck") -> Dictionary:
	return {"id": id, "type": type, "name": type, "pos": HERE + dir * d, "visibility": vis, "event_type": "wreck_field", "state": "new", "enemy": "", "main": false}


func _ids(list: Array) -> Array:
	return list.map(func(c): return c["poi"]["id"])


func _find(list: Array, id: String) -> Dictionary:
	for c in list:
		if c["poi"]["id"] == id:
			return c
	return {}


# --- the rules, with radar numbers ---------------------------------------------------------------------------

func test_beacons_are_always_shown_with_their_type() -> void:
	var s = _sector([_poi("b", "beacon", 22000.0, Vector2.DOWN, "station"), _poi("b2", "beacon", 100.0, Vector2.LEFT, "distress")])
	var list := Radar.contacts_for(s, 0.0, 0.0)
	eq(_ids(list), ["b2", "b"], "both beacons, with no radar at all, nearest first")
	eq(_find(list, "b")["known_type"], "station", "a beacon's type is known")
	eq(_find(list, "b2")["known_type"], "distress", "even the near one")
	eq(_find(list, "b")["via"], "beacon", "seen by its broadcast")
	near(float(_find(list, "b")["distance"]), 22000.0, "the distance")


func test_signals_show_within_the_best_radar_range() -> void:
	var s = _sector([_poi("in", "signal", 5900.0), _poi("out", "signal", 6100.0)])
	eq(_ids(Radar.contacts_for(s, 6000.0, 0.0)), ["in"], "a 6,000 px radar sees the one at 5,900 and not the one at 6,100")
	eq(_ids(Radar.contacts_for(s, 10000.0, 0.0)), ["in", "out"], "a 10,000 px radar sees both")
	var c := _find(Radar.contacts_for(s, 6000.0, 0.0), "in")
	eq(c["known_type"], Radar.CONTACT, "a radar that does not identify shows just a contact")
	eq(c["via"], "radar", "seen by radar")


func test_with_no_radar_only_the_visual_range_shows_signals() -> void:
	var s = _sector([_poi("eye", "signal", 1400.0), _poi("far", "signal", 1600.0)])
	var list := Radar.contacts_for(s, 0.0, 0.0)
	eq(_ids(list), ["eye"], "no radar: a signal shows within 1,500 px only")
	eq(list[0]["via"], "visual", "by eye")
	eq(list[0]["known_type"], "wreck", "and what is in visual range is known")


func test_hidden_contacts_show_only_within_1500_px() -> void:
	var s = _sector([_poi("near", "hidden", 1400.0), _poi("far", "hidden", 1600.0)])
	eq(_ids(Radar.contacts_for(s, 0.0, 0.0)), ["near"], "hidden: seen at 1,400 px, not at 1,600")
	eq(_ids(Radar.contacts_for(s, 20000.0, 20000.0)), ["near"], "no radar of this size changes that")
	eq(Radar.contacts_for(s, 0.0, 0.0)[0]["known_type"], "wreck", "and it is known by sight")


func test_the_type_is_known_by_beacon_identification_or_sight() -> void:
	var s = _sector([_poi("a", "signal", 800.0), _poi("b", "signal", 1400.0), _poi("c", "signal", 4000.0), _poi("d", "signal", 9000.0), _poi("e", "signal", 12000.0)])
	# a radar of 16,000 px, of which a Mk2-like one identifies out to 10,000 px
	var list := Radar.contacts_for(s, 16000.0, 10000.0)
	eq(_ids(list), ["a", "b", "c", "d", "e"], "all five are in radar range")
	for id in ["a", "b", "c", "d"]:
		eq(_find(list, id)["known_type"], "wreck", "%s: known (in sight or identified)" % id)
	eq(_find(list, "e")["known_type"], Radar.CONTACT, "beyond the identifying range it is only a contact")
	list = Radar.contacts_for(s, 16000.0, 0.0)
	eq(_find(list, "b")["known_type"], "wreck", "within 1,500 px the type is known without identification")
	eq(_find(list, "c")["known_type"], Radar.CONTACT, "farther, without it, only a contact")


func test_bearing_follows_the_flight_convention() -> void:
	var s = _sector([_poi("n", "beacon", 1000.0, Vector2.UP), _poi("e", "beacon", 1000.0, Vector2.RIGHT), _poi("s", "beacon", 1000.0, Vector2.DOWN), _poi("w", "beacon", 1000.0, Vector2.LEFT)])
	var list := Radar.contacts_for(s, 0.0, 0.0)
	near(float(_find(list, "n")["bearing"]), 0.0, "up is 0")
	near(float(_find(list, "e")["bearing"]), PI / 2.0, "right is a quarter turn clockwise")
	near(absf(float(_find(list, "s")["bearing"])), PI, "down is half a turn")
	near(float(_find(list, "w")["bearing"]), -PI / 2.0, "left is a quarter turn counter-clockwise")


func test_contacts_are_nearest_first_and_a_done_poi_stays_listed() -> void:
	var done := _poi("done", "signal", 500.0)
	done["state"] = "done"
	var s = _sector([_poi("far", "signal", 900.0), done, _poi("mid", "signal", 700.0)])
	var list := Radar.contacts_for(s, 3000.0, 0.0)
	eq(_ids(list), ["done", "mid", "far"], "by distance")
	eq(list[0]["poi"]["state"], "done", "the POI is the sector's own, with its state, for the HUD to dim")


func test_ambient_contacts_are_seen_like_any_signal() -> void:
	var s = _sector([])
	s.ambient.append({"id": "a1", "type": "unknown", "name": "Unknown ship", "pos": HERE + Vector2(2500.0, 0.0), "visibility": "signal", "event_type": "pirate", "state": "new", "enemy": "", "main": false, "ambient": true, "vel": Vector2.ZERO, "ttl": 100.0})
	eq(_ids(Radar.contacts_for(s, 3000.0, 0.0)), ["a1"], "the helm's radar sees a passing ship at 2,500 px")
	eq(Radar.contacts_for(s, 3000.0, 0.0)[0]["known_type"], Radar.CONTACT, "but not what it is")
	eq(_ids(Radar.contacts_for(s, 0.0, 0.0)), [], "and nobody without a radar")


# --- the ship's radars ---------------------------------------------------------------------------------------

func test_a_powered_helm_has_a_3000_px_radar_that_does_not_identify() -> void:
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	var r := Radar.ranges(ship)
	eq(r["range"], 3000.0, "the helm's Mk0 radar: 3,000 px")
	eq(r["identify_range"], 0.0, "with no identification")
	eq(r["hidden_range"], 0.0, "and no sight of hidden contacts")
	var s = _sector([_poi("in", "signal", 2900.0), _poi("out", "signal", 3100.0), _poi("beacon", "beacon", 15000.0, Vector2.UP, "store")])
	var list := Radar.contacts(s, ship)
	eq(_ids(list), ["in", "beacon"], "the Mk0 sees 2,900 px, not 3,100, and the beacon")
	eq(_find(list, "in")["known_type"], Radar.CONTACT, "and does not name the signal")
	near(Radar.reach(ship), 3000.0, "its reach")


func test_a_ship_with_no_working_helm_sees_by_eye_only() -> void:
	var ship := Wall.wall_ship(1, 0)
	var r := Radar.ranges(ship)
	eq(r["range"], 0.0, "no helm, no radar part: no range")
	near(Radar.reach(ship), 1500.0, "the reach is the visual range")
	var helm := _helm_ship(false)
	eq(Radar.ranges(helm)["range"], 0.0, "a helm with no power gives no radar")
	eq(Radar.ranges(_helm_ship(true))["range"], 3000.0, "a powered one does")
	eq(Radar.ranges(null)["range"], 0.0, "no ship, no radar")


func test_radar_parts_set_the_range_and_identification() -> void:
	var ship := _helm_ship(true)
	var mk1 := _part(ship, "radar_mk1", 1, {"radar_range": 6000, "identify": 0}, Wall.at(0, 0, 1))
	eq(Radar.ranges(ship), {"range": 6000.0, "identify_range": 0.0, "hidden_range": 0.0}, "a Mk1-like radar: 6,000 px, no identification")
	var mk2 := _part(ship, "radar_mk2", 1, {"radar_range": 10000, "identify": 1}, Wall.at(0, -1, 1))
	eq(Radar.ranges(ship), {"range": 10000.0, "identify_range": 10000.0, "hidden_range": 0.0}, "a Mk2-like one: 10,000 px, and it identifies")
	var s = _sector([_poi("mid", "signal", 8000.0), _poi("far", "signal", 12000.0)])
	var list := Radar.contacts(s, ship)
	eq(_ids(list), ["mid"], "the best range counts")
	eq(_find(list, "mid")["known_type"], "wreck", "and the identifying radar names it")
	ship.components.instances[mk2]["status"] = "disabled"
	eq(Radar.ranges(ship), {"range": 6000.0, "identify_range": 0.0, "hidden_range": 0.0}, "a disabled radar does not count")
	ship.components.instances[mk1]["status"] = "disabled"
	eq(Radar.ranges(ship)["range"], 3000.0, "back to the helm's own")


func test_an_unpowered_radar_does_not_work_but_one_that_needs_no_power_does() -> void:
	var ship := _helm_ship(true)
	_part(ship, "radar_wired", 1, {"radar_range": 6000}, Wall.at(0, 0, 1))
	var loose := _part(ship, "radar_loose", 1, {"radar_range": 9000}, Wall.at(0, -6, 3))
	eq(Radar.ranges(ship)["range"], 6000.0, "a part that needs power and is on no cable gives nothing")
	ship.components.remove_uid(loose)
	ship.mark_dirty()
	_part(ship, "horn", 0, {"radar_range": 5000}, Wall.at(0, -6, 3))
	eq(Radar.ranges(ship)["range"], 6000.0, "the Listening Horn-like part (no power) works unwired, but 5,000 is under the wired 6,000")
	var ship2 := _helm_ship(false)
	_part(ship2, "horn", 0, {"radar_range": 5000}, Wall.at(0, -6, 3))
	eq(Radar.ranges(ship2)["range"], 5000.0, "it needs no power: 5,000 px with the helm dark")


# --- fixtures ------------------------------------------------------------------------------------------------

## The wall ship with a helm; `powered`: a reactor behind it and a cable row joining them (the row is at depth 1,
## u -2..2; radar parts that should be wired sit on it).
func _helm_ship(powered: bool) -> Ship:
	var ship := Wall.wall_ship(1, 0)
	check(ship.components.place(ship.grid, "helm", Wall.corner(0, -3, -2, 1, 2), 0) >= 0, "the helm goes in")
	if powered:
		check(ship.components.place(ship.grid, "reactor_mk1", Wall.corner(0, 2, 5, 1, 4), 0) >= 0, "the reactor goes in")
		for u in range(-2, 3):
			ship.cables.place(ship.grid, Wall.at(0, u, 1))
	ship.mark_dirty()
	ship.refresh()
	return ship


## Add a one-cell part `id` (family radar, `power`, `stats`) to `ship`'s component defs and place it at `cell`.
func _part(ship: Ship, id: String, power: int, stats: Dictionary, cell: Vector2i) -> int:
	ship.components.by_id[id] = {"id": id, "name": id, "family": "radar", "line": "standard", "tier": 1, "size": [1, 1], "color": "#ffffff", "power": -power if power > 0 else 0,
		"priority": 3, "hp": 4, "heat_limit": 100, "heat_per_s": 0, "cooling": 0, "stats": stats}
	if not ship.components.order.has(id):
		ship.components.order.append(id)
	var uid: int = ship.components.place(ship.grid, id, cell, 0)
	check(uid >= 0, "%s goes in at %s" % [id, str(cell)])
	ship.mark_dirty()
	ship.refresh()
	return uid
