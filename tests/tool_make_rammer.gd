extends SceneTree
## Not a test (the runner only loads test_*.gd). Rebuilds the test rammer enemy, data/ships/rustfang_rammer.json:
##   godot --headless --path . --script res://tests/tool_make_rammer.gd [-- skin]
## A scrap ship shaped like a battering ram (docs/CONTENT.md 4c): a V bow of ram plating (a two-thick skin
## round a floor cavity, its edges exact slope45 cells, its tip cut flat to carry the bow gun), short
## stubby flanks, and a heavy engine block at the stern, wider than the flanks and chamfered at the rear
## corners, with two Kickjets on its back wall. A Bolt Thrower through the flat tip of the bow (a fixed
## gun: the whole ship is aimed), two scrap reactors and the rammer pilot style. The outline is turned
## into cells by hull_outline.gd. Local coordinates: the top-left corner of its bounding box is 0,0. Built
## through BuildSession (a mount is [id, x, y, rot] with x, y its OUTSIDE half's top-left, see
## tool_make_starters.gd), wired by a breadth-first router, exported with Ship.to_dict() plus its "ai"
## entry. Prints a map; "skin" prints the bare hull and builds nothing.

const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const HullOutline = preload("res://tests/hull_outline.gd")

const GRID := Vector2i(63, 63)
const MARGIN := 2
const OUT := "res://data/ships/rustfang_rammer.json"
const STOCK := {"scrap": 5000, "copper": 600, "titanium": 400, "polymer": 100}
const BOW_ROWS := 4  ## the rows of the V bow, ram plated two thick; the flanks and the engine block are scrap plate
const OUTLINE := [[6, 0], [10, 0], [14, 4], [14, 6], [16, 8], [16, 16], [12, 20], [4, 20], [0, 16], [0, 8], [2, 6], [2, 4]]
const WALLS := [[2, 9, 13, 9], [2, 15, 13, 15], [2, 16, 2, 16], [13, 16, 13, 16]]  ## bulkheads [x0, y0, x1, y1]: floor turned into wall: the bow room's floor, the engine room's ceiling and corners
const DOORS := [[7, 9, "h"], [7, 15, "h"]]  ## [x, y, "h" | "v"]
const PARTS := [  ## [id, x, y, rot]; a mount is placed by its outside half
	["bolt_thrower_scrap", 6, -2], ["helm", 7, 5],
	["reactor_scrap_mk1", 3, 10], ["reactor_scrap_mk1", 9, 10],
	["engine_scrap_mk1", 4, 20, 2], ["engine_scrap_mk1", 8, 20, 2],
]
const SIDES: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

var _bad := false


func _init() -> void:
	var ras := HullOutline.rasterize(OUTLINE)
	for e in ras["errors"]:
		_fail("Rustfang: " + e)
	var skin := HullOutline.layers(ras["cells"], func(c): return "ram_plating" if c.y < BOW_ROWS else "scrap_plate", func(c): return "ram_plating" if c.y < BOW_ROWS else ("scrap_plate" if c.y < 16 else ""))
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in skin:
		lo = lo.min(c)
		hi = hi.max(c)
	if lo != Vector2i.ZERO:
		_fail("Rustfang: the outline starts at %s, not 0,0" % str(lo))
	for w in WALLS:
		for y in range(w[1], w[3] + 1):
			for x in range(w[0], w[2] + 1):
				var c := Vector2i(x, y)
				if not skin.has(c):
					_fail("Rustfang: the bulkhead %s leaves the hull at %s" % [str(w), str(c)])
				elif skin[c]["tile"] == "floor":
					skin[c]["tile"] = "wall"
	if "skin" in OS.get_cmdline_user_args():
		_print_skin(skin, lo, hi)
		quit(1 if _bad else 0)
		return

	var defs := TileDefs.new()
	defs.load_file(Ship.TILES_PATH)
	var ship := Ship.new("Rustfang", ShipGrid.new(GRID, defs))
	var g: ShipGrid = ship.grid
	for y in GRID.y:
		for x in GRID.x:
			g.hull[Vector2i(x, y)] = true
	ship.inventory.load_dict(STOCK)
	for p in PARTS:
		ship.inventory.add(p[0], 1)
	var off: Vector2i = (GRID - (hi - lo + Vector2i.ONE)) / 2
	var session := BuildSession.new(ship)

	var cells: Array = skin.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var changes := []
	for c in cells:
		var e := {"layer": "tile", "cell": c + off, "to": skin[c]["tile"]}
		e.merge(skin[c]["shape"])
		changes.append(e)
	_apply(session, changes, "hull")
	changes = []
	for d in DOORS:
		changes.append({"layer": "tile", "cell": Vector2i(d[0], d[1]) + off, "to": "door", "axis": Vector2i.RIGHT if d[2] == "h" else Vector2i.DOWN})
	_apply(session, changes, "doors")
	for p in PARTS:  # one at a time, so a refusal names its part
		_apply(session, [{"layer": "component", "id": p[0], "anchor": Vector2i(p[1], p[2]) + off, "rot": p[3] if p.size() > 3 else 0}], "%s at %d,%d" % [p[0], p[1], p[2]])
	_wire(ship, session)

	var blo := Vector2i(GRID)
	var bhi := Vector2i.ZERO
	for c in g.tiles:
		blo = blo.min(c)
		bhi = bhi.max(c)
	for uid in ship.components.instances:
		for c in ship.components.instances[uid]["out_cells"]:
			blo = blo.min(c)
			bhi = bhi.max(c)
	blo -= Vector2i(MARGIN, MARGIN)
	bhi += Vector2i(MARGIN, MARGIN)
	g.hull.clear()
	for y in range(blo.y, bhi.y + 1):
		for x in range(blo.x, bhi.x + 1):
			g.hull[Vector2i(x, y)] = true
	ship.inventory.load_dict({"scrap": 200, "copper": 30})
	ship.refresh()

	var saved := ship.to_dict()
	saved["blurb"] = "A scrap wedge with ram plating for a nose and two Kickjets for a temper. Flies straight at you, backs off, comes round again."
	saved["ai"] = {"style": "rammer", "aim_skill": 0.4}
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(_format(saved))
	f.close()
	_report(off)
	quit(1 if _bad else 0)


func _apply(session: BuildSession, changes: Array, what: String) -> void:
	var r := session.apply(changes)
	if r["skipped"] > 0:
		_fail("%s: %d of %d changes refused: %s" % [what, r["skipped"], changes.size(), r["reason"]])


func _fail(text: String) -> void:
	printerr("FAIL " + text)
	_bad = true


## The bare hull: # steel, . floor, s scrap plate, r ram plating, triangles and / \ for slopes.
func _print_skin(skin: Dictionary, lo: Vector2i, hi: Vector2i) -> void:
	print(HullOutline.ruler(lo, hi))
	for y in range(lo.y, hi.y + 1):
		var row := "%3d " % y
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			if not skin.has(c):
				row += " "
			elif not skin[c]["shape"].is_empty():
				row += HullOutline.shape_glyph(skin[c]["shape"])
			else:
				row += {"wall": "#", "floor": ".", "scrap_plate": "s", "ram_plating": "r"}.get(skin[c]["tile"], "?")
		print(row)


## Join every part to the first reactor: each part's cheapest (fewest cells) cable path to the network, nearest first.
func _wire(ship: Ship, session: BuildSession) -> void:
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	var net := {}
	var rest: Array = []
	for uid in uids:
		if ship.components.def(ship.components.instances[uid]["id"])["family"] == "reactor" and net.is_empty():
			net[ship.components.instances[uid]["cells"][5]] = true
		else:
			rest.append(uid)
	var cables := [{"layer": "cable", "cell": net.keys()[0]}]
	while not rest.is_empty():
		var best: Array = []
		var best_uid := -1
		for uid in rest:
			var path := _route(ship, ship.components.instances[uid]["cells"], net)
			if not path.is_empty() and (best.is_empty() or path.size() < best.size()):
				best = path
				best_uid = uid
		if best.is_empty():
			printerr("FAIL no route to a part")
			_bad = true
			return
		for c in best:
			net[c] = true
			cables.append({"layer": "cable", "cell": c})
		rest.erase(best_uid)
	_apply(session, cables, "cables")


## Breadth first from the cells `starts` over built cells to the first cell of `targets`: the path without the target cells.
func _route(ship: Ship, starts: Array, targets: Dictionary) -> Array:
	var prev := {}
	var queue: Array = []
	for s in starts:
		prev[s] = null
		queue.append(s)
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if targets.has(c):
			var path: Array = []
			var at = prev[c]
			while at != null:
				path.append(at)
				at = prev[at]
			return path.filter(func(p): return not targets.has(p))
		for s in SIDES:
			var n: Vector2i = c + s
			if not prev.has(n) and (ship.grid.tiles.has(n) or ship.components.at(n) >= 0):
				prev[n] = c
				queue.append(n)
	return []


func _format(d: Dictionary) -> String:
	var keys := d.keys()
	keys.sort()
	var lines := []
	for k in keys:
		if k == "tiles":
			var rows := []
			for t in d[k]:
				rows.append("\t" + JSON.stringify(t))
			lines.append("\"tiles\": [\n" + ",\n".join(rows) + "\n]")
		else:
			lines.append("%s: %s" % [JSON.stringify(k), JSON.stringify(d[k], "", true)])
	return "{\n" + ",\n".join(lines) + "\n}\n"


func _report(off: Vector2i) -> void:
	var ship := Ship.from_design(OUT)
	if ship == null:
		_fail("the exported file does not load")
		return
	var g: ShipGrid = ship.grid
	var lo := Vector2i(GRID)
	var hi := Vector2i.ZERO
	var cells: Array = g.tiles.keys()
	for uid in ship.components.instances:
		cells.append_array(ship.components.instances[uid]["out_cells"])
	for c in cells:
		lo = lo.min(c)
		hi = hi.max(c)
	var glyph := {"reactor": "R", "engine": "E", "weapon": "W", "helm": "H"}
	var tile_glyph := {"floor": ".", "wall": "#", "door": "D", "scrap_plate": "s", "ram_plating": "r"}
	print(HullOutline.ruler(lo - off, hi - off))
	for y in range(lo.y, hi.y + 1):
		var row := "%3d " % (y - off.y)
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			var ch := " "
			var t: String = g.get_tile(c)
			if t != "":
				ch = HullOutline.shape_glyph(g.shapes[c]) if g.shapes.has(c) else tile_glyph.get(t, "?")
			var uid: int = ship.components.at(c)
			if uid >= 0:
				ch = glyph.get(ship.components.def(ship.components.instances[uid]["id"])["family"], "?")
			elif ship.components.at_out(c) >= 0:
				ch = glyph.get(ship.components.def(ship.components.instances[ship.components.at_out(c)]["id"])["family"], "?").to_lower()
			row += ch
		print(row)
	var unpowered := []
	for uid in ship.components.instances:
		if not ship.power_state["powered"].get(uid, false):
			unpowered.append(ship.components.def(ship.components.instances[uid]["id"])["name"])
	var arena := Arena.new(1)
	arena.add_ship(ship)
	var co = arena.ships[0]
	var tlo := Vector2i(GRID)
	var thi := Vector2i.ZERO
	var area := 0.0
	for c in g.tiles:
		tlo = tlo.min(c)
		thi = thi.max(c)
		area += g.area_at(c)
	var box := thi - tlo + Vector2i.ONE
	print("Rustfang: tiles %dx%d, solid %.0f%% of its box, %d shaped  unpowered %s  rooms %d sealed %s  can_fly '%s'  bow %s" % [box.x, box.y, 100.0 * area / (box.x * box.y), g.shapes.size(),
		str(unpowered), ship.atmosphere.rooms.size(), str(ship.atmosphere.rooms.all(func(r): return r["sealed"])), co.flight.can_fly(ship.components, co.powered), str(PilotAI.bow_of(co))])
	print("   mass %.0f  thrust %.1f  accel %.1f px/s2  turn %.2f rad/s2  inertia %.0f  hull %d  weapons %d  cables %d  tiles %d  shaped %d" % [
		co.mass, co.thrust, co.thrust * co.flight.thrust_to_accel / co.mass, co.thrust * co.flight.turn_factor / co.mass, co.inertia,
		co.hull_max, co.mounts.size(), ship.cables.cells.size(), g.tiles.size(), g.shapes.size()])
	var pockets := HullOutline.pockets(ship)
	if not pockets.is_empty():
		_fail("Rustfang: %d floor cells no crew body reaches from the helm: %s" % [pockets.size(), str(pockets.map(func(c): return c - off))])
