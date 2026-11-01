extends "res://tests/base_test.gd"
## Beta 3, events refresh: the new requires (crew_min / crew_max, any-of lists and species_any / component_any), the one free crew
## offer a region makes, and the rules the new pack data/packs/events_2 keeps (alone-friendly, repeatable, no recruiting).

const Events = preload("res://scripts/space/events.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


## The Rustbucket with `plan` as its crew (names; the first is the soldier).
func _ship(plan: Array = [["Soldier", "human"]]) -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	s.crew_plan = plan.map(func(p): return {"name": p[0], "species": p[1]})
	Jobs.spawn_crew(s)
	return s


func _crewed() -> Ship:
	return _ship([["Soldier", "human"], ["Ada", "human"], ["Rook", "basalt"], ["Juno", "fenn"]])


func _events(list: Array) -> Events:
	var e := Events.new("res://tests")  # no *.json there
	for x in list:
		e.add(x, str(x.get("_file", "test.json")))
	e._index_recruiters()
	return e


func _camp(list: Array, seed_value := 1) -> Campaign:
	var c := Campaign.new(seed_value, {}, _events(list))
	c.cfg = c.cfg.duplicate(true)  # (the config is shared)
	return c


func _node(type: String) -> Dictionary:
	return {"id": "n99", "type": type, "place": ""}


func _ev(id: String, type: String, requires: Dictionary = {}, effects: Dictionary = {}, extra: Dictionary = {}) -> Dictionary:
	var e := {"id": id, "type": type, "weight": 10, "once": false, "requires": requires, "text": "Text of " + id,
		"choices": [{"text": "Go", "outcomes": [{"weight": 100, "text": "Done", "effects": effects}]}]}
	e.merge(extra, true)
	return e


func _shown(c: Campaign, ev: Dictionary, ship: Ship) -> Array:
	return c.events.choice_view(ev, c, ship, _node(str(ev["type"]))).map(func(v): return v["index"])


# --- crew_min / crew_max -----------------------------------------------------------------------------------------------

func test_crew_count_is_the_crew_besides_the_soldier() -> void:
	eq(Events.crew_count(_ship()), 0, "a soldier alone")
	eq(Events.crew_count(_crewed()), 3, "three crew besides the soldier")
	eq(Events.crew_count(null), 0, "no ship, no crew")


func test_a_choice_can_ask_for_crew_or_for_none() -> void:
	var out := [{"weight": 1, "text": "ok", "effects": {}}]
	var ev := {"id": "c", "type": "pirate", "text": "x", "choices": [
		{"text": "Plain", "outcomes": out},
		{"text": "Send someone", "requires": {"crew_min": 1}, "outcomes": out},
		{"text": "Send two", "requires": {"crew_min": 2, "crew_max": 2}, "outcomes": out},
		{"text": "Alone", "requires": {"crew_max": 0}, "outcomes": out}]}
	var c := _camp([ev])
	eq(_shown(c, ev, _ship()), [0, 3], "alone: the plain choice and the alone one")
	eq(_shown(c, ev, _ship([["Soldier", "human"], ["Ada", "human"]])), [0, 1], "one crewmate: send someone, not two, not alone")
	eq(_shown(c, ev, _ship([["Soldier", "human"], ["Ada", "human"], ["Rook", "basalt"]])), [0, 1, 2], "two crewmates")
	eq(_shown(c, ev, _crewed()), [0, 1], "three crewmates: more than the two asked for")
	check(not c.events.choose(ev, 1, c, _ship(), _node("pirate"))["ok"], "a hidden crew choice cannot be taken")
	check(c.events.choose(ev, 3, c, _ship(), _node("pirate"))["ok"], "and the alone one can")


func test_an_event_can_ask_for_crew_or_for_none() -> void:
	var needs := _ev("needs_crew", "pirate", {"crew_min": 2})
	var lone := _ev("lone_only", "pirate", {"crew_max": 0})
	var c := _camp([needs, lone])
	var n := _node("pirate")
	check(not c.events.eligible(needs, c, n, _ship()) and c.events.eligible(needs, c, n, _crewed()), "crew_min on an event")
	check(c.events.eligible(lone, c, n, _ship()) and not c.events.eligible(lone, c, n, _crewed()), "crew_max 0 on an event: alone only")
	for i in 20:
		eq(c.events.pick(c, n, _ship()).get("id"), "lone_only", "alone only the alone event is picked")
		eq(c.events.pick(c, n, _crewed()).get("id"), "needs_crew", "with a crew only the crewed one")


func test_the_validator_knows_the_new_requires_keys() -> void:
	var good := _ev("good", "pirate", {"crew_min": 1, "crew_max": 3}, {}, {"choices": [{"text": "x", "requires": {"crew_min": 1, "species_any": ["basalt", "fenn"], "component_any": ["shield_mk1", "shield_scrap_mk1"]}, "outcomes": [{"weight": 1, "text": "", "effects": {}}]}]})
	var bad := _ev("bad", "pirate", {"crew_min": "two"}, {}, {"choices": [{"text": "x", "requires": {"species_any": ["klingon"], "component_any": ["warp_core"]}, "outcomes": [{"weight": 1, "text": "", "effects": {}}]}]})
	var msgs := _events([good, bad]).validate()
	check(not msgs.any(func(m): return m.contains("'good'")), "the new keys are accepted")
	check(msgs.any(func(m): return m.contains("'bad'") and m.contains("crew_min must be a number")), "a text crew_min is refused")
	check(msgs.any(func(m): return m.contains("'bad'") and m.contains("klingon")), "an unknown species in species_any is refused")
	check(msgs.any(func(m): return m.contains("'bad'") and m.contains("warp_core")), "an unknown component in component_any is refused")


func test_a_part_of_a_pack_can_be_asked_for() -> void:
	var ev := _ev("strafe", "pirate", {}, {}, {"choices": [{"text": "x", "requires": {"component": "strafe_jets_mk1"}, "outcomes": [{"weight": 1, "text": "", "effects": {}}]}]})
	check(not _events([ev]).validate().any(func(m): return m.contains("strafe_jets_mk1")), "strafe jets (the engines pack) are a known component")


# --- any-of lists ------------------------------------------------------------------------------------------------------

func test_a_list_of_species_or_components_means_any_of_them() -> void:
	var out := [{"weight": 1, "text": "ok", "effects": {}}]
	var ev := {"id": "any", "type": "pirate", "text": "x", "choices": [
		{"text": "[Pair] a list", "requires": {"species": ["emberkin", "fenn"]}, "outcomes": out},
		{"text": "[Pair] none of them", "requires": {"species": ["emberkin", "mire"]}, "outcomes": out},
		{"text": "species_any", "requires": {"species_any": ["emberkin", "basalt"]}, "outcomes": out},
		{"text": "species_any, none", "requires": {"species_any": ["emberkin", "mire"]}, "outcomes": out},
		{"text": "a list of parts", "requires": {"component": ["reactor_scrap_kettle", "fabricator"]}, "outcomes": out},
		{"text": "component_any", "requires": {"component_any": ["warp", "fabricator"]}, "outcomes": out},
		{"text": "component_any, none", "requires": {"component_any": ["reactor_scrap_kettle", "radar_mk3"]}, "outcomes": out},
		{"text": "both keys must hold", "requires": {"species": "basalt", "species_any": ["emberkin", "mire"]}, "outcomes": out},
		{"text": "a plain species still works", "requires": {"species": "fenn"}, "outcomes": out}]}
	ev["choices"][5]["requires"]["component_any"] = ["reactor_scrap_kettle", "fabricator"]
	var c := _camp([ev])
	eq(_shown(c, ev, _crewed()), [0, 2, 4, 5, 8], "any one of the species or parts is enough; every key that is present must hold")
	eq(_shown(c, ev, _ship()), [4, 5], "a soldier alone has no species but the ship still has its fabricator")


func test_the_reason_of_a_blue_choice_names_the_parts_aboard() -> void:
	var out := [{"weight": 1, "text": "ok", "effects": {}}]
	var ev := {"id": "why", "type": "pirate", "text": "x", "choices": [
		{"text": "Use it", "requires": {"component_any": ["radar_mk3", "fabricator"]}, "outcomes": out},
		{"text": "Ask", "requires": {"species_any": ["fenn", "mire"]}, "outcomes": out}]}
	var c := _camp([ev])
	var view := c.events.choice_view(ev, c, _crewed(), _node("pirate"))
	eq(view.map(func(v): return v["text"]), ["[Fabricator] Use it", "[Fenn / Mire] Ask"], "the part that is fitted, the species asked for")
	check(view.all(func(v): return v["blue"]), "both are blue")


# --- one free crew offer a region ----------------------------------------------------------------------------------------

func _recruit(id: String, extra: Dictionary = {}, species := "fenn") -> Dictionary:
	var e := _ev(id, "wreck_field", {}, {"recruit": {"species": species}}, extra)
	return e


func _cap(c: Campaign, per_region := 1, exempt: Array = []) -> void:
	c.cfg["crew"] = {"species_event": 1.0, "unique_event": 1.0, "station_event": 1.0, "offers_per_region": per_region, "offers_exempt_packs": exempt}


func test_a_region_makes_one_crew_offer_and_a_new_region_another() -> void:
	var c := _camp([_recruit("rec_a"), _recruit("rec_b"), _ev("plain", "wreck_field")])
	_cap(c)
	var n := _node("wreck_field")
	var ship := _ship()
	eq(c.crew_offers, 0, "no offer yet")
	var first := ""
	for i in 40:
		var id := str(c.events.pick(c, n, ship).get("id"))
		if first == "" and id != "plain":
			first = id
			eq(c.crew_offers, 1, "the offer is counted when the event fires")
		elif first != "":
			eq(id, "plain", "after the offer only the event that adds nobody is picked")
	check(first != "", "an offer did come up")
	eq(c.crew_offers, 1, "and only one was counted")
	c.enter_region(c.region_id)
	eq(c.crew_offers, 0, "a new region starts with none")
	var again := false
	for i in 40:
		again = again or str(c.events.pick(c, n, ship).get("id")) != "plain"
	check(again, "and may make its offer")


func test_the_limit_is_in_the_config_and_missing_means_no_limit() -> void:
	var c := _camp([_recruit("rec_a"), _recruit("rec_b")])
	_cap(c, 3)
	for i in 10:
		c.events.pick(c, _node("wreck_field"), _ship())
	eq(c.crew_offers, 3, "three offers when the config says three")
	check(c.events.pick(c, _node("wreck_field"), _ship()).is_empty(), "then the pool is empty (both events add crew)")
	var free := _camp([_recruit("rec_a")])
	free.cfg["crew"] = {"species_event": 1.0, "unique_event": 1.0, "station_event": 1.0}
	for i in 10:
		eq(str(free.events.pick(free, _node("wreck_field"), _ship()).get("id")), "rec_a", "no offers_per_region: no limit")
	check(Campaign.config()["crew"].get("offers_per_region", 0) == 1, "the game's data/drift.json allows one")


func test_ada_and_the_story_packs_are_not_counted_or_stopped() -> void:
	var ada := _ev("ada_like", "wreck_field", {}, {"recruit": {"name": str(CrewMember.config()["ada"]["name"]), "species": "human"}})
	var story := _recruit("story_rec", {"_file": "res://data/packs/story_1/events/x.json"})
	var other := _recruit("other_rec")
	var c := _camp([ada, story, other, _ev("plain", "wreck_field")])
	_cap(c, 1, ["story_1"])
	check(not c.events.offers_crew("ada_like", c), "Ada's event is no offer")
	check(not c.events.offers_crew("story_rec", c), "an event of an exempt pack is no offer")
	check(c.events.offers_crew("other_rec", c) and not c.events.offers_crew("plain", c), "another recruiter is one, a plain event is not")
	c.crew_offers = 1  # the region has made its offer
	var seen := {}
	for i in 200:
		seen[str(c.events.pick(c, _node("wreck_field"), _ship()).get("id"))] = true
	check(seen.has("ada_like") and seen.has("story_rec") and seen.has("plain"), "Ada's, the story's and a plain event are still picked")
	check(not seen.has("other_rec"), "but not another recruiter")
	eq(c.crew_offers, 1, "and none of those counted")


func test_the_offer_counter_is_saved_and_an_old_save_has_none() -> void:
	check(Campaign.VERSION >= 9, "the counter came with save version 9")
	var c := Campaign.new(5)
	c.crew_offers = 1
	var d = JSON.parse_string(JSON.stringify(c.to_dict()))
	eq(int(d["crew_offers"]), 1, "saved")
	var back := Campaign.new(2)
	eq(back.load_dict(d), "", "loads")
	eq(back.crew_offers, 1, "and comes back")
	d.erase("crew_offers")
	d["version"] = 8
	var old := Campaign.new(3)
	old.crew_offers = 1
	eq(old.load_dict(d), "", "a version 8 save still loads")
	eq(old.crew_offers, 0, "with no offer made")
