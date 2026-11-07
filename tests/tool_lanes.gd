extends SceneTree
## Not a test. The share of generated ships with a room cut off by a part, per run stage:
##   godot --headless --path . --script res://tests/tool_lanes.gd [-- n=200]

const LaneUtil = preload("res://tests/lane_util.gd")


func _init() -> void:
	var n := 200
	for a in OS.get_cmdline_user_args():
		if a.begins_with("n="):
			n = int(a.substr(2))
	for stage in range(1, 7):
		var r := LaneUtil.sweep(stage, n)
		print("stage %d: %d ships, %d with a blocked room (%.1f%%), %d rooms" % [stage, r["ships"], r["blocked"], 100.0 * r["blocked"] / maxf(1, r["ships"]), r["rooms"]])
	quit()
