extends SceneTree
## Not a test. Threat.power of generated enemies, per faction and stage, the mean over N seeds of the ships the campaign would send (the size
## from the budget as Shipgen.pick_size does). Run it on a branch and on main and compare: the enemy variety track keeps it within +-15%.
##   godot --headless --path . --script res://tests/tool_enemy_parity.gd [-- seeds=40 factions=rustfangs,clans out=<json>]

const Shipgen = preload("res://scripts/space/shipgen.gd")
const Threat = preload("res://scripts/space/threat.gd")
const Content = preload("res://scripts/data/content.gd")

const JUMPS_A_STAGE := 12.5


func _mean(f: String, budget: float, stage: int, seeds: int) -> float:
	var sum := 0.0
	var n := 0
	for k in seeds:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5000 + k
		var ship = Shipgen.build(f, Shipgen.pick_size(budget, rng), 5000 + k * 31, budget, {"stage": stage})
		if ship != null:
			sum += float(Threat.power(ship, float(ship.get_meta("ai", {}).get("aim_skill", 0.6)))["power"])
			n += 1
	return sum / maxf(n, 1)


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var seeds := int(args.get("seeds", 40))
	var facs: Array = str(args["factions"]).split(",") if args.has("factions") else Shipgen.factions()
	var out := {}
	for f in facs:
		if not Shipgen.tables()["factions"].has(f):
			continue
		for stage in [1, 3, 5]:
			var j := roundi(JUMPS_A_STAGE * (float(stage) - 0.5))
			var tier := 3 if j >= 25 else (2 if j >= 10 else 1)
			var kin := str(Shipgen.tables()["factions"][f].get("lines_as", f))
			var danger := 1.0
			for r in Content.regions():
				if str(r.get("enemies", "")) == kin:
					danger = float(r.get("danger", 1.0))
					break
			var budget := Shipgen.budget_for(tier, j, danger, "normal", stage)
			var sum := 0.0
			var n := 0
			for k in seeds:
				var rng := RandomNumberGenerator.new()
				rng.seed = 5000 + k
				var ship = Shipgen.build(f, Shipgen.pick_size(budget, rng), 5000 + k * 31, budget, {"stage": stage})
				if ship != null:
					sum += float(Threat.power(ship, float(ship.get_meta("ai", {}).get("aim_skill", 0.6)))["power"])
					n += 1
			out["%s/s%d" % [f, stage]] = snappedf(sum / maxf(n, 1), 0.01)
			var mean := sum / maxf(n, 1)
			if Shipgen.tables()["factions"][f].has("lines_as"):
				var key := "%s/s%d" % [kin, stage]
				if not out.has(key):
					out[key] = _mean(kin, budget, stage, seeds)
				print("   ratio to %s: %.2f" % [kin, mean / maxf(float(out[key]), 0.01)])
			print("%-10s stage %d budget %6.1f  mean power %7.2f  (%d ships)" % [f, stage, budget, sum / maxf(n, 1), n])
	if args.has("out"):
		FileAccess.open(str(args["out"]), FileAccess.WRITE).store_string(JSON.stringify(out))
	quit(0)
