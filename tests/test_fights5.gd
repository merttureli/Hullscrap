extends "res://tests/base_test.gd"
## The Beta 4 fights-and-balance fixes (fights5): the weak guns' numbers, the ion lock, a spare reactor in every starter's hold,
## the salvage a spared ship opens (test_salvage.gd has the page) and the threat rating's reading of a gun that cannot last.

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
