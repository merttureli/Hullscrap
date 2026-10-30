extends RefCounted
## Shots in flight, and the collision test every shot uses (hitscan lasers and beams too).
## A segment travelled is tested against each other ship: first its shield bubble, then its grid
## cells walked with a DDA. The earliest contact wins and the shot is spent there. Works on the
## arena (arena.gd): its `projectiles` list holds {owner, w, pos, vel, left, target}.

const Damage = preload("res://scripts/combat/damage.gd")
const Shields = preload("res://scripts/combat/shields.gd")


## Launch a projectile of weapon `w` from the world point `origin` along the unit vector `dir`.
static func spawn(arena, owner: int, w: Dictionary, origin: Vector2, dir: Vector2) -> void:
	arena.projectiles.append({"owner": owner, "w": w, "pos": origin, "vel": dir * float(w["speed"]),
		"left": float(w["range"]), "target": _nearest_enemy(arena, owner, origin) if w["kind"] == "missile" else -1})


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
		if trace(arena, p["owner"], p["w"], from, to):
			continue
		if p["left"] > 0.0:
			alive.append(p)
	arena.projectiles = alive


## Send a shot of weapon `w` from `p0` to `p1` (world points). If it meets another ship the shield
## or cells there resolve it and this returns true; else false. `out` (optional) gets "end": where the
## shot stopped (`p1` when it met nothing) and "shield": whether the bubble stopped it.
static func trace(arena, owner: int, w: Dictionary, p0: Vector2, p1: Vector2, out := {}) -> bool:
	var best := {}
	for i in arena.ships.size():
		if i == owner:
			continue
		arena.sync(i)
		var hit := _contact(arena, i, w, p0, p1)
		if not hit.is_empty() and (best.is_empty() or hit["t"] < best["t"]):
			best = hit
	out["end"] = p1 if best.is_empty() else p0.lerp(p1, best["t"])
	out["shield"] = not best.is_empty() and best["shield"]
	if best.is_empty():
		return false
	if best["shield"]:
		Shields.absorb(arena, best["ship"], w, out["end"], (p1 - p0).normalized())
	else:
		Damage.march(arena, best["ship"], w, best["entries"], best["dir"])
	return true


## The first thing the segment meets on ship `i`: {} for nothing, else {ship, t (fraction of the
## segment), shield, and for cells: entries (from the first solid cell on) and dir (ship-local)}.
static func _contact(arena, i: int, w: Dictionary, p0: Vector2, p1: Vector2) -> Dictionary:
	var co = arena.ships[i]
	var a: Vector2 = arena.world_to_local(i, p0)
	var b: Vector2 = arena.world_to_local(i, p1)
	var entries := cells_along(a, b)
	var first := -1
	for k in entries.size():
		if not Damage.solid_at(co, entries[k]["c"]).is_empty():
			first = k
			break
	var t_cell: float = entries[first]["t"] if first >= 0 else INF
	var t_shield := INF
	if Shields.blocks(co, w):
		var ts := Shields.entry_t(co, a, b)
		if ts >= 0.0 and not Shields.sector_open(co, Shields.sector_of(co, a.lerp(b, ts) - co.pivot), arena.tick):
			t_shield = ts
	if first < 0 and t_shield == INF:
		return {}
	if t_shield <= t_cell:
		return {"ship": i, "t": t_shield, "shield": true}
	return {"ship": i, "t": t_cell, "shield": false, "entries": entries.slice(first), "dir": (b - a).normalized()}


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
