extends "res://tests/base_test.gd"
## The endings of the endings_1 pack are reachable on a route of regions (docs/CONTENT.md sections 13 and 15). The events are
## placed by `requires.region` and `stage_min` / `stage_max`, and the Dead Gates can be approached in the ending region, so for each
## of the eight endings this walks a run through the real campaign: it enters a region per stage (each valid for that stage, none
## twice), meets the chain's events one after another with the real eligibility check and the real choices, and ends on the ending
## effect. The walks assume an ordinary ship (rustbucket: a Basalt and a Fenn aboard, money, fuel and scrap in the hold) and the
## reputation each step asks for; the money and the gate alloy come from the events themselves where they can.

const Campaign = preload("res://scripts/space/campaign.gd")
const Content = preload("res://scripts/data/content.gd")
const Endings = preload("res://scripts/space/endings.gd")
const Events = preload("res://scripts/space/events.gd")
const Regions = preload("res://scripts/space/regions.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const PACK := "endings_1"
const FINAL := "gate_approaches"

var c: Campaign
var ship: Ship
var _info := {}  # region id -> {stations, gates, places}: the place ids of its map (made once)


## A new run (stage 1, Clan space) with an ordinary ship.
func _begin(seed_value := 3) -> void:
	c = Campaign.new(seed_value)
	ship = Ship.from_design(RUSTBUCKET)
	ship.crew_plan = [{"name": "Soldier", "species": "human"}, {"name": "Rook", "species": "basalt"}]  # (a Basalt aboard for the way-out choices that ask for one)
	Jobs.spawn_crew(ship)
	ship.inventory.add("credits", 6000)
	ship.inventory.add("fuel", 20)
	ship.inventory.add("scrap", 60)
	c.jumps = 9


## Jump (a crossing) into `region` as the run's stage `stage`.
func _go(stage: int, region: String) -> void:
	var r := Regions.get_region(region)
	var last := c.stages()
	if stage <= last:
		check(Regions.valid_for(r, stage), "%s may be the region of stage %d" % [region, stage])
	else:
		check(region == str(Regions.run_of(c.cfg)["ending"]), "the ending region follows the last stage")
	check(not c.route.has(region), "%s is not visited twice" % region)
	c.stage = stage
	c.enter_region(region)
	c.jumps = maxi(c.jumps, (stage - 1) * 6 + 3)
	if stage > last:
		for g in ["gate_1", "gate_2", "gate_3"]:
			var lanes: Array = c.neighbours(g)
			check(not lanes.is_empty(), g + " has a lane to it")
			if not lanes.is_empty():
				c.current = lanes[0]
				eq(c.jump_block(g, ship), "", g + " can be jumped to from the next place")


## The node an event of `e`'s kind happens at in the region: its station (docked: the flag at_<place> is up) or gate, else a plain one.
func _node_for(e: Dictionary) -> Dictionary:
	var type := str(e["type"])
	var want := str(e.get("requires", {}).get("node", ""))
	if type == "gate":
		if want != "" and c.drift.has(want):
			return c.node(want)
		for n in c.drift.nodes:
			if n["type"] == "gate":
				return n
	if type == "station":
		for f in Events._list(e.get("requires", {}).get("flag")):  # a station named by its dock flag (at_gantry_barge)
			if str(f).begins_with("at_") and c.drift.has(str(f).substr(3)):
				c.flags[str(f)] = true
				return c.node(str(f).substr(3))
		for n in c.drift.nodes:
			if n["type"] == "station":
				c.flags["at_" + str(n["place"])] = true
				return n
	return {"id": "n0", "type": type, "place": ""}


## Meet event `id` and take `choices` (a choice for it, then one for each page it leads to). Returns the last result.
func _meet(id: String, choices: Array = [0]) -> Dictionary:
	var cur: Dictionary = c.events.get_event(id)
	check(not cur.is_empty(), id + " exists")
	var where := "stage %d %s: %s" % [c.stage, c.region_id, id]
	var node := _node_for(cur)
	check(c.events.eligible(cur, c, node, ship), where + " can happen")
	var r := {}
	for k in choices.size():
		r = c.events.choose(cur, int(choices[k]), c, ship, node)
		check(r["ok"], "%s: choice %d is on offer (%s)" % [where, choices[k], str(r.get("why", ""))])
		check(str(r.get("fight", "")) == "", where + ": choice %d starts no fight" % choices[k])
		if not r["ok"] or str(r["goto"]) == "":
			break
		cur = c.events.get_event(str(r["goto"]))
		node = _node_for(cur)
	return r


## Is event `id` closed to the run now (a flag it needs is missing, or the region or the stage is wrong)?
func _closed(id: String) -> bool:
	var e: Dictionary = c.events.get_event(id)
	return not c.events.eligible(e, c, _node_for(e), ship)


func _end(r: Dictionary, ending: String) -> String:
	eq(str(r.get("ending", "")), ending, "the last choice ends the run with " + ending)
	eq(c.ending, ending, "and the campaign is won")
	return ending


## The Haven chain up to the bearings across the chart (flag haven_reach), over stages 2 to 7 of the route R1; `lure` takes the
## voice beacon, a lure, for the fifth fragment.
func _haven_trail(lure := false) -> void:
	_begin()
	_go(2, "boneyard")
	_meet("anomaly_haven_ghost_first")
	_go(3, "fenn_bazaar")
	_meet("distress_haven_lantern_blind")
	_go(4, "human_core")
	_meet("wreck_field_haven_relay_log")
	_meet("station_haven_signals_desk")
	_go(5, "mire_fens")
	_meet("distress_haven_voice_beacon" if lure else "distress_haven_fig_skiff", [0])
	_go(6, "basalt_quarries")
	_meet("anomaly_haven_bearings_cross")
	check(c.flags.has("haven_reach"), "the Reach is on the chart")
	_go(7, "emberkin_forges")


func _haven_settle() -> String:
	_haven_trail()
	return _end(_meet("empty_haven_lantern_reach", [0, 0]), "haven_settle")


func _haven_exodus() -> String:
	_haven_trail()
	c.rep["clans"] = 5
	return _end(_meet("empty_haven_lantern_reach", [1, 0]), "haven_exodus")


func _haven_lure() -> String:
	_haven_trail(true)
	check(c.flags.has("haven_lured"), "the fifth fragment was a lure")
	check(_closed("empty_haven_lantern_reach"), "so the true Reach is shut")
	return _end(_meet("empty_haven_lantern_reach_wrong", [0]), "haven_lure")


func _wayout_concord() -> String:
	_begin()
	_go(2, "fenn_bazaar")
	_go(3, "boneyard")
	_go(4, "concord_space")
	c.rep["concord"] = 5
	check(_closed("station_wayout_clans_moot") and _closed("station_wayout_lumen_consent"), "Meridian has only the Concord's offer")
	_meet("station_wayout_concord_charter", [0])
	for g in ["gate_wayout_concord_core", "gate_wayout_concord_restart"]:
		check(_closed(g), g + " waits for the gate")
	_go(5, "mire_fens")
	_go(6, "basalt_quarries")
	_go(7, "emberkin_forges")
	_go(8, "grundl_barges")
	_go(9, FINAL)
	_meet("gate_wayout_concord_core", [2])
	check(ship.inventory.count("gate_core") == 1 and ship.inventory.count("gate_alloy") >= 4, "the core and the alloy are in the hold")
	return _end(_meet("gate_wayout_concord_restart", [0]), "wayout_concord")


func _wayout_clans() -> String:
	_begin()
	_go(2, "boneyard")
	_go(3, "kett_hives")
	c.rep["clans"] = 5
	_meet("station_wayout_clans_moot", [0])
	_go(4, "fenn_bazaar")
	_go(5, "human_core")
	_go(6, "mire_fens")
	_go(7, "emberkin_forges")
	_go(8, "grundl_barges")
	_go(9, FINAL)
	_meet("gate_inside_the_shell", [0])
	_meet("gate_wayout_clans_core", [1])
	return _end(_meet("gate_wayout_clans_restart", [0]), "wayout_clans")


func _wayout_lumen() -> String:
	_begin()
	_go(2, "boneyard")
	_go(3, "fenn_bazaar")
	_go(4, "lumen_space")
	c.flags["prism_revealed"] = true  # the Prism is hidden in Lumen space until some anomaly sings (data/events)
	c.rep["lumen"] = 5
	_meet("station_wayout_lumen_consent", [0])
	_go(5, "human_core")
	_go(6, "basalt_quarries")
	_go(7, "mire_fens")
	_go(8, "grundl_barges")
	_go(9, FINAL)
	_meet("gate_wayout_lumen_core", [0])
	return _end(_meet("gate_wayout_lumen_restart", [0]), "wayout_lumen")


func _hollow_truth() -> String:
	_begin()
	_go(2, "boneyard")
	_go(3, "fenn_bazaar")
	_meet("wreck_field_hollow_green_lit")
	_go(4, "human_core")
	_meet("patrol_hollow_roll_call")
	_go(5, "mire_fens")
	_meet("anomaly_hollow_listening_post")
	_meet("distress_hollow_knucklehead")
	_go(6, "basalt_quarries")
	_meet("asteroid_hollow_basalt_camp")
	_go(7, "emberkin_forges")
	_go(8, "grundl_barges")
	_go(9, FINAL)
	check(_closed("gate_hollow_the_table"), "the table is laid only after the approach")
	_meet("gate_hollow_approach", [0])
	var r := _meet("gate_hollow_the_table", [0, 0])
	check(c.unlocks_earned.has("map_hollow_tide") and c.unlocks_earned.has("ship_hollow_touched"), "the Hollow ending unlocks the early tide and its starter")
	return _end(r, "hollow_truth")


func _retire() -> String:
	_begin()
	_go(2, "boneyard")
	_go(3, "concord_space")
	return _end(_meet("station_meridian_hold_line", [0]), "retire")


# --- the walks ------------------------------------------------------------------------------------------------------

func test_the_haven_can_be_settled_at_the_reach() -> void:
	eq(_haven_settle(), "haven_settle", "walked")
	check(c.unlocks_earned.has("ship_halcyon_tender") and c.unlocks_earned.has("skin_lantern_lights"), "with the Halcyon Tender and the first fragment's skin earned")


func test_the_haven_can_be_led_there_by_any_faction() -> void:
	eq(_haven_exodus(), "haven_exodus", "walked with the Clans")
	check(c.unlocks_earned.has("start_halcyon_gardener"), "the Gardener start is earned")
	for faction in ["concord", "lumen"]:
		_haven_trail()
		c.rep[faction] = 5
		var e: Dictionary = c.events.get_event("empty_haven_lantern_reach")
		var shown: Array = c.events.choice_view(e, c, ship, _node_for(e)).map(func(v): return v["index"])
		check(shown.has(2 if faction == "concord" else 3), "%s: with its standing the exodus is offered" % faction)


func test_a_lure_leads_to_the_wrong_reach() -> void:
	eq(_haven_lure(), "haven_lure", "walked")
	check(c.unlocks_earned.has("skin_lantern_hollow"), "the cold lanterns are earned")


func test_a_lured_ship_is_caught_at_the_signals_desk() -> void:
	_begin()
	_go(2, "boneyard")
	_meet("anomaly_haven_ghost_first")
	_go(3, "fenn_bazaar")
	_meet("distress_haven_lantern_blind")
	_go(4, "human_core")
	_meet("wreck_field_haven_clean_shrine", [0])
	check(c.flags.has("haven_lured") and c.flags.has("haven_3"), "the shrine was the first lure")
	var desk: Dictionary = c.events.get_event("station_haven_signals_desk")
	var shown: Array = c.events.choice_view(desk, c, ship, _node_for(desk)).map(func(v): return v["index"])
	check(shown.has(1) and not shown.has(0), "the desk offers its lured choice only")
	_meet("station_haven_signals_desk", [1])
	check(c.flags.has("haven_4") and not c.flags.has("haven_lured"), "the desk catches the lure and the trail goes on")


func test_the_concord_way_out_can_be_restarted() -> void:
	eq(_wayout_concord(), "wayout_concord", "walked")
	check(c.unlocks_earned.has("ship_concord_frigate"), "with the Concord Frigate earned")


func test_the_clans_way_out_can_be_restarted() -> void:
	eq(_wayout_clans(), "wayout_clans", "walked")
	check(c.unlocks_earned.has("ship_door_prize"), "with Door Prize earned")


func test_the_lumen_way_out_can_be_restarted() -> void:
	eq(_wayout_lumen(), "wayout_lumen", "walked")
	check(c.unlocks_earned.has("ship_lumen_skiff"), "with the Lumen Skiff earned")


func test_the_hollow_thread_leads_into_the_scrapper_gate() -> void:
	eq(_hollow_truth(), "hollow_truth", "walked")


func test_a_run_can_hold_the_line_at_meridian_from_stage_3() -> void:
	eq(_retire(), "retire", "walked")
	check(c.unlocks_earned.has("ship_kettle_tug"), "with Ma's tug earned")
	eq(Endings.title_of("retire"), "Hold the Line", "the old Retire ending is Hold the Line")
	_begin()
	_go(2, "concord_space")
	check(_closed("station_meridian_hold_line"), "not at stage 2: the Concord has not started to lose yet")
	_go(3, "boneyard")
	c.flags.erase("at_meridian")
	check(_closed("station_meridian_hold_line"), "and not where Meridian is not")
	_begin()
	_go(2, "boneyard")
	_go(3, "concord_space")
	ship.inventory.counts["credits"] = 4999
	var e: Dictionary = c.events.get_event("station_meridian_hold_line")
	var r: Dictionary = c.events.choose(e, 0, c, ship, _node_for(e))
	check(not r["ok"], "5,000 credits are needed to fund the defence")
	check(c.ending == "", "and the run goes on")


func test_the_old_rusthold_berth_is_gone() -> void:
	check(Events.shared().get_event("station_retire_ma_berth").is_empty() and Events.shared().get_event("retire_berth_page").is_empty(), "no berth at Rusthold any more")


func test_halcyon_names_who_came_with_you() -> void:
	_begin()
	eq(Endings.title_of("haven_settle"), "Halcyon", "the Haven ending is Halcyon")
	var alone: String = Endings.report(c, ship, "haven_settle")["ending"]["epilogue"]
	check(alone.contains("Rook") and alone.contains("Soldier"), "it names the crew that came: " + alone.substr(alone.find("You did not"), 80))
	check(not alone.contains("Ma Gantry's barge"), "and no barge when the barge was not helped")
	c.flags["helped_barge"] = true
	var with_barge: String = Endings.report(c, ship, "haven_settle")["ending"]["epilogue"]
	check(with_barge.contains("Ma Gantry's barge") and with_barge.begins_with(alone.substr(0, 60)), "with helped_barge Ma's barge comes in too")
	check(Endings.validate().is_empty(), "the endings validate: " + str(Endings.validate()))


func test_every_ending_of_the_pack_is_reached_by_a_walk() -> void:
	var all: Array = [_haven_settle(), _haven_exodus(), _haven_lure(), _wayout_concord(), _wayout_clans(), _wayout_lumen(), _hollow_truth(), _retire()]
	var pack_endings: Array = Endings.all().filter(func(e): return Content.origin("endings", str(e["id"])) == PACK).map(func(e): return str(e["id"]))
	pack_endings.sort()
	all.sort()
	eq(all, pack_endings, "the walks end in exactly the pack's eight endings")


# --- the landmarks -------------------------------------------------------------------------------------------------

func test_every_landmark_can_be_met_where_it_is_placed() -> void:
	_begin()
	c.rep["clans"] = 3
	c.flags["met_ma"] = true
	_meet("station_ma_in_person", [1])
	_go(2, "boneyard")
	_go(3, "human_core")
	c.rep["concord"] = 3
	_meet("wreck_field_cs001_patience", [0])
	_go(4, "lumen_space")
	c.rep["lumen"] = 3
	c.flags["prism_revealed"] = true
	_meet("station_lumen_first_gate_study", [0])
	_go(5, "mire_fens")
	_meet("empty_hollow_node_survived", [0])
	_go(6, "basalt_quarries")
	_go(7, "emberkin_forges")
	_go(8, "grundl_barges")
	_go(9, FINAL)
	_meet("gate_inside_the_shell", [0])
	eq(c.landmarks.size(), 5, "five landmarks met")
	for id in ["bp_ma_shrapnel", "ship_patience_sister", "bp_lumen_siren", "skin_green_running_lights", "start_basalt_gatewright"]:
		check(c.unlocks_earned.has(id), id + " is earned")


# --- where the events are placed ---------------------------------------------------------------------------------

## The place ids of region `r`'s map: {stations, gates, places}.
func _info_of(r: Dictionary) -> Dictionary:
	var id := str(r["id"])
	if not _info.has(id):
		var info := {"stations": [], "gates": [], "places": []}
		for n in Regions.make_map(r, c.cfg, 1, false).nodes:
			var place := str(n["place"])
			if place == "":
				continue
			info["places"].append(place)
			if n["type"] == "station":
				info["stations"].append(place)
			if n["type"] == "gate":
				info["gates"].append(place)
		_info[id] = info
	return _info[id]


## Every (stage, region) of a run in which `e` can happen with everything it asks for held: its flags up, reputation high, many jumps,
## and the station or gate it needs on the region's map.
func _homes(e: Dictionary) -> Array:
	var out := []
	var last := c.stages()
	var req: Dictionary = e.get("requires", {})
	var type := str(e["type"])
	for stage in range(1, last + 2):
		for r in Regions.all():
			var fits: bool = Regions.valid_for(r, stage) if stage <= last else str(r["id"]) == str(Regions.run_of(c.cfg)["ending"])
			if not fits:
				continue
			var info := _info_of(r)
			c.stage = stage
			c.region_id = str(r["id"])
			c.region_data = r
			c.flags = {}
			c.rep = {"clans": 10, "concord": 10, "lumen": 10}
			c.jumps = 99
			var needs: Array = req["flag"] if req.get("flag") is Array else ([req["flag"]] if req.has("flag") else [])
			var place_ok := true
			for f in needs:
				c.flags[str(f)] = true
				if str(f).begins_with("at_") and not info["places"].has(str(f).substr(3)):
					place_ok = false  # docked at a station this region does not have
			var node := {"id": "n0", "type": type, "place": ""}
			if type == "station" and info["stations"].is_empty() or type == "gate" and info["gates"].is_empty():
				place_ok = false
			elif type == "station":
				node["place"] = info["stations"][0]
			elif type == "gate":
				var want := str(req.get("node", ""))
				node["place"] = want if info["gates"].has(want) else info["gates"][0]
				place_ok = place_ok and (want == "" or info["gates"].has(want))
			if place_ok and c.events.eligible(e, c, node, ship):
				out.append([stage, str(r["id"])])
	return out


func test_every_event_of_the_pack_has_a_region_and_a_stage_to_happen_in() -> void:
	_begin()
	var n := 0
	for ev in Content.events():
		if Content.origin("events", str(ev["id"])) != PACK or c.events.is_page(str(ev["id"])):
			continue
		n += 1
		check(not _homes(c.events.get_event(str(ev["id"]))).is_empty(), "%s can happen somewhere on a run" % ev["id"])
	check(n >= 30, "the pack's %d playable events were checked" % n)


func test_the_dead_gate_events_wait_in_the_ending_region_only() -> void:
	_begin()
	for ev in Content.events():
		if Content.origin("events", str(ev["id"])) != PACK or str(ev["type"]) != "gate":
			continue
		var homes := _homes(c.events.get_event(str(ev["id"])))
		check(not homes.is_empty() and homes.all(func(h): return h[0] == c.stages() + 1 and h[1] == FINAL), "%s happens only at the Dead Gates of the ending region (%s)" % [ev["id"], str(homes)])


func test_the_way_out_backings_are_in_their_factions_regions() -> void:
	_begin()
	var want := {"station_wayout_concord_charter": ["concord_space"], "station_wayout_lumen_consent": ["lumen_space"],
		"station_wayout_clans_moot": ["basalt_quarries", "gauntling_scrapyards", "kett_hives"]}
	for id in want:
		var regions := []
		for h in _homes(c.events.get_event(id)):
			if not regions.has(h[1]):
				regions.append(h[1])
		regions.sort()
		var list: Array = want[id].duplicate()
		list.sort()
		eq(regions, list, id + " is in the faction's regions")
		for h in _homes(c.events.get_event(id)):
			check(h[0] >= 3, "%s: not before stage 3 (%s)" % [id, str(h)])


func test_a_chain_has_room_in_its_stage_windows() -> void:
	_begin()
	var chains := {
		"haven": ["anomaly_haven_ghost_first", "distress_haven_lantern_blind", "wreck_field_haven_relay_log", "station_haven_signals_desk", "distress_haven_fig_skiff", "anomaly_haven_bearings_cross", "empty_haven_lantern_reach"],
		"haven lure": ["anomaly_haven_ghost_first", "distress_haven_lantern_blind", "wreck_field_haven_clean_shrine", "station_haven_signals_desk", "distress_haven_voice_beacon", "anomaly_haven_bearings_cross", "empty_haven_lantern_reach_wrong"],
		"haven (Ada)": ["ada_hears_loop", "ada_halcyon", "anomaly_haven_bearings_cross", "empty_haven_lantern_reach"],  # data/packs/story_1: the pod's recorder carries the first and the fifth fragment
		"hollow": ["wreck_field_hollow_green_lit", "patrol_hollow_roll_call", "anomaly_hollow_listening_post", "distress_hollow_knucklehead", "asteroid_hollow_basalt_camp", "gate_hollow_approach", "gate_hollow_the_table"],
	}
	for name in chains:
		# the earliest stage each link can happen in, never before the link before it; and the latest each can be put off to, never
		# after the link after it: both must fit the link's own window
		var early := 1
		var spans := []
		for id in chains[name]:
			var stages := _homes(c.events.get_event(str(id))).map(func(h): return h[0])
			check(not stages.is_empty(), "%s: %s has stages" % [name, id])
			spans.append([stages.min(), stages.max()] if not stages.is_empty() else [1, 1])
		for i in spans.size():
			early = maxi(early, spans[i][0])
			check(early <= spans[i][1], "%s: link %d (%s) is still open at stage %d" % [name, i + 1, chains[name][i], early])
		var late := 99
		for i in range(spans.size() - 1, -1, -1):
			late = mini(late, spans[i][1])
			check(late >= spans[i][0], "%s: link %d (%s) is not shut before the stage %d the links after it need" % [name, i + 1, chains[name][i], late])
		var width := 0
		for s in spans:
			width = maxi(width, s[1] - s[0] + 1)
		check(width >= 3, "%s: some link has a window of 3 stages or more (widest %d)" % [name, width])


# --- steering by the region cards ----------------------------------------------------------------------------------

## A player who takes the faction's region whenever the cards offer it in the window of its Way Out backing (else the first card) is
## offered it on most seeds: the Way Out is a choice of route, not luck.
func test_a_player_steering_by_the_cards_is_offered_each_factions_backing_in_time() -> void:
	var cfg := Campaign.config()
	var want := {"concord": [["concord_space"], 3, 6, 0.6], "clans": [["basalt_quarries", "gauntling_scrapyards", "kett_hives"], 3, 7, 0.9], "lumen": [["lumen_space"], 4, 8, 0.75]}
	var seeds := 100
	for faction in want:
		var t: Array = want[faction]
		var hits := 0
		for seed_value in range(1, seeds + 1):
			var route := ["clan_space"]
			var got := false
			for stage in range(1, Regions.stages(cfg)):
				var offers := Regions.offers(seed_value, stage, route, cfg)
				var pick: String = offers[0]
				for o in offers:
					if t[0].has(o) and stage + 1 >= t[1] and stage + 1 <= t[2]:
						pick = o
						got = true
						break
				route.append(pick)
			hits += int(got)
		check(float(hits) / seeds >= t[3], "%s: offered in its window on %d of %d seeds (wanted %d%%)" % [faction, hits, seeds, int(t[3] * 100.0)])

