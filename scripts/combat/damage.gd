extends RefCounted
## What a shot does once it meets a ship's cells. Walls, doors and components stop shots; floor and
## empty cells do not; a shaped cell (slope, curve) only where its polygon is. The shot's incidence
## theta is the angle between its reversed path and the outward normal of the face it enters (0 is
## straight on). Order on each wall or door: deflect roll, kinetic ricochet roll, then damage times
## the material's resist (and, for kinetic and explosive, clamp(cos theta, 0.5, 1): sloped armour),
## applied to the cell's hp (a part's hp for a component). A wall or door at 0 hp is breached (the
## cell becomes empty); a component at 0 hp is disabled, and a direct hit on one that is already at
## 0 wrecks it: it is gone, with debris on its cells (ion and fire never do; see wreck_part). The
## outside half of a hull mount (docs/CONTENT.md 4f) has its own hp, is only ever disabled, and a
## disabled one lets shots through to the cells behind it. Hull integrity drops by the damage dealt to
## walls and doors. A deflect or ricochet reflects the shot about the normal at half damage (see
## projectiles.gd for the bounces that follow). Works on arena combatants (arena.gd); every roll
## comes from the arena's seeded rng.

const Shapes = preload("res://scripts/ship/shapes.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Ammo = preload("res://scripts/sim/ammo.gd")

const RICOCHET_FROM_DEG := 40.0  ## kinetic shots never glance off a face closer to straight on than this
const RICOCHET_FULL_DEG := 75.0  ## and from here on glance off with RICOCHET_MAX
const RICOCHET_MAX := 0.8
const SLOPE_MIN := 0.5  ## least share of kinetic and explosive damage that a glancing hit does
const BOUNCE_DAMAGE := 0.5  ## share of its damage a bounced shot keeps
const SPLASH_FRACTION := 0.5  ## of the shot's damage, to every solid cell within the splash radius
const SPACED_FRACTION := 0.3  ## of that splash, for a cell behind an empty or floor gap
const LATTICE_FRACTION := 0.2  ## of the energy damage a neon lattice absorbs, counted as ship power
const DEFAULT_COMPONENT_HP := 4.0  ## for a part whose instance and definition give no hp


## What stops a shot on `cell` of combatant `co`: {} where it passes (empty, floor, an open door), else
## {"kind": "wall" | "door" | "component", "def": tile def, "uid": component uid, "half": "out" for the
## outside half of a hull mount}. A disabled outside half lets shots through, but `hitbox` (ships
## touching: the shape of the hull) still counts it.
static func solid_at(co, cell: Vector2i, hitbox := false) -> Dictionary:
	var grid = co.ship.grid
	var id: String = grid.get_tile(cell)
	if id != "" and grid.defs != null:
		var d: Dictionary = grid.defs.get_def(id)
		if bool(d.get("solid", false)):
			return {"kind": "wall", "def": d}
		if bool(d.get("door", false)):  # an open door lets shots through
			return {} if grid.is_door_open(cell) else {"kind": "door", "def": d}
	var uid: int = co.ship.components.at(cell)
	if uid >= 0:
		return {"kind": "component", "uid": uid}
	uid = co.ship.components.at_out(cell)
	if uid >= 0 and (hitbox or co.ship.components.outside_alive(uid)):
		return {"kind": "component", "uid": uid, "half": "out"}
	return {}


## The factor a corroded wall or door at `cell` of ship `idx` divides its resist by (effects.gd keeps them in `arena.fx`): 1 when it is sound.
static func corrode_mult(arena, idx: int, cell: Vector2i) -> float:
	var c: Dictionary = arena.fx["corroded"]
	if c.is_empty():
		return 1.0
	return float(c[Vector3i(idx, cell.x, cell.y)][0]) if c.has(Vector3i(idx, cell.x, cell.y)) else 1.0


## The key of the part `obj` (a solid_at result) hit: its uid, plus "o" for the outside half of a mount.
static func part_key(obj: Dictionary) -> String:
	return "%d%s" % [obj["uid"], "o" if obj.get("half", "") == "out" else ""]


## Chance that a kinetic shot hitting a face at `theta_deg` off its normal glances off: 0 below 40
## degrees, rising linearly to 0.8 at 75 degrees and more.
static func ricochet_chance(theta_deg: float) -> float:
	return RICOCHET_MAX * clampf((theta_deg - RICOCHET_FROM_DEG) / (RICOCHET_FULL_DEG - RICOCHET_FROM_DEG), 0.0, 1.0)


## Share of a hit that damage of `type` does at an incidence whose cosine is `cos_t`: kinetic and
## explosive lose to a shallow angle (a shot at an angle crosses more plate), down to 0.5; the rest do not.
static func slope_factor(type: String, cos_t: float) -> float:
	return clampf(cos_t, SLOPE_MIN, 1.0) if type == "kinetic" or type == "explosive" else 1.0


## Where the segment a -> b (ship-local cell coordinates) meets solid `cell` of `co`, which the DDA
## entered at `entry` ({t, n} of Projectiles.cells_along): {t, n} (n is the outward face normal, zero
## when the segment starts inside), or {} for a shaped cell whose empty part it only crosses.
static func cell_hit(co, cell: Vector2i, a: Vector2, b: Vector2, entry: Dictionary) -> Dictionary:
	var sh: Dictionary = co.ship.grid.shape_of(cell)
	if sh.is_empty():
		return {"t": entry["t"], "n": entry["n"]}
	return Shapes.segment_hit(sh, a - Vector2(cell), b - Vector2(cell))


## A shot of weapon `w` crosses `entries` (cells in order, from Projectiles.cells_along, the first
## already a solid one that `first_hit` ({t, n}, see cell_hit) was found for) of ship `idx` along the
## segment a -> b (ship-local). Resolves it to the end: {} when it was spent, {"bounce": {pos (world),
## n (world face normal), dir (new world direction), ship, cell, dmg, pierce}} when a cell glanced it off.
## `first_out` (optional) is filled with the first cell it damaged: {cell, obj (solid_at), dir (ship-local unit
## vector)}, for the weapon effects (effects.gd) the caller applies.
static func march(arena, idx: int, w: Dictionary, a: Vector2, b: Vector2, entries: Array, first_hit: Dictionary, first_out := {}) -> Dictionary:
	var co = arena.ships[idx]
	var dmg := float(w["damage"])
	var pierce := int(w["pierce"])
	var type: String = w["damage_type"]
	var seen := {}  # parts (part_key) already hit by this shot
	var dir := (b - a).normalized()
	var wdir: Vector2 = dir.rotated(co.flight.angle)  # the shot's direction in the world, for the effects
	var first := true
	for k in entries.size():
		var e: Dictionary = entries[k]
		var cell: Vector2i = e["c"]
		var obj := solid_at(co, cell)
		if obj.is_empty():
			continue
		var h: Dictionary = first_hit if k == 0 else cell_hit(co, cell, a, b, e)
		if h.is_empty():
			continue  # a shaped cell the shot passes the empty half of
		var n: Vector2 = h["n"]
		var nw: Vector2 = n.rotated(co.flight.angle)
		var cos_t := clampf(-dir.dot(n), 0.0, 1.0) if n != Vector2.ZERO else 1.0
		var factor := 1.0
		if obj["kind"] == "component":
			if seen.has(part_key(obj)):
				continue
			seen[part_key(obj)] = true
		else:
			var chance := float(obj["def"].get("deflect", {}).get(type, 0.0)) * (1.0 + 0.5 * sqrt(1.0 - cos_t * cos_t))
			if chance > 0.0 and arena.rng.randf() < chance:
				return {"bounce": _bounce(arena, "deflect", idx, cell, a.lerp(b, h["t"]), wdir, nw, dmg, pierce)}
			if type == "kinetic":
				var p := ricochet_chance(rad_to_deg(acos(cos_t)))
				if p > 1e-6 and arena.rng.randf() < p:
					return {"bounce": _bounce(arena, "ricochet", idx, cell, a.lerp(b, h["t"]), wdir, nw, dmg, pierce)}
			factor = slope_factor(type, cos_t)
		var res := apply(arena, idx, cell, obj, dmg * factor, type, {"dir": wdir, "n": nw, "weapon": str(w.get("id", ""))})
		if first:
			first = false
			first_out.merge({"cell": cell, "obj": obj, "dir": dir})
			var fc := float(w.get("fire_chance", 0.0))
			if fc > 0.0 and arena.rng.randf() < fc:
				arena.log_event("ignite", idx, cell)
			var radius := float(w.get("splash", 0.0))
			if radius > 0.0:
				splash(arena, idx, cell, dmg * SPLASH_FRACTION, radius, type, part_key(obj) if obj["kind"] == "component" else "")
		if res["left"] <= 0.0 or pierce <= 0:
			return {}
		pierce -= 1
		dmg = res["left"]
	return {}


## A shot glanced off `cell` of ship `idx` at `local_pt` (ship-local cell coordinates): log the event
## (`type` ricochet or deflect: pos is the hit point, dir the way the shot flew, n the face normal and
## new_dir the way it leaves, all in the world) and give the bounce for the caller to carry on with.
static func _bounce(arena, type: String, idx: int, cell: Vector2i, local_pt: Vector2, wdir: Vector2, nw: Vector2, dmg: float, pierce: int) -> Dictionary:
	var pt: Vector2 = arena.local_to_world(idx, local_pt)
	var nn := nw if nw != Vector2.ZERO else -wdir
	var out := wdir - 2.0 * wdir.dot(nn) * nn
	arena.log_event(type, idx, cell, {"pos": pt, "dir": wdir, "n": nw, "new_dir": out})
	return {"pos": pt, "n": nn, "dir": out, "ship": idx, "cell": cell, "dmg": dmg * BOUNCE_DAMAGE, "pierce": pierce}


## Apply `dmg` of `type` to the wall, door or part `obj` on `cell`. `info`: extra keys for the hit
## event (the shot's dir and face normal). Returns {"dealt": hp removed, "left": raw damage that
## carries on past it (0 unless it was used up)}.
static func apply(arena, idx: int, cell: Vector2i, obj: Dictionary, dmg: float, type: String, info := {}) -> Dictionary:
	var co = arena.ships[idx]
	var comps = co.ship.components
	var grid = co.ship.grid
	var is_part: bool = obj["kind"] == "component"
	if is_part and not comps.instances.has(obj["uid"]):  # wrecked a moment ago by the same blast
		return {"dealt": 0.0, "left": dmg}
	var outside: bool = is_part and obj.get("half", "") == "out"
	var resist := 1.0
	var cur: float
	var inst: Dictionary
	if is_part:
		inst = comps.instances[obj["uid"]]
		cur = float(inst["out_hp"]) if outside else float(inst.get("hp", comps.def(inst["id"]).get("hp", DEFAULT_COMPONENT_HP)))
	else:
		resist = float(obj["def"].get("resist", {}).get(type, 1.0)) / corrode_mult(arena, idx, cell)  # a corroded wall takes more
		cur = grid.hp_of(cell)
	var eff := 0.0 if type == "ion" else dmg * resist  # ion does no structural damage
	var dealt := minf(eff, cur)
	var left := dmg - cur / resist if eff > cur and resist > 0.0 else 0.0
	var was := cur
	cur -= dealt
	var hit := {"dealt": dealt, "kind": obj["kind"], "dtype": type}
	hit.merge(info)  # dir and n of the shot, for the effects
	if outside:
		hit["half"] = "out"
	arena.log_event("hit", idx, cell, hit)
	if dealt > 0.0 and Ammo.cut_near(co.ship, cell) > 0:  # a belt beside the damage is cut until crew mend it
		arena.log_event("belt_cut", idx, cell)
	if type == "ion":
		Jobs.ion_hit(co.ship, cell, dmg)  # the crew in that room are jolted and may be stunned
		if is_part and not outside:
			Ammo.ion_hit(co.ship, obj["uid"])  # a Mag-Rail drive stops for a while
	if is_part:
		if outside:  # built to take it: disabled at 0, never destroyed
			inst["out_hp"] = cur
			if cur <= 0.0 and was > 0.0:
				co.dirty = true
				arena.log_event("disable", idx, cell, {"uid": obj["uid"], "half": "out"})
			return {"dealt": dealt, "left": left}
		inst["hp"] = cur
		if was <= 0.0 and eff > 0.0 and int(inst.get("zero_tick", -1)) < arena.tick:  # disabled already, and hit again: gone
			wreck_part(arena, idx, obj["uid"])
			return {"dealt": dealt, "left": left}
		if cur <= 0.0 and inst.get("status", "") != "disabled":
			inst["status"] = "disabled"
			inst["zero_tick"] = arena.tick  # a hit in this same tick does not wreck it
			co.dirty = true
			arena.log_event("disable", idx, cell, {"uid": obj["uid"]})
		return {"dealt": dealt, "left": left}
	if dealt > 0.0:
		grid.hp[cell] = cur
		co.hull = maxf(co.hull - dealt, 0.0)
	if type == "energy":
		var quirk := str(obj["def"].get("quirk", ""))
		if quirk == "ablative":  # burns away: every energy hit lowers the max hp
			var mx := maxf(grid.max_hp_of(cell) - 1.0, 0.0)
			grid.hp_max[cell] = mx
			cur = minf(cur, mx)
			grid.hp[cell] = cur
		elif quirk == "lattice_power":
			arena.power_bonus[idx] = float(arena.power_bonus.get(idx, 0.0)) + LATTICE_FRACTION * dealt
	if cur <= 0.0:
		var tile: String = grid.breach(cell)
		co.ship.mark_dirty()
		co.dirty = true
		arena.log_event("breach", idx, cell, {"tile": tile})
	if co.hull <= 0.0 and not co.wrecked:
		arena.wreck(idx)
	return {"dealt": dealt, "left": left}


## Part `uid` of ship `idx` is wrecked (a direct hit on one that was already disabled): it is removed,
## the outside half of a mount with it, and its inside cells get a wreck decal until a crew member
## clears them (the `clear_wreck` job gives back half its recipe). Logs a "wreck_part" event.
static func wreck_part(arena, idx: int, uid: int) -> void:
	var co = arena.ships[idx]
	var ship = co.ship
	var inst: Dictionary = ship.components.instances[uid]
	var id: String = inst["id"]
	var at: Vector2i = inst["cells"][0]
	var blast := Ammo.blast(ship, uid)  # an ammo rack with explosive ammo goes up
	ship.components.wreck(uid)
	co.mounts.erase(uid)
	co.cooldowns.erase(uid)
	ship.manned.erase(uid)
	co.dirty = true
	ship.mark_dirty()
	ship.log_event("%s wrecked" % ship.components.def(id).get("name", id))
	arena.log_event("wreck_part", idx, at, {"uid": uid, "id": id})
	if not blast.is_empty():
		rack_blast(arena, idx, blast)


## A wrecked ammo rack's blast (Ammo.blast): `damage` of explosive type to every part in its room and every wall and
## door round the room (docs/CONTENT.md 4f: 2 damage a unit). Logs a "rack_blast" event.
static func rack_blast(arena, idx: int, blast: Dictionary) -> void:
	var co = arena.ships[idx]
	var hits: Array = []  # [cell, obj]
	var seen := {}
	for c in blast["cells"]:
		var around: Array = [c]
		for d in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			around.append(c + d)
		for q in around:
			var obj := solid_at(co, q)
			if obj.is_empty() or (obj["kind"] == "component" and q != c):
				continue  # a part only if it stands in the room
			var key := part_key(obj) if obj["kind"] == "component" else "%d,%d" % [q.x, q.y]
			if not seen.has(key):
				seen[key] = true
				hits.append([q, obj])
	arena.log_event("rack_blast", idx, blast["at"], {"units": blast["units"], "item": blast["item"], "damage": blast["damage"]})
	co.ship.log_event("The ammo rack blew up (%d %s)" % [blast["units"], blast["item"]])
	for h in hits:
		apply(arena, idx, h[0], h[1], float(blast["damage"]), "explosive")


## An explosion at `impact`: every solid cell within `radius` cells takes `amount` of `type`
## (resist applies; deflect and ricochet do not), or SPACED_FRACTION of it when an empty or floor
## cell lies between it and the impact. A part takes it once (each half of a mount is a part).
## `skip`: the part_key of the part hit directly.
static func splash(arena, idx: int, impact: Vector2i, amount: float, radius: float, type: String, skip := "") -> void:
	var co = arena.ships[idx]
	var r := ceili(radius)
	var hits: Array = []  # [cell, obj, amount]
	var part_hit := {}  # part_key -> index in hits
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if (dx == 0 and dy == 0) or dx * dx + dy * dy > radius * radius + 1e-9:
				continue
			var c := impact + Vector2i(dx, dy)
			var obj := solid_at(co, c)
			if obj.is_empty() or (obj["kind"] == "component" and part_key(obj) == skip):
				continue
			var a := amount * (SPACED_FRACTION if _spaced(co, impact, c) else 1.0)
			if obj["kind"] == "component":
				var key := part_key(obj)
				if part_hit.has(key):
					hits[part_hit[key]][2] = maxf(hits[part_hit[key]][2], a)
					continue
				part_hit[key] = hits.size()
			hits.append([c, obj, a])
	for h in hits:
		apply(arena, idx, h[0], h[1], h[2], type)


## Is there an empty or floor cell on the straight line between cells `a` and `b` (not counting them)?
static func _spaced(co, a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	var n := maxi(absi(d.x), absi(d.y))
	for k in range(1, n):
		var c := a + Vector2i(roundi(float(d.x * k) / n), roundi(float(d.y * k) / n))
		if solid_at(co, c).is_empty():
			return true
	return false
