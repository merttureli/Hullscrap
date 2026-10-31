extends "res://tests/base_test.gd"
## Race wave 3 as data (docs/waves/races_2_4.md, pack data/packs/races_3/): the seven species come out of TraitSet with
## the numbers of the table, each race has three events with a blue option for it, each homeland has six events that ask for
## its region, a recruit and a blue option of the race, and the recruit tables name them where the lore says.

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Content = preload("res://scripts/data/content.gd")
const Events = preload("res://scripts/space/events.gd")
const Regions = preload("res://scripts/space/regions.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")

const RACES := ["revenant", "choir", "rattler", "tessellate", "sable", "quillback", "kite"]
const HOMES := {"revenant": "revenant_cairns", "choir": "choir_chantry", "rattler": "rattler_walls", "tessellate": "tessellate_mend",
	"sable": "sable_moorings", "quillback": "quillback_lists", "kite": "kite_slack"}


func near(got: float, want: float, msg: String, eps := 1e-6) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, want, got])


func _of(species: String) -> Array:
	var m := CrewMember.new("X", Vector2.ZERO, species)
	return [m, TraitSet.of(m)]


func test_the_seven_species_have_the_numbers_of_the_table() -> void:
	var r := _of("revenant")
	near(r[0].max_hp, 110.0, "revenant hp")
	near(r[1]["o2_use"], 0.0, "revenant does not breathe")
	near(r[1]["heal_mult"]["bed"], 0.0, "no healing from a bed")
	near(r[1]["heal_mult"]["medbay"], 0.5, "half from a medbay")
	eq([r[1]["revive_once"]["after"], r[1]["revive_once"]["hp"]], [10.0, 50.0], "gets up after 10 s at 50 hp")
	var c := _of("choir")
	near(c[1]["aura"]["work_mult"], 1.15, "others in the room work x1.15")
	near(c[1]["melee_mult"], 0.3, "choir melee")
	eq(c[0].sidearm(), "", "the Choir carry nothing")
	var t := _of("rattler")
	near(t[0].max_hp, 60.0, "rattler hp")
	eq(t[0].body_size, 1, "a small body")
	near(t[1]["line_affinity"]["scrap"], 2.0, "scrap work x2")
	var s := _of("tessellate")
	near(s[1]["o2_use"], 0.0, "tessellate does not breathe")
	near(s[1]["damage_taken"]["ion"], 2.0, "ion x2")
	near(s[1]["split_on_death"]["reform_s"], 30.0, "reforms in 30 s")
	var a := _of("sable")
	near(a[0].max_hp, 90.0, "sable hp")
	near(a[1]["work_mult"]["breach"], 2.0, "breach work x2")
	near(a[1]["ranged_mult"], 1.25, "ranged x1.25")
	var q := _of("quillback")
	near(q[0].max_hp, 110.0, "quillback hp")
	near(q[1]["counter_melee"], 10.0, "hits back for 10")
	check(q[1]["no_suit"], "no suit")
	var k := _of("kite")
	near(k[0].max_hp, 90.0, "kite hp")
	near(k[1]["suffocate_mult"], 0.5, "half the damage without air")
	near(k[1]["vacuum_speed"], 1.5, "x1.5 in thin air")
	for id in RACES:
		var m := CrewMember.new("X", Vector2.ZERO, id)
		eq(m.rig(), id, id + ": its own rig")
		check(m.sidearm() != "" or id == "choir", id + ": a sidearm")


func _blue_for(ev: Dictionary, species: String) -> bool:
	for ch in ev.get("choices", []):
		if ch.get("requires", {}).get("species", "") == species:
			return true
	return false


func _recruits(ev: Dictionary, species: String) -> bool:
	for ch in ev.get("choices", []):
		for o in ch.get("outcomes", []):
			if o.get("effects", {}).get("recruit", {}).get("species", "") == species:
				return true
	return false


func test_each_race_has_three_events_with_blue_options_and_each_homeland_six() -> void:
	var evs: Events = Events.shared()
	for id in RACES:
		var own := []
		var home := []
		for eid in evs.order:
			var ev: Dictionary = evs.events[eid]
			if not evs.files[eid].contains("races_3/"):
				continue
			if str(ev.get("requires", {}).get("region", "")) == HOMES[id]:
				home.append(ev)
			elif evs.files[eid].get_file() == id + "_events.json":
				own.append(ev)
		eq(own.size(), 3, id + ": three race events")
		eq(home.size(), 6, id + ": six homeland events")
		check(own.all(func(e): return _blue_for(e, id)), id + ": every race event has a blue option for it")
		check(own.any(func(e): return _recruits(e, id)), id + ": a race event recruits one")
		check(home.any(func(e): return _recruits(e, id)), id + ": a homeland event recruits one")
		check(home.all(func(e): return _blue_for(e, id)), id + ": every homeland event has a blue option for the race")
		check(home.any(func(e): return e["type"] == "station"), id + ": the homeland has its station greeting")


func test_the_homelands_fit_the_region_rules() -> void:
	for id in RACES:
		var r := Regions.get_region(HOMES[id])
		check(not r.is_empty(), HOMES[id] + " exists")
		eq(r["home_species"], id, HOMES[id] + ": its race")
		eq(r["events"], HOMES[id], HOMES[id] + ": its event tag is its id")
		check(r["recruit"].get(id, 0) == 8, HOMES[id] + ": the race is recruited here at weight 8")
		for sp in r["recruit"]:
			check(r["recruit"][sp] <= r["recruit"][id], "%s: %s weighs no more than the home race" % [HOMES[id], sp])
		check(r["places"].size() == 1 and r["places"][0]["type"] == "station" and r["places"][0].get("beacon", false), HOMES[id] + ": one station, a beacon")
	for p in Regions.problems():
		check(false, p)


func test_the_stations_recruit_the_races_the_lore_says() -> void:
	var cfg: Dictionary = Content.read("res://data/drift.json")
	check(cfg["stations"]["rusthold"]["recruit"].has("rattler") and cfg["stations"]["rusthold"]["recruit"].has("quillback"), "Rattler and Quillback at Rusthold")
	check(cfg["stations"]["prism"]["recruit"].has("choir"), "the Choir at the Prism")
	for id in ["revenant", "tessellate", "sable", "kite"]:
		var found := false
		var evs: Events = Events.shared()
		for eid in evs.order:
			if evs.files[eid].get_file() == id + "_events.json" and _recruits(evs.events[eid], id):
				found = true
		check(found, id + " joins through an event")
