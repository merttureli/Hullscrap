extends RefCounted
## The enemy pilot: flies one ship of the arena against another and shoots. Deterministic: its few
## random choices (aim jitter, which way it strafes) come from its own generator, seeded from the
## arena's seed, and it only reads the arena. Call think(dt) once per arena substep, before stepping.
## - Range: it keeps RANGE_FRACTION of its shortest weapon range.
## - Strafing: no side thrust exists, so it turns its guns' axis a few degrees off the target (never
##   enough to leave an arc) and lets the thrust push it sideways, flipping now and then.
## - Aim: the player's weapons first, then engines, then the reactor, at the part's centre, led by the
##   part's own velocity for shots that fly (hitscan lasers and beams go at the part as it is).
## - With a sectored shield it holds back weapons whose shot would open the sector the player's loaded
##   guns are pointing at, for at most HOLD_MAX seconds.
## - It overcharges its shield when the layers are gone, and does nothing once wrecked.

const Shields = preload("res://scripts/combat/shields.gd")

const RANGE_FRACTION := 0.7
const DEFAULT_RANGE := 600.0
const PRIORITY: Array[String] = ["weapon", "engine", "reactor"]  ## families it shoots at first
const JITTER_DEG := 1.5  ## aim error, either way
const STRAFE_MAX_DEG := 30.0
const STRAFE_MIN_DEG := 12.0
const LATERAL_MAX := 150.0  ## px/s of sideways drift before it turns the other way
const CLOSE_MAX := 260.0  ## px/s it closes at, at most
const BACK_MAX := 120.0  ## px/s it backs off at, at most
const HOLD_THROTTLE := 0.5  ## at the preferred range it still pushes this hard
const HOLD_MAX := 1.5  ## seconds a weapon waits for a safer sector
const RETARGET_S := 0.5

var arena
var me: int
var foe: int
var rng := RandomNumberGenerator.new()
var side := 1.0  ## +1 or -1: which way the guns' axis is turned off the target
var target_uid := -1  ## the part of the foe it aims at (-1: the ship's centre)
var _flip := 0.0
var _retarget := 0.0
var _hold := {}  # weapon uid -> seconds held back


func _init(p_arena, p_me: int, p_foe: int) -> void:
	arena = p_arena
	me = p_me
	foe = p_foe
	rng.seed = int(arena.rng.seed) * 7919 + me * 104729 + 17
	side = 1.0 if rng.randf() < 0.5 else -1.0
	_flip = rng.randf_range(2.0, 4.0)


## Decide for `dt` seconds: set the helm and fire what is ready.
func think(dt: float) -> void:
	var co = arena.ships[me]
	var tgt = arena.ships[foe]
	if co.wrecked or tgt.wrecked:
		arena.set_input(me, 0.0, 0.0)
		return
	_retarget -= dt
	if _retarget <= 0.0 or not _part_ok(target_uid):
		_retarget = RETARGET_S
		target_uid = pick_target()
	_fly(dt)
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
	# The axis its guns point along (ship-local), its shortest range, and how far it may turn off the target.
	var axis := Vector2.ZERO
	var reach := INF
	for uid in armed:
		var m: Dictionary = armed[uid]
		var w: Dictionary = arena.weapons.def(m["id"])
		reach = minf(reach, float(w["range"]))
		if float(w["arc"]) < 360.0:
			axis += (m["pos"] - co.pivot).normalized()
	axis = axis.normalized() if axis.length_squared() > 1e-6 else Vector2.UP
	var margin := STRAFE_MAX_DEG
	for uid in armed:
		var m: Dictionary = armed[uid]
		var arc := float(arena.weapons.def(m["id"])["arc"])
		if arc < 360.0:
			var off := rad_to_deg(absf(axis.angle_to((m["pos"] - co.pivot).normalized())))
			margin = minf(margin, arc * 0.5 - off - 5.0)
	var offset := deg_to_rad(clampf(margin, STRAFE_MIN_DEG, STRAFE_MAX_DEG))
	var preferred := RANGE_FRACTION * (reach if reach < INF else DEFAULT_RANGE)
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
	# Turn so the guns' axis points at the target, a little to one side.
	var want: float = u.angle() + side * offset - axis.angle()
	var err := wrapf(want - co.flight.angle, -PI, PI)
	var alpha: float = co.thrust * co.flight.turn_factor / maxf(co.mass, 1.0)  # rad/s^2 at full turn
	var turn := 0.0
	if alpha > 1e-4:
		var w_cap := alpha / maxf(co.flight.angular_damping, 0.1) * 0.8
		var w_des := signf(err) * minf(sqrt(2.0 * alpha * 0.5 * absf(err)), w_cap)
		turn = clampf((w_des - co.flight.ang_vel) / (alpha * 0.12), -1.0, 1.0)
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
			throttle = HOLD_THROTTLE * (1.0 if gap >= 0.0 else -1.0)  # keep pushing on the slant: that is the strafe
	arena.set_input(me, throttle, turn)


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
	var inst = arena.ships[foe].ship.components.instances.get(uid)
	return inst != null and inst.get("status", "ok") != "disabled" and float(inst.get("hp", 1)) > 0.0


## The centre of part `uid` of ship `idx`, in its grid cell coordinates.
func part_centre(idx: int, uid: int) -> Vector2:
	var sum := Vector2.ZERO
	var cells: Array = arena.ships[idx].ship.components.instances[uid]["cells"]
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


## The world point to aim mount `m` at: the chosen part (or the centre of the ship), led, with the jitter.
func aim_for(m: Dictionary, jitter := true) -> Vector2:
	var local: Vector2 = part_centre(foe, target_uid) if target_uid >= 0 and _part_ok(target_uid) else arena.ships[foe].pivot
	var origin: Vector2 = arena.local_to_world(me, m["pos"])
	var w: Dictionary = arena.weapons.def(m["id"])
	var speed := float(w["speed"]) if w["kind"] in ["bolt", "flak", "missile"] else 0.0
	var aim := lead_point(origin, arena.local_to_world(foe, local), point_velocity(foe, local), speed)
	if jitter:
		aim = origin + (aim - origin).rotated(deg_to_rad(rng.randf_range(-JITTER_DEG, JITTER_DEG)))
	return aim


func _shoot(dt: float) -> void:
	var co = arena.ships[me]
	if co.layers == 0 and co.layers_cap > 0 and co.overcharge_left <= 0.0 and co.overcharge_cd <= 0.0:
		arena.overcharge(me)
	var danger := _exposed_sectors() if co.sectors > 1 and co.layers > 0 else []
	var uids: Array = co.mounts.keys()
	uids.sort()
	for uid in uids:
		if arena.cooldown_left(me, uid) > 0.0:
			continue
		var m: Dictionary = co.mounts[uid]
		var w: Dictionary = arena.weapons.def(m["id"])
		var aim := aim_for(m)
		var origin: Vector2 = arena.local_to_world(me, m["pos"])
		if origin.distance_to(aim) > float(w["range"]) or arena.weapons.can_fire(arena, me, uid, aim) != "":
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
