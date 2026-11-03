extends "res://tests/base_test.gd"
## Boarding, stage B3 (docs/BOARDING.md, scripts/board/people.gd, themes.gd): the people aboard (how many, who, where), talking to them through the event machinery
## and what the effects npc_trade, npc_reveal, npc_join, npc_hostile, npc_follow, npc_leave and site_fight do, the site themes by region, the discoveries
## (marks), and the rounds recipe.

const Site = preload("res://scripts/board/site.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const People = preload("res://scripts/board/people.gd")
const Themes = preload("res://scripts/board/themes.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Party = preload("res://scripts/board/party.gd")
const Loot = preload("res://scripts/board/loot.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Events = preload("res://scripts/space/events.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Content = preload("res://scripts/data/content.gd")
const Crafting = preload("res://scripts/craft/crafting.gd")
const Inventory = preload("res://scripts/ship/inventory.gd")
const Audio = preload("res://scripts/audio/audio.gd")
const BoardView = preload("res://scripts/board/board_view.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
const SectorView = preload("res://scripts/view/sector_view.gd")
const CombatView = preload("res://scripts/combat/combat_view.gd")
const Mood = preload("res://scripts/audio/mood.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


func _ship(credits := 500) -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	s.crew.append(CrewMember.new("Rook", Vector2(10, 10), "human"))
	s.inventory.add("hand_ammo", 40)
	s.inventory.add("credits", credits - s.inventory.count("credits"))
	return s


## A visit to a site of `kind` made from `seed_value` (with `theme`) and no sector or campaign behind it.
func _visit(kind := "station", seed_value := 31, theme := "", ship = null):
	var sh = ship if ship != null else _ship()
	var s = Boarding.start(null, null, "p%d" % seed_value, {"kind": kind}, sh)
	s.site = Site.make(seed_value, kind, {"faction": "clans", "theme": theme})
	s.soldier.pos = s.site.airlock["spawn"]
	s.foes = Foes.new(s)
	s.foes.spawn_site({})
	s.people = People.new(s)
	s.people.spawn_site({})
	return s


## A person of `role` standing in the airlock's room, a few cells from the soldier.
func _person(s, role := "survivor", species := "human", name := "Pell") -> Dictionary:
	var spots: Array = s.site.free_anchors(s.site.airlock["room"])
	spots.sort_custom(func(a, b): return (Vector2(a) + Vector2.ONE).distance_to(s.soldier.pos) < (Vector2(b) + Vector2.ONE).distance_to(s.soldier.pos))
	var at := Vector2.ZERO
	for a in spots:
		var p := Vector2(a) + Vector2.ONE
		if p.distance_to(s.soldier.pos) >= 2.6:
			at = p
			break
	return s.people.add(role, at, s.site.airlock["room"], species, name)


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


func _ev(id: String, type: String, requires: Dictionary = {}, effects: Dictionary = {}, extra: Dictionary = {}) -> Dictionary:
	var e := {"id": id, "type": type, "weight": 10, "once": false, "requires": requires, "text": "Text of " + id,
		"choices": [{"text": "Go", "outcomes": [{"weight": 100, "text": "Done", "effects": effects}]}, {"text": "Leave.", "outcomes": [{"weight": 1, "text": "", "effects": {}}]}]}
	e.merge(extra, true)
	return e


## Talk to person `n` of session `s` and take choice `index` of what they say: returns [the outcome, what finish_talk made of it].
func _say(s, c: Campaign, n: Dictionary, index := 0) -> Array:
	s.campaign = c
	var t: Dictionary = s.talk(n["id"])
	var r: Dictionary = c.events.choose(t["event"], index, c, s.ship, t["node"])
	return [r, s.finish_talk(n["id"], r["npc"], r["acted"])]


# --- how many, who, where -----------------------------------------------------------------------------------------

func test_people_are_placed_at_about_the_target_rates() -> void:
	var rate := {}
	for kind in ["station", "derelict", "nest", "wreck"]:
		var some := 0
		var total := 80
		for i in total:
			var b = Boarding.start(null, null, "r%d" % i, {"kind": kind}, null)
			if not b.people.list.is_empty():
				some += 1
			for n in b.people.list:
				check(People.cfg()["kinds"][kind]["roles"].has(n["role"]), "%s: a %s is a person of that kind of site" % [kind, n["role"]])
		rate[kind] = float(some) / float(total)
	check(rate["station"] >= 0.35 and rate["station"] <= 0.65, "about 1 in 2 stations holds someone (%.2f)" % rate["station"])
	check(rate["derelict"] >= 0.25 and rate["derelict"] <= 0.6, "about 2 in 5 derelicts does (%.2f)" % rate["derelict"])
	check(rate["nest"] > 0.0 and rate["nest"] <= 0.5, "a nest holds a captive now and then (%.2f)" % rate["nest"])
	eq(rate["wreck"], 0.0, "a wreck holds only the survivors who fight")


func test_a_nest_holds_nobody_but_a_captive() -> void:
	var seen := 0
	for i in 60:
		var b = Boarding.start(null, null, "n%d" % i, {"kind": "nest"}, null)
		for n in b.people.list:
			seen += 1
			eq(n["role"], "captive", "the only person in a nest is a captive")
	check(seen > 0, "some nest had one (%d)" % seen)


func test_people_stand_in_rooms_apart_from_the_airlock_and_each_other() -> void:
	var seen := 0
	for i in 40:
		var b = Boarding.start(null, null, "q%d" % i, {"kind": "station"}, null)
		var names := {}
		for n in b.people.list:
			seen += 1
			check(n["m"].pos.distance_to(b.site.airlock["spawn"]) >= float(People.cfg()["min_from_airlock"]) - 0.01, "%s stands away from the airlock" % n["name"])
			check(n["room"] >= 0 and n["room"] != b.site.airlock["room"] and b.site.room_at(n["m"].pos) == n["room"], "in a room that is not the airlock's")
			check(not names.has(n["name"]), "no two people share a name")
			names[n["name"]] = true
			check(CrewMember.species_table()["species"].has(n["species"]), "%s is a species of the game (%s)" % [n["name"], n["species"]])
			eq(n["state"], "here", "standing")
	check(seen >= 8, "enough people to test with (%d)" % seen)


func test_the_same_seed_places_the_same_people() -> void:
	for i in 12:
		var a = Boarding.start(null, null, "s%d" % i, {"kind": "station"}, null)
		var b = Boarding.start(null, null, "s%d" % i, {"kind": "station"}, null)
		eq(a.people.list.map(func(n): return [n["role"], n["name"], n["species"], n["m"].pos]), b.people.list.map(func(n): return [n["role"], n["name"], n["species"], n["m"].pos]), "visit %d" % i)


func test_the_hollow_makes_the_hollow_touched_likelier() -> void:
	var plain := 0
	var held := 0
	for i in 60:
		var s = _visit("station", 100 + i)
		var h = _visit("station", 100 + i)
		h.people.spawn_site({"hollow": true})
		plain += s.people.list.filter(func(n): return n["role"] == "touched_talker").size()
		held += h.people.list.filter(func(n): return n["role"] == "touched_talker").size()
	check(held > plain, "a place the Hollow holds has more of the Hollow-touched who talk (%d against %d)" % [held, plain])


# --- talking ------------------------------------------------------------------------------------------------------------

func test_a_talk_picks_an_event_by_role_site_and_theme_and_keeps_it() -> void:
	var c := _camp([_ev("for_survivors", "boarding_npc", {"role": "survivor"}), _ev("for_traders", "boarding_npc", {"role": ["trader", "hermit"]}),
		_ev("for_nests", "boarding_npc", {"site": "nest"}), _ev("for_lumen", "boarding_npc", {"theme": "lumen"}), _ev("a_node_event", "wreck_field")])
	var s = _visit()
	s.campaign = c
	var a := _person(s, "survivor")
	var t: Dictionary = s.talk(a["id"])
	eq(t["event"]["id"], "for_survivors", "a survivor in a station hears the survivors' event")
	eq(t["node"]["role"], "survivor", "the node says who")
	eq(t["node"]["npc"]["name"], "Pell", "and their name")
	for k in 6:
		eq(s.talk(a["id"])["event"]["id"], "for_survivors", "the same page every time")
	var b := _person(s, "trader", "human", "Mags")
	eq(s.talk(b["id"])["event"]["id"], "for_traders", "a trader hears another")
	var n = _visit("nest", 77)
	n.campaign = c
	var cap := _person(n, "captive", "human", "Ines")
	eq(n.talk(cap["id"])["event"]["id"], "for_nests", "a captive in a nest hears the nest's event")
	var l = _visit("station", 31, "lumen")
	l.campaign = c
	var h := _person(l, "hermit", "human", "Motet")
	check(["for_traders", "for_lumen"].has(l.talk(h["id"])["event"]["id"]), "a theme's event is in the pool of its sites")
	var none := _person(s, "captive", "human", "Rue")
	eq(s.talk(none["id"])["event"], {}, "no event for a role and a site that none is written for: nothing to say")


func test_a_node_event_is_never_rolled_for_a_person_and_a_person_event_never_at_a_node() -> void:
	var c := _camp([_ev("boards", "boarding_npc"), _ev("looks", "boarding_site"), _ev("flies", "wreck_field")])
	var node := {"id": "n01", "type": "wreck_field", "place": ""}
	for i in 12:
		eq(c.events.pick(c, node, _ship())["id"], "flies", "a node rolls its own")
	eq(c.events.pick(c, {"type": "boarding_npc", "site": "station", "role": "survivor", "theme": ""}, _ship())["id"], "boards", "a person rolls theirs")
	eq(c.events.pick(c, {"type": "boarding_site", "site": "station", "mark": "body", "theme": ""}, _ship())["id"], "looks", "a spot rolls its own")


func test_an_acted_talk_spends_the_person_and_a_walk_away_does_not() -> void:
	var c := _camp([_ev("gives", "boarding_npc", {}, {"items": {"scrap": 3}})])
	var s = _visit()
	var n := _person(s)
	var before: int = s.ship.inventory.count("scrap")
	var out := _say(s, c, n, 1)  # "Leave."
	check(not out[0]["acted"], "leaving does nothing")
	check(not n["done"], "they are not spent by it")
	out = _say(s, c, n, 0)
	check(out[0]["acted"], "taking the gift does something")
	eq(s.ship.inventory.count("scrap"), before + 3, "and the scrap comes")
	check(n["done"], "they have said what there is to say")
	check(s.talk(n["id"]).has("say") and not s.talk(n["id"]).has("event"), "the next E gets a word, not the page again")


# --- the effects ---------------------------------------------------------------------------------------------------------

func test_npc_trade_rolls_three_things_and_buying_pays() -> void:
	var c := _camp([_ev("sells", "boarding_npc", {}, {"npc_trade": true})])
	var s = _visit()
	var n := _person(s, "trader")
	var out := _say(s, c, n)
	eq(out[0]["npc"], [{"op": "trade"}], "the outcome asks for goods")
	eq(out[1]["shop"], n["id"], "the goods go on the list")
	eq(n["shop"].size(), 3, "three things")
	var ids: Array = n["shop"].map(func(x): return x["item"])
	for row in n["shop"]:
		check(row["item"] != "credits" and int(row["n"]) >= 1 and int(row["price"]) >= 1, "%s has a count and a price" % row["item"])
		eq(ids.count(row["item"]), 1, "%s is on the list once" % row["item"])
	check(not n["done"], "a trader is not spent by trading")
	check(s.talk(n["id"]).get("shop", false), "E again opens the goods, not the page")
	var row0: Dictionary = n["shop"][0]
	var credits: int = s.ship.inventory.count("credits")
	var held: int = s.ship.inventory.count(str(row0["item"]))
	var r: Dictionary = s.buy(n["id"], 0)
	check(r["ok"], "bought")
	eq(s.ship.inventory.count("credits"), credits - int(row0["price"]), "the price is paid")
	eq(s.ship.inventory.count(str(row0["item"])), held + int(row0["n"]), "and the stack is in the hold")
	check(not s.buy(n["id"], 0)["ok"], "a thing sold is sold")
	s.ship.inventory.add("credits", -s.ship.inventory.count("credits"))
	var broke: Dictionary = s.buy(n["id"], 1)
	check(not broke["ok"] and broke["text"] == People.cfg()["broke"], "no credits, no sale")
	var again = _visit()
	again.campaign = c
	var n2 := _person(again, "trader")
	again.finish_talk(n2["id"], [{"op": "trade"}], true)
	eq(n2["shop"].map(func(x): return [x["item"], x["n"], x["price"]]), n["shop"].map(func(x): return [x["item"], x["n"], x["price"]]), "the same person sells the same things")


func test_the_goods_follow_the_tables_of_the_room() -> void:
	var s = _visit()
	var n := _person(s, "trader")
	var purpose := str(s.site.rooms[n["room"]]["purpose"])
	var table: Array = Loot.table_for(s.site, purpose).map(func(o): return str(o["item"]))
	for row in s.people.roll_shop(n):
		check(table.has(row["item"]), "%s is in the %s table" % [row["item"], purpose])


func test_npc_reveal_marks_a_container_or_a_locked_door() -> void:
	var s = _visit()
	for seed_value in range(31, 80):
		s = _visit("station", seed_value)
		if s.site.props.any(func(p): return p["slot"] == "blueprint") and s.site.doors.any(func(d): return d["lock"] == "hack" or d["lock"] == "card"):
			break
	var n := _person(s, "hermit")
	var bp: int = s.site.props.filter(func(p): return p["slot"] == "blueprint")[0]["id"]
	var out: Dictionary = s.finish_talk(n["id"], [{"op": "reveal", "what": "blueprint"}], true)
	check(s.people.revealed.has(bp), "the word marks the container with the blueprint")
	check(str(out["lines"][0]).begins_with("Marked: "), "and says so (%s)" % out["lines"][0])
	s.finish_talk(-1, [{"op": "reveal", "what": "container"}], true)
	eq(s.people.revealed.size(), 2, "a second word marks another")
	s.finish_talk(-1, [{"op": "reveal", "what": "locked"}], true)
	check(not s.people.revealed_doors.is_empty(), "a locked door can be marked")
	var door: int = s.people.revealed_doors.keys()[0]
	check(s.site.doors[door]["lock"] != "", "and it is one that is locked")
	var m: Dictionary = s.people.memory()
	check(m["revealed"].has(bp) and m["revealed_doors"].has(door), "the marks are remembered")


func test_npc_join_makes_the_person_crew_and_counts_as_the_regions_offer() -> void:
	var c := _camp([_ev("joins", "boarding_npc", {}, {"npc_join": true})])
	c.cfg["crew"]["species_event"] = 1.0
	c.cfg["crew"]["offers_per_region"] = 1
	var s = _visit()
	var n := _person(s, "survivor", "fenn", "Wren")
	var crew: int = s.ship.crew.size()
	var out := _say(s, c, n)
	eq(s.ship.crew.size(), crew + 1, "a crew member more")
	var mate = s.ship.crew[-1]
	eq([mate.name, mate.species], ["Wren", "fenn"], "it is the person, of their species")
	eq(out[0]["npc"], [{"op": "join", "ok": true}], "the outcome says so")
	check(out[0]["lines"].any(func(l): return str(l).contains("Wren")), "and the lines (%s)" % str(out[0]["lines"]))
	eq(n["state"], "joined", "they are not standing there any more")
	check(not s.people.here().has(n), "")
	check(c.events.offers_crew("joins", c), "an event that lets a person join counts as one that adds crew")
	var node := {"type": "boarding_npc", "site": "station", "role": "survivor", "theme": ""}
	c.crew_offers = 0
	eq(c.events.pick(c, node, s.ship)["id"], "joins", "the region's offer is made once")
	eq(c.crew_offers, 1, "and counted")
	eq(c.events.pick(c, node, s.ship), {}, "then the pool is closed to it")
	var shut := _camp([_ev("joins", "boarding_npc", {}, {"npc_join": true})])
	var calls := 0
	for i in 200:
		if not shut.events.pick(shut, node, s.ship).is_empty():
			calls += 1
			shut.crew_offers = 0
	check(calls < 40, "a person who joins is rare (the species gate): %d of 200" % calls)


func test_npc_hostile_turns_the_person_into_a_foe_that_hunts() -> void:
	var c := _camp([_ev("turns", "boarding_npc", {}, {"npc_hostile": true}), _ev("turns_pirate", "boarding_npc", {"role": "trader"}, {"npc_hostile": "pirate"})])
	var s = _visit()
	var n := _person(s, "survivor")
	var foes: int = s.foes.list.size()
	var out := _say(s, c, n)
	eq(n["state"], "hostile", "they turn")
	eq(s.foes.list.size(), foes + 1, "a foe stands where they stood")
	var f: Dictionary = s.foes.find(n["foe"])
	eq(f["kind"], "scavenger", "of their role's kind")
	eq(f["mode"], "hunt", "already after him")
	eq(f["m"].pos, n["m"].pos, "at their feet")
	check(s.foes.live().has(f), "a foe like any other")
	check(not s.people.here().has(n), "and no longer a person to talk to")
	check(str(out[1]["lines"][0]).contains("turns on you"), "the lines say so")
	var t = _visit()
	var tr := _person(t, "trader")
	t.campaign = c
	var h = c.events.get_event("turns_pirate")
	var r = c.events.choose(h, 0, c, t.ship, t.talk(tr["id"])["node"])
	t.finish_talk(tr["id"], r["npc"], true)
	eq(t.foes.find(tr["foe"])["kind"], "pirate", "a named kind is the kind they become")


func test_npc_follow_makes_a_temporary_follower_who_stays_when_he_leaves() -> void:
	var c := _camp([_ev("follows", "boarding_npc", {}, {"npc_follow": true})])
	var s = _visit()
	var n := _person(s, "survivor")
	var crew: int = s.ship.crew.size()
	_say(s, c, n)
	eq(n["state"], "follow", "they follow")
	eq(s.party.size(), 1, "in the party")
	check(bool(s.party[0]["temp"]) and s.party[0]["src"] == null, "a follower with no crew member behind them")
	eq(s.party[0]["m"].name, "Pell", "it is them")
	for i in 40:
		s.tick(0.25)
	check(s.party[0]["m"].pos.distance_to(s.soldier.pos) < 9.0, "they keep up with him")
	s.party[0]["m"].hp = 0.0
	eq(s.downed_party(), [], "one who falls is no loss to the ship")
	var out: Dictionary = s.leave()
	check(out["said"].any(func(l): return str(l).contains("Pell stays behind")), "they stay when he goes")
	eq(s.ship.crew.size(), crew, "nobody is lost or gained")
	eq(out["lost"], [], "")
	eq(s.people.memory()["npcs"][str(n["id"])]["st"], "gone", "and a later visit does not find them")


func test_npc_leave_makes_the_person_walk_away_and_go() -> void:
	var c := _camp([_ev("goes", "boarding_npc", {}, {"npc_leave": true})])
	var s = _visit()
	var n := _person(s, "hermit")
	var from: Vector2 = n["m"].pos
	_say(s, c, n)
	eq(n["state"], "leaving", "they walk off")
	var moved := false
	var steps := 0
	while n["state"] != "gone" and steps < 400:
		s.people.tick(0.1)
		steps += 1
		moved = moved or n["moved"]
	check(moved, "they walked")
	eq(n["state"], "gone", "and they are gone in the end")
	check(float(steps) * 0.1 <= float(People.cfg()["leave_s"]) + 0.2, "within the time allowed (%.1f s)" % (steps * 0.1))
	check(n["m"].pos != from, "from where they stood")
	check(not s.people.here().has(n), "nobody there to talk to")


func test_site_fight_sends_foes_out_of_the_dark() -> void:
	var s = _visit()
	var foes: int = s.foes.live().size()
	var out: Dictionary = s.finish_talk(-1, [{"op": "fight", "kind": "pirate", "n": 2}], true)
	var came: Array = s.foes.live().filter(func(f): return f["kind"] == "pirate" and not f["spawned"])
	eq(came.size(), 2, "two pirates came")
	for f in came:
		eq(f["mode"], "hunt", "hunting")
		var d: float = f["m"].pos.distance_to(s.soldier.pos)
		check(d >= 4.9 and d <= 11.1, "from out of sight, %.1f cells away" % d)
	eq(out["lines"], ["Someone is coming."], "and he is told")
	eq(s.foes.live().size(), foes + 2, "")


func test_a_person_who_is_shot_turns_on_the_shooter_but_a_captive_is_not_a_target() -> void:
	var s = _visit()
	var n := _person(s, "trader")
	var cap := _person(s, "captive", "human", "Ines")
	check(s.people.bodies().any(func(b): return b["ref"] == n) and not s.people.bodies().any(func(b): return b["ref"] == cap), "a captive cannot be hit")
	s.people.shot(n, 12.0)
	eq(n["state"], "hostile", "a person who is shot fights back")
	var f: Dictionary = s.foes.find(n["foe"])
	eq(f["m"].hp, float(Foes.def("scavenger")["hp"]) - 12.0, "with the damage on them")
	check(f["mode"] == "hunt", "")
	s.people.shot(cap, 10.0)
	check(cap["state"] == "hostile", "(a captive does turn when struck, if it ever comes to it)")
	# fire along a clear line: the first body is the person
	var s2 = _visit("station", 31)
	var p := _person(s2, "survivor")
	var dir: float = (p["m"].pos - s2.soldier.pos).angle()
	if s2.site.clear_line(s2.soldier.pos, p["m"].pos):
		s2.fire(dir)
		check(p["state"] == "hostile" or s2.take_events().any(func(e): return e["type"] == "shot"), "a shot at someone standing there")


func test_a_dead_hostile_person_stays_dead_on_a_revisit_and_a_live_one_comes_back() -> void:
	var c := _sector_camp()
	var sector = c.current_sector()
	var ship := _ship()
	var poi := ""
	var b = null
	for i in 60:
		poi = "m%d" % i
		b = Boarding.start(c, sector, poi, {"kind": "station"}, ship)
		if b.people.list.size() >= 1:
			break
	check(b.people.list.size() >= 1, "a station with someone")
	var n: Dictionary = b.people.list[0]
	b.people.turn(n)
	var f: Dictionary = b.foes.find(n["foe"])
	var out: Dictionary = b.leave()
	var b2 = Boarding.start(c, sector, poi, {"kind": "station"}, ship)
	eq(b2.people.list[0]["state"], "hostile", "someone who turned on him is still against him on the next visit")
	b2.foes.hurt(b2.foes.find(b2.people.list[0]["foe"]), 9999.0, Vector2.ZERO)
	b2.leave()
	var b3 = Boarding.start(c, sector, poi, {"kind": "station"}, ship)
	check(b3.people.list[0]["state"] in ["gone"], "once beaten they do not come back (%s)" % b3.people.list[0]["state"])
	check(out["name"] != "" and not f.is_empty(), "")


func _sector_camp() -> Campaign:
	var cfg: Dictionary = Campaign.config().duplicate(true)
	cfg["instant_jump"] = false
	return Campaign.new(3, cfg)


func test_what_was_said_to_a_person_is_remembered_through_a_save() -> void:
	var c := _sector_camp()
	var sector = c.current_sector()
	var ship := _ship()
	var poi := ""
	var b = null
	for i in 80:
		poi = "k%d" % i
		b = Boarding.start(c, sector, poi, {"kind": "station"}, ship)
		if b.people.list.size() >= 1:
			break
	var n: Dictionary = b.people.list[0]
	var cam := _camp([_ev("sells", "boarding_npc", {}, {"npc_trade": true})])
	b.campaign = cam
	var t: Dictionary = b.talk(n["id"])
	var r: Dictionary = cam.events.choose(t["event"], 0, cam, ship, t["node"])
	b.finish_talk(n["id"], r["npc"], r["acted"])
	var ev_id: String = n["ev"]
	var shop: Array = n["shop"].duplicate(true)
	b.leave()
	var saved = JSON.parse_string(JSON.stringify(sector.to_save()))  # through the file
	var s2 = _sector_camp().current_sector()
	s2.boarded = {}
	eq(s2.load_save(saved), "", "the sector loads")
	var b2 = Boarding.start(c, s2, poi, {"kind": "station"}, ship)
	var n2: Dictionary = b2.people.list[0]
	eq([n2["name"], n2["role"], n2["species"]], [n["name"], n["role"], n["species"]], "the same person")
	eq(n2["ev"], ev_id, "who was given the same page")
	eq(n2["shop"], shop, "and has the same goods out")
	check(n2["shop_open"], "")
	eq(b2.site.theme, b.site.theme, "the place is dressed the way it was")


# --- validation ----------------------------------------------------------------------------------------------------------

func test_the_new_keys_validate_and_the_bad_ones_are_named() -> void:
	var good := _events([_ev("ok1", "boarding_npc", {"role": ["survivor", "hermit"], "site": "station", "theme": "lumen"}, {"npc_trade": true, "npc_reveal": "blueprint", "flag": ["x"]}),
		_ev("ok2", "boarding_site", {"mark": "terminal", "site": ["station", "derelict"]}, {"site_fight": {"kind": "pirate", "n": 2}, "npc_reveal": true}),
		_ev("ok3", "boarding_npc", {}, {"npc_hostile": "hollow_touched", "npc_follow": true, "npc_leave": true, "npc_join": true})])
	var errs := good.validate()
	eq(errs, [], "a sound set of boarding events")
	var bad := _events([_ev("b1", "boarding_npc", {"role": "wizard"}), _ev("b2", "boarding_npc", {"site": "moon"}), _ev("b3", "boarding_npc", {"theme": "pink"}),
		_ev("b4", "boarding_site", {"mark": "ceiling"}), _ev("b5", "boarding_npc", {}, {"fight": "tier"}), _ev("b6", "boarding_npc", {}, {"board": {"kind": "station"}}),
		_ev("b7", "wreck_field", {}, {"npc_trade": true}), _ev("b8", "boarding_npc", {}, {"npc_hostile": "sentry"}), _ev("b9", "boarding_npc", {}, {"npc_reveal": "the moon"}),
		_ev("b10", "boarding_site", {}, {"site_fight": {"kind": "pirate", "n": 9}}), _ev("b11", "boarding_npc", {}, {"npc_trade": "yes"})])
	var text := "\n".join(bad.validate())
	for id in ["b1", "b2", "b3", "b4", "b5", "b6", "b7", "b8", "b9", "b10", "b11"]:
		check(text.contains("event '%s'" % id), "%s is reported (%s)" % [id, text])


func test_personalize_fills_the_name_in_every_text() -> void:
	var ev := _ev("p", "boarding_npc", {}, {}, {"text": "{name} looks up.", "choices": [{"text": "Ask {name}.", "outcomes": [{"weight": 1, "text": "{name} says no.", "effects": {}}]}]})
	var out := Events.personalize(ev, "Okafor")
	eq(out["text"], "Okafor looks up.", "the page")
	eq(out["choices"][0]["text"], "Ask Okafor.", "the choice")
	eq(out["choices"][0]["outcomes"][0]["text"], "Okafor says no.", "the outcome")
	eq(ev["text"], "{name} looks up.", "and the event itself is left alone")


# --- themes -----------------------------------------------------------------------------------------------------------

func test_themes_resolve_by_region() -> void:
	var want := {"boneyard": "boneyard", "gauntling_scrapyards": "boneyard", "clan_space": "clans", "basalt_quarries": "clans", "kett_hives": "clans",
		"concord_space": "concord", "human_core": "concord", "lumen_space": "lumen", "emberkin_forges": "lumen", "gate_approaches": "hollow", "revenant_cairns": "hollow",
		"fenn_bazaar": "", "kite_slack": ""}
	var regions := {}
	for r in Content.list("regions"):
		regions[str(r["id"])] = r
	for id in want:
		check(regions.has(id), "region %s exists" % id)
		if regions.has(id):
			eq(Themes.for_region(regions[id]), want[id], "the theme of " + id)
	eq(Themes.for_region(regions["concord_space"], true), "hollow", "a place the Hollow holds is the Hollow's whatever the region")
	eq(Themes.ids(), ["boneyard", "clans", "concord", "hollow", "lumen"], "five themes")
	eq(Themes.def("nowhere"), {}, "an unknown theme is the plain site")


func test_a_visit_takes_the_theme_of_its_region_and_keeps_it() -> void:
	var c := _sector_camp()
	var sector = c.current_sector()
	var b = Boarding.start(c, sector, "t1", {"kind": "station"}, _ship())
	eq(b.site.theme, Themes.for_region(c.region_data, c.is_hollow(c.current)), "the region's theme")
	check(b.site.theme != "" or str(c.region_data.get("faction", "")) == "", "(a region of a faction has one)")
	b.leave()
	eq(sector.boarded["t1"]["theme"], b.site.theme, "it is in the memory")
	sector.boarded["t1"]["theme"] = "lumen"
	var b2 = Boarding.start(c, sector, "t1", {"kind": "station"}, _ship())
	eq(b2.site.theme, "lumen", "and a later visit is dressed the same, whatever the region says now")


func test_a_theme_names_and_dresses_its_sites_and_changes_no_layout() -> void:
	var extra := {"boneyard": "heap", "concord": "files", "lumen": "crystal", "clans": "cask"}
	for theme in Themes.ids():
		var tdef := Themes.def(theme)
		var props := {}
		for i in 14:
			for kind in ["station", "derelict", "nest"]:
				var plain = Site.make(500 + i, kind, {"faction": "clans"})
				var site = Site.make(500 + i, kind, {"faction": "clans", "theme": theme})
				check(site.ok and site.problems().is_empty(), "%s %s %d is whole" % [theme, kind, i])
				eq(site.theme, theme, "dressed")
				var pattern := RegEx.new()
				var names: Array = tdef["names"][kind]
				var hit := names.any(func(nm): return str(site.site_name) == str(nm) or (str(nm).contains("{n}") and site.site_name.begins_with(str(nm).split("{n}")[0])))
				check(hit, "%s: '%s' is a name from the theme's list" % [theme, site.site_name])
				eq(site.rooms.map(func(r): return [r["rect"], r["purpose"]]), plain.rooms.map(func(r): return [r["rect"], r["purpose"]]), "%s %d: the same rooms" % [theme, i])
				eq(site.doors.map(func(d): return d["cells"]), plain.doors.map(func(d): return d["cells"]), "the same doors")
				eq(site.airlock, plain.airlock, "the same airlock")
				for p in site.props:
					props[p["prop"]] = int(props.get(p["prop"], 0)) + 1
		if extra.has(theme):
			check(int(props.get(extra[theme], 0)) > 0, "%s sites have %s (%s)" % [theme, extra[theme], str(props)])
		for k in extra:
			if k != theme:
				check(int(props.get(extra[k], 0)) == 0, "%s sites have no %s" % [theme, extra[k]])


func test_a_theme_tilts_the_loot() -> void:
	var share := {}
	for theme in ["", "boneyard", "lumen", "clans", "concord"]:
		var scrap := 0
		var crystal := 0
		var credits := 0
		var all := 0
		for i in 10:
			var site = Site.make(900 + i, "station", {"faction": "clans", "theme": theme})
			for id in site.containers():
				var got: Dictionary = Loot.resolve(site, id, {"tier": 2})
				for item in got["items"]:
					all += int(got["items"][item])
					if item == "scrap":
						scrap += int(got["items"][item])
					elif item == "crystal":
						crystal += int(got["items"][item])
					elif item == "credits":
						credits += int(got["items"][item])
		share[theme] = {"scrap": float(scrap) / float(all), "crystal": float(crystal) / float(all), "credits": float(credits) / float(all)}
	check(share["boneyard"]["scrap"] > share[""]["scrap"] * 1.15, "a Boneyard site holds more scrap (%.2f against %.2f)" % [share["boneyard"]["scrap"], share[""]["scrap"]])
	check(share["lumen"]["crystal"] > share[""]["crystal"] * 1.5, "a Lumen shrine holds more crystal (%.3f against %.3f)" % [share["lumen"]["crystal"], share[""]["crystal"]])
	check(share["clans"]["credits"] > share[""]["credits"] or share["concord"]["credits"] > share[""]["credits"], "the Clans and the Concord hold more credits")


func test_a_theme_tilts_who_stands_guard() -> void:
	var count := {}
	for theme in ["", "boneyard", "concord", "lumen", "clans", "hollow"]:
		var kinds := {}
		var total := 0
		for i in 14:
			var s = _visit("station", 700 + i, theme)
			for f in s.foes.list:
				if f["spawned"] and f["kind"] != "crawler":
					kinds[f["kind"]] = int(kinds.get(f["kind"], 0)) + 1
					total += 1
		kinds["total"] = total
		count[theme] = kinds
	check(int(count["concord"].get("sentry", 0)) > int(count["boneyard"].get("sentry", 0)), "a checkpoint has more sentries than a scrapyard %s %s" % [str(count["concord"]), str(count["boneyard"])])
	check(int(count["boneyard"].get("scavenger", 0)) > int(count["clans"].get("scavenger", 0)), "a scrapyard has more scavengers than a clan hall")
	check(int(count["clans"].get("pirate", 0)) > int(count["boneyard"].get("pirate", 0)), "a clan hall has more pirates")
	check(int(count["lumen"]["total"]) < int(count[""]["total"]), "a Lumen shrine is quiet (%d against %d foes)" % [count["lumen"]["total"], count[""]["total"]])
	check(int(count["lumen"].get("hollow_touched", 0)) > 0, "with a Hollow tilt")
	check(int(count["hollow"].get("hollow_touched", 0)) * 2 > int(count["hollow"]["total"]), "and a Hollow place is mostly the Hollow-touched")
	eq(int(count[""].get("hollow_touched", 0)), 0, "(a plain site has none)")


func test_the_theme_colours_exist_for_the_props_it_names() -> void:
	for theme in Themes.ids():
		for prop in Themes.def(theme).get("colors", {}):
			check(Site.config()["props"].has(prop), "%s colours a prop that exists (%s)" % [theme, prop])
			eq(Themes.def(theme)["colors"][prop].size(), 2, "[fill, edge]")
		for purpose in Themes.def(theme).get("rooms", {}):
			check(Site.config()["rooms"].has(purpose), "%s names a room that exists (%s)" % [theme, purpose])
			for e in Themes.def(theme)["rooms"][purpose]:
				check(Site.config()["props"].has(e["prop"]), "%s puts a prop that exists in %s (%s)" % [theme, purpose, e["prop"]])
		for kind in Site.kinds():
			check(not Themes.def(theme)["names"].get(kind, ["x"]).is_empty(), "%s has names for a %s" % [theme, kind])
	for prop in Site.config()["props"]:
		var def: Dictionary = Site.config()["props"][prop]
		if def["loot"] and def.has("table"):
			check(Site.config()["tables"].has(def["table"]), "%s has its table" % prop)


# --- discoveries ----------------------------------------------------------------------------------------------------------

func test_marks_are_placed_in_rooms_and_come_from_a_stream_of_their_own() -> void:
	var by_kind := {}
	for kind in ["station", "derelict", "nest", "wreck"]:
		var n := 0
		for i in 20:
			var a = Site.make(300 + i, kind, {"faction": "clans"})
			var b = Site.make(300 + i, kind, {"faction": "clans"})
			eq(a.marks, b.marks, "%s %d: the same marks" % [kind, i])
			var span: Array = Site.config()["marks"]["count"][kind]
			check(a.marks.size() >= int(span[0]) and a.marks.size() <= int(span[1]), "%s %d: %d marks" % [kind, i, a.marks.size()])
			var rooms := {}
			for m in a.marks:
				n += 1
				check(["terminal", "body", "room"].has(m["kind"]), "a known kind of spot")
				check(not rooms.has(m["room"]), "one to a room")
				rooms[m["room"]] = true
				check(a.rooms[m["room"]]["purpose"] != "airlock" and not a.rooms[m["room"]]["corridor"], "not in the airlock or a corridor")
				if m["kind"] != "room":
					check(a.props[m["prop"]]["room"] == m["room"] and a.props[m["prop"]]["prop"] == m["kind"], "on a prop of its kind in the room")
		by_kind[kind] = n
	check(by_kind["station"] > by_kind["derelict"] and by_kind["wreck"] <= 20, "a station has the most, a wreck at most one a site (%s)" % str(by_kind))


func test_stepping_into_a_marked_room_tells_the_view_once() -> void:
	var s = _visit("station", 31)
	check(not s.site.marks.is_empty(), "this station has a marked spot")
	var m: Dictionary = s.site.marks[0]
	var r: Rect2i = s.site.rooms[m["room"]]["rect"]
	s.foes.list.clear()
	s.soldier.pos = Vector2(r.position) + Vector2(r.size) / 2.0
	s.take_events()
	s.tick(0.1)
	var told: Array = s.take_events().filter(func(e): return e["type"] == "discover")
	eq(told.size(), 1, "told once")
	eq(told[0]["mark"], m["id"], "which spot")
	s.tick(0.1)
	eq(s.take_events().filter(func(e): return e["type"] == "discover").size(), 0, "and not again")
	check(s.seen_marks.has(m["id"]), "it is seen")
	var b = _visit("station", 31)
	b.foes.list.clear()
	b.soldier.pos = Vector2(r.position) + Vector2(r.size) / 2.0
	var f: Dictionary = b.foes.add("pirate", b.soldier.pos + Vector2(4, 0), m["room"], false)
	f["mode"] = "hunt"
	b.take_events()
	b.tick(0.1)
	eq(b.take_events().filter(func(e): return e["type"] == "discover").size(), 0, "not with a foe on the hunt")
	f["mode"] = "idle"
	f["track"] = 0.0
	b.foes.list.clear()
	b.tick(0.1)
	eq(b.take_events().filter(func(e): return e["type"] == "discover").size(), 1, "but when it is quiet")


func test_a_discovery_picks_a_site_event_by_the_kind_of_spot() -> void:
	var c := _camp([_ev("at_terminals", "boarding_site", {"mark": "terminal"}), _ev("at_bodies", "boarding_site", {"mark": "body"}), _ev("in_rooms", "boarding_site", {"mark": "room"})])
	var s = _visit("station", 31)
	s.campaign = c
	for m in s.site.marks:
		var d: Dictionary = s.discover(m["id"])
		eq(d["event"]["id"], {"terminal": "at_terminals", "body": "at_bodies", "room": "in_rooms"}[m["kind"]], "the event of a %s" % m["kind"])
		eq(d["node"]["type"], "boarding_site", "")
	eq(s.discover(99), {}, "no such spot")


# --- the rounds ---------------------------------------------------------------------------------------------------------------

func test_the_rounds_recipe_makes_ten_for_four_scrap_and_two_copper_and_is_known_at_the_start() -> void:
	var c := Crafting.new()
	c.load("res://data/recipes.json", "res://data/materials.json")
	check(c.is_known("hand_ammo"), "known at the start")
	eq(c.def("hand_ammo")["output"], {"item": "hand_ammo", "count": 10}, "ten rounds")
	eq(c.def("hand_ammo")["materials"], {"scrap": 4, "copper": 2}, "for four scrap and two copper")
	eq(int(c.def("hand_ammo")["fab_level"]), 1, "at the plainest fabricator")
	var inv := Inventory.new()
	inv.add("scrap", 10)
	inv.add("copper", 5)
	eq(c.enqueue("hand_ammo", inv, {"level": 1, "tools": [], "modules": []}), "", "queued")
	eq([inv.count("scrap"), inv.count("copper")], [6, 3], "the materials are paid")
	var done := c.tick(float(c.def("hand_ammo")["time"]) + 0.1, inv, {"level": 1, "tools": [], "modules": []})
	eq(done, ["hand_ammo"], "made")
	eq(inv.count("hand_ammo"), 10, "ten rounds in the hold")
	var short := Inventory.new()
	short.add("scrap", 3)
	short.add("copper", 5)
	check(c.can_craft("hand_ammo", short, {"level": 1, "tools": []}).begins_with("missing: 1 scrap"), "three scrap is not enough")


# --- the music ------------------------------------------------------------------------------------------------------------

func test_the_fight_layer_comes_up_aboard_when_a_foe_is_on_the_hunt_and_the_muffle_stays() -> void:
	var a = Audio.new()
	a.setup()
	var v = BoardView.new()
	a.board = v
	eq(bool(a.mood_inputs().get("fight", false)), false, "not aboard: no fight")
	v.active = true
	eq(bool(a.mood_inputs().get("fight", false)), false, "aboard and quiet: explore")
	v._fight_t = 5.0
	eq(bool(a.mood_inputs().get("fight", false)), true, "a foe has noticed him: the fight layer")
	eq(Mood.raw(a.mood_inputs()), "combat", "which is the combat mood")
	v.active = false
	eq(bool(a.mood_inputs().get("fight", false)), false, "back aboard the ship, no longer")
	a.muffle(true)
	a.music_state("combat")
	check(a.muffled and a.music_now == "combat", "the muffle is on while the combat mood plays")
	a.music_state("explore")
	check(a.muffled, "and it is not the mood's to take off")
	a.muffle(false)
	v.free()
	a.free()


# --- the whole way: E, the panel, the world standing still, the outcome ---------------------------------------------------

func _screen(seed_value := 5) -> Dictionary:
	var sim := ShipSim.new()
	sim.ships = [_ship()]
	var build := BuildMode.new()
	build.sim = sim
	var map := MapView.new()
	map.sim = sim
	map.build = build
	map.size = Vector2(1600.0, 900.0)
	build.drift = map
	var combat := CombatView.new()
	combat.sim = sim
	combat.build = build
	map.combat = combat
	var view := SectorView.new()
	view.sim = sim
	view.build = build
	view.combat = combat
	view.cam = Camera2D.new()
	var board := BoardView.new()
	board.sim = sim
	board.build = build
	board.cam = view.cam
	board.sector = view
	board.ask_party = false
	map.board = board
	board.finished.connect(map._on_board_finished)
	board.talk_requested.connect(map._on_talk)  # (map._ready does it in the scene)
	map.new_game(seed_value)
	map.visible = false
	map.save_path = "user://test_boarding_people_campaign.json"
	build.build_on = false
	view.frame(0.05)
	return {"sim": sim, "build": build, "map": map, "view": view, "board": board, "combat": combat}


func _free(d: Dictionary) -> void:
	if d["board"].active:
		d["board"].leave()
	d["view"].cam.free()
	for k in ["board", "view", "combat", "map", "build", "sim"]:
		d[k].free()


func test_e_opens_the_event_panel_over_the_dark_and_the_world_waits_until_it_is_done() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var board: BoardView = d["board"]
	var s: Sector = map.campaign.current_sector()
	var poi := {"id": "pt", "type": "abandoned_station", "name": "Hulk", "pos": s.ship_pos, "visibility": "signal", "event_type": "wreck_field", "state": Sector.NEW, "enemy": "", "main": false}
	s.pois.append(poi)
	var ev := {"id": "t_wreck", "type": "wreck_field", "title": "Hulk", "text": "A dead hull.", "choices": [{"text": "Pick through it.", "outcomes": [{"weight": 1, "text": "Scrap.", "effects": {"items": {"scrap": 3}}}]}]}
	map.open_poi({"poi": poi, "refused": "", "event": Boarding.offer(ev, "station"), "dock": false}, s)
	var go := -1
	for i in map.event_panel.view.size():
		if str(map.event_panel.view[i]["text"]).begins_with("Board"):
			go = i
	map.event_panel.choose(go)
	map.event_panel.proceed()
	check(board.active, "aboard")
	var ses = board.session
	var n: Dictionary = ses.people.add("survivor", Vector2.ZERO, ses.site.airlock["room"], "human", "Okafor")
	var spots: Array = ses.site.free_anchors(ses.site.airlock["room"])
	spots.sort_custom(func(a, b): return (Vector2(a) + Vector2.ONE).distance_to(ses.soldier.pos) < (Vector2(b) + Vector2.ONE).distance_to(ses.soldier.pos))
	for a in spots:
		if (Vector2(a) + Vector2.ONE).distance_to(ses.soldier.pos) >= 2.0:
			n["m"].pos = Vector2(a) + Vector2.ONE
			break
	var camp: Campaign = map.campaign
	camp.events.add({"id": "t_person", "type": "boarding_npc", "weight": 1000, "once": false, "requires": {"role": "survivor"}, "text": "{name} looks up.",
		"choices": [{"text": "Ask about the cargo.", "outcomes": [{"weight": 1, "text": "{name} points.", "effects": {"npc_reveal": "container", "flag": "talked_aboard"}}]},
			{"text": "Leave.", "outcomes": [{"weight": 1, "text": "", "effects": {}}]}]}, "test.json")
	board.e_override = false
	board.step(0.05)
	eq(str(board.target.get("type", "")), "npc", "E would talk to the person")
	board.e_override = true
	board.step(0.05)
	check(board.talking, "the world stands still")
	check(map.visible and map.panel_only and map.event_panel.visible, "the event panel is up over it")
	eq(map.event_panel.title, "Okafor, survivor", "titled with the person")
	eq(map.event_panel.event["text"], "Okafor looks up.", "with their name in the text")
	var at: Vector2 = ses.soldier.pos
	board.step(0.5)
	eq(ses.soldier.pos, at, "he does not move meanwhile")
	check(s.find("pt")["state"] == Sector.NEW, "and the POI is not resolved by the panel closing")
	map.event_panel.choose(0)
	check(map.event_panel.result["text"] == "Okafor points.", "the outcome is in their words")
	map.event_panel.proceed()
	check(not board.talking and not map.visible, "he is on his feet again, the map gone")
	check(camp.flags.has("talked_aboard"), "the flag is set")
	eq(ses.people.revealed.size(), 1, "and the place they pointed to is marked")
	check(n["done"], "the person has said their piece")
	check(s.find("pt")["state"] == Sector.NEW, "the POI is still not done")
	board.e_override = false
	board.step(0.05)
	board.e_override = true
	board.step(0.05)
	check(not board.talking and board.message_alive(), "a second E is a word, not the page again (%s)" % board.message)
	_free(d)
