extends SceneTree
## Not a test (the runner only loads test_*.gd). The workshop of the test ships of the K page (data/test_ships.json, data/ships/test/*.json):
##   godot --headless --path . --script res://tests/tool_test_ships.gd -- make [only=id,id]   rebuilds the designs from the `build` of each entry
##   godot --headless --path . --script res://tests/tool_test_ships.gd -- measure [n=2]       prints each ship's Threat power against its stage's median enemy
## The median enemy of a stage: n generated enemies of every (fielded faction, role) cell (tool_standoff.gd cell_enemies), rated with the same Threat code the game uses.
## A ship is built like a bench build (tool_standoff.gd build_from: Shipgen's hull grammar and mount rules, every gun mounted) and gets its crew.

const Standoff = preload("res://tests/tool_standoff.gd")
const TestFights = preload("res://scripts/combat/test_fights.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Threat = preload("res://scripts/space/threat.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")

static var _medians := {}


func _initialize() -> void:
	var args := {}
	var cmd := ""
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		if kv.size() == 1:
			cmd = kv[0]
		else:
			args[kv[0]] = kv[1]
	match cmd:
		"make":
			make(str(args.get("only", "")))
		"measure":
			print(table(int(args.get("n", 2))))
		_:
			printerr("tool_test_ships: make | measure")
	quit(0)


## The ship of a roster entry (a bench build with its crew), or null.
static func build(e: Dictionary):
	var ship = Standoff.build_from(int(e["stage"]), e["build"])
	if ship != null:
		ship.name = str(e["name"])
		Jobs.spawn_crew(ship)
	return ship


static func make(only := "") -> void:
	for e in TestFights.config()["ships"]:
		if only != "" and not only.split(",").has(str(e["id"])):
			continue
		var ship = build(e)
		if ship == null:
			printerr("test ship %s: no hull found" % e["id"])
			continue
		var path := ProjectSettings.globalize_path(str(e["design"]))
		var fa := FileAccess.open(path, FileAccess.WRITE)
		fa.store_string(JSON.stringify(ship.to_dict(), "\t"))
		fa.close()
		print("test ship %s: %d parts, hull %s -> %s" % [e["id"], ship.components.instances.size(), str(ship.grid.size), e["design"]])


## The median Threat power of the enemies of `stage` (the fielded factions x their roles, `n` seeds a cell). Cached.
static func median(stage: int, n := 2) -> float:
	var key := "%d|%d" % [stage, n]
	if _medians.has(key):
		return _medians[key]
	var powers: Array = []
	for f in Standoff.FIELDED[stage]:
		for role in Shipgen.roles_of(str(f)):
			for e in Standoff.cell_enemies(stage, str(f), str(role), n, []):
				var ship = Session.load_ship(e["spec"])
				if ship != null:
					powers.append(float(Threat.power(ship, float(ship.get_meta("ai", {}).get("aim_skill", 0.6)))["power"]))
	powers.sort()
	_medians[key] = powers[powers.size() / 2] if not powers.is_empty() else 0.0
	return _medians[key]


## A ship's Threat power as a player (the table's player_aim).
static func power_of(ship) -> float:
	return float(Threat.power(ship, float(Threat.config()["player_aim"]))["power"])


static func table(n := 2) -> String:
	var lines := ["id | stage | power | median enemy | ratio | guns | layers"]
	for e in TestFights.config()["ships"]:
		var ship = Session.load_ship(str(e["design"]))
		if ship == null:
			lines.append("%s: no design" % e["id"])
			continue
		var st := TestFights.stats_of(ship, float(Threat.config()["player_aim"]))
		var m := median(int(e["stage"]), n)
		lines.append("%s | %d | %.1f | %.1f | %.2f | %d | %d" % [e["id"], e["stage"], st["power"], m, st["power"] / maxf(m, 0.001), st["guns"], st["layers"]])
	return "\n".join(lines)
