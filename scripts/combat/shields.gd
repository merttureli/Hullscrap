extends RefCounted
## Shield bubbles. An ellipse around the hull's bounding box (plus a margin) with `layers` taken
## from the powered shield components (one shared pool). A hit on the bubble uses a layer and stops
## the shot; each used layer recharges RECHARGE seconds later. Missiles pass. An ion hit also locks
## the shields for ION_LOCK seconds: they stop nothing and do not recharge meanwhile.
## The bubble is split into N equal sectors round the ship's centre, sector 0 centred on the bow (N =
## the best powered generator's `stats.sectors`, default 1). Firing opens the sector the shot leaves
## through for the weapon's drop time (see drop_seconds): shots pass an open sector and use no layer.
## An overcharge adds one layer for OVERCHARGE_S seconds, then needs OVERCHARGE_COOLDOWN to rest.
## Works on arena combatants (see arena.gd) and is deterministic: no randomness here.

const RECHARGE := 2.0  ## seconds until a used layer is back
const ION_LOCK := 3.0  ## seconds an ion hit keeps the shields offline
const MARGIN := 1.0  ## cells between the hull's bounding box and the bubble
const OVERCHARGE_S := 6.0  ## seconds the extra layer lasts
const OVERCHARGE_COOLDOWN := 15.0  ## seconds after the extra layer ends before the next one
## Seconds a shot opens its sector, by weapon kind (and for ion damage). A beam opens it for its whole
## duration; a missile never does. A weapon entry's own `drops_shield_s` wins.
const DROP := {"laser": 0.3, "bolt": 0.4, "flak": 0.6, "ion": 0.3}


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


## Sectors of the bubble: the largest `stats.sectors` among the powered shield components (1 if none says).
static func sectors_of(co) -> int:
	var best := 1
	var comps = co.ship.components
	for uid in comps.instances:
		if co.powered.get(uid, false):
			var d: Dictionary = comps.def(comps.instances[uid]["id"])
			if d.get("family", "") == "shield":
				best = maxi(best, int(d.get("stats", {}).get("sectors", 1)))
	return best


## Re-read the layer cap and the sector count after power changed: new capacity arrives full, lost
## capacity is dropped. The overcharge layer counts while it lasts and a generator is up.
static func resync(co) -> void:
	var base := 0 if co.wrecked else layers_max(co)
	var cap := base + (1 if co.overcharge_left > 0.0 and base > 0 else 0)
	if cap > co.layers_cap:
		co.layers += cap - co.layers_cap
	co.layers_cap = cap
	co.layers = mini(co.layers, cap)
	while co.layers + co.shield_timers.size() > cap and not co.shield_timers.is_empty():
		co.shield_timers.pop_back()
	co.sectors = sectors_of(co)


## Does the bubble stop shots of weapon `w` right now (a layer is up, no ion lock)? Which sector the
## shot crosses, and whether that one is open, is sector_open()'s business.
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


## The sector (0..sectors-1) of `v`, a vector from the ship's centre in ship-local coordinates.
## Sector 0 is centred on the bow (local up); sectors count clockwise on screen.
static func sector_of(co, v: Vector2) -> int:
	var n: int = co.sectors
	if n <= 1 or v.length_squared() < 1e-12:
		return 0
	return posmod(floori((atan2(v.x, -v.y) + PI / n) / (TAU / n)), n)


## The sector of a world direction seen from ship `co` (turned by its heading).
static func sector_of_world_dir(co, dir: Vector2) -> int:
	return sector_of(co, dir.rotated(-co.flight.angle))


## The sector a shot leaves through: from `a` (ship-local cell coordinates, normally inside the
## bubble) along `d` to where it crosses the bubble. From outside the bubble the direction itself counts.
static func outgoing_sector(co, a: Vector2, d: Vector2) -> int:
	var ax := axes(co)
	var p: Vector2 = (a - co.pivot) / ax
	var q: Vector2 = d / ax
	var qc := p.dot(p) - 1.0
	var qa := q.dot(q)
	if qc > 0.0 or qa < 1e-12:
		return sector_of(co, d)
	var qb := 2.0 * p.dot(q)
	var t := (-qb + sqrt(maxf(qb * qb - 4.0 * qa * qc, 0.0))) / (2.0 * qa)
	return sector_of(co, a + d * t - co.pivot)


## Is sector `s` open (shots pass) on arena tick `tick`?
static func sector_open(co, s: int, tick: int) -> bool:
	var w = co.sector_open.get(s)
	return w != null and tick >= w.x and tick <= w.y


## Open state of every sector of ship `co` on `tick`.
static func open_sectors(co, tick: int) -> Array:
	var out := []
	for s in co.sectors:
		out.append(sector_open(co, s, tick))
	return out


## Seconds a shot of weapon `w` opens its sector: 0 for a missile, else `drops_shield_s` if the
## entry has it, else the beam's duration or the DROP default of the kind (ion damage counts as ion).
static func drop_seconds(w: Dictionary) -> float:
	var kind := str(w.get("kind", "laser"))
	if kind == "missile":
		return 0.0
	if w.has("drops_shield_s"):
		return maxf(0.0, float(w["drops_shield_s"]))
	if kind == "beam":
		return float(w.get("duration", 2.0))
	if w.get("damage_type", "") == "ion":
		return float(DROP["ion"])
	return float(DROP.get(kind, 0.0))


## Ship `idx` fired weapon `w` from the world point `origin` along the unit vector `dir`: the sector
## the shot leaves through opens from the next tick for drop_seconds(w). Shots already in contact
## this tick were resolved before. Overlapping windows of a sector run to the latest end.
static func drop(arena, idx: int, w: Dictionary, origin: Vector2, dir: Vector2) -> void:
	var secs := drop_seconds(w)
	if secs <= 0.0:
		return
	var co = arena.ships[idx]
	var s := outgoing_sector(co, arena.world_to_local(idx, origin), dir.rotated(-co.flight.angle))
	var from: int = arena.tick + 1
	var until: int = arena.tick + ceili(secs / arena.SUBSTEP - 1e-6)
	var cur = co.sector_open.get(s)
	if cur != null and cur.y >= arena.tick:
		from = mini(cur.x, from)
		until = maxi(cur.y, until)
	co.sector_open[s] = Vector2i(from, until)


## Add the overcharge layer to ship `idx`: "" when done, else why not.
static func overcharge(arena, idx: int) -> String:
	var co = arena.ships[idx]
	if co.wrecked:
		return "wrecked"
	arena.sync(idx)
	if co.layers_cap - (1 if co.overcharge_left > 0.0 else 0) <= 0:
		return "no shield"
	if co.overcharge_left > 0.0:
		return "already overcharged"
	if co.overcharge_cd > 0.0:
		return "cooling down"
	co.overcharge_left = OVERCHARGE_S
	resync(co)
	arena.log_event("overcharge", idx)
	return ""


## A shot of weapon `w` hits the bubble of ship `idx` at the world point `point`, travelling along
## `dir`: one layer is used up (and, for ion, the shields lock).
static func absorb(arena, idx: int, w: Dictionary, point := Vector2.ZERO, dir := Vector2.ZERO) -> void:
	var co = arena.ships[idx]
	co.layers -= 1
	co.shield_timers.append(RECHARGE)
	if w.get("damage_type", "") == "ion":
		co.ion_lock = ION_LOCK
		arena.log_event("ion_lock", idx)
	var extra := {"layers": co.layers, "dir": dir, "dtype": w.get("damage_type", "")}
	if point != Vector2.ZERO:
		extra["pos"] = point
	arena.log_event("shield", idx, Vector2i(-1, -1), extra)


## Advance recharge, the overcharge and the ion lock by `dt` seconds.
static func tick(co, dt: float) -> void:
	if co.wrecked:
		return
	if co.overcharge_left > 0.0:
		co.overcharge_left -= dt
		if co.overcharge_left <= 1e-9:
			co.overcharge_left = 0.0
			co.overcharge_cd = OVERCHARGE_COOLDOWN
			resync(co)
	elif co.overcharge_cd > 0.0:
		co.overcharge_cd = maxf(co.overcharge_cd - dt, 0.0)
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
