extends RefCounted
## What a module station's walls and floors carry besides its fixtures (data/station_fixtures.json `dressing`): pipes, cables, vents, lamps, signs, posters and
## panels on the walls; hazard stripes, arrows, lane marks, stains and scuffs on the floor; and the state's own: scorch marks and debris (abandoned), clutter
## (half-active), frost in an airless room. None of it blocks and none of it is a prop. Placed from a stream of the site's seed of its own, after the fixtures,
## so nothing else moves. An item is {kind, cell, dir (the way it faces: into the room for a wall item), room, len, seed, word (a sign's)}.
## A wall item sits on the wall cell `cell` (outside the room's floor), `dir` pointing into the room; a floor item on a floor cell.

const SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func config() -> Dictionary:
	return preload("res://scripts/board/station_fixtures.gd").config()["dressing"]


## Fill site `s`: s.dressing.
static func place(s) -> void:
	s.dressing = []
	var cfg := config()
	var rng := RandomNumberGenerator.new()
	rng.seed = s._mix(s.seed_value, "dressing", 0)
	var st: Dictionary = cfg["states"].get(s.state, {})
	for r in s.rooms:
		if r["purpose"] == "gone" or not r.has("module"):
			continue
		var m: Dictionary = s.modules[int(r["module"])]
		var rect: Rect2i = r["rect"]
		var area := float(rect.get_area())
		var mouth: Dictionary = s._mouth(r)
		var walls := _wall_cells(s, r, mouth)
		var sign_word := str(cfg["signs"].get(str(r["purpose"]), ""))
		if bool(m.get("own", false)):  # (a race's own room is named for what it is)
			sign_word = str(m["name"]).to_upper()
		if sign_word == "" and not r["corridor"]:
			sign_word = str(m["name"]).to_upper()
		# walls: one sign (a room with a name), then pipes, cables, vents, lamps, panels, posters by the room's area
		if sign_word != "" and not walls.is_empty():
			var best := _pick_wall(walls, rng, true)
			if not best.is_empty():
				s.dressing.append({"kind": "sign", "cell": best["cell"], "dir": best["dir"], "room": r["id"], "len": 3, "seed": rng.randi(), "word": sign_word})
				_take(walls, best, 3)
		for kind in cfg["wall"]:
			var rule: Dictionary = cfg["wall"][kind]
			if rule.has("purposes") and not rule["purposes"].has(str(r["purpose"])):
				continue
			var n := int(floor(float(rule["per_area"]) * area / 40.0 + rng.randf() * float(rule.get("extra", 1.0))))
			n = mini(n, int(rule.get("max", 6)))
			for i in n:
				var pick := _pick_wall(walls, rng, false)
				if pick.is_empty():
					break
				var len := rng.randi_range(int(rule["len"][0]), int(rule["len"][1]))
				s.dressing.append({"kind": kind, "cell": pick["cell"], "dir": pick["dir"], "room": r["id"], "len": len, "seed": rng.randi()})
				_take(walls, pick, len)
		# the floor
		var floor_free: Array = _floor_cells(s, r, mouth)
		for kind in cfg["floor"]:
			var rule: Dictionary = cfg["floor"][kind]
			if rule.has("purposes") and not rule["purposes"].has(str(r["purpose"])):
				continue
			var n := int(floor(float(rule["per_area"]) * area / 40.0 + rng.randf() * float(rule.get("extra", 1.0))))
			for i in mini(n, int(rule.get("max", 6))):
				if floor_free.is_empty():
					break
				var c: Vector2i = floor_free[rng.randi() % floor_free.size()]
				s.dressing.append({"kind": kind, "cell": c, "dir": SIDES[rng.randi() % 4], "room": r["id"], "len": 1, "seed": rng.randi()})
		# hazard stripes round whatever burns or turns (fixtures with `hazard`): a frame of stripes just outside it
		for f in s.fixtures:
			if int(f["room"]) == int(r["id"]) and bool(_def(f["fixture"]).get("hazard", false)):
				s.dressing.append({"kind": "hazard", "cell": f["cell"], "dir": f["dir"], "room": r["id"], "len": 1, "seed": 0, "size": f["size"]})
		# the state: scorch and debris (abandoned), clutter (half), frost in an airless room
		for kind in st.get("floor", {}):
			var rule: Dictionary = st["floor"][kind]
			var n := int(floor(float(rule["per_area"]) * area / 40.0 + rng.randf()))
			for i in mini(n, int(rule.get("max", 5))):
				if floor_free.is_empty():
					break
				var c: Vector2i = floor_free[rng.randi() % floor_free.size()]
				s.dressing.append({"kind": kind, "cell": c, "dir": SIDES[rng.randi() % 4], "room": r["id"], "len": 1, "seed": rng.randi()})
		for kind in st.get("wall", {}):
			var rule: Dictionary = st["wall"][kind]
			var n := int(floor(float(rule["per_area"]) * area / 40.0 + rng.randf()))
			for i in mini(n, int(rule.get("max", 4))):
				var pick := _pick_wall(walls, rng, false)
				if pick.is_empty():
					break
				s.dressing.append({"kind": kind, "cell": pick["cell"], "dir": pick["dir"], "room": r["id"], "len": 1, "seed": rng.randi()})
				_take(walls, pick, 1)
		if not s.breathable(r["id"]) or float(r.get("air", 1.0)) < 0.5:
			for corner in [rect.position, Vector2i(rect.end.x - 1, rect.position.y), Vector2i(rect.position.x, rect.end.y - 1), rect.end - Vector2i.ONE]:
				if s.fixture_of.has(corner) or s.prop_of.has(corner):
					continue
				s.dressing.append({"kind": "frost", "cell": corner, "dir": Vector2i.DOWN, "room": r["id"], "len": 1, "seed": rng.randi()})


static func _def(id: String) -> Dictionary:
	return preload("res://scripts/board/station_fixtures.gd").defs().get(id, {})


## The wall cells of room `r` a wall item may take: [{cell (the wall), dir (into the room), at (the floor cell in front), along (the direction a run goes)}], not by a door,
## a window or the hatch.
static func _wall_cells(s, r: Dictionary, mouth: Dictionary) -> Array:
	var out := []
	var rect: Rect2i = r["rect"]
	for c in _ring(rect):
		for d in SIDES:
			var wall: Vector2i = c - d  # the wall behind the floor cell when d points into the room
			if rect.has_point(wall) or int(s.room_of.get(wall, -1)) >= 0:
				continue
			if s.grid.get_tile(wall) != "wall" or mouth.has(c):
				continue
			if int(s.door_of.get(wall, -1)) >= 0:
				continue
			out.append({"cell": wall, "dir": d, "at": c, "along": Vector2i(absi(d.y), absi(d.x))})
	return out


static func _ring(rect: Rect2i) -> Array:
	var out := []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if x == rect.position.x or x == rect.end.x - 1 or y == rect.position.y or y == rect.end.y - 1:
				out.append(Vector2i(x, y))
	return out


## A wall cell that starts a run: random; `centred` prefers the middle of the longest wall (a sign).
static func _pick_wall(walls: Array, rng: RandomNumberGenerator, centred: bool) -> Dictionary:
	if walls.is_empty():
		return {}
	if not centred:
		return walls[rng.randi() % walls.size()]
	var best: Dictionary = walls[0]
	var bs := -1.0
	for w in walls:
		var run := 0
		for k in range(-3, 4):
			if walls.any(func(o): return o["cell"] == w["cell"] + w["along"] * k and o["dir"] == w["dir"]):
				run += 1
		var score := float(run) + rng.randf() * 0.5 + (1.0 if w["dir"] == Vector2i.DOWN else 0.0)  # (a sign reads best on a wall you face from the south)
		if score > bs:
			bs = score
			best = w
	return best


## Remove `len` wall cells from `pick` along its wall (and the same again beside it, for room between items).
static func _take(walls: Array, pick: Dictionary, len: int) -> void:
	for k in range(-1, len + 1):
		var c: Vector2i = pick["cell"] + pick["along"] * k
		for i in range(walls.size() - 1, -1, -1):
			if walls[i]["cell"] == c and walls[i]["dir"] == pick["dir"]:
				walls.remove_at(i)


## Floor cells with no fixture, prop, bed or door mouth on them.
static func _floor_cells(s, r: Dictionary, mouth: Dictionary) -> Array:
	var out := []
	var rect: Rect2i = r["rect"]
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, y)
			if not mouth.has(c) and not s.prop_of.has(c) and not s.fixture_of.has(c):
				out.append(c)
	return out
