extends SceneTree
## Not a test (the runner only loads test_*.gd). How many crew a run gains, and how often it meets Ada (playtest 2, A1 + A2):
##   godot --headless --path . --script res://tests/tool_crew_rate.gd [-- <runs> <ship design path> [roam]]
## Plays <runs> seeded campaigns at the map level (tests/crew_walk.gd: no flying, no arena; it takes a recruit whenever a choice offers
## one and hires at a station when it can pay) and prints the average crew aboard at the end of stage 2, 4 and 8 (the start crew
## counts), the average gained, the share of runs that met Ada by the end of stage 2 and the share that took her aboard, and where
## the recruits came from. With `roam` as the third argument the walk plays every other POI of each node's sector (not one half of the time).

const CrewWalk = preload("res://tests/crew_walk.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := int(args[0]) if args.size() > 0 else 100
	var design: String = args[1] if args.size() > 1 else "res://data/ships/starter_courier.json"
	var walk := CrewWalk.new()
	walk.roam = args.size() > 2 and args[2] == "roam"
	var sums := {}
	var start_sum := 0
	var met := 0
	var took := 0
	var distress12 := 0
	for i in runs:
		var r := walk.run(i, design)
		start_sum += r["start"]
		for s in CrewWalk.CHECKPOINTS:
			sums[s] = int(sums.get(s, 0)) + int(r["crew"].get(s, 0))
		met += int(r["met_ada"])
		took += int(r["took_ada"])
		distress12 += int(r["distress12"] > 0)
	print("%d runs of %s%s, %.1f crew at the start" % [runs, design.get_file(), " (roaming)" if walk.roam else "", float(start_sum) / runs])
	for s in CrewWalk.CHECKPOINTS:
		print("  end of stage %d: %.2f crew aboard, %+.2f gained" % [s, float(sums[s]) / runs, float(sums[s] - start_sum) / runs])
	print("  met Ada by the end of stage 2: %d%%, took her aboard: %d%%, ran into a distress POI in stages 1-2: %d%%" % [100 * met / runs, 100 * took / runs, 100 * distress12 / runs])
	var keys: Array = walk.from.keys()
	keys.sort()
	for k in keys:
		print("  recruit from %s: %.2f a run" % [k, float(walk.from[k]) / runs])
	quit(0)
