extends SceneTree
## Run: godot --headless --path . --script res://tests/tool_race_rooms.gd -- rate
##      xvfb-run -a godot --path . --script res://tests/tool_race_rooms.gd -- perf
## rate: the early-mod rate a station (tests/test_station_interiors.gd's formula) over clan space and over every region; perf: the frame time aboard the
## biggest habitat (240 frames, the real board view, lit). Not a test (no test_ prefix).

const Site = preload("res://scripts/board/site.gd")
const Loot = preload("res://scripts/board/loot.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const BoardView = preload("res://scripts/board/board_view.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const StationGen = preload("res://scripts/board/station_gen.gd")
const Races = preload("res://scripts/board/station_races.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")

const REGIONS: Array[String] = ["clan_space", "human_core", "kett_hives", "emberkin_forges", "sporeling_groves", "prismatic_choir", "boneyard", "fenn_bazaar", "basalt_quarries", "gauntling_scrapyards", "mire_fens", "grundl_barges", "lumen_space", "concord_space", "gate_approaches"]


func _initialize() -> void:
	_run.call_deferred()


func _rate(region: String, n: int, base: int) -> float:
	var total := 0.0
	var k := 0
	for i in n:
		var s = Site.make(base + i * 37, "station", {"faction": "clans", "region": region})
		if s.gen != "modules":
			continue
		k += 1
		for id in s.containers():
			var p: Dictionary = s.props[id]
			var table: Array = Loot.table_of(s, id)
			var w := 0.0
			var m := 0.0
			for o in table:
				w += float(o["weight"])
				if str(o["item"]) in ["mod", "mod_low"]:
					m += float(o["weight"])
			total += ((float(p["rolls"][0]) + float(p["rolls"][1])) / 2.0 + (1.0 if s.rooms[p["room"]]["locked"] else 0.0)) * m / w
	return total / float(maxi(k, 1))


## The expected early mods of each room of a station, by module id: {module id: [mods, containers, instances]}.
func _by_module(s, acc: Dictionary) -> void:
	for id in s.containers():
		var p: Dictionary = s.props[id]
		var table: Array = Loot.table_of(s, id)
		var w := 0.0
		var m := 0.0
		for o in table:
			w += float(o["weight"])
			if str(o["item"]) in ["mod", "mod_low"]:
				m += float(o["weight"])
		var mid := str(s.modules[int(s.rooms[p["room"]]["module"])]["id"])
		var a: Array = acc.get(mid, [0.0, 0, 0])
		a[0] += ((float(p["rolls"][0]) + float(p["rolls"][1])) / 2.0 + (1.0 if s.rooms[p["room"]]["locked"] else 0.0)) * m / w
		a[1] += 1
		acc[mid] = a


func _run() -> void:
	var mode: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "rate"
	if mode == "rate":
		print("clan_space(80): %.3f" % _rate("clan_space", 80, 1000))
		var sum := 0.0
		for r in REGIONS:
			var v := _rate(r, 60, 3000)
			sum += v
			print("%s: %.3f" % [r, v])
		print("all regions mean: %.3f" % (sum / float(REGIONS.size())))
		quit()
		return
	if mode == "bymod":  # every module forced into 10 stations of its race: mods and containers a module
		var res := {}
		var ids: Array = StationGen.modules().keys()
		ids.sort()
		for mid in ids:
			if mid == "dock":
				continue
			var races: Array = StationGen.modules()[mid].get("races", [])
			Races.forced = [races[0]] if not races.is_empty() else ["human"]
			StationGen.forced_module = mid
			var acc := {}
			var n := 0
			for i in 12:
				var s = Site.make(20000 + i * 53, "station", {"faction": "clans", "region": "clan_space"})
				if s.gen == "modules":
					_by_module(s, acc)
					n += s.modules.filter(func(m): return m["id"] == mid).size()
			if acc.has(mid) and n > 0:
				print("%-22s mods %.2f  containers %.1f  (%d)" % [mid, acc[mid][0] / float(n), float(acc[mid][1]) / float(n), n])
		quit()
		return
	DisplayServer.window_set_size(Vector2i(1280, 840))
	await process_frame
	var ship: Ship = Ship.from_design("res://data/ships/starter_rustbucket.json")
	Jobs.spawn_crew(ship)
	var best = null
	for i in 60:
		var s = Site.make(9000 + i * 11, "station", {"faction": "clans", "region": REGIONS[i % REGIONS.size()], "state": "operational"})
		if s.gen == "modules" and (best == null or s.bounds.get_area() > best.bounds.get_area()):
			best = s
	var cam := Camera2D.new()
	root.add_child(cam)
	cam.make_current()
	var board := BoardView.new()
	board.cam = cam
	board.ask_party = false
	root.add_child(board)
	var ses = Boarding.start(null, null, "perf", {"kind": "station"}, ship)
	ses.site = best
	ses.foes = Foes.new(ses)
	ses.soldier.pos = best.airlock["spawn"]
	board.enter(ses)
	board.set_lights_up(true)
	var b: Rect2i = best.bounds
	var z := minf(1280.0 / (float(b.size.x + 4) * 32.0), 840.0 / (float(b.size.y + 4) * 32.0))
	for k in 20:
		await process_frame
	var t0 := Time.get_ticks_usec()
	for k in 240:
		board._follow = false
		cam.zoom = Vector2(z, z) * (1.0 + 0.5 * float(k % 2))  # (a zoomed-out and a closer view, both drawn)
		cam.position = (Vector2(b.position) + Vector2(b.size) / 2.0) * 32.0
		await process_frame
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 240.0
	print("perf: %s %s %d modules, bounds %s, %.2f ms a frame (240 frames)" % [best.station_type, best.state, best.modules.size(), str(best.bounds.size), ms])
	quit()
