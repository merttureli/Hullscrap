extends "res://tests/base_test.gd"
## Beta 4 content and Ledger fixes (topic fixes5): louder regions, story events that fade when skipped, the Ledger's words and the
## spare-reactor warning, loot nobody could find (suits, the plasma rifle, void crystal), mods in lockers, discoveries by kind,
## people aboard, the Baron's Yacht promise, the Boneyard's fuel station.

const Events = preload("res://scripts/space/events.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Advisor = preload("res://scripts/sim/advisor.gd")
const Site = preload("res://scripts/board/site.gd")
const Loot = preload("res://scripts/board/loot.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Shops = preload("res://scripts/space/shops.gd")
const Content = preload("res://scripts/data/content.gd")
const HelpPanel = preload("res://scripts/ui/help_panel.gd")
const Regions = preload("res://scripts/space/regions.gd")


func _ev(id: String, type: String, requires: Dictionary = {}, weight := 10, once := false) -> Dictionary:
	return {"id": id, "type": type, "weight": weight, "once": once, "requires": requires, "text": "Text of " + id,
		"choices": [{"text": "Go", "outcomes": [{"weight": 100, "text": "Done", "effects": {}}]}]}


func _camp(list: Array, seed_value := 1) -> Campaign:
	var e := Events.new("res://tests")
	for x in list:
		e.add(x, "test.json")
	e._index_recruiters()
	var c := Campaign.new(seed_value, {}, e)
	c.cfg = c.cfg.duplicate(true)
	return c


# --- regions ----------------------------------------------------------------------------------------------------

func test_a_region_weight_makes_the_homeland_louder() -> void:
	check(float(Campaign.config().get("region_weight", 1.0)) > 1.0, "drift.json has a region_weight above 1")
	var share := {}
	for w in [1.0, 20.0]:
		var c := _camp([_ev("generic", "wreck_field", {}, 20), _ev("homeland", "wreck_field", {"region": "clan_space"}, 5), _ev("elsewhere", "wreck_field", {"region": "boneyard"}, 5)])
		c.cfg["region_weight"] = w
		var n := 0
		for i in 400:
			if c.events.pick(c, {"id": "n1", "type": "wreck_field", "place": ""})["id"] == "homeland":
				n += 1
		share[w] = n
	check(share[20.0] > share[1.0] * 3, "an event of the region is drawn far more often with the weight (%d against %d)" % [share[20.0], share[1.0]])


# --- story events fade --------------------------------------------------------------------------------------------

func test_a_skipped_story_event_comes_back_less_often() -> void:
	var c := _camp([_ev("story", "wreck_field", {}, 200, true), _ev("plain", "wreck_field", {}, 10)])
	var ev: Dictionary = c.events.get_event("story")
	eq(Events.fade_weight(ev, 200.0, c), 200.0, "unseen: its full weight")
	c.events.pick(c, {"id": "n1", "type": "wreck_field", "place": ""}, null, func(e): return e["id"] == "story")
	eq(int(c.story_views.get("story", 0)), 1, "a view is counted")
	eq(Events.fade_weight(ev, 200.0, c), 100.0, "one view halves it")
	c.story_views["story"] = 3
	eq(Events.fade_weight(ev, 200.0, c), 25.0, "three views: an eighth")
	c.story_views["story"] = 30
	eq(Events.fade_weight(ev, 200.0, c), 1.0, "never under 1")
	var light: Dictionary = c.events.get_event("plain")
	c.story_views["plain"] = 5
	eq(Events.fade_weight(light, 10.0, c), 10.0, "an ordinary event does not fade")
	var twice := _ev("heavy_repeatable", "wreck_field", {}, 300, false)
	c.story_views["heavy_repeatable"] = 2
	eq(Events.fade_weight(twice, 300.0, c), 300.0, "nor does one that is not `once`")


func test_the_views_are_saved_and_an_old_save_has_none() -> void:
	check(Campaign.VERSION >= 12, "story_views came with save version 12")
	var c := Campaign.new(5)
	c.story_views = {"doors_briefing": 2}
	var d = JSON.parse_string(JSON.stringify(c.to_dict()))
	var back := Campaign.new(2)
	eq(back.load_dict(d), "", "loads")
	eq(back.story_views, {"doors_briefing": 2}, "the views come back")
	d.erase("story_views")
	d["version"] = 11
	var old := Campaign.new(3)
	old.story_views = {"x": 1}
	eq(old.load_dict(d), "", "a version 11 save still loads")
	eq(old.story_views, {}, "with none")


# --- the Ledger ---------------------------------------------------------------------------------------------------

func test_the_ledger_says_what_the_game_does() -> void:
	var a := Advisor.new()
	var goals: Dictionary = {}
	for g in a.goals(1):
		goals[g["id"]] = g
	check(str(goals["s1_intake"]["why"]).contains("net mouth Ma gave you") and not str(goals["s1_intake"]["why"]).contains("Craft a net mouth"), "the intake goal: Ma gave you one")
	check(str(goals["s1_cover"]["why"]).contains("one medbay") and not str(goals["s1_cover"]["why"]).contains("bed"), "the cover goal: a medbay, not a bed")
	var tip := str(a.tip_words("first_fight")["text"])
	check(tip.contains("J spools the jump drive (10 s)") and tip.contains("engines or helm"), "the first fight tip says what J does")
	check(tip.contains("one gun") and tip.length() <= 130, "and that a pirate with one gun breaks when it is knocked out (%d characters)" % tip.length())


func test_the_ledger_warns_of_one_reactor_and_no_spare() -> void:
	var a := Advisor.new()
	check(Advisor.WARNINGS.has("reactor") and a.warning_text("reactor") == "One reactor and no spare. If it's wrecked, you're adrift.", "the warning exists")
	var ids := func(v: Dictionary) -> Array: return a.conditions(v).map(func(c): return c["id"])
	check(ids.call({"stage": 1, "reactors": 1, "spare_reactor": false}).has("reactor"), "one reactor, no spare: warned")
	check(not ids.call({"stage": 1, "reactors": 1, "spare_reactor": true}).has("reactor"), "a spare in the hold: no warning")
	check(not ids.call({"stage": 1, "reactors": 2, "spare_reactor": false}).has("reactor"), "two reactors: no warning")


func test_measure_counts_reactors_and_the_spare_in_the_hold() -> void:
	var Ship = load("res://scripts/ship/ship.gd")
	var ship = Ship.from_design("res://data/ships/starter_rustbucket.json")
	var v := Advisor.measure(ship, null)
	check(int(v["reactors"]) >= 1, "the Rustbucket has a reactor")
	var before := bool(v["spare_reactor"])
	ship.inventory.add("reactor_mk1", 1)
	v = Advisor.measure(ship, null)
	check(bool(v["spare_reactor"]), "a reactor in the hold is a spare (it was %s before)" % str(before))


# --- debug keys on the help screen ----------------------------------------------------------------------------------

func test_the_debug_row_of_the_help_screen_is_marked() -> void:
	var marked := 0
	for col in HelpPanel.COLUMNS:
		for sec in col:
			for row in sec[1]:
				if row.size() >= 3 and str(row[0]) == "U":
					marked += 1
	eq(marked, 1, "the U row is marked debug (a release build drops it)")
	check(HelpPanel.keys_text().contains("U") == OS.is_debug_build() or not OS.is_debug_build(), "a debug build lists it")
	var j := ""
	for col in HelpPanel.COLUMNS:
		for sec in col:
			for row in sec[1]:
				if str(sec[0]).begins_with("COMBAT") and str(row[0]) == "J":
					j = str(row[1])
	check(j.contains("10 s") and j.contains("engines or helm"), "the combat J row says what it does")


# --- loot nobody could find ---------------------------------------------------------------------------------------

func test_suits_the_plasma_rifle_and_void_crystal_have_a_source() -> void:
	var cfg := Site.config()
	for room in ["engineering", "command"]:
		var items: Array = cfg["tables"][room].map(func(o): return str(o["item"]))
		check(items.has("exosuit") and items.has("salamander_suit"), "the %s table holds both suits" % room)
	var weapon := Arms.item_weapon("plasma_rifle")
	check(weapon != "" and not Arms.weapon(weapon).is_empty(), "the plasma rifle stands for a real hand weapon (%s)" % weapon)
	for item in cfg["combat"]["hand_items"]:
		check(Content.has("items", str(item)), "hand item %s is an item" % item)
		check(not Arms.weapon(str(cfg["combat"]["hand_items"][item])).is_empty(), "and its weapon %s exists" % cfg["combat"]["hand_items"][item])
	check(Arms.item_weapon("doorbuster") == "doorbuster" and Arms.item_weapon("flare_gun") == "flare_gun", "the pirate's and the scavenger's guns can be carried")
	var Ev = load("res://scripts/space/events.gd").new()
	var givers := []
	for id in Ev.order:
		if JSON.stringify(Ev.events[id]).contains("void_crystal"):
			givers.append(id)
	check(not givers.is_empty(), "an event hands out void crystal (%s)" % str(givers))
	for id in givers:
		check(str(Ev.events[id].get("type", "")) == "hollow" and int(Ev.events[id]["requires"].get("stage_min", 0)) >= 5, "%s: a Hollow event from stage 5" % id)
	var users := 0
	for rid in Content.ids("recipes"):
		if JSON.stringify(Content.entry("recipes", rid)).contains("void_crystal"):
			users += 1
	check(users >= 2, "and two recipes need it")


func test_beaten_foes_leave_their_weapon_sometimes() -> void:
	var Ship = load("res://scripts/ship/ship.gd")
	var Boarding = load("res://scripts/board/boarding.gd")
	var Foes = load("res://scripts/board/foes.gd")
	var dropped := 0
	var foes := 0
	for seed_value in 12:
		var ship = Ship.from_design("res://data/ships/starter_rustbucket.json")
		var s = Boarding.start(null, null, "p%d" % seed_value, {"kind": "station"}, ship)
		s.site = Site.make(300 + seed_value, "station", {"faction": "clans"})
		s.foes = Foes.new(s)
		s.foes.spawn_site({})
		for f in s.foes.list:
			if f["kind"] in ["scavenger", "pirate"]:
				foes += 1
				s.foes.hurt(f, 9999.0, f["m"].pos)
		dropped += ship.inventory.count("flare_gun") + ship.inventory.count("doorbuster")
	check(foes > 10, "foes to beat (%d)" % foes)
	check(dropped > 0 and dropped < foes, "some leave a weapon, not all (%d of %d)" % [dropped, foes])


# --- mods -----------------------------------------------------------------------------------------------------------

func test_lockers_and_cabinets_may_hold_a_mod_and_the_shop_sells_mark_one_more_often() -> void:
	var props: Dictionary = Site.config()["props"]
	for p in ["locker", "cabinet"]:
		check(props[p].get("bonus", []).any(func(o): return str(o["item"]) == "mod_low"), "a %s can hold a mod (Mk I or II)" % p)
	var found := 0
	for s in 40:
		var site = Site.make(500 + s, "station", {"faction": "clans"})
		for p in site.props:
			if p["loot"] and p["prop"] in ["locker", "cabinet"]:
				for k in Loot.resolve(site, int(p["id"]), {"tier": 1, "stage": 2})["items"]:
					if str(k).ends_with("_mk1") and (str(k).begins_with("spotter") or str(k).begins_with("salvage") or str(k).begins_with("overcharge")):
						found += 1
	check(found >= 5, "lockers and cabinets gave mods (%d in 40 stations)" % found)
	var cfg := Campaign.config()
	var pool := Shops.unique_pool(cfg, [])
	check(pool.has("mod") and pool.has("mod1"), "the shop pool has Mk I and the others")
	check(pool["mod1"].all(func(id): return str(id).ends_with("_mk1")) and pool["mod"].all(func(id): return not str(id).ends_with("_mk1")), "split by tier")
	check(float(cfg["shops"]["kinds"]["mod1"]) > float(cfg["shops"]["kinds"]["mod"]), "Mk I is rolled more often")


# --- discoveries ------------------------------------------------------------------------------------------------------

func test_discoveries_pick_the_kind_first_and_a_room_that_fits() -> void:
	var seen := {"room": 0, "terminal": 0, "body": 0}
	for kind in ["derelict", "station", "nest", "wreck"]:
		for s in 40:
			var site = Site.make(1000 + s * 37, kind, {"faction": "clans"})
			var rooms := {}
			for m in site.marks:
				seen[str(m["kind"])] += 1
				check(not rooms.has(m["room"]), "one mark to a room")
				rooms[m["room"]] = true
				if str(m["kind"]) != "room":
					check(int(m["prop"]) >= 0 and str(site.props[int(m["prop"])]["prop"]) == str(m["kind"]) and int(site.props[int(m["prop"])]["room"]) == int(m["room"]), "a %s mark is on a %s of its room" % [m["kind"], m["kind"]])
	var total: int = seen["room"] + seen["terminal"] + seen["body"]
	check(total > 100, "marks to count (%d)" % total)
	check(float(seen["room"]) / total < 0.6, "strange rooms are no longer most of them (%s)" % str(seen))
	check(seen["terminal"] > 0 and seen["body"] > 0, "and both other kinds appear")


func test_wrecks_have_a_discovery_and_derelicts_more_people() -> void:
	var wreck := 0
	for s in 40:
		wreck += Site.make(2000 + s, "wreck", {"faction": "clans"}).marks.size()
	check(wreck > 0, "a wreck can hold a discovery (%d in 40)" % wreck)
	eq(Site.config()["marks"]["count"]["wreck"].map(func(x): return int(x)), [0, 1], "wrecks: 0 or 1")
	var none: float = Site.config()["people"]["kinds"]["derelict"]["count"]["0"]
	eq(none, 0.6, "a derelict has no one aboard 60% of the time")


# --- promises and stations ---------------------------------------------------------------------------------------------

func test_the_barons_duel_promises_no_yacht() -> void:
	var duel: Dictionary = Events.shared().get_event("baron_duel")
	check(not JSON.stringify(duel).contains("ship_barons_yacht"), "no unlock of a ship that does not exist")
	check(JSON.stringify(duel).contains("sterling"), "Sterling still joins")


func test_the_boneyard_has_a_fuel_station() -> void:
	var r := Regions.get_region("boneyard")
	var ids: Array = r["places"].filter(func(p): return str(p["type"]) == "station").map(func(p): return str(p["id"]))
	check(not ids.is_empty(), "the Boneyard has a station")
	for id in ids:
		check(Campaign.config()["fuel"]["stations"].has(id), "%s sells fuel" % id)
	check(not Regions.station(ids[0], Campaign.config()).get("stock", {}).is_empty(), "and has a stock")
