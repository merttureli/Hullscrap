extends RefCounted
## The fixtures of a module station (data/station_fixtures.json): the big things in a room, a reactor core, a market stall, a bunk, a holo-table.
## Pure logic. A fixture covers cells like a prop and blocks the walk like one (blocks: true) or is walked through. It is NOT a prop, so the container
## ids, the slots and the loot are what they were before there were fixtures; a fixture may be a container only by being a prop (none is).
## Placement is data: per module (and room, and room purpose) a list of rules {fixture, n, at (wall, corner, centre, free or row), inset, gap, window
## (only: the wall must be a window wall; avoid: it must not hide a window; default avoid for a `tall` fixture), ref (the room's area n is meant for: n
## scales with area / ref), room, purpose, states}. Everything comes from a stream of the site's seed of its own. A fixture goes where the lanes stay
## clear: after each blocking one every door of its room must still reach every other by a 2x2 body, and every container and bed in it must still
## be reachable (the walk is checked like beds.gd's), else it is taken out again and another place is tried.
## A fixture of a station is {id, fixture, cell, size, room, dir (the way it faces: into the room), blocks, glow, variant (the art of its section's
## race), dead (screens and lamps off), wreck (toppled or broken)}.

const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Races = preload("res://scripts/board/station_races.gd")

const PATH := "res://data/station_fixtures.json"
const SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

static var _cfg := {}
static var enabled := true  ## tests switch it off to compare a site without fixtures


static func config() -> Dictionary:
	if _cfg.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		assert(d is Dictionary and d.get("fixtures") is Dictionary, "bad fixtures: " + PATH)
		_cfg = d
	return _cfg


static func defs() -> Dictionary:
	return config()["fixtures"]


## The rules of module `mid` (its own, else those of the module it counts as... none: a module without rules has no fixtures).
static func rules_of(mid: String) -> Array:
	return config()["rules"].get(mid, [])


## The cells a fixture covers.
static func cells_of(f: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in f["size"].y:
		for x in f["size"].x:
			out.append(f["cell"] + Vector2i(x, y))
	return out


## Fill site `s` (a module station, built to its beds): s.fixtures and s.fixture_of, and the blocking ones are walls of s.walk.
static func place(s) -> void:
	s.fixtures = []
	s.fixture_of = {}
	if not enabled:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = s._mix(s.seed_value, "fixtures", 0)
	var cfg := config()
	var st: Dictionary = cfg["states"].get(s.state, {})
	var taken := {}
	for b in s.beds:
		for c in s.bed_cells(b):
			taken[c] = true
	for p in s.posts:  # (a sentry's body)
		var a := Vector2i(floori(p["pos"].x), floori(p["pos"].y)) - Vector2i.ONE
		for c in Pathfinder.body_cells(a):
			taken[c] = true
	for r in s.rooms:
		if r["purpose"] == "gone" or not r.has("module"):
			continue
		var m: Dictionary = s.modules[int(r["module"])]
		var mouth: Dictionary = s._mouth(r)
		for rule in rules_of(str(m["id"])):
			if int(rule.get("room", 0)) != int(r.get("mroom", 0)):
				continue
			if rule.has("purpose") and str(rule["purpose"]) != str(r["purpose"]):
				continue
			if rule.has("states") and not rule["states"].has(s.state):
				continue
			var def: Dictionary = defs()[str(rule["fixture"])]
			var n := rng.randi_range(int(rule["n"][0]), int(rule["n"][1]))
			if rule.has("ref"):
				n = int(floor(float(n) * float(r["rect"].get_area()) / float(rule["ref"]) + rng.randf()))
			var at := str(rule.get("at", "wall"))
			if at != "centre":  # (the data's `density` fills the big rooms: a centrepiece stays one)
				n = int(floor(float(n) * float(cfg.get("density", 1.0)) + rng.randf()))
			var placed := 0
			if at == "row":
				placed = _row(s, r, rule, def, n, mouth, taken, rng)
			else:
				for i in n:
					if _one(s, r, rule, def, at, mouth, taken, rng):
						placed += 1
		# the state's dice come last, from the same stream, so where they stand never depends on them
	for f in s.fixtures:
		var m: Dictionary = s.modules[int(s.rooms[f["room"]]["module"])]
		var def: Dictionary = defs()[f["fixture"]]
		var roll := rng.randf()
		var roll2 := rng.randf()
		f["dead"] = bool(def.get("screen", false) or def.get("glow", "") != "") and (not m["powered"] or roll < float(st.get("dead", 0.0)))
		f["wreck"] = bool(def.get("topple", false)) and roll2 < float(st.get("topple", 0.0))


## One fixture: the candidates by `at` in a random order, the first that fits. True when placed.
static func _one(s, r: Dictionary, rule: Dictionary, def: Dictionary, at: String, mouth: Dictionary, taken: Dictionary, rng: RandomNumberGenerator) -> bool:
	var size := Vector2i(int(def["size"][0]), int(def["size"][1]))
	var cands := _cands(r["rect"], size, at, int(rule.get("inset", 0)), rng)
	if at == "centre":  # (a centrepiece that finds no place in the middle takes any other)
		cands.append_array(_cands(r["rect"], size, "free", 0, rng))
	for c in cands:
		if _fits(s, r, rule, def, c, mouth, taken):
			_commit(s, r, def, str(rule["fixture"]), c, taken)
			return true
	return false


## n fixtures in a line along one wall (inset cells in), `gap` cells apart, from a random start; as many as fit.
static func _row(s, r: Dictionary, rule: Dictionary, def: Dictionary, n: int, mouth: Dictionary, taken: Dictionary, rng: RandomNumberGenerator) -> int:
	var size := Vector2i(int(def["size"][0]), int(def["size"][1]))
	var gap := int(rule.get("gap", 1))
	var inset := int(rule.get("inset", 0))
	var rect: Rect2i = r["rect"]
	var walls := [0, 1, 2, 3]
	for i in range(3, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = walls[i]
		walls[i] = walls[j]
		walls[j] = t
	for w in walls:
		var horizontal: bool = w < 2
		var sz := size if horizontal else Vector2i(size.y, size.x)
		var span: int = (rect.size.x if horizontal else rect.size.y)
		var step: int = (sz.x if horizontal else sz.y) + gap
		var fit := maxi((span + gap) / step, 0)
		if fit <= 0:
			continue
		var count := mini(n, fit)
		var slack := span - (count * step - gap)
		var off := rng.randi() % (slack + 1)
		var placed := 0
		for k in count:
			var along := off + k * step
			var cell: Vector2i
			var dir: Vector2i
			match w:
				0:
					cell = rect.position + Vector2i(along, inset)
					dir = Vector2i.DOWN
				1:
					cell = Vector2i(rect.end.x - sz.x - inset, rect.position.y + along)
					dir = Vector2i.LEFT
				2:
					cell = Vector2i(rect.position.x + along, rect.end.y - sz.y - inset)
					dir = Vector2i.UP
				_:
					cell = rect.position + Vector2i(inset, along)
					dir = Vector2i.RIGHT
			var c := {"cell": cell, "size": sz, "dir": dir}
			if _fits(s, r, rule, def, c, mouth, taken):
				_commit(s, r, def, str(rule["fixture"]), c, taken)
				placed += 1
		if placed > 0:
			return placed
	return 0


## The places `at` (wall, corner, centre, free) for a fixture of `size` in `rect`, shuffled: [{cell, size, dir}].
static func _cands(rect: Rect2i, size: Vector2i, at: String, inset: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var flip := Vector2i(size.y, size.x)
	match at:
		"wall":
			for x in range(rect.position.x, rect.end.x - size.x + 1):
				out.append({"cell": Vector2i(x, rect.position.y + inset), "size": size, "dir": Vector2i.DOWN})
				out.append({"cell": Vector2i(x, rect.end.y - size.y - inset), "size": size, "dir": Vector2i.UP})
			for y in range(rect.position.y, rect.end.y - flip.y + 1):
				out.append({"cell": Vector2i(rect.position.x + inset, y), "size": flip, "dir": Vector2i.RIGHT})
				out.append({"cell": Vector2i(rect.end.x - flip.x - inset, y), "size": flip, "dir": Vector2i.LEFT})
		"corner":
			for sz in [size, flip]:
				for cx in [rect.position.x, rect.end.x - sz.x]:
					for cy in [rect.position.y, rect.end.y - sz.y]:
						out.append({"cell": Vector2i(cx, cy), "size": sz, "dir": Vector2i.DOWN if cy == rect.position.y else Vector2i.UP})
		"centre":
			for sz in [size, flip]:
				var base: Vector2i = rect.position + (rect.size - sz) / 2
				for j in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(0, 2)]:
					out.append({"cell": base + j, "size": sz, "dir": Vector2i.DOWN})
		_:
			for sz in [size, flip]:
				for y in range(rect.position.y, rect.end.y - sz.y + 1):
					for x in range(rect.position.x, rect.end.x - sz.x + 1):
						out.append({"cell": Vector2i(x, y), "size": sz, "dir": Vector2i.DOWN})
	if at == "centre":  # (the middle first)
		return out
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = out[i]
		out[i] = out[j]
		out[j] = t
	return out


static func _fits(s, r: Dictionary, rule: Dictionary, def: Dictionary, c: Dictionary, mouth: Dictionary, taken: Dictionary) -> bool:
	var cells: Array[Vector2i] = []
	for y in c["size"].y:
		for x in c["size"].x:
			cells.append(c["cell"] + Vector2i(x, y))
	for cc in cells:
		if not r["rect"].has_point(cc) or mouth.has(cc) or s.prop_of.has(cc) or taken.has(cc) or int(s.room_of.get(cc, -1)) != int(r["id"]):
			return false
	var win := 0
	for cc in cells:
		for d in SIDES:
			if s.grid.get_tile(cc + d) == "" and not s.room_of.has(cc + d):
				win += 1
	var want := str(rule.get("window", "avoid" if bool(def.get("tall", false)) else ""))
	if want == "only" and win == 0:
		return false
	if want == "avoid" and win > 0:
		return false
	if not bool(def["blocks"]):
		return true
	for cc in cells:
		s.walk.tiles[cc] = "wall"
	var ok := _lanes_ok(s, r, cells)
	if not ok:
		for cc in cells:
			s.walk.tiles[cc] = s.grid.tiles[cc]
	return ok


static func _commit(s, r: Dictionary, def: Dictionary, fid: String, c: Dictionary, taken: Dictionary) -> void:
	var m: Dictionary = s.modules[int(r["module"])]
	var f := {"id": s.fixtures.size(), "fixture": fid, "cell": c["cell"], "size": c["size"], "room": int(r["id"]), "dir": c["dir"], "blocks": bool(def["blocks"]),
		"glow": str(def.get("glow", "")), "variant": Races.variant(str(m.get("race", "")), fid), "dead": false, "wreck": false}
	s.fixtures.append(f)
	for cc in cells_of(f):
		s.fixture_of[cc] = f["id"]
		taken[cc] = true


## After a blocking fixture on `cells` (already walls of the walk): every door of room `r` still reaches every other through the room by a 2x2 body, and every
## container and bed of it can still be reached (a free body within a cell of it).
static func _lanes_ok(s, r: Dictionary, cells: Array[Vector2i]) -> bool:
	var anchors: Array[Vector2i] = s.free_anchors(r["id"])
	var set := {}
	for a in anchors:
		set[a] = true
	var starts: Array = []
	for did in r["doors"]:
		var d: Dictionary = s.doors[did]
		var inside: Array[Vector2i] = []
		for dc in d["cells"]:
			for side in SIDES:
				var f: Vector2i = dc + side
				if int(s.room_of.get(f, -1)) == int(r["id"]):
					inside.append(f)
		var found := false
		for f in inside:
			for ox in [-1, 0]:
				for oy in [-1, 0]:
					var a: Vector2i = f + Vector2i(ox, oy)
					if set.has(a) and not found:
						var body: Array = Pathfinder.body_cells(a)
						if inside.all(func(q): return body.has(q)):
							starts.append(a)
							found = true
		if not found:
			return false
	if starts.is_empty():
		return true
	var seen := {starts[0]: true}
	var queue: Array = [starts[0]]
	while not queue.is_empty():
		var a: Vector2i = queue.pop_back()
		for d in SIDES:
			var b: Vector2i = a + d
			if set.has(b) and not seen.has(b):
				seen[b] = true
				queue.append(b)
	for a in starts:
		if not seen.has(a):
			return false
	var near := {}
	for a in seen:
		for c in Pathfinder.body_cells(a):
			near[c] = true
	for p in s.props:
		if int(p["room"]) == int(r["id"]) and p["loot"] and not p.has("foe") and not _touches(s.cells_of(p), near):
			return false
	for b in s.beds:
		if int(b["room"]) == int(r["id"]) and not _touches(s.bed_cells(b), near):
			return false
	return true


static func _touches(cells: Array, near: Dictionary) -> bool:
	for c in cells:
		for ox in range(-1, 2):
			for oy in range(-1, 2):
				if near.has(c + Vector2i(ox, oy)):
					return true
	return false
