extends "res://tests/base_test.gd"
## The title of an event window at a sector POI (Beta 3 known issue 4): the event's own title, else the name of the POI it is at
## (a wreck far from the beacon is "Wreck", not the node's name); only the node's own POI (the main one) keeps the node's name.

const Campaign = preload("res://scripts/space/campaign.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const MapView = preload("res://scripts/ui/map_view.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


## A map with a new campaign on the light-speed flow, the ship at the first node that is not a gate. Returns {map, sim, build, ship, sector}.
func _screen() -> Dictionary:
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(ship)
	var sim := ShipSim.new()
	sim.ships = [ship]
	var build := BuildMode.new()
	build.sim = sim
	var map := MapView.new()
	map.sim = sim
	map.build = build
	map.size = Vector2(1600.0, 900.0)
	build.drift = map
	map.new_game(5)
	map.visible = false
	map.save_path = "user://test_poi_titles_campaign.json"
	var c: Campaign = map.campaign
	var id := ""
	for o in c.neighbours(c.current):
		if c.node(o)["type"] != "gate":
			id = o
			break
	c.current = id
	c.visited[id] = true
	var s: Sector = c.current_sector()
	s.enter()
	s.set_flight(ship)
	return {"map": map, "sim": sim, "build": build, "ship": ship, "sector": s}


func _free(d: Dictionary) -> void:
	for k in ["map", "build", "sim"]:
		d[k].free()


## Fly to `poi` and take its trigger; null when nothing fired.
func _fire(d: Dictionary, poi: Dictionary) -> Dictionary:
	var s: Sector = d["sector"]
	s.ship_pos = poi["pos"] + Vector2(100.0, 0.0)
	return s.trigger(d["map"].campaign, d["ship"])


func _far_without_a_title(s: Sector) -> Dictionary:
	s.ship_pos = Vector2(30000.0, 6000.0)
	for p in s.all_pois():
		if p.get("far", false):
			return p
	return {}


func test_a_far_poi_event_is_titled_with_the_poi_not_the_nodes_name() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var s: Sector = d["sector"]
	var seen := 0
	s.ship_pos = Vector2(30000.0, 6000.0)
	for p in s.all_pois().filter(func(q): return q.get("far", false)).slice(0, 8):
		var res := _fire(d, p)
		if res.is_empty() or res["event"].is_empty():
			continue
		seen += 1
		map.open_poi(res, s)
		var want := str(res["event"]["title"]) if res["event"].has("title") else str(p["name"])
		eq(map.event_panel.title, want, "%s (%s): the window carries %s" % [p["id"], p["type"], "its event's title" if res["event"].has("title") else "the POI's name"])
		check(map.event_panel.title != map.campaign.label(map.campaign.current) or want == map.campaign.label(map.campaign.current), "%s: not the node's name" % p["id"])
		map.event_panel.close()
		map._poi_done()
	check(seen >= 3, "(setup) several far POIs fired (%d)" % seen)
	_free(d)


func test_a_near_poi_that_is_not_the_nodes_own_gets_its_name_and_the_nodes_own_keeps_the_node() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var s: Sector = d["sector"]
	var main: Dictionary = {}
	var other: Dictionary = {}
	for p in s.pois:
		if p["main"] and main.is_empty():
			main = p
		elif not p["main"] and other.is_empty() and p["type"] in ["wreck", "unknown", "distress", "abandoned_station"]:
			other = p
	if other.is_empty():  # (poi.thin can leave a sector with only its own places)
		other = {"id": "pw1", "type": "wreck", "name": "Wreck", "pos": s.ship_pos, "visibility": "signal", "event_type": "wreck_field", "state": Sector.NEW, "enemy": "", "main": false}
		s.pois.append(other)
	check(not main.is_empty() and not other.is_empty(), "(setup) the sector has its main POI and another")
	var res := _fire(d, main)
	check(not res.is_empty() and not res["event"].is_empty(), "(setup) the node's own POI has an event")
	map.open_poi(res, s)
	eq(map.event_panel.title, str(res["event"]["title"]) if res["event"].has("title") else map.campaign.label(map.campaign.current), "the node's own POI: the node's name (or the event's title)")
	map.event_panel.close()
	map._poi_done()
	res = _fire(d, other)
	check(not res.is_empty() and not res["event"].is_empty(), "(setup) the other POI has an event")
	map.open_poi(res, s)
	eq(map.event_panel.title, str(res["event"]["title"]) if res["event"].has("title") else str(other["name"]), "another near POI: its own name")
	map.event_panel.close()
	map._poi_done()
	_free(d)


func test_the_poi_name_goes_with_the_following_pages_and_ends_with_the_poi() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var s: Sector = d["sector"]
	var poi := {"id": "pt", "type": "wreck", "name": "Wreck", "pos": s.ship_pos, "visibility": "signal", "event_type": "wreck_field", "state": Sector.NEW, "enemy": "", "main": false, "far": true}
	s.pois.append(poi)
	var ev := {"id": "t_page1", "type": "wreck_field", "text": "A hull.", "choices": [{"text": "On.", "outcomes": [{"weight": 1, "text": "", "effects": {"goto": "t_page2"}}]}]}
	map.campaign.events.add(ev, "test.json")
	map.campaign.events.add({"id": "t_page2", "type": "wreck_field", "once": false, "weight": 0, "text": "More.", "choices": [{"text": "Leave.", "outcomes": [{"weight": 1, "text": "", "effects": {}}]}]}, "test.json")
	map.open_poi({"poi": poi, "refused": "", "event": ev, "dock": false}, s)
	eq(map.event_panel.title, "Wreck", "page one")
	map.event_panel.choose(0)
	map.event_panel.proceed()
	eq(map.event_panel.event.get("id", ""), "t_page2", "(setup) the follow-up page is up")
	eq(map.event_panel.title, "Wreck", "and still carries the POI's name")
	map.event_panel.choose(0)
	map.event_panel.proceed()
	eq(map.poi_title(), "", "the POI is done: no name is left for a later window")
	_free(d)
