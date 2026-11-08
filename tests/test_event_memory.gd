extends "res://tests/base_test.gd"
## Event memory: every event shown in a run fades (events.gd fade_weight, data/drift.json events.repeat_fade), the stations also
## have the derelict people who fit them, and the capital recruiter always talks.

const Events = preload("res://scripts/space/events.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


func _ev(id: String, type: String, weight := 10, fallback := false) -> Dictionary:
	return {"id": id, "type": type, "weight": weight, "once": false, "requires": {}, "fallback": fallback, "text": "Text of " + id,
		"choices": [{"text": "Go", "outcomes": [{"weight": 100, "text": "Done", "effects": {}}]}]}


func _camp(list: Array, seed_value := 1) -> Campaign:
	var e := Events.new("res://tests")
	for x in list:
		e.add(x, "test.json")
	e._index_recruiters()
	var c := Campaign.new(seed_value, {}, e)
	c.cfg = c.cfg.duplicate(true)
	return c


const NODE := {"id": "n1", "type": "wreck_field", "place": ""}


func test_an_event_shown_once_is_picked_less_often_after() -> void:
	var c := _camp([_ev("a", "wreck_field"), _ev("b", "wreck_field")], 7)
	eq(float(c.cfg["events"]["repeat_fade"]), 0.25, "the factor is in drift.json")
	var fresh := 0
	for i in 600:
		c.story_views = {}
		if c.events.pick(c, NODE)["id"] == "a":
			fresh += 1
	var seen := 0
	for i in 600:
		c.story_views = {"a": 1}
		if c.events.pick(c, NODE)["id"] == "a":
			seen += 1
	check(fresh > 240 and fresh < 360, "unseen: about half (%d of 600)" % fresh)
	check(seen > 60 and seen < 140, "seen once: about a fifth (%d of 600)" % seen)  # 2.5 against 10
	c.story_views = {}
	c.events.pick(c, NODE)
	eq(c.story_views.values().reduce(func(x, y): return x + y, 0), 1, "every pick is counted, for any event")


func test_a_lone_event_is_still_picked_however_often_it_was_shown() -> void:
	var c := _camp([_ev("only", "wreck_field")])
	c.story_views = {"only": 40}
	eq(Events.fade_weight(c.events.get_event("only"), 10.0, c), Events.FADE_FLOOR, "the weight stops at the floor")
	eq(Events.fade_weight(c.events.get_event("only"), 0.2, c), 0.2, "and never rises above its own weight")
	for i in 50:
		eq(c.events.pick(c, NODE)["id"], "only", "a pool of one still picks it")
	eq(c.story_views["only"], 90, "(and counts it)")


func test_a_fallback_never_crowds_out_a_real_event() -> void:
	var c := _camp([_ev("real", "wreck_field"), _ev("nothing", "wreck_field", 10, true)])
	c.story_views = {"real": 12}
	for i in 50:
		eq(c.events.pick(c, NODE)["id"], "real", "the fallback is rolled only when nothing else is eligible")


func test_the_memory_is_saved_and_an_old_save_loads() -> void:
	var c := Campaign.new(5)
	c.story_views = {"trader_a": 3, "doors_briefing": 1}
	var d = JSON.parse_string(JSON.stringify(c.to_dict()))
	var back := Campaign.new(2)
	eq(back.load_dict(d), "", "loads")
	eq(back.story_views, {"trader_a": 3, "doors_briefing": 1}, "every event's count comes back")
	d.erase("story_views")
	var old := Campaign.new(3)
	old.story_views = {"x": 1}
	eq(old.load_dict(d), "", "an old save without the key loads")
	eq(old.story_views, {}, "with an empty memory")


func test_the_derelict_people_that_fit_a_station_can_appear_on_one() -> void:
	var c := Campaign.new(5)
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	for id in ["bnpc_hermit_one_light", "bnpc_hermit_dead_letters", "bnpc_survivor_bad_air"]:
		var ev: Dictionary = c.events.get_event(id)
		var role := str(ev["requires"]["role"])
		c.stage = 3
		check(c.events.eligible(ev, c, {"type": "boarding_npc", "site": "station", "theme": "", "role": role}, ship), id + " on a station")
		check(c.events.eligible(ev, c, {"type": "boarding_npc", "site": "derelict", "theme": "", "role": role}, ship), id + " still on a derelict")
	for id in ["bnpc_hermit_clock_winder", "bnpc_trader_room_pricer", "bnpc_trader_waiting_tow"]:
		var ev: Dictionary = c.events.get_event(id)
		check(not c.events.eligible(ev, c, {"type": "boarding_npc", "site": "station", "theme": "", "role": str(ev["requires"]["role"])}, ship), id + " stays derelict-only (its text says ship, derelict or wreck)")


func test_the_capital_recruiter_talks_when_the_crew_limit_is_reached() -> void:
	var c := Campaign.new(5)
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	var node := {"type": "boarding_npc", "site": "station", "theme": "", "role": "recruiter", "npc": {"id": 1, "name": "Pell", "species": "human", "role": "recruiter", "label": "Recruiter"}}
	var ev: Dictionary = c.events.get_event("bnpc_capital_recruiter")
	check(Events.is_recruiter_talk(ev), "it is a recruiter's talk")
	var hits := 0
	for i in 100:
		c.crew_offers = int(Events.offers_cap(c))
		if c.events.pick(c, node, ship).get("id", "") == "bnpc_capital_recruiter":
			hits += 1
	eq(hits, 100, "with the limit reached it is still the one picked")
	eq(c.crew_offers, int(Events.offers_cap(c)), "and a talk alone is not an offer")
	var texts: Array = c.events.choice_view(ev, c, ship, node).map(func(v): return str(v["text"]))
	check(not texts.any(func(t): return t.begins_with("Sign on")), "no recruit is offered then (%s)" % str(texts))
	check(texts.size() == 2, "the talk and the way out stay")
	c.crew_offers = 0
	c.events.pick(c, node, ship)
	eq(c.crew_offers, 0, "below the limit a talk is not an offer either")
	texts = c.events.choice_view(ev, c, ship, node).map(func(v): return str(v["text"]))
	check(texts.any(func(t): return t.begins_with("Sign on")), "below the limit the recruit is offered")
