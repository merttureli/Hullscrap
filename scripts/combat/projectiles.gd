extends RefCounted
## Shots in flight, and the collision test every shot uses (hitscan lasers and beams too).
## A segment travelled is tested against each other ship: first its shield bubble (the sector it enters through), then its grid
## cells walked with a DDA, and in a shaped cell (slope, curve) the cell's real polygon. The earliest
## contact wins and the shot is spent there, unless the cell glanced it off (a ricochet or a deflect,
## see damage.gd): then it carries on reflected at half damage, and from then on it can hit any ship,
## the one that fired it included. Projectiles bounce up to MAX_BOUNCES times, lasers LASER_BOUNCES.
## Works on the arena (arena.gd): its `projectiles` list holds {owner, w, pos, vel, left, target,
## bounces, skip}; `skip` is the {ship, cell} a shot has just bounced off, which it ignores for one step.

const Damage = preload("res://scripts/combat/damage.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Drones = preload("res://scripts/combat/drones.gd")

const MAX_BOUNCES := 2
const LASER_BOUNCES := 1
const BOUNCE_LIFT := 0.3  ## px a bounced shot starts off the surface it left


## Launch a projectile of weapon `w` from the world point `origin` along the unit vector `dir`.
static func spawn(arena, owner: int, w: Dictionary, origin: Vector2, dir: Vector2) -> void:
	arena.projectiles.append({"owner": owner, "w": w, "pos": origin, "vel": dir * float(w["speed"]),
		"left": float(w["range"]), "target": _nearest_enemy(arena, owner, origin) if w["kind"] == "missile" else -1,
		"bounces": 0, "skip": {}})


## Move every projectile by `dt` seconds and collide it. Spent or expired ones are dropped.
static func step(arena, dt: float) -> void:
	var alive: Array = []
	for p in arena.projectiles:
		if p["target"] >= 0:
			_home(arena, p, dt)
		var from: Vector2 = p["pos"]
		var to: Vector2 = from + p["vel"] * dt
		p["pos"] = to
		p["left"] -= p["vel"].length() * dt
		var out := {}
		var spent := trace(arena, p["owner"], p["w"], from, to, out, {"bounces": p["bounces"], "skip": p["skip"]})
		p["skip"] = {}
		if spent:
			if out.has("bounce") and p["bounces"] < MAX_BOUNCES and p["left"] > 0.0:
				_rebound(p, out["bounce"])
				alive.append(p)
			continue
		if p["left"] > 0.0:
			alive.append(p)
	arena.projectiles = alive
	for sp in arena.fx["spawn"]:  # the shots a shield split this step fly on from the next one
		spawn(arena, sp[0], sp[1], sp[2], sp[3])
	arena.fx["spawn"].clear()


## Turn projectile `p` round on the bounce `b` (Damage.march): half the damage, the new heading, off the surface.
static func _rebound(p: Dictionary, b: Dictionary) -> void:
	p["bounces"] += 1
	p["w"] = bounced(p["w"], b)
	p["pos"] = b["pos"] + b["n"] * BOUNCE_LIFT
	p["vel"] = b["dir"] * p["vel"].length()
	p["skip"] = {"ship": b["ship"], "cell": b["cell"]}


## The weapon entry of a shot after bounce `b`: its damage and pierce as the bounce left them.
static func bounced(w: Dictionary, b: Dictionary) -> Dictionary:
	var out := w.duplicate()
	out["damage"] = b["dmg"]
	out["pierce"] = b["pierce"]
	return out


## A hitscan line (laser or beam tick) of weapon `w` from `from` to `to`, followed through its bounces
## (LASER_BOUNCES): the segments it travelled, each {from, to, shield, bounce (false for the first)}.
static func hitscan(arena, owner: int, w: Dictionary, from: Vector2, to: Vector2) -> Array:
	var segs: Array = []
	var ctx := {"bounces": 0, "skip": {}}
	var rest := from.distance_to(to)
	var cur := w
	var p0 := from
	var p1 := to
	while true:
		var out := {}
		trace(arena, owner, cur, p0, p1, out, ctx)
		segs.append({"from": p0, "to": out["end"], "shield": out["shield"], "bounce": ctx["bounces"] > 0})
		rest -= p0.distance_to(out["end"])
		if not out.has("bounce") or ctx["bounces"] >= LASER_BOUNCES or rest < 1.0:
			break
		var b: Dictionary = out["bounce"]
		ctx["bounces"] += 1
		ctx["skip"] = {"ship": b["ship"], "cell": b["cell"]}
		cur = bounced(cur, b)
		p0 = b["pos"] + b["n"] * BOUNCE_LIFT
		p1 = p0 + b["dir"] * rest
	return segs


## Send a shot of weapon `w` from `p0` to `p1` (world points). If it meets another ship the shield
## or cells there resolve it and this returns true; else false. `out` (optional) gets "end": where the
## shot stopped (`p1` when it met nothing), "shield": whether the bubble stopped it, and "bounce" when
## a cell glanced it off (Damage.march: {pos, n, dir, ship, cell, dmg, pierce}). `ctx`: {"bounces":
## how many times the shot has bounced (the shooter's own ship counts as a target once it has),
## "skip": {ship, cell} to ignore}.
static func trace(arena, owner: int, w: Dictionary, p0: Vector2, p1: Vector2, out := {}, ctx := {}) -> bool:
	var skip: Dictionary = ctx.get("skip", {})
	var own_target: bool = int(ctx.get("bounces", 0)) > 0
	var best := {}
	for i in arena.ships.size():
		if i == owner and not own_target:
			continue
		arena.sync(i)
		var hit := _contact(arena, i, w, p0, p1, skip)
		if not hit.is_empty() and (best.is_empty() or hit["t"] < best["t"]):
			best = hit
	var dh := Drones.contact(arena, owner, p0, p1) if not own_target else {}  # a drone the line crosses before it reaches a ship
	if not dh.is_empty() and (best.is_empty() or dh["t"] < best["t"]):
		out["end"] = p0.lerp(p1, dh["t"])
		out["shield"] = false
		Drones.hit_by_shot(arena, dh["drone"], w, owner)
		return true
	out["end"] = p1 if best.is_empty() else p0.lerp(p1, best["t"])
	out["shield"] = not best.is_empty() and best["shield"]
	if best.is_empty():
		return false
	if best["shield"]:
		Shields.absorb(arena, best["ship"], w, out["end"], (p1 - p0).normalized(), best["sector"])
		Effects.on_shield(arena, owner, best["ship"], w, out["end"], (p1 - p0).normalized())  # a shot that splits on the bubble
	else:
		var first := {}
		var res := Damage.march(arena, best["ship"], w, best["a"], best["b"], best["entries"], best["hit"], first)
		if res.has("bounce"):
			out["bounce"] = res["bounce"]
		if not first.is_empty() and w.get("effects") is Dictionary:  # the weapon's effects (acid, spores ...) land where it first hit
			Effects.on_hit(arena, owner, best["ship"], w, first)
	return true


## The first thing the segment meets on ship `i`: {} for nothing, else {ship, t (fraction of the
## segment), shield (and `sector`, the one it entered through), and for cells: entries (from the first cell hit on), a and b (the segment in
## ship-local cell coordinates) and hit ({t, n} of that cell, see Damage.cell_hit)}. A shaped cell
## the segment only crosses the empty part of does not count. `skip`: a {ship, cell} to ignore.
static func _contact(arena, i: int, w: Dictionary, p0: Vector2, p1: Vector2, skip := {}) -> Dictionary:
	var co = arena.ships[i]
	var a: Vector2 = arena.world_to_local(i, p0)
	var b: Vector2 = arena.world_to_local(i, p1)
	var entries := cells_along(a, b)
	var first := -1
	var hit := {}
	for k in entries.size():
		var cell: Vector2i = entries[k]["c"]
		if not skip.is_empty() and skip["ship"] == i and skip["cell"] == cell:
			continue
		if Damage.solid_at(co, cell).is_empty():
			continue
		hit = Damage.cell_hit(co, cell, a, b, entries[k])
		if not hit.is_empty():
			first = k
			break
	var t_cell: float = hit["t"] if first >= 0 else INF
	var t_shield := INF
	var hit_sector := -1
	if Shields.blocks(co, w):
		var ts := Shields.entry_t(co, a, b)
		if ts >= 0.0:
			var s := Shields.sector_of(co, a.lerp(b, ts) - co.pivot)
			if Shields.stops(co, s, w, arena.tick):
				t_shield = ts
				hit_sector = s
	if first < 0 and t_shield == INF:
		return {}
	if t_shield <= t_cell:
		return {"ship": i, "t": t_shield, "shield": true, "sector": hit_sector}
	return {"ship": i, "t": t_cell, "shield": false, "entries": entries.slice(first), "a": a, "b": b, "hit": hit}


## The cells the segment a -> b (cell coordinates) passes through, in order, as
## {"c": cell, "t": fraction of the segment where it is entered, "n": unit normal of the face it
## was entered through, pointing back toward where the shot came from (zero for the first cell)}.
## Amanatides-Woo DDA; a tie between x and y steps takes the x step first.
static func cells_along(a: Vector2, b: Vector2) -> Array:
	var cell := Vector2i(floori(a.x), floori(a.y))
	var out: Array = [{"c": cell, "t": 0.0, "n": Vector2.ZERO}]
	var d := b - a
	var step := Vector2i(int(signf(d.x)), int(signf(d.y)))
	var t_max := Vector2(INF, INF)
	var t_delta := Vector2(INF, INF)
	if step.x != 0:
		t_max.x = (float(cell.x + (1 if step.x > 0 else 0)) - a.x) / d.x
		t_delta.x = absf(1.0 / d.x)
	if step.y != 0:
		t_max.y = (float(cell.y + (1 if step.y > 0 else 0)) - a.y) / d.y
		t_delta.y = absf(1.0 / d.y)
	while true:
		if t_max.x <= t_max.y:
			if t_max.x > 1.0:
				break
			cell.x += step.x
			out.append({"c": cell, "t": t_max.x, "n": Vector2(-step.x, 0)})
			t_max.x += t_delta.x
		else:
			if t_max.y > 1.0:
				break
			cell.y += step.y
			out.append({"c": cell, "t": t_max.y, "n": Vector2(0, -step.y)})
			t_max.y += t_delta.y
	return out


## Index of the nearest ship that is not `owner` and not wrecked, by distance from `from`; -1 if none.
static func _nearest_enemy(arena, owner: int, from: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in arena.ships.size():
		if i == owner or arena.ships[i].wrecked:
			continue
		var d: float = from.distance_squared_to(arena.ships[i].flight.pos)
		if d < best_d:
			best_d = d
			best = i
	return best


## Turn a missile toward its target ship, at most `turn` rad/s.
static func _home(arena, p: Dictionary, dt: float) -> void:
	var want: Vector2 = arena.ships[p["target"]].flight.pos - p["pos"]
	if want.length_squared() < 1e-6:
		return
	var cur: float = p["vel"].angle()
	var limit: float = float(p["w"]["turn"]) * dt
	p["vel"] = Vector2.from_angle(cur + clampf(angle_difference(cur, want.angle()), -limit, limit)) * p["vel"].length()
