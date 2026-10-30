extends RefCounted
## What a shot does once it meets a ship's cells. Walls, doors and components stop shots; floor and
## empty cells do not. Order on each solid cell: deflect roll, kinetic ricochet roll, then damage
## times the material's resist, applied to the cell's hp (a part's hp for a component). A wall or
## door at 0 hp is breached (the cell becomes empty); a component at 0 hp is disabled. Hull
## integrity drops by the damage dealt to walls and doors. Works on arena combatants (arena.gd);
## every roll comes from the arena's seeded rng.

const RICOCHET_COS := 0.5  ## cos 60 degrees: a shot more than 60 degrees off the face normal may glance off
const RICOCHET_CHANCE := 0.5
const SPLASH_FRACTION := 0.5  ## of the shot's damage, to every solid cell within the splash radius
const SPACED_FRACTION := 0.3  ## of that splash, for a cell behind an empty or floor gap
const LATTICE_FRACTION := 0.2  ## of the energy damage a neon lattice absorbs, counted as ship power
const DEFAULT_COMPONENT_HP := 4.0  ## for a part whose instance and definition give no hp


## What stops a shot on `cell` of combatant `co`: {} where it passes (empty, floor, an open door), else
## {"kind": "wall" | "door" | "component", "def": tile def, "uid": component uid}.
static func solid_at(co, cell: Vector2i) -> Dictionary:
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
	return {}


## A shot of weapon `w` crosses `entries` (cells in order, from Projectiles.cells_along, the first
## already a solid one) of ship `idx` going along `dir` (ship-local). Resolves it to the end.
static func march(arena, idx: int, w: Dictionary, entries: Array, dir: Vector2) -> void:
	var co = arena.ships[idx]
	var dmg := float(w["damage"])
	var pierce := int(w["pierce"])
	var type: String = w["damage_type"]
	var seen := {}  # component uids already hit by this shot
	var wdir: Vector2 = dir.rotated(co.flight.angle)  # the shot's direction in the world, for the effects
	var first := true
	for e in entries:
		var cell: Vector2i = e["c"]
		var obj := solid_at(co, cell)
		if obj.is_empty():
			continue
		if obj["kind"] == "component":
			if seen.has(obj["uid"]):
				continue
			seen[obj["uid"]] = true
		else:
			var chance := float(obj["def"].get("deflect", {}).get(type, 0.0))
			if chance > 0.0 and arena.rng.randf() < chance:
				arena.log_event("deflect", idx, cell, {"dir": wdir, "n": e["n"].rotated(co.flight.angle)})
				return
			var n: Vector2 = e["n"]
			if type == "kinetic" and n != Vector2.ZERO and absf(dir.dot(n)) < RICOCHET_COS and arena.rng.randf() < RICOCHET_CHANCE:
				arena.log_event("ricochet", idx, cell, {"dir": wdir, "n": n.rotated(co.flight.angle)})
				return
		var res := apply(arena, idx, cell, obj, dmg, type, {"dir": wdir, "n": e["n"].rotated(co.flight.angle)})
		if first:
			first = false
			var fc := float(w.get("fire_chance", 0.0))
			if fc > 0.0 and arena.rng.randf() < fc:
				arena.log_event("ignite", idx, cell)
			var radius := float(w.get("splash", 0.0))
			if radius > 0.0:
				splash(arena, idx, cell, dmg * SPLASH_FRACTION, radius, type, obj.get("uid", -1))
		if res["left"] <= 0.0 or pierce <= 0:
			return
		pierce -= 1
		dmg = res["left"]


## Apply `dmg` of `type` to the wall, door or part `obj` on `cell`. `info`: extra keys for the hit
## event (the shot's dir and face normal). Returns {"dealt": hp removed, "left": raw damage that
## carries on past it (0 unless it was used up)}.
static func apply(arena, idx: int, cell: Vector2i, obj: Dictionary, dmg: float, type: String, info := {}) -> Dictionary:
	var co = arena.ships[idx]
	var comps = co.ship.components
	var grid = co.ship.grid
	var is_part: bool = obj["kind"] == "component"
	var resist := 1.0
	var cur: float
	var inst: Dictionary
	if is_part:
		inst = comps.instances[obj["uid"]]
		cur = float(inst.get("hp", comps.def(inst["id"]).get("hp", DEFAULT_COMPONENT_HP)))
	else:
		resist = float(obj["def"].get("resist", {}).get(type, 1.0))
		cur = grid.hp_of(cell)
	var eff := 0.0 if type == "ion" else dmg * resist  # ion does no structural damage
	var dealt := minf(eff, cur)
	var left := dmg - cur / resist if eff > cur and resist > 0.0 else 0.0
	cur -= dealt
	var hit := {"dealt": dealt, "kind": obj["kind"], "dtype": type}
	hit.merge(info)  # dir and n of the shot, for the effects
	arena.log_event("hit", idx, cell, hit)
	if is_part:
		inst["hp"] = cur
		if cur <= 0.0 and inst.get("status", "") != "disabled":
			inst["status"] = "disabled"
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


## An explosion at `impact`: every solid cell within `radius` cells takes `amount` of `type`
## (resist applies; deflect and ricochet do not), or SPACED_FRACTION of it when an empty or floor
## cell lies between it and the impact. A part takes it once. `skip_uid`: the part hit directly.
static func splash(arena, idx: int, impact: Vector2i, amount: float, radius: float, type: String, skip_uid := -1) -> void:
	var co = arena.ships[idx]
	var r := ceili(radius)
	var hits: Array = []  # [cell, obj, amount]
	var part_hit := {}  # part uid -> index in hits
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if (dx == 0 and dy == 0) or dx * dx + dy * dy > radius * radius + 1e-9:
				continue
			var c := impact + Vector2i(dx, dy)
			var obj := solid_at(co, c)
			if obj.is_empty() or (obj["kind"] == "component" and obj["uid"] == skip_uid):
				continue
			var a := amount * (SPACED_FRACTION if _spaced(co, impact, c) else 1.0)
			if obj["kind"] == "component":
				if part_hit.has(obj["uid"]):
					hits[part_hit[obj["uid"]]][2] = maxf(hits[part_hit[obj["uid"]]][2], a)
					continue
				part_hit[obj["uid"]] = hits.size()
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
