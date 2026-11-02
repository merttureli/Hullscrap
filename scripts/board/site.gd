extends RefCounted
## A boarding site (docs/BOARDING.md): the vessel the soldier explores on foot. Pure logic, no nodes, no drawing.
## make(seed, kind, opts) builds it from the seed alone, so the same seed always gives the same site:
## - the hull is shaped by hullgen.gd with the hull ops of an enemy faction (enemy_tables.json), the way shipgen.gd shapes a
##   ship, and the inside is cut like one: bands of rooms and corridors one wall thick, joined by 2-wide doors;
## - every room has a purpose (data/boarding.json), one room is the airlock, on the hull edge, with the hatch the soldier leaves by;
## - a few doors are locked (hold E to hack, or a keycard that lies in a container the airlock reaches without it);
## - the props (crates, lockers, cabinets, pallets, terminals, bodies, cables) are a site-only layer: `props`, each on the cells it covers.
## Two grids, which share the tile rules (data/tiles.json): `grid` is what is drawn (floor, wall, door) and `walk` is what blocks the
## soldier (the same, with the cells of the props that block as walls), so the crew pathfinder and CrewMember.move_input run on it.
## Anything a visit changes (what was opened, what was unlocked) lives in boarding.gd; the site only knows its layout.
## Cell coordinates: x right, y down. A body is 2x2 (pathfinder.gd), so every opening is two cells wide and a prop stands on the
## ring of cells along a room's walls, never in front of a door, which leaves a 2-wide lane through every room.

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Shapes = preload("res://scripts/ship/shapes.gd")
const Hullgen = preload("res://scripts/space/hullgen.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Themes = preload("res://scripts/board/themes.gd")

const PATH := "res://data/boarding.json"
const TILES_PATH := "res://data/tiles.json"
const MARGIN := 2  ## free cells round the hull in the grid
const SHELL := 1  ## the hull plating is one wall thick
const CORRIDOR_H := 3
const MIN_ROOMS := 3  ## rooms besides the airlock and the corridors a site needs
const ATTEMPTS := 9  ## tries: three of the full hull grammar, three of less, two plain bevels, and a rectangle last (cannot fail)
const LEVELS: Array[int] = [2, 2, 2, 1, 1, 1, 0, 0, -1]
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const KEY_NAMES: Array[String] = ["red", "blue", "green", "amber"]

static var _cfg := {}

var kind := ""
var seed_value := 0
var site_name := ""
var theme := ""  ## the theme it is dressed in (themes.gd, data/boarding.json `themes`), "" for the plain site
var faction := ""
var ok := false  ## the site was built (a rectangle always can be, so it is false only for a kind that does not exist)
var attempt := 0  ## the try that worked (0 = the first)
var grid: ShipGrid  ## drawn: floor, wall, door
var walk: ShipGrid  ## walked: grid plus the cells of the blocking props as walls
var rooms: Array = []  ## [{id, rect (Rect2i, the floor), purpose, corridor, band, locked (only reached through a locked door), doors: [door ids]}]
var doors: Array = []  ## [{id, cells: [Vector2i, Vector2i], rooms: [a, b], lock ("", "hack" or "card"), card (the key id of a card door)}]
var props: Array = []  ## [{id, prop, cell, size (Vector2i), room, blocks, loot, rolls, table, slot ("", "blueprint", "log" or "key"), key, fixed: {item: n}}]
var airlock := {}  ## {room, hatch: [Vector2i, Vector2i] (wall cells, drawn as the hatch), spawn (Vector2: the centre of the soldier's body on arrival), normal (Vector2, out of the hull)}
var lights: Array = []  ## [{pos (Vector2, cells), color ("red" or "green"), room}]
var parts: Array = []  ## the part ids a wreck's containers hold besides their tables
var marks: Array = []  ## discoveries: [{id, kind ("terminal", "body" or "room"), room, prop (id, -1 for a room), pos (Vector2, cells)}], placed after the rest from a stream of their own
var room_of := {}  ## cell -> room id
var door_of := {}  ## cell -> door id
var prop_of := {}  ## cell -> prop id (every cell a prop covers)
var bounds := Rect2i()  ## the cells of the hull (the grid minus its margin)
var _skin := {}  # cell -> true: flat hull cells on the outside (where a hatch can go)
var _rng := RandomNumberGenerator.new()


## data/boarding.json, read once.
static func config() -> Dictionary:
	if _cfg.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		assert(data is Dictionary and data.get("kinds") is Dictionary, "bad boarding data: " + PATH)
		_cfg = data
	return _cfg


static func kinds() -> Array:
	return config()["kinds"].keys()


## The site of `kind` ("derelict", "station", "nest" or "wreck") for `seed_value`. `opts`: {faction (whose hull ops shape it, else the
## kind's own, else clans), name (the POI's own), parts (part ids a wreck holds), theme (a theme id: its props, loot, names)}.
static func make(p_seed: int, p_kind: String, opts := {}):
	var s = new()
	s.kind = p_kind
	s.seed_value = p_seed
	if not config()["kinds"].has(p_kind):
		return s
	var cfg: Dictionary = config()["kinds"][p_kind]
	s.faction = str(cfg.get("hull", ""))
	if s.faction == "":
		s.faction = str(opts.get("faction", ""))
	if not Shipgen.tables()["factions"].has(s.faction):
		s.faction = "clans"
	s.parts = opts.get("parts", []).duplicate()
	s.theme = str(opts.get("theme", ""))
	if not Themes.ids().has(s.theme):
		s.theme = ""
	for i in ATTEMPTS:
		s._clear()
		if s._try(i) == "":
			s.ok = true
			s.attempt = i
			break
	var names: Array = cfg["names"]
	var themed := Themes.site_name(s.theme, p_kind, s._rng) if str(opts.get("name", "")) == "" else ""
	s.site_name = str(opts.get("name", "")) if str(opts.get("name", "")) != "" else (themed if themed != "" else str(names[s._rng.randi() % names.size()]))
	if s.ok:
		s._place_marks()
	return s


static func _mix(p_seed: int, p_kind: String, p_attempt: int) -> int:
	var h := 2166136261
	for b in p_kind.to_utf8_buffer():
		h = ((h ^ int(b)) * 16777619) & 0xFFFFFFFF
	return (p_seed * 1000003) ^ h ^ (p_attempt * 7919)


func _clear() -> void:
	grid = null
	walk = null
	rooms = []
	doors = []
	props = []
	marks = []
	airlock = {}
	lights = []
	room_of = {}
	door_of = {}
	prop_of = {}
	_skin = {}


# --- queries -----------------------------------------------------------------------------------------------------

## Cells a prop covers.
func cells_of(p: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in p["size"].y:
		for x in p["size"].x:
			out.append(p["cell"] + Vector2i(x, y))
	return out


## The middle of a prop, in cells.
func centre_of(p: Dictionary) -> Vector2:
	return Vector2(p["cell"]) + Vector2(p["size"]) / 2.0


## The middle of a door piece, in cells.
func door_centre(d: Dictionary) -> Vector2:
	return (Vector2(d["cells"][0]) + Vector2(d["cells"][1])) / 2.0 + Vector2(0.5, 0.5)


## The ids of the props that hold something (containers), in id order.
func containers() -> Array:
	var out := []
	for p in props:
		if p["loot"]:
			out.append(p["id"])
	return out


## The room whose floor holds point `p` (cells), -1 for none.
func room_at(p: Vector2) -> int:
	return int(room_of.get(Vector2i(floori(p.x), floori(p.y)), -1))


## The nearest container (not in `skip`) whose middle is within `radius` cells of `p`, -1 for none.
func nearest_container(p: Vector2, radius: float, skip := {}) -> int:
	var best := -1
	var best_d := radius
	for q in props:
		if q["loot"] and not skip.has(q["id"]):
			var d := centre_of(q).distance_to(p)
			if d <= best_d:
				best = q["id"]
				best_d = d
	return best


## The nearest locked door (not in `skip`) whose middle is within `radius` cells of `p`, -1 for none.
func nearest_locked_door(p: Vector2, radius: float, skip := {}) -> int:
	var best := -1
	var best_d := radius
	for d in doors:
		if d["lock"] != "" and not skip.has(d["id"]):
			var dd := door_centre(d).distance_to(p)
			if dd <= best_d:
				best = d["id"]
				best_d = dd
	return best


## The middle of the hatch the soldier leaves by, in cells.
func hatch_centre() -> Vector2:
	var h: Array = airlock["hatch"]
	return (Vector2(h[0]) + Vector2(h[1])) / 2.0 + Vector2(0.5, 0.5)


## Unlock door `id` on both grids.
func unlock_door(id: int) -> void:
	for c in doors[id]["cells"]:
		grid.door_locked.erase(c)
		walk.door_locked.erase(c)


## Free body anchors (2x2, top-left cell) inside room `id`, left to right, top to bottom: the places something can stand (enemies spawn on them, stage B2).
func free_anchors(id: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r: Rect2i = rooms[id]["rect"]
	for y in range(r.position.y, r.end.y - 1):
		for x in range(r.position.x, r.end.x - 1):
			if Pathfinder.body_ok(walk, Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


## Does a shot or a look stop in cell `c`: outside the hull, a wall, or a door that is shut?
func opaque(c: Vector2i) -> bool:
	var id := grid.get_tile(c)
	if id == "" or grid.tile_flag(id, "solid"):
		return true
	return grid.tile_flag(id, "door") and not grid.is_door_open(c)


## Is the line from `a` to `b` (cells) clear of walls and shut doors?
func clear_line(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var n := maxi(1, ceili(d.length() / 0.25))
	for i in range(1, n + 1):
		var p := a + d * (float(i) / float(n))
		if opaque(Vector2i(floori(p.x), floori(p.y))):
			return false
	return true


## How many different blocking props the line from `a` to `b` (cells) crosses: the cover between two bodies.
func cover_between(a: Vector2, b: Vector2) -> int:
	var d := b - a
	var n := maxi(1, ceili(d.length() / 0.25))
	var seen := {}
	for i in range(1, n):
		var p := a + d * (float(i) / float(n))
		var pid: int = int(prop_of.get(Vector2i(floori(p.x), floori(p.y)), -1))
		if pid >= 0 and props[pid]["blocks"]:
			seen[pid] = true
	return seen.size()


## The body anchors reachable from `from` on the walk grid; `open` is a Callable(door cell) -> bool for the locked doors.
func reach(from: Vector2i, open: Callable) -> Dictionary:
	var seen := {}
	if not Pathfinder.body_ok(walk, from, open):
		return seen
	seen[from] = true
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var a: Vector2i = queue[head]
		head += 1
		for d in SIDES:
			var n: Vector2i = a + d
			if not seen.has(n) and Pathfinder.body_ok(walk, n, open):
				seen[n] = true
				queue.append(n)
	return seen


## The rooms (ids) the soldier can get to from the airlock: doors with a lock in `shut` (a list of lock kinds, "hack" and "card") are closed.
func reachable_rooms(shut: Array) -> Dictionary:
	var out := {}
	var open := func(c: Vector2i) -> bool:
		var d: int = door_of.get(c, -1)
		return d < 0 or not shut.has(doors[d]["lock"])
	var seen := reach(spawn_anchor(), open)
	for a in seen:
		var r: int = int(room_of.get(a, -1))
		if r >= 0 and room_of.get(a + Vector2i.ONE, -2) == r:
			out[r] = true
	return out


## The body anchor the soldier arrives on.
func spawn_anchor() -> Vector2i:
	return Vector2i(roundi(airlock["spawn"].x), roundi(airlock["spawn"].y)) - Vector2i.ONE


## Every problem in the site, one message each (empty when it is sound): used by the tests.
func problems() -> Array:
	var out := []
	if not ok:
		return ["not built"]
	var all := reachable_rooms([])
	for r in rooms:
		if r["purpose"] != "gone" and not all.has(r["id"]):
			out.append("room %d (%s) cannot be reached" % [r["id"], r["purpose"]])
	var no_card := reachable_rooms(["card"])
	for d in doors:
		if d["lock"] == "card":
			var held := false
			for p in props:
				if p["slot"] == "key" and p["key"] == d["card"] and no_card.has(p["room"]):
					held = true
			if not held:
				out.append("the %s keycard cannot be reached without itself" % d["card"])
	for p in props:
		for c in cells_of(p):
			if prop_of.get(c, -1) != p["id"] or not room_of.has(c):
				out.append("prop %d stands outside its room or on another prop" % p["id"])
				break
	if airlock.is_empty() or rooms[airlock["room"]]["purpose"] != "airlock":
		out.append("no airlock")
	return out


# --- generation ----------------------------------------------------------------------------------------------

func _try(p_attempt: int) -> String:
	var cfg: Dictionary = config()["kinds"][kind]
	_rng.seed = _mix(seed_value, kind, p_attempt)
	var rng := _rng
	var rw_min: int = int(cfg["room_w"][0])
	var rw_max: int = int(cfg["room_w"][1])
	var pattern: String = cfg["bands"][rng.randi() % cfg["bands"].size()]
	var n_room := pattern.count("R")
	var bands: Array = []
	var seen_room := 0
	for ch in pattern:
		if ch == "R":
			var kind_of := "aux"
			if n_room > 1 and seen_room == 0:
				kind_of = "gun"
			elif n_room > 1 and seen_room == n_room - 1:
				kind_of = "engine"
			bands.append({"kind": kind_of, "corridor": false, "h": rng.randi_range(int(cfg["room_h"][0]), int(cfg["room_h"][1])), "need": 2 * rw_min + 1, "rooms": []})
			seen_room += 1
		else:
			bands.append({"kind": "core", "corridor": true, "h": CORRIDOR_H, "need": 2 * rw_min + 1, "rooms": []})
	var y := SHELL
	for b in bands:
		b["y0"] = y
		b["y1"] = y + int(b["h"]) - 1
		y = int(b["y1"]) + 2
	var rows := y - 1 + SHELL
	var style := {"hull": Shipgen.tables()["factions"][faction]["hull"].duplicate(true)}
	style["hull"]["band"] = {"gun": 0.62, "bridge": 0.8, "core": 1.0, "aux": 0.92, "engine": 0.78}
	Hullgen.extents(style, bands, rng.randi_range(int(cfg["interior"][0]), int(cfg["interior"][1])), rng, 0, SHELL)
	var raw := {}
	if LEVELS[p_attempt] >= 0:
		var hull := Hullgen.make(style, bands, SHELL, rows, rng, {"level": LEVELS[p_attempt]})
		var ras := Hullgen.raster(hull["outline"])
		if not ras["errors"].is_empty():
			return "outline: " + str(ras["errors"][0])
		raw = ras["cells"]
	else:
		raw = _rectangle(bands)
	var why := _build_grid(raw, bands)
	if why != "":
		return why
	why = _cut_rooms(bands, cfg, rng)
	if why != "":
		return why
	why = _join(bands, cfg, rng)
	if why != "":
		return why
	_lock_doors(cfg, rng)
	_assign_purposes(cfg, rng)
	_place_props(cfg, rng)
	_make_walk()
	why = _clear_lanes()
	if why != "":
		return why
	_fill_slots(cfg, rng)
	_place_lights(cfg, rng)
	if containers().size() < MIN_ROOMS:
		return "too few containers"
	return ""


## The cells of a plain hull: every band's floor columns and rows grown by the shell.
func _rectangle(bands: Array) -> Dictionary:
	var out := {}
	for b in bands:
		for yy in range(int(b["y0"]) - SHELL, int(b["y1"]) + SHELL + 1):
			for xx in range(int(b["x0"]) - SHELL, int(b["x1"]) + SHELL + 2):
				out[Vector2i(xx, yy)] = {}
	return out


## The grid from the rasterized outline: a one-thick wall all round, everything inside solid until the rooms are cut out.
func _build_grid(raw: Dictionary, bands: Array) -> String:
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in raw:
		lo = lo.min(c)
		hi = hi.max(c)
	var off := Vector2i(MARGIN, MARGIN) - lo
	var cells := {}
	for c in raw:
		var sd: Dictionary = raw[c]
		cells[c + off] = {} if not sd.is_empty() and Shapes.area_of(sd) > 0.9999 else sd  # (float noise can leave a cell a hair under a square)
	for b in bands:
		b["x0"] = int(b["x0"]) + off.x
		b["x1"] = int(b["x1"]) + off.x
		b["y0"] = int(b["y0"]) + off.y
		b["y1"] = int(b["y1"]) + off.y
	var size := hi - lo + Vector2i.ONE + Vector2i(MARGIN, MARGIN) * 2
	bounds = Rect2i(Vector2i(MARGIN, MARGIN), hi - lo + Vector2i.ONE)
	var defs := TileDefs.new()
	defs.load_file(TILES_PATH)
	grid = ShipGrid.new(size, defs)
	for yy in size.y:
		for xx in size.x:
			grid.hull[Vector2i(xx, yy)] = true
	var depth := _depths(cells)
	var inner := {}
	for c in cells:
		grid.force_tile(c, "wall", cells[c])
		if depth[c] == 0:
			if cells[c].is_empty():
				_skin[c] = true
		else:
			inner[c] = true
	for b in bands:
		var rect := _rect_of(inner, b)
		if rect.size.x < (6 if b["corridor"] else int(config()["kinds"][kind]["room_w"][0])):
			return "a band has no floor"
		b["rect"] = rect
	return ""


## Cut every band into its room(s) and carve the floor.
func _cut_rooms(bands: Array, cfg: Dictionary, rng: RandomNumberGenerator) -> String:
	for bi in bands.size():
		var b: Dictionary = bands[bi]
		var rect: Rect2i = b["rect"]
		if b["corridor"]:
			_add_room(rect, bi, true)
			continue
		var x := rect.position.x
		for w in _split(rect.size.x, int(cfg["room_w"][0]), int(cfg["room_w"][1]), rng):
			_add_room(Rect2i(x, rect.position.y, w, rect.size.y), bi, false)
			x += w + 1
	return ""


func _add_room(rect: Rect2i, band: int, corridor: bool) -> void:
	var id := rooms.size()
	rooms.append({"id": id, "rect": rect, "purpose": "corridor" if corridor else "", "corridor": corridor, "band": band, "locked": false, "doors": []})
	for yy in range(rect.position.y, rect.end.y):
		for xx in range(rect.position.x, rect.end.x):
			grid.force_tile(Vector2i(xx, yy), "floor")
			room_of[Vector2i(xx, yy)] = id


## The widths of the rooms that fill `total` cells with a wall cell between them, each `mn` to `mx` wide (the last may be a little wider).
static func _split(total: int, mn: int, mx: int, rng: RandomNumberGenerator) -> Array:
	var out := []
	var left := total
	while true:
		if left <= mx:
			out.append(left)
			break
		var w := rng.randi_range(mn, mx)
		if left - w - 1 < mn:
			var fit := left - 1 - mn
			w = fit if fit >= mn else left
		out.append(w)
		left -= w + 1
		if left <= 0:
			break
	return out


## Doors: every room to a corridor beside its band, passage rooms between two corridors, extra doors between neighbours; then the airlock and the rooms nothing reaches go.
func _join(bands: Array, cfg: Dictionary, rng: RandomNumberGenerator) -> String:
	var by_band := {}  # band -> [room ids] left to right
	for r in rooms:
		if not by_band.has(r["band"]):
			by_band[r["band"]] = []
		by_band[r["band"]].append(r["id"])
	for bi in bands.size():
		if bands[bi]["corridor"]:
			continue
		var side_corr: Array = []  # the corridor rooms above and below this band
		for nb in [bi - 1, bi + 1]:
			if by_band.has(nb) and bands[nb]["corridor"]:
				side_corr.append(by_band[nb][0])
		var passage := -1
		if side_corr.size() == 2:
			passage = by_band[bi][rng.randi() % by_band[bi].size()]
		for rid in by_band[bi]:
			var want: Array = side_corr.duplicate()
			if rid != passage and want.size() == 2:
				_shuffle(want, rng)
				if rng.randf() > 0.3:
					want = [want[0]]
			for cid in want:
				if rooms[cid]["rect"].position.y < rooms[rid]["rect"].position.y:
					_door_between(cid, rid)
				else:
					_door_between(rid, cid)
		var ids: Array = by_band[bi]
		for i in range(ids.size() - 1):
			if rng.randf() < float(cfg["loop"]) or rooms[ids[i]]["doors"].is_empty() or rooms[ids[i + 1]]["doors"].is_empty():
				_door_beside(ids[i], ids[i + 1], rng)
	# the airlock: an end room of a band, on a flat stretch of the hull
	var cands := []
	for bi in bands.size():
		if bands[bi]["corridor"]:
			continue
		var ids: Array = by_band[bi]
		for end in [[ids[0], -1], [ids[ids.size() - 1], 1]]:
			var hatch := _hatch(end[0], end[1])
			if not hatch.is_empty() and not rooms[end[0]]["doors"].is_empty():
				cands.append({"room": end[0], "hatch": hatch, "side": end[1]})
	if cands.is_empty():
		return "no place for an airlock"
	var pick: Dictionary = cands[rng.randi() % cands.size()]
	_set_airlock(pick)
	var joined := _room_graph_reach(pick["room"])
	var keep := 0
	for r in rooms:
		if not joined.has(r["id"]):
			_drop_room(r["id"])
		elif not r["corridor"] and r["id"] != pick["room"]:
			keep += 1
	if keep < MIN_ROOMS:
		return "too few rooms"
	return ""


## A door piece (two cells wide) in the wall row between room `upper` and room `lower`. False when they share no two columns.
func _door_between(upper: int, lower: int) -> bool:
	var a: Rect2i = rooms[upper]["rect"]
	var b: Rect2i = rooms[lower]["rect"]
	var lo := maxi(a.position.x, b.position.x)
	var hi := mini(a.end.x, b.end.x)
	if hi - lo < 2 or a.end.y + 1 != b.position.y:
		return false
	var span := hi - lo - 1  # starts lo .. hi - 2
	var start := _rng.randi() % span
	for k in span:
		var x := lo + (start + k) % span
		if grid.place_door("door", Vector2i(x, a.end.y), Vector2i.RIGHT):
			_add_door([Vector2i(x, a.end.y), Vector2i(x + 1, a.end.y)], upper, lower)
			return true
	return false


## A door piece in the wall column between two neighbours of a band.
func _door_beside(left: int, right: int, rng: RandomNumberGenerator) -> bool:
	var a: Rect2i = rooms[left]["rect"]
	var b: Rect2i = rooms[right]["rect"]
	var lo := maxi(a.position.y, b.position.y)
	var hi := mini(a.end.y, b.end.y)
	if hi - lo < 2 or a.end.x + 1 != b.position.x:
		return false
	var span := hi - lo - 1
	var start := rng.randi() % span
	for k in span:
		var y := lo + (start + k) % span
		if grid.place_door("door", Vector2i(a.end.x, y), Vector2i.DOWN):
			_add_door([Vector2i(a.end.x, y), Vector2i(a.end.x, y + 1)], left, right)
			return true
	return false


func _add_door(cells: Array[Vector2i], a: int, b: int) -> void:
	var id := doors.size()
	doors.append({"id": id, "cells": cells, "rooms": [a, b], "lock": "", "card": ""})
	rooms[a]["doors"].append(id)
	rooms[b]["doors"].append(id)
	for c in cells:
		door_of[c] = id


## The two wall cells of a hatch on the `side` (-1 left, 1 right) of room `rid` on the flat hull, [] when there is none.
func _hatch(rid: int, side: int) -> Array:
	var r: Rect2i = rooms[rid]["rect"]
	var x := r.position.x - 1 if side < 0 else r.end.x
	var mid := r.position.y + r.size.y / 2
	for dy in [0, -1, 1, -2, 2]:
		var yy: int = mid + dy
		if yy >= r.position.y and yy + 1 < r.end.y and _skin.has(Vector2i(x, yy)) and _skin.has(Vector2i(x, yy + 1)):
			return [Vector2i(x, yy), Vector2i(x, yy + 1)]
	return []


func _set_airlock(pick: Dictionary) -> void:
	var r: Rect2i = rooms[pick["room"]]["rect"]
	var h: Array = pick["hatch"]
	var side: int = pick["side"]
	rooms[pick["room"]]["purpose"] = "airlock"
	var ax := r.position.x if side < 0 else r.end.x - 2
	airlock = {"room": pick["room"], "hatch": h, "spawn": Vector2(ax + 1, h[0].y + 1), "normal": Vector2(side, 0)}


## The rooms joined to room `start` through doors (ids as keys).
func _room_graph_reach(start: int, shut_ids := {}) -> Dictionary:
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var r: int = queue.pop_back()
		for did in rooms[r]["doors"]:
			if shut_ids.has(did):
				continue
			for other in doors[did]["rooms"]:
				if not seen.has(other):
					seen[other] = true
					queue.append(other)
	return seen


## A room nothing reaches goes back to solid wall, with the doors that led into it.
func _drop_room(id: int) -> void:
	var r: Rect2i = rooms[id]["rect"]
	for did in rooms[id]["doors"]:
		for c in doors[did]["cells"]:
			grid.force_tile(c, "wall")
			door_of.erase(c)
		doors[did]["lock"] = "gone"
	for yy in range(r.position.y, r.end.y):
		for xx in range(r.position.x, r.end.x):
			grid.force_tile(Vector2i(xx, yy), "wall")
			room_of.erase(Vector2i(xx, yy))
	rooms[id]["rect"] = Rect2i(r.position, Vector2i.ZERO)
	rooms[id]["purpose"] = "gone"
	rooms[id]["doors"] = []


## Lock some doors: `hack` ones anywhere but the airlock's, `card` ones on the only door of a dead-end room, with the key in a room the airlock reaches without it.
func _lock_doors(cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	var air: int = airlock["room"]
	var live: Array = doors.filter(func(d): return d["lock"] != "gone" and not d["rooms"].has(air))
	var n_card := rng.randi_range(int(cfg["card"][0]), int(cfg["card"][1]))
	var dead: Array = live.filter(func(d): return d["rooms"].any(func(r): return rooms[r]["doors"].size() == 1 and not rooms[r]["corridor"]))
	_shuffle(dead, rng)
	var made := 0
	for d in dead:
		if made >= n_card or made >= KEY_NAMES.size():
			break
		d["lock"] = "card"
		d["card"] = KEY_NAMES[made]
		made += 1
	var n_hack := rng.randi_range(int(cfg["hack"][0]), int(cfg["hack"][1]))
	var rest: Array = live.filter(func(d): return d["lock"] == "")
	_shuffle(rest, rng)
	for i in mini(n_hack, rest.size()):
		rest[i]["lock"] = "hack"
	var open_rooms := _room_graph_reach(air, _lock_ids())  # the rooms only a lock opens
	for r in rooms:
		r["locked"] = r["purpose"] != "gone" and not open_rooms.has(r["id"])


func _lock_ids() -> Dictionary:
	var out := {}
	for d in doors:
		if d["lock"] == "hack" or d["lock"] == "card":
			out[d["id"]] = true
	return out


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = list[i]
		list[i] = list[j]
		list[j] = t


## A purpose for every room but the airlock and the corridors: the kind's minimums first, then by weight within its maximums.
func _assign_purposes(cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	var open: Array = rooms.filter(func(r): return r["purpose"] == "")
	_shuffle(open, rng)
	var count := {}
	var weights: Dictionary = cfg["weights"]
	var mins: Dictionary = cfg["min"]
	var maxes: Dictionary = cfg["max"]
	var names: Array = weights.keys()
	names.sort()
	for p in mins:
		for i in int(mins[p]):
			if not open.is_empty():
				var r: Dictionary = open.pop_back()
				r["purpose"] = p
				count[p] = int(count.get(p, 0)) + 1
	for r in open:
		var total := 0.0
		for p in names:
			if int(count.get(p, 0)) < int(maxes.get(p, 99)):
				total += float(weights[p])
		var roll := rng.randf() * total
		var chosen: String = names[0]
		for p in names:
			if int(count.get(p, 0)) < int(maxes.get(p, 99)):
				chosen = p
				roll -= float(weights[p])
				if roll < 0.0:
					break
		r["purpose"] = chosen
		count[chosen] = int(count.get(chosen, 0)) + 1


## The props of every room: along its walls (a 2-wide lane stays free), never in front of a door.
func _place_props(cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	var pdefs: Dictionary = config()["props"]
	var rdefs: Dictionary = config()["rooms"]
	for r in rooms:
		if r["purpose"] == "gone" or not rdefs.has(r["purpose"]):
			continue
		var mult := float(cfg["prop_mult"]) * (float(cfg["locked_bonus"]) if r["locked"] else 1.0)
		var mouth := _mouth(r)
		var entries: Array = rdefs[r["purpose"]]["props"] + Themes.def(theme).get("rooms", {}).get(r["purpose"], [])
		for entry in entries:
			var n := rng.randi_range(int(entry["n"][0]), int(entry["n"][1]))
			n = int(floor(float(n) * mult + rng.randf()))
			for i in n:
				_put(r, str(entry["prop"]), pdefs[entry["prop"]], mouth, rng)


## The cells of room `r` the doors and the arrival keep clear.
func _mouth(r: Dictionary) -> Dictionary:
	var out := {}
	var rect: Rect2i = r["rect"]
	for did in r["doors"]:
		for dc in doors[did]["cells"]:
			for d in SIDES:
				var f: Vector2i = dc + d
				if rect.has_point(f):
					for oy in range(-1, 2):
						for ox in range(-1, 2):
							out[f + Vector2i(ox, oy)] = true
	if r["id"] == airlock["room"]:
		var a := spawn_anchor()
		for oy in range(-2, 4):
			for ox in range(-2, 4):
				out[a + Vector2i(ox, oy)] = true
	return out


func _on_ring(rect: Rect2i, c: Vector2i) -> bool:
	return rect.has_point(c) and (c.x == rect.position.x or c.x == rect.end.x - 1 or c.y == rect.position.y or c.y == rect.end.y - 1)


func _put(r: Dictionary, prop: String, def: Dictionary, mouth: Dictionary, rng: RandomNumberGenerator) -> void:
	var rect: Rect2i = r["rect"]
	var blocks: bool = def["blocks"]
	var cand: Array[Vector2i] = []
	for yy in range(rect.position.y, rect.end.y):
		for xx in range(rect.position.x, rect.end.x):
			var c := Vector2i(xx, yy)
			if not mouth.has(c) and not prop_of.has(c) and (not blocks or _on_ring(rect, c)):
				cand.append(c)
	while not cand.is_empty():
		var i := rng.randi() % cand.size()
		var c: Vector2i = cand[i]
		cand.remove_at(i)
		var size := Vector2i(int(def["size"][0]), int(def["size"][1]))
		if blocks and c.y != rect.position.y and c.y != rect.end.y - 1:
			size = Vector2i(size.y, size.x)  # along a side wall a pallet turns
		var ok_cells := true
		for yy in size.y:
			for xx in size.x:
				var cc := c + Vector2i(xx, yy)
				if mouth.has(cc) or prop_of.has(cc) or (blocks and not _on_ring(rect, cc)) or not rect.has_point(cc):
					ok_cells = false
		if not ok_cells:
			continue
		var id := props.size()
		props.append({"id": id, "prop": prop, "cell": c, "size": size, "room": r["id"], "blocks": blocks, "loot": bool(def["loot"]),
			"rolls": def["rolls"].duplicate(), "table": str(def.get("table", "")), "slot": "", "key": "", "fixed": {}})
		for yy in size.y:
			for xx in size.x:
				prop_of[c + Vector2i(xx, yy)] = id
		return


func _make_walk() -> void:
	walk = ShipGrid.new(grid.size, grid.defs)
	walk.hull = grid.hull
	walk.tiles = grid.tiles.duplicate()
	for p in props:
		if p["blocks"]:
			for c in cells_of(p):
				walk.tiles[c] = "wall"


## Every room must be walkable from the airlock by a 2x2 body with all doors open; a room it cannot reach loses its blocking props.
func _clear_lanes() -> String:
	var open := func(_c: Vector2i) -> bool: return true
	for pass_no in 2:
		var seen := reach(spawn_anchor(), open)
		var reached := {}
		for a in seen:
			var r: int = int(room_of.get(a, -1))
			if r >= 0 and room_of.get(a + Vector2i.ONE, -2) == r:
				reached[r] = true
		var bad := rooms.filter(func(r): return r["purpose"] != "gone" and not reached.has(r["id"]))
		if bad.is_empty():
			break
		if pass_no == 1:
			return "a room cannot be walked to"
		for p in props:
			if p["blocks"] and bad.any(func(r): return r["id"] == p["room"]):
				for c in cells_of(p):
					walk.tiles[c] = grid.tiles[c]
				p["blocks"] = false
	for d in doors:
		if d["lock"] == "hack" or d["lock"] == "card":
			for c in d["cells"]:
				grid.door_locked[c] = true
				walk.door_locked[c] = true
	return ""


## Blueprints, logs, keycards and a wreck's parts go into containers (their contents are rolled when opened, loot.gd).
func _fill_slots(cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	var pdefs: Dictionary = config()["props"]
	var rdefs: Dictionary = config()["rooms"]
	var bp_n := _weighted_count(cfg["blueprints"], rng)
	for i in bp_n:
		var w := {}
		for p in props:
			if p["loot"] and p["slot"] == "":
				w[p["id"]] = float(pdefs[p["prop"]]["bp"]) * float(rdefs[rooms[p["room"]]["purpose"]]["bp"])
		var id := _pick_weighted(w, rng)
		if id >= 0:
			props[id]["slot"] = "blueprint"
	var more := int(Themes.def(theme).get("loot", {}).get("logs", 0))
	var log_n := rng.randi_range(int(cfg["logs"][0]) + more, int(cfg["logs"][1]) + more)
	for i in log_n:
		var w := {}
		for p in props:
			if p["loot"] and p["slot"] == "":
				w[p["id"]] = float(pdefs[p["prop"]]["log"])
		var id := _pick_weighted(w, rng)
		if id >= 0:
			props[id]["slot"] = "log"
	var no_card := reachable_rooms(["card"])
	for d in doors:
		if d["lock"] != "card":
			continue
		var w := {}
		for p in props:
			if p["loot"] and p["slot"] == "" and no_card.has(p["room"]) and not rooms[p["room"]]["locked"]:
				w[p["id"]] = 1.0
		var id := _pick_weighted(w, rng)
		if id >= 0:
			props[id]["slot"] = "key"
			props[id]["key"] = d["card"]
		else:
			d["lock"] = "hack"  # no safe place for the card: the door is hacked instead
			d["card"] = ""
	for part in parts:
		var w := {}
		for p in props:
			if p["loot"]:
				w[p["id"]] = (3.0 if p["prop"] == "pallet" else 1.0) * (2.0 if rooms[p["room"]]["purpose"] in ["cargo", "engineering"] else 1.0)
		var id := _pick_weighted(w, rng)
		if id >= 0:
			props[id]["fixed"][str(part)] = int(props[id]["fixed"].get(str(part), 0)) + 1


## An index of `cfg` ({"0": p, "1": p, ...}) by weight.
static func _weighted_count(cfg: Dictionary, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	var keys: Array = cfg.keys()
	keys.sort()
	for k in keys:
		total += float(cfg[k])
	var roll := rng.randf() * total
	for k in keys:
		roll -= float(cfg[k])
		if roll < 0.0:
			return int(k)
	return int(keys[-1])


## A key of `w` (id -> weight) by weight, -1 when every weight is 0.
static func _pick_weighted(w: Dictionary, rng: RandomNumberGenerator) -> int:
	var ids: Array = w.keys()
	ids.sort()
	var total := 0.0
	for id in ids:
		total += float(w[id])
	if total <= 0.0:
		return -1
	var roll := rng.randf() * total
	for id in ids:
		roll -= float(w[id])
		if roll < 0.0 and float(w[id]) > 0.0:
			return id
	return ids[-1]


## Dim red emergency lights in some rooms; the airlock has a green one.
func _place_lights(cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	for r in rooms:
		if r["purpose"] == "gone":
			continue
		var rect: Rect2i = r["rect"]
		var mid := Vector2(rect.position) + Vector2(rect.size) / 2.0
		if r["id"] == airlock["room"]:
			lights.append({"pos": mid, "color": "green", "room": r["id"]})
		elif rng.randf() < float(cfg["emergency"]) * float(Themes.def(theme).get("emergency", 1.0)):
			lights.append({"pos": mid, "color": "red", "room": r["id"]})


## Discoveries (data/boarding.json `marks`): a few rooms that are not the airlock or a corridor hold a marked terminal, a marked body, or are a strange room
## themselves. A stream of its own, so the layout and the loot of a site are what they were before there were marks.
func _place_marks() -> void:
	marks = []
	var mc: Dictionary = config()["marks"]
	var span: Array = mc["count"].get(kind, [0, 0])
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix(seed_value, "marks", 0)
	var n := rng.randi_range(int(span[0]), int(span[1]))
	var open: Array = rooms.filter(func(r): return r["purpose"] != "gone" and r["purpose"] != "airlock" and not r["corridor"])
	_shuffle(open, rng)
	var kinds_w: Dictionary = mc["weights"]
	for r in open:
		if marks.size() >= n:
			break
		var rect: Rect2i = r["rect"]
		var mid := Vector2(rect.position) + Vector2(rect.size) / 2.0
		var opts := {"room": 1.0}
		var prop := -1
		for p in props:
			if p["room"] == r["id"] and p["prop"] == "terminal":
				opts["terminal"] = 1.0
				prop = p["id"]
				break
		var body := -1
		for p in props:
			if p["room"] == r["id"] and p["prop"] == "body":
				opts["body"] = 1.0
				body = p["id"]
				break
		var w := {}
		for k in opts:
			w[k] = float(kinds_w.get(k, 1.0))
		var names: Array = w.keys()
		names.sort()
		var total := 0.0
		for k in names:
			total += float(w[k])
		var roll := rng.randf() * total
		var chosen: String = names[0]
		for k in names:
			chosen = k
			roll -= float(w[k])
			if roll < 0.0:
				break
		var at := mid
		var pid := -1
		if chosen == "terminal":
			pid = prop
			at = centre_of(props[prop])
		elif chosen == "body":
			pid = body
			at = centre_of(props[body])
		marks.append({"id": marks.size(), "kind": chosen, "room": r["id"], "prop": pid, "pos": at})


# --- hull helpers (as in shipgen.gd) ---------------------------------------------------------------------------------

## BFS depth from the skin (shaped cells and cells next to space) into the hull.
static func _depths(cells: Dictionary) -> Dictionary:
	var depth := {}
	var queue: Array = []
	for c in cells:
		var skin: bool = not cells[c].is_empty()
		if not skin:
			for d in SIDES:
				if not cells.has(c + d):
					skin = true
					break
		if skin:
			depth[c] = 0
			queue.append(c)
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in SIDES:
			var n: Vector2i = c + d
			if cells.has(n) and not depth.has(n):
				depth[n] = int(depth[c]) + 1
				queue.append(n)
	return depth


## The floor rectangle of a band: its rows, from the widest span every row has round the band's middle.
static func _rect_of(inner: Dictionary, b: Dictionary) -> Rect2i:
	var mid: int = (int(b["x0"]) + int(b["x1"])) / 2
	var lo_x := -(1 << 20)
	var hi_x := 1 << 20
	for yy in range(int(b["y0"]), int(b["y1"]) + 1):
		var x := mid
		if not inner.has(Vector2i(x, yy)):
			var found := false
			for dx in range(1, 9):
				if inner.has(Vector2i(mid + dx, yy)):
					x = mid + dx
					found = true
					break
				if inner.has(Vector2i(mid - dx, yy)):
					x = mid - dx
					found = true
					break
			if not found:
				return Rect2i()
		var a := x
		while inner.has(Vector2i(a - 1, yy)):
			a -= 1
		var z := x
		while inner.has(Vector2i(z + 1, yy)):
			z += 1
		lo_x = maxi(lo_x, a)
		hi_x = mini(hi_x, z)
	if hi_x - lo_x + 1 < 2:
		return Rect2i()
	return Rect2i(lo_x, int(b["y0"]), hi_x - lo_x + 1, int(b["y1"]) - int(b["y0"]) + 1)
