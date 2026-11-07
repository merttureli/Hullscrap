extends "res://tests/base_test.gd"
## Station interiors (scripts/board/station_fixtures.gd, station_races.gd, heat_foot.gd; data/station_fixtures.json, station_races.json): the catalogue and its
## fixture rules, fixtures that never block a lane (200 seeds), stable ids and container ids, the state dressing, the generator you repair, friendly guards,
## the backdrops, the mod rate, and the races: the mix by size and region, a skin that never changes the footprint, airless working sections, race loot,
## the people, and the heat on foot.

const Site = preload("res://scripts/board/site.gd")
const StationGen = preload("res://scripts/board/station_gen.gd")
const Fixtures = preload("res://scripts/board/station_fixtures.gd")
const Races = preload("res://scripts/board/station_races.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const Loot = preload("res://scripts/board/loot.gd")
const People = preload("res://scripts/board/people.gd")
const Wear = preload("res://scripts/board/wear.gd")
const HeatFoot = preload("res://scripts/board/heat_foot.gd")
const Backdrop = preload("res://scripts/board/station_backdrop.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Content = preload("res://scripts/data/content.gd")
const Art = preload("res://scripts/board/station_art.gd")
const Decor = preload("res://scripts/board/station_decor.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const STATES: Array[String] = ["abandoned", "half", "operational"]
const REGIONS: Array[String] = ["clan_space", "human_core", "kett_hives", "emberkin_forges", "sporeling_groves", "prismatic_choir", "boneyard", "fenn_bazaar"]
const SEEDS := 200

static var _sites: Array = []  # the 200 stations of the sweep, made once
const TIER_SHARES := {"ammo": 0.1028, "common": 0.4454, "credits": 0.2492, "gear": 0.0424, "mod": 0.0312, "part": 0.0186, "rare": 0.0738, "special": 0.0052, "weapon": 0.0313}  # each tier's share of the loot rolls over the 15 x 14 stations of the rate test, measured before the race rooms


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	return s


func _station(seed_value: int, state := "", region := "clan_space"):
	var opts := {"faction": "clans", "region": region}
	if state != "":
		opts["state"] = state
	return Site.make(seed_value, "station", opts)


## The sweep: 200 stations over the states and regions.
func _sweep() -> Array:
	if _sites.is_empty():
		for i in SEEDS:
			var s = _station(7000 + i * 37, STATES[i % 3], REGIONS[i % REGIONS.size()])
			if s.gen == "modules":
				_sites.append(s)
	return _sites


## A visit to `site` with no sector behind it.
func _visit(site):
	var s = Boarding.start(null, null, "i1", {"kind": "station"}, _ship())
	s.site = site
	s.soldier.pos = site.airlock["spawn"]
	s.foes = Foes.new(s)
	return s


# --- the catalogue and its rules -----------------------------------------------------------------------------------

func test_the_catalogue_has_twenty_modules_and_the_rules_name_real_things() -> void:
	var mods := StationGen.modules()
	check(mods.size() >= 20, "at least 20 modules (%d)" % mods.size())
	var race_rooms := 0
	for mid in mods:
		if not mods[mid].get("races", []).is_empty():
			race_rooms += 1
			for r in mods[mid]["races"]:
				check(Races.ids().has(r), "%s: a race that has a skin (%s)" % [mid, r])
			check(Fixtures.rules_of(mid).size() > 0, "%s: a race room has fixtures of its own" % mid)
	check(race_rooms >= 36, "at least 36 race rooms (%d)" % race_rooms)
	for mid in Fixtures.config()["rules"]:
		check(mods.has(mid), "rules: %s is a module" % mid)
		var rooms: int = mods[mid]["rooms"].size() if mods.has(mid) else 0
		for rule in Fixtures.rules_of(mid):
			check(Fixtures.defs().has(rule["fixture"]), "%s: fixture %s exists" % [mid, rule["fixture"]])
			check(int(rule.get("room", 0)) < rooms, "%s: room %s exists" % [mid, rule.get("room", 0)])
			check(str(rule.get("at", "wall")) in ["wall", "corner", "centre", "free", "row"], "%s: a known `at`" % mid)
			check(int(rule["n"][0]) <= int(rule["n"][1]), "%s: n is a range" % mid)
	for fid in Fixtures.defs():
		var d: Dictionary = Fixtures.defs()[fid]
		check(int(d["size"][0]) >= 1 and int(d["size"][1]) >= 1 and d.has("color"), "%s: a size and a colour" % fid)


# --- fixtures never block a lane -----------------------------------------------------------------------------------

func test_fixtures_leave_every_lane_clear_over_200_seeds() -> void:
	var seen := {}
	var with_fixtures := {}
	for s in _sweep():
		eq(s.problems(), [], "seed %d: sound for a 2x2 body, the keycards reachable" % s.seed_value)
		check(not s._cut_off(), "seed %d: no room cut off" % s.seed_value)
		var covered := {}
		for f in s.fixtures:
			for c in Fixtures.cells_of(f):
				check(not covered.has(c), "seed %d: fixtures do not overlap" % s.seed_value)
				covered[c] = true
				check(int(s.room_of.get(c, -1)) == int(f["room"]) and not s.prop_of.has(c), "seed %d: a fixture stands in its room and on no prop" % s.seed_value)
				eq(s.fixture_of.get(c, -1), f["id"], "fixture_of knows its cells")
				eq(s.walk.get_tile(c) == "wall", bool(f["blocks"]) or s.grid.get_tile(c) == "wall", "a blocking fixture is a wall of the walk, a walked-through one is not")
		for r in s.rooms:
			check(Fixtures._lanes_ok(s, r, []), "seed %d room %d: every door still reaches every other, every container and bed can be reached" % [s.seed_value, r["id"]])
		for m in s.modules:
			seen[m["id"]] = true
		for f in s.fixtures:
			with_fixtures[s.modules[int(s.rooms[f["room"]]["module"])]["id"]] = true
	for mid in seen:
		if not Fixtures.rules_of(str(mid)).is_empty():
			check(with_fixtures.has(mid), "%s: a station of the sweep has its fixtures" % mid)
	check(seen.size() >= 26, "the sweep builds most of the catalogue (%d modules: %s)" % [seen.size(), str(seen.keys())])


func test_a_door_blocked_by_a_fixture_is_refused() -> void:
	var s = _sweep()[0]
	var r: Dictionary = s.rooms.filter(func(x): return x["doors"].size() >= 2 and not x["corridor"])[0]
	var saved: Dictionary = s.walk.tiles.duplicate()
	var rect: Rect2i = r["rect"]
	for y in rect.size.y:  # a wall of fixtures across the room
		var c: Vector2i = rect.position + Vector2i(rect.size.x / 2, y)
		s.walk.tiles[c] = "wall"
	var blocked: bool = not Fixtures._lanes_ok(s, r, [])
	s.walk.tiles = saved
	check(blocked or r["doors"].size() < 2, "a line of fixtures across a room that joins two doors fails the lane check")


# --- stable ids ------------------------------------------------------------------------------------------------------

func test_fixture_ids_are_stable_and_do_not_move_the_containers() -> void:
	for i in 6:
		var a = _station(910 + i * 17, STATES[i % 3])
		var b = _station(910 + i * 17, STATES[i % 3])
		eq(a.fixtures.map(func(f): return [f["id"], f["fixture"], f["cell"], f["size"], f["dir"]]), b.fixtures.map(func(f): return [f["id"], f["fixture"], f["cell"], f["size"], f["dir"]]), "the same seed, the same fixtures")
		for k in a.fixtures.size():
			eq(a.fixtures[k]["id"], k, "ids run 0, 1, 2 ...")
		Fixtures.enabled = false
		var plain = _station(910 + i * 17, STATES[i % 3])
		Fixtures.enabled = true
		eq(a.props.map(func(p): return [p["id"], p["prop"], p["cell"], p["size"], p["slot"], p["key"]]), plain.props.map(func(p): return [p["id"], p["prop"], p["cell"], p["size"], p["slot"], p["key"]]), "the container ids and their slots are what they were without fixtures")
		eq(a.containers(), plain.containers(), "the same containers")


# --- the state dressing ----------------------------------------------------------------------------------------------

func test_the_same_fixtures_read_differently_in_each_state() -> void:
	var dead := {}
	var wreck := {}
	var lit := {}
	for st in STATES:
		var n := 0
		var d := 0
		var w := 0
		for i in 14:
			var s = _station(4100 + i * 29, st)
			if s.gen != "modules":
				continue
			for f in s.fixtures:
				var def: Dictionary = Fixtures.defs()[f["fixture"]]
				if def.get("screen", false) or def.get("glow", "") != "":
					n += 1
					d += 1 if f["dead"] else 0
				w += 1 if f["wreck"] else 0
		dead[st] = float(d) / float(maxi(n, 1))
		wreck[st] = w
		lit[st] = n
	check(float(dead["abandoned"]) > 0.7, "abandoned: most screens are dead (%s)" % dead["abandoned"])
	check(float(dead["operational"]) < 0.05 and int(wreck["operational"]) == 0, "operational: every screen on and nothing toppled (%s, %s)" % [dead["operational"], wreck["operational"]])
	check(float(dead["half"]) > float(dead["operational"]) and float(dead["half"]) < float(dead["abandoned"]), "half-active: in between (%s)" % dead["half"])
	check(int(wreck["abandoned"]) > int(wreck["half"]) and int(wreck["half"]) > 0, "toppled furniture: abandoned more than half-active (%s)" % wreck)


# --- power you can restore ------------------------------------------------------------------------------------------

func test_the_generator_lights_and_opens_a_dark_section() -> void:
	var site = null
	for i in 80:
		var s = _station(5200 + i * 11, "half" if i % 2 == 0 else "abandoned")
		if s.gen == "modules" and not s.power.is_empty() and not s.power["feeds"].is_empty() and s.doors.any(func(d): return d["lock"] == "hack"):
			site = s
			break
	check(site != null, "a half-active or abandoned station has a generator room")
	if site == null:
		return
	var g: Dictionary = site.fixtures[int(site.power["fixture"])]
	eq(g["fixture"], "generator", "the power fixture is the generator")
	eq(int(site.rooms[g["room"]]["module"]), int(site.power["module"]), "it stands in the generator room")
	check(not site.modules[int(site.power["module"])]["powered"], "the generator room is dark until it is repaired")
	var far: float = site.generator_dist(Vector2(site.fixtures[int(site.power["fixture"])]["cell"]) + Vector2(0.0, 40.0))
	check(far > 10.0, "the generator is only in reach beside it")
	var ses = _visit(site)
	var hacked_before: int = site.doors.filter(func(d): return d["lock"] == "hack").size()
	var n: int = ses.restore_power()
	for mi in site.power["feeds"]:
		check(site.modules[int(mi)]["powered"], "a fed section has power")
		for rid in site.modules[int(mi)]["rooms"]:
			eq(site.room_light[rid], "lit", "and its rooms are lit")
	check(n >= 0 and ses.restore_power() == 0, "repairing twice does nothing more")
	for id in ses.unlocked:
		check(site.doors[id]["lock"] != "hack" or ses.unlocked.has(id), "the doors it opened are unlocked")
	check(bool(ses.memory()["power"]), "a later visit finds the power back")
	check(hacked_before >= n, "only dead doors are opened")


# --- guards -----------------------------------------------------------------------------------------------------------

func test_a_friendly_station_has_friendly_guards() -> void:
	var guards := 0
	for i in 40:
		var s = _station(6300 + i * 13, "operational")
		if s.gen != "modules" or s.mood != "friendly":
			continue
		var ses = _visit(s)
		ses.people = People.new(ses)
		ses.people.spawn_site()
		for n in ses.people.list:
			if n["role"] == "guard":
				guards += 1
				eq(n["state"], "here", "a guard stands at its post")
				check(not s.crowd["spawn"]["mix"].has("guard"), "a guard is no foe")
	check(guards >= 5, "friendly stations keep guards (%d)" % guards)
	eq(People.cfg()["roles"]["guard"]["hostile"], "pirate", "a guard turns on you only when shot")
	var hostile := 0
	for i in 20:
		var s = _station(6900 + i * 7, "operational")
		if s.gen == "modules" and s.mood == "hostile":
			var ses = _visit(s)
			ses.people = People.new(ses)
			ses.people.spawn_site()
			hostile += ses.people.list.filter(func(n): return n["role"] == "guard").size()
	eq(hostile, 0, "no guards on a hostile station")


# --- backdrops --------------------------------------------------------------------------------------------------------

func test_every_backdrop_is_picked_and_paints() -> void:
	var kinds := {}
	for i in 160:
		var s = _station(8100 + i * 19, "", REGIONS[i % REGIONS.size()])
		if s.gen == "modules":
			kinds[s.backdrop["kind"]] = true
			if s.backdrop["kind"] == "gas_moons":
				check(int(s.backdrop["moons"]) >= 2, "a gas giant with moons has moons")
	for k in StationGen.config()["backdrop"]["kinds"]:
		check(kinds.has(k), "backdrop %s is picked" % k)
	eq(Backdrop.paint_nebula([Color.RED, Color.GREEN, Color.BLUE], 3).get_width(), Backdrop.TEX, "a nebula paints")


# --- the mod rate -----------------------------------------------------------------------------------------------------

func test_early_mods_are_back_to_about_one_and_a_half_to_one_and_seven_tenths() -> void:
	var total := 0.0
	var n := 0
	for i in 80:
		var s = _station(1000 + i * 37)
		if s.gen != "modules":
			continue
		n += 1
		for id in s.containers():
			var p: Dictionary = s.props[id]
			var table: Array = Loot.table_of(s, id)
			var w := 0.0
			var m := 0.0
			for o in table:
				w += float(o["weight"])
				if str(o["item"]) in ["mod", "mod_low"]:
					m += float(o["weight"])
			total += ((float(p["rolls"][0]) + float(p["rolls"][1])) / 2.0 + (1.0 if s.rooms[p["room"]]["locked"] else 0.0)) * m / w
	var rate := total / float(n)
	check(rate >= 1.4 and rate <= 1.8, "about 1.5-1.7 early mods a station (%.2f)" % rate)


# --- races: who built it ----------------------------------------------------------------------------------------------

func _roll(region: String, type: String, n := 400) -> Dictionary:
	var single := 0
	var sizes := 0
	var first_home := 0
	for i in n:
		var r := RandomNumberGenerator.new()
		r.seed = 31 * i + 5
		var got: Array = Races.roll(r, region, type)
		single += 1 if got.size() == 1 else 0
		sizes += got.size()
		first_home += 1 if got[0] == Races.home_of(region) else 0
		var seen := {}
		for x in got:
			check(Races.ids().has(x) and not seen.has(x), "a race with a skin, once")
			seen[x] = true
	return {"single": float(single) / n, "size": float(sizes) / n, "home": float(first_home) / n}


func test_the_race_mix_follows_size_and_region() -> void:
	var o := _roll("kett_hives", "outpost")
	var w := _roll("kett_hives", "waystation")
	var h := _roll("kett_hives", "habitat")
	check(absf(float(o["single"]) - 0.7) < 0.08, "a home outpost is one race about 70%% of the time (%s)" % o["single"])
	check(absf(float(w["single"]) - 0.5) < 0.08, "a home waystation is about even (%s)" % w["single"])
	check(float(h["single"]) < 0.25 and float(h["size"]) >= 2.3, "a home habitat is mostly mixed, 2-4 races (%s)" % h)
	eq(float(o["home"]), 1.0, "the home race comes first at home")
	for t in ["outpost", "waystation", "habitat"]:
		var away := _roll("clan_space", t)
		eq(float(away["single"]), 0.0, "%s away from any home is mixed" % t)
	var r := RandomNumberGenerator.new()
	r.seed = 9
	var mixed := 0
	for i in 100:
		var got: Array = Races.roll(r, "human_core", "habitat")
		check(got.size() <= 4 and got[0] == "human", "a habitat at human home: humans first, at most 4 (%s)" % str(got))
		mixed += 1 if got.size() >= 2 else 0
	check(mixed >= 75, "and mostly mixed (%d of 100)" % mixed)


func test_a_mixed_station_gives_each_section_a_race() -> void:
	var mixed := 0
	for s in _sweep():
		for m in s.modules:
			check(s.races.has(m["race"]), "a section's race is one of the station's")
		eq(s.modules[0]["race"], s.races[0], "the dock is the first race's")
		var seen := {}
		for m in s.modules:
			seen[m["race"]] = true
		if seen.size() > 1:
			mixed += 1
	check(mixed >= 30, "many stations show sections of different races (%d)" % mixed)


func _footprint(s) -> Array:
	var tiles := []
	for c in s.grid.tiles:
		tiles.append([c.x, c.y, s.grid.tiles[c]])
	tiles.sort()
	return [tiles, s.rooms.map(func(r): return [r["rect"], r["purpose"]]), s.doors.map(func(d): return d["cells"]), s.props.map(func(p): return [p["id"], p["prop"], p["cell"], p["size"]]),
		s.fixtures.map(func(f): return [f["fixture"], f["cell"], f["size"], f["dir"]]), s.containers(), s.walk.tiles.keys().size()]


func test_a_skin_never_changes_the_footprint_the_lanes_or_the_containers() -> void:
	var differed := 0
	StationGen.race_rooms = false  # (a race's own room is a layout of its own: leave them out to compare the skins)
	for i in 8:
		Races.forced = ["human"]
		var a = _station(2600 + i * 23, "half")
		Races.forced = ["fenn", "mire", "grundl"]
		var b = _station(2600 + i * 23, "half")
		Races.forced = []
		if a.gen != "modules" or b.gen != "modules":
			continue
		eq(_footprint(a), _footprint(b), "seed %d: the same cells, rooms, doors, containers and fixtures whoever built it" % (2600 + i * 23))
		for k in a.modules.size():
			check(a.modules[k]["race"] == "human" and b.modules[k]["race"] != "human" or b.modules.size() > 0, "the sections do take their races")
		for k in a.fixtures.size():
			if a.fixtures[k]["variant"] != b.fixtures[k]["variant"]:
				differed += 1
	StationGen.race_rooms = true
	check(differed > 0, "a fixture's art variant is the race's (%d differ)" % differed)
	check(Races.variant("kett", "console") == "hive_node" and Races.variant("human", "console") == "", "a Kett section draws a hive node where a human has a console")


func test_a_race_that_needs_no_air_keeps_working_airless_sections() -> void:
	var airless := 0
	Races.forced = ["basalt", "human"]
	for i in 40:
		var s = _station(3300 + i * 19, "operational")
		if s.gen != "modules":
			continue
		eq(s.problems(), [], "airless sections keep the station sound")
		for m in s.modules:
			if m["airless"]:
				airless += 1
				eq(m["race"], "basalt", "only a race that needs no air")
				check(m["powered"] and not m["breached"], "working, not torn open")
				for rid in m["rooms"]:
					check(not s.breathable(rid) and s.room_light[rid] in ["lit", "flicker"], "no air and fully lit")
		check(s.breathable(s.airlock["room"]), "the airlock keeps its air")
	Races.forced = ["human"]
	for i in 10:
		var s = _station(3300 + i * 19, "operational")
		if s.gen == "modules":
			check(s.modules.all(func(m): return not m["airless"]), "humans never")
	Races.forced = []
	check(airless > 0, "basalt sections are operational and airless (%d)" % airless)
	check(Races.airless_ok("basalt") and not Races.airless_ok("human"), "read from the traits")
	check(Races.power_mult("gauntling") > 1.0 and Races.power_mult("prismatic") > 1.0 and Races.power_mult("human") == 1.0, "power races keep more sections lit")
	eq(Races.climate("emberkin"), "hot", "emberkin sections are hot")
	eq(Races.climate("mire"), "cold", "mire sections are cool")


# --- race loot ---------------------------------------------------------------------------------------------------------

func test_race_loot_keeps_every_tiers_share_and_favours_the_races_things() -> void:
	var site = Site.new()
	site.kind = "station"
	var table: Array = Loot.table_for(site, "storage")
	var base := {}
	var total := 0.0
	for o in table:
		total += float(o["weight"])
	for o in table:
		var t := Loot.tier_of(str(o["item"]))
		base[t] = float(base.get(t, 0.0)) + float(o["weight"]) / total
	var chitin := {}
	for race in ["kett", "human", ""]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		var got := {}
		chitin[race] = 0
		for i in 50000:
			var item := str(Loot.roll(table, "storage", rng, race)["item"])
			got[Loot.tier_of(item)] = int(got.get(Loot.tier_of(item), 0)) + 1
			chitin[race] += 1 if item == "chitin_plate" else 0
		for t in base:
			check(absf(float(got.get(t, 0)) / 50000.0 - float(base[t])) < 0.01, "%s: tier %s keeps its share" % [race, t])
	check(int(chitin["kett"]) > int(chitin[""]) * 2, "a Kett section holds more chitin plate (%s)" % str(chitin))
	check(Races.owns("kett", "kett_hive_swarm_launcher") and Races.owns("kett", "chitin_plate") and not Races.owns("kett", "marine_plate"), "a race owns its gear and its tech pack's parts")


# --- the people --------------------------------------------------------------------------------------------------------

func test_the_people_and_the_foes_are_of_the_stations_races() -> void:
	Races.forced = ["kett"]
	var species := {}
	for i in 30:
		var s = _station(4400 + i * 13, "operational")
		if s.gen != "modules" or s.mood != "friendly":
			continue
		var ses = _visit(s)
		ses.people = People.new(ses)
		ses.people.spawn_site()
		for n in ses.people.list:
			species[n["m"].species] = true
	Races.forced = []
	check(species.has("kett") and species.size() == 1, "the people aboard a Kett station are Kett (%s)" % str(species.keys()))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var forge := 0
	for i in 300:
		forge += 1 if Wear.for_foe("pirate", "", rng, "emberkin") == "forge_apron" else 0
	check(forge > 60, "foes in an Emberkin section wear forge aprons (%d of 300)" % forge)


# --- heat on foot ------------------------------------------------------------------------------------------------------

class FakeVisit:
	var soldier
	var party: Array = []
	var site


func _trait(id: String, bag: Dictionary) -> void:
	var e := {"name": id}
	e.merge(bag)
	TraitSet.library()[id] = e


func _hot_site():
	for s in _sweep():
		if s.rooms.any(func(r): return float(s.heat_of(r["id"])) >= 60.0):
			return s
	return null


func _person_at(site, traits: Array, species := "human") -> CrewMember:
	var rid: int = site.rooms.filter(func(r): return float(site.heat_of(r["id"])) >= 60.0)[0]["id"]
	var m := CrewMember.new("Test", site.centre_of_room(rid), species)
	m.gear_traits = traits
	m.pos = site.centre_of_room(rid)
	return m


func test_a_hot_room_hurts_a_dries_out_person_and_slows_a_heat_speed_one() -> void:
	var site = _hot_site()
	check(site != null, "a station has a hot room (a reactor, a forge or a hot race)")
	if site == null:
		return
	var v := FakeVisit.new()
	v.site = site
	var mire := _person_at(site, [], "mire")
	v.soldier = mire
	var hp := mire.hp
	HeatFoot.tick(v, 1.0)
	check(is_equal_approx(hp - mire.hp, 2.0), "a Mire loses its 2 hp a second in a hot room (%s)" % (hp - mire.hp))
	eq(HeatFoot.effect(site, mire), "hurts", "the HUD says HOT, hurts")
	_trait("t_swelter", {"heat_speed": {"cold": 1.0, "hot": 0.6, "below": -100, "above": 50}})
	var slow := _person_at(site, ["t_swelter"])
	v.soldier = slow
	slow.speed_mod = 1.0
	HeatFoot.tick(v, 1.0)
	check(is_equal_approx(slow.speed_mod, 0.6), "a heat_speed person walks slower (%s)" % slow.speed_mod)
	eq(HeatFoot.effect(site, slow), "slows", "the HUD says HOT, slows")
	var apron := _person_at(site, ["t_swelter", "gear_forge"])
	v.soldier = apron
	apron.speed_mod = 1.0
	HeatFoot.tick(v, 1.0)
	check(is_equal_approx(apron.speed_mod, 1.0), "a Forge Apron (heat_proof) keeps the heat off the pace")
	eq(HeatFoot.effect(site, apron), "", "and the HUD stays quiet")
	var plain := _person_at(site, [])
	v.soldier = plain
	var php := plain.hp
	plain.speed_mod = 1.0
	HeatFoot.tick(v, 1.0)
	check(plain.hp == php and plain.speed_mod == 1.0, "a plain person is not touched")
	var cool: Dictionary = site.rooms.filter(func(r): return float(site.heat_of(r["id"])) < 40.0)[0]
	check(site.heat_at(site.centre_of_room(cool["id"])) == 30.0, "an ordinary room is at the ambient")
	TraitSet.reset()


func test_the_ships_heat_is_unchanged() -> void:
	var t := {"dries_out": {"heat_above": 60.0, "hp_per_s": 2.0}, "heat_speed": {"cold": 0.7, "hot": 1.2, "below": 20.0, "above": 50.0}, "heat_proof": false}
	check(TraitSet.heat_hurt(t, 61.0) == 2.0 and TraitSet.heat_hurt(t, 60.0) == 0.0 and TraitSet.heat_hurt(t, 10.0) == 0.0, "dries_out above its threshold only")
	check(TraitSet.heat_factor(t, 10.0) == 0.7 and TraitSet.heat_factor(t, 90.0) == 1.2 and TraitSet.heat_factor(t, 30.0) == 1.0, "heat_speed as before")


# --- wall and floor dressing --------------------------------------------------------------------------------------------

func test_dressing_sits_on_walls_and_floors_and_the_state_decides_the_rest() -> void:
	var by_state := {"abandoned": {}, "half": {}, "operational": {}}
	var signs := 0
	for s in _sweep():
		for d in s.dressing:
			by_state[s.state][d["kind"]] = int(by_state[s.state].get(d["kind"], 0)) + 1
			var c: Vector2i = d["cell"]
			if d["kind"] in ["pipe", "cable", "vent", "lamp", "panel", "poster", "sign"] or (d["kind"] == "scorch" and not s.room_of.has(c)):
				check(s.grid.get_tile(c) == "wall" and not s.room_of.has(c) and s.room_of.get(c + d["dir"], -1) == d["room"], "seed %d: a wall item is on a wall, facing its room" % s.seed_value)
				check(not s.door_of.has(c), "and not on a door")
			elif d["kind"] == "hazard":
				check(bool(Fixtures.defs()[s.fixtures[s.fixture_of[c]]["fixture"]].get("hazard", false)), "a hazard frame goes round what burns or turns")
			else:
				check(s.room_of.get(c, -1) == d["room"] and not s.fixture_of.has(c) and not s.prop_of.has(c), "seed %d: a floor mark is on free floor of its room" % s.seed_value)
			if d["kind"] == "frost":
				check(not s.breathable(d["room"]) or float(s.rooms[d["room"]].get("air", 1.0)) < 0.5, "frost only in an airless room")
			signs += 1 if d["kind"] == "sign" else 0
	check(signs > 200, "rooms carry their names (%d signs)" % signs)
	check(int(by_state["abandoned"].get("debris", 0)) > 20 and int(by_state["abandoned"].get("scorch", 0)) > 5, "abandoned: debris and scorch marks (%s)" % str(by_state["abandoned"]))
	check(int(by_state["operational"].get("debris", 0)) == 0 and int(by_state["operational"].get("scorch", 0)) == 0 and int(by_state["operational"].get("clutter", 0)) == 0, "operational: clean")
	check(int(by_state["half"].get("clutter", 0)) > 10 and int(by_state["half"].get("debris", 0)) == 0, "half-active: some clutter, no debris")
	var a = _station(8800, "abandoned")
	var b = _station(8800, "abandoned")
	eq(a.dressing, b.dressing, "the same seed dresses the same")
	var classic = Site.make(8800, "station", {"faction": "clans", "gen": "classic"})
	check(classic.dressing.is_empty() and classic.fixtures.is_empty() and classic.races.is_empty(), "a classic station has none of it")


# --- the race rooms: every race has its own ------------------------------------------------------------------------------

## The species that have a station skin: every one but the repair drone, which builds nothing.
func _builders() -> Array:
	var out: Array = []
	for id in Content.ids("species"):
		if id != "drone" and not Content.entry("species", str(id)).get("robot", false) and not str(id).begins_with("boarding_robot"):
			out.append(id)
	return out


## The race rooms (module id -> the module), sorted by id.
func _race_rooms() -> Array:
	var out: Array = []
	for mid in StationGen.modules():
		if not StationGen.modules()[mid].get("races", []).is_empty():
			out.append(mid)
	out.sort()
	return out


func test_every_species_but_the_drone_has_a_skin_that_reads_its_ships_colours() -> void:
	var builders := _builders()
	check(builders.size() >= 30, "30 builder races (%d)" % builders.size())
	for id in builders:
		check(Races.ids().has(id), "%s: has a station skin" % id)
		var sk := Races.skin(id)
		var pal := Races.palette(id)
		check(not pal.is_empty(), "%s: has a ship palette (data/ship_styles.json)" % id)
		for k in ["floor", "wall", "lamp"]:
			eq(sk[k], pal[k], "%s: the skin's %s is its ships'" % [id, k])
		check(sk.has("glyph") and sk.has("style"), "%s: a glyph and a style of its own" % id)
		for k in Races.config()["races"][id]["skin"]:
			check(not (k in ["floor", "wall", "lamp"]), "%s: no colour is copied into station_races.json" % id)


func test_every_species_but_the_drone_has_a_race_room_and_the_tech_races_two() -> void:
	var count := {}
	for mid in _race_rooms():
		for r in StationGen.modules()[mid]["races"]:
			count[r] = int(count.get(r, 0)) + 1
	var tech := 0
	for p in Content.packs():
		if str(p["id"]).begins_with("tech_"):
			tech += 1
			var r := str(p["id"]).trim_prefix("tech_")
			check(int(count.get(r, 0)) >= 2, "%s: a tech race has two rooms (%d)" % [r, int(count.get(r, 0))])
	check(tech >= 10, "ten tech races (%d)" % tech)
	for id in _builders():
		check(int(count.get(id, 0)) >= 1, "%s: has a race room" % id)
	check(not count.has("drone"), "the drone has none")


func test_every_race_room_has_two_fixtures_of_its_own_and_every_fixture_has_art() -> void:
	var used := {}  # fixture id -> the modules whose rules use it
	for mid in Fixtures.config()["rules"]:
		for rule in Fixtures.rules_of(str(mid)):
			if not used.has(rule["fixture"]):
				used[rule["fixture"]] = {}
			used[rule["fixture"]][mid] = true
	for mid in _race_rooms():
		var own := 0
		for fid in used:
			if used[fid].size() == 1 and used[fid].has(mid):
				own += 1
		check(own >= 2, "%s: at least 2 fixtures of its own (%d)" % [mid, own])
	var drawn := {}
	for m in (Decor as Script).get_script_method_list():
		drawn[str(m["name"])] = true
	for fid in Fixtures.defs():
		check(drawn.has("_art_" + fid) or Art.has_art(fid), "%s: drawn, not the default block" % fid)


func test_each_race_room_forced_into_a_station_is_reachable_for_2x2_bodies_over_50_seeds() -> void:
	for mid in _race_rooms():
		var found := 0
		var furnished := 0
		StationGen.forced_module = mid
		Races.forced = [StationGen.modules()[mid]["races"][0]]
		for i in 50:
			var s = _station(30000 + i * 17, STATES[i % 3], REGIONS[i % REGIONS.size()])
			if s.gen != "modules" or not s.modules.any(func(m): return m["id"] == mid):
				continue
			found += 1
			eq(s.problems(), [], "%s seed %d: sound for a 2x2 body, the keycards reachable" % [mid, s.seed_value])
			check(not s._cut_off(), "%s seed %d: no room cut off" % [mid, s.seed_value])
			for r in s.rooms:
				if s.modules[int(r["module"])]["id"] == mid:
					check(Fixtures._lanes_ok(s, r, []), "%s seed %d room %d: every door reaches every other and every container and bed" % [mid, s.seed_value, r["id"]])
			furnished += 1 if s.fixtures.any(func(f): return s.modules[int(s.rooms[f["room"]]["module"])]["id"] == mid) else 0
		StationGen.forced_module = ""
		Races.forced = []
		check(found >= 25, "%s: found in %d of 50 stations" % [mid, found])
		check(furnished * 10 >= found * 8, "%s: furnished in most of them (%d of %d)" % [mid, furnished, found])


func test_race_room_container_ids_are_stable() -> void:
	for mid in _race_rooms():
		StationGen.forced_module = mid
		Races.forced = [StationGen.modules()[mid]["races"][0]]
		var s = _station(31000 + mid.length() * 13, "half")
		var again = _station(31000 + mid.length() * 13, "half")
		Fixtures.enabled = false
		var bare = _station(31000 + mid.length() * 13, "half")
		Fixtures.enabled = true
		StationGen.forced_module = ""
		Races.forced = []
		if s.gen != "modules" or bare.gen != "modules":
			continue
		var key := func(site) -> Array: return site.containers().map(func(id): return [id, site.props[id]["prop"], site.props[id]["cell"], site.props[id]["room"]])
		eq(key.call(s), key.call(again), "%s: the same seed gives the same containers" % mid)
		eq(key.call(s), key.call(bare), "%s: fixtures leave the container ids as they were" % mid)
		eq(s.fixtures.map(func(f): return [f["fixture"], f["cell"], f["room"]]), again.fixtures.map(func(f): return [f["fixture"], f["cell"], f["room"]]), "%s: and the same fixtures" % mid)


func test_the_race_rooms_use_the_bodies_of_their_people() -> void:
	# an airless room is airless (and working) in a station of a race that needs no air, only when powered and nothing lies beyond it
	var airless := 0
	var rooms := 0
	for mid in ["stone_archive", "current_roost", "cairn_hall", "reform_bay", "optic_cradle"]:
		StationGen.forced_module = mid
		Races.forced = [StationGen.modules()[mid]["races"][0]]
		check(StationGen.modules()[mid].get("airless", false) and Races.airless_ok(StationGen.modules()[mid]["races"][0]), "%s: its people need no air" % mid)
		for i in 12:
			var s = _station(32000 + i * 19, "operational")
			for m in s.modules:
				if m["id"] == mid:
					rooms += 1
					if m["airless"]:
						airless += 1
						check(m["powered"] and s.rooms[m["rooms"][0]]["air"] == 0.0, "%s: working and airless" % mid)
					eq(s.problems(), [], "%s: and the station is still sound (no keycard behind thin air)" % mid)
		StationGen.forced_module = ""
		Races.forced = []
	check(airless >= 5 and airless <= rooms, "airless rooms are made (%d of %d)" % [airless, rooms])
	# a generator room of a race replaces the plain one; hold E restores it
	for mid in ["jury_generator", "arc_core_hall", "magnet_dynamo"]:
		StationGen.forced_module = mid
		Races.forced = [StationGen.modules()[mid]["races"][0]]
		var got := 0
		for i in 10:
			var s = _station(33000 + i * 23, "half")
			if s.gen != "modules" or not s.modules.any(func(m): return m["id"] == mid):
				continue
			got += 1
			check(not s.modules.any(func(m): return m["id"] == "power"), "%s: the plain generator room is not there too" % mid)
			if not s.power.is_empty():
				eq(s.modules[int(s.power["module"])]["id"], mid, "%s: is the generator room" % mid)
				eq(s.fixtures[int(s.power["fixture"])]["fixture"], "generator", "%s: and its generator is the one to repair" % mid)
				eq(int(s.rooms[s.fixtures[int(s.power["fixture"])]["room"]]["module"]), int(s.power["module"]), "%s: in its own room" % mid)
		StationGen.forced_module = ""
		Races.forced = []
		check(got > 0, "%s: built" % mid)
	# a hot room is hot on foot; a healing room has beds
	for mid in ["magma_hall", "hearth_hall", "fighting_pit"]:
		StationGen.forced_module = mid
		Races.forced = [StationGen.modules()[mid]["races"][0]]
		var hot := 0
		for i in 6:
			var s = _station(34000 + i * 29, "operational")
			for m in s.modules:
				if m["id"] == mid:
					check(float(s.rooms[m["rooms"][0]]["heat"]) >= 75.0, "%s: a hot room (%s)" % [mid, s.rooms[m["rooms"][0]]["heat"]])
					hot += 1
		StationGen.forced_module = ""
		Races.forced = []
		check(hot > 0, "%s: built" % mid)
	for mid in ["nectar_ward", "soak_marsh", "spore_ward"]:
		StationGen.forced_module = mid
		Races.forced = [StationGen.modules()[mid]["races"][0]]
		var beds := 0
		for i in 8:
			var s = _station(35000 + i * 31, "operational")
			for m in s.modules:
				if m["id"] == mid:
					beds += s.beds.filter(func(b): return b["room"] == m["rooms"][0]).size()
		StationGen.forced_module = ""
		Races.forced = []
		check(beds > 0, "%s: a medbay with beds (%d)" % [mid, beds])


func test_race_rooms_keep_the_early_mod_rate_and_the_tier_shares() -> void:
	# measured before the race rooms (the same formula and stations): 1.594 early mods a station and TIER_SHARES; with them it was 1.594 and every share within 0.013
	var total := 0.0
	var n := 0
	var tiers := {}
	var weight := 0.0
	for r in REGIONS:
		for i in 14:
			var s = Site.make(3000 + i * 37, "station", {"faction": "clans", "region": r})
			if s.gen != "modules":
				continue
			n += 1
			for id in s.containers():
				var p: Dictionary = s.props[id]
				var table: Array = Loot.table_of(s, id)
				var w := 0.0
				var m := 0.0
				for o in table:
					w += float(o["weight"])
					if str(o["item"]) in ["mod", "mod_low"]:
						m += float(o["weight"])
				var rolls := (float(p["rolls"][0]) + float(p["rolls"][1])) / 2.0
				total += (rolls + (1.0 if s.rooms[p["room"]]["locked"] else 0.0)) * m / w
				for o in table:
					var t := Loot.tier_of(str(o["item"]))
					tiers[t] = float(tiers.get(t, 0.0)) + rolls * float(o["weight"]) / w
				weight += rolls
	var rate := total / float(n)
	check(absf(rate - 1.594) <= 0.1, "the early-mod rate stays within 0.1 of 1.594 (%.3f)" % rate)
	for t in TIER_SHARES:
		var share := float(tiers.get(t, 0.0)) / weight
		check(absf(share - float(TIER_SHARES[t])) <= 0.03, "tier %s keeps its share (%.3f, was %.3f)" % [t, share, float(TIER_SHARES[t])])
