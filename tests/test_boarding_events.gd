extends "res://tests/base_test.gd"
## Boarding, stage B3, the writing (data/packs/boarding_1): the events people and places aboard another vessel say. Every role and every kind of mark has something to
## say, every event has a way out, the story spine can be carried by them, and every outcome can be run through the session.

const Site = preload("res://scripts/board/site.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const People = preload("res://scripts/board/people.gd")
const Themes = preload("res://scripts/board/themes.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Events = preload("res://scripts/space/events.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Content = preload("res://scripts/data/content.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const RECRUITERS := ["bnpc_survivor_pulled_through", "bnpc_trader_lost_partner", "bnpc_captive_cut_free"]
## The events that carry the story spine, and the flag each sets.
const SPINE := {"bnpc_survivor_lantern_chalk": "haven_2", "bsite_relay_terminal": "haven_3", "bnpc_trader_radio": "haven_4", "bsite_room_eleven_chairs": "hollow_1",
	"bnpc_touched_roll_call": "hollow_2", "bnpc_hermit_ledger": "doors_known"}


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	s.crew.append(CrewMember.new("Rook", Vector2(10, 10), "human"))
	s.inventory.add("hand_ammo", 40 - s.inventory.count("hand_ammo"))
	s.inventory.add("credits", 500)
	s.inventory.add("scrap", 100)
	s.inventory.add("polymer", 20)
	return s


## The events of the pack, by id.
func _pack() -> Dictionary:
	var c := Campaign.new(1)
	var out := {}
	for id in c.events.order:
		if str(c.events.files[id]).contains("/packs/boarding_1/"):
			out[id] = c.events.events[id]
	return out


## The role an event is for: the one it asks for ("" for a discovery).
func _role_of(ev: Dictionary) -> String:
	return str(ev.get("requires", {}).get("role", ""))


func _texts(v) -> Array:
	var out := []
	if v is String:
		out.append(v)
	elif v is Array:
		for x in v:
			out.append_array(_texts(x))
	elif v is Dictionary:
		for k in v:
			if k != "requires" and k != "effects" and k != "id":
				out.append_array(_texts(v[k]))
	return out


func test_the_pack_has_the_events_it_promises() -> void:
	var pack := _pack()
	var npc := pack.values().filter(func(e): return e["type"] == "boarding_npc")
	var site := pack.values().filter(func(e): return e["type"] == "boarding_site")
	eq(npc.size(), 31, "31 events of what the people say (28 and three of the station guard)")
	eq(site.size(), 18, "18 discoveries")
	eq(pack.size(), 49, "and nothing else")
	for role in People.role_ids():
		if role == "recruiter":
			continue  # (the capital's recruiter: its events are in the homelands_1 pack)
		var mine := npc.filter(func(e): return _role_of(e) == role)
		check(mine.size() >= 3, "%s has at least three events (%d)" % [role, mine.size()])
	for kind in ["terminal", "body", "room"]:
		check(site.filter(func(e): return e["requires"].get("mark") == kind).size() >= 2, "%s marks have at least two events" % kind)


func test_every_role_has_something_to_say_in_every_kind_of_site_and_theme() -> void:
	var c := Campaign.new(5)
	var ship := _ship()
	var themes: Array = [""] + Themes.ids()
	for kind in People.cfg()["kinds"]:
		for role in People.cfg()["kinds"][kind]["roles"]:
			for theme in themes:
				for stage in [1, 4, 8]:
					c.stage = stage
					var node := {"type": "boarding_npc", "site": kind, "theme": theme, "role": role}
					c.crew_offers = 0
					check(not c.events.pick(c, node, ship).is_empty(), "a %s in a %s (%s, stage %d) has an event" % [role, kind, theme, stage])
	for kind in Site.kinds():
		for mark in ["terminal", "body", "room"]:
			for theme in themes:
				for stage in [1, 4, 8]:
					c.stage = stage
					check(not c.events.pick(c, {"type": "boarding_site", "site": kind, "theme": theme, "mark": mark}, ship).is_empty(), "a %s mark in a %s (%s, stage %d) has an event" % [mark, kind, theme, stage])


func test_every_event_has_a_way_out_a_voice_and_no_stray_braces() -> void:
	for id in _pack():
		var ev: Dictionary = _pack()[id]
		var free := false
		for ch in ev["choices"]:
			var spent := false
			for o in ch["outcomes"]:
				spent = spent or not o.get("effects", {}).is_empty()
			if not ch.has("requires") and not spent and not ch.get("pay", false):
				free = true
		check(free, "%s: a choice that asks nothing and does nothing" % id)
		for t in _texts(ev):
			var rest := str(t).replace("{name}", "")
			check(not rest.contains("{") and not rest.contains("}"), "%s: only {name} is filled in (%s)" % [id, str(t).left(40)])
			check(ev["type"] == "boarding_npc" or not str(t).contains("{name}"), "%s: a place has no one to name" % id)
		var crew_text := false
		for t in _texts(ev):
			crew_text = crew_text or str(t).to_lower().contains("your crew")
		if crew_text:
			var gated: bool = ev.get("requires", {}).has("crew_min") or ev["choices"].any(func(ch): return ch.get("requires", {}).has("crew_min"))
			check(gated, "%s: says 'your crew' without a crew_min that guarantees one" % id)
		check(ev["type"] == "boarding_site" or str(ev["text"]).contains("{name}"), "%s names the person" % id)


func test_each_role_has_a_fallback_and_it_asks_for_nothing() -> void:
	var fallbacks := _pack().values().filter(func(e): return bool(e.get("fallback", false)))
	eq(fallbacks.size(), 7, "one for each of the seven roles")
	var roles := {}
	for e in fallbacks:
		eq(e["requires"].keys(), ["role"], "%s asks for its role and nothing else" % e["id"])
		roles[e["requires"]["role"]] = true
		check(e["type"] == "boarding_npc", "")
	eq(roles.keys().size(), 7, "and every role has its own")
	for e in _pack().values():
		check(e["type"] != "boarding_npc" or People.has_role(_role_of(e)), "%s is for a role" % e["id"])


func test_only_three_events_recruit_and_they_count_as_the_regions_offer() -> void:
	var c := Campaign.new(2)
	var got := []
	for id in _pack():
		if c.events.offers_crew(id, c):
			got.append(id)
		var joins := false
		for ch in _pack()[id]["choices"]:
			for o in ch["outcomes"]:
				joins = joins or o.get("effects", {}).has("npc_join") or o.get("effects", {}).has("recruit")
		eq(joins, RECRUITERS.has(id), "%s: recruits only if it is one of the three" % id)
	got.sort()
	var want := RECRUITERS.duplicate()
	want.sort()
	eq(got, want, "and each counts toward the region's one free offer")


func test_the_story_spine_can_be_carried_by_boarding_events() -> void:
	var c := Campaign.new(4)
	var ship := _ship()
	var read := {}  # the flags that story events ask for
	for id in c.events.order:
		var path := str(c.events.files[id])
		if path.contains("/packs/story_1/") or path.contains("/packs/endings_1/"):
			var ev: Dictionary = c.events.events[id]
			var reqs := [ev.get("requires", {})]
			for ch in ev.get("choices", []):
				reqs.append(ch.get("requires", {}))
			for req in reqs:
				for f in Events._list(req.get("flag")) + Events._list(req.get("not_flag")):
					read[str(f)] = true
	eq(SPINE.size(), 6, "six events carry the spine")
	var pack := _pack()
	var set_by_pack := {}
	for id in pack:
		for ch in pack[id]["choices"]:
			for o in ch["outcomes"]:
				for f in Events._list(o.get("effects", {}).get("flag")):
					set_by_pack[str(f)] = id
	for id in SPINE:
		var flag: String = SPINE[id]
		check(read.has(flag), "the story reads %s" % flag)
		eq(set_by_pack.get(flag, ""), id, "%s sets %s" % [id, flag])
		var ev: Dictionary = pack[id]
		var logs := []
		for ch in ev["choices"]:
			for o in ch["outcomes"]:
				logs.append_array(Events._list(o.get("effects", {}).get("log")))
		check(not logs.is_empty() and logs.all(func(l): return c.events.logs.has(l)), "%s hands out logs that exist" % id)
		# it is eligible once what comes before it is set, and not before
		var req: Dictionary = ev["requires"]
		var node := {"type": ev["type"], "site": "station", "theme": "concord" if req.get("theme") == "concord" else "", "role": req.get("role", "hermit" if id == "bnpc_hermit_ledger" else ("survivor" if id.contains("survivor") else ("trader" if id.contains("trader") else "touched_talker"))),
			"mark": req.get("mark", "")}
		c.flags.clear()
		c.stage = int(req.get("stage_min", 1))
		for f in Events._list(req.get("flag")):
			c.flags[str(f)] = true
		check(c.events.eligible(ev, c, node, ship), "%s is eligible once its flags are set (stage %d)" % [id, c.stage])
		if req.has("flag"):
			c.flags.clear()
			check(not c.events.eligible(ev, c, node, ship), "%s waits for %s" % [id, str(req["flag"])])
		c.flags.clear()
		for f in Events._list(req.get("flag")):
			c.flags[str(f)] = true
		c.flags[flag] = true
		check(not c.events.eligible(ev, c, node, ship), "%s is done once %s is set" % [id, flag])


func test_every_outcome_runs_through_the_session() -> void:
	var pack := _pack()
	var ran := 0
	for id in pack:
		var ev: Dictionary = pack[id]
		var is_npc: bool = ev["type"] == "boarding_npc"
		var role := _role_of(ev) if is_npc else ""
		var kind := "nest" if role == "captive" else "station"
		for ci in ev["choices"].size():
			for oi in ev["choices"][ci]["outcomes"].size():
				var c := Campaign.new(7)
				var ship := _ship()
				var s = Boarding.start(null, null, "z%d" % ran, {"kind": kind}, ship)
				s.campaign = c
				var n := {}
				if is_npc:
					var spots: Array = s.site.free_anchors(s.site.airlock["room"])
					var at: Vector2 = Vector2(spots[spots.size() - 1]) + Vector2.ONE
					n = s.people.add(role, at, s.site.airlock["room"], "human", "Okafor")
				var node: Dictionary = s.people.node_of(n) if is_npc else {"type": "boarding_site", "site": kind, "theme": "", "mark": "terminal"}
				var effects: Dictionary = ev["choices"][ci]["outcomes"][oi].get("effects", {})
				var r: Dictionary = c.events.apply(effects, c, ship, node)
				var out: Dictionary = s.finish_talk(n["id"] if is_npc else -1, r["npc"], not effects.is_empty())
				check(r["lines"] is Array and out["lines"] is Array, "%s %d.%d runs" % [id, ci, oi])
				for i in 20:
					s.tick(0.1)  # a foe that came, a person who walks off
				ran += 1
	check(ran > 80, "every outcome of every event was run (%d)" % ran)


func test_the_new_logs_exist_and_are_in_the_voice() -> void:
	var c := Campaign.new(1)
	for id in ["log_board_last_message", "log_board_note_in_pocket", "log_board_wake_menu", "log_board_air_budget", "log_board_glass_prayer"]:
		check(c.events.logs.has(id), "%s is a log" % id)
		var l: Dictionary = c.events.logs[id]
		check(str(l["title"]) != "" and str(l["text"]).length() > 100 and ["clans", "concord", "lumen"].has(str(l["faction"])), "%s has a title, a faction and a text" % id)
		var given := false
		for eid in _pack():
			given = given or JSON.stringify(_pack()[eid]).contains(id)
		check(given, "%s is handed out by an event" % id)


func test_a_person_hears_only_the_events_of_their_role() -> void:
	var c := Campaign.new(9)
	var ship := _ship()
	var pack := _pack()
	for kind in People.cfg()["kinds"]:
		for role in People.cfg()["kinds"][kind]["roles"]:
			for theme in [""] + Themes.ids():
				for i in 12:
					c.stage = 1 + i % 8
					c.crew_offers = 0
					var ev: Dictionary = c.events.pick(c, {"type": "boarding_npc", "site": kind, "theme": theme, "role": role}, ship)
					check(not pack.has(ev.get("id", "")) or _role_of(ev) == role, "%s in a %s is not told %s's page (%s)" % [role, kind, _role_of(ev), ev.get("id", "")])
