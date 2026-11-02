extends SceneTree
## Not a test (the runner only loads test_*.gd). How scarce fuel is (playtest 2, economy):
##   godot --headless --path . --script res://tests/tool_fuel_rate.gd -- [runs=100] [design=res://data/ships/starter_courier.json] [nodes=3] [start=-1] [stock=2,4] [buy_to=12] [waits=1] [drift=1] [fly_s=75] [per_min=4]
## Plays <runs> seeded campaigns at the map level (tests/fuel_walk.gd has the player's policy) and prints, per stage, the average fuel
## at the start and at the end of the stage (before the crossing), the jumps made and where the fuel came from; then per run the jumps
## made, the fuel left at the end of a stage (the slack, in jumps) and the share of runs that had to be towed by Ma Gantry.

const FuelWalk = preload("res://tests/fuel_walk.gd")


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var runs := int(args.get("runs", 100))
	var design := str(args.get("design", "res://data/ships/starter_courier.json"))
	var walk := FuelWalk.new()
	walk.nodes = int(args.get("nodes", walk.nodes))
	walk.waits = int(args.get("waits", walk.waits))
	walk.buy_to = int(args.get("buy_to", walk.buy_to))
	walk.drift = int(args.get("drift", 1)) != 0
	walk.start = int(args.get("start", walk.start))
	if args.has("stock"):
		walk.stock = Array(str(args["stock"]).split(",")).map(func(v): return int(v))
	walk.fly_s = float(args.get("fly_s", walk.fly_s))
	walk.per_min = float(args.get("per_min", walk.per_min))
	var n := FuelWalk.STAGES
	var start := PackedFloat32Array()
	var end := PackedFloat32Array()
	var jumps := PackedFloat32Array()
	var src := {"stations": PackedFloat32Array(), "events": PackedFloat32Array(), "debris": PackedFloat32Array(), "tow": PackedFloat32Array()}
	var reach := PackedFloat32Array()  # runs that got as far as each stage
	for k in n:
		for arr in [start, end, jumps, reach]:
			arr.append(0.0)
		for key in src:
			src[key].append(0.0)
	var towed := 0
	var tows := 0
	var waited := 0
	var drifted := 0
	var stuck := 0
	var total_jumps := 0
	var finished := 0
	var slack_sum := 0.0
	var slack_n := 0
	for i in runs:
		var r := walk.run(i, design)
		tows += int(r["tows"])
		towed += int(r["tows"] > 0)
		waited += int(r["waits"])
		drifted += int(r["drifts"])
		stuck += int(r["stuck"])
		total_jumps += int(r["jumps"])
		finished += int(r["stages"].size() >= n)
		for k in r["stages"].size():
			var row: Dictionary = r["stages"][k]
			reach[k] += 1.0
			start[k] += float(row["start"])
			end[k] += float(row["end"])
			jumps[k] += float(row["jumps"])
			for key in src:
				src[key][k] += float(row["from"][key])
			slack_sum += float(row["end"])
			slack_n += 1
	print("%d runs of %s: %d nodes a stage, %d wait(s) for a trader, %.0f s of flight a node at %.1f pieces a minute" % [runs, design.get_file(), walk.nodes, walk.waits, walk.fly_s, walk.per_min])
	print("  stage | runs | fuel at start | fuel at end | jumps | from stations | events | debris | tow")
	for k in n:
		if reach[k] < 1.0:
			continue
		var m: float = reach[k]
		print("  %5d | %4d | %13.2f | %11.2f | %5.1f | %13.2f | %6.2f | %6.2f | %.2f" % [k + 1, int(m), start[k] / m, end[k] / m, jumps[k] / m, src["stations"][k] / m, src["events"][k] / m, src["debris"][k] / m, src["tow"][k] / m])
	print("  jumps a run: %.1f (the runs that reached stage %d: %d%%)   fuel left at the end of a stage, on average: %.2f (jumps of slack)" % [float(total_jumps) / runs, n, 100 * finished / runs, slack_sum / maxf(slack_n, 1)])
	print("  tows: %.2f a run, %d%% of runs towed at least once   waits for a trader: %.2f a run   drift jumps: %.2f a run   stuck runs: %d" % [float(tows) / runs, 100 * towed / runs, float(waited) / runs, float(drifted) / runs, stuck])
	quit(0)
