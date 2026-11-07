extends RefCounted
## Volley fire (docs/GUNS.md 14). Every fire group of a ship (LMB, RMB, Q, AUTO) is in Ripple mode (each gun fires as it is ready: today's
## behaviour) or Volley mode (`ship.volley_groups`, copied to `Combatant.volley` when the fight starts; the enemy's `ai_volley` puts all its
## non-rapid guns in Volley). arena.fire() hands the fire order of a Volley gun to request() instead of firing it. tick() then
## watches each group: while a gun of it keeps asking (the button is held, the AUTO turret is on target, the pilot wants to shoot) and
## another gun of the group is still cooling or feeding, the asking guns wait - at most MAX_WAIT_S after the first asked. When none is
## cooling they fire together, spread over STAGGER_S (a short stagger for the look). Guns that are unpowered, jammed, out of arc ... do not
## hold the volley up. The shots leave within a fraction of a second, so the sector they cross opens once (shields.gd merges the windows)
## and the ship's shield stays up longer; the mode has no bonus of its own (docs/GUNS.md 14).
## Point defence (intercept) and rapid guns never join a volley. Deterministic: no randomness here.

const STAGGER_S := 0.15  ## the volley's shots leave over this long
const MAX_WAIT_S := 3.0  ## the longest the guns wait for the slowest one
const READY_GRACE := 2  ## substeps a gun that just came off cooldown is given to ask before the others go without it
const FRESH_TICKS := 10  ## a fire order counts for this many substeps (the player's button is read once a frame)


## Is `w` (a Weapons.def()) point defence? It shoots down what comes at the ship and never waits for anybody.
static func is_pd(w: Dictionary) -> bool:
	return w.get("effects") is Dictionary and w["effects"].has("intercept")


## Does the fire order of mount `uid` of ship `idx` go through the volley (its group is in Volley mode)?
static func mode(arena, idx: int, uid: int) -> bool:
	var co = arena.ships[idx]
	var m = co.mounts.get(uid)
	if m == null:
		return false
	var w: Dictionary = arena.weapons.def(m["id"])
	if is_pd(w):
		return false
	if bool(w.get("rapid", false)):
		return false  # a rapid gun is a spam weapon by nature: it always ripples
	if co.ai_volley:
		return true
	return not co.volley.is_empty() and bool(co.volley.get(arena.weapons.mount_group(arena, idx, uid), false))


## The group of ship `idx` is in Volley mode (what the header shows).
static func group_on(arena, idx: int, group: int) -> bool:
	return bool(arena.ships[idx].volley.get(group, false))


## Mount `uid` wants to fire at `aim` (arena.fire() in Volley mode): remember it for its group. Always false: tick() fires.
static func request(arena, idx: int, uid: int, aim: Vector2) -> bool:
	if arena.weapons.can_fire(arena, idx, uid, aim) != "":
		return false
	var g: int = arena.weapons.mount_group(arena, idx, uid)
	var key := idx * 8 + g
	if not arena.volleys.has(key):
		arena.volleys[key] = {"idx": idx, "group": g, "req": {}, "wait": -1, "pending": []}
	arena.volleys[key]["req"][uid] = {"tick": arena.tick, "aim": aim}
	return false


## One substep: fire the shots of a volley that are due, and start a volley when the group is ready (see the top).
static func tick(arena) -> void:
	var keys: Array = arena.volleys.keys()
	keys.sort()
	for key in keys:
		var v: Dictionary = arena.volleys[key]
		var idx: int = v["idx"]
		var rest := []
		for p in v["pending"]:
			if int(p["tick"]) <= arena.tick:
				_shoot(arena, idx, p["uid"], p["aim"])
			else:
				rest.append(p)
		v["pending"] = rest
		var fresh := {}
		for uid in v["req"]:
			if arena.tick - int(v["req"][uid]["tick"]) <= FRESH_TICKS:
				fresh[uid] = v["req"][uid]
		v["req"] = fresh
		if fresh.is_empty():
			v["wait"] = -1
			if rest.is_empty():
				arena.volleys.erase(key)
			continue
		if not rest.is_empty():
			continue  # the last volley is still leaving
		var asking: Array = fresh.keys()
		asking.sort()
		if _cooling(arena, idx, v["group"], fresh, fresh[asking[0]]["aim"]):
			if int(v["wait"]) < 0:
				v["wait"] = arena.tick
			if arena.tick - int(v["wait"]) < ceili(MAX_WAIT_S / arena.SUBSTEP - 1e-6):
				continue
		v["wait"] = -1
		v["req"] = {}
		var span := ceili(STAGGER_S / arena.SUBSTEP - 1e-6)
		for i in asking.size():
			v["pending"].append({"tick": arena.tick + (roundi(float(i * span) / float(asking.size() - 1)) if asking.size() > 1 else 0), "uid": asking[i], "aim": fresh[asking[i]]["aim"]})
		var left := []
		for p in v["pending"]:
			if int(p["tick"]) <= arena.tick:
				_shoot(arena, idx, p["uid"], p["aim"])
			else:
				left.append(p)
		v["pending"] = left


## Is a gun of the group (other than the asking ones) still cooling down or waiting for its belt: the volley holds for it.
static func _cooling(arena, idx: int, group: int, asking: Dictionary, aim: Vector2) -> bool:
	var uids: Array = arena.ships[idx].mounts.keys()
	uids.sort()
	for uid in uids:
		if asking.has(uid) or not mode(arena, idx, uid) or arena.weapons.mount_group(arena, idx, uid) != group:
			continue
		var why: String = arena.weapons.can_fire(arena, idx, uid, aim)
		if why in ["cooling down", "feeding"]:
			return true
		var cd: int = int(arena.ships[idx].cooldowns.get(uid, 0))
		if why == "" and cd > 0 and arena.tick - cd <= READY_GRACE:
			return true  # it only just became ready: its controller has not had a substep to ask yet
	return false


static func _shoot(arena, idx: int, uid: int, aim: Vector2) -> void:
	arena.volley_exec = true
	arena.fire(idx, uid, aim)
	arena.volley_exec = false
