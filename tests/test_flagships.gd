extends "res://tests/base_test.gd"
## The race flagships (scripts/space/flagships.gd, data/flagships.json, data/packs/flagships_1/ships/flagship_<race>.json, data/packs/flagships_1; docs/CONTENT.md section 25): one
## named boss ship for each of the ten major races, met as an optional beacon in its homeland. The designs are valid and use only real parts; the
## beacon appears in one sector of the homeland, from its stage on, never at the exit; a win pays the trophy once and sets the flag; the contact card
## says it is a boss; a flagship never flees; each fight ends inside 180 s.

const Campaign = preload("res://scripts/space/campaign.gd")
const Flagships = preload("res://scripts/space/flagships.gd")
const FoeInfo = preload("res://scripts/space/foe_info.gd")
const FoePic = preload("res://scripts/ui/foe_pic.gd")
const Morale = preload("res://scripts/combat/morale.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Content = preload("res://scripts/data/content.gd")
const Events = preload("res://scripts/space/events.gd")
const Regions = preload("res://scripts/space/regions.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Threat = preload("res://scripts/space/threat.gd")
const Standoff = preload("res://tests/tool_standoff.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const MAJORS: Array = ["basalt", "emberkin", "fenn", "gauntling", "grundl", "human", "kett", "mire", "prismatic", "sporeling"]
const REGION_OF := {"basalt": "basalt_quarries", "emberkin": "emberkin_forges", "fenn": "fenn_bazaar", "gauntling": "gauntling_scrapyards", "grundl": "grundl_barges",
	"human": "human_core", "kett": "kett_hives", "mire": "mire_fens", "prismatic": "prismatic_choir", "sporeling": "sporeling_groves"}


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	return s


## A campaign in the homeland of `race` at run stage `stage`.
func _camp(race: String, stage: int, seed_value := 5) -> Campaign:
	var c := Campaign.new(seed_value)
	c.stage = stage
	c.enter_region(REGION_OF[race])
	return c


## Every flagship POI of the campaign's current region: [{node, poi}].
func _bosses(c: Campaign) -> Array:
	var out := []
	for id in c.drift.ids():
		for p in c.sector_at(str(id)).all_pois():
			if p.has("boss"):
				out.append({"node": str(id), "poi": p})
	return out


# --- the data and the designs -----------------------------------------------------------------------------------

func test_every_major_race_has_a_flagship_and_the_data_is_sound() -> void:
	eq(Flagships.races(), MAJORS, "a flagship for each of the ten major races")
	eq(Flagships.problems(), [], "data/flagships.json has no problems")
	for race in MAJORS:
		var e := Flagships.entry(race)
		eq(str(e["region"]), REGION_OF[race], race + ": it sails in its homeland")
		eq(Flagships.race_of_region(Regions.get_region(REGION_OF[race])), race, race + ": the homeland names it")
		check(str(e["poi_name"]).contains(str(e["name"])), race + ": the beacon carries the ship's name")
		check(str(e["card"]).length() <= 60, race + ": the card line is short enough to read at a glance")
		var cap := str(e["captain"])
		eq(str(Morale.config()["lines"]["flagship_" + race]["title"]) != "", true, race + ": its captain has a title")
		check(cap != "", race + ": a captain")


func test_each_design_loads_is_valid_and_uses_only_real_parts() -> void:
	var known := {}
	for c in Content.list("components"):
		known[str(c["id"])] = true
	for race in MAJORS:
		var path := Flagships.design_of(race)
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(d is Dictionary, race + ": the design file reads")
		var ship = Session.load_ship(path)
		check(ship != null, race + ": the design loads")
		if ship == null:
			continue
		for inst in d["components"]["instances"]:
			check(known.has(str(inst["id"])), "%s: part %s exists" % [race, inst["id"]])
		var why := Shipgen.validate(ship, 0.9)
		eq(why, [], race + ": a valid ship (power, air, mounts, flight, a gun)")
		var look: Dictionary = ship.get_meta("style", {})
		check(not look.is_empty() and str(look["race"]) == race, race + ": in its race's livery")
		check(not look.get("emblem", {}).is_empty(), race + ": with its emblem")
		eq(str(ship.get_meta("ai")["faction"]), "flagship_" + race, race + ": it says its own lines")
		eq(str(ship.get_meta("ai")["captain"]), ship.crew_plan[0]["name"], race + ": the captain is the first of the crew")
		check(ship.crew_plan.size() >= 8, race + ": a crew fit for a flagship (%d)" % ship.crew_plan.size())
		var big := Shipgen.build(race, "large", 7, 400.0)
		check(ship.grid.tiles.size() > big.grid.tiles.size(), "%s: bigger than the largest ship it normally flies (%d vs %d tiles)" % [race, ship.grid.tiles.size(), big.grid.tiles.size()])
		var ids := {}
		for uid in ship.components.instances:
			ids[str(ship.components.instances[uid]["id"])] = true
		var sig := false
		for id in ids:
			sig = sig or str(id).begins_with(race + "_")
		check(sig or race == "human" and ids.has("human_concord_railgun"), race + ": it carries its race's own parts")


func test_the_trophies_are_unique_parts_found_nowhere_else() -> void:
	var seen := {}
	for race in MAJORS:
		var part := str(Flagships.entry(race)["reward"]["part"])
		check(not seen.has(part), race + ": its own trophy")
		seen[part] = true
		var def := {}
		for c in Content.list("components"):
			if str(c["id"]) == part:
				def = c
		check(not def.is_empty() and bool(def.get("unique", false)), race + ": " + part + " is a unique part")
		for r in Content.list("recipes"):
			check(str(r.get("output", {}).get("item", "")) != part, part + " has no recipe")
		for reg in Content.regions():
			check(not reg.get("stock", {}).has(part), part + " is sold nowhere")
		check(str(def.get("blurb", "")) != "" and str(def.get("quirk", "")) != "", part + " explains itself")


func test_the_flagship_logs_exist() -> void:
	var ev := Events.new()
	for race in MAJORS:
		var id := str(Flagships.entry(race)["log"])
		check(ev.logs.has(id), race + ": log " + id)


# --- where it is met ----------------------------------------------------------------------------------------------

func test_the_beacon_is_in_one_sector_of_its_homeland_from_its_stage_on() -> void:
	for race in MAJORS:
		var stage := int(Flagships.entry(race)["stage"])
		var before := _camp(race, stage - 1)
		eq(_bosses(before).size(), 0, "%s: none before stage %d" % [race, stage])
		var c := _camp(race, stage)
		var found := _bosses(c)
		eq(found.size(), 1, "%s: one beacon from stage %d" % [race, stage])
		if found.is_empty():
			continue
		var poi: Dictionary = found[0]["poi"]
		eq(str(poi["type"]), "flagship", race + ": a flagship POI")
		eq(str(poi["visibility"]), "beacon", race + ": a beacon, on the radar from anywhere in its sector")
		eq(str(poi["boss"]), race, race + ": of its own race")
		var n: Dictionary = c.drift.node(str(found[0]["node"]))
		check(str(n["type"]) != "exit" and str(n["place"]) == "" and str(found[0]["node"]) != c.drift.start_id(), race + ": not at the exit, the start or a fixed place")
		var again := _camp(race, stage)
		eq(str(_bosses(again)[0]["node"]), str(found[0]["node"]), race + ": the same seed puts it in the same sector")
		check(_bosses(again)[0]["poi"]["pos"].is_equal_approx(poi["pos"]), race + ": at the same place")
		var later := _camp(race, int(Regions.get_region(REGION_OF[race])["stages"][1]))
		eq(_bosses(later).size(), 1, race + ": and in the later stages of the region too")


func test_it_is_only_in_its_homeland_and_never_in_the_other_regions() -> void:
	for race in ["kett", "human", "prismatic"]:
		for other in ["concord_space", "clan_space", "boneyard", "fenn_bazaar", "mire_fens"]:
			if REGION_OF[race] == other:
				continue
			var c := Campaign.new(5)
			c.stage = 8
			c.enter_region(other)
			var home := Flagships.race_of_region(Regions.get_region(other))
			var got := _bosses(c)
			eq(got.size(), 0 if home == "" else 1, "%s at stage 8: %s" % [other, "no flagship" if home == "" else "only its own"])
			for b in got:
				eq(str(b["poi"]["boss"]), home, other + ": its own race's flagship")


func test_it_never_blocks_the_exit() -> void:
	for race in MAJORS:
		var c := _camp(race, int(Flagships.entry(race)["stage"]))
		var exit_poi := false
		for p in c.sector_at(c.drift.exit_id()).all_pois():
			exit_poi = exit_poi or p.has("boss")
		check(not exit_poi, race + ": not in the exit's sector")
		check(not c.flags.has(Flagships.flag_of(race)), race + ": not beaten")
		check(not c.warden.is_empty() and c.warden_up(), race + ": the exit warden is untouched, and it alone holds the lane")
		var at = c.sector_at(c.drift.exit_id())
		check(at.pois.all(func(p): return not p.has("boss")), race + ": the exit sector has no flagship to clear first")


func test_the_beacon_page_warns_and_offers_a_fight_or_to_stay_clear() -> void:
	var c := _camp("kett", 3)
	var b: Dictionary = _bosses(c)[0]
	var sector = c.sector_at(str(b["node"]))
	var ship := _ship()
	c.current = str(b["node"])
	c.visited[c.current] = true
	sector.ship_pos = b["poi"]["pos"] + Vector2(100.0, 0.0)
	var res: Dictionary = sector.trigger(c, ship)
	eq(str(res.get("poi", {}).get("id", "")), "flagship", "flying up to the beacon opens its page")
	var ev: Dictionary = res["event"]
	check(str(ev["text"]).begins_with("FLAGSHIP SIGNAL"), "the page opens with the warning")
	eq(ev["choices"].size(), 2, "engage or stay clear")
	var out := c.events.choose(ev, 1, c, ship, c.node(c.current))
	check(out["ok"] and str(out["fight"]) == "", "staying clear starts no fight")
	sector.resolve("flagship")
	eq(str(sector.find("flagship")["state"]), Sector.NEW, "and the beacon is still there")
	sector.ship_pos = b["poi"]["pos"] + Vector2(4000.0, 0.0)
	sector.trigger(c, ship)
	sector.ship_pos = b["poi"]["pos"]
	check(not sector.trigger(c, ship).is_empty(), "it hails again when the ship comes back")


# --- winning ------------------------------------------------------------------------------------------------------

func test_a_win_pays_the_trophy_once_sets_the_flag_and_leaves_a_log() -> void:
	for race in ["kett", "fenn"]:
		var e := Flagships.entry(race)
		var c := _camp(race, int(e["stage"]))
		var b: Dictionary = _bosses(c)[0]
		var sector = c.sector_at(str(b["node"]))
		var ship := _ship()
		c.current = str(b["node"])
		c.visited[c.current] = true
		sector.ship_pos = b["poi"]["pos"]
		var res: Dictionary = sector.trigger(c, ship)
		var picked := c.events.choose(res["event"], 0, c, ship, c.node(c.current))
		eq(str(picked["fight"]), Flagships.design_of(race), race + ": engaging fights the flagship's design")
		eq(sector.fight_design(c, "flagship", str(picked["fight"])), Flagships.design_of(race), race + ": and the sector sends that design")
		var foe = Session.load_ship(Flagships.design_of(race))
		var part := str(e["reward"]["part"])
		var credits := ship.inventory.count("credits")
		var scrap := ship.inventory.count("scrap")
		eq(ship.inventory.count(part), 0, race + ": no trophy yet")
		var r := c.fight_done({"state": "won", "enemy": foe, "threat": 3}, ship, picked["after_win"])
		eq(ship.inventory.count(part), 1, race + ": the trophy")
		check(ship.inventory.count("credits") >= credits + int(e["reward"]["credits"]), race + ": credits like a big ship")
		check(ship.inventory.count("scrap") >= scrap + int(e["reward"]["scrap"]), race + ": and scrap")
		check(c.flags.has("flagship_%s_beaten" % race), race + ": the flag the race's events can read")
		check(r["lines"].any(func(l): return str(l).begins_with("Log found")), race + ": a log line")
		check(c.logs_found.has(str(e["log"])), race + ": the log is kept")
		sector.resolve("flagship")
		eq(str(sector.find("flagship")["state"]), Sector.DONE, race + ": the beacon goes quiet")
		sector.ship_pos = b["poi"]["pos"] + Vector2(5000.0, 0.0)
		sector.trigger(c, ship)
		sector.ship_pos = b["poi"]["pos"]
		eq(sector.trigger(c, ship), {}, race + ": it cannot be fought, or paid, twice")
		eq(ship.inventory.count(part), 1, race + ": still one trophy")


func test_a_lost_or_fled_fight_pays_nothing_and_does_not_set_the_flag() -> void:
	var c := _camp("kett", 3)
	var ship := _ship()
	var sector = c.sector_at(str(_bosses(c)[0]["node"]))
	var ev := Flagships.event(c, ship, sector.find("flagship"))
	var after: Dictionary = ev["choices"][0]["outcomes"][0]["after_win"]
	var fled := c.fight_done({"state": "fled", "enemy": null}, ship, after)
	eq(fled["state"], "fled", "a fight left is just left")
	check(not c.flags.has("flagship_kett_beaten"), "no flag")
	eq(ship.inventory.count(str(Flagships.entry("kett")["reward"]["part"])), 0, "no trophy")
	var lost := c.fight_done({"state": "lost", "enemy": null}, ship, after)
	eq(lost["state"], "lost", "a lost fight is lost like any other")


func test_the_saved_campaign_keeps_the_beacon_and_its_state() -> void:
	var c := _camp("human", 4)
	var b: Dictionary = _bosses(c)[0]
	c.flags[Flagships.flag_of("human")] = true
	c.current = str(b["node"])
	c.visited[c.current] = true
	c.sector_at(c.current).ship_pos = b["poi"]["pos"]
	c.sector_at(c.current).trigger(c, _ship())  # the flag is set, so the beacon is done
	var d := c.to_dict()
	var c2 := Campaign.new(5)
	eq(c2.load_dict(JSON.parse_string(JSON.stringify(d))), "", "the save loads")
	var again := _bosses(c2)
	eq(again.size(), 1, "the beacon is made again")
	eq(str(again[0]["poi"]["state"]), Sector.DONE, "and it is still done")


# --- the card, the words, the morale ---------------------------------------------------------------------------------

func test_the_contact_card_says_it_is_a_boss() -> void:
	for race in MAJORS:
		var e := Flagships.entry(race)
		var info := FoeInfo.of(Flagships.design_of(race))
		check(not info.is_empty(), race + ": the card can show her")
		var boss: Dictionary = info["boss"]
		eq([boss["title"], boss["name"], boss["captain"], boss["line"]], ["FLAGSHIP", e["name"], e["captain"], e["card"]], race + ": the boss line")
		eq(str(info["line"]), str(Shipgen.style_of(race, "large", str(e["role"]))["line"]), race + ": her name line is her race's")
	var pic := FoePic.new()
	var info := FoeInfo.of(Flagships.design_of("kett"))
	pic.show_foe(info["ship"], _ship(), info["line"], info["boss"])
	check(pic.size.y > FoePic.BOX.y, "a boss card is taller, to say it")
	eq(pic.boss["title"], "FLAGSHIP", "and carries the boss tag")
	var plain := FoePic.new()
	var pirate := FoeInfo.of("res://data/ships/pirate_raider.json")
	plain.show_foe(pirate["ship"], _ship(), pirate["line"], pirate["boss"])
	eq(plain.size.y, FoePic.BOX.y, "any other ship keeps the old card")
	pic.free()
	plain.free()


func test_flagships_never_flee_and_yield_with_an_offer_of_their_own() -> void:
	var styles: Dictionary = Morale.config()["styles"]
	for race in MAJORS:
		var ship = Session.load_ship(Flagships.design_of(race))
		var style := str(ship.get_meta("ai")["morale"])
		eq(style, "flagship_" + race, race + ": a style of its own")
		check(styles.has(style), "%s: style %s exists" % [race, style])
		eq(float(styles[style]["flee"]), 0.0, race + ": never flees")
		check(float(styles[style]["surrender"]) > 0.0, race + ": yields, or no fight of a very big hull would end")
		var o: Dictionary = styles[style]["offer"]
		check(o["credits"][0] > 0 and o["extra"].size() == 1 and o.has("part_chance"), race + ": a race-fitting offer of its own")
		var line: float = float(ship.get_meta("ai")["break_structure"])
		check(line > 0.5 and line < 1.0, "%s: it yields at its own structure line (%.3f)" % [race, line])
		var lines: Dictionary = Morale.config()["lines"]["flagship_" + race]
		for k in ["hail", "surrender", "flee", "refuse"]:
			check(lines[k] is Array and not lines[k].is_empty(), "%s: %s lines" % [race, k])
	var s := Session.new()
	s.start(Session.load_ship("res://data/ships/starter_courier.json"), Session.load_ship(Flagships.design_of("human")), 3)
	eq(s.morale.captain, "Reyne", "the Commodore speaks for the ship")
	eq(s.morale.speaker(), "Commodore Reyne of the Concord Ascendant", "as the Commodore of the Concord Ascendant")
	var offer := s.morale._roll_offer()
	check(offer.has("credits") and offer["credits"] >= 90 and offer.has("missile"), "and her surrender offer is her own (%s)" % str(offer))
	eq(s.morale.break_at, float(s.arena.ships[1].ship.get_meta("ai")["break_structure"]), "she breaks at her own line")


# --- the fights end -------------------------------------------------------------------------------------------------

## One fight of `race`'s flagship against the player-like ship of its stage, both pilots on the AI, as the balance tools run it: the end state and the seconds.
func _fight(race: String, seed_value: int) -> Dictionary:
	var player: Ship = Standoff.build_player(int(Flagships.entry(race)["stage"]))
	var enemy: Ship = Session.load_ship(Flagships.design_of(race))
	var sim := ShipSim.new()
	sim.ships = [player, enemy]
	Jobs.spawn_crew(player)
	var sess := Session.new()
	sess.start(player, enemy, 1 + seed_value * 7919)
	var pilot := PilotAI.new(sess.arena, Session.PLAYER, Session.ENEMY, {"aim_skill": float(Threat.config()["player_aim"])})
	pilot.foe_morale = sess.morale
	var n := 0
	while sess.state() == "fighting" and n < 180 * 60:
		if n % 3 == 0:
			pilot.think(3.0 / 60.0)
		if sess.morale.state == "offering":
			sess.accept_surrender()
		sess.ai.think(1.0 / 60.0)
		sess.arena.step(1.0 / 60.0)
		sess.morale.tick(1.0 / 60.0)
		n += 1
		if n % 12 == 0:
			sim.step(12.0 / 60.0)
	var out := {"state": sess.state(), "t": n / 60.0}
	sim.free()
	return out


func test_each_flagship_fight_ends_within_180_seconds() -> void:  # one seed each keeps the suite short; tests/tool_flagships.gd runs the full bench
	for race in MAJORS:
		var r := _fight(race, 0)
		check(r["state"] != "fighting", "%s: the fight ends (%s after %.0f s)" % [race, r["state"], r["t"]])
