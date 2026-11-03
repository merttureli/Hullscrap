extends SceneTree
## Not a test. Content audit: what generated boarding sites hold. Samples N seeds of each kind and tallies containers, blueprint/log slots, marks, loot items.
##   godot --headless --path . --script res://tests/tool_audit_content_sites.gd -- <n> <out json>
const Site = preload("res://scripts/board/site.gd")
const Loot = preload("res://scripts/board/loot.gd")
const Content = preload("res://scripts/data/content.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 100
	var known: Array = Content.read("res://data/recipes.json")["start_known"]
	var unknown: Array = Content.ids("recipes").filter(func(r): return not known.has(r))
	var logs: Array = []
	var ev = load("res://scripts/space/events.gd").new()
	logs = ev.logs.keys()
	var out := {}
	for kind in ["derelict", "station", "nest", "wreck"]:
		var tot := {"sites": 0, "ok": 0, "rooms": 0, "containers": 0, "bp_slots": 0, "log_slots": 0, "key_slots": 0, "marks": 0, "locked_doors": 0, "bp_got": 0, "log_got": 0, "empty": 0}
		var items := {}
		var marks := {"terminal": 0, "body": 0, "room": 0}
		for s in n:
			var site = Site.make(1000 + s * 37, kind, {"faction": "clans"})
			tot["sites"] += 1
			if not site.ok:
				continue
			tot["ok"] += 1
			tot["rooms"] += site.rooms.size()
			tot["marks"] += site.marks.size()
			for m in site.marks:
				marks[str(m["kind"])] += 1
			for p in site.props:
				if not p["loot"]:
					continue
				tot["containers"] += 1
				match str(p["slot"]):
					"blueprint": tot["bp_slots"] += 1
					"log": tot["log_slots"] += 1
					"key": tot["key_slots"] += 1
				var c := Loot.resolve(site, int(p["id"]), {"tier": 1 + s % 3, "stage": 1 + s % 8, "unknown": unknown, "levels": {}, "logs": logs, "log_factions": {}, "faction": "clans"})
				if Loot.empty(c):
					tot["empty"] += 1
				if c["blueprint"] != "":
					tot["bp_got"] += 1
				if c["log"] != "":
					tot["log_got"] += 1
				for it in c["items"]:
					items[it] = int(items.get(it, 0)) + int(c["items"][it])
		out[kind] = {"tot": tot, "items": items, "marks": marks}
	var f := FileAccess.open(args[1] if args.size() > 1 else "/tmp/sites.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	quit(0)
