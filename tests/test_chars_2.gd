extends "res://tests/base_test.gd"
## The second character pack (data/packs/chars_2; docs/CONTENT.md section 16): 24 named crew, one for each of the twenty
## newer races (the Warden-frame, who has no homeland, is met in the late stages anywhere) and four wanderers, each with an
## active ability and an event that recruits them. These tests read the real data: the roster, the events (reachable, with a
## free way out, chained by flags, fights paid after the win), the fresh names and a recruit onto a ship. The schema and the
## ability numbers themselves are checked by test_content.gd and test_crew_abilities.gd.

const Campaign = preload("res://scripts/space/campaign.gd")
const Content = preload("res://scripts/data/content.gd")
const CrewAbilities = preload("res://scripts/crew/crew_abilities.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Events = preload("res://scripts/space/events.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Regions = preload("res://scripts/space/regions.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")

const PACK := "chars_2"
## race -> its homeland region ("" for the Warden-frame: no homeland, a late-stage quest).
const HOMES := {"vellum": "vellum_stacks", "oorth": "oorth_quietude", "drakkin": "drakkin_pits", "wisp": "wisp_stormfield", "hullkin": "hullkin_reefs",
	"lantern": "lantern_lanes", "revenant": "revenant_cairns", "choir": "choir_chantry", "rattler": "rattler_walls", "tessellate": "tessellate_mend",
	"sable": "sable_moorings", "quillback": "quillback_lists", "kite": "kite_slack", "warden_frame": "", "murrow": "murrow_diggings",
	"siltborn": "siltborn_rings", "corvin": "corvin_roost", "brine": "brine_yards", "echo": "echo_glassways", "ferro": "ferro_lodes"}
const WANDERERS: Array[String] = ["tilley", "pettifer", "tinder", "cadence"]
## The chains of two events: [flag, first event, second event].
const CHAINS: Array = [
	["char_obliged_invited", "char_obliged_late_reply", "char_obliged_arrives_yesterday"],
	["char_tilley_dusk", "char_tilley_is_it_dusk", "char_tilley_lights_the_way"],
]


func _roster() -> Array:
	return Content.list("characters").filter(func(c): return Content.origin("characters", c["id"]) == PACK)


## Every event of the pack, by id.
func _pack_events() -> Dictionary:
	var out := {}
	var evs = Events.shared()
	for id in evs.order:
		if Content.origin("events", id) == PACK:
			out[id] = evs.events[id]
	return out


## Every effects dictionary an outcome of `ev` can run: its effects, and its after_win's (the fight was won).
func _effects(ev: Dictionary) -> Array:
	var out := []
	for ch in ev.get("choices", []):
		for o in ch.get("outcomes", []):
			out.append(o.get("effects", {}))
			if o.get("after_win") is Dictionary:
				out.append(o["after_win"].get("effects", {}))
	return out


## character id -> the ids of the events that recruit them.
func _recruiters() -> Dictionary:
	var out := {}
	var evs := _pack_events()
	for id in evs:
		for eff in _effects(evs[id]):
			var r = eff.get("recruit")
			if r is Dictionary and r.has("character"):
				var who := str(r["character"])
				if not out.has(who):
					out[who] = []
				if not out[who].has(id):
					out[who].append(id)
	return out


## The region a recruit event belongs to: its own `region`, or (for the second event of a chain) that of the event that sets its flag.
func _origin(evs: Dictionary, id: String) -> String:
	var req: Dictionary = evs[id].get("requires", {})
	if req.has("region"):
		return str(req["region"])
	for f in Events._list(req.get("flag")):
		for other in evs:
			if other != id and _effects(evs[other]).any(func(eff): return Events._list(eff.get("flag")).has(f)):
				return _origin(evs, other)
	return ""


func _camp(region: String, stage: int) -> Campaign:
	var c := Campaign.new(1, {}, Events.shared())
	c.stage = stage
	c.region_id = region
	c.region_data = Regions.get_region(region)
	c.flags["in_" + region] = true
	return c


func _ship() -> Ship:
	var s: Ship = Ship.from_design("res://data/ships/starter_rustbucket.json")
	Jobs.spawn_crew(s)
	for k in ["fuel", "credits", "crystal", "plasma_cell", "bed", "scrap", "polymer", "copper", "titanium"]:
		s.inventory.add(k, 1000)
	return s


func _node(ev: Dictionary) -> Dictionary:
	return {"id": "n01", "type": str(ev["type"]), "place": ""}


func _aboard(ship: Ship, id: String) -> bool:
	return ship.crew.any(func(m): return m.character == id)


# --- the roster -----------------------------------------------------------------------------------------------

func test_24_characters_one_per_newer_race_and_four_wanderers() -> void:
	var roster := _roster()
	eq(roster.size(), 24, "24 characters in " + PACK)
	var evs := _pack_events()
	var recruiters := _recruiters()
	var home := {}
	var wanderers := []
	var abilities := {}
	for c in roster:
		abilities[str(c["ability"]["id"])] = true
		var first: Array = recruiters.get(c["id"], [])
		check(not first.is_empty(), "%s has a recruit event" % c["id"])
		if first.is_empty():
			continue
		var region := _origin(evs, first[0])
		if c.get("species") == "warden_frame":
			check(region == "" and evs[first[0]].get("requires", {}).get("flag") == "warden_lit", "the Warden-frame has no homeland: %s asks for the reboot quest's flag" % first[0])
			home["warden_frame"] = int(home.get("warden_frame", 0)) + 1
		elif region == "":
			wanderers.append(c["id"])
		elif Regions.get_region(region).get("home_species") == c.get("species"):
			home[c["species"]] = int(home.get(c["species"], 0)) + 1
			eq(region, HOMES[c["species"]], "%s is found in the homeland of their race" % c["id"])
		else:
			check(false, "%s is found in %s, which is not their race's homeland" % [c["id"], region])
	for r in HOMES:
		eq(home.get(r, 0), 1, "one %s character, found where that race lives" % r)
	wanderers.sort()
	eq(wanderers, ["cadence", "pettifer", "tilley", "tinder"], "four wanderers found in any region")
	check(abilities.size() >= 10, "the roster uses at least 10 of the abilities: " + str(abilities.keys()))
	check(not abilities.has("berserk"), "nothing reads berserk yet, so nobody has it")
	for c in roster:
		check(float(CrewAbilities.of(_member(c["id"]))["cooldown"]) >= 10.0, "%s: a sane cooldown" % c["id"])
	eq(CrewAbilities.problems(), [], "the ability data is sound")


func _member(id: String):
	var m = CrewMember.from_character(id, Vector2(5.0, 5.0))
	check(m != null, id + " makes a crew member")
	return m


func test_every_name_is_fresh_across_every_pool() -> void:
	var seen := {}
	for n in CrewMember.config()["names"]:
		seen[str(n).to_lower()] = "crew.json"
	var pools: Dictionary = Content.names()
	for kind in pools:
		var pool = pools[kind]
		if pool is Dictionary:
			for species in pool:
				for n in pool[species]:
					seen[str(n).to_lower()] = "%s/%s" % [kind, species]
		else:
			for n in pool:
				seen[str(n).to_lower()] = kind
	for c in Content.list("characters"):
		if Content.origin("characters", c["id"]) != PACK:
			seen[str(c["name"]).to_lower()] = "character " + c["id"]
	var mine := {}
	for c in _roster():
		var n := str(c["name"]).to_lower()
		check(not seen.has(n), "%s: the name is also in %s" % [c["name"], seen.get(n, "")])
		check(not mine.has(n), "%s: two characters of the pack share a name" % c["name"])
		mine[n] = true


# --- the events -----------------------------------------------------------------------------------------------

func test_every_recruit_event_can_be_rolled_somewhere() -> void:
	var evs := _pack_events()
	eq(evs.size(), 26, "24 recruit events and 2 chain openers")
	var setters := {}  # flag -> the events that set it
	for id in evs:
		for eff in _effects(evs[id]):
			for f in Events._list(eff.get("flag")):
				if not setters.has(f):
					setters[f] = []
				setters[f].append(id)
	for id in evs:
		var ev: Dictionary = evs[id]
		var req: Dictionary = ev.get("requires", {})
		check(Events.NODE_TYPES.has(ev["type"]), "%s: type %s is a node type, so it is rolled" % [id, ev["type"]])
		check(float(ev.get("weight", 0)) > 0.0 and not Events.shared().is_page(id), "%s: has a weight and is no page" % id)
		check(bool(ev.get("once", false)), id + ": once")
		var lo := int(req.get("stage_min", 1))
		var hi := int(req.get("stage_max", 8))
		if req.has("region"):
			var r := Regions.get_region(str(req["region"]))
			check(not r.is_empty(), "%s: region %s exists" % [id, req["region"]])
			lo = maxi(lo, int(r.get("stages", [1, 8])[0]))
			hi = mini(hi, int(r.get("stages", [1, 8])[1]))
		check(lo <= hi, "%s: its stage window is not empty (%d to %d)" % [id, lo, hi])
		for f in Events._list(req.get("flag")):
			if f == "warden_lit":
				var quest: Dictionary = Events.shared().get_event("warden_cold_start")
				check(_effects(quest).any(func(eff): return Events._list(eff.get("flag")).has("warden_lit")), "%s: the flag warden_lit is set by the Warden reboot quest" % id)
			else:
				check(setters.has(f) and not setters[f].has(id), "%s: the flag %s is set by another event" % [id, f])


func test_every_event_has_a_free_way_out_and_most_have_a_blue_choice() -> void:
	var blue := 0
	for id in _pack_events():
		var ev: Dictionary = _pack_events()[id]
		var free := false
		var always := false  # a choice that is always on offer (the soak test's rule)
		for ch in ev["choices"]:
			var req: Dictionary = ch.get("requires", {})
			var costs: bool = req.has("items") or req.has("credits") or req.has("pay") or bool(ch.get("pay", false))
			var does_nothing: bool = ch["outcomes"].all(func(o): return Events._dict(o.get("effects")).is_empty())
			free = free or (not costs and does_nothing)
			always = always or req.is_empty()
		check(free, id + " has a way out that costs and changes nothing")
		check(always, id + " has a choice that is always on offer")
		blue += int(ev["choices"].any(func(ch): return Events.is_blue(ch)))
	check(blue >= 20, "blue options on most events (%d of 26)" % blue)


func test_about_a_third_of_the_characters_are_hard_to_get() -> void:
	var evs := _pack_events()
	var hard := {}
	for who in _recruiters():
		for id in _recruiters()[who]:
			var ev: Dictionary = evs[id]
			if ev.get("requires", {}).has("flag"):
				hard[who] = "chain"
			for ch in ev["choices"]:
				if int(ch.get("requires", {}).get("credits", 0)) >= 300 and not hard.has(who):
					hard[who] = "price"
				for o in ch["outcomes"]:
					if o.get("effects", {}).has("fight") and o.get("after_win") is Dictionary and hard.get(who) != "chain":
						hard[who] = "fight"
	check(hard.size() >= 7 and hard.size() <= 9, "8 or so are hard to get: " + str(hard))
	for kind in ["chain", "price", "fight"]:
		check(hard.values().has(kind), "some are hard by a " + kind)


# --- recruiting -----------------------------------------------------------------------------------------------

func test_every_recruiting_outcome_puts_the_character_aboard() -> void:
	var evs := _pack_events()
	for who in _recruiters():
		for id in _recruiters()[who]:
			var ev: Dictionary = evs[id]
			var joined := false
			for eff in _effects(ev):
				var r = eff.get("recruit")
				if not (r is Dictionary and r.get("character") == who):
					continue
				var c := _camp("clan_space", 3)
				var ship := _ship()
				var n := ship.crew.size()
				var res: Dictionary = c.events.apply(eff, c, ship, _node(ev))
				check(_aboard(ship, who) and ship.crew.size() == n + 1, "%s: %s joins" % [id, who])
				var m = ship.crew[-1]
				eq(m.name, Content.entry("characters", who)["name"], who + " keeps their own name")
				check(not CrewAbilities.of(m).is_empty() and CrewAbilities.card(ship, m)["has"], who + " has an ability on their crew card")
				check(m.hp > 0.0 and m.max_hp > 0.0, who + " has a body")
				check(res["lines"].any(func(l): return str(l).contains("joins the crew")), id + " says who joined")
				joined = true
			check(joined, "%s recruits %s" % [id, who])


func test_the_fights_pay_in_a_character_only_after_the_win() -> void:
	for pair in [["char_kharra_house_tug", 0, "kharra", "drakkin_pits", 3], ["char_tamsin_the_contract", 0, "tamsin", "sable_moorings", 4],
			["char_pyracantha_challenge_in_writing", 0, "pyracantha", "quillback_lists", 3]]:
		var ev: Dictionary = Events.shared().get_event(pair[0])
		var c := _camp(pair[3], pair[4])
		var ship := _ship()
		var r: Dictionary = c.events.choose(ev, pair[1], c, ship, _node(ev))
		check(bool(r["ok"]) and str(r["fight"]) != "", "%s: the choice starts a fight (%s)" % [pair[0], str(r)])
		check(not _aboard(ship, pair[2]), "%s is not aboard before the win" % pair[2])
		var fx: Dictionary = r["after_win"].get("effects", {})
		c.events.apply(fx, c, ship, _node(ev))
		check(_aboard(ship, pair[2]), "%s joins after the win" % pair[2])


func test_the_chains_follow_their_flags() -> void:
	var evs = Events.shared()
	for chain in CHAINS:
		var first: Dictionary = evs.get_event(chain[1])
		var second: Dictionary = evs.get_event(chain[2])
		var region := str(first.get("requires", {}).get("region", "clan_space"))
		var stage := maxi(int(first["requires"].get("stage_min", 1)), int(Regions.get_region(region).get("stages", [1, 8])[0]))
		var c := _camp(region, stage)
		var ship := _ship()
		check(evs.eligible(first, c, _node(first), ship), chain[1] + " can happen to begin with")
		check(not evs.eligible(second, c, _node(second), ship), chain[2] + " cannot happen before the flag")
		var r: Dictionary = evs.choose(first, 0, c, ship, _node(first))
		check(bool(r["ok"]) and c.flags.has(chain[0]), "%s: the first choice sets %s (%s)" % [chain[1], chain[0], str(r)])
		check(not evs.eligible(first, c, _node(first), ship), chain[1] + " is spent")
		var later := _camp("clan_space", maxi(int(second["requires"].get("stage_min", 1)), stage))
		later.flags[chain[0]] = true
		check(evs.eligible(second, later, _node(second), ship), chain[2] + " follows in any region once the flag is set")
		var r2: Dictionary = evs.choose(second, 0, later, ship, _node(second))
		check(bool(r2["ok"]), chain[2] + " can be taken")
		check(ship.crew.any(func(m): return m.character != ""), "%s ends with a character aboard" % chain[2])


func test_the_warden_frame_character_waits_for_a_woken_warden() -> void:
	var evs = Events.shared()
	var ev: Dictionary = evs.get_event("char_quoin_the_arch")
	var ship := _ship()
	var c := _camp("clan_space", 5)
	check(not evs.eligible(ev, c, _node(ev), ship), "not before the reboot quest has lit a Warden")
	c.flags["warden_lit"] = true
	check(evs.eligible(ev, c, _node(ev), ship), "once a Warden is lit, in any region")
	check(not evs.eligible(ev, _camp("clan_space", 4), _node(ev), ship), "(but not before the late stages)")
	var r: Dictionary = evs.choose(ev, 1, c, ship, _node(ev))  # the struts
	check(bool(r["ok"]) and _aboard(ship, "quoin"), "shoring the arch with titanium brings Quoin aboard")
	var m = ship.crew[-1]
	eq(m.species, "warden_frame", "Quoin is a Warden-frame")
	check(TraitSet.of(m)["mechanical"], "and so mechanical")


func test_a_homeland_character_is_found_only_in_their_homeland() -> void:
	var evs = Events.shared()
	var ev: Dictionary = evs.get_event("char_graticule_withdrawn_cart")
	var ship := _ship()
	check(evs.eligible(ev, _camp("vellum_stacks", 3), _node(ev), ship), "in the Stacks")
	check(not evs.eligible(ev, _camp("clan_space", 3), _node(ev), ship), "not in Clan space")
	check(not evs.eligible(ev, _camp("oorth_quietude", 4), _node(ev), ship), "not in the Quietude")
	for id in ["tilley", "pettifer", "tinder", "cadence"]:
		var first: String = _recruiters()[id][0]
		var wanderer: Dictionary = evs.get_event(first)
		if wanderer.get("requires", {}).has("flag"):
			continue  # the second event of a chain: the flag, not the region, finds you
		check(evs.eligible(wanderer, _camp("mire_fens", 4), _node(wanderer), ship), "%s turns up in any region" % id)
		check(not evs.eligible(wanderer, _camp("clan_space", 1), _node(wanderer), ship), "(but not in the first stage: %s)" % id)
