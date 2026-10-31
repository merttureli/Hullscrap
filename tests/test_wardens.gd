extends "res://tests/base_test.gd"
## The exit wardens (docs/MECHANICS_REVIEW.md P7; scripts/space/wardens.gd, data/wardens.json, the warden parts of campaign.gd,
## map_view.gd and region_choice.gd): a warden per region, rolled from the seed and known before the region is chosen; the
## event at the exit beacon (pay, good standing, break through, turn back); the lane stays shut until it is cleared; saves.

const Campaign = preload("res://scripts/space/campaign.gd")
const Regions = preload("res://scripts/space/regions.gd")
const Wardens = preload("res://scripts/space/wardens.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Threat = preload("res://scripts/space/threat.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const MapView = preload("res://scripts/ui/map_view.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const GUARDS := {"clan_space": "clans", "basalt_quarries": "clans", "concord_space": "concord", "human_core": "concord", "lumen_space": "lumen",
	"emberkin_forges": "lumen", "boneyard": "rustfangs", "fenn_bazaar": "rustfangs", "gate_approaches": "hollow"}


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	return s


func _to_exit(c: Campaign) -> void:
	c.current = c.drift.exit_id()
	c.visited[c.current] = true


## The index (into the event's choices) of the shown choice whose text starts with `prefix`, -1 when it is not shown.
func _index(c: Campaign, ev: Dictionary, ship, prefix: String) -> int:
	for v in c.events.choice_view(ev, c, ship, c.node(c.current)):
		if str(v["text"]).begins_with(prefix):
			return int(v["index"])
	return -1


func _choose(c: Campaign, ev: Dictionary, ship, prefix: String) -> Dictionary:
	return c.events.choose(ev, _index(c, ev, ship, prefix), c, ship, c.node(c.current))


## A campaign at its exit beacon with the warden's event up: {c, ship, ev}.
func _meeting(seed_value := 11) -> Dictionary:
	var c := Campaign.new(seed_value)
	var ship := _ship()
	c.flags["met_ma"] = true
	_to_exit(c)
	var a := c.arrive(ship)
	return {"c": c, "ship": ship, "ev": a["event"], "a": a}


# --- the warden of a region ---------------------------------------------------------------------------------------

func test_the_data_is_sound_and_every_region_has_a_guard() -> void:
	eq(Wardens.problems(), [], "data/wardens.json has no problems")
	var cfg := Wardens.config()
	var ids: Array = cfg["wardens"].keys()
	ids.sort()
	eq(ids, ["clans", "concord", "hollow", "lumen", "rustfangs"], "an entry per guarding faction")
	eq([cfg["stage_size"].size(), cfg["stage_budget_mult"].size(), int(cfg["jumps_ahead"])], [8, 8, 8], "eight stages, eight jumps ahead")
	for r in Regions.all():
		check(cfg["wardens"].has(Wardens.faction_of(r)), "region %s has a guard with an entry" % r["id"])
		eq(Wardens.for_region(3, 2, r, 5)["faction"], Wardens.faction_of(r), "%s: the warden is of its guard's faction" % r["id"])


func test_for_region_is_deterministic_per_seed_stage_and_region_and_leaves_the_rng_alone() -> void:
	var c := Campaign.new(11)
	var state := c.rng.state
	var concord := Regions.get_region("concord_space")
	var a := Wardens.for_region(11, 3, concord, 12, "normal")
	eq(Wardens.for_region(11, 3, concord, 12, "normal"), a, "the same arguments, the same warden")
	check(Wardens.for_region(12, 3, concord, 12, "normal")["spec"] != a["spec"], "another seed, another ship")
	check(Wardens.for_region(11, 4, concord, 12, "normal")["spec"] != a["spec"], "another stage, another ship")
	check(Wardens.for_region(11, 3, Regions.get_region("human_core"), 12, "normal")["spec"] != a["spec"], "another region, another ship")
	eq(c.rng.state, state, "the campaign's rng was not touched")
	eq([a["region"], a["stage"], a["flag"]], ["concord_space", 3, "warden_concord_space_3"], "it knows its place and its flag")
	var p: PackedStringArray = str(a["spec"]).split(":")
	var want := Shipgen.budget_for(Wardens.tier_at(20), 20, 1.1, "normal") * 1.2
	eq([p[0], p[1], p[2], int(p[4])], ["gen", "concord", "large", roundi(want * 100.0)], "a concord large ship at the budget of jumps + 8, times the stage factor")
	check(Shipgen.from_spec(a["spec"]) != null, "and the spec builds")
	var easy := Wardens.for_region(11, 3, concord, 12, "easy")
	check(int(str(easy["spec"]).split(":")[4]) < int(p[4]), "easy difficulty buys less")
	var first := Wardens.for_region(11, 1, Regions.get_region("clan_space"), 0)
	eq(str(first["spec"]).split(":")[2], "medium", "stage 1 is a medium hull")
	eq(Wardens.for_region(11, 9, Regions.get_region("gate_approaches"), 0), {}, "past the last stage there is none")
	eq(Wardens.for_region(11, 0, concord, 0), {}, "nor before the first")


func test_each_faction_maps_right_including_a_region_with_no_faction() -> void:
	for id in GUARDS:
		var w := Wardens.for_region(5, 2, Regions.get_region(id), 6)
		eq(w["faction"], GUARDS[id], "%s is guarded by the %s" % [id, GUARDS[id]])
		eq(str(w["spec"]).split(":")[1], GUARDS[id], "%s: the warden's ship is of that faction" % id)
	eq(Regions.get_region("fenn_bazaar")["faction"], "", "(the Fenn bazaar belongs to no faction)")
	eq(Wardens.faction_of({"faction": "", "enemies": "concord"}), "concord", "no faction: the enemies' faction")
	eq(Wardens.faction_of({"faction": "clans", "enemies": "concord"}), "clans", "a faction with an entry wins over the enemies")
	eq(Wardens.faction_of({"faction": "", "enemies": "wardens"}), "rustfangs", "enemies with no entry: the Rustfangs")
	for f in ["clans", "concord", "lumen", "rustfangs", "hollow"]:
		for stage in [1, 8]:
			check(Shipgen.from_spec(Wardens.for_region(9, stage, {"id": "x_" + f, "faction": f, "danger": 1.2}, 10)["spec"]) != null, "%s stage %d builds" % [f, stage])


func test_the_hollow_has_no_toll_and_no_pass_and_the_rustfangs_no_pass() -> void:
	var m := _meeting()
	var c: Campaign = m["c"]
	var hollow := Wardens.for_region(5, 6, Regions.get_region("gate_approaches"), 30)
	eq(hollow["toll"], 0, "no toll")
	check(not hollow.has("pass_rep"), "no pass")
	var ev := Wardens.event(hollow, c, m["ship"])
	eq(ev["choices"].map(func(ch): return ch["text"]), ["Break through.", "Turn back."], "only a fight or a retreat")
	var fangs := Wardens.for_region(5, 2, Regions.get_region("boneyard"), 6)
	check(int(fangs["toll"]) > 0 and not fangs.has("pass_rep"), "the Rustfangs sell a toll but never wave you through")
	var clans := Wardens.for_region(5, 1, Regions.get_region("clan_space"), 0)
	check(int(clans["toll"]) > 0 and clans.has("pass_rep") and int(clans["rep_on_fight"]) < 0, "the Clans take a toll, know their friends and mind a fight")
	eq(int(fangs["rep_on_fight"]) + int(hollow["rep_on_fight"]), 0, "hostile factions have no reputation to lose")


func test_the_threat_is_rated_against_the_ship_and_cached() -> void:
	var ship := _ship()
	var w := Wardens.for_region(11, 4, Regions.get_region("concord_space"), 27)
	var n := Wardens.skulls(w, ship)
	check(n >= 1 and n <= 5, "1 to 5 skulls: %d" % n)
	eq(Wardens.threat_label(w, ship), Threat.label(n), "the label is Threat n/5")
	eq(Wardens.line(w, ship), "Exit warden: Concord Bulwark (%s)" % Threat.label(n), "the card and tooltip line")
	var cached := Wardens._rated.size()
	eq(Wardens.skulls(w, ship), n, "asked again, the same")
	eq(Wardens._rated.size(), cached, "from the cache")
	eq(Wardens.skulls({}, ship), 0, "no warden, no rating")
	eq(Wardens.skulls(w, null), 0, "no ship, no rating")
	eq(Wardens.line(w, null), "Exit warden: Concord Bulwark", "and the line leaves the threat out")


# --- the event at the beacon ----------------------------------------------------------------------------------------

func test_the_event_names_the_warden_the_toll_and_the_threat_and_offers_four_ways() -> void:
	var m := _meeting()
	var c: Campaign = m["c"]
	var ev: Dictionary = m["ev"]
	var w: Dictionary = c.warden
	eq(ev["title"], "Clan Hulk", "the title is the warden's name")
	check(str(ev["text"]).contains("30 credits"), "the text names the toll: " + str(ev["text"]))
	check(str(ev["text"]).contains("Threat "), "and shows the threat: " + str(ev["text"]))
	check(str(ev["text"]).contains(Wardens.threat_label(w, m["ship"])), "the one the card shows")
	var texts: Array = c.events.choice_view(ev, c, m["ship"], c.node(c.current)).map(func(v): return v["text"])
	eq(texts, ["Pay the toll (30 credits).", "Break through.", "Turn back."], "pay, break through, turn back (no pass at 0 standing)")
	c.rep["clans"] = 4
	texts = c.events.choice_view(ev, c, m["ship"], c.node(c.current)).map(func(v): return v["text"])
	eq(texts.size(), 4, "a pass joins them at standing 4")
	check(texts[1].begins_with("[Good standing] They know your registry"), "it reads as a blue option: " + texts[1])
	var view: Array = c.events.choice_view(ev, c, m["ship"], c.node(c.current))
	check(view[1]["blue"] and not view[0]["blue"], "blue is the pass only")


func test_arriving_at_the_exit_with_the_warden_up_gives_its_event_and_no_exit() -> void:
	var m := _meeting()
	var c: Campaign = m["c"]
	var a: Dictionary = m["a"]
	check(c.warden_up() and a["warden"], "the warden holds the lane")
	check(not a["exit"], "so there is no exit yet")
	eq(a["event"]["title"], c.warden["name"], "the event is the warden's")
	eq(c.arrive(m["ship"])["event"]["title"], c.warden["name"], "it comes every time the ship arrives while it holds")
	c.flags[c.warden["flag"]] = true
	var b := c.arrive(m["ship"])
	check(b["exit"] and not b["warden"] and not c.warden_up(), "cleared: the exit is open")
	check(b["event"].is_empty() or str(b["event"].get("title", "")) != c.warden["name"], "and the warden's event is gone")
	c.current = c.drift.start_id()
	check(not c.arrive(m["ship"])["warden"], "other places have no warden")


func test_the_toll_pays_and_clears() -> void:
	var m := _meeting()
	var c: Campaign = m["c"]
	var ship = m["ship"]
	ship.inventory.add("credits", 100 - ship.inventory.count("credits"))
	var view: Array = c.events.choice_view(m["ev"], c, ship, c.node(c.current))
	check(not view[0]["grey"], "100 credits cover 30")
	var r := _choose(c, m["ev"], ship, "Pay the toll")
	check(r["ok"], "paid")
	eq(ship.inventory.count("credits"), 70, "the toll left the cargo")
	check(not c.warden_up() and c.flags.has("warden_clan_space_1"), "the flag is set")
	check(c.arrive(ship)["exit"], "the exit is open")
	# broke: the toll is greyed and cannot be paid
	var b := _meeting(12)
	var poor = b["ship"]
	poor.inventory.add("credits", -poor.inventory.count("credits") + 5)
	var v: Array = b["c"].events.choice_view(b["ev"], b["c"], poor, b["c"].node(b["c"].current))
	check(v[0]["grey"], "5 credits do not cover it")
	var refused: Dictionary = b["c"].events.choose(b["ev"], v[0]["index"], b["c"], poor, b["c"].node(b["c"].current))
	check(not refused["ok"] and b["c"].warden_up(), "and paying is refused")
	# the toll grows with the stage
	var concord := Wardens.for_region(7, 3, Regions.get_region("concord_space"), 20)
	var other := _ship()
	var ev := Wardens.event(concord, b["c"], other)
	check(str(ev["choices"][0]["text"]).contains("120 credits"), "Concord at stage 3 asks 40 x 3: " + str(ev["choices"][0]["text"]))


func test_good_standing_waves_you_through_for_free() -> void:
	var m := _meeting()
	var c: Campaign = m["c"]
	var ship = m["ship"]
	eq(_index(c, m["ev"], ship, "[Good standing]"), -1, "no pass without standing")
	c.rep["clans"] = 3
	eq(_index(c, m["ev"], ship, "[Good standing]"), -1, "nor one short of it")
	c.rep["clans"] = 4
	var credits: int = ship.inventory.count("credits")
	var r := _choose(c, m["ev"], ship, "[Good standing]")
	check(r["ok"], "waved through")
	eq(ship.inventory.count("credits"), credits, "for nothing")
	check(not c.warden_up(), "the lane is clear")


func test_a_won_fight_clears_pays_and_changes_the_standing() -> void:
	var m := _meeting()
	var c: Campaign = m["c"]
	var ship = m["ship"]
	var r := _choose(c, m["ev"], ship, "Break through")
	check(r["ok"], "break through")
	eq(r["fight"], c.warden["spec"], "the fight is against the warden's own ship")
	eq(c.fight_path(r["fight"], "exit"), c.warden["spec"], "and the campaign keeps the spec as the design")
	var win: Dictionary = r["after_win"]
	check(win["effects"]["flag"].has("warden_clan_space_1") and int(win["effects"]["items"]["credits"]) == 50, "it clears the lane and pays 50 x stage 1")
	eq(win["effects"]["rep"], {"clans": -2}, "and costs the Clans' goodwill")
	check(c.warden_up(), "(until it is won)")
	var credits: int = ship.inventory.count("credits")
	var foe := Shipgen.from_spec(c.warden["spec"])
	var done := c.fight_done({"state": "won", "enemy": foe, "hull": 100.0, "hull_max": 100.0}, ship, win)
	eq(done["state"], "won", "won")
	check(not c.warden_up(), "the lane is clear")
	check(ship.inventory.count("credits") >= credits + 50, "50 credits for the stage, on top of the loot")
	eq(c.rep["clans"], -2, "reputation with the Clans fell")
	check(str(done["text"]).contains("Clan Hulk"), "the text names the warden: " + str(done["text"]))


func test_a_warden_that_escapes_is_spared_or_captured_leaves_the_lane() -> void:
	for state in ["escaped", "spared", "captured"]:
		var m := _meeting()
		var c: Campaign = m["c"]
		var ship = m["ship"]
		var r := _choose(c, m["ev"], ship, "Break through")
		var res := {"state": state, "hull": 100.0, "hull_max": 100.0, "enemy": Shipgen.from_spec(c.warden["spec"])}
		if state == "spared":
			res["offer"] = {"credits": 10}
		var credits: int = ship.inventory.count("credits")
		c.fight_done(res, ship, r["after_win"])
		check(not c.warden_up(), "%s: the lane is clear" % state)
		if state == "escaped":
			eq([ship.inventory.count("credits"), c.rep["clans"]], [credits, 0], "an escaped warden pays nothing and costs no standing")
		else:
			eq(c.rep["clans"], -2, "%s: the fight still costs standing" % state)
	for state in ["fled", "lost"]:
		var m := _meeting()
		var c: Campaign = m["c"]
		var r := _choose(c, m["ev"], m["ship"], "Break through")
		c.fight_done({"state": state, "hull": 100.0, "hull_max": 100.0}, m["ship"], r["after_win"])
		check(c.warden_up(), "%s: the warden still holds the lane" % state)
	var m2 := _meeting()
	m2["c"].fight_done({"state": "escaped", "hull": 100.0, "hull_max": 100.0}, m2["ship"], {})
	check(m2["c"].warden_up(), "an escape from some other fight clears nothing")


func test_turning_back_keeps_the_warden_up() -> void:
	var m := _meeting()
	var c: Campaign = m["c"]
	var ship = m["ship"]
	var credits: int = ship.inventory.count("credits")
	var r := _choose(c, m["ev"], ship, "Turn back")
	check(r["ok"] and r["fight"] == "" and r["goto"] == "", "turned back: no fight, no page")
	check(c.warden_up(), "the warden still holds the lane")
	eq(ship.inventory.count("credits"), credits, "and nothing was paid")
	eq(c.arrive(ship)["event"]["title"], "Clan Hulk", "you may come back and face it again")


# --- the map ------------------------------------------------------------------------------------------------------

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


func _free(d: Dictionary) -> void:
	d["map"].free()
	d["sim"].free()


func test_the_region_choice_is_gated_until_the_warden_is_cleared() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var c: Campaign = map.campaign
	c.flags["met_ma"] = true
	_to_exit(c)
	map._arrive()
	var ep = map.event_panel
	var rc = map.region_choice
	check(ep.visible and not rc.visible, "arriving shows the warden's hail, not the region choice")
	eq(ep.title, "Clan Hulk", "titled with the warden")
	ep.choose(ep.view.size() - 1)  # Turn back
	ep.proceed()
	check(not ep.visible and not rc.visible, "turning back leaves the lane shut")
	eq(map.cross_to(c.region_offers()[0]), "the warden still holds the exit lane", "and crossing is refused")
	eq(c.stage, 1, "still in stage 1")
	map.dock()
	check(ep.visible and ep.title == "Clan Hulk" and not rc.visible, "Enter at the beacon brings the warden back")
	var pay := -1
	for i in ep.view.size():
		if str(ep.view[i]["text"]).begins_with("Pay the toll"):
			pay = i
	map.ship().inventory.add("credits", 100)
	eq(ep.choose(pay), "", "pay the toll")
	check(not c.warden_up(), "cleared")
	ep.proceed()
	check(rc.visible and rc.page == "confirm", "and the region choice opens after it")
	_free(d)


func test_a_fight_against_the_warden_ends_at_the_region_choice() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var c: Campaign = map.campaign
	c.flags["met_ma"] = true
	_to_exit(c)
	map._arrive()
	var ep = map.event_panel
	var r: Dictionary = c.events.choose(ep.event, _index(c, ep.event, map.ship(), "Break through"), c, map.ship(), c.node(c.current))
	map._fighting = true  # (the combat view is not in this scene: hand over the result it would give)
	map._after_win = r["after_win"]
	map._on_fight_finished({"state": "escaped", "hull": 100.0, "hull_max": 100.0})
	check(not c.warden_up(), "the warden left the lane")
	check(ep.visible and ep.title == "The fight is over", "the map says so")
	ep.proceed()
	check(map.region_choice.visible, "and the region choice opens")
	_free(d)


func test_the_beacon_tooltip_names_the_warden_and_its_threat() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var c: Campaign = map.campaign
	var tip: Array = map.warden_tip()
	eq(tip.size(), 1, "one line")
	eq(tip[0], Wardens.line(c.warden, map.ship()), "the warden's name and threat")
	check(str(tip[0]).contains("Clan Hulk") and str(tip[0]).contains("Threat "), "Clan Hulk, Threat n/5: " + str(tip[0]))
	c.flags[c.warden["flag"]] = true
	check(str(map.warden_tip()[0]).contains("has let you through"), "once cleared it says it let you through")
	_free(d)


func test_the_region_cards_show_the_next_warden_and_its_hint() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var c: Campaign = map.campaign
	c.flags["met_ma"] = true
	c.flags[c.warden["flag"]] = true
	_to_exit(c)
	map.dock()
	var rc = map.region_choice
	_press(rc, KEY_ENTER)
	eq(rc.page, "choose", "the cards are up")
	var offers := c.region_offers()
	eq(rc.wardens.size(), offers.size(), "a warden per card")
	for i in offers.size():
		var want := Wardens.for_region(c.seed_value, 2, Regions.get_region(offers[i]), c.jumps)
		eq(rc.wardens[i], want, "card %d shows the warden of %s at stage 2" % [i, offers[i]])
		var line: String = rc.warden_line(i)
		check(line.begins_with("Exit warden: " + str(want["name"])), "card %d: %s" % [i, line])
		check(line.contains("(Threat ") and line.ends_with("/5)"), "and its threat: " + line)
		check(rc.warden_skulls[i] >= 1 and rc.warden_skulls[i] <= 5, "with skulls")
		check(str(want["hint"]) != "", "and a hint")
	_press(rc, KEY_1)
	eq(c.warden, Wardens.for_region(c.seed_value, 2, Regions.get_region(offers[0]), c.jumps), "the card told the truth about the warden met in the region")
	_free(d)


func test_the_last_region_cards_have_no_warden_line() -> void:
	var d := _screen(8)
	var map: MapView = d["map"]
	var c: Campaign = map.campaign
	c.stage = 8
	c.flags[c.warden["flag"]] = true
	_to_exit(c)
	map.dock()
	_press(map.region_choice, KEY_ENTER)
	eq(map.region_choice.options[0]["id"], "gate_approaches", "the ending region is offered")
	eq(map.region_choice.warden_line(0), "", "and it has no exit warden")
	_free(d)


# --- the run ------------------------------------------------------------------------------------------------------------

func test_every_region_of_a_run_has_a_warden_and_the_ending_region_has_none() -> void:
	var c := Campaign.new(21)
	var ship := _ship()
	var flags := {}
	for stage in range(1, 9):
		check(not c.warden.is_empty(), "stage %d (%s) has a warden" % [stage, c.region_id])
		eq(c.warden["stage"], stage, "stage %d: it knows the stage" % stage)
		eq(c.warden, Wardens.for_region(21, stage, c.region_data, c.jumps), "stage %d: it is the one the cards showed" % stage)
		check(not flags.has(c.warden["flag"]), "its flag is its own")
		flags[c.warden["flag"]] = true
		c.jumps += 9
		_to_exit(c)
		check(c.cross(c.region_offers()[-1], ship)["ok"], "crossing %d" % stage)
	check(c.is_final() and c.warden.is_empty(), "the ending region has no warden")
	check(not c.warden_up() and c.warden_event(ship).is_empty(), "so none is ever up")
	eq(c.drift.exit_id(), "", "(it has no exit to hold)")


func test_saving_and_loading_keep_the_warden_and_its_flag() -> void:
	var m := _meeting(33)
	var c: Campaign = m["c"]
	var ship = m["ship"]
	var d = JSON.parse_string(JSON.stringify(c.to_dict()))
	eq(int(d["version"]), Campaign.VERSION, "saved at the current version")
	var back := Campaign.new(1)
	eq(back.load_dict(d), "", "loads")
	eq(back.warden, c.warden, "the warden is as it was")
	check(back.warden_up(), "and still up")
	eq(JSON.stringify(back.to_dict()), JSON.stringify(c.to_dict()), "saves the same again")
	_choose(c, m["ev"], ship, "Turn back")
	c.flags[c.warden["flag"]] = true
	var d2 = JSON.parse_string(JSON.stringify(c.to_dict()))
	var back2 := Campaign.new(1)
	eq(back2.load_dict(d2), "", "loads again")
	check(not back2.warden_up() and back2.flags.has(c.warden["flag"]), "the cleared flag survives")
	check(back2.arrive(ship)["exit"], "and the exit is open")
	# an older save has none: it is rolled on load; a bad one is rolled again; a stage's other warden is not trusted
	var old = JSON.parse_string(JSON.stringify(c.to_dict()))
	old.erase("warden")
	old["version"] = 5
	var b := Campaign.new(2)
	eq(b.load_dict(old), "", "a version 5 save loads")
	eq(b.warden, Wardens.for_region(c.seed_value, c.stage, c.region_data, c.jumps), "and rolls its warden")
	for bad in [{"spec": "nonsense"}, {"region": "boneyard"}, {"stage": 3}, "junk"]:
		var e = JSON.parse_string(JSON.stringify(c.to_dict()))
		if bad is Dictionary:
			for k in bad:
				e["warden"][k] = bad[k]
		else:
			e["warden"] = bad
		var f := Campaign.new(3)
		eq(f.load_dict(e), "", "a damaged warden does not stop the load")
		eq(f.warden, Wardens.for_region(c.seed_value, c.stage, c.region_data, c.jumps), "it is rolled again: " + str(bad))
