extends "res://tests/base_test.gd"
## The story spine (data/packs/story_1, docs/LORE.md): one beat in every stage, Ada's arc, the fallback ending and the warden's
## per-stage story line. The beats are checked against the real eligibility rules (the stage band they live in, the flags they ask
## for), the quest beacons are checked to always have an event, every derelict log is checked to be handed out by something, and the
## walks reuse the helpers of test_endings_route.gd (the real campaign, a route of regions, the real choices).

const Route = preload("res://tests/test_endings_route.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Content = preload("res://scripts/data/content.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Endings = preload("res://scripts/space/endings.gd")
const Events = preload("res://scripts/space/events.gd")
const Flagships = preload("res://scripts/space/flagships.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Regions = preload("res://scripts/space/regions.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Wardens = preload("res://scripts/space/wardens.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const PACK := "story_1"
## The spine: id -> [node type, first stage, last stage, the flags a run holds when it happens]. Debt calls are not a node (the clock picks them).
const SPINE := {
	"ma_snap_call": ["debt", 1, 2, ["met_ma"]],
	"hollow_welcome_aboard": ["hollow", 2, 4, []],
	"ada_hears_loop": ["quest", 2, 4, ["ada_aboard"]],
	"hollow_laid_for_twelve": ["hollow", 5, 8, []],
	"ada_halcyon": ["quest", 5, 7, ["ada_aboard"]],
	"doors_briefing": ["quest", 6, 8, []],
	"hollow_porch_light": ["hollow", 7, 8, []],
	"ledger_last_call": ["quest", 8, 8, []],
}


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	s.crew_plan = [{"name": "Soldier", "species": "human"}, {"name": "Rook", "species": "basalt"}]
	Jobs.spawn_crew(s)
	s.inventory.add("credits", 500)
	return s


## A campaign at `stage` in a region valid for it (the first), holding `flags`.
func _camp(stage: int, flags: Array = [], seed_value := 1) -> Campaign:
	var c := Campaign.new(seed_value)
	c.stage = stage
	for r in Regions.all():
		if Regions.valid_for(r, stage) and str(r["id"]) != "gate_approaches":
			c.region_id = str(r["id"])
			c.region_data = r
			break
	for f in flags:
		c.flags[str(f)] = true
	c.jumps = 20
	return c


func _pool_node(type: String) -> Dictionary:
	return {"id": "n0", "type": type, "place": ""}


# --- the pack -----------------------------------------------------------------------------------------------

func test_the_pack_loads_and_its_events_pass_the_validator() -> void:
	var ev := Events.new()
	var mine := ev.validate().filter(func(m): return m.contains("story_1") or m.contains("ada_pod") or m.contains("ada_recorder"))
	eq(mine, [], "no problem in the story pack")
	eq(Content.errors(), [], "the content loader has no problem")
	check(Content.has("items", "ada_recorder"), "Ada's recorder is an item")
	check(Endings.has("scrapper_rights"), "the fallback ending exists")
	var n := 0
	for e in Content.events():
		n += int(Content.origin("events", str(e["id"])) == PACK)
	check(n >= 14, "the pack's %d events are loaded" % n)


## Collect the ids of every `log` effect inside `o` (an event, a list, an object) into `used`.
static func _collect_logs(o, used: Dictionary) -> void:
	if o is Dictionary:
		for k in o:
			if k == "log":
				for id in (o[k] if o[k] is Array else [o[k]]):
					used[str(id)] = true
			_collect_logs(o[k], used)
	elif o is Array:
		for x in o:
			_collect_logs(x, used)


func test_every_derelict_log_is_handed_out_by_some_event() -> void:
	var ev := Events.new()
	var used := {}
	for id in ev.order:
		_collect_logs(ev.events[id], used)
	for race in Flagships.races():  # a flagship's log is handed out by its beacon's page, made in code (flagships.gd event)
		used[str(Flagships.entry(race)["log"])] = true
	var orphans := []
	for id in ev.logs:
		if not used.has(id):
			orphans.append(id)
	orphans.sort()
	eq(orphans, [], "no log is left without an event that hands it out")


# --- the spine ----------------------------------------------------------------------------------------------

func test_every_beat_of_the_spine_is_open_in_its_stage_band_and_shut_outside_it() -> void:
	for id in SPINE:
		var s: Array = SPINE[id]
		var ship := _ship()
		var e: Dictionary = Events.shared().get_event(id)
		check(not e.is_empty(), id + " exists")
		eq(str(e.get("type", "")), s[0], id + " has the node type of its place in the spine")
		for stage in range(1, 10):
			var c := _camp(stage, s[3])
			var open: bool = Events.shared().eligible(e, c, _pool_node(s[0]), ship)
			check(open == (stage >= s[1] and stage <= s[2]), "%s is %s at stage %d" % [id, "open" if not open else "shut", stage])


func test_a_beat_that_needs_ada_waits_for_the_flag_and_not_for_the_woman() -> void:
	var ship := _ship()  # nobody called Ada aboard
	var e: Dictionary = Events.shared().get_event("ada_hears_loop")
	check(not Events.shared().eligible(e, _camp(3), _pool_node("quest"), ship), "without the flag the beat does not happen")
	check(Events.shared().eligible(e, _camp(3, ["ada_aboard"]), _pool_node("quest"), ship), "with it the beat happens, whoever is aboard (the recorder carries her voice)")
	var h: Dictionary = Events.shared().get_event("ada_halcyon")
	check(Events.shared().eligible(h, _camp(6, ["ada_aboard"]), _pool_node("quest"), ship), "her confession too")


func test_a_quest_beacon_gives_the_beat_of_the_stage_first() -> void:
	var want := {2: ["ada_hears_loop"], 5: ["ada_halcyon"], 6: ["ada_halcyon", "doors_briefing"], 8: ["ledger_last_call", "doors_briefing"]}
	for stage in want:
		var wins := 0
		var trials := 40
		for seed_value in range(1, trials + 1):
			var c := _camp(stage, ["ada_aboard"], seed_value)
			var ev: Dictionary = Events.shared().pick(c, _pool_node("quest"), _ship())
			wins += int(want[stage].has(str(ev.get("id", ""))))
		check(wins >= int(trials * 0.85), "stage %d: a beat of the spine (%s) is the event of the first beacon in %d of %d runs" % [stage, ", ".join(want[stage]), wins, trials])
	check(float(Events.shared().get_event("ledger_last_call")["weight"]) > float(Events.shared().get_event("doors_briefing")["weight"]), "the last call comes before the briefing when both are open")


func test_the_first_reminder_of_ma_is_the_snap_call() -> void:
	var hits := 0
	var trials := 30
	for seed_value in range(1, trials + 1):
		var c := Campaign.new(seed_value)
		c.flags["met_ma"] = true
		c.debt = 1000
		c.jumps = 6
		var ev: Dictionary = c._debt_event(_ship())
		hits += int(str(ev.get("id", "")) == "ma_snap_call")
	check(hits >= int(trials * 0.85), "Ma's reminder is the Snap call in %d of %d runs" % [hits, trials])
	var c2 := Campaign.new(2)
	c2.flags["met_ma"] = true
	c2.debt = 1000
	c2.jumps = 6
	var ship := _ship()
	var e: Dictionary = Events.shared().get_event("ma_snap_call")
	var r: Dictionary = Events.shared().choose(e, 0, c2, ship, {"id": "n0", "type": "debt", "place": ""})
	check(r["ok"], "the hundred can be paid on the call: " + str(r.get("why", "")))
	eq(c2.debt, 900, "and comes off the debt")
	eq(r["logs"].size(), 2, "and Ma hands over the two Concord pages")
	check(c2.used.has("ma_snap_call"), "the call is spent")


func test_the_hollow_tide_carries_its_clues_in_the_stage_bands() -> void:
	var want := {2: ["hollow_welcome_aboard", []], 5: ["hollow_laid_for_twelve", []], 8: ["hollow_porch_light", ["hollow_laid_for_twelve"]]}
	for stage in want:
		var wins := 0
		var trials := 60
		for seed_value in range(1, trials + 1):
			var c := _camp(stage, [], seed_value)
			for spent in want[stage][1]:
				c.used[spent] = true
			wins += int(str(Events.shared().pick(c, _pool_node("hollow"), _ship()).get("id", "")) == want[stage][0])
		check(wins >= int(trials * 0.5), "stage %d: %s is the tide event in %d of %d runs (weight 200 against ~110 of the rest)" % [stage, want[stage][0], wins, trials])


# --- the quest beacons never come up empty --------------------------------------------------------------------

func test_every_region_has_quest_beacons_and_a_beacon_never_comes_up_empty() -> void:
	var fillers := 0
	for e in Content.events():
		if str(e["type"]) == "quest" and Content.origin("events", str(e["id"])) == PACK and not bool(e.get("once", false)):
			fillers += 1
			check(float(e.get("weight", 10)) <= 4.0, "%s is a low-weight filler" % e["id"])
	check(fillers >= 3, "at least three repeatable filler quests (%d)" % fillers)
	var ship := _ship()
	var seen := 0
	for r in Regions.all():
		check(Sector.has_quest(str(r["id"]), str(r.get("events", ""))), "%s has quest beacons" % r["id"])
		for stage in range(1, 9):
			if not Regions.valid_for(r, stage):
				continue
			var c := Campaign.new(5)
			c.stage = stage
			c.region_id = str(r["id"])
			c.region_data = r
			c.flags["in_" + str(r["id"])] = true
			var ev: Dictionary = Events.shared().pick(c, _pool_node("quest"), ship)
			seen += 1
			check(not ev.is_empty(), "stage %d in %s: a quest beacon has an event" % [stage, r["id"]])
	check(seen > 20, "%d region and stage pairs were checked" % seen)


func test_a_filler_quest_can_be_met_again_and_hands_out_a_log() -> void:
	var c := _camp(3)
	var ship := _ship()
	var e: Dictionary = Events.shared().get_event("quest_dead_relay")
	for i in 2:
		var r: Dictionary = Events.shared().choose(e, 0, c, ship, _pool_node("quest"))
		check(r["ok"] and r["logs"].size() == 1, "round %d: the relay hands out a log" % i)
	check(Events.shared().eligible(e, c, _pool_node("quest"), ship), "and is not spent")


# --- the Haven chain is no longer behind the crew gate --------------------------------------------------------

func test_the_first_haven_fragment_recruits_nobody_so_the_crew_gate_does_not_hold_it_back() -> void:
	var c := _camp(3)
	var e: Dictionary = Events.shared().get_event("anomaly_haven_ghost_first")
	eq(Events.shared().crew_factor("anomaly_haven_ghost_first", c), 1.0, "no crew gate on the first fragment")
	var recruits := 0
	for ch in e["choices"]:
		for o in ch["outcomes"]:
			recruits += int(o.get("effects", {}).has("recruit"))
	eq(recruits, 0, "none of its outcomes recruits")


func test_the_chain_carriers_are_heavy_and_the_lures_stay_lighter_than_the_real_ones() -> void:
	var ev = Events.shared()
	for id in ["anomaly_haven_ghost_first", "distress_haven_lantern_blind", "wreck_field_haven_relay_log", "station_haven_signals_desk", "distress_haven_fig_skiff",
			"anomaly_haven_bearings_cross", "wreck_field_hollow_green_lit", "patrol_hollow_roll_call", "anomaly_hollow_listening_post", "distress_hollow_knucklehead", "asteroid_hollow_basalt_camp"]:
		check(float(ev.get_event(id).get("weight", 0)) >= 150.0, "%s weighs 150 or more" % id)
	for pair in [["wreck_field_haven_relay_log", "wreck_field_haven_clean_shrine"], ["distress_haven_fig_skiff", "distress_haven_voice_beacon"]]:
		check(float(ev.get_event(pair[0])["weight"]) > float(ev.get_event(pair[1])["weight"]) and float(ev.get_event(pair[1])["weight"]) >= 100.0, "%s beats its lure %s" % pair)


# --- Ada ----------------------------------------------------------------------------------------------------

func test_ada_is_a_tinkerer_and_brings_her_recorder() -> void:
	check(Events.traits_of(CrewMember.new("Ada")).has("tinkerer"), "Ada has the tinkerer trait (the blue options light up)")
	var c := _camp(1)
	var ship := _ship()
	var pod: Dictionary = Events.shared().get_event("ada_pod")
	var r: Dictionary = Events.shared().choose(pod, 0, c, ship, _pool_node("distress"))
	check(r["ok"], "the pod can be opened")
	check(c.flags.has("ada_aboard") and c.flags.has("ada_met"), "Ada aboard sets both flags")
	eq(ship.inventory.count("ada_recorder"), 1, "and her recorder is in the hold")
	var c2 := _camp(1)
	var ship2 := _ship()
	Events.shared().choose(pod, 1, c2, ship2, _pool_node("distress"))
	check(c2.flags.has("ada_met") and not c2.flags.has("ada_aboard"), "leaving her sets only ada_met")
	eq(ship2.inventory.count("ada_recorder"), 0, "and takes no recorder")


func test_ada_s_arc_runs_from_the_pod_to_the_reach() -> void:
	var r := Route.new()
	r._begin()
	r._meet("ada_pod", [0])
	check(r.c.flags.has("ada_aboard") and r.ship.inventory.count("ada_recorder") == 1, "stage 1: Ada and her recorder are aboard")
	r._go(2, "boneyard")
	r._meet("ada_hears_loop", [0])
	check(r.c.flags.has("haven_1") and r.c.logs_found.has("log_haven_first_fragment"), "stage 2: she knows the cough, the broadcast is real")
	r._go(3, "fenn_bazaar")
	r._go(4, "human_core")
	r._go(5, "mire_fens")
	r.c.flags["haven_lured"] = true  # a lure has been followed: her word undoes it
	r._meet("ada_halcyon", [0, 0])
	check(r.c.flags.has("ada_halcyon") and r.c.flags.has("haven_5") and not r.c.flags.has("haven_lured"), "stage 5: Halcyon, her word given, the fifth note, the lure undone")
	r._go(6, "basalt_quarries")
	r._meet("anomaly_haven_bearings_cross")
	r._go(7, "emberkin_forges")
	var reach: Dictionary = r.c.events.get_event("empty_haven_lantern_reach")
	var shown: Array = r.c.events.choice_view(reach, r.c, r.ship, r._node_for(reach)).map(func(v): return v["text"])
	check(shown.any(func(t): return str(t).begins_with("[Ada's recorder]")), "the Reach offers the recorder")
	r._end(r._meet("empty_haven_lantern_reach", [5, 0]), "haven_settle")
	failures.append_array(r.failures)


func test_without_her_word_the_recorder_does_not_open_the_reach() -> void:
	var r := Route.new()
	r._begin()
	r.c.flags["ada_aboard"] = true
	r.ship.inventory.add("ada_recorder", 1)
	r._go(2, "boneyard")
	r._go(3, "fenn_bazaar")
	r._go(4, "human_core")
	r._go(5, "mire_fens")
	r._meet("ada_halcyon", [0, 1])
	check(r.c.flags.has("haven_5") and not r.c.flags.has("ada_halcyon"), "she gives the fifth note, but not the rest")
	r.c.flags["haven_reach"] = true
	r._go(6, "basalt_quarries")
	r._go(7, "emberkin_forges")
	var reach: Dictionary = r.c.events.get_event("empty_haven_lantern_reach")
	var shown: Array = r.c.events.choice_view(reach, r.c, r.ship, r._node_for(reach)).map(func(v): return v["index"])
	check(not shown.has(5), "no recorder choice without her word")
	failures.append_array(r.failures)


func test_the_recorder_sees_through_the_wrong_reach_and_the_true_one_follows() -> void:
	var r := Route.new()
	r._begin()
	r._go(2, "boneyard")
	r._go(3, "fenn_bazaar")
	r._go(4, "human_core")
	r._go(5, "mire_fens")
	r._go(6, "basalt_quarries")
	r._go(7, "emberkin_forges")
	r.c.flags["haven_reach"] = true
	r.c.flags["haven_lured"] = true
	r.c.flags["ada_halcyon"] = true
	r.ship.inventory.add("ada_recorder", 1)
	r._meet("empty_haven_lantern_reach_wrong", [4])
	check(not r.c.flags.has("haven_lured") and r.c.flags.has("haven_reach"), "the lure is undone and the chart still holds the Reach")
	check(not r._closed("empty_haven_lantern_reach") and r._closed("empty_haven_lantern_reach_wrong"), "so the true Reach is what the next empty place shows")
	failures.append_array(r.failures)


func test_the_recorder_plays_the_fourth_note_at_the_prism() -> void:
	var r := Route.new()
	r._begin()
	r._go(2, "boneyard")
	r._go(3, "fenn_bazaar")
	r._go(4, "lumen_space")
	r.c.flags["prism_revealed"] = true
	r.c.rep["lumen"] = 5
	r.c.flags["ada_halcyon"] = true
	r.ship.inventory.add("ada_recorder", 1)
	var consent: Dictionary = r.c.events.get_event("station_wayout_lumen_consent")
	var idx := -1
	for i in consent["choices"].size():
		if str(consent["choices"][i]["text"]).begins_with("[Ada's recorder]"):
			idx = i
	check(idx >= 0, "the Prism's consent has the recorder choice")
	r._meet("station_wayout_lumen_consent", [idx])
	check(r.c.flags.has("wayout_lumen_backed"), "the school bell is the fourth note: the Prism backs the door")
	failures.append_array(r.failures)


# --- the fallback ending ------------------------------------------------------------------------------------

func test_a_run_with_no_thread_can_still_end_at_the_scrapper_gate() -> void:
	var r := Route.new()
	r._begin()
	r._go(2, "boneyard")
	r._go(3, "kett_hives")
	r._go(4, "fenn_bazaar")
	r._go(5, "human_core")
	r._go(6, "mire_fens")
	r._go(7, "emberkin_forges")
	r._go(8, "grundl_barges")
	r._go(9, "gate_approaches")
	check(r.c.flags.is_empty() or not r.c.flags.has("hollow_6"), "no thread was followed")
	var gate: Dictionary = r.c.node("gate_2")
	# the shell is met first (or not); once it is spent the fallback is the only event left at the Scrapper Gate
	r.c.used["gate_inside_the_shell"] = true
	var picked: Dictionary = r.c.events.pick(r.c, gate, r.ship)
	eq(str(picked.get("id", "")), "gate_scrapper_rights", "the Scrapper Gate offers its salvage rights when nothing else is open")
	var end: Dictionary = r._meet("gate_scrapper_rights", [0])
	eq(str(end.get("ending", "")), "scrapper_rights", "filing the claim ends the run")
	var e := Endings.entry("scrapper_rights")
	check(int(e.get("base_score", 9999)) < 1000, "and it scores low (%s)" % str(e.get("base_score")))
	check(str(e.get("epilogue", "")).length() > 400, "with an epilogue")
	var also: Dictionary = r.c.events.get_event("gate_scrapper_rights")
	var blue := r.c.events.choice_view(also, r.c, r.ship, r._node_for(also))
	check(blue.size() >= 2, "and a way to decline")
	failures.append_array(r.failures)


func test_the_fallback_does_not_crowd_out_a_live_thread() -> void:
	var r := Route.new()
	r._begin()
	var table: Dictionary = r.c.events.get_event("gate_hollow_the_table")
	var rights: Dictionary = r.c.events.get_event("gate_scrapper_rights")
	check(float(rights["weight"]) * 20.0 <= float(table["weight"]), "it is at least twenty times lighter than the Hollow's table")
	var clans: Dictionary = r.c.events.get_event("gate_wayout_clans_restart")
	check(float(rights["weight"]) * 20.0 <= float(clans["weight"]), "and than the Free Gate's")


# --- the warden's story line ----------------------------------------------------------------------------------

func test_the_warden_hail_carries_the_line_of_the_stage() -> void:
	var cfg := Wardens.config()
	var story: Array = cfg["story"]
	eq(story.size(), cfg["stage_size"].size(), "one story line a stage")
	eq(Wardens.problems(), [], "wardens.json is sound")
	var c := Campaign.new(4)
	var ship := _ship()
	for stage in range(1, story.size() + 1):
		var region := {}
		for r in Regions.all():
			if Regions.valid_for(r, stage) and str(r["id"]) != "gate_approaches":
				region = r
				break
		var w := Wardens.for_region(4, stage, region, 10)
		var ev := Wardens.event(w, c, ship)
		check(str(ev["text"]).contains(str(story[stage - 1])), "stage %d: the hail carries its story line" % stage)
		check(str(ev["text"]).contains(str(cfg["wardens"][w["faction"]]["hail"])), "stage %d: and the faction's own hail" % stage)
	var lines := {}
	for l in story:
		lines[l] = true
	eq(lines.size(), story.size(), "no two stages repeat a line")


# --- the `fallback` events (the filler quests) ----------------------------------------------------------------

func test_a_fallback_event_is_rolled_only_when_nothing_else_is_eligible() -> void:
	var quest := {"id": "real_quest", "type": "quest", "weight": 1, "once": true, "requires": {}, "text": "Real",
		"choices": [{"text": "Go", "outcomes": [{"weight": 100, "text": "Done", "effects": {"flag": "done"}}]}]}
	var filler := {"id": "filler_quest", "type": "quest", "weight": 1000, "once": false, "fallback": true, "requires": {}, "text": "Filler",
		"choices": [{"text": "Go", "outcomes": [{"weight": 100, "text": "Done", "effects": {}}]}]}
	var ev := Events.new("res://tests")  # no *.json there
	ev.add(quest, "test.json")
	ev.add(filler, "test.json")
	eq(ev.validate().filter(func(m): return m.contains("filler_quest") or m.contains("real_quest")), [], "both pass the validator")
	var c := Campaign.new(3, {}, ev)
	for i in 30:
		eq(str(ev.pick(c, _pool_node("quest")).get("id", "")), "real_quest", "pick %d: the real quest, however heavy the filler" % i)
	c.used["real_quest"] = true
	for i in 5:
		eq(str(ev.pick(c, _pool_node("quest")).get("id", "")), "filler_quest", "pick %d: nothing else is left, so the filler" % i)
	var bad := filler.duplicate(true)
	bad["id"] = "bad_filler"
	bad["fallback"] = "yes"
	ev.add(bad, "test.json")
	check(ev.validate().any(func(m): return m.contains("bad_filler") and m.contains("fallback must be true or false")), "fallback must be a bool")
