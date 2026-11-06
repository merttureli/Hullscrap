extends RefCounted
## The reference layout and Rebuild (build mode's "Save layout" and "Rebuild" buttons). `capture` stores the tiles, the
## parts and the cables of a ship as JSON-friendly data (Ship.layout, saved with the run); `rebuild` puts back what is missing
## or destroyed compared with it, through BuildSession, so it is paid at the normal build cost and is ONE undo step.
## Hull = every tile (walls, outer hull, floor, doors); Parts = the components (with their fire group) and the cables.
## Order: hull before parts, cheap before dear (doors last: they need their walls). A part is taken from the cargo first,
## else made on the spot from its recipe (blueprint known, materials paid). What cannot be done is listed, never skipped silently.

const Ship = preload("res://scripts/ship/ship.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")

const WHAT := ["hull", "parts", "both"]


## The ship's tiles, parts and cables as a layout dictionary.
static func capture(ship: Ship) -> Dictionary:
	var tiles := []
	var g = ship.grid
	var cells: Array = g.tiles.keys()
	cells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for c in cells:
		var id: String = g.tiles[c]
		var e := {"c": [c.x, c.y], "id": id}
		if g.tile_flag(id, "door"):
			var piece: Array = g.door_piece(c)
			if piece.is_empty() or piece[0] != c:  # (one entry per door piece, at its first cell)
				continue
			e["axis"] = [1, 0] if piece.size() < 2 or piece[1].x != c.x else [0, 1]
		if not g.shape_of(c).is_empty():
			e["shape"] = g.shape_of(c).duplicate()
		tiles.append(e)
	var parts := []
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var i: Dictionary = ship.components.instances[uid]
		var anchor: Vector2i = i["out_anchor"] if not i["out_cells"].is_empty() else i["anchor"]  # a hull mount is placed by its outside half
		var p := {"id": i["id"], "anchor": [anchor.x, anchor.y], "rot": int(i["rot"])}
		if i.has("group"):
			p["group"] = int(i["group"])
		parts.append(p)
	var cables := []
	for c in ship.cables.cells.keys():
		cables.append([c.x, c.y])
	cables.sort_custom(func(a, b): return a[1] < b[1] or (a[1] == b[1] and a[0] < b[0]))
	return {"tiles": tiles, "parts": parts, "cables": cables}


## Put back what `layout` has and the ship lacks: `what` is "hull", "parts" or "both". One undo step on `session`.
## Returns {text, hull_done, hull_missing, parts_done, parts_missing, short {material: count}, blocked [[name, why]]}.
static func rebuild(session: BuildSession, layout: Dictionary, what: String) -> Dictionary:
	var ship: Ship = session.ship
	var g = ship.grid
	var hull := what != "parts"
	var parts := what != "hull"
	var changes := []
	var kinds := []  # per change: "hull", "part" or "cable"
	var names := []  # per change: what to call it in the summary
	if hull:
		var list := []
		for e in layout.get("tiles", []):
			var c := Vector2i(int(e["c"][0]), int(e["c"][1]))
			if g.get_tile(c) != "":
				continue
			var ch := {"layer": "tile", "cell": c, "to": str(e["id"])}
			if e.has("axis"):
				ch["axis"] = Vector2i(int(e["axis"][0]), int(e["axis"][1]))
			if e.has("shape"):
				ch["shape"] = str(e["shape"].get("shape", ""))
				ch["rot"] = int(e["shape"].get("rot", 0))
				ch["mirror"] = bool(e["shape"].get("mirror", false))
			list.append([_total(g.cost_of(ch["to"])) + (100000 if g.tile_flag(ch["to"], "door") else 0), ch])
		list.sort_custom(func(a, b): return a[0] < b[0])  # (stable on ties: row by row)
		for p in list:
			changes.append(p[1])
			kinds.append("hull")
			names.append("hull")
	if parts:
		var have := {}  # parts the ship still has: "id@x,y,rot"
		for uid in ship.components.instances:
			var i: Dictionary = ship.components.instances[uid]
			var a: Vector2i = i["out_anchor"] if not i["out_cells"].is_empty() else i["anchor"]
			have[_key(i["id"], a, int(i["rot"]))] = have.get(_key(i["id"], a, int(i["rot"])), 0) + 1
		var list := []
		var stock: Dictionary = ship.inventory.counts.duplicate()
		for p in layout.get("parts", []):
			var a := Vector2i(int(p["anchor"][0]), int(p["anchor"][1]))
			var k := _key(str(p["id"]), a, int(p["rot"]))
			if int(have.get(k, 0)) > 0:
				have[k] = int(have[k]) - 1
				continue
			var id := str(p["id"])
			var ch := {"layer": "component", "id": id, "anchor": a, "rot": int(p["rot"]), "craft": true}
			if p.has("group"):
				ch["group"] = int(p["group"])
			var in_cargo := int(stock.get(id, 0)) > 0
			if in_cargo:
				stock[id] = int(stock[id]) - 1
			list.append([-1 if in_cargo else _total(ship.crafting.def(id).get("materials", {})), ch])
		list.sort_custom(func(a, b): return a[0] < b[0])
		for p in list:
			changes.append(p[1])
			kinds.append("part")
			names.append(ship.components.def(p[1]["id"]).get("name", p[1]["id"]))
		for c in layout.get("cables", []):
			var cell := Vector2i(int(c[0]), int(c[1]))
			if not ship.cables.has(cell):
				changes.append({"layer": "cable", "cell": cell})
				kinds.append("cable")
				names.append("cables")
	var auto: bool = session.auto_floor
	session.auto_floor = false  # the layout says which cells get floor
	session.apply(changes)
	session.auto_floor = auto
	var reasons: Array = session.last_reasons
	var out := {"hull_done": 0, "hull_missing": 0, "parts_done": 0, "parts_missing": 0, "cables_done": 0, "cables_missing": 0, "short": {}, "blocked": []}
	var need := {}  # what the cells and parts left undone would take: name -> {material: count}
	var seen_block := {}
	for i in changes.size():
		var k: String = kinds[i]
		var done: bool = reasons[i] == ""
		out[k + "s_done" if k != "hull" else "hull_done"] += 1 if done else 0
		out[k + "s_missing" if k != "hull" else "hull_missing"] += 1
		if done:
			continue
		var why: String = reasons[i]
		if why.begins_with("not enough "):
			var cost: Dictionary = _cost(session, changes[i])
			var nm: String = names[i]
			if not need.has(nm):
				need[nm] = {}
			for m in cost:
				need[nm][m] = int(need[nm].get(m, 0)) + int(cost[m])
		elif k != "cable" or not seen_block.has(why):
			seen_block[why] = true
			out["blocked"].append([names[i], why])
	var short_txt := []
	for nm in need:
		for m in need[nm]:
			var lack: int = int(need[nm][m]) - ship.inventory.count(m)
			if lack > 0:
				short_txt.append("%d %s for %s" % [lack, m, "the hull" if nm == "hull" else str(nm)])
				out["short"][m] = int(out["short"].get(m, 0)) + lack
	var bits := []
	if hull:
		bits.append("%d hull cells" % out["hull_done"])
	if parts:
		bits.append("%d of %d parts" % [out["parts_done"], out["parts_missing"]])
	var text := "Rebuilt " + ", ".join(bits) + "."
	if changes.is_empty():
		text = "Nothing to rebuild: the ship matches the saved layout."
	if out["cables_missing"] > 0:
		text += " Cables: %d of %d." % [out["cables_done"], out["cables_missing"]]
	if not short_txt.is_empty():
		text += " Short: " + "; ".join(short_txt) + "."
	if not out["blocked"].is_empty():
		var b := []
		for e in out["blocked"]:
			b.append("%s (%s)" % [e[0], e[1]])
		text += " Not built: " + ", ".join(b) + "."
	out["text"] = text
	return out


static func _key(id: String, a: Vector2i, rot: int) -> String:
	return "%s@%d,%d,%d" % [id, a.x, a.y, rot]


static func _total(cost: Dictionary) -> int:
	var n := 0
	for m in cost:
		n += int(cost[m])
	return n


## The materials a change would take.
static func _cost(session: BuildSession, ch: Dictionary) -> Dictionary:
	match ch["layer"]:
		"tile":
			return session.grid.cost_of(ch["to"])
		"component":
			return session.ship.crafting.def(ch["id"]).get("materials", {})
		_:
			return session.cable_cost
