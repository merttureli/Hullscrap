extends RefCounted
## Racial weapon effects (docs/CONTENT.md section 17). A weapon entry of data/weapons.json may carry
## `"effects": {...}`: a Dictionary of the keys below (an old-style list of tags, ["lock_doors"], stays
## valid and means nothing here). Every effect is built once, here, and read from data.
## On the target, when a shot first meets a ship's cells (a shield that stops the shot stops the effect too):
##   acid {dps, seconds, type?, spread?}  the hit cell takes dps damage a second for `seconds` (never wrecks a part that is already out);
##                                    spread: each 0.25 s tick the acid has this chance (0 to 1) to creep to one more neighbouring wall, door or part (once each, at most ACID_MAX_CELLS)
##   spores {o2_drain, seconds}       the room hit loses o2_drain of its air (a fraction of full pressure) a second
##   shard {splinters, dmg}           `splinters` of the neighbouring solid cells take dmg each (the weapon's damage type)
##   sonic {stun_s}                   the crew in the room hit are stunned: no walking, no work
##   magnetic {pull}                  the target ship is pulled toward the shooter: it gains `pull` px/s at PULL_MASS (lighter ships more); debris within DEBRIS_RADIUS is dragged too
##   frost {slow, seconds}            the system hit (a wall: the systems in the room hit) charges slower: its weapon cooldown, shield recharge and ability cooldowns run at 1 - slow
##   corrode {resist_mult, seconds}   the wall or door hit takes 1 / resist_mult times the damage
##   split_on_shield {count, damage_mult}  when a shield stops the shot, `count` weaker shots (damage x damage_mult) fan out from just outside the
##                                    bubble and meet it again: each uses a layer, or reaches the hull where the sector is down. They do not split again.
##                                    Needs a shot with a speed (bolt, flak, missile), not a laser or beam
## On the shooter, per shot:
##   self_room {o2_drain, heat, fire_chance, shock_dps}   the room of the weapon's inside half loses o2_drain of its air, its parts gain `heat`, a fire may start, organic crew take shock_dps a second while it fires
##   needs_operator {species, else_mult, stat?}           full damage (stat "damage", the default) or rate ("rate") only while a crew member of `species` (an id or a list) mans it; else x else_mult
##   needs_crew_in_room {count, else_mult, stat?}         the same with `count` crew in the weapon's room (stat defaults to "rate")
##   ammo_mult                                            ammo per shot x this (1.5 spends 1, 2, 1, 2 ...)
## A beam applies its effects every tick; acid, spores, sonic, frost and corrode refresh instead of stacking,
## magnetic and shard scale with the tick (`fx_k`, set by Weapons.tick_beams).
## State lives on the arena (`arena.fx`, see fresh) and is stepped by tick(); everything is deterministic
## (the arena's rng picks the splinters and the fire roll). Each effect logs an "effect" arena event
## ({kind, weapon, ...}) that effect_fx.gd turns into pictures.

const Damage = preload("res://scripts/combat/damage.gd")
const Fire = preload("res://scripts/sim/fire.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")

const TAGS: Array[String] = ["lock_doors", "drain_power", "tether"]  ## the old list-style effect tags
const NONE := {}
const TICK := 0.25  ## seconds between the hits of a damage over time
const ROOM_REACH := 6.0  ## cells a shot is followed into the hull to find the room it hits
const PULL_MASS := 1000.0  ## the ship mass at which magnetic `pull` is a speed in px/s
const DEBRIS_RADIUS := 320.0  ## px round the impact within which magnetic drags debris
const DEBRIS_DAMPING := 0.25  ## per second
const MIN_MULT := 0.05  ## the smallest else_mult
const SPLIT_BACK := 8.0  ## px outside the bubble that the shots of a split_on_shield start
const SPLIT_FAN_DEG := 25.0  ## the split shots fan out this many degrees each side of the shot that was stopped
const ACID_MAX_CELLS := 12  ## the most cells one acid cloud (a `spread` acid) eats at once
## Required numbers of each effect: key -> [lowest, highest]. Optional keys are in OPTIONAL.
const SPEC := {
	"acid": {"dps": [0.001, 100.0], "seconds": [0.1, 60.0]},
	"spores": {"o2_drain": [0.001, 5.0], "seconds": [0.1, 60.0]},
	"shard": {"splinters": [1.0, 8.0], "dmg": [0.001, 100.0]},
	"sonic": {"stun_s": [0.1, 30.0]},
	"magnetic": {"pull": [0.001, 1000.0]},
	"frost": {"slow": [0.01, 0.95], "seconds": [0.1, 60.0]},
	"corrode": {"resist_mult": [0.05, 1.0], "seconds": [0.1, 60.0]},
	"split_on_shield": {"count": [1.0, 8.0], "damage_mult": [0.05, 1.0]},
	"needs_operator": {"else_mult": [MIN_MULT, 1.0]},
	"needs_crew_in_room": {"count": [1.0, 12.0], "else_mult": [MIN_MULT, 1.0]},
}
const OPTIONAL := {"acid": ["type", "spread"], "needs_operator": ["species", "stat"], "needs_crew_in_room": ["stat"]}
const SELF_ROOM := {"o2_drain": [0.0, 1.0], "heat": [0.0, 500.0], "fire_chance": [0.0, 1.0], "shock_dps": [0.0, 50.0]}
const STATS: Array[String] = ["damage", "rate"]
const DAMAGE_TYPES: Array[String] = ["kinetic", "energy", "explosive", "ion"]


# --- the data ---------------------------------------------------------------------------------------------

## The effects of weapon stats `w` (Weapons.def) as one Dictionary: its `effects` object, a list of tags as
## {tag: true}, and a top-level `ammo_mult` filed under its own name. Read it, do not change it.
static func of(w: Dictionary) -> Dictionary:
	var e = w.get("effects")
	var ammo := w.has("ammo_mult")
	if e is Dictionary and not ammo:
		return e
	if not (e is Dictionary or e is Array or ammo):
		return NONE
	var out := {}
	if e is Dictionary:
		out = e.duplicate()
	elif e is Array:
		for t in e:
			out[str(t)] = true
	if ammo and not out.has("ammo_mult"):
		out["ammo_mult"] = w["ammo_mult"]
	return out


## What is wrong with the effects of weapon entry `entry` (data/weapons.json): one line each, [] when it is fine.
## `species`: the known species ids, to check needs_operator against (empty: not checked).
static func problems(entry: Dictionary, species: Array = []) -> Array[String]:
	var out: Array[String] = []
	var e = entry.get("effects")
	if entry.has("ammo_mult"):
		_check(out, "ammo_mult", entry["ammo_mult"], 0.1, 20.0)
	if e == null:
		return out
	if e is Array:
		if e.is_empty():
			out.append("effects is an empty list")
		for t in e:
			if not (t is String and t in TAGS):
				out.append("effects tag %s is not one of %s" % [str(t), str(TAGS)])
		return out
	if not e is Dictionary:
		out.append("effects must be a list of tags or an object")
		return out
	if e.is_empty():
		out.append("effects is empty")
	for k in e:
		var v = e[k]
		if k in TAGS:
			continue
		elif k == "ammo_mult":
			_check(out, "ammo_mult", v, 0.1, 20.0)
		elif k == "self_room":
			_self_room_problems(out, v)
		elif SPEC.has(k):
			_spec_problems(out, str(k), v, species)
			if k == "split_on_shield" and str(entry.get("kind", "")) in ["laser", "beam"]:
				out.append("split_on_shield needs a shot that flies (a bolt, flak or missile), not a %s" % str(entry["kind"]))
		else:
			out.append("unknown effect '%s'" % str(k))
	return out


static func _spec_problems(out: Array[String], k: String, v, species: Array) -> void:
	if not v is Dictionary:
		out.append("%s must be an object" % k)
		return
	var allowed: Array = SPEC[k].keys() + OPTIONAL.get(k, [])
	for p in v:
		if not p in allowed:
			out.append("%s has an unknown key '%s'" % [k, str(p)])
	for p in SPEC[k]:
		if not v.has(p):
			out.append("%s needs '%s'" % [k, p])
		else:
			_check(out, "%s.%s" % [k, p], v[p], SPEC[k][p][0], SPEC[k][p][1], p in ["splinters", "count"])
	if k == "acid" and v.has("spread"):
		_check(out, "acid.spread", v["spread"], 0.0, 1.0)
	if v.has("stat") and not str(v["stat"]) in STATS:
		out.append("%s.stat must be one of %s" % [k, str(STATS)])
	if v.has("type") and not str(v["type"]) in DAMAGE_TYPES:
		out.append("%s.type must be a damage type" % k)
	if k == "needs_operator":
		var sp = v.get("species")
		var ids: Array = sp if sp is Array else [sp]
		if sp == null or ids.is_empty():
			out.append("needs_operator needs a species (an id, or a list)")
		for id in ids:
			if not id is String or id == "":
				out.append("needs_operator species must be ids")
			elif not species.is_empty() and not id in species:
				out.append("needs_operator species '%s' is not a species" % id)


static func _self_room_problems(out: Array[String], v) -> void:
	if not v is Dictionary or v.is_empty():
		out.append("self_room must be an object with at least one key")
		return
	for p in v:
		if not SELF_ROOM.has(p):
			out.append("self_room has an unknown key '%s' (one of %s)" % [str(p), str(SELF_ROOM.keys())])
		else:
			_check(out, "self_room.%s" % p, v[p], SELF_ROOM[p][0], SELF_ROOM[p][1])


static func _check(out: Array[String], what: String, v, lo: float, hi: float, whole := false) -> void:
	if not (v is float or v is int) or float(v) < lo - 1e-9 or float(v) > hi + 1e-9:
		out.append("%s must be a number from %s to %s" % [what, str(lo), str(hi)])
	elif whole and not is_equal_approx(float(v), roundf(float(v))):
		out.append("%s must be a whole number" % what)


# --- state ----------------------------------------------------------------------------------------------

## A fresh arena.fx: {timed (running effects, see _timed), corroded (Vector3i(ship, x, y) -> [resist_mult, seconds left]), debris (bodies {pos, vel, mass} magnetic can drag),
## spawn (shots a split_on_shield made during this step: [owner, weapon, origin, dir]; Projectiles.step launches them)}.
static func fresh() -> Dictionary:
	return {"timed": [], "corroded": {}, "debris": [], "spawn": []}


## A piece of debris drifting in the arena for magnetic to drag: `mass` in the units of ship mass. Returns its index.
static func add_debris(arena, pos: Vector2, vel := Vector2.ZERO, mass := 20.0) -> int:
	arena.fx["debris"].append({"pos": pos, "vel": vel, "mass": maxf(mass, 1.0)})
	return arena.fx["debris"].size() - 1


## Start (or renew) a timed effect `e` under `key`: an effect already running under it takes the longer time and the stronger numbers.
static func _timed(arena, key: String, e: Dictionary) -> void:
	e["key"] = key
	for old in arena.fx["timed"]:
		if old["key"] == key:
			old["left"] = maxf(old["left"], e["left"])
			for p in ["dps", "rate", "slow", "stun", "spread"]:
				if e.has(p):
					old[p] = maxf(old[p], e[p])
			return
	arena.fx["timed"].append(e)


## Advance the running effects by `dt` seconds (the arena calls this every substep).
static func tick(arena, dt: float) -> void:
	var fx: Dictionary = arena.fx
	if fx["timed"].is_empty() and fx["corroded"].is_empty() and fx["debris"].is_empty():
		return
	var keep: Array = []
	for e in fx["timed"]:
		var co = arena.ships[e["ship"]]
		if co.wrecked:
			continue
		var step := minf(dt, float(e["left"]))
		e["left"] -= step
		var alive := true
		match e["k"]:
			"acid":
				alive = _tick_acid(arena, co, e, step)
			"spores":
				alive = _tick_spores(co, e, step)
			"shock":
				alive = _tick_shock(co, e, step)
			"frost":
				alive = _tick_frost(arena, co, e, step)
		if alive and e["left"] > 1e-9:
			keep.append(e)
	fx["timed"] = keep
	for key in fx["corroded"].keys():
		var c: Array = fx["corroded"][key]
		c[1] -= dt
		if c[1] <= 1e-9:
			fx["corroded"].erase(key)
	var damp := exp(-DEBRIS_DAMPING * dt)
	for d in fx["debris"]:
		d["pos"] += d["vel"] * dt
		d["vel"] *= damp


## Everything that matters for replay, as plain data.
static func summary(arena) -> Dictionary:
	var timed := []
	for e in arena.fx["timed"]:
		timed.append([e["key"], snappedf(float(e["left"]), 1e-6), e["cells"].size() if e.has("cells") else 0])
	var cor := {}
	for key in arena.fx["corroded"]:
		cor[str(key)] = [arena.fx["corroded"][key][0], snappedf(float(arena.fx["corroded"][key][1]), 1e-6)]
	var deb := []
	for d in arena.fx["debris"]:
		deb.append([d["pos"].x, d["pos"].y, d["vel"].x, d["vel"].y])
	return {"timed": timed, "corroded": cor, "debris": deb}


# --- the target: what a shot does where it lands --------------------------------------------------------

## The shot of weapon `w`, fired by ship `owner`, first met ship `idx` at `first` (Damage.march's `first`
## out: {cell, obj (Damage.solid_at), dir (the shot's heading, ship-local unit vector)}): apply its effects.
static func on_hit(arena, owner: int, idx: int, w: Dictionary, first: Dictionary) -> void:
	var fx := of(w)
	if fx.is_empty():
		return
	var cell: Vector2i = first["cell"]
	var id := str(w.get("id", ""))
	if fx.has("acid"):
		_acid(arena, idx, id, w, fx["acid"], cell)
	if fx.has("corrode") and first["obj"]["kind"] != "component":
		_corrode(arena, idx, id, fx["corrode"], cell)
	var ship = arena.ships[idx].ship
	var room := -1
	if fx.has("spores") or fx.has("sonic") or fx.has("frost"):
		room = room_hit(ship, cell, first["dir"])
	if fx.has("spores") and room >= 0:
		_spores(arena, idx, id, fx["spores"], cell, room)
	if fx.has("sonic") and room >= 0:
		_sonic(arena, idx, id, fx["sonic"], cell, room)
	if fx.has("shard"):
		_shard(arena, idx, id, w, fx["shard"], first)
	if fx.has("frost"):
		_frost(arena, idx, id, fx["frost"], first, room)
	if fx.has("magnetic"):
		_magnetic(arena, owner, idx, id, w, fx["magnetic"], cell)


## A shot of weapon `w`, fired by ship `owner`, was stopped by the shield of ship `idx` at the world point `point`, flying along the unit vector `dir`:
## split_on_shield sends its weaker shots on (queued in arena.fx["spawn"], Projectiles.step launches them), fanned out from just outside the bubble.
static func on_shield(arena, owner: int, idx: int, w: Dictionary, point: Vector2, dir: Vector2) -> void:
	var fx := of(w)
	if not fx.has("split_on_shield") or not w.has("speed"):
		return
	var spec: Dictionary = fx["split_on_shield"]
	var mult := float(spec["damage_mult"])
	var child := w.duplicate()
	child["damage"] = float(w["damage"]) * mult
	child["fx_k"] = float(w.get("fx_k", 1.0)) * mult  # shard and magnetic scale with it
	var kept := fx.duplicate()
	kept.erase("split_on_shield")  # a split shot does not split again
	child["effects"] = kept
	var n := roundi(float(spec["count"]))
	var origin := point - dir * SPLIT_BACK
	var dirs := []
	for i in n:
		var d := dir.rotated(0.0 if n == 1 else deg_to_rad(SPLIT_FAN_DEG) * (2.0 * float(i) / float(n - 1) - 1.0))
		dirs.append(d)
		arena.fx["spawn"].append([owner, child, origin, d])
	_log(arena, idx, arena.world_to_cell(idx, point), "split", str(w.get("id", "")), {"pos": point, "origin": origin, "dirs": dirs})


## The room a shot that struck `cell` heading `dir` (ship-local unit vector) reaches: the room at the cell, else the first
## one along its heading within ROOM_REACH cells, else one beside the cell. -1 for none (open space).
static func room_hit(ship, cell: Vector2i, dir: Vector2) -> int:
	var atm = ship.atmosphere
	var r: int = atm.room_at(cell)
	if r >= 0:
		return r
	var from := Vector2(cell) + Vector2(0.5, 0.5)
	var t := 0.5
	while t <= ROOM_REACH:
		var p := from + dir * t
		r = atm.room_at(Vector2i(floori(p.x), floori(p.y)))
		if r >= 0:
			return r
		t += 0.5
	for d in Fire.SIDES:
		r = atm.room_at(cell + d)
		if r >= 0:
			return r
	return -1


## The world point at the middle of room `room` of ship `idx`.
static func room_pos(arena, idx: int, room: int) -> Vector2:
	var cells: Array = arena.ships[idx].ship.atmosphere.rooms[room]["cells"]
	var sum := Vector2.ZERO
	for c in cells:
		sum += Vector2(c) + Vector2(0.5, 0.5)
	return arena.local_to_world(idx, sum / float(maxi(cells.size(), 1)))


static func _log(arena, idx: int, cell: Vector2i, kind: String, id: String, extra := {}) -> void:
	var e := {"kind": kind, "weapon": id}
	e.merge(extra, true)
	arena.log_event("effect", idx, cell, e)


static func _acid(arena, idx: int, id: String, w: Dictionary, spec: Dictionary, cell: Vector2i) -> void:
	var type := str(spec.get("type", w.get("damage_type", "energy")))
	if type == "ion":
		type = "energy"
	var key := "acid:%d:%d,%d" % [idx, cell.x, cell.y]
	for e in arena.fx["timed"]:  # a cell an acid cloud already eats is renewed through that cloud, not eaten twice
		if e["k"] == "acid" and e["ship"] == idx and cell in e["cells"]:
			key = e["key"]
	_timed(arena, key, {"k": "acid", "ship": idx, "cell": cell, "cells": [cell], "dps": float(spec["dps"]), "spread": float(spec.get("spread", 0.0)),
		"left": float(spec["seconds"]), "acc": 0.0, "type": type, "weapon": id})
	_log(arena, idx, cell, "acid", id)


## One step of an acid: every TICK seconds (and at its end) each cell of the cloud takes the damage of that time, and a
## spreading acid may creep on. A cell with nothing left to eat leaves the cloud. False when the cloud is done with.
static func _tick_acid(arena, co, e: Dictionary, step: float) -> bool:
	e["acc"] += step
	if e["acc"] < TICK - 1e-9 and e["left"] > 1e-9:
		return true
	var span: float = e["acc"]
	var amount: float = e["dps"] * span
	e["acc"] = 0.0
	var keep: Array = []
	for cell in e["cells"]:
		var obj := Damage.solid_at(co, cell)
		if obj.is_empty():
			continue
		if obj["kind"] == "component" and _part_hp(co, obj) <= 0.0:
			continue  # acid wears a part down to out of action, it does not finish it off
		Damage.apply(arena, e["ship"], cell, obj, amount, e["type"], {"dot": "acid", "weapon": e["weapon"]})
		keep.append(cell)
	e["cells"] = keep
	if float(e["spread"]) > 0.0 and not keep.is_empty() and e["left"] > 1e-9 and keep.size() < ACID_MAX_CELLS \
			and arena.rng.randf() < float(e["spread"]) * span / TICK:
		_creep(arena, co, e)
	return not keep.is_empty()


## The acid cloud `e` of ship `co` eats one more cell: a wall, door or part beside its cells (a part once, one that is already
## out of action never), and none that another cloud holds. Which one is the arena's rng's pick.
static func _creep(arena, co, e: Dictionary) -> void:
	var held := {}  # cells and parts any acid on this ship holds already
	for other in arena.fx["timed"]:
		if other["k"] == "acid" and other["ship"] == e["ship"]:
			_hold(co, other["cells"], held)
	_hold(co, e["cells"], held)
	var cands: Array = []
	for c in e["cells"]:
		for d in Fire.SIDES:
			var n: Vector2i = c + d
			var obj := Damage.solid_at(co, n)
			if obj.is_empty() or held.has(n) or cands.has(n):
				continue
			if obj["kind"] == "component" and (held.has(Damage.part_key(obj)) or _part_hp(co, obj) <= 0.0):
				continue
			cands.append(n)
	if cands.is_empty():
		return
	var pick: Vector2i = cands[arena.rng.randi_range(0, cands.size() - 1)]
	e["cells"].append(pick)
	_log(arena, e["ship"], pick, "acid", str(e["weapon"]), {"spread": true})


static func _hold(co, cells: Array, held: Dictionary) -> void:
	for c in cells:
		held[c] = true
		var obj := Damage.solid_at(co, c)
		if obj.get("kind", "") == "component":
			held[Damage.part_key(obj)] = true


static func _part_hp(co, obj: Dictionary) -> float:
	var inst = co.ship.components.instances.get(obj["uid"])
	if inst == null:
		return 0.0
	if obj.get("half", "") == "out":
		return float(inst["out_hp"])
	return float(inst.get("hp", co.ship.components.def(inst["id"]).get("hp", Damage.DEFAULT_COMPONENT_HP)))


static func _corrode(arena, idx: int, id: String, spec: Dictionary, cell: Vector2i) -> void:
	var key := Vector3i(idx, cell.x, cell.y)
	var mult := float(spec["resist_mult"])
	var left := float(spec["seconds"])
	var old = arena.fx["corroded"].get(key)
	if old != null:
		mult = minf(mult, old[0])
		left = maxf(left, old[1])
	arena.fx["corroded"][key] = [mult, left]
	_log(arena, idx, cell, "corrode", id)


static func _spores(arena, idx: int, id: String, spec: Dictionary, cell: Vector2i, room: int) -> void:
	var atm = arena.ships[idx].ship.atmosphere
	_timed(arena, "spores:%d:%d" % [idx, room], {"k": "spores", "ship": idx, "cell": atm.rooms[room]["cells"][0], "rate": float(spec["o2_drain"]),
		"left": float(spec["seconds"])})
	_log(arena, idx, cell, "spores", id, {"room_pos": room_pos(arena, idx, room), "room_size": atm.rooms[room]["size"]})


static func _tick_spores(co, e: Dictionary, step: float) -> bool:
	var atm = co.ship.atmosphere
	var room: int = atm.room_at(e["cell"])
	if room < 0:
		return false
	atm.consume(room, e["rate"] * step * float(atm.rooms[room]["size"]))
	return true


static func _sonic(arena, idx: int, id: String, spec: Dictionary, cell: Vector2i, room: int) -> void:
	var ship = arena.ships[idx].ship
	var n := 0
	for m in ship.crew:
		if ship.atmosphere.room_at(m.cell()) == room and not m.is_down():
			if m.stun <= 0.0:
				n += 1
			m.stun = maxf(m.stun, float(spec["stun_s"]))
	if n > 0:
		ship.log_event("Crew stunned by a sonic blast")
	_log(arena, idx, cell, "sonic", id, {"room_pos": room_pos(arena, idx, room), "stunned": n})


static func _shard(arena, idx: int, id: String, w: Dictionary, spec: Dictionary, first: Dictionary) -> void:
	var co = arena.ships[idx]
	var cell: Vector2i = first["cell"]
	var skip := Damage.part_key(first["obj"]) if first["obj"]["kind"] == "component" else ""
	var cands: Array = []  # [cell, obj] of the neighbours that are solid, a part once
	var seen := {}
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var c := cell + Vector2i(dx, dy)
			var obj := Damage.solid_at(co, c)
			if obj.is_empty():
				continue
			if obj["kind"] == "component":
				var key := Damage.part_key(obj)
				if key == skip or seen.has(key):
					continue
				seen[key] = true
			cands.append([c, obj])
	var n := mini(roundi(float(spec["splinters"])), cands.size())
	for i in n:  # a partial shuffle on the arena's rng picks which ones
		var j: int = arena.rng.randi_range(i, cands.size() - 1)
		var t = cands[i]
		cands[i] = cands[j]
		cands[j] = t
	var dmg := float(spec["dmg"]) * float(w.get("fx_k", 1.0))
	var targets := []
	for i in n:
		Damage.apply(arena, idx, cands[i][0], cands[i][1], dmg, str(w.get("damage_type", "kinetic")), {"splinter": true, "weapon": id})
		targets.append(arena.cell_to_world(idx, cands[i][0]))
	_log(arena, idx, cell, "shard", id, {"targets": targets})


static func _frost(arena, idx: int, id: String, spec: Dictionary, first: Dictionary, room: int) -> void:
	var co = arena.ships[idx]
	var uids: Array = []
	if first["obj"]["kind"] == "component":
		uids.append(int(first["obj"]["uid"]))
	elif room >= 0:  # a wall was hit: the cold fills the room behind it
		var keys: Array = co.ship.components.instances.keys()
		keys.sort()
		for uid in keys:
			if co.ship.atmosphere.room_at(co.ship.components.instances[uid]["anchor"]) == room:
				uids.append(uid)
	var at := []
	for uid in uids:
		_timed(arena, "frost:%d:%d" % [idx, uid], {"k": "frost", "ship": idx, "uid": uid, "slow": float(spec["slow"]), "left": float(spec["seconds"]), "acc": 0.0})
		at.append(arena.cell_to_world(idx, co.ship.components.instances[uid]["anchor"]))
	_log(arena, idx, first["cell"], "frost", id, {"parts": uids, "at": at})


## One step of a frost on part `uid`: whatever it is charging (a weapon's cooldown, the shield's recharge, an ability's
## cooldown) runs `slow` slower, by pushing its finish back.
static func _tick_frost(arena, co, e: Dictionary, step: float) -> bool:
	var uid: int = e["uid"]
	var inst = co.ship.components.instances.get(uid)
	if inst == null:
		return false
	e["acc"] += e["slow"]
	var whole := int(e["acc"] + 1e-9)
	e["acc"] -= whole
	if whole > 0 and co.cooldowns.has(uid) and int(co.cooldowns[uid]) > arena.tick:
		co.cooldowns[uid] = int(co.cooldowns[uid]) + whole
	if str(co.ship.components.def(inst["id"]).get("family", "")) == "shield" and co.ion_lock <= 0.0:
		for s in co.sectors:
			var timers: Array = co.sector_timers[s]
			for i in timers.size():
				timers[i] = Vector2(timers[i].x + e["slow"] * step, timers[i].y)
	for k in co.ship.ability_state["slots"]:
		var st: Dictionary = co.ship.ability_state["slots"][k]
		if st["uid"] == uid and st["active"] <= 0.0 and st["cd"] > 0.0:
			st["cd"] += e["slow"] * step
	return true


static func _magnetic(arena, owner: int, idx: int, id: String, w: Dictionary, spec: Dictionary, cell: Vector2i) -> void:
	if owner < 0 or owner == idx:
		return
	var co = arena.ships[idx]
	var gun: Vector2 = arena.ships[owner].flight.pos
	var to: Vector2 = gun - co.flight.pos
	if to.length() < 1.0:
		return
	var pull := float(spec["pull"]) * float(w.get("fx_k", 1.0)) * PULL_MASS
	co.flight.vel += to.normalized() * pull / co.mass
	var at: Vector2 = arena.cell_to_world(idx, cell)
	var dragged := 0
	for d in arena.fx["debris"]:
		if d["pos"].distance_to(at) <= DEBRIS_RADIUS:
			d["vel"] += (gun - d["pos"]).normalized() * pull / d["mass"]
			dragged += 1
	_log(arena, idx, cell, "magnetic", id, {"toward": gun, "dragged": dragged})


# --- the shooter: what a shot costs and needs -----------------------------------------------------------

## The stats of a shot of weapon `w` from mount `m` (uid `uid`) of ship `idx`: `w` itself, or a copy with the power or rate
## its needs_operator and needs_crew_in_room ask for and do not get.
static func adjust(arena, idx: int, uid: int, m: Dictionary, w: Dictionary) -> Dictionary:
	var fx := of(w)
	if not (fx.has("needs_operator") or fx.has("needs_crew_in_room")):
		return w
	var out := w.duplicate()
	var co = arena.ships[idx]
	if fx.has("needs_operator") and not operated(co, uid, fx["needs_operator"]):
		_scale(out, fx["needs_operator"], "damage")
	if fx.has("needs_crew_in_room") and crew_in_room(co, uid, m) < roundi(float(fx["needs_crew_in_room"]["count"])):
		_scale(out, fx["needs_crew_in_room"], "rate")
	return out


static func _scale(w: Dictionary, spec: Dictionary, default_stat: String) -> void:
	var mult := maxf(float(spec["else_mult"]), MIN_MULT)
	if str(spec.get("stat", default_stat)) == "rate":
		w["cooldown"] = float(w["cooldown"]) / mult
	else:
		w["damage"] = float(w["damage"]) * mult


## Is weapon `uid` of `co` manned right now by a crew member of the species `spec` names?
static func operated(co, uid: int, spec: Dictionary) -> bool:
	var who = co.ship.manned.get(uid)
	if who == null:
		return false
	var sp = spec.get("species", [])
	var ids: Array = sp if sp is Array else [sp]
	for m in co.ship.crew:
		if m.name == who and not m.is_down() and not m.is_stunned():
			return str(m.species) in ids
	return false


## The crew in the room of weapon `uid` (mount `m`) who can work: not down, not stunned.
static func crew_in_room(co, uid: int, m: Dictionary) -> int:
	var room: int = co.ship.atmosphere.room_at(weapon_cell(co, uid, m))
	var n := 0
	for c in co.ship.crew:
		if room >= 0 and co.ship.atmosphere.room_at(c.cell()) == room and not c.is_down() and not c.is_stunned():
			n += 1
	return n


## A cell of the inside half of mount `m` (uid `uid`) of `co`.
static func weapon_cell(co, uid: int, m: Dictionary) -> Vector2i:
	var inst = null if m["virtual"] else co.ship.components.instances.get(uid)
	if inst != null:
		return inst["anchor"]
	return Vector2i(floori(m["pos"].x), floori(m["pos"].y))


## How much ammo the next shot of mount `m` costs (ammo_mult, with the fraction carried from earlier shots); `commit` keeps the carry.
static func ammo_cost(m: Dictionary, w: Dictionary, commit := false) -> int:
	var acc := float(m.get("ammo_acc", 0.0)) + float(of(w).get("ammo_mult", 1.0))
	var n := int(acc + 1e-9)
	if commit:
		m["ammo_acc"] = acc - n
	return n


## Mount `m` (uid `uid`) of ship `idx` fired weapon `w`: its self_room costs.
static func on_fire(arena, idx: int, uid: int, m: Dictionary, w: Dictionary) -> void:
	var fx := of(w)
	var spec = fx.get("self_room")
	if not spec is Dictionary:
		return
	var co = arena.ships[idx]
	var ship = co.ship
	var cell := weapon_cell(co, uid, m)
	var room: int = ship.atmosphere.room_at(cell)
	if room < 0:
		return
	var id := str(w.get("id", ""))
	var seen := {}
	if float(spec.get("o2_drain", 0.0)) > 0.0:
		ship.atmosphere.consume(room, float(spec["o2_drain"]) * float(ship.atmosphere.rooms[room]["size"]))
		seen["o2"] = true
	if float(spec.get("heat", 0.0)) > 0.0:
		for part in ship.components.instances:
			var inst: Dictionary = ship.components.instances[part]
			if ship.atmosphere.room_at(inst["anchor"]) == room:
				inst["heat"] = float(inst.get("heat", 0.0)) + float(spec["heat"])
		seen["heat"] = true
	if float(spec.get("fire_chance", 0.0)) > 0.0 and arena.rng.randf() < float(spec["fire_chance"]):
		arena.log_event("ignite", idx, cell)
		seen["fire"] = true
	if float(spec.get("shock_dps", 0.0)) > 0.0:
		_timed(arena, "shock:%d:%d" % [idx, uid], {"k": "shock", "ship": idx, "cell": cell, "dps": float(spec["shock_dps"]),
			"left": maxf(float(w["cooldown"]), float(w.get("duration", 0.0)) if w["kind"] == "beam" else 0.0)})
		seen["shock"] = true
	if not seen.is_empty():
		_log(arena, idx, cell, "self_room", id, {"has": seen.keys(), "room_pos": room_pos(arena, idx, room)})


## One step of a shock: the organic crew in the room (not the mechanical ones) take dps a second.
static func _tick_shock(co, e: Dictionary, step: float) -> bool:
	var ship = co.ship
	var room: int = ship.atmosphere.room_at(e["cell"])
	if room < 0:
		return false
	for m in ship.crew:
		if ship.atmosphere.room_at(m.cell()) != room or m.is_down() or bool(TraitSet.of(m)["mechanical"]):
			continue
		m.hurt(e["dps"] * step)
		if m.is_down():
			m.job = {}
			m.path.clear()
			ship.log_event("%s is down" % m.name)
	return true
