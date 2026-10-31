extends RefCounted
## The enemy pilot: flies one ship of the arena against another and shoots. Deterministic: its few
## random choices (aim jitter, which way it strafes) come from its own generator, seeded from the
## arena's seed, and it only reads the arena. Call think(dt) once per arena substep, before stepping.
## - Range: it keeps RANGE_FRACTION of its shortest weapon range between the ships' centres, and at
##   least both hulls' radii plus HULL_MARGIN (it used to hold 630 px between centres and clip the
##   player's hull with its own).
## - Pointing: it turns its nose so the fixed guns (their mean outward direction) lead the target, off by
##   an aim error that shrinks with `aim_skill` (the design's `ai.aim_skill`, 0..1, default 0.6): up to
##   (1 - aim_skill) x AIM_ERROR_DEG degrees either way, re-rolled every RETARGET_S. It fires a fixed gun
##   only when the gun can bear (its gimbal reaches the aim point). Turrets track and fire by themselves
##   in the arena (Weapons.tick_turrets). It strafes with side engines when it has them.
## - Aim: the player's weapons first, then engines, then the reactor (the outside half of a mount, the part
##   it can see), led by the part's own velocity for shots that fly (hitscan lasers and beams go at the part
##   as it is).
## - With a sectored shield it holds back weapons whose shot would open the sector the player's loaded
##   guns are pointing at, for at most HOLD_MAX seconds.
## - With 2+ shield sectors it shifts the balance toward the side that faces its foe, one step every
##   SHIFT_BASE_S - aim_skill seconds (the design's `ai.aim_skill`, default 0.6).
## - It overcharges its shield when the layers are gone, and does nothing once wrecked.
## - Morale (morale.gd, set by the session): surrendering it holds fire and cuts the throttle; fleeing it turns
##   its stern to the foe and burns at full throttle (the guns still fire when they bear); once captured, spared
##   or gone it does nothing.
## - Style "rammer" (a ship design's `"ai": {"style": "rammer"}`) does not keep a range: it finds its
##   bow (the side with the most ram plating, else forward), points it at where the foe will be and
##   closes at full throttle, uses its engine ability within RAM_ABILITY_RANGE of the foe's hull, and after a collision
##   backs off for RAM_BACKOFF_S seconds before coming round again. Its guns still fire when they can.

const Shields = preload("res://scripts/combat/shields.gd")
const Collisions = preload("res://scripts/combat/collisions.gd")

const RANGE_FRACTION := 0.7
const HULL_MARGIN := 40.0  ## px kept between the two hulls' bounding circles, at least
const DEFAULT_RANGE := 600.0
const PRIORITY: Array[String] = ["weapon", "engine", "reactor"]  ## families it shoots at first
const DEFAULT_AIM_SKILL := 0.6
const AIM_ERROR_DEG := 12.0  ## aim error either way of a pilot with no skill; a pilot of skill s is off by up to (1 - s) of it
const LATERAL_MAX := 150.0  ## px/s of sideways drift before it turns the other way
const CLOSE_MAX := 260.0  ## px/s it closes at, at most
const BACK_MAX := 120.0  ## px/s it backs off at, at most
const HOLD_THROTTLE := 0.5  ## at the preferred range it still pushes this hard
const HOLD_MAX := 1.5  ## seconds a weapon waits for a safer sector
const SHIFT_BASE_S := 1.5  ## a shield balance step comes every this many seconds less the aim skill
const RETARGET_S := 0.5
const RAM_BACKOFF_S := 2.0  ## seconds a rammer reverses after a collision
const RAM_ABILITY_RANGE := 600.0  ## px from the foe's hull (its centre less its bounding radius): a rammer presses its engine ability inside this
const RAM_FINAL := 160.0  ## px: inside this a rammer steers straight at the foe
const RAM_CLOSE_SPEED := 320.0  ## px/s a rammer steers to close at
const RAM_MIN_CLOSE := 100.0  ## px/s: the closing speed it assumes when working out the time to contact
const RAM_MAX_LEAD_S := 4.0
const RAM_ALIGNED := 0.45  ## rad: full throttle when the heading is this close to the steering direction
const FLEE_ALIGNED := 0.6  ## rad: a fleeing ship burns once its nose is this close to straight away from the foe

var arena
var me: int
var foe: int
var rng := RandomNumberGenerator.new()
var aim_skill := DEFAULT_AIM_SKILL  ## 0..1: how true the pilot's aim is and how quickly it shifts its shield balance (the design's ai.aim_skill)
var side := 1.0  ## +1 or -1: which way it strafes (when it has side engines)
var bias := 0.0  ## radians: its aim error now, re-rolled with each retarget
var target_uid := -1  ## the part of the foe it aims at (-1: the ship's centre)
var style := ""  ## "" (keeps its range and strafes) or "rammer"
var morale = null  ## morale.gd of this fight (the session sets it): pilot_mode() says hold, flee or stop
var _flip := 0.0
var _retarget := 0.0
var _hold := {}  # weapon uid -> seconds held back
var _bow := Vector2.UP  # ship-local direction of a rammer's bow
var _shift_in := 0.0  # seconds until the next shield balance step
var _backoff := 0.0  # seconds a rammer still reverses
var _contact_seen := -1  # the last arena.contact_tick this pilot has reacted to


## `p_ai`: the `ai` entry of the ship's design ({"style": "rammer"}), if it has one.
func _init(p_arena, p_me: int, p_foe: int, p_ai := {}) -> void:
	arena = p_arena
	me = p_me
	foe = p_foe
	style = str(p_ai.get("style", ""))
	aim_skill = clampf(float(p_ai.get("aim_skill", DEFAULT_AIM_SKILL)), 0.0, 1.0)
	_shift_in = shift_interval()
	_bow = bow_of(arena.ships[me])
	rng.seed = int(arena.rng.seed) * 7919 + me * 104729 + 17
	side = 1.0 if rng.randf() < 0.5 else -1.0
	_flip = rng.randf_range(2.0, 4.0)


## Decide for `dt` seconds: set the helm and fire what is ready.
func think(dt: float) -> void:
	var co = arena.ships[me]
	var tgt = arena.ships[foe]
	var mode: String = morale.pilot_mode() if morale != null else ""
	if co.wrecked or tgt.wrecked or mode == "stop":
		arena.set_input(me, 0.0, 0.0)
		return
	_retarget -= dt
	if _retarget <= 0.0 or not _part_ok(target_uid):
		_retarget = RETARGET_S
		target_uid = pick_target()
		_bow = bow_of(co)
		var e := deg_to_rad((1.0 - aim_skill) * AIM_ERROR_DEG)
		bias = rng.randf_range(-e, e)
	if mode == "hold":  # surrendering: no throttle, no fire
		arena.set_input(me, 0.0, 0.0)
		_balance(dt)
		return
	if mode == "flee":
		_flee()
	elif style == "rammer":
		_ram(dt)
	else:
		_fly(dt)
	_balance(dt)
	_shoot(dt)


# --- flying ------------------------------------------------------------------------------------

## The weapons that can shoot now: uid -> mount, in uid order.
func _armed() -> Dictionary:
	var out := {}
	var uids: Array = arena.ships[me].mounts.keys()
	uids.sort()
	for uid in uids:
		var m: Dictionary = arena.ships[me].mounts[uid]
		if arena.weapons.status_of(arena, me, uid) == "ok" and (m["powered"] if m["virtual"] else arena.ships[me].powered.get(uid, false)):
			out[uid] = m
	return out


func _fly(dt: float) -> void:
	var co = arena.ships[me]
	var tgt = arena.ships[foe]
	var armed := _armed()
	# The axis its fixed guns point along (ship-local: the mean of their outward directions), the
	# first of them, and its shortest range.
	var axis := Vector2.ZERO
	var reach := INF
	var lead_mount := {}
	var pivots := Vector2.ZERO  # where the fixed guns turn, summed
	var fixed := 0
	for uid in armed:
		var m: Dictionary = armed[uid]
		var w: Dictionary = arena.weapons.def(m["id"])
		reach = minf(reach, float(w["range"]))
		if not w["turret"]:
			axis += Vector2(m["dir"])
			pivots += Vector2(m["pos"])
			fixed += 1
			if lead_mount.is_empty():
				lead_mount = m
	axis = axis.normalized() if axis.length_squared() > 1e-6 else Vector2.UP
	var preferred := maxf(RANGE_FRACTION * (reach if reach < INF else DEFAULT_RANGE), _radius(me) + _radius(foe) + HULL_MARGIN)
	var to_foe: Vector2 = tgt.flight.pos - co.flight.pos
	var dist := to_foe.length()
	var u := to_foe / maxf(dist, 1.0)
	# Flip the strafe now and then, and when the sideways drift gets too big.
	_flip -= dt
	if _flip <= 0.0:
		_flip = rng.randf_range(2.5, 5.0)
		side = -side
	var lateral: float = co.flight.vel.dot(u.rotated(PI / 2.0))
	if absf(lateral) > LATERAL_MAX:
		side = -signf(lateral)
	# Turn so the fixed guns' axis leads the target (a guess off by its aim error).
	var aim: Vector2 = aim_for(lead_mount) if not lead_mount.is_empty() else tgt.flight.pos
	var want: float = (aim - co.flight.pos).angle() - axis.angle()
	if fixed > 0:  # the guns sit off the middle: aim so that they, not the centre, point at it
		for k in 3:
			var at: Vector2 = co.flight.pos + ((pivots / fixed - co.pivot) * arena.CELL).rotated(want)
			want = (aim - at).angle() - axis.angle()
	var turn: float = co.flight.steer_toward(want, co.mass, co.thrust)
	# Close or open the range with the thrust (it pushes along the heading, near the target's direction).
	var closing: float = co.flight.vel.dot(u)
	var brake: float = co.thrust * co.flight.thrust_to_accel / maxf(co.mass, 1.0) * co.flight.REVERSE * 0.6  # px/s^2 it can stop with
	var gap := dist - preferred
	var want_closing := signf(gap) * minf(sqrt(2.0 * brake * absf(gap)), CLOSE_MAX if gap > 0.0 else BACK_MAX)
	var heading := Vector2.UP.rotated(co.flight.angle)
	var throttle := 0.0
	if heading.dot(u) > 0.5:
		throttle = clampf((want_closing - closing) / 90.0, -1.0, 1.0)
		if absf(gap) < preferred * 0.15 and absf(throttle) < HOLD_THROTTLE:
			throttle = HOLD_THROTTLE * (1.0 if gap >= 0.0 else -1.0)  # keep pushing: the hold is a slow orbit
	var strafe := side if float(co.thrusts["left"]) + float(co.thrusts["right"]) > 0.0 else 0.0
	arena.set_input(me, throttle, turn, strafe)


## Px from the pivot of ship `idx` to its farthest cell corner: how far its hull reaches.
func _radius(idx: int) -> float:
	return float(Collisions.hit_cells(arena, idx)["radius"])


## The ship's bow, ship-local: the unit vector toward the side (up, down, left, right of its centre)
## holding the most ram plating (a tile with the `ram` quirk); forward (up) when it has none, and on a tie the first of up, down, left, right.
static func bow_of(co) -> Vector2:
	var sides: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	var count := [0, 0, 0, 0]
	var grid = co.ship.grid
	for c in grid.tiles:
		if str(grid.defs.get_def(grid.tiles[c]).get("quirk", "")) != "ram":
			continue
		var v: Vector2 = Vector2(c) + Vector2(0.5, 0.5) - co.pivot
		if absf(v.x) > absf(v.y):
			count[3 if v.x > 0.0 else 2] += 1
		else:
			count[1 if v.y > 0.0 else 0] += 1
	var best := 0
	for k in range(1, 4):
		if count[k] > count[best]:
			best = k
	return sides[best]


## Helm turn (-1..1) that brings an angle error `err` (rad, positive is clockwise) to zero, braking in time.
func _turn_for(err: float) -> float:
	var co = arena.ships[me]
	return co.flight.steer_toward(co.flight.angle + err, co.mass, co.thrust)


## A rammer's flying: bow at the foe's future position and full throttle, or reversing after a collision.
func _ram(dt: float) -> void:
	var co = arena.ships[me]
	var tgt = arena.ships[foe]
	var to_foe: Vector2 = tgt.flight.pos - co.flight.pos
	var dist := to_foe.length()
	var touched: int = int(arena.contact_tick.get(me, -1))
	if touched > _contact_seen:
		_contact_seen = touched
		if _backoff <= 0.0:
			_backoff = RAM_BACKOFF_S
	var u := to_foe / maxf(dist, 1.0)
	if _backoff > 0.0:  # keep the bow on the foe while backing away, ready to come round
		_backoff -= dt
		arena.set_input(me, -1.0, _turn_for(wrapf(u.angle() - _bow.angle() - co.flight.angle, -PI, PI)))
		return
	var rel_v: Vector2 = co.flight.vel - tgt.flight.vel
	var t_hit := clampf(dist / maxf(rel_v.dot(u), RAM_MIN_CLOSE), 0.0, RAM_MAX_LEAD_S)
	var aim: Vector2 = tgt.flight.pos + tgt.flight.vel * t_hit
	var steer: Vector2 = (aim - co.flight.pos).normalized()
	if dist > RAM_FINAL:  # cancel the sideways drift as well as closing in
		steer = (steer * RAM_CLOSE_SPEED - (rel_v - steer * rel_v.dot(steer))).normalized()
	var turn := _turn_for(wrapf(steer.angle() - _bow.angle() - co.flight.angle, -PI, PI))
	var heading := Vector2.UP.rotated(co.flight.angle)
	arena.set_input(me, 1.0 if heading.dot(steer) > cos(RAM_ALIGNED) else 0.0, turn)
	if dist - float(Collisions.hit_cells(arena, foe)["radius"]) < RAM_ABILITY_RANGE:
		arena.use_key(me, "engine")


## Fleeing: nose straight away from the foe (stern to it), full throttle once it points that way.
func _flee() -> void:
	var co = arena.ships[me]
	var away: Vector2 = co.flight.pos - arena.ships[foe].flight.pos
	away = away.normalized() if away.length_squared() > 1.0 else Vector2.UP
	var turn: float = co.flight.steer_toward(away.angle() + PI / 2.0, co.mass, co.thrust)
	arena.set_input(me, 1.0 if Vector2.UP.rotated(co.flight.angle).dot(away) > cos(FLEE_ALIGNED) else 0.0, turn)


## Seconds between two steps of shield balance.
func shift_interval() -> float:
	return SHIFT_BASE_S - aim_skill


## With a sectored shield: a step of weight toward the sector that faces the foe every shift_interval().
func _balance(dt: float) -> void:
	var co = arena.ships[me]
	if co.sectors < 2 or co.layers_cap <= 0:
		return
	_shift_in -= dt
	if _shift_in > 0.0:
		return
	_shift_in = shift_interval()
	Shields.shift_sector(co, Shields.sector_of_world_dir(co, arena.ships[foe].flight.pos - co.flight.pos))


# --- shooting ------------------------------------------------------------------------------------

## The foe's part to aim at: its first alive part of the first family in PRIORITY that has one, else
## any alive part; -1 when everything is out (it then aims at the ship's centre). Nearest wins.
func pick_target() -> int:
	var tgt = arena.ships[foe]
	var comps = tgt.ship.components
	var uids: Array = comps.instances.keys()
	uids.sort()
	var from: Vector2 = arena.ships[me].flight.pos
	for family in PRIORITY + [""]:
		var best := -1
		var best_d := INF
		for uid in uids:
			if not _part_ok(uid) or (family != "" and comps.def(comps.instances[uid]["id"]).get("family", "") != family):
				continue
			var d := from.distance_squared_to(arena.local_to_world(foe, part_centre(foe, uid)))
			if d < best_d:
				best_d = d
				best = uid
		if best >= 0:
			return best
	return -1


func _part_ok(uid: int) -> bool:
	var ship = arena.ships[foe].ship
	var inst = ship.components.instances.get(uid)
	return inst != null and inst.get("status", "ok") != "disabled" and float(inst.get("hp", 1)) > 0.0 and ship.components.offline_reason(ship.grid, uid) == ""


## The centre of part `uid` of ship `idx`, in its grid cell coordinates: the outside half of a hull
## mount (what the pilot sees), else the part.
func part_centre(idx: int, uid: int) -> Vector2:
	var sum := Vector2.ZERO
	var inst: Dictionary = arena.ships[idx].ship.components.instances[uid]
	var cells: Array = inst["out_cells"] if not inst["out_cells"].is_empty() else inst["cells"]
	for c in cells:
		sum += Vector2(c) + Vector2(0.5, 0.5)
	return sum / cells.size()


## Where to aim from `origin` at a point moving with `vel`: the spot a shot of `speed` px/s meets it
## (the smallest positive time), or the point itself for hitscan (`speed` 0) or when no meeting exists.
static func lead_point(origin: Vector2, point: Vector2, vel: Vector2, speed: float) -> Vector2:
	if speed <= 0.0:
		return point
	var r := point - origin
	var qa := vel.dot(vel) - speed * speed
	var qb := 2.0 * r.dot(vel)
	var qc := r.dot(r)
	var t := -1.0
	if absf(qa) < 1e-6:
		if absf(qb) > 1e-9:
			t = -qc / qb
	else:
		var disc := qb * qb - 4.0 * qa * qc
		if disc >= 0.0:
			var s := sqrt(disc)
			var t1 := (-qb - s) / (2.0 * qa)
			var t2 := (-qb + s) / (2.0 * qa)
			t = minf(t1, t2) if minf(t1, t2) > 0.0 else maxf(t1, t2)
	return point + vel * t if t > 0.0 else point


## The velocity of the point of ship `idx` at ship-local `local` (its drift plus its spin).
func point_velocity(idx: int, local: Vector2) -> Vector2:
	var co = arena.ships[idx]
	var r: Vector2 = ((local - co.pivot) * arena.CELL).rotated(co.flight.angle)
	return co.flight.vel + r.rotated(PI / 2.0) * co.flight.ang_vel


## The world point to aim mount `m` at: the chosen part (or the centre of the ship), led, and turned off
## by the pilot's aim error `bias` when `jitter`.
func aim_for(m: Dictionary, jitter := true) -> Vector2:
	var local: Vector2 = part_centre(foe, target_uid) if target_uid >= 0 and _part_ok(target_uid) else arena.ships[foe].pivot
	var origin: Vector2 = arena.local_to_world(me, m["pos"])
	var w: Dictionary = arena.weapons.def(m["id"])
	var speed := float(w["speed"]) if w["kind"] in ["bolt", "flak", "missile"] else 0.0
	var aim := lead_point(origin, arena.local_to_world(foe, local), point_velocity(foe, local), speed)
	if jitter:
		aim = origin + (aim - origin).rotated(bias)
	return aim


func _shoot(dt: float) -> void:
	var co = arena.ships[me]
	if co.layers == 0 and co.layers_cap > 0 and co.overcharge_left <= 0.0 and co.overcharge_cd <= 0.0:
		arena.overcharge(me)
	var danger := _exposed_sectors() if co.sectors > 1 and co.layers > 0 else []
	var uids: Array = co.mounts.keys()
	uids.sort()
	for uid in uids:
		var m: Dictionary = co.mounts[uid]
		var w: Dictionary = arena.weapons.def(m["id"])
		if w["turret"]:
			continue  # it tracks and fires by itself (Weapons.tick_turrets)
		var aim := aim_for(m)
		arena.weapons.point_barrel(arena, me, uid, aim)
		if arena.cooldown_left(me, uid) > 0.0:
			continue
		var origin: Vector2 = arena.weapons.muzzle_of(arena, me, m)
		if origin.distance_to(aim) > float(w["range"]) or arena.weapons.can_fire(arena, me, uid, aim) != "" or not arena.weapons.in_arc(arena, me, m, aim):
			continue
		if not danger.is_empty() and Shields.drop_seconds(w) > 0.0:
			var s := Shields.outgoing_sector(co, m["pos"], (aim - origin).rotated(-co.flight.angle))
			if s in danger and float(_hold.get(uid, 0.0)) < HOLD_MAX:
				_hold[uid] = float(_hold.get(uid, 0.0)) + dt
				continue
		_hold.erase(uid)
		arena.fire(me, uid, aim)


## The sectors of its own bubble that the foe's loaded guns (ready within 0.4 s, aimed at it) would hit.
func _exposed_sectors() -> Array:
	var co = arena.ships[me]
	var out := []
	var f = arena.ships[foe]
	for uid in f.mounts:
		var m: Dictionary = f.mounts[uid]
		if arena.cooldown_left(foe, uid) > 0.4 or not (m["powered"] if m["virtual"] else f.powered.get(uid, false)):
			continue
		if not arena.weapons.in_arc(arena, foe, m, co.flight.pos):
			continue
		var a: Vector2 = arena.world_to_local(me, arena.local_to_world(foe, m["pos"]))
		var t := Shields.entry_t(co, a, co.pivot)
		var s := Shields.sector_of(co, (a.lerp(co.pivot, t) if t >= 0.0 else a) - co.pivot)
		if not out.has(s):
			out.append(s)
	return out
