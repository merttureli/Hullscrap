extends "res://tests/base_test.gd"
## The six test ships of the K page (data/test_ships.json, data/ships/test; rebuilt by tests/tool_test_ships.gd): each loads with its crew, mounts every gun and
## shield it was built with, carries only parts of its pool, and sits in its band of the stage's median enemy (the fielded factions, the Threat code of the game).

const Tool = preload("res://tests/tool_test_ships.gd")
const TestFights = preload("res://scripts/combat/test_fights.gd")
const Session = preload("res://scripts/combat/combat_session.gd")

## The band of Threat power / the stage's median enemy that each ship must sit in.
const BANDS := {"scraped_by": [0.5, 0.7], "curve_early": [0.9, 1.3], "curve_mid": [0.85, 1.15], "ahead": [1.2, 1.5], "flagship_ready": [1.6, 2.1], "lucky": [1.6, 2.2]}


func _counts(ship) -> Dictionary:
	var got := {}
	for uid in ship.components.instances:
		var id := str(ship.components.instances[uid]["id"])
		got[id] = int(got.get(id, 0)) + 1
	return got


func test_every_test_ship_loads_mounts_its_guns_and_keeps_to_its_pool() -> void:
	var cfg := TestFights.config()
	eq(cfg["ships"].map(func(e): return e["id"]), BANDS.keys(), "the roster")
	for e in cfg["ships"]:
		var ship = Session.load_ship(str(e["design"]))
		check(ship != null, "%s loads" % e["id"])
		if ship == null:
			continue
		check(not ship.crew.is_empty(), "%s has its crew" % e["id"])
		var got := _counts(ship)
		var want := {}
		for id in e["build"]["weapons"] + e["build"]["shields"]:
			want[id] = int(want.get(id, 0)) + 1
			check(cfg["pools"][str(e["pool"])].has(id), "%s: %s is in its pool (%s)" % [e["id"], id, e["pool"]])
		for id in want:
			eq(int(got.get(id, 0)), int(want[id]), "%s carries %d x %s" % [e["id"], want[id], id])


func test_every_test_ship_sits_in_its_threat_band() -> void:
	for e in TestFights.config()["ships"]:
		var ship = Session.load_ship(str(e["design"]))
		if ship == null:
			continue
		var ratio: float = Tool.power_of(ship) / maxf(Tool.median(int(e["stage"])), 0.001)
		var band: Array = BANDS[str(e["id"])]
		check(ratio >= band[0] and ratio <= band[1], "%s: %.2f x the stage %d median, wanted %s" % [e["id"], ratio, e["stage"], str(band)])
