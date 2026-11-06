extends RefCounted
## Drones and the drone bay (docs/DRONES.md sections 2, 3 and 7), headless. A bay is a hull mount (family `drone_bay`): its inside half holds one loaded
## drone kit (an item of kind `drone`, its stats in the item's `drone` entry; the kit is permanent, a launch spends drone parts: 1, 2 or 3 by tier)
## and one drone is out per bay at a time. A combat drone orbits the enemy ship at its own gap outside the hull and its shield, at its own speed and
## always moving (a smooth weave on the fight's seeded rng), and fires its family's shot at about half the rate of a hull gun of its tier. A defence
## drone orbits its own ship and shoots missiles, slow shells and (Mk II) the enemy's drones. A drone has hp: a shot that crosses it hurts it,
## point defence and turrets shoot at it (Weapons.missile_target), and it dies at 0 with debris. A bay with no power recalls its drone; so does the
## end of the fight: it flies home, and the part is spent. A bay is {id (component id), kit, pos (the hatch, cell coordinates), dir (outward, ship-local),
## virtual, powered (virtual only), drone (the drone out, or null), ready (arena tick it may launch again), launched (the tick of the last launch)}.
## Works on the arena (arena.gd): `arena.drones` is the list of live drones, `Combatant.bays` the bays.

const Collisions = preload("res://scripts/combat/collisions.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Content = preload("res://scripts/data/content.gd")
const Limpets = preload("res://scripts/combat/limpets.gd")

const FAMILY := "drone_bay"
const PART := "drone_part"
const KIT_KIND := "drone"
const HP_PER_DAMAGE := 3.0  ## a shot of damage d takes d / this hp off a drone (at least MIN_LOSS)
const MIN_LOSS := 0.5
const HIT_RADIUS := {1: 14.0, 2: 16.0, 3: 19.0}  ## px: how near a shot's line must pass to hit a drone of that tier
const LAUNCH_SPEED := 230.0  ## px/s out of the hatch
const ACCEL := 520.0  ## px/s2 a drone can change its velocity by
const CHASE := 1.9  ## top speed over the orbit speed
const SHOW_AFTER_S := 0.3  ## seconds a launched drone is still inside the hatch (the cradle carries it up the rail; the doors are open 2 by then)
const GROW_S := 0.25  ## seconds from the hatch mouth to its full size
const DOCKED_SCALE := 0.714  ## the size it has on the cradle (the view draws a flying drone 1/this larger)
const HOME_DIST := 26.0  ## px from the hatch at which a returning drone is docked
const EVASION := 0.12  ## the chance a turret's tracer misses a drone, on top of its accuracy
const LIMPET_REACH := 2660.0  ## an enemy throws limpets and pods only when the foe is this near
const LIMPET_SIGHT := 3.0  ## point defence and turrets engage a flying limpet or pod from this many times their usual reach
const AI_SKILL := 0.75  ## how often the enemy picks its best-predicted throw
const DRONE_EVENTS := ["drone_launch", "drone_shot", "drone_hit", "drone_down", "drone_home", "drone_recall"]

static var _kits := {}
static var _key := ""


## The kit entry of item `id` ({id, name, kind, drone}), or {} when it is no drone kit.
static func kit(id: String) -> Dictionary:
	var k := Content.root + "|" + Content.packs_root
	if k != _key:
		_key = k
		_kits = {}
		for e in Content.list("items"):
			if str(e.get("kind", "")) == KIT_KIND and e.get("drone") is Dictionary:
				_kits[str(e["id"])] = e
	return _kits.get(id, {})


static func kit_ids() -> Array:
	kit("")
	var out := _kits.keys()
	out.sort()
	return out


## The weapon entry (Weapons.def shape) of a drone kit's gun.
static func gun_of(arena, spec: Dictionary) -> Dictionary:
	var g: Dictionary = spec["gun"]
	var out: Dictionary = arena.weapons.BASE.duplicate()
	out.merge(arena.weapons.KIND_DEFAULTS.get(str(g.get("kind", "laser")), {}), true)
	out.merge(g, true)
	out["id"] = str(g.get("weapon", "drone"))
	out["aim"] = "turret"
	out["turret"] = true
	out["drone"] = true  # (the view draws its shots smaller)
	return out


## Can bay component def `def` launch a drone of `tier`?
static func fits(def: Dictionary, tier: int) -> bool:
	return tier <= int(def.get("bay", {}).get("max_tier", 1))


## The bays of `ship`: uid -> bay (see the top), one per placed bay component, in the hatch's place.
static func bays_of(ship) -> Dictionary:
	var out := {}
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		var def: Dictionary = ship.components.def(inst["id"])
		if str(def.get("family", "")) != FAMILY:
			continue
		var pos := Vector2.ZERO
		if ship.components.has_outside(uid):
			pos = Mounts.out_centre(def, inst)
		else:
			for c in inst["cells"]:
				pos += Vector2(c) + Vector2(0.5, 0.5)
			pos /= inst["cells"].size()
		out[uid] = _bay(str(inst["id"]), str(inst.get("kit", "")), pos, Mounts.dir_of(inst), false, true)
	return out


static func _bay(id: String, kit_id: String, pos: Vector2, dir: Vector2, virt: bool, powered: bool) -> Dictionary:
	return {"id": id, "kit": kit_id, "pos": pos, "dir": dir, "virtual": virt, "powered": powered, "drone": null, "ready": 0, "launched": -1000000}


## A bay without a placed component (tests, tools): `bay_id` a component id, `cell_pos` the hatch in grid cell coordinates, `dir` outward. Returns its uid.
static func add_bay(arena, idx: int, bay_id: String, kit_id: String, cell_pos: Vector2, dir := Vector2.UP, powered := true) -> int:
	var co = arena.ships[idx]
	var uid: int = co.next_virtual
	co.next_virtual -= 1
	co.bays[uid] = _bay(bay_id, kit_id, cell_pos, dir.normalized(), true, powered)
	return uid


## The bay uids of ship `idx`, in slot order (placed ones by uid, then virtual ones as added).
static func slots(arena, idx: int) -> Array:
	var uids: Array = arena.ships[idx].bays.keys()
	uids.sort_custom(func(a, b): return a < b if (a < 0) == (b < 0) and a >= 0 else (a > b if (a < 0) == (b < 0) else a >= 0))
	return uids


static func def_of(arena, idx: int, uid: int) -> Dictionary:
	return arena.ships[idx].ship.components.def(arena.ships[idx].bays[uid]["id"])


## The kit loaded in bay `uid` ({} when none or unknown).
static func kit_of(arena, idx: int, uid: int) -> Dictionary:
	return kit(str(arena.ships[idx].bays[uid]["kit"]))


## "ok", or why bay `uid` is out of action: wrecked, malfunction, overheated, disabled (outside half shot out), offline (link cut), unpowered.
static func status_of(arena, idx: int, uid: int) -> String:
	var co = arena.ships[idx]
	var b: Dictionary = co.bays[uid]
	if co.wrecked:
		return "wrecked"
	if b["virtual"]:
		return "ok" if b["powered"] else "unpowered"
	var inst = co.ship.components.instances.get(uid)
	if inst == null:
		return "wrecked"
	match co.ship.components.offline_reason(co.ship.grid, uid):
		"outside half disabled":
			return "disabled"
		"link cut":
			return "offline"
	if str(inst.get("status", "ok")) != "ok":
		return str(inst["status"])
	return "ok" if co.powered.get(uid, false) else "unpowered"


## Seconds a bay takes to re-arm after a lost drone: its tier's, 25% quicker with a crew member in its room.
static func rearm_s(arena, idx: int, uid: int) -> float:
	var def := def_of(arena, idx, uid)
	var t := float(def.get("bay", {}).get("rearm_s", 12.0))
	return t * (float(def.get("bay", {}).get("crew_mult", 0.75)) if _crewed(arena, idx, uid) else 1.0)


static func _crewed(arena, idx: int, uid: int) -> bool:
	var ship = arena.ships[idx].ship
	if not ship.components.instances.has(uid):
		return false
	var room: int = ship.atmosphere.room_at(ship.components.instances[uid]["anchor"])
	if room < 0:
		return false
	for m in ship.crew:
		if not m.is_down() and not m.is_drone() and ship.atmosphere.room_at(m.cell()) == room:
			return true
	return false


## Seconds until bay `uid` may launch again (0 when it can).
static func ready_in(arena, idx: int, uid: int) -> float:
	return maxf(0.0, float(int(arena.ships[idx].bays[uid]["ready"]) - arena.tick) * arena.SUBSTEP)


## "" when bay `uid` of ship `idx` can launch now, else why: wrecked, no kit, bay too small, a status, drone out, re-arming, no parts.
static func can_launch(arena, idx: int, uid: int) -> String:
	var co = arena.ships[idx]
	if not co.bays.has(uid):
		return "no such bay"
	var b: Dictionary = co.bays[uid]
	var st := status_of(arena, idx, uid)
	if st != "ok":
		return st
	var k := kit_of(arena, idx, uid)
	if k.is_empty():
		return "no kit"
	var inv = co.ship.inventory
	var rank := 0  # bays loaded with the same kit share the kits the hold has
	for u in slots(arena, idx):
		if u == uid:
			break
		if co.bays[u]["kit"] == b["kit"]:
			rank += 1
	if inv.count(str(b["kit"])) <= rank:
		return "no kit"
	var tier := int(k["drone"]["tier"])
	if not fits(def_of(arena, idx, uid), tier):
		return "bay too small"
	if b["drone"] != null:
		return "drone out"
	if arena.tick < int(b["ready"]):
		return "re-arming"
	if inv.count(PART) < tier:
		return "no parts"
	return ""


## Launch bay `uid`'s drone. "" when it flew, else why not (can_launch). Spends the parts. The drone leaves the hatch along the mount's outward direction; a limpet or
## a boarder pod (limpets.gd) is thrown toward the world point `aim` (straight out of the hatch when it is left out) and the magnet does the rest.
static func launch(arena, idx: int, uid: int, aim := Vector2.INF) -> String:
	var why := can_launch(arena, idx, uid)
	if why != "":
		return why
	var co = arena.ships[idx]
	var b: Dictionary = co.bays[uid]
	var spec: Dictionary = kit_of(arena, idx, uid)["drone"]
	co.ship.inventory.add(PART, -int(spec["tier"]))
	var hatch: Vector2 = arena.local_to_world(idx, b["pos"])
	var dir: Vector2 = Vector2(b["dir"]).rotated(co.flight.angle)
	var o: Dictionary = spec.get("orbit", {"gap": 0.0, "speed": 0.0, "weave": 0.0, "hz": 0.0})
	var d := {"id": arena.drone_serial, "owner": idx, "bay": uid, "kit": str(b["kit"]), "role": str(spec["role"]), "tier": int(spec["tier"]), "name": str(kit(str(b["kit"]))["name"]),
		"art": str(spec["art"]), "hp": float(spec["hp"]), "max_hp": float(spec["hp"]), "spec": spec, "w": gun_of(arena, spec) if spec.has("gun") else {},
		"pos": hatch, "dir": dir, "vel": dir * LAUNCH_SPEED + co.flight.vel, "angle": dir.angle() + PI / 2.0, "born": arena.tick, "state": "out", "hit_tick": -1000000, "fire_tick": -1000000,
		"cool": arena.tick + int(1.2 / arena.SUBSTEP), "theta": arena.rng.randf() * TAU, "sign": 1.0 if arena.rng.randf() < 0.5 else -1.0, "ph1": arena.rng.randf() * TAU,
		"ph2": arena.rng.randf() * TAU, "ph3": arena.rng.randf() * TAU, "orbit": o, "beam": {}, "r": 0.0}
	arena.drone_serial += 1
	arena.drones.append(d)
	if Limpets.is_limpet(d):
		Limpets.start(arena, d, hatch, aim if aim != Vector2.INF else hatch + dir * 600.0, co.flight.vel)
		dir = Vector2.from_angle(float(d["angle"]) - PI / 2.0)
	b["drone"] = d
	b["launched"] = arena.tick
	arena.log_event("drone_launch", idx, Vector2i(-1, -1), {"drone": d["id"], "uid": uid, "pos": hatch, "dir": dir, "kit": d["kit"]})
	return ""


## The drones of ship `idx` that are out.
static func of_ship(arena, idx: int) -> Array:
	return arena.drones.filter(func(d): return d["owner"] == idx)


## The drone out of bay `uid` of ship `idx`, or null.
static func out_of(arena, idx: int, uid: int):
	return arena.ships[idx].bays[uid]["drone"]


## Recall one drone: it flies home and docks.
static func recall(arena, d: Dictionary) -> void:
	if Limpets.is_limpet(d):  # (it cannot turn back: the magnet has it)
		return
	if d["state"] != "home":
		d["state"] = "home"
		d["home_tick"] = arena.tick
		arena.log_event("drone_recall", d["owner"], Vector2i(-1, -1), {"drone": d["id"], "pos": d["pos"]})


## The end of the fight: every drone flies home.
static func recall_all(arena) -> void:
	for d in arena.drones:
		recall(arena, d)
	Limpets.clear(arena)


# --- the loaded kit (build mode) -----------------------------------------------------------------

## The kits bay `uid` of `ship` could be loaded with: [{id, name, tier, hp, held (in the hold), free (not loaded in another bay), ok, why}], the lowest tier first.
static func kit_choices(ship, uid: int) -> Array:
	var def: Dictionary = ship.components.def(ship.components.instances[uid]["id"])
	var out := []
	for id in kit_ids():
		var k := kit(id)
		var d: Dictionary = k["drone"]
		var held: int = ship.inventory.count(id)
		var used := 0
		for u in ship.components.instances:
			if u != uid and str(ship.components.instances[u].get("kit", "")) == id:
				used += 1
		var why := ""
		if not fits(def, int(d["tier"])):
			why = "needs a Mk %s bay" % ["I", "II", "III"][int(d["tier"]) - 1]
		elif held <= 0:
			why = "none in the hold"
		elif held <= used:
			why = "loaded in another bay"
		out.append({"id": id, "name": str(k["name"]), "tier": int(d["tier"]), "hp": int(d["hp"]), "role": str(d["role"]), "held": held, "ok": why == "", "why": why})
	out.sort_custom(func(a, b): return [a["tier"], a["id"]] < [b["tier"], b["id"]])
	return out


## Load kit `id` ("" to unload) into bay `uid` of `ship`. "" when it worked, else why not.
static func set_kit(ship, uid: int, id: String) -> String:
	if not ship.components.instances.has(uid) or str(ship.components.def(ship.components.instances[uid]["id"]).get("family", "")) != FAMILY:
		return "not a drone bay"
	if id == "":
		ship.components.instances[uid].erase("kit")
		return ""
	for c in kit_choices(ship, uid):
		if c["id"] == id:
			if not c["ok"]:
				return str(c["why"])
			ship.components.instances[uid]["kit"] = id
			return ""
	return "no such kit"


## Fill every empty bay of `ship` with the best kit it can take (what a fight start does for a bay nobody loaded).
static func autoload(ship) -> void:
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		if str(ship.components.def(inst["id"]).get("family", "")) != FAMILY or str(inst.get("kit", "")) != "":
			continue
		var best := ""
		for c in kit_choices(ship, uid):
			if c["ok"] and str(c["role"]) == "combat":
				best = c["id"]
		if best == "":
			for c in kit_choices(ship, uid):
				if c["ok"]:
					best = c["id"]
		if best != "":
			inst["kit"] = best


# --- the step ------------------------------------------------------------------------------------

## Advance every drone one substep: recall on no power, fly, shoot.
static func step(arena, dt: float) -> void:
	if arena.drones.is_empty():
		return
	var keep: Array = []
	for d in arena.drones.duplicate():
		if Limpets.is_limpet(d):  # (a limpet or a pod flies by the magnet and works where it sticks)
			if d["hp"] > 0.0 and Limpets.step(arena, d, dt):
				keep.append(d)
			continue
		var co = arena.ships[d["owner"]]
		var b: Dictionary = co.bays.get(d["bay"], {})
		if d["state"] != "home" and (b.is_empty() or status_of(arena, d["owner"], d["bay"]) != "ok"):
			recall(arena, d)
		if d["hp"] <= 0.0:
			continue
		if d["state"] == "home":
			if _fly_home(arena, d, dt):
				b["drone"] = null
				b["ready"] = arena.tick
				arena.log_event("drone_home", d["owner"], Vector2i(-1, -1), {"drone": d["id"], "pos": d["pos"]})
				continue
		else:
			_fly_orbit(arena, d, dt)
			if arena.tick == int(d["born"]) + int(round(SHOW_AFTER_S / dt)):  # it shows: the puff out of the open hatch
				arena.log_event("drone_emerge", d["owner"], Vector2i(-1, -1), {"drone": d["id"], "pos": d["pos"], "dir": d["dir"]})
			_shoot(arena, d)
		keep.append(d)
	# (a drone shot down inside this step was removed by kill())
	arena.drones = arena.drones.filter(func(d): return keep.has(d) and d["hp"] > 0.0)


## A limpet or pod already stuck to a hull (or falling off): no shot or turret takes it any more.
static func _clamped(d: Dictionary) -> bool:
	return d["state"] == "stuck" or d["state"] == "fall" or d["state"] == "gone"


static func _target_ship(arena, d: Dictionary) -> int:
	if d["role"] == "defence":
		return d["owner"]
	return arena.weapons.target_of(arena, d["owner"])


## The radius (px) of the orbit's inner edge about ship `t`: its hull, and its shield bubble when it holds one (a shot from outside the bubble is stopped by it).
static func ring_radius(arena, t: int) -> float:
	var co = arena.ships[t]
	var r: float = float(Collisions.hit_cells(arena, t)["radius"])
	if r < 3.0 * arena.CELL:  # (a hull with no wall cells: its bounding box)
		r = co.half.length() * arena.CELL
	if co.layers_cap > 0:
		r = maxf(r, (Shields.reach(co) + 0.5) * arena.CELL)
	return r


static func _fly_orbit(arena, d: Dictionary, dt: float) -> void:
	var t := _target_ship(arena, d)
	if t < 0:
		recall(arena, d)
		return
	var o: Dictionary = d["orbit"]
	var tc = arena.ships[t]
	var now: float = float(arena.tick - int(d["born"])) * dt
	var r0: float = ring_radius(arena, t) + float(o["gap"])
	var hz: float = float(o["hz"])
	var weave: float = float(o["weave"])
	var r := r0 + weave * sin(TAU * hz * now + d["ph1"]) + 0.5 * weave * sin(TAU * 1.7 * hz * now + d["ph2"])
	d["r"] = r
	var omega: float = d["sign"] * float(o["speed"]) / r0
	d["theta"] = float(d["theta"]) + (omega + 0.18 * sin(TAU * 0.6 * hz * now + d["ph3"])) * dt
	var want: Vector2 = tc.flight.pos + Vector2.from_angle(d["theta"]) * r
	var vmax: float = float(o["speed"]) * CHASE
	var v_des: Vector2 = (want - d["pos"]) / 0.35 + tc.flight.vel * 0.0
	if v_des.length() > vmax:
		v_des = v_des.normalized() * vmax
	var age: float = float(arena.tick - int(d["born"])) * dt
	if age < SHOW_AFTER_S:  # still in the bay: held at the hatch mouth, no motion until it shows
		d["pos"] = arena.local_to_world(d["owner"], arena.ships[d["owner"]].bays[d["bay"]]["pos"])
		d["vel"] = Vector2(d["dir"]) * LAUNCH_SPEED + arena.ships[d["owner"]].flight.vel
		d["angle"] = Vector2(d["dir"]).angle() + PI / 2.0
		return
	var launching: bool = age < SHOW_AFTER_S + GROW_S
	if launching:
		v_des = d["vel"]  # straight out of the hatch first
	d["vel"] = Vector2(d["vel"]).move_toward(v_des, ACCEL * dt)
	if not launching and Vector2(d["vel"]).length() < float(o["speed"]) * 0.5:  # never still
		d["vel"] = Vector2(d["vel"]) + Vector2.from_angle(float(d["theta"]) + d["sign"] * PI / 2.0) * float(o["speed"]) * 0.5
	d["pos"] = Vector2(d["pos"]) + Vector2(d["vel"]) * dt
	var face: Vector2 = tc.flight.pos - Vector2(d["pos"]) if d["role"] != "defence" else Vector2(d["vel"])
	if d["role"] == "defence":  # the radar ring turns slowly
		d["angle"] = float(d["angle"]) + 1.2 * dt
	elif face.length() > 1.0:
		d["angle"] = lerp_angle(float(d["angle"]), face.angle() + PI / 2.0, minf(1.0, 6.0 * dt))


## Fly a recalled drone to its hatch. True when it has docked.
static func _fly_home(arena, d: Dictionary, dt: float) -> bool:
	var co = arena.ships[d["owner"]]
	var b: Dictionary = co.bays[d["bay"]]
	var hatch: Vector2 = arena.local_to_world(d["owner"], b["pos"])
	var to: Vector2 = hatch - Vector2(d["pos"])
	var vmax: float = float(d["orbit"]["speed"]) * CHASE + co.flight.vel.length()
	var v_des: Vector2 = to.normalized() * minf(vmax, maxf(to.length() * 2.5, 90.0)) + co.flight.vel
	d["vel"] = Vector2(d["vel"]).move_toward(v_des, ACCEL * 1.4 * dt)
	d["pos"] = Vector2(d["pos"]) + Vector2(d["vel"]) * dt
	if to.length() > 1.0:
		d["angle"] = lerp_angle(float(d["angle"]), to.angle() + PI / 2.0, minf(1.0, 6.0 * dt))
	return to.length() < HOME_DIST or float(arena.tick - int(d["home_tick"])) * dt > 12.0


## 0..1: how far out of the hatch a launching drone is (the view grows it), 1 once it is out; a homing one shrinks again near its hatch.
static func scale_of(arena, d: Dictionary) -> float:
	var s := clampf((float(arena.tick - int(d["born"])) * arena.SUBSTEP - SHOW_AFTER_S) / GROW_S, 0.0, 1.0)
	if d["state"] == "home":
		var co = arena.ships[d["owner"]]
		var hatch: Vector2 = arena.local_to_world(d["owner"], co.bays[d["bay"]]["pos"])
		s = minf(s, clampf((Vector2(d["pos"]).distance_to(hatch) - HOME_DIST) / 90.0 + 0.25, 0.25, 1.0))
	return DOCKED_SCALE + (1.0 - DOCKED_SCALE) * s


# --- shooting ------------------------------------------------------------------------------------

static func _shoot(arena, d: Dictionary) -> void:
	if d["role"] == "defence":
		_defend(arena, d)
		return
	var w: Dictionary = d["w"]
	var idx: int = d["owner"]
	if not d["beam"].is_empty():
		_beam_tick(arena, d)
	if arena.tick < int(d["cool"]) or not d["beam"].is_empty() or arena.time() < 0.5 + float(d["born"]) * arena.SUBSTEP:
		return
	var t := _target_ship(arena, d)
	if t < 0 or arena.ships[t].wrecked:
		return
	var origin: Vector2 = Vector2(d["pos"]) + Vector2.from_angle(float(d["angle"]) - PI / 2.0) * 14.0
	if not _in_range(arena, t, origin, float(w["range"])):
		return
	var tc = arena.ships[t]
	var hit: bool = arena.rng.randf() < clampf(float(w["accuracy"]) - arena.weapons.evasion(arena, t), 0.0, 1.0)
	var cells: Array = arena.weapons.facing_cells(arena, t, origin)
	var speed: float = float(w["speed"]) if w["kind"] in ["bolt", "flak", "missile"] else 0.0
	var point: Vector2
	if hit and not cells.is_empty():
		var local := Vector2(cells[arena.rng.randi_range(0, cells.size() - 1)]) + Vector2(0.5, 0.5)
		point = arena.weapons.PilotAI.lead_point(origin, arena.local_to_world(t, local), arena.weapons._point_velocity(tc, local), speed)
	else:
		var side := 1.0 if arena.rng.randf() < 0.5 else -1.0
		var away: Vector2 = (tc.flight.pos - origin).normalized().rotated(side * PI / 2.0)
		point = arena.weapons.PilotAI.lead_point(origin, tc.flight.pos + away * (float(Collisions.hit_cells(arena, t)["radius"]) + arena.weapons.MISS_MARGIN), tc.flight.vel, speed)
	var dir: Vector2 = (point - origin).normalized()
	d["cool"] = arena.tick + int(ceil(float(w["cooldown"]) / arena.SUBSTEP - 1e-6))
	d["fire_tick"] = arena.tick
	arena.log_event("drone_shot", idx, Vector2i(-1, -1), {"drone": d["id"], "origin": origin, "dir": dir, "kind": w["kind"], "weapon": w["id"], "dtype": w["damage_type"]})
	if w["kind"] == "beam":
		var dur := int(ceil(float(w["duration"]) / arena.SUBSTEP - 1e-6))
		d["beam"] = {"end": arena.tick + dur, "start": arena.tick, "next": arena.tick + 1, "dir": dir, "sweep": deg_to_rad(8.0) * (1.0 if arena.rng.randf() < 0.5 else -1.0),
			"every": maxi(1, roundi(float(w["tick"]) / arena.SUBSTEP))}
	elif w["kind"] == "laser":
		arena.weapons._line(arena, idx, w, str(w["id"]), origin, origin + dir * float(w["range"]))
	else:
		var spread := deg_to_rad(float(w["spread"]))
		for i in int(w["shots"]):
			var dd := dir
			if spread > 0.0:
				dd = dir.rotated(arena.rng.randf_range(-spread * 0.5, spread * 0.5))
			arena.weapons.Projectiles.spawn(arena, idx, w, origin, dd)


static func _beam_tick(arena, d: Dictionary) -> void:
	var b: Dictionary = d["beam"]
	if arena.tick > int(b["end"]):
		d["beam"] = {}
		return
	if arena.tick < int(b["next"]):
		return
	b["next"] = int(b["next"]) + int(b["every"])
	var w: Dictionary = (d["w"] as Dictionary).duplicate()
	w["damage"] = float(w["damage"]) * int(b["every"]) * arena.SUBSTEP
	w["fx_k"] = float(b["every"]) * arena.SUBSTEP
	var span: float = maxf(float(int(b["end"]) - int(b["start"])), 1.0)
	var k: float = float(arena.tick - int(b["start"])) / span - 0.5
	var origin: Vector2 = Vector2(d["pos"]) + Vector2.from_angle(float(d["angle"]) - PI / 2.0) * 14.0
	var dir: Vector2 = Vector2(b["dir"]).rotated(float(b["sweep"]) * 2.0 * k)
	arena.weapons._line(arena, d["owner"], w, str(w["id"]), origin, origin + dir * float(w["range"]))


static func _in_range(arena, t: int, from: Vector2, reach: float) -> bool:
	return from.distance_to(arena.ships[t].flight.pos) <= reach + ring_radius(arena, t) * 0.6


## A defence drone: shoot the nearest incoming shot (missile or slow), or (Mk II) enemy drone, in range, rolling its accuracy.
static func _defend(arena, d: Dictionary) -> void:
	if arena.tick < int(d["cool"]):
		return
	var w: Dictionary = d["w"]
	var targets: Array = w["targets"]
	var from: Vector2 = d["pos"]
	var best = null
	var best_d := float(w["range"]) * float(w["range"])
	for p in arena.projectiles:
		if p["owner"] == d["owner"]:
			continue
		var slow: bool = Vector2(p["vel"]).length() <= arena.weapons.pd_speed
		if not ((str(p["w"]["kind"]) == "missile" and targets.has("missile")) or (slow and targets.has("slow"))):
			continue
		var dd := from.distance_squared_to(p["pos"])
		if dd <= best_d:
			best_d = dd
			best = p
	if targets.has("drone"):
		for e in arena.drones:
			if e["owner"] != d["owner"] and not _clamped(e):
				var dd := from.distance_squared_to(e["pos"])
				if dd <= best_d:
					best_d = dd
					best = e
	if best == null:
		return
	d["cool"] = arena.tick + int(ceil(float(w["cooldown"]) / arena.SUBSTEP - 1e-6))
	d["fire_tick"] = arena.tick
	var hit: bool = arena.rng.randf() < float(w["accuracy"])
	var at: Vector2 = best["pos"]
	d["angle"] = (at - from).angle() + PI / 2.0
	arena.log_event("drone_shot", d["owner"], Vector2i(-1, -1), {"drone": d["id"], "origin": from, "dir": (at - from).normalized(), "kind": "pd", "weapon": w["id"], "dtype": "kinetic", "to": at, "hit": hit})
	if hit:
		if best.has("hp"):
			damage(arena, best, 1.0, d["owner"])
		else:
			arena.projectiles.erase(best)
			arena.log_event("effect", d["owner"], Vector2i(-1, -1), {"kind": "intercept", "weapon": str(w["id"]), "hit": true, "pos": at})


# --- being hit -----------------------------------------------------------------------------------

## The drone of another ship that segment p0 -> p1 crosses first: {t (0..1 along it), drone}, or {} when it crosses none. `owner` is who shot.
static func contact(arena, owner: int, p0: Vector2, p1: Vector2) -> Dictionary:
	var best := {}
	var seg := p1 - p0
	var len2 := seg.length_squared()
	for d in arena.drones:
		if d["owner"] == owner or d["hp"] <= 0.0 or float(arena.tick - int(d["born"])) * arena.SUBSTEP < SHOW_AFTER_S or _clamped(d):  # (not while it is inside the bay)
			continue
		var r: float = float(HIT_RADIUS[int(d["tier"])]) * scale_of(arena, d)
		var t := 0.0 if len2 < 1e-9 else clampf((Vector2(d["pos"]) - p0).dot(seg) / len2, 0.0, 1.0)
		if (p0 + seg * t).distance_to(d["pos"]) <= r and (best.is_empty() or t < best["t"]):
			best = {"t": t, "drone": d}
	return best


## A shot of weapon `w` hit drone `d`: it loses damage / HP_PER_DAMAGE hp (at least MIN_LOSS; a beam's tick is only its share).
static func hit_by_shot(arena, d: Dictionary, w: Dictionary, by: int) -> void:
	var loss := float(w["damage"]) / HP_PER_DAMAGE
	if str(w.get("kind", "")) != "beam":
		loss = maxf(loss, MIN_LOSS)
	damage(arena, d, loss, by)


## Take `hp` off drone `d` (a hit flash); at 0 it dies: debris, an event, the bay re-arms.
static func damage(arena, d: Dictionary, hp: float, by := -1) -> void:
	if d["hp"] <= 0.0:
		return
	d["hp"] = float(d["hp"]) - hp
	d["hit_tick"] = arena.tick
	arena.log_event("drone_hit", d["owner"], Vector2i(-1, -1), {"drone": d["id"], "pos": d["pos"], "hp": d["hp"], "by": by})
	if d["hp"] <= 0.0:
		kill(arena, d)


static func kill(arena, d: Dictionary) -> void:
	d["hp"] = 0.0
	var co = arena.ships[d["owner"]]
	var b: Dictionary = co.bays.get(d["bay"], {})
	if not b.is_empty() and b["drone"] == d:
		b["drone"] = null
		b["ready"] = arena.tick + int(ceil(rearm_s(arena, d["owner"], d["bay"]) / arena.SUBSTEP - 1e-6))
	arena.log_event("drone_down", d["owner"], Vector2i(-1, -1), {"drone": d["id"], "pos": d["pos"], "vel": d["vel"], "kit": d["kit"], "tier": d["tier"]})
	arena.drones.erase(d)


# --- turrets and point defence shoot drones ------------------------------------------------------

## What turret `m` (mount of ship `idx`, weapon entry `w`) shoots at when a drone is to be answered: a pseudo-shot {pos, vel, drone} for the nearest
## enemy drone in range and arc; a point-defence turret counts drones as incoming along with shots (the caller compares distances), any other turret
## answers a third of its volleys (flak all of them).
static func turret_target(arena, idx: int, m: Dictionary, w: Dictionary, uid: int, pd: bool):
	if arena.drones.is_empty():
		return null
	if not pd and str(w["kind"]) != "flak" and (int(m.get("shots", 0)) + absi(uid)) % 3 != 0:
		return null
	var from: Vector2 = arena.local_to_world(idx, m["pos"])
	var reach: float = float((Effects_of(w).get("intercept") as Dictionary)["range"]) if pd else float(w["range"]) * 0.9
	var best = null
	var best_d := INF
	for d in arena.drones:
		if d["owner"] == idx or d["hp"] <= 0.0 or _clamped(d):
			continue
		var rr := reach * (LIMPET_SIGHT if Limpets.is_limpet(d) else 1.0)  # a slow limpet or pod is seen coming from further off
		var dd := from.distance_squared_to(d["pos"])
		if dd <= rr * rr and dd <= best_d and arena.weapons.in_arc(arena, idx, m, d["pos"]):
			best_d = dd
			best = d
	return null if best == null else {"pos": best["pos"], "vel": best["vel"], "drone": best, "d2": best_d}


static func Effects_of(w: Dictionary) -> Dictionary:
	return w.get("effects", {}) if w.get("effects") is Dictionary else {}


## A tracer from a turret hit a drone: roll the turret's accuracy (less EVASION); on a hit PD takes 1 hp, a gun its damage share.
static func shot_at(arena, idx: int, w: Dictionary, mis: Dictionary, pd: bool) -> bool:
	var hit: bool = arena.rng.randf() < clampf(float(w["accuracy"]) - EVASION, 0.0, 1.0)
	if hit:
		var d: Dictionary = mis["drone"]
		damage(arena, d, 1.0 if pd else maxf(float(w["damage"]) / HP_PER_DAMAGE, MIN_LOSS), idx)
	return hit


# --- the enemy's bays ----------------------------------------------------------------------------

## The enemy pilot's launch: every ready bay launches when its kit and parts are there and the foe is within reach of the drone.
static func ai_launch(arena, idx: int, foe: int) -> void:
	var co = arena.ships[idx]
	if co.bays.is_empty() or co.wrecked or arena.ships[foe].wrecked or arena.tick % 30 != 0:
		return
	for uid in slots(arena, idx):
		var k := kit_of(arena, idx, uid)
		if k.is_empty() or can_launch(arena, idx, uid) != "":
			continue
		if str(k["drone"]["role"]) == "defence" and not _threatened(arena, idx):
			continue
		if Limpets.is_limpet({"role": str(k["drone"]["role"])}):  # limpets and pods are thrown: a lead plus a skilled wide angle for the side and back rooms
			if co.flight.pos.distance_to(arena.ships[foe].flight.pos) < LIMPET_REACH:
				var hatch: Vector2 = arena.local_to_world(idx, co.bays[uid]["pos"])
				launch(arena, idx, uid, Limpets.ai_aim(arena, idx, hatch, k["drone"], AI_SKILL))
		elif co.flight.pos.distance_to(arena.ships[foe].flight.pos) < 3640.0:
			launch(arena, idx, uid)


## Does ship `idx` have something worth a defence drone: an enemy missile, a slow shell or a drone out?
static func _threatened(arena, idx: int) -> bool:
	for p in arena.projectiles:
		if p["owner"] != idx and (str(p["w"]["kind"]) == "missile" or Vector2(p["vel"]).length() <= arena.weapons.pd_speed):
			return true
	return arena.drones.any(func(d): return d["owner"] != idx) or arena.time() > 8.0
