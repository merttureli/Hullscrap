extends RefCounted
## Magnetic limpets and boarder pods (docs/DRONES.md sections 4 to 6), headless. They are drones in `arena.drones` with role "limpet" or "boarder" (drones.gd launches
## and steps them). A kit is thrown out of the bay's hatch toward the aim point at its launch speed; then the target ship's magnet works on it: an acceleration
## pull / max(d, d0)^2 (d in cells, to the nearest hull point; pull in cells^3/s2) toward that hull point, its heading turning at no more than `turn` rad/s and its
## speed capped, so a shot aimed wide curls round to a side or the back room, and one aimed far too wide drifts off (lost: the part is spent). It passes shields
## (it is no projectile), has 2-3 hp (limpet) or 4-6 (pod) which point defence, flak and turrets take (drones.gd), and sticks to the first exposed hull cell it
## touches. A limpet then works on the room behind that wall (the nearest room inside, through wall cells) for its seconds, and falls off when they are up, when its
## cell is gone, or when a crew member scrapes it off (the `scrape` job, crew.json jobs.scrape: 85, 6 s). A pod drills a breach in that cell (the room vents until it
## is patched) and drops its robots into the room behind (Intruders.spawn); the husk then falls away.
## A flying one is {state "flying", pos, vel, magnet, target (ship idx), ...}; stuck: {state "stuck", cell, local (where it sits, cell coordinates), room, rcell
## (a cell of the room behind), until/next (ticks), phase}; falling off: {state "fall", t0}. All randomness is the arena's rng.

const Collisions = preload("res://scripts/combat/collisions.gd")
const Fire = preload("res://scripts/sim/fire.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const Intruders = preload("res://scripts/crew/intruders.gd")

const ROLES := ["limpet", "boarder"]
const COARSE := 48  ## the magnet pulls toward at most this many hull points (a subsample of the exposed cells)
const MAX_FLIGHT_S := 8.0  ## a flight longer than this is lost
const LOST_DIST := 3600.0  ## px from the target's middle: past it with the pull no longer closing, it is lost
const FALL_S := 1.1  ## the husk falls away this long
const ROOM_DEPTH := 6  ## cells of wall a limpet's room behind is looked for through
const FIRST_PULSE_S := 0.6
const PREDICT_S := 3.0
const SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func is_limpet(d: Dictionary) -> bool:
	return str(d["role"]) in ROLES


# --- the magnet --------------------------------------------------------------------------------

## The hull points the magnet pulls toward, ship-local px from the pivot: a subsample of the exposed cells' centres (cached with the hit cells).
static func points(arena, t: int) -> Array:
	var hc: Dictionary = Collisions.hit_cells(arena, t)
	if not hc.has("coarse"):
		var cells: Array = hc["cells"]
		var stride := maxi(1, int(ceil(float(cells.size()) / float(COARSE))))
		var out := []
		for i in range(0, cells.size(), stride):
			out.append(hc["info"][cells[i]]["ctr"])
		if out.is_empty():
			out.append(Vector2.ZERO)
		hc["coarse"] = out
	return hc["coarse"]


## One step of the magnet: position and velocity `p`, `v` (world px, px/s) after `dt` seconds, the hull points `pts` already in the world. Returns [p, v].
static func advance(p: Vector2, v: Vector2, pts: Array, m: Dictionary, dt: float, cell: float) -> Array:
	var q: Vector2 = pts[0]
	var best := INF
	for x in pts:
		var dd := p.distance_squared_to(x)
		if dd < best:
			best = dd
			q = x
	var d := sqrt(best) / cell
	var acc := float(m["pull"]) / pow(maxf(d, float(m["d0"])), 2.0) * cell
	var nv: Vector2 = v + (q - p).normalized() * acc * dt
	var turn := float(m["turn"]) * dt
	var ang := v.angle_to(nv)
	if absf(ang) > turn and v.length() > 1.0:  # the course turns with the pull, never in one snap
		nv = v.rotated(signf(ang) * turn).normalized() * nv.length()
	if nv.length() > float(m["cap"]):
		nv = nv.normalized() * float(m["cap"])
	return [p + nv * dt, nv]


static func _world_pts(local: Array, pos: Vector2, angle: float) -> Array:
	var out := []
	for l in local:
		out.append(pos + (l as Vector2).rotated(angle))
	return out


## The first exposed hull cell of ship `t` on the way from `a` to `b` (world px): {cell, at (world)} or {}.
static func hull_hit(arena, t: int, a: Vector2, b: Vector2) -> Dictionary:
	var info: Dictionary = Collisions.hit_cells(arena, t)["info"]
	var co = arena.ships[t]
	for k in 3:
		var p := a.lerp(b, float(k + 1) / 3.0)
		var l: Vector2 = (p - co.flight.pos).rotated(-co.flight.angle) / arena.CELL + co.pivot
		var c := Vector2i(floori(l.x), floori(l.y))
		if info.has(c):
			return {"cell": c, "at": p}
	return {}


## Where a kit thrown from `hatch` (world) toward `aim` would fly: {path: PackedVector2Array (a point every `every` steps), end ("hit", "lost" or "time"), cell, t}.
## The same integration as the flight, the target ship carried along at its velocity.
static func predict(arena, owner: int, hatch: Vector2, aim: Vector2, spec: Dictionary, every := 6, seconds := PREDICT_S) -> Dictionary:
	var t: int = arena.weapons.target_of(arena, owner)
	var out := {"path": PackedVector2Array(), "end": "time", "cell": Vector2i(-1, -1), "t": 0.0}
	if t < 0:
		return out
	var m: Dictionary = spec["magnet"]
	var co = arena.ships[t]
	var me = arena.ships[owner]
	var local: Array = points(arena, t)
	var dir := (aim - hatch).normalized()
	var p := hatch
	var v: Vector2 = dir * float(m["launch"]) + me.flight.vel
	var dt: float = arena.SUBSTEP
	var tpos: Vector2 = co.flight.pos
	var pts := _world_pts(local, tpos, co.flight.angle)
	var n := int(seconds / dt)
	out["path"].append(p)
	for i in n:
		var shift: Vector2 = co.flight.vel * dt
		tpos += shift
		for k in pts.size():
			pts[k] = (pts[k] as Vector2) + shift
		var r := advance(p, v, pts, m, dt, arena.CELL)
		var hit := _hit_at(arena, t, tpos, co.flight.angle, p, r[0])
		p = r[0]
		v = r[1]
		if i % every == 0:
			out["path"].append(p)
		if not hit.is_empty():
			out["end"] = "hit"
			out["cell"] = hit["cell"]
			out["t"] = float(i) * dt
			out["path"].append(hit["at"])
			return out
		if p.distance_to(tpos) > LOST_DIST:
			out["end"] = "lost"
			break
	out["path"].append(p)
	return out


static func _hit_at(arena, t: int, tpos: Vector2, angle: float, a: Vector2, b: Vector2) -> Dictionary:
	var info: Dictionary = Collisions.hit_cells(arena, t)["info"]
	var co = arena.ships[t]
	for k in 3:
		var p := a.lerp(b, float(k + 1) / 3.0)
		var l: Vector2 = (p - tpos).rotated(-angle) / arena.CELL + co.pivot
		var c := Vector2i(floori(l.x), floori(l.y))
		if info.has(c):
			return {"cell": c, "at": p}
	return {}


# --- launching ---------------------------------------------------------------------------------

## Fill in the flight fields of a freshly launched limpet or pod `d` thrown toward the world point `aim`.
static func start(arena, d: Dictionary, hatch: Vector2, aim: Vector2, owner_vel: Vector2) -> void:
	var m: Dictionary = d["spec"]["magnet"]
	var dir := (aim - hatch).normalized() if aim.distance_to(hatch) > 1.0 else Vector2.UP
	d["magnet"] = m
	d["vel"] = dir * float(m["launch"]) + owner_vel
	d["angle"] = dir.angle() + PI / 2.0
	d["state"] = "flying"
	d["target"] = arena.weapons.target_of(arena, int(d["owner"]))
	d["aim"] = aim
	d["orbit"] = {"speed": float(m["launch"]), "gap": 0.0}


# --- the step ----------------------------------------------------------------------------------

## Advance limpet or pod `d` one substep. Returns false when it is gone (the caller drops it).
static func step(arena, d: Dictionary, dt: float) -> bool:
	match str(d["state"]):
		"flying", "home":
			return _fly(arena, d, dt)
		"stuck":
			return _work(arena, d, dt)
		"fall":
			d["pos"] = Vector2(d["pos"]) + Vector2(d["vel"]) * dt
			return float(arena.tick - int(d["t0"])) * dt < FALL_S
	return false


static func _free_bay(arena, d: Dictionary) -> void:
	var co = arena.ships[d["owner"]]
	var b: Dictionary = co.bays.get(d["bay"], {})
	if not b.is_empty() and b["drone"] == d:
		b["drone"] = null
		b["ready"] = arena.tick + int(ceil(arena.Drones.rearm_s(arena, d["owner"], d["bay"]) / arena.SUBSTEP - 1e-6))


static func _fly(arena, d: Dictionary, dt: float) -> bool:
	var t: int = d["target"]
	if t < 0 or arena.ships[t].wrecked:
		_lose(arena, d)
		return false
	var co = arena.ships[t]
	var pts := _world_pts(points(arena, t), co.flight.pos, co.flight.angle)
	var r := advance(d["pos"], d["vel"], pts, d["magnet"], dt, arena.CELL)
	var hit := hull_hit(arena, t, d["pos"], r[0])
	d["pos"] = r[0]
	d["vel"] = r[1]
	d["angle"] = Vector2(r[1]).angle() + PI / 2.0
	if not hit.is_empty():
		_stick(arena, d, t, hit["cell"])
		return d["state"] != "gone"
	if float(arena.tick - int(d["born"])) * dt > MAX_FLIGHT_S or (Vector2(d["pos"]).distance_to(co.flight.pos) > LOST_DIST and Vector2(d["vel"]).dot(co.flight.pos - Vector2(d["pos"])) < 0.0):
		_lose(arena, d)
		return false
	return true


static func _lose(arena, d: Dictionary) -> void:
	_free_bay(arena, d)
	arena.log_event("limpet_lost", d["owner"], Vector2i(-1, -1), {"drone": d["id"], "pos": d["pos"], "kit": d["kit"]})


## The room behind hull cell `c` of `ship`: {room, rcell} (the nearest room inside, searched through wall cells, `depth` deep), or {}.
static func room_behind(ship, c: Vector2i, depth := ROOM_DEPTH) -> Dictionary:
	var atm = ship.atmosphere
	var seen := {c: 0}
	var queue: Array[Vector2i] = [c]
	var i := 0
	while i < queue.size():
		var cur: Vector2i = queue[i]
		i += 1
		var r: int = atm.room_at(cur)
		if r >= 0:
			return {"room": r, "rcell": cur}
		if int(seen[cur]) >= depth:
			continue
		for s in SIDES:
			var n: Vector2i = cur + s
			if seen.has(n) or not (ship.grid.tiles.has(n) or ship.components.at(n) >= 0):
				continue
			seen[n] = int(seen[cur]) + 1
			queue.append(n)
	return {}


static func _stick(arena, d: Dictionary, t: int, cell: Vector2i) -> void:
	var co = arena.ships[t]
	var behind := room_behind(co.ship, cell)
	var spec: Dictionary = d["spec"]
	_free_bay(arena, d)
	if behind.is_empty():  # nothing inside to work on: it clamps on, finds no room, and falls
		d["state"] = "gone"
		arena.log_event("limpet_off", d["owner"], Vector2i(-1, -1), {"drone": d["id"], "pos": d["pos"], "why": "no room"})
		return
	var ctr: Vector2 = Vector2(cell) + Vector2(0.5, 0.5)
	var out: Vector2 = (Vector2(d["pos"]) - arena.local_to_world(t, ctr)).rotated(-co.flight.angle).normalized()
	d["state"] = "stuck"
	d["cell"] = cell
	d["target"] = t
	d["local"] = ctr + out * (1.3 if str(d["role"]) == "boarder" else 0.62)
	d["face"] = (-out).angle()  # (a pod's nose turned into the wall, ship-local)
	d["room"] = behind["room"]
	d["rcell"] = behind["rcell"]
	d["stuck_tick"] = arena.tick
	d["hit_tick"] = -1000000
	var eff: Dictionary = spec.get("effect", {})
	var secs := float(eff.get("seconds", 0.0))
	if str(d["role"]) == "boarder":
		secs = float(spec.get("breach_s", 2.4))
	d["until"] = arena.tick + int(secs / arena.SUBSTEP)
	d["next"] = arena.tick + int(FIRST_PULSE_S / arena.SUBSTEP)
	d["pos"] = arena.local_to_world(t, d["local"])
	d["vel"] = Vector2.ZERO
	co.ship.stuck.append(d)
	var room_name: String = Fire.room_name(co.ship, int(d["room"]))
	if str(d["role"]) == "limpet":
		co.ship.log_event("A %s stuck to the wall of the %s" % [str(d["name"]).to_lower(), room_name])
	arena.log_event("limpet_stick", d["owner"], cell, {"drone": d["id"], "pos": d["pos"], "kit": d["kit"], "ship": t})


static func _fall(arena, d: Dictionary, why: String) -> void:
	var t: int = d["target"]
	var co = arena.ships[t]
	co.ship.stuck.erase(d)
	d["state"] = "fall"
	d["t0"] = arena.tick
	d["vel"] = Vector2.from_angle(float(d["angle"]) - PI / 2.0).rotated(1.0) * 30.0 + co.flight.vel
	arena.log_event("limpet_off", d["owner"], Vector2i(-1, -1), {"drone": d["id"], "pos": d["pos"], "why": why, "kit": d["kit"]})


## A stuck limpet or pod at work.
static func _work(arena, d: Dictionary, dt: float) -> bool:
	var t: int = d["target"]
	var co = arena.ships[t]
	d["pos"] = arena.local_to_world(t, d["local"])
	d["angle"] = float(d["face"]) + co.flight.angle + PI / 2.0
	if co.wrecked:
		co.ship.stuck.erase(d)
		return false
	if not _cell_holds(co, d["cell"]):
		_fall(arena, d, "cell destroyed")
		return true
	if bool(d.get("scraped", false)):
		co.ship.log_event("A %s was scraped off" % str(d["name"]).to_lower())
		_fall(arena, d, "scraped")
		return true
	if str(d["role"]) == "boarder":
		if arena.tick >= int(d["until"]):
			_breach(arena, d, t)
			_fall(arena, d, "delivered")
		return true
	var eff: Dictionary = d["spec"]["effect"]
	var ship = co.ship
	var room: int = ship.atmosphere.room_at(d["rcell"])
	if room < 0:
		room = int(d["room"])
	match str(eff["kind"]):
		"fire":
			if arena.tick >= int(d["next"]):
				d["next"] = arena.tick + int(float(eff["every"]) / arena.SUBSTEP)
				var cells: Array = ship.atmosphere.rooms[room]["cells"]
				for i in int(eff.get("cells", 1)):
					Fire.ignite(ship, cells[arena.rng.randi_range(0, cells.size() - 1)])
		"poison":
			_poison(ship, room, eff, dt)
		"heat":
			_heat(ship, room, float(eff["rate"]) * dt)
	if arena.tick >= int(d["until"]):
		_fall(arena, d, "spent")
	return true


## Is hull cell `c` of `co` still solid (not breached, not wrecked away)?
static func _cell_holds(co, c: Vector2i) -> bool:
	return co.ship.grid.tiles.has(c) or co.ship.components.at(c) >= 0


## Poison: the crew in room `room` take dps hp a second (a suit, a species that needs no air and its poison factor stop it) and the room's air drains.
static func _poison(ship, room: int, eff: Dictionary, dt: float) -> void:
	var atm = ship.atmosphere
	atm.consume(room, float(eff["o2_drain"]) * dt * float(atm.rooms[room]["size"]))
	for m in ship.crew:
		if m.is_down() or atm.room_at(m.cell()) != room:
			continue
		var tr := TraitSet.of(m)
		if tr["vacuum_walk"] or float(tr["o2_use"]) <= 0.0:
			continue
		m.hurt(float(eff["dps"]) * float(tr["damage_taken"]["poison"]) * dt)


## Heat: every part in room `room` gains `amount` heat (it trips at its heat_limit, heat.gd).
static func _heat(ship, room: int, amount: float) -> void:
	for uid in ship.components.instances:
		var inst: Dictionary = ship.components.instances[uid]
		if ship.atmosphere.room_at(inst["anchor"]) == room:
			inst["heat"] = minf(float(inst["heat"]) + amount, float(ship.effective(inst["id"])["heat_limit"]))


## The pod breaches its wall cell and drops its robots into the room behind.
static func _breach(arena, d: Dictionary, t: int) -> void:
	var co = arena.ships[t]
	var ship = co.ship
	var cell: Vector2i = d["cell"]
	if ship.grid.tiles.has(cell) and ship.components.at(cell) < 0:
		var tile: String = ship.grid.breach(cell)
		if tile != "":
			ship.mark_dirty()
			co.dirty = true
			arena.log_event("breach", t, cell, {"tile": tile})
	ship.refresh()
	var room: int = ship.atmosphere.room_at(d["rcell"])
	var near := Vector2(d["rcell"]) + Vector2(0.5, 0.5)
	var name := Fire.room_name(ship, room) if room >= 0 else "hull"
	for sp in d["spec"]["robots"]:
		Intruders.spawn(ship, str(sp), near, arena.rng)
	ship.log_event("A boarding robot cut in at the %s" % name)
	arena.log_event("pod_breach", d["owner"], cell, {"drone": d["id"], "pos": d["pos"], "ship": t, "robots": d["spec"]["robots"].size()})


## The end of the fight: nothing stays stuck to a hull.
static func clear(arena) -> void:
	for co in arena.ships:
		co.ship.stuck.clear()


# --- the enemy's aim ---------------------------------------------------------------------------

## Where ship `idx`'s pilot throws kit `spec` from `hatch` at ship `foe`: it looks at a few aims (the middle, then wider each side), predicts each, and prefers one that
## lands on the side or back of the foe; `skill` (0..1) is how often it picks the best, else the front or a poorer one. Returns a world point.
static func ai_aim(arena, idx: int, hatch: Vector2, spec: Dictionary, skill: float) -> Vector2:
	var foe: int = arena.weapons.target_of(arena, idx)
	var fc = arena.ships[foe]
	var to: Vector2 = fc.flight.pos - hatch
	var lead: Vector2 = fc.flight.pos + fc.flight.vel * (to.length() / maxf(float(spec["magnet"]["launch"]), 1.0))
	var base := (lead - hatch).angle()
	var best_a := base
	var best_score := -INF
	var options := []
	for deg in [-50, -38, -26, -14, 0, 14, 26, 38, 50]:
		var a := base + deg_to_rad(float(deg))
		var aim := hatch + Vector2.from_angle(a) * 600.0
		var r := predict(arena, idx, hatch, aim, spec, 12, 4.0)
		var score := -1.0
		if r["end"] == "hit":
			var l: Vector2 = Vector2(r["cell"]) + Vector2(0.5, 0.5) - fc.pivot  # cells from the pivot, ship-local
			var dirw: Vector2 = (hatch - fc.flight.pos).rotated(-fc.flight.angle)  # the way the shooter lies, ship-local
			var side := 1.0 - maxf(0.0, l.normalized().dot(dirw.normalized()))  # 0 = the face toward us, 1 = away or abeam
			score = 0.4 + side
		options.append([score, a])
		if score > best_score:
			best_score = score
			best_a = a
	if best_score < 0.0 or arena.rng.randf() > skill:  # a poor throw: a random one of the options
		best_a = options[arena.rng.randi_range(0, options.size() - 1)][1]
	return hatch + Vector2.from_angle(best_a) * 600.0
