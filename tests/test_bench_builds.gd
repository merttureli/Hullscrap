extends "res://tests/base_test.gd"
## The player-like ships of the balance tools (tests/tool_standoff.gd BUILDS, read by tool_flagships, tool_gun_bench and test_flagships) mount every
## gun and shield they list: Shipgen drops a gun that finds no wall to mount through, and until 2026-11 builds 3 to 7 flew without their pulse
## and a turret, so every bench number of a stage ship understated its guns.

const Standoff = preload("res://tests/tool_standoff.gd")


func test_every_build_mounts_all_its_guns_and_shields() -> void:
	for stage in Standoff.BUILDS:
		var b: Dictionary = Standoff.BUILDS[stage]
		var ship = Standoff.build_player(stage)
		check(ship != null, "build %d is built" % stage)
		if ship == null:
			continue
		var got := {}
		for uid in ship.components.instances:
			var id := str(ship.components.instances[uid]["id"])
			got[id] = int(got.get(id, 0)) + 1
		var want := {}
		for id in b["weapons"] + b["shields"]:
			want[id] = int(want.get(id, 0)) + 1
		for id in want:
			eq(int(got.get(id, 0)), int(want[id]), "build %d carries %d x %s" % [stage, want[id], id])
