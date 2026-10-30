extends SceneTree
## Not a test (the runner only loads test_*.gd). Rebuilds the test rammer enemy, data/ships/rustfang_rammer.json:
##   godot --headless --path . --script res://tests/tool_make_rammer.gd
## A scrap ship with a ram-plated wedge bow (a two-thick ram plating skin round a floor cavity, its edges
## built from slope45 pieces), two Kickjets, two Rattle Bursts, two scrap reactors and the rammer pilot
## style. Local coordinates: the top-left cell of its bounding box is 0,0. Built through BuildSession,
## wired by a breadth-first router, exported with Ship.to_dict() plus its "ai" entry. Prints a map.

const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")

const GRID := Vector2i(63, 63)
const SIZE := Vector2i(14, 20)
const MARGIN := 2
const OUT := "res://data/ships/rustfang_rammer.json"
const STOCK := {"scrap": 5000, "copper": 600, "titanium": 400, "polymer": 100}
const WEDGE := 7  ## rows of the wedge; its widest row spans the whole hull
const SIDES: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const PARTS := [
	["rattle_burst_scrap", 1, 8], ["rattle_burst_scrap", 9, 8], ["helm", 6, 9],
	["reactor_scrap_mk1", 1, 13], ["reactor_scrap_mk1", 9, 13],
	["engine_scrap_mk1", 1, 17], ["engine_scrap_mk1", 9, 17],
]

var _bad := false


func _init() -> void:
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
	var off: Vector2i = (GRID - SIZE) / 2
	var session := BuildSession.new(ship)

	# The two decks: scrap plate walls, floor inside. The row between them is a shared wall.
	var deck := {}
	for r in [Rect2i(0, 7, 14, 6), Rect2i(0, 12, 14, 8)]:
		for y in r.size.y:
			for x in r.size.x:
				var edge: bool = x == 0 or y == 0 or x == r.size.x - 1 or y == r.size.y - 1
				var c: Vector2i = r.position + Vector2i(x, y) + off
				if edge or not deck.has(c):
					deck[c] = "scrap_plate" if edge else "floor"
	var changes := []
	for c in deck:
		changes.append({"layer": "tile", "cell": c, "to": deck[c]})
	_apply(session, changes, "decks")

	# The wedge: row r has its edge slopes at 6 - r and 7 + r, ram plating next to them, floor between.
	changes = []
	for r in WEDGE:
		for x in range(7 - r, 7 + r):
			var c := Vector2i(x, r) + off
			if r >= 1 and (x == 7 - r or x == 6 + r):
				changes.append({"layer": "tile", "cell": c, "to": "ram_plating"})
			elif r >= 2:
				changes.append({"layer": "tile", "cell": c, "to": "floor"})
	_apply(session, changes, "wedge body")
	changes = []
	for r in WEDGE:
		changes.append_array(session.plan_piece("slope45", "ram_plating", Vector2i(6 - r, r) + off, 0, true)["changes"])
		changes.append_array(session.plan_piece("slope45", "ram_plating", Vector2i(7 + r, r) + off, 0, false)["changes"])
	_apply(session, changes, "wedge slopes")

	_apply(session, [
		{"layer": "tile", "cell": Vector2i(6, 7) + off, "to": "door", "axis": Vector2i.RIGHT},
		{"layer": "tile", "cell": Vector2i(6, 12) + off, "to": "door", "axis": Vector2i.RIGHT},
	], "doors")

	changes = []
	for p in PARTS:
		changes.append({"layer": "component", "id": p[0], "anchor": Vector2i(p[1], p[2]) + off, "rot": 0})
	_apply(session, changes, "parts")
	_wire(ship, session)

	var lo := Vector2i(GRID)
	var hi := Vector2i.ZERO
	for c in g.tiles:
		lo = lo.min(c)
		hi = hi.max(c)
	lo -= Vector2i(MARGIN, MARGIN)
	hi += Vector2i(MARGIN, MARGIN)
	g.hull.clear()
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			g.hull[Vector2i(x, y)] = true
	ship.inventory.load_dict({"scrap": 200, "copper": 30})
	ship.refresh()

	var saved := ship.to_dict()
	saved["blurb"] = "A scrap wedge with ram plating for a nose and two Kickjets for a temper. Flies straight at you, backs off, comes round again."
	saved["ai"] = {"style": "rammer"}
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(_format(saved))
	f.close()
	_report()
	quit(1 if _bad else 0)


func _apply(session: BuildSession, changes: Array, what: String) -> void:
	var r := session.apply(changes)
	if r["skipped"] > 0:
		printerr("FAIL %s: %d of %d changes refused: %s" % [what, r["skipped"], changes.size(), r["reason"]])
		_bad = true


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


func _report() -> void:
	var ship := Ship.from_design(OUT)
	if ship == null:
		printerr("FAIL the exported file does not load")
		_bad = true
		return
	var g: ShipGrid = ship.grid
	var lo := Vector2i(GRID)
	var hi := Vector2i.ZERO
	for c in g.tiles:
		lo = lo.min(c)
		hi = hi.max(c)
	var glyph := {"reactor": "R", "engine": "E", "weapon": "W", "helm": "H"}
	for y in range(lo.y, hi.y + 1):
		var row := ""
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			var ch := " "
			var t: String = g.get_tile(c)
			if t != "":
				ch = {"floor": ".", "scrap_plate": "#", "door": "D", "ram_plating": "r"}.get(t, "?")
				if g.shapes.has(c):
					ch = "/" if t == "ram_plating" else "~"
			var uid: int = ship.components.at(c)
			if uid >= 0:
				ch = glyph.get(ship.components.def(ship.components.instances[uid]["id"])["family"], "?")
			row += ch
		print(row)
	var unpowered := []
	for uid in ship.components.instances:
		if not ship.power_state["powered"].get(uid, false):
			unpowered.append(ship.components.def(ship.components.instances[uid]["id"])["name"])
	var arena := Arena.new(1)
	arena.add_ship(ship)
	var co = arena.ships[0]
	print("Rustfang: unpowered %s  rooms %d sealed %s  can_fly '%s'  bow %s" % [str(unpowered), ship.atmosphere.rooms.size(),
		str(ship.atmosphere.rooms.all(func(r): return r["sealed"])), co.flight.can_fly(ship.components, co.powered), str(PilotAI.bow_of(co))])
	print("   mass %.0f  thrust %.1f  accel %.1f px/s2  turn %.2f rad/s2  inertia %.0f  hull %d  weapons %d  cables %d  tiles %d  shaped %d" % [
		co.mass, co.thrust, co.thrust * co.flight.thrust_to_accel / co.mass, co.thrust * co.flight.turn_factor / co.mass, co.inertia,
		co.hull_max, co.mounts.size(), ship.cables.cells.size(), g.tiles.size(), g.shapes.size()])
