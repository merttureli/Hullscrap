extends "res://tests/base_test.gd"
## The Beta 4 fights-and-balance fixes (fights5): the weak guns' numbers, the ion lock, a spare reactor in every starter's hold,
## the salvage a spared ship opens (test_salvage.gd has the page) and the threat rating's reading of a ship that lost its shield or its gun
## (the rating's formula is unchanged: the starter fix moved the outcomes, see the fights5 handoff for the proposal).

const Weapons = preload("res://scripts/combat/weapons.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Threat = preload("res://scripts/space/threat.gd")

const STARTERS := ["rustbucket", "courier", "prism"]


func test_the_weak_guns_land_something() -> void:
	var w := Weapons.new()
	var rb: Dictionary = w.defs["rattle_burst_scrap"]  # as written (def() applies the turret's 0.6)
	eq([rb["damage"], rb["shots"], rb["cooldown"]], [2.0, 1.0, 0.8], "Rattle Burst: one shot of damage 2 (1 on the bench landed 0.06 hp/s)")
	var sh: Dictionary = w.defs["shrapnel_cannon_scrap"]
	eq([sh["damage"], sh["shots"], sh["range"], sh["cooldown"]], [2.0, 6.0, 600.0, 4.4], "Shrapnel Cannon: six pellets of 2 over 600 px (0.13 hp/s on the bench before, 0.43 after)")


func test_an_ion_hit_locks_the_bubble_for_five_seconds() -> void:
	eq(Shields.ION_LOCK, 5.0, "one Ion Blast (5.25 s cycle) keeps a bubble down almost all the time")


func test_every_starter_carries_a_spare_reactor() -> void:
	for name in STARTERS:
		var ship: Ship = Ship.from_design("res://data/ships/starter_%s.json" % name)
		check(ship.inventory.count("reactor_mk1") >= 1, "%s: a Reactor Mk1 in the hold (a wrecked reactor ended runs quietly)" % name)


# --- the threat rating --------------------------------------------------------------------------------------

func _ship(path: String) -> Ship:
	return Ship.from_design(path)


func _drop(ship: Ship, family: String) -> void:
	for uid in ship.components.instances.keys():
		if str(ship.components.def(ship.components.instances[uid]["id"]).get("family", "")) == family:
			ship.components.remove_uid(uid)


func test_an_unshielded_exposed_gun_or_a_dead_one_rates_more_danger() -> void:
	var foe := _ship("res://data/ships/pirate_raider.json")
	var courier := _ship("res://data/ships/starter_courier.json")
	var base := float(Threat.rate(foe, courier)["ratio"])
	var bare := _ship("res://data/ships/starter_courier.json")
	_drop(bare, "shield")
	check(float(Threat.rate(foe, bare)["ratio"]) > base, "the Courier without its shield reads a more dangerous foe (%.2f against %.2f)" % [float(Threat.rate(foe, bare)["ratio"]), base])
	var dead := _ship("res://data/ships/starter_courier.json")
	for uid in dead.components.instances.keys():
		dead.components.instances[uid]["out_hp"] = 0 if dead.components.has_outside(uid) else dead.components.instances[uid]["out_hp"]
	check(float(Threat.rate(foe, dead)["ratio"]) > base * 5.0, "with its gun shot out the foe is far more dangerous")
	var r := Threat.rate(foe, courier)
	check(int(r["skulls"]) >= 1 and int(r["skulls"]) <= 5, "the output is still 1 to 5 skulls")


func test_a_light_kinetic_round_counts_over_the_plating_floor() -> void:
	var w := Weapons.new().def("rattle_burst_scrap")
	var cfg := Threat.config()
	var share := minf(1.0, float(w["damage"]) / float(cfg["kinetic_floor"]))
	check(share < 0.5, "the Rattle Burst's hit counts for %s of itself" % str(share))
	var ship := _ship("res://data/ships/pirate_raider.json")
	for uid in ship.components.instances.keys():
		var id := str(ship.components.instances[uid]["id"])
		if str(ship.components.def(id).get("family", "")) == "weapon" and id != "rattle_burst_scrap":
			ship.components.remove_uid(uid)
	var want: float = float(w["damage"]) * float(cfg["kind_factor"]["bolt"]) * share * (float(w["accuracy"]) - float(cfg["turret_miss"])) / float(w["cooldown"])
	check(absf(float(Threat.power(ship, 0.5)["dps"]) - want) < 1e-6, "and the raider's turret alone is rated %.3f dps" % want)
