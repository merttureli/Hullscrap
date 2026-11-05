extends SceneTree
## godot --headless --path . --script res://tests/run_expedition_sim.gd [-- N]   prints the expected reward and loss per kind (tests/expedition_sim.gd).

const Sim = preload("res://tests/expedition_sim.gd")


func _init() -> void:
	var n := 400
	for a in OS.get_cmdline_user_args():
		if str(a).is_valid_int():
			n = int(a)
	print("kind | team/policy | mean value | poor/fair/good/rich | P(lose a member) | members lost | gear lost | hurts | (n=%d)" % n)
	for kind in ["planet", "base", "ruin", "platform"]:
		for row in [["random team, random choices", "random", false], ["equipped team, choosing well", "well", true], ["equipped team, always pushing on", "bold", true]]:
			var r: Dictionary = Sim.run(kind, row[1], n, 3, row[2])
			var t: Dictionary = r["tiers"]
			print("%s | %s | %.0f | %d/%d/%d/%d | %.1f%% | %.2f | %.2f | %.2f" % [kind, row[0], r["mean"], t["poor"], t["fair"], t["good"], t["rich"], r["loss_rate"] * 100.0, r["members"], r["gear"], r["hurt"]])
	quit()
