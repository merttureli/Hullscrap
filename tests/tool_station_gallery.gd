extends SceneTree
## Run: xvfb-run -a godot --path . --script res://tests/tool_station_gallery.gd [-- out_dir]
## Renders 8 module stations from above (data/station_modules.json), one image each: every cell, the modules outlined and named, the light of each
## room (lit, flickering, red, dark), airless rooms hatched, windows, locked doors, beds (working or broken), sentries. Not a test (no test_ prefix).

const Site = preload("res://scripts/board/site.gd")
const Fixtures = preload("res://scripts/board/station_fixtures.gd")

const SEEDS := [101, 2207, 3319, 4421, 5531, 6649, 7757, 8863]
const OPTS := [{"region": "clan_space"}, {"region": "human_core"}, {"region": "boneyard"}, {"region": "fenn_bazaar"}, {"region": "clan_space", "state": "half"},
	{"region": "human_core", "state": "operational"}, {"region": "clan_space", "state": "abandoned"}, {"region": "concord_space", "state": "half"}]
const LIGHT := {"lit": Color(1.0, 0.95, 0.8), "flicker": Color(0.85, 0.85, 0.6), "red": Color(0.75, 0.25, 0.2), "dark": Color(0.28, 0.3, 0.36)}

var out_dir := "/home/user/hs/shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	await process_frame
	RenderingServer.set_default_clear_color(Color("#0b0e14"))
	for i in SEEDS.size():
		var opts: Dictionary = OPTS[i].duplicate()
		opts["faction"] = "clans"
		var s = Site.make(SEEDS[i], "station", opts)
		var node := Node2D.new()
		node.draw.connect(func(): _draw_site(node, s, i))
		root.add_child(node)
		for k in 3:
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png("%s/stations_map_%d.png" % [out_dir, i + 1])
		print("saved stations_map_%d: %s %s %s %d modules, problems %s" % [i + 1, s.station_type, s.state, s.mood, s.modules.size(), s.problems()])
		node.queue_free()
		await process_frame
	quit()


func _draw_site(n: Node2D, s, idx: int) -> void:
	var font := ThemeDB.fallback_font
	var W: float = root.get_visible_rect().size.x
	var H: float = root.get_visible_rect().size.y
	var b: Rect2i = s.bounds
	var top := 64.0
	var cell := minf(float(W - 40) / float(b.size.x + 2), float(H - top - 60) / float(b.size.y + 2))
	var o := Vector2((W - cell * b.size.x) / 2.0, top + (H - top - 60 - cell * b.size.y) / 2.0) - Vector2(b.position) * cell
	var rdefs: Dictionary = Site.config()["rooms"]
	for r in s.rooms:
		if r["purpose"] == "gone":
			continue
		var tint := Color(str(rdefs.get(r["purpose"], {}).get("tint", "#888888")))
		var lc: Color = LIGHT.get(str(s.room_light.get(r["id"], "dark")), LIGHT["dark"])
		var col := tint.lerp(lc, 0.45) * Color(lc.v, lc.v, lc.v)
		col.a = 1.0
		var rr := Rect2(o + Vector2(r["rect"].position) * cell, Vector2(r["rect"].size) * cell)
		n.draw_rect(rr, col)
		if str(s.room_light.get(r["id"], "")) == "flicker":
			var y := rr.position.y
			while y < rr.end.y:
				n.draw_line(Vector2(rr.position.x, y), Vector2(rr.end.x, y), Color(0, 0, 0, 0.35), 1.0)
				y += 4.0
		if not s.breathable(r["id"]):
			var x := rr.position.x - rr.size.y
			while x < rr.end.x:
				n.draw_line(Vector2(maxf(x, rr.position.x), rr.position.y + maxf(rr.position.x - x, 0.0)), Vector2(minf(x + rr.size.y, rr.end.x), rr.end.y - maxf(x + rr.size.y - rr.end.x, 0.0)), Color(0.4, 0.75, 1.0, 0.7), 2.0)
				x += 8.0
	for c in s.grid.tiles:
		var t: String = s.grid.tiles[c]
		var cr := Rect2(o + Vector2(c) * cell, Vector2(cell, cell))
		if t == "wall":
			n.draw_rect(cr, Color("#5d6573"))
		elif t == "door":
			n.draw_rect(cr.grow(-cell * 0.15), Color("#c8ccd4"))
	for run in s.windows:
		for c in run["cells"]:
			n.draw_rect(Rect2(o + Vector2(c) * cell, Vector2(cell, cell)), Color("#7fdbff"))
	for d in s.doors:
		if d["lock"] == "hack" or d["lock"] == "card":
			var col := Color("#e8a23a") if d["lock"] == "hack" else Color(["#e0453a", "#4aa3ff", "#58d36a", "#e8c43a"][Site.KEY_NAMES.find(d["card"])])
			for c in d["cells"]:
				n.draw_rect(Rect2(o + Vector2(c) * cell, Vector2(cell, cell)), col)
				n.draw_rect(Rect2(o + Vector2(c) * cell, Vector2(cell, cell)), Color.BLACK, false, 1.0)
	for c in s.airlock["hatch"]:
		n.draw_rect(Rect2(o + Vector2(c) * cell, Vector2(cell, cell)), Color("#58e08a"))
	for p in s.props:
		var col := Color("#b08850") if p["loot"] else Color("#7a7a7a")
		for c in s.cells_of(p):
			n.draw_rect(Rect2(o + Vector2(c) * cell, Vector2(cell, cell)).grow(-cell * 0.2), col)
	for f in s.fixtures:  # the fixtures: their footprints, in the colour of their data (walked-through ones outlined only), an arrow for the way they face
		var fr := Rect2(o + Vector2(f["cell"]) * cell, Vector2(f["size"]) * cell).grow(-cell * 0.08)
		var fcol := Color(str(Fixtures.defs()[f["fixture"]]["color"]))
		if f["blocks"]:
			n.draw_rect(fr, fcol)
		n.draw_rect(fr, Color.BLACK, false, 1.0)
		if f["glow"] != "" and not f["dead"]:
			n.draw_rect(fr.grow(-cell * 0.3), Color(f["glow"]))
		var mid := fr.get_center()
		n.draw_line(mid, mid + Vector2(f["dir"]) * cell * 0.45, Color.BLACK, 1.5)
	if not s.power.is_empty() and int(s.power["fixture"]) >= 0:
		var gf: Dictionary = s.fixtures[int(s.power["fixture"])]
		n.draw_rect(Rect2(o + Vector2(gf["cell"]) * cell, Vector2(gf["size"]) * cell).grow(2.0), Color("#ffd060"), false, 3.0)
	for bd in s.beds:
		var br := Rect2(o + Vector2(bd["cell"]) * cell, Vector2(bd["size"]) * cell).grow(-cell * 0.1)
		n.draw_rect(br, Color("#e8eef4") if bd["works"] else Color("#6a6e74"))
		n.draw_rect(br, Color("#58d36a") if bd["works"] else Color("#e0453a"), false, 2.0)
	for e in s.posts:
		var at: Vector2 = o + e["pos"] * cell
		n.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -cell), at + Vector2(cell * 0.8, cell * 0.6), at + Vector2(-cell * 0.8, cell * 0.6)]), Color("#ff5a4a"))
	for i in s.modules.size():
		var m: Dictionary = s.modules[i]
		var mr := Rect2(o + Vector2(m["rect"].position) * cell, Vector2(m["rect"].size) * cell)
		var mc := Color.from_hsv(fmod(float(i) * 0.137, 1.0), 0.55, 1.0)
		n.draw_rect(mr.grow(-1.0), mc, false, 2.0)
		var label := "%s [%s]%s%s%s" % [m["name"], m["race"], "" if m["powered"] else " (no power)", " BREACHED" if m["breached"] else "", " AIRLESS" if m["airless"] else ""]
		var fs := 13
		var sz := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var at := mr.get_center() - sz / 2.0
		n.draw_rect(Rect2(at - Vector2(3, 2), sz + Vector2(6, 4)), Color(0, 0, 0, 0.72))
		n.draw_string(font, at + Vector2(0, sz.y * 0.78), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, mc)
	var title := "Station %d  seed %d  %s  %s%s  %s  %d modules  %dx%d cells  %d rooms  %d containers  %d beds  %d fixtures  races %s" % [idx + 1, s.seed_value, s.station_type, s.state,
		(" (" + s.mood + ")") if s.mood != "" else "", s.site_name, s.modules.size(), s.bounds.size.x, s.bounds.size.y, s.rooms.size(), s.containers().size(), s.beds.size(), s.fixtures.size(), ",".join(s.races)]
	n.draw_string(font, Vector2(20, 30), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	n.draw_string(font, Vector2(20, 54), "room light: bright lit, striped flicker, red emergency, grey dark; blue hatching no air; cyan windows; pale doors; amber hack lock; coloured card lock; green hatch; beds white (working) or grey (broken); fixtures: coloured blocks with an arrow (the way they face), outlined = walked through, glow = lit; gold frame = the generator; red triangle sentry",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.8, 0.88))
