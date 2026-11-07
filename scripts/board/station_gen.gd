extends RefCounted
## Stations built from modules (data/station_modules.json, docs/BOARDING.md). Pure logic, no nodes: build() fills a site (site.gd) with the same
## fields the bands of a classic site give it (grid, walk, rooms with purposes, doors, props, containers, the airlock), so foes, loot, air,
## light, the HUD and saving work on it unchanged. Everything comes from the seed:
## - the station's type (its size budget and which modules it favours) and state (abandoned, half or operational, by region and theme), from a
##   stream of their own, so every attempt builds the same kind of place;
## - growth: the docking collar first, then modules on its open connectors, picked by weight for the type and by their rules (after, not_after,
##   leads, max, clear), until the budget is spent; then the type's minimum modules; then a spoke or a crossing that leads nowhere gets a module
##   at its end or goes; connectors of two modules that meet are joined (a loop); the rest close as wall (or window);
## - the module cells become the site: rooms, doors (a door connector is one 2-wide door, a hall is two with a pillar), windows (only where
##   space is right outside), the hatch; then the state: power, light and air per module, dead doors to hack, the checkpoint's card door,
##   who is aboard (site.crowd), sentries over the crossings (site.posts), the backdrop the windows show.
## A station that cannot be built in `attempts` tries is built the classic way (site.gd make falls back).

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Races = preload("res://scripts/board/station_races.gd")
const Fixtures = preload("res://scripts/board/station_fixtures.gd")
const Dressing = preload("res://scripts/board/station_dressing.gd")
const Homelands = preload("res://scripts/space/homelands.gd")

const PATH := "res://data/station_modules.json"
const SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const KEY_NAMES: Array[String] = ["red", "blue", "green", "amber"]
const BREACH_MAX := 2  ## modules that lost their air, at most

static var _cfg := {}
static var _variants := {}  # "mid|rot|x|y" -> _variant(): the modules are data, so each turn and stretch is parsed once
static var race_rooms := true  ## a test switches it off to compare two stations of different builders: a race's own room is a different layout
static var forced_module := ""  ## a test or a tool sets it: a module every station must have (besides its type's)

var s  ## the site being built (site.gd)
var rng := RandomNumberGenerator.new()
var type := ""
var capital := ""  ## the race whose capital this is (a single-race station with all its signature rooms), "" for none
var wanted := ""  ## a module this station must have (a wonder's site)
var state := ""
var mood := ""
var insts: Array = []  ## [{mod, v (the variant: rotated, stretched), off (Vector2i), parent, links: [per connector: -1 open, -2 closed, or the inst joined]}]
var occ := {}  ## world cell -> "f" (floor), "x" (a wall, a window, a connector, the hatch)
var keep := {}  ## world cell -> the inst that keeps it empty (space in front of the hatch and the windows that need a view)


## data/station_modules.json, read once.
static func config() -> Dictionary:
	if _cfg.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		assert(data is Dictionary and data.get("modules") is Dictionary, "bad station data: " + PATH)
		for mid in data["modules"]:  # a module that is `like` another has its footprint, and what it does not say itself
			var def: Dictionary = data["modules"][mid]
			if def.has("like"):
				var merged: Dictionary = data["modules"][str(def["like"])].duplicate(true)
				for k in def:
					merged[k] = def[k]
				data["modules"][mid] = merged
		_cfg = data
		_variants = {}
	return _cfg


## The data switch: "modules" or "classic".
static func switch() -> String:
	return str(config().get("station_gen", "classic"))


static func modules() -> Dictionary:
	return config()["modules"]


## Build site `s` (kind station) from modules. `opts` as Site.make's, plus state (a remembered state). "" when it worked, else why not.
static func build(p_site, opts := {}) -> String:
	var g = new()
	g.s = p_site
	g._roll_kind(opts)
	var why := "no attempt"
	for i in int(config().get("attempts", 8)):
		p_site._clear()
		p_site.modules = []
		why = g._attempt(i)
		if why == "":
			p_site.attempt = i
			return ""
	return why


# --- the kind of place ---------------------------------------------------------------------------------------------

## The type, the state and (operational) the mood, from a stream of their own.
func _roll_kind(opts: Dictionary) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = s._mix(s.seed_value, "station", 0)
	var tw := {}
	for t in config()["types"]:
		tw[t] = float(config()["types"][t]["weight"])
	type = _pick(tw, r)
	if str(opts.get("capital", "")) != "":  # a race's capital: the size class above the habitat (homelands.gd)
		capital = str(opts["capital"])
		type = str(Homelands.config()["capital"]["type"])
	var sw := {}
	var tilt: Dictionary = config().get("regions", {}).get(s.region, {})
	var ttilt: Dictionary = config().get("themes", {}).get(s.theme, {})
	for st in config()["states"]:
		sw[st] = float(config()["states"][st]["weight"]) * float(tilt.get(st, 1.0)) * float(ttilt.get(st, 1.0))
	state = _pick(sw, r)
	if config()["states"].has(str(opts.get("state", ""))):
		state = str(opts["state"])
	var moods: Dictionary = config()["states"][state].get("moods", {})
	mood = _pick(moods, r) if not moods.is_empty() else ""
	if moods.has(str(opts.get("mood", ""))):
		mood = str(opts["mood"])
	var rr := RandomNumberGenerator.new()
	rr.seed = s._mix(s.seed_value, "races", 0)
	s.races = [capital] if capital != "" else ([str(opts["race"])] if str(opts.get("race", "")) != "" else Races.roll(rr, s.region, type))
	if opts.has("module"):
		wanted = str(opts["module"])
	s.state = state
	s.mood = mood
	s.station_type = type
	s.arrival = str(config()["states"][state].get("text", ""))


# --- one attempt ---------------------------------------------------------------------------------------------------

func _attempt(p_attempt: int) -> String:
	rng.seed = s._mix(s.seed_value, "modules", p_attempt)
	insts = []
	occ = {}
	keep = {}
	var tcfg: Dictionary = config()["types"][type]
	var dock := _variant("dock", rng.randi() % 4)
	_stamp({"mod": "dock", "v": dock, "off": Vector2i.ZERO, "parent": -1, "links": _open_links(dock)})
	var budget := rng.randi_range(int(tcfg["modules"][0]), int(tcfg["modules"][1]))
	var guard := 0
	while _count() + _missing() < budget and guard < 400:
		guard += 1
		var open := _open()
		if open.is_empty():
			break
		var pick: Array = open[0] if rng.randf() < 0.45 else open[rng.randi() % open.size()]  # (the oldest often: a station grows round its core)
		if not _grow(pick[0], pick[1], _weights(), true):
			insts[pick[0]]["links"][pick[1]] = -2
	var mins: Dictionary = tcfg.get("min", {}).duplicate()
	if forced_module != "" and modules().has(forced_module):  # (a test or a tool wants this module in)
		mins[forced_module] = 1
	if wanted != "" and modules().has(wanted):
		mins[wanted] = 1
	if capital != "":  # every signature room of the race
		for mid in modules():
			if modules()[mid].get("races", []).has(capital):
				mins[mid] = 1
	var need: Array = mins.keys()
	need.sort()
	for mid in need:
		var tries := 0
		while _count_of(mid) < int(mins[mid]) and tries < 3:
			tries += 1
			_place_required(str(mid))
		if _count_of(mid) < int(mins[mid]):
			return "no room for a %s" % mid
	_cap_links()
	_loops()
	return _realize()


## Modules placed besides the dock.
## The type whose module weights this station uses (a capital uses the habitat's).
func wtype() -> String:
	return str(config()["types"][type].get("weights_as", type))


func _count() -> int:
	return insts.size() - 1


func _count_of(mid: String) -> int:
	return insts.filter(func(i): return i["mod"] == mid or str(modules()[i["mod"]].get("counts_as", "")) == mid).size()


## The modules the type must still have (a secure one counts its checkpoint too): the budget keeps room for them.
func _missing() -> int:
	var n := 0
	var mins: Dictionary = config()["types"][type].get("min", {})
	for mid in mins:
		var short := maxi(int(mins[mid]) - _count_of(str(mid)), 0)
		n += short * (2 if not modules()[mid].get("after", []).is_empty() else 1)
	return n


## The open connectors, oldest first: [[inst, connector]].
func _open() -> Array:
	var out := []
	for i in insts.size():
		for k in insts[i]["links"].size():
			if int(insts[i]["links"][k]) == -1:
				out.append([i, k])
	return out


## The weights of the modules for the type (only those that can still be placed). A module the type must still have weighs more, and so does the
## module that leads to one (a checkpoint, for the command deck), so they go in while there are connectors to spare.
func _weights() -> Dictionary:
	var out := {}
	var ids: Array = modules().keys()
	ids.sort()
	var boost := {}
	var mins: Dictionary = config()["types"][type].get("min", {})
	for mid in mins:
		if _count_of(str(mid)) < int(mins[mid]):
			boost[mid] = true
			for m in ids:
				if str(modules()[m].get("leads", "")) != "" and modules()[mid].get("tags", []).has(str(modules()[m]["leads"])):
					boost[m] = true
	for mid in ids:
		var w := float(modules()[mid].get("weights", {}).get(wtype(), 0.0))
		var rcs: Array = modules()[mid].get("races", [])
		if not rcs.is_empty() and (not race_rooms or not rcs.any(func(x): return s.races.has(x))):  # (a race's own room only in a station its people built)
			continue
		w *= float(config().get("race_boost", 1.0)) if not rcs.is_empty() else 1.0
		var ex := str(modules()[mid].get("exclusive", ""))  # (a race's generator room replaces the plain one: not both)
		if ex != "" and _count_of(ex) > 0:
			continue
		if w > 0.0 and _count_of(mid) < _max_of(mid):
			out[mid] = w * (3.0 if boost.has(mid) else 1.0)
	return out


func _max_of(mid: String) -> int:
	return int(config()["types"][type].get("max", {}).get(mid, modules()[mid].get("max", 99)))


## A module of `weights` on connector `k` of inst `i`, tried in weighted order (each in every rotation and every matching connector). With `leads`, the
## module's lead comes too. True when one went in.
func _grow(i: int, k: int, weights: Dictionary, leads: bool) -> bool:
	var w := weights.duplicate()
	var parent: Dictionary = insts[i]
	while not w.is_empty():
		var mid := _pick(w, rng)
		w.erase(mid)
		if not _rules_ok(mid, parent):
			continue
		var def: Dictionary = modules()[mid]
		if str(def.get("leads", "")) != "" and not leads:
			continue
		if _attach(mid, i, k):
			if str(def.get("leads", "")) == "" or _lead(insts.size() - 1):
				return true
			_remove(insts.size() - 1)
			insts[i]["links"][k] = -1
	return false


## Does module `mid` follow `parent` by its after and not_after tags?
func _rules_ok(mid: String, parent: Dictionary) -> bool:
	var def: Dictionary = modules()[mid]
	var tags: Array = modules()[parent["mod"]].get("tags", [])
	var after: Array = def.get("after", [])
	if not after.is_empty() and not after.any(func(t): return tags.has(t)):
		return false
	return not def.get("not_after", []).any(func(t): return tags.has(t))


## A module whose tags hold the lead of the newest inst, on another of its connectors; the door between is a card door. False when none fits.
func _lead(i: int) -> bool:
	var tag := str(modules()[insts[i]["mod"]]["leads"])
	var w := {}
	for mid in modules():
		if modules()[mid].get("tags", []).has(tag) and _count_of(mid) < _max_of(mid):
			w[mid] = maxf(float(modules()[mid].get("weights", {}).get(wtype(), 0.0)), 0.1)
	var ks: Array = []
	for k in insts[i]["links"].size():
		if int(insts[i]["links"][k]) == -1:
			ks.append(k)
	s.shuffle(ks, rng)
	for k in ks:
		var n := insts.size()
		if _grow(i, k, w, false):
			insts[n]["lead"] = true
			return true
	return false


## Try module `mid` on connector `k` of inst `i`: every rotation (and the stretch rolled once), every connector of it that matches. True when placed.
func _attach(mid: String, i: int, k: int) -> bool:
	var pc: Dictionary = insts[i]["v"]["conns"][k]
	var pcells: Array = pc["cells"].map(func(c): return c + insts[i]["off"])
	var stretch := _roll_stretch(mid)
	var rots := [0, 1, 2, 3]
	s.shuffle(rots, rng)
	for rot in rots:
		var v := _variant(mid, rot, stretch)
		var ks: Array = range(v["conns"].size())
		s.shuffle(ks, rng)
		for ck in ks:
			var cc: Dictionary = v["conns"][ck]
			if cc["type"] != pc["type"] or cc["side"] != -pc["side"] or cc["cells"].size() != pcells.size():
				continue
			var off: Vector2i = pcells[0] - cc["cells"][0]
			if not _fits(v, off):
				continue
			var links := _open_links(v)
			links[ck] = i
			_stamp({"mod": mid, "v": v, "off": off, "parent": i, "links": links})
			insts[i]["links"][k] = insts.size() - 1
			return true
	return false


## Can variant `v` stand at `off`: a floor only on empty space, a wall only on space or another wall, nothing on the space another keeps, and its
## own space to keep empty?
func _fits(v: Dictionary, off: Vector2i) -> bool:
	for c in v["cells"]:
		var wc: Vector2i = c + off
		if keep.has(wc):
			return false
		var k: String = v["cells"][c]
		if occ.has(wc) and (k == "f" or k == "@" or occ[wc] == "f" or occ[wc] == "@"):
			return false
	for c in v["keep"]:
		if occ.has(c + off):
			return false
	return true


func _stamp(inst: Dictionary) -> void:
	insts.append(inst)
	var v: Dictionary = inst["v"]
	for c in v["cells"]:
		var k: String = v["cells"][c]
		var wc: Vector2i = c + inst["off"]
		if not occ.has(wc) or k == "f" or k == "@":
			occ[wc] = "f" if k == "f" else ("@" if k == "@" else "x")
	for c in v["keep"]:
		keep[c + inst["off"]] = insts.size() - 1


## Take inst `i` out (the last one placed, or a leaf): its parent's connector closes; the cells are stamped again from the rest.
func _remove(i: int) -> void:
	var p := int(insts[i]["parent"])
	if p >= 0:
		for k in insts[p]["links"].size():
			if int(insts[p]["links"][k]) == i:
				insts[p]["links"][k] = -2
	insts.remove_at(i)
	for inst in insts:  # (the ids above i move down one)
		inst["parent"] = int(inst["parent"]) - 1 if int(inst["parent"]) > i else int(inst["parent"])
		for k in inst["links"].size():
			var l := int(inst["links"][k])
			if l > i:
				inst["links"][k] = l - 1
	var all := insts
	insts = []
	occ = {}
	keep = {}
	for inst in all:
		_stamp(inst)


## A module the type must have: on any open connector; one that must follow a tag (the command deck after a checkpoint) comes with the module
## that leads to it.
func _place_required(mid: String) -> void:
	var w := {mid: 1.0}
	var after: Array = modules()[mid].get("after", [])
	if not after.is_empty():
		w = {}
		for m in modules():
			if str(modules()[m].get("leads", "")) != "" and modules()[m]["tags"].any(func(t): return after.has(t)) and _count_of(m) < _max_of(m):
				w[m] = 1.0
	var open := _open()
	s.shuffle(open, rng)
	for o in open:
		if _grow(o[0], o[1], w, true):
			return
	var links := {}  # nowhere for it: a spoke first, and it at the spoke's far end
	for m in modules():
		if modules()[m].get("tags", []).has("link") and float(modules()[m].get("weights", {}).get(wtype(), 0.0)) > 0.0 and _count_of(m) < _max_of(m):
			links[m] = 1.0
	for o in open:
		var n := insts.size()
		if int(insts[o[0]]["links"][o[1]]) != -1 or not _grow(o[0], o[1], links, true):
			continue
		for k in insts[n]["links"].size():
			if int(insts[n]["links"][k]) == -1 and _grow(n, k, w, true):
				return
		_remove(n)
		insts[o[0]]["links"][o[1]] = -1


## A spoke or a crossing (tag link) must lead somewhere: one with nothing past it gets a module there, or goes.
func _cap_links() -> void:
	var changed := true
	while changed:
		changed = false
		for i in range(insts.size() - 1, 0, -1):
			if not modules()[insts[i]["mod"]].get("tags", []).has("link"):
				continue
			var kids := 0
			for k in insts[i]["links"].size():
				var l := int(insts[i]["links"][k])
				if l >= 0 and l != int(insts[i]["parent"]):
					kids += 1
			if kids > 0:
				continue
			var w := _weights()
			for m in w.keys():
				if modules()[m].get("tags", []).has("link"):
					w.erase(m)
			var done := false
			for k in insts[i]["links"].size():
				if int(insts[i]["links"][k]) == -1 and _grow(i, k, w, true):
					done = true
					break
			if not done:
				_remove(i)
			changed = true
			break


## Open connectors of two modules on the same cells, facing each other, are joined: a loop.
func _loops() -> void:
	var open := _open()
	for a in open.size():
		for b in range(a + 1, open.size()):
			var ia: int = open[a][0]
			var ib: int = open[b][0]
			if ia == ib or int(insts[ia]["links"][open[a][1]]) != -1 or int(insts[ib]["links"][open[b][1]]) != -1:
				continue
			var ca: Dictionary = insts[ia]["v"]["conns"][open[a][1]]
			var cb: Dictionary = insts[ib]["v"]["conns"][open[b][1]]
			if ca["type"] == cb["type"] and ca["side"] == -cb["side"] and ca["cells"][0] + insts[ia]["off"] == cb["cells"][0] + insts[ib]["off"] and ca["cells"].size() == cb["cells"].size():
				insts[ia]["links"][open[a][1]] = ib
				insts[ib]["links"][open[b][1]] = ia


# --- the modules as cells -----------------------------------------------------------------------------------------

func _roll_stretch(mid: String) -> Dictionary:
	var st: Dictionary = modules()[mid].get("stretch", {})
	var out := {}
	for axis in ["x", "y"]:
		if st.has(axis):
			out[axis] = rng.randi_range(int(st[axis][1]), int(st[axis][2]))
	return out


## The cells of module `mid` turned `rot` quarter turns clockwise, its `stretch` row or column repeated: {cells: {Vector2i: "f" floor, "x" wall,
## "w" window, "@" hatch}, room ({cell: room number}), conns: [{side, cells (in order along the wall), type ("door" or "hall")}], wins ({cell: normal}),
## inner ([[cell, cell]]: the inner doors), hatch ([cell, cell]), keep (cells to keep empty), w, h}.
static func _variant(mid: String, rot: int, stretch := {}) -> Dictionary:
	var key := "%s|%d|%d|%d" % [mid, posmod(rot, 4), int(stretch.get("x", -1)), int(stretch.get("y", -1))]
	if not _variants.has(key):
		_variants[key] = _parse_variant(mid, rot, stretch)
	return _variants[key]  # (shared: nothing writes to a variant)


static func _parse_variant(mid: String, rot: int, stretch: Dictionary) -> Dictionary:
	var def: Dictionary = modules()[mid]
	var rows: Array = def["cells"].duplicate()
	var st: Dictionary = def.get("stretch", {})
	if stretch.has("y"):
		var at := int(st["y"][0])
		for i in int(stretch["y"]):
			rows.insert(at, rows[at])
	if stretch.has("x"):
		var at := int(st["x"][0])
		for r in rows.size():
			var row: String = rows[r]
			rows[r] = row.substr(0, at) + row[at].repeat(int(stretch["x"])) + row.substr(at)
	for i in posmod(rot, 4):
		rows = _turn(rows)
	return _parse(rows, int(def.get("clear", 0)))


## The rows turned a quarter clockwise.
static func _turn(rows: Array) -> Array:
	var h := rows.size()
	var w: int = rows[0].length()
	var out := []
	for x in w:
		var line := ""
		for y in range(h - 1, -1, -1):
			line += rows[y][x]
		out.append(line)
	return out


static func _parse(rows: Array, clear: int) -> Dictionary:
	var h := rows.size()
	var w: int = rows[0].length()
	var out := {"cells": {}, "room": {}, "conns": [], "wins": {}, "inner": [], "hatch": [], "keep": [], "w": w, "h": h}
	var plus := []
	for y in h:
		for x in w:
			var ch: String = rows[y][x] if x < rows[y].length() else " "
			var c := Vector2i(x, y)
			match ch:
				" ":
					pass
				"#", "p", "d", "h":
					out["cells"][c] = "x"
				"w":
					out["cells"][c] = "w"
					out["wins"][c] = _edge(c, h)
				"@":
					out["cells"][c] = "@"
					out["hatch"].append(c)
				"+":
					out["cells"][c] = "x"
					plus.append(c)
				_:
					out["cells"][c] = "f"
					out["room"][c] = 0 if ch == "." else int(ch)
	for c in plus:  # inner doors: a pair, the first cell's partner right or below it
		for d in [Vector2i.RIGHT, Vector2i.DOWN]:
			if plus.has(c + d):
				out["inner"].append([c, c + d])
	for side in SIDES:
		var line: Array = _edge_line(side, w, h)
		var i := 0
		while i < line.size():
			var c: Vector2i = line[i]
			var ch: String = rows[c.y][c.x]
			if ch == "d" and i + 1 < line.size() and rows[line[i + 1].y][line[i + 1].x] == "d":
				out["conns"].append({"side": side, "cells": [c, line[i + 1]], "type": "door"})
				i += 2
				continue
			if ch == "h" and i + 4 < line.size():
				var run := ""
				for j in 5:
					run += rows[line[i + j].y][line[i + j].x]
				if run == "hhphh":
					out["conns"].append({"side": side, "cells": line.slice(i, i + 5), "type": "hall"})
					i += 5
					continue
			i += 1
	var hatch: Array = out["hatch"]
	if hatch.size() == 2:  # space in front of the hatch stays empty
		var n := _edge(hatch[0], h)
		for k in range(1, 5):
			for c in hatch:
				for side_off in [-1, 0, 1]:
					out["keep"].append(c + n * k + Vector2i(n.y, n.x) * side_off)
	if clear > 0 and not out["wins"].is_empty():  # the view out of the window wall (the side with most windows) stays empty
		var by := {}
		for c in out["wins"]:
			by[out["wins"][c]] = int(by.get(out["wins"][c], 0)) + 1
		var best := Vector2i.ZERO
		for n in SIDES:
			if int(by.get(n, 0)) > int(by.get(best, 0)):
				best = n
		for c in out["wins"]:
			if out["wins"][c] == best:
				for k in range(1, clear + 1):
					out["keep"].append(c + best * k)
	return out


## The outward side of an edge cell.
static func _edge(c: Vector2i, h: int) -> Vector2i:
	if c.y == 0:
		return Vector2i.UP
	if c.y == h - 1:
		return Vector2i.DOWN
	if c.x == 0:
		return Vector2i.LEFT
	return Vector2i.RIGHT


## The cells of one edge, corners left out, in order along it.
static func _edge_line(side: Vector2i, w: int, h: int) -> Array:
	var out := []
	match side:
		Vector2i.UP:
			for x in range(1, w - 1):
				out.append(Vector2i(x, 0))
		Vector2i.DOWN:
			for x in range(1, w - 1):
				out.append(Vector2i(x, h - 1))
		Vector2i.LEFT:
			for y in range(1, h - 1):
				out.append(Vector2i(0, y))
		_:
			for y in range(1, h - 1):
				out.append(Vector2i(w - 1, y))
	return out


static func _open_links(v: Dictionary) -> Array:
	var out := []
	for c in v["conns"]:
		out.append(-1)
	return out


# --- the site ----------------------------------------------------------------------------------------------------

## Turn the modules into the site: grid, rooms, doors, windows, the hatch; then the state; then the props, lanes and slots as a classic site.
func _realize() -> String:
	var floor_at := {}  # world cell -> [inst, room]
	var door_cells := {}  # world cell -> true: a joined connector's door cell
	var own := {}  # world cell -> how many modules have a wall, a window or a connector on it
	var win_at := {}  # world cell -> outward normal: a window of a module, or an unused connector of one that closes with glass
	for i in insts.size():
		var inst: Dictionary = insts[i]
		var v: Dictionary = inst["v"]
		var glass: bool = str(modules()[inst["mod"]].get("close", "wall")) == "window"
		for k in v["conns"].size():
			var conn: Dictionary = v["conns"][k]
			for j in conn["cells"].size():
				var wc: Vector2i = conn["cells"][j] + inst["off"]
				if int(inst["links"][k]) >= 0 and (conn["type"] == "door" or j != 2):
					door_cells[wc] = true
				elif int(inst["links"][k]) < 0 and glass:
					win_at[wc] = conn["side"]
		for c in v["cells"]:
			var wc: Vector2i = c + inst["off"]
			if str(v["cells"][c]) == "f":
				floor_at[wc] = [i, int(v["room"][c])]
				continue
			own[wc] = int(own.get(wc, 0)) + 1
			if str(v["cells"][c]) == "w":
				win_at[wc] = v["wins"][c]
	var windows := {}
	for wc in win_at:  # a window only on one module's wall, with space right outside it
		var out: Vector2i = wc + win_at[wc]
		if int(own.get(wc, 0)) == 1 and not door_cells.has(wc) and not floor_at.has(out) and not own.has(out):
			windows[wc] = win_at[wc]
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := -lo
	for wc in occ:
		lo = lo.min(wc)
		hi = hi.max(wc)
	var off := Vector2i(s.MARGIN, s.MARGIN) - lo
	var size := hi - lo + Vector2i.ONE + Vector2i(s.MARGIN, s.MARGIN) * 2
	s.bounds = Rect2i(Vector2i(s.MARGIN, s.MARGIN), hi - lo + Vector2i.ONE)
	var defs := TileDefs.new()
	defs.load_file(s.TILES_PATH)
	s.grid = ShipGrid.new(size, defs)
	for yy in size.y:
		for xx in size.x:
			s.grid.hull[Vector2i(xx, yy)] = true
	for wc in own:  # every wall, window and connector is a wall for now (doors go in below, windows come out at the end)
		s.grid.force_tile(wc + off, "wall")
	# rooms
	var rid_of := {}  # "inst:room" -> room id
	var cells_of := {}
	for wc in floor_at:
		var key := "%d:%d" % floor_at[wc]
		if not cells_of.has(key):
			cells_of[key] = []
		cells_of[key].append(wc)
	var keys: Array = cells_of.keys()
	keys.sort_custom(func(a, b): return _key_lt(a, b))
	for key in keys:
		var cl: Array = cells_of[key]
		var a: Vector2i = cl[0]
		var b: Vector2i = cl[0]
		for c in cl:
			a = a.min(c)
			b = b.max(c)
		var rect := Rect2i(a + off, b - a + Vector2i.ONE)
		if rect.get_area() != cl.size():
			return "room %s is not a rectangle" % key
		var parts: PackedStringArray = key.split(":")
		var i := int(parts[0])
		var rdef: Dictionary = modules()[insts[i]["mod"]]["rooms"][int(parts[1])]
		s._add_room(rect, i, bool(rdef.get("corridor", false)))
		var r: Dictionary = s.rooms[-1]
		r["purpose"] = _purpose(rdef)
		r["module"] = i
		r["mroom"] = int(parts[1])
		if rdef.has("props"):
			r["props"] = rdef["props"]
		rid_of[key] = r["id"]
	# doors: the joined connectors (once per pair), then the inner doors
	for i in insts.size():
		var inst: Dictionary = insts[i]
		for k in inst["v"]["conns"].size():
			var j := int(inst["links"][k])
			if j < i:
				continue
			var conn: Dictionary = inst["v"]["conns"][k]
			var cl: Array = conn["cells"].map(func(c): return c + inst["off"] + off)
			var pieces: Array = [[cl[0], cl[1]]] if conn["type"] == "door" else [[cl[0], cl[1]], [cl[3], cl[4]]]
			for piece in pieces:
				var why := _door(piece, conn["side"], bool(insts[j].get("lead", false)) and int(insts[j]["parent"]) == i)
				if why != "":
					return why
	for i in insts.size():
		for pair in insts[i]["v"]["inner"]:
			var a: Vector2i = pair[0] + insts[i]["off"] + off
			var b: Vector2i = pair[1] + insts[i]["off"] + off
			var side := Vector2i((b - a).y, (b - a).x)
			var why := _door([a, b], side, false)
			if why != "":
				return why
	# the hatch
	var dock: Dictionary = insts[0]
	var h: Array = dock["v"]["hatch"].map(func(c): return c + dock["off"] + off)
	var n := _edge(dock["v"]["hatch"][0], int(dock["v"]["h"]))
	var air_room := int(s.room_of.get(h[0] - n, -1))
	if air_room < 0:
		return "no airlock"
	var mid := (Vector2(h[0]) + Vector2(h[1])) / 2.0 + Vector2(0.5, 0.5)
	s.airlock = {"room": air_room, "hatch": h, "spawn": mid - Vector2(n) * 1.5, "normal": Vector2(n)}
	s.rooms[air_room]["purpose"] = "airlock"
	# the windows: cleared from the drawn grid (space shows through), kept as runs for the view
	for wc in windows:
		s.grid.force_tile(wc + off, "")
	s.windows = _runs(windows, off)
	for i in insts.size():
		var mrooms: Array = s.rooms.filter(func(r): return r.get("module", -1) == i).map(func(r): return r["id"])
		var a := Vector2i(1 << 20, 1 << 20)
		var b := -a
		for c in insts[i]["v"]["cells"]:
			a = a.min(c + insts[i]["off"] + off)
			b = b.max(c + insts[i]["off"] + off)
		s.modules.append({"id": insts[i]["mod"], "name": str(modules()[insts[i]["mod"]]["name"]), "rect": Rect2i(a, b - a + Vector2i.ONE), "rooms": mrooms,
			"powered": true, "breached": false, "own": not modules()[insts[i]["mod"]].get("races", []).is_empty()})
	return _dress()


static func _key_lt(a: String, b: String) -> bool:
	var pa := a.split(":")
	var pb := b.split(":")
	return int(pa[0]) < int(pb[0]) or (int(pa[0]) == int(pb[0]) and int(pa[1]) < int(pb[1]))


## A door piece on cells `cells` in a wall whose rooms lie across `side`; `lead` makes it the checkpoint's card door.
func _door(cells: Array, side: Vector2i, lead: bool) -> String:
	var a: Vector2i = cells[0]
	var axis := Vector2i.RIGHT if side.y != 0 else Vector2i.DOWN
	if not s.grid.place_door("door", a, axis):
		return "a door would not fit at %s" % a
	var r1 := int(s.room_of.get(a - side, -1))
	var r2 := int(s.room_of.get(a + side, -1))
	if r1 < 0 or r2 < 0:
		return "a door at %s leads nowhere" % a
	var typed: Array[Vector2i] = [cells[0], cells[1]]
	s._add_door(typed, r1, r2)
	if lead:
		s.doors[-1]["lead"] = true
	return ""


## Window cells as runs along a wall: [{cells (grid), normal}].
static func _runs(windows: Dictionary, off: Vector2i) -> Array:
	var cells: Array = windows.keys()
	cells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var seen := {}
	var out := []
	for c in cells:
		if seen.has(c):
			continue
		var n: Vector2i = windows[c]
		var along := Vector2i(n.y, n.x).abs()
		var run: Array[Vector2i] = []
		var p: Vector2i = c
		while windows.has(p) and windows[p] == n:
			seen[p] = true
			run.append(p + off)
			p += along
		out.append({"cells": run, "normal": n})
	return out


func _purpose(rdef: Dictionary) -> String:
	var p = rdef.get("purpose", "storage")
	if p is Dictionary:
		var keys: Array = p.keys()
		keys.sort()
		var w := {}
		for k in keys:
			w[k] = p[k]
		return _pick(w, rng)
	return str(p)


# --- the state ------------------------------------------------------------------------------------------------------

## Power, air and light per module, the doors' locks, who is aboard, the props, the lanes, the slots, the sentries, the beds, the backdrop.
func _dress() -> String:
	var scfg: Dictionary = config()["states"][state]
	var kcfg: Dictionary = s.config()["kinds"]["station"]
	_assign_races()
	var breached := 0
	for i in s.modules.size():
		var m: Dictionary = s.modules[i]
		if i == 0:  # (the dock has power unless the whole station is dead)
			m["powered"] = float(scfg["powered"]) > 0.0
			continue
		var pm := Races.power_mult(str(m["race"])) if float(scfg["powered"]) < 1.0 else 1.0  # (a power race keeps more of a half-active station lit)
		m["powered"] = rng.randf() < minf(float(scfg["powered"]) * pm, 1.0)
		var bm := float(modules()[m["id"]].get("breach_mult", 1.0))
		if breached < BREACH_MAX and rng.randf() < float(scfg["breach"]) * bm:
			m["breached"] = true
			m["powered"] = false
			breached += 1
			for rid in m["rooms"]:
				s.rooms[rid]["air"] = 0.0
	for i in range(1, s.modules.size()):  # a module that is a torn-open hull in its data: always breached (not counted against the cap)
		var m: Dictionary = s.modules[i]
		if bool(modules()[m["id"]].get("breached", false)) and not m["breached"] and float(scfg["breach"]) > 0.0:  # (an operational station keeps her hull whole)
			m["breached"] = true
			m["powered"] = false
			for rid in m["rooms"]:
				s.rooms[rid]["air"] = 0.0
	_airless_races()
	_power()
	s.room_light = {}
	for r in s.rooms:
		var m: Dictionary = s.modules[int(r["module"])]
		var lw: Dictionary = scfg["light"]["on" if m["powered"] else "off"]
		var mode := _pick(lw, rng)
		s.room_light[r["id"]] = mode
		var mid := Vector2(r["rect"].position) + Vector2(r["rect"].size) / 2.0
		if r["id"] == s.airlock["room"]:
			s.lights.append({"pos": mid, "color": "green", "room": r["id"]})
		elif mode == "red":
			s.lights.append({"pos": mid, "color": "red", "room": r["id"]})
	_heat()
	_lock(scfg)
	s.crowd = scfg["crowd"].get(mood if mood != "" else "any", scfg["crowd"].get("any", {}))
	if capital != "":  # a capital's people: its traders and recruiters, and its guards
		s.crowd = {"spawn": {"count": [0, 0], "mix": {"scavenger": 1}}, "people": Homelands.config()["capital"]["people"].duplicate(true)}
		s.capital = capital
	s._place_props(kcfg, rng)
	s._make_walk()
	var why: String = s._clear_lanes()
	if why != "":
		return why
	s._fill_slots(kcfg, rng)
	if s.containers().size() < s.MIN_ROOMS:
		return "too few containers"
	_posts(scfg)
	_beds(scfg)
	Fixtures.place(s)
	if not s.power.is_empty() and Fixtures.enabled:
		var gen_fx: Array = s.fixtures.filter(func(f): return f["fixture"] == "generator" and int(s.rooms[f["room"]]["module"]) == int(s.power["module"]))
		if gen_fx.is_empty():
			return "no generator"
		s.power["fixture"] = gen_fx[0]["id"]
	if s._cut_off():
		return "fixtures cut a room off"
	Dressing.place(s)
	_backdrop()
	return ""


## Each module is a section of one race: the dock the station's first; a race-only module its race's; the rest keep their parent's at `stay` chance, else
## take another of the station's races. A stream of its own, so the layout and the rest of the dice are what they were.
func _assign_races() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = s._mix(s.seed_value, "sections", 0)
	var stay := float(Races.config()["stay"])
	for i in s.modules.size():
		var m: Dictionary = s.modules[i]
		var own := ""
		for x in modules()[m["id"]].get("races", []):
			if own == "" and s.races.has(x):
				own = str(x)
		var race: String = s.races[0]
		if own != "":
			race = own
		elif i > 0:
			var parent: int = maxi(int(insts[i]["parent"]), 0)
			race = str(s.modules[parent]["race"])
			var roll := r.randf()
			var pick := r.randi()
			if roll >= stay and s.races.size() > 1:
				var others: Array = s.races.filter(func(x): return x != race)
				race = str(others[pick % others.size()])
		m["race"] = race
		m["climate"] = Races.climate(race)
		m["airless"] = false


## A race that needs no air keeps a powered section of its own airless and working: lit, doors live, and nobody in it needs a suit but the soldier.
func _airless_races() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = s._mix(s.seed_value, "airless", 0)
	var left := int(Races.config()["airless_max"])
	for i in range(1, s.modules.size()):
		var m: Dictionary = s.modules[i]
		var roll := r.randf()
		var ends: int = insts[i]["links"].filter(func(l): return int(l) >= 0).size()
		var lives_so: bool = bool(modules()[m["id"]].get("airless", false)) and ends <= 1  # (a room its people live in without air: airless whenever it has power, if nothing lies beyond it: a keycard is never put behind thin air)
		if m["powered"] and not m["breached"] and Races.airless_ok(str(m["race"])) and (lives_so or (left > 0 and roll < float(Races.config()["airless_chance"]))):
			m["airless"] = true
			left -= 0 if lives_so else 1
			for rid in m["rooms"]:
				s.rooms[rid]["air"] = 0.0


## The generator room (tag power; in an operational station it just works and there is nothing to repair): its section is dark until the soldier repairs it. The section is every unpowered module that has
## not lost its air within `power.reach` modules of it (at least one besides itself, else one is cut off from power).
func _power() -> void:
	s.power = {}
	if float(config()["states"][state]["powered"]) >= 1.0:
		return
	var gi := -1
	for i in s.modules.size():
		if modules()[s.modules[i]["id"]].get("tags", []).has("power"):
			gi = i
	if gi < 0:
		return
	s.modules[gi]["powered"] = false
	var dist := {gi: 0}
	var queue: Array = [gi]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		for l in insts[i]["links"]:
			if int(l) >= 0 and not dist.has(int(l)):
				dist[int(l)] = int(dist[i]) + 1
				queue.append(int(l))
	var reach := int(config().get("power", {}).get("reach", 3))
	var feeds := []
	for i in range(1, s.modules.size()):
		var m: Dictionary = s.modules[i]
		if i != gi and dist.has(i) and int(dist[i]) <= reach and not m["powered"] and not m["breached"] and not m["airless"]:
			feeds.append(i)
	if feeds.is_empty():
		var near := dist.keys().filter(func(i): return i != gi and i > 0 and not s.modules[i]["breached"] and not s.modules[i]["airless"])
		near.sort_custom(func(a, b): return int(dist[a]) < int(dist[b]) or (int(dist[a]) == int(dist[b]) and a < b))
		if not near.is_empty():
			feeds.append(near[0])
			s.modules[near[0]]["powered"] = false
	s.power = {"module": gi, "fixture": -1, "feeds": feeds, "restored": false}


## The static heat of each room (data `heat`): the ambient, a purpose's own (a reactor), a module's own (a forge), and a hot race's sections.
func _heat() -> void:
	var hc: Dictionary = config().get("heat", {})
	for r in s.rooms:
		var m: Dictionary = s.modules[int(r["module"])]
		var h := float(hc.get("ambient", 30.0))
		h = maxf(h, float(hc.get("purposes", {}).get(str(r["purpose"]), 0.0)))
		h = maxf(h, float(hc.get("modules", {}).get(str(m["id"]), 0.0)))
		if str(m["climate"]) == "hot":
			h = maxf(h, float(hc.get("hot", 70.0)))
		r["heat"] = h


## Locks: the checkpoint's door to its secure module is a card door; a door that touches a module without power is dead at the state's `hack`
## chance; `card` more card doors on dead-end rooms (as a classic site); never a door of the airlock. Then the rooms only a lock opens.
func _lock(scfg: Dictionary) -> void:
	var air: int = s.airlock["room"]
	var made := 0
	for d in s.doors:
		if d.get("lead", false):
			d["lock"] = "card"
			d["card"] = KEY_NAMES[made]
			made += 1
	var live: Array = s.doors.filter(func(d): return d["lock"] == "" and not d["rooms"].has(air))
	var dead: Array = live.filter(func(d): return d["rooms"].any(func(r): return s.rooms[r]["doors"].size() == 1 and not s.rooms[r]["corridor"]))
	s.shuffle(dead, rng)
	var n_card := rng.randi_range(int(scfg["card"][0]), int(scfg["card"][1]))
	for d in dead:
		if n_card <= 0 or made >= KEY_NAMES.size():
			break
		d["lock"] = "card"
		d["card"] = KEY_NAMES[made]
		made += 1
		n_card -= 1
	for d in s.doors:
		if d["lock"] != "" or d["rooms"].has(air):
			continue
		var off_power: bool = d["rooms"].any(func(r): return not s.modules[int(s.rooms[r]["module"])]["powered"])
		if off_power and rng.randf() < float(scfg["hack"]):
			d["lock"] = "hack"
	var open_rooms: Dictionary = s._room_graph_reach(air, s._lock_ids())
	for r in s.rooms:
		r["locked"] = not open_rooms.has(r["id"])


## A sentry watches some crossings (not on a friendly station): it stands at the far end of the tube, looking down it.
func _posts(scfg: Dictionary) -> void:
	s.posts = []
	if int(s.crowd.get("spawn", {}).get("count", [0, 0])[1]) <= 0:
		return
	for i in s.modules.size():
		if not modules()[s.modules[i]["id"]].get("tags", []).has("crossing") or rng.randf() >= float(scfg["sentry"]):
			continue
		var rid: int = s.modules[i]["rooms"][0]
		var entry: Vector2 = s.centre_of_room(rid)
		for did in s.rooms[rid]["doors"]:
			var other: int = s.doors[did]["rooms"][0] if s.doors[did]["rooms"][1] == rid else s.doors[did]["rooms"][1]
			if int(s.rooms[other].get("module", -1)) == int(insts[i]["parent"]):
				entry = s.door_centre(s.doors[did])
		var best := Vector2.ZERO
		var best_d := -1.0
		for a in s.free_anchors(rid):
			var p := Vector2(a) + Vector2.ONE
			if p.distance_to(entry) > best_d:
				best = p
				best_d = p.distance_to(entry)
		if best_d > 0.0:
			s.posts.append({"kind": "sentry", "pos": best, "room": rid})


## Beds in the medbays: the type's count each, working by the state's chance on a powered module or an unpowered one.
func _beds(scfg: Dictionary) -> void:
	var span: Array = config()["types"][type]["beds"]
	var want := {}
	var works := {}
	for r in s.rooms:
		if r["purpose"] == "medbay":
			want[r["id"]] = rng.randi_range(int(span[0]), int(span[1]))
			works[r["id"]] = float(scfg["beds"]["on" if s.modules[int(r["module"])]["powered"] else "off"])
	s._place_beds(want, works, rng)


## What the windows look out on: a planet or a gas giant (by weight x the region's tilt), its colours and size, and where it lies: past the windows of
## the first observation deck, else of the longest window run (`at`, the run's middle, and `dir`, the way it looks), else past any side.
func _backdrop() -> void:
	var bc: Dictionary = config()["backdrop"]
	var w := {}
	var tilt: Dictionary = bc.get("regions", {}).get(s.region, {})
	var kinds: Array = bc["kinds"].keys()
	kinds.sort()
	for k in kinds:
		w[k] = float(bc["kinds"][k]) * float(tilt.get(k, 1.0))
	var kind := _pick(w, rng)
	var kc: Dictionary = bc[kind]
	var pick := {}
	for i in s.modules.size():
		if pick.is_empty() and modules()[s.modules[i]["id"]].get("tags", []).has("observation"):
			for run in s.windows:
				if pick.is_empty() and s.modules[i]["rect"].has_point(run["cells"][0]) and run["cells"].size() > 2:
					pick = run
	if pick.is_empty():
		for run in s.windows:
			if pick.is_empty() or run["cells"].size() > pick["cells"].size():
				pick = run
	var dir: Vector2i = pick.get("normal", SIDES[rng.randi() % 4])
	var at := Vector2(s.bounds.get_center())
	if not pick.is_empty():
		at = (Vector2(pick["cells"][0]) + Vector2(pick["cells"][-1])) / 2.0 + Vector2(0.5, 0.5)
	s.backdrop = {"kind": kind, "palette": rng.randi() % kc["palettes"].size(), "radius": rng.randf_range(float(kc["radius"][0]), float(kc["radius"][1])),
		"dir": Vector2(dir), "at": at, "seed": rng.randi(), "ring": rng.randf() < float(kc.get("ring", 0.0)), "tilt": rng.randf_range(-0.5, 0.5)}
	if kc.has("moons"):  # (from the seed already rolled: no more dice)
		var mn: Array = kc["moons"]
		s.backdrop["moons"] = int(mn[0]) + int(s.backdrop["seed"]) % (int(mn[1]) - int(mn[0]) + 1)


# --- dice ----------------------------------------------------------------------------------------------------------

## A key of `w` ({key: weight}) by weight, keys in sorted order so the dice mean the same on every run.
static func _pick(w: Dictionary, r: RandomNumberGenerator) -> String:
	var keys: Array = w.keys()
	keys.sort()
	var total := 0.0
	for k in keys:
		total += float(w[k])
	if total <= 0.0:
		return str(keys[0]) if not keys.is_empty() else ""
	var roll := r.randf() * total
	for k in keys:
		roll -= float(w[k])
		if roll < 0.0 and float(w[k]) > 0.0:
			return str(k)
	return str(keys[-1])
