extends "res://tests/base_test.gd"
## Foes on foot are real races (docs/CONTENT.md 22, boarding.json `foe`, scripts/board/foes.gd pick_species): a beaten ship's crew keep their species, a friendly
## who turns keeps theirs, a race-built section is mostly its race, the rest follow the region's mix; the numbers stay the kind's.

const Site = preload("res://scripts/board/site.gd")
const WreckSite = preload("res://scripts/board/wreck_site.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Air = preload("res://scripts/board/air.gd")
const Races = preload("res://scripts/board/station_races.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const PEOPLE := ["scavenger", "pirate", "hollow_touched"]


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	s.crew.append(CrewMember.new("Bram", Vector2(10, 10), "human"))
	s.inventory.add("hand_ammo", 40)
	return s


## A session on `site`, its foes made empty (the test places them).
func _on(site):
	var s = Boarding.start(null, null, "w1", {"kind": "wreck"}, _ship())
	s.site = site
	s.soldier.pos = site.airlock["spawn"]
	s.foes = Foes.new(s)
	return s


func _enemy(faction: String, seed_value := 3) -> Dictionary:
	var e: Ship = Shipgen.build(faction, "medium", seed_value, 150.0)
	Jobs.spawn_enemy_crew(e)
	return JSON.parse_string(JSON.stringify(e.to_dict()))


func _classic(seed_value := 41, region := "kett_hives"):
	return Site.make(seed_value, "station", {"faction": "clans", "gen": "classic", "region": region})


func _race_section(race: String) -> Array:
	Races.forced = [race]
	for sd in 30:
		var site = Site.make(9100 + sd * 13, "station", {"faction": "clans", "region": "clan_space", "state": "operational"})
		if site.gen != "modules":
			continue
		for m in site.modules:
			if str(m.get("race", "")) == race and not m["rooms"].is_empty():
				Races.forced = []
				return [site, int(m["rooms"][0])]
	Races.forced = []
	return []


func test_a_won_fights_crew_board_as_the_species_they_were() -> void:
	for faction in ["kett", "concord"]:
		var s = _on(WreckSite.make(77, _enemy(faction), {"fight": "won"}))
		var crew: Array = s.site.foe_crew
		check(crew.size() > 0, "%s: crew on their feet" % faction)
		s.foes.spawn_site({"mem": {}})
		eq(s.foes.list.size(), crew.size(), "%s: a foe for each" % faction)
		for i in crew.size():
			var f: Dictionary = s.foes.list[i]
			eq(f["species"], crew[i]["species"], "%s: the same race" % faction)
			eq(f["m"].species, crew[i]["species"], "%s: the body is that race" % faction)
			eq(f["m"].name, crew[i]["name"], "%s: the same name" % faction)
		if faction == "kett":
			check(s.foes.list.all(func(f): return f["species"] == "kett"), "the kett you shot at are the kett you board against")
			check(Foes.title(s.foes.list[0]).begins_with("Kett "), "and are called so (%s)" % Foes.title(s.foes.list[0]))


func test_a_race_section_is_its_race_at_the_configured_share() -> void:
	var r := _race_section("kett")
	if r.is_empty():
		failures.append("no kett section found")
		return
	var s = _on(r[0])
	var share := float(Site.config()["foe"]["section_share"])
	eq(share, 0.6, "the share starts at 0.6")
	var n := 0
	for id in 200:
		if s.foes.pick_species("pirate", int(r[1]), id) == "kett":
			n += 1
	check(absf(float(n) / 200.0 - share) <= 0.08, "kett share %.2f" % (float(n) / 200.0))


func test_a_classic_station_follows_the_regions_mix() -> void:
	var s = _on(_classic())
	var home := 0
	var seen := {}
	for id in 400:
		var sp: String = s.foes.pick_species("scavenger", 0, id)
		seen[sp] = true
		if sp == "kett":
			home += 1
		check(sp != "" and Foes.person_species(sp), "%s is a person's species" % sp)
	var share := float(home) / 400.0
	check(share >= 0.5 and share <= 0.7, "the region's own race at its share (%.2f)" % share)
	check(seen.size() > 1, "and the rest from the people mix")
	for sp in seen:
		check(sp == "kett" or Site.config()["people"]["species"].has(sp), "%s is in the people table" % sp)


func test_no_drone_species_and_sentries_and_crawlers_are_unchanged() -> void:
	var s = _on(_classic(52, "human_core"))
	for id in 300:
		for k in PEOPLE:
			var sp: String = s.foes.pick_species(k, 0, id)
			check(not CrewMember.is_drone_species(sp) and sp != "", "%s is no drone" % sp)
	for k in ["sentry", "crawler"]:
		eq(s.foes.pick_species(k, 0, 1), "", k + " has no race")
		var f: Dictionary = s.foes.add(k, Vector2(10, 10), 0)
		eq(f["species"], "", k + " keeps no species")
		eq(f["m"].species, "human", k + " body as before")
		eq(Foes.title(f), str(f["d"]["name"]), k + " name line as before")
	eq(s.foes.add("crawler", Vector2(10, 10), 0)["m"].body_size, 1, "the crawler stays small")


func test_a_foes_numbers_are_the_kinds_whatever_its_race() -> void:
	var s = _on(_classic())
	for sp in CrewMember.species_table()["species"]:
		if CrewMember.is_drone_species(sp):
			continue
		for k in PEOPLE:
			var f: Dictionary = s.foes.add(k, Vector2(10, 10), 0, false, sp)
			var d: Dictionary = Foes.def(k)
			eq(f["m"].species, sp, "%s: the race" % sp)
			eq(f["m"].max_hp, float(d["hp"]), "%s %s: hp" % [sp, k])
			eq(f["m"].hp, float(d["hp"]), "%s %s: full hp" % [sp, k])
			eq(f["m"].speed, CrewMember.BASE_SPEED * float(d["speed"]), "%s %s: speed" % [sp, k])
			eq(f["m"].body_size, 2, "%s %s: body size" % [sp, k])
			eq(f["d"]["attack"], d["attack"], "%s %s: attack" % [sp, k])
			eq(f["m"].speed_mod, 1.0, "%s %s: speed_mod" % [sp, k])
	var q: Dictionary = s.foes.add("pirate", Vector2(12, 12), 0, false, "quillback")
	q["m"].kit = {}
	eq(Foes.counter_melee(q["m"]), 0.0, "a quillback foe's quills are not in the numbers")


func test_same_seed_same_races_stable_ids_and_the_dead_stay_dead() -> void:
	var a = _on(_classic())
	var b = _on(_classic())
	a.foes.spawn_site({"mem": {}})
	b.foes.spawn_site({"mem": {}})
	check(a.foes.list.size() > 3, "foes stand here")
	eq(a.foes.list.map(func(f): return [f["id"], f["kind"], f["species"], f["corpse"] if f.has("corpse") else -1]), b.foes.list.map(func(f): return [f["id"], f["kind"], f["species"], f["corpse"] if f.has("corpse") else -1]), "same seed, same races and ids")
	var rng_before: int = a.rng.state
	a.foes.pick_species("pirate", 0, 5)
	eq(a.rng.state, rng_before, "the fight's dice do not move")
	var f: Dictionary = a.foes.list[1]
	a.foes.hurt(f, 9999.0, f["m"].pos)
	var mem: Dictionary = a.foes.memory()
	var c = _on(_classic())
	c.foes.spawn_site({"mem": mem})
	var dead: Array = c.foes.list.filter(func(g): return g["dead"]).map(func(g): return g["id"])
	eq(dead, [f["id"]], "a revisit marks the same dead")
	eq(c.foes.list[1]["species"], f["species"], "as the same race")
	eq(c.site.props[int(c.foes.list[1]["corpse"])]["species"], f["species"], "with the same body")


func test_a_friendly_who_turns_keeps_their_race_name_and_look() -> void:
	var s = _on(_classic(63, "human_core"))
	s.people.spawn_site({})
	for sp in ["kett", "basalt"]:
		var n: Dictionary = s.people.add("guard", Vector2(12, 12), 0, sp, "Aldo")
		var f: Dictionary = s.people.turn(n)
		eq(f["species"], sp, "%s keeps their species" % sp)
		eq(f["m"].species, sp, "%s: the body" % sp)
		eq(f["m"].name, "Aldo", "and their name")
		eq(f["look"], n["d"]["look"], "and their look")
		eq(f["m"].kit, n["m"].kit, "and their gear")
		check(Foes.title(f).begins_with(Foes.race_label(sp)), "and are called by it (%s)" % Foes.title(f))


func test_a_body_carries_its_species_and_the_name_line_its_label() -> void:
	var s = _on(_classic())
	var f: Dictionary = s.foes.add("pirate", Vector2(12, 12), 0, true, "kett")
	eq(s.site.props[int(f["corpse"])]["species"], "kett", "the body at its feet")
	eq(Foes.title(f), "Kett pirate", "the name line")
	var h: Dictionary = s.foes.add("hollow_touched", Vector2(14, 12), 0, true, "human")
	eq(Foes.title(h), "Human hollow-touched", "a hollow-touched is a person too")
	var amb: Dictionary = s.foes.add("scavenger", Vector2(16, 12), 0, false)
	s.foes.hurt(amb, 9999.0, amb["m"].pos)
	eq(s.site.props[int(amb["corpse"])]["species"], amb["species"], "an ambusher's body is made when it falls, as its race")


func test_a_race_that_lives_without_air_needs_no_seal_in_an_airless_room() -> void:
	var s = _on(WreckSite.make(77, _enemy("concord"), {"fight": "won"}))
	s.site.rooms[0]["air"] = 0.0
	var pos: Vector2 = s.site.centre_of_room(0)
	var rock: Dictionary = s.foes.add("pirate", pos, 0, true, "basalt")
	var man: Dictionary = s.foes.add("pirate", pos + Vector2(3, 0), 0, true, "human")
	for f in [rock, man]:
		f["sealed"] = false
		s.foes.dress(f, "")
	Air.tick(s, 2.0)
	eq(rock["m"].hp, rock["m"].max_hp, "the stone-bodied one takes no air damage")
	check(man["m"].hp < man["m"].max_hp, "the human with no seal does")
