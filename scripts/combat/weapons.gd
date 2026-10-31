extends RefCounted
## Weapon stats (data/weapons.json, keyed by component id), aiming and firing. A ship's weapons are
## "mounts": one per placed weapon component, plus virtual ones the arena can add by weapon id.
## A mount is a hull mount (docs/CONTENT.md 4f): its barrel turns about a pivot on the outside half and
## points outward through the wall (`dir`, ship-local); shots leave from the muzzle, `reach` cells along
## the barrel's live direction `aim`. A FIXED gun fires along `dir`, turned up to its `gimbal` degrees
## toward the point aimed at, so the ship is aimed. A TURRET (`turret` true) turns its barrel within
## its `arc` at `track` degrees per second toward the lead point on the enemy (tick_turrets) and fires by
## itself when ready and on target (the owner's T key toggles it); each of its shots rolls a hit
## against the target's evasion on the arena's rng: a hit aims at a random outer cell facing the
## turret, a miss at a point just off the hull. A turret deals `turret_damage` of its entry's damage.
## A turret with an `intercept` {range} effect (point defence, effects.gd) turns on the nearest enemy missile within that
## range before any ship, and each shot rolls its accuracy to destroy the missile outright.
## Works on the arena (arena.gd).

const Projectiles = preload("res://scripts/combat/projectiles.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Collisions = preload("res://scripts/combat/collisions.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Content = preload("res://scripts/data/content.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Hazards = preload("res://scripts/combat/hazards.gd")

const PATH := "res://data/weapons.json"
const BASE := {"damage_type": "energy", "damage": 1.0, "cooldown": 1.0, "range": 900.0, "arc": 360.0,
	"shots": 1, "pierce": 0, "fire_chance": 0.0, "spread": 0.0, "splash": 0.0, "pass_shields": false,
	"ammo": "", "jam_chance": 0.0, "heat_per_shot": 0.0,
	"turret": false, "gimbal": 0.0, "track": 90.0, "accuracy": 0.75}  # ammo: cargo item id used per shot; jam_chance: per shot; heat_per_shot: added to the part; gimbal (fixed guns) and arc, track, accuracy (turrets): see the top
## Fire group (LMB = 1, RMB = 2) by kind; an entry's own `group` wins.
const GROUPS := {"laser": 1, "bolt": 1, "beam": 1, "missile": 2, "flak": 2}
const KIND_DEFAULTS := {
	"laser": {},
	"bolt": {"speed": 700.0},
	"flak": {"speed": 600.0, "shots": 5, "spread": 12.0},
	"missile": {"speed": 300.0, "turn": 1.5, "splash": 2.0, "pass_shields": true},
	"beam": {"duration": 2.0, "tick": 0.25},  # damage is per second, dealt every `tick` seconds
}

const ON_TARGET_DEG := 4.0  ## a turret fires when its barrel is this close to the lead direction
const SPEED_EVASION := 0.25  ## evasion of a ship at full speed (docs/CONTENT.md 4)
const MISS_MARGIN := 40.0  ## px past the hull's edge that a missed turret shot aims at

var defs := {}  ## weapon id -> entry as written in the data file
var turret_damage := 0.6  ## the share of its entry's damage that a turret deals


func _init(path := PATH) -> void:
	if path != "":
		load_defs(path)


func load_defs(path: String) -> void:
	var data = Content.read(path)
	assert(data is Dictionary and data.get("weapons") is Dictionary, "bad weapon data: " + path)
	defs = data["weapons"]
	turret_damage = float(data.get("turret_damage", turret_damage))


func has(id: String) -> bool:
	return defs.has(id)


## The full stats of weapon `id`: base values, then the kind's defaults, then its own entry. A
## turret's damage is turret_damage of the entry's (the fixed equivalent at its tier).
func def(id: String) -> Dictionary:
	var e: Dictionary = defs.get(id, {})
	var out := BASE.duplicate()
	out.merge(KIND_DEFAULTS.get(e.get("kind", "laser"), {}), true)
	out.merge(e, true)
	out["id"] = id  # the art looks for art/projectiles/<id> before the kind's
	if out["turret"]:
		out["damage"] = float(out["damage"]) * turret_damage
	return out


## The fire group (1 or 2) of weapon `id`: its `group` entry, else by kind (lasers, bolts and beams 1; missiles and flak 2).
func group_of(id: String) -> int:
	var w := def(id)
	return int(w["group"]) if w.has("group") else int(GROUPS.get(w["kind"], 1))


## A mount for every placed component that has weapon stats: {uid: {id, pos (the barrel's pivot, cell
## coordinates), dir (outward, ship-local unit vector), reach (cells from the pivot to the muzzle), aim
## (the barrel's live direction, ship-local; starts as dir), virtual: false}}. A part with no outside
## half pivots at the middle of its inside half and fires from there.
func mounts_of(ship) -> Dictionary:
	var out := {}
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		if not has(inst["id"]):
			continue
		var dir := Vector2(Mounts.outward(inst["rot"]))
		var pos := Vector2.ZERO
		var reach := 0.0
		if ship.components.has_outside(uid):
			var b := Mounts.barrel(ship.components.def(inst["id"]), inst["out_anchor"], inst["rot"])
			pos = b["pivot"]
			reach = b["reach"]
		else:
			for c in inst["cells"]:
				pos += Vector2(c) + Vector2(0.5, 0.5)
			pos /= inst["cells"].size()
		out[uid] = {"id": inst["id"], "pos": pos, "dir": dir, "reach": reach, "aim": dir, "virtual": false}
	return out


## The part's state when it is out of action ("malfunction" for a jam, "overheated", "disabled"), else "ok".
func status_of(arena, idx: int, uid: int) -> String:
	var co = arena.ships[idx]
	var m = co.mounts.get(uid)
	if m == null:
		return "ok"
	if m["virtual"]:
		return "malfunction" if m.get("jammed", false) else "ok"
	var inst = co.ship.components.instances.get(uid)
	if inst == null:
		return "ok"
	match co.ship.components.offline_reason(co.ship.grid, uid):
		"outside half disabled":
			return "disabled"
		"link cut":
			return "offline"
	return str(inst.get("status", "ok"))


## Put a jammed (or otherwise stopped) mount back to work, like a crew repair.
func repair(arena, idx: int, uid: int) -> void:
	var co = arena.ships[idx]
	var m = co.mounts.get(uid)
	if m == null:
		return
	if m["virtual"]:
		m.erase("jammed")
	else:
		co.ship.repair(uid)
	co.dirty = true


## "" when mount `uid` of ship `idx` can fire at the world point `aim`, else why not: wrecked, no
## such weapon, its status (malfunction, overheated, disabled: an outside half shot out; offline: a
## cut link), unpowered, no ammo, cooling down. A fixed gun fires wherever it points, so it is never
## out of arc; a turret is, when the enemy it would shoot at is outside its arc, and has "no target"
## when nothing is left to shoot at (`aim` is not used by a turret).
func can_fire(arena, idx: int, uid: int, aim: Vector2) -> String:
	var co = arena.ships[idx]
	if co.wrecked:
		return "wrecked"
	var m = co.mounts.get(uid)
	if m == null:
		return "no such weapon"
	arena.sync(idx)
	var status := status_of(arena, idx, uid)
	if status != "ok":
		return status
	if not (m["powered"] if m["virtual"] else co.powered.get(uid, false)):
		return "unpowered"
	var w := def(m["id"])
	var ammo := str(w["ammo"])
	if ammo != "" and co.ship.inventory.count(ammo) < maxi(Effects.ammo_cost(m, w), 1):
		return "no ammo"
	if arena.tick < int(co.cooldowns.get(uid, 0)):
		return "cooling down"
	if w["turret"]:
		var mis = missile_target(arena, idx, m, w)
		var tgt := target_of(arena, idx)
		if tgt < 0 and mis == null:
			return "no target"
		if not in_arc(arena, idx, m, missile_point(arena, idx, m, w, mis) if mis != null else lead_point_of(arena, idx, m, tgt)):
			return "out of arc"
	return ""


## Can mount `mount` of ship `idx` bear on the world point `aim`? A fixed gun, when the point lies inside
## its gimbal cone (else it fires along the edge of that cone); a turret, inside its arc.
func in_arc(arena, idx: int, mount: Dictionary, aim: Vector2) -> bool:
	var to_aim: Vector2 = aim - arena.local_to_world(idx, mount["pos"])
	if to_aim.length_squared() < 1e-6:
		return false
	var w := def(mount["id"])
	var limit := float(w["arc"]) * 0.5 if w["turret"] else float(w["gimbal"])
	if limit >= 180.0:
		return true
	var local: Vector2 = to_aim.rotated(-arena.ships[idx].flight.angle)
	return absf(Vector2(mount["dir"]).angle_to(local)) <= deg_to_rad(limit) + 1e-6


## The direction (ship-local unit vector) a fixed gun `mount` of ship `idx` fires along toward the
## world point `aim`: toward it, but at most `gimbal` degrees off the mount's outward direction.
func fixed_dir(arena, idx: int, mount: Dictionary, aim: Vector2) -> Vector2:
	var want: Vector2 = (aim - arena.local_to_world(idx, mount["pos"])).rotated(-arena.ships[idx].flight.angle)
	return clamp_dir(want, mount["dir"], float(def(mount["id"])["gimbal"]))


## `want` turned toward `centre` until it is at most `limit_deg` degrees off it (a unit vector). Both
## directions as ship-local vectors; a zero `want` gives `centre`.
static func clamp_dir(want: Vector2, centre: Vector2, limit_deg: float) -> Vector2:
	if want.length_squared() < 1e-9:
		return centre
	if limit_deg >= 180.0:
		return want.normalized()
	var lim := deg_to_rad(limit_deg)
	return centre.rotated(clampf(centre.angle_to(want), -lim, lim))


## Point the barrel of fixed gun `uid` of ship `idx` at the world point `aim` (its gimbal limits how
## far it turns): what the view draws, and where the next shot goes. A turret turns itself.
func point_barrel(arena, idx: int, uid: int, aim: Vector2) -> void:
	var m = arena.ships[idx].mounts.get(uid)
	if m != null and not def(m["id"])["turret"]:
		m["aim"] = fixed_dir(arena, idx, m, aim)


## Where a shot of mount `m` (ship `idx`) leaves, in the world: the muzzle, `reach` cells along its barrel.
func muzzle_of(arena, idx: int, m: Dictionary) -> Vector2:
	return arena.local_to_world(idx, m["pos"] + Vector2(m["aim"]) * float(m["reach"]))


## Fire mount `uid` of ship `idx` at the world point `aim`. Returns false (and does nothing) when
## can_fire() says no. Lasers resolve at once, projectiles are launched, a beam starts burning. A
## fixed gun fires along its gimbal-limited direction toward `aim`; a turret at the enemy ship
## (target_of), rolling its hit (see the top).
func fire(arena, idx: int, uid: int, aim: Vector2) -> bool:
	if can_fire(arena, idx, uid, aim) != "":
		return false
	var co = arena.ships[idx]
	var m: Dictionary = co.mounts[uid]
	var w := Effects.adjust(arena, idx, uid, m, def(m["id"]))  # less power or rate without the operator or crew it needs
	co.cooldowns[uid] = arena.tick + int(ceil(float(w["cooldown"]) / arena.SUBSTEP - 1e-6))
	var mis = missile_target(arena, idx, m, w) if w["turret"] else null  # point defence shoots a missile before a ship
	if w["turret"]:
		var point: Vector2 = missile_point(arena, idx, m, w, mis) if mis != null else _turret_point(arena, idx, uid, m, w, target_of(arena, idx))
		var want: Vector2 = (point - arena.local_to_world(idx, m["pos"])).rotated(-co.flight.angle)
		m["aim"] = clamp_dir(want, m["dir"], float(w["arc"]) * 0.5)
	else:
		m["aim"] = fixed_dir(arena, idx, m, aim)
	var origin: Vector2 = muzzle_of(arena, idx, m)
	var dir: Vector2 = Vector2(m["aim"]).rotated(co.flight.angle)
	arena.log_event("shot", idx, Vector2i(-1, -1), {"weapon": m["id"], "uid": uid, "kind": w["kind"], "origin": origin, "dir": dir})
	_spend(arena, idx, uid, m, w)
	if mis != null:
		_intercept(arena, idx, w, origin, mis)
		Effects.on_fire(arena, idx, uid, m, w)
		return true  # (a point-defence shot leaves through its own port: it does not open the shield)
	if w["kind"] == "beam":
		var every := maxi(1, roundi(float(w["tick"]) / arena.SUBSTEP))
		arena.beams.append({"owner": idx, "uid": uid, "w": w, "local_dir": m["aim"],
			"end": arena.tick + int(ceil(float(w["duration"]) / arena.SUBSTEP - 1e-6)), "every": every, "next": arena.tick + 1})
	else:
		var spread := deg_to_rad(float(w["spread"]))
		for i in int(w["shots"]):
			var d := dir
			if spread > 0.0:
				d = dir.rotated(arena.rng.randf_range(-spread * 0.5, spread * 0.5))
			if w["kind"] == "laser":
				_line(arena, idx, w, m["id"], origin, origin + d * float(w["range"]))
			else:
				Projectiles.spawn(arena, idx, w, origin, d)
	Effects.on_fire(arena, idx, uid, m, w)
	Shields.drop(arena, idx, w, origin, dir)  # after the shots: those in contact this tick were resolved first
	return true


# --- turrets ------------------------------------------------------------------------------------

## The ship a turret of `idx` shoots at: the nearest ship that is not wrecked; -1 when none.
func target_of(arena, idx: int) -> int:
	var best := -1
	var best_d := INF
	for i in arena.ships.size():
		if i == idx or arena.ships[i].wrecked:
			continue
		var d: float = arena.ships[i].flight.pos.distance_squared_to(arena.ships[idx].flight.pos)
		if d < best_d:
			best_d = d
			best = i
	return best


## The enemy missile (an entry of arena.projectiles) turret mount `m` of ship `idx` would shoot down now: the nearest one within the
## `intercept` range of its entry `w`, or null (a weapon without the effect, or no missile near).
func missile_target(arena, idx: int, m: Dictionary, w: Dictionary):
	var spec = Effects.of(w).get("intercept")
	if not spec is Dictionary:
		return null
	var from: Vector2 = arena.local_to_world(idx, m["pos"])
	var best = null
	var best_d := float(spec["range"]) * float(spec["range"])
	for p in arena.projectiles:
		if p["owner"] == idx or str(p["w"]["kind"]) != "missile":
			continue
		var d := from.distance_squared_to(p["pos"])
		if d <= best_d:
			best_d = d
			best = p
	return best


## The world point turret mount `m` of ship `idx` aims at to hit the missile `mis`, with perfect lead for the shot's speed.
func missile_point(arena, idx: int, m: Dictionary, w: Dictionary, mis: Dictionary) -> Vector2:
	var speed := float(w["speed"]) if w["kind"] in ["bolt", "flak", "missile"] else 0.0
	return PilotAI.lead_point(arena.local_to_world(idx, m["pos"]), mis["pos"], mis["vel"], speed)


## A point-defence shot at the missile `mis` from `origin`: a tracer to where it is, and it is destroyed when the shot rolls
## its accuracy (no evasion: a missile does not dodge). Logs an `intercept` effect event ({weapon, hit}, at the missile).
func _intercept(arena, idx: int, w: Dictionary, origin: Vector2, mis: Dictionary) -> void:
	var id := str(w["id"])
	var hit: bool = arena.rng.randf() < float(w["accuracy"])
	arena.log_event("beam", idx, Vector2i(-1, -1), {"weapon": id, "from": origin, "to": mis["pos"], "dtype": w["damage_type"], "shield": false, "bounce": false})
	arena.log_event("effect", idx, Vector2i(-1, -1), {"kind": "intercept", "weapon": id, "hit": hit, "pos": mis["pos"]})
	if hit:
		arena.projectiles.erase(mis)


## Evasion of ship `idx` (docs/CONTENT.md 4): 0.25 x speed / max speed, plus a manned helm's bonus and
## any running ability's.
func evasion(arena, idx: int) -> float:
	var co = arena.ships[idx]
	var e: float = SPEED_EVASION * co.flight.vel.length() / maxf(co.flight.max_speed, 1.0)
	return e + Jobs.evasion_bonus(co.ship) + Abilities.evasion_add(co.ship)


## The chance a shot of turret `uid` of ship `idx` hits ship `target`: its accuracy less the target's evasion.
func hit_chance(arena, idx: int, uid: int, target: int) -> float:
	return clampf(float(def(arena.ships[idx].mounts[uid]["id"])["accuracy"]) + Hazards.accuracy_add(arena) - evasion(arena, target), 0.0, 1.0)


## The world point turret mount `m` of ship `idx` should aim at to hit ship `target`'s middle, with
## perfect lead for the shot's speed.
func lead_point_of(arena, idx: int, m: Dictionary, target: int) -> Vector2:
	var w := def(m["id"])
	var tc = arena.ships[target]
	var speed := float(w["speed"]) if w["kind"] in ["bolt", "flak", "missile"] else 0.0
	return PilotAI.lead_point(arena.local_to_world(idx, m["pos"]), tc.flight.pos, tc.flight.vel, speed)


## One shot of a turret: roll for a hit (accuracy less evasion, on the arena's rng). A hit gives a random
## outer cell of ship `target` that faces the turret, led; a miss a point just off the hull, on a
## random side. The world point to aim at.
func _turret_point(arena, idx: int, uid: int, m: Dictionary, w: Dictionary, target: int) -> Vector2:
	var tc = arena.ships[target]
	var pivot: Vector2 = arena.local_to_world(idx, m["pos"])
	var speed := float(w["speed"]) if w["kind"] in ["bolt", "flak", "missile"] else 0.0
	var hit: bool = arena.rng.randf() < hit_chance(arena, idx, uid, target)
	var cells := facing_cells(arena, target, pivot)
	if hit and not cells.is_empty():
		var local := Vector2(cells[arena.rng.randi_range(0, cells.size() - 1)]) + Vector2(0.5, 0.5)
		return PilotAI.lead_point(pivot, arena.local_to_world(target, local), _point_velocity(tc, local), speed)
	var side := 1.0 if arena.rng.randf() < 0.5 else -1.0
	var away: Vector2 = (tc.flight.pos - pivot).normalized().rotated(side * PI / 2.0)
	var edge: Vector2 = tc.flight.pos + away * (float(Collisions.hit_cells(arena, target)["radius"]) + MISS_MARGIN)
	return PilotAI.lead_point(pivot, edge, tc.flight.vel, speed)


## The outer cells of ship `target` (Collisions.hit_cells) that have a free face looking toward the
## world point `from`, in (y, x) order.
func facing_cells(arena, target: int, from: Vector2) -> Array:
	var tc = arena.ships[target]
	var hc := Collisions.hit_cells(arena, target)
	var out := []
	for c in hc["cells"]:
		var info: Dictionary = hc["info"][c]
		var centre: Vector2 = tc.flight.pos + Vector2(info["ctr"]).rotated(tc.flight.angle)
		for k in info["n"].size():
			if info["e"][k] and Vector2(info["n"][k]).rotated(tc.flight.angle).dot(from - centre) > 0.0:
				out.append(c)
				break
	return out


## Velocity of the point of ship `co` at ship-local `local` (its drift plus its spin).
static func _point_velocity(co, local: Vector2) -> Vector2:
	var r: Vector2 = ((local - co.pivot) * 32.0).rotated(co.flight.angle)
	return co.flight.vel + r.rotated(PI / 2.0) * co.flight.ang_vel


## Turn the turrets of every ship toward their enemy for one substep (at `track` degrees per second,
## inside the arc) and fire the ones that are loaded and on target, unless the ship's autofire is off.
func tick_turrets(arena) -> void:
	for idx in arena.ships.size():
		var co = arena.ships[idx]
		if co.wrecked:
			continue
		var uids: Array = co.mounts.keys()
		uids.sort()
		for uid in uids:
			var m: Dictionary = co.mounts[uid]
			var w := def(m["id"])
			if not w["turret"] or status_of(arena, idx, uid) != "ok" or not (m["powered"] if m["virtual"] else co.powered.get(uid, false)):
				continue
			var tgt := target_of(arena, idx)
			var mis = missile_target(arena, idx, m, w)  # point defence turns on a missile before a ship
			if tgt < 0 and mis == null:
				continue
			var lead: Vector2 = missile_point(arena, idx, m, w, mis) if mis != null else lead_point_of(arena, idx, m, tgt)
			var want: Vector2 = (lead - arena.local_to_world(idx, m["pos"])).rotated(-co.flight.angle)
			var half := deg_to_rad(float(w["arc"]) * 0.5)
			var goal := clampf(Vector2(m["dir"]).angle_to(want), -half, half)  # the barrel's angle from dir that points best
			var cur := Vector2(m["dir"]).angle_to(m["aim"])
			var step: float = deg_to_rad(float(w["track"])) * arena.SUBSTEP
			cur += clampf(angle_difference(cur, goal), -step, step)
			m["aim"] = Vector2(m["dir"]).rotated(cur)
			if arena.autofire.get(idx, true) and absf(angle_difference(cur, Vector2(m["dir"]).angle_to(want))) <= deg_to_rad(ON_TARGET_DEG) \
					and arena.cooldown_left(idx, uid) <= 0.0 and (mis != null or _in_range(arena, idx, m, w, tgt)):
				arena.fire(idx, uid, lead)


## Is some part of ship `target` within the range of weapon `w` of mount `m` (ship `idx`)?
func _in_range(arena, idx: int, m: Dictionary, w: Dictionary, target: int) -> bool:
	var tc = arena.ships[target]
	var from := muzzle_of(arena, idx, m)
	var hc := Collisions.hit_cells(arena, target)
	var reach := float(w["range"])
	for c in hc["cells"]:
		if from.distance_to(tc.flight.pos + Vector2(hc["info"][c]["ctr"]).rotated(tc.flight.angle)) <= reach:
			return true
	return false


## What one shot costs: its ammo from the cargo, heat in the part, and the roll to jam it (the part,
## or a virtual mount, stops until repaired). The jam roll is only made for weapons that can jam.
func _spend(arena, idx: int, uid: int, m: Dictionary, w: Dictionary) -> void:
	var co = arena.ships[idx]
	if str(w["ammo"]) != "":
		co.ship.inventory.add(str(w["ammo"]), -Effects.ammo_cost(m, w, true))
	var inst = null if m["virtual"] else co.ship.components.instances.get(uid)
	if inst != null:
		inst["heat"] = float(inst.get("heat", 0.0)) + float(w["heat_per_shot"])
	var chance := float(w["jam_chance"])
	if chance > 0.0 and (chance >= 1.0 or arena.rng.randf() < chance):
		if inst != null:
			inst["status"] = "malfunction"
			co.ship.log_event("%s jammed" % co.ship.components.def(inst["id"]).get("name", inst["id"]))
		else:
			m["jammed"] = true
		co.dirty = true
		arena.log_event("jam", idx, Vector2i(-1, -1), {"uid": uid, "weapon": m["id"]})


## A hitscan line of weapon `w` from `from` to `to` (world); a "beam" event says where each part of it
## ended: one, or two when a cell glanced it off and it bounced once (the second has bounce true).
func _line(arena, idx: int, w: Dictionary, id: String, from: Vector2, to: Vector2) -> void:
	for seg in Projectiles.hitscan(arena, idx, w, from, to):
		arena.log_event("beam", idx, Vector2i(-1, -1), {"weapon": id, "from": seg["from"], "to": seg["to"], "dtype": w["damage_type"], "shield": seg["shield"], "bounce": seg["bounce"]})


## Burn the active beams for one substep: each ends after its duration, with its ship wrecked or
## its mount unpowered, and deals damage x tick length every `every` substeps along its line.
func tick_beams(arena) -> void:
	var live: Array = []
	for b in arena.beams:
		var co = arena.ships[b["owner"]]
		var m = co.mounts.get(b["uid"])  # a wrecked weapon is gone
		if m == null or arena.tick > b["end"] or co.wrecked or not (m["powered"] if m["virtual"] else co.powered.get(b["uid"], false)):
			continue
		live.append(b)
		if arena.tick < b["next"]:
			continue
		b["next"] += b["every"]
		var w: Dictionary = b["w"].duplicate()
		w["damage"] = float(w["damage"]) * b["every"] * arena.SUBSTEP
		w["fx_k"] = float(b["every"]) * arena.SUBSTEP  # the effects that act per hit (shard, magnetic) scale the same way
		var origin: Vector2 = arena.local_to_world(b["owner"], m["pos"] + Vector2(b["local_dir"]) * float(m["reach"]))
		var d: Vector2 = b["local_dir"].rotated(co.flight.angle)
		_line(arena, b["owner"], w, m["id"], origin, origin + d * float(w["range"]))
	arena.beams = live
