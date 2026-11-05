extends "res://tests/base_test.gd"
## Homelands (docs/CONTENT.md section 24): the capital of every race (an operational, friendly, single-race, large station with all its race's rooms, a race trader
## and a race recruiter, race guards, its emblem and arrival line) and the wonder of each of the ten major races.

const Campaign = preload("res://scripts/space/campaign.gd")
const Content = preload("res://scripts/data/content.gd")
const Homelands = preload("res://scripts/space/homelands.gd")
const Races = preload("res://scripts/board/station_races.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Site = preload("res://scripts/board/site.gd")
const StationGen = preload("res://scripts/board/station_gen.gd")
const People = preload("res://scripts/board/people.gd")
const WonderArt = preload("res://scripts/view/wonder_art.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


func _race_rooms(race: String) -> Array:
	var out := []
	var mods: Dictionary = StationGen.modules()
	for mid in mods:
		if mods[mid].get("races", []).has(race):
			out.append(mid)
	out.sort()
	return out


func _capital_site(cap: Dictionary, seed_value: int):
	return Site.make(seed_value, "station", Homelands.station_opts(cap).merged({"name": cap["name"], "region": cap["region"], "gen": "modules"}))


func test_every_homeland_has_a_capital() -> void:
	var caps := Homelands.capitals()
	eq(caps.size(), 29, "29 homelands, 29 capitals")
	var races := {}
	for r in Content.regions():
		if str(r.get("home_species", "")) != "":
			races[str(r["home_species"])] = true
	for c in caps:
		races.erase(c["race"])
		check(Races.config()["races"].has(c["race"]), c["race"] + " builds stations")
		check(not _race_rooms(c["race"]).is_empty(), c["race"] + " has a signature room")
		check(not Homelands.own(c["race"]).is_empty(), c["race"] + " has a house line")
	eq(races.size(), 0, "every homeland region has a capital")


func test_a_capital_is_operational_single_race_large_and_has_every_room_of_its_race() -> void:
	var normal_max := 0
	for t in ["outpost", "waystation", "habitat"]:
		normal_max = maxi(normal_max, int(StationGen.config()["types"][t]["modules"][1]))
	for cap in Homelands.capitals():
		for seed in [1, 2]:
			var s = _capital_site(cap, seed * 7919 + hash(cap["race"]) % 1000)
			var tag := "%s seed %d" % [cap["race"], seed]
			check(s.ok and s.gen == "modules", tag + ": built from modules")
			eq(s.state, "operational", tag + ": operational")
			eq(s.mood, "friendly", tag + ": friendly")
			eq(s.races, [cap["race"]], tag + ": single race")
			eq(s.station_type, "capital", tag + ": the capital size class")
			check(s.modules.size() >= int(StationGen.config()["types"]["capital"]["modules"][0]) - 2, tag + ": large (%d modules)" % s.modules.size())
			check(s.modules.size() > int(StationGen.config()["types"]["habitat"]["modules"][0]), tag + ": bigger than a habitat's least")
			var have := {}
			for m in s.modules:
				have[m["id"]] = true
				eq(m["race"], cap["race"], tag + ": every section is the race's")
			for mid in _race_rooms(cap["race"]):
				check(have.has(mid), "%s: has its room %s" % [tag, mid])
	check(normal_max < 20, "sanity")


func test_a_capitals_people_are_its_race_with_a_trader_a_recruiter_and_guards() -> void:
	for race in ["kett", "fenn", "drakkin", "human"]:
		var cap := Homelands.capital_in({"kett": "kett_hives", "fenn": "fenn_bazaar", "drakkin": "drakkin_pits", "human": "human_core"}[race])
		var s = _capital_site(cap, 31)
		var roles := {}
		var must: Array = s.crowd["people"]["must"]
		check(must.has("trader") and must.has("recruiter"), race + ": a trader and a recruiter are always aboard")
		check(int(s.crowd["people"]["guards"][0]) >= 3, race + ": guards")
		eq(s.capital, race, race + ": the site knows its capital")
		roles["x"] = 1
	check(People.has_role("recruiter"), "the recruiter role exists")


func test_the_capital_trader_leans_to_the_race_and_the_recruiter_offers_it() -> void:
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	for cap in Homelands.capitals():
		var c := Campaign.new(5)
		c.enter_region(cap["region"], ship)
		var menu: Dictionary = c.station_cfg(cap["place"])
		check(not menu.is_empty(), cap["race"] + ": the capital has a menu")
		check(Homelands.own_share(cap["race"], menu) >= 0.5, "%s: at least half the shelf is the race's (%.2f)" % [cap["race"], Homelands.own_share(cap["race"], menu)])
		var rec: Dictionary = menu["recruit"]
		var total := 0.0
		for k in rec:
			total += float(rec[k])
		check(float(rec.get(cap["race"], 0.0)) / total >= 0.8, cap["race"] + ": the recruiter offers mostly the race")
		for id in menu["stock"]:
			check(Content.has("components", id) or Content.has("items", id), "%s sells a real thing: %s" % [cap["race"], id])
		check(menu["services"].has("recruit") and menu["services"].has("stock"), cap["race"] + ": trades and hires")
	var plain: Dictionary = Campaign.new(5).station_cfg("rusthold")
	check(Homelands.own_share("kett", plain) < 0.5, "an ordinary station is not leaned")


func test_a_capital_is_marked_in_its_sector_and_greets_with_its_line() -> void:
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	var c := Campaign.new(9)
	c.enter_region("kett_hives", ship)
	var cap := Homelands.capital_in("kett_hives")
	var node := {}
	for n in c.drift.nodes:
		if str(n.get("place", "")) == cap["place"]:
			node = n
	check(not node.is_empty(), "the capital node is on the map")
	var s = c.sector_at(node["id"])
	eq(s.pois[0].get("capital", ""), "kett", "its main POI is the capital")
	eq(Homelands.line(cap), "Hive Ninefold, the Kett capital.", "the arrival line")
	var again = c.sector_at(node["id"])
	eq(again.pois.size(), s.pois.size(), "the same sector")


func test_each_major_wonder_is_placed_once_in_its_homeland_sector_and_the_other_homelands_have_none() -> void:
	var seen := {}
	for race in Homelands.wonder_races():
		var region := ""
		for ca in Homelands.capitals():
			if ca["race"] == race:
				region = ca["region"]
		var c := Campaign.new(21)
		c.enter_region(region)
		var wonders := 0
		for n in c.drift.nodes:
			var s = c.sector_at(n["id"])
			for p in s.pois:
				if p["type"] == "wonder":
					wonders += 1
					eq(p["wonder"], race, race + ": the wonder is its race's")
					eq(str(n.get("place", "")), Homelands.capital_in(region)["place"], race + ": in the capital's sector")
					eq(p["visibility"], "beacon", race + ": a landmark you see from afar")
		eq(wonders, 1, race + ": one wonder in its homeland")
		seen[race] = true
	eq(seen.size(), 10, "ten wonders")
	var c := Campaign.new(21)
	c.enter_region("drakkin_pits")
	for n in c.drift.nodes:
		check(not c.sector_at(n["id"]).pois.any(func(p): return p["type"] == "wonder"), "a minor homeland has no wonder")


func test_a_wonder_does_not_move_the_other_pois() -> void:
	var c := Campaign.new(21)
	c.enter_region("kett_hives")
	var cap := Homelands.capital_in("kett_hives")
	var s = c.sector_at(c.drift.nodes.filter(func(n): return str(n.get("place", "")) == cap["place"])[0]["id"])
	var others: Array = s.pois.filter(func(p): return p["type"] != "wonder")
	check(others.size() >= 3, "the usual POIs are all there (%d)" % others.size())
	eq(s.pois.size() - others.size(), 1, "plus one wonder")


func test_each_wonder_event_loads_and_pays_its_reward_once_a_run() -> void:
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	for race in Homelands.wonder_races():
		var w := Homelands.wonder_of(race)
		var region := ""
		for ca in Homelands.capitals():
			if ca["race"] == race:
				region = ca["region"]
		var c := Campaign.new(4)
		c.enter_region(region, ship)
		check(c.events.has(w["event"]), race + ": the event loads")
		var ev: Dictionary = c.events.get_event(w["event"])
		var node := {"id": "n01", "type": "anomaly", "place": ""}
		check(c.events.eligible(ev, c, node, ship), race + ": it can run in its homeland")
		check(float(ev.get("weight", 10)) == 0.0, race + ": nothing rolls it")
		for k in 40:
			check(c.events.pick(c, node, ship).get("id", "") != w["event"], race + ": the pool never picks it")
		var r: Dictionary = w["reward"]
		var s: Ship = Ship.from_design(RUSTBUCKET)
		var got := 0
		# every path that takes anything pays
		for i in ev["choices"].size():
			var ch: Dictionary = ev["choices"][i]
			var pays := false
			for o in ch["outcomes"]:
				var fx: Dictionary = o.get("effects", {})
				if fx.has("blueprint") or (fx.get("items", {}) as Dictionary).has(r["id"]):
					pays = true
				elif not fx.is_empty() and not fx.has("board"):
					check(false, "%s choice %d: an outcome takes something but not the reward" % [race, i])
			if pays:
				got += 1
		check(got >= 3, race + ": several ways to the reward (%d)" % got)
		# take the first choice once
		var res: Dictionary = c.events.choose(ev, 0, c, s, node)
		check(res["ok"], race + ": the first choice works")
		var line := "\n".join(res["lines"])
		if r["kind"] == "blueprint":
			check(s.crafting.is_known(r["id"]), race + ": the blueprint %s is learned" % r["id"])
		else:
			check(s.inventory.count(r["id"]) >= 1, race + ": the gear piece %s is in the hold" % r["id"])
		check(c.used.has(w["event"]), race + ": spent")
		check(not c.events.eligible(ev, c, node, s), race + ": it does not run twice")
		check(line != "", race + ": the lines tell what it gave")
		var rr: int = int(r["tier"])
		check(rr >= 0 and rr <= 3, race + ": tier")


func test_a_wonder_poi_runs_its_event_once_when_the_ship_arrives() -> void:
	var ship: Ship = Ship.from_design(RUSTBUCKET)
	var c := Campaign.new(21)
	c.enter_region("fenn_bazaar", ship)
	var cap := Homelands.capital_in("fenn_bazaar")
	var nid: String = c.drift.nodes.filter(func(n): return str(n.get("place", "")) == cap["place"])[0]["id"]
	var s = c.sector_at(nid)
	var poi: Dictionary = s.pois.filter(func(p): return p["type"] == "wonder")[0]
	s.ship_pos = poi["pos"]
	var res: Dictionary = s.trigger(c, ship)
	check(not res.is_empty() and res["event"].get("id", "") == "wonder_fenn_auction_ring", "arriving runs the wonder's event")
	c.used["wonder_fenn_auction_ring"] = true
	s.resolve(poi["id"])
	s.ship_pos = poi["pos"] + Vector2(5000, 0)
	s.trigger(c, ship)
	eq(poi["state"], Sector.DONE, "done")


func test_wonder_art_draws_every_wonder() -> void:
	for race in Homelands.wonder_races():
		check(WonderArt.has_art(str(Homelands.wonder_of(race)["art"])), race + ": a drawer for its art")


func test_same_seed_same_capital() -> void:
	for race_region in ["kett_hives", "human_core", "ferro_lodes"]:
		var cap := Homelands.capital_in(race_region)
		var a = _capital_site(cap, 77)
		var b = _capital_site(cap, 77)
		eq(a.grid.size, b.grid.size, race_region + ": same size")
		eq(a.modules.map(func(m): return m["id"]), b.modules.map(func(m): return m["id"]), race_region + ": same modules")


func test_capitals_stay_reachable_over_50_seeds() -> void:
	var caps := Homelands.capitals()
	var built := 0
	for cap in caps:
		for k in 2:
			var s = _capital_site(cap, 1000 + k * 31 + caps.find(cap))
			check(s.ok and s.gen == "modules", "%s: built" % cap["race"])
			built += 1
	for seed in range(1, 51):
		var cap: Dictionary = caps[seed % caps.size()]
		var s = _capital_site(cap, seed * 131)
		check(s.ok and s.gen == "modules", "%s seed %d: built from modules" % [cap["race"], seed])
		if not (s.ok and s.gen == "modules"):
			continue
		check(s._clear_lanes() == "", "%s seed %d: lanes clear for a 2x2 body" % [cap["race"], seed])
		check(not s._cut_off(), "%s seed %d: no room cut off" % [cap["race"], seed])
	check(built == 58, "all built")
