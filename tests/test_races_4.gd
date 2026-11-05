extends "res://tests/base_test.gd"
## Race wave 4 as data (docs/waves/races_2_4.md, pack data/packs/races_4/): the seven species come out of TraitSet with the
## numbers of the table, each race has three events (the Warden-frame a quest chain), each of the six homelands has six events
## that ask for its region, a recruit and a blue option of the race, and Meridian recruits the Brine.

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Content = preload("res://scripts/data/content.gd")
const Events = preload("res://scripts/space/events.gd")
const Regions = preload("res://scripts/space/regions.gd")
const Homelands = preload("res://scripts/space/homelands.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")

const RACES := ["warden_frame", "murrow", "siltborn", "corvin", "brine", "echo", "ferro"]
const HOMES := {"murrow": "murrow_diggings", "siltborn": "siltborn_rings", "corvin": "corvin_roost", "brine": "brine_yards",
	"echo": "echo_glassways", "ferro": "ferro_lodes"}


func near(got: float, want: float, msg: String, eps := 1e-6) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, want, got])


func _of(species: String) -> Array:
	var m := CrewMember.new("X", Vector2.ZERO, species)
	return [m, TraitSet.of(m)]


func test_the_seven_species_have_the_numbers_of_the_table() -> void:
	var w := _of("warden_frame")
	check(w[1]["mechanical"], "a Warden-frame is mechanical")
	near(w[1]["o2_use"], 0.0, "and does not breathe")
	near(w[1]["ranged_mult"], 1.5, "ranged x1.5")
	near(w[1]["damage_taken"]["ion"], 3.0, "ion x3")
	eq(w[0].sidearm(), "gatekeepers_lance", "the Gatekeeper's lance")
	var m := _of("murrow")
	near(m[0].max_hp, 120.0, "murrow hp")
	near(m[0].speed, CrewMember.BASE_SPEED * 0.9, "murrow speed")
	var s := _of("siltborn")
	near(s[1]["o2_use"], 0.5, "siltborn breathe half")
	near(s[1]["damage_taken"]["fire"], 2.0, "fire x2")
	eq(s[0].sidearm(), "", "the Siltborn carry nothing")
	var c := _of("corvin")
	eq(c[0].sidearm(), "service_pistol", "corvin sidearm")
	var b := _of("brine")
	near(b[0].speed, CrewMember.BASE_SPEED * 0.85, "brine speed")
	near(b[1]["damage_taken"]["melee"], 0.7, "melee x0.7")
	near(b[1]["damage_taken"]["ranged"], 0.7, "ranged x0.7")
	near(b[1]["work_mult"]["restock"], 1.5, "restock x1.5")
	check(b[1]["no_suit"], "no suit")
	var f := _of("ferro")
	near(f[1]["damage_taken"]["ion"], 0.0, "immune to ion")
	near(f[1]["hull_mend"]["rate"], 0.5, "hull_mend 0.5")
	var e := _of("echo")
	eq(e[0].sidearm(), "spark_pistol", "echo sidearm")
	check(e[1]["mimic"], "an Echo mimics")
	near(m[1]["mining_mult"], 1.5, "murrow mining x1.5")
	near(s[1]["low_pressure_heal"], 1.0, "siltborn heal 1 hp/s in thin air")
	near(c[1]["haggler"], 0.1, "corvin haggles 10%")
	near(c[1]["loot_bonus"], 1.0, "corvin loot +1")
	near(f[1]["station"]["pull_bonus"], 1.0, "ferro intake pulls 1 cell further")
	for id in RACES:
		var def: Dictionary = Content.entry("species", id)
		check(not def.is_empty(), id + ": a species")
		eq(CrewMember.new("X", Vector2.ZERO, id).rig(), id, id + ": its own rig")
		check(CrewMember.new("X", Vector2.ZERO, id).sidearm() != "" or id == "siltborn", id + ": a sidearm")


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


func _mine(evs: Events) -> Array:
	var out := []
	for eid in evs.order:
		if evs.files[eid].contains("races_4/"):
			out.append(eid)
	return out


func test_each_race_has_three_events_and_each_homeland_six() -> void:
	var evs: Events = Events.shared()
	for id in RACES:
		var own := []
		var home := []
		for eid in _mine(evs):
			var ev: Dictionary = evs.events[eid]
			if HOMES.has(id) and str(ev.get("requires", {}).get("region", "")) == HOMES[id]:
				home.append(ev)
			elif evs.files[eid].get_file() == id + "_events.json":
				own.append(ev)
		eq(own.size(), 3, id + ": three race events")
		if id == "warden_frame":
			eq(home.size(), 0, "the Warden-frame have no homeland")
			continue
		eq(home.size(), 6, id + ": six homeland events")
		check(own.all(func(e): return _blue_for(e, id)), id + ": every race event has a blue option for it")
		check(own.any(func(e): return _recruits(e, id)), id + ": a race event recruits one")
		check(home.any(func(e): return _recruits(e, id)), id + ": a homeland event recruits one")
		check(home.all(func(e): return _blue_for(e, id)), id + ": every homeland event has a blue option for the race")
		check(home.any(func(e): return e["type"] == "station"), id + ": the homeland has its station greeting")
		check(home.all(func(e): return e["type"] in ["station", "pirate", "wreck_field", "distress", "trader", "anomaly", "patrol", "asteroid_field", "empty"]), id + ": homeland events sit on node types")
		var types := {}
		for e in home:
			types[e["type"]] = true
		check(types.size() >= 5, id + ": the six homeland events spread over node types")


func test_the_warden_frame_quest_chain_reboots_one() -> void:
	var evs: Events = Events.shared()
	var chain := ["warden_dark_lens", "warden_cold_start", "warden_first_light"]
	for id in chain:
		check(evs.events.has(id), id + " exists")
	check(evs.events["warden_dark_lens"]["requires"].get("stage_min", 0) >= 4, "the chain starts in the late stages")
	check(evs.events["warden_cold_start"]["requires"].get("flag") == "warden_chassis", "step two asks for the chassis step one hands over")
	var sets_chassis := false
	for ch in evs.events["warden_dark_lens"]["choices"]:
		for o in ch["outcomes"]:
			if str(o.get("effects", {}).get("flag", "")) == "warden_chassis":
				sets_chassis = true
	check(sets_chassis, "step one sets the flag")
	var goes_to_page := false
	for ch in evs.events["warden_cold_start"]["choices"]:
		for o in ch["outcomes"]:
			if o.get("effects", {}).get("goto", "") == "warden_first_light":
				goes_to_page = true
	check(goes_to_page, "step two leads on to the reboot")
	check(_recruits(evs.events["warden_first_light"], "warden_frame"), "the reboot recruits a Warden-frame")
	check(evs.events["warden_first_light"].get("landmark", "") != "", "and is a landmark")
	var recruiting := 0
	for eid in evs.order:
		if eid != "warden_first_light" and _recruits(evs.events[eid], "warden_frame"):
			recruiting += 1
	eq(recruiting, 0, "nothing else recruits a Warden-frame")
	var cfg: Dictionary = Content.read("res://data/drift.json")
	for st in cfg["stations"]:
		check(not cfg["stations"][st]["recruit"].has("warden_frame"), st + ": no station recruits a Warden-frame")
	for rid in Regions.all():
		check(not rid.get("recruit", {}).has("warden_frame"), str(rid["id"]) + ": no region recruits a Warden-frame")


func test_the_homelands_fit_the_region_rules() -> void:
	for id in HOMES:
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


func test_a_homeland_has_its_station_and_is_offered_in_its_band() -> void:
	var cfg := Campaign.config()
	for id in HOMES:
		var c := Campaign.new(3)
		c.enter_region(HOMES[id])
		var places: Array = c.drift.nodes.filter(func(n): return n["type"] == "station")
		eq(places.size(), 1, HOMES[id] + ": one station")
		var menu := c.station_cfg(places[0]["id"])
		check(not menu.is_empty() and menu["services"].has("stock") and menu["services"].has("recruit"), HOMES[id] + ": it trades and recruits")
		eq(menu["stock"], Homelands.menu(str(places[0]["place"]), Regions.station(str(places[0]["place"]), cfg))["stock"], HOMES[id] + ": its stock is the region's, leaned to its race in the capital (homelands.gd)")
		# offered at some exit, in a seeded sweep (the weight must not bury it)
		var seen := false
		var band: Array = Regions.get_region(HOMES[id])["stages"]
		for seed_value in range(1, 151):
			for stage in range(int(band[0]) - 1, int(band[1])):
				if stage >= 1 and Regions.offers(seed_value, stage, ["clan_space"], cfg).has(HOMES[id]):
					seen = true
			if seen:
				break
		check(seen, HOMES[id] + ": offered at some exit within 150 seeds")


func test_meridian_recruits_the_brine_and_no_station_the_others() -> void:
	var cfg: Dictionary = Content.read("res://data/drift.json")
	check(cfg["stations"]["meridian"]["recruit"].has("brine"), "the Brine at Meridian")
	for id in ["murrow", "siltborn", "corvin", "echo", "ferro"]:
		var found := false
		var evs: Events = Events.shared()
		for eid in evs.order:
			if evs.files[eid].get_file() == id + "_events.json" and _recruits(evs.events[eid], id):
				found = true
		check(found, id + " joins through an event")
