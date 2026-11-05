extends "res://tests/base_test.gd"
## Away-team expeditions (scripts/space/expedition.gd, data/expeditions.json, data/events/expeditions_*.json): the sites in sector space, the team, the team
## requires, what a lost member takes with them, the content, the reward tiers and saving mid-run.

const Expedition = preload("res://scripts/space/expedition.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Regions = preload("res://scripts/space/regions.gd")
const Events = preload("res://scripts/space/events.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Sim = preload("res://tests/expedition_sim.gd")
const TeamPicker = preload("res://scripts/ui/team_picker.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const KINDS := ["planet", "base", "ruin", "platform"]


func _ship(n := 3) -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	for i in n:
		s.crew.append(CrewMember.new("Hand%d" % i, Vector2(10 + i, 10), ["basalt", "fenn", "human", "emberkin"][i % 4]))
	return s


func _poi(kind: String) -> Dictionary:
	return {"id": "t", "type": "exp_" + kind, "name": "Site"}


func _sites(seed_n: int, region: String, node_type: String) -> Dictionary:
	var counts := {}
	var data := Regions.get_region(region)
	for i in 60:
		var s = Sector.generate(seed_n + i, {"id": "n%02d" % (i % 9), "type": node_type, "name": ""}, region, {}, data)
		for p in s.pois:
			if str(p["type"]).begins_with("exp_"):
				counts[p["type"]] = int(counts.get(p["type"], 0)) + 1
	return counts


func test_the_sites_place_with_region_weights_and_the_same_seed_makes_the_same_sector() -> void:
	var cfg: Dictionary = Sector.config()
	for k in KINDS:
		var t: Dictionary = cfg["poi_types"]["exp_" + k]
		check(bool(t["manual"]) and float(t["reach"]) > 0.0, "%s is a manual POI with a reach" % k)
		check(Expedition.kinds().has(k), "%s is a kind" % k)
	var groves := _sites(100, "sporeling_groves", "empty")
	var yards := _sites(100, "gauntling_scrapyards", "empty")
	check(int(groves.get("exp_planet", 0)) > int(yards.get("exp_planet", 0)), "the groves have more planets than the scrapyards")
	check(int(yards.get("exp_base", 0)) > int(groves.get("exp_base", 0)), "the scrapyards have more bases than the groves")
	var any := 0
	for k in groves:
		any += int(groves[k])
	check(any > 20, "sites are common enough to meet (%d in 60 sectors)" % any)
	var a = Sector.generate(7, {"id": "n03", "type": "empty", "name": ""}, "sporeling_groves", {}, Regions.get_region("sporeling_groves"))
	var b = Sector.generate(7, {"id": "n03", "type": "empty", "name": ""}, "sporeling_groves", {}, Regions.get_region("sporeling_groves"))
	eq(a.pois.map(func(p): return [p["type"], p["pos"]]), b.pois.map(func(p): return [p["type"], p["pos"]]), "same seed, same sector")


func test_a_site_never_triggers_alone_and_waits_for_the_ship_to_be_near() -> void:
	var s = Sector.generate(9, {"id": "n01", "type": "empty", "name": ""}, "boneyard", {}, Regions.get_region("boneyard"))
	s.pois.append({"id": "px", "type": "exp_ruin", "name": "Ice ruin", "pos": Vector2(5000, 5000), "visibility": "signal", "event_type": "exp_ruin", "state": "new", "enemy": "", "main": false})
	s.ship_pos = Vector2(5100, 5000)
	check(s.site_near().get("id", "") == "px", "within reach the site is offered")
	s.ship_pos = Vector2(5000 + 1500, 5000)
	check(s.site_near().is_empty(), "out of reach it is not")
	s.ship_pos = Vector2(5100, 5000)
	var c := Campaign.new(1)
	var res: Dictionary = s.trigger(c, _ship())
	check(res.is_empty() or str(res["poi"]["id"]) != "px", "trigger() leaves the site alone")
	s.set_hollow(true)
	check(s.site_near().is_empty(), "no away team into a Hollow place")
	s.set_hollow(false)
	s.resolve("px")
	check(s.site_near().is_empty(), "a site that was visited is done")


func test_the_team_limits() -> void:
	var s := _ship(5)
	eq(Expedition.check_team(s, []), "Pick at least one.", "nobody cannot go")
	eq(Expedition.check_team(s, ["Soldier"]), "", "alone is allowed")
	eq(Expedition.check_team(s, ["Soldier", "Hand0", "Hand1", "Hand2"]), "", "four is allowed")
	check(Expedition.check_team(s, ["Soldier", "Hand0", "Hand1", "Hand2", "Hand3"]) != "", "five is too many")
	check(Expedition.check_team(s, ["Nobody"]) != "", "a stranger cannot go")
	check(Expedition.check_team(s, ["Hand0", "Hand0"]) != "", "nor the same one twice")
	s.crew[2].hp = 0.0
	check(Expedition.check_team(s, [s.crew[2].name]) != "", "a downed crew member cannot go")
	check(not Expedition.candidates(s).any(func(m): return m.is_drone()), "no drone goes")
	var picker := TeamPicker.new()
	var stub := Control.new()
	stub.set_script(load("res://tests/expedition_stub.gd"))
	stub.set("the_ship", s)
	picker.map = stub
	picker.open(_poi("planet"))
	for i in 6:
		picker.toggle(i)
	eq(picker.pick.size(), 4, "the picker stops at four")
	picker.toggle(0)
	eq(picker.pick.size(), 3, "a second click drops one")
	stub.free()
	picker.free()


func _expedition(c, s: Ship, names: Array) -> Dictionary:
	c.expedition = {"poi": "t", "kind": "planet", "team": names, "page": "x"}
	return c.expedition


func test_team_requires_read_only_the_team() -> void:
	var c := Campaign.new(2)
	var s := _ship(3)  # Hand0 basalt, Hand1 fenn, Hand2 human
	s.crew[1].kit = {"weapons": [s.crew[1].sidearm(), ""], "body": "exosuit", "mods": ["", ""]}
	var ev := {"id": "t", "type": "exp_planet", "text": "x", "choices": [
		{"text": "basalt", "requires": {"species": "basalt"}, "outcomes": [{"weight": 1}]},
		{"text": "suit", "requires": {"gear": "exosuit"}, "outcomes": [{"weight": 1}]},
		{"text": "all sealed", "requires": {"suits": true}, "outcomes": [{"weight": 1}]},
		{"text": "free", "outcomes": [{"weight": 1}]}]}
	var outside: Array = c.events.choice_view(ev, c, s, {}).map(func(v): return v["text"])
	check(outside.has("[Basalt] basalt") or outside.has("basalt"), "a basalt aboard shows the basalt option")
	_expedition(c, s, ["Hand1", "Hand2"])  # no basalt in the team
	var away: Array = c.events.choice_view(ev, c, s, {}).map(func(v): return v["text"])
	check(not away.any(func(t): return str(t).contains("basalt")), "the basalt aboard but not in the team gives no option")
	check(away.any(func(t): return str(t).contains("suit")), "the exosuit in the team does")
	var sealed: Array = c.events.choice_view(ev, c, s, {}).filter(func(v): return str(v["text"]).contains("all sealed"))
	check(sealed.size() == 1 and sealed[0]["grey"], "every member sealed: grey while one is not")
	_expedition(c, s, ["Hand0"])
	check(c.events.choice_view(ev, c, s, {}).any(func(v): return str(v["text"]).contains("basalt")), "with the basalt in the team the option is there")
	s.crew[1].kit = {}
	_expedition(c, s, ["Hand0", "Hand2"])
	check(not c.events.choice_view(ev, c, s, {}).any(func(v): return str(v["text"]).contains("suit") and not str(v["text"]).contains("sealed")), "the gear left aboard (in the hold) is not the team's")
	Expedition.finish(c)


func test_a_lost_members_gear_is_gone_from_the_ship() -> void:
	var c := Campaign.new(3)
	var s := _ship(3)
	var m = s.crew[3]
	s.inventory.add("exosuit", 1)
	check(Kit_set(s, m, "exosuit"), "the exosuit is worn")
	var hold_before: int = s.inventory.count("exosuit")
	_expedition(c, s, [m.name, "Hand1"])
	var r: Dictionary = c.events.apply({"lose_member": "dead"}, c, s, {}, null)
	check(not s.crew.has(m), "the member is gone from the crew")
	eq(s.inventory.count("exosuit"), hold_before, "their exosuit did not go back to the hold")
	check(s.crew.all(func(x): return Expedition.gear_of(x).count("exosuit") == 0), "no one aboard has it")
	check(s.dead_crew.has(m.name), "they are dead for good")
	check(not c.expedition["team"].has(m.name), "and out of the team")
	check(str(" ".join(r["lines"])).contains("lost with them"), "the report says the gear went")
	var cap = s.crew.filter(func(x): return x.name == "Hand1")[0]
	c.events.apply({"lose_member": "captured"}, c, s, {}, null)
	check(c.captives.size() == 1 and c.flags.has("captive") and c.flags.has("captive_" + cap.name.to_lower()), "a captive is remembered, by flag and by name")
	var back: Dictionary = c.events.apply({"rescue": true}, c, s, {}, null)
	check(s.crew.any(func(x): return x.name == cap.name) and c.captives.is_empty() and not c.flags.has("captive"), "a rescue brings them home, without their kit")
	check(back["lines"].size() > 0, "and says so")
	Expedition.finish(c)


func Kit_set(s, m, item: String) -> bool:
	return load("res://scripts/board/kit.gd").set_body(s, m, item) == ""


func test_lose_gear_and_hurt_and_a_lone_soldier() -> void:
	var c := Campaign.new(4)
	var s := _ship(1)
	var m = s.crew[1]
	m.kit = {"weapons": [m.sidearm(), ""], "body": "exosuit", "mods": ["", ""]}
	_expedition(c, s, [m.name])
	c.events.apply({"lose_gear": "body"}, c, s, {}, null)
	eq(str(m.kit["body"]), "", "the carried suit is gone")
	eq(s.inventory.count("exosuit"), 0, "and not back in the hold")
	var hp: float = m.hp
	c.events.apply({"hurt": 20}, c, s, {}, null)
	eq(m.hp, hp - 20.0, "hurt takes hp from the one in the team")
	var other = s.crew[0]
	var before: float = other.hp
	c.events.apply({"crew_hp": -10}, c, s, {}, null)
	eq(other.hp, before, "crew_hp spares those who stayed aboard")
	c.expedition["team"] = [other.name]
	c.events.apply({"lose_member": "dead"}, c, s, {}, null)
	check(s.crew.has(other) and other.is_down(), "the soldier alone is knocked down, never lost")
	Expedition.finish(c)


func test_the_odds_show_on_a_choice() -> void:
	var team := [CrewMember.new("A", Vector2.ZERO, "human")]
	var safe := Expedition.risk_tag({"outcomes": [{"weight": 1, "effects": {"items": {"scrap": 1}}}]}, team)
	check(safe.is_empty(), "a safe choice has no tag")
	var risky := Expedition.risk_tag({"outcomes": [{"weight": 90, "effects": {}}, {"weight": 10, "effects": {"hurt": 10}}]}, team)
	check(str(risky["text"]).contains("low"), "a low risk says so")
	var dire := Expedition.risk_tag({"outcomes": [{"weight": 70}, {"weight": 30, "effects": {"lose_member": "dead"}}]}, team)
	check(str(dire["text"]).contains("30%") and dire["tone"] == "loss", "a possible loss names the percentage")
	var boosted := Expedition.risk_tag({"outcomes": [{"weight": 70, "boost": [{"species": "human", "x": 3.0}]}, {"weight": 30, "effects": {"lose_member": "dead"}}]}, team)
	check(str(boosted["text"]).contains("13%"), "the team's boost counts in the odds")


func _entries(c) -> Dictionary:
	var out := {}
	for id in c.events.order:
		var t := str(c.events.events[id].get("type", ""))
		if t.begins_with("exp_"):
			out[id] = c.events.events[id]
	return out


func test_every_expedition_event_loads_and_is_fair() -> void:
	var ev := Events.new()
	for e in ev.validate():
		check(not str(e).contains("expeditions"), "content check: " + str(e))
	var per := {}
	var entries := {}
	for id in ev.order:
		var e: Dictionary = ev.events[id]
		if str(e.get("type", "")).begins_with("exp_"):
			entries[id] = e
			per[e["type"]] = int(per.get(e["type"], 0)) + 1
	check(entries.size() >= 24, "at least 24 expedition events (%d)" % entries.size())
	for k in KINDS:
		check(int(per.get("exp_" + k, 0)) >= 6, "%s has at least six events (%d)" % [k, int(per.get("exp_" + k, 0))])
	var regional := 0
	var generic := 0
	for id in entries:
		var req: Dictionary = entries[id].get("requires", {})
		if req.has("region"):
			regional += 1
		else:
			generic += 1
	check(regional >= 4 and generic >= 10, "some are region-flavoured, some generic (%d, %d)" % [regional, generic])
	var chains := 0
	for id in ev.order:
		var e: Dictionary = ev.events[id]
		if not (str(ev.files[id]).contains("expeditions_")):
			continue
		var is_entry := str(e["type"]).begins_with("exp_")
		if is_entry and ev.events.has(id + "_deep"):
			chains += 1
		# a way out with no demands on every scene
		check(e["choices"].any(func(ch): return not ch.has("requires") or ch["requires"].is_empty()), "%s has a choice with no requirement" % id)
		for ch in e["choices"]:
			var lose := 0.0
			var total := 0.0
			for o in ch["outcomes"]:
				total += float(o.get("weight", 1))
				var eff: Dictionary = o.get("effects", {})
				if eff.has("lose_member"):
					lose += float(o.get("weight", 1))
					check(not is_entry, "%s: no loss in a first scene" % id)
			check(lose / maxf(total, 1.0) <= 0.35, "%s: a loss is never likelier than 35%%" % id)
			if lose > 0.0:
				check(e["choices"].any(func(c2): return not c2["outcomes"].any(func(o2): return o2.get("effects", {}).has("lose_member"))), "%s: a page that can lose someone also offers a way that cannot" % id)
	check(chains >= 20, "chains of scenes (%d)" % chains)


func test_rewards_come_in_tiers_and_losses_stay_rare() -> void:
	var low := Expedition.tier_of(10.0)
	eq(low, "poor", "10 is poor")
	eq(Expedition.tier_of(45.0), "fair", "45 is fair, about a wreck")
	eq(Expedition.tier_of(90.0), "good", "90 is good")
	eq(Expedition.tier_of(150.0), "rich", "150 is rich")
	eq(Expedition.tier_of(Expedition.value_of({"items": {"exosuit": 1}})), "fair", "a found suit is worth gear")
	for k in KINDS:
		var well := Sim.run(k, "well", 40, 5, true)
		check(float(well["mean"]) >= 65.0, "%s: an equipped team choosing well gets a good reward (%.0f)" % [k, well["mean"]])
		var bold := Sim.run(k, "bold", 60, 5, true)
		check(float(bold["loss_rate"]) < 0.2, "%s: pushing on always still loses someone rarely (%.2f)" % [k, bold["loss_rate"]])
		check(float(well["mean"]) > 0.0 and float(bold["mean"]) > 25.0, "%s: pushing on pays (%.0f)" % [k, bold["mean"]])


func test_finds_are_marked_found_only_and_exist() -> void:
	var items: Dictionary = {}
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	for it in data["items"]:
		items[it["id"]] = it
	var marked := 0
	for id in items:
		if str(items[id].get("found", "")) == "expedition":
			marked += 1
			check(["special", "mod"].has(str(items[id]["kind"])), "%s is special gear or a mod" % id)
	check(marked >= 4, "a few finds are marked expedition (%d)" % marked)
	var ev := Events.new()
	var given := {}
	for id in ev.order:
		if not str(ev.files[id]).contains("expeditions_"):
			continue
		for ch in ev.events[id]["choices"]:
			for o in ch["outcomes"]:
				for item in o.get("effects", {}).get("items", {}):
					if str(items.get(item, {}).get("found", "")) == "expedition":
						given[item] = true
	check(given.size() >= 4, "the events give the marked gear (%d)" % given.size())


func test_save_and_load_mid_run() -> void:
	var c := Campaign.new(6)
	var s := _ship(2)
	var r := Expedition.begin(c, s, {"id": "p1", "type": "exp_planet", "name": "Planet"}, ["Soldier", "Hand0"])
	check(r["ok"], "a team is sent")
	c.captives["Rook"] = "human"
	c.flags["captive_rook"] = true
	var d: Dictionary = c.to_dict()
	var back := Campaign.new(99)
	eq(back.load_dict(JSON.parse_string(JSON.stringify(d))), "", "the save loads")
	eq(back.expedition["team"], ["Soldier", "Hand0"], "the team away is kept")
	eq(back.expedition["page"], c.expedition["page"], "and the page it is on")
	eq(back.captives, {"Rook": "human"}, "the captives are kept")
	d.erase("expedition")
	d.erase("captives")
	var old := Campaign.new(98)
	eq(old.load_dict(d), "", "an older save with neither still loads")
	check(old.expedition.is_empty() and old.captives.is_empty(), "and starts with none")
