extends "res://tests/base_test.gd"
## Beds on foot (scripts/board/beds.gd, data/boarding.json beds): which stations have medbays and how many beds, which beds work by state, beds in a
## derelict's medbay, healing by a working bed (and not under fire, not on a broken or a taken bed), a follower laid on a bed.

const Site = preload("res://scripts/board/site.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Beds = preload("res://scripts/board/beds.gd")
const Party = preload("res://scripts/board/party.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	s.crew.append(CrewMember.new("Rook", Vector2(10, 10), "human"))
	return s


## A visit to `site` with no sector behind it, nobody hostile aboard.
func _visit(site, ship = null):
	var s = Boarding.start(null, null, "b1", {"kind": site.kind}, ship if ship != null else _ship())
	s.site = site
	s.soldier.pos = site.airlock["spawn"]
	s.foes = Foes.new(s)
	s.beds = Beds.new(s)
	return s


func _with_working_bed(state := "operational"):
	for i in 40:
		var site = Site.make(600 + i * 13, "station", {"faction": "clans", "state": state})
		if site.beds.any(func(b): return b["works"]):
			return site
	return null


func test_bigger_stations_have_more_beds_and_the_state_says_which_work() -> void:
	var beds := {}
	var count := {}
	var work := {"operational": [0, 0], "abandoned": [0, 0]}
	for st in ["operational", "abandoned"]:
		for i in 30:
			var s = Site.make(100 + i * 7, "station", {"faction": "clans", "state": st})
			if s.gen != "modules":
				continue
			beds[s.station_type] = int(beds.get(s.station_type, 0)) + s.beds.size()
			count[s.station_type] = int(count.get(s.station_type, 0)) + 1
			for b in s.beds:
				work[st][0] += 1 if b["works"] else 0
				work[st][1] += 1
				check(s.rooms[b["room"]]["purpose"] == "medbay", "a bed stands in a medbay")
			eq(s.problems(), [], "beds leave the station sound")
	var per := {}
	for t in beds:
		per[t] = float(beds[t]) / float(count[t])
	check(float(per.get("outpost", 0.0)) < float(per.get("habitat", 0.0)), "a habitat has more beds than an outpost (%s)" % str(per))
	eq(work["operational"][0], work["operational"][1], "on an operational station every bed works")
	check(work["abandoned"][1] > 0 and float(work["abandoned"][0]) / float(work["abandoned"][1]) < 0.4, "on an abandoned one most are broken (%s)" % str(work["abandoned"]))


func test_half_active_beds_work_on_powered_sections() -> void:
	var on := [0, 0]
	var off := [0, 0]
	for i in 40:
		var s = Site.make(200 + i * 7, "station", {"faction": "clans", "state": "half"})
		for b in s.beds:
			var powered: bool = s.modules[int(s.rooms[b["room"]]["module"])]["powered"]
			var tally: Array = on if powered else off
			tally[0] += 1 if b["works"] else 0
			tally[1] += 1
	check(on[1] > 0 and off[1] > 0, "beds on both kinds of section (%s %s)" % [str(on), str(off)])
	check(float(on[0]) / float(on[1]) > 0.6 and float(off[0]) / float(off[1]) < 0.4, "powered beds mostly work, the rest mostly not (%s %s)" % [str(on), str(off)])


func test_a_derelict_medbay_has_beds_mostly_broken_and_they_are_not_containers() -> void:
	var n := 0
	var works := 0
	for i in 40:
		var s = Site.make(300 + i * 11, "derelict", {"faction": "clans"})
		var before: Array = s.containers()
		for b in s.beds:
			n += 1
			works += 1 if b["works"] else 0
			check(not s.prop_of.has(b["cell"]), "a bed is not a prop")
		eq(s.containers(), before, "the containers are what they were")
		eq(s.problems(), [], "seed %d: sound with its beds" % (300 + i * 11))
	check(n > 5 and float(works) / float(n) < 0.4, "derelict medbays have beds, mostly broken (%d of %d work)" % [works, n])


func test_holding_e_by_a_working_bed_heals_but_not_under_fire_or_on_a_broken_bed() -> void:
	var site = _with_working_bed()
	check(site != null, "a station with a working bed")
	var s = _visit(site)
	var bed: Dictionary = site.beds.filter(func(b): return b["works"])[0]
	s.soldier.hp = 30.0
	eq(s.beds.heal(bed["id"], 1.0), "", "he heals")
	check(absf(s.soldier.hp - 30.0 - float(Site.config()["beds"]["heal_hp_s"])) < 0.01, "heal_hp_s a second (%.2f)" % s.soldier.hp)
	var f: Dictionary = s.foes.add("scavenger", s.soldier.pos + Vector2(6, 0))
	f["mode"] = "hunt"
	var hp: float = s.soldier.hp
	eq(s.beds.heal(bed["id"], 1.0), str(Site.config()["beds"]["refuse"]), "not with a foe on the hunt")
	eq(s.soldier.hp, hp, "and no health comes")
	f["mode"] = "idle"
	bed["works"] = false
	eq(s.beds.heal(bed["id"], 1.0), str(Site.config()["beds"]["broken"]), "a broken bed heals nobody")
	bed["works"] = true
	s.soldier.hp = s.soldier.max_hp
	eq(s.beds.heal(bed["id"], 1.0), str(Site.config()["beds"]["full"]), "a whole man is told so")


func test_a_follower_laid_on_a_bed_heals_takes_it_and_gets_up() -> void:
	var site = _with_working_bed()
	var sh := _ship()
	var s = _visit(site, sh)
	s.join_party(Party.eligible(sh).map(func(m): return m.name).slice(0, 1))
	var p: Dictionary = s.party[0]
	var bed: Dictionary = site.beds.filter(func(b): return b["works"])[0]
	p["m"].pos = site.bed_centre(bed) + Vector2(1.5, 0)
	p["m"].hp = 10.0
	var got: int = s.beds.bed_for(0, 3.0)  # (the nearest free working bed: two can lie side by side)
	check(got >= 0 and site.beds[got]["works"], "a free working bed by them")
	bed = site.beds[got]
	eq(s.beds.lay(0, bed["id"]), "", "they lie down on it")
	check(Beds.lying(p) and p["m"].pos == site.bed_centre(bed), "on the bed")
	eq(s.beds.why_not(bed["id"]), str(Site.config()["beds"]["busy"]), "one person to a bed")
	s.beds.tick(2.0)
	check(absf(p["m"].hp - 10.0 - 2.0 * float(Site.config()["beds"]["heal_hp_s"])) < 0.01, "they heal there (%.2f)" % p["m"].hp)
	var f: Dictionary = s.foes.add("scavenger", s.soldier.pos + Vector2(6, 0))
	f["mode"] = "hunt"
	s.beds.tick(0.1)
	check(not Beds.lying(p) and s.beds.is_free(bed["id"]), "they get up when a foe hunts the party")
	f["mode"] = "idle"
	eq(s.beds.lay(0, bed["id"]), "", "back on the bed")
	p["m"].hp = p["m"].max_hp - 0.5
	s.beds.tick(1.0)
	check(not Beds.lying(p) and p["m"].hp >= p["m"].max_hp, "and up again when whole")
