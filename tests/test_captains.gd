extends "res://tests/base_test.gd"
## The captains and their words (scripts/combat/morale.gd, data/morale.json lines, shipgen.gd): every faction has a pool
## of captain names and its hail, surrender, flee and refuse lines; a generated enemy speaks as "Captain Vex of the
## Dental Plan"; an authored design with no faction keeps the plain lines; the events that name a ship fight a design
## of that name.

const Events = preload("res://scripts/space/events.gd")
const Morale = preload("res://scripts/combat/morale.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const COURIER := "res://data/ships/starter_courier.json"
const KINDS: Array[String] = ["hail", "surrender", "flee", "refuse"]


func _fight(faction: String, seed_value := 3) -> Session:
	var enemy := Shipgen.build(faction, "medium", seed_value, 150.0)
	var s := Session.new()
	s.start(Session.load_ship(COURIER), enemy, enemy.rng_seed)
	return s


func test_every_faction_has_captain_names_and_all_four_kinds_of_line() -> void:
	var lines: Dictionary = Morale.config()["lines"]
	var factions: Dictionary = Shipgen.tables()["factions"]
	check(factions.size() >= 8, "the eight factions: %d" % factions.size())
	for id in factions:
		var names: Array = factions[id]["crew"]["names"]
		check(names.size() >= 10, "%s: a pool of captain names (%d)" % [id, names.size()])
		check(lines.has(id), id + ": has lines in data/morale.json")
		for kind in KINDS:
			var pool = lines.get(id, {}).get(kind)
			check(pool is Array and not pool.is_empty() and pool.all(func(l): return l is String and l != ""), "%s: %s lines" % [id, kind])
		for kind in ["hail", "surrender", "flee", "refuse"]:
			for l in lines.get(id, {}).get(kind, []):
				check(not str(l).contains("{") or str(l).contains("{ship}") or str(l).contains("{captain}"), "%s: a stray brace in '%s'" % [id, l])
	for id in ["rustfangs", "clans", "concord", "lumen", "barons"]:
		eq([lines[id]["hail"].size(), lines[id]["surrender"].size(), lines[id]["flee"].size(), lines[id]["refuse"].size()], [3, 5, 3, 2], id + ": the breaking factions have a voice")


func test_a_generated_enemy_hails_by_its_captain_and_its_ship() -> void:
	for faction in ["rustfangs", "concord", "wardens"]:
		var s := _fight(faction)
		var foe = s.arena.ships[Session.ENEMY].ship
		eq(foe.get_meta("ai")["faction"], faction, faction + ": the ship knows whose lines it says")
		eq(s.morale.captain, foe.crew_plan[0]["name"], faction + ": the captain is the first of the crew")
		var who: String = s.morale.speaker()
		if faction == "wardens":
			eq(who, "The " + foe.name, "a warden has no captain to name")
		else:
			eq(who, "Captain %s of the %s" % [foe.crew_plan[0]["name"], foe.name.trim_prefix("The ")], faction + ": 'Captain <name> of the <ship>'")
		eq(s.morale.banner(), "", "no hail yet at the start of the fight (the threat banner has the floor)")
		for i in 270:
			s.tick(Session.STEP)
		var hail: String = s.morale.banner()
		check(hail.begins_with(who + " hails: '") and hail.ends_with("'"), "%s: the hail after 3 s: %s" % [faction, hail])
		for i in 300:
			s.tick(Session.STEP)
		eq(s.morale.banner(), "", faction + ": the hail goes after a few seconds")


func test_a_ship_always_says_the_same_line_and_the_others_differ() -> void:
	var s := _fight("clans")
	var first: String = s.morale.say("surrender")
	for i in 5:
		eq(s.morale.say("surrender"), first, "the same ship, the same words")
	var seen := {}
	for seed_value in range(1, 25):
		seen[_fight("clans", seed_value).morale.say("surrender")] = true
	check(seen.size() >= 3, "other ships, other words: %d different" % seen.size())
	check(not first.contains("{"), "the placeholders are filled: " + first)


func test_the_offer_the_flight_and_the_refusal_speak_for_the_captain() -> void:
	var s := _fight("rustfangs")
	var who: String = s.morale.speaker()
	s.morale.state = "offering"
	s.morale.offer = {"credits": 40}
	s.morale.offer_left = 12.0
	var offer: String = s.morale.banner()
	check(offer.begins_with("%s hails: '%s' Offer: 40 credits." % [who, s.morale.say("surrender")]), "the offer: " + offer)
	check(offer.contains("Y accept / keep firing to refuse (12 s)"), "with the keys and the clock: " + offer)
	s.morale.state = "fleeing"
	eq(s.morale.banner(), "%s: '%s' Spooling its jump drive! Knock out its engines or helm" % [who, s.morale.say("flee")], "the flight")
	s.morale.state = "fighting_on"
	s.morale.refused_at = s.arena.time()
	eq(s.morale.banner(), "%s: '%s'" % [who, s.morale.say("refuse")], "the refusal")


func test_an_authored_design_keeps_the_plain_lines_and_a_named_one_has_its_captain() -> void:
	var plain := Session.new()
	plain.start(Session.load_ship(COURIER), Session.load_ship("res://data/ships/pirate_raider.json"), 3)
	eq(plain.morale.faction, "", "no faction on a design without one")
	eq(plain.morale.speaker(), "The Pirate Raider", "so 'The <ship>'")
	var vex := Session.new()
	vex.start(Session.load_ship(COURIER), Session.load_ship("res://data/ships/dental_plan.json"), 3)
	eq(vex.morale.speaker(), "Captain Vex of the Dental Plan", "the Dental Plan has Captain Vex")
	var skarn := Session.new()
	skarn.start(Session.load_ship(COURIER), Session.load_ship("res://data/ships/eviction_notice.json"), 3)
	eq(skarn.morale.speaker(), "Captain Skarn of the Eviction Notice", "the Eviction Notice has Captain Skarn")


func test_the_events_that_name_a_ship_fight_a_design_of_that_name() -> void:
	var c: Events = Events.shared()
	var named := {"pirate_vex_toll": "dental_plan", "pirate_vex_raffle": "dental_plan", "patrol_bounty_posting": "dental_plan", "pirate_skarn_eviction_notice": "eviction_notice"}
	for id in named:
		var ev: Dictionary = c.get_event(id)
		check(not ev.is_empty(), id + " exists")
		check(JSON.stringify(ev).contains('"fight":"%s"' % named[id]) and not JSON.stringify(ev).contains('"fight":"pirate_raider"') and not JSON.stringify(ev).contains('"fight":"rustfang_rammer"'), id + " fights " + named[id])
	check(c.validate().is_empty(), "the events still validate: " + str(c.validate().slice(0, 3)))
