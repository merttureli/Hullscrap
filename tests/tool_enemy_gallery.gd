extends SceneTree
## Not a test (the runner only loads test_*.gd). The enemy ship audit of the `enemy-variety` track.
## For every faction of data/enemy_tables.json it builds ships over every size class x stages 1, 3, 5, 7 x N seeds, prints how varied they are
## (distinct silhouettes, mean pairwise IoU inside a size class, the part families on the outside) and how hull cells, outside guns, armour
## tiles and engines grow with the budget, and (with a window: xvfb-run -a, not --headless) draws a contact sheet per faction of the real ship art.
##   xvfb-run -a godot --path . --script res://tests/tool_enemy_gallery.gd -- tag=before [seeds=6] [factions=rustfangs,concord] [sheets=0]
## Sheets go to /home/user/hs/shots/enemy_<tag>_<faction>.png (out=<dir> to change the directory).

const Shipgen = preload("res://scripts/space/shipgen.gd")
const ShipView = preload("res://scripts/view/ship_view.gd")
const Content = preload("res://scripts/data/content.gd")

static var STAGES := [1, 3, 5, 7]
const SIZES := ["small", "medium", "large"]
const JUMPS_A_STAGE := 12.5
const K := 3.0  ## screen px per cell on the sheet

var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_run.call_deferred()


func _run() -> void:
	if args.has("stages"):
		STAGES = []
		for x in str(args["stages"]).split(","):
			STAGES.append(int(x))
	var seeds := int(args.get("seeds", 6))
	var tag := str(args.get("tag", "before"))
	var out := str(args.get("out", "/home/user/hs/shots"))
	var facs: Array = str(args["factions"]).split(",") if args.has("factions") else Shipgen.factions()
	for faction in facs:
		var rows: Array = gather(faction, seeds)
		print(report(faction, rows))
		if str(args.get("sheets", "1")) != "0" and DisplayServer.get_name() != "headless":
			await sheet(faction, rows, "%s/enemy_%s_%s.png" % [out, tag, faction])
	quit(0)


## The budget a (faction, stage) fight has: the campaign's for the middle of the stage.
static func budget_of(faction: String, stage: int) -> float:
	var j := roundi(JUMPS_A_STAGE * (float(stage) - 0.5))
	var tier := 3 if j >= 25 else (2 if j >= 10 else 1)
	var danger := INF
	var kin := str(Shipgen.tables()["factions"][faction].get("lines_as", faction))  # a race ship has its base faction's regions' danger
	for r in Content.regions():
		if str(r.get("enemies", "")) == kin:
			danger = minf(danger, float(r.get("danger", 1.0)))
	return Shipgen.budget_for(tier, j, danger if danger < INF else 1.0, "normal", stage)


## [{size, stage, seed, budget, ship}] of every combination.
static func gather(faction: String, seeds: int) -> Array:
	var rows: Array = []
	for size in SIZES:
		if Shipgen.at_least(faction, size) != size:
			continue
		for stage in STAGES:
			var budget := budget_of(faction, stage)
			for k in seeds:
				var sd: int = 1000 + k * 7919 + stage * 31
				var ship = Shipgen.build(faction, size, sd, budget, {"stage": stage})
				if ship != null:
					rows.append({"size": size, "stage": stage, "seed": sd, "budget": budget, "ship": ship})
	return rows


## The occupied cells of a ship's hull (a shaped cell counts), cropped to its box: [w, h, Dictionary of Vector2i].
static func occupancy(ship) -> Array:
	var cells := {}
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in ship.grid.tiles:
		cells[c] = true
		lo = lo.min(c)
		hi = hi.max(c)
	var g := {}
	for c in cells:
		g[c - lo] = true
	return [hi.x - lo.x + 1, hi.y - lo.y + 1, g]


static func key_of(occ: Array, mirror: bool) -> String:
	var w: int = occ[0]
	var parts := PackedStringArray()
	for y in int(occ[1]):
		var row := ""
		for x in w:
			row += "#" if occ[2].has(Vector2i(w - 1 - x if mirror else x, y)) else "."
		parts.append(row)
	return "%dx%d:%s" % [w, occ[1], "/".join(parts)]


## Left-right mirror-normalised key.
static func silhouette_key(ship) -> String:
	var o := occupancy(ship)
	var a := key_of(o, false)
	var b := key_of(o, true)
	return a if a < b else b


## IoU of two occupancy grids, bows aligned (top), centred on the middle column; the better of the two mirrorings.
static func iou(a: Array, b: Array) -> float:
	var best := 0.0
	for m in [false, true]:
		var inter := 0
		var uni := 0
		var ox: int = (int(a[0]) - int(b[0])) / 2
		var ca: Dictionary = a[2]
		var cb := {}
		for c in b[2]:
			var x: int = (int(b[0]) - 1 - c.x) if m else c.x
			cb[Vector2i(x + ox, c.y)] = true
		for c in ca:
			if cb.has(c):
				inter += 1
		uni = ca.size() + cb.size() - inter
		best = maxf(best, float(inter) / float(maxi(uni, 1)))
	return best


static func armour_tiles(ship, faction: String) -> int:
	var ids: Array = Shipgen.tables()["factions"][faction]["armour"]["tiles"].duplicate()
	ids.append(str(Shipgen.tables()["factions"][faction]["armour"].get("ram", "ram_plating")))
	var n := 0
	for c in ship.grid.tiles:
		if ids.has(ship.grid.tiles[c]):
			n += 1
	return n


## {families: {family: count}, guns, engines, outside}: what stands on the outside of the hull.
static func outside(ship) -> Dictionary:
	var fam := {}
	var guns := 0
	var engines := 0
	for uid in ship.components.instances:
		var inst: Dictionary = ship.components.instances[uid]
		if inst["out_cells"].is_empty():
			continue
		var f := str(ship.components.def(inst["id"]).get("family", ""))
		fam[f] = int(fam.get(f, 0)) + 1
		guns += int(f == "weapon")
		engines += int(f == "engine")
	return {"families": fam, "guns": guns, "engines": engines}


static func report(faction: String, rows: Array) -> String:
	var lines := PackedStringArray()
	lines.append("=== %s: %d ships ===" % [faction, rows.size()])
	var keys := {}
	var fams := {}
	for r in rows:
		keys[silhouette_key(r["ship"])] = true
		r["occ"] = occupancy(r["ship"])
		var o := outside(r["ship"])
		r["out"] = o
		for f in o["families"]:
			fams[f] = int(fams.get(f, 0)) + int(o["families"][f])
	lines.append("distinct silhouettes: %d of %d" % [keys.size(), rows.size()])
	for size in SIZES:
		var g: Array = rows.filter(func(r): return r["size"] == size)
		if g.size() < 2:
			continue
		var sum := 0.0
		var n := 0
		for i in g.size():
			for j in range(i + 1, g.size()):
				sum += iou(g[i]["occ"], g[j]["occ"])
				n += 1
		lines.append("mean pairwise IoU, %s (%d ships): %.3f" % [size, g.size(), sum / maxf(n, 1)])
	lines.append("outside part families: " + str(fams))
	for size in SIZES:
		for stage in STAGES:
			var g: Array = rows.filter(func(r): return r["size"] == size and r["stage"] == stage)
			if g.is_empty():
				continue
			var cells := 0.0
			var guns := 0.0
			var arm := 0.0
			var eng := 0.0
			var w := 0.0
			for r in g:
				cells += r["ship"].grid.tiles.size()
				guns += int(r["out"]["guns"])
				eng += int(r["out"]["engines"])
				arm += armour_tiles(r["ship"], faction)
				w += float(r["ship"].get_meta("shipgen")["weapons"].size())
			var n := float(g.size())
			lines.append("  %-6s stage %d budget %6.1f: hull cells %6.1f  outside guns %4.2f (all guns %4.2f)  armour tiles %6.1f  engines %4.2f" % [size, stage, g[0]["budget"], cells / n, guns / n, w / n, arm / n, eng / n])
	return "\n".join(lines)


func sheet(faction: String, rows: Array, path: String) -> void:
	var maxw := {}
	var maxh := {}
	for r in rows:
		# the box of everything drawn: hull area of the ship, outside halves included
		var hb: Rect2 = hull_box(r["ship"])
		r["box"] = hb
		maxw[r["size"]] = maxf(float(maxw.get(r["size"], 0.0)), hb.size.x)
		maxh[r["size"]] = maxf(float(maxh.get(r["size"], 0.0)), hb.size.y)
	var cw := 0.0
	for s in maxw:
		cw = maxf(cw, float(maxw[s]))
	var cell_w := int(cw * K) + 10
	var seeds := int(args.get("seeds", 6))
	var y := 0
	var row_y := {}
	for size in SIZES:
		for stage in STAGES:
			if maxh.has(size):
				row_y[size + str(stage)] = y
				y += int(float(maxh[size]) * K) + 26
	var vp := SubViewport.new()
	vp.size = Vector2i(cell_w * seeds, y + 4)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color("#0b0e14")
	bg.size = Vector2(vp.size)
	vp.add_child(bg)
	var lab := Node2D.new()
	vp.add_child(lab)
	var seen := {}
	for r in rows:
		var col := int(seen.get(r["size"] + str(r["stage"]), 0))
		seen[r["size"] + str(r["stage"])] = col + 1
		var v := ShipView.new()
		v.skin_on = true
		v.scale = Vector2(K / ShipView.CELL, K / ShipView.CELL)
		vp.add_child(v)
		v.show_ship(r["ship"])
		var oy: float = row_y[r["size"] + str(r["stage"])]
		var hb: Rect2 = r["box"]
		# v.pivot is the hull centre; the box is in cell coordinates
		v.position = Vector2(col * cell_w + cell_w / 2.0, oy + 22.0) - (hb.position + Vector2(hb.size.x / 2.0, 0.0) - v.pivot) * K
		var meta: Dictionary = r["ship"].get_meta("shipgen")
		var t := Label.new()
		t.text = "%s s%d b%d g%d" % [r["size"].substr(0, 1).to_upper(), r["stage"], roundi(r["budget"]), meta["weapons"].size()]
		t.position = Vector2(col * cell_w + 2, oy + 2)
		t.add_theme_font_size_override("font_size", 11)
		t.add_theme_color_override("font_color", Color("#9fb0c8"))
		vp.add_child(t)
	for i in 6:
		await process_frame
	var img := vp.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("sheet: ", path)
	vp.queue_free()
	await process_frame


## The cell box of the tiles and the mounts' outside halves.
static func hull_box(ship) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var cells: Array = ship.grid.tiles.keys()
	for uid in ship.components.instances:
		cells.append_array(ship.components.instances[uid]["out_cells"])
	for c in cells:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x + 1.0), maxf(hi.y, c.y + 1.0))
	return Rect2(lo - Vector2(0, 2), hi - lo + Vector2(0, 2))
