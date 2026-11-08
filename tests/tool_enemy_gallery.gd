extends SceneTree
## Not a test (the runner only loads test_*.gd). The enemy ship audit of the `enemy-variety` track.
## For every faction of data/enemy_tables.json it builds ships over every size class x stages 1, 3, 5, 7 x N seeds, prints how varied they are
## (distinct silhouettes, mean pairwise IoU inside a size class, the part families on the outside) and how hull cells, outside guns, armour
## tiles and engines grow with the budget, and (with a window: xvfb-run -a, not --headless) draws a contact sheet per faction of the real ship art.
##   xvfb-run -a godot --path . --script res://tests/tool_enemy_gallery.gd -- tag=before [seeds=6] [factions=rustfangs,concord] [sheets=0]
## Sheets go to /home/user/hs/shots/enemy_<tag>_<faction>.png (out=<dir> to change the directory).
## The roles (data/role_looks.json): `roles=1` draws a sheet per faction of the roles it flies (a row each, three seeds of each size class),
## `races=kett,sporeling` one of the six fighting roles side by side in those races' palettes (the race's own gunboat first, to compare),
## `rates=1` prints the build rates of each faction's new roles against its old ones (20 seeds; rate_seeds=<n>).

const Shipgen = preload("res://scripts/space/shipgen.gd")
const ShipView = preload("res://scripts/view/ship_view.gd")
const Content = preload("res://scripts/data/content.gd")

static var STAGES := [1, 3, 5, 7]
const SIZES := ["small", "medium", "large"]
const JUMPS_A_STAGE := 12.5
const K := 3.0  ## screen px per cell on the sheet
const BASES := ["rustfangs", "concord", "lumen", "wardens", "clans", "hollow"]
const NEW_ROLES := ["skirmisher", "carrier", "boarder", "flanker", "siege", "bulwark"]  ## the fighting roles, with a look of their own
const RATE_BUDGETS := [60.0, 90.0, 130.0, 200.0, 320.0]

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
	if args.has("rates"):
		print(rate_report(facs, int(args.get("rate_seeds", 20))))
		quit(0)
		return
	if args.has("roles") or args.has("races"):
		var k := float(args.get("k", K))
		if args.has("roles"):
			for faction in (str(args["factions"]).split(",") if args.has("factions") else BASES):
				await role_sheet(faction, "%s/roles_%s.png" % [out, faction], k)
		if args.has("races"):
			await race_sheet(str(args["races"]).split(","), "%s/roles_races.png" % out, k)
		quit(0)
		return
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


# --- the roles ---------------------------------------------------------------------------------------

## Can `role` be flown by a ship of `size` (its min_size)?
static func fits(role: String, size: String) -> bool:
	return SIZES.find(size) >= SIZES.find(str(Shipgen.tables()["roles"]["list"][role].get("min_size", "small")))


## The build rates of `faction`'s `size` ships of `roles` over `seeds` seeds (stage 4, the budgets of RATE_BUDGETS in turn):
## {n, first, made}. made: a ship came out, of the role asked (not the gunboat a role with no wall for its bay falls back to);
## first: and on the first roll.
static func rates(faction: String, size: String, roles: Array, seeds: int) -> Dictionary:
	var out := {"n": 0, "first": 0, "made": 0}
	for role in roles:
		if not fits(role, size):
			continue
		for k in seeds:
			var ship = Shipgen.build(faction, size, 7000 + k * 101, RATE_BUDGETS[k % RATE_BUDGETS.size()], {"role": role, "stage": 4})
			out["n"] += 1
			if ship != null and str(ship.get_meta("shipgen")["role"]) == role:
				out["made"] += 1
				out["first"] += int(ship.get_meta("shipgen")["attempts"] == 1)
	return out


## [new roles, old roles] that `faction` flies.
static func split_roles(faction: String) -> Array:
	var roles: Array = Shipgen.roles_of(faction)
	return [roles.filter(func(r): return NEW_ROLES.has(r)), roles.filter(func(r): return not NEW_ROLES.has(r))]


static func rate_report(facs: Array, seeds: int) -> String:
	var lines := PackedStringArray(["faction    size    new roles: first / made      old roles: first / made"])
	var tot := {"new": {"n": 0, "first": 0, "made": 0}, "old": {"n": 0, "first": 0, "made": 0}}
	for faction in facs:
		var sp := split_roles(faction)
		for size in SIZES:
			var a := rates(faction, size, sp[0], seeds)
			var b := rates(faction, size, sp[1], seeds)
			for k in ["n", "first", "made"]:
				tot["new"][k] += a[k]
				tot["old"][k] += b[k]
			lines.append("%-10s %-7s %3d: %5.1f%% / %5.1f%%      %3d: %5.1f%% / %5.1f%%%s" % [faction, size, a["n"], _pct(a, "first"), _pct(a, "made"), b["n"], _pct(b, "first"), _pct(b, "made"),
				"   <" if _pct(a, "first") < _pct(b, "first") or _pct(a, "made") < _pct(b, "made") else ""])
	lines.append("all: new %d ships %.1f%% first, %.1f%% made; old %d ships %.1f%% first, %.1f%% made" % [tot["new"]["n"], _pct(tot["new"], "first"), _pct(tot["new"], "made"), tot["old"]["n"], _pct(tot["old"], "first"), _pct(tot["old"], "made")])
	return "\n".join(lines)


static func _pct(r: Dictionary, k: String) -> float:
	return 100.0 * float(r[k]) / maxf(float(r["n"]), 1.0)


## A sheet of `faction`'s roles: a row per role it flies, three seeds of each size class (a dash where the role is too big for the size).
func role_sheet(faction: String, path: String, k: float) -> void:
	var cells: Array = []  # [row, col, ship, label]
	var roles: Array = Shipgen.roles_of(faction)
	for i in roles.size():
		for si in SIZES.size():
			for n in 3:
				var size: String = SIZES[si]
				var sd := 300 + n * 7919
				var ship = Shipgen.build(faction, size, sd, 160.0, {"role": roles[i], "stage": 4}) if fits(roles[i], size) else null
				cells.append([i, si * 3 + n, ship, "%s %s %d" % [roles[i], size.substr(0, 1).to_upper(), sd] if ship != null else roles[i] + " -"])
	await draw_grid(cells, path, k, "%s: the roles it flies (small, medium, large; three seeds each)" % faction)


## The six fighting roles side by side in each race's palette, medium and large, after the race's own gunboat.
func race_sheet(races: Array, path: String, k: float) -> void:
	var cells: Array = []
	var row := 0
	for race in races:
		for size in ["medium", "large"]:
			var cols: Array = ["gunboat"] + NEW_ROLES
			for c in cols.size():
				var ship = Shipgen.build(race, size, 41, 200.0, {"role": cols[c], "stage": 4})
				cells.append([row, c, ship, "%s %s %s" % [race, cols[c], size.substr(0, 1).to_upper()]])
			row += 1
	await draw_grid(cells, path, k, "the six fighting roles in two race palettes (the race's own gunboat first)")


## Draw `cells` ([row, col, ship or null, label]) on a grid of equal boxes, each ship centred in its box, and save the PNG.
func draw_grid(cells: Array, path: String, k: float, title: String) -> void:
	var bw := 0.0
	var bh := 0.0
	var rows := 0
	var cols := 0
	for c in cells:
		rows = maxi(rows, int(c[0]) + 1)
		cols = maxi(cols, int(c[1]) + 1)
		if c[2] != null:
			var hb: Rect2 = hull_box(c[2])
			c.append(hb)
			bw = maxf(bw, hb.size.x)
			bh = maxf(bh, hb.size.y)
	var cw := int(bw * k) + 14
	var ch := int(bh * k) + 24
	var vp := SubViewport.new()
	vp.size = Vector2i(cw * cols, ch * rows + 22)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color("#0b0e14")
	bg.size = Vector2(vp.size)
	vp.add_child(bg)
	_label(vp, title, Vector2(4, 2), 13)
	for c in cells:
		var at := Vector2(int(c[1]) * cw, 22 + int(c[0]) * ch)
		_label(vp, str(c[3]), at + Vector2(2, 2), 10)
		if c[2] == null:
			continue
		var v := ShipView.new()
		v.skin_on = true
		v.scale = Vector2(k / ShipView.CELL, k / ShipView.CELL)
		vp.add_child(v)
		v.show_ship(c[2])
		var hb: Rect2 = c[4]
		v.position = at + Vector2(cw / 2.0, 18.0) - (hb.position + Vector2(hb.size.x / 2.0, 0.0) - v.pivot) * k
	for i in 6:
		await process_frame
	var img := vp.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("sheet: ", path)
	vp.queue_free()
	await process_frame


func _label(vp: Node, text: String, at: Vector2, size: int) -> void:
	var t := Label.new()
	t.text = text
	t.position = at
	t.add_theme_font_size_override("font_size", size)
	t.add_theme_color_override("font_color", Color("#9fb0c8"))
	vp.add_child(t)
