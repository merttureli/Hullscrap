extends "res://tests/base_test.gd"
## The events of the Drift without a screen: the loader and the validator that protects every pack in
## data/events, requires filtering (events and choices), blue and greyed choices, weighted outcome rolls,
## every effect type, goto pages, once, fights calling back, the debt events and the pack conventions.

const Events = preload("res://scripts/space/events.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


## The Rustbucket with its starting crew (the Soldier, Ada, Rook the Basalt and Juno the Fenn).
func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	return s


## An event set holding only `list` (the logs of data/logs are loaded as usual).
func _events(list: Array) -> Events:
	var e := Events.new("res://tests")  # no *.json there
	for x in list:
		e.add(x, "test.json")
	return e


func _camp(list: Array = [], seed_value := 1) -> Campaign:
	return Campaign.new(seed_value, {}, _events(list))


## An event of one choice with one outcome.
func _ev(id: String, type: String, requires: Dictionary = {}, effects: Dictionary = {}, extra: Dictionary = {}) -> Dictionary:
	var e := {"id": id, "type": type, "weight": 10, "once": false, "requires": requires, "text": "Text of " + id,
		"choices": [{"text": "Go", "outcomes": [{"weight": 100, "text": "Done", "effects": effects}]}]}
	e.merge(extra, true)
	return e


func _node(type: String, place := "") -> Dictionary:
	return {"id": "n99", "type": type, "place": place}


func _has_view(view: Array, index: int) -> bool:
	return view.any(func(v): return v["index"] == index)


# --- loading and the validator ------------------------------------------------------------------------

func test_every_event_file_in_data_events_is_valid() -> void:
	var e := Events.new()
	check(e.order.size() >= 40, "the core events and the first pack are loaded (%d events)" % e.order.size())
	for msg in e.validate():
		check(false, msg)  # each message names the file and the event id


func test_the_loader_reads_every_json_file_in_the_folder() -> void:
	var e := Events.new()
	var from := {}
	for id in e.files:
		from[e.files[id]] = true
	check(from.has("res://data/events/core.json"), "core.json is read")
	check(from.has("res://data/events/drift_pack1.json") and from.has("res://data/events/drift_pack2.json") and from.has("res://data/events/stations.json"), "both packs and the station greetings are read")
	check(e.has("station_debt_intro") and e.has("distress_hauler_fire") and e.has("asteroid_tumbling_rock"), "events of both files are there")


func test_every_outcome_of_every_event_applies_and_every_choice_can_be_taken() -> void:
	var ship := _ship()
	ship.inventory.add("credits", 100000)
	ship.inventory.add("scrap", 1000)
	var events := Events.new()
	var outcomes := 0
	for id in events.order:
		var c := Campaign.new(3)
		var ev: Dictionary = events.events[id]
		for ch in ev.get("choices", []):
			for o in ch["outcomes"]:
				var r := c.events.apply(o.get("effects", {}), c, ship, _node(str(ev["type"])))
				check(r["lines"] is Array and r["logs"] is Array, "%s: the effects of an outcome apply" % id)
				outcomes += 1
		var view := c.events.choice_view(ev, c, ship, _node(str(ev["type"])))
		for v in view:
			check(v["text"] != "", "%s: choice %d has text" % [id, v["index"]])
	check(outcomes > 400, "every outcome of the packs was run (%d)" % outcomes)


func test_validator_names_the_file_and_the_event() -> void:
	var e := _events([
		_ev("bad_key", "pirate", {}, {}, {"colour": "red"}),
		_ev("bad_type", "volcano"),
		_ev("bad_effect", "pirate", {}, {"explode": 1}),
		_ev("bad_item", "pirate", {}, {"items": {"unobtainium": 5}}),
		_ev("bad_species", "pirate", {}, {"recruit": {"species": "klingon"}}),
		_ev("bad_goto", "pirate", {}, {"goto": "nowhere"}),
		_ev("bad_faction", "pirate", {}, {"rep": {"rustfangs": 1}}),
		_ev("bad_node", "pirate", {"node": "atlantis"}),
		_ev("bad_fight", "pirate", {}, {"fight": "no_such_design"}),
		_ev("bad_log", "pirate", {}, {"log": "no_such_log"}),
		_ev("bad_trait", "pirate", {}, {}, {"choices": [{"text": "x", "requires": {"trait": "telepathy"}, "outcomes": [{"weight": 1, "text": "", "effects": {}}]}]}),
		_ev("bad_component", "pirate", {}, {}, {"choices": [{"text": "x", "requires": {"component": "warp_core"}, "outcomes": [{"weight": 1, "text": "", "effects": {}}]}]}),
		_ev("Bad Id", "pirate"),
	])
	var errs := e.validate()
	var want := {"bad_key": "colour", "bad_type": "volcano", "bad_effect": "explode", "bad_item": "unobtainium", "bad_species": "klingon",
		"bad_goto": "nowhere", "bad_faction": "rustfangs", "bad_node": "atlantis", "bad_fight": "no_such_design", "bad_log": "no_such_log",
		"bad_trait": "telepathy", "bad_component": "warp_core", "Bad Id": "snake_case"}
	for id in want:
		check(errs.any(func(m): return m.begins_with("test.json: event '%s':" % id) and m.contains(want[id])), "an error names test.json, '%s' and '%s'" % [id, want[id]])
	eq(errs.size(), want.size(), "one error per broken event: " + str(errs))


func test_validator_reports_a_duplicate_id_in_two_files() -> void:
	var e := _events([_ev("twin", "pirate")])
	e.add(_ev("twin", "pirate"), "other.json")
	check(e.validate().any(func(m): return m.begins_with("other.json: event 'twin'") and m.contains("test.json")), "the second file is blamed and the first named")


func test_asteroid_field_is_a_valid_node_type_and_event_type() -> void:
	check(Events.NODE_TYPES.has("asteroid_field") and Events.EVENT_TYPES.has("asteroid_field"), "known")
	check(_events([_ev("rock", "asteroid_field")]).validate().is_empty(), "an asteroid_field event validates")
	check(Events.EVENT_TYPES.has("debt") and not Events.NODE_TYPES.has("debt"), "debt is an event type that is not a node type")


# --- the core events ----------------------------------------------------------------------------------------

func test_core_events_cover_every_node_type_and_station() -> void:
	var e := Events.new()
	var seen := {}
	for id in e.order:
		if e.files[id].ends_with("core.json"):
			var ev: Dictionary = e.events[id]
			seen[ev["type"]] = true
			if ev["type"] == "station":
				seen[ev["requires"].get("node", "")] = true
	for t in ["pirate", "wreck_field", "distress", "trader", "anomaly", "patrol", "empty", "asteroid_field", "rusthold", "meridian", "prism"]:
		check(seen.has(t), "core.json has an event for " + t)
	var intro: Dictionary = e.get_event("station_debt_intro")
	check(intro["once"] and intro["requires"]["node"] == "rusthold", "Ma's introduction is a once-event at Rusthold")
	check(JSON.stringify(intro).contains("met_ma"), "it sets the flag met_ma")
	check(e.get_event("repo_collectors")["requires"]["flag"] == "debt_missed", "the repo crew come when a payment is missed")


func test_the_two_asteroid_events_offer_surface_mining_the_deep_vein_and_moving_on() -> void:
	var e := Events.new()
	var found := 0
	for id in e.order:
		var ev: Dictionary = e.events[id]
		if ev["type"] != "asteroid_field" or not e.files[id].ends_with("core.json"):
			continue
		found += 1
		eq(ev["choices"].map(func(c): return c["text"]), ["Surface mining.", "Crack the deep vein.", "Move on."], id + " choices")
		var surface: Array = ev["choices"][0]["outcomes"]
		for o in surface:
			var n: int = o["effects"]["items"]["scrap"]
			check(n >= 20 and n <= 40 and o["effects"].size() == 1, id + ": surface mining is safe, scrap 20 to 40")
		var deep: Array = ev["choices"][1]["outcomes"]
		var good := 0.0
		var bad := 0.0
		for o in deep:
			var items: Dictionary = o["effects"].get("items", {})
			if o["effects"].has("hull"):
				eq(o["effects"]["hull"], -10, id + ": the bad outcome costs 10 hull")
				bad += o["weight"]
			else:
				good += o["weight"]
				check((items.has("copper") and items["copper"] >= 15 and items["copper"] <= 30) or (items.has("titanium") and items["titanium"] >= 10 and items["titanium"] <= 20), id + ": copper 15-30 or titanium 10-20")
		eq([good, bad], [60.0, 40.0], id + ": 60% ore, 40% hull damage")
	eq(found, 2, "two asteroid events in core.json")


# --- requires on events -----------------------------------------------------------------------------------------

func test_event_requires_jumps_flags_reputation_and_node() -> void:
	var c := _camp([
		_ev("early", "pirate", {"jumps_max": 3}),
		_ev("late", "wreck_field", {"jumps_min": 5}),
		_ev("flagged", "distress", {"flag": "met_ma"}),
		_ev("unflagged", "trader", {"not_flag": "met_ma"}),
		_ev("friend", "anomaly", {"rep_min": {"clans": 3}}),
		_ev("enemy", "patrol", {"rep_max": {"concord": -3}}),
		_ev("rusty", "station", {"node": "rusthold"}),
		_ev("typed", "empty", {"node": "empty"}),
	])
	var ship := _ship()
	var ev := c.events
	check(not ev.pick(c, _node("pirate"), ship).is_empty(), "jumps_max 3 holds at jump 0")
	c.jumps = 4
	check(ev.pick(c, _node("pirate"), ship).is_empty(), "jumps_max 3 fails at jump 4")
	check(ev.pick(c, _node("wreck_field"), ship).is_empty(), "jumps_min 5 fails at jump 4")
	c.jumps = 5
	check(not ev.pick(c, _node("wreck_field"), ship).is_empty(), "jumps_min 5 holds at jump 5")
	check(ev.pick(c, _node("distress"), ship).is_empty(), "a flag that is not set blocks")
	c.flags["met_ma"] = true
	check(not ev.pick(c, _node("distress"), ship).is_empty(), "a flag that is set lets it through")
	check(ev.pick(c, _node("trader"), ship).is_empty(), "not_flag blocks when the flag is set")
	check(ev.pick(c, _node("anomaly"), ship).is_empty(), "rep_min 3 fails at 0")
	c.rep["lumen"] = 3
	check(ev.pick(c, _node("anomaly"), ship).is_empty(), "rep_min is per faction: lumen 3 does not do for clans")
	c.rep["clans"] = 3
	check(not ev.pick(c, _node("anomaly"), ship).is_empty(), "clans 3 does")
	check(ev.pick(c, _node("patrol"), ship).is_empty(), "rep_max -3 fails at 0")
	c.rep["concord"] = -3
	check(not ev.pick(c, _node("patrol"), ship).is_empty(), "rep_max -3 holds at -3")
	check(not ev.pick(c, _node("station", "rusthold"), ship).is_empty(), "node matches a place id")
	check(ev.pick(c, _node("station", "meridian"), ship).is_empty(), "and only that place")
	check(not ev.pick(c, _node("empty"), ship).is_empty(), "node matches a node type")


func test_a_once_event_is_spent_only_by_an_outcome_that_does_something() -> void:
	var leave := {"text": "Leave", "outcomes": [{"weight": 1, "text": "You go.", "effects": {}}]}
	var act := {"text": "Act", "outcomes": [{"weight": 1, "text": "Done.", "effects": {"items": {"scrap": 1}}}]}
	var c := _camp([_ev("quest", "pirate", {}, {}, {"once": true, "choices": [leave, act]})])
	var ship := _ship()
	var ev := c.events.pick(c, _node("pirate"), ship)
	eq(ev.get("id", ""), "quest", "the first time")
	check(not c.used.has("quest"), "being picked spends nothing")
	check(c.events.choose(ev, 0, c, ship)["ok"], "a Leave choice (empty effects)")
	check(not c.used.has("quest"), "does not burn the quest step")
	eq(c.events.pick(c, _node("pirate"), ship).get("id", ""), "quest", "so it comes again")
	check(c.events.choose(ev, 1, c, ship)["ok"], "a choice that does something")
	check(c.used.has("quest"), "spends it")
	check(c.events.pick(c, _node("pirate"), ship).is_empty(), "and it never comes back")


func test_a_once_event_that_only_has_a_goto_effect_is_spent() -> void:
	var c := _camp([_ev("start", "pirate", {}, {"goto": "next"}, {"once": true}), _ev("next", "pirate", {}, {}, {"weight": 0})])
	var ship := _ship()
	c.events.choose(c.events.pick(c, _node("pirate"), ship), 0, c, ship)
	check(c.used.has("start"), "a goto is an effect")


func test_pages_and_weight_zero_events_are_never_picked() -> void:
	var c := _camp([
		_ev("opener", "distress", {}, {"goto": "page_two"}),
		_ev("page_two", "distress"),
		_ev("silent", "distress", {}, {}, {"weight": 0}),
		_ev("typed_page", "page"),
	])
	var ship := _ship()
	for i in 30:
		eq(c.events.pick(c, _node("distress"), ship).get("id", ""), "opener", "only the opener is rolled")


func test_picks_are_weighted_and_follow_the_seed() -> void:
	var list := [_ev("heavy", "pirate", {}, {}, {"weight": 90}), _ev("light", "pirate", {}, {}, {"weight": 10})]
	var ship := _ship()
	var runs := []
	for k in 2:
		var c := _camp(list, 42)
		var seq := []
		for i in 100:
			seq.append(c.events.pick(c, _node("pirate"), ship)["id"])
		runs.append(seq)
	eq(runs[0], runs[1], "same seed, same events")
	var heavy: int = runs[0].count("heavy")
	check(heavy > 75 and heavy < 100, "about 90 of 100 are the heavy one (%d)" % heavy)


# --- requires on choices: hidden, greyed, blue ----------------------------------------------------------------------

func _choices_event() -> Dictionary:
	var out := func(text := "ok") -> Array: return [{"weight": 1, "text": text, "effects": {}}]
	return {"id": "many", "type": "pirate", "text": "x", "choices": [
		{"text": "Plain", "outcomes": out.call()},
		{"text": "[Basalt] Walk out", "requires": {"species": "basalt"}, "outcomes": out.call()},
		{"text": "Walk out as a klingon", "requires": {"species": "emberkin"}, "outcomes": out.call()},
		{"text": "Breathe less", "requires": {"trait": "no_breath"}, "outcomes": out.call()},
		{"text": "Use the fabricator", "requires": {"component": "fabricator"}, "outcomes": out.call()},
		{"text": "Use a warp drive", "requires": {"component": "reactor_scrap_kettle"}, "outcomes": out.call()},
		{"text": "Pay in scrap", "requires": {"items": {"scrap": 100000}}, "outcomes": out.call()},
		{"text": "Pay in credits", "requires": {"credits": 100000}, "outcomes": out.call()},
		{"text": "Pay a little", "requires": {"credits": 10}, "outcomes": out.call()},
		{"text": "Needs the flag", "requires": {"flag": "never"}, "outcomes": out.call()},
		{"text": "Needs a rich friend", "requires": {"rep_min": {"lumen": 5}, "credits": 100000}, "outcomes": out.call()},
		{"text": "Fenn and broke", "requires": {"species": "fenn", "credits": 100000}, "outcomes": out.call()},
	]}


func test_choices_are_hidden_greyed_or_blue() -> void:
	var c := _camp()
	var ship := _ship()
	var ev := _choices_event()
	var view := c.events.choice_view(ev, c, ship, _node("pirate"))
	var by := {}
	for v in view:
		by[v["index"]] = v
	check(by.has(0) and not by[0]["blue"] and not by[0]["grey"], "a plain choice shows normally")
	check(by.has(1) and by[1]["blue"] and not by[1]["grey"], "a species the crew has: blue")
	check(not by.has(2), "a species the crew lacks: hidden")
	check(by.has(3) and by[3]["blue"], "a trait someone has (the Basalt does not breathe): blue")
	check(by.has(4) and by[4]["blue"], "an installed component: blue")
	check(not by.has(5), "a component that is not installed: hidden")
	check(by.has(6) and by[6]["grey"] and not by[6]["blue"] and by[6]["need"].contains("100000") and by[6]["need"].contains("Scrap"), "missing items: greyed, with the need")
	check(by.has(7) and by[7]["grey"] and by[7]["need"] == "100000 credits", "missing credits: greyed, with the need")
	check(by.has(8) and ship.inventory.count("credits") >= 10 and not by[8]["grey"], "enough credits: on offer")
	check(not by.has(9), "a flag that is not set: hidden")
	check(not by.has(10), "reputation not met: hidden even though credits are short too")
	check(not by.has(11) or by[11]["grey"], "a blue choice that only lacks credits is greyed, not hidden")
	check(by[11]["blue"] and by[11]["grey"], "and still blue")


func test_blue_choices_get_their_reason_in_brackets() -> void:
	var c := _camp()
	var ship := _ship()
	var view := c.events.choice_view(_choices_event(), c, ship, _node("pirate"))
	var by := {}
	for v in view:
		by[v["index"]] = v
	eq(by[1]["text"], "[Basalt] Walk out", "text that already has a bracket is left alone")
	eq(by[3]["text"], "[Doesn't breathe] Breathe less", "a trait gets its label")
	eq(by[4]["text"], "[Fabricator] Use the fabricator", "a component gets its name")


func test_a_greyed_choice_cannot_be_taken_and_costs_nothing() -> void:
	var c := _camp()
	var ship := _ship()
	var ev := _choices_event()
	var scrap := ship.inventory.count("scrap")
	var r := c.events.choose(ev, 6, c, ship, _node("pirate"))
	check(not r["ok"] and r["why"].begins_with("needs "), "refused with the need: " + str(r["why"]))
	eq(ship.inventory.count("scrap"), scrap, "nothing was paid")
	check(not c.events.choose(ev, 9, c, ship, _node("pirate"))["ok"], "a hidden choice cannot be taken either")


func test_items_and_credits_are_paid_only_when_pay_is_set() -> void:
	var c := _camp()
	var ship := _ship()
	var free := {"id": "f", "type": "pirate", "text": "x", "choices": [{"text": "Show the scrap", "requires": {"items": {"scrap": 50}}, "outcomes": [{"weight": 1, "text": "", "effects": {}}]}]}
	var scrap := ship.inventory.count("scrap")
	check(c.events.choose(free, 0, c, ship)["ok"], "held items are enough")
	eq(ship.inventory.count("scrap"), scrap, "and they are not taken")
	var paid := {"id": "p", "type": "pirate", "text": "x", "choices": [{"text": "Pay", "requires": {"items": {"scrap": 50}, "credits": 25, "pay": true}, "outcomes": [{"weight": 1, "text": "", "effects": {}}]}]}
	var credits := ship.inventory.count("credits")
	var r := c.events.choose(paid, 0, c, ship)
	eq([ship.inventory.count("scrap"), ship.inventory.count("credits")], [scrap - 50, credits - 25], "with pay set both are taken")
	check(r["lines"].has("-25 credits") and r["lines"].has("-50 Scrap"), "and said in the lines: " + str(r["lines"]))
	var on_choice := {"id": "q", "type": "pirate", "text": "x", "choices": [{"text": "Pay", "pay": true, "requires": {"credits": 5}, "outcomes": [{"weight": 1, "text": "", "effects": {}}]}]}
	c.events.choose(on_choice, 0, c, ship)
	eq(ship.inventory.count("credits"), credits - 30, "pay on the choice works too")


# --- outcome rolls -------------------------------------------------------------------------------------------------------

func test_outcome_rolls_are_weighted_and_deterministic() -> void:
	var outcomes := [{"weight": 70, "text": "a"}, {"weight": 30, "text": "b"}]
	var seqs := []
	for k in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		var seq := []
		for i in 400:
			seq.append(Events.roll(outcomes, rng)["text"])
		seqs.append(seq)
	eq(seqs[0], seqs[1], "the same seed rolls the same outcomes")
	var a: int = seqs[0].count("a")
	check(a > 240 and a < 320, "about 70%% are the first (%d of 400)" % a)
	var rng := RandomNumberGenerator.new()
	eq(Events.roll([], rng), {}, "no outcomes: nothing")
	eq(Events.roll([{"weight": 0, "text": "only"}], rng)["text"], "only", "all weights zero: the first")


# --- effects, one test each ------------------------------------------------------------------------------------------------

func _fx(effects: Dictionary, c: Campaign, ship: Ship) -> Dictionary:
	return c.events.apply(effects, c, ship, _node("empty"))


func test_effect_items_give_and_take_cargo_credits_fuel_materials_and_parts() -> void:
	var c := _camp()
	var ship := _ship()
	var before := {"credits": ship.inventory.count("credits"), "fuel": ship.inventory.count("fuel"), "titanium": ship.inventory.count("titanium"), "pulse_mk1": ship.inventory.count("pulse_mk1")}
	var r := _fx({"items": {"credits": 40, "fuel": -2, "titanium": 7, "pulse_mk1": 1}}, c, ship)
	eq(ship.inventory.count("credits"), before["credits"] + 40, "credits")
	eq(ship.inventory.count("fuel"), before["fuel"] - 2, "fuel")
	eq(ship.inventory.count("titanium"), before["titanium"] + 7, "a material")
	eq(ship.inventory.count("pulse_mk1"), before["pulse_mk1"] + 1, "a component")
	check(r["lines"].has("+40 credits") and r["lines"].has("-2 Fuel") and r["lines"].has("+1 Pulse Mk1"), "the lines say so: " + str(r["lines"]))
	_fx({"items": {"credits": -100000}}, c, ship)
	eq(ship.inventory.count("credits"), 0, "taking more than is held stops at zero")


func test_effect_rep_changes_a_faction_and_is_clamped_to_ten() -> void:
	var c := _camp()
	var ship := _ship()
	var r := _fx({"rep": {"clans": 4, "concord": -2}}, c, ship)
	eq([c.rep["clans"], c.rep["concord"], c.rep["lumen"]], [4, -2, 0], "each faction moves on its own")
	check(r["lines"].has("Clans reputation +4"), "said in the lines: " + str(r["lines"]))
	_fx({"rep": {"clans": 50, "concord": -50}}, c, ship)
	eq([c.rep["clans"], c.rep["concord"]], [10, -10], "clamped to +-10")


func test_effect_crew_hp_hurts_and_heals_everyone() -> void:
	var c := _camp()
	var ship := _ship()
	_fx({"crew_hp": -30}, c, ship)
	for m in ship.crew:
		eq(m.hp, m.max_hp - 30.0, m.name + " lost 30 hp")
	_fx({"crew_hp": 20}, c, ship)
	for m in ship.crew:
		eq(m.hp, m.max_hp - 10.0, m.name + " got 20 back")
	_fx({"crew_hp": -1000}, c, ship)
	check(ship.crew.all(func(m): return m.hp == 0.0 and m.is_down()), "hp stops at 0 and they are down")


func test_effect_hull_changes_integrity_and_never_kills_the_ship() -> void:
	var c := _camp()
	var ship := _ship()
	var top := c.hull_max(ship)
	_fx({"hull": -10}, c, ship)
	eq(c.hull_left(ship), top - 10, "integrity -10")
	_fx({"hull": 4}, c, ship)
	eq(c.hull_left(ship), top - 6, "integrity +4")
	_fx({"hull": 500}, c, ship)
	eq(c.hull_left(ship), top, "never above the maximum")
	_fx({"hull": -100000}, c, ship)
	eq(c.hull_left(ship), 1, "events never take the last point")


func test_effect_flag_and_clear_flag() -> void:
	var c := _camp()
	var ship := _ship()
	_fx({"flag": "met_ma"}, c, ship)
	_fx({"flag": ["a", "b"]}, c, ship)
	check(c.flags.has("met_ma") and c.flags.has("a") and c.flags.has("b"), "flags set, one or a list")
	_fx({"clear_flag": "a"}, c, ship)
	check(not c.flags.has("a") and c.flags.has("b"), "clear_flag removes it")


func test_effect_recruit_adds_a_crew_member_of_the_species() -> void:
	var c := _camp()
	var ship := _ship()
	var n := ship.crew.size()
	var r := _fx({"recruit": {"species": "emberkin", "name": "Cinder"}}, c, ship)
	eq(ship.crew.size(), n + 1, "one more aboard")
	var m = ship.crew[-1]
	eq([m.name, m.species], ["Cinder", "emberkin"], "the name and the species")
	check(m.traits().has("heat_resistant"), "the species gives its traits")
	check(r["lines"].has("Cinder (Emberkin) joins the crew"), "said: " + str(r["lines"]))
	_fx({"recruit": {"species": "fenn"}}, c, ship)
	check(ship.crew[-1].species == "fenn" and ship.crew[-1].name != "", "no name given: one is picked")
	var names := ship.crew.map(func(x): return x.name)
	eq(names.size(), (names.duplicate() as Array).filter(func(x): return names.count(x) == 1).size(), "and it is nobody's name already")


func test_effect_lose_crew_takes_a_random_non_player() -> void:
	var c := _camp()
	var ship := _ship()
	var n := ship.crew.size()
	var r := _fx({"lose_crew": 1}, c, ship)
	eq(ship.crew.size(), n - 1, "one crew member gone")
	check(ship.crew.any(func(m): return m.is_player), "never the player")
	check(r["lines"].size() == 1 and r["lines"][0].ends_with("is lost"), "said: " + str(r["lines"]))
	_fx({"lose_crew": 100}, c, ship)
	eq(ship.crew.size(), 1, "only the player is left")
	_fx({"lose_crew": true}, c, ship)
	eq(ship.crew.size(), 1, "and the player stays")


func test_effect_blueprint_unlocks_a_recipe() -> void:
	var c := _camp()
	var ship := _ship()
	var locked := ""
	for id in ship.crafting.ids():
		if not ship.crafting.is_known(id):
			locked = id
			break
	check(locked != "", "there is a locked blueprint to learn")
	var r := _fx({"blueprint": locked}, c, ship)
	check(ship.crafting.is_known(locked), "learned")
	check(r["lines"].size() == 1 and r["lines"][0].begins_with("Blueprint learned"), "said: " + str(r["lines"]))
	eq(_fx({"blueprint": locked}, c, ship)["lines"].size(), 0, "nothing new the second time")


func test_effect_fight_is_handed_back_not_started() -> void:
	var c := _camp()
	var ship := _ship()
	eq(_fx({"fight": "tier"}, c, ship)["fight"], "tier", "tier")
	eq(_fx({"fight": "pirate_raider"}, c, ship)["fight"], "pirate_raider", "a design id")
	eq(c.fight_path("pirate_raider", "pirate"), "res://data/ships/pirate_raider.json", "which is a file in data/ships")
	check(FileAccess.file_exists(c.fight_path("tier", "pirate")), "tier rolls a design that exists")


func test_effect_goto_names_the_next_page() -> void:
	var c := _camp()
	eq(_fx({"goto": "somewhere"}, c, _ship())["goto"], "somewhere", "goto")


func test_effect_reveal_shows_a_node_or_a_station_on_the_map() -> void:
	var c := _camp()
	var ship := _ship()
	c.enter_region("gate_approaches")
	check(not c.is_known("gate_1"), "the Concord Gate is far away and unknown")
	var far := ""
	for id in c.drift.ids():
		if not c.is_known(id) and id != "gate_1":
			far = id
			break
	var r := _fx({"reveal": [far, "gate_1"]}, c, ship)
	check(c.is_known(far) and c.is_known("gate_1"), "revealed nodes show their type")
	check(r["lines"].size() == 2 and r["lines"][0].begins_with("On the map:"), "said: " + str(r["lines"]))
	eq(_fx({"reveal": "no_such_place"}, c, ship)["lines"].size(), 0, "an unknown id does nothing")


func test_effect_debt_changes_what_is_owed_and_counts_as_payments() -> void:
	var c := _camp()
	var ship := _ship()
	var r := _fx({"debt": 50}, c, ship)
	eq(c.debt, 1050, "a penalty")
	check(r["lines"].has("Debt +50"), "said: " + str(r["lines"]))
	_fx({"debt": -250}, c, ship)
	eq([c.debt, c.paid], [800, 250], "forgiven or paid: it counts towards the payments")
	_fx({"debt": -100000}, c, ship)
	eq(c.debt, 0, "never below zero")
	check(c.flags.has("debt_free") and ship.inventory.count("reactor_scrap_kettle") == 1, "clearing it by event also pays out the Kettle")


func test_effect_log_shows_a_derelict_log_and_remembers_it() -> void:
	var c := _camp()
	var ship := _ship()
	var id: String = c.events.logs.keys()[0]
	var r := _fx({"log": id}, c, ship)
	eq(r["logs"].size(), 1, "the log comes back")
	check(r["logs"][0]["text"] != "" and r["logs"][0]["title"] != "", "with a title and a text")
	check(c.logs_found.has(id), "and the campaign remembers it")
	check(r["lines"].size() == 1 and r["lines"][0].begins_with("Log found: "), "said: " + str(r["lines"]))
	var back := Campaign.new(1)
	eq(back.load_dict(c.to_dict()), "", "saved")
	check(back.logs_found.has(id), "and loaded")
	eq(_fx({"log": "no_such_log"}, c, ship)["logs"].size(), 0, "an unknown id does nothing")


func test_every_effect_type_in_the_spec_is_known_to_the_validator() -> void:
	var want := ["items", "rep", "crew_hp", "hull", "flag", "clear_flag", "recruit", "lose_crew", "blueprint", "fight", "goto", "reveal", "debt", "log"]
	for k in want:
		check(Events.EFFECT_KEYS.has(k), k + " is an effect")
	eq(Events.EFFECT_KEYS.size(), want.size(), "and there are no others")


# --- goto, fights ---------------------------------------------------------------------------------------------------------------

func test_goto_chains_pages() -> void:
	var c := _camp([
		_ev("one", "pirate", {}, {"goto": "two", "items": {"scrap": 1}}),
		_ev("two", "pirate", {}, {"goto": "three"}, {"weight": 0}),
		_ev("three", "pirate", {}, {"items": {"scrap": 2}}, {"weight": 0}),
	])
	var ship := _ship()
	var scrap := ship.inventory.count("scrap")
	var ev := c.events.pick(c, _node("pirate"), ship)
	var r := c.events.choose(ev, 0, c, ship)
	eq(r["goto"], "two", "page one leads to two")
	r = c.events.choose(c.events.get_event(r["goto"]), 0, c, ship)
	eq(r["goto"], "three", "two leads to three")
	r = c.events.choose(c.events.get_event(r["goto"]), 0, c, ship)
	eq(r["goto"], "", "three ends the chain")
	eq(ship.inventory.count("scrap"), scrap + 3, "every page applied its effects")


func test_a_won_fight_calls_back_with_loot_and_the_after_win_text() -> void:
	var after := {"text": "Their ledger floats by.", "effects": {"items": {"fuel": 2}, "rep": {"clans": -1}}}
	var c := _camp([_ev("brawl", "pirate", {}, {"fight": "tier"}, {"after_win": after})])
	var ship := _ship()
	var ev := c.events.pick(c, _node("pirate"), ship)
	var r := c.events.choose(ev, 0, c, ship)
	eq([r["fight"], r["after_win"]], ["tier", after], "the choice hands back the fight and its after_win")
	var credits := ship.inventory.count("credits")
	var fuel := ship.inventory.count("fuel")
	var done := c.fight_done({"state": "won", "hull": 100.0, "hull_max": 120.0, "enemy": Ship.from_design("res://data/ships/pirate_raider.json")}, ship, r["after_win"])
	eq(done["state"], "won", "state")
	eq(done["text"], "Their ledger floats by.", "the after_win text is shown")
	eq(ship.inventory.count("fuel"), fuel + 2, "its effects ran")
	eq(c.rep["clans"], -1, "including reputation")
	check(ship.inventory.count("credits") >= credits + 20 and ship.inventory.count("credits") <= credits + 60, "loot: credits 20-60 at tier 1")
	eq(c.hull_loss, 20, "the hull integrity left in the fight is kept")


func test_loot_scales_with_the_tier_and_may_include_an_enemy_part() -> void:
	var enemy: Ship = Ship.from_design("res://data/ships/pirate_raider.json")
	var parts := {}
	for inst in enemy.components.instances.values():
		parts[inst["id"]] = true
	var got_part := 0
	for seed_value in 60:
		var c := _camp([], seed_value)
		var ship := _ship()
		c.jumps = 30  # tier 3
		var credits := ship.inventory.count("credits")
		var scrap := ship.inventory.count("scrap")
		var before := ship.inventory.counts.duplicate()
		c.loot(enemy, ship)
		var dc: int = ship.inventory.count("credits") - credits
		var ds: int = ship.inventory.count("scrap") - scrap
		check(dc >= 60 and dc <= 180, "credits 20-60 x tier 3 (%d)" % dc)
		check(ds >= 90 and ds <= 240, "scrap 30-80 x tier 3 (%d)" % ds)
		for id in ship.inventory.counts:
			if parts.has(id) and ship.inventory.count(id) > int(before.get(id, 0)):
				got_part += 1
	check(got_part > 5 and got_part < 30, "about a quarter of the wins give one of the enemy's parts (%d of 60)" % got_part)


func test_a_lost_fight_ends_the_run_and_a_fled_one_gives_nothing() -> void:
	var c := _camp()
	var ship := _ship()
	var credits := ship.inventory.count("credits")
	eq(c.fight_done({"state": "lost"}, ship)["state"], "lost", "lost")
	var fled := c.fight_done({"state": "fled", "hull": 90.0, "hull_max": 100.0}, ship)
	eq(fled["state"], "fled", "fled")
	eq(ship.inventory.count("credits"), credits, "no loot for running")
	eq(c.hull_loss, 10, "but the damage stays")


# --- the debt events (type debt) -----------------------------------------------------------------------------------------------

func _hop(c: Campaign, ship: Ship, n: int) -> Dictionary:
	var last := {}
	for i in n:
		var to := ""
		for o in c.neighbours(c.current):
			if c.node(o)["type"] != "gate":
				to = o
				break
		last = c.jump(to, ship)
		check(last["ok"], "hop %d: %s" % [i, last["why"]])
	return last


func test_debt_events_come_from_the_clock_by_their_requires() -> void:
	var first := _ev("debt_first", "debt", {"jumps_min": 2, "not_flag": "met_ma"}, {"flag": "met_ma"}, {"once": true})
	var remind := _ev("debt_remind", "debt", {"jumps_min": 6, "flag": "met_ma", "not_flag": "debt_missed"})
	var repo := _ev("debt_repo", "debt", {"flag": "debt_missed"})
	var c := _camp([first, remind, repo, _ev("plain", "empty"), _ev("plain_pirate", "pirate"), _ev("plain_wreck", "wreck_field"), _ev("plain_asteroid", "asteroid_field"),
		_ev("plain_distress", "distress"), _ev("plain_trader", "trader"), _ev("plain_anomaly", "anomaly"), _ev("plain_patrol", "patrol")])
	var ship := _ship()
	ship.inventory.add("fuel", 100)
	eq(Events.debt_kind(first), "first", "not_flag met_ma: Ma's first call")
	eq(Events.debt_kind(remind), "reminder", "otherwise a reminder")
	eq(Events.debt_kind(repo), "miss", "flag debt_missed: the collectors' talk")
	_hop(c, ship, 1)
	check(c.arrive(ship)["event"].get("id", "") != "debt_first", "too early for Ma's first call (jumps_min 2)")
	_hop(c, ship, 1)
	eq(c.arrive(ship)["event"].get("id", ""), "debt_first", "at jump 2 Ma calls, before the node's own event")
	c.flags["met_ma"] = true
	_hop(c, ship, 3)  # jump 5: the payment is 3 jumps away
	check(c.arrive(ship)["event"].get("type", "") != "debt", "no reminder when the payment is more than 2 jumps off")
	_hop(c, ship, 1)  # jump 6: due within 2
	eq(c.arrive(ship)["event"].get("id", ""), "debt_remind", "a reminder when a payment is due within 2 jumps")
	_hop(c, ship, 1)  # jump 7
	check(c.arrive(ship)["event"].get("type", "") != "debt", "once per payment cycle")
	_hop(c, ship, 1)  # jump 8: the payment falls due and is missed
	check(c.flags.has("debt_missed"), "the campaign sets debt_missed when a payment is missed")
	_hop(c, ship, 1)  # jump 9: the jump after
	eq(c.arrive(ship)["event"].get("id", ""), "debt_repo", "the collectors talk on the jump after a missed payment")
	_hop(c, ship, 1)
	check(c.arrive(ship)["event"].get("type", "") != "debt", "only that jump")


func test_fuel_max_requires_checks_the_hold() -> void:
	var c := _camp([_ev("dry", "trader", {"fuel_max": 0})])
	var ship := _ship()
	check(c.events.pick(c, _node("trader"), ship).is_empty(), "with fuel aboard it does not come")
	ship.inventory.counts.erase("fuel")
	eq(c.events.pick(c, _node("trader"), ship).get("id", ""), "dry", "with the tank empty it does")
	var choice := {"id": "x", "type": "trader", "text": "x", "choices": [{"text": "Beg", "requires": {"fuel_max": 1}, "outcomes": [{"weight": 1, "text": "", "effects": {}}]}]}
	ship.inventory.add("fuel", 1)
	check(c.events.choice_view(choice, c, ship).size() == 1, "fuel_max 1 holds with 1 fuel on a choice")
	ship.inventory.add("fuel", 1)
	check(c.events.choice_view(choice, c, ship).is_empty(), "and fails with 2")


func test_waiting_with_an_empty_tank_brings_a_trader() -> void:
	var c := _camp([_ev("peddler", "trader", {}, {"items": {"fuel": 1}})])
	var ship := _ship()
	check(not c.wait(ship)["ok"], "you cannot wait while you have fuel")
	ship.inventory.counts.erase("fuel")
	var r := c.wait(ship)
	check(r["ok"] and r["event"].get("id", "") == "peddler", "a trader passes")
	eq(c.jumps, 1, "and time passed")


func test_station_events_greet_each_station_and_the_debt_intro_opens_the_run() -> void:
	var c := Campaign.new(5)
	var ship := _ship()
	var a := c.arrive(ship)
	eq(a["event"].get("id", ""), "station_debt_intro", "a new run opens with Ma Gantry at Rusthold")
	var r := c.events.choose(a["event"], 0, c, ship, a["node"])
	check(r["ok"] and c.flags.has("met_ma"), "signing sets met_ma")
	var greeting: Dictionary = c.arrive(ship)["event"]
	eq(greeting.get("type", ""), "station", "afterwards Rusthold greets you with a station event")
	check(greeting.get("id", "") == "station_rusthold_greeting" or Events._list(greeting["requires"].get("flag")).has("at_rusthold"), "one of Rusthold's: " + str(greeting.get("id", "")))
	c.flags.erase("at_rusthold")  # (picking at other stations without travelling there)
	for place in ["meridian", "prism"]:
		var ev := c.events.pick(c, {"id": place, "type": "station", "place": place}, ship)
		eq(ev.get("id", ""), "station_%s_greeting" % place, place + " has its greeting")


func test_the_station_flag_is_set_while_docked_and_cleared_on_leaving() -> void:
	var c := _camp([_ev("hello", "station", {"flag": "at_rusthold"}, {}), _ev("elsewhere", "station", {"flag": "at_meridian"}, {})], 2)
	var ship := _ship()
	check(not c.flags.has("at_rusthold"), "not docked before arriving")
	eq(c.arrive(ship)["event"].get("id", ""), "hello", "docking at Rusthold runs a greeting that asks for at_rusthold")
	check(c.flags.has("at_rusthold") and not c.flags.has("at_meridian"), "the flag is set for that station only")
	c.rep["clans"] = -8
	c.flags.erase("at_rusthold")
	check(c.arrive(ship)["refused"] != "" and not c.flags.has("at_rusthold"), "a station that turns you away does not dock you")
	c.rep["clans"] = 0
	c.arrive(ship)
	check(c.flags.has("at_rusthold"), "docked again")
	check(c.jump(_neighbour(c), ship)["ok"], "jumped away")
	check(not c.flags.has("at_rusthold"), "undocked: the flag is cleared")
	var back := Campaign.new(2)
	back.arrive(ship)
	eq(back.load_dict(c.to_dict()), "", "(a save keeps the flags)")


func test_a_station_event_is_picked_by_weight_among_the_greetings() -> void:
	var list := [_ev("heavy", "station", {"flag": "at_rusthold"}, {}, {"weight": 90}), _ev("light", "station", {"flag": "at_rusthold"}, {}, {"weight": 10})]
	var ship := _ship()
	var counts := {"heavy": 0, "light": 0}
	for seed_value in 50:
		var c := _camp(list, seed_value)
		counts[c.arrive(ship)["event"]["id"]] += 1
	check(counts["heavy"] > 35 and counts["light"] > 0, "one greeting per docking, weighted: " + str(counts))


func _neighbour(c: Campaign) -> String:
	for o in c.neighbours(c.current):
		if c.node(o)["type"] != "gate":
			return o
	return ""


func test_reveal_with_a_node_type_shows_the_nearest_unrevealed_node_of_that_type() -> void:
	var c := _camp()
	for seed_value in range(1, 60):  # a map with at least two pirate nodes out of sight
		c = _camp([], seed_value)
		if c.drift.nodes.filter(func(n): return n["type"] == "pirate" and not c.is_known(n["id"])).size() >= 2:
			break
	var ship := _ship()
	var here: Vector2 = c.node(c.current)["pos"]
	var want := ""
	var want_d := INF
	for n in c.drift.nodes:
		if n["type"] == "pirate" and not c.is_known(n["id"]):
			var d: float = here.distance_to(n["pos"])
			if d < want_d:
				want = n["id"]
				want_d = d
	check(want != "", "there is a pirate node out of sight")
	var r := _fx({"reveal": "pirate"}, c, ship)
	check(c.is_known(want) and c.revealed.has(want), "the nearest unknown pirate node is shown: " + want)
	check(r["lines"].size() == 1 and r["lines"][0].begins_with("On the map:"), "said: " + str(r["lines"]))
	var second := ""
	for id in c.revealed:
		if id != want:
			second = id
	eq(second, "", "only one")
	_fx({"reveal": "pirate"}, c, ship)
	eq(c.revealed.size(), 2, "the next call shows the next one")
	for i in 40:
		_fx({"reveal": "pirate"}, c, ship)
	var left := 0
	for n in c.drift.nodes:
		if n["type"] == "pirate" and not c.is_known(n["id"]):
			left += 1
	eq(left, 0, "until none is left")
	eq(_fx({"reveal": "pirate"}, c, ship)["lines"].size(), 0, "then it does nothing")
	check(not _events([_ev("r", "empty", {}, {"reveal": "wreck_field"})]).validate().size() > 0, "a node type is a valid reveal for the validator")


func test_a_log_found_again_is_shown_again_but_kept_once() -> void:
	var c := _camp()
	var ship := _ship()
	var id: String = c.events.logs.keys()[0]
	var first := _fx({"log": id}, c, ship)
	var again := _fx({"log": id}, c, ship)
	eq(again["logs"].size(), 1, "the log is shown again")
	check(first["lines"][0].begins_with("Log found: ") and again["lines"][0].begins_with("Log read again: "), "and the line says so")
	eq(c.logs_found.keys(), [id], "but it is in the campaign's list once")
