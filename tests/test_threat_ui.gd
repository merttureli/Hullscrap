extends "res://tests/base_test.gd"
## Danger you can read before you choose it (docs/MECHANICS_REVIEW.md, round 3): the foe of a place is rolled once and kept
## (Campaign.foe_for), the event panel tags fight choices with its threat, the fight opens with a banner and skulls on the
## enemy's schematic, and a dangerous enemy pays more parts at the salvage (Salvage.event_for, data/drift.json loot.threat_picks).

const Campaign = preload("res://scripts/space/campaign.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const CombatView = preload("res://scripts/combat/combat_view.gd")
const EventPanel = preload("res://scripts/ui/event_panel.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
const Salvage = preload("res://scripts/space/salvage.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Skulls = preload("res://scripts/ui/skulls.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const RAIDER := "res://data/ships/pirate_raider.json"


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	return s


## A big generated enemy: plenty of different parts to cut out.
func _wreck() -> Ship:
	return Shipgen.build("wardens", "large", 7, 300.0)


func _distinct(enemy: Ship) -> int:
	var seen := {}
	for id in Salvage.parts(enemy):
		seen[id] = true
	return seen.size()


func _cut_rows(ev: Dictionary) -> int:
	var n := 0
	for ch in ev["choices"]:
		if str(ch["text"]).begins_with("Cut out"):
			n += 1
	return n


# --- the foe of a place --------------------------------------------------------------------------------

func test_foe_for_is_deterministic_cached_and_leaves_the_campaign_rng_alone() -> void:
	var c := Campaign.new(5)
	var here := c.current
	var rng_before := c.rng.state
	var a := c.foe_for(here, "pirate")
	check(Shipgen.is_spec(a), "a generated raider: " + a)
	eq(c.rng.state, rng_before, "rolling it did not move the campaign rng")
	eq(c.foe_for(here, "pirate"), a, "asked again, the same foe")
	eq(Campaign.new(5).foe_for(here, "pirate"), a, "the same seed and place give the same foe")
	var others := {}
	for s in [6, 7, 8, 9, 10]:
		others[Campaign.new(s).foe_for(Campaign.new(s).current, "pirate")] = true
	check(others.size() > 1, "other seeds give other foes")
	c.jumps = 30
	eq(c.foe_for(here, "pirate"), a, "kept, with the budget it was first rolled at")
	var late := Campaign.new(5)
	late.jumps = 30
	var late_spec := late.foe_for(here, "pirate")
	check(late_spec != a and float(late_spec.split(":")[4]) > 3.0 * float(a.split(":")[4]), "a place first met late has the late budget (%s, %s)" % [a, late_spec])
	check(c.foe_for(here, "patrol").begins_with("gen:concord:"), "each kind of fight has its own foe")
	eq(c.foes.size(), 2, "two foes kept")
	eq(c.rng.state, rng_before, "and the campaign rng is still where it was")


func test_the_foes_are_saved_and_an_old_save_starts_with_none() -> void:
	var c := Campaign.new(5)
	var a := c.foe_for(c.current, "pirate")
	var text := JSON.stringify(c.to_dict())
	var d := Campaign.new(99)
	eq(d.load_dict(JSON.parse_string(text)), "", "loads")
	eq(d.foes, c.foes, "the foes survived")
	d.jumps = 30
	eq(d.foe_for(d.current, "pirate"), a, "and the loaded foe is the one that was rated")
	eq(JSON.stringify(Campaign.new(99).to_dict()["foes"]), "{}", "a new campaign has none")
	var old: Dictionary = JSON.parse_string(text)
	old.erase("foes")
	old["version"] = 5
	var e := Campaign.new(1)
	eq(e.load_dict(old), "", "a version 5 save loads")
	eq(e.foes, {}, "with no foe rolled")
	check(Shipgen.is_spec(e.foe_for(e.current, "pirate")), "they roll when asked")
	old["foes"] = {"x/y/pirate": "gen:rustfangs:small:1:100", "bad": 7}
	var f := Campaign.new(1)
	eq(f.load_dict(old), "", "a save with a stray entry loads")
	eq(f.foes, {"x/y/pirate": "gen:rustfangs:small:1:100"}, "keeping only the text ones")


func test_fight_path_tier_returns_the_rated_foe() -> void:
	var c := Campaign.new(4)
	var rng_before := c.rng.state
	var path := c.fight_path("tier", "pirate")
	eq(path, c.foe_for(c.current, "pirate"), "fight_path(tier) is the foe of the node")
	eq(c.fight_path("tier", "pirate"), path, "every time")
	eq(c.fight_path("tier", "empty"), path, "any non-patrol place sends the pirates")
	check(c.fight_path("tier", "patrol").begins_with("gen:concord:"), "a patrol sends the Concord")
	eq(c.fight_path("tier", "patrol"), c.foe_for(c.current, "patrol"), "and keeps it")
	eq(c.fight_path("pirate_raider", "pirate"), RAIDER, "a named design stays what it is")
	eq(c.rng.state, rng_before, "no fight_path moved the campaign rng")
	c.jumps = 16
	var rammer := c.fight_path("tier", "pirate")
	check(rammer.ends_with(":ram"), "two missed payments send a rammer: " + rammer)
	eq(c.fight_path("tier", "pirate"), rammer, "and it is kept")


# --- the bands and tags -------------------------------------------------------------------------------

func test_the_skull_colours_and_the_tag_text() -> void:
	eq([Skulls.color(1), Skulls.color(2)], [Skulls.DIM, Skulls.DIM], "1 and 2 skulls are dim")
	eq(Skulls.color(3), Skulls.AMBER, "3 is amber")
	eq([Skulls.color(4), Skulls.color(5)], [Skulls.RED, Skulls.RED], "4 and 5 are red")
	eq(Skulls.tag(4), "[Threat 4/5]", "the tag")
	eq(Skulls.tag(2, true), "[may fight: Threat 2/5]", "a choice that may fight")
	check(Skulls.width(0.6) < Skulls.width(), "small skulls are narrower")


## An event with four choices: a sure fight with the tier foe, no fight, a maybe-fight, and a named design.
func _event() -> Dictionary:
	var fight := func(who): return {"weight": 1, "text": "Guns.", "effects": {"fight": who}}
	var calm := {"weight": 1, "text": "Quiet.", "effects": {"items": {"credits": 5}}}
	return {"id": "t_threat", "type": "pirate", "title": "Raiders", "text": "They bristle.", "choices": [
		{"text": "Run the gauntlet.", "outcomes": [fight.call("tier")]},
		{"text": "Talk.", "outcomes": [calm]},
		{"text": "Try the sweet talk first.", "outcomes": [calm, fight.call("tier")]},
		{"text": "Take on the old raider.", "outcomes": [fight.call("pirate_raider")]}]}


class FakeCombat extends Node:
	signal finished(result: Dictionary)
	var active := false

	func enter(_path := "") -> String:
		active = true
		return ""


func _screen() -> Dictionary:
	var sim := ShipSim.new()
	sim.ships = [_ship()]
	var fake := FakeCombat.new()
	var map := MapView.new()
	map.sim = sim
	map.combat = fake
	fake.finished.connect(map._on_fight_finished)
	map.size = Vector2(1600.0, 900.0)
	map.new_seed = 5
	map.open()
	map.event_panel.size = map.size
	map.station_panel.size = map.size
	map.event_panel.close()
	return {"map": map, "sim": sim, "fake": fake}


func _free(d: Dictionary) -> void:
	d["map"].free()
	d["sim"].free()
	d["fake"].free()


func test_the_event_panel_tags_fight_choices_with_the_threat() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var c: Campaign = map.campaign
	var ship = map.ship()
	var rng_before := c.rng.state
	map.event_panel.open_event(_event())
	var view: Array = map.event_panel.view
	eq(view.size(), 4, "four choices")
	eq(c.rng.state, rng_before, "rating the fights moved no campaign rng")
	var foe := c.foe_for(c.current, "pirate" if str(c.node(c.current)["type"]) != "patrol" else "patrol")
	var tier_skulls := int(Shipgen.threat(Session.load_ship(foe), ship)["skulls"])
	var raider_skulls := int(Shipgen.threat(Session.load_ship(RAIDER), ship)["skulls"])
	check(tier_skulls >= 1 and tier_skulls <= 5, "the tier foe has a rating: %d" % tier_skulls)
	eq(view[0].get("tag", ""), "[Threat %d/5]" % tier_skulls, "a sure fight with the tier foe")
	eq(view[0].get("threat", 0), tier_skulls, "with its skulls")
	check(not view[1].has("tag") and not view[1].has("lines"), "a choice with no fight has no tag")
	eq(view[2].get("tag", ""), "[may fight: Threat %d/5]" % tier_skulls, "a maybe-fight says so")
	eq(view[3].get("tag", ""), "[Threat %d/5]" % raider_skulls, "a named design is rated too")
	eq(c.fight_path("tier", str(c.node(c.current)["type"])), foe, "and fight_path hands out that foe")
	check(c.foes.size() >= 1, "the foe was rolled when the page opened")
	var lines: Array = view[0]["lines"]
	check(lines.size() >= 1 and str(lines[lines.size() - 1]).ends_with(view[0]["tag"]), "the tag ends the text of its row: " + str(lines))
	check(str(lines[0]).begins_with("Run the gauntlet."), "after the choice's own words")
	var lay: Dictionary = map.event_panel.layout()
	eq(lay["rows"].size(), 4, "the layout has a row each")
	check(lay["rows"][0].size.y >= 40.0, "the tagged row is tall enough")
	_free(d)


func test_the_panel_keeps_ratings_until_the_ship_changes() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	map.event_panel.open_event(_event())
	var kept: int = EventPanel._rated.size()
	check(kept >= 2, "the tier foe and the raider were rated (%d)" % kept)
	map.event_panel.open_event(_event())
	eq(EventPanel._rated.size(), kept, "opening it again rates nothing new")
	var ship = map.ship()
	var key := EventPanel.ship_key(ship)
	eq(EventPanel.ship_key(ship), key, "the ship's key is steady")
	for uid in ship.components.instances.keys():
		if ship.components.instances[uid]["id"] == "shield_mk1" or str(ship.components.def(ship.components.instances[uid]["id"]).get("family", "")) == "weapon":
			ship.components.wreck(uid)
			break
	check(EventPanel.ship_key(ship) != key, "losing a part changes it")
	map.event_panel.open_event(_event())
	check(EventPanel._rated.size() > kept, "and the foes are rated again")
	_free(d)


func test_a_page_with_no_fight_has_no_tags() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var ev := {"id": "t_calm", "type": "pirate", "title": "Calm", "text": "Nothing.", "choices": [{"text": "Leave.", "outcomes": [{"weight": 1, "text": "", "effects": {}}]}]}
	map.event_panel.open_event(ev)
	check(map.event_panel.view.all(func(v): return not v.has("tag")), "no tag anywhere")
	_free(d)


# --- the fight ------------------------------------------------------------------------------------------

func test_the_session_rates_the_enemy_once_and_names_it_in_a_banner() -> void:
	var player := _ship()
	var enemy := Shipgen.build("rustfangs", "medium", 3, 150.0)
	var want := int(Shipgen.threat(Shipgen.build("rustfangs", "medium", 3, 150.0), player)["skulls"])
	var s := Session.new()
	s.start(player, enemy, enemy.rng_seed)
	eq(s.threat, want, "the session stored the skulls against the player's ship")
	eq(s.threat_banner(), "%s: Threat %d/5" % [enemy.name, want], "the banner names the enemy and its threat")
	for i in 120:
		s.tick(Session.STEP)
	eq(s.threat_banner(), "%s: Threat %d/5" % [enemy.name, want], "two seconds in it is still up")
	for i in 90:
		s.tick(Session.STEP)
	eq(s.threat_banner(), "", "after 3 s it is gone")
	eq(s.threat, want, "and the rating stayed")


func test_the_result_of_a_fight_carries_the_threat_into_the_campaign() -> void:
	var sim := ShipSim.new()
	var build := BuildMode.new()
	build.sim = sim
	build.build_on = false
	var view := CombatView.new()
	view.sim = sim
	view.build = build
	var k := InputEventKey.new()
	k.keycode = KEY_K
	k.pressed = true
	view._unhandled_input(k)
	check(view.active, "a fight")
	var want: int = view.session.threat
	check(want >= 1 and want <= 5, "the pirate has a rating: %d" % want)
	var got := []
	view.finished.connect(func(r): got.append(r))
	view.leave()
	eq(got.size(), 1, "the map was told")
	eq(got[0].get("threat", -1), want, "the result carries the threat")
	var c := Campaign.new(1)
	var ship := _ship()
	eq(c.fight_done(got[0], ship)["threat"], want, "fight_done hands it on")
	eq(c.fight_done({"state": "won"}, ship)["threat"], 0, "0 when the result has none")
	view.free()
	build.free()
	sim.free()


# --- salvage by threat -------------------------------------------------------------------------------------

func test_a_dangerous_enemy_gives_more_parts_to_cut() -> void:
	var enemy := _wreck()
	check(_distinct(enemy) >= 7, "the wreck has enough different parts (%d)" % _distinct(enemy))
	var ship := _ship()
	var rows := {}
	for threat in [0, 1, 3, 4, 5]:
		rows[threat] = [_cut_rows(Salvage.event_for(enemy, "won", Campaign.new(3), ship, null, threat)), _cut_rows(Salvage.event_for(enemy, "captured", Campaign.new(3), ship, null, threat))]
	eq(rows[0], [3, 4], "no threat known: 3 won, 4 captured")
	eq(rows[1], [3, 4], "1 skull: the same")
	eq(rows[3], [3, 4], "3 skulls: the same")
	eq(rows[4], [4, 5], "4 skulls: one more")
	eq(rows[5], [5, 6], "5 skulls: two more")
	var plain := Salvage.event_for(enemy, "won", Campaign.new(3), ship, null, 3)
	var danger := Salvage.event_for(enemy, "won", Campaign.new(3), ship, null, 5)
	check(not str(plain["text"]).contains(Salvage.DANGEROUS_TEXT.strip_edges()), "a tame wreck has no extra words")
	check(str(danger["text"]).ends_with("She was dangerous. There's more worth cutting."), "a dangerous one says so: " + str(danger["text"]))
	check(str(Salvage.event_for(enemy, "captured", Campaign.new(3), ship, null, 4)["text"]).contains("She was dangerous"), "captured too")
	var strip := 0
	for ch in danger["choices"]:
		strip += int(str(ch["text"]).begins_with("Strip"))
	eq(strip, 1, "the strip row is still there on a won fight")


func test_the_hollow_rule_still_comes_first_and_a_small_wreck_has_no_bonus() -> void:
	var enemy := _wreck()
	var ship := _ship()
	var ghost := Salvage.event_for(enemy, "captured", Campaign.new(3), ship, true, 5)
	eq(ghost["choices"].size(), 1, "a ghost ship offers only the strip row, whatever its threat")
	check(str(ghost["choices"][0]["text"]).begins_with("Strip"), "which is the strip row")
	check(not str(ghost["text"]).contains("dangerous"), "and no word of danger")
	var tiny := Ship.from_design(RAIDER)
	for uid in tiny.components.instances.keys():
		if not ["laser_mk1", "reactor_scrap_mk1"].has(tiny.components.instances[uid]["id"]):
			tiny.components.remove_uid(uid)
	var n := _distinct(tiny)
	eq(n, 2, "a wreck with two kinds of part")
	var ev := Salvage.event_for(tiny, "won", Campaign.new(3), ship, null, 5)
	eq(_cut_rows(ev), n, "offers them all")
	check(not str(ev["text"]).contains("dangerous"), "no extra words when the bonus gave no row")


func test_the_numbers_come_from_the_data() -> void:
	var c := Campaign.new(3)
	var table: Dictionary = c.cfg["loot"]["threat_picks"]
	eq([int(table["4"]), int(table["5"]), table.size()], [1, 2, 2], "data/drift.json loot.threat_picks")
	eq([Salvage.picks_for("won", 5, c), Salvage.picks_for("captured", 5, c), Salvage.picks_for("won", 2, c)], [5, 6, 3], "picks_for")
	var tuned := Campaign.new(3, Campaign.config().duplicate(true))
	tuned.cfg["loot"]["threat_picks"] = {"3": 3}
	eq(Salvage.picks_for("won", 3, tuned), 6, "a tuned table is read")
	tuned.cfg["loot"].erase("threat_picks")
	eq(Salvage.picks_for("won", 5, tuned), 3, "no table, no bonus")


func test_a_five_skull_win_on_the_map_offers_five_parts() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	map.event_panel.open_event(map.campaign.events.get_event("repo_fight"))
	map.event_panel.choose(0)
	map.event_panel.proceed()
	d["fake"].finished.emit({"state": "won", "enemy": _wreck(), "hull": 100.0, "hull_max": 100.0, "threat": 5})
	map.event_panel.proceed()
	eq(map.event_panel.event.get("id", ""), "salvage", "the salvage pick follows")
	eq(_cut_rows(map.event_panel.event), 5, "five parts to cut out")
	check(str(map.event_panel.event["text"]).contains("She was dangerous"), "and the page says why")
	_free(d)


# --- in sector space -----------------------------------------------------------------------------------------

func test_a_poi_rates_the_foe_its_fight_will_send() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var c: Campaign = map.campaign
	var sector = c.current_sector()
	var poi: Dictionary = sector.pois[0]
	poi["event_type"] = "patrol"
	poi["enemy"] = ""
	var design: String = sector.fight_design(c, poi["id"], "tier")
	check(design.begins_with("gen:concord:"), "a patrol POI sends the Concord: " + design)
	eq(design, c.fight_path("tier", "patrol"), "the same foe the campaign keeps for that kind here")
	eq(sector.fight_design(c, "nope", "tier"), "", "an unknown POI sends nothing")
	eq(sector.fight_spawn(c, poi["id"], "tier")["design"], design, "and fight_spawn hands out that design")
	map._poi_sector = sector
	map._poi = poi["id"]
	eq(map.fight_design("tier"), design, "the map rates the POI's foe while its event is up")
	eq(map.fight_design("pirate_raider"), RAIDER, "a named design stays a file")
	map.event_panel.open_event(_event())
	var skulls := int(Shipgen.threat(Session.load_ship(design), map.ship())["skulls"])
	eq(map.event_panel.view[0].get("tag", ""), "[Threat %d/5]" % skulls, "so the tag on its choice rates that foe")
	map._forget_poi()
	_free(d)
