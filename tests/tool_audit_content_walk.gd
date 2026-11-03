extends SceneTree
## Not a test. Content audit: how many distinct events a seeded run shows in stages 1-3 and how often one repeats.
##   godot --headless --path . --script res://tests/tool_audit_content_walk.gd -- <runs> <out json> [roam]
## Reuses tests/crew_walk.gd (map-level walk, a random open choice, fights stubbed). Per run it reads CrewWalk.seen (event id -> times shown, pages too).

const CrewWalk = preload("res://tests/crew_walk.gd")
const Events = preload("res://scripts/space/events.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := int(args[0]) if args.size() > 0 else 60
	var out_path: String = args[1] if args.size() > 1 else "/tmp/walk.json"
	var roam: bool = args.size() > 2 and args[2] == "roam"
	var ev := Events.new()
	var res := {"runs": runs, "roam": roam, "by_last": {}, "total": {}}
	for last in [1, 2, 3, 8]:
		var rows: Array = []
		for i in runs:
			var w := CrewWalk.new()
			w.roam = roam
			w.run(i, "res://data/ships/starter_courier.json", last)
			var types := {}
			var draws := 0
			var rep := 0
			for id in w.seen:
				var n: int = w.seen[id]
				draws += n
				rep += n - 1
				var t := str(ev.get_event(id).get("type", "?"))
				types[t] = int(types.get(t, 0)) + n
				if last == 8:
					res["total"][id] = int(res["total"].get(id, 0)) + n
			rows.append({"distinct": w.seen.size(), "draws": draws, "repeats": rep, "seen": w.seen})
		res["by_last"][str(last)] = rows
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(res))
	quit(0)
