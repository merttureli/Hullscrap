extends "res://tests/base_test.gd"
## The weapon table (data/weapons.json plus the packs' weapons.json): the rapid guns are few and auto turrets, and every other
## gun is slower than one shot a second (Beta 3 pacing, docs/CONTENT.md 4).

const Weapons = preload("res://scripts/combat/weapons.gd")

const RAPID_SHARE := [0.10, 0.15]  ## of the player's guns (every entry that is not a test_*)


## Shots a second of weapon entry `w` (Weapons.def): shots / cooldown. A flak volley's pellets fly together: one shot. So does the volley of a
## fixed gun's barrels (a burst battery or a gun strip: one pull of the trigger, G2).
func _rate(w: Dictionary) -> float:
	var shots := 1.0 if str(w["kind"]) == "flak" or not bool(w["turret"]) else float(w["shots"])
	return shots / float(w["cooldown"])


func _guns() -> Array:
	var weapons := Weapons.new()
	var out := []
	for id in weapons.defs:
		if not str(id).begins_with("test_"):
			out.append(weapons.def(id))
	return out


func test_only_ten_to_fifteen_percent_of_the_guns_are_rapid() -> void:
	var guns := _guns()
	var rapid := 0
	for w in guns:
		rapid += 1 if bool(w.get("rapid", false)) else 0
	var share := float(rapid) / float(guns.size())
	check(share >= RAPID_SHARE[0] - 1e-9 and share <= RAPID_SHARE[1] + 1e-9, "%d of %d guns are rapid (%.1f%%), the brief wants 10 to 15%%" % [rapid, guns.size(), share * 100.0])


func test_a_gun_that_fires_a_shot_a_second_is_marked_rapid_and_is_an_auto_turret() -> void:
	for w in _guns():
		var rate := _rate(w)
		if rate >= 1.0 - 1e-9:
			check(bool(w.get("rapid", false)), "%s fires %.2f shots a second: it must be marked rapid (or slowed)" % [w["id"], rate])
			check(bool(w["turret"]), "%s is rapid, so it is a turret" % w["id"])
		else:
			check(not bool(w.get("rapid", false)), "%s fires %.2f shots a second: it is not rapid" % [w["id"], rate])


func test_every_rapid_gun_is_a_light_quick_turret() -> void:
	var entries: Dictionary = Weapons.new().defs  # as written in the data (def() applies the turret's 0.6 to the damage)
	var best_track := 0.0
	var best_acc := 0.0
	var tiers := {}
	for w in _guns():
		if bool(w.get("rapid", false)):
			var cd := float(w["cooldown"])
			check(cd >= 0.4 - 1e-9 and cd <= 0.8 + 1e-9, "%s: cooldown %s is 0.4 to 0.8 s" % [w["id"], str(cd)])
			# damage 1, except the Rattle Burst: at 1 (0.6 after the turret factor) the plating ate it, 0.056 hp/s on the bench (Beta 4 mechanics audit, fights5)
			var want_damage := 2.0 if w["id"] == "rattle_burst_scrap" else 1.0
			check(float(entries[w["id"]]["damage"]) == want_damage and int(w["shots"]) == 1, "%s: one shot of damage %s" % [w["id"], str(want_damage)])
			best_track = maxf(best_track, float(w["track"]))
			best_acc = maxf(best_acc, float(w["accuracy"]))
	var sov := Weapons.new().def("sovereign_turret")
	eq([float(sov["track"]), float(sov["accuracy"])], [best_track, best_acc], "the tier-3 rapid gun tracks and aims best of all the rapid guns")
	for id in ["rattle_burst_scrap", "laser_turret_mk1", "kett_drone_picket", "sovereign_turret"]:
		tiers[id] = bool(Weapons.new().def(id).get("rapid", false))
	eq(tiers, {"rattle_burst_scrap": true, "laser_turret_mk1": true, "kett_drone_picket": true, "sovereign_turret": true}, "a tier-1, a tier-2 and a tier-3 gun are rapid")


func test_the_heavy_guns_are_slower_and_hit_harder_than_before() -> void:
	var weapons := Weapons.new()
	# [cooldown, damage] as they were in Beta 2 -> now: lasers, bolts and flak x1.75 / x1.5 (damage to 0.5), beams the same,
	# missiles x1.4 / x1.25 (the Shrapnel Cannon's row is 1.34, not 1.0: its pellets went 1.5 -> 2 in the fights5 balance pass)
	for row in [["laser_mk1", 1.2, 2.0], ["laser_mk2", 1.0, 3.0], ["pulse_mk1", 1.5, 2.0], ["shrapnel_cannon_scrap", 2.5, 1.34], ["heat_lance_neon", 6.0, 3.0], ["artemis_mk1", 5.0, 3.0], ["gilded_lance", 1.6, 5.0]]:
		var w := weapons.def(row[0])
		var kind := str(w["kind"])
		var cd_mult := 1.4 if kind == "missile" else 1.75
		var dmg_mult := 1.25 if kind == "missile" else 1.5
		check(absf(float(w["cooldown"]) - float(row[1]) * cd_mult) <= 0.06, "%s: cooldown %s is about %s x %s" % [row[0], str(w["cooldown"]), str(row[1]), str(cd_mult)])
		check(absf(float(w["damage"]) - float(row[2]) * dmg_mult) <= 0.26, "%s: damage %s is about %s x %s" % [row[0], str(w["damage"]), str(row[2]), str(dmg_mult)])
