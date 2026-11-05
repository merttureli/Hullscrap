extends SceneTree
## Not a test. The full boarding walkability sweep (Beta 3 owner-bugs track): for every faction/style x size x seeds of generated enemy ships, every hand-made
## design (data/ships, data/packs/*/ships) and the wrecks of both, builds the boarding site and says how many ships have parts that block the way.
##   godot --headless --path . --script res://tests/tool_walkable.gd -- [seeds=30] [budget=150] [only=designs|generated] [factions=a,b] [v]
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Content = preload("res://scripts/data/content.gd")
const Check = preload("res://tests/walk_check.gd")

const SIZES := ["small", "medium", "large"]
var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_run.call_deferred()


func _run() -> void:
	var seeds := int(args.get("seeds", 30))
	var budget := float(args.get("budget", 150.0))
	var only := str(args.get("only", ""))
	var why := {}
	if only != "designs":
		var total := 0
		var bad := 0
		for f in (str(args["factions"]).split(",") if args.has("factions") else Shipgen.factions()):
			var fb := 0
			var n := 0
			for size in SIZES:
				for sd in seeds:
					var e = Shipgen.build(f, size, sd + 1, budget)
					if e == null:
						continue
					Jobs.spawn_enemy_crew(e)
					var a: Dictionary = Check.audit(JSON.parse_string(JSON.stringify(e.to_dict())), sd + 1)
					n += 1
					if not (a["site"] and a["strict"] == 0):
						fb += 1
						_tally(why, a)
						if args.has("v"):
							print("  %s %s %d: %s" % [f, size, sd + 1, a])
			print("generated %-14s %3d / %3d fail" % [f, fb, n])
			total += n
			bad += fb
		print("GENERATED: %d of %d ships fail (%.1f%%)" % [bad, total, 100.0 * bad / maxf(total, 1)])
	if only != "generated":
		var paths: Array = _designs()
		var bad := 0
		for p in paths:
			var sh = Ship.from_design(p)
			if sh == null:
				continue
			Jobs.spawn_crew(sh)
			var a: Dictionary = Check.audit(JSON.parse_string(JSON.stringify(sh.to_dict())), 7)
			if not (a["site"] and a["strict"] == 0):
				bad += 1
				_tally(why, a)
				print("  design %s: %s" % [p, a])
		print("DESIGNS: %d of %d fail (%.1f%%)" % [bad, paths.size(), 100.0 * bad / maxf(paths.size(), 1)])
	var keys: Array = why.keys()
	keys.sort_custom(func(a, b): return why[a] > why[b])
	for k in keys:
		print("  blocking part %s: %d ships" % [k, why[k]])
	quit(0)


func _tally(why: Dictionary, a: Dictionary) -> void:
	why["(rooms cut as played)"] = int(why.get("(rooms cut as played)", 0)) + (1 if a["shipped"] > 0 else 0)
	why["(parts made walk-through, total)"] = int(why.get("(parts made walk-through, total)", 0)) + int(a["lifted"])
	if not a["site"]:
		why["(no hatch)"] = int(why.get("(no hatch)", 0)) + 1
	for id in a["blockers"]:
		why[id] = int(why.get(id, 0)) + 1


static func _designs() -> Array:
	var out: Array = Content.ships().map(func(e): return str(e["path"]))
	out.sort()
	return out
