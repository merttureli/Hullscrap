extends RefCounted
## Shield bubbles. The bubble hugs the hull (shield_shape.gd: the convex hull of the ship's cells,
## inflated 1.5 cells with rounded corners) and is split into N sectors round the ship's centre, sector 0
## centred on the bow. N and the layers come from the powered shield components: N is the best powered
## generator's `stats.sectors` (1, 2, 4 or 8), the layers add up.
## - Shield HP: a layer is `layer_hp` shield HP (set per shield part by its tier: weapons.json `shields.tiers`, params_of_ship), so a
##   sector holds `layers x weight x layer_hp` HP. Sector state is kept in layers (a float; HP = layers x layer_hp). A hit takes its
##   damage off the pool of the sector it enters through; damage beyond the pool passes on to the hull (absorb returns it).
##   After a hit the sector waits `regen_delay`, then regains `regen_rate` HP/s (times the parts' recharge speed, the storm and crew);
##   a sector knocked to 0 waits `break_delay` instead. shift() moves a step of weight toward a side: the sector that loses it drops
##   at once, the one that gains it fills at the regen rate. A changed N starts again from even weights.
## - A shot is stopped by the sector it enters through while that holds any HP. Missiles and piercing rounds pass. An ion hit takes
##   ION_DAMAGE x its damage off the pool (x the shield parts' line ion_vulnerability: neon) and locks the whole bubble for
##   ION_LOCK seconds: it stops nothing and does not regen.
## - Firing opens only the sector the shot leaves through for the weapon's drop time (see drop_seconds):
##   shots pass an open sector and use no HP. A volley opens it once (volley.gd); point defence never.
## - Abilities with a shield_layer effect (the Overcharge of the shield parts, abilities.gd) add layers (HP) while they run,
##   spread by the weights.
## Works on arena combatants (see arena.gd) and is deterministic: no randomness here.

const Abilities = preload("res://scripts/sim/abilities.gd")
const Shape = preload("res://scripts/combat/shield_shape.gd")
const Balance = preload("res://scripts/combat/shield_balance.gd")
const CrewFx = preload("res://scripts/crew/crew_fx.gd")

const ION_LOCK := 5.0  ## seconds an ion hit keeps the shields offline
const EPS := 1e-6  ## a sector stops a shot while it holds more than this many layers
const ION_DAMAGE := 2.0  ## an ion hit takes this many times its damage off the shield HP
## Seconds a shot opens its sector, by weapon kind (and for ion damage). A beam opens it for its whole
## duration; a missile never does. A weapon entry's own `drops_shield_s` wins.
const DROP := {"laser": 0.3, "bolt": 0.4, "flak": 0.6, "ion": 0.3}


# --- what the parts give ---------------------------------------------------------------------------

## Layers the ship's powered shield components give (`powered`: uid -> bool, from the power solve).
static func layers_of_ship(ship, powered: Dictionary) -> int:
	var total := 0
	var comps = ship.components
	for uid in comps.instances:
		if powered.get(uid, false):
			var d: Dictionary = comps.def(comps.instances[uid]["id"])
			if d.get("family", "") == "shield":
				total += Abilities.part_layers(ship, uid, int(d.get("stats", {}).get("layers", 0)))  # crew and heat can change a part's layers
	return total


## Sectors of the bubble: the largest `stats.sectors` among the powered shield components (1 if none
## says), as a legal count (1, 2, 4 or 8).
static func sectors_of_ship(ship, powered: Dictionary) -> int:
	var best := 1
	var comps = ship.components
	for uid in comps.instances:
		if powered.get(uid, false):
			var d: Dictionary = comps.def(comps.instances[uid]["id"])
			if d.get("family", "") == "shield":
				best = maxi(best, int(d.get("stats", {}).get("sectors", 1)))
	return Balance.legal(best)


## The shield HP numbers of the ship's powered shield parts: {layer_hp, regen_delay, regen_rate (HP/s), break_delay}, the mean of the parts
## weighted by their layers (a part's stats.layer_hp / regen_delay / regen_rate / break_delay win over its tier's row of weapons.json
## `shields.tiers`). A ship with none gets the tier 1 row.
static func params_of_ship(ship, powered: Dictionary) -> Dictionary:
	var sum := {"layer_hp": 0.0, "regen_delay": 0.0, "regen_rate": 0.0, "break_delay": 0.0}
	var weight := 0.0
	var comps = ship.components
	for uid in comps.instances:
		if powered.get(uid, false):
			var d: Dictionary = comps.def(comps.instances[uid]["id"])
			if d.get("family", "") == "shield":
				var row := Abilities.shield_row(d)
				var wt := maxf(float(d.get("stats", {}).get("layers", 0)), 0.01)
				for k in sum:
					sum[k] += float(row[k]) * wt
				weight += wt
	if weight <= 0.0:
		return Abilities.shield_row({})
	for k in sum:
		sum[k] /= weight
	return sum


static func layers_max(co) -> int:
	return layers_of_ship(co.ship, co.powered)


static func sectors_of(co) -> int:
	return sectors_of_ship(co.ship, co.powered)


# --- state of the sectors --------------------------------------------------------------------------

## The layers sector `s` can hold: the layers of a weight-1 sector times its weight.
static func cap_of(co, s: int) -> float:
	return co.layers_cap * float(co.weights[s])


## Layers up across all sectors, a partly full layer counting as one (what `co.layers` reads: 0 means no sector holds any HP).
static func layers_up(co) -> int:
	var n := 0
	for x in co.sector_layers:
		n += ceili(float(x) - EPS)
	return n


## Shield HP now in sector `s`, and the most it holds.
static func hp_of(co, s: int) -> float:
	return float(co.sector_layers[s]) * float(co.shield_hp["layer_hp"])


static func hp_cap_of(co, s: int) -> float:
	return cap_of(co, s) * float(co.shield_hp["layer_hp"])


## What the HUD shows for sector `s`: {layers (up now), cap, weight, open (on the arena's tick), filling, hp, hp_cap, down (knocked to 0, waiting)}.
static func sector_state(co, s: int, tick: int) -> Dictionary:
	return {"layers": float(co.sector_layers[s]), "cap": cap_of(co, s), "weight": float(co.weights[s]),
		"open": sector_open(co, s, tick), "filling": float(co.sector_layers[s]) < cap_of(co, s) - EPS,
		"hp": hp_of(co, s), "hp_cap": hp_cap_of(co, s), "down": float(co.sector_layers[s]) <= EPS and float(co.sector_wait[s]) > 0.0}


## Bring the sectors in line with the parts after power or an ability changed: a changed sector count
## re-forms the bubble (even weights, the same share full); otherwise capacity that arrives (a generator
## coming up, an overcharge) arrives full, and lost capacity is dropped.
static func resync(co) -> void:
	var base := 0 if co.wrecked else layers_max(co)
	var cap := base + (Abilities.extra_layers(co.ship) if base > 0 else 0)
	co.shield_hp = params_of_ship(co.ship, co.powered)
	var n := sectors_of(co)
	if n != co.sectors or co.weights.size() != n:
		_reform(co, n, cap)
		return
	var old: int = co.layers_cap
	co.layers_cap = cap
	for s in n:
		var w := float(co.weights[s])
		if cap * w > old * w:
			co.sector_layers[s] = float(co.sector_layers[s]) + (cap - old) * w
		_fit(co, s)


## A new sector count: even weights, and each sector holds the share of its capacity that the old bubble
## had (all of it for a bubble that was not there), the rest recharging.
static func _reform(co, n: int, cap: int) -> void:
	var old_cap: float = co.layers_cap * co.sectors
	var share := 1.0
	if old_cap > 0.0:
		var sum := 0.0
		for x in co.sector_layers:
			sum += float(x)
		share = clampf(sum / old_cap, 0.0, 1.0)
	co.sectors = n
	co.layers_cap = cap
	co.weights = Balance.even(n)
	co.sector_layers = []
	co.sector_wait = []
	co.sector_hit = []
	co.sector_open = {}
	for s in n:
		co.sector_layers.append(cap * share)
		co.sector_wait.append(0.0)
		co.sector_hit.append(-1000000)


## Keep sector `s` within its capacity.
static func _fit(co, s: int) -> void:
	co.sector_layers[s] = minf(float(co.sector_layers[s]), cap_of(co, s))


## A fight starts: the ship's saved weights (even when they do not suit the sector count) and every
## sector full.
static func start(co) -> void:
	co.weights = Balance.normalized(co.ship.shield_balance.get("weights", []), co.sectors)
	for s in co.sectors:
		co.sector_layers[s] = cap_of(co, s)
		co.sector_wait[s] = 0.0


# --- balance ---------------------------------------------------------------------------------------

## Use weights `w` (they must suit the sector count): a sector that loses cap drops to it at once, one that
## gains cap fills the difference at the regen rate.
static func set_weights(co, w: Array) -> bool:
	if not Balance.valid(w, co.sectors):
		return false
	co.weights = w.duplicate()
	for s in co.sectors:
		_fit(co, s)
	return true


## Everything back to even weights.
static func reset_even(co) -> void:
	set_weights(co, Balance.even(co.sectors))


## One step of balance toward the side `dir` ("up" bow, "down" stern, "left" port, "right" starboard).
## "" when it moved, else why not.
static func shift(co, dir: String) -> String:
	if co.wrecked or co.layers_cap <= 0:
		return "no shield"
	if co.sectors < 2:
		return "one piece: no balance to set"
	var s := Balance.dir_sector(co.sectors, dir)
	if s < 0:
		return "port and starboard need 4 sectors"
	return shift_sector(co, s)


## One step of balance toward sector `s` (or away from it with `delta` -1). "" when it moved, else why not.
static func shift_sector(co, s: int, delta := 1) -> String:
	if co.wrecked or co.layers_cap <= 0:
		return "no shield"
	var r := Balance.step(co.weights, s, delta)
	if r["why"] != "":
		return r["why"]
	set_weights(co, r["weights"])
	return ""


# --- the shape -------------------------------------------------------------------------------------

## The ship's bubble outline (shield_shape.gd), kept until its cells change.
static func shape_of(co):
	var sig: Array = Shape.signature(co.ship)
	if co.shape == null or co.shape_sig != sig:
		co.shape = Shape.from_cells(Shape.cells_of(co.ship), co.pivot)
		co.shape_sig = sig
	return co.shape


## Cells from the centre to the farthest point of the bubble.
static func reach(co) -> float:
	return shape_of(co).radius


## Where the segment a -> b (ship-local cell coordinates) first enters the bubble, as a fraction 0..1 of
## the segment; -1 when it does not, or when it starts inside (it is through already).
static func entry_t(co, a: Vector2, b: Vector2) -> float:
	return shape_of(co).entry_t(a, b)


## The sector (0..sectors-1) of `v`, a vector from the ship's centre in ship-local coordinates.
## Sector 0 is centred on the bow (local up); sectors count clockwise on screen.
static func sector_of(co, v: Vector2) -> int:
	return Shape.sector_at(v, co.sectors)


## The sector of a world direction seen from ship `co` (turned by its heading).
static func sector_of_world_dir(co, dir: Vector2) -> int:
	return sector_of(co, dir.rotated(-co.flight.angle))


## The sector a shot leaves through: from `a` (ship-local cell coordinates, normally inside the
## bubble) along `d` to where it crosses the bubble. From outside the bubble the direction itself counts.
static func outgoing_sector(co, a: Vector2, d: Vector2) -> int:
	var shape = shape_of(co)
	if shape.contains(a) and d.length_squared() > 1e-12:
		var far: Vector2 = a + d.normalized() * (shape.radius * 2.0 + 4.0)
		var t: float = shape.exit_t(a, far)
		if t >= 0.0:
			return sector_of(co, a.lerp(far, t) - co.pivot)
	return sector_of(co, d)


# --- shots -----------------------------------------------------------------------------------------

## Could the bubble stop shots of weapon `w` at all right now (a sector holds some HP, no ion lock)?
## Which sector the shot crosses is stops()' business.
static func blocks(co, w: Dictionary) -> bool:
	return co.layers > 0 and co.ion_lock <= 0.0 and not co.wrecked and not bool(w.get("pass_shields", false))


## Does sector `s` stop a shot of weapon `w` on arena tick `tick`: it holds some HP and is not open?
static func stops(co, s: int, w: Dictionary, tick: int) -> bool:
	return blocks(co, w) and float(co.sector_layers[s]) > EPS and not sector_open(co, s, tick)


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
	if kind == "missile" or bool(w.get("ap", false)) or (w.get("effects") is Dictionary and w["effects"].has("intercept")):  # a piercing round and point defence never open the sector
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


## A shot of weapon `w` hits the bubble of ship `idx` at the world point `point`, travelling along `dir`: its damage comes off the HP
## of the sector it entered through (`sector`, else the one `point` is in), which then waits regen_delay before it regens (break_delay
## when it is knocked to 0). Returns the damage that passes on to the hull (0 when the pool covered the shot). An ion hit takes ION_DAMAGE x
## its damage (x the shield parts' ion_vulnerability, Abilities.shield_ion_vulnerability: neon 2) and locks the whole bubble.
static func absorb(arena, idx: int, w: Dictionary, point := Vector2.ZERO, dir := Vector2.ZERO, sector := -1) -> float:
	var co = arena.ships[idx]
	var s := sector
	if s < 0:
		s = sector_of(co, arena.world_to_local(idx, point) - co.pivot) if point != Vector2.ZERO else 0
	var mult := 1.0
	var lock := ION_LOCK
	var ion: bool = w.get("damage_type", "") == "ion"
	if ion:
		var vuln := Abilities.shield_ion_vulnerability(co.ship, co.powered)
		mult = ION_DAMAGE * vuln
		lock = ION_LOCK * vuln
	var lhp: float = co.shield_hp["layer_hp"]
	var pool: float = float(co.sector_layers[s]) * lhp
	var dmg: float = float(w.get("damage", 1.0)) * mult
	var took := minf(dmg, pool)
	co.sector_layers[s] = (pool - took) / lhp
	var passed := (dmg - took) / mult
	if float(co.sector_layers[s]) <= EPS:
		co.sector_layers[s] = 0.0
		co.sector_wait[s] = float(co.shield_hp["break_delay"])  # knocked down: it waits longer
	else:
		co.sector_wait[s] = float(co.shield_hp["regen_delay"])
	co.sector_hit[s] = arena.tick
	if ion:
		co.ion_lock = maxf(co.ion_lock, lock)
		arena.log_event("ion_lock", idx)
	var extra := {"layers": co.layers, "sector": s, "sector_layers": float(co.sector_layers[s]), "dir": dir, "dtype": w.get("damage_type", ""), "hp": took, "passed": passed}
	if point != Vector2.ZERO:
		extra["pos"] = point
	arena.log_event("shield", idx, Vector2i(-1, -1), extra)
	return passed


## Advance regen and the ion lock by `dt` seconds (regen runs faster while a shield part is overclocked, and
## `rate_mult` times as fast, 0.5 in an ion storm; the ion lock runs at the real rate).
static func tick(co, dt: float, rate_mult := 1.0) -> void:
	if co.wrecked:
		return
	if co.ion_lock > 0.0:
		co.ion_lock = maxf(co.ion_lock - dt, 0.0)
		return
	dt *= CrewFx.family_mult(co.ship, "shield") * rate_mult
	var rate := -1.0
	for s in co.sectors:
		var cap := cap_of(co, s)
		if float(co.sector_layers[s]) >= cap - EPS:
			co.sector_wait[s] = 0.0
			continue
		if rate < 0.0:
			rate = Abilities.recharge_rate(co.ship, co.powered)  # the parts' speed and the crew a shield lacks
		var step := dt * rate
		var wait: float = co.sector_wait[s]
		if wait > 0.0:
			var spent := minf(wait, step)
			co.sector_wait[s] = wait - spent
			step -= spent
		if step > 0.0:
			var up := minf(float(co.sector_layers[s]) + step * float(co.shield_hp["regen_rate"]) / float(co.shield_hp["layer_hp"]), cap)
			co.sector_layers[s] = cap if up >= cap - 1e-9 else up
