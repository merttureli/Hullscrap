extends SceneTree
## Not a test. The on-foot fight bench (model in tests/foot_bench.gd): foes killed per 100 hp lost, by foe kind and by site kind.
##   godot --headless --path . --script res://tests/tool_foot_bench.gd -- <seeds> <sites, comma list or all> <gear> <rounds> <followers> [first seed]
## gear: start, basic, exo, medic. rounds: the rounds in the hold. followers: 0-2 crew who come along.
const Bench = preload("res://tests/foot_bench.gd")


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var n := int(a[0]) if a.size() > 0 else 40
	var sites: Array = Bench.SITES if a.size() < 2 or a[1] == "all" else Array(a[1].split(","))
	var gear := a[2] if a.size() > 2 else "start"
	var rounds := int(a[3]) if a.size() > 3 else 60
	var fol := int(a[4]) if a.size() > 4 else 0
	var first := int(a[5]) if a.size() > 5 else 1
	var tot := {"kills": {}, "lost": {}, "ttk": [], "runs": 0, "died": 0, "lost_total": 0.0, "kills_total": 0, "time": 0.0, "dry": 0, "party_down": 0, "pool": 0.0, "medkits": 0, "rounds_left": 0, "shots": 0, "hits": 0}
	print("gear=%s rounds=%d followers=%d seeds=%d" % [gear, rounds, fol, n])
	print("%-20s %5s %6s %7s %8s %6s %6s %5s" % ["site", "runs", "foes", "kills", "hp lost", "k/100", "ttk s", "died%"])
	for kind in sites:
		var st := {"kills": {}, "lost": {}, "ttk": [], "runs": 0, "died": 0, "lost_total": 0.0, "kills_total": 0, "foes": 0}
		for i in n:
			var r: Dictionary = Bench.run(kind, first + i * 37, gear, rounds, fol)
			if r.is_empty():
				continue
			st["runs"] += 1
			tot["runs"] += 1
			st["foes"] += int(r["foes"])
			st["died"] += 1 if r["died"] else 0
			tot["died"] += 1 if r["died"] else 0
			st["lost_total"] += float(r["lost_total"])
			tot["lost_total"] += float(r["lost_total"])
			tot["time"] += float(r["time"])
			tot["pool"] += float(r["hp_pool"])
			tot["party_down"] += int(r["party_down"])
			tot["medkits"] += int(r["medkits"])
			tot["shots"] += int(r["shots"])
			tot["hits"] += int(r["hits"])
			tot["rounds_left"] += int(r["rounds_left"])
			tot["dry"] += 1 if float(r["dry_s"]) > 0.0 else 0
			st["ttk"].append_array(r["ttk"])
			tot["ttk"].append_array(r["ttk"])
			for k in r["kills"]:
				st["kills"][k] = int(st["kills"].get(k, 0)) + int(r["kills"][k])
				tot["kills"][k] = int(tot["kills"].get(k, 0)) + int(r["kills"][k])
				st["kills_total"] += int(r["kills"][k])
				tot["kills_total"] += int(r["kills"][k])
			for k in r["lost"]:
				st["lost"][k] = float(st["lost"].get(k, 0.0)) + float(r["lost"][k])
				tot["lost"][k] = float(tot["lost"].get(k, 0.0)) + float(r["lost"][k])
		print("%-20s %5d %6.1f %7.1f %8.0f %6.2f %6.2f %5.0f" % [kind, st["runs"], float(st["foes"]) / maxf(st["runs"], 1), float(st["kills_total"]) / maxf(st["runs"], 1),
			float(st["lost_total"]) / maxf(st["runs"], 1), 100.0 * st["kills_total"] / maxf(st["lost_total"], 1.0), _mean(st["ttk"]), 100.0 * st["died"] / maxf(st["runs"], 1)])
	print("--- by foe kind (all sites): kills, hp lost to it, kills per 100 hp lost to it")
	for k in tot["kills"]:
		print("  %-16s %5d %8.0f %6.2f" % [k, tot["kills"][k], float(tot["lost"].get(k, 0.0)), 100.0 * tot["kills"][k] / maxf(float(tot["lost"].get(k, 0.0)), 1.0)])
	print("  other/unattributed hp lost: %.0f" % float(tot["lost"].get("other", 0.0)))
	print("TOTAL runs=%d kills/100hp=%.2f ttk=%.2fs died=%.0f%% mean_time=%.0fs dry_runs=%.0f%% party_down/run=%.2f medkits/run=%.2f rounds_left/run=%.1f kills per party hp pool=%.2f hit%%=%.0f" % [
		tot["runs"], 100.0 * tot["kills_total"] / maxf(tot["lost_total"], 1.0), _mean(tot["ttk"]), 100.0 * tot["died"] / maxf(tot["runs"], 1), tot["time"] / maxf(tot["runs"], 1),
		100.0 * tot["dry"] / maxf(tot["runs"], 1), float(tot["party_down"]) / maxf(tot["runs"], 1), float(tot["medkits"]) / maxf(tot["runs"], 1), float(tot["rounds_left"]) / maxf(tot["runs"], 1),
		float(tot["kills_total"]) / maxf(tot["pool"] / 100.0, 1.0), 100.0 * tot["hits"] / maxf(tot["shots"], 1)])
	quit(0)


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += float(x)
	return s / a.size()
