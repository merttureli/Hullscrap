extends RefCounted
## Shield bubbles. An ellipse around the hull's bounding box (plus a margin) with `layers` taken
## from the powered shield components. A hit on the bubble uses a layer and stops the shot; each
## used layer recharges RECHARGE seconds later. Missiles pass. An ion hit also locks the shields
## for ION_LOCK seconds: they stop nothing and do not recharge meanwhile. Works on arena
## combatants (see arena.gd) and is deterministic: no randomness here.

const RECHARGE := 2.0  ## seconds until a used layer is back
const ION_LOCK := 3.0  ## seconds an ion hit keeps the shields offline
const MARGIN := 1.0  ## cells between the hull's bounding box and the bubble


## Layers the ship's powered, working shield components give (power comes from `co.powered`).
static func layers_max(co) -> int:
	var total := 0
	var comps = co.ship.components
	for uid in comps.instances:
		if co.powered.get(uid, false):
			var d: Dictionary = comps.def(comps.instances[uid]["id"])
			if d.get("family", "") == "shield":
				total += int(d.get("stats", {}).get("layers", 0))
	return total


## Re-read the layer cap after power changed: new capacity arrives full, lost capacity is dropped.
static func resync(co) -> void:
	var cap := 0 if co.wrecked else layers_max(co)
	if cap > co.layers_cap:
		co.layers += cap - co.layers_cap
	co.layers_cap = cap
	co.layers = mini(co.layers, cap)
	while co.layers + co.shield_timers.size() > cap and not co.shield_timers.is_empty():
		co.shield_timers.pop_back()


## Does the bubble stop shots of weapon `w` right now?
static func blocks(co, w: Dictionary) -> bool:
	return co.layers > 0 and co.ion_lock <= 0.0 and not co.wrecked and not bool(w.get("pass_shields", false))


## Semi-axes of the bubble in cells (half the hull bounding box plus the margin).
static func axes(co) -> Vector2:
	return co.half + Vector2(MARGIN, MARGIN)


## Where the segment a -> b (ship-local cell coordinates) first enters the bubble, as a fraction
## 0..1 of the segment; -1 when it does not, or when it starts inside (it is through already).
static func entry_t(co, a: Vector2, b: Vector2) -> float:
	var ax := axes(co)
	var p: Vector2 = (a - co.pivot) / ax
	var d: Vector2 = (b - co.pivot) / ax - p
	var qc := p.dot(p) - 1.0
	var qa := d.dot(d)
	if qc <= 0.0 or qa < 1e-12:
		return -1.0
	var qb := 2.0 * p.dot(d)
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return -1.0
	var t := (-qb - sqrt(disc)) / (2.0 * qa)
	return t if t >= 0.0 and t <= 1.0 else -1.0


## A shot of weapon `w` hits the bubble of ship `idx`: one layer is used up (and, for ion, the
## shields lock).
static func absorb(arena, idx: int, w: Dictionary) -> void:
	var co = arena.ships[idx]
	co.layers -= 1
	co.shield_timers.append(RECHARGE)
	if w.get("damage_type", "") == "ion":
		co.ion_lock = ION_LOCK
		arena.log_event("ion_lock", idx)
	arena.log_event("shield", idx, Vector2i(-1, -1), {"layers": co.layers})


## Advance recharge and the ion lock by `dt` seconds.
static func tick(co, dt: float) -> void:
	if co.wrecked:
		return
	if co.ion_lock > 0.0:
		co.ion_lock = maxf(co.ion_lock - dt, 0.0)
		return
	var left: Array[float] = []
	for t in co.shield_timers:
		if t - dt <= 1e-9:
			co.layers = mini(co.layers + 1, co.layers_cap)
		else:
			left.append(t - dt)
	co.shield_timers = left
