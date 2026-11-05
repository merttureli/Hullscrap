extends SceneTree
## Not a test. How often each new gun (the pack guns_2) is on a generated enemy, per run stage (docs/GUNS.md 9, G2).
##   godot --headless --path . --script res://tests/tool_gun_census.gd -- [n=200] [stages=1,2,3,4,5,6]
## For each stage `n` ships are generated through the real pipeline (Shipgen.spec with the budget of the middle of the stage, the factions of the enemy tables
## taken in turn, the Hollow's ghosts and the Barons left out); the table is the share of ships that carry the gun.

const Shipgen = preload("res://scripts/space/shipgen.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Standoff = preload("res://tests/tool_standoff.gd")

var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_run.call_deferred()


func _run() -> void:
	var n := int(args.get("n", 200))
	var stages: Array = Array(str(args.get("stages", "1,2,3,4,5,6")).split(",")).map(func(x): return int(x))
	var pack = JSON.parse_string(FileAccess.get_file_as_string("res://data/packs/guns_2/weapons.json"))["weapons"]
	var factions: Array = []
	for f in Shipgen.tables()["factions"]:
		if f not in ["hollow", "barons"]:
			factions.append(str(f))
	factions.sort()
	var table := {}  # gun -> stage -> ships carrying it
	var armed := {}  # stage -> ships with any new gun
	for st in stages:
		armed[st] = 0
		var j := roundi(12.5 * (float(st) - 0.5))
		var tier := 3 if j >= 25 else (2 if j >= 10 else 1)
		for k in n:
			var seed_value: int = 101 + k * 7919 + st * 31
			var f: String = factions[k % factions.size()]
			var budget: float = Shipgen.budget_for(tier, j, Standoff.danger_for(str(Shipgen.tables()["factions"][f].get("lines_as", f))), "normal", st)
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var ship: Ship = Session.load_ship(Shipgen.spec(f, Shipgen.pick_size(budget, rng), seed_value, budget, false, st))
			if ship == null:
				continue
			var seen := {}
			for uid in ship.components.instances:
				var id := str(ship.components.instances[uid]["id"])
				if pack.has(id):
					seen[id] = true
			for id in seen:
				if not table.has(id):
					table[id] = {}
				table[id][st] = int(table[id].get(st, 0)) + 1
			armed[st] += 1 if not seen.is_empty() else 0
	var head := "| gun |"
	for st in stages:
		head += " stage %d |" % st
	print(head)
	print("|---|" + "---|".repeat(stages.size()))
	var ids: Array = pack.keys()
	ids.sort()
	for id in ids:
		var row := "| %s |" % id
		for st in stages:
			row += " %.1f%% |" % (100.0 * float(table.get(id, {}).get(st, 0)) / float(n))
		print(row)
	var row := "| ships with any new gun |"
	for st in stages:
		row += " %.0f%% |" % (100.0 * float(armed[st]) / float(n))
	print(row)
	quit(0)
