extends "res://tests/base_test.gd"
## Playtest 2, A1 + A2: every run starts with the soldier alone, Ada is the likely first crewmate (a free distress event of
## stages 1-2), and crew are rare (a gate on the events that add crew, dearer and rarer hires at stations).

const Campaign = preload("res://scripts/space/campaign.gd")
const Events = preload("res://scripts/space/events.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const CrewWalk = preload("res://tests/crew_walk.gd")

const COURIER := "res://data/ships/starter_courier.json"
const RUNS := 60  ## seeded campaigns for the Ada rate


func _alone() -> Ship:
	var s: Ship = Ship.from_design(COURIER)
	Jobs.spawn_crew(s)
	return s


func _node(c: Campaign) -> Dictionary:
	return c.node(c.current)


# --- Ada's pod ------------------------------------------------------------------------------------------------------

func test_the_pod_is_a_valid_distress_event_of_the_first_two_stages_once_per_run() -> void:
	var ev: Events = Events.shared()
	check(ev.events.has("ada_pod"), "the ada_pod event is loaded")
	var e: Dictionary = ev.events.get("ada_pod", {})
	eq([e.get("type"), e.get("once")], ["distress", true], "a distress event, once")
	var req: Dictionary = e.get("requires", {})
	eq([int(req.get("stage_min", 0)), int(req.get("stage_max", 0)), req.get("not_flag")], [1, 2, "ada_met"], "stages 1 and 2, until she is met")
	check(ev.validate().filter(func(m): return m.contains("ada_pod")).is_empty(), "it passes the event validator")
	var c := Campaign.new(3)
	c.node(c.current)
	check(ev.eligible(e, c, {"id": c.current, "type": "distress", "place": ""}), "eligible at stage 1")
	c.stage = 2
	check(ev.eligible(e, c, {"id": c.current, "type": "distress", "place": ""}), "and at stage 2")
	c.stage = 3
	check(not ev.eligible(e, c, {"id": c.current, "type": "distress", "place": ""}), "not at stage 3")


func test_taking_ada_aboard_is_free_and_needs_no_bed_and_she_keeps_her_colours() -> void:
	var c := Campaign.new(5)
	var ship := _alone()
	var beds: Array = ship.components.instances.keys().filter(func(u): return ship.components.def(ship.components.instances[u]["id"])["family"] == "bed")
	for uid in beds:
		ship.components.remove_uid(uid)  # no bed at all: she sleeps on the floor
	eq(Jobs._beds(ship).size(), 0, "no bed aboard")
	var credits := ship.inventory.count("credits")
	var e: Dictionary = c.events.get_event("ada_pod")
	var r := c.events.choose(e, 0, c, ship, _node(c))
	check(r["ok"], "taking her aboard is allowed: " + str(r.get("why", "")))
	var ada = ship.crew.filter(func(m): return m.name == "Ada")
	eq(ada.size(), 1, "Ada is aboard")
	eq(ada[0].look, CrewMember.config()["ada"]["look"], "in her own colours")
	eq(ship.inventory.count("credits"), credits, "it cost nothing")
	check(c.flags.has("ada_met") and c.used.has("ada_pod"), "she is met once per run")


func test_leaving_her_is_a_free_way_out() -> void:
	var c := Campaign.new(5)
	var ship := _alone()
	var e: Dictionary = c.events.get_event("ada_pod")
	var view := c.events.choice_view(e, c, ship, _node(c))
	check(view.size() == 2 and not view[1]["grey"] and not view[1]["blue"], "the second choice has no requirement")
	var r := c.events.choose(e, 1, c, ship, _node(c))
	check(r["ok"], "leaving her is allowed")
	eq(ship.crew.size(), 1, "the soldier is still alone")
	check(not c.events.eligible(e, c, _node(c)), "and she does not come back")


# --- crew are rare -------------------------------------------------------------------------------------------------

func test_events_that_add_crew_are_gated_and_adas_is_not() -> void:
	var c := Campaign.new(1)
	var ev: Events = c.events
	eq(ev.crew_factor("ada_pod", c), 1.0, "Ada's pod is never gated")
	eq(ev.crew_factor("empty_quiet", c), 1.0, "an event that adds no crew is not gated")
	check(ev.crew_factor("char_hydrant_standing_by", c) < 1.0, "a unique character's event is gated")
	check(ev.crew_factor("pirate_defector", c) < ev.crew_factor("char_hydrant_standing_by", c), "an ordinary recruit more than a unique one")
	check(ev.crew_factor("pits_heat_sink_dock", c) < 1.0, "a station greeting that hires someone is gated")


func test_the_gate_keeps_recruit_events_out_of_the_pool() -> void:
	var c := Campaign.new(2)
	c.cfg = c.cfg.duplicate(true)  # (the config is shared)
	c.cfg["crew"] = {"species_event": 0.0, "unique_event": 0.0, "station_event": 0.0}
	var recruiters := 0
	for i in 150:
		var e := c.events.pick(c, {"id": c.current, "type": "distress", "place": ""})
		recruiters += int(e.get("id", "") != "ada_pod" and c.events._recruiters.has(str(e.get("id", ""))))
	eq(recruiters, 0, "with the gates shut no distress event adds crew")
	c.cfg["crew"] = {"species_event": 1.0, "unique_event": 1.0, "station_event": 1.0}
	var open := 0
	for i in 400:
		var e := c.events.pick(c, {"id": c.current, "type": "distress", "place": ""})
		open += int(e.get("id", "") != "ada_pod" and c.events._recruiters.has(str(e.get("id", ""))))
	check(open > 0, "with the gates open recruit events are picked as before")


func test_hiring_costs_three_times_as_much_and_most_stations_have_nobody() -> void:
	var c := Campaign.new(4)
	eq(int(c.cfg["prices"]["recruit"]), 450, "three times the old 150 credits")
	check(float(c.cfg["prices"]["recruit_chance"]) < 1.0, "a station often has nobody to hire")
	c.cfg = c.cfg.duplicate(true)
	var ship := _alone()
	var station := ""
	for id in c.drift.ids():
		if not c.station_cfg(id).is_empty() and not c.station_cfg(id).get("recruit", {}).is_empty():
			station = id
			break
	check(station != "", "the map has a station that hires")
	c.cfg["prices"]["recruit_chance"] = 0.0
	eq(c.roll_offers(station, ship), [], "chance 0: nobody on offer")
	c.cfg["prices"]["recruit_chance"] = 1.0
	eq(c.roll_offers(station, ship).size(), int(c.cfg["prices"]["offers"]), "chance 1: the usual offers")


# --- the rates (a seeded walk over many campaigns: tests/crew_walk.gd, tests/tool_crew_rate.gd) ----------------------

func test_about_seven_runs_in_ten_meet_ada_by_the_end_of_stage_two() -> void:
	var walk := CrewWalk.new()
	var met := 0
	var gained := 0
	for i in RUNS:
		var r := walk.run(i, COURIER, 2)
		eq(r["start"], 1, "the run starts with the soldier alone")
		met += int(r["met_ada"])
		gained += int(r["crew"].get(2, 1)) - 1
	var rate := float(met) / RUNS
	check(rate >= 0.55 and rate <= 0.85, "%.0f%% of %d runs met Ada by the end of stage 2 (about 70%% wanted)" % [100.0 * rate, RUNS])
	check(float(gained) / RUNS <= 2.0, "and the soldier has at most two crewmates on average after stage 2 (%.2f)" % (float(gained) / RUNS))
