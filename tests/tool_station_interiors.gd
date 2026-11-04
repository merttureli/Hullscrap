extends SceneTree
## Run: xvfb-run -a godot --path . --script res://tests/tool_station_interiors.gd -- sheets [out_dir] [module ids...]
##      xvfb-run -a godot --path . --script res://tests/tool_station_interiors.gd -- room <module> <state> [seed] [out.png]
##      xvfb-run -a godot --path . --script res://tests/tool_station_interiors.gd -- overview <state> <type> <seed> <out.png>   (the whole station, lit up)
##      xvfb-run -a godot --path . --script res://tests/tool_station_interiors.gd -- lineup <out.png> [module ids...]   (every race room, operational and lit, labelled)
## The environment variables RACES (a comma list: the races of the station) and REGION pick who built it and where.
## sheets: one contact sheet per module (interiors_<module>.png): the module's room in an abandoned, a half-active and an operational station, in the real
## board view (lit up, no HUD). room: one module in one state at full size. Not a test (no test_ prefix).

const Site = preload("res://scripts/board/site.gd")
const StationGen = preload("res://scripts/board/station_gen.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const BoardView = preload("res://scripts/board/board_view.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Races = preload("res://scripts/board/station_races.gd")

const STATES: Array[String] = ["abandoned", "half", "operational"]
const REGIONS: Array[String] = ["clan_space", "human_core", "kett_hives", "emberkin_forges", "sporeling_groves", "prismatic_choir", "boneyard", "fenn_bazaar", "basalt_quarries", "gauntling_scrapyards"]
const TILE := Vector2i(640, 420)

var out_dir := "/home/user/hs/shots"
var _ship: Ship


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	DisplayServer.window_set_size(Vector2i(1280, 840))
	await process_frame
	_ship = Ship.from_design("res://data/ships/starter_rustbucket.json")
	Jobs.spawn_crew(_ship)
	var mode: String = args[0] if args.size() > 0 else "sheets"
	if OS.get_environment("RACES") != "":
		Races.forced = Array(OS.get_environment("RACES").split(","))
	if mode == "overview":
		var region := OS.get_environment("REGION") if OS.get_environment("REGION") != "" else "clan_space"
		var want_type: String = args[2]
		var sv := int(args[3])
		var site = null
		for i in 300:
			var s = Site.make(sv + i, "station", {"faction": "clans", "region": region, "state": args[1]})
			if s.gen == "modules" and (want_type == "-" or s.station_type == want_type):
				site = s
				break
		var img := await _overview(site)
		img.save_png(args[4])
		print("overview %s %s %s races %s modules %s" % [site.station_type, site.state, site.site_name, str(site.races), str(site.modules.map(func(m): return "%s[%s]" % [m["id"], m["race"]]))])
		quit()
		return
	if mode == "room":
		var mid: String = args[1]
		var st: String = args[2]
		var site = _find(mid, st, int(args[3]) if args.size() > 3 else -1)
		var img := await _shot(site, mid, false)
		img.save_png(args[4] if args.size() > 4 else "%s/interiors_room_%s_%s.png" % [out_dir, mid, st])
		quit()
		return
	if mode == "lineup":
		await _lineup(args[1], args.slice(2))
		quit()
		return
	if args.size() > 1:
		out_dir = args[1]
	var only: Array = args.slice(2)
	var mods: Array = StationGen.modules().keys()
	mods.sort()
	var pool := {}
	for st in STATES:
		pool[st] = {}
	for mid in mods:
		if not only.is_empty() and not only.has(mid):
			continue
		var tiles: Array = []
		for st in STATES:
			var site = _find(mid, st, -1)
			if site == null:
				tiles.append(null)
				continue
			tiles.append({"img": await _shot(site, mid, true), "site": site})
		await _sheet(mid, tiles)
	quit()


## A station in `state` with module `mid` (a race's room: a station its people built, with the module required).
func _find(mid: String, state: String, seed_value: int):
	var races: Array = StationGen.modules()[mid].get("races", [])
	var forced_before: Array = Races.forced
	StationGen.forced_module = ""
	if not races.is_empty():
		Races.forced = [races[0]]
		StationGen.forced_module = mid
	for i in 600:
		var sv: int = seed_value if seed_value >= 0 else 50000 + i * 31 + state.length() * 7
		var region: String = REGIONS[i % REGIONS.size()]
		var s = Site.make(sv, "station", {"faction": "clans", "region": region, "state": state})
		if s.gen == "modules" and s.modules.any(func(m): return m["id"] == mid):
			Races.forced = forced_before
			StationGen.forced_module = ""
			return s
		if seed_value >= 0:
			seed_value += 1
	Races.forced = forced_before
	StationGen.forced_module = ""
	return null


## The room of module `mid` in `site` in the real board view, framed on the module.
func _shot(site, mid: String, lit_up: bool, label := "") -> Image:
	var m: Dictionary = site.modules.filter(func(x): return x["id"] == mid)[0]
	var cam := Camera2D.new()
	root.add_child(cam)
	cam.make_current()
	var board := BoardView.new()
	board.cam = cam
	board.ask_party = false
	root.add_child(board)
	var ses = Boarding.start(null, null, "shot", {"kind": "station"}, _ship)
	ses.site = site
	ses.foes = Foes.new(ses)
	ses.soldier.pos = _aside(site, m["rooms"][0])
	board.enter(ses)
	board.set_lights_up(lit_up)
	if board._layer != null and lit_up:
		board._layer.visible = false
	board._follow = false
	var r: Rect2i = m["rect"]
	var vp := get_root().get_visible_rect().size
	var z := minf(vp.x / (float(r.size.x + 2) * 32.0), vp.y / (float(r.size.y + 2) * 32.0))
	cam.zoom = Vector2(z, z)
	cam.position = (Vector2(r.position) + Vector2(r.size) / 2.0) * 32.0
	for k in 6:
		board._follow = false
		cam.zoom = Vector2(z, z)
		cam.position = (Vector2(r.position) + Vector2(r.size) / 2.0) * 32.0
		await process_frame
	var tag: Label = null
	if label != "":
		var layer := CanvasLayer.new()
		layer.layer = 50
		root.add_child(layer)
		tag = Label.new()
		tag.text = label
		tag.add_theme_font_size_override("font_size", 28)
		tag.add_theme_color_override("font_outline_color", Color.BLACK)
		tag.add_theme_constant_override("outline_size", 8)
		tag.position = Vector2(14, 8)
		layer.add_child(tag)
		for k in 2:
			await process_frame
	var img := root.get_texture().get_image()
	if tag != null:
		tag.get_parent().queue_free()
	board.leave()
	board.queue_free()
	cam.queue_free()
	await process_frame
	return img


## Every race room (or the `only` ones) operational and lit in one image, 4 to a row, each labelled with its race and its name.
func _lineup(out: String, only: Array) -> void:
	var mods: Array = StationGen.modules().keys().filter(func(m): return not StationGen.modules()[m].get("races", []).is_empty() and (only.is_empty() or only.has(m)))
	mods.sort_custom(func(a, b): return str(StationGen.modules()[a]["races"][0]) + a < str(StationGen.modules()[b]["races"][0]) + b)
	var cols := 4
	var tw := 480
	var th := 315
	var big := Image.create(cols * tw, ((mods.size() + cols - 1) / cols) * th, false, Image.FORMAT_RGB8)
	big.fill(Color("#0b0e14"))
	for i in mods.size():
		var mid: String = mods[i]
		var site = _find(mid, "operational", -1)
		if site == null:
			continue
		var m: Dictionary = StationGen.modules()[mid]
		var img := await _shot(site, mid, true, "%s: %s" % [str(m["races"][0]).capitalize(), m["name"]])
		img.convert(Image.FORMAT_RGB8)
		img.resize(tw - 4, th - 4, Image.INTERPOLATE_LANCZOS)
		big.blit_rect(img, Rect2i(0, 0, tw - 4, th - 4), Vector2i((i % cols) * tw + 2, (i / cols) * th + 2))
		print("lineup %d/%d %s" % [i + 1, mods.size(), mid])
	big.save_png(out)


## A free spot of room `rid` far from its middle (the soldier stands there, not on the centrepiece).
func _aside(site, rid: int) -> Vector2:
	var mid: Vector2 = site.centre_of_room(rid)
	var best := mid
	var best_d := -1.0
	for a in site.free_anchors(rid):
		var p := Vector2(a) + Vector2.ONE
		if p.distance_to(mid) > best_d:
			best = p
			best_d = p.distance_to(mid)
	return best


func _sheet(mid: String, tiles: Array) -> void:
	var node := Node2D.new()
	root.add_child(node)
	var font := ThemeDB.fallback_font
	var vp := get_root().get_visible_rect().size
	var tile := Vector2(vp.x / 2.0 - 12.0, (vp.y - 56.0) / 2.0 - 6.0)
	var textures: Array = tiles.map(func(t): return ImageTexture.create_from_image(t["img"]) if t != null else null)
	node.draw.connect(func():
		node.draw_rect(Rect2(Vector2.ZERO, vp), Color("#0b0e14"))
		node.draw_string(font, Vector2(16, 28), "%s: %s" % [mid, StationGen.modules()[mid]["name"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
		for i in 3:
			var at := Vector2(8.0 + float(i % 2) * (tile.x + 8.0), 44.0 + float(i / 2) * (tile.y + 8.0))
			if i == 2:
				at.x = (vp.x - tile.x) / 2.0
			if textures[i] != null:
				node.draw_texture_rect(textures[i], Rect2(at, tile), false)
				var s = tiles[i]["site"]
				var m: Dictionary = s.modules.filter(func(x): return x["id"] == mid)[0]
				node.draw_rect(Rect2(at, Vector2(tile.x, 26)), Color(0, 0, 0, 0.6))
				node.draw_string(font, at + Vector2(8, 19), "%s  %s  [%s]%s%s%s" % [STATES[i], s.station_type, m["race"], "" if m["powered"] else "  no power", "  AIRLESS" if not s.breathable(m["rooms"][0]) else "", "  " + m["climate"] if m["climate"] != "" else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.95))
	)
	for k in 3:
		await process_frame
	root.get_texture().get_image().save_png("%s/interiors_%s.png" % [out_dir, mid])
	print("saved interiors_%s" % mid)
	node.queue_free()
	await process_frame


## The whole station lit up in the board view (the HUD away).
func _overview(site) -> Image:
	var cam := Camera2D.new()
	root.add_child(cam)
	cam.make_current()
	var board := BoardView.new()
	board.cam = cam
	board.ask_party = false
	root.add_child(board)
	var ses = Boarding.start(null, null, "shot", {"kind": "station"}, _ship)
	ses.site = site
	ses.foes = Foes.new(ses)
	ses.soldier.pos = site.airlock["spawn"]
	board.enter(ses)
	board.set_lights_up(true)
	board._layer.visible = false
	var b: Rect2i = site.bounds
	var vp := get_root().get_visible_rect().size
	var z := minf(vp.x / (float(b.size.x + 4) * 32.0), vp.y / (float(b.size.y + 4) * 32.0))
	for k in 6:
		board._follow = false
		cam.zoom = Vector2(z, z)
		cam.position = (Vector2(b.position) + Vector2(b.size) / 2.0) * 32.0
		await process_frame
	var img := root.get_texture().get_image()
	board.leave()
	board.queue_free()
	cam.queue_free()
	await process_frame
	return img
