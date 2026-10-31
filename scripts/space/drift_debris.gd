extends RefCounted
## Debris that drifts past the ship on a current (docs/CONTENT.md section 11, the Raft loop). Pure logic, no nodes: debris_view.gd steps it in play mode and draws it.
## All numbers are in data/debris.json. The current has a direction and a speed in world px/s, with a slow
## wobble. Pieces appear just outside the view upstream, drift and tumble, and despawn past the downstream edge
## of the view. A piece within an intake's pull radius of its outside half (the mouth) is drawn toward it, and
## one that touches the mouth lands in ship.inventory (refused when the hold cannot take it: it bounces). A
## piece that touches any other solid cell (a tile, an outside half) bounces off and keeps drifting.
## While `tractor_on` (Q held, debris_view.gd) the working tractor beams (tractor.gd) haul every piece within their range
## toward the nearest working intake, faster than an intake's own pull.
## A sector (sector.gd) can set the current and the density (for_sector); with none, the numbers of debris.json run.
## Positions are world px. On the build screen that is the space the build view draws the ship in (ship.world_pos is
## the grid centre); in a sector the pieces live in sector px and `frame` says where the ship's cells are (its place and
## heading, helm.gd frame()) and `frame_vel` how fast it moves: pieces then spawn upstream of the flow past the ship,
## and the mouths and the hull are tested in the ship's own frame.
## Randomness comes from one RandomNumberGenerator seeded by the caller (the ship's rng_seed): same seed, same run.

const Content = preload("res://scripts/data/content.gd")
const Tractor = preload("res://scripts/space/tractor.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const PATH := "res://data/debris.json"
const CELL := 32.0  ## world px per grid cell (build_mode.gd CELL)
const SUBSTEP := 0.05  ## longest time step the pieces move by
const PULL_GLOW := 0.35  ## seconds a mouth keeps `pulling` after it last drew a piece
const LANE_REFRESH := 1.0  ## seconds between looks at the ship's outline
const BEAM_LINES := 4  ## most pieces a tractor beam is drawn to at once
const MAX_EVENTS := 64
const HUD_ORDER: Array[String] = ["scrap", "copper", "polymer", "fuel", "missile", "ice"]  ## the order the HUD lists what was taken
const COMPASS: Array[String] = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]

var cfg: Dictionary
var types: Array = []  ## data/debris.json "types"
var pieces: Array = []  ## {uid, type, pos, vel, angle, spin, phase, age, r, no_pull}
var collected := {}  ## cargo id -> units taken in this session ("ice" counts pieces); for the HUD
var picked := 0  ## pieces collected in this session
var events: Array = []  ## for the view, until take_events(): {kind: "collect", pos (the mouth), text, uid, type}
var pulling := {}  ## intake uid -> seconds it still shows the pulling animation
var mouth_count := 0  ## working intakes at the last step
var tractor_on := false  ## Q is held: the working tractor beams haul pieces toward the nearest intake (the view sets it)
var beams_on: Array = []  ## uids of the tractor beams that work now, while tractor_on (the view lights their emitters)
var beam_lines: Array = []  ## while a beam hauls: [{uid, from (its emitter), to (a piece), aim (a unit vector in the ship's own frame)}], nearest piece first
var time := 0.0  ## seconds of drifting; the current's wobble follows it
var rng := RandomNumberGenerator.new()
var view_centre := Vector2.ZERO  ## world point at the middle of the screen (the view sets it)
var view_half := Vector2(1600.0, 900.0)  ## half the visible world size (the view sets it from the viewport and zoom)
var frame := Transform2D.IDENTITY  ## the build view's px (the ship's cells) in the pieces' space: the identity on the build screen
var frame_vel := Vector2.ZERO  ## the ship's velocity in the pieces' space, px/s
var _by_id := {}
var _total_weight := 0.0
var _spawn_in := 0.0
var _phase: Array[float] = [0.0, 0.0, 0.0]
var _next_uid := 1
var _beams: Array = []  # the working tractor beams of this step (tractor.gd beams)
var _hauls := {}  # beam uid -> [{d, at, lp, pos}] the pieces it hauled in the last sub-step (distance to its emitter, the emitter and the piece in the ship's px, the piece in world px)
var _bounds := Rect2()
var _bounds_age := 1.0e9


func _init(seed_value := 1, p_cfg: Dictionary = {}) -> void:
	cfg = p_cfg if not p_cfg.is_empty() else Content.read(PATH)
	types = cfg["types"]
	for t in types:
		_by_id[str(t["id"])] = t
		_total_weight += float(t["weight"])
	rng.seed = seed_value
	for i in 3:
		_phase[i] = rng.randf() * TAU
	_spawn_in = float(cfg["spawn"]["every"])


## A spawner driven by `sector` (sector.gd): its current's direction and speed, its debris density and the theme of
## its node type, on top of data/debris.json. The ship in `sector` moves; the pieces still drift with the current.
static func for_sector(sector, seed_value := 1):
	return new(seed_value, sector.debris_cfg(Content.read(PATH)))


## `sector` changed its density (the Hollow tide took it, sector.gd hollow): take its spawn numbers again. The pieces already
## adrift stay, and no more come until fewer than the new cap are about.
func rescale(sector) -> void:
	cfg["spawn"] = sector.debris_cfg(Content.read(PATH))["spawn"]


# --- the current ---------------------------------------------------------------------------------------

## The unit direction debris drifts in now (degrees: 0 east, 90 south on the screen), the base angle plus the wobble.
func current_dir() -> Vector2:
	var c: Dictionary = cfg["current"]
	var period := float(c["wobble_period"])
	var swing := 0.6 * sin(time * TAU / period + _phase[0]) + 0.4 * sin(time * TAU / (period * 0.37) + _phase[1])
	return Vector2.from_angle(deg_to_rad(float(c["angle"]) + float(c["wobble_deg"]) * swing))


func current_speed() -> float:
	var c: Dictionary = cfg["current"]
	return float(c["speed"]) * (1.0 + float(c["speed_wobble"]) * sin(time * TAU / (float(c["wobble_period"]) * 0.8) + _phase[2]))


func current_vel() -> Vector2:
	return current_dir() * current_speed()


## Where the current comes from and goes to, in words ("south-east"): the way it drifts, without the wobble.
## The way the pieces cross the view: the current less the ship's own velocity (the current's own direction while the
## ship is still, or nearly as fast as the current).
func flow_dir() -> Vector2:
	if frame_vel == Vector2.ZERO:
		return current_dir()
	var f := current_vel() - frame_vel
	return f.normalized() if f.length() > 1.0 else current_dir()


func compass() -> String:
	return COMPASS[posmod(roundi(float(cfg["current"]["angle"]) / 45.0), 8)]


func type_of(piece: Dictionary) -> Dictionary:
	return _by_id[piece["type"]]


# --- stepping ------------------------------------------------------------------------------------------

## Drift `dt` seconds of `ship`: spawn, move, pull, collect, bounce, despawn.
func step(ship, dt: float) -> void:
	if ship == null or dt <= 0.0:
		return
	var mouths := intakes(ship)
	mouth_count = mouths.size()
	_beams = Tractor.beams(ship, _origin(ship)) if tractor_on else []
	beams_on = _beams.map(func(b): return b["uid"])
	if _beams.is_empty():
		beam_lines = []
	var left := dt
	while left > 1.0e-6:
		var h := minf(SUBSTEP, left)
		left -= h
		_sub(ship, mouths, h)


## Put the starting pieces along the stream (cfg spawn.start_alive), so there is something to see and catch
## the moment play begins. Call once, before the first step().
func prewarm(ship) -> void:
	var lane := _lane(ship)
	var reach := _reach(lane)
	for k in int(cfg["spawn"]["start_alive"]):
		var p := _spawn(ship, rng.randf_range(-reach, reach * 0.6))
		if p.is_empty():
			continue
		if _blocked_at(ship, p["pos"], p["r"] + 8.0):
			pieces.erase(p)


## Add a piece of type `type_id` at `pos` moving at `vel` (a test or a later feature, such as a crate shot open, puts one where it likes).
func add_piece(type_id: String, pos: Vector2, vel: Vector2) -> Dictionary:
	var p := {"uid": _next_uid, "type": type_id, "pos": pos, "vel": vel, "angle": 0.0, "spin": 0.0, "phase": 0.0, "age": 0.0,
		"r": float(_by_id[type_id]["size"]) * 0.5, "no_pull": false}
	_next_uid += 1
	pieces.append(p)
	return p


func take_events() -> Array:
	var out := events
	events = []
	return out


func _sub(ship, mouths: Array, h: float) -> void:
	time += h
	_spawn_in -= h
	if _spawn_in <= 0.0:
		var s: Dictionary = cfg["spawn"]
		_spawn_in += float(s["every"]) * (1.0 + float(s["jitter"]) * rng.randf_range(-1.0, 1.0))
		if pieces.size() < int(s["max_alive"]):
			_spawn(ship)
	for uid in pulling.keys():
		pulling[uid] -= h
		if pulling[uid] <= 0.0:
			pulling.erase(uid)
	var dir := flow_dir()
	var lane := _lane(ship)
	var limit := {"vel": current_dir() * current_speed(), "along": _reach(lane), "across": _cross_reach(lane), "dir": dir, "inv": frame.affine_inverse()}
	_hauls.clear()
	var i := 0
	while i < pieces.size():
		if _move(ship, pieces[i], mouths, limit, h):
			i += 1
		else:
			pieces.remove_at(i)
	if not _beams.is_empty():
		_note_hauls()


## Move one piece by `h`; `now`: the current's vel and dir and the despawn distances (along, across). False when it is gone.
func _move(ship, p: Dictionary, mouths: Array, now: Dictionary, h: float) -> bool:
	var r: float = p["r"]
	var inv: Transform2D = now["inv"]
	p["age"] += h
	p["vel"] += (now["vel"] - p["vel"]) * minf(1.0, float(cfg["relax"]) * h)
	if not p["no_pull"]:
		var lp: Vector2 = inv * p["pos"]
		var best := {}
		var best_d := INF
		for m in mouths:
			var d := _dist_to_rect(lp, m["rect"])
			if d - r <= float(m["pull"]) and d < best_d:
				best = m
				best_d = d
		var speed := 0.0
		var to := Vector2.ZERO
		if not best.is_empty():
			speed = float(cfg["pull"]["speed"])
			to = best["rect"].get_center()
			pulling[best["uid"]] = PULL_GLOW
		if not _beams.is_empty():  # Q: a tractor beam hauls it, faster than a mouth does
			var t := Tractor.pull(_beams, mouths, lp, r)
			if not t.is_empty():
				var list: Array = _hauls.get(t["beam"], [])
				list.append({"d": lp.distance_to(t["at"]), "at": t["at"], "lp": lp, "pos": p["pos"]})
				_hauls[t["beam"]] = list
				if float(t["speed"]) > speed:
					speed = float(t["speed"])
					to = t["to"]
		if speed > 0.0:
			p["vel"] = p["vel"].lerp(frame_vel + frame.basis_xform(to - lp).normalized() * speed, 1.0 - exp(-float(cfg["pull"]["ease"]) * h))
	p["pos"] += p["vel"] * h
	p["angle"] += p["spin"] * h
	for m in mouths:  # touching the mouth: into the hold
		if _dist_to_rect(inv * p["pos"], m["rect"]) > r * 0.6:
			continue
		var t := type_of(p)
		var gains := _gains(t, ship)
		if _store(ship, t, gains):
			picked += 1
			_note(m, t, gains)
			return false
		p["no_pull"] = true  # the hold is full: it bounces off the mouth like hull and is not drawn again
		_hit_local(p, m["rect"], inv)
	_hull(ship, p, mouths, inv)
	var rel: Vector2 = p["pos"] - view_centre
	var dir: Vector2 = now["dir"]
	return p["age"] < float(cfg["spawn"]["max_age"]) and rel.dot(dir) <= now["along"] and absf(rel.dot(Vector2(-dir.y, dir.x))) <= now["across"]


## The beams' lines of the last sub-step: for each beam that hauled, the BEAM_LINES nearest pieces it holds, nearest first.
func _note_hauls() -> void:
	beam_lines = []
	var uids: Array = _hauls.keys()
	uids.sort()
	for uid in uids:
		var list: Array = _hauls[uid]
		list.sort_custom(func(a, b): return a["d"] < b["d"])
		for k in mini(list.size(), BEAM_LINES):
			var e: Dictionary = list[k]
			beam_lines.append({"uid": uid, "from": frame * e["at"], "to": e["pos"], "aim": (e["lp"] - e["at"]).normalized()})


## The way each beam that hauls points, in the ship's own frame: uid -> unit vector (its nearest piece).
func beam_aims() -> Dictionary:
	var out := {}
	for l in beam_lines:
		if not out.has(l["uid"]):
			out[l["uid"]] = l["aim"]
	return out


# --- spawning ------------------------------------------------------------------------------------------

## A new piece upstream (or `along` px along the current from the view centre, for the prewarm). Returns it, {} at the cap.
func _spawn(ship, along := NAN) -> Dictionary:
	var s: Dictionary = cfg["spawn"]
	if pieces.size() >= int(s["max_alive"]):
		return {}
	var lane := _lane(ship)
	var dir := flow_dir()
	var perp := Vector2(-dir.y, dir.x)
	var t := _pick()
	var half := minf(_cross_half(lane, perp) + float(s["lane_margin"]), float(s["lane_max"]))
	if rng.randf() < float(s["scatter"]):  # a share of the debris is spread over the whole view, so it is not one stream
		half = maxf(half, _cross_reach(lane) - 2.0 * float(s["margin"]))
	var lat := perp.dot(lane["centre"] - view_centre) + rng.randf_range(-1.0, 1.0) * half
	var a := -_reach(lane) if is_nan(along) else along
	var p := {"uid": _next_uid, "type": str(t["id"]), "pos": view_centre + dir * a + perp * lat,
		"vel": current_vel() * rng.randf_range(0.9, 1.1), "angle": rng.randf() * TAU, "spin": rng.randf_range(-0.8, 0.8),
		"phase": rng.randf() * 10.0, "age": 0.0, "r": float(t["size"]) * 0.5, "no_pull": false}
	_next_uid += 1
	pieces.append(p)
	return p


func _pick() -> Dictionary:
	var x := rng.randf() * _total_weight
	for t in types:
		x -= float(t["weight"])
		if x < 0.0:
			return t
	return types[-1]


## How far along the current (px from the view centre) pieces appear upstream and vanish downstream.
func _reach(lane: Dictionary) -> float:
	var dir := flow_dir()
	var view := absf(dir.x) * view_half.x + absf(dir.y) * view_half.y
	var ship: float = absf(dir.x) * lane["rect"].size.x * 0.5 + absf(dir.y) * lane["rect"].size.y * 0.5 + absf(dir.dot(lane["centre"] - view_centre)) + 200.0
	return maxf(view, ship) + float(cfg["spawn"]["margin"])


## How far sideways of the current a piece may stray from the view centre before it despawns.
func _cross_reach(lane: Dictionary) -> float:
	var dir := flow_dir()
	var perp := Vector2(-dir.y, dir.x)
	return maxf(absf(perp.x) * view_half.x + absf(perp.y) * view_half.y, _cross_half(lane, perp) + absf(perp.dot(lane["centre"] - view_centre))) + 2.0 * float(cfg["spawn"]["margin"])


func _cross_half(lane: Dictionary, perp: Vector2) -> float:
	return (absf(perp.x) * lane["rect"].size.x + absf(perp.y) * lane["rect"].size.y) * 0.5


## The ship's outline in world px (through `frame`, the box round it): {rect, centre}. Its cells are looked at again every
## LANE_REFRESH seconds.
func _lane(ship) -> Dictionary:
	if time - _bounds_age >= LANE_REFRESH or _bounds_age > time:
		_bounds_age = time
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := Vector2i(-(1 << 20), -(1 << 20))
		for c in ship.grid.tiles:
			lo = lo.min(c)
			hi = hi.max(c)
		var o := _origin(ship)
		if hi.x < lo.x:
			_bounds = Rect2(ship.world_pos - Vector2(CELL, CELL), Vector2(CELL, CELL) * 2.0)
		else:
			_bounds = Rect2(o + Vector2(lo) * CELL, Vector2(hi - lo + Vector2i.ONE) * CELL)
	var box: Rect2 = _bounds if frame == Transform2D.IDENTITY else frame * _bounds
	return {"rect": box, "centre": box.get_center()}


# --- intakes, collecting and bouncing ------------------------------------------------------------------

## The intakes that work now (an outside half that is alive, link intact, status ok, powered when it draws power):
## [{uid, id, rect (the mouth in world px), pull (px: the part's pull_radius, plus the station.pull_bonus of whoever mans it)}].
func intakes(ship) -> Array:
	var out := []
	var origin := _origin(ship)
	var off: Dictionary = ship.disabled_uids()
	var powered: Dictionary = ship.power_state.get("powered", {})
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		var def: Dictionary = ship.components.def(inst["id"])
		if str(def.get("family", "")) != "intake" or inst["out_cells"].is_empty() or off.has(uid):
			continue
		if int(def.get("power", 0)) < 0 and not powered.get(uid, false):
			continue
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := Vector2i(-(1 << 20), -(1 << 20))
		for c in inst["out_cells"]:
			lo = lo.min(c)
			hi = hi.max(c)
		out.append({"uid": uid, "id": inst["id"], "rect": Rect2(origin + Vector2(lo) * CELL, Vector2(hi - lo + Vector2i.ONE) * CELL),
			"pull": (float(def.get("stats", {}).get("pull_radius", 0)) + TraitSet.pull_bonus(ship, uid)) * CELL})
	return out


## What collecting a piece of type `t` gives: cargo id -> units (a crate rolls here: once, and once more for each point of
## loot_bonus of the best crew member aboard `ship`, the finds adding up). {} for ice.
func _gains(t: Dictionary, ship = null) -> Dictionary:
	if t.has("roll"):
		var total := 0.0
		for o in t["roll"]:
			total += float(o["weight"])
		var got := {}
		for n in 1 + TraitSet.loot_bonus(ship):
			var x := rng.randf() * total
			var pick: Dictionary = t["roll"][-1]
			for o in t["roll"]:
				x -= float(o["weight"])
				if x < 0.0:
					pick = o
					break
			var id := str(pick["item"])
			got[id] = int(got.get(id, 0)) + rng.randi_range(int(pick["count"][0]), int(pick["count"][1]))
		return got
	var out := {}
	for id in t.get("yield", {}):
		out[str(id)] = int(t["yield"][id])
	return out


## Put `gains` in the hold (and an ice chunk's air in every room). False, and nothing changes, when the hold refuses.
func _store(ship, t: Dictionary, gains: Dictionary) -> bool:
	var units := 0
	for id in gains:
		if not (ship.components.has(id) or Content.has("items", id) or Content.has("materials", id)):
			return false
		units += int(gains[id])
	var limit := int(cfg.get("cargo_limit", 0))
	if limit > 0:
		var held := 0
		for id in ship.inventory.counts:
			held += int(ship.inventory.counts[id])
		if held + units > limit:
			return false
	for id in gains:
		ship.inventory.add(id, int(gains[id]))
		collected[id] = int(collected.get(id, 0)) + int(gains[id])
	var o2 := float(t.get("effect", {}).get("o2", 0.0))
	if o2 > 0.0:
		for room in ship.atmosphere.rooms:
			ship.atmosphere.add_oxygen(room["id"], o2 * float(room["size"]))
		collected["ice"] = int(collected.get("ice", 0)) + 1
	return true


func _note(mouth: Dictionary, t: Dictionary, gains: Dictionary) -> void:
	var text := "+%d%% O2" % roundi(float(t["effect"]["o2"]) * 100.0) if t.has("effect") else ""
	for id in gains:
		text = "+%d %s" % [gains[id], id]
	events.append({"kind": "collect", "pos": frame * mouth["rect"].get_center(), "text": text, "uid": mouth["uid"], "type": t["id"]})
	if events.size() > MAX_EVENTS:
		events.pop_front()


## Bounce piece `p` off every solid cell it touches: a tile (wall, floor, door) or any outside half. The mouth of a
## working intake is not solid (a piece that touches it is collected), unless the hold refused this piece. `inv` takes
## the piece into the ship's frame.
func _hull(ship, p: Dictionary, mouths: Array, inv: Transform2D) -> void:
	var o := _origin(ship)
	var r: float = p["r"]
	var lp: Vector2 = inv * p["pos"]
	var lo: Vector2 = ((lp - Vector2(r, r) - o) / CELL).floor()
	var hi: Vector2 = ((lp + Vector2(r, r) - o) / CELL).floor()
	for y in range(int(lo.y), int(hi.y) + 1):
		for x in range(int(lo.x), int(hi.x) + 1):
			var c := Vector2i(x, y)
			if _solid(ship, c) and (p["no_pull"] or not _open_mouth(ship, c, mouths)):
				_hit_local(p, Rect2(o + Vector2(c) * CELL, Vector2(CELL, CELL)), inv)


func _open_mouth(ship, c: Vector2i, mouths: Array) -> bool:
	var uid: int = ship.components.at_out(c)
	for m in mouths:
		if m["uid"] == uid:
			return true
	return false


func _solid(ship, c: Vector2i) -> bool:
	return ship.grid.get_tile(c) != "" or ship.components.at_out(c) >= 0


## Is a disc of radius `r` at world point `pos` touching a solid cell?
func _blocked_at(ship, pos: Vector2, r: float) -> bool:
	pos = frame.affine_inverse() * pos
	var o := _origin(ship)
	var lo := ((pos - Vector2(r, r) - o) / CELL).floor()
	var hi := ((pos + Vector2(r, r) - o) / CELL).floor()
	for y in range(int(lo.y), int(hi.y) + 1):
		for x in range(int(lo.x), int(hi.x) + 1):
			if _solid(ship, Vector2i(x, y)):
				return true
	return false


## _hit_rect() for `rect` in the ship's frame (`inv` takes a point there): the piece is moved into that frame, with its
## speed relative to the ship, bounced, and put back.
func _hit_local(p: Dictionary, rect: Rect2, inv: Transform2D) -> void:
	var pos: Vector2 = p["pos"]
	var vel: Vector2 = p["vel"]
	p["pos"] = inv * pos
	p["vel"] = inv.basis_xform(vel - frame_vel)
	if _hit_rect(p, rect):
		p["pos"] = frame * p["pos"]
		p["vel"] = frame.basis_xform(p["vel"]) + frame_vel
	else:
		p["pos"] = pos
		p["vel"] = vel


## Push piece `p` out of `rect` if it overlaps, and turn its speed if it was going in: part of it is kept
## (bounce.restitution) and some goes sideways, so a piece slides off the hull instead of sticking to it.
func _hit_rect(p: Dictionary, rect: Rect2) -> bool:
	var pos: Vector2 = p["pos"]
	var q := Vector2(clampf(pos.x, rect.position.x, rect.end.x), clampf(pos.y, rect.position.y, rect.end.y))
	var d := pos - q
	var dist := d.length()
	var r: float = p["r"]
	if dist >= r:
		return false
	var n := d / dist if dist > 0.001 else (pos - rect.get_center()).normalized()
	if n == Vector2.ZERO:
		n = Vector2.UP
	p["pos"] = pos + n * (r - dist)
	var vn: float = p["vel"].dot(n)
	if vn < 0.0:
		var b: Dictionary = cfg["bounce"]
		p["vel"] -= n * ((1.0 + float(b["restitution"])) * vn)
		p["vel"] += Vector2(-n.y, n.x) * (-vn * float(b["kick"]) * rng.randf_range(-1.0, 1.0))
		p["spin"] = rng.randf_range(-1.5, 1.5)
	return true


static func _dist_to_rect(pos: Vector2, rect: Rect2) -> float:
	return (pos - Vector2(clampf(pos.x, rect.position.x, rect.end.x), clampf(pos.y, rect.position.y, rect.end.y))).length()


static func _origin(ship) -> Vector2:
	return ship.world_pos - Vector2(ship.grid.size) * CELL / 2.0


# --- the HUD line --------------------------------------------------------------------------------------

## "Salvage: +12 scrap, +4 copper this trip", with a hint while no intake works and the way the current runs.
func hud_line() -> String:
	var parts: Array[String] = []
	var ids: Array = collected.keys()
	ids.sort_custom(func(a, b): return _rank(a) < _rank(b) or (_rank(a) == _rank(b) and a < b))
	for id in ids:
		parts.append("+%d %s" % [collected[id], id])
	var s := "Salvage: " + (", ".join(parts) if not parts.is_empty() else "nothing yet") + " this trip"
	if mouth_count == 0:
		s += " (no working intake: bolt a Net Mouth to an outer wall)"
	return s + "   current: " + compass()


static func _rank(id: String) -> int:
	var i := HUD_ORDER.find(id)
	return i if i >= 0 else HUD_ORDER.size()
