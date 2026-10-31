extends "res://tests/base_test.gd"
## The region graph (docs/CONTENT.md section 15; scripts/space/regions.gd, the region parts of campaign.gd, the region
## choice screen): stage 1 is Clan space; the offers at an exit are deterministic per seed, valid for the next stage and
## never a region already visited; the last stage leads to the ending region; every region's map has an exit beacon;
## crossing keeps the campaign; Ma's debt clock stops from stage 3; saves mid-run and old saves; the region data and
## its validator; events tied to a region or a stage; the map footer and the choice screen.

const Campaign = preload("res://scripts/space/campaign.gd")
const Regions = preload("res://scripts/space/regions.gd")
const Drift = preload("res://scripts/space/drift.gd")
const Events = preload("res://scripts/space/events.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
const Content = preload("res://scripts/data/content.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const FACTION_REGIONS := ["clan_space", "concord_space", "lumen_space", "boneyard", "gate_approaches"]
const HOMELANDS := {"human_core": "human", "basalt_quarries": "basalt", "emberkin_forges": "emberkin", "fenn_bazaar": "fenn", "kett_hives": "kett",
	"mire_fens": "mire", "sporeling_groves": "sporeling", "gauntling_scrapyards": "gauntling", "prismatic_choir": "prismatic", "grundl_barges": "grundl"}


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	return s


## Put the campaign at its region's exit beacon (no jump counted).
func _to_exit(c: Campaign) -> void:
	c.current = c.drift.exit_id()
	c.visited[c.current] = true


## Play a whole route from seed `seed_value`: at every exit take an offer chosen by `pick` (a seeded rng). Returns the
## campaign at the end (in the ending region) and checks every offer on the way.
func _play(seed_value: int, ship: Ship) -> Campaign:
	var c := Campaign.new(seed_value)
	var pick := RandomNumberGenerator.new()
	pick.seed = seed_value * 31 + 7
	var last := c.stages()
	while not c.is_final():
		var offers := c.region_offers()
		var tag := "seed %d stage %d" % [seed_value, c.stage]
		if c.stage < last:
			check(offers.size() >= 2 and offers.size() <= 3, "%s: 2 or 3 offers (%s)" % [tag, str(offers)])
			for id in offers:
				check(Regions.valid_for(Regions.get_region(id), c.stage + 1), "%s: %s is valid for stage %d" % [tag, id, c.stage + 1])
				check(not c.route.has(id), "%s: %s is not a region already visited" % [tag, id])
			var unique := {}
			for id in offers:
				unique[id] = true
			eq(unique.size(), offers.size(), tag + ": no offer twice")
		else:
			eq(offers, ["gate_approaches"], tag + ": the last stage leads to the ending region")
		_to_exit(c)
		var r := c.cross(str(offers[pick.randi() % offers.size()]), ship)
		check(r["ok"], tag + ": crossed " + str(r.get("why", "")))
	return c


# --- the graph -------------------------------------------------------------------------------------------------

func test_stage_1_is_always_clan_space_at_gantry_rusthold() -> void:
	for seed_value in [1, 2, 3, 99, 12345]:
		var c := Campaign.new(seed_value)
		eq([c.stage, c.region_id, c.route], [1, "clan_space", ["clan_space"]], "seed %d: stage 1, Clan space" % seed_value)
		eq(c.current, "rusthold", "seed %d: at Gantry Rusthold" % seed_value)
		check(c.flags.has("in_clan_space"), "seed %d: the region flag is set" % seed_value)
		eq(c.stage_text(), "Stage 1/8: Clan Space", "seed %d: the map's line" % seed_value)


func test_the_graph_is_deterministic_per_seed() -> void:
	var ship := _ship()
	ship.inventory.add("fuel", 50)
	var a := _play(7, ship)
	var b := _play(7, ship)
	eq(a.route, b.route, "the same seed and the same choices: the same route")
	eq(a.route.size(), 9, "8 stages and the ending region")
	eq(Regions.offers(7, 3, ["clan_space", "boneyard", "kett_hives"], a.cfg), Regions.offers(7, 3, ["clan_space", "boneyard", "kett_hives"], a.cfg), "offers are a function of the seed, the stage and the route")
	var differ := false
	for s in range(1, 20):
		differ = differ or Regions.offers(s, 1, ["clan_space"], a.cfg) != Regions.offers(7, 1, ["clan_space"], a.cfg)
	check(differ, "other seeds offer other regions")
	var c := Campaign.new(7)
	var before := c.rng.state
	c.region_offers()
	eq(c.rng.state, before, "looking at the offers rolls nothing on the campaign's rng")


func test_offers_are_valid_for_the_stage_and_never_repeat_over_many_runs() -> void:
	var ship := _ship()
	var seen := {}
	for seed_value in range(1, 61):
		ship.inventory.add("fuel", 50)
		var c := _play(seed_value, ship)
		eq(c.route[0], "clan_space", "seed %d: starts in Clan space" % seed_value)
		eq(c.route[-1], "gate_approaches", "seed %d: ends in the ending region" % seed_value)
		var mid: Array = c.route.slice(1, 8)
		var unique := {}
		for id in mid:
			unique[id] = true
			seen[id] = true
		eq(unique.size(), 7, "seed %d: stages 2 to 8 never repeat a region (%s)" % [seed_value, str(mid)])
		check(not mid.has("clan_space"), "seed %d: Clan space is stage 1 only" % seed_value)
		eq(c.stage, 9, "seed %d: past the last stage" % seed_value)
		check(c.is_final() and c.drift.exit_id() == "" and c.region_offers().is_empty(), "seed %d: the ending region has no exit and no offers" % seed_value)
	for id in HOMELANDS:
		check(seen.has(id), "60 runs pass through %s" % id)
	for id in FACTION_REGIONS.slice(1):
		check(seen.has(id), "60 runs pass through %s" % id)


func test_rarity_weights_the_offers() -> void:
	var counts := {}
	var cfg := Campaign.config()
	for s in 400:
		for id in Regions.offers(s, 4, ["clan_space"], cfg):
			counts[id] = int(counts.get(id, 0)) + 1
	check(int(counts.get("sporeling_groves", 0)) > 0, "a rare region does turn up")
	check(int(counts.get("sporeling_groves", 0)) * 2 < int(counts.get("boneyard", 0)), "a rare region far less often than a common one (%s)" % str(counts))


# --- the maps -------------------------------------------------------------------------------------------------

func test_every_regions_map_has_a_start_and_an_exit_beacon_on_the_far_side() -> void:
	var cfg := Campaign.config()
	for r in Regions.all():
		for seed_value in [1, 2, 3, 4, 5]:
			var d = Regions.make_map(r, cfg, seed_value)
			var tag := "%s/%d" % [r["id"], seed_value]
			check(d.nodes.size() >= 16 and d.nodes.size() <= 20, "%s: 16 to 20 places (%d)" % [tag, d.nodes.size()])
			var exit: String = d.exit_id()
			check(exit != "", tag + ": an exit beacon")
			eq(d.nodes.filter(func(n): return n["type"] == "exit").size(), 1, tag + ": exactly one")
			check(d.node(exit)["pos"].x > 1400.0 and d.node(d.start_id())["pos"].x < 160.0, tag + ": the start on the left, the exit on the far side")
			check(d.connected(), tag + ": connected")
			for n in d.nodes:
				check(d.degree(n["id"]) >= 2, "%s: %s has 2 lanes or more" % [tag, n["id"]])
		check(Regions.make_map(r, cfg, 1, true).exit_id() == "", "%s: as the ending region it has no exit" % r["id"])


func test_a_homeland_has_its_race_station_as_a_beacon_selling_and_recruiting_its_people() -> void:
	var ship := _ship()
	for id in HOMELANDS:
		var c := Campaign.new(3)
		c.enter_region(id)
		var r: Dictionary = c.region_data
		eq(r["home_species"], HOMELANDS[id], id + ": its home race")
		var places: Array = c.drift.nodes.filter(func(n): return n["type"] == "station")
		eq(places.size(), 1, id + ": one station")
		var st: String = places[0]["id"]
		check(c.is_known(st), id + ": the station is on the map from the start (a beacon)")
		var menu := c.station_cfg(st)
		check(not menu.is_empty() and menu["services"].has("stock") and menu["services"].has("recruit"), id + ": it trades and recruits")
		eq(menu["stock"], r["stock"], id + ": its stock is the region's")
		var home: String = HOMELANDS[id]
		for sp in menu["recruit"]:
			check(int(menu["recruit"][sp]) <= int(menu["recruit"][home]), "%s: %s weighs no more than the home race" % [id, sp])
		c.current = st
		c.roll_offers(st, ship)
		eq(c.offers[st].size(), 2, id + ": two recruits on offer")
		var price := c.stock_price(st, str(r["stock"].keys()[0]))
		check(price > 0, id + ": it sells its stock")


func test_faction_regions_keep_their_stations() -> void:
	var c := Campaign.new(2)
	c.enter_region("concord_space")
	check(c.drift.has("meridian") and c.is_known("meridian"), "Meridian is in Concord space, on the map")
	eq(c.station_cfg("meridian"), Campaign.config()["stations"]["meridian"], "with its own menu")
	c.enter_region("lumen_space")
	check(c.drift.has("prism") and c.is_hidden("prism"), "the Prism is in Lumen space, hidden until revealed")
	c.enter_region("gate_approaches")
	for g in ["gate_1", "gate_2", "gate_3"]:
		check(c.drift.has(g), g + " is in the Gate approaches")
	c.enter_region("boneyard")
	check(c.drift.nodes.all(func(n): return n["type"] != "station"), "the Boneyard has no station")


# --- crossing ---------------------------------------------------------------------------------------------------

func test_crossing_keeps_the_campaign_and_starts_the_new_region_afresh() -> void:
	var c := Campaign.new(11)
	var ship := _ship()
	ship.inventory.add("fuel", 10)
	var to := ""
	for o in c.neighbours(c.current):
		to = o
		break
	check(c.jump(to, ship)["ok"], "a jump in Clan space")
	c.flags["met_ma"] = true
	c.rep["concord"] = 4
	c.debt = 700
	c.used["some_event"] = true
	c.logs_found["some_log"] = true
	c.hull_loss = 9
	c.arrive(ship)
	c.sector_at(c.current)
	var fuel := ship.inventory.count("fuel")
	var crew := ship.crew.size()
	var jumps := c.jumps
	eq(c.cross(c.region_offers()[0], ship)["why"], Campaign.NOT_AT_EXIT, "no crossing away from the exit beacon")
	_to_exit(c)
	eq(c.cross("no_such_region", ship)["ok"], false, "only to a region on offer")
	var next: String = c.region_offers()[0]
	var r := c.cross(next, ship)
	check(r["ok"], "crossed: " + str(r["why"]))
	eq([c.stage, c.region_id, c.route], [2, next, ["clan_space", next]], "stage 2 in the chosen region")
	eq([c.debt, c.rep["concord"], c.jumps, c.hull_loss], [700, 4, jumps, 9], "debt, reputation, jumps and hull carry across (the crossing is no jump)")
	check(c.flags.has("met_ma") and c.used.has("some_event") and c.logs_found.has("some_log"), "flags, spent events and logs too")
	eq([ship.inventory.count("fuel"), ship.crew.size()], [fuel, crew], "the fuel and the crew are the ship's")
	check(c.flags.has("in_" + next) and not c.flags.has("in_clan_space"), "the region flag follows")
	eq(c.current, c.drift.start_id(), "at the new region's start")
	eq(c.visited.keys(), [c.current], "nothing else visited")
	check(c.revealed.is_empty() and c.offers.is_empty() and c.spool.is_empty(), "nothing revealed, no recruits on offer, no spool")
	eq(c.sectors.keys(), [c.current], "the ship is in the start's sector, the old region's are gone")
	check(not c.drift.has("rusthold"), "the new map is not Clan space's")
	eq(c.region_seed, Regions.seed_for(11, 2, next), "the region's own seed")


func test_mas_debt_clock_runs_in_stages_1_and_2_and_stops_from_stage_3() -> void:
	var c := Campaign.new(5)
	var ship := _ship()
	check(c.debt_running(), "it runs in Clan space")
	_to_exit(c)
	c.cross(c.region_offers()[0], ship)
	check(c.debt_running(), "and in stage 2")
	c.jumps = 8
	eq(c.behind(), 100, "a payment falls due in stage 2")
	c.paid = 100
	c.jumps = 13
	_to_exit(c)
	var r := c.cross(c.region_offers()[0], ship)
	eq(c.stage, 3, "stage 3")
	check(not c.debt_running() and c.debt_stop == 13, "the clock stopped at jump 13")
	check(" ".join(r["notes"]).contains("debt clock stops"), "and the player is told: " + str(r["notes"]))
	c.jumps = 40
	eq([c.behind(), c.misses()], [0, 0], "no payment falls due after that")
	eq(c.next_due_in(), 3, "the date stays where it was")
	check(c._advance(8).is_empty(), "jumps bring no payment news")
	c.paid = 0
	c.debt_stop = 16
	c.flags["debt_missed"] = true
	eq(c.misses(), 2, "(two payments behind from before the clock stopped)")
	eq(c.fight_path("tier", "pirate"), c.cfg["enemies"]["pirate"][str(c.tier())][0], "but no rammer is sent out here")
	c.flags.erase("debt_missed")
	c.current = c.drift.start_id()
	c.flags.erase("met_ma")
	var a := c.arrive(ship)
	check(a["event"].is_empty() or str(a["event"].get("type", "")) != "debt", "no debt event out here")
	check(c.pay_debt(ship, 50)["ok"], "the debt can still be paid")


func test_arriving_at_the_exit_beacon_says_so() -> void:
	var c := Campaign.new(4)
	var ship := _ship()
	c.flags["met_ma"] = true
	check(not c.arrive(ship)["exit"], "Rusthold is no exit")
	_to_exit(c)
	check(c.at_exit() and c.arrive(ship)["exit"], "the exit beacon is")
	check(c.is_known(c.drift.exit_id()), "and it is always on the map")


# --- saves ------------------------------------------------------------------------------------------------------

func test_a_save_mid_run_keeps_the_stage_the_route_and_the_region() -> void:
	var c := Campaign.new(21)
	var ship := _ship()
	for i in 3:
		_to_exit(c)
		check(c.cross(c.region_offers()[-1], ship)["ok"], "crossing %d" % i)
	c.sector_at(c.current).pois[0]["state"] = "done"
	var d = JSON.parse_string(JSON.stringify(c.to_dict()))
	eq([int(d["version"]), int(d["stage"]), d["region"]], [4, 4, c.region_id], "saved as version 4 with the stage and the region")
	var back := Campaign.new(1)
	eq(back.load_dict(d), "", "loads")
	eq([back.stage, back.region_id, back.route, back.region_seed, back.debt_stop], [c.stage, c.region_id, c.route, c.region_seed, c.debt_stop], "the run's place")
	eq(back.region_data.get("name"), c.region_data.get("name"), "the region's data")
	eq(back.drift.lanes, c.drift.lanes, "the map")
	eq(back.region_offers(), c.region_offers(), "the same offers at the exit")
	eq(back.sector_at(back.current).pois[0]["state"], "done", "the sectors")
	eq(JSON.stringify(back.to_dict()), JSON.stringify(c.to_dict()), "everything survived")
	for k in [["region", "nowhere"], ["route", []], ["stage", 0], ["region_seed", 5]]:
		var e = JSON.parse_string(JSON.stringify(d))
		e[k[0]] = k[1]
		var c2 := Campaign.new(3)
		eq(c2.load_dict(e), "bad campaign region", "a bad %s is refused" % k[0])
		eq(c2.region_id, "clan_space", "and changes nothing")


func test_an_old_save_loads_as_stage_1_in_clan_space() -> void:
	# a version 3 campaign: the old 28-node map of the whole Drift, no exit beacon, no regions
	var old_cfg: Dictionary = Campaign.config().duplicate(true)
	old_cfg["map"]["nodes"] = 28
	old_cfg["places"] = [{"id": "rusthold", "name": "Gantry Rusthold", "type": "station", "faction": "clans", "pos": [70, 500], "start": true},
		{"id": "meridian", "name": "Concord Station Meridian", "type": "station", "faction": "concord", "pos": [800, 500], "jitter": 90},
		{"id": "gate_1", "name": "The Concord Gate", "type": "gate", "pos": [790, 45]}]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var old_map = Drift.generate(rng, old_cfg)
	var c := Campaign.new(9)
	var d = JSON.parse_string(JSON.stringify(c.to_dict()))
	for k in ["stage", "region", "route", "region_seed", "debt_stop"]:
		d.erase(k)
	d["version"] = 3
	d["map"] = old_map.to_dict()
	d["current"] = "meridian"
	d["visited"] = ["rusthold", "meridian"]
	d["jumps"] = 6
	d["debt"] = 800
	d["flags"] = ["met_ma"]
	var back := Campaign.new(1)
	eq(back.load_dict(d), "", "a version 3 save loads")
	eq([back.stage, back.region_id, back.route], [1, "clan_space", ["clan_space"]], "as stage 1 in Clan space")
	check(back.drift.exit_id() != "" and back.drift.has("rusthold"), "its map is made again as Clan space's, with an exit")
	eq(back.current, "rusthold", "the ship is at Gantry Rusthold")
	eq([back.jumps, back.debt, back.flags.has("met_ma")], [6, 800, true], "the rest of the run is kept")
	eq(back.drift.lanes, Campaign.new(9).drift.lanes, "the same map a new run of its seed has")
	check(back.debt_running(), "Ma's clock runs")


# --- data -------------------------------------------------------------------------------------------------------

func test_the_regions_pass_the_validator() -> void:
	var ids := Content.ids("regions")
	for id in FACTION_REGIONS + HOMELANDS.keys():
		check(ids.has(id), id + " exists")
	eq(ids.size(), 15, "5 faction regions and 10 homelands")
	for p in Regions.problems():
		check(false, p)
	eq(Regions.get_region("clan_space")["stages"], [1.0, 1.0], "Clan space is stage 1 only")
	eq(Regions.get_region("gate_approaches")["stages"], [6.0, 8.0], "the Gate approaches are stages 6 to 8")


func test_the_validator_catches_broken_regions() -> void:
	var good: Dictionary = Regions.get_region("kett_hives")
	eq(Regions.problems([good]).filter(func(p): return not p.begins_with("stage ") and not p.begins_with("data/drift.json")).size(), 0, "a good region")
	var bad := good.duplicate(true)
	bad["id"] = "broken"
	bad["colour"] = "red"
	bad["home_species"] = "dragon"
	bad["stages"] = [5, 2]
	bad["rarity"] = "mythic"
	bad["stock"] = {"no_such_part": 10, "bed": -1}
	bad["recruit"] = {"elf": 3}
	bad["node_weights"] = {"station": 5}
	bad["debris"] = {"gold_bar": 1}
	bad["pois"] = {"castle": 1}
	bad["palette"] = {"tint": "nope", "nebula": "clan"}
	bad["places"] = [bad["places"][0], {"id": "ninefold", "name": "Again", "type": "station", "pos": [1, 2]}]
	var p := Regions.problems([good, bad])
	var want := ["unknown key 'colour'", "home_species 'dragon'", "stages must be", "rarity 'mythic'", "unknown item 'no_such_part'", "price of 'bed'",
		"recruit: 'elf'", "node_weights: 'station'", "debris: 'gold_bar'", "pois: 'castle'", "palette must be", "place id 'ninefold' is also used"]
	for w in want:
		check(p.any(func(x): return x.contains("'broken'") and x.contains(w)), "caught: %s (%s)" % [w, str(p)])
	var short := Regions.problems([Regions.get_region("clan_space"), good])
	check(short.any(func(x): return x.begins_with("stage 8:")), "too few regions for the late stages is a problem: " + str(short))
	var lonely := Regions.problems([good])
	check(lonely.any(func(x): return x.contains("start region 'clan_space' does not exist")), "and so is a missing start region")


# --- events ---------------------------------------------------------------------------------------------------

func test_events_can_require_a_region_or_a_stage() -> void:
	var ev := Events.new("res://tests")
	var only := {"id": "kett_only", "type": "trader", "weight": 10, "requires": {"region": "kett_hives"}, "text": "Hive traders.",
		"choices": [{"text": "Trade.", "outcomes": [{"weight": 1, "text": "Done.", "effects": {}}]}]}
	var late := {"id": "late_only", "type": "trader", "weight": 10, "requires": {"stage_min": 3, "stage_max": 5}, "text": "Late.",
		"choices": [{"text": "Go.", "requires": {"region": ["boneyard", "kett_hives"]}, "outcomes": [{"weight": 1, "text": "Done.", "effects": {}}]}]}
	ev.add(only)
	ev.add(late)
	var c := Campaign.new(3, {}, ev)
	var ship := _ship()
	var node := {"id": "n01", "type": "trader", "place": ""}
	check(not ev.eligible(only, c, node, ship), "not in Clan space")
	c.enter_region("kett_hives")
	check(ev.eligible(only, c, node, ship), "in the Kett Hives")
	c.region_data["events"] = "hive_pool"
	only["requires"]["region"] = "hive_pool"
	check(ev.eligible(only, c, node, ship), "by the region's events tag too")
	check(not ev.eligible(late, c, node, ship), "stage 1 is before stage_min")
	c.stage = 4
	check(ev.eligible(late, c, node, ship), "stage 4 is within 3 to 5")
	eq(ev.choice_view(late, c, ship, node).size(), 1, "its choice asks for this region")
	c.stage = 6
	check(not ev.eligible(late, c, node, ship), "stage 6 is past stage_max")
	only["requires"]["region"] = "kett_hives"
	eq(ev.validate().size(), 0, "the validator knows region ids and stages: " + str(ev.validate()))
	only["requires"]["region"] = "atlantis"
	check(ev.validate().any(func(x): return x.contains("region 'atlantis'")), "and names an unknown region")


# --- the screens ------------------------------------------------------------------------------------------------

## A map view on a sim with the Rustbucket, its campaign started and Ma's introduction closed.
func _screen(seed_value := 5) -> Dictionary:
	var sim := ShipSim.new()
	sim.ships = [_ship()]
	var map := MapView.new()
	map.sim = sim
	map.size = Vector2(1600.0, 900.0)
	map.new_seed = seed_value
	map.open()
	map.event_panel.close()
	map.station_panel.close()
	map.region_choice.size = map.size
	return {"map": map, "sim": sim}


func _press(node: Node, code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	node._input(e)


func test_the_exit_beacon_opens_the_region_choice_after_a_confirm() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var c: Campaign = map.campaign
	c.flags["met_ma"] = true
	_to_exit(c)
	map._arrive()
	var rc = map.region_choice
	check(rc.visible and rc.page == "confirm", "arriving at the exit beacon asks first")
	_press(rc, KEY_ESCAPE)
	check(not rc.visible and map.visible, "Esc stays in the region")
	_press(map, KEY_ENTER)
	check(rc.visible and rc.page == "confirm", "Enter on the beacon asks again")
	_press(rc, KEY_ENTER)
	eq(rc.page, "choose", "Enter reads the charts")
	var offers := c.region_offers()
	eq(rc.options.map(func(r): return r["id"]), offers, "a card for each region on offer")
	check(rc.card_rect(0).end.x <= rc.panel_rect().end.x and rc.card_rect(offers.size() - 1).end.x <= rc.panel_rect().end.x, "the cards fit the panel")
	eq(rc.card_at(rc.card_rect(1).get_center()), 1, "hit testing finds the second card")
	check(not c.rarity_known(offers[0], map.ship()), "the rarity is unknown without an identifying radar")
	c.flags["known_" + offers[0]] = true
	check(c.rarity_known(offers[0], map.ship()), "a known region shows it")
	_press(rc, KEY_1)
	check(not rc.visible, "1 jumps")
	eq([c.stage, c.region_id], [2, offers[0]], "into the first region on offer")
	check(map.message.contains("You jump into"), "the map says so: " + map.message)
	map.queue_redraw()
	eq(c.stage_text(), "Stage 2/8: " + str(Regions.get_region(offers[0])["name"]), "and the footer names the stage")
	d["map"].free()
	d["sim"].free()


func test_the_last_exit_offers_only_the_ending_region() -> void:
	var d := _screen(8)
	var map: MapView = d["map"]
	var c: Campaign = map.campaign
	c.stage = 8
	_to_exit(c)
	map.dock()
	var rc = map.region_choice
	_press(rc, KEY_ENTER)
	eq(rc.options.size(), 1, "one card")
	eq(rc.options[0]["id"], "gate_approaches", "the ending region")
	_press(rc, KEY_1)
	check(c.is_final(), "past the last stage")
	eq(c.stage_text(), "Final region: The Gate Approaches", "the footer says so")
	eq(c.drift.exit_id(), "", "no way on from there")
	d["map"].free()
	d["sim"].free()
